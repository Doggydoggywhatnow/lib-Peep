# Liberated Peep (lib-Peep)
NASM ?= nasm
CC   ?= gcc
MINGW ?= x86_64-w64-mingw32-gcc
B := build
FLACDIR ?= third_party
OBJS := $(B)/peep.o $(B)/flac.o $(B)/wav.o
WOBJS := $(B)/peep.obj $(B)/flac.obj $(B)/wav.obj

# On an ARM64 machine a plain `make` builds the ARM64 library (arm64/*.s, GNU as).
# On x86-64 it builds the x86-64 one (*.asm, nasm). Cross-build ARM64 from x86-64 with
#   make arm64 CROSS=aarch64-linux-gnu-
ifneq (,$(filter aarch64 arm64,$(shell uname -m)))
all: $(B)/libpeep_a64.a
else
all: $(B)/libpeep.a
endif
$(B):; mkdir -p $(B)
$(B)/%.o: %.asm abi.inc | $(B);     $(NASM) -f elf64 $< -o $@
$(B)/%.obj: %.asm abi.inc | $(B);   $(NASM) -f win64 -DWIN64 $< -o $@
$(B)/libpeep.a: $(OBJS);            rm -f $@; ar rcs $@ $^
$(B)/drflac.o: examples/codec_drflac.c | $(B)
	$(CC) -O2 -I$(FLACDIR) -c $< -o $@
$(B)/peepdump: tools/peepdump.c $(B)/drflac.o $(B)/libpeep.a
	$(CC) -O2 -o $@ tools/peepdump.c $(B)/drflac.o $(B)/libpeep.a -lm
$(B)/fuzz: tools/fuzz.c $(B)/drflac.o $(B)/libpeep.a
	$(CC) -O1 -g -o $@ tools/fuzz.c $(B)/drflac.o $(B)/libpeep.a -lm
$(B)/testaudio: tools/testaudio.c $(B)/libpeep.a
	$(CC) -O2 -DPEEP_WIDE -I. -o $@ tools/testaudio.c $(B)/libpeep.a
$(B)/bench: tools/bench.c $(B)/drflac.o $(B)/libpeep.a
	$(CC) -O2 -o $@ tools/bench.c $(B)/drflac.o $(B)/libpeep.a -lm
win: $(WOBJS)
$(B)/peepdump.exe: tools/peepdump.c $(WOBJS)
	$(MINGW) -O2 -DNO_DR -o $@ tools/peepdump.c $(WOBJS)
clean:; rm -rf $(B)
.PHONY: all win clean

# ---- tests ------------------------------------------------------------------
# `make test`: ground-truth FLAC corpus (random streams from tools/mkflac.py), the WAV
# suite, and a short fuzz run. Needs python3 + numpy. `make fuzz` runs a longer one.
SEEDDIR := $(B)/seeds
$(SEEDDIR): tools/mkflac.py tools/testwavx.py
	mkdir -p $@ && for s in 1 10 13 15 17 19; do python3 tools/mkflac.py --gen $@/s$$s --seed $$s >/dev/null; done; python3 tools/testwavx.py --gen $@
test: $(B)/peepdump $(B)/fuzz $(SEEDDIR)
	python3 tools/testwav.py $(B)/peepdump
	python3 tools/mkflac.py --run 120 --seed 1 --tool $(B)/peepdump
	python3 tools/testcrc.py --run 300 --seed 1 --tool $(B)/peepdump
	python3 tools/testhires.py --run 120 --seed 1 --tool $(B)/peepdump
	python3 tools/testwavx.py --run 240 --seed 1 --tool $(B)/peepdump
	$(MAKE) --no-print-directory test-audio
	$(MAKE) --no-print-directory test-simd
	$(B)/fuzz 200000 $(SEEDDIR)/s1.flac $(SEEDDIR)/s10.flac $(SEEDDIR)/s13.flac $(SEEDDIR)/s15.flac $(SEEDDIR)/s17.flac $(SEEDDIR)/s19.flac $(SEEDDIR)/w0.wav $(SEEDDIR)/w1.wav $(SEEDDIR)/w2.wav $(SEEDDIR)/w3.wav $(SEEDDIR)/w4.wav
# SIMD LPC (flac.asm): the SSE4.1 loop is used only when cpuid says the CPU has it. `make test-simd` proves the other half: the same sources must
# decode bit-exactly (1) in a build forced to the scalar loop (-dNOSIMD) and (2) on an emulated CPU WITHOUT SSE4.1, where running the SIMD
# instruction would crash, so a wrong cpuid check (inverted, wrong bit, ignored) fails here. Needs qemu-x86_64 for (2); skipped with a notice if absent.
QEMUX ?= qemu-x86_64
$(B)/flac_nosimd.o: flac.asm abi.inc | $(B);   $(NASM) -dNOSIMD -f elf64 $< -o $@
$(B)/libpeep_nosimd.a: $(B)/peep.o $(B)/flac_nosimd.o $(B)/wav.o;   rm -f $@; ar rcs $@ $^
$(B)/peepdump_nosimd: tools/peepdump.c $(B)/drflac.o $(B)/libpeep_nosimd.a
	$(CC) -O2 -o $@ tools/peepdump.c $(B)/drflac.o $(B)/libpeep_nosimd.a -lm
$(B)/peepdump_static: tools/peepdump.c $(B)/drflac.o $(B)/libpeep.a
	$(CC) -static -O2 -o $@ tools/peepdump.c $(B)/drflac.o $(B)/libpeep.a -lm
