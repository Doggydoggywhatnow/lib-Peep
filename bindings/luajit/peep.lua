-- Liberated Peep for LuaJIT (built-in ffi library)
local ffi = require("ffi")

ffi.cdef[[
int    peep_open(void *p, void *codecs, const void *data, size_t len, void *work, size_t work_size);
size_t peep_fill(void *p, void *out, size_t frames);
void   peep_seek(void *p, uint64_t frame);
void   peep_close(void *p);
void  *peep_flac(void);
]]

local dir = (debug.getinfo(1, "S").source:match("^@(.*)[/\\]") or ".")
local name = (ffi.os == "Windows") and "peep.dll" or "libpeep.so"
local lib = ffi.load(os.getenv("PEEP_LIB") or (dir .. "/" .. name))
local FLAC = lib.peep_flac()                       -- address of the FLAC codec table

local Peep = {}
Peep.__index = Peep

-- Peep.new(bytes): bytes is a string holding a WAV or FLAC file
function Peep.new(bytes)
  local self = setmetatable({}, Peep)
  self.len = #bytes
  self.data = ffi.new("uint8_t[?]", self.len)       -- the library reads from this: keep it alive
  ffi.copy(self.data, bytes, self.len)
  self.p = ffi.new("uint8_t[160]")                  -- struct peep (zeroed)
  self.codecs = ffi.new("void*[2]")
  self.codecs[0] = FLAC
  if lib.peep_open(self.p, self.codecs, self.data, self.len, nil, 0) == 0 then
    local need = tonumber(ffi.cast("uint64_t*", self.p + 144)[0])      -- work_need
    if need == 0 then error("not a playable WAV or FLAC file") end
    self.work = ffi.new("uint8_t[?]", need)
    if lib.peep_open(self.p, self.codecs, self.data, self.len, self.work, need) == 0 then
      error("not a playable WAV or FLAC file")
    end
  end
  self.out = ffi.new("int16_t[?]", 4096 * 2)
  return self
end

function Peep:rate()     return tonumber(ffi.cast("uint32_t*", self.p + 40)[0]) end   -- Hz
function Peep:channels() return tonumber(ffi.cast("uint32_t*", self.p + 44)[0]) end   -- channels in the file
function Peep:total()    return tonumber(ffi.cast("uint64_t*", self.p + 32)[0]) end   -- frames, 0 = unknown
function Peep:position() return tonumber(ffi.cast("uint64_t*", self.p + 24)[0]) end   -- frames played so far

-- Up to `frames` stereo frames as a Lua table of interleaved int16 values; empty at the end.
function Peep:read(frames)
  frames = math.min(frames or 1024, 4096)
  local n = tonumber(lib.peep_fill(self.p, self.out, frames))
  local t = {}
  for i = 0, n * 2 - 1 do t[i + 1] = self.out[i] end
  return t
end

function Peep:seek(frame) lib.peep_seek(self.p, frame) end

function Peep:set_gain(q8)                          -- volume 0..256 (256 = full)
  ffi.cast("uint32_t*", self.p + 48)[0] = math.max(0, math.min(256, q8))
end

function Peep:close() lib.peep_close(self.p) end

return Peep
