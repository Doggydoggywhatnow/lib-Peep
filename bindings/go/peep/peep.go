// Package peep is Liberated Peep for Go. It uses purego, so it needs no cgo and no C compiler.
package peep

import (
	"encoding/binary"
	"errors"
	"os"
	"path/filepath"
	"runtime"
	"unsafe"

	"github.com/ebitengine/purego"
)

var (
	peepOpen  func(p, codecs, data unsafe.Pointer, n uintptr, work unsafe.Pointer, workSize uintptr) int32
	peepFill  func(p, out unsafe.Pointer, frames uintptr) uintptr
	peepSeek  func(p unsafe.Pointer, frame uint64)
	peepClose func(p unsafe.Pointer)
	peepFlac  func() uintptr
	flac      uintptr // address of the FLAC codec table
)

func init() {
	name := "libpeep.so"
	if runtime.GOOS == "darwin" {
		name = "libpeep.dylib"
	}
	candidates := []string{os.Getenv("PEEP_LIB"), name}
	if exe, err := os.Executable(); err == nil {
		candidates = append(candidates, filepath.Join(filepath.Dir(exe), name))
	}
	var lib uintptr
	var err error
	for _, c := range candidates {
		if c == "" {
			continue
		}
		if abs, e := filepath.Abs(c); e == nil {
			if _, e := os.Stat(abs); e == nil {
				if lib, err = purego.Dlopen(abs, purego.RTLD_NOW|purego.RTLD_GLOBAL); err == nil {
					break
				}
			}
		}
	}
	if lib == 0 {
		panic("libpeep not found: run ./build.sh first (or set PEEP_LIB)")
	}
	purego.RegisterLibFunc(&peepOpen, lib, "peep_open")
	purego.RegisterLibFunc(&peepFill, lib, "peep_fill")
	purego.RegisterLibFunc(&peepSeek, lib, "peep_seek")
	purego.RegisterLibFunc(&peepClose, lib, "peep_close")
	purego.RegisterLibFunc(&peepFlac, lib, "peep_flac")
	flac = peepFlac()
}

// Peep decodes a WAV or FLAC file held in memory into stereo 16-bit samples.
type Peep struct {
	p      []byte // struct peep
	data   []byte // the library reads from this: it must stay alive
	codecs [2]uintptr
	work   []byte
	out    []int16
}

var errBad = errors.New("not a playable WAV or FLAC file")

// New opens a WAV or FLAC file given as bytes.
func New(data []byte) (*Peep, error) {
	if len(data) == 0 {
		return nil, errBad
	}
	s := &Peep{data: append([]byte(nil), data...), p: make([]byte, 160), out: make([]int16, 4096*2)}
	s.codecs[0] = flac
	n := uintptr(len(s.data))
	if peepOpen(unsafe.Pointer(&s.p[0]), unsafe.Pointer(&s.codecs[0]), unsafe.Pointer(&s.data[0]), n, nil, 0) == 0 {
		need := binary.LittleEndian.Uint64(s.p[144:]) // work_need
		if need == 0 {
			return nil, errBad
		}
		s.work = make([]byte, need)
		if peepOpen(unsafe.Pointer(&s.p[0]), unsafe.Pointer(&s.codecs[0]), unsafe.Pointer(&s.data[0]), n,
			unsafe.Pointer(&s.work[0]), uintptr(need)) == 0 {
			return nil, errBad
		}
	}
	runtime.KeepAlive(s)
	return s, nil
}

func (s *Peep) Rate() uint32     { return binary.LittleEndian.Uint32(s.p[40:]) } // Hz
func (s *Peep) Channels() uint32 { return binary.LittleEndian.Uint32(s.p[44:]) } // channels in the file
func (s *Peep) Total() uint64    { return binary.LittleEndian.Uint64(s.p[32:]) } // frames, 0 = unknown
func (s *Peep) Position() uint64 { return binary.LittleEndian.Uint64(s.p[24:]) } // frames played so far

// Read returns up to frames stereo frames as interleaved int16 values; empty at the end.
func (s *Peep) Read(frames int) []int16 {
	if frames > 4096 {
		frames = 4096
	}
	n := peepFill(unsafe.Pointer(&s.p[0]), unsafe.Pointer(&s.out[0]), uintptr(frames))
	runtime.KeepAlive(s)
	return append([]int16(nil), s.out[:n*2]...)
}

// Seek jumps to a frame (clamped to the end).
func (s *Peep) Seek(frame uint64) { peepSeek(unsafe.Pointer(&s.p[0]), frame); runtime.KeepAlive(s) }

// SetGain sets the volume, 0..256 (256 = full).
func (s *Peep) SetGain(q8 int) {
	if q8 < 0 {
		q8 = 0
	}
	if q8 > 256 {
		q8 = 256
	}
	binary.LittleEndian.PutUint32(s.p[48:], uint32(q8))
}

// Close releases the decoder.
func (s *Peep) Close() { peepClose(unsafe.Pointer(&s.p[0])); runtime.KeepAlive(s) }
