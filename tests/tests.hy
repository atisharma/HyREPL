(import os queue socket sys threading time)
(import io [StringIO]
        socketserver [ThreadingMixIn UnixStreamServer TCPServer])

(os.chdir "/Users/wiz/hy/HyREPL/") ; for development

(import HyREPL.bencode [encode decode decode-multiple])
(import HyREPL.server [start-server ReplServer ReplRequestHandler])
(import HyREPL.session [sessions])
(import toolz [first second nth])
(require hyrule [->])

(defreader b
  (setv expr (.parse-one-form &reader))
  `(bytes ~expr "utf-8"))

(defmacro assert-multi [#* cases]
  (let [s (lfor c cases `(assert ~c))]
    `(do ~s)))

(defclass ReplTestServer [TCPServer] ; ThreadingMixIn
  (setv allow-reuse-address True))

(defclass TestServer []
  (defn __init__ [self]
    (print "in TestServer __init__")
    
    (setv self.o sys.stderr)

    ;; Start server
    (setv self.s (ReplTestServer #("127.0.0.1" 1337) ReplRequestHandler))
    (setv self.t (threading.Thread :target (. self s serve-forever)))
    (setv (. self t daemon) True)

    ;; (setv self.s (ReplUnixStreamServer sock ReplRequestHandler))
    ;; (setv self.t (threading.Thread :target (. self s serve-forever)))
    ;; (setv (. self t daemon) True)

    (setv sys.stderr (StringIO))
    None)
  (defn __enter__ [self]
    (print "in TestServer __enter__")
    (.start self.t)
    self)

  (defn __exit__ [self #* args]
    (print "in TestServer __exit__")
    (.shutdown self.s)
    (.server-close self.s)
    (setv sys.stderr self.o)
    (.join self.t)
    ))

(defn soc-send [message [return-reply True]]
  ;; (print (.format "DEBUG[soc-send] message: {}" message) :flush True)
  (let [s (socket.socket :family socket.AF-INET)
        r []]
    (.connect s #("127.0.0.1" 1337))
    ;; (print (.format "DEBUG[soc-send] after connect, s: {}" s)  :flush True)
    (.sendall s (encode message))
    ;; (print (.format "DEBUG[soc-send] after sendall, message: {}" (encode message))  :flush True) ; debug 
    (when return-reply
      (.setblocking s False)
      ;; (print "DEBUG soc-send: after setblocking" :flush True) ; debug 
      (let [buf #b ""]
        (while True
          (try
            (+= buf (.recv s 1024))
            (except [e BlockingIOError]))

          ;; (print "DEBUG[soc-send] after exit first try" :flush True) ; debug 

          ;; 1byteずつ読み取って毎回decodeをtryする、失敗すればcontinueするので常に失敗してると終わらない
          (try
            (setv #(resp rest) (decode buf))
            ;; (print (.format "DEBUG soc-send: resp: {}, rest: {}" resp rest) :flush True) ; debug 
            (except [e Exception]
              ;; (print (.format "DEBUG[soc-send] e: {}" e) :flush True) ; debug
              ;; (print (.format "DEBUG[soc-send] buf: {}" buf) :flush True) ; debug 
              (continue)))
          (setv buf rest)
          (.append r resp)
          (when (in "done" (.get resp "status" []))
            (break)))))
    (.close s)
    r))

(defn test-bencode []
  (let [d {"foo" 42 "spam" [1 2 "a"]}]
    (assert (= d (-> d encode decode first))))

  (let [d {}]
    (assert (= d (-> d encode decode first))))

  (let [d {"requires" {}
           "optional" {"session" "The session to be cloned."}}]
    (assert (= d (-> d encode decode first))))

  (let [d (decode-multiple (+
                             #b"d5:value1:47:session36:31594b80-7f2e-4915-9969-f1127d562cc42:ns2:Hye"
                             #b"d6:statusl4:donee7:session36:31594b80-7f2e-4915-9969-f1127d562cc4e"))]
    (assert-multi
      (= (len d) 2)
      (isinstance (first d) dict)
      (isinstance (second d) dict)
      (= (. d [0] ["value"]) "4")
      (= (. d [0] ["ns"]) "Hy")
      (isinstance (. d [1] ["status"]) list)
      (= (len (. d [1] ["status"])) 1)
      (= (. d [1] ["status"] [0]) "done"))))

(defn test-describe []
  "simple eval
  Example output from the server:
  [{'session': '0361c419-ef89-4a86-ae1a-48388be56041', 'ns': 'Hy', 'value': '4'}, 
               {'status': ['done'], 'session': '0361c419-ef89-4a86-ae1a-48388be56041'}]
  "
  (with [(TestServer)]
    (print "DEBUG[test-describe] after with in test-describe(before soc-send)")
    (let [req {"op" "describe"}
          ret (soc-send req)
          status (first (.get (first ret) "status"))]

      (print (.format "DEBUG[test-describe] req: {}" req) :flush True)
      (print (.format "DEBUG[test-describe] ret: {}" ret) :flush True)
      (print (.format "DEBUG[test-describe] status: {}" status) :flush True)
      
      (assert (= status "done")))))

;; (defn test-interrupt []
;;   (with [(TestServer)]
;;     (print "DEBUG[test-describe] after with in test-describe(before soc-send)")
;;     (let [req {"op" "interrupt"}
;;           ret (soc-send req)
;;           status (first (.get (first ret) "status"))]

;;       (print (.format "DEBUG[test-describe] req: {}" req) :flush True)
;;       (print (.format "DEBUG[test-describe] ret: {}" ret) :flush True)
;;       (print (.format "DEBUG[test-describe] status: {}" status) :flush True)
      
;;       (assert (= status "done")))))

(defn test-code-eval []
  "simple eval
  Example output from the server:
  [{'session': '0361c419-ef89-4a86-ae1a-48388be56041', 'ns': 'Hy', 'value': '4'}, 
   {'status': ['done'], 'session': '0361c419-ef89-4a86-ae1a-48388be56041'}]
  "
  (with [(TestServer)]
    (let [code {"op" "eval" "code" "(+ 2 2)"}
          ret (soc-send code)
          value (first ret)
          status (second ret)]

      (print (.format "DEBUG[test-code-eval] code: {}" code) :flush True)
      (print (.format "DEBUG[test-code-eval] ret: {}" ret) :flush True)
      (print (.format "DEBUG[test-code-eval] status: {}" status) :flush True)

      (assert-multi
        (= (len ret) 2)
        (= (. value ["value"]) "4")
        (in "done" (. status ["status"]))
        (= (. value ["session"]) (. status ["session"]))))

    (let [code {"op" "eval" "code" "(* 3 3)"}
          ret (soc-send code)
          value (first ret)
          status (second ret)]

      (print (.format "DEBUG[test-code-eval] code: {}" code) :flush True)
      (print (.format "DEBUG[test-code-eval] ret: {}" ret) :flush True)
      (print (.format "DEBUG[test-code-eval] status: {}" status) :flush True)

      (assert-multi
        (= (len ret) 2)
        (= (. value ["value"]) "9")
        (in "done" (. status ["status"]))
        (= (. value ["session"]) (. status ["session"])))

      (setv session-id (. status ["session"]))
      (print (.format "DEBUG[test-code-eval] session-id: {}" session-id) :flush True)
      (soc-send {"op" "interrupt" "session" session-id})
      )))


(defn test-stdout-eval []
  "stdout eval
  Example output from the server:
  [{'session': '2d6b48d8-4a3e-49a6-9131-3321a11f70d4', 'ns': 'Hy', 'value': 'None'},
               {'session': '2d6b48d8-4a3e-49a6-9131-3321a11f70d4', 'out': 'Hello World\n'},
               {'status': ['done'], 'session': '2d6b48d8-4a3e-49a6-9131-3321a11f70d4'}]
  "
  (with [(TestServer)]
    (let [code {"op" "eval" "code" "(print \"Hello World\")"}
          ret (soc-send code)
          value (first ret)
          out (second ret)
          status (nth 2 ret)]
      (assert-multi
            (= (len ret) 3)
            (= (. value ["value"]) "None")
            (= (. out ["out"]) "Hello World\n")
            (in "done" (. status ["status"]))
            (= (. value ["session"]) (. out ["session"]) (. status ["session"]))))))


(defn stdin-send [code my-queue]
  (.put my-queue (soc-send code)))


(defn test-stdin-eval []
    "stdin eval
    The current implementation will send all the responses back
    into the first thread which dispatched the (def...), so we throw
    it into a thread and add a Queue to get it.
    Bad hack. But it works.

    Example output from the server:
        [{'status': ['need-input'], 'session': 'ec100813-8e76-4d69-9116-6460c1db4428'},
         {'session': 'ec100813-8e76-4d69-9116-6460c1db4428', 'ns': 'Hy', 'value': 'test'},
         {'status': ['done'], 'session': 'ec100813-8e76-4d69-9116-6460c1db4428'}]
    "
    (with [(TestServer)]
      (let [my-queue (queue.Queue)
            code {"op" "eval" "code" "(def a (input))"}
            t (threading.Thread :target stdin-send :args [code my-queue])]
            (.start t)
            ; Might encounter a race condition where
            ; we send stdin before we eval (input)
            (time.sleep 0.5)

            (soc-send {"op" "stdin" "value" "test"} :return-reply False)

            (.join t)

        (let [ret (.get my-queue)
              input-request (first ret)
              value (second ret)
              status (nth 2 ret)]
          (assert-multi
            (= (len ret) 3)
            (= (. value ["value"]) "test")
            (= (. input-request ["status"]) ["need-input"])
            (in "done" (. status ["status"]))
            (= (. value ["session"]) (. input-request ["session"]) (. status ["session"])))))))
