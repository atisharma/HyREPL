;; Inspired by
;; https://github.com/clojure-emacs/cider-nrepl/blob/master/src/cider/nrepl/middleware/complete.clj

(import sys re)

(import
  hy.macros
  hy.compiler
  hy.completer [Completer]
  hy.models [Symbol])

(import toolz [first second])

(import HyREPL.ops [ops])
(require HyREPL.ops [defop])

(defn make-type [item [override-type None]]
  (let [t (type item)]
    (cond
      (and (is-not override-type None)
           (= t (. make-type __class__)))
      override-type

      (= t (. dir __class__))
      "function"

      (= t dict)
      "namespace"

      True
      (. t __name__))))

(defclass TypedCompleter [hy.completer.Completer]
  (defn attr-matches [self text]
    (setv m (re.match r"(\S+(\.[\w-]+)*)\.([\w-]*)$" text))
    (print "m: " m)
    (print "namespace: " (. self namespace))
    (print (dir (. self namespace)))
    (try
      (let [groups (.group m 1 3)
            expr (.replace (first groups)"_" "-")
            attr (.replace (second groups )"_" "-")]

        (print "groups => " groups)
        (print "expr => " expr)
        (print "attr => " attr)

        (let [obj (eval (Symbol expr) (. self namespace))
              words (dir obj)
              n (len attr)
              matches []]

          (print "obj => " obj)
          (print "words => " words)
          (print "n => " n)
          (print "matches => " matches)
          
          (for [w words]
            (when (= (cut w 0 n) attr)
              (.append matches
                       {"candidate" (.format "{}.{}" expr (.replace w "_" "-"))
                        "type" (make-type obj)})))
          matches))
      (except [e Exception]
        (print e)
        [])))

  (defn global-matches [self text]
    (let [matches []]
      (for [p (. self path)
            #(k v) (.items p)]
        (when (isinstance k str)
          (setv k (.replace k "_" "-"))
          (when (.startswith k text)
            (.append matches {"candidate" k
                              "type" (make-type v)}))))
      matches)))

(defn get-completions [session stem [extra None]]
  (let [comp (TypedCompleter (. session.module __dict__))]
    (cond
      (in "." stem)
      (.attr-matches comp stem)

      True
      (.global-matches comp stem))))


;; complete
;; https://docs.cider.mx/cider-nrepl/nrepl-api/ops.html#complete

(defop complete [session msg transport]
  {"doc" "Returns a list of symbols matching the specified (partial) symbol."
   "requires" {"prefix" "The symbol to look up"}
   "optional" {"context" "Completion context"
               "extra-metadata" "List of additional metadata"}
   "returns" {"completions" "A list of possible completions"}}
  (print "Complete: " msg :file sys.stderr)
  (.write session {"id" (.get msg "id")
                   "completions" (get-completions session (.get msg "prefix") (.get msg "extra-metadata" []))
                   "status" ["done"]}
          transport))

;; completions
;; built-in ops
(defop completions [session msg transport]
  {"doc" "Returns a list of symbols matching the specified (partial) symbol."
   "requires" {"prefix" "The symbol to look up"}
   "optional" {"complete-fn" "The fully qualified name of a completion function to use instead of the default one (e.g. my.ns/completion)."
               "ns" "The namespace in which we want to obtain completion candidates. Defaults to *ns*."
               "options" "A map of options supported by the completion function. Supported keys: extra-metadata (possible values: :arglists, :docs)"}
   "returns" {"completions" "A list of possible completions"}}
  (print "Complete: " msg :file sys.stderr)
  (.write session {"id" (.get msg "id")
                   "completions" (get-completions session (.get msg "prefix"))
                   "status" ["done"]}
          transport))
