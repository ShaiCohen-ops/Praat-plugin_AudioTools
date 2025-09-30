# 10. CUBIC PHASE DISTORTION
form Cubic Phase Ring Modulation
    positive f0 180
    real cubic_factor 2
endform
Copy... soundObj
Formula... self*(sin(2*pi*f0*x + cubic_factor*x*x*x))
Play