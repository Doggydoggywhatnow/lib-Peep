// Liberated Peep for F# (P/Invoke)
module LiberatedPeep

open System
open System.IO
open System.Reflection
open System.Runtime.InteropServices

module Native =
    [<DllImport("peep")>]
    extern int peep_open(nativeint p, nativeint codecs, nativeint data, unativeint len, nativeint work, unativeint workSize)
    [<DllImport("peep")>]
    extern unativeint peep_fill(nativeint p, nativeint outBuf, unativeint frames)
    [<DllImport("peep")>]
    extern void peep_seek(nativeint p, uint64 frame)
    [<DllImport("peep")>]
    extern void peep_close(nativeint p)
    [<DllImport("peep")>]
    extern nativeint peep_flac() // address of the FLAC codec table

    let private resolve (name: string) (_asm: Assembly) (_path: Nullable<DllImportSearchPath>) : nativeint =
        if name <> "peep" then 0n
        else
            let file = if RuntimeInformation.IsOSPlatform(OSPlatform.Windows) then "peep.dll" else "libpeep.so"
            let candidates =
                [ Environment.GetEnvironmentVariable "PEEP_LIB"
                  Path.Combine(Directory.GetCurrentDirectory(), file)
                  Path.Combine(AppContext.BaseDirectory, file) ]
            match candidates |> List.tryFind (fun c -> not (String.IsNullOrEmpty c) && File.Exists c) with
            | Some c -> NativeLibrary.Load c
            | None -> raise (DllNotFoundException "libpeep not found: run ./build.sh first (or set PEEP_LIB)")

    let mutable private ready = false
    let ensureReady () =
        if not ready then
            NativeLibrary.SetDllImportResolver(Assembly.GetExecutingAssembly(), DllImportResolver(resolve))
            ready <- true

let private zeroed (n: int) =
    let m = Marshal.AllocHGlobal n
    Marshal.Copy(Array.zeroCreate<byte> n, 0, m, n)
    m

/// Decodes a WAV or FLAC file held in memory into stereo 16-bit samples.
type Peep(bytes: byte[]) =
    do Native.ensureReady ()
    let data = Marshal.AllocHGlobal bytes.Length // the library reads from this: keep it alive
    do Marshal.Copy(bytes, 0, data, bytes.Length)
    let p = zeroed 160 // struct peep
    let codecs = zeroed 16
    do Marshal.WriteInt64(codecs, 0, int64 (Native.peep_flac ()))
    let mutable work = 0n
    do
        if Native.peep_open (p, codecs, data, unativeint bytes.Length, 0n, 0un) = 0 then
            let need = Marshal.ReadInt64(p, 144) // work_need
            if need = 0L then invalidArg "bytes" "not a playable WAV or FLAC file"
            work <- zeroed (int need)
            if Native.peep_open (p, codecs, data, unativeint bytes.Length, work, unativeint need) = 0 then
                invalidArg "bytes" "not a playable WAV or FLAC file"
    let outBuf = zeroed (4096 * 4)

    member _.Rate = uint32 (Marshal.ReadInt32(p, 40)) // Hz
    member _.Channels = uint32 (Marshal.ReadInt32(p, 44)) // channels in the file
    member _.Total = uint64 (Marshal.ReadInt64(p, 32)) // frames, 0 = unknown
    member _.Position = uint64 (Marshal.ReadInt64(p, 24)) // frames played so far

    /// Up to `frames` stereo frames as interleaved int16 values; empty at the end.
    member _.Read(frames: int) : int16[] =
        let n = int (Native.peep_fill (p, outBuf, unativeint (min frames 4096)))
        let s = Array.zeroCreate<int16> (n * 2)
        Marshal.Copy(outBuf, s, 0, s.Length)
        s

    member _.Seek(frame: uint64) = Native.peep_seek (p, frame)
    /// Volume 0..256 (256 = full).
    member _.SetGain(q8: int) = Marshal.WriteInt32(p, 48, max 0 (min 256 q8))

    interface IDisposable with
        member _.Dispose() =
            Native.peep_close p
            Marshal.FreeHGlobal p
            Marshal.FreeHGlobal data
            Marshal.FreeHGlobal codecs
            Marshal.FreeHGlobal outBuf
            if work <> 0n then Marshal.FreeHGlobal work
