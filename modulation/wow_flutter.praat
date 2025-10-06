# ============================================================
# Praat AudioTools - wow_flutter.praat
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

form Wow and Flutter Vibrato Effect
    comment This script simulates tape wow and flutter
    comment Delay parameters:
    positive base_delay_ms 7.0
    positive modulation_depth 0.12
    comment Wow parameters (slow speed variation):
    positive wow_rate_hz 0.6
    positive wow_mix 0.6
    comment Flutter parameters (fast speed variation):
    positive flutter_rate_hz 6.5
    positive flutter_mix 0.4
    positive flutter_phase_offset 1.1
    comment Noise parameters (random variation):
    positive noise_amount 0.02
    positive noise_frequency 17.3
    positive noise_phase_offset 0.8
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
Copy: originalName$ + "_wow_flutter"

# Get sampling frequency
sampling = Get sampling frequency

# Calculate base delay in samples
base = round(base_delay_ms * sampling / 1000)

# Apply wow and flutter vibrato
# Combines slow wow, fast flutter, and random noise
Formula: "self[max(1, min(ncol, col + round('base' * (1 + 'modulation_depth' * ('wow_mix' * sin(2 * pi * 'wow_rate_hz' * x) + 'flutter_mix' * sin(2 * pi * 'flutter_rate_hz' * x + 'flutter_phase_offset') + 'noise_amount' * sin(2 * pi * 'noise_frequency' * x + 'noise_phase_offset'))))))]"

# Rename result
Rename: originalName$ + "_vibrato_wow_flutter"

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif


