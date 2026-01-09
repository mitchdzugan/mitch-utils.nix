(fn desc [s & body] `(describe ,s (fn [] (do ,(unpack body)) nil)))
(fn spec [s & body] `(it ,s (fn [] (do ,(unpack body)) nil)))

{: desc
 : spec}
