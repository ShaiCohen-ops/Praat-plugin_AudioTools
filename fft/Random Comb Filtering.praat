# ============================================================
# Praat AudioTools - Random Comb Filtering.praat
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

form Random Comb Filtering
    comment This script applies multiple random comb filter iterations
    comment Iteration parameters:
    natural number_of_iterations 100
    comment Random comb filter range:
    positive comb_factor_min 0.5
    positive comb_factor_max 0.9
    comment Filtering strength:
    positive filter_mix 0.1
    comment (lower = more subtle, higher = more extreme)
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

# Get name
name$ = selected$("Sound")

# Apply random comb filtering iterations
for k to number_of_iterations
    factor = randomUniform(comb_factor_min, comb_factor_max)
    Formula: "self - 'filter_mix' * self[col/factor]"
endfor

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif