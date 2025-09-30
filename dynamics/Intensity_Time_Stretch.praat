# VARIATION 3: Intensity Time Stretch
# Stretch intensity curve to be twice as long
a = selected("Sound")
b = Copy...
To Intensity: 100, 0, "yes"
Scale times by: 2.0
c = Down to IntensityTier
select a
plus c
Multiply: "yes"
Play
select b
Remove
select c
Remove
