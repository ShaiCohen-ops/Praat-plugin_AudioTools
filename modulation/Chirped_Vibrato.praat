# ============================================================
# Praat AudioTools - Chirped_Vibrato.praat
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

form Chirped Vibrato Effect
    comment This script creates vibrato with accelerating rate
    comment Delay parameters:
    positive base_delay_ms 5.0
    comment (base delay time in milliseconds)
    positive modulation_depth 0.12
    comment (depth of delay modulation)
    comment Chirp parameters:
    positive start_rate_hz 2.0
    comment (initial vibrato rate in Hz)
    positive sweep_rate_hz_per_sec 3.0
    comment (rate of acceleration in Hz/second)
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
Copy: originalName$ + "_chirped_vibrato"

# Get sampling frequency
sampling = Get sampling frequency

# Calculate base delay in samples
base = round(base_delay_ms * sampling / 1000)

# Apply chirped vibrato effect
# Vibrato rate increases linearly with time
Formula: "self[max(1, min(ncol, col + round('base' + 'base' * 'modulation_depth' * sin(2 * pi * x * ('start_rate_hz' + 'sweep_rate_hz_per_sec' * x)))))]"

# Scale to peak
Scale peak: scale_peak

# Rename result
Rename: originalName$ + "_vibrato_chirped"

# Play if requested
if play_after_processing
    Play
endif