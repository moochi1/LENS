;; Some user helper macros
;; Copyright (C) 2007 Dr. John A.R. Williams

;; Author: Dr. John A.R. Williams <J.A.R.Williams@jarw.org.uk>
;; Keywords:

;; This file is part of Lisp Educational Network Simulator (LENS)

;; This is free software released under the GNU General Public License (GPL)
;; See <http://www.gnu.org/copyleft/gpl.html>

;;; Commentary:

;;

;;; Code:

(in-package :lens-user)

(defmacro with-new-instances((&rest defs) &body body)
  "Macro lexically binding variables to instances created using
make-instance.  over the body. defs is a list of definitions. The
first element of the definition is a variable name or a list of
variable names, each bound to a new instance. The rest of the def is
the arguments to pass to make-instance for each variable name."
  `(let (,@(mapcan #'(lambda(def)
			(mapcar
			 #'(lambda(name)
			     `(,name (make-instance ,@(rest def))))
			 (if (listp (car def)) (car def) (list (car def)))))
		     defs))
    ,@body))

(defmacro def-new-instances((&rest defs) &body body)
  "Globall bind variables to instances created using
make-instance.  over the body. defs is a list of definitions. The
first element of the definition is a variable name or a list of
variable names, each bound to a new instance. The rest of the def is
the arguments to pass to make-instance for each variable name."
  `(progn
     ,@(mapcan #'(lambda(def)
		   (mapcar
		    #'(lambda(name)
			`(defparameter ,name (make-instance ,@(rest def))))
		    (if (listp (car def)) (car def) (list (car def)))))
	       defs)
     ,@body
     (values ,@(mapcan
		#'(lambda(def)
		    (if (listp (car def)) (car def) (list (car def))))
		defs))))

(defun duplex-link
    (local-node remote-node &key (link-type *default-link*)
     (local-link-type link-type)
     (remote-link-type link-type)
     local-ipaddr remote-ipaddr local-ipmask remote-ipmask)
  "Connect local-node to remote-node using with a duplex link. Returns
the peer interfaces"
  (flet((get-interface(node link-type ipaddr ipmask)
          (let* ((link (apply #'make-instance
                             (if (listp link-type)
                                 link-type
                                 (list link-type))))
                (interface
                 (or
                  (when ipaddr (node:find-interface ipaddr node))
                  (make-new-interface link :ipaddr ipaddr :ipmask ipmask))))
            (setf (link interface) link
                  (local-interface link) interface)
            (add-interface interface node)
            interface)))
    (let ((local-interface
           (get-interface
            local-node local-link-type local-ipaddr local-ipmask))
          (remote-interface
           (get-interface
            remote-node remote-link-type remote-ipaddr remote-ipmask)))
      (setf (link::peer-interface (link local-interface)) remote-interface
            (link::peer-interface (link remote-interface)) local-interface)
      (values local-interface remote-interface))))

