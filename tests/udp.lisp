(in-package :lens-user)

(clear-nodes)
(reset :all)

;; make 6 nodes with successive ip addresses
(make-nodes 6)
;(dotimes(x 6) (setf (trace-status (node x) *lens-trace-output*) :enabled))
(setf (trace-status (node 0) *lens-trace-output*) :enabled)
(setf (trace-status (node 5) *lens-trace-output*) :enabled)
;; connect them all in a row using default links
(connect '((0 1)
           (1 2)
           (2 3)
           (3 4)
           (4 5)))

;; notify routing of new topology
(topology-changed)

;; put udp layer at either end and send 100 kbytes from one to the other
(defparameter udp0
  (make-instance 'udp
                 :node (node 0)
                 :peer-address (ipaddr (node 5))
                 :peer-port 20000))

(defparameter udp1
  (make-instance 'udp :node (node 5)))

(setf (interface:limit-bytes
       (interface:queue (aref (interfaces (node 0)) 0)))
      1000)

(layer4:bind udp1 :port 20000)
(layer4:send 1500 udp0)

;; schedule simulation to stop after 10 seconds
;; (schedule 10 #'stop-simulation)

;; run the scheduler
;;(start-simulation t)