$(B)/run_nosse41.sh: $(B)/peepdump_static
	printf '#!/bin/sh\nexec $(QEMUX) -cpu qemu64 $(CURDIR)/$(B)/peepdump_static "$$@"\n' > $@; chmod +x $@
test-simd: $(B)/peepdump $(B)/peepdump_nosimd $(SEEDDIR)
	python3 tools/mkflac.py --run 60 --seed 7 --tool $(B)/peepdump_nosimd
	python3 tools/testhires.py --run 12 --seed 3 --tool $(B)/peepdump_nosimd
	@if command -v $(QEMUX) >/dev/null 2>&1; then $(MAKE) --no-print-directory $(B)/run_nosse41.sh && \
	  python3 tools/mkflac.py --run 60 --seed 7 --tool $(B)/run_nosse41.sh && python3 tools/testwav.py $(B)/run_nosse41.sh && \
	  python3 tools/testhires.py --run 12 --seed 3 --tool $(B)/run_nosse41.sh; \
	else echo "test-simd: $(QEMUX) not found, skipping the emulated CPU without SSE4.1 (only the forced-scalar build was tested)"; fi
# `make test-audio`: stutter / click / garble tests. A soak that hammers the API with random fills, seeks and volume
# changes against a reference decode (C), then synthetic signals judged on their output (tones, spectrum, channels, seeks).
AUDIODIR := $(B)/audio
$(AUDIODIR): tools/testaudio.py
	mkdir -p $@ && python3 tools/testaudio.py --gen $@
test-audio: $(B)/peepdump $(B)/testaudio $(SEEDDIR) $(AUDIODIR)
	$(B)/testaudio 4000 $(SEEDDIR)/s*.flac $(AUDIODIR)/*
	python3 tools/testaudio.py --tool $(B)/peepdump
fuzz: $(B)/fuzz $(SEEDDIR)
	for k in 1 2 3 4; do FUZZSEED=$$k $(B)/fuzz 2000000 $(SEEDDIR)/s*.flac $(SEEDDIR)/w*.wav & done; wait
.PHONY: test test-audio test-simd fuzz

# ---- ARM64 (AArch64) ----------------------------------------------------------
# Pure assembly, GNU as syntax. CROSS is the toolchain prefix when cross-building;
# QEMU runs the ARM64 test tools on a non-ARM machine (leave empty on real ARM).
CROSS ?=
A64AS ?= $(CROSS)as
A64AR ?= $(CROSS)ar
A64CC ?= $(CROSS)gcc
A64OBJS := $(B)/peep_a64.o $(B)/flac_a64.o $(B)/wav_a64.o
ifneq (,$(filter aarch64 arm64,$(shell uname -m)))
QEMU ?=
else
QEMU ?= qemu-aarch64
endif
$(B)/%_a64.o: arm64/%.s arm64/abi_a64.inc | $(B);   $(A64AS) -I arm64 $< -o $@
$(B)/libpeep_a64.a: $(A64OBJS);                     rm -f $@; $(A64AR) rcs $@ $^
$(B)/drflac_a64.o: examples/codec_drflac.c | $(B)
	$(A64CC) -O2 -I$(FLACDIR) -c $< -o $@
$(B)/peepdump_a64: tools/peepdump.c $(B)/drflac_a64.o $(B)/libpeep_a64.a
	$(A64CC) -static -O2 -o $@ tools/peepdump.c $(B)/drflac_a64.o $(B)/libpeep_a64.a -lm
$(B)/fuzz_a64: tools/fuzz.c $(B)/libpeep_a64.a
	$(A64CC) -static -O1 -g -o $@ tools/fuzz.c $(B)/libpeep_a64.a
$(B)/bench_a64: tools/bench.c $(B)/drflac_a64.o $(B)/libpeep_a64.a
	$(A64CC) -static -O2 -o $@ tools/bench.c $(B)/drflac_a64.o $(B)/libpeep_a64.a -lm
$(B)/run_a64.sh: $(B)/peepdump_a64
	printf '#!/bin/sh\nexec $(QEMU) $(CURDIR)/$(B)/peepdump_a64 "$$@"\n' > $@; chmod +x $@
arm64: $(B)/libpeep_a64.a
# `make test-arm64`: the same suites as `make test`, run on the ARM64 build
test-arm64: $(B)/run_a64.sh $(B)/fuzz_a64 $(SEEDDIR)
	python3 tools/testwav.py $(B)/run_a64.sh
	python3 tools/mkflac.py --run 120 --seed 1 --tool $(B)/run_a64.sh
	python3 tools/testcrc.py --run 150 --seed 1 --tool $(B)/run_a64.sh
	python3 tools/testhires.py --run 60 --seed 1 --tool $(B)/run_a64.sh
	python3 tools/testwavx.py --run 120 --seed 1 --tool $(B)/run_a64.sh
	$(QEMU) $(B)/fuzz_a64 100000 $(SEEDDIR)/s1.flac $(SEEDDIR)/s10.flac $(SEEDDIR)/s13.flac $(SEEDDIR)/s15.flac $(SEEDDIR)/s17.flac $(SEEDDIR)/s19.flac $(SEEDDIR)/w0.wav $(SEEDDIR)/w1.wav $(SEEDDIR)/w2.wav $(SEEDDIR)/w3.wav $(SEEDDIR)/w4.wav
.PHONY: arm64 test-arm64

# `make appimage`: Linux AppImage test environment (WAV + native FLAC, no other codecs).
# Needs appimagetool at build/appimagetool (or APPIMAGETOOL=...).
appimage:; sh tools/mkappimage.sh
.PHONY: appimage