(defun connect(graph &optional (link-type *default-link*))
  (dolist(row graph)
    (let ((src (first row)))
      (unless (typep src 'node) (setf src (node src)))
      (dolist(dst (rest row))
        (unless (typep dst 'node) (setf dst (node dst)))
        (duplex-link src dst :link-type link-type)))))

(defun start-simulation(&key (granularity 10000) step)
  "Start or restart the simulation scheduler. If the optional `foreground`
argument is true the scheduler will run in the current thread, otherwise it
will run on a backgound thread."
  (scheduler::run (scheduler) :granularity granularity :step step))

(defun stop-simulation()
  (scheduler:stop (scheduler) :abort t)
  (format t "~%-- Simulation stopped at ~,4f~%" (simulation-time)))

(defun load-test(name)
  (clear-nodes)
  (reset :all)
  (load (merge-pathnames (make-pathname :name name :type "lisp")
                         #p"/home/willijar/dev/lisp/src/lens/tests/")
        :verbose nil :print nil)
  (format t "~%-- Test ~S loaded~%" name))

;;; topology generation functions and helpers

(defvar *default-ipaddrs*
  (make-instance 'ipaddr-allocator :ipaddr #I"192.168.0.0")
  "Default IP address allocation")

(pushnew
 #'(lambda()
     (setq  *default-ipaddrs*
            (make-instance 'ipaddr-allocator :ipaddr #I"192.168.0.0")))
 *reset-hooks*)

(defun make-nodes(n &optional (ipaddrs *default-ipaddrs*))
  (loop :for i :from 1 :upto n
        :collect (make-instance 'node
                                :ipaddr (when ipaddrs (next-ipaddr ipaddrs)))))

(defun dumbell-topology(n-left n-right &key
                        (ipaddrs (make-instance 'ipaddr-allocator))
                        (left-ipaddrs ipaddrs)
                        (right-ipaddrs left-ipaddrs)
                        (link-type *default-link*)
                        (bottleneck-multiplier 1.0))
  "Create nodes in a dumbell topology where some number of nodes on
the left and right side of the topology communicate through a single
bottleneck link. Creates `n-left` nodes on the left hand side and
`n-right` nodes on the right connected to a left and right router
respectively using the specified link-type. The ip addresses will
be allocated successively using left-ipaddrs and right-ipaddrs.
bottleneck-multiplier is the ratio of the bandwidth of the
bottlenect link to the other links.

Arguments:
- `n-left`: an integer, the number of nodes on the left side of the
- `n-right`: an integer
- `ipaddrs`: an ipaddr-allocator (default default ipaddr-allocator)
- `left-ipaddrs`: an ipaddr-allocator (default ipaddrs)
- `right-ipaddrs`: an ipaddr-allocator (default left-ipaddrs)
- `link-type`: a list of arguments for make-instance
- `bottleneck-multiplier`: a real number

Results:

- `left-nodes`: a list of nodes
- `left-router`: a node
- `right-router`: a node
- `right-nodes`: a list of nodes"
  (let* ((left-router (make-instance 'node :ipaddr (next-ipaddr left-ipaddrs)))
         (left-nodes (make-nodes n-left left-ipaddrs))
         (right-router (make-instance 'node
                                      :ipaddr (next-ipaddr right-ipaddrs)))
         (right-nodes (make-nodes n-right right-ipaddrs)))
    (dolist(n left-nodes)
      (duplex-link n left-router :link-type link-type))
    (dolist(n right-nodes)
      (duplex-link n right-router :link-type link-type))
    (let* ((bottleneck (copy-list link-type))
           (bandwidth (getf (rest bottleneck) :bandwidth *default-bandwidth*)))
      (setf (getf (rest bottleneck) :bandwidth)
            (* bandwidth bottleneck-multiplier))
      (duplex-link left-router right-router :link-type bottleneck))
  (values left-nodes left-router right-router right-nodes)))

(defun star-topology(n-leaf &key (link-type *default-link*) node
                     (ipaddrs (make-instance
                               'ipaddr-allocator
                               :ipaddr (if node
                                           (ipaddr node)
                                           (next-ipaddr (last-ipaddr))))))
  "Create nodes in a star topology. `n-leaf` is the number of leaf
nodes, `node` is an existing node to be used as the core - if nil
a new node will be created as core. The leaf nodes are connected to
the core node using the specified `link-type`. ipaddresses are
allocated using `ipaddrs`.

Arguments:

- `n-leaf`: an integer
- `ipaddrs`: an ipaddr-allocator
- `link-type`: a list of arguments for make-instance
- `node`: a node

Results:

- `leaf-nodes`: a list of nodes
- `core-node`: a node"
  (let ((core (or node (make-instance 'node :ipaddr (next-ipaddr ipaddrs))))
        (leaves (make-nodes n-leaf ipaddrs)))
    (dolist(n leaves)
      (duplex-link n core :link-type link-type))
    (values leaves core)))

;; data analysis

(defun save-data(path data)
  (with-open-file(os path :direction :output
                     :if-exists :overwrite
                     :if-does-not-exist :create)
    (dolist(row data)
      (dolist(n row) (format os " ~12f" n))
      (terpri os))))

(defun linspace(start end &optional (steps 100))
  (loop :for x :from start :to end :by (/ (- end start) steps) :collect x))