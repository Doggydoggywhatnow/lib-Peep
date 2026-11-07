# Changelog

All notable changes to Liberated Peep.

## 0.3.0

**Built from Peep 0.2.11.** Liberated Peep now comes ready-made for 22 programming languages.

### Added
- **`Downloads/Header Versions/`: 22 self-contained packages, one per language**: Bun, C#, C++, Common
  Lisp (SBCL), D, F#, Fortran, Free Pascal, Go, GNU Guile, Java, LuaJIT, Nim, Node.js, Perl, PHP, Python,
  Racket, Raku, Ruby, Rust and Visual Basic .NET. Each package (a folder and a zip) holds the assembly
  library, a `build.sh`, **one** language binding, a demo, two tiny test files and a README. It never holds
  a C header or another language's binding, so each download has one sort of header.
- `build.sh` in every package builds a shared library: `libpeep.so` on Linux x86-64 and Linux ARM64,
  `peep.dll` on Windows (MSYS2/MinGW).
- `peep_flac()`, a new exported function that returns the FLAC codec table's address. Languages whose FFI
  can call functions but cannot read a data symbol (Bun, COBOL and others) need it; every binding uses it.
  It is position independent, so it works in a shared library, on x86-64 and ARM64. `peep_codec_flac` still
  works as before.
- `tools/make_header_versions.py` (builds the packages from `bindings/`) and
  `tools/test_header_versions.py` (builds each package in a scratch folder and checks its demo's output).

### Verified
- All 22 demos were built and run on Linux x86-64 and printed exactly the expected output (decode a WAV and
  a FLAC, then seek and read again), checked against the C reference.
- The shared library: x86-64 loaded from Python; ARM64 built as a shared library and run under QEMU with a
  dynamically linked test; the Windows DLL built with MinGW, exports all five functions, and decodes a WAV
  and a FLAC correctly under Wine.
- The whole test suites were re-run after the assembly change: `make test` (x86-64) and
  `make test-arm64` (ARM64, under QEMU) both pass.

### Not verified
- No binding has been run on ARM64, Windows or macOS; only Linux x86-64. macOS has no shared-library
  build yet.
- Free Pascal needs libc linked explicitly (`{$linklib c}`, already in its `Peep.pas`), otherwise a program
  that loads a shared library crashes in the dynamic loader when it exits.
- Not written: Swift, Kotlin, Scala, Clojure, Zig, Julia, Haskell, Ada, OCaml, COBOL, Dart, Deno, Crystal,
  Odin, V, PowerShell, AutoHotkey and others. No untested bindings were shipped; every package here ran.

## 0.2.0

**Built from Peep 0.2.11.** Liberated Peep now runs on 64-bit ARM as well as x86-64.

### Added
- An ARM64 (AArch64) port, in pure assembly, with the same API, behaviour and features as the
  x86-64 version: `arm64/peep.s` (1.4 KB, core and built-in WAV), `arm64/flac.s` (4.6 KB, the
  FLAC decoder) and `arm64/abi_a64.inc`. No C is involved; building the library needs only the
  GNU assembler and a linker. NEON does the volume scaling, the stereo reconstruction and the
  output interleaving.
- `make arm64 CROSS=aarch64-linux-gnu-` to cross-build from an x86-64 machine; on an ARM64
  machine a plain `make` builds the ARM64 library.
- `make test-arm64`: the same test suites as `make test`, run on the ARM64 build (under QEMU on
  an x86-64 machine).
- A macOS mode in the ARM64 sources (`as --defsym APPLE=1`: underscore-prefixed symbol names and
  Mach-O sections). It has never been assembled or run.

### Verified (ARM64, under QEMU emulation on Linux)
- The 2,505 WAV checks and 480+ random FLAC streams with 1,100+ seeks pass with no failures.
- Output is identical to the x86-64 decoder and to `dr_flac` on every real ffmpeg-encoded file
  tried (levels 0 to 12, mono, 5.1, 96 kHz, 24-bit), including volume scaling.
- 1.2 million fuzz inputs (2.4 billion frames), with the input and workspace against unmapped guard
  pages: no crash, hang or out-of-bounds access.
- 17 deliberate breakages of the ARM64 decoder, all caught by the tests.

### Not verified
- Real ARM hardware: the port has only been run under emulation, and **its speed has not been
  measured**.
- Apple Silicon Macs, iPhones and Windows on ARM.
- 32-bit ARM is not supported.

### Unchanged
- The x86-64 code is unchanged apart from the version in a comment. The API, the struct layout and
  every limit listed under 0.1.0 still apply.

## 0.1.0

First release. **Built from Peep 0.2.11.**

Liberated Peep takes the playback kernel out of Peep, the music player that is just a
screen, and makes it a library any program can use. Everything about the window, the
sound device, the playlist and the cover art stays in Peep; what is left is the part that
turns an audio file into samples.

### Added
- The core, `peep.asm` (1.3 KB): `peep_open`, `peep_fill`, `peep_seek`, `peep_close`. It is
  pull-based (your audio callback asks for samples), freestanding (no libc, no `malloc`,
  no threads, no system calls, no writable globals) and takes all its memory from the
  caller.
- A built-in WAV decoder for 16-bit PCM: plain, `WAVE_FORMAT_EXTENSIBLE`, odd-sized chunks
  with their pad byte, unknown-length ("streaming") data and truncated files. It reads
  straight from the caller's memory, and volume is applied in the same pass.
- A native FLAC decoder written in assembly, `flac.asm` (4.2 KB): 4 to 24 bits per sample,
  1 to 8 channels, fixed and variable block sizes, constant / verbatim / fixed / LPC
  subframes, both Rice methods, escape partitions, wasted bits, left/side, side/right and
  mid/side stereo, header CRC-8 checking, resynchronisation over damaged frames, and
  seeking by binary search over frame headers (no seek table needed).
- A codec interface (`peep_codec`: `open`, `read`, `seek`, `close`) so a format can be
  added without touching the core, and a workspace protocol so a codec can ask the host for
  memory (`p->work`, `p->work_need`) instead of allocating it.
- `examples/codec_drflac.c`, a 20-line adapter showing how to plug in an existing C decoder.
- Windows x64 as well as System V, from the same source (`abi.inc`). The Windows build is
  tested under Wine.
- Tests (`make test`): a randomised FLAC encoder that uses every feature of the format and
  checks the decoder against the exact PCM it wrote; 2,505 WAV checks; and a mutation
  fuzzer that puts the input and the workspace against unmapped guard pages.
- Released under the Unlicense (public domain), like Peep.

### Carried over from Peep
- The WAV parser, the volume mix and the volume table are Peep's own, unchanged. They are
  byte-identical in Peep 0.2.6 and 0.2.11, so the development tests that were first run
  against 0.2.6 apply to the 0.2.11 sources this release is built from.

### Not in this release
- MP3 and Ogg Vorbis (Peep plays them through C decoders; there is no native or packaged
  version here yet).
- FLAC audio CRC-16 checking: a bit flip inside audio data gives a wrong sample, not an
  error.
- FLAC above 24 bits per sample.
- Any CPU other than x86-64.

### Measured against dr_flac (the C decoder Peep used)
Between 16% slower and 16% faster depending on the file, with 4.2 KB of code against about
90 KB. See the README for the table.
