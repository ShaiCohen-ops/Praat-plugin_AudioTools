# Variation 13: Underwater/muffled - low pass simulation with bubbling
Copy... soundObj
name$ = selected$("Sound")
sound = selected("Sound")
Formula... (self[col/1.05] + self[col/1.08] + self[col/1.12])/3 - self[col*1.3]
Formula... self*12^(-(x-xmin)/(xmax-xmin))*(1+0.3*randomUniform(-1,1))
Scale peak: 0.99
Play