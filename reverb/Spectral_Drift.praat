# VARIATION 3: "Spectral Drift" - Frequency-dependent delays
Copy... soundObj
drift_cycles = 4
a = Get number of samples
sample_rate = Get sampling frequency
for cycle from 1 to drift_cycles
    base_freq = 100 * cycle
    delay_samples = sample_rate / base_freq
    drift_amount = randomUniform(0.5, 2.0)
    Formula: "self + 0.4 * (self[col+'delay_samples'*'drift_amount'] - self[col]) * cos(2*pi*col*'base_freq'/'sample_rate')"
endfor
Scale peak: 0.99
Play