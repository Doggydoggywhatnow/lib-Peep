# Liberated Peep (lib-Peep)
NASM ?= nasm
CC   ?= gcc
MINGW ?= x86_64-w64-mingw32-gcc
B := build
FLACDIR ?= third_party
OBJS := $(B)/peep.o $(B)/flac.o
WOBJS := $(B)/peep.obj $(B)/flac.obj

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
$(SEEDDIR): tools/mkflac.py
	mkdir -p $@ && for s in 1 10 13 15 17 19; do python3 tools/mkflac.py --gen $@/s$$s --seed $$s >/dev/null; done
test: $(B)/peepdump $(B)/fuzz $(SEEDDIR)
	python3 tools/testwav.py $(B)/peepdump
	python3 tools/mkflac.py --run 120 --seed 1 --tool $(B)/peepdump
	python3 tools/testcrc.py --run 300 --seed 1 --tool $(B)/peepdump
	python3 tools/testhires.py --run 120 --seed 1 --tool $(B)/peepdump
	$(B)/fuzz 200000 $(SEEDDIR)/s1.flac $(SEEDDIR)/s10.flac $(SEEDDIR)/s13.flac $(SEEDDIR)/s15.flac $(SEEDDIR)/s17.flac $(SEEDDIR)/s19.flac
fuzz: $(B)/fuzz $(SEEDDIR)
	for k in 1 2 3 4; do FUZZSEED=$$k $(B)/fuzz 2000000 $(SEEDDIR)/s*.flac & done; wait
.PHONY: test fuzz

# ---- ARM64 (AArch64) ----------------------------------------------------------
# Pure assembly, GNU as syntax. CROSS is the toolchain prefix when cross-building;
# QEMU runs the ARM64 test tools on a non-ARM machine (leave empty on real ARM).
CROSS ?=
A64AS ?= $(CROSS)as
A64AR ?= $(CROSS)ar
A64CC ?= $(CROSS)gcc
A64OBJS := $(B)/peep_a64.o $(B)/flac_a64.o
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
	$(QEMU) $(B)/fuzz_a64 100000 $(SEEDDIR)/s1.flac $(SEEDDIR)/s10.flac $(SEEDDIR)/s13.flac $(SEEDDIR)/s15.flac $(SEEDDIR)/s17.flac $(SEEDDIR)/s19.flac
.PHONY: arm64 test-arm64
