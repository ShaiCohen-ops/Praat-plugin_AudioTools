# Variation 11: Spectral reversal with pulsing decay
Copy... soundObj
name$ = selected$("Sound")
sound = selected("Sound")
Formula... self[col/1.2] - self[col*1.2]
Formula... self*abs(sin(15*(x-xmin)/(xmax-xmin)))*20^(-(x-xmin)/(xmax-xmin))
Scale peak: 0.99
Play