// Liberated Peep for C# (P/Invoke)
using System.Reflection;
using System.Runtime.InteropServices;

namespace LiberatedPeep;

/// <summary>Decodes a WAV or FLAC file held in memory into stereo 16-bit samples.</summary>
public sealed class Peep : IDisposable
{
    private static class Native
    {
        [DllImport("peep")] public static extern int peep_open(IntPtr p, IntPtr codecs, IntPtr data, nuint len, IntPtr work, nuint workSize);
        [DllImport("peep")] public static extern nuint peep_fill(IntPtr p, IntPtr outBuf, nuint frames);
        [DllImport("peep")] public static extern void peep_seek(IntPtr p, ulong frame);
        [DllImport("peep")] public static extern void peep_close(IntPtr p);
        [DllImport("peep")] public static extern IntPtr peep_flac();   // address of the FLAC codec table

        static Native() => NativeLibrary.SetDllImportResolver(typeof(Native).Assembly, Resolve);

        private static IntPtr Resolve(string name, Assembly asm, DllImportSearchPath? path)
        {
            if (name != "peep") return IntPtr.Zero;
            string file = RuntimeInformation.IsOSPlatform(OSPlatform.Windows) ? "peep.dll" : "libpeep.so";
            foreach (var c in new[] { Environment.GetEnvironmentVariable("PEEP_LIB"),
                                      Path.Combine(Directory.GetCurrentDirectory(), file),
                                      Path.Combine(AppContext.BaseDirectory, file) })
                if (!string.IsNullOrEmpty(c) && File.Exists(c)) return NativeLibrary.Load(c);
            throw new DllNotFoundException("libpeep not found: run ./build.sh first (or set PEEP_LIB)");
        }
    }

    private readonly IntPtr _p, _data, _codecs, _out;
    private IntPtr _work;

    /// <param name="bytes">a WAV or FLAC file</param>
    public Peep(byte[] bytes)
    {
        _data = Marshal.AllocHGlobal(bytes.Length);                 // the library reads from this: keep it alive
        Marshal.Copy(bytes, 0, _data, bytes.Length);
        _p = Zeroed(160);                                           // struct peep
        _codecs = Zeroed(16);
        Marshal.WriteInt64(_codecs, 0, Native.peep_flac().ToInt64());
        if (Native.peep_open(_p, _codecs, _data, (nuint)bytes.Length, IntPtr.Zero, 0) == 0)
        {
            ulong need = (ulong)Marshal.ReadInt64(_p, 144);         // work_need
            if (need == 0) throw new ArgumentException("not a playable WAV or FLAC file");
            _work = Zeroed((int)need);
            if (Native.peep_open(_p, _codecs, _data, (nuint)bytes.Length, _work, (nuint)need) == 0)
                throw new ArgumentException("not a playable WAV or FLAC file");
        }
        _out = Zeroed(4096 * 4);
    }

    private static IntPtr Zeroed(int n)
    {
        IntPtr m = Marshal.AllocHGlobal(n);
        Marshal.Copy(new byte[n], 0, m, n);
        return m;
    }

    public uint Rate => (uint)Marshal.ReadInt32(_p, 40);          // Hz
    public uint Channels => (uint)Marshal.ReadInt32(_p, 44);      // channels in the file
    public ulong Total => (ulong)Marshal.ReadInt64(_p, 32);       // frames, 0 = unknown
    public ulong Position => (ulong)Marshal.ReadInt64(_p, 24);    // frames played so far

    /// <summary>Up to <paramref name="frames"/> stereo frames as interleaved samples; empty at the end.</summary>
    public short[] Read(int frames = 1024)
    {
        int n = (int)Native.peep_fill(_p, _out, (nuint)Math.Min(frames, 4096));
        var s = new short[n * 2];
        Marshal.Copy(_out, s, 0, s.Length);
        return s;
    }

    public void Seek(ulong frame) => Native.peep_seek(_p, frame);

    /// <summary>Volume 0..256 (256 = full).</summary>
    public void SetGain(int q8) => Marshal.WriteInt32(_p, 48, Math.Clamp(q8, 0, 256));

    public void Dispose()
    {
        Native.peep_close(_p);
        Marshal.FreeHGlobal(_p); Marshal.FreeHGlobal(_data); Marshal.FreeHGlobal(_codecs); Marshal.FreeHGlobal(_out);
        if (_work != IntPtr.Zero) Marshal.FreeHGlobal(_work);
    }
}
