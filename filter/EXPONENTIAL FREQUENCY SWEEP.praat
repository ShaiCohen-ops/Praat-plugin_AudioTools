# ============================================================
# Praat AudioTools - EXPONENTIAL FREQUENCY SWEEP.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Filtering or timbral modification script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Exponential Ring Modulation
    comment This script applies ring modulation with exponential frequency sweep
    comment Frequency sweep parameters:
    positive start_frequency 50
    comment (starting frequency in Hz)
    positive end_frequency 800
    comment (ending frequency in Hz)
    comment Output options:
    positive scale_peak 0.99
    boolean play_after_processing 1
endform

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Get the name of the original sound
originalName$ = selected$("Sound")

# Copy the sound object
Copy: originalName$ + "_exp_sweep"

# Apply exponential frequency sweep ring modulation
Formula: "self * (sin(2 * pi * 'start_frequency' * exp(ln('end_frequency' / 'start_frequency') * x / xmax) * x))"

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif