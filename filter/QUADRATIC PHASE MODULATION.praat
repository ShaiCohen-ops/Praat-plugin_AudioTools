# 4. QUADRATIC PHASE MODULATION
form Quadratic Phase Ring Modulation
    positive f0 150
    real phase_curve 0.5
endform
Copy... soundObj
Formula... self*(sin(2*pi*f0*x + phase_curve*x*x*x))
Play