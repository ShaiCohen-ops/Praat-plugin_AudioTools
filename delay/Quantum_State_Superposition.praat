# ============================================================
# Praat AudioTools - Quantum_State_Superposition.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Delay or temporal structure script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Quantum-Inspired Sound Processing
    optionmenu Preset: 1
        option "Default (balanced)"
        option "Gentle Quantum Drift"
        option "Intense Superposition"
        option "Phase Entanglement"
        option "Custom"
    comment Quantum state parameters:
    natural states 5
    comment Superposition strength range (for randomization):
    positive superposition_min 0.3
    positive superposition_max 0.8
    comment Or use a fixed superposition strength:
    boolean use_fixed_superposition 0
    positive fixed_superposition 0.55
    comment Phase shift range (for randomization):
    positive phase_shift_min 0.1
    positive phase_shift_max 6.283185307
    comment Or use fixed phase shifts:
    boolean use_fixed_phase 0
    positive fixed_phase_shift 3.14159
    comment State offset parameters:
    positive state_offset_base 10
    positive state_offset_increment 2
    comment Collapse probability decay:
    positive superposition_decay 0.75
    comment Output options:
    positive scale_peak 0.96
    boolean play_after_processing 1
endform

# Apply preset if not Custom
if preset = 1
    # Default (balanced)
    states = 5
    superposition_min = 0.3
    superposition_max = 0.8
    fixed_superposition = 0.55
    phase_shift_min = 0.1
    phase_shift_max = 6.283185307
    fixed_phase_shift = 3.14159
    state_offset_base = 10
    state_offset_increment = 2
    superposition_decay = 0.75
    scale_peak = 0.96
elsif preset = 2
    # Gentle Quantum Drift
    states = 4
    superposition_min = 0.2
    superposition_max = 0.5
    fixed_superposition = 0.35
    phase_shift_min = 0.1
    phase_shift_max = 3.14
    fixed_phase_shift = 1.57
    state_offset_base = 12
    state_offset_increment = 3
    superposition_decay = 0.85
    scale_peak = 0.96
elsif preset = 3
    # Intense Superposition
    states = 6
    superposition_min = 0.6
    superposition_max = 0.9
    fixed_superposition = 0.75
    phase_shift_min = 0.2
    phase_shift_max = 6.0
    fixed_phase_shift = 3.14159
    state_offset_base = 8
    state_offset_increment = 2
    superposition_decay = 0.7
    scale_peak = 0.96
elsif preset = 4
    # Phase Entanglement
    states = 7
    superposition_min = 0.4
    superposition_max = 0.9
    fixed_superposition = 0.65
    phase_shift_min = 0.5
    phase_shift_max = 5.5
    fixed_phase_shift = 2.618
    state_offset_base = 9
    state_offset_increment = 1.5
    superposition_decay = 0.8
    scale_peak = 0.96
endif

# Copy the sound object
Copy... soundObj

# Get the number of samples
a = Get number of samples

# Determine initial superposition strength
if use_fixed_superposition
    superpositionStrength = fixed_superposition
else
    superpositionStrength = randomUniform(superposition_min, superposition_max)
endif

# Main quantum-inspired processing loop
for state from 1 to states
    # Quantum-inspired probability amplitudes
    probAmplitude = sin(state * pi / (states + 1))
    
    # Determine phase shift for this state
    if use_fixed_phase
        phaseShift = fixed_phase_shift
    else
        phaseShift = randomUniform(phase_shift_min, phase_shift_max)
    endif
    
    stateOffset = round(a / (state_offset_base + state * state_offset_increment))
    
    # State superposition
    Formula: "sqrt(1 - superpositionStrength) * self + sqrt(superpositionStrength) * (cos(phaseShift) * self[col + stateOffset] + sin(phaseShift) * self[col - stateOffset])"
    
    # Collapse probability
    superpositionStrength = superpositionStrength * superposition_decay
endfor

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif
