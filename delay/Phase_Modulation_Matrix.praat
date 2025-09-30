Copy... soundObj
a = Get number of samples
modulationLayers = 5
carrierFreq = randomUniform(0.1, 0.5)

for layer from 1 to modulationLayers
# Dynamic modulation depth
modDepth = a / (8 + layer * 2)
modulatorFreq = carrierFreq * (layer + 1)
# Phase modulation with feedback
Formula: "self + self[col + round(modDepth * sin(2 * pi * modulatorFreq * col / a))] * (0.7 / layer)"

# Spectral tilt compensation
Formula: "self * (1.1 - 0.1 * layer)"
endfor
Scale peak: 0.93
Play