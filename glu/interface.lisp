;;; -*- Mode: Lisp; indent-tabs-mode: nil -*-
;;;
;;; interface.lisp --- CLOS interface to GLU routines.
;;;
;;; Copyright (c) 2010, Boian Tzonev <boiantz@gmail.com>
;;;   All rights reserved.
;;;
;;; Redistribution and use in source and binary forms, with or without
;;; modification, are permitted provided that the following conditions
;;; are met:
;;;
;;;  o Redistributions of source code must retain the above copyright
;;;    notice, this list of conditions and the following disclaimer.
;;;  o Redistributions in binary form must reproduce the above copyright
;;;    notice, this list of conditions and the following disclaimer in the
;;;    documentation and/or other materials provided with the distribution.
;;;  o Neither the name of the author nor the names of the contributors may
;;;    be used to endorse or promote products derived from this software
;;;    without specific prior written permission.
;;;
;;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
;;; "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
;;; LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
;;; A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT
;;; OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
;;; SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
;;; LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
;;; DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
;;; THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
;;; (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
;;; OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

(in-package #:cl-glu)

;;;; Polygon Tessellation
(defparameter *active-tessellator* nil)

(defparameter *tess-callbacks* '())

(defstruct tess-callback name generic-function callback callback-type arg-count)

(defmacro define-tessellation-callback (name callback-type args &body callback-body)
  (let ((arg-names (mapcar #'car (cdr args)))
        (tessellation-cb (gl::symbolicate "%" name))
        (tessellation-name (intern (symbol-name name) '#:keyword)))
    `(progn
       ;;define generic function
       (defgeneric ,name (,(car args) ,@arg-names))
       ;;define callback
       ,(if callback-body
            `(defcallback ,tessellation-cb :void ,(cdr args)
               ,@callback-body)
            `(defcallback ,tessellation-cb :void ,(cdr args)
               (,name *active-tessellator* ,@arg-names)))
       (push (make-tess-callback :name ,tessellation-name :generic-function #',name 
                                 :callback ',tessellation-cb :callback-type ,callback-type
                                 :arg-count ,(length args))
             *tess-callbacks*))))

(defmacro define-tessellation-callbacks (&body callback-specs)
  `(progn
     (setq *tess-callbacks* '())
     ,@(loop for (name callback-type args) in callback-specs 
          collect `(define-tessellation-callback ,name ,callback-type ,args))))

(define-tessellation-callbacks
  (tess-begin-data-cb :tess-begin-data (tessellator (type :unsigned-int) (polygon-data :pointer)))
  (tess-edge-flag-data-cb :tess-edge-flag (tessellator (flag %gl:boolean) (polygon-data :pointer)))
  (tess-end-data-cb :tess-end-data (tessellator (polygon-data :pointer)))
  (tess-vertex-data-cb :tess-vertex-data (tessellator (vertex-data :pointer) (polygon-data :pointer))
                       ;;TODO need to free vertex-data here
                       )
  (tess-error-data-cb :tess-error-data (tessellator (error-number :unsigned-int) (polygon-data (:pointer :void))))
  (tess-combine-data-cb :tess-combine-data (tessellator (coords (:pointer %gl:double)) 
                                                        (vertex-data (:pointer %gl:double)) 
                                                        (weight (:pointer %gl:float)) 
                                                        (out-data :pointer) 
                                                        (polygon-data :pointer))))

(defclass tessellator ()
  ((glu-tessellator :reader glu-tessellator)))

(defmethod initialize-instance :after ((obj tessellator) &key)
  (let ((tess (new-tess)))
    (if (cffi:null-pointer-p tess)
        (error "Error creating tessellator object")
        (progn
          (setf (slot-value obj 'glu-tessellator) (new-tess))
          (register-callbacks obj)))))
        

;;TODO make polygon-data optional
(defmethod tess-begin-polygon ((tess tessellator) polygon-data)
  (setf *active-tessellator* tess)
  (glu-tess-begin-polygon (glu-tessellator tess) 
                      (or polygon-data (null-pointer))))

(defmethod tess-begin-contour ((tess tessellator))
  (glu-tess-begin-contour (glu-tessellator tess)))

(defmethod tess-vertex ((tess tessellator) coords)
  (glu-tess-vertex (glu-tessellator tess) coords))

(defmethod tess-end-contour ((tess tessellator))
  (glu-tess-end-contour (glu-tessellator tess)))

(defmethod tess-end-polygon ((tess tessellator))
  (glu-tess-end-polygon (glu-tessellator tess)))

(defmethod tess-begin-data-cb ((tess tessellator) which polygon-data)
  (gl:begin which))

(defmethod tess-error-data-cb ((tess tessellator) error-code polygon-data)
  (error "Tessellation error: ~A~%" (error-string error-code)))

(defmethod tess-end-data-cb ((tess tessellator) polygon-data)
  (gl:end))

(defmethod tess-property ((tess tessellator) which value)
  (glu-tess-property (glu-tessellator tess) which value))

(defun register-callbacks (tess)
  (loop for tess-cb in *tess-callbacks*      
     when (compute-applicable-methods 
           (tess-callback-generic-function tess-cb) 
           (cons tess (loop repeat (tess-callback-arg-count tess-cb) collect t)))
     do (progn
          (glu-tess-callback (glu-tessellator tess) 
                             (tess-callback-callback-type tess-cb)
                             (get-callback (tess-callback-callback tess-cb))))))