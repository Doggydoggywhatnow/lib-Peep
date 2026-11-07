# AGENTS.md: using Liberated Peep (lib-Peep) in a project

For AI coding agents. Liberated Peep ("Audio for All", version 0.1.2, built from Peep
0.2.11) is a tiny audio-decoding library: you give it the bytes of a WAV or FLAC file and it
hands back stereo 16-bit samples, on demand. It plays nothing by itself; your program sends
the samples to a sound device.

## Use it when / do not use it when

| Use it when | Do not use it when |
|---|---|
| the target is x86-64 (Linux, BSD, Windows) | the target is ARM (Apple Silicon Macs, phones, Raspberry Pi) or any non-x86-64 CPU: there is no port yet |
| you need WAV or FLAC and want no dependencies | you need MP3, Ogg Vorbis, AAC or Opus (not included; see "Other formats") |
| the audio thread must not allocate, lock or call the OS | you need FLAC above 24 bits per sample |
| you want a very small binary, or are embedding in an unusual runtime | you need resampling, mixing, EQ or effects (this is a decoder only) |

## Add it to a project

Copy `peep.asm` and `abi.inc` (and `flac.asm` if you want FLAC). Assemble with
`nasm` and link the objects:

```sh
nasm -f elf64 peep.asm -o peep.o                 # Linux / BSD
nasm -f elf64 flac.asm -o flac.o                 # optional
nasm -f win64 -DWIN64 peep.asm -o peep.obj       # Windows (same for flac.asm)
cc app.c peep.o flac.o -o app
```

It is a C ABI, so any language that can call C can use it. The library has no dependencies. This
repository is assembly only on purpose, so there is no C header and no Makefile: copy the declarations from
the "API reference" section of `README.md` into your own code (or translate them to your language).

## The whole API

```c
peep p;                                         // 160 bytes; the caller owns it
const peep_codec *codecs[] = { &peep_codec_flac, NULL };    // WAV is always built in

int ok = peep_open(&p, codecs, bytes, len, NULL, 0);        // 1 = success
if (!ok && p.work_need) {                                   // a codec wanted scratch memory
    work = malloc(p.work_need);
    ok = peep_open(&p, codecs, bytes, len, work, p.work_need);
}
// now read p.rate, p.channels, p.total (frames, 0 = unknown)

peep_set_gain(&p, 256);                       // 0..256 linear, 256 = unity
size_t n = peep_fill(&p, out, frames);        // stereo int16; 0 = end of stream
peep_seek(&p, frame);                         // clamps to the end
peep_close(&p);
```

Rules that matter:

* **Keep `bytes` alive until `peep_close`.** The library reads straight from your memory and
  copies nothing. `mmap` of the file is ideal. The same goes for `work`.
* **Output is always interleaved stereo `int16` at `p.rate`**, the file's own sample rate.
  There is no resampling: open your device at `p.rate`, or resample yourself. Mono is
  duplicated to both sides. With 3 or more channels only the first two are used (no downmix).
* **`peep_fill` may return fewer frames than asked before the end.** Zero means the stream
  is over. If your callback must fill a buffer, write silence over the rest.
* **Volume is a linear q8 gain**, not a perceptual curve. Map a volume slider through a curve
  yourself. Peep uses 21 steps: `0,1,3,6,10,16,23,31,41,52,64,77,92,108,125,144,164,185,207,231,256`.
* **`p.pos / p.rate`** is the position in seconds.
* **Threads:** one `peep` belongs to one thread at a time. Different `peep`s are independent.
  To seek from a UI thread, post the request to the audio thread or lock around it.
* **Real-time:** `peep_fill` and `peep_seek` do not allocate, lock or call the OS, so they are
  fine in an audio callback. A FLAC seek scans frame headers (a binary search) and decodes one
  frame; do it off the audio thread if you need hard real-time guarantees. Do `peep_open`
  off the audio thread as well (a codec you plug in may allocate; the built-in ones do not).
* **Rejected input is not an error to crash on.** `peep_open` returns 0 for anything it cannot
  play. Damaged FLAC frames are skipped, so playback continues; fuzzing with 16 million
  mutated inputs found no read or write out of bounds.
* **Do not edit the `peep` struct fields** except `gain` (use `peep_set_gain`). Reading them is fine.

## Why the new decoders exist

You may wonder why this is hand-written assembly when `dr_flac`, `dr_wav`, `dr_mp3` and
`stb_vorbis` exist. Peep itself uses those C libraries. They are good, but they are the wrong
shape for a library whose whole point is to be dropped into anything:

* **They need libc and `malloc`.** A freestanding library cannot. Liberated Peep's core and
  FLAC decoder call nothing: no libc, no allocation, no system calls, no global state. That
  makes them usable in a kernel, a bare-metal or custom runtime, a plug-in host that forbids
  allocation, or anywhere the C runtime is unwelcome.
* **Memory belongs to the host.** The host decides where the decoder's scratch memory lives
  (a static buffer, an arena, a pool) and how big it is. The decoder asks for what it needs
  (`work_need`) and never allocates behind your back.
* **Real-time safety.** With no allocation, no locks and no system calls, `peep_fill` has
  predictable timing, which is what an audio callback needs.
