#!/bin/sh
# Build $OUT: a drag-and-drop player (tools/peepplay.c) plus the
# command-line self test (tools/peeptest.c). Codecs: built-in WAV + native FLAC only.
# Needs: nasm, gcc, SDL2 dev files (libsdl2-dev), and appimagetool at build/appimagetool
# (or APPIMAGETOOL=/path/to/it). SDL2 is bundled into the AppImage.
set -e
cd "$(dirname "$0")/.."
make build/libpeep.a >/dev/null
VER=$(sed -n 's/.*LIBPEEP_VERSION "\(.*\)".*/\1/p' peep.h)
OUT=${OUT:-build/libpeep-$VER-dropplayer-x86_64.AppImage}
gcc -O2 -o build/peeptest tools/peeptest.c build/libpeep.a -lm
gcc -O2 -o build/peepplay tools/peepplay.c build/libpeep.a $(pkg-config --cflags --libs sdl2)
A=build/AppDir; rm -rf $A; mkdir -p $A/usr/bin $A/usr/lib
cp build/peeptest build/peepplay $A/usr/bin/
cp -L "$(ldconfig -p | awk '/libSDL2-2.0.so.0 /{print $NF; exit}')" $A/usr/lib/
cat > $A/AppRun <<'X'
#!/bin/sh
H=$(dirname "$(readlink -f "$0")")
export LD_LIBRARY_PATH="$H/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
case "$1" in
    --test) shift; exec "$H/usr/bin/peeptest" "$@";;       # --test [file [out.wav]]
    -h|--help) echo "libpeep test player. Run it and drop a .wav/.flac on the window, or:"
               echo "  AppImage FILE          play FILE"
               echo "  AppImage --test [FILE [OUT.wav]]   self test / decode info"; exit 0;;
esac
exec "$H/usr/bin/peepplay" "$@"
X
chmod +x $A/AppRun
cat > $A/libpeep-test.desktop <<'X'
[Desktop Entry]
Type=Application
Name=libpeep test player
Exec=peepplay %f
Icon=libpeep-test
Categories=AudioVideo;Audio;Player;
MimeType=audio/x-wav;audio/flac;audio/x-flac;
Terminal=false
X
printf '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><rect width="64" height="64" fill="#246"/><path d="M8 32h8l4-16 8 32 8-24 6 16h14" stroke="#fff" fill="none" stroke-width="3"/></svg>' > $A/libpeep-test.svg
TOOL=${APPIMAGETOOL:-build/appimagetool}
[ -x "$TOOL" ] || { echo "appimagetool not found at $TOOL (see https://github.com/AppImage/appimagetool/releases)"; exit 1; }
ARCH=x86_64 "$TOOL" --appimage-extract-and-run --no-appstream $A $OUT
echo built $OUT
