# ============================================================
# Praat AudioTools - Oscillating amplitude with decay.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral analysis or frequency-domain processing script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Oscillating Amplitude with Decay
    comment This script applies spectral filtering with oscillating decay
    comment Spectral filtering parameters:
    positive low_freq_factor 1.1
    positive high_freq_factor 1.1
    comment Oscillation parameters:
    positive oscillation_center 0.5
    positive oscillation_depth 0.5
    positive oscillation_frequency 10
    comment (number of oscillations across duration)
    comment Exponential decay parameters:
    positive decay_base 10
    comment (higher = faster decay)
    comment Output options:
    positive scale_peak 0.99
    boolean play_after_processing 1
endform

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Copy the sound object
Copy... soundObj

# Get name and ID
name$ = selected$("Sound")
sound = selected("Sound")

# Apply spectral filtering (emphasize mids, reduce extremes)
Formula: "self[col/'low_freq_factor'] - self[col*'high_freq_factor']"

# Apply oscillating amplitude with exponential decay
Formula: "self * ('oscillation_center' + 'oscillation_depth' * sin('oscillation_frequency' * (x-xmin) / (xmax-xmin))) * 'decay_base'^(-(x-xmin)/(xmax-xmin))"

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif