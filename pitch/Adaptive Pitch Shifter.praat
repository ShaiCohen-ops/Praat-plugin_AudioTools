# ============================================================
# Praat AudioTools - Adaptive Pitch Shifter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Pitch-based transformation script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# Adaptive Pitch Shifter - pitch changes with amplitude
sound = selected("Sound")
if !sound
    exitScript: "Please select a Sound object first."
endif

form Adaptive Pitch Shift
    positive Base_pitch_shift 1.0
    positive Modulation_amount 0.5
endform

selectObject: sound
Copy: "pitch_shifted"
processed = selected("Sound")

# Simple pitch modulation based on amplitude
selectObject: processed
Formula: "self * sin(2*pi*440*x * (base_pitch_shift + modulation_amount * abs(self)))"

Play