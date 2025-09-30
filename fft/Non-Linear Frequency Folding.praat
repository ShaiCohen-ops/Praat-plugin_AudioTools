# ========================================
# SPECTRAL KNOTS: Non-Linear Frequency Folding
# ========================================
sampling_rate = Get sampling frequency
To Spectrum: "yes"
Formula: "if col < 100 then self[1,col] else self[1, abs(col - 2*round(col/1000)*1000)] * (sin(col/300) + cos(col/150))^2 fi"
To Sound
Scale peak: 0.88
Play