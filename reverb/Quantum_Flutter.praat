# VARIATION 2: "Quantum Flutter" - Reverse exponential with modulation
a = Copy... soundObj
Create Poisson process: "quantum_poisson", 0, 4, 800
To Sound (pulse train): 44100, 1, 0.08, 1200
# Reverse exponential with frequency modulation
Formula: "self * 120^((x-xmin)/(xmax-xmin)-1) * (1 + 0.6*cos(2*pi*x*60 + 10*sin(2*pi*x*3)))"
select a
plusObject: "Sound quantum_poisson"
b = Convolve
Multiply: 0.35
# Create triple-layer texture
select a
Copy... a_layer2
Formula: "self * 0.7"
select a
plusObject: "Sound a_layer2"
plus b
Combine to stereo
Convert to mono
result2 = selected("Sound")
Scale peak: 0.88
Play
# Cleanup
removeObject: "PointProcess quantum_poisson"
removeObject: "Sound quantum_poisson"
removeObject: "Sound a_layer2"
removeObject: b
removeObject: a