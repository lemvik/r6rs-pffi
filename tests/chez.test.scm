#!r6rs
(import (rnrs)
	(pffi)
	(srfi :64)
	(rename (pffi bv-pointer)
		(bytevector->pointer bytevector->address))
        (only (pffi compat) pointer-tracker)
        (only (chezscheme) collect locked-object?
              make-weak-eq-hashtable))

(define *pointer-table* (make-weak-eq-hashtable))
(define *refcount-table* (make-weak-eq-hashtable))
(define (pointer-statistic)
  (list (hashtable-size *pointer-table*)
	(hashtable-keys *pointer-table*)
	(let-values (((keys values) (hashtable-entries *refcount-table*)))
	  (vector-map cons keys values))))

;; Set the tracker to count pointer allocations.
(pointer-tracker (lambda (bv p)
                   (hashtable-set! *pointer-table* p bv)
                   (hashtable-update! *refcount-table* bv (lambda (v) (+ v 1)) 0)))

(test-begin "PFFI Chez specific")

(define test-lib (open-shared-object "./functions.so"))
(define fill-one (foreign-procedure test-lib void fill_one (pointer int)))
(define fill-n (foreign-procedure test-lib void fill_n
				  (pointer int (callback int int))))

(define (allocate-alot n)
  (do ((i 0 (+ i 1))
       (bv (make-bytevector n) (make-bytevector (bytevector-length bv))))
      ((= i 100000))
    (bytevector-u8-set! bv (mod i n) (mod i 255))))

(let* ((bv (make-bytevector (* 4 5) 0))
       (ptr (bytevector->pointer bv)))
  (test-assert (locked-object? bv))
  (fill-one ptr 1)
  (test-equal '(1 0 0 0 0) (bytevector->uint-list bv (native-endianness) 4))
  (collect)
  (fill-one ptr 2)
  (test-equal '(1 1 0 0 0) (bytevector->uint-list bv (native-endianness) 4)))

(let* ((callback (c-callback int ((int i)) (lambda (i) (collect) i)))
       (bv (make-bytevector (* 4 5) 0))
       (ptr (bytevector->pointer bv)))
  (fill-n ptr 2 callback)
  (test-equal '(1 2 0 0 0) (bytevector->uint-list bv (native-endianness) 4))
  (free-c-callback callback))

;; make sure the locked pointers are gone
(allocate-alot 1000)
(collect)
(test-assert (< (car (pointer-statistic)) 2))

(test-end)

