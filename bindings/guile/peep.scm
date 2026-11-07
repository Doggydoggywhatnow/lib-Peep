;;; Liberated Peep for GNU Guile ((system foreign), no extra libraries)
(define-module (peep)
  #:use-module (system foreign)
  #:use-module (rnrs bytevectors)
  #:use-module (srfi srfi-9)
  #:export (peep-open peep-read peep-seek peep-set-gain! peep-close
            peep-rate peep-channels peep-total peep-position))

(define here (dirname (current-filename)))
(define lib
  (dynamic-link (or (getenv "PEEP_LIB")
                    (string-append here "/" (if (string-contains %host-type "mingw") "peep.dll" "libpeep.so")))))
(define (fn ret name . args) (pointer->procedure ret (dynamic-func name lib) args))
(define %open  (fn int "peep_open" '* '* '* size_t '* size_t))
(define %fill  (fn size_t "peep_fill" '* '* size_t))
(define %seek  (fn void "peep_seek" '* uint64))
(define %close (fn void "peep_close" '*))
(define %flac  ((fn '* "peep_flac")))                 ; address of the FLAC codec table

(define-record-type <peep> (make-peep p codecs data work out) peep?
  (p peep-p) (codecs peep-codecs) (data peep-data) (work peep-work) (out peep-out))

;; data: a bytevector holding a WAV or FLAC file (it must stay alive: the record keeps it)
(define* (peep-open data #:key (flac #t))
  (let ((p (make-bytevector 160 0))                       ; struct peep
        (codecs (make-bytevector 16 0)))
    (bytevector-u64-native-set! codecs 0 (if flac (pointer-address %flac) 0))
    (let ((out (make-bytevector (* 4096 4) 0)))
      (if (zero? (%open (bytevector->pointer p) (bytevector->pointer codecs) (bytevector->pointer data)
                        (bytevector-length data) %null-pointer 0))
          (let ((need (bytevector-u64-native-ref p 144))) ; work_need
            (when (zero? need) (error "not a playable WAV or FLAC file"))
            (let ((work (make-bytevector need 0)))
              (when (zero? (%open (bytevector->pointer p) (bytevector->pointer codecs) (bytevector->pointer data)
                                  (bytevector-length data) (bytevector->pointer work) need))
                (error "not a playable WAV or FLAC file"))
              (make-peep p codecs data work out)))
          (make-peep p codecs data #f out)))))

(define (peep-rate pe)     (bytevector-u32-native-ref (peep-p pe) 40))   ; Hz
(define (peep-channels pe) (bytevector-u32-native-ref (peep-p pe) 44))   ; channels in the file
(define (peep-total pe)    (bytevector-u64-native-ref (peep-p pe) 32))   ; frames, 0 = unknown
(define (peep-position pe) (bytevector-u64-native-ref (peep-p pe) 24))   ; frames played so far

;; Up to `frames` stereo frames as a list of interleaved int16 values; '() at the end.
(define* (peep-read pe #:optional (frames 1024))
  (let* ((n (%fill (bytevector->pointer (peep-p pe)) (bytevector->pointer (peep-out pe)) (min frames 4096)))
         (out (peep-out pe)))
    (let loop ((i (- (* n 2) 1)) (acc '()))
      (if (< i 0) acc (loop (- i 1) (cons (bytevector-s16-native-ref out (* 2 i)) acc))))))

(define (peep-seek pe frame) (%seek (bytevector->pointer (peep-p pe)) frame))
(define (peep-set-gain! pe q8)                              ; volume 0..256 (256 = full)
  (bytevector-u32-native-set! (peep-p pe) 48 (max 0 (min 256 q8))))
(define (peep-close pe) (%close (bytevector->pointer (peep-p pe))))
