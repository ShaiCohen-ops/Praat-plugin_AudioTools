# ========================================
# VARIATION 5: Wave Interference Pattern
# ========================================
sampling_rate = Get sampling frequency
To Spectrum: "yes"
Formula: "if col < 11000 then self[1,col] * abs(sin(col/800) + 0.5*cos(col/1200)) else self[1,col] * abs(sin(col/800) + 0.5*cos(col/1200)) * 0.3 fi"
To Sound
Scale peak: 0.87
Play