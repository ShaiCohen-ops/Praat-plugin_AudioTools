# ============================================================
# Praat AudioTools - abs.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Non-linear distortion or waveshaping script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Full-Wave Rectifier
    optionmenu Preset: 1
        option "Default (0.99, play)"
        option "Soft Normalize (0.8, play)"
        option "Hard Normalize (1.0, no play)"
        option "Custom"
    comment This script applies full-wave rectification to a sound
    comment (converts all negative values to positive)
    comment Output options:
    positive scale_peak 0.99
    boolean play_after_processing 1
endform

# Apply preset values if not Custom
if preset = 1
    scale_peak = 0.99
    play_after_processing = 1
elsif preset = 2
    scale_peak = 0.8
    play_after_processing = 1
elsif preset = 3
    scale_peak = 1.0
    play_after_processing = 0
endif

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Get the name of the original sound
originalName$ = selected$("Sound")

# Copy the sound object
Copy: originalName$ + "_rectified"

# Apply full-wave rectification (absolute value)
Formula: "abs(self)"

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif
