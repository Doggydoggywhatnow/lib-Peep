# AGENTS.md: using Liberated Peep (lib-Peep) in a project

For AI coding agents. Liberated Peep ("Audio for All", version 0.3.0, built from Peep
0.2.11) is a tiny audio-decoding library: you give it the bytes of a WAV or FLAC file and it
hands back stereo 16-bit samples, on demand. It plays nothing by itself; your program sends
the samples to a sound device.

## Use it when / do not use it when

| Use it when | Do not use it when |
|---|---|
| the target is x86-64 (Linux, BSD, Windows) or ARM64 Linux (Raspberry Pi, ARM servers) | the target is 32-bit ARM, RISC-V or any other CPU: there is no port |
| you need WAV or FLAC and want no dependencies | you need MP3, Ogg Vorbis, AAC or Opus (not included; see "Other formats") |
| the audio thread must not allocate, lock or call the OS | you need FLAC above 24 bits per sample |
| you want a very small binary, or are embedding in an unusual runtime | you need resampling, mixing, EQ or effects (this is a decoder only) |

## Add it to a project

Pick the files for your CPU and copy them with `peep.h`. FLAC is optional.

* x86-64: `peep.asm`, `abi.inc`, and `flac.asm` for FLAC. Assemble with `nasm`.
* ARM64: `arm64/peep.s`, `arm64/abi_a64.inc`, and `arm64/flac.s` for FLAC. Assemble with GNU `as`.

```sh
# ARM64 (Linux)
as -I arm64 arm64/peep.s -o peep.o
as -I arm64 arm64/flac.s -o flac.o               # optional
cc app.c peep.o flac.o -o app
```

x86-64:

```sh
nasm -f elf64 peep.asm -o peep.o                 # Linux / BSD
nasm -f elf64 flac.asm -o flac.o                 # optional
nasm -f win64 -DWIN64 peep.asm -o peep.obj       # Windows (same for flac.asm)
cc app.c peep.o flac.o -o app
```

`make` in this repo does the same and builds `build/libpeep.a` (or `build/libpeep_a64.a` on an ARM64 machine). It is a C ABI, so any
language that can call C can use it. The library has no dependencies; `third_party/dr_flac.h`
is only for the example adapter and the tests.

## Using it from another language

`Downloads/Header Versions/<Language>/` is a ready-made package for each of 22 languages (Bun, C#, C++, Common
Lisp, D, F#, Fortran, Free Pascal, Go, Guile, Java, LuaJIT, Nim, Node.js, Perl, PHP, Python, Racket, Raku, Ruby, Rust,
Visual Basic .NET). If your language is listed, use that package: run its `./build.sh`, then follow its README.
Do not mix packages: each has one binding and no C header on purpose. For a language that is not listed, call the
C ABI below through its FFI. Every FFI can use these five functions: `peep_open`, `peep_fill`, `peep_seek`,
`peep_close` and `peep_flac()` (returns the FLAC codec table's address, so you never need to read a data
symbol). Build a shared library first (`build.sh` shows how). Only Linux x86-64 was tested for the bindings.

## The whole API (`peep.h`)

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
  off the audio thread as well (the dr_flac example adapter calls `malloc`).
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
* **Size.** The native FLAC decoder is 4.2 KB of code on x86-64 (4.6 KB on ARM64); `dr_flac` is about
  90 KB. The whole library, WAV and FLAC together, is 5.5 KB on x86-64 and 6.0 KB on ARM64.
* **Speed costs nothing.** Native FLAC decodes between 16% slower and 16% faster than
  `dr_flac` depending on the file, roughly 700 to 2,500 times faster than real time. Choosing the
  small decoder does not slow anything audible.
* **Behaviour you can reason about.** Corrupt data is resynchronised over, seeking needs no seek
  table, work on hostile input is bounded, and every claim is checked against ground truth
  (see "Tests") rather than assumed.

What each piece is:

| Decoder | Where | Why it exists |
|---|---|---|
| WAV, 16-bit PCM | `peep.asm` (built in) | Peep's own decoder, carried over unchanged. The simplest format, so the kernel is useful on its own with no codec at all. It reads straight from your memory and applies volume in the same pass. |
| FLAC | `flac.asm` (`peep_codec_flac`) | The most widely used lossless format, and the one where a freestanding native decoder pays off most: it is where the dependency, memory and size cost of a C decoder is greatest. |
| `dr_flac` adapter | `examples/codec_drflac.c` | Not part of the library. It is (1) the model for plugging in any other decoder, (2) the reference the native decoder is compared against in the tests, and (3) the fallback for FLAC above 24 bits per sample, which the native decoder rejects. (It still needs the core, so it is not a way to run on a CPU the core does not support.) |

## Other formats (MP3, Vorbis, ...)

Not included in this release, and there is no adapter for them in this repository. Peep's own repository
vendors `dr_mp3` and `stb_vorbis`. To use them here, write an adapter in the style of
`examples/codec_drflac.c` (about 20 lines) and pass it in the `codecs` list. Those C libraries
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

* The `peep` struct layout is written in **five places that must agree**: `peep.h`, the `P_*`
  constants at the top of `peep.asm`, the `P_*` / `S_*` constants at the top of `flac.asm`, the
  `P_*` constants in `arm64/abi_a64.inc`, and the `S_*` constants at the top of `arm64/flac.s`.
  Change one, change all, then run the tests.
* The two ports are the same design in two instruction sets. A behaviour change belongs in both, and
  both must pass the same tests: `make test` (x86-64) and `make test-arm64` (ARM64).
* Run `make test` after every change (needs `python3` with `numpy`). ARM64 changes: `make test-arm64
  CROSS=aarch64-linux-gnu-` (needs `qemu-aarch64`; on a real ARM machine leave `CROSS` empty). After touching `flac.asm` also
  run `make fuzz`. Windows changes can be checked under Wine: `make build/peepdump.exe` (needs mingw-w64),
  then run it with `wine` on the same files and compare the output with the Linux build.
* A decoder is only correct if it matches ground truth. `tools/mkflac.py` is the oracle for FLAC: it
  knows the exact PCM it encoded. A good habit is to break the decoder on purpose and confirm the
  tests fail.
* The decoder registers are fixed by convention (documented at the top of `flac.asm`): `rbx` is the
  `peep`, `r12` to `r15` are the bit reader. Internal routines clobber only what their comments say.
* Measure speed on an idle machine (`make build/bench`, `build/bench file [dr|native]`) and say what you
  measured. Do not claim a speed-up from instruction counts alone: the prediction loop here was
  limited by memory latency, not instruction count.

## Things to tell the user honestly

* The ARM64 port has only been run under QEMU emulation, never on real ARM hardware, and its speed has
  not been measured. Correctness is verified; real-world speed is not.
* Apple Silicon Macs, iPhones and Windows on ARM are not verified. A macOS mode exists in the ARM64
  sources (`--defsym APPLE=1`) but has never been assembled or run. Intel Macs are untested too.
* 32-bit ARM is not supported.
* The Windows build has been tested under Wine, not on real Windows.
* FLAC audio data is not CRC-16 checked, so a flipped bit inside audio gives a wrong sample.
* FLAC above 24 bits, MP3 and Vorbis are not handled natively.
* WAV is 16-bit PCM only (8-bit, 24-bit and float WAV need a codec).
