/// Liberated Peep for D: extern(C) declarations, no libraries needed.
module peep;

extern (C) @nogc nothrow
{
    int peep_open(void* p, const(void)* codecs, const(void)* data, size_t len, void* work, size_t workSize);
    size_t peep_fill(void* p, short* outBuf, size_t frames);
    void peep_seek(void* p, ulong frame);
    void peep_close(void* p);
    const(void)* peep_flac(); // address of the FLAC codec table
}

/// Decodes a WAV or FLAC file held in memory into stereo 16-bit samples.
final class Peep
{
    private ulong[20] p;        // struct peep (160 bytes, 8-aligned)
    private ubyte[] data;       // the library reads from this: it must stay alive
    private size_t[2] codecs;
    private ulong[] work;
    private short[] outBuf;

    /// bytes: a WAV or FLAC file
    this(const(ubyte)[] bytes)
    {
        import std.exception : enforce;
        data = bytes.dup;
        outBuf = new short[4096 * 2];
        codecs[0] = cast(size_t) peep_flac();
        if (!peep_open(p.ptr, codecs.ptr, data.ptr, data.length, null, 0))
        {
            immutable need = cast(size_t) p[18]; // work_need (offset 144)
            enforce(need != 0, "not a playable WAV or FLAC file");
            work = new ulong[(need + 7) / 8];
            enforce(peep_open(p.ptr, codecs.ptr, data.ptr, data.length, work.ptr, need) != 0,
                    "not a playable WAV or FLAC file");
        }
    }

    @property uint rate() const { return cast(uint)(p[5] & 0xFFFF_FFFF); } // Hz
    @property uint channels() const { return cast(uint)(p[5] >> 32); }     // channels in the file
    @property ulong total() const { return p[4]; }                         // frames, 0 = unknown
    @property ulong position() const { return p[3]; }                      // frames played so far

    /// Up to `frames` stereo frames as interleaved short values; empty at the end.
    short[] read(size_t frames = 1024)
    {
        immutable n = peep_fill(p.ptr, outBuf.ptr, frames > 4096 ? 4096 : frames);
        return outBuf[0 .. n * 2].dup;
    }

    void seek(ulong frame) { peep_seek(p.ptr, frame); }

    /// Volume 0..256 (256 = full).
    void setGain(uint q8)
    {
        p[6] = (p[6] & ~0xFFFF_FFFFUL) | (q8 > 256 ? 256 : q8);
    }

    void close() { peep_close(p.ptr); }
}
