# ========================================
# SPECTRAL CELLULAR AUTOMATA: Rule-Based Evolution
# ========================================
sampling_rate = Get sampling frequency
To Spectrum: "yes"
Formula: "if (round(col/100) mod 2 = 0 and round(col/150) mod 2 = 1) or (round(col/100) mod 2 = 1 and round(col/150) mod 2 = 0) then self[1,col] * 1.5 * sin(col/500) else self[1,col] * 0.2 fi"
To Sound
Scale peak: 0.84
Play