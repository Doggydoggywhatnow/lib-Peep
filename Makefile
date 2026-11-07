# Liberated Peep (lib-Peep)
NASM ?= nasm
CC   ?= gcc
MINGW ?= x86_64-w64-mingw32-gcc
B := build
FLACDIR ?= third_party
OBJS := $(B)/peep.o $(B)/flac.o
WOBJS := $(B)/peep.obj $(B)/flac.obj

all: $(B)/libpeep.a
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
	$(CC) -O2 -I. -o $@ tools/testaudio.c $(B)/libpeep.a
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
	$(MAKE) --no-print-directory test-audio
	$(B)/fuzz 200000 $(SEEDDIR)/s1.flac $(SEEDDIR)/s10.flac $(SEEDDIR)/s13.flac $(SEEDDIR)/s15.flac $(SEEDDIR)/s17.flac $(SEEDDIR)/s19.flac
# `make test-audio`: stutter / click / garble tests. A soak that hammers the API with random fills, seeks and volume
# changes against a reference decode (C), then synthetic signals judged on their output (tones, spectrum, channels, seeks).
AUDIODIR := $(B)/audio
$(AUDIODIR): tools/testaudio.py
	mkdir -p $@ && python3 tools/testaudio.py --gen $@
test-audio: $(B)/peepdump $(B)/testaudio $(SEEDDIR) $(AUDIODIR)
	$(B)/testaudio 4000 $(SEEDDIR)/s*.flac $(AUDIODIR)/*
	python3 tools/testaudio.py --tool $(B)/peepdump
fuzz: $(B)/fuzz $(SEEDDIR)
	for k in 1 2 3 4; do FUZZSEED=$$k $(B)/fuzz 2000000 $(SEEDDIR)/s*.flac & done; wait
.PHONY: test test-audio fuzz

# `make appimage`: Linux AppImage test environment (WAV + native FLAC, no other codecs).
# Needs appimagetool at build/appimagetool (or APPIMAGETOOL=...).
appimage:; sh tools/mkappimage.sh
.PHONY: appimage
