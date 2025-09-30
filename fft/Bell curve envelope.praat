# Variation 5: Bell curve envelope
Copy... soundObj
name$ = selected$("Sound")
sound = selected("Sound")
Formula... self[col/1.1] - self[col*1.1]
Formula... self*exp(-((x-(xmin+xmax)/2)/((xmax-xmin)/4))^2)
Scale peak: 0.99
Play
