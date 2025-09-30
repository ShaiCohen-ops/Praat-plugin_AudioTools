Copy... soundObj
a = Get number of samples
numIterations = 7
harmonicBase = randomUniform(1.5, 4.0)

for k from 1 to numIterations
    # Exponential harmonic progression
    shiftFactor = harmonicBase ^ k
    b = a / shiftFactor
    # Bidirectional formula with harmonic weighting
    Formula: "(self [col + round(b)] - self [col - round(b/2)]) * (1/k)"
    # Harmonic amplitude decay
    Formula: "self * (1 - k/numIterations * 0.6)"
endfor
Scale peak: 0.95
Play
