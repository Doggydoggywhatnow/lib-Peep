# Changelog

All notable changes to Liberated Peep.

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
