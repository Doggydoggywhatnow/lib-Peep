#!/bin/sh
# Build build/libpeep-test-x86_64.AppImage (no extra codecs: WAV built in + native FLAC).
# Needs appimagetool: put it at build/appimagetool, or set APPIMAGETOOL=/path/to/it.
set -e
cd "$(dirname "$0")/.."
make build/libpeep.a >/dev/null
gcc -O2 -o build/peeptest tools/peeptest.c build/libpeep.a -lm
A=build/AppDir; rm -rf $A; mkdir -p $A/usr/bin
cp build/peeptest $A/usr/bin/
cat > $A/AppRun <<'X'
#!/bin/sh
H=$(dirname "$(readlink -f "$0")")
# Started from a file manager (no terminal)? Re-run inside a terminal window and wait for Enter.
if [ ! -t 0 ] && [ ! -t 1 ] && [ ! -t 2 ] && [ -z "$PEEP_IN_TERM" ] && [ -n "$DISPLAY$WAYLAND_DISPLAY" ]; then
    export PEEP_IN_TERM=1
    S="$H/usr/bin/peeptest \"\$@\"; echo; printf 'Press Enter to close...'; read x"
    for t in x-terminal-emulator gnome-terminal konsole xfce4-terminal xterm; do
        if command -v $t >/dev/null 2>&1; then
            case $t in gnome-terminal) exec $t -- sh -c "$S" peeptest "$@";; *) exec $t -e sh -c "$S" peeptest "$@";; esac
        fi
    done
fi
exec "$H/usr/bin/peeptest" "$@"
X
chmod +x $A/AppRun
cat > $A/libpeep-test.desktop <<'X'
[Desktop Entry]
Type=Application
Name=libpeep test
Exec=peeptest
Icon=libpeep-test
Categories=AudioVideo;
Terminal=true
X
printf '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><rect width="64" height="64" fill="#246"/><path d="M8 32h8l4-16 8 32 8-24 6 16h14" stroke="#fff" fill="none" stroke-width="3"/></svg>' > $A/libpeep-test.svg
TOOL=${APPIMAGETOOL:-build/appimagetool}
[ -x "$TOOL" ] || { echo "appimagetool not found at $TOOL (see https://github.com/AppImage/appimagetool/releases)"; exit 1; }
ARCH=x86_64 "$TOOL" --appimage-extract-and-run --no-appstream $A build/libpeep-test-x86_64.AppImage
echo built build/libpeep-test-x86_64.AppImage
