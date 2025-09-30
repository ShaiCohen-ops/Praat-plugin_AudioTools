# 3. SINUSOIDAL FREQUENCY MODULATION
form Sinusoidal FM Ring Modulation
    positive carrier_f0 300
    positive mod_rate 2
    positive mod_depth 100
endform
Copy... soundObj
Formula... self*(sin(2*pi*(carrier_f0 + mod_depth*sin(2*pi*mod_rate*x))*x))
Play