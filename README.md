# Liberated Peep

**Audio for All**

Liberated Peep is [Peep](https://github.com/Doggydoggywhatnow/Peep)'s playback
kernel, set free from the player. Peep is a music player that is just a screen;
Liberated Peep is what is left when you take the screen away: the part that turns
an audio file into samples, small enough to drop into any program that can call C.

Version **0.5.0**, built from **Peep 0.2.11**, for **x86-64 and ARM64**. This repository is called `lib-Peep`.

**Branches.** `main` is the assembly and documentation only, at the old x86-64 version 0.1.2. **`dev` (this branch) has the library
at 0.5.0, identical to `arm64` except for two speed experiments in `flac.asm` and `arm64/flac.s` (fused fixed-predictor decoding and a vector LPC loop: SSE4.1 chosen by `cpuid` on x86-64, NEON on ARM64) and the new compressed-WAV codec (`wavc.asm`, `arm64/wavc.s`); see the CHANGELOG, plus the test suite and its C and Python support files** (`peep.h`, `Makefile`, `examples/`,
`third_party/`, `tools/`), the audio-quality tests, and the AppImage tooling. `arm64` has all of that and also the 22 language packages
(`Downloads/`) and their bindings (`bindings/`), which are not on this branch. The earlier x86-64-only documentation is kept at the
end of each of these files.

* **About 13 KB of pure assembly** for WAV, FLAC and every WAV depth together (4 KB of that is CRC tables), hand-written for both x86-64 and ARM64
* **No libc, no `malloc`, no threads, no system calls, no global state**
* **You pull the audio**: call `peep_fill` from your audio callback and get stereo samples
* **You own the memory**: nothing is allocated behind your back
* **Codecs plug in**: four function pointers add a format
* Works with **any GUI or engine**: Qt, GTK, SDL, JUCE, a game, a terminal, a kernel module

```c
#include "peep.h"

peep p;
const peep_codec *codecs[] = { &peep_codec_flac, &peep_codec_wavx, NULL };   // 16-bit WAV is built in
if (!peep_open(&p, codecs, file_bytes, file_len, NULL, 0) && p.work_need) {
    work = malloc(p.work_need);                                // FLAC asked for scratch memory
    peep_open(&p, codecs, file_bytes, file_len, work, p.work_need);
}
peep_set_gain(&p, 256);                  // 0..256, 256 = full volume

// in your audio callback (stereo int16 out):
size_t n = peep_fill(&p, out, frames);   // 0 = end of track
memset(out + n * 2, 0, (frames - n) * 4);

// or, for a 24-bit device, the file's own resolution (stereo int32, left-justified):
size_t m = peep_fill32(&p, out32, frames);
// a 16-bit device fed from a 24-bit file sounds cleaner with dither: peep_set_dither(&p, 2);

peep_seek(&p, frame);  peep_close(&p);
```

## Philosophy

**Audio for All.** A decoder should be something you can drop into anything, not something you have to build a
program around.

* **Small enough to read.** The whole library is about 13 KB of assembly. One person can read all of it, and nothing
  in it is there "just in case". If a feature costs size, it is a separate codec you opt into: the built-in WAV
  decoder stays 1.3 KB, and 8/24/32-bit and float WAV, or FLAC, are extra files.
* **The host is in charge.** Liberated Peep calls no libc, allocates nothing, takes no locks, makes no system calls and
  keeps no global state. You lend it memory, you pull the samples, you decide the thread. That is why it runs in
  an audio callback, a kernel, a plug-in host that forbids allocation, or a runtime nobody has heard of.
* **True to the file.** Samples are never changed behind your back. `peep_fill32` hands over every bit of a 24-bit file;
  the 16-bit path only rounds once, at the very end, and only if you ask for rounding or dither. Volume is applied at full
  precision before that step. A damaged FLAC frame becomes silence, never a plausible wrong sample, and it is counted.
* **Assembly, on purpose.** Not for speed's sake (it is within a few percent of the C decoders it replaces), but because
  assembly is the one language every other language can call without a runtime. It stays pure assembly.
* **Claims are checked, and the checking is checked.** Every decoder is compared with an independent model or an encoder
  that knows the exact answer, then deliberately broken to prove the tests would notice. When something has not been
  verified (real ARM hardware, macOS, Windows beyond Wine, the speed of the ARM64 port) this README says so.
* **Everywhere it can go.** x86-64 and ARM64 with the same design, the same API and the same tests, and a ready-made
  package for 22 languages. If your CPU or language is missing, the C ABI is five functions.

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
| `peep.asm` | 2.5 KB | `peep_open / fill / fill32 / seek / close`, full-resolution output, 16-bit reduction with rounding or dither, built-in 16-bit PCM WAV (plain, extensible, odd chunks, unknown length, truncated), volume, channel mapping to stereo |
| `flac.asm` | 9.3 KB | native FLAC decoder: 4 to 31 bit, 1 to 8 channels, fixed and variable block size, every stereo mode, seeking without a seek table, CRC-16 checked frames (4 KB of the size is the CRC tables), full-resolution output, ID3v2 skipping, damage counter, metadata access |
| `wav.asm` | 1.1 KB | WAV extension codec: unsigned 8-bit, 12 / 16 / 20 / 24 / 32-bit PCM, 32 and 64-bit float, plain or extensible, 1 to 8 channels, full-resolution output |
| `abi.inc` | | System V and Microsoft x64 glue, so one source builds for both |
| `arm64/peep.s` | 2.5 KB | the same core in AArch64 assembly |
| `arm64/flac.s` | 9.7 KB | the same FLAC decoder in AArch64 assembly (NEON for stereo and output), same features |
| `arm64/wav.s` | 1.3 KB | the same WAV extension codec in AArch64 assembly |
| `wavc.asm` | 2.5 KB | compressed WAV codec: A-law, mu-law, IMA ADPCM, Microsoft ADPCM (16-bit output) |
| `arm64/wavc.s` | 2.5 KB | the same compressed WAV codec in AArch64 assembly |
| `arm64/abi_a64.inc` | | AArch64 glue: calling convention, symbol naming |
| `peep.h` | | the whole public API |
| `examples/codec_drflac.c` | | a 20-line codec adapter (wraps `dr_flac`): the model for adding any other format |

## Sound quality (0.4.0)

* **`peep_fill32`** returns stereo `int32`, each sample left-justified (`value << (32 - bits)`): a 24-bit file arrives
  with every bit, a 16-bit file as `x << 16`. Volume is applied at 64-bit precision and nothing is rounded.
* **`peep_fill`** (16-bit output) now applies the volume to the full-resolution sample *before* the one reduction to
  16 bits. `peep_set_dither(&p, mode)` picks it: 0 truncate (default, and bit-exact as before), 1 round to nearest,
  2 TPDF dither. 16-bit sources are never touched. The dither is deterministic (xorshift32), so output is repeatable.
* **FLAC 4 to 31 bits** per sample (25 to 31 were rejected before). 32-bit FLAC is not supported yet.
* **`p->bits`** is the source bit depth. **`p->errors`** counts damaged frames met so far (CRC failure or an
  undecodable frame), so a caller can now be told that damage happened.
* **`peep_flac_metadata(p, type, index, &data)`** gives zero-copy access to STREAMINFO, SEEKTABLE, VORBIS_COMMENT,
  PICTURE and the other metadata blocks.
* ID3v2 tags in front of a FLAC stream are skipped. Sample rates up to 1,048,575 Hz are accepted.

## WAV at any bit depth (0.5.0)

The built-in WAV decoder still takes 16-bit PCM and nothing else (and stays 1.3 KB). Put `&peep_codec_wavx` in the codecs list
and these work too: **unsigned 8-bit; signed 12, 16, 20, 24 and 32-bit PCM; 32-bit and 64-bit IEEE float**, in plain and
`WAVE_FORMAT_EXTENSIBLE` form, 1 to 8 channels, odd chunks, unknown-length and truncated files. `p->bits` reports the
valid bit depth (float: 32). `peep_fill32` gives every bit left-justified; `peep_fill` gives 16 bits, with the same volume,
rounding and dither choices as for FLAC. Float is scaled by 2^31, rounded to nearest even and clipped; NaN is silence.
No workspace is needed. Not handled here (see the next section for A-law, mu-law and ADPCM): 16-bit files that the built-in decoder already takes
(an extensible 16-bit file with fewer valid bits reports 16).

## Compressed WAV: A-law, mu-law and ADPCM

Add `&peep_codec_wavc` to the codecs list (`wavc.asm`, `arm64/wavc.s`, about 2.5 KB each) and these WAV files play:

| Format (WAV tag) | Channels | Notes |
|---|---|---|
| A-law (6) and mu-law (7) | 1 to 8 | 8-bit logarithmic; plain or `WAVE_FORMAT_EXTENSIBLE` headers |
| IMA ADPCM (0x11) | 1 or 2 | 4-bit, block based |
| Microsoft ADPCM (2) | 1 or 2 | 4-bit, block based, uses the coefficient table in the file |

* **Output is 16-bit** (`p->bits` = 16); `peep_fill32` gives each sample shifted left by 16. Volume works as for any 16-bit source.
* **ADPCM needs an 80-byte workspace** (the usual `work_need` protocol: open once without one, then again with the buffer it asks for). A-law and mu-law need none.
* **Seeking** decodes from the start of the block that holds the frame, so a seek costs at most one block of work.
* **A `fact` chunk, when present, trims the padding of the last ADPCM block.** A partial last block plays the groups it holds.
* **IMA ADPCM follows the reference algorithm**, the one `libsndfile` and Windows use. `ffmpeg` rounds differently (`((2*delta+1)*step)>>3`), so an IMA file *made by
  ffmpeg* decodes here to values that differ from ffmpeg's own decoding by a few units (up to about 45 on a 30,000-sample test file; the block headers resynchronise it).
  A-law, mu-law and Microsoft ADPCM agree with `ffmpeg` and `libsndfile` bit for bit.
* **Not covered:** GSM 6.10, MP3 inside WAV, Dialogic OKI / Yamaha ADPCM, G.72x, ADPCM in `WAVE_FORMAT_EXTENSIBLE` form, and ADPCM with more than 2 channels. These are rejected
  (`peep_open` returns 0 and `work_need` stays 0), never decoded wrongly.

## Adding a codec

A codec is four function pointers: `open`, `read`, `seek`, `close` (plus an optional fifth, `read32`, for full resolution). Hand `peep_open` a
NULL-terminated list of them. `examples/codec_drflac.c` shows a complete adapter;
`flac.asm` is the same interface written in assembly. A codec that needs memory reads
`p->work` and reports what it wants in `p->work_need`. See `AGENTS.md` for the contract.

## Other languages

On the `arm64` branch (they are not on `dev`), `Downloads/Header Versions/` has **22 ready-made packages, one per language**: Bun, C#, C++, Common Lisp,
D, F#, Fortran, Free Pascal, Go, Guile, Java, LuaJIT, Nim, Node.js, Perl, PHP, Python, Racket, Raku, Ruby,
Rust and Visual Basic .NET. Each is a folder (and a zip) with the library, a `build.sh`, one binding, a demo
and test audio, and **no C header and no other language's binding**. All 22 demos were run on Linux x86-64
and matched the reference output; none has been run on ARM64, Windows or macOS. Start with
`Downloads/Header Versions/README.md` on that branch.

## Speed

x86-64 only (the ARM64 port has not been timed on real hardware). Decode only, data already in
RAM, same machine, against `dr_flac` (the C decoder Peep used):

| FLAC file | dr_flac | Liberated Peep | |
|---|---|---|---|
| level 0 (fixed predictors) | 2184x realtime | 1875x | -14% |
| level 2 | 2358x realtime | 1953x | -17% |
| level 5 (the usual default) | 1669x realtime | 1523x | -9% |
| level 8 | 1292x realtime | 1346x | +4% |
| level 12 | 1043x realtime | 1073x | +3% |
| mono | 2468x realtime | 2585x | +5% |
| 5.1 | 1084x realtime | 1098x | +1% |
| 96 kHz | 831x realtime | 713x | -14% |
| 24-bit | 1660x realtime | 1248x | -25% |

Liberated Peep checks every frame's CRC-16; this table includes that cost. Measured against the same decoder
without the check, it costs 4% to 12% (most on lightly compressed files, least on high compression levels).

WAV decodes at about 140,000x realtime at full volume (it is a copy) and about 80,000x
with volume applied. Code size: 9.3 KB for FLAC (9.7 KB on ARM64) against about 90 KB of `dr_flac`.

## Limits

* **x86-64 and 64-bit ARM (AArch64) only.** 32-bit ARM is not supported.
* **The ARM64 port has been run only under QEMU emulation on Linux, never on real ARM hardware,**
  and its speed has not been measured (emulated timings mean nothing). Correctness is
  verified; performance on real chips is not.
* **Apple Silicon Macs, iPhones, Windows on ARM: not verified.** The ARM64 sources have a macOS
  mode (`as --defsym APPLE=1`: underscore-prefixed symbols, Mach-O sections) but it has never been
  assembled or run. Intel Macs are untested too and would need `nasm -f macho64` and
  underscore-prefixed symbol names, which the x86 sources do not have.
* **FLAC above 31 bits per sample (that is, 32-bit) is rejected**, as is a stream whose STREAMINFO block is
  missing or understates the maximum block size.
* **A damaged FLAC frame comes out as silence, not as a decoded error.** Every frame's CRC-16 is checked. A
  frame that fails it is replaced by silence of the same length (so timing and seek positions stay
  right) and decoding resumes at the next valid frame. A bit flip is never turned into wrong samples.
  `p->errors` counts how many frames were damaged.
* Seeking is a binary search over frame headers; a byte pattern that looks like a valid
  header could, very rarely, mislead it.
* The built-in WAV handles 16-bit PCM only; add `peep_codec_wavx` for 8, 12, 20, 24, 32-bit and float. A-law, mu-law, IMA ADPCM and Microsoft ADPCM WAV need `peep_codec_wavc`; GSM 6.10, MP3-in-WAV and the other compressed WAV types are not supported.
* MP3 and Ogg Vorbis are not included yet (Peep itself plays them through C decoders).
* One `peep` belongs to one thread at a time. Separate `peep`s are independent.
* The Windows build is tested under Wine, not on real Windows.

## Tests

**This is the `dev` branch: it is `main` plus the test suite and its C support files**, with the library identical to the `arm64` branch except for the `flac.asm` / `arm64/flac.s` experiments described in the CHANGELOG (run `make test-simd` for the SIMD/fallback proof); `arm64` is the unchanged baseline it is compared against. Run it here with `make test` (x86-64) and `make test-arm64 CROSS=aarch64-linux-gnu-` (ARM64, under QEMU).

`make test` runs all of these (needs `python3` with `numpy`; ffmpeg is not needed):

* `tools/mkflac.py`: a randomised FLAC **encoder** that uses every feature of the format and
  knows the exact PCM it wrote, so the decoder is checked against ground truth (all 11
  channel modes, fixed and variable block size, every block-size and sample-rate code, 4 to
  31 bit, constant / verbatim / fixed / LPC subframes, wasted bits, both Rice methods,
  escape partitions, very long unary runs, extra metadata, unknown length, random seeks)
* `tools/testwav.py`: 2,504 checks of the 16-bit WAV path
* `make test-audio` (also part of `make test`): tests for stutter, clicks, crackle and garbling. `tools/testaudio.c` hammers the
  API like a hostile audio callback (random fill sizes, seeks anywhere, volume changes, canary bytes after every buffer) and
  compares every fill with a reference decode; `tools/testaudio.py` plays synthetic tones, sweeps, square waves, noise, DC,
  silence, two-tone stereo and 6 channels through WAV and 16/24-bit FLAC and judges the output alone: exact samples, identical
  bytes whatever the request sizes, exact length, no step larger than the signal allows, sine SINAD and spurious tones,
  channel integrity, exact volume, files cut short, seeks at every frame edge, and damaged frames (silence, never noise)
  They also run against older libraries (0.3.x and earlier): `testaudio.c` built without `-DPEEP_WIDE` and the Python suite detects which behaviour to expect. On this branch the Makefile builds it with `-DPEEP_WIDE`.
* `tools/testwavc.py` (`make test-wavc`): the compressed-WAV codec against independent models that are themselves checked against real decoders (`ffmpeg` and
  `libsndfile`, through `tools/wavmodels.py` and `tools/sndfileref.py`); every format, mono and stereo, many block sizes, signals that push the ADPCM step to its limits,
  `fact` chunks, partial and truncated blocks, extensible headers, custom Microsoft coefficient tables, damaged headers and streams, seeks at every block edge,
  random request sizes, volume, 32-bit output and rejected files. `tools/testwavc_ws.c` checks the workspace protocol. Needs `ffmpeg` (skipped with a notice if missing).
* `tools/testwavx.py`: the WAV extension codec against an independent model (every format, extensible headers, volume,
  the three 16-bit modes, `peep_fill32`, seeking, truncation, rejects)
* `tools/fuzz.c`: a mutation fuzzer that puts the input and the workspace against unmapped
  guard pages and has a hang watchdog (`make fuzz` runs a long one)
* `tools/testhires.py`: independent model checks of `peep_fill32`, the gain, the 16-bit rounding and dither modes
  (bit-exact against a Python model), metadata blocks, WAV and legacy-codec widening
* `make test-arm64` runs the same suites on the ARM64 build (under QEMU on an x86 machine:
  `make test-arm64 CROSS=aarch64-linux-gnu-`; needs `qemu-aarch64`)
* `make build/peepdump.exe` builds the Windows test tool (needs mingw-w64); run it under `wine`
  on the same files and compare with the Linux output

x86-64 results: thousands of random streams and seeks with zero failures; 16 million fuzz
inputs (about 32 billion frames decoded) with no crash, hang or out-of-bounds access; clean
under valgrind; identical output to `dr_flac` on every real ffmpeg-encoded file tried
(levels 0 to 12, mono, 5.1, 96 kHz, 24-bit); the Windows build passes the same corpus under
Wine. The decoder was deliberately broken in 39 ways; 35 were caught and the other 4 turned
out not to change the output. The 0.4.0 code was broken 16 more ways on each CPU; all 32 were caught (one gap in the
tests, ID3 sizes above 2 MB, was found this way and closed).

The ARM64 build, run under QEMU: 2,505 WAV checks and 480+ random FLAC streams with 1,100+ seeks
with zero failures; output identical to the x86-64 decoder and to `dr_flac` on every real file;
1.2 million fuzz inputs (2.4 billion frames) with no crash; and 17 of 17 deliberate breakages caught.

## For AI agents

Read [`AGENTS.md`](AGENTS.md).

## License

Public domain, under the [Unlicense](LICENSE), like Peep. `third_party/dr_flac.h` is David
Reid's `dr_flac` (public domain or MIT-0, at your option); it is used only by the example
adapter and the test tools, never by the library.

## Archive: the earlier README (0.1.2, x86-64 only)

Kept for reference. This is the README of the `dev` branch before it was brought up to the 0.5.0 library; it describes the x86-64-only library (WAV and FLAC, no ARM64, no `peep_fill32`, no `peep_codec_wavx`) and so differs from everything above. Its sections are unchanged apart from heading levels. The C declarations in its "API reference" are the 0.1.2 API; the current ones are in `peep.h`.

Version **0.1.2**, built from **Peep 0.2.11**.

* **10 KB of x86-64 assembly** for WAV and FLAC together (4 KB of that is CRC tables)
* **No libc, no `malloc`, no threads, no system calls, no global state**
* **You pull the audio**: call `peep_fill` from your audio callback and get stereo samples
* **You own the memory**: nothing is allocated behind your back
* **Codecs plug in**: four function pointers add a format
* Works with **any GUI or engine**: Qt, GTK, SDL, JUCE, a game, a terminal, a kernel module

```c
// declarations: see "API reference" below

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

#### Build

You need `nasm` and a linker. This repository is assembly only, so there is no build system: assemble the
files and link the objects into your program.

```sh
nasm -f elf64 peep.asm -o peep.o                 # Linux / BSD: the core and WAV
nasm -f elf64 flac.asm -o flac.o                 # optional: FLAC
nasm -f win64 -DWIN64 peep.asm -o peep.obj       # Windows (same for flac.asm)
cc app.c peep.o flac.o -o app                    # link with your program
```

`peep.asm` and `flac.asm` are separate objects, so a program that never mentions `peep_codec_flac` does not
need `flac.o` at all. Add `ar rcs libpeep.a peep.o flac.o` if you want a static library.

#### What is in it

| File | Code size | What |
|---|---|---|
| `peep.asm` | 1.3 KB | `peep_open / fill / seek / close`, built-in 16-bit PCM WAV (plain, extensible, odd chunks, unknown length, truncated), volume, channel mapping to stereo |
| `flac.asm` | 8.6 KB | native FLAC decoder: 4 to 24 bit, 1 to 8 channels, fixed and variable block size, every stereo mode, seeking without a seek table, CRC-16 checked frames (4 KB of the size is the CRC tables) |
| `abi.inc` | | System V and Microsoft x64 glue, so one source builds for both |

#### API reference

There is no header file in this repository (it is assembly only). Copy these C declarations into your own
code, or translate them to your language: the library is a plain C ABI.

```c
/* Liberated Peep (lib-Peep): Peep's playback kernel as a library.  "Audio for All"
 * Version 0.1.0, built from Peep 0.2.11. Public domain (Unlicense), see LICENSE.
 *
 * Freestanding x86-64 assembly: no libc, no malloc, no threads, no OS calls.
 * You own all memory. Pull-based: your audio callback calls peep_fill().
 *
 * Output is always interleaved stereo int16 at peep_rate(); the volume is a
 * q8 gain (0..256) applied in the same pass that reads the samples.
 * Built in: 16-bit PCM WAV (incl. WAVE_FORMAT_EXTENSIBLE), decoded straight
 * from your memory with no copy. Anything else comes from a plugged-in codec.
 */
#ifndef PEEP_H
#define PEEP_H
#include <stddef.h>
#include <stdint.h>
#define LIBPEEP_VERSION "0.1.0"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct peep peep;

/* A codec. Fill p->rate, p->channels (1..8) and p->total (frames, 0 = unknown)
 * in open(). p->ctx and p->state[] are yours; p->src/p->len are the file.
 * read() returns interleaved int16 in the file's own channel count, up to
 * `frames` frames; 0 means end of stream. seek and close may be NULL.
 * Peep maps any channel count to stereo (mono is duplicated, 3+ uses the
 * first two channels). */
typedef struct peep_codec {
    int    (*open)(peep *p, const void *data, size_t len);  /* nonzero = mine */
    size_t (*read)(peep *p, int16_t *out, size_t frames);
    void   (*seek)(peep *p, uint64_t frame);
    void   (*close)(peep *p);
} peep_codec;

/* 160 bytes. The fields are public: read them, and set only `gain`. */
struct peep {
    const peep_codec *codec;   /*   0  */
    const uint8_t    *src;     /*   8  the file in memory */
    size_t            len;     /*  16 */
    uint64_t          pos;     /*  24  frame cursor */
    uint64_t          total;   /*  32  frames, 0 = unknown */
    uint32_t          rate;    /*  40  Hz */
    uint32_t          channels;/*  44  of the source */
    uint32_t          gain;    /*  48  q8: 256 = unity, 0 = silence (max 256) */
    uint32_t          kind;    /*  52  0 closed, 1 built-in WAV, 2 codec */
    const uint8_t    *data;    /*  56  built-in WAV: first sample */
    void             *ctx;     /*  64  codec use */
    uint8_t           state[56]; /* 72  codec use */
    void             *work;    /* 128  workspace you lent to peep_open */
    size_t            work_size;/* 136 */
    size_t            work_need;/* 144 bytes a codec wanted; valid after a failed open */
    uint64_t          reserved;/* 152 */
};

/* codecs: NULL-terminated array tried in order after the built-in WAV
 * (may be NULL). The memory at `data` must stay valid until peep_close().
 *
 * work, work_size: scratch memory for codecs that need some (FLAC needs
 * channels * max_blocksize * 4 + 16 bytes, typically 36 KB). It must stay valid until
 * peep_close(). Built-in WAV needs none. If a codec finds it too small, open
 * fails and p->work_need says how many bytes it wanted, so you can allocate
 * and call again.
 *
 * Returns 1 on success, 0 if no decoder accepts the data. */
int    peep_open (peep *p, const peep_codec *const *codecs, const void *data, size_t len,
                  void *work, size_t work_size);

/* Write up to `frames` stereo frames (4 bytes each) to `out`. Returns the
 * number written; 0 = end of stream. A short count before the end is
 * allowed, so fill the rest with silence if your callback needs it. */
size_t peep_fill (peep *p, int16_t *out, size_t frames);

void   peep_seek (peep *p, uint64_t frame);   /* clamps to the end */
void   peep_close(peep *p);

/* Native assembly FLAC (flac.asm), up to 24 bits per sample, 1 to 8 channels. */
extern const peep_codec peep_codec_flac;

static inline void peep_set_gain(peep *p, unsigned q8) { p->gain = q8 > 256 ? 256 : q8; }

#ifdef __cplusplus
}
#endif
#endif
```

#### Adding a codec

A codec is four function pointers: `open`, `read`, `seek`, `close`. Hand `peep_open` a
NULL-terminated list of them. `flac.asm` is a complete codec written in assembly. A codec that needs memory reads
`p->work` and reports what it wants in `p->work_need`. See `AGENTS.md` for the contract.

#### Speed

Decode only, data already in RAM, same machine, against `dr_flac` (the C decoder Peep used):

| FLAC file | dr_flac | Liberated Peep | |
|---|---|---|---|
| level 0 (fixed predictors) | 2184x realtime | 1875x | -14% |
| level 2 | 2358x realtime | 1953x | -17% |
| level 5 (the usual default) | 1669x realtime | 1523x | -9% |
| level 8 | 1292x realtime | 1346x | +4% |
| level 12 | 1043x realtime | 1073x | +3% |
| mono | 2468x realtime | 2585x | +5% |
| 5.1 | 1084x realtime | 1098x | +1% |
| 96 kHz | 831x realtime | 713x | -14% |
| 24-bit | 1660x realtime | 1248x | -25% |

Liberated Peep checks every frame's CRC-16; this table includes that cost. Measured against the same decoder
without the check, it costs 4% to 12% (most on lightly compressed files, least on high compression levels).

WAV decodes at about 140,000x realtime at full volume (it is a copy) and about 80,000x
with volume applied. Code size: 8.6 KB for FLAC against about 90 KB of `dr_flac`.

#### Limits

* **x86-64 only.** ARM needs a separate port. That includes Apple Silicon Macs, iPhones, Android
  phones and Raspberry Pi. Intel Macs are x86-64 but macOS is untested here, and the build would
  need `nasm -f macho64` and underscore-prefixed symbol names, which the sources do not have yet.
* **FLAC above 24 bits per sample is rejected**, as is a stream whose STREAMINFO block is
  missing or understates the maximum block size.
* **A damaged FLAC frame comes out as silence, not as a decoded error.** Every frame's CRC-16 is checked. A
  frame that fails it is replaced by silence of the same length (so timing and seek positions stay
  right) and decoding resumes at the next valid frame. A bit flip is never turned into wrong samples.
  The decoder cannot tell you that it happened: there is no error report yet.
* Seeking is a binary search over frame headers; a byte pattern that looks like a valid
  header could, very rarely, mislead it.
* Built-in WAV handles 16-bit PCM only. Other WAV formats need a codec.
* MP3 and Ogg Vorbis are not included yet (Peep itself plays them through C decoders).
* One `peep` belongs to one thread at a time. Separate `peep`s are independent.
* The Windows build is tested under Wine, not on real Windows.

#### Tests

**This is the `dev` branch: it is `main` plus the test suite and its C support files** (`peep.h`, `Makefile`,
`examples/`, `third_party/`, `tools/`). `main` is assembly only. Run the suite here:

```sh
make test                 # needs python3 with numpy; ffmpeg is not needed
```

It contains:

* `tools/mkflac.py`: a randomised FLAC **encoder** that uses every feature of the format and
  knows the exact PCM it wrote, so the decoder is checked against ground truth (all 11
  channel modes, fixed and variable block size, every block-size and sample-rate code, 4 to
  24 bit, constant / verbatim / fixed / LPC subframes, wasted bits, both Rice methods,
  escape partitions, very long unary runs, extra metadata, unknown length, random seeks)
* `tools/testwav.py`: 2,505 checks of the WAV path
* `make test-audio` (also part of `make test`): tests for stutter, clicks, crackle and garbling. `tools/testaudio.c` hammers the
  API like a hostile audio callback (random fill sizes, seeks anywhere, volume changes, canary bytes after every buffer) and
  compares every fill with a reference decode; `tools/testaudio.py` plays synthetic tones, sweeps, square waves, noise, DC,
  silence, two-tone stereo and 6 channels through WAV and 16/24-bit FLAC and judges the output alone: exact samples, identical
  bytes whatever the request sizes, exact length, no step larger than the signal allows, sine SINAD and spurious tones,
  channel integrity, exact volume, files cut short, seeks at every frame edge, and damaged frames (silence, never noise)
  They also run against library 0.4.0 and later (build `testaudio.c` with `-DPEEP_WIDE`; the Python suite detects it).
* `tools/fuzz.c`: a mutation fuzzer that puts the input and the workspace against unmapped
  guard pages and has a hang watchdog

Results at 0.1.0: thousands of random streams and seeks with zero failures; 16 million fuzz
inputs (about 32 billion frames decoded) with no crash, hang or out-of-bounds access; clean
under valgrind; identical output to `dr_flac` on every real ffmpeg-encoded file tried
(levels 0 to 12, mono, 5.1, 96 kHz, 24-bit); the Windows build passes the same corpus under
Wine. The decoder was deliberately broken in 39 ways; 35 were caught and the other 4 turned
out not to change the output. The assembly was not changed by the 0.1.1 cleanup (the objects are
byte-identical) and the suite was re-run against it.
