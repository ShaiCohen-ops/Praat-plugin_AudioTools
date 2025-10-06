# ============================================================
# Praat AudioTools - XMod.praat
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

form Rhythmic Gating
    comment This script applies rhythmic on/off gating to the sound
    comment Gating parameters:
    positive gate_period 0.1
    comment (duration of one complete gate cycle in seconds)
    positive gate_duty_cycle 0.05
    comment (duration gate is OFF before turning ON)
    comment Output options:
    positive scale_peak 0.99
    boolean play_after_processing 1
endform

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Get the name of the original sound
originalName$ = selected$("Sound")

# Copy the sound object
Copy: originalName$ + "_gated"

# Apply rhythmic gating
Formula: "if (x mod 'gate_period' > 'gate_duty_cycle') then self else 0 fi"

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif