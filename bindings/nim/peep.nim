## Liberated Peep for Nim (importc + dynlib, standard library only)
when defined(windows):
  const libName = "peep.dll"
elif defined(macosx):
  const libName = "libpeep.dylib"
else:
  const libName = "libpeep.so"

proc peep_open(p, codecs, data: pointer, len: csize_t, work: pointer, workSize: csize_t): cint {.cdecl, dynlib: libName, importc.}
proc peep_fill(p, outBuf: pointer, frames: csize_t): csize_t {.cdecl, dynlib: libName, importc.}
proc peep_seek(p: pointer, frame: uint64) {.cdecl, dynlib: libName, importc.}
proc peep_close(p: pointer) {.cdecl, dynlib: libName, importc.}
proc peep_flac(): pointer {.cdecl, dynlib: libName, importc.}   # address of the FLAC codec table

type
  Peep* = ref object
    p: array[20, uint64]        # struct peep (160 bytes, 8-aligned)
    data: seq[byte]             # the library reads from this: it must stay alive
    codecs: array[2, pointer]
    work: seq[uint64]
    outBuf: seq[int16]

proc openPeep*(bytes: openArray[byte]): Peep =
  ## `bytes` is a WAV or FLAC file held in memory.
  result = Peep(data: @bytes, outBuf: newSeq[int16](4096 * 2))
  result.codecs[0] = peep_flac()
  let pp = addr result.p[0]
  if peep_open(pp, addr result.codecs[0], addr result.data[0], csize_t(result.data.len), nil, 0) == 0:
    let need = int(result.p[18])            # work_need (offset 144)
    if need == 0: raise newException(ValueError, "not a playable WAV or FLAC file")
    result.work = newSeq[uint64]((need + 7) div 8)
    if peep_open(pp, addr result.codecs[0], addr result.data[0], csize_t(result.data.len),
                 addr result.work[0], csize_t(need)) == 0:
      raise newException(ValueError, "not a playable WAV or FLAC file")

proc rate*(s: Peep): uint32 = uint32(s.p[5] and 0xFFFFFFFF'u64)      # Hz
proc channels*(s: Peep): uint32 = uint32(s.p[5] shr 32)              # channels in the file
proc total*(s: Peep): uint64 = s.p[4]                                # frames, 0 = unknown
proc position*(s: Peep): uint64 = s.p[3]                             # frames played so far

proc read*(s: Peep, frames = 1024): seq[int16] =
  ## Up to `frames` stereo frames as interleaved int16 values; empty at the end.
  let n = int(peep_fill(addr s.p[0], addr s.outBuf[0], csize_t(min(frames, 4096))))
  result = s.outBuf[0 ..< n * 2]

proc seek*(s: Peep, frame: uint64) = peep_seek(addr s.p[0], frame)

proc setGain*(s: Peep, q8: int) =
  ## Volume 0..256 (256 = full).
  s.p[6] = (s.p[6] and not 0xFFFFFFFF'u64) or uint64(max(0, min(256, q8)))

proc close*(s: Peep) = peep_close(addr s.p[0])
