Copy... soundObj
a = Get number of samples
states = 5
superpositionStrength = randomUniform(0.3, 0.8)

for state from 1 to states
# Quantum-inspired probability amplitudes
probAmplitude = sin(state * pi / (states + 1))
phaseShift = randomUniform(0, 2 * pi)
stateOffset = round(a / (10 + state * 2))
# State superposition
Formula: "sqrt(1 - superpositionStrength) * self + sqrt(superpositionStrength) * (cos(phaseShift) * self[col + stateOffset] + sin(phaseShift) * self[col - stateOffset])"

# Collapse probability
superpositionStrength = superpositionStrength * 0.75
endfor
Scale peak: 0.96
Play