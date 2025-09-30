# VARIATION 4: "Chaotic Bloom" - Sinusoidal envelope with chaos
a = Copy... soundObj
Create Poisson process: "chaos_poisson", 0, 6, 3000
To Sound (pulse train): 44100, 1, 0.04, 2500
# Chaotic sinusoidal envelope with feedback-like modulation
Formula: "self * (sin(pi*(x-xmin)/(xmax-xmin))^2) * 80^(-(x-xmin)/(xmax-xmin)) * (1 + 0.8*sin(2*pi*x*200*(x-xmin)/(xmax-xmin)))"
select a
plusObject: "Sound chaos_poisson"
b = Convolve
Multiply: 0.4
# Dynamic panning simulation
select a
Copy... a_pan
Formula: "self * (0.5 + 0.5*sin(2*pi*(x-xmin)*2))"
selectObject: b
Copy... b_pan
Formula: "self * (0.5 - 0.5*sin(2*pi*(x-xmin)*2))"
selectObject: "Sound a_pan"
plusObject: "Sound b_pan"
Combine to stereo
Convert to mono
Scale peak: 0.85
result4 = selected("Sound")
Play
# Cleanup
removeObject: "PointProcess chaos_poisson"
removeObject: "Sound chaos_poisson"
removeObject: "Sound a_pan"
removeObject: "Sound b_pan"
removeObject: b
removeObject: a