Copy... soundObj
a = Get number of samples
generations = 6
printThrough = 0.25
bias = randomUniform(0.8, 1.2)

for gen from 1 to generations
# Tape hysteresis effect
Formula: "0.7 * self + 0.3 * self[col-1]"
# Print-through effect (bleeding between layers)
printOffset = round(a / 100)
Formula: "self + printThrough * (self[col - printOffset] + self[col + printOffset])/2"

# High-frequency loss per generation
Formula: "self * (1 - 0.1 * gen) + 0.9 * (self[col-1] + self[col+1])/2"

# Bias modulation
Formula: "self * (0.9 + 0.1 * sin(2 * pi * bias * col / a))"
printThrough = printThrough * 0.8
endfor
Scale peak: 0.87
Play