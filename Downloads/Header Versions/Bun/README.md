# Liberated Peep for Bun

**Audio for All** · lib-Peep 0.3.1 · built from Peep 0.2.11

Liberated Peep is a tiny audio decoder for WAV and FLAC, hand-written in assembly (x86-64 and ARM64), with no
dependencies. This download is Liberated Peep with a **Bun** binding. It contains one language binding only
(Bun): no C header, and nothing for any other language.

Binding mechanism: Bun's built-in `bun:ffi`.

## Status

**Verified.** Bun 1.4, Linux x86-64. The demo was built/run in this environment and its output matched the reference exactly (see "Expected output"). The shared library itself is also verified on ARM64 (under QEMU); this binding has not been run on ARM64, macOS or Windows.

## What is in this download

| File | What |
|---|---|
| `peep.js` | the binding: `Peep` class (ES module) |
| `demo.js` | decodes the test files and prints checksums |
| `build.sh` | builds the shared library from `lib/` |
| `lib/` | the assembly library (x86-64 `*.asm` for nasm, ARM64 `arm64/*.s` for GNU as) |
| `test.wav`, `test.flac` | 0.1 s of stereo audio, for the demo |
| `LICENSE` | Unlicense (public domain) |

## Use it

```sh
./build.sh            # makes libpeep.so (Linux) or peep.dll (Windows)
```

```sh
bun demo.js
```

Needs: Bun 1.0 or newer and nasm and ld (Linux x86-64) or as and ld (Linux ARM64).

Expected output:

```
test.wav rate=44100 channels=2 frames=4410 sum=263816 seek_sum=-69992
test.flac rate=44100 channels=2 frames=4410 sum=263816 seek_sum=-69992
```

## The Bun API

```js
import { Peep } from "./peep.js";

const peep = new Peep(await Bun.file("song.flac").bytes());   // WAV or FLAC, from memory
console.log(peep.rate, peep.channels, peep.total);
for (;;) {
  const samples = peep.read(1024);        // Int16Array of interleaved stereo samples
  if (samples.length === 0) break;
  play(samples);                          // your audio output
}
peep.seek(44100);                         // jump to frame 44100
peep.setGain(128);                        // half volume
peep.close();
```

Every Liberated Peep binding offers the same few things: open a WAV or FLAC file from memory, read its
`rate`, `channels` and `total` frames, `read` stereo 16-bit samples, `seek`, set the volume (`0..256`, 256 =
full), and `close`. Output is always interleaved stereo 16-bit at the file's own sample rate; mono is
duplicated and 3+ channels use the first two.

## Notes

* No npm packages needed: `bun:ffi` is built into Bun.
* `read` returns at most 4096 frames per call.

## Platforms

* Linux x86-64 and Linux ARM64: the library builds with `./build.sh` (verified; ARM64 under QEMU only).
* Windows x64: `./build.sh` in MSYS2/MinGW builds `peep.dll` (the DLL loads and decodes under Wine; this binding was
  not run on Windows).
* macOS: not supported yet. Android, iOS, 32-bit ARM, RISC-V and others: not supported.

## Limits

x86-64 and ARM64 only. FLAC up to 24 bits per sample. 16-bit PCM WAV only. No MP3 or Vorbis. A FLAC frame that fails its
CRC-16 is output as silence. Full details: https://github.com/Doggydoggywhatnow/lib-Peep

## License

Public domain, under the Unlicense (`LICENSE`).
