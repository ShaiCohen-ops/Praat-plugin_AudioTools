Copy... soundObj
a = Get number of samples
cascadeLevels = 6
decayRate = 0.75

for level from 1 to cascadeLevels
    # Fibonacci-based delay progression
    if level = 1
        fibPrev = 1
        fibCurrent = 1
    else
        fibNext = fibPrev + fibCurrent
        fibPrev = fibCurrent
        fibCurrent = fibNext
    endif
    
    delayShift = a / (5 + fibCurrent)
    currentDecay = decayRate ^ level
    
    # Multi-tap delay with spectral coloring
    Formula: "self + self [col - round(delayShift)] * currentDecay * (0.5 + 0.5 * cos(level * 2 * pi * col / a))"
endfor
Scale peak: 0.88
Play