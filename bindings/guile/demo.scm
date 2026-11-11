(use-modules (peep) (ice-9 binary-ports) (ice-9 format) (srfi srfi-1))

(define here (dirname (current-filename)))
(define (slurp path) (call-with-input-file path get-bytevector-all #:binary #t))
(define (sum lst) (fold + 0 lst))

(for-each
 (lambda (name)
   (let ((pe (peep-open (slurp (string-append here "/" name)))))
     (let loop ((total 0) (total-sum 0))
       (let ((s (peep-read pe 1024)))
         (if (null? s)
             (begin
               (peep-seek pe 2205)
               (let ((seek-sum (sum (peep-read pe 100))))
                 (format #t "~a rate=~d channels=~d frames=~d sum=~d seek_sum=~d~%"
                         name (peep-rate pe) (peep-channels pe) total total-sum seek-sum)
                 (peep-close pe)))
             (loop (+ total (quotient (length s) 2)) (+ total-sum (sum s))))))))
 '("test.wav" "test.flac"))
