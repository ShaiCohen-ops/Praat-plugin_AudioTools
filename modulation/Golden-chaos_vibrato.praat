# ============================================================
# Praat AudioTools - Golden-chaos_vibrato.praat
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

form Golden-Chaos Vibrato Effect
    comment This script creates complex vibrato using mathematical constants
    comment Delay parameters:
    positive base_delay_ms 6.0
    comment (base delay time in milliseconds)
    positive modulation_depth 0.14
    comment (depth of delay modulation)
    comment Modulation rates (mathematical constants):
    positive rate1_hz 3.14159
    comment (π - Pi)
    positive rate2_hz 2.71828
    comment (e - Euler's number)
    positive rate3_hz 1.61803
    comment (φ - Golden ratio)
    comment Frequency modulation mix:
    positive rate2_mix 0.6
    comment (depth of rate2 modulation)
    positive rate3_mix 0.4
    comment (depth of rate3 modulation)
    comment Output options:
    positive scale_peak 0.99
    boolean play_after_processing 1
endform

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Get original sound name
originalName$ = selected$("Sound")

# Work on a copy
Copy: originalName$ + "_golden_chaos"

# Get sampling frequency
sampling = Get sampling frequency

# Calculate base delay in samples
base = round(base_delay_ms * sampling / 1000)

# Apply golden-chaos vibrato effect
# Uses nested frequency modulation with irrational number ratios
Formula: "self[max(1, min(ncol, col + round('base' + 'base' * 'modulation_depth' * sin(2 * pi * 'rate1_hz' * x + 'rate2_mix' * sin(2 * pi * 'rate2_hz' * x) + 'rate3_mix' * sin(2 * pi * 'rate3_hz' * x)))))]"

# Scale to peak
Scale peak: scale_peak

# Rename result
Rename: originalName$ + "_vibrato_golden_chaos"

# Play if requested
if play_after_processing
    Play
endif