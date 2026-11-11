local dir = (debug.getinfo(1, "S").source:match("^@(.*)[/\\]") or ".")
package.path = dir .. "/?.lua;" .. package.path
local Peep = require("peep")

local function sum(t) local s = 0 for i = 1, #t do s = s + t[i] end return s end

for _, name in ipairs({ "test.wav", "test.flac" }) do
  local f = assert(io.open(dir .. "/" .. name, "rb"))
  local peep = Peep.new(f:read("*a"))
  f:close()
  local total, total_sum = 0, 0
  while true do
    local s = peep:read(1024)
    if #s == 0 then break end
    total = total + #s / 2
    total_sum = total_sum + sum(s)
  end
  peep:seek(2205)
  local seek_sum = sum(peep:read(100))
  print(string.format("%s rate=%d channels=%d frames=%d sum=%d seek_sum=%d",
    name, peep:rate(), peep:channels(), total, total_sum, seek_sum))
  peep:close()
end
