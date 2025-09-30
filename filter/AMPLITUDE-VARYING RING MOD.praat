# 5. AMPLITUDE-VARYING RING MOD
form Amplitude Varying Ring Modulation
    positive f0 250
    positive amp_rate 3
endform
Copy... soundObj
Formula... self*(sin(2*pi*f0*x*x/2))*(0.5 + 0.5*sin(2*pi*amp_rate*x))
Play