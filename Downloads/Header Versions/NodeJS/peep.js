// Liberated Peep for Node.js (koffi)
'use strict';
const fs = require('fs');
const path = require('path');
const koffi = require('koffi');

const name = process.platform === 'win32' ? 'peep.dll' : 'libpeep.so';
const libPath = process.env.PEEP_LIB || path.join(__dirname, name);
if (!fs.existsSync(libPath)) throw new Error('libpeep not found: run ./build.sh first (or set PEEP_LIB)');
const lib = koffi.load(libPath);
const peep_open = lib.func('int peep_open(void *p, void *codecs, void *data, size_t len, void *work, size_t work_size)');
const peep_fill = lib.func('size_t peep_fill(void *p, void *out, size_t frames)');
const peep_seek = lib.func('void peep_seek(void *p, uint64_t frame)');
const peep_close = lib.func('void peep_close(void *p)');
const peep_flac = lib.func('void *peep_flac(void)');
const FLAC = koffi.address(peep_flac());          // address of the FLAC codec table

class Peep {
  // data: a Buffer holding a WAV or FLAC file
  constructor(data, { flac = true } = {}) {
    this.data = Buffer.from(data);                  // the library reads from this: keep it alive
    this.p = Buffer.alloc(160);                     // struct peep
    this.codecs = Buffer.alloc(16);
    this.codecs.writeBigUInt64LE(flac ? FLAC : 0n, 0);
    this.work = null;
    if (!peep_open(this.p, this.codecs, this.data, this.data.length, null, 0)) {
      const need = Number(this.p.readBigUInt64LE(144));        // work_need
      if (!need) throw new Error('not a playable WAV or FLAC file');
      this.work = Buffer.alloc(need);
      if (!peep_open(this.p, this.codecs, this.data, this.data.length, this.work, need)) {
        throw new Error('not a playable WAV or FLAC file');
      }
    }
    this.out = Buffer.alloc(4096 * 4);
  }
  get rate() { return this.p.readUInt32LE(40); }                       // Hz
  get channels() { return this.p.readUInt32LE(44); }                   // channels in the file
  get total() { return Number(this.p.readBigUInt64LE(32)); }           // frames, 0 = unknown
  get position() { return Number(this.p.readBigUInt64LE(24)); }        // frames played so far

  // Up to `frames` stereo frames as an Int16Array of interleaved samples; empty at the end.
  read(frames = 1024) {
    const n = Number(peep_fill(this.p, this.out, Math.min(frames, 4096)));
    const samples = new Int16Array(n * 2);
    for (let i = 0; i < n * 2; i++) samples[i] = this.out.readInt16LE(i * 2);
    return samples;
  }
  seek(frame) { peep_seek(this.p, frame); }
  setGain(q8) { this.p.writeUInt32LE(Math.max(0, Math.min(256, q8)), 48); }   // 0..256, 256 = full
  close() { peep_close(this.p); }
}

module.exports = { Peep };
