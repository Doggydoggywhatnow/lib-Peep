import peep

proc slurp(path: string): seq[byte] =
  let s = readFile(path)
  result = newSeq[byte](s.len)
  if s.len > 0: copyMem(addr result[0], unsafeAddr s[0], s.len)

for name in ["test.wav", "test.flac"]:
  let p = openPeep(slurp(name))
  var total, sum, seekSum: int64
  while true:
    let s = p.read(1024)
    if s.len == 0: break
    total += s.len div 2
    for v in s: sum += v
  p.seek(2205)
  for v in p.read(100): seekSum += v
  echo name, " rate=", p.rate, " channels=", p.channels, " frames=", total, " sum=", sum, " seek_sum=", seekSum
  p.close()
