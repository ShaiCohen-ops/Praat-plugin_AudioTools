# 12. SPIRAL FREQUENCY MODULATION
form Spiral Ring Modulation
    positive center_f0 250
    positive spiral_rate 0.8
    positive spiral_depth 150
endform
Copy... soundObj
Formula... self*(sin(2*pi*(center_f0 + spiral_depth*sin(spiral_rate*x)*x/xmax)*x))
Play