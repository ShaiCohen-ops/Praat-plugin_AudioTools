# ============================================================
# Praat AudioTools - Working Adaptive Filter.praat
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

# Adaptive Low-pass Filter - cutoff frequency sweeps over time
sound = selected("Sound")
if !sound
    exitScript: "Please select a Sound object first."
endif

form Adaptive Filter
    positive Start_cutoff_Hz 200
    positive End_cutoff_Hz 2000
endform

selectObject: sound
duration = Get total duration

# Create a filter that sweeps frequency
Copy: "adaptive_filter"
processed = selected("Sound")

# Simple frequency sweep effect
selectObject: processed
Formula: "self * sin(2*pi*(start_cutoff_Hz + (end_cutoff_Hz-start_cutoff_Hz)*(x/duration))*x)"

Play