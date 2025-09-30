# Variation 4: Reverse exponential (crescendo instead of decay)
Copy... soundObj
name$ = selected$("Sound")
sound = selected("Sound")
Formula... self[col/1.1] - self[col*1.1]
Formula... self*20^((x-xmin)/(xmax-xmin)-1)
Scale peak: 0.99
Play

