# ============================================================
# Praat AudioTools - Rotary.praat
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

form Rotary Speaker Effect
    comment This script simulates rotary speaker (vibrato + tremolo)
    comment Delay parameters:
    positive base_delay_ms 6.0
    comment (base delay time in milliseconds)
    comment Vibrato parameters:
    positive vibrato_depth 0.12
    comment (depth of pitch modulation)
    positive vibrato_rate_hz 5.0
    comment (vibrato frequency)
    comment Tremolo parameters:
    positive tremolo_depth 0.40
    comment (depth of amplitude modulation)
    positive tremolo_rate_hz 4.8
    comment (tremolo frequency)
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
Copy: originalName$ + "_rotary_speaker"

# Get sampling frequency
sampling = Get sampling frequency

# Calculate base delay in samples
base = round(base_delay_ms * sampling / 1000)

# Apply rotary speaker effect (combined vibrato and tremolo)
# Vibrato creates pitch modulation via delay
# Tremolo creates amplitude modulation
Formula: "(self[max(1, min(ncol, col + round('base' * (1 + 'vibrato_depth' * sin(2 * pi * 'vibrato_rate_hz' * x)))))]) * (1 + 'tremolo_depth' * sin(2 * pi * 'tremolo_rate_hz' * x))"

# Rename result
Rename: originalName$ + "_rotary_speaker"

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif
