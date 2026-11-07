const fs = require('fs');
const path = require('path');
const { Peep } = require('./peep');

const sum = (a) => a.reduce((s, v) => s + v, 0);
for (const name of ['test.wav', 'test.flac']) {
  const peep = new Peep(fs.readFileSync(path.join(__dirname, name)));
  let total = 0, total_sum = 0;
  for (;;) {
    const s = peep.read(1024);
    if (s.length === 0) break;
    total += s.length / 2;
    total_sum += sum(s);
  }
  peep.seek(2205);
  const seek_sum = sum(peep.read(100));
  console.log(`${name} rate=${peep.rate} channels=${peep.channels} frames=${total} sum=${total_sum} seek_sum=${seek_sum}`);
  peep.close();
}
