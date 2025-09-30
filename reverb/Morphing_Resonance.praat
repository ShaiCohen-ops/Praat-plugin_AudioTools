# VARIATION 6: "Morphing Resonance" - Dynamic frequency-dependent decay
a = Copy... soundObj
Create Poisson process: "morph_poisson", 0, 4.5, 1800
To Sound (pulse train): 44100, 1, 0.055, 2200
# Frequency-morphing envelope
Formula: "self * 85^(-(x-xmin)/(xmax-xmin)) * (1 + 0.5*sin(2*pi*x*(220 + 880*(x-xmin)/(xmax-xmin))) * exp(-3*(x-xmin)/(xmax-xmin)))"
select a
plusObject: "Sound morph_poisson"
b = Convolve
Multiply: 0.32
# Add subtle chorus effect
select b
Copy... b_chorus
Formula: "0.7*(self + 0.3*self[col, 1-0.01*44100])"
select a
plusObject: "Sound b_chorus"
Combine to stereo
Convert to mono
result6 = selected("Sound")
Scale peak: 0.9
Play
# Cleanup
removeObject: "PointProcess morph_poisson"
removeObject: "Sound morph_poisson"
removeObject: "Sound b_chorus"
removeObject: b
removeObject: a