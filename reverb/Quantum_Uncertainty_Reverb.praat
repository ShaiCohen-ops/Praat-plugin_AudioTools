# VARIATION 4: Quantum Uncertainty Reverb  
# Probabilistic delays with uncertainty principle-inspired behavior

Copy... "reverb_copy"

quantum_states = 35
uncertainty = 0.35
collapse_threshold = 0.65
base_amplitude = 0.25

for state from 1 to quantum_states
    # Heisenberg-like uncertainty between time and amplitude precision
    time_uncertainty = randomGauss (0.18, uncertainty)
    amplitude_precision = 1 / (1 + abs (time_uncertainty))
    
    # Gentler amplitude decay to keep effect present
    state_decay = 0.7 + 0.3 * (quantum_states - state) / quantum_states
    
    probability = randomUniform (0, 1)
    if probability > collapse_threshold
        # Wave function "collapses" - creates discrete reflection
        delay = abs (time_uncertainty) + 0.02
        amp = base_amplitude * amplitude_precision * state_decay * 0.8
        Formula... self + amp * self (x - delay)
    else
        # Superposition state - creates diffuse reflection
        for substates from 1 to 4
            sub_delay = abs (time_uncertainty) + randomGauss (0, 0.015) + 0.02
            sub_amp = base_amplitude * amplitude_precision * state_decay * 0.5 / substates
            Formula... self + sub_amp * self (x - sub_delay)
        endfor
    endif
endfor
Play