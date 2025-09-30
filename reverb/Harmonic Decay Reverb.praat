# VARIATION 1: Harmonic Decay Reverb
# Creates delays based on harmonic intervals with exponential decay

Copy... "reverb_copy"

n = 48
base_delay = 0.05
decay_factor = 0.92
harmonic_spread = 1.2

for k from 1 to n
    harmonic_power = 1 / harmonic_spread
    harmonic_delay = base_delay * k^harmonic_power
    amplitude = decay_factor^k * randomGauss (0.25, 0.08)
    Formula... self + amplitude * self (x - harmonic_delay)
endfor
Play