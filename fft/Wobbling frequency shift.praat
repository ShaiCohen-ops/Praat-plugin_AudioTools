# Wobbling frequency shift with turbulent decay
Copy... soundObj
name$ = selected$("Sound")
sound = selected("Sound")
Formula... self[col/(1.1+0.05*sin(50*(x-xmin)/(xmax-xmin)))] - self[col*(1.1+0.05*cos(50*(x-xmin)/(xmax-xmin)))]
Formula... self*25^(-(x-xmin)/(xmax-xmin))*(1+0.1*randomGauss(0,1))
Scale peak: 0.99
Play
