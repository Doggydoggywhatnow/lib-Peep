<?php
// Liberated Peep for PHP (FFI extension)
final class Peep
{
    private static ?FFI $ffi = null;
    private static $flac;

    private static function ffi(): FFI
    {
        if (self::$ffi === null) {
            $name = PHP_OS_FAMILY === 'Windows' ? 'peep.dll' : 'libpeep.so';
            $path = getenv('PEEP_LIB') ?: __DIR__ . DIRECTORY_SEPARATOR . $name;
            if (!is_file($path)) {
                throw new RuntimeException('libpeep not found: run ./build.sh first (or set PEEP_LIB)');
            }
            self::$ffi = FFI::cdef('
                int    peep_open(void *p, void *codecs, const void *data, size_t len, void *work, size_t work_size);
                size_t peep_fill(void *p, void *out, size_t frames);
                void   peep_seek(void *p, uint64_t frame);
                void   peep_close(void *p);
                void  *peep_flac(void);', $path);
            self::$flac = self::$ffi->peep_flac();     // address of the FLAC codec table
        }
        return self::$ffi;
    }

    private $p, $data, $codecs, $work = null, $out;

    /** $bytes: a string holding a WAV or FLAC file */
    public function __construct(string $bytes, bool $flac = true)
    {
        $f = self::ffi();
        $n = strlen($bytes);
        $this->data = FFI::new("uint8_t[$n]");           // the library reads from this: keep it alive
        FFI::memcpy($this->data, $bytes, $n);
        $this->p = FFI::new('uint8_t[160]');             // struct peep
        FFI::memset($this->p, 0, 160);
        $this->codecs = FFI::new('void*[2]');
        $this->codecs[0] = $flac ? self::$flac : null;
        $this->codecs[1] = null;
        if (!$f->peep_open($this->p, $this->codecs, $this->data, $n, null, 0)) {
            $need = $this->u64(144);                      // work_need
            if ($need === 0) {
                throw new InvalidArgumentException('not a playable WAV or FLAC file');
            }
            $this->work = FFI::new("uint8_t[$need]");
            FFI::memset($this->work, 0, $need);
            if (!$f->peep_open($this->p, $this->codecs, $this->data, $n, $this->work, $need)) {
                throw new InvalidArgumentException('not a playable WAV or FLAC file');
            }
        }
        $this->out = FFI::new('uint8_t[' . (4096 * 4) . ']');
    }

    private function u64(int $off): int { return unpack('P', FFI::string($this->p, 160), $off)[1]; }
    private function u32(int $off): int { return unpack('V', FFI::string($this->p, 160), $off)[1]; }

    public function rate(): int     { return $this->u32(40); }   // Hz
    public function channels(): int { return $this->u32(44); }   // channels in the file
    public function total(): int    { return $this->u64(32); }   // frames, 0 = unknown
    public function position(): int { return $this->u64(24); }   // frames played so far

    /** Up to $frames stereo frames as an array of interleaved int16 values; empty at the end. */
    public function read(int $frames = 1024): array
    {
        $n = self::ffi()->peep_fill($this->p, $this->out, min($frames, 4096));
        return $n === 0 ? [] : array_values(unpack('s*', FFI::string($this->out, $n * 4)));
    }

    public function seek(int $frame): void { self::ffi()->peep_seek($this->p, $frame); }

    /** Volume 0..256 (256 = full). */
    public function setGain(int $q8): void
    {
        $q8 = max(0, min(256, $q8));
        $this->p[48] = $q8 & 0xFF;
        $this->p[49] = $q8 >> 8;
    }

    public function close(): void { self::ffi()->peep_close($this->p); }
}
