import os
from peep import Peep

here = os.path.dirname(os.path.abspath(__file__))
for name in ("test.wav", "test.flac"):
    with open(os.path.join(here, name), "rb") as f:
        p = Peep(f.read())
    total = total_sum = 0
    while True:
        samples = p.read(1024)
        if not samples:
            break
        total += len(samples) // 2
        total_sum += sum(samples)
    p.seek(2205)
    seek_sum = sum(p.read(100))
    print(f"{name} rate={p.rate} channels={p.channels} frames={total} sum={total_sum} seek_sum={seek_sum}")
    p.close()
