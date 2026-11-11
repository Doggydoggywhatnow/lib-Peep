import { Peep } from "./peep.js";
import { join, dirname } from "node:path";

const here = dirname(new URL(import.meta.url).pathname);
const sum = (a) => a.reduce((s, v) => s + v, 0);
for (const name of ["test.wav", "test.flac"]) {
  const peep = new Peep(await Bun.file(join(here, name)).bytes());
  let total = 0, totalSum = 0;
  for (;;) {
    const s = peep.read(1024);
    if (s.length === 0) break;
    total += s.length / 2;
    totalSum += sum(s);
  }
  peep.seek(2205);
  const seekSum = sum(peep.read(100));
  console.log(`${name} rate=${peep.rate} channels=${peep.channels} frames=${total} sum=${totalSum} seek_sum=${seekSum}`);
  peep.close();
}
