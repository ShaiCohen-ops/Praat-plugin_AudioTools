# ========================================
# SPECTRAL MIRROR: Basic Mirror
# ========================================
sampling_rate = Get sampling frequency
To Spectrum: "yes"
nyquist = sampling_rate / 2
Formula: "if col < nyquist/2 then self[1,col] + self[1,nyquist-col] else self[1,col] fi"
To Sound
Scale peak: 0.9
Play