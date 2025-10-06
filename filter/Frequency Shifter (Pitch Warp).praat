# ============================================================
# Praat AudioTools - Frequency Shifter (Pitch Warp).praat
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

form Frequency Shift
    comment This script shifts all frequencies by a fixed amount
    comment WARNING: This process can have long runtime on long files
    comment due to FFT calculations
    comment Spectrum parameters:
    boolean fast_fourier no
    comment (use "no" for precise control)
    comment Frequency shift parameters:
    integer frequency_shift_hz 800
    comment (positive = shift up, negative = shift down)
    comment (shifts all frequencies by this amount in Hz)
    comment Output options:
    positive scale_peak 0.99
    boolean play_after_processing 1
    boolean keep_intermediate_objects 0
endform

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Get the original sound name
originalName$ = selected$("Sound")

# Convert to spectrum
spectrum = To Spectrum: fast_fourier

# Shift all frequencies
# Note: This shifts frequency bins, creating inharmonic effects
Formula: "self[col + 'frequency_shift_hz']"

# Convert back to sound
result = To Sound

# Rename result
Rename: originalName$ + "_freq_shifted"

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif

# Clean up intermediate objects unless requested to keep
if not keep_intermediate_objects
    select spectrum
    Remove
endif