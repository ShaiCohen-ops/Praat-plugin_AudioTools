# ============================================================
# Praat AudioTools - Stereo_Swirl_Vibrato.praat
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

form Stereo Swirl Vibrato Effect
    comment This script creates stereo vibrato with phase offset
    comment NOTE: Requires a stereo (2-channel) sound
    comment Delay parameters:
    positive base_delay_ms 6.0
    comment (base delay time in milliseconds)
    positive modulation_depth 0.12
    comment (depth of delay modulation)
    positive modulation_rate_hz 4.5
    comment (vibrato frequency)
    comment Stereo phase parameters:
    real phase_step_radians 1.5707963268
    comment (phase offset between channels, default = π/2)
    comment (π/2 = 90°, π = 180°, 0 = mono)
    comment Output options:
    positive scale_peak 0.99
    boolean play_after_processing 1
endform

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Check if sound is stereo
numberOfChannels = Get number of channels
if numberOfChannels <> 2
    exitScript: "This script requires a stereo (2-channel) sound."
endif

# Get original sound name
originalName$ = selected$("Sound")

# Work on a copy
Copy: originalName$ + "_stereo_swirl"

# Get sampling frequency
sampling = Get sampling frequency

# Calculate base delay in samples
base = round(base_delay_ms * sampling / 1000)

# Apply stereo swirl vibrato
# Each channel gets phase-shifted modulation based on row number
Formula: "self[max(1, min(ncol, col + round('base' + 'base' * 'modulation_depth' * sin(2 * pi * 'modulation_rate_hz' * x + (row - 1) * 'phase_step_radians'))))]"

# Scale to peak
Scale peak: scale_peak

# Rename result
Rename: originalName$ + "_vibrato_stereo_swirl"

# Play if requested
if play_after_processing
    Play
endif


