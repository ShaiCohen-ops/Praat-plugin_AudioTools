# ============================================================
# Praat AudioTools - Adaptive Low-pass Filter.praat
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

form Adaptive Low-Pass Filter
    comment This script applies a sweeping low-pass filter effect
    comment Filter sweep parameters:
    positive start_cutoff_frequency 200
    comment (starting cutoff frequency in Hz)
    positive end_cutoff_frequency 2000
    comment (ending cutoff frequency in Hz)
    comment Output options:
    positive scale_peak 0.99
    boolean play_after_processing 1
endform

# Check if a Sound is selected
sound = selected("Sound")
if !sound
    exitScript: "Please select a Sound object first."
endif

# Get original sound name and duration
selectObject: sound
originalName$ = selected$("Sound")
duration = Get total duration

# Create a copy for processing
Copy: originalName$ + "_adaptive_filtered"
processed = selected("Sound")

# Apply adaptive filter with frequency sweep
# The cutoff frequency increases linearly from start to end over duration
selectObject: processed
Formula: "self * sin(2 * pi * ('start_cutoff_frequency' + ('end_cutoff_frequency' - 'start_cutoff_frequency') * (x / duration)) * x)"

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif