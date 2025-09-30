# ========================================
# VARIATION 8: Rhythmic Pulsing
# ========================================
sampling_rate = Get sampling frequency
To Spectrum: "yes"
Formula: "if col < 9000 then self[1,col] * (0.5 + 0.5 * cos(col/333)) else self[1,col] * (0.5 + 0.5 * cos(col/333)) * (col/9000)^(-2) fi"
To Sound
Scale peak: 0.86
Play