# VARIATION 3: "Temporal Erosion" - Logarithmic decay with granular texture
a = Copy... soundObj
Create Poisson process: "erosion_poisson", 0, 5, 2500
To Sound (pulse train): 44100, 1, 0.02, 4000
# Logarithmic decay with granular modulation
Formula: "self * (1 - log10(1 + 9*(x-xmin)/(xmax-xmin))) * randomGauss(1, 0.3)"
select a
plusObject: "Sound erosion_poisson"
b = Convolve
Multiply: 0.28
# Apply spectral filtering
Filter (pass Hann band): 100, 8000, 100
select a
plus b
Combine to stereo
Convert to mono
result3 = selected("Sound")
Scale peak: 0.92
Play
# Cleanup
removeObject: "PointProcess erosion_poisson"
removeObject: "Sound erosion_poisson"
removeObject: b
removeObject: a