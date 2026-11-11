(load (merge-pathnames "peep.lisp" (directory-namestring *load-truename*)))

(defun slurp (path)
  (with-open-file (s path :element-type '(unsigned-byte 8))
    (let ((v (make-array (file-length s) :element-type '(unsigned-byte 8))))
      (read-sequence v s)
      v)))

(dolist (name '("test.wav" "test.flac"))
  (let ((pe (peep:open-peep (slurp (merge-pathnames name (directory-namestring *load-truename*)))))
        (total 0) (total-sum 0))
    (loop for s = (peep:read-peep pe 1024)
          while s
          do (incf total (floor (length s) 2))
             (incf total-sum (reduce #'+ s)))
    (peep:seek-peep pe 2205)
    (let ((seek-sum (reduce #'+ (peep:read-peep pe 100))))
      (format t "~a rate=~d channels=~d frames=~d sum=~d seek_sum=~d~%"
              name (peep:peep-rate pe) (peep:peep-channels pe) total total-sum seek-sum))
    (peep:close-peep pe)))
