# ============================================================
# Praat AudioTools - CUBIC PHASE DISTORTION.praat
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

form Cubic Phase Distortion
    comment This script applies ring modulation with cubic phase distortion
    comment Ring modulation parameters:
    positive carrier_frequency 180
    comment (base frequency for ring modulation in Hz)
    comment Phase distortion parameters:
    real cubic_factor 2
    comment (controls cubic phase distortion amount)
    comment (positive = accelerating, negative = decelerating)
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
Copy: originalName$ + "_cubic_phase"

# Apply cubic phase distortion ring modulation
Formula: "self * (sin(2 * pi * 'carrier_frequency' * x + 'cubic_factor' * x^3))"

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif