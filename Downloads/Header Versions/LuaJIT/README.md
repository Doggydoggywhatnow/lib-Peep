# Liberated Peep for LuaJIT

**Audio for All** · lib-Peep 0.5.0 · built from Peep 0.2.11

Liberated Peep is a tiny audio decoder for WAV and FLAC, hand-written in assembly (x86-64 and ARM64), with no
dependencies. This download is Liberated Peep with a **LuaJIT** binding. It contains one language binding only
(LuaJIT): no C header, and nothing for any other language.

Binding mechanism: LuaJIT's built-in `ffi` library.

## Status

**Verified.** LuaJIT 2.1, Linux x86-64. The demo was built/run in this environment and its output matched the reference exactly (see "Expected output"). The shared library itself is also verified on ARM64 (under QEMU); this binding has not been run on ARM64, macOS or Windows.

## What is in this download

| File | What |
|---|---|
| `peep.lua` | the binding: `Peep` module |
| `demo.lua` | decodes the test files and prints checksums |
| `build.sh` | builds the shared library from `lib/` |
| `lib/` | the assembly library (x86-64 `*.asm` for nasm, ARM64 `arm64/*.s` for GNU as) |
| `test.wav`, `test.flac` | 0.1 s of stereo audio, for the demo |
| `LICENSE` | Unlicense (public domain) |

## Use it

```sh
./build.sh            # makes libpeep.so (Linux) or peep.dll (Windows)
```

```sh
luajit demo.lua
```

Needs: LuaJIT 2.0 or newer and nasm and ld (Linux x86-64) or as and ld (Linux ARM64).

Expected output:

```
test.wav rate=44100 channels=2 frames=4410 sum=263816 seek_sum=-69992
test.flac rate=44100 channels=2 frames=4410 sum=263816 seek_sum=-69992
```

## The LuaJIT API

```lua
local Peep = require("peep")

local peep = Peep.new(io.open("song.flac", "rb"):read("*a"))   -- WAV or FLAC, from memory
print(peep:rate(), peep:channels(), peep:total())
while true do
  local samples = peep:read(1024)          -- table of interleaved stereo int16
  if #samples == 0 then break end
  play(samples)                            -- your audio output
end
peep:seek(44100)                           -- jump to frame 44100
peep:set_gain(128)                         -- half volume
peep:close()
```

Every Liberated Peep binding offers the same few things: open a WAV or FLAC file from memory, read its
`rate`, `channels` and `total` frames, `read` stereo 16-bit samples, `seek`, set the volume (`0..256`, 256 =
full), and `close`. Output is always interleaved stereo 16-bit at the file's own sample rate; mono is
duplicated and 3+ channels use the first two.

## Notes

* LuaJIT's FFI declares functions with a C-syntax string (`ffi.cdef`). That string lives inside `peep.lua`; there is no separate header file.
* This needs LuaJIT. Plain PUC Lua (5.x) has no built-in FFI.
* `read` returns at most 4096 frames per call.

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
