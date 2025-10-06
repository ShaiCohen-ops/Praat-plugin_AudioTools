# ============================================================
# Praat AudioTools - vibrato.praat
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

form Sine Vibrato Effect
    comment This script applies simple sine wave vibrato
    comment Delay parameters:
    positive base_delay_ms 5.0
    comment (base delay time in milliseconds)
    positive modulation_depth 0.10
    comment (depth of delay modulation)
    comment Modulation parameters:
    positive modulation_rate_hz 5.0
    comment (vibrato frequency)
    real initial_phase_radians 0.0
    comment (starting phase in radians)
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
Copy: originalName$ + "_sine_vibrato"

# Get sampling frequency
sampling = Get sampling frequency

# Calculate base delay in samples
base = round(base_delay_ms * sampling / 1000)

# Apply sine vibrato
Formula: "self[max(1, min(ncol, col + round('base' * (1 + 'modulation_depth' * sin(2 * pi * 'modulation_rate_hz' * x + 'initial_phase_radians')))))]"

# Rename result
Rename: originalName$ + "_vibrato_sine"

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif


