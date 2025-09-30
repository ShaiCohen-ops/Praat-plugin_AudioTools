# VARIATION 2: Intensity Early Arrival
# Move intensity curve to start earlier
a = selected("Sound")
b = Copy...
To Intensity: 100, 0, "yes"
Shift times to: "start time", -0.3
c = Down to IntensityTier
select a
plus c
Multiply: "yes"
Play
select b
Remove
select c
Remove
