# Liberated Peep for Rust

**Audio for All** · lib-Peep 0.4.0 · built from Peep 0.2.11

Liberated Peep is a tiny audio decoder for WAV and FLAC, hand-written in assembly (x86-64 and ARM64), with no
dependencies. This download is Liberated Peep with a **Rust** binding. It contains one language binding only
(Rust): no C header, and nothing for any other language.

Binding mechanism: plain `extern "C"` blocks (standard library only, no crates).

## Status

**Verified.** Rust 1.97, Linux x86-64. The demo was built/run in this environment and its output matched the reference exactly (see "Expected output"). The shared library itself is also verified on ARM64 (under QEMU); this binding has not been run on ARM64, macOS or Windows.

## What is in this download

| File | What |
|---|---|
| `Cargo.toml` | Cargo manifest (no dependencies) |
| `build.rs` | links against the shared library in this folder |
| `src/peep.rs` | the binding: module `peep` |
| `src/main.rs` | demo: decodes the test files and prints checksums |
| `build.sh` | builds the shared library from `lib/` |
| `lib/` | the assembly library (x86-64 `*.asm` for nasm, ARM64 `arm64/*.s` for GNU as) |
| `test.wav`, `test.flac` | 0.1 s of stereo audio, for the demo |
| `LICENSE` | Unlicense (public domain) |

## Use it

```sh
./build.sh            # makes libpeep.so (Linux) or peep.dll (Windows)
```

```sh
cargo run --release -q
```

Needs: Rust 1.60 or newer with cargo and nasm and ld (Linux x86-64) or as and ld (Linux ARM64).

Expected output:

```
test.wav rate=44100 channels=2 frames=4410 sum=263816 seek_sum=-69992
test.flac rate=44100 channels=2 frames=4410 sum=263816 seek_sum=-69992
```

## The Rust API

```rust
mod peep;
use peep::Peep;

let data = std::fs::read("song.flac")?;       // WAV or FLAC, from memory
let mut p = Peep::new(&data)?;
println!("{} {} {}", p.rate(), p.channels(), p.total());
loop {
    let samples = p.read(1024);               // &[i16], interleaved stereo
    if samples.is_empty() { break; }
    play(samples);                            // your audio output
}
p.seek(44_100);                               // jump to frame 44100
p.set_gain(128);                              // half volume
p.close();
```

Every Liberated Peep binding offers the same few things: open a WAV or FLAC file from memory, read its
`rate`, `channels` and `total` frames, `read` stereo 16-bit samples, `seek`, set the volume (`0..256`, 256 =
full), and `close`. Output is always interleaved stereo 16-bit at the file's own sample rate; mono is
duplicated and 3+ channels use the first two.

## Notes

* No crates are needed. `build.rs` links against `libpeep.so` in this folder and sets an rpath to it.
* On Windows you also need an import library (`peep.lib`) for `peep.dll`; this binding was only run on Linux.
* `read` returns a slice of at most 4096 frames and is valid until the next call.

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