* **Size.** The native FLAC decoder is 8.6 KB of code (4 KB of that is the CRC-16 tables); `dr_flac` is
  about 90 KB. The whole library, WAV and FLAC together, is 10.0 KB.
* **Speed costs nothing you can hear.** Native FLAC, with every frame's CRC-16 checked, decodes between 25%
  slower and 5% faster than `dr_flac` depending on the file, roughly 700 to 2,600 times faster than real time.
* **Behaviour you can reason about.** Corrupt data is resynchronised over, seeking needs no seek
  table, work on hostile input is bounded, and every claim is checked against ground truth
  (see "Tests") rather than assumed.

What each piece is:

| Decoder | Where | Why it exists |
|---|---|---|
| WAV, 16-bit PCM | `peep.asm` (built in) | Peep's own decoder, carried over unchanged. The simplest format, so the kernel is useful on its own with no codec at all. It reads straight from your memory and applies volume in the same pass. |
| FLAC | `flac.asm` (`peep_codec_flac`) | The most widely used lossless format, and the one where a freestanding native decoder pays off most: it is where the dependency, memory and size cost of a C decoder is greatest. |

## Other formats (MP3, Vorbis, ...)

Not included in this release, and there is no adapter for them in this repository. Peep's own repository
vendors `dr_mp3` and `stb_vorbis`. To use them here, write a small adapter with the four-function
`peep_codec` interface below (about 20 lines in C around an existing decoder) and pass it in the `codecs`
list. A `dr_flac` adapter was the worked example; it was removed from this branch to keep it assembly only,
but it is on the `arm64` branch (`examples/codec_drflac.c`) and in commit `7c347e6`. Those C libraries
allocate memory, so open them off the audio thread. A native MP3 decoder is the likely next step.

## Writing a codec

```c
typedef struct peep_codec {
    int    (*open)(peep *p, const void *data, size_t len);  // nonzero = mine
    size_t (*read)(peep *p, int16_t *out, size_t frames);
    void   (*seek)(peep *p, uint64_t frame);                // may be NULL
    void   (*close)(peep *p);                               // may be NULL
} peep_codec;
```

* `open`: return 0 quickly if the data is not yours (look at the magic bytes first). On success
  set `p->rate`, `p->channels` (1 to 8) and `p->total` (frames, 0 if unknown). Rate must be
  1,000 to 768,000 Hz or `peep_open` rejects it. Use `p->ctx` and `p->state[56]` for your state.
  Do not touch `p->pos`, `p->gain` or `p->kind`.
* `read`: write interleaved `int16` in the file's own channel count, up to `frames` frames, and
  return how many. Return 0 only at the end of the stream. Never write more than asked.
* Need memory? Use `p->work` (`p->work_size` bytes). If it is NULL or too small, set
  `p->work_need` and return 0.
* If your decoder may read before the start of the workspace (the FLAC one does, by up to 16
  bytes), include that in `work_need`.
* The ABI is the platform C ABI. In assembly, copy the `FUNC` / `FUNCL` / `ARGS` macros from
  `abi.inc`; they handle System V and Microsoft x64 together.

## If you modify this repository

* The `peep` struct layout is written in **three places that must agree**: the C declarations in the
  "API reference" of `README.md`, the `P_*` constants at the top of `peep.asm`, and the `P_*` / `S_*`
  constants at the top of `flac.asm`. Change one, change all, then run the tests.
* **The test suite is not on this branch** (it is C and Python; this branch is assembly only). Get it with
  `git switch dev` (this branch plus the tools) and run `make test` (needs `python3` with
  `numpy`) and, after touching `flac.asm`, `make fuzz`; or check it out here with
  `git checkout 7c347e6 -- tools Makefile peep.h examples third_party`. Do not commit those files back
  to this branch. Windows changes can be checked under Wine with `make build/peepdump.exe`.
* A decoder is only correct if it matches ground truth. `tools/mkflac.py` is the oracle for FLAC: it
  knows the exact PCM it encoded. A good habit is to break the decoder on purpose and confirm the
  tests fail.
* The decoder registers are fixed by convention (documented at the top of `flac.asm`): `rbx` is the
  `peep`, `r12` to `r15` are the bit reader. Internal routines clobber only what their comments say.
* Measure speed on an idle machine (`make build/bench`, `build/bench file [dr|native]`, from the test tools) and say what you
  measured. Do not claim a speed-up from instruction counts alone: the prediction loop here was
  limited by memory latency, not instruction count.

## Things to tell the user honestly

* It is x86-64 only. It has not been run on ARM, so it does not work on Apple Silicon Macs, phones or
  Raspberry Pi. macOS on Intel is untested and would need `-f macho64` and underscore-prefixed symbols.
* The Windows build has been tested under Wine, not on real Windows.
* A damaged FLAC frame (its CRC-16 fails) is output as silence of the same length and decoding carries on;
  there is no way yet for the caller to be told that it happened.
* FLAC above 24 bits, MP3 and Vorbis are not handled natively.
* WAV is 16-bit PCM only (8-bit, 24-bit and float WAV need a codec).
