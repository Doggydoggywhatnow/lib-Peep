# Liberated Peep for Java

**Audio for All** · lib-Peep 0.4.0 · built from Peep 0.2.11

Liberated Peep is a tiny audio decoder for WAV and FLAC, hand-written in assembly (x86-64 and ARM64), with no
dependencies. This download is Liberated Peep with a **Java** binding. It contains one language binding only
(Java): no C header, and nothing for any other language.

Binding mechanism: java.lang.foreign (Foreign Function & Memory API).

## Status

**Verified.** OpenJDK 21, Linux x86-64. The demo was built/run in this environment and its output matched the reference exactly (see "Expected output"). The shared library itself is also verified on ARM64 (under QEMU); this binding has not been run on ARM64, macOS or Windows.

## What is in this download

| File | What |
|---|---|
| `Peep.java` | the binding: class `Peep` |
| `Demo.java` | demo: decodes the test files and prints checksums |
| `run.sh` | compiles and runs the demo (picks the right flags for your JDK) |
| `build.sh` | builds the shared library from `lib/` |
| `lib/` | the assembly library (x86-64 `*.asm` for nasm, ARM64 `arm64/*.s` for GNU as) |
| `test.wav`, `test.flac` | 0.1 s of stereo audio, for the demo |
| `LICENSE` | Unlicense (public domain) |

## Use it

```sh
./build.sh            # makes libpeep.so (Linux) or peep.dll (Windows)
```

```sh
sh run.sh
```

Needs: JDK 21 (uses the preview FFM API) or JDK 22 and newer and nasm and ld (Linux x86-64) or as and ld (Linux ARM64).

Expected output:

```
test.wav rate=44100 channels=2 frames=4410 sum=263816 seek_sum=-69992
test.flac rate=44100 channels=2 frames=4410 sum=263816 seek_sum=-69992
```

## The Java API

```java
// javac --release 21 --enable-preview ... (JDK 22+: plain javac)
byte[] file = Files.readAllBytes(Path.of("song.flac"));
try (Peep peep = new Peep(file)) {                // WAV or FLAC, from memory
    System.out.println(peep.rate() + " " + peep.channels() + " " + peep.total());
    for (;;) {
        short[] samples = peep.read(1024);        // interleaved stereo
        if (samples.length == 0) break;
        play(samples);                            // your audio output
    }
    peep.seek(44100);                             // jump to frame 44100
    peep.setGain(128);                            // half volume
}
```

Every Liberated Peep binding offers the same few things: open a WAV or FLAC file from memory, read its
`rate`, `channels` and `total` frames, `read` stereo 16-bit samples, `seek`, set the volume (`0..256`, 256 =
full), and `close`. Output is always interleaved stereo 16-bit at the file's own sample rate; mono is
duplicated and 3+ channels use the first two.

## Notes

* Uses the standard Foreign Function & Memory API, so there is no JNI and no extra library. On JDK 21 it is a preview feature, so `run.sh` compiles with `--enable-preview`; on JDK 22+ it is final and `run.sh` compiles normally.
* `read` returns at most 4096 frames per call.

## Platforms

* Linux x86-64 and Linux ARM64: the library builds with `./build.sh` (verified; ARM64 under QEMU only).
* Windows x64: `./build.sh` in MSYS2/MinGW builds `peep.dll` (the DLL loads and decodes under Wine; this binding was
  not run on Windows).
* macOS: not supported yet. Android, iOS, 32-bit ARM, RISC-V and others: not supported.

## Limits

x86-64 and ARM64 only. FLAC 4 to 31 bits per sample (32-bit is not supported). 16-bit PCM WAV only. No MP3 or Vorbis. A FLAC frame that fails
its CRC-16 is output as silence. Full details: https://github.com/Doggydoggywhatnow/lib-Peep

## License

Public domain, under the Unlicense (`LICENSE`).
