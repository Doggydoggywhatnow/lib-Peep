# AGENTS.md: using Liberated Peep (lib-Peep) in a project

For AI coding agents. Liberated Peep ("Audio for All", version 0.5.0, built from Peep
0.2.11) is a tiny audio-decoding library: you give it the bytes of a WAV or FLAC file and it
hands back stereo 16-bit samples, on demand. It plays nothing by itself; your program sends
the samples to a sound device.

## Use it when / do not use it when

| Use it when | Do not use it when |
|---|---|
| the target is x86-64 (Linux, BSD, Windows) or ARM64 Linux (Raspberry Pi, ARM servers) | the target is 32-bit ARM, RISC-V or any other CPU: there is no port |
| you need WAV (8 to 32-bit, float) or FLAC and want no dependencies | you need MP3, Ogg Vorbis, AAC or Opus (not included; see "Other formats") |
| the audio thread must not allocate, lock or call the OS | you need 32-bit FLAC (up to 31 bits works) |
| you want a very small binary, or are embedding in an unusual runtime | you need resampling, mixing, EQ or effects (this is a decoder only) |

## Add it to a project

Pick the files for your CPU and copy them with `peep.h`. FLAC is optional.

* x86-64: `peep.asm`, `abi.inc`, `flac.asm` for FLAC and `wav.asm` for 8/24/32-bit and float WAV. Assemble with `nasm`.
* ARM64: `arm64/peep.s`, `arm64/abi_a64.inc`, `arm64/flac.s` for FLAC and `arm64/wav.s` for 8/24/32-bit and float WAV. Assemble with GNU `as`.

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

## Using it from assembly (no C header at all)

The library itself contains no C: `peep.h` is only a description of the API for C programs, and nothing in the `.asm`
or `.s` files includes it (three comments mention its name, nothing more). If your program is written in assembly, you do not need it, and you do not need a C compiler
or libc either (a static `ld` link works; see the two programs below, which were built and run on both CPUs).

**Keep** (copy these into your project):

| CPU | Required | Optional |
|---|---|---|
| x86-64 | `peep.asm`, `abi.inc` | `flac.asm` (FLAC), `wav.asm` (8/12/20/24/32-bit and float WAV) |
| ARM64 | `arm64/peep.s`, `arm64/abi_a64.inc` | `arm64/flac.s` (FLAC), `arm64/wav.s` (8/12/20/24/32-bit and float WAV) |

**Remove** (all of it is C, Python or packaging, and none of it is used by the library):

* `peep.h`: the one C header. Its job is taken over by the table below.
* `examples/` and `third_party/`: the `dr_flac` adapter and `dr_flac.h` (C).
* `tools/`: the test programs (`*.c`) and generators (`*.py`).
* `bindings/` and `Downloads/`: the language packages and their bindings.
* `Makefile`: optional. Its default target (`make`, then `build/libpeep.a`) uses only `nasm`/`as` and `ar`, but the test targets
  need `cc` and Python, so a pure-assembly project usually builds the files itself.

The C header was also one of the five places that hold the `peep` layout (see "If you modify this repository"). Without it
there are four, and only `peep.asm`/`flac.asm` (x86-64) and `arm64/abi_a64.inc`/`arm64/flac.s` (ARM64) still carry it.

**What replaces `peep.h`.** The calls use the platform C ABI, so from assembly you just follow it (System V: `rdi rsi rdx rcx r8 r9`;
Windows x64: `rcx rdx r8 r9` then the stack; AArch64: `x0` to `x5`). Result in `rax` / `x0`.

| Symbol | Arguments | Result |
|---|---|---|
| `peep_open` | `p`, `codecs`, `data`, `len`, `work`, `work_size` | 1 = ok |
| `peep_fill` / `peep_fill32` | `p`, `out`, `frames` | frames written, 0 = end |
| `peep_seek` | `p`, `frame` | |
| `peep_close` | `p` | |
| `peep_flac_metadata` | `p`, `type`, `index`, `&data` | length, or -1 |
| `peep_flac` / `peep_wavx` | none | address of that codec table |

`peep_codec_flac` and `peep_codec_wavx` are the same tables as data symbols (fine in a static link; use the functions in a shared
library). `codecs` is a NULL-terminated array of table addresses, or NULL for the built-in 16-bit WAV only.

`struct peep` is 160 bytes that you reserve (aligned to 8; read freely, write only `gain` and `dither`):

| Offset | Size | Field | | Offset | Size | Field |
|---|---|---|---|---|---|---|
| 0 | 8 | codec | | 52 | 4 | kind (0 closed, 1 WAV, 2 codec) |
| 8 | 8 | src | | 56 | 8 | data |
| 16 | 8 | len | | 64 | 8 | ctx |
| 24 | 8 | pos (frames) | | 72 | 56 | state |
| 32 | 8 | total (frames, 0 = unknown) | | 128 | 8 | work |
| 40 | 4 | rate (Hz) | | 136 | 8 | work_size |
| 44 | 4 | channels | | 144 | 8 | work_need (valid after a failed open) |
| 48 | 4 | gain (q8, 0 to 256) | | 152 | 4 | errors |
| 156 | 2 | dither (0 to 2) | | 158 | 2 | bits |

`peep_set_gain` and `peep_set_dither` are C inline functions, so in assembly write the fields yourself: `gain` is a 32-bit
value you must keep at 256 or below, `dither` a 16-bit value of 0, 1 or 2. A codec table (for writing your own codec) is five
8-byte pointers: `open`, `read`, `seek`, `close` (0 allowed), `read32` (0 allowed).

**Build and link** with no C toolchain (`-I` is needed so the assembler finds `abi.inc` / `abi_a64.inc`):

```sh
nasm -I path/to/lib-peep/ -f elf64 path/to/lib-peep/peep.asm -o peep.o        # x86-64 (add flac.asm, wav.asm if you want them)
nasm -f elf64 host.asm -o host.o && ld -o host host.o peep.o

as -I path/to/lib-peep/arm64 path/to/lib-peep/arm64/peep.s -o peep.o          # ARM64
as host.s -o host.o && ld -o host host.o peep.o
```

A complete host, x86-64 Linux (decodes a 16-bit WAV built into the program and writes the samples to standard output; the libc-free
`_start` and the `syscall`s are only for the demo, your program has its own):

```nasm
default rel
global _start
extern peep_open, peep_fill, peep_close
section .rodata
wav:     incbin "t.wav"
wav_end:
section .bss
p:       resb 160                 ; struct peep
out:     resb 4096
section .text
_start:
    lea  rdi, [p]
    xor  esi, esi                 ; no extra codecs: 16-bit WAV is built in
    lea  rdx, [wav]
    mov  ecx, wav_end - wav
    xor  r8d, r8d                 ; no workspace
    xor  r9d, r9d
    call peep_open
    test eax, eax
    jz   .bad
.l: lea  rdi, [p]
    lea  rsi, [out]
    mov  edx, 1024
    call peep_fill
    test rax, rax
    jz   .done
    mov  rdx, rax
    shl  rdx, 2                   ; 4 bytes per stereo frame
    mov  edi, 1
    lea  rsi, [out]
    mov  eax, 1                   ; write(1, out, n)
    syscall
    jmp  .l
.done:
    lea  rdi, [p]
    call peep_close
    xor  edi, edi
    mov  eax, 60                  ; exit(0)
    syscall
.bad:
    mov  edi, 1
    mov  eax, 60
    syscall
section .note.GNU-stack noalloc noexec nowrite progbits
```

The same host, ARM64 Linux:

```asm
    .global _start
    .extern peep_open, peep_fill, peep_close
    .section .rodata
    .balign 8
wav:    .incbin "t.wav"
wav_end:
    .balign 8
wavlen: .quad wav_end - wav
    .bss
    .balign 16
p:      .skip 160                 // struct peep
out:    .skip 4096
    .text
_start:
    adrp x0, p
    add  x0, x0, :lo12:p
    mov  x1, #0                   // no extra codecs: 16-bit WAV is built in
    adrp x2, wav
    add  x2, x2, :lo12:wav
    adrp x3, wavlen
    ldr  x3, [x3, :lo12:wavlen]
    mov  x4, #0                   // no workspace
    mov  x5, #0
    bl   peep_open
    cbz  w0, bad
1:  adrp x0, p
    add  x0, x0, :lo12:p
    adrp x1, out
    add  x1, x1, :lo12:out
    mov  x2, #1024
    bl   peep_fill
    cbz  x0, 2f
    lsl  x2, x0, #2               // 4 bytes per stereo frame
    mov  x0, #1
    adrp x1, out
    add  x1, x1, :lo12:out
    mov  x8, #64                  // write(1, out, n)
    svc  #0
    b    1b
2:  adrp x0, p
    add  x0, x0, :lo12:p
    bl   peep_close
    mov  x0, #0
    mov  x8, #93                  // exit(0)
    svc  #0
bad:
    mov  x0, #1
    mov  x8, #93
    svc  #0
```

Verified: both programs were assembled with `nasm`/`as` and linked with `ld` only (no `cc`, no libc, a static executable) and their output was
byte-for-byte what the C test tool produces for the same file, on x86-64 and on ARM64 (under QEMU). Not tested: an assembly host on
Windows x64 (the ABI is the Microsoft one, handled by `abi.inc`), on macOS, or on real ARM hardware. Keep `bytes` alive until `peep_close`, as always.

