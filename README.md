# Liberated Peep

**Audio for All**

Liberated Peep is [Peep](https://github.com/Doggydoggywhatnow/Peep)'s playback
kernel, set free from the player. Peep is a music player that is just a screen;
Liberated Peep is what is left when you take the screen away: the part that turns
an audio file into samples, small enough to drop into any program that can call C.

Version **0.1.1**, built from **Peep 0.2.11**.

* **5.5 KB of x86-64 assembly** for WAV and FLAC together
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

## Build

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

## What is in it

| File | Code size | What |
|---|---|---|
| `peep.asm` | 1.3 KB | `peep_open / fill / seek / close`, built-in 16-bit PCM WAV (plain, extensible, odd chunks, unknown length, truncated), volume, channel mapping to stereo |
| `flac.asm` | 4.2 KB | native FLAC decoder: 4 to 24 bit, 1 to 8 channels, fixed and variable block size, every stereo mode, seeking without a seek table |
| `abi.inc` | | System V and Microsoft x64 glue, so one source builds for both |

## API reference

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

## Adding a codec

A codec is four function pointers: `open`, `read`, `seek`, `close`. Hand `peep_open` a
NULL-terminated list of them. `flac.asm` is a complete codec written in assembly. A codec that needs memory reads
`p->work` and reports what it wants in `p->work_need`. See `AGENTS.md` for the contract.

## Speed

Decode only, data already in RAM, same machine, against `dr_flac` (the C decoder Peep used):

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
with volume applied. Code size: 4.2 KB for FLAC against about 90 KB of `dr_flac`.

## Limits

* **x86-64 only.** ARM needs a separate port. That includes Apple Silicon Macs, iPhones, Android
  phones and Raspberry Pi. Intel Macs are x86-64 but macOS is untested here, and the build would
  need `nasm -f macho64` and underscore-prefixed symbol names, which the sources do not have yet.
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

This repository holds only the library (assembly) and its documentation. The test suite, which is written in
C and Python, is not kept here; it lives in git history and on the `arm64` branch:

```sh
git switch arm64          # same x86-64 sources plus the tools; also has the ARM64 port
make test                 # needs python3 with numpy
```

(or `git checkout 7c347e6 -- tools Makefile peep.h examples third_party` on this branch). It contains:

* `tools/mkflac.py`: a randomised FLAC **encoder** that uses every feature of the format and
  knows the exact PCM it wrote, so the decoder is checked against ground truth (all 11
  channel modes, fixed and variable block size, every block-size and sample-rate code, 4 to
  24 bit, constant / verbatim / fixed / LPC subframes, wasted bits, both Rice methods,
  escape partitions, very long unary runs, extra metadata, unknown length, random seeks)
* `tools/testwav.py`: 2,505 checks of the WAV path
* `tools/fuzz.c`: a mutation fuzzer that puts the input and the workspace against unmapped
  guard pages and has a hang watchdog

Results at 0.1.0: thousands of random streams and seeks with zero failures; 16 million fuzz
inputs (about 32 billion frames decoded) with no crash, hang or out-of-bounds access; clean
under valgrind; identical output to `dr_flac` on every real ffmpeg-encoded file tried
(levels 0 to 12, mono, 5.1, 96 kHz, 24-bit); the Windows build passes the same corpus under
Wine. The decoder was deliberately broken in 39 ways; 35 were caught and the other 4 turned
out not to change the output. The assembly was not changed by the 0.1.1 cleanup (the objects are
byte-identical) and the suite was re-run against it.

## For AI agents

Read [`AGENTS.md`](AGENTS.md).

## License

Public domain, under the [Unlicense](LICENSE), like Peep.
