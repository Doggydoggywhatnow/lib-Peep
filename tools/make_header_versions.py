#!/usr/bin/env python3
"""Builds "Downloads/Header Versions/": one self-contained package per language.

Each package holds the assembly library (x86-64 + ARM64), a build.sh that makes a shared
library, ONE language binding, a demo, two tiny test files and a generated README. A package
never contains a C header or another language's binding, so each download has one sort of header.

Source of truth: bindings/<slug>/{meta.json, binding + demo files, usage.txt}.
    python3 tools/make_header_versions.py
"""
import json, os, shutil, sys, zipfile, textwrap

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'bindings')
OUT = os.path.join(ROOT, 'Downloads', 'Header Versions')
LIBFILES = ['peep.asm', 'flac.asm', 'abi.inc', 'arm64/peep.s', 'arm64/flac.s', 'arm64/abi_a64.inc']
VERSION, BUILT_FROM = '0.3.1', 'Peep 0.2.11'

BUILD_SH = r'''#!/bin/sh
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
'''

def read(p, mode='r'):
    with open(p, mode) as f: return f.read()

def make_readme(meta, files, expected):
    name = meta['name']
    if meta['status'] == 'verified':
        status = ("**Verified.** " + meta.get('verified_with', '') + " The demo was built/run in this environment and its "
                  "output matched the reference exactly (see \"Expected output\"). The shared library itself is also "
                  "verified on ARM64 (under QEMU); this binding has not been run on ARM64, macOS or Windows.")
    else:
        status = ("**UNVERIFIED.** This binding was written from the language's FFI documentation but has never been "
                  "compiled or run, because its toolchain was not available when it was made. Expect to fix small "
                  "things. The library it loads is verified; the binding code is not.")
    rows = '\n'.join(f'| `{f}` | {d} |' for f, d in files)
    setup = ''
    if meta.get('setup'):
        setup = '\n'.join(f'    {s}' for s in meta['setup'])
        setup = f"\n**Prepare** (once):\n\n```sh\n{setup}\n```\n"
    notes = ('\n## Notes\n\n' + '\n'.join(f'* {n}' for n in meta['notes']) + '\n') if meta.get('notes') else ''
    lang = meta.get('fence', '')
    return f'''# Liberated Peep for {name}

**Audio for All** · lib-Peep {VERSION} · built from {BUILT_FROM}

Liberated Peep is a tiny audio decoder for WAV and FLAC, hand-written in assembly (x86-64 and ARM64), with no
dependencies. This download is Liberated Peep with a **{name}** binding. It contains one language binding only
({name}): no C header, and nothing for any other language.

Binding mechanism: {meta['ffi']}.

## Status

{status}

## What is in this download

| File | What |
|---|---|
{rows}
| `build.sh` | builds the shared library from `lib/` |
| `lib/` | the assembly library (x86-64 `*.asm` for nasm, ARM64 `arm64/*.s` for GNU as) |
| `test.wav`, `test.flac` | 0.1 s of stereo audio, for the demo |
| `LICENSE` | Unlicense (public domain) |

## Use it

```sh
./build.sh            # makes libpeep.so (Linux) or peep.dll (Windows)
```
{setup}
```sh
{meta['run']}
```

Needs: {meta['needs']}.

Expected output:

```
{expected.strip()}
```

## The {name} API

```{lang}
{read(os.path.join(SRC, meta['slug'], 'usage.txt')).rstrip()}
```

Every Liberated Peep binding offers the same few things: open a WAV or FLAC file from memory, read its
`rate`, `channels` and `total` frames, `read` stereo 16-bit samples, `seek`, set the volume (`0..256`, 256 =
full), and `close`. Output is always interleaved stereo 16-bit at the file's own sample rate; mono is
duplicated and 3+ channels use the first two.
{notes}
## Platforms

* Linux x86-64 and Linux ARM64: the library builds with `./build.sh` (verified; ARM64 under QEMU only).
* Windows x64: `./build.sh` in MSYS2/MinGW builds `peep.dll` (the DLL loads and decodes under Wine; this binding was
  not run on Windows).
* macOS: not supported yet. Android, iOS, 32-bit ARM, RISC-V and others: not supported.

## Limits

x86-64 and ARM64 only. FLAC up to 24 bits per sample. 16-bit PCM WAV only. No MP3 or Vorbis. A FLAC frame that fails its
CRC-16 is output as silence. Full details: https://github.com/Doggydoggywhatnow/lib-Peep

## License

Public domain, under the Unlicense (`LICENSE`).
'''

def main():
    os.makedirs(OUT, exist_ok=True)
    expected = read(os.path.join(SRC, '_common', 'expected.txt'))
    packages = []
    for slug in sorted(os.listdir(SRC)):
        mp = os.path.join(SRC, slug, 'meta.json')
        if slug.startswith('_') or not os.path.exists(mp): continue
        meta = json.loads(read(mp)); meta['slug'] = slug
        folder = os.path.join(OUT, meta['folder'])
        if os.path.exists(folder): shutil.rmtree(folder)
        os.makedirs(os.path.join(folder, 'lib', 'arm64'))
        for f in LIBFILES: shutil.copy(os.path.join(ROOT, f), os.path.join(folder, 'lib', f))
        shutil.copy(os.path.join(ROOT, 'LICENSE'), folder)
        for f in ('test.wav', 'test.flac'): shutil.copy(os.path.join(SRC, '_common', f), folder)
        with open(os.path.join(folder, 'build.sh'), 'w', newline='\n') as f: f.write(BUILD_SH)
        os.chmod(os.path.join(folder, 'build.sh'), 0o755)
        files = []
        for f, d in meta['files']:
            dst = os.path.join(folder, f); os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy(os.path.join(SRC, slug, f), dst); files.append((f, d))
        with open(os.path.join(folder, 'README.md'), 'w') as f: f.write(make_readme(meta, files, expected))
        zp = os.path.join(OUT, meta['folder'] + '.zip')
        with zipfile.ZipFile(zp, 'w', zipfile.ZIP_DEFLATED) as z:
            for dp, _, fns in os.walk(folder):
                for fn in sorted(fns):
                    full = os.path.join(dp, fn); arc = os.path.join(meta['folder'], os.path.relpath(full, folder))
                    zi = zipfile.ZipInfo(arc, (2026, 11, 6, 0, 0, 0)); zi.compress_type = zipfile.ZIP_DEFLATED
                    zi.external_attr = (0o755 if fn.endswith('.sh') else 0o644) << 16
                    z.writestr(zi, read(full, 'rb'))
        packages.append(meta)
    ver = [m for m in packages if m['status'] == 'verified']; unv = [m for m in packages if m['status'] != 'verified']
    rows = '\n'.join(f"| {m['name']} | [{m['folder']}/]({m['folder'].replace(' ', '%20')}/) · [zip]({m['folder'].replace(' ', '%20')}.zip) | {m['ffi']} | "
                     f"{'verified' if m['status'] == 'verified' else '**unverified**'} |" for m in sorted(packages, key=lambda m: (m['status'] != 'verified', m['name'].lower())))
    unv_line = (f"* **{len(unv)} are unverified**: written from the language's FFI documentation but never compiled or run, because the toolchain\n  was not available. They are marked UNVERIFIED in their README.\n") if unv else ''
    idx = f'''# Header Versions

**Liberated Peep, Audio for All** · lib-Peep {VERSION} · built from {BUILT_FROM}

Liberated Peep is a tiny WAV and FLAC decoder written in assembly. Its native interface is a plain C ABI, so any language
that can call into a shared library can use it. This folder has **{len(packages)} ready-made packages, one per language**.

**Each download has one sort of header.** A package contains the library, a `build.sh`, test audio, a demo, and the
binding for exactly one language. It never contains a C header or another language's binding, so you can take a single
folder (or its zip) and nothing else.

## Status, honestly

* **{len(ver)} are verified**: their demo was built and run in the development environment (Linux x86-64) and printed
  exactly the expected output.
{unv_line}* The assembly library itself is verified on x86-64 and on ARM64 (the ARM64 build under QEMU emulation). No binding was run on ARM64,
  macOS or Windows. macOS is not supported yet.

| Language | Download | Binding mechanism | Status |
|---|---|---|---|
{rows}

## Using one

```sh
cd "<Language>"
./build.sh            # builds libpeep.so (Linux x86-64 / ARM64) or peep.dll (Windows, MSYS2/MinGW)
# then follow that folder's README.md
```

Each demo decodes `test.wav` and `test.flac` (0.1 s of stereo), then seeks and reads again, and prints a line like

```
{expected.splitlines()[0]}
```

Every verified package prints exactly the lines in `expected.txt` below, which were produced by the C reference.

```
{expected.strip()}
```

## Regenerating

The packages are generated from `bindings/<language>/` by `tools/make_header_versions.py`; do not edit them by hand.
`python3 tools/test_header_versions.py` builds each package in a scratch directory and runs its demo.
'''
    with open(os.path.join(OUT, 'README.md'), 'w') as f: f.write(idx)
    print(f'{len(packages)} packages ({len(ver)} verified, {len(unv)} unverified) -> {OUT}')

if __name__ == '__main__': main()
