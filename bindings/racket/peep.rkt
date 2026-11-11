#lang racket/base
;; Liberated Peep for Racket (ffi/unsafe, no extra libraries)
(require ffi/unsafe racket/runtime-path)
(provide open-peep peep-read peep-seek! peep-set-gain! peep-close!
         peep-rate peep-channels peep-total peep-position)

(define-runtime-path here ".")
(define lib
  (ffi-lib (or (getenv "PEEP_LIB")
               (build-path here (if (eq? (system-type) 'windows) "peep.dll" "libpeep.so")))))
(define peep_open  (get-ffi-obj "peep_open" lib (_fun _pointer _pointer _pointer _size _pointer _size -> _int)))
(define peep_fill  (get-ffi-obj "peep_fill" lib (_fun _pointer _pointer _size -> _size)))
(define peep_seek  (get-ffi-obj "peep_seek" lib (_fun _pointer _uint64 -> _void)))
(define peep_close (get-ffi-obj "peep_close" lib (_fun _pointer -> _void)))
(define peep_flac  (get-ffi-obj "peep_flac" lib (_fun -> _pointer)))   ; address of the FLAC codec table

(struct peep (p codecs data work out))

(define (zeroed n) (let ([m (malloc n 'raw)]) (memset m 0 n) m))

;; bytes: a byte string holding a WAV or FLAC file
(define (open-peep bytes #:flac [flac? #t])
  (define n (bytes-length bytes))
  (define data (malloc n 'raw))                       ; the library reads from this: keep it alive
  (memcpy data bytes n)
  (define p (zeroed 160))                             ; struct peep
  (define codecs (zeroed 16))
  (ptr-set! codecs _uint64 'abs 0 (if flac? (cast (peep_flac) _pointer _uint64) 0))
  (define work #f)
  (when (zero? (peep_open p codecs data n #f 0))
    (define need (ptr-ref p _uint64 'abs 144))        ; work_need
    (when (zero? need) (error 'open-peep "not a playable WAV or FLAC file"))
    (set! work (zeroed need))
    (when (zero? (peep_open p codecs data n work need)) (error 'open-peep "not a playable WAV or FLAC file")))
  (peep p codecs data work (zeroed (* 4096 4))))

(define (peep-rate pe)     (ptr-ref (peep-p pe) _uint32 'abs 40))   ; Hz
(define (peep-channels pe) (ptr-ref (peep-p pe) _uint32 'abs 44))   ; channels in the file
(define (peep-total pe)    (ptr-ref (peep-p pe) _uint64 'abs 32))   ; frames, 0 = unknown
(define (peep-position pe) (ptr-ref (peep-p pe) _uint64 'abs 24))   ; frames played so far

;; Up to `frames` stereo frames as a list of interleaved int16 values; '() at the end.
(define (peep-read pe [frames 1024])
  (define n (peep_fill (peep-p pe) (peep-out pe) (min frames 4096)))
  (for/list ([i (in-range (* n 2))]) (ptr-ref (peep-out pe) _int16 i)))

(define (peep-seek! pe frame) (peep_seek (peep-p pe) frame))
(define (peep-set-gain! pe q8)                        ; volume 0..256 (256 = full)
  (ptr-set! (peep-p pe) _uint32 'abs 48 (max 0 (min 256 q8))))
(define (peep-close! pe) (peep_close (peep-p pe)))
