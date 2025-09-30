# 2. LOGARITHMIC FREQUENCY SWEEP  
form Logarithmic Ring Modulation
    positive f0_start 800
    positive f0_end 50
endform
Copy... soundObj
Formula... self*(sin(2*pi*f0_start*exp(-ln(f0_start/f0_end)*x/xmax)*x))
Play