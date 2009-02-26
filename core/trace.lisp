;; $Id$
;; LENS Global Trace Control
;; Copyright (C) 2007 Dr. John A.R. Williams

;; Author: Dr. John A.R. Williams <J.A.R.Williams@jarw.org.uk>
;; Keywords:

;; This file is part of Lisp Educational Network Simulator (LENS)

;; This is free software released under the GNU General Public License (GPL)
;; See <http://www.gnu.org/copyleft/gpl.html>

;;; Commentary:

;; trace-stream combines the functionality of the tfstream and trace classes
;; in GTNetS
;; Note due to the structure of Lisp streams and IO,
;;; Code:

(in-package :trace)

(deftype trace-status() '(member :enabled :disabled :default))

(defclass trace-stream(fundamental-stream)
  ((os :initarg :stream :reader os :initform *standard-output*)
   (col-index :initform 0 :accessor col-index)
   (node :initform nil :reader node :documentation "Current node")
   (print-time-format
    :initform "~7,3F" :initarg :time-format
    :accessor print-time-format :type string
    :documentation "Format for outputing time in trace")
   (print-ipformat
    :initform :dotted :accessor print-ipformat :initarg :ipformat
    :documentation "How ip addresses are to be printed on this stream")
   (last-log-time
    :initform -1.0 :type time-type :accessor last-log-time
    :documentation "")
   (status :type hash-table :initform (make-hash-table)
           :reader status)
   (detail :type hash-table :initform (make-hash-table)
           :reader detail))
  (:documentation "A packet trace stream"))

(defmethod reset((ts trace-stream))
  (clrhash (status ts))
  (clrhash (detail ts))
  (terpri (os ts))
  (setf (col-index ts) 0)
  (setf (last-log-time ts) (simulation-time)))

(defmethod stream-element-type ((stream trace-stream))
  (stream-element-type (os stream)))

(defmethod close ((stream trace-stream) &key abort)
  (close (os stream) :abort abort))

(defmethod open-stream-p((stream trace-stream))
  (open-stream-p (os stream)))

(defmethod stream-line-column ((stream trace-stream))
  (col-index stream))

(defun check-sim-time(trace-stream)
  (let ((tm (simulation-time))
        (os (os trace-stream)))
    (unless (= tm (last-log-time trace-stream))
      (eol trace-stream))
    (setf (last-log-time trace-stream) tm)
    (when (zerop (col-index trace-stream))
      (let ((msg (format nil "~? N~D"
                         (print-time-format trace-stream)
                         (list tm)
                         (if (node trace-stream)
                             (uid (node trace-stream)) -1))))
        (write-string msg os)
        (setf (col-index trace-stream) (length msg))))))

(defmethod stream-write-char ((stream trace-stream) char)
  (cond
    ((eql char #\newline)
     (terpri (os stream))
     (setf (col-index stream) 0))
    (t (check-sim-time stream)
       (incf  (col-index stream))
       (write-char char (os stream)))))

(defmethod stream-write-sequence((ts trace-stream)
                                 sequence start end
                                 &key &allow-other-keys)
  (declare (type (integer 0 *) start end))
  (check-sim-time ts)
  (let ((os (os ts)))
    (loop :for index :from start :below end
          :for c = (elt sequence index)
          :when (eql c #\newline)
          :do (write-char #\space os)
          :else
          :do (write-char c os)))
  sequence)

(defmethod stream-write-string((ts trace-stream) string &optional start end)
  (stream-write-sequence ts string start end))

(defmethod sb-gray:stream-line-length((ts trace-stream))
  (sb-gray:stream-line-length (os ts)))

(defgeneric (setf node)(node stream)
  (:documentation "CHande node reporting on a trace"))

(defmethod (setf node) (node (ts trace-stream))
  (unless (eql node (node ts))
    (eol ts)
    (setf (slot-value ts 'node) node)))

;; trace status and trace detail are set by node, protocol
;; or protocol layer number

(defvar *lens-trace-output*
  (make-instance 'trace-stream :stream *standard-output*)
  "Global trace stream(s)")

(defun reset-traces() (reset *lens-trace-output*))
(eval-when(:load-toplevel :execute) (pushnew #'reset-traces *reset-hooks*))

(defmethod (setf node)(node (ts list))
  (dolist(s ts) (setf (node s) node)))

(defmethod (setf node)(node (ts (eql nil)))
  (when *lens-trace-output* (setf (node *lens-trace-output*) node)))

(defgeneric trace-status(entity stream)
  (:documentation "Return the trace status for given protocol layer on stream")
  (:method(protocol (stream trace-stream))
    (gethash protocol (status stream) :default)))

(defgeneric (setf trace-status)(value entity stream)
  (:documentation "Set the trace status for given protocol, node or layer")
  (:method(value entity (stream trace-stream))
    (check-type value trace-status)
    (setf (gethash entity (status stream)) value))
  (:method(value entity (streams list))
    (dolist(stream streams) (setf (trace-status entity stream) value)))
  (:method(value entity (stream (eql 'nil)))
    "Set trace status for *lens-trace-output*"
    (when *lens-trace-output*
      (setf (trace-status entity *lens-trace-output*) value))))

;; trace detail is passed to a PDU trace to control its output
;; a value of t means trace everything

(defgeneric default-trace-detail(entity)
  (:documentation "Return the default detail for an entity")
  (:method(entity) nil))

(defgeneric trace-detail(entity stream)
  (:documentation "Return the trace detail for given entity on stream")
  (:method(entity (stream trace-stream))
    "Return the list of all for entity on stream details"
    (or (gethash entity (detail stream))
        (default-trace-detail entity))))

(defgeneric (setf trace-detail)(value protocol stream)
  (:documentation
   "Return the trace  detail for given protocol layer on stream")
  (:method((value list) protocol (stream trace-stream))
    (setf (gethash protocol (detail stream)) value))
  (:method(value protocol (streams list))
    (dolist(stream streams)
      (setf (trace-detail protocol stream) value)))
  (:method(value protocol (streams (eql 'nil)))
    (when *lens-trace-output*
      (setf (trace-detail protocol *lens-trace-output*) value))))

(defun eol(entity)
  (etypecase entity
    (trace-stream (unless (zerop (col-index entity))
                    (write-char #\newline entity)
                    (setf (col-index entity) 0)))
    (null (when *lens-trace-output* (eol *lens-trace-output*)))
    (list (map 'nil #'eol entity))))

(defun write-pdu-slots(pdu slots mask stream)
  "Helper to write the slots of a PDU to stream. mask is the detail mask
specifying which slots to write. slots is a list of either slot names
or a list of slot name and format string"
  (dolist(slot slots)
    (multiple-value-bind(slot format)
        (if (listp slot)
            (values (first slot) (second slot))
            (values slot " ~A"))
      (when (member slot mask)
        (format stream format (slot-value pdu slot))))))

(defun trace-enabled-p(node protocol stream)
  "Determine if tracing enabled for this node,
protocol and pdu on stream. Check is heirarchical - node, protocol and
then layer."
  ;; if no protocol this is a drop
  (when (open-stream-p stream)
    (let ((ts (trace-status node stream)))
      (when (eql ts :default)
        (setf ts (trace-status protocol stream)))
      (when (and protocol (eql ts :default))
        (setf ts (trace-status (layer protocol) stream)))
      (eql ts :enabled))))

(defgeneric pdu-trace(pdu detail stream &key packet text)
  (:documentation "All PDUs should define this method to trace theor
output according to detail onto stream")
  (:method((pdu (eql :drop)) detail stream &key packet text)
    "Trace a packet drop"
    (declare (ignore detail))
    (break)
    (format stream " D-~A ~D" text (uid packet))
    (eol stream))
  (:method((pdu null) detail stream &key packet text)
    (format stream " ~A ~D" text (uid packet))))

(defgeneric write-trace(node protocol pdu stream &key packet text)
  (:documentation "Main entry point to trace a PDU")
  (:method(node protocol pdu (streams list)  &key packet text)
    (dolist(stream streams)
      (write-trace node  protocol pdu stream :packet packet :text text)))
  (:method(node protocol pdu (streams (eql 'nil)) &key packet text)
    (when *lens-trace-output*
      (write-trace node protocol pdu *lens-trace-output*
                   :packet packet :text text)))
  (:method(node protocol pdu (stream trace-stream) &key packet text)
    "Main entry point to trace a PDU on a given node"
    (when (trace-enabled-p node protocol stream)
      (setf (node stream) node)
      (pdu-trace pdu
                 (if protocol (trace-detail protocol stream) nil)
                 stream
                 :packet packet
                 :text text))))
