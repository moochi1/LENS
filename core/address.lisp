;; $Id: address.lisp,v 1.2 2007/11/10 10:45:02 willijar Exp willijar $
;; Internet Address and Mask functionality
;; Copyright (C) 2007 Dr. John A.R. Williams

;; Author: Dr. John A.R. Williams <J.A.R.Williams@jarw.org.uk>
;; Keywords:

;; This file is part of Lisp Educations Network Simulator (LENS)

;; This is free software released under the GNU General Public License (GPL)
;; See <http://www.gnu.org/copyleft/gpl.html>

;;; Commentary:

;; address and mask classes
;; All address classes should be invariant so instances can be shared.

;; classname returns instance associated with entity or creates a new address
;; address= will return true if two addresses match
;; address< enables address sorting in a consistent way
;; next-address will return the next address along in a sequence

;;; Code:

(in-package :address)

(defvar *print-ip-format* :dotted
  "Default format for printing ip addresses")

(defgeneric print-ip-format(stream)
  (:documentation "Format control for print ip addresses to a
stream. Can be :dotted for dotted format, a number to output in a
given base or nil which will output as a default unreadable
object. Used only if *print-readably* is false as a reader for ip
addresses is defined.")
  (:method(stream) (declare (ignore stream)) *print-ip-format*))

(defconstant +broadcast+ #xFFFFFFFF)
(defconstant +ip-addr-size+ 32)

;; 32bit ip and mac addresses, 16bit port addresses
(deftype ip () '(unsigned-byte 32))
(deftype mac () '(unsigned-byte 32))
(deftype ipport() '(unsigned-byte 16))

(define-condition address-condition(condition)
  ())

(define-condition address-out-of-range(address-condition error)
  ((addr :initarg :addr :reader addr)
   (subnet :initarg :subnet :initform nil :reader error-subnet))
  (:report (lambda(c s)
             (format s "Address ~S out of range ~@[for subnet ~S~]"
                     (addr c) (error-subnet c)))))

(defun dotted-to-ipaddr (dotted)
  "String --> number."
  (declare (string dotted))
  (let ((ll (mapcar #'parse-integer (split-sequence #\. dotted :count 4))))
    (+ (ash (first ll) 24) (ash (second ll) 16)
       (ash (third ll) 8) (fourth ll))))

(defun ipaddr-to-dotted (ipaddr)
  "ipaddr --> string."
  (declare (type ip ipaddr))
  (format nil "~d.~d.~d.~d"
          (logand #xff (ash ipaddr -24)) (logand #xff (ash ipaddr -16))
          (logand #xff (ash ipaddr -8)) (logand #xff ipaddr)))

(defclass ipaddr()
  ((ip :initarg :ip :type ip :reader ip
       :documentation "Actual 32bit stored value"))
  (:documentation "An IP Address"))

(defmethod make-load-form((ipaddr ipaddr) &optional environment)
  (make-load-form-saving-slots ipaddr :environment environment))

(defgeneric ipaddr(entity)
  (:documentation "Make and return an ip address.")
  (:method((ip integer))
    (assert (typep ip 'ip)
            (ip)
            'address-out-of-range :addr ip)
    (make-instance 'ipaddr :ip ip))
  (:method((dotted string))
    (make-instance 'ipaddr :ip (dotted-to-ipaddr dotted)))
  (:method((ip (eql :broadcast)))
    (make-instance 'ipaddr :ip +broadcast+)))

(defmethod print-object((addr ipaddr) stream)
  (let ((format (print-ip-format stream)))
    (cond
      (*print-escape*
       (format stream "#I\"~A\"" (ipaddr-to-dotted (ip addr))))
      ((eql format :dotted)
       (write-string (ipaddr-to-dotted (ip addr)) stream))
      ((integerp format)
       (write (ip addr) :stream stream :base format))
      (t
       (print-unreadable-object (addr stream :type t :identity t)
         (princ (ipaddr-to-dotted (ip addr)) stream))))))

(defclass ipmask()
  ((mask :initform #xFFFFFFFF
         :initarg :mask :type ip :reader mask
         :documentation "Actual 32 bit stored value")
   (bitcount :initarg :bitcount :reader bitcount))
  (:documentation "An IP Mask"))

(defmethod make-load-form((ipmask ipmask) &optional env)
  (declare (ignore env))
  `(ipmask ,(bitcount ipmask)))

(defmethod bitcount((mask null)) 32)

(defmethod print-object((mask ipmask) stream)
  (if *print-escape*
      (print-unreadable-object (mask stream :type t :identity t)
        (write (mask mask) :stream stream :base 16))
      (write (mask mask) :stream stream :base 16)))

;; we keep a static array of all 32 ipmasks
(defvar *ipmasks*
  (let ((array (make-array (1+ +ip-addr-size+))))
    (let ((m #xFFFFFFFF00000000))
      (loop :for c :from 1 :upto +ip-addr-size+
            :do (setf (aref array c)
                      (make-instance 'ipmask
                                     :bitcount c
                                     :mask (ldb (byte 32 0) (ash m (- c)))))))
    array)
  "Static array of all 32 ipmasks")

(defgeneric ipmask(entity)
  (:documentation "Construct an ipmask from entity")
  (:method((nobits integer)) (aref *ipmasks* nobits))
  (:method((s string)) (aref *ipmasks* (parse-integer s :radix 16))))

(defun subnet(ipaddr mask)
  (if mask
      (make-instance 'ipaddr :ip (logand (mask mask) (ip ipaddr)))
      ipaddr))

(defgeneric broadcast-p(addr)
  (:documentation "Return true if a broadcast address")
  (:method ((ipaddr ipaddr)) (= +broadcast+ (ip ipaddr))))

(defun read-address(in &optional char arg)
  (declare (ignore char arg))
  (ipaddr (read in t nil t)))


(defgeneric address=(a b)
  (:documentation "Return true if addresses the same (up to mask if provided")
  (:method((a ipaddr) (b ipaddr))
    (or (eql a b) (= (ip a) (ip b)))))

(defgeneric address<(a b)
  (:documentation "Return true if address a<b")
  (:method((a ipaddr) (b ipaddr))
    (< (ip a) (ip b))))

(defclass macaddr()
  ((mac :type mac :reader mac :initarg :mac)
   (nextmac :initform 0 :allocation :class :type mac))
  (:documentation "A class for managing mac addresses"))

(defmethod make-load-form((macaddr macaddr) &optional env)
  (declare (ignore env))
  `(make-instance 'macaddr :mac ,(mac macaddr)))

(defmethod initialize-instance :after ((addr macaddr)
                                       &key mac &allow-other-keys)
  (setf (slot-value addr 'mac)
        (cond
          ((or (not mac) (eql mac :next))
           (incf (slot-value addr 'nextmac)))
          ((numberp mac)
           (check-type mac mac)
           (setf (slot-value addr 'nextmac)
                 (max mac (slot-value addr 'nextmac)))
           mac)
          ((eql mac :broadcast) +broadcast+)
          (t (error "Invalid Mac Address specification ~S" mac)))))

(defgeneric macaddr(arg)
  (:documentation "Create a mac address entity. May be aliased")
  (:method(mac) (make-instance 'macaddr :mac mac)))

(defmethod print-object((addr macaddr) stream)
  (if *print-escape*
      (print-unreadable-object (addr stream :type t :identity t)
        (write (mac addr) :stream stream :base 16))
      (write (mac addr) :stream stream :base 16)))

(defmethod broadcast-p ((addr macaddr)) (= (mac addr) +broadcast+))

(defmethod address=((a macaddr) (b macaddr))
  (or (eql a b) (= (mac a) (mac b))))

(defmethod address<((a macaddr) (b macaddr)) (< (mac a) (mac b)))

(defgeneric src-address(entity)
  (:documentation "Return the source address on an entity"))

(defgeneric dst-address(entity)
  (:documentation "Return the destination address of an entity"))

(defgeneric next-ipaddr(current &optional mask increment)
  (:documentation "Return a new ipaddress by incrementing current by
increment, and return provided it is in the subnet made up of mask and
current")
  (:method ((ipaddr ipaddr) &optional mask (increment 1))
    "Return the next ipaddr (optionally in subnet given by subnet mask).
Throws an error if next address would be out of range"
    (let ((next (ipaddr (+ (if (integerp increment) increment (ip increment))
                         (ip ipaddr)))))
    (when mask
      (let ((subnet (subnet ipaddr mask)))
        (assert (address= (subnet next mask) subnet)
                (next)
                'address-out-of-range
                :addr next
                :subnet subnet)))
    next)))

(set-dispatch-macro-character #\# #\I #'read-address)

(defun last-ipaddr(&optional (nodes (node:nodes)))
  (if (> (length nodes) 0)
      (reduce #'(lambda(a b) (if (> (address::ip a) (address::ip b)) a b))
              (mapcan #'identity
                      (map 'list #'node:ipaddrs nodes)))
      (ipaddr "192.168.0.0")))

(defclass ipaddr-allocator()
  ((ipaddr :type ipaddr :initarg :ipaddr
           :initform (last-ipaddr)
           :accessor ipaddr)
   (mask :type ipmask :initarg :ipmask :initform nil :reader ipmask)
   (increment :initform 1 :initarg :increment :reader increment)))

(defmethod print-object((a ipaddr-allocator) stream)
  (print-unreadable-object (a stream :type t :identity t)
    (format stream "~A~@[/~A~] ~D" (ipaddr a) (ipmask a) (increment a))))

(defmethod next-ipaddr((a ipaddr-allocator) &optional
                        (mask (ipmask a)) (increment (increment a)))
  (setf (ipaddr a) (next-ipaddr (ipaddr a) mask increment)))