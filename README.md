# Liberated Peep

**Audio for All**

Liberated Peep is [Peep](https://github.com/Doggydoggywhatnow/Peep)'s playback
kernel, set free from the player. Peep is a music player that is just a screen;
Liberated Peep is what is left when you take the screen away: the part that turns
an audio file into samples, small enough to drop into any program that can call C.

Version **0.3.0**, built from **Peep 0.2.11**, for **x86-64 and ARM64**. This repository is called `lib-Peep`.

* **About 6 KB of pure assembly** for WAV and FLAC together, hand-written for both x86-64 and ARM64
* **No libc, no `malloc`, no threads, no system calls, no global state**
* **You pull the audio**: call `peep_fill` from your audio callback and get stereo samples
* **You own the memory**: nothing is allocated behind your back
* **Codecs plug in**: four function pointers add a format
* Works with **any GUI or engine**: Qt, GTK, SDL, JUCE, a game, a terminal, a kernel module

```c
#include "peep.h"

peep p;
const peep_codec *codecs[] = { &peep_codec_flac, NULL };      // WAV is built in
if (!peep_open(&p, codecs, file_bytes, file_len, NULL, 0) && p.work_need) {
    work = malloc(p.work_need);                                // FLAC asked for scratch memory
    peep_open(&p, codecs, file_bytes, file_len, work, p.work_need);
}
peep_set_gain(&p, 256);                  // 0..256, 256 = full volume

// in your audio callback (stereo int16 out):
size_t n = peep_fill(&p, out, frames);   // 0 = end of track
memset(out + n * 2, 0, (frames - n) * 4);

peep_seek(&p, frame);  peep_close(&p);
```

## Build

On x86-64 you need `nasm` and a linker. On ARM64 you need only the GNU assembler (`as`) and a linker.

```sh
make                                   # build/libpeep.a (x86-64) or build/libpeep_a64.a (on an ARM64 machine)
make win                               # Win64 objects (build/peep.obj, build/flac.obj)
make arm64 CROSS=aarch64-linux-gnu-    # cross-build the ARM64 library from an x86-64 machine
```

Link `libpeep.a`, `#include "peep.h"`. The two objects are separate in the archive, so a
program that never mentions `peep_codec_flac` does not link the FLAC code. Or skip
the build system: assemble `peep.asm` and `flac.asm` yourself
(`nasm -f elf64 peep.asm`; add `-f win64 -DWIN64` for Windows; on ARM64
`as -I arm64 arm64/peep.s`).

## What is in it

| File | Code size | What |
|---|---|---|
| `peep.asm` | 1.3 KB | `peep_open / fill / seek / close`, built-in 16-bit PCM WAV (plain, extensible, odd chunks, unknown length, truncated), volume, channel mapping to stereo |
| `flac.asm` | 4.2 KB | native FLAC decoder: 4 to 24 bit, 1 to 8 channels, fixed and variable block size, every stereo mode, seeking without a seek table |
| `abi.inc` | | System V and Microsoft x64 glue, so one source builds for both |
| `arm64/peep.s` | 1.4 KB | the same core in AArch64 assembly (NEON for volume) |
| `arm64/flac.s` | 4.6 KB | the same FLAC decoder in AArch64 assembly (NEON for stereo and output) |
| `arm64/abi_a64.inc` | | AArch64 glue: calling convention, symbol naming |
| `peep.h` | | the whole public API |
| `examples/codec_drflac.c` | | a 20-line codec adapter (wraps `dr_flac`): the model for adding any other format |

## Adding a codec

A codec is four function pointers: `open`, `read`, `seek`, `close`. Hand `peep_open` a
NULL-terminated list of them. `examples/codec_drflac.c` shows a complete adapter;
`flac.asm` is the same interface written in assembly. A codec that needs memory reads
`p->work` and reports what it wants in `p->work_need`. See `AGENTS.md` for the contract.

## Other languages

`Downloads/Header Versions/` has **22 ready-made packages, one per language**: Bun, C#, C++, Common Lisp,
D, F#, Fortran, Free Pascal, Go, Guile, Java, LuaJIT, Nim, Node.js, Perl, PHP, Python, Racket, Raku, Ruby,
Rust and Visual Basic .NET. Each is a folder (and a zip) with the library, a `build.sh`, one binding, a demo
and test audio, and **no C header and no other language's binding**. All 22 demos were run on Linux x86-64
and matched the reference output; none has been run on ARM64, Windows or macOS. Start with
[`Downloads/Header Versions/README.md`](<Downloads/Header Versions/README.md>).

## Speed

x86-64 only (the ARM64 port has not been timed on real hardware). Decode only, data already in
RAM, same machine, against `dr_flac` (the C decoder Peep used):

| FLAC file | dr_flac | Liberated Peep | |
|---|---|---|---|
| level 0 (fixed predictors) | 2027x realtime | 1853x | -9% |
| level 5 (the usual default) | 1451x | 1459x | +1% |
| level 8 | 1165x | 1284x | +10% |
| level 12 | 917x | 1005x | +10% |
| mono | 2201x | 2544x | +16% |
| 5.1 | 960x | 1078x | +12% |
| 96 kHz | 754x | 668x | -11% |
| 24-bit | 1429x | 1196x | -16% |

WAV decodes at about 140,000x realtime at full volume (it is a copy) and about 80,000x
with volume applied. Code size: 4.2 KB for FLAC (4.6 KB on ARM64) against about 90 KB of `dr_flac`.

## Limits

* **x86-64 and 64-bit ARM (AArch64) only.** 32-bit ARM is not supported.
* **The ARM64 port has been run only under QEMU emulation on Linux, never on real ARM hardware,**
  and its speed has not been measured (emulated timings mean nothing). Correctness is
  verified; performance on real chips is not.
* **Apple Silicon Macs, iPhones, Windows on ARM: not verified.** The ARM64 sources have a macOS
  mode (`as --defsym APPLE=1`: underscore-prefixed symbols, Mach-O sections) but it has never been
  assembled or run. Intel Macs are untested too and would need `nasm -f macho64` and
  underscore-prefixed symbol names, which the x86 sources do not have.
* **FLAC above 24 bits per sample is rejected**, as is a stream whose STREAMINFO block is
  missing or understates the maximum block size.
* **The FLAC audio CRC-16 is not checked.** Frame headers are CRC-8 checked and a damaged
  frame is skipped by resynchronising, but a bit flip inside audio data decodes to a wrong
  sample instead of an error.
* Seeking is a binary search over frame headers; a byte pattern that looks like a valid
  header could, very rarely, mislead it.
* Built-in WAV handles 16-bit PCM only. Other WAV formats need a codec.
* MP3 and Ogg Vorbis are not included yet (Peep itself plays them through C decoders).
* One `peep` belongs to one thread at a time. Separate `peep`s are independent.
* The Windows build is tested under Wine, not on real Windows.

## Tests

`make test` runs all of these (needs `python3` with `numpy`; ffmpeg is not needed):

* `tools/mkflac.py`: a randomised FLAC **encoder** that uses every feature of the format and
  knows the exact PCM it wrote, so the decoder is checked against ground truth (all 11
  channel modes, fixed and variable block size, every block-size and sample-rate code, 4 to
  24 bit, constant / verbatim / fixed / LPC subframes, wasted bits, both Rice methods,
  escape partitions, very long unary runs, extra metadata, unknown length, random seeks)
* `tools/testwav.py`: 2,505 checks of the WAV path
* `tools/fuzz.c`: a mutation fuzzer that puts the input and the workspace against unmapped
  guard pages and has a hang watchdog (`make fuzz` runs a long one)
* `make test-arm64` runs the same suites on the ARM64 build (under QEMU on an x86 machine:
  `make test-arm64 CROSS=aarch64-linux-gnu-`; needs `qemu-aarch64`)
* `make build/peepdump.exe` builds the Windows test tool (needs mingw-w64); run it under `wine`
  on the same files and compare with the Linux output

x86-64 results: thousands of random streams and seeks with zero failures; 16 million fuzz
inputs (about 32 billion frames decoded) with no crash, hang or out-of-bounds access; clean
under valgrind; identical output to `dr_flac` on every real ffmpeg-encoded file tried
(levels 0 to 12, mono, 5.1, 96 kHz, 24-bit); the Windows build passes the same corpus under
Wine. The decoder was deliberately broken in 39 ways; 35 were caught and the other 4 turned
out not to change the output.

The ARM64 build, run under QEMU: 2,505 WAV checks and 480+ random FLAC streams with 1,100+ seeks
with zero failures; output identical to the x86-64 decoder and to `dr_flac` on every real file;
1.2 million fuzz inputs (2.4 billion frames) with no crash; and 17 of 17 deliberate breakages caught.

## For AI agents

Read [`AGENTS.md`](AGENTS.md).

## License

Public domain, under the [Unlicense](LICENSE), like Peep. `third_party/dr_flac.h` is David
Reid's `dr_flac` (public domain or MIT-0, at your option); it is used only by the example
adapter and the test tools, never by the library.
