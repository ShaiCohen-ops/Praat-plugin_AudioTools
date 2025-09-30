# VARIATION 10: Intensity Rhythmic Gating
# Create rhythmic patterns in intensity
a = selected("Sound")
b = Copy...
To Intensity: 100, 0, "yes"
Formula: "self * (0.3 + 0.7 * (sin(x * 8) > 0))"
c = Down to IntensityTier
select a
plus c
Multiply: "yes"
Play
select b
Remove
select c
Remove


