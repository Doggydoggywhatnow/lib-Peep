# AGENTS.md: using Liberated Peep (lib-Peep) in a project

For AI coding agents. Liberated Peep ("Audio for All", version 0.5.0, built from Peep
0.2.11) is a tiny audio-decoding library: you give it the bytes of a WAV or FLAC file and it
hands back stereo 16-bit samples, on demand. It plays nothing by itself; your program sends
the samples to a sound device.

**Branches.** `main` is the assembly and documentation only, at the old x86-64 version 0.1.2. **`dev` (this branch) has the library
at 0.5.0, identical to `arm64` except for two speed experiments in `flac.asm` and `arm64/flac.s` (fused fixed-predictor and LPC decoding in the residual loop, and a vector LPC loop: SSE4.1 chosen by `cpuid` on x86-64, NEON on ARM64) and the new compressed-WAV codec (`wavc.asm`, `arm64/wavc.s`); see the CHANGELOG, plus the test suite and its C and Python support files** (`peep.h`, `Makefile`, `examples/`,
`third_party/`, `tools/`), the audio-quality tests, and the AppImage tooling. `arm64` has all of that and also the 22 language packages
(`Downloads/`) and their bindings (`bindings/`), which are not on this branch. The earlier x86-64-only AGENTS.md is kept at the
end of this file, marked as historical: where it disagrees with the text above, the text above is right.

## Use it when / do not use it when

| Use it when | Do not use it when |
|---|---|
| the target is x86-64 (Linux, BSD, Windows) or ARM64 Linux (Raspberry Pi, ARM servers) | the target is 32-bit ARM, RISC-V or any other CPU: there is no port |
| you need WAV (8 to 32-bit, float, A-law, mu-law, IMA and MS ADPCM) or FLAC and want no dependencies | you need MP3, Ogg Vorbis, AAC or Opus (not included; see "Other formats") |
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

On the `arm64` branch (not on `dev`), `Downloads/Header Versions/<Language>/` is a ready-made package for each of 22 languages (Bun, C#, C++, Common
Lisp, D, F#, Fortran, Free Pascal, Go, Guile, Java, LuaJIT, Nim, Node.js, Perl, PHP, Python, Racket, Raku, Ruby, Rust,
Visual Basic .NET). If your language is listed, use that package: run its `./build.sh`, then follow its README.
Do not mix packages: each has one binding and no C header on purpose. For a language that is not listed, call the
C ABI below through its FFI. Every FFI can use these five functions: `peep_open`, `peep_fill`, `peep_seek`,
`peep_close` and `peep_flac()` (returns the FLAC codec table's address, so you never need to read a data
symbol). Build a shared library first (`build.sh` shows how). Only Linux x86-64 was tested for the bindings.

## Using it from assembly (no C header at all)

This section is the complete reference for a program written in assembly, on x86-64 or ARM64, that uses Liberated Peep. You do
not need `peep.h`, a C compiler or libc. The library itself contains no C: `peep.h` only describes the API for C programs, and nothing in
the `.asm` or `.s` files includes it (three comments mention its name, nothing more). Everything the header says is restated below.

### 1. Files: what to keep, what to remove

| CPU | Required | Optional |
|---|---|---|
| x86-64 | `peep.asm`, `abi.inc` | `flac.asm` (FLAC), `wav.asm` (8/12/20/24/32-bit and float WAV), `wavc.asm` (A-law, mu-law, IMA and MS ADPCM WAV) |
| ARM64 | `arm64/peep.s`, `arm64/abi_a64.inc` | `arm64/flac.s` (FLAC), `arm64/wav.s` (8/12/20/24/32-bit and float WAV), `arm64/wavc.s` (A-law, mu-law, IMA and MS ADPCM WAV) |

Remove (C, Python or packaging; the library uses none of it):

* `peep.h`: the one C header. Sections 4 and 5 replace it.
* `examples/` and `third_party/`: the `dr_flac` adapter and `dr_flac.h` (C).
* `tools/`: the test programs (`*.c`) and generators (`*.py`).
* `bindings/` and `Downloads/`: the language packages and their bindings (they exist on the `arm64` branch only).
* `Makefile`: optional. `make` (target `build/libpeep.a`) needs only `nasm`/`as` and `ar`; the test targets need `cc` and Python.

The `peep` layout was written in five places (see "If you modify this repository"); without `peep.h` it is in four.

### 2. Build and link (no C toolchain)

`-I` is required so the assembler finds `abi.inc` / `abi_a64.inc` when you assemble from another directory.

```sh
# x86-64 Linux (add flac.asm and wav.asm the same way if you use them)
nasm -I path/to/lib-peep/ -f elf64 path/to/lib-peep/peep.asm -o peep.o
nasm -f elf64 host.asm -o host.o && ld -o host host.o peep.o

# ARM64 Linux
as -I path/to/lib-peep/arm64 path/to/lib-peep/arm64/peep.s -o peep.o
as host.s -o host.o && ld -o host host.o peep.o
```

For Windows x64 use `nasm -f win64 -DWIN64` (section 7). Leaving out `flac.asm` / `wav.asm` leaves those codecs out of the program; their
tables (`peep_flac`, `peep_wavx`) then do not exist.

### 3. The contract with the caller

* **Calling convention:** the platform C ABI, exactly. System V x86-64 (`rdi rsi rdx rcx r8 r9`), Windows x64 (`rcx rdx r8 r9`, then the stack),
  AArch64 (`x0` to `x5`). The result is in `rax` / `x0`. A 32-bit result (`peep_open`) is in `eax` / `w0`; read only that half.
* **Registers:** the library preserves every callee-saved register of the ABI (x86-64: `rbx rbp r12 to r15`, and `rsi rdi` as well for Windows;
  ARM64: `x19` to `x29` and `d8` to `d15`). Everything else may be clobbered: `rax rcx rdx rsi rdi r8 to r11 xmm0 to xmm7` (x86-64), `x0 to x17 v0 to v7`
  (ARM64). ARM64 never touches `x18`. Checked on every call with marker values (section 10).
* **Stack:** `rsp` must be 16-byte aligned at the `call` (x86-64) and `sp` at the `bl` (ARM64), as the ABI says. The deepest use measured over the whole test
  corpus (open, fill, fill32, seek, metadata, 8-channel FLAC with dither) is about 4.2 KB on x86-64 and 4.1 KB on ARM64 (`peep_fill` alone keeps a 3 KB
  frame). Leave at least 8 KB free. On x86-64 do not keep data below `rsp` across a call (the return address overwrites the red zone).
* **CPU state:** x86-64 code runs on baseline SSE2 alone. On `dev`, `flac.asm` also has an SSE4.1 loop for LPC prediction that `peep_open` enables only if `cpuid` reports SSE4.1 (the `cpuid` instruction runs once per FLAC open, and can be slow inside a virtual machine); no AVX is used. Build with `nasm -dNOSIMD` to force the scalar loop. The direction flag must be clear (`peep_open` uses `rep stosq`; the ABI already says so).
  Float WAV conversion uses the current rounding mode, so leave MXCSR at round-to-nearest (the default). ARM64 uses NEON and rounds explicitly.
* **Alignment:** `data` (the file) and `work` may start at any address: input shifted by 1 byte and workspace by 3 bytes gave identical output on both CPUs. Align the
  160-byte `peep` struct to 8 bytes. Output buffers: align them to 16 (misaligned output buffers have not been tested).
* **Lifetime:** keep the file bytes (`data`) and the workspace alive and unchanged from `peep_open` until `peep_close`; the library reads your memory in place and copies
  nothing. Do not move or copy an open `peep`.
* **Memory:** the library allocates nothing and makes no system call. Everything it needs is your `peep`, your workspace and your stack.
* **Threads:** one `peep` belongs to one thread at a time; different `peep`s are independent. `peep_fill` and `peep_seek` take no locks and call nothing, so they
  are fine in an audio callback (a FLAC seek decodes one frame; do it off the audio thread if you need hard real time). Run `peep_open` off the audio thread.

### 4. `struct peep`: reserve 160 bytes

You reserve it; `peep_open` clears all 160 bytes itself and sets `gain` to 256 (you do not zero it). Read any field. Write only `gain` and `dither`.

| Offset | Size | Field | Meaning |
|---|---|---|---|
| 0 | 8 | codec | the codec table in use (0 = built-in WAV) |
| 8 | 8 | src | the file's address |
| 16 | 8 | len | the file's length |
| 24 | 8 | pos | next frame to be returned (frames) |
| 32 | 8 | total | length in frames, 0 = unknown |
| 40 | 4 | rate | sample rate in Hz (1,000 to 1,048,575) |
| 44 | 4 | channels | channels in the file (1 to 8) |
| 48 | 4 | gain | **you write:** volume, q8: 256 = unity, 0 = silence; values above 256 count as 256 |
| 52 | 4 | kind | 0 closed, 1 built-in WAV, 2 codec |
| 56 | 8 | data | built-in WAV: address of the first sample |
| 64 | 8 | ctx | codec use |
| 72 | 56 | state | codec use |
| 128 | 8 | work | the workspace you lent |
| 136 | 8 | work_size | its size |
| 144 | 8 | work_need | bytes a codec wanted; valid after a failed open |
| 152 | 4 | errors | damaged frames met so far (FLAC) |
| 156 | 2 | dither | **you write:** reduction to 16 bits for sources wider than 16 bits: 0 truncate (default), 1 round, 2 TPDF dither; above 2 counts as 2 |
| 158 | 2 | bits | bits per sample of the source (built-in WAV 16; FLAC 4 to 31; wav.asm: the valid bits, float 32) |

`peep_set_gain(p, q)` and `peep_set_dither(p, m)` are C inline functions: in assembly store a 32-bit value at offset 48 and a 16-bit value at offset 156.
A codec table (`peep_codec`) is five 8-byte pointers: offset 0 `open`, 8 `read`, 16 `seek`, 24 `close`, 32 `read32`. `seek`, `close` and `read32` may be 0.

### 5. The functions

| Symbol | Arguments | Result |
|---|---|---|
| `peep_open` | `p`, `codecs`, `data`, `len`, `work`, `work_size` | `eax`: 1 ok, 0 not playable |
| `peep_fill` | `p`, `out`, `frames` | frames written |
| `peep_fill32` | `p`, `out`, `frames` | frames written |
| `peep_seek` | `p`, `frame` | none |
| `peep_close` | `p` | none |
| `peep_flac_metadata` | `p`, `type`, `index`, `&data` | block length, or -1 |
| `peep_flac`, `peep_wavx`, `peep_wavc` | none | address of that codec's table |

* **`peep_open`** tries the built-in 16-bit PCM WAV (plain and extensible) first, then each codec in `codecs` in order. `codecs` is a NULL-terminated array of 8-byte table
  addresses, or 0 for the built-in WAV alone. Get a table's address from `peep_flac()` / `peep_wavx()` (works in a static link and in a shared library); the data symbols
  `peep_codec_flac` / `peep_codec_wavx` are the same tables. It returns 0 for anything it cannot play, including a sample rate outside 1,000 to 1,048,575 Hz or more than 8 channels.
  **Workspace protocol:** pass `work` = 0, `work_size` = 0 first. If it returns 0 and `[p + 144]` (`work_need`) is nonzero, a codec wants that many bytes: call `peep_open` again with
  `work` = a buffer of at least that size and `work_size` = its size. If it returns 0 and `work_need` is 0, the data is not supported. FLAC needs `channels * max_blocksize * 4 + 16`
  bytes: typically 36 KB, at most 2,097,136 (8 channels, 65,535-sample blocks), so a static 2 MB buffer always suffices. WAV, wav.asm and wavc.asm's A-law / mu-law need none; wavc.asm's IMA and MS ADPCM need 80 bytes (`work_need` = 80). The second call clears `p` again, so
  load every argument before each call.
* **`peep_fill`** writes up to `frames` stereo frames, 4 bytes each, little-endian `int16` left then right, to `out` (room for `frames * 4` bytes), and returns how many. Mono is written to
  both sides; with 3 or more channels only the first two are used. It may return **fewer** than asked before the end; **0 means the end** (and every later call returns 0 until you seek).
  Asking for 0 frames returns 0. It never writes beyond what you asked for. `gain` is applied in the same pass; a source wider than 16 bits is reduced as `dither` says. Output is at
  the file's own `rate`: there is no resampling.
* **`peep_fill32`** is the same with 8-byte frames: little-endian `int32` left then right, each sample left-justified (`value << (32 - bits)`), `gain` applied at 64-bit precision, no
  rounding. Room for `frames * 8` bytes.
* **`peep_seek`** moves to `frame` (the next fill starts there). It clamps to `total` when the length is known; for a stream of unknown length it takes the position you give, and fills
  past the real end return 0. `pos` is updated.
* **`peep_close`** calls the codec's `close` if it has one and sets `kind` to 0 (later fills return 0). It frees nothing: the memory is yours. The `peep` can be opened again.
* **`peep_flac_metadata`** returns the length of the `index`-th (from 0) metadata block of that `type` (0 STREAMINFO, 1 PADDING, 2 APPLICATION, 3 SEEKTABLE, 4 VORBIS_COMMENT,
  5 CUESHEET, 6 PICTURE) and stores its address, inside your file memory, at `*data` (pass 0 to skip the store). It returns -1 if there is no such block or `p` is not a FLAC file.

### 6. The sequence of a program

1. Reserve 160 bytes (`p`), a NULL-terminated codec list, and a workspace if you use FLAC.
2. `peep_open` (twice if it asked for memory, see above). Read `rate`, `channels`, `total`, `bits` and `kind` from `p`.
3. Optionally store `gain` (offset 48) and `dither` (offset 156).
4. Loop: `peep_fill` or `peep_fill32` into your buffer; hand the frames to your sound device; stop at 0 (fill any unfilled rest of a callback buffer with silence yourself).
5. `peep_seek` whenever you like; the next fill continues from there.
6. `peep_close`.

### 7. Windows x64

