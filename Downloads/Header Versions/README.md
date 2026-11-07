# Header Versions

**Liberated Peep, Audio for All** · lib-Peep 0.3.1 · built from Peep 0.2.11

Liberated Peep is a tiny WAV and FLAC decoder written in assembly. Its native interface is a plain C ABI, so any language
that can call into a shared library can use it. This folder has **22 ready-made packages, one per language**.

**Each download has one sort of header.** A package contains the library, a `build.sh`, test audio, a demo, and the
binding for exactly one language. It never contains a C header or another language's binding, so you can take a single
folder (or its zip) and nothing else.

## Status, honestly

* **22 are verified**: their demo was built and run in the development environment (Linux x86-64) and printed
  exactly the expected output.
* The assembly library itself is verified on x86-64 and on ARM64 (the ARM64 build under QEMU emulation). No binding was run on ARM64,
  macOS or Windows. macOS is not supported yet.

| Language | Download | Binding mechanism | Status |
|---|---|---|---|
| Bun | [Bun/](Bun/) · [zip](Bun.zip) | Bun's built-in `bun:ffi` | verified |
| C# | [CSharp/](CSharp/) · [zip](CSharp.zip) | P/Invoke (`DllImport`) | verified |
| C++ | [CPlusPlus/](CPlusPlus/) · [zip](CPlusPlus.zip) | `extern "C"` declarations inside the C++ header `peep.hpp` | verified |
| Common Lisp | [CommonLisp/](CommonLisp/) · [zip](CommonLisp.zip) | SBCL `sb-alien` (built into SBCL) | verified |
| D | [D/](D/) · [zip](D.zip) | `extern(C)` declarations (the D language links to C directly) | verified |
| F# | [FSharp/](FSharp/) · [zip](FSharp.zip) | P/Invoke (`DllImport`) | verified |
| Fortran | [Fortran/](Fortran/) · [zip](Fortran.zip) | `iso_c_binding` with `bind(C)` interfaces (Fortran 2003) | verified |
| Free Pascal | [FreePascal/](FreePascal/) · [zip](FreePascal.zip) | `external` procedure declarations | verified |
| GNU Guile | [Guile/](Guile/) · [zip](Guile.zip) | (system foreign), built into Guile | verified |
| Go | [Go/](Go/) · [zip](Go.zip) | purego (github.com/ebitengine/purego): no cgo, no C compiler | verified |
| Java | [Java/](Java/) · [zip](Java.zip) | java.lang.foreign (Foreign Function & Memory API) | verified |
| LuaJIT | [LuaJIT/](LuaJIT/) · [zip](LuaJIT.zip) | LuaJIT's built-in `ffi` library | verified |
| Nim | [Nim/](Nim/) · [zip](Nim.zip) | `importc` with the `dynlib` pragma | verified |
| Node.js | [NodeJS/](NodeJS/) · [zip](NodeJS.zip) | koffi (npm package) | verified |
| Perl | [Perl/](Perl/) · [zip](Perl.zip) | FFI::Platypus (CPAN; `apt install libffi-platypus-perl`) | verified |
| PHP | [PHP/](PHP/) · [zip](PHP.zip) | PHP FFI extension (`FFI::cdef`) | verified |
| Python | [Python/](Python/) · [zip](Python.zip) | ctypes (Python standard library) | verified |
| Racket | [Racket/](Racket/) · [zip](Racket.zip) | `ffi/unsafe` (built into Racket) | verified |
| Raku | [Raku/](Raku/) · [zip](Raku.zip) | NativeCall (built into Raku) | verified |
| Ruby | [Ruby/](Ruby/) · [zip](Ruby.zip) | Fiddle (Ruby standard library) | verified |
| Rust | [Rust/](Rust/) · [zip](Rust.zip) | plain `extern "C"` blocks (standard library only, no crates) | verified |
| Visual Basic .NET | [VisualBasicNET/](VisualBasicNET/) · [zip](VisualBasicNET.zip) | P/Invoke (`DllImport`) | verified |

## Using one

```sh
cd "<Language>"
./build.sh            # builds libpeep.so (Linux x86-64 / ARM64) or peep.dll (Windows, MSYS2/MinGW)
# then follow that folder's README.md
```

Each demo decodes `test.wav` and `test.flac` (0.1 s of stereo), then seeks and reads again, and prints a line like

```
test.wav rate=44100 channels=2 frames=4410 sum=263816 seek_sum=-69992
```

Every verified package prints exactly the lines in `expected.txt` below, which were produced by the C reference.

```
test.wav rate=44100 channels=2 frames=4410 sum=263816 seek_sum=-69992
test.flac rate=44100 channels=2 frames=4410 sum=263816 seek_sum=-69992
```

## Regenerating

The packages are generated from `bindings/<language>/` by `tools/make_header_versions.py`; do not edit them by hand.
`python3 tools/test_header_versions.py` builds each package in a scratch directory and runs its demo.
