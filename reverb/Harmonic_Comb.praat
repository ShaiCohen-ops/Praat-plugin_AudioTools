# VARIATION 6: "Harmonic Comb" - Harmonic series-based delays
Copy... soundObj
harmonics = 7
a = Get number of samples
fundamental_delay = randomUniform(20, 100)
for harmonic from 1 to harmonics
    harmonic_delay = fundamental_delay / harmonic
    harmonic_weight = 1.0 / (harmonic * harmonic)
    phase_shift = randomUniform(0, 2*pi)
    Formula: "self + 'harmonic_weight' * (self[col+'harmonic_delay'] - self[col]) * cos('phase_shift' + 2*pi*col*'harmonic'/1000)"
endfor
Scale peak: 0.99
Play