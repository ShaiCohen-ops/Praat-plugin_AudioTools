# VARIATION 1: "Cascading Echoes" - Multiple delayed differences
original = selected("Sound")
Copy... cascading_echoes
iterations = 5
a = Get number of samples
for k from 1 to iterations
    delay = randomUniform(50, 500)
    amplitude = 0.8^k
    Formula: "self + 'amplitude' * (self[col+'delay'] - self[col])"
endfor
Scale peak: 0.99
result1 = selected("Sound")
Play
