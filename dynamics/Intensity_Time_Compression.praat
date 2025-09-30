# VARIATION 4: Intensity Time Compression
# Compress intensity to fit in first half
a = selected("Sound")
duration = Get total duration
b = Copy...
To Intensity: 100, 0, "yes"
Scale times to: 0, duration/2
c = Down to IntensityTier
select a
plus c
Multiply: "yes"
Play
select b
Remove
select c
Remove
