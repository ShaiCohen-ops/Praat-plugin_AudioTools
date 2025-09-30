# VARIATION 7: "Spectral Decay" - Frequency-selective exponential processing
a = Copy... soundObj
Create Poisson process: "spectral_poisson", 0, 3, 2000
To Sound (pulse train): 44100, 1, 0.035, 2800
# Spectral decay with frequency-dependent envelope
Formula: "self * 110^(-(x-xmin)/(xmax-xmin)) * (1 + 0.7*sin(2*pi*x*150 + (x-xmin)*20))"
select a
plusObject: "Sound spectral_poisson"
b = Convolve
# Apply frequency-dependent amplitude scaling
Filter (pass Hann band): 100, 4000, 100
Multiply: 0.25
select a
plusObject: b
Combine to stereo
Convert to mono
result7 = selected("Sound")
Scale peak: 0.87
Play
# Cleanup
removeObject: "PointProcess spectral_poisson"
removeObject: "Sound spectral_poisson"
removeObject: b
removeObject: a