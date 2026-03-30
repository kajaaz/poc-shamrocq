;; This extracted scheme code relies on some additional macros
;; available at http://www.pps.univ-paris-diderot.fr/~letouzey/scheme


(define length (lambda (l)
  (match l
     ((Nil) `(O))
     ((Cons _ l~) `(S ,(length l~))))))
  
(define leb (lambdas (n m)
  (match n
     ((O) `(True))
     ((S n~) (match m
                ((O) `(False))
                ((S m~) (@ leb n~ m~)))))))
  
(define take (lambdas (n l)
  (match n
     ((O) `(Nil))
     ((S n~)
       (match l
          ((Nil) `(Nil))
          ((Cons x rest) `(Cons ,x ,(@ take n~ rest))))))))
  
(define drop (lambdas (n l)
  (match n
     ((O) l)
     ((S n~) (match l
                ((Nil) `(Nil))
                ((Cons _ rest) (@ drop n~ rest)))))))
  
(define parse_field (lambdas (size data)
  (match (@ leb size (length data))
     ((True) `(Some ,`(Pair ,(@ take size data) ,(@ drop size data))))
     ((False) `(None)))))

(define tx_nonce (lambda (tx) (match tx
                                 ((MkTransaction n _ _ _) n))))

(define tx_to (lambda (tx) (match tx
                              ((MkTransaction _ t _ _) t))))

(define tx_value (lambda (tx) (match tx
                                 ((MkTransaction _ _ v _) v))))

(define tx_memo (lambda (tx) (match tx
                                ((MkTransaction _ _ _ m) m))))

(define mAX_TX_LEN 510)

(define aDDRESS_LEN 20)

(define mAX_MEMO_LEN 465)

(define nONCE_LEN 8)

(define vALUE_LEN 8)

(define mAX_ASCII 127)

(define check_encoding (lambda (memo)
  (match memo
     ((Nil) `(True))
     ((Cons b rest)
       (match (@ leb b mAX_ASCII)
          ((True) (check_encoding rest))
          ((False) `(False)))))))
  
(define format_memo_check (lambdas (memo_len dst_len)
  (match (@ leb memo_len mAX_MEMO_LEN)
     ((True) (@ leb `(S ,memo_len) dst_len))
     ((False) `(False)))))

(define deserialize_transaction (lambda (data)
  (match (@ leb (length data) mAX_TX_LEN)
     ((True)
       (match (@ parse_field nONCE_LEN data)
          ((Some p)
            (match p
               ((Pair nonce rest1)
                 (match (@ parse_field aDDRESS_LEN rest1)
                    ((Some p0)
                      (match p0
                         ((Pair to_addr rest2)
                           (match (@ parse_field vALUE_LEN rest2)
                              ((Some p1)
                                (match p1
                                   ((Pair value memo)
                                     (match (@ leb (length memo)
                                              mAX_MEMO_LEN)
                                        ((True)
                                          (match (check_encoding memo)
                                             ((True) `(Inr ,`(MkTransaction
                                               ,nonce ,to_addr ,value
                                               ,memo)))
                                             ((False) `(Inl
                                               ,`(MEMO_ENCODING_ERROR)))))
                                        ((False) `(Inl
                                          ,`(MEMO_LENGTH_ERROR)))))))
                              ((None) `(Inl ,`(VALUE_PARSING_ERROR)))))))
                    ((None) `(Inl ,`(TO_PARSING_ERROR)))))))
          ((None) `(Inl ,`(NONCE_PARSING_ERROR)))))
     ((False) `(Inl ,`(WRONG_LENGTH_ERROR))))))

(define boilerplate_exports `(Pair ,`(Pair ,`(Pair ,`(Pair ,`(Pair ,`(Pair
  ,check_encoding ,format_memo_check) ,deserialize_transaction) ,tx_nonce)
  ,tx_to) ,tx_value) ,tx_memo))

