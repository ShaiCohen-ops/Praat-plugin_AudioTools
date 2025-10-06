# ============================================================
# Praat AudioTools - Fractal Feedback.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Reverberation or diffusion script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Fractal Feedback
    comment This script applies self-modulating delays at multiple scales
    natural depth_layers 3
    positive delay_range_min 0.1
    positive delay_range_max 0.9
    positive feedback_base 0.6
    positive scale_peak 0.99
    boolean play_after_processing 1
endform

if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

originalName$ = selected$("Sound")
Copy: originalName$ + "_fractal"

a = Get number of samples

for layer from 1 to depth_layers
    divisions = 2^layer
    for segment from 1 to divisions
        segment_size = a / divisions
        delay_offset = segment_size * randomUniform(delay_range_min, delay_range_max)
        feedback_strength = feedback_base / layer
        Formula: "self + 'feedback_strength' * (self[col+'delay_offset'] - self[col]) * sin(2*pi*col/'segment_size')"
    endfor
endfor

Scale peak: scale_peak

if play_after_processing
    Play
endif