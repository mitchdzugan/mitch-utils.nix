(#(+ $ 5) 9)

(print 0x29 "hello")

(macro foo []
  `(do
     (print :stuff)
     (hello ,world)))
