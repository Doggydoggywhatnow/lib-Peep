// Liberated Peep for Bun (bun:ffi)
import { dlopen, FFIType, ptr } from "bun:ffi";
import { existsSync } from "node:fs";
import { join, dirname } from "node:path";

const name = process.platform === "win32" ? "peep.dll" : "libpeep.so";
const libPath = process.env.PEEP_LIB || join(dirname(new URL(import.meta.url).pathname), name);
if (!existsSync(libPath)) throw new Error("libpeep not found: run ./build.sh first (or set PEEP_LIB)");

const { symbols: lib } = dlopen(libPath, {
  peep_open: { args: [FFIType.ptr, FFIType.ptr, FFIType.ptr, FFIType.u64, FFIType.ptr, FFIType.u64], returns: FFIType.i32 },
  peep_fill: { args: [FFIType.ptr, FFIType.ptr, FFIType.u64], returns: FFIType.u64 },
  peep_seek: { args: [FFIType.ptr, FFIType.u64], returns: FFIType.void },
  peep_close: { args: [FFIType.ptr], returns: FFIType.void },
  peep_flac: { args: [], returns: FFIType.ptr },
});
const FLAC = lib.peep_flac();                       // address of the FLAC codec table

export class Peep {
  // data: a Uint8Array holding a WAV or FLAC file
  constructor(data, { flac = true } = {}) {
    this.data = new Uint8Array(data);               // the library reads from this: keep it alive
    this.p = new Uint8Array(160);                   // struct peep
    this.view = new DataView(this.p.buffer);
    this.codecs = new BigUint64Array(2);
    this.codecs[0] = flac ? BigInt(FLAC) : 0n;
    this.work = null;
    if (!lib.peep_open(ptr(this.p), ptr(this.codecs), ptr(this.data), this.data.length, null, 0)) {
      const need = Number(this.view.getBigUint64(144, true));   // work_need
      if (!need) throw new Error("not a playable WAV or FLAC file");
      this.work = new Uint8Array(need);
      if (!lib.peep_open(ptr(this.p), ptr(this.codecs), ptr(this.data), this.data.length, ptr(this.work), need)) {
        throw new Error("not a playable WAV or FLAC file");
      }
    }
    this.out = new Int16Array(4096 * 2);
  }
  get rate() { return this.view.getUint32(40, true); }                    // Hz
  get channels() { return this.view.getUint32(44, true); }                // channels in the file
  get total() { return Number(this.view.getBigUint64(32, true)); }        // frames, 0 = unknown
  get position() { return Number(this.view.getBigUint64(24, true)); }     // frames played so far

  // Up to `frames` stereo frames as an Int16Array of interleaved samples; empty at the end.
  read(frames = 1024) {
    const n = Number(lib.peep_fill(ptr(this.p), ptr(this.out), Math.min(frames, 4096)));
    return this.out.slice(0, n * 2);
  }
  seek(frame) { lib.peep_seek(ptr(this.p), frame); }
  setGain(q8) { this.view.setUint32(48, Math.max(0, Math.min(256, q8)), true); }   // 0..256, 256 = full
  close() { lib.peep_close(ptr(this.p)); }
}