## The whole API (`peep.h`)

```c
peep p;                                         // 160 bytes; the caller owns it
const peep_codec *codecs[] = { &peep_codec_flac, &peep_codec_wavx, NULL };    // 16-bit WAV is always built in

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
* **WAV beyond 16-bit:** add `&peep_codec_wavx` to the `codecs` list (before or after FLAC; it needs no workspace). Use
  `peep_fill32` to keep 24/32-bit and float at full resolution.
* **`peep_fill32(&p, out32, frames)`** is the full-resolution alternative: interleaved stereo `int32`, each sample
  left-justified (`value << (32 - bits)`), volume at 64-bit precision, no rounding. Use it for 24-bit devices or your own
  mixer. For a 16-bit device fed from a >16-bit file, call `peep_set_dither(&p, 2)` (TPDF) or `1` (round); the default `0`
  truncates. `p.bits` is the source depth, `p.errors` the damaged frames met so far.
* `peep_flac_metadata(&p, type, index, &data)` returns a FLAC metadata block's length and its address (zero-copy), or
  `(size_t)-1`. Types: 0 STREAMINFO, 1 PADDING, 2 APPLICATION, 3 SEEKTABLE, 4 VORBIS_COMMENT, 5 CUESHEET, 6 PICTURE.
* **`peep_fill` output is always interleaved stereo `int16` at `p.rate`**, the file's own sample rate.
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
* **Size.** The native FLAC decoder is 9.3 KB of code on x86-64 (9.7 KB on ARM64), 4 KB of it the CRC-16
  tables; `dr_flac` is about 90 KB. The whole library, WAV and FLAC together, is 11.8 KB on x86-64 and
  12.1 KB on ARM64.
* **Speed costs nothing you can hear.** Native FLAC (x86-64, with every frame's CRC-16 checked) decodes between 25% slower and 5% faster than
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
| `dr_flac` adapter | `examples/codec_drflac.c` | Not part of the library. It is (1) the model for plugging in any other decoder, (2) the reference the native decoder is compared against in the tests, and (3) the fallback for 32-bit FLAC, which the native decoder rejects. (It still needs the core, so it is not a way to run on a CPU the core does not support.) |

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
    size_t (*read32)(peep *p, int32_t *out, size_t frames); // may be NULL: int32, left-justified (<< 32 - bits)
} peep_codec;
```

* `open`: return 0 quickly if the data is not yours (look at the magic bytes first). On success
  set `p->rate`, `p->channels` (1 to 8) and `p->total` (frames, 0 if unknown). Rate must be
  1,000 to 1,048,575 Hz or `peep_open` rejects it. Also set `p->bits` (0 means 16). Use `p->ctx` and `p->state[56]` for your state.
  Do not touch `p->pos`, `p->gain` or `p->kind`.
* `read`: write interleaved `int16` in the file's own channel count, up to `frames` frames, and
  return how many. Return 0 only at the end of the stream. Never write more than asked.
* Optional `read32`: the same frames as `int32`, left-justified, in the file's channel count. Provide it when `p->bits`
  is above 16 so `peep_fill32` and the dithered 16-bit output get the full resolution; without it they widen `read`.
  Note the `peep_codec` struct grew by one pointer: adapters compiled against the old header must be rebuilt.
* Need memory? Use `p->work` (`p->work_size` bytes). If it is NULL or too small, set
  `p->work_need` and return 0.
* If your decoder may read before the start of the workspace (the FLAC one does, by up to 16
  bytes), include that in `work_need`.
* The ABI is the platform C ABI. In assembly, copy the `FUNC` / `FUNCL` / `ARGS` macros from
  `abi.inc`; they handle System V and Microsoft x64 together.

## If you modify this repository

* The `peep` struct layout is written in **five places that must agree**: `peep.h`, the `P_*`
  constants at the top of `peep.asm`, the `P_*` / `S_*` constants (`P_ERRS` 152, `P_DITH` 156, `P_BITS` 158 are new) at the top of `flac.asm`, the
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
* A damaged FLAC frame (its CRC-16 fails) is output as silence of the same length and decoding carries on;
  `p->errors` counts them, so the caller can be told afterwards.
* 32-bit FLAC, MP3 and Vorbis are not handled natively.
* The built-in WAV is 16-bit PCM only. `peep_codec_wavx` (wav.asm / arm64/wav.s) adds unsigned 8-bit, 12/20/24/32-bit PCM and
  32/64-bit float; A-law, mu-law and ADPCM WAV are not handled.
