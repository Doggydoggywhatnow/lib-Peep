# Liberated Peep for F#

**Audio for All** · lib-Peep 0.3.1 · built from Peep 0.2.11

Liberated Peep is a tiny audio decoder for WAV and FLAC, hand-written in assembly (x86-64 and ARM64), with no
dependencies. This download is Liberated Peep with a **F#** binding. It contains one language binding only
(F#): no C header, and nothing for any other language.

Binding mechanism: P/Invoke (`DllImport`).

## Status

**Verified.** .NET SDK 8.0, Linux x86-64. The demo was built/run in this environment and its output matched the reference exactly (see "Expected output"). The shared library itself is also verified on ARM64 (under QEMU); this binding has not been run on ARM64, macOS or Windows.

## What is in this download

| File | What |
|---|---|
| `Peep.fsproj` | project file |
| `Peep.fs` | the binding: module `LiberatedPeep`, class `Peep` |
| `Program.fs` | demo: decodes the test files and prints checksums |
| `build.sh` | builds the shared library from `lib/` |
| `lib/` | the assembly library (x86-64 `*.asm` for nasm, ARM64 `arm64/*.s` for GNU as) |
| `test.wav`, `test.flac` | 0.1 s of stereo audio, for the demo |
| `LICENSE` | Unlicense (public domain) |

## Use it

```sh
./build.sh            # makes libpeep.so (Linux) or peep.dll (Windows)
```

```sh
DOTNET_NOLOGO=1 DOTNET_CLI_TELEMETRY_OPTOUT=1 dotnet run -c Release --nologo -v q
```

Needs: .NET 6 SDK or newer (built with .NET 8) and nasm and ld (Linux x86-64) or as and ld (Linux ARM64).

Expected output:

```
test.wav rate=44100 channels=2 frames=4410 sum=263816 seek_sum=-69992
test.flac rate=44100 channels=2 frames=4410 sum=263816 seek_sum=-69992
```

## The F# API

```fsharp
open LiberatedPeep

use peep = new Peep(File.ReadAllBytes "song.flac")        // WAV or FLAC, from memory
printfn "%d %d %d" peep.Rate peep.Channels peep.Total
let mutable go = true
while go do
    let samples = peep.Read 1024                          // int16[], interleaved stereo
    if samples.Length = 0 then go <- false else play samples   // your audio output
peep.Seek 44100UL                                         // jump to frame 44100
peep.SetGain 128                                          // half volume
```

Every Liberated Peep binding offers the same few things: open a WAV or FLAC file from memory, read its
`rate`, `channels` and `total` frames, `read` stereo 16-bit samples, `seek`, set the volume (`0..256`, 256 =
full), and `close`. Output is always interleaved stereo 16-bit at the file's own sample rate; mono is
duplicated and 3+ channels use the first two.

## Notes

* The library is looked for in `$PEEP_LIB`, then the current directory, then the program directory.
* `Read` returns at most 4096 frames per call.

## Platforms

* Linux x86-64 and Linux ARM64: the library builds with `./build.sh` (verified; ARM64 under QEMU only).
* Windows x64: `./build.sh` in MSYS2/MinGW builds `peep.dll` (the DLL loads and decodes under Wine; this binding was
  not run on Windows).
* macOS: not supported yet. Android, iOS, 32-bit ARM, RISC-V and others: not supported.

## Limits

x86-64 and ARM64 only. FLAC up to 24 bits per sample. 16-bit PCM WAV only. No MP3 or Vorbis. A FLAC frame that fails its
CRC-16 is output as silence. Full details: https://github.com/Doggydoggywhatnow/lib-Peep

## License

Public domain, under the Unlicense (`LICENSE`).
