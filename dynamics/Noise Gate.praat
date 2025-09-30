form Noise Gate
real Threshold_(dB) -20
endform

# Get original sound
original = selected("Sound")
name$ = selected$("Sound")

# Create intensity analysis
To Intensity: 100, 0, "yes"
Down to IntensityTier

# Apply gate threshold
Formula: "if self < threshold then -80 else self fi"

# Apply gate to original sound
selectObject: original
plusObject: "IntensityTier " + name$
gated = Multiply: "yes"

# Clean up and play
selectObject: gated
Scale peak: 0.99
Play