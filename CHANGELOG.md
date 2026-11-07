# Changelog

All notable changes to Liberated Peep.

## Unreleased (dev branch)

### Added (tests only, no library change)
- `make test-audio`: a stutter / click / garble suite (`tools/testaudio.c`, `tools/testaudio.py`; the tool gains `-R seed`,
  a random request size on every call). About 640,000 soak checks and 857 signal checks, in under 4 seconds. 10 deliberate
  breakages of the decoder (swapped channels, repeated samples, a wrong output stride, an off-by-one seek, wrong volume,
  a position that does not advance, and others) are all caught. It found two gaps in its own first version (no truncated-file
  case, no stereo volume case), now closed.

### Experiment (dev branch): fused fixed-predictor decoding, x86-64 only
- `flac.asm`: fixed predictors of order 1 to 4 are now applied inside `decode_residual`, as each sample is decoded, instead of in a second
  pass. The predictor's short dependency chain then runs alongside the bit reader's chain. Escape-coded partitions run the old fixed loop over
  just their region. LPC subframes are unchanged. No API, struct, workspace or output change.
- Measured against the unchanged `arm64` branch (same machine, alternating runs, min and median of 6): **level 0 +17%, level 2 +11 to +12%**
  (the gap to `dr_flac` fell from -17% to about -4% and -9%); level 5, 8, 12, mono, 6-channel, 96 kHz and 24-bit within about +-2%
  (level 5 and 96 kHz about -2% at worst, which is within this VM's noise of about 5%).
- Found by profiling first: ablation (skip a stage and time it) showed stereo reconstruction and interleaving cost about nothing, CRC-16 2 to 10%,
  prediction 18 to 57%, and the rest residual decoding; a branch-free bit-cache refill, tried because a branch simulator blamed the refill check for
  92% of mispredicts, gained at most 3% and was dropped.
- Tests: `make test` (x86-64) passes, including 300 random streams with escape partitions, the audio suite and 200,000 fuzz inputs. 9 deliberate
  breakages of the new code (wrong formula terms, a missing history reload, an escape partition left unpredicted or with a wrong end pointer, and
  others) were all caught.
- Not done: the ARM64 port (`arm64/flac.s` is unchanged, so the two ports now differ on `dev`); the change is not on the `arm64` branch.
  The remaining gaps to `dr_flac` (96 kHz about -21%, 24-bit about -28%, levels 5 and 8 about -4% to -10%) are LPC and wide-residual cases and
  need their own look. Measured on a shared x86-64 cloud VM, not on an idle machine.

### Experiment (dev branch): SSE4.1 LPC prediction chosen by cpuid, x86-64 only
- `flac.asm`: the LPC prediction loop has a second version that multiplies four taps per pass with SSE4.1 `pmuldq` (two 2-lane signed 32x32 to 64-bit
  multiplies, summed in 64 bits, so the result is exact exactly like the scalar loop). `peep_open` asks `cpuid` once (leaf 1, ECX bit 19) and records the answer in
  bit 8 of the FLAC bit-depth field of the `peep` (no global state, no struct change); `peep_fill` uses the vector loop only when that bit is set and the order is
  above 4. A CPU without SSE4.1 keeps the scalar loop. `nasm -dNOSIMD` builds without the vector loop at all. The newest four taps stay scalar (reading a vector that
  overlaps just-stored samples would stall store forwarding).
- Measured against the unchanged `arm64` branch (min of 6, alternating, shared x86-64 VM): level 12 **+26%**, level 8 **+11 to +13%**, mono +3%; level 0 and 2 keep the
  fixed-predictor gain (+18% and +11%); level 5, 5.1, 96 kHz and 24-bit are flat (within about 2%). The flat ones were encoded at the default level, whose LPC order (about 8) is
  a single group of taps, where four-at-a-time multiplies cannot beat the scalar loop; requiring two groups changed nothing.
- Tests: `make test` passes. New `make test-simd` (part of `make test`): bit-exact decoding in a `-dNOSIMD` build and on an emulated CPU without SSE4.1 (`qemu-x86_64 -cpu qemu64`),
  where executing the vector instruction would crash. Eight breakages of the new code were caught by the normal tests (wrong lane order, wrong coefficient pair, a lane not
  summed, a stale sum, a wrong step, a bit-depth read without its mask); three more that only matter on an older CPU (flag test inverted, wrong `cpuid` bit, `cpuid` ignored)
  passed the normal tests, which is why `make test-simd` exists: it now catches all three.
- Not done: ARM64 (NEON always present, so no detection needed); LPC fused with residual decoding; faster order-8 prediction, which is where the default-level files
  (24-bit, 96 kHz, level 5) still spend their time. Measured on a shared VM, not an idle machine.

### Changed (dev branch)
- The library files on `dev` (`peep.asm`, `flac.asm`, `wav.asm`, `abi.inc`, `peep.h`, `arm64/`) were replaced by the 0.5.0 versions from the `arm64` branch, with the tools and Makefile that depend on them; the documentation was merged, keeping the old text in an archive section at the end of each file. The old x86-64-only changelog (0.1.0 to 0.1.2) is at the end of this file.

## 0.5.0

**Built from Peep 0.2.11.** WAV at every common bit depth, on x86-64 and ARM64.

### Added
- **`peep_codec_wavx`** (`wav.asm`, `arm64/wav.s`, about 1.1 KB and 1.3 KB), a WAV extension codec in pure assembly:
  unsigned 8-bit; signed 12, 16, 20, 24 and 32-bit PCM; 32-bit and 64-bit IEEE float; plain and
  `WAVE_FORMAT_EXTENSIBLE`; 1 to 8 channels; odd chunks, unknown-length data, truncated files. It needs no workspace.
  It provides `read32` and sets `p->bits` (float: 32), so `peep_fill32`, volume and the rounding/dither modes work as for FLAC.
  Float is scaled by 2^31, rounded to nearest even and clipped (NaN is 0). `peep_wavx()` returns its table's address.
- The built-in 16-bit WAV decoder is unchanged: its size, speed and rejections are the same. The extension is a separate
  codec on purpose, so a program that only needs 16-bit WAV does not carry it.

### Changed
- `testwav.py` no longer expects 8-bit and float WAV to be rejected (with the extension in the codec list they are accepted;
  the plain built-in still rejects them). The `peepdump` test tool and the fuzzer now list `peep_codec_wavx`.

### Tests
- New `tools/testwavx.py` (in `make test` and `make test-arm64`): an independent Python model of every format, extensible
  headers, odd and junk chunks, unknown length, truncation, seeking, volume, the three 16-bit modes, `peep_fill32` and 12
  kinds of file that must be rejected. Float cases include NaN, infinities, denormals, 1.0, out-of-range values and exact
  rounding ties.
- The fuzzer now mutates five WAV seeds as well.

### Not done
- The 22 language packages build the new codec into their library but their bindings do not yet pass it in the codec list.
- A-law, mu-law, ADPCM and WAV with more than 8 channels are not supported.
- ARM64 speed and real hardware are still unmeasured; the new codec was run under QEMU only.

## 0.4.0

**Built from Peep 0.2.11.** Full-resolution FLAC output and a sturdier decoder, on x86-64 and ARM64.

### Added
- **`peep_fill32`**: stereo `int32` output, each sample left-justified (`value << (32 - bits)`), volume at 64-bit
  precision, nothing rounded. Works for WAV, FLAC (through the new optional `read32` codec pointer) and legacy
  codecs (their 16-bit output is widened).
- **Cleaner 16-bit output.** For sources wider than 16 bits `peep_fill` applies the volume at full precision and
  reduces to 16 bits once. `peep_set_dither(p, mode)`: 0 truncate (default; unchanged behaviour), 1 round, 2 TPDF
  dither (deterministic xorshift32). 16-bit sources are untouched.
- **FLAC 25 to 31 bits per sample** (the limit was 24). 32-bit is still rejected.
- **ID3v2 tags** in front of a FLAC stream are skipped (including footers and stacked tags).
- **`p->errors`** counts damaged frames (CRC-16 failures and undecodable frames), so callers can be told. **`p->bits`**
  gives the source bit depth.
- **`peep_flac_metadata`**: zero-copy access to FLAC metadata blocks (STREAMINFO, SEEKTABLE, VORBIS_COMMENT, PICTURE, ...).
- Sample-rate cap raised from 768,000 to 1,048,575 Hz (STREAMINFO's own limit).
- ARM64 has all of the above, with the same arithmetic (the dither stream is bit-identical on both CPUs).

### Changed (API)
- `peep_codec` has a fifth, optional member `read32`, and `struct peep` uses the previously spare tail
  (`errors`, `dither`, `bits`; still 160 bytes). **Adapters compiled against the 0.3.x header must be rebuilt.**
  The language packages need no change.

### Cost
- Code size: x86-64 core 1.3 -> 2.5 KB, FLAC 8.6 -> 9.3 KB; ARM64 core 1.4 -> 2.5 KB, FLAC 9.0 -> 9.7 KB.

### Tests
- New `tools/testhires.py`: independent model checks of `peep_fill32`, gain, the three 16-bit modes (bit-exact against a
  Python model of the dither), metadata blocks, WAV at every channel count, and the legacy-codec path.
  `mkflac.py` now covers 25/27/31-bit, 1 MHz, ID3v2 prefixes (up to 2 MB) and trailers; `testcrc.py` also requires
  `p->errors` to be counted; `fuzz.c` exercises the new calls.
- x86-64: WAV 2,505, FLAC 120 streams, CRC 300, hires 1,167 checks, 200,000 fuzz inputs, all clean. ARM64 (QEMU): WAV 2,505,
  FLAC 120, CRC 150, hires 614, 100,000 fuzz inputs, all clean.
- 16 deliberate breakages of the new code on each CPU, all caught. One was first missed on both CPUs (an ID3 size
  shift that only matters above 2 MB); the generator now makes such tags and it is caught.

### Not verified / not done
- ARM64 still only under QEMU. The 22 language packages were regenerated but only the library inside them changed.
- 32-bit FLAC, MD5 verification, Ogg FLAC and seek-table seeking are not done.

## 0.3.1

**Built from Peep 0.2.11.** FLAC frames are now integrity-checked, on x86-64 and ARM64.

### Fixed
- **The FLAC audio CRC-16 was not checked**, so a bit flipped inside audio data silently decoded to a wrong
  sample. Every frame's CRC-16 (FLAC's polynomial 0x8005, over the frame from its header to the last audio
  byte) is now verified, in `flac.asm` and in `arm64/flac.s`. A frame that fails is output as silence of the
  right length, so timing and seek positions stay correct, and decoding resumes at the next valid frame header.
  (The decoder does not trust a damaged frame's own length to find the next frame.)
- The 22 language packages in `Downloads/Header Versions/` are regenerated with the fixed library.

### Cost
- x86-64: 4% to 12% slower FLAC decoding, FLAC code 4.2 KB -> 8.6 KB. ARM64: FLAC code 4.6 KB -> 9.0 KB; its speed
  has not been measured (the port has only been run under emulation). Almost all the growth is eight 512-byte
  lookup tables per CPU, which the assembler builds itself (no generator); the check runs 8 bytes per step.

### Tests
- New `tools/testcrc.py` (in `make test` and `make test-arm64`) flips one bit inside the audio, or in the CRC,
  of a random frame of a generated stream. The only allowed results are that frame silenced or that frame
  dropped, with every other frame exact. x86-64: about 3,000 corrupted streams, none wrong. ARM64 (QEMU): about
  750 more, none wrong. It caught a first version that trusted a damaged frame's length (2 of 400), a copy with
  the check disabled (106 of 150 on x86-64, 70 of 100 on ARM64), and sabotaged tables, tails and byte lanes on
  both CPUs.
- Re-run on both CPUs: 2,505 WAV checks, 120 FLAC streams with seeks, fuzzing (x86-64 6 million more inputs,
  ARM64 900,000 more) and valgrind. All 22 language demos, and the ARM64 and Windows shared libraries (QEMU, Wine).

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

## Archive: the main/dev changelog, 0.1.0 to 0.1.2 (x86-64 only)

Kept for reference. These entries are the changelog of the `main` and `dev` branches before the 0.5.0 library was brought to `dev`. The version numbers overlap with the `arm64` line above (that line reached 0.3.1 for the same CRC-16 fix that `main` calls 0.1.2). Unchanged apart from heading levels.

#### 0.1.2

**Built from Peep 0.2.11.** FLAC frames are now integrity-checked.

##### Fixed
- **The FLAC audio CRC-16 was not checked**, so a bit flipped inside audio data silently decoded to a wrong
  sample. Every frame's CRC-16 (FLAC's polynomial 0x8005, over the frame from its header to the last audio
  byte) is now verified. A frame that fails is output as silence of the right length, so timing and seek
  positions stay correct, and decoding resumes at the next valid frame header. (The decoder no longer
  trusts the damaged frame's own length to find the next frame.)

##### Cost
- The check adds 4% to 12% to FLAC decode time (most on lightly compressed files) and about 4.4 KB of code,
  almost all of it the eight 512-byte lookup tables, which the assembler itself builds (no generator). It
  runs 8 bytes per step.

##### Tests
- New `tools/testcrc.py` (part of `make test`): flips one bit inside the audio, or in the CRC, of a random frame
  of a generated stream. The only allowed results are that frame silenced or that frame dropped, with every other
  frame exact. About 3,000 corrupted streams: none produced a wrong sample. It caught a first version of the fix
  that trusted a damaged frame's length (2 of 400), and a copy of the decoder with the check disabled (106 of 150).
- Also re-run: the 2,505 WAV checks, 120 FLAC streams with seeks, 6 million more fuzz inputs, valgrind.

#### 0.1.1 (dev branch)

The `dev` branch is `main` at 0.1.1 plus the test suite (`tools/`, `Makefile`, `peep.h`, `examples/`,
`third_party/`) restored from commit `7c347e6`. The assembly is identical to `main`.

#### 0.1.1

**Built from Peep 0.2.11.** The repository is now assembly (and documentation) only. The library is unchanged.

##### Removed
- Everything that was not assembly: the C header `peep.h`, the `Makefile`, `examples/codec_drflac.c`, the
  vendored `third_party/dr_flac.h`, and the test tools in `tools/` (`mkflac.py`, `testwav.py`, `fuzz.c`,
  `peepdump.c`, `bench.c`).
- Nothing the library does depends on them: `peep.asm` and `flac.asm` assemble to byte-identical
  objects before and after, and the full test suite (run from the removed tools) still passes.

##### Changed
- The C declarations that were in `peep.h` are now in the README's "API reference", as documentation to copy.
- The README and `AGENTS.md` give the `nasm` commands instead of `make`, and say where the removed test
  suite lives: git history (commit `7c347e6`) and the `arm64` branch.

#### 0.1.0

First release. **Built from Peep 0.2.11.**

Liberated Peep takes the playback kernel out of Peep, the music player that is just a
screen, and makes it a library any program can use. Everything about the window, the
sound device, the playlist and the cover art stays in Peep; what is left is the part that
turns an audio file into samples.

##### Added
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

##### Carried over from Peep
- The WAV parser, the volume mix and the volume table are Peep's own, unchanged. They are
  byte-identical in Peep 0.2.6 and 0.2.11, so the development tests that were first run
  against 0.2.6 apply to the 0.2.11 sources this release is built from.

##### Not in this release
- MP3 and Ogg Vorbis (Peep plays them through C decoders; there is no native or packaged
  version here yet).
- FLAC audio CRC-16 checking: a bit flip inside audio data gives a wrong sample, not an
  error.
- FLAC above 24 bits per sample.
- Any CPU other than x86-64.

##### Measured against dr_flac (the C decoder Peep used)
Between 16% slower and 16% faster depending on the file, with 4.2 KB of code against about
90 KB. See the README for the table.
