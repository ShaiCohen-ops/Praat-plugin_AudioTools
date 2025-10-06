# ============================================================
# Praat AudioTools - Noise Gate.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Dynamic range or envelope control script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Noise Gate
real Threshold_(dB) -20
endform

# Get original sound
original = selected("Sound")
name$ = selected$("Sound")

# Create intensity analysis
To Intensity: 100, 0, "yes"
Down to IntensityTier

# Apply gate threshold
Formula: "if self < threshold then -80 else self fi"

# Apply gate to original sound
selectObject: original
plusObject: "IntensityTier " + name$
gated = Multiply: "yes"

# Clean up and play
selectObject: gated
Scale peak: 0.99
Play