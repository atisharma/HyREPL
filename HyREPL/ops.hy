;; https://github.com/clojure/tools.nrepl/blob/34093111923031888f8bf6da457aaebc3381d67e/doc/ops.md
;; Incomplete ops:
;; - load-file (file name not handled)
;; - eval

(import sys)
(import hy.models)
(require hyrule [unless defmacro/g! assoc])
(import toolz [first second nth])

(setv ops {})

(defmacro/g! defop [name args desc #*body]
  (unless (or (isinstance name hy.models.String)
              (isinstance name hy.models.Symbol))
    (raise (TypeError "Name must be a symbol or a string.")))
  (unless (isinstance args hy.models.List)
    (raise (TypeError "Arguments must be a list.")))
  (unless (isinstance desc hy.models.Dict)
    (raise (TypeError "Description must be a dictionary.")))
  (setv fn-checked
        `(fn [~@args]
           (print (.format "DEBUG[defop fn-checked]: before check, {}, {}"
                           (.get ~desc "requires" {})
                           (.keys (.get ~desc "requires" {})))
                  :flush True)
           (setv g!failed False)
           (for [g!r (.keys (.get ~desc "requires" {}))]
             (print (.format "DEBUG[defop fn-checked]: g!r: {}" g!r) :flush True)
             (if (in g!r (second ~args))
                 None
                 (do
                   (.write (first ~args)
                           {"status" ["done"]
                            "id" (.get (second ~args) "id")
                            "missing" (str g!r)} (nth 2 ~args))
                   (setv g!failed True)
                   (break))))
           (print (.format "DEBUG[defop fn-checked]: after check, g!failed: {}" g!failed) :flush True)
           (if g!failed
               None
               (do ~@body))))
  (setv n (str name))
  (setv o {:f fn-checked :desc desc})
  `(assoc ops ~n ~o))

(defn find-op [op]
  (print op)
  (if (in op ops)
    (get ops op :f)
    (fn [s m t]
      (print (.format "Unknown op {} called" op) :file sys.stderr)
      (.write s {"status" ["done"] "id" (.get m "id")} t))))

(defop clone [session msg transport]
  {"doc" "Clones a session"
   "requires" {}
   "optional" {"session" "The session to be cloned. If this is left out, the current session is cloned"}
   "returns" {"new-session" "The ID of the new session"}}
  (print "[clone] before load Session")
  (import HyREPL.session [Session]) ; Imported here to avoid circ. dependency
  (let [s (Session)]
    (.write session {"status" ["done"] "id" (.get msg "id") "new-session" (str s)} transport)))


(defop close [session msg transport]
  {"doc" "Closes the specified session"
   "requires" {"session" "The session to close"}
   "optional" {}
   "returns" {}}
  (.write session
          {"status" ["done"]
           "id" (.get msg "id")
           "session" session.uuid}
          transport)
  (import HyREPL.session [sessions]) ; Imported here to avoid circ. dependency
  (try
    (del (get sessions (.get msg "session" "")))
    (except [e KeyError]))
  (.close transport))


(defn make-version [[major 0] [minor 0] [incremental 0]]
  {"major" major
   "minor" minor
   "incremental" incremental
   "version-string" (.join "." (map str [major minor incremental]))})


(defop describe [session msg transport]
  {"doc" "Describe available commands"
   "requires" {}
   "optional" {"verbose?" "True if more verbose information is requested"}
   "returns" {"aux" "Map of auxiliary data"
              "ops" "Map of operations supported by this nREPL server"
              "versions" "Map containing version maps, for example of the nREPL protocol supported by this server"}}
                                ; TODO: don't ignore verbose argument
                                ; TODO: more versions: Python, Hy
  (print "DEBUG: in body of describe" :flush True)
  (.write session
          {"status" ["done"]
           "id" (.get msg "id")
           "versions" {"nrepl" (make-version 0 2 7)
                       "java" (make-version)
                       "clojure" (make-version)}
           "ops" (dfor [k v] (.items ops) k (get v :desc))
           "session" (.get msg "session")}
          transport))


(defop stdin [session msg transport]
       {"doc" "Feeds value to stdin"
       "requires" { "value" "value to feed in" }
       "optional" {}
       "returns" {"status" "\"need-input\" if more input is needed"}}
       (.put sys.stdin (get msg "value"))
       (.task-done sys.stdin))


(defop "ls-sessions" [session msg transport]
       {"doc" "Lists running sessions"
        "requires" {}
        "optional" {}
        "returns" {"sessions" "A list of running sessions"}}
       (import HyREPL.session [sessions]) ; Imported here to avoid circ. dependency
       (.write session
               {"status" ["done"]
                "sessions" (lfor s (.values sessions) s.uuid)
                "id" (.get msg "id")
                "session" session.uuid}
               transport))


(defop "client.init" [session msg transport]
  {"doc" "Inits the Lighttable client"
   "requires" {}
   "optional" {}
   "returns" {"encoding" "edn"
              "data" "Data about supported middleware"}}
  (.write session 
          {"encoding" "edn"
           "data" (+ "{:remote true, :client-id "
                     (str  (get msg "id")) ", :name \"localhost:1337\", "
                     ":dir \"/somehing/something/something/workaroundl\", :type \"lein-light-nrepl\", "
                     ":commands [:editor.eval.clj :editor.clj.doc :editor.cljs.doc "
                     ":editor.clj.hints :editor.cljs.hints :docs.clj.search "
                     ":docs.cljs.search :editor.eval.clj.sonar "
                     ":editor.eval.clj.cancel :editor.eval.cljs :cljs.compile]}")
           "op" "client.settings"
           "status" ["done"]
           "id" (get msg "id")}
          transport))
