# ============================================================
# Praat AudioTools - crunchy.praat
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

form Bit Crushing Effect
    optionmenu Preset: 1
        option "Default (4 levels)"
        option "Mild Crunch (8 levels)"
        option "Heavy Crunch (2 levels)"
        option "Lo-Fi Digital (3 levels)"
        option "Custom"
    comment This script applies bit crushing (quantization) to a sound
    comment Bit crushing parameters:
    positive quantization_levels 4
    comment Output options:
    positive scale_peak 0.99
    boolean play_after_processing 1
endform

# Apply preset values if not Custom
if preset = 1
    quantization_levels = 4
    scale_peak = 0.99
    play_after_processing = 1
elsif preset = 2
    # Mild Crunch
    quantization_levels = 8
    scale_peak = 0.99
    play_after_processing = 1
elsif preset = 3
    # Heavy Crunch
    quantization_levels = 2
    scale_peak = 0.95
    play_after_processing = 1
elsif preset = 4
    # Lo-Fi Digital
    quantization_levels = 3
    scale_peak = 0.9
    play_after_processing = 1
endif

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Get the name of the original sound
originalName$ = selected$("Sound")

# Copy the sound object
Copy: originalName$ + "_bitcrushed"

# Apply bit crushing (quantization)
Formula: "round(self * 'quantization_levels') / 'quantization_levels'"

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif
