# 1. EXPONENTIAL FREQUENCY SWEEP
form Exponential Ring Modulation
    positive f0_start 50
    positive f0_end 800
endform
Copy... soundObj
Formula... self*(sin(2*pi*f0_start*exp(ln(f0_end/f0_start)*x/xmax)*x))
Play