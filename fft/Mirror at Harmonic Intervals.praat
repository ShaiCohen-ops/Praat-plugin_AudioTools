# ========================================
# HARMONIC MIRROR: Mirror at Harmonic Intervals
# ========================================
sampling_rate = Get sampling frequency
To Spectrum: "yes"
nyquist = sampling_rate / 2
fundamental = 220
Formula: "if col mod fundamental < 50 and col < nyquist/2 then self[1,col] + self[1,nyquist-col] * 1.2 else self[1,col] * 0.6 fi"
To Sound
Scale peak: 0.89
Play