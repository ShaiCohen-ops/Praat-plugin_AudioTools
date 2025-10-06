# ============================================================
# Praat AudioTools - Enveloped_Vibrato(attack-release).praat
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

form Enveloped Vibrato Effect
    comment This script creates vibrato with attack and release envelopes
    comment Delay parameters:
    positive base_delay_ms 6.0
    comment (base delay time in milliseconds)
    positive modulation_depth 0.15
    comment (depth of delay modulation)
    positive modulation_rate_hz 5.5
    comment (vibrato frequency in Hz)
    comment Envelope parameters:
    positive attack_time_seconds 0.25
    comment (time for vibrato to fade in)
    positive release_time_seconds 0.35
    comment (time for vibrato to fade out at end)
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
Copy: originalName$ + "_enveloped_vibrato"

# Get sampling frequency and duration
sampling = Get sampling frequency
dur = Get total duration

# Calculate base delay in samples
base = round(base_delay_ms * sampling / 1000)

# Apply enveloped vibrato effect
# Envelope fades in during attack, fades out during release
Formula: "self[max(1, min(ncol, col + round('base' + 'base' * 'modulation_depth' * max(0, min(1, min(x/'attack_time_seconds', ('dur' - x)/'release_time_seconds'))) * sin(2 * pi * 'modulation_rate_hz' * x))))]"

# Scale to peak
Scale peak: scale_peak

# Rename result
Rename: originalName$ + "_vibrato_enveloped"

# Play if requested
if play_after_processing
    Play
endif

