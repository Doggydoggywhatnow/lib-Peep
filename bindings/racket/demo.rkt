#lang racket/base
(require "peep.rkt" racket/file racket/runtime-path)
(define-runtime-path here ".")

(for ([name '("test.wav" "test.flac")])
  (define pe (open-peep (file->bytes (build-path here name))))
  (define-values (total total-sum)
    (let loop ([total 0] [total-sum 0])
      (define s (peep-read pe 1024))
      (if (null? s)
          (values total total-sum)
          (loop (+ total (quotient (length s) 2)) (+ total-sum (apply + s))))))
  (peep-seek! pe 2205)
  (define seek-sum (apply + (peep-read pe 100)))
  (printf "~a rate=~a channels=~a frames=~a sum=~a seek_sum=~a\n"
          name (peep-rate pe) (peep-channels pe) total total-sum seek-sum)
  (peep-close! pe))
