
# Variation 9: Doppler shift - accelerating frequency change
Copy... soundObj
name$ = selected$("Sound")
sound = selected("Sound")
Formula... self[col/(1.0+0.5*((x-xmin)/(xmax-xmin))^2)] - self[col*(1.0+0.5*((x-xmin)/(xmax-xmin))^2)]
Formula... self*15^(-(x-xmin)/(xmax-xmin))
Scale peak: 0.99
Play