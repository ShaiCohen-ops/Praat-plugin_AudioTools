# ============================================================
# Praat AudioTools - rate_modulation.praat
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

form Vibrato Rate Modulation Effect
    comment This script creates vibrato with time-varying rate
    comment Delay parameters:
    positive base_delay_ms 5.0
    comment (base delay time in milliseconds)
    positive modulation_depth 0.10
    comment (depth of delay modulation)
    comment Rate modulation parameters:
    positive base_rate_hz 4.0
    comment (center frequency of vibrato)
    positive rate_sensitivity 3.0
    comment (amount of rate variation)
    positive rate_modulation_hz 0.8
    comment (frequency of rate changes)
    comment Output options:
    positive scale_peak 0.99
    boolean play_after_processing 1
endform

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Get original sound name
originalName$ = selected$("Sound")

# Work on a copy
Copy: originalName$ + "_vibrato_rate_mod"

# Get sampling frequency
sampling = Get sampling frequency

# Calculate base delay in samples
base = round(base_delay_ms * sampling / 1000)

# Apply vibrato with rate modulation
# Vibrato rate varies between (base_rate - sensitivity) and (base_rate + sensitivity)
Formula: "self[max(1, min(ncol, col + round('base' * (1 + 'modulation_depth' * sin(2 * pi * x * ('base_rate_hz' + 'rate_sensitivity' * (0.5 + 0.5 * sin(2 * pi * 'rate_modulation_hz' * x))))))))]"

# Scale to peak
Scale peak: scale_peak

# Rename result
Rename: originalName$ + "_vibrato_rate_mod"

# Play if requested
if play_after_processing
    Play
endif



