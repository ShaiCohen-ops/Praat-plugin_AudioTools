# ========================================
# VARIATION 1: Dynamic Tremolo Effect
# ========================================
sampling_rate = Get sampling frequency
To Spectrum: "yes"
Formula: "if col < 8000 then self[1,col] * (0.3 + 0.7 * cos(col/500)^2) else self[1,col] * 0.8 fi"
To Sound
Scale peak: 0.9
Play