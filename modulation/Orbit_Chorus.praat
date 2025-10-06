# ============================================================
# Praat AudioTools - Orbit_Chorus.praat
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

form Orbit Chorus Effect
    comment This script creates chorus with dual drifting taps
    comment Delay parameters:
    positive base_delay_ms 8.0
    comment (base delay time in milliseconds)
    positive modulation_depth 0.12
    comment (depth of delay modulation)
    comment Modulation parameters:
    positive base_rate_hz 4.2
    comment (primary modulation frequency)
    positive phase_drift_hz 0.08
    comment (phase drift frequency for orbit effect)
    real phase_offset 1.3
    comment (phase offset between the two taps)
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
Copy: originalName$ + "_orbit_chorus"

# Get sampling frequency
sampling = Get sampling frequency

# Calculate base delay in samples
base = round(base_delay_ms * sampling / 1000)

# Apply orbit chorus effect
# Two taps with counter-rotating phase drift
Formula: "(self[max(1, min(ncol, col + round('base' + 'base' * 'modulation_depth' * sin(2 * pi * 'base_rate_hz' * x + 2 * pi * 'phase_drift_hz' * x))))] + self[max(1, min(ncol, col + round('base' + 'base' * 'modulation_depth' * sin(2 * pi * 'base_rate_hz' * x + 'phase_offset' - 2 * pi * 'phase_drift_hz' * x))))] ) / 2"

# Scale to peak
Scale peak: scale_peak

# Rename result
Rename: originalName$ + "_chorus_orbit"

# Play if requested
if play_after_processing
    Play
endif
