Copy... soundObj
a = Get number of samples
freezePoints = 12
freezeDuration = a / 25

for point from 1 to freezePoints
# Random freeze position
freezePos = randomInteger(floor(freezeDuration), a - floor(freezeDuration))
freezeLength = randomInteger(floor(freezeDuration/2), floor(freezeDuration*1.5))
# Freeze and repeat segment
Formula: "if col >= freezePos and col < freezePos + freezeLength then self[freezePos + ((col - freezePos) mod (freezeLength/3))] else self fi"

# Add spectral artifacts
Formula: "self * (1 + 0.1 * sin(2 * pi * point * col / a))"
endfor
Scale peak: 0.91
Play