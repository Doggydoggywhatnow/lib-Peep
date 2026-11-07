"""Liberated Peep for Python (ctypes, standard library only)."""
import array
import ctypes
import os
import sys


def _load():
    name = "peep.dll" if sys.platform == "win32" else "libpeep.so"
    here = os.path.dirname(os.path.abspath(__file__))
    for path in (os.environ.get("PEEP_LIB"), os.path.join(here, name)):
        if path and os.path.exists(path):
            return ctypes.CDLL(path)
    raise OSError("libpeep not found: run ./build.sh first (or set PEEP_LIB)")


_lib = _load()
_lib.peep_open.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t,
                           ctypes.c_void_p, ctypes.c_size_t]
_lib.peep_open.restype = ctypes.c_int
_lib.peep_fill.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t]
_lib.peep_fill.restype = ctypes.c_size_t
_lib.peep_seek.argtypes = [ctypes.c_void_p, ctypes.c_uint64]
_lib.peep_close.argtypes = [ctypes.c_void_p]
_lib.peep_flac.restype = ctypes.c_void_p
_FLAC = _lib.peep_flac()                       # address of the FLAC codec table


class Peep:
    """Decodes a WAV or FLAC file held in memory into stereo 16-bit samples."""

    def __init__(self, data, flac=True):
        self._data = bytes(data)                       # must stay alive until close()
        self._p = ctypes.create_string_buffer(160)     # struct peep
        self._codecs = (ctypes.c_void_p * 2)(_FLAC if flac else None, None)
        self._work = None
        if not _lib.peep_open(self._p, self._codecs, self._data, len(self._data), None, 0):
            need = ctypes.c_size_t.from_buffer(self._p, 144).value      # work_need
            if need:
                self._work = ctypes.create_string_buffer(need)
                if _lib.peep_open(self._p, self._codecs, self._data, len(self._data), self._work, need):
                    need = 0
            if need:
                raise ValueError("not a playable WAV or FLAC file")
        self._out = ctypes.create_string_buffer(4096 * 4)
        self._open = True

    def _u32(self, off):
        return ctypes.c_uint32.from_buffer(self._p, off).value

    def _u64(self, off):
        return ctypes.c_uint64.from_buffer(self._p, off).value

    rate = property(lambda self: self._u32(40))        # Hz
    channels = property(lambda self: self._u32(44))    # channels in the file
    total = property(lambda self: self._u64(32))       # frames, 0 = unknown
    position = property(lambda self: self._u64(24))    # frames played so far

    def read(self, frames=1024):
        """Returns an array('h') of up to frames*2 interleaved stereo samples; empty at the end."""
        frames = min(frames, 4096)
        n = _lib.peep_fill(self._p, self._out, frames)
        samples = array.array("h")
        samples.frombytes(self._out.raw[: n * 4])
        return samples

    def seek(self, frame):
        _lib.peep_seek(self._p, frame)

    def set_gain(self, q8):
        """Volume 0..256 (256 = full)."""
        ctypes.c_uint32.from_buffer(self._p, 48).value = max(0, min(256, q8))

    def close(self):
        if self._open:
            _lib.peep_close(self._p)
            self._open = False
