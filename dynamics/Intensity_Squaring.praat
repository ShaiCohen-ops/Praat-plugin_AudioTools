# VARIATION 6: Intensity Squaring
# Square intensity values for sharper dynamics
a = selected("Sound")
b = Copy...
To Intensity: 100, 0, "yes"
Formula: "(self/100)^2 * 100"
c = Down to IntensityTier
select a
plus c
Multiply: "yes"
Play
select b
Remove
select c
Remove
