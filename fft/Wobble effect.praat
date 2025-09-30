# Variation 7: Wobble effect - frequency modulation with tremolo
Copy... soundObj
name$ = selected$("Sound")
sound = selected("Sound")
Formula... self[col/(1.1+0.3*sin(50*(x-xmin)/(xmax-xmin)))] - self[col*(1.1+0.3*cos(50*(x-xmin)/(xmax-xmin)))]
Formula... self*10^(-(x-xmin)/(xmax-xmin))*(1+0.5*sin(20*(x-xmin)/(xmax-xmin)))
Scale peak: 0.99
Play

