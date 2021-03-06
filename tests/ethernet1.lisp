(in-package :lens-user)

(clear-nodes)
(reset :all)

;; make 4 nodes on an ethernet connected to 1 destination node
(defparameter gateway (make-instance 'node))
(defparameter lan-nodes (make-nodes 3 nil))
(defparameter ethernet (make-instance
                  'ethernet:ethernet
                  :nodes lan-nodes
                  :gateway gateway
                  :ipaddr #I"192.168.100.0"
                  :ipmask (ipmask 24)))
(defparameter dst (first (make-nodes 1)))
(duplex-link gateway dst)

(dolist(n '(0 1 4))
  (setf (trace-status (node n) *lens-trace-output*) :enabled))

;; notify routing of new topology
(topology-changed)

;; put udp layer at either end and send 100 kbytes from one to the other
(defparameter udp0
  (make-instance 'udp
                 :node (node 1)
                 :peer-address (ipaddr (node 4))
                 :peer-port 20000))

(defparameter udp1
  (make-instance 'udp :node (node 4)))


(layer4:bind udp1 :port 20000)
(layer4:send 1500 udp0)

;; schedule simulation to stop after 10 seconds
;; (schedule 10 #'stop-simulation)

;; run the scheduler
;;(start-simulation t)


