# 7. TREMBLING RING MOD (with micro-vibrato)
form Trembling Ring Modulation
    positive f0 200
    positive vibrato_rate 15
    real vibrato_depth 0.05
endform
Copy... soundObj
Formula... self*(sin(2*pi*f0*(1 + vibrato_depth*sin(2*pi*vibrato_rate*x))*x*x/2))
Play