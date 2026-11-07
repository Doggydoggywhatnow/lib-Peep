# Changelog

All notable changes to Liberated Peep.

## 0.1.2

**Built from Peep 0.2.11.** FLAC frames are now integrity-checked.

### Fixed
- **The FLAC audio CRC-16 was not checked**, so a bit flipped inside audio data silently decoded to a wrong
  sample. Every frame's CRC-16 (FLAC's polynomial 0x8005, over the frame from its header to the last audio
  byte) is now verified. A frame that fails is output as silence of the right length, so timing and seek
  positions stay correct, and decoding resumes at the next valid frame header. (The decoder no longer
  trusts the damaged frame's own length to find the next frame.)

### Cost
- The check adds 4% to 12% to FLAC decode time (most on lightly compressed files) and about 4.4 KB of code,
  almost all of it the eight 512-byte lookup tables, which the assembler itself builds (no generator). It
  runs 8 bytes per step.

### Tests (they live on the `dev` branch)
- New `tools/testcrc.py` flips one bit inside the audio, or in the CRC, of a random frame of a generated
  stream. The only allowed results are that frame silenced or that frame dropped, with every other frame
  exact. About 3,000 corrupted streams: none produced a wrong sample. It caught a first version of the fix
  that trusted a damaged frame's length (2 of 400), and a copy of the decoder with the check disabled
  (106 of 150). Also re-run: the 2,505 WAV checks, 120 FLAC streams with seeks, 6 million more fuzz inputs,
  valgrind.

## 0.1.1

**Built from Peep 0.2.11.** The repository is now assembly (and documentation) only. The library is unchanged.

### Removed
- Everything that was not assembly: the C header `peep.h`, the `Makefile`, `examples/codec_drflac.c`, the
  vendored `third_party/dr_flac.h`, and the test tools in `tools/` (`mkflac.py`, `testwav.py`, `fuzz.c`,
  `peepdump.c`, `bench.c`).
- Nothing the library does depends on them: `peep.asm` and `flac.asm` assemble to byte-identical
  objects before and after, and the full test suite (run from the removed tools) still passes.

### Changed
- The C declarations that were in `peep.h` are now in the README's "API reference", as documentation to copy.
- The README and `AGENTS.md` give the `nasm` commands instead of `make`, and say where the removed test
  suite lives: git history (commit `7c347e6`) and the `arm64` branch.

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
