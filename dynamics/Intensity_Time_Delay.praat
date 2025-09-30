# VARIATION 1: Intensity Time Delay
# Shift intensity curve later in time
a = selected("Sound")
b = Copy...
To Intensity: 100, 0, "yes"
Shift times by: 0.5
c = Down to IntensityTier
select a
plus c
Multiply: "yes"
Play
select b
Remove
select c
Remove

