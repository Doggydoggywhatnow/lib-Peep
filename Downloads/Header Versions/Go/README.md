# Liberated Peep for Go

**Audio for All** · lib-Peep 0.5.0 · built from Peep 0.2.11

Liberated Peep is a tiny audio decoder for WAV and FLAC, hand-written in assembly (x86-64 and ARM64), with no
dependencies. This download is Liberated Peep with a **Go** binding. It contains one language binding only
(Go): no C header, and nothing for any other language.

Binding mechanism: purego (github.com/ebitengine/purego): no cgo, no C compiler.

## Status

**Verified.** Go 1.24, Linux x86-64. The demo was built/run in this environment and its output matched the reference exactly (see "Expected output"). The shared library itself is also verified on ARM64 (under QEMU); this binding has not been run on ARM64, macOS or Windows.

## What is in this download

| File | What |
|---|---|
| `go.mod` | module file (depends on purego) |
| `peep/peep.go` | the binding: package `peep` |
| `main.go` | demo: decodes the test files and prints checksums |
| `build.sh` | builds the shared library from `lib/` |
| `lib/` | the assembly library (x86-64 `*.asm` for nasm, ARM64 `arm64/*.s` for GNU as) |
| `test.wav`, `test.flac` | 0.1 s of stereo audio, for the demo |
| `LICENSE` | Unlicense (public domain) |

## Use it

```sh
./build.sh            # makes libpeep.so (Linux) or peep.dll (Windows)
```

**Prepare** (once):

```sh
    go mod tidy
```

```sh
CGO_ENABLED=0 go run .
```

Needs: Go 1.21 or newer, network access once to fetch purego and nasm and ld (Linux x86-64) or as and ld (Linux ARM64).

Expected output:

```
test.wav rate=44100 channels=2 frames=4410 sum=263816 seek_sum=-69992
test.flac rate=44100 channels=2 frames=4410 sum=263816 seek_sum=-69992
```

## The Go API

```go
import "peepdemo/peep"

data, _ := os.ReadFile("song.flac")          // WAV or FLAC, from memory
p, err := peep.New(data)
fmt.Println(p.Rate(), p.Channels(), p.Total())
for {
	samples := p.Read(1024)                  // []int16, interleaved stereo
	if len(samples) == 0 {
		break
	}
	play(samples)                            // your audio output
}
p.Seek(44100)                                // jump to frame 44100
p.SetGain(128)                               // half volume
p.Close()
```

Every Liberated Peep binding offers the same few things: open a WAV or FLAC file from memory, read its
`rate`, `channels` and `total` frames, `read` stereo 16-bit samples, `seek`, set the volume (`0..256`, 256 =
full), and `close`. Output is always interleaved stereo 16-bit at the file's own sample rate; mono is
duplicated and 3+ channels use the first two.

## Notes

* Loads the library with purego, so no C compiler is needed to build your program. Linux and macOS only in this binding: on Windows use `syscall.LoadLibrary` instead of `purego.Dlopen`.
* The library is looked for in `$PEEP_LIB`, then the current directory, then next to the executable.
* `Read` returns at most 4096 frames per call.

## Platforms

* Linux x86-64 and Linux ARM64: the library builds with `./build.sh` (verified; ARM64 under QEMU only).
* Windows x64: `./build.sh` in MSYS2/MinGW builds `peep.dll` (the DLL loads and decodes under Wine; this binding was
  not run on Windows).
* macOS: not supported yet. Android, iOS, 32-bit ARM, RISC-V and others: not supported.

## Limits

x86-64 and ARM64 only. FLAC 4 to 31 bits per sample (32-bit is not supported), sample rates from 1 Hz. WAV: 16-bit PCM built in; the library also contains the
extension for 8/12/20/24/32-bit and float WAV (`peep_wavx()`) and the one for A-law, mu-law, IMA and Microsoft ADPCM WAV (`peep_wavc()`), which these bindings do not enable yet. No MP3 or Vorbis. A FLAC frame that fails
its CRC-16 is output as silence. Full details: https://github.com/Doggydoggywhatnow/lib-Peep

## License

Public domain, under the Unlicense (`LICENSE`).
