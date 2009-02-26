;; UDP implementation
;; Copyright (C) 2006 Dr. John A.R. Williams

;; Author: Dr. John A.R. Williams <J.A.R.Williams@jarw.org.uk>
;; Keywords:

;; This file is part of Lisp Educational Network Simulator (LENS)

;; This is free software released under the GNU General Public License (GPL)
;; See <http://www.gnu.org/copyleft/gpl.html>

;;; Commentary:

;;

;;; Code:

(defpackage :protocol.udp
  (:nicknames :udp)
  (:use :cl :common :address :protocol.layer4 :queues)
  (:shadowing-import-from :packet #:size)
  (:import-from :ipv4 #:ipv4 #:ipv4-demux #:src-port #:dst-port)
  (:import-from :packet #:packet #:pop-pdu #:push-pdu)
  (:import-from :layer5 #:data #:copy-from-offset)
  (:import-from :layer4 #:buffer-available-p)
  (:import-from :protocol #:layer)
  (:import-from :application #:receive #:sent)
  (:import-from :trace
                 #:default-trace-detail
                 #:eol #:pdu-trace #:write-trace #:write-pdu-slots)
  (:export #:udp
           #:udp-header #:msg-size #:checksum
           #:fid #:seq #:packet-size))

(in-package :protocol.udp)

(defclass udp-header(pdu)
  ((layer4:protocol-number :initform 17 :accessor layer4:protocol-number
                           :allocation :class)
   (src-port :type ipport :initform 0 :accessor src-port :initarg :src-port)
   (dst-port :type ipport :initform 0 :accessor dst-port :initarg :dst-port)
   (msg-size :type word :initform 0 :accessor msg-size :initarg :msg-size)
   (checksum :type word :accessor checksum :initarg :checksum)
   (seq :type seq :initform 0 :accessor seq :initarg :seq
        :documentation "Sequence id's are not part of UDP, but are useful"))
  (:documentation "UDP PDU class"))

(defmethod size((h udp-header)) 8)

(defmethod copy((h udp-header))
  (copy-with-slots h '(src-port dst-port msg-size checksum fid seq)))

(defmethod pdu-trace((pdu udp-header) detail os &key packet text)
  (declare (ignore packet))
  (format os " ~@[~A~] L4-UDP" text)
  (write-pdu-slots
   pdu
   '(src-port dst-port msg-size (checksum "~4,'0X") seq)
   detail
   os))

(defvar *default-udp-packet-size* 512 "Default UDP datagram size")

(defclass udp-pending()
  ((data :initarg :data :reader data)
   (dst-address :initarg :dst-address :reader dst-address)
   (dst-port :initarg :dst-port :reader dst-port)
   (bytes-sent :initform 0 :accessor bytes-sent))
  (:documentation "Record of pending udp requests"))

(defmethod print-object((p udp-pending) stream)
  (print-unreadable-object(p stream :type t :identity t)
    (format stream "~:/print-eng/bytes/~:/print-eng/bytes sent"
            (bytes-sent p) (size (data p)))))

(defclass udp(protocol)
  ((packet-size :initform *default-udp-packet-size*
                :initarg :packet-size :accessor packet-size
                :documentation "Size of packets")
   (seq :type seq :initform 0 :accessor seq
        :documentation "Seq number of next packet")
   (pending-data :type queue :initform (make-instance 'queue)
                 :reader pending-data))
  (:documentation "A  model of the User Datagram Protocol."))

(defmethod layer4:protocol-number((p udp)) 17)

(defmethod default-trace-detail((protocol udp))
  `(src-port dst-port msg-size))

(defmethod notify((protocol udp)) (udp-send-pending protocol))

(defmethod data-indication((protocol udp) node packet dst-address interface)
  (let ((h (pop-pdu packet))
        (application (application protocol)))
    (when node
      (write-trace (node protocol) protocol h nil :packet packet :text "+"))
    (if application
      (receive application packet protocol (seq h)))))

(defmethod send((data data) (protocol udp) &key
                (dst-address (peer-address protocol))
                (dst-port (peer-port protocol)))
  (assert (and dst-address dst-port)
          (dst-address dst-port)
          "send of data to ~A:~A invalid for UDP" dst-address dst-port)
  (assert (or (address= dst-address (peer-address protocol))
              (eql (interface protocol)
                   (layer3:find-interface (layer3:protocol protocol)
                                          (node protocol)
                                          dst-address)))
          (dst-address)
          "UDP using interface ~A cannot send data to ~A"
          (interface protocol) dst-address)
  (insert (make-instance 'udp-pending
                         :data data
                         :dst-port dst-port
                         :dst-address dst-address)
          (pending-data protocol))
  (udp-send-pending protocol))

(defmethod connect((protocol udp) (peer-address ipaddr) (peer-port integer))
  (setf (peer-address protocol) peer-address
        (peer-port protocol) peer-port)
  (let ((application (application protocol)))
    (when application
      (application:connection-complete application protocol))))

(defmethod close-connection((udp udp))
  (application:closed (application udp) udp)
  t)

(defmethod notify((protocol udp)) (udp-send-pending protocol))

(defmethod send((packet packet) (protocol udp) &key
                (dst-address (peer-address protocol))
                (dst-port (peer-port protocol)))
  "Actually send a packet"
  (let ((pdu (make-instance 'udp-header
                            :src-port (local-port protocol)
                            :dst-port dst-port
                            :msg-size (size packet)
                            :seq (incf (seq protocol))))
        (node (node protocol))
        (application (application protocol)))
    (push-pdu pdu packet)
    (when node
      (unless (node:call-callbacks
               (layer protocol) (protocol-number protocol) :tx packet node)
        (return-from send 0))
      (write-trace node protocol pdu nil :packet packet :text "-"))
    (layer3:data-request (layer3:protocol protocol) node packet
                         :dst-address dst-address
                         :ttl (ttl protocol)
                         :protocol-number (protocol-number protocol)
                         :tos (tos protocol))
    (when application
      (sent application (msg-size pdu) protocol))
    (msg-size pdu)))

(defun udp-send-pending(protocol)
  (do ((pd (head (pending-data protocol)) (head (pending-data protocol))))
      ((not pd))
    (let* ((ts (size (data pd)))
           (data
            (if (and (= (bytes-sent pd) 0) (< ts (packet-size protocol)))
                (data pd)
                (copy-from-offset
                 (packet-size protocol) (bytes-sent pd) (data pd) ))))
      (cond
        ((buffer-available-p (size data) protocol)
         ;; if buffer available send data now
         (eol nil)
         (let ((packet (make-packet protocol)))
           (push-pdu data packet)
           (incf (bytes-sent pd) (size data))
           ;; remove pending entry if finished
           (when (= ts (bytes-sent pd))
             (extract-head (pending-data protocol)))
           (send packet protocol
                 :dst-address (dst-address pd) :dst-port (dst-port pd))))
        (t ;; request notification when buffer available
         (request-notification protocol)
         (return))))))

(defmethod reset((udp udp))
  (cancel-notification udp)
  (while (extract-head (pending-data udp))))

(def-singleton-class udp-demux(ipv4:ipv4-demux)
  ((layer4:protocol-number :initform 17 :reader layer4:protocol-number
                           :allocation :class))
  (:documentation "Demultiplexer for UDP protocol"))

(udp-demux) ;; ENsure instance of udp-demux is created