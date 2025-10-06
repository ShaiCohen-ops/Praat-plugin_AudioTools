# ============================================================
# Praat AudioTools - Chorus.praat
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

form Chorus / Unison Effect
    comment This script creates a 3-tap chorus effect
    comment Delay parameters:
    positive base_delay_ms 8.0
    comment (base delay time in milliseconds)
    positive modulation_depth 0.12
    comment (depth of delay modulation)
    comment Modulation rates for each tap:
    positive tap1_rate_hz 3.6
    positive tap2_rate_hz 4.7
    positive tap3_rate_hz 5.8
    comment Phase offsets for taps 2 and 3:
    real tap2_phase_offset 1.9
    real tap3_phase_offset 3.1
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
Copy: originalName$ + "_chorus"

# Get sampling frequency
sampling = Get sampling frequency

# Calculate base delay in samples
base = round(base_delay_ms * sampling / 1000)

# Apply 3-tap chorus effect
# Each tap has independent modulation rate and phase
Formula: "(self[max(1, min(ncol, col + round('base' * (1 + 'modulation_depth' * sin(2 * pi * 'tap1_rate_hz' * x)))))] + self[max(1, min(ncol, col + round('base' * (1 + 'modulation_depth' * sin(2 * pi * 'tap2_rate_hz' * x + 'tap2_phase_offset')))))] + self[max(1, min(ncol, col + round('base' * (1 + 'modulation_depth' * sin(2 * pi * 'tap3_rate_hz' * x + 'tap3_phase_offset')))))] ) / 3"

# Scale to peak
Scale peak: scale_peak

# Rename result
Rename: originalName$ + "_chorus_unison"

# Play if requested
if play_after_processing
    Play
endif
