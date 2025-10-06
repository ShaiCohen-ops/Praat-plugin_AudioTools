# ============================================================
# Praat AudioTools - Underwater.praat
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

form Underwater Muffled Effect
    comment This script simulates underwater/muffled sound with bubbling
    comment Low-pass simulation parameters:
    positive averaging_factor_1 1.05
    positive averaging_factor_2 1.08
    positive averaging_factor_3 1.12
    positive averaging_divisor 3
    positive high_freq_removal_factor 1.3
    comment Exponential fade parameters:
    positive fade_base 12
    comment Bubbling/noise parameters:
    positive bubble_center 1.0
    positive bubble_amount 0.3
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

# Apply low-pass simulation with averaging and high-frequency removal
Formula: "(self[col/'averaging_factor_1'] + self[col/'averaging_factor_2'] + self[col/'averaging_factor_3']) / 'averaging_divisor' - self[col*'high_freq_removal_factor']"

# Apply exponential fade with random bubbling effect
Formula: "self * 'fade_base'^(-(x-xmin)/(xmax-xmin)) * ('bubble_center' + 'bubble_amount' * randomUniform(-1, 1))"

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif