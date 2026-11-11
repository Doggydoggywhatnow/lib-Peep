;;; Liberated Peep for Common Lisp (SBCL sb-alien, no libraries needed)
(defpackage :peep
  (:use :cl)
  (:export #:open-peep #:read-peep #:seek-peep #:set-peep-gain #:close-peep
           #:peep-rate #:peep-channels #:peep-total #:peep-position))
(in-package :peep)

(defvar *here* (directory-namestring (or *load-truename* *default-pathname-defaults*)))
(sb-alien:load-shared-object
 (or (sb-ext:posix-getenv "PEEP_LIB") (concatenate 'string *here* "libpeep.so")))

(sb-alien:define-alien-routine ("peep_open" %open) sb-alien:int
  (p sb-sys:system-area-pointer) (codecs sb-sys:system-area-pointer) (data sb-sys:system-area-pointer)
  (len sb-alien:unsigned-long) (work sb-sys:system-area-pointer) (work-size sb-alien:unsigned-long))
(sb-alien:define-alien-routine ("peep_fill" %fill) sb-alien:unsigned-long
  (p sb-sys:system-area-pointer) (out sb-sys:system-area-pointer) (frames sb-alien:unsigned-long))
(sb-alien:define-alien-routine ("peep_seek" %seek) sb-alien:void
  (p sb-sys:system-area-pointer) (frame sb-alien:unsigned-long))
(sb-alien:define-alien-routine ("peep_close" %close) sb-alien:void
  (p sb-sys:system-area-pointer))
(sb-alien:define-alien-routine ("peep_flac" %flac) sb-sys:system-area-pointer)

(defstruct (peep (:constructor %make-peep (p codecs data work out)))
  p codecs data work out)

(defun zeroed (n)
  (let ((sap (sb-alien:alien-sap (sb-alien:make-alien (sb-alien:unsigned 8) n))))
    (dotimes (i n sap) (setf (sb-sys:sap-ref-8 sap i) 0))))

(defun open-peep (bytes &key (flac t))
  "BYTES: a (vector (unsigned-byte 8)) holding a WAV or FLAC file."
  (let* ((n (length bytes))
         (data (zeroed n)) (p (zeroed 160)) (codecs (zeroed 16)) (work nil))
    (dotimes (i n) (setf (sb-sys:sap-ref-8 data i) (aref bytes i)))   ; the library reads from this
    (setf (sb-sys:sap-ref-64 codecs 0) (if flac (sb-sys:sap-int (%flac)) 0))
    (when (zerop (%open p codecs data n (sb-sys:int-sap 0) 0))
      (let ((need (sb-sys:sap-ref-64 p 144)))                          ; work_need
        (when (zerop need) (error "not a playable WAV or FLAC file"))
        (setf work (zeroed need))
        (when (zerop (%open p codecs data n work need)) (error "not a playable WAV or FLAC file"))))
    (%make-peep p codecs data work (zeroed (* 4096 4)))))

(defun peep-rate (pe)     (sb-sys:sap-ref-32 (peep-p pe) 40))   ; Hz
(defun peep-channels (pe) (sb-sys:sap-ref-32 (peep-p pe) 44))   ; channels in the file
(defun peep-total (pe)    (sb-sys:sap-ref-64 (peep-p pe) 32))   ; frames, 0 = unknown
(defun peep-position (pe) (sb-sys:sap-ref-64 (peep-p pe) 24))   ; frames played so far

(defun read-peep (pe &optional (frames 1024))
  "Up to FRAMES stereo frames as a list of interleaved int16 values; NIL at the end."
  (let ((n (%fill (peep-p pe) (peep-out pe) (min frames 4096))))
    (loop for i below (* n 2) collect (sb-sys:signed-sap-ref-16 (peep-out pe) (* 2 i)))))

(defun seek-peep (pe frame) (%seek (peep-p pe) frame))
(defun set-peep-gain (pe q8)                                  ; volume 0..256 (256 = full)
  (setf (sb-sys:sap-ref-32 (peep-p pe) 48) (max 0 (min 256 q8))))
(defun close-peep (pe) (%close (peep-p pe)))
