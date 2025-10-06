# ============================================================
# Praat AudioTools - Tremolo.praat
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

form Adaptive Tremolo
    comment This script creates tremolo that adapts to signal amplitude
    comment Modulation parameters:
    positive modulation_rate_hz 3
    comment (tremolo frequency)
    positive max_modulation_depth 0.7
    comment (maximum depth of amplitude modulation)
    comment Adaptation parameters:
    positive signal_sensitivity 0.5
    comment (how much signal level affects modulation)
    positive sensitivity_offset 0.5
    comment (base sensitivity level)
    comment Output options:
    positive scale_peak 0.99
    boolean play_after_processing 1
endform

# Check if a Sound is selected
sound = selected("Sound")
if !sound
    exitScript: "Please select a Sound object first."
endif

# Get original sound name
selectObject: sound
originalName$ = selected$("Sound")

# Create a copy for processing
Copy: originalName$ + "_adaptive_tremolo"
processed = selected("Sound")

# Apply adaptive tremolo
# Modulation depth is controlled by signal amplitude
selectObject: processed
Formula: "self * (1 - 'max_modulation_depth' * (1 + sin(2 * pi * 'modulation_rate_hz' * x)) / 2 * ('sensitivity_offset' + 'signal_sensitivity' * abs(self)))"

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif