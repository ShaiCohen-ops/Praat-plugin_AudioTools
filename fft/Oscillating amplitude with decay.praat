# Oscillating amplitude with decay
Copy... soundObj
name$ = selected$("Sound")
sound = selected("Sound")
Formula... self[col/1.1] - self[col*1.1]
Formula... self*(0.5+0.5*sin(10*(x-xmin)/(xmax-xmin)))*10^(-(x-xmin)/(xmax-xmin))
Scale peak: 0.99
Play