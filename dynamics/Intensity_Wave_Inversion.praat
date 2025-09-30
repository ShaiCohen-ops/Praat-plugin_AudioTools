# VARIATION 5: Intensity Wave Inversion
# Invert intensity values around midpoint
a = selected("Sound")
b = Copy...
To Intensity: 100, 0, "yes"
Formula: "100 - self"
c = Down to IntensityTier
select a
plus c
Multiply: "yes"
Play
select b
Remove
select c
Remove
