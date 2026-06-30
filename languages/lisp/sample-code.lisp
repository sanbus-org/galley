(define square
  (lambda (x)
    (multiply x x)))

(print (square 12))

(define cube
  (lambda (x)
    (multiply x (multiply x x))))

(define factorial
  (lambda (n)
    (if (less-than n 2)
      1
      (multiply n (factorial (subtract n 1))))))

(define fibonacci
  (lambda (n)
    (if (less-than n 2)
      n
      (add
        (fibonacci (subtract n 1))
        (fibonacci (subtract n 2))))))

(define map
  (lambda (fn values)
    (if (empty values)
      ()
      (cons
        (fn (head values))
        (map fn (tail values))))))

(define reduce
  (lambda (fn initial values)
    (if (empty values)
      initial
      (reduce
        fn
        (fn initial (head values))
        (tail values)))))

(define values
  (list 1 2 3 4 5 6 7 8 9 10 11 12))

(define squares
  (map square values))

(define cubes
  (map cube values))

(define total
  (reduce add 0 values))

(define weighted-total
  (reduce
    add
    0
    (map
      (lambda (value)
        (multiply value (add value 3)))
      values)))

(define report
  (lambda (label data)
    (print
      (list
        "report"
        label
        data
        (reduce add 0 data)))))

(report "squares" squares)
(report "cubes" cubes)
(print (list "total" total))
(print (list "weighted-total" weighted-total))
(print (list "factorial" (factorial 8)))
(print (list "fibonacci" (fibonacci 10)))

(define program
  (list
    (list "name" "sample-lisp-program")
    (list "version" 1)
    (list "features"
      (list
        "nested-lists"
        "symbols"
        "integers"
        "strings"
        "multiple-top-level-forms"))
    (list "pipeline"
      (list
        (list "step" "load-values")
        (list "step" "map-square")
        (list "step" "map-cube")
        (list "step" "reduce-total")
        (list "step" "print-report")))))

(print program)
