# ========================================
# VARIATION 3: Harmonic Resonance Boost
# ========================================
sampling_rate = Get sampling frequency
To Spectrum: "yes"
Formula: "if col mod 440 < 50 then self[1,col] * 1.5 else if col < 6000 then self[1,col] * 0.6 else self[1,col] * 0.4 fi fi"
To Sound
Scale peak: 0.88
Play