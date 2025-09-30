# VARIATION 7: Intensity Sine Modulation
# Modulate intensity with sine wave
a = selected("Sound")
b = Copy...
To Intensity: 100, 0, "yes"
Formula: "self * (0.5 + 0.5 * sin(x * 10))"
c = Down to IntensityTier
select a
plus c
Multiply: "yes"
Play
select b
Remove
select c
Remove
