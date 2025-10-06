# ============================================================
# Praat AudioTools - Barber-Pole_Orbit.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Modulation or vibrato-based processing script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Barber-Pole Orbit Effect
    comment This script creates a continuously rising/falling pitch illusion
    comment Orbit parameters:
    natural number_of_turns 5
    comment (number of orbit iterations)
    comment Delay parameters:
    positive base_delay_ms 7.0
    comment (base delay time in milliseconds)
    positive modulation_depth 0.10
    comment (depth of delay modulation)
    comment Modulation rates:
    positive base_rate_hz 3.8
    comment (primary modulation frequency)
    positive drift_rate_hz 0.12
    comment (secondary drift frequency)
    positive phase_offset 1.2
    comment (phase offset between up/down halos)
    comment Mix parameters:
    positive turn_attenuation 1.0
    comment (attenuation factor: weight = 1/(turn + attenuation))
    positive temporal_shift 0.3
    comment (temporal phase shift per turn)
    comment Output options:
    positive scale_peak 0.95
    boolean play_after_processing 1
endform

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Get original sound name
originalName$ = selected$("Sound")

# Work on a copy
Copy: originalName$ + "_barber_pole"

# Get sampling frequency
sampling = Get sampling frequency

# Calculate base delay in samples
base = round(base_delay_ms * sampling / 1000)

# Apply barber-pole orbit effect
for t from 1 to number_of_turns
    # Calculate weight for this turn
    w = 1 / (t + turn_attenuation)
    
    # Upward-drifting halo
    Formula: "self + self[max(1, min(ncol, col + round('base' + 'base' * 'modulation_depth' * sin(2 * pi * 'base_rate_hz' * x + 2 * pi * 'drift_rate_hz' * x + 't' * 'temporal_shift'))))] * 'w'"
    
    # Downward-drifting halo
    Formula: "self + self[max(1, min(ncol, col + round('base' + 'base' * 'modulation_depth' * sin(2 * pi * 'base_rate_hz' * x - 2 * pi * 'drift_rate_hz' * x + 'phase_offset' - 't' * 'temporal_shift'))))] * 'w'"
endfor

# Scale to peak
Scale peak: scale_peak

# Rename result
Rename: originalName$ + "_barber_pole_orbit"

# Play if requested
if play_after_processing
    Play
endif