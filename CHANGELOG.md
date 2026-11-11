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

### Experiment (dev branch): LPC prediction fused into the residual loop, x86-64 only
- `flac.asm`: the Rice residual loop is now a macro expanded four times (no prediction, fixed predictor, LPC scalar, LPC with SSE4.1), chosen once per subframe, so each
  sample's prediction is computed in the same loop as it is decoded and the predictor's dependency chain overlaps the bit reader's. Before this the whole block was predicted in a second
  pass. `predict` became `lpc_prep` (pads the coefficients, once per subframe) and `lpc_run` (LPC over a region, used for escape-coded partitions). No API, struct, workspace or output change;
  the code grew by about 1 KB (four loop copies).
- Why: counting instructions per cycle (clock measured at about 3.7 GHz) showed 24-bit and default-level files ran at about 3.1 instructions per cycle against about 4.2 for `dr_flac`
  on nearly the same instruction count, so the time was stalls, not work.
- Measured against the previous `dev` build and `dr_flac` (same machine, alternating runs, min of 7): level 5 (the default 16-bit) **+23%** (from 12% slower than `dr_flac` to **6% faster**),
  96 kHz **+25%** (from 18% slower to **3% faster**), level 8 +15%, level 12 +13%, mono +19%, 5.1 +15%, 24-bit +19% (still **14% slower than `dr_flac`**); levels 0 and 2 (fixed predictors) unchanged
  and still 8 to 10% slower.
- Tests: `make test` (x86-64) passes in full, including the 300 random streams with escape partitions, the audio suite, `make test-simd` and 200,000 fuzz inputs.
- **ARM64 port done** (`arm64/flac.s`): the same design (a macro expanded for no prediction, fixed predictor and LPC; NEON `smlal` for the older taps, then the newest four taps scalar from
  the register; `predict` split into `lpc_prep` and `lpc_run`). `make test-arm64` passes in full under QEMU (including the audio tests and the 100,000-input fuzz run). ARM64 speed is **not measured**.
- Breakage check: 13 deliberate breakages of the new loops on x86-64 and 12 on ARM64 (wrong coefficient, newest tap, window start, lane sums, padding, escape partitions, mode selection and others);
  all caught except one on each CPU that cannot change the output (an LPC shift made logical instead of arithmetic: the shift is at most 15, so only bits that the 32-bit result never uses differ).
- Still behind `dr_flac`: **24-bit by about 14%** and the fixed-predictor files (levels 0 and 2) by 8 to 10%. Measured on a shared x86-64 VM.
- 24-bit investigation (x86-64; nothing from it is in the code). At about 3.7 GHz the 24-bit file runs 3.3 instructions per cycle against 4.2 for `dr_flac`, and with prediction switched off the Rice loop
  alone takes 11.0 ns of the 12.9 ns frame (`dr_flac`'s whole decode is 11.2 ns), so the remaining gap is the bit-reading loop. Tried in scratch copies and measured: BMI2 variable shifts (at most +3%),
  a branch-free refill (about 0%), a bit-position reader decoding two samples per 8-byte load (identical output, +3% on 24-bit and up to +9% on 96 kHz with prediction off), and a 56-bit refill (3 to 10%
  slower, and wrong). None closes the gap and the cause of the loop's low instruction rate is still unknown; finding it needs hardware performance counters, which this VM does not provide.


### Changed (dev branch): the 22 language packages carry this branch's library
- `Downloads/` and `bindings/` (from the `arm64` branch) are now on `dev`, and every package's `lib/` holds the current library: the optimised x86-64 FLAC decoder, the ARM64 FLAC changes, the compressed-WAV codec (`wavc`), the 1 Hz rate limit and the FLAC STREAMINFO fixes.
  `build.sh` (all 22) now also builds `wavc`, so `peep_wavc()` is in `libpeep.so` / `peep.dll`; the READMEs' Limits section says so. The zips are rebuilt.
- The bindings themselves are unchanged: they still enable FLAC and built-in 16-bit WAV only (`peep_wavx()` and `peep_wavc()` are in the library but not switched on by any binding).
- Checked: all 22 `build.sh` build on x86-64 and export `peep_wavc`; the Python, Ruby, Perl and PHP demos print the reference output. The ARM64 sources of the package assemble and link (cross tools); only the library was run on ARM64 (QEMU), no binding. Not run here: the other 18 bindings (their runtimes or packages are missing), Windows, macOS.

### Changed (dev branch): the ARM64 FLAC decoder gets the optimisations that carry over from x86-64
- `arm64/flac.s`: (1) one Rice loop per predictor: fixed orders 1 to 4 each written out, LPC with 4, 8, 12 or 16 taps straight-line (the coefficients live in `v16` to `v18` and four scalar registers for the partition, so the loop loads only samples), and a NEON loop for 20 taps and up: ten loops chosen once per subframe
  instead of a test per sample; (2) one unaligned 8-byte refill, inlined (it was a 4-byte call), with the invariant that the cache may hold genuine bits below its valid count, so a leading one at or past the valid count goes to the long-run path; (3) a 2-instruction zig-zag and no zero test in the fast path;
  (4) `rd_signed`, one arithmetic shift of the cache per value, for verbatim, warm-up and escape data; (5) a NEON wasted-bits shift; (6) NEON interleaving of mono and of 3 to 8 channels (it was one scalar pass per channel).
- Not ported: the PCLMULQDQ CRC-16 (ARM64 would need PMULL and a way to detect it without a system call), `lzcnt`/BMI2 (`clz` and variable shifts are already single instructions), and the x86-specific coefficient shuffle.
- **Measured as instructions, not time**: dynamic instruction count per stereo frame (6-channel and mono: per frame of all channels) on 300 KB prefixes of the test files, QEMU single-step, before to after: level 0 89.4 to **68.9**, level 2 83.7 to **65.3**, level 5 121.3 to **82.9**, level 8 133.3 to **88.9**,
  mono 82.3 to **56.9**, 5.1 194.9 to **126.0**, 24-bit 132.0 to **86.0** (22 to 35% fewer). Instruction counts are not speed (the x86 work showed that dependency chains, not counts, decide it), and QEMU timings mean nothing: **the ARM64 speed has not been measured**.
- Checked: `make test-arm64` passes in full (100,000 fuzz inputs). Deliberately broken versions (refill byte count, fixed order 3 and LPC tap terms, the signed reader's shift, the long-run guard, mode selection, a coefficient register load, the interleave and wasted-bit counts) are all caught by the tests.

### Changed (dev branch): optimised x86-64 FLAC decoder, and two FLAC behaviour fixes in both ports
- `flac.asm` is replaced by an optimised decoder written by another AI session from the previous `flac.asm`, then reviewed, built against this repo's `abi.inc`, and checked here: `make test` (200,000 fuzz inputs, audio suite, `make test-simd`) passes in full,
  and a callee-saved-register check over open, fill, fill32, seek, metadata and close on a 6-channel 24-bit file passes. Same exported symbols, same `peep` layout, same workspace size. What changed: one 8-byte refill (inlined in the Rice loops), `lzcnt` and `shrx`/`shlx`
  in the BMI2 loops (BMI2 and LZCNT both required), a 3-instruction zig-zag, a separate loop per predictor (fixed orders 1 to 4 written out, LPC order 4, scalar, SSE4.1 order 8, order 12 and 16 and up: 20 loop copies chosen once per subframe), end-aligned coefficients
  with the older taps arranged for `pshufd`+`pmuldq`, a PCLMULQDQ frame CRC-16 (`-dNOCLMUL` to force the table code), a tight signed-value reader for verbatim, warm-up and escape data, and SIMD mono and row-wise multichannel interleaving.
- Speed (same VM, alternating runs, best of 5, ns per frame; `cur` = the build before this change, which already had the fusion, `bsr` fix, reordering and BMI2): level 0 9.32 to **7.10**, level 2 9.20 to **7.29**, level 5 12.17 to **9.34**, level 8 13.38 to **9.88**,
  level 12 15.76 to **12.20**, mono 7.95 to **5.65**, 5.1 18.96 to **13.96**, 96 kHz 11.70 to **8.96**, 24-bit 15.75 to **12.69**. Against `dr_flac` on the same run: 24-bit is now **25% faster** (15.87), the 16-bit files 32 to 100% faster.
  This VM was slower than earlier runs, so compare the ratios, not the absolute figures. `flac.o` grows from 12.3 KB to 17.8 KB of code. Not ported to ARM64 (speed unmeasured there anyway).
- **Behaviour fixes, in both ports, with new tests:** (1) STREAMINFO min or max block size 0 ("unknown", written by some streaming encoders) used to make `peep_open` fail; now max 0 counts as 65,535 and min 0 as the max. (2) Fixed-blocksize frames' sample positions were frame number x STREAMINFO's min block size, which is wrong
  when an encoder writes the short last block as the minimum: seeking then landed in the wrong place or returned nothing. The first frame's own block size is now used. `tools/mkflac.py` now writes the true minimum (a short last block), `0` and `0,max` in fixed-blocksize streams: the previous decoder fails 18 of 300 such cases (and the ARM64 port failed 3 of 120 before the fix); the new code passes all.
  `make test-simd` also runs a `-dNOCLMUL` build.

### Changed (dev branch): sample rates from 1 Hz are accepted
- `peep_open` (both ports) now accepts 1 to 1,048,575 Hz; it was 1,000 to 1,048,575. Rate 0 is still rejected. Only the check in `peep.asm` / `arm64/peep.s` changed: the codecs just pass the rate through.
  `tools/mkflac.py` now also makes FLAC files at 1, 8, 500 and 999 Hz, and `tools/testwav.py` plays WAV at 1 to 1,048,575 Hz and rejects 1,048,576. `make test` and `make test-arm64` pass. Docs updated.

### Tried and dropped (dev branch): inlining the bit reader's refill into the Rice loops, x86-64
- The fast path of `br_refill` copied into both refill sites of every loop copy (no call or return). Best of 9 alternating runs: 24-bit 10.78 to 10.70 ns per frame, level 8 9.18 to 9.11: under 1%, inside the noise of a shared VM, for more code. Not kept.
  Same session: `dr_flac` on the 24-bit file 10.56 ns, so 24-bit is about 1% behind.

### Experiment (dev branch): BMI2 shifts in the Rice loops, x86-64 only
- `flac.asm`: each Rice loop now has a second copy that uses `shrx` / `shlx` (a shift by a register is one micro-op and reads no flags). `peep_open` picks it only if `cpuid` leaf 7 reports BMI2 (`BMI2F`, bit 9 of `S_SIBPS`);
  other CPUs run the plain-shift copy. `-dNOBMI2` builds without it. Code grows by about 1.5 KB (`flac.o` 10.8 to 12.3 KB). An earlier scratch test of BMI2 shifts showed 3% at most; it gained more after the `bsr` and ordering fixes.
- Measured against the build before it (alternating runs, same machine): 24-bit 12.04 to 11.41 ns per frame (`dr_flac` 11.45: a tie), level 0 -5%, level 2 -2%, level 5 -4%, level 8 -5%, 96 kHz -4%, mono -5%, 5.1 -4%. `make test` passes in full;
  `make test-simd` now also runs a `-dNOBMI2` build, and the `qemu64` run covers a CPU with neither SSE4.1 nor BMI2. ARM64: not applicable, not changed.

### Experiment (dev branch): the bit reader's cache update goes first in the Rice loop, x86-64 only
- `flac.asm`: in the fast path of the residual loop the `shl r13, cl` that drops the consumed bits now comes before the value arithmetic (a shift by `cl` depends on the flags it is given, so it
  now takes them from the short `cmp` just above, not from the value arithmetic). The instruction set is unchanged, only the order, so output is identical. ARM64 not changed or measured.
- Measured against the build before it (same machine, alternating runs, min of 7): 24-bit +3.7%, level 2 +7.4%, level 0 +5.1%, 96 kHz +4.3%, level 8 +0.6%, level 5 unchanged. 24-bit is still about 8% slower than `dr_flac`
  (12.00 against 11.00 ns per frame). The bit-position reader was tried again after the `bsr` fix: 12 to 17% slower, dropped. `make test` passes in full.

### Experiment (dev branch): one instruction removes a false dependency in the Rice loop, x86-64 only
- `flac.asm`: `xor eax, eax` before `bsr rax, r13` in the residual loop. `bsr` leaves its destination unchanged when its source is zero, so the CPU treats the old `rax` as an input; `rax` held the
  previous sample's zig-zag or prediction result, which chained each sample's bit scan to the last sample's value and stopped the bit reader and the predictor overlapping. The zeroing idiom breaks the chain.
  Found by measurement after four guesses about the loop (BMI2 shifts, a branch-free refill, a bit-position reader, a 56-bit refill) had each gained little or nothing. ARM64 needs nothing: `clz` has no such input.
- Measured against the build just before it (same machine, alternating runs, min of 7): levels 0 and 2 **+21 to +23%** (now **12 to 14% faster than `dr_flac`**, from 8 to 10% slower), level 5 +5%, 96 kHz +4%,
  level 8 +8%, 24-bit +5% (still about **10% slower than `dr_flac`**), mono unchanged. Output is identical; `make test` passes in full (200,000 fuzz inputs, the audio suite, `make test-simd`).

### Added (dev branch): compressed WAV codec, `peep_codec_wavc`
- `wavc.asm` and `arm64/wavc.s` (about 2.5 KB each), pure assembly: **A-law** (tag 6) and **mu-law** (tag 7), 1 to 8 channels, plain or extensible headers;
  **IMA ADPCM** (0x11) and **Microsoft ADPCM** (2), mono or stereo. Output is 16-bit (`p->bits` = 16, `read32` is each sample << 16). ADPCM needs an 80-byte workspace
  (`work_need` protocol); A-law and mu-law need none. Seeking decodes from the start of the block that holds the frame. A `fact` chunk trims the padding of the last block and a
  partial last block plays the groups it holds. Microsoft ADPCM uses the coefficient table in the file (division by 256 truncates toward zero; the header delta is used as it stands).
  `peep_wavc()` returns the table's address; `peep.h` declares both.
- **IMA ADPCM follows the reference algorithm**, not ffmpeg's rounding. Checked against a second independent decoder: `libsndfile` (through `ctypes`) matches the reference-form model
  bit for bit, and `ffmpeg` differs from both (its `((2*delta+1)*step)>>3` shortcut): up to about 45 units on a test file. A-law, mu-law and Microsoft ADPCM agree across ffmpeg,
  libsndfile and the model bit for bit.
- Not covered (rejected, never decoded wrongly): GSM 6.10, MP3 inside WAV, Dialogic OKI and Yamaha ADPCM, G.72x, extensible-header ADPCM, ADPCM above 2 channels.
- Tests, all saved: `tools/wavmodels.py` (independent models), `tools/sndfileref.py` (libsndfile reference), `tools/testwavc.py` (`make test-wavc`; 1,085 checks on x86-64, 643 in
  the ARM64 `--quick` run under QEMU) and `tools/testwavc_ws.c` (the workspace protocol, 23 checks on each CPU). The fuzzer also mutates five compressed-WAV seeds: 2.1 million inputs on
  x86-64 and 150,000 on ARM64 run clean.
- Found and fixed along the way: (1) the fuzzer found an unchecked read of a `fact` chunk whose body lies past the end of the file (a crash on a damaged file), in both ports;
  (2) the breakage check showed the decoder floored the Microsoft ADPCM header delta at 16 while `libsndfile` and `ffmpeg` use it as it stands, so a header delta below 16 or negative
  decoded differently from both (valid encoders never write one, so ordinary files were unaffected); (3) a first stereo MS ADPCM bug (a scratch register clobbered) caught immediately by the tests.
- Breakage check: 23 deliberate breakages on x86-64 and 22 on ARM64 (formulas, tables, offsets, header rules, fact trimming, partial blocks, seeking, workspace and channel limits).
  All were caught once the new tests above were added, except one on x86-64 that only slows seeking (a resync that decodes from the block start every call but gives the same samples).
- Not done: the language packages and bindings do not know the new codec (dev has none); ARM64 has only been run under QEMU, never on real hardware; speed was not measured or tuned.

### Experiment (dev branch): both speed changes ported to ARM64 (`arm64/flac.s`)
- Fused fixed-predictor decoding: the same design as x86-64 (orders 1 to 4 applied inside `decode_residual` with the previous sample in `x15`, older history read back
  from the plane, escape partitions run the fixed loop over their region only). LPC prediction: the scalar loop is replaced by NEON, four taps per pass as `smlal` and
  `smlal2` (signed 32x32 to 64-bit multiply-accumulate) over the int32 coefficients, then the newest four taps scalar as before. NEON is mandatory on AArch64, so there is
  no `cpuid`-style check and no scalar fallback loop; the x86-64 `NOSIMD` option has no ARM64 counterpart.
- Verified under QEMU only: `make test-arm64` passes (2,504 WAV checks, 120 FLAC streams, 150 corrupted streams, 614 high-resolution and 796 WAV-format checks, 100,000 fuzz
  inputs), as do the audio tests (320,490 soak checks, 857 signal checks). 11 deliberate breakages of the ported code were caught (a twelfth did not assemble and so
  was not a valid test).
- **Not measured:** the speed on ARM64. QEMU timings are meaningless, and the port has never run on real ARM hardware, so whether it is faster, by how much, or at all
  is unknown. The x86-64 gains (levels 0 and 2, 8 and 12) show the idea works, not that ARM64 will match them.

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
