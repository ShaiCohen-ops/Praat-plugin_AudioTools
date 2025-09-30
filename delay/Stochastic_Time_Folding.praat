Copy... soundObj
a = Get number of samples
foldIterations = 6
adaptiveThreshold = 0.5

for fold from 1 to foldIterations
    # Adaptive folding based on previous iteration
    if fold > 1
        adaptiveThreshold = adaptiveThreshold + randomUniform(-0.2, 0.2)
        adaptiveThreshold = max(0.1, min(0.9, adaptiveThreshold))
    endif
    
    foldDistance = a / randomUniform(3, 12)
    probabilityMask = randomUniform(0, 1)
    
    # Conditional time-folding with probability gates
    Formula: "if probabilityMask < adaptiveThreshold then (self [col] + self [col + round(foldDistance)] + self [col - round(foldDistance/2)]) / 3 else self * randomUniform(0.7, 1.2) fi"
endfor
Scale peak: 0.96
Play
