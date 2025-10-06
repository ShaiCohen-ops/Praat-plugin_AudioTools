# ============================================================
# Praat AudioTools - Swarm_Vibrato_Stack.praat
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

form Swarm Vibrato Stack Effect
    comment This script creates layered vibrato with multiple frequencies
    comment Stack parameters:
    natural number_of_layers 6
    comment (number of vibrato layers to add)
    comment Delay parameters:
    positive base_delay_ms 6.0
    comment (base delay time in milliseconds)
    positive modulation_depth 0.12
    comment (depth of delay modulation)
    comment Layer modulation parameters:
    positive base_rate_hz 3.0
    comment (base frequency, multiplied by layer number)
    positive phase_step 0.9
    comment (phase increment per layer)
    positive weight_offset 1
    comment (attenuation offset: weight = 1/(layer + offset))
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
Copy: originalName$ + "_swarm_vibrato"

# Get sampling frequency
sampling = Get sampling frequency

# Calculate base delay in samples
base = round(base_delay_ms * sampling / 1000)

# Apply swarm vibrato stack
for d from 1 to number_of_layers
    # Each layer has progressively higher frequency
    rate = base_rate_hz * d
    
    # Each layer has different phase offset
    phase = phase_step * d
    
    # Each layer is progressively attenuated
    weight = 1 / (d + weight_offset)
    
    # Add this vibrato layer
    Formula: "self + self[max(1, min(ncol, col + round('base' * (1 + 'modulation_depth' * sin(2 * pi * rate * x + phase))))) ] * weight"
endfor

# Scale to peak
Scale peak: scale_peak

# Rename result
Rename: originalName$ + "_vibrato_swarm_stack"

# Play if requested
if play_after_processing
    Play
endif