Assemble with `nasm -f win64 -DWIN64` (`abi.inc` then emits Microsoft-ABI entry points). Arguments: `rcx rdx r8 r9`, then the 5th and 6th (`peep_open`'s `work`, `work_size`) on the stack
at `[rsp + 32]` and `[rsp + 40]` at the moment of the `call`, above the 32-byte shadow space you must reserve. `rsp` is 16-byte aligned at the call. `rsi`, `rdi`, `rbx`, `rbp`,
`r12` to `r15` and `xmm6` to `xmm15` are preserved by the callee, and the library preserves them. Nothing in this section was run on Windows from an assembly host (the library
build was tested under Wine).

### 8. Writing a codec in assembly

A codec is the five-pointer table above plus its functions, which follow the same ABI as everything else (callee-saved registers preserved; the examples below use System V / AArch64 registers).

* `open(p, data, len)`: return 0 at once if the data is not yours (check the magic). On success store `rate` (u32 at 40), `channels` (u32 at 44, 1 to 8), `total` (u64 at 32, 0 if unknown) and
  `bits` (u16 at 158), and return 1. `p->src` and `p->len` already hold the file. Keep your state in `ctx` (offset 64) and `state` (offsets 72 to 127). Do not touch `pos`, `gain` or `kind`.
* If you need memory, take it from `work` / `work_size` (offsets 128 / 136); if it is 0 or too small, store the byte count you need at `work_need` (offset 144) and return 0.
* `read(p, out, frames)`: write interleaved `int16`, the file's own channel count, at most `frames` frames; return how many; 0 only at the end. Keep your own cursor in `state`.
* `seek(p, frame)`, `close(p)`: optional. `read32(p, out, frames)`: optional; int32, left-justified, native channel count; provide it when `bits` is above 16 so `peep_fill32` and dithering get every bit
  (without it they widen `read`'s output).
* Put the table in writable or relocatable data. It may sit anywhere in the codec list; codecs are tried in order after the built-in WAV.

### 9. Complete examples (all built and run; see section 10)

Smallest possible host, x86-64 Linux: decode a 16-bit WAV (`t.wav`) built into the program and write the samples to standard output. The libc-free `_start` and `syscall`s are for the demo only.

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

The same, ARM64 Linux:

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

The whole API from assembly, x86-64 Linux (input `t.flac`, a stereo FLAC): FLAC and WAV-extension codec list built with `peep_flac()` / `peep_wavx()`, the workspace retry, gain, seek, `peep_fill32`,
dither with `peep_fill`, metadata, close. Link it with `peep.o`, `flac.o` and `wav.o`.

```nasm
default rel
global _start
extern peep_open, peep_fill, peep_fill32, peep_seek, peep_close, peep_flac_metadata, peep_flac, peep_wavx
section .rodata
file:    incbin "t.flac"
file_end:
section .bss
align 16
p:       resb 160                 ; struct peep
codecs:  resq 3                   ; NULL-terminated list of codec tables
blk:     resq 1                   ; metadata block address
work:    resb 65536               ; workspace lent to FLAC
out32:   resb 4096
out16:   resb 1024

%macro WRITE 2                    ; write(1, buffer, bytes)
    mov  edi, 1
    lea  rsi, [%1]
    mov  edx, %2
    mov  eax, 1
    syscall
%endmacro

section .text
_start:
    call peep_flac               ; the FLAC table's address (works in a shared library too)
    mov  [codecs], rax
    call peep_wavx               ; the WAV extension table
    mov  [codecs + 8], rax        ; codecs + 16 stays 0: the list's end
    lea  rdi, [p]
    lea  rsi, [codecs]
    lea  rdx, [file]
    mov  ecx, file_end - file
    xor  r8d, r8d                 ; first try without a workspace
    xor  r9d, r9d
    call peep_open
    test eax, eax
    jnz  bad                      ; FLAC must ask for memory
    mov  rax, [p + 144]           ; work_need
    test rax, rax
    jz   bad
    cmp  rax, 65536
    ja   bad
    lea  rdi, [p]
    lea  rsi, [codecs]
    lea  rdx, [file]
    mov  ecx, file_end - file
    lea  r8, [work]
    mov  r9, [p + 144]            ; work_size: what it asked for
    call peep_open
    test eax, eax
    jz   bad
    mov  dword [p + 48], 128      ; gain: half volume (q8)
    lea  rdi, [p]
    mov  esi, 100
    call peep_seek
    lea  rdi, [p]
    lea  rsi, [out32]
    mov  edx, 512
    call peep_fill32             ; stereo int32, left-justified
    cmp  rax, 512
    jne  bad
    WRITE out32, 4096
    mov  word [p + 156], 2        ; dither: TPDF
    lea  rdi, [p]
    lea  rsi, [out16]
    mov  edx, 256
    call peep_fill               ; stereo int16
    cmp  rax, 256
    jne  bad
    WRITE out16, 1024
    lea  rdi, [p]
    xor  esi, esi                 ; type 0: STREAMINFO
    xor  edx, edx                 ; index 0
    lea  rcx, [blk]
    call peep_flac_metadata
    cmp  rax, 34
    jne  bad
    mov  rsi, [blk]
    mov  edx, 34
    mov  edi, 1
    mov  eax, 1
    syscall
    lea  rdi, [p]
    call peep_close
    xor  edi, edi
    mov  eax, 60
    syscall
bad:
    mov  edi, 1
    mov  eax, 60
    syscall
section .note.GNU-stack noalloc noexec nowrite progbits
```

The same, ARM64 Linux:

```asm
    .global _start
    .extern peep_open, peep_fill, peep_fill32, peep_seek, peep_close, peep_flac_metadata, peep_flac, peep_wavx
    .section .rodata
    .balign 8
file:   .incbin "t.flac"
file_end:
    .balign 8
filelen: .quad file_end - file
    .bss
    .balign 16
p:      .skip 160                 // struct peep
codecs: .skip 24                  // NULL-terminated list of codec tables
blk:    .skip 8                   // metadata block address
work:   .skip 65536               // workspace lent to FLAC
out32:  .skip 4096
out16:  .skip 1024

.macro LEA reg, sym
    adrp \reg, \sym
    add  \reg, \reg, :lo12:\sym
.endm
.macro WRITE buf, bytes           // write(1, buf, bytes)
    mov  x0, #1
    LEA  x1, \buf
    mov  x2, #\bytes
    mov  x8, #64
    svc  #0
.endm
    .text
_start:
    bl   peep_flac               // the FLAC table's address (works in a shared library too)
    LEA  x1, codecs
    str  x0, [x1]
    bl   peep_wavx               // the WAV extension table
    LEA  x1, codecs
    str  x0, [x1, #8]             // codecs + 16 stays 0: the list's end
    LEA  x0, p
    LEA  x1, codecs
    LEA  x2, file
    LEA  x3, filelen
    ldr  x3, [x3]
    mov  x4, #0                   // first try without a workspace
    mov  x5, #0
    bl   peep_open
    cbnz w0, bad                  // FLAC must ask for memory
    LEA  x9, p
    ldr  x5, [x9, #144]           // work_need
    cbz  x5, bad
    mov  x10, #65536
    cmp  x5, x10
    b.hi bad
    LEA  x0, p
    LEA  x1, codecs
    LEA  x2, file
    LEA  x3, filelen
    ldr  x3, [x3]
    LEA  x4, work
    LEA  x9, p
    ldr  x5, [x9, #144]           // work_size: what it asked for
    bl   peep_open
    cbz  w0, bad
    LEA  x9, p
    mov  w10, #128
    str  w10, [x9, #48]           // gain: half volume (q8)
    LEA  x0, p
    mov  x1, #100
    bl   peep_seek
    LEA  x0, p
    LEA  x1, out32
    mov  x2, #512
    bl   peep_fill32             // stereo int32, left-justified
    cmp  x0, #512
    b.ne bad
    WRITE out32, 4096
    LEA  x9, p
    mov  w10, #2
    strh w10, [x9, #156]          // dither: TPDF
    LEA  x0, p
    LEA  x1, out16
    mov  x2, #256
    bl   peep_fill               // stereo int16
    cmp  x0, #256
    b.ne bad
    WRITE out16, 1024
    LEA  x0, p
    mov  w1, #0                   // type 0: STREAMINFO
    mov  w2, #0                   // index 0
    LEA  x3, blk
    bl   peep_flac_metadata
    cmp  x0, #34
    b.ne bad
    LEA  x1, blk
    ldr  x1, [x1]
    mov  x2, #34
    mov  x0, #1
    mov  x8, #64
    svc  #0
    LEA  x0, p
    bl   peep_close
    mov  x0, #0
    mov  x8, #93
    svc  #0
bad:
    mov  x0, #1
    mov  x8, #93
    svc  #0
```

A codec written in assembly (input `t.raw8`: the bytes `RAW8` then unsigned 8-bit mono samples at 8000 Hz), x86-64 Linux:

```nasm
; A minimal codec in assembly: "RAW8" + unsigned 8-bit mono samples at 8000 Hz. System V registers (rdi rsi rdx).
default rel
global _start
extern peep_open, peep_fill, peep_seek, peep_close
section .rodata
file:    incbin "t.raw8"
file_end:
section .data
align 8
raw8:    dq raw8_open, raw8_read, raw8_seek, 0, 0      ; open, read, seek, close (none), read32 (none)
codecs:  dq raw8, 0                                    ; NULL-terminated list
section .bss
align 16
p:       resb 160
out:     resb 4096

section .text
; int open(peep *p, const void *data, size_t len): nonzero = this data is mine
raw8_open:
    cmp  rdx, 4
    jb   .no
    cmp  dword [rsi], 'RAW8'
    jne  .no
    mov  dword [rdi + 40], 8000   ; rate
    mov  dword [rdi + 44], 1      ; channels
    lea  rax, [rdx - 4]
    mov  [rdi + 32], rax          ; total frames
    mov  word [rdi + 158], 8      ; bits
    mov  qword [rdi + 72], 0      ; my cursor, in the state area
    mov  eax, 1
    ret
.no:xor  eax, eax
    ret
; size_t read(peep *p, int16_t *out, size_t frames): the file's own channel count (the core makes it stereo)
raw8_read:
    mov  rax, [rdi + 32]
    sub  rax, [rdi + 72]          ; frames left
    cmp  rdx, rax
    cmova rdx, rax
    mov  r8, rdx                  ; the count to return
    mov  rcx, [rdi + 8]           ; p->src
    add  rcx, 4
    add  rcx, [rdi + 72]
    test rdx, rdx
    jz   .d
.l: movzx eax, byte [rcx]
    sub  eax, 128
    shl  eax, 8
    mov  [rsi], ax
    inc  rcx
    add  rsi, 2
    dec  rdx
    jnz  .l
.d: add  [rdi + 72], r8
    mov  rax, r8
    ret
; void seek(peep *p, uint64_t frame)
raw8_seek:
    mov  rax, [rdi + 32]
    cmp  rsi, rax
    cmova rsi, rax
    mov  [rdi + 72], rsi
    ret

_start:
    lea  rdi, [p]
    lea  rsi, [codecs]
    lea  rdx, [file]
    mov  ecx, file_end - file
    xor  r8d, r8d
    xor  r9d, r9d
    call peep_open
    test eax, eax
    jz   .bad
.l: lea  rdi, [p]
    lea  rsi, [out]
    mov  edx, 1024
    call peep_fill
    test rax, rax
    jz   .seek
    mov  rdx, rax
    shl  rdx, 2
    mov  edi, 1
    lea  rsi, [out]
    mov  eax, 1
    syscall
    jmp  .l
.seek:
    lea  rdi, [p]
    mov  esi, 500
    call peep_seek
    lea  rdi, [p]
    lea  rsi, [out]
    mov  edx, 100
    call peep_fill
    mov  rdx, rax
    shl  rdx, 2
    mov  edi, 1
    lea  rsi, [out]
    mov  eax, 1
    syscall
    lea  rdi, [p]
    call peep_close
    xor  edi, edi
    mov  eax, 60
    syscall
.bad:
    mov  edi, 1
    mov  eax, 60
    syscall
section .note.GNU-stack noalloc noexec nowrite progbits
```

The same, ARM64 Linux:

```asm
// A minimal codec in assembly: "RAW8" + unsigned 8-bit mono samples at 8000 Hz. AAPCS64 (x0 x1 x2).
    .global _start
    .extern peep_open, peep_fill, peep_seek, peep_close
    .section .rodata
    .balign 8
file:   .incbin "t.raw8"
file_end:
    .balign 8
filelen: .quad file_end - file
    .section .data.rel.ro,"aw"
    .balign 8
raw8:   .quad raw8_open, raw8_read, raw8_seek, 0, 0     // open, read, seek, close (none), read32 (none)
codecs: .quad raw8, 0                                   // NULL-terminated list
    .bss
    .balign 16
p:      .skip 160
out:    .skip 4096
    .text
// int open(peep *p, const void *data, size_t len): nonzero = this data is mine
raw8_open:
    cmp  x2, #4
    b.lo 1f
    ldr  w3, [x1]
    movz w4, #0x4152
    movk w4, #0x3857, lsl #16     // 'RAW8'
    cmp  w3, w4
    b.ne 1f
    mov  w3, #8000
    str  w3, [x0, #40]            // rate
    mov  w3, #1
    str  w3, [x0, #44]            // channels
    sub  x3, x2, #4
    str  x3, [x0, #32]            // total frames
    mov  w3, #8
    strh w3, [x0, #158]           // bits
    str  xzr, [x0, #72]           // my cursor, in the state area
    mov  w0, #1
    ret
1:  mov  w0, #0
    ret
// size_t read(peep *p, int16_t *out, size_t frames): the file's own channel count (the core makes it stereo)
raw8_read:
    ldr  x3, [x0, #32]
    ldr  x4, [x0, #72]
    sub  x3, x3, x4               // frames left
    cmp  x2, x3
    csel x2, x2, x3, lo
    ldr  x5, [x0, #8]             // p->src
    add  x5, x5, #4
    add  x5, x5, x4
    mov  x6, x2
    cbz  x6, 2f
1:  ldrb w7, [x5], #1
    sub  w7, w7, #128
    lsl  w7, w7, #8
    strh w7, [x1], #2
    subs x6, x6, #1
    b.ne 1b
2:  add  x4, x4, x2
    str  x4, [x0, #72]
    mov  x0, x2
    ret
// void seek(peep *p, uint64_t frame)
raw8_seek:
    ldr  x2, [x0, #32]
    cmp  x1, x2
    csel x1, x1, x2, lo
    str  x1, [x0, #72]
    ret

.macro LEA reg, sym
    adrp \reg, \sym
    add  \reg, \reg, :lo12:\sym
.endm
_start:
    LEA  x0, p
    LEA  x1, codecs
    LEA  x2, file
    LEA  x3, filelen
    ldr  x3, [x3]
    mov  x4, #0
    mov  x5, #0
    bl   peep_open
    cbz  w0, bad
1:  LEA  x0, p
    LEA  x1, out
    mov  x2, #1024
    bl   peep_fill
    cbz  x0, 2f
    lsl  x2, x0, #2
    mov  x0, #1
    LEA  x1, out
    mov  x8, #64
    svc  #0
    b    1b
2:  LEA  x0, p
    mov  x1, #500
    bl   peep_seek
    LEA  x0, p
    LEA  x1, out
    mov  x2, #100
    bl   peep_fill
    lsl  x2, x0, #2
    mov  x0, #1
    LEA  x1, out
    mov  x8, #64
    svc  #0
    LEA  x0, p
    bl   peep_close
    mov  x0, #0
    mov  x8, #93
    svc  #0
bad:
    mov  x0, #1
    mov  x8, #93
    svc  #0
```

### 10. What was verified, and what was not

* All six programs above were extracted from this file, assembled with `nasm` / `as`, linked with `ld` only (static executables: no `cc`, no libc) and run. The two API programs
  produced exactly the bytes a C program calling the same functions produces (5,154 bytes); the codec programs produced the expected samples; the smallest host matched the C test tool.
  x86-64 natively, ARM64 under QEMU.
* A harness that fills every callee-saved register with a marker before each call and checks it afterwards (x86-64 `rbx rbp r12 to r15`; ARM64 `x19` to `x29`, `d8` to `d15`) passed for
  `peep_flac`, `peep_wavx`, `peep_open` (both calls), `peep_seek`, `peep_fill32`, `peep_fill`, `peep_flac_metadata` and `peep_close` on both CPUs.
* Checked on both CPUs over the whole test corpus: a request for 0 frames returns 0 (`peep_fill` and `peep_fill32`); after the end every call returns 0 until a seek; `peep_seek(p, 0)` plays again;
  after `peep_close` fills return 0 and `kind` is 0.
* Stack depth was measured by painting the stack and finding the deepest write (about 4.2 KB and 4.1 KB, over FLAC and WAV files including 8 channels, with gain and dither). Input shifted by 1 byte and
  workspace by 3 gave identical results in 135 runs on each CPU.
* **Not tested:** an assembly host on Windows x64 (the conventions in section 7 follow the ABI and `abi.inc`), on macOS, or on real ARM hardware; output buffers that are not 16-byte aligned;
  a host linked as a shared library or position-independent executable (the examples address everything relative to the program counter, and `peep_flac()` / `peep_wavx()` exist for that case).

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
* `make test-wavc` (part of `make test`, and `testwavc.py --quick` in `make test-arm64`) tests the compressed-WAV codec against models checked with ffmpeg and libsndfile; keep both ports passing. IMA ADPCM follows the reference
  algorithm (libsndfile), not ffmpeg's rounding: see the README. A parser change must keep the fuzzer clean on the `c?.wav` seeds (it found an unchecked read of a `fact` chunk past the end of the file).
* `make test-simd` (part of `make test`) proves the SIMD/fallback dispatch: bit-exact decoding in a forced-scalar build and on an emulated CPU with no SSE4.1 (needs `qemu-x86_64`). Any change to the `cpuid` check must keep it passing.
* **This is the `dev` branch:** the library here is identical to the `arm64` branch except `flac.asm` and `arm64/flac.s`, which carry speed experiments (fused fixed-predictor and LPC decoding, and a vector LPC loop: SSE4.1 chosen by `cpuid` on x86-64, NEON on ARM64) (check with `git diff origin/arm64 -- peep.asm flac.asm wav.asm abi.inc peep.h arm64`; only `flac.asm` and `arm64/flac.s` should differ). `arm64` is the unchanged baseline to compare speed against. Both ports carry both changes (NEON is always present on AArch64, so the ARM64 version needs no detection and has no scalar fallback loop). The ARM64 speed effect has not been measured (QEMU timings mean nothing). `main` stays assembly and documentation only, at the old 0.1.2 library. A library change made here must also go to `arm64`, and keep the tests on `dev`/`arm64`, never on `main`.
* Beyond `make test` and `make test-arm64`, run `make test-audio` (stutter, click and garble tests; part of `make test`). `make clean` deletes `build/`, which also holds the tracked `build/libpeep-test-x86_64.AppImage`: restore it with `git checkout -- build/libpeep-test-x86_64.AppImage` afterwards.
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
* The built-in WAV is 16-bit PCM only. `peep_codec_wavx` (wav.asm / arm64/wav.s) adds unsigned 8-bit, 12/20/24/32-bit PCM and 32/64-bit float;
  `peep_codec_wavc` (wavc.asm / arm64/wavc.s) adds A-law, mu-law, IMA ADPCM and Microsoft ADPCM (ADPCM mono or stereo only). GSM 6.10, MP3-in-WAV and other compressed WAV types are not handled. IMA ADPCM made by ffmpeg
  decodes a few units away from ffmpeg's own output because ffmpeg rounds differently from the reference algorithm. The ARM64 versions have only been run under QEMU.

## Archive: the earlier AGENTS.md (0.1.2, x86-64 only), historical

**Historical, kept for reference; superseded by everything above.** It describes the library as it was at 0.1.2 on `main` and `dev` before the 0.5.0 library arrived: x86-64 only, no ARM64, FLAC up to 24 bits, WAV 16-bit only, no `peep_fill32`, no dither, no error counter, no `peep_codec_wavx`, a four-pointer codec interface, a rate limit of 768,000 Hz, three places holding the struct layout, and no way for a caller to be told about damaged frames. Where it contradicts the text above (for example "do not use it on ARM"), the text above is correct. Its headings are demoted and nothing else is changed.

For AI coding agents. Liberated Peep ("Audio for All", version 0.1.2, built from Peep
0.2.11) is a tiny audio-decoding library: you give it the bytes of a WAV or FLAC file and it
hands back stereo 16-bit samples, on demand. It plays nothing by itself; your program sends
the samples to a sound device.

#### Use it when / do not use it when

| Use it when | Do not use it when |
|---|---|
| the target is x86-64 (Linux, BSD, Windows) | the target is ARM (Apple Silicon Macs, phones, Raspberry Pi) or any non-x86-64 CPU: there is no port yet |
| you need WAV or FLAC and want no dependencies | you need MP3, Ogg Vorbis, AAC or Opus (not included; see "Other formats") |
| the audio thread must not allocate, lock or call the OS | you need FLAC above 24 bits per sample |
| you want a very small binary, or are embedding in an unusual runtime | you need resampling, mixing, EQ or effects (this is a decoder only) |

#### Add it to a project

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

#### The whole API

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

#### Why the new decoders exist

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

#### Other formats (MP3, Vorbis, ...)

Not included in this release, and there is no adapter for them in this repository. Peep's own repository
vendors `dr_mp3` and `stb_vorbis`. To use them here, write a small adapter with the four-function
`peep_codec` interface below (about 20 lines in C around an existing decoder) and pass it in the `codecs`
list. A `dr_flac` adapter was the worked example; it was removed from this branch to keep it assembly only,
but it is on the `arm64` branch (`examples/codec_drflac.c`) and in commit `7c347e6`. Those C libraries
allocate memory, so open them off the audio thread. A native MP3 decoder is the likely next step.

#### Writing a codec

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

#### If you modify this repository

* The `peep` struct layout is written in **three places that must agree**: the C declarations in the
  "API reference" of `README.md`, the `P_*` constants at the top of `peep.asm`, and the `P_*` / `S_*`
  constants at the top of `flac.asm`. Change one, change all, then run the tests.
* **This is the `dev` branch: it has the test suite** (`main` is assembly only). Run `make test` (needs `python3`
  with `numpy`) after every change and, after touching `flac.asm`, `make fuzz`. Windows changes can be checked
  under Wine with `make build/peepdump.exe`. Keep the tests on `dev`; `main` must stay assembly only.
* A decoder is only correct if it matches ground truth. `tools/mkflac.py` is the oracle for FLAC: it
  knows the exact PCM it encoded. A good habit is to break the decoder on purpose and confirm the
  tests fail.
* The decoder registers are fixed by convention (documented at the top of `flac.asm`): `rbx` is the
  `peep`, `r12` to `r15` are the bit reader. Internal routines clobber only what their comments say.
* Measure speed on an idle machine (`make build/bench`, `build/bench file [dr|native]`, from the test tools) and say what you
  measured. Do not claim a speed-up from instruction counts alone: the prediction loop here was
  limited by memory latency, not instruction count.

#### Things to tell the user honestly

* It is x86-64 only. It has not been run on ARM, so it does not work on Apple Silicon Macs, phones or
  Raspberry Pi. macOS on Intel is untested and would need `-f macho64` and underscore-prefixed symbols.
* The Windows build has been tested under Wine, not on real Windows.
* A damaged FLAC frame (its CRC-16 fails) is output as silence of the same length and decoding carries on;
  there is no way yet for the caller to be told that it happened.
* FLAC above 24 bits, MP3 and Vorbis are not handled natively.
* WAV is 16-bit PCM only (8-bit, 24-bit and float WAV need a codec).
