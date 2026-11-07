#!/bin/sh
# Builds the Liberated Peep shared library for this machine from the assembly in lib/:
#   Linux x86-64   -> libpeep.so   (needs nasm and ld)
#   Linux ARM64    -> libpeep.so   (needs as and ld)
#   Windows x64    -> peep.dll     (MSYS2/MinGW: needs nasm and gcc; or CC=x86_64-w64-mingw32-gcc)
# macOS is not supported yet.
set -e
cd "$(dirname "$0")/lib"
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)
    nasm -f elf64 peep.asm -o peep.o
    nasm -f elf64 flac.asm -o flac.o
    ld -shared -z noexecstack -o ../libpeep.so peep.o flac.o ;;
  Linux-aarch64|Linux-arm64)
    as -I arm64 arm64/peep.s -o peep.o
    as -I arm64 arm64/flac.s -o flac.o
    ld -shared -z noexecstack -o ../libpeep.so peep.o flac.o ;;
  MINGW64*|MSYS*|CYGWIN*|Windows*)
    nasm -f win64 -DWIN64 peep.asm -o peep.obj
    nasm -f win64 -DWIN64 flac.asm -o flac.obj
    ${CC:-gcc} -shared -nostdlib -Wl,--entry=0 -Wl,--export-all-symbols -o ../peep.dll peep.obj flac.obj ;;
  *)
    echo "Liberated Peep: unsupported platform $(uname -s)-$(uname -m) (supported: Linux x86-64, Linux ARM64, Windows x64)" >&2
    exit 1 ;;
esac
rm -f peep.o flac.o peep.obj flac.obj
echo "built the Liberated Peep shared library"
