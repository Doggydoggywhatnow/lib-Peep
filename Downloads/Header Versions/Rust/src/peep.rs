//! Liberated Peep for Rust: plain `extern "C"` declarations, standard library only.
use std::os::raw::{c_int, c_void};

extern "C" {
    fn peep_open(p: *mut c_void, codecs: *const c_void, data: *const c_void, len: usize, work: *mut c_void, work_size: usize) -> c_int;
    fn peep_fill(p: *mut c_void, out: *mut i16, frames: usize) -> usize;
    fn peep_seek(p: *mut c_void, frame: u64);
    fn peep_close(p: *mut c_void);
    fn peep_flac() -> *const c_void; // address of the FLAC codec table
}

/// Decodes a WAV or FLAC file held in memory into stereo 16-bit samples.
pub struct Peep {
    p: Box<[u64; 20]>,     // struct peep (160 bytes, 8-aligned)
    _data: Vec<u8>,        // the library reads from this: it must stay alive
    _codecs: Box<[usize; 2]>,
    _work: Vec<u64>,
    out: Vec<i16>,
    closed: bool,
}

impl Peep {
    /// Opens a WAV or FLAC file given as bytes.
    pub fn new(data: &[u8]) -> Result<Peep, &'static str> {
        let data = data.to_vec();
        let mut p = Box::new([0u64; 20]);
        let codecs = Box::new([unsafe { peep_flac() } as usize, 0usize]);
        let mut work: Vec<u64> = Vec::new();
        let pp = p.as_mut_ptr() as *mut c_void;
        let ok = unsafe { peep_open(pp, codecs.as_ptr() as *const c_void, data.as_ptr() as *const c_void, data.len(), std::ptr::null_mut(), 0) };
        if ok == 0 {
            let need = p[18] as usize; // work_need (offset 144)
            if need == 0 {
                return Err("not a playable WAV or FLAC file");
            }
            work = vec![0u64; (need + 7) / 8];
            let ok = unsafe { peep_open(pp, codecs.as_ptr() as *const c_void, data.as_ptr() as *const c_void, data.len(), work.as_mut_ptr() as *mut c_void, need) };
            if ok == 0 {
                return Err("not a playable WAV or FLAC file");
            }
        }
        Ok(Peep { p, _data: data, _codecs: codecs, _work: work, out: vec![0i16; 4096 * 2], closed: false })
    }

    fn bytes(&self) -> &[u8] {
        unsafe { std::slice::from_raw_parts(self.p.as_ptr() as *const u8, 160) }
    }
    pub fn rate(&self) -> u32 { u32::from_le_bytes(self.bytes()[40..44].try_into().unwrap()) } // Hz
    pub fn channels(&self) -> u32 { u32::from_le_bytes(self.bytes()[44..48].try_into().unwrap()) } // channels in the file
    pub fn total(&self) -> u64 { self.p[4] } // frames, 0 = unknown
    pub fn position(&self) -> u64 { self.p[3] } // frames played so far

    /// Up to `frames` stereo frames as interleaved i16 values; empty at the end.
    pub fn read(&mut self, frames: usize) -> &[i16] {
        let n = unsafe { peep_fill(self.p.as_mut_ptr() as *mut c_void, self.out.as_mut_ptr(), frames.min(4096)) };
        &self.out[..n * 2]
    }

    pub fn seek(&mut self, frame: u64) { unsafe { peep_seek(self.p.as_mut_ptr() as *mut c_void, frame) } }

    /// Volume 0..256 (256 = full).
    pub fn set_gain(&mut self, q8: u32) {
        let g = q8.min(256) as u64;
        self.p[6] = (self.p[6] & !0xFFFF_FFFFu64) | g; // offset 48
    }

    pub fn close(&mut self) {
        if !self.closed {
            unsafe { peep_close(self.p.as_mut_ptr() as *mut c_void) };
            self.closed = true;
        }
    }
}

impl Drop for Peep {
    fn drop(&mut self) { self.close(); }
}
