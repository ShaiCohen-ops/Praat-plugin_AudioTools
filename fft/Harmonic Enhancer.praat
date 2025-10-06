# ============================================================
# Praat AudioTools - Harmonic Enhancer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral analysis or frequency-domain processing script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Harmonic Enhancer
    comment This script adds harmonic overtones to enhance brightness
    comment WARNING: This process can have long runtime on long files
    comment due to FFT calculations
    comment Spectrum parameters:
    boolean fast_fourier yes
    comment Harmonic enhancement parameters:
    positive second_harmonic_weight 0.3
    comment (amount of 2x frequency content to add)
    positive third_harmonic_weight 0.1
    comment (amount of 3x frequency content to add)
    comment Output options:
    positive scale_peak 0.85
    boolean play_after_processing 1
    boolean keep_intermediate_objects 0
endform

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Get the original sound name
originalName$ = selected$("Sound")

# Get sampling frequency
sampling_frequency = Get sampling frequency

# Convert to spectrum
spectrum = To Spectrum: fast_fourier

# Add harmonic overtones
# Each frequency gets enhanced with content from 2x and 3x its frequency
Formula: "self[1,col] + 'second_harmonic_weight' * self[1,col*2] + 'third_harmonic_weight' * self[1,col*3]"

# Convert back to sound
result = To Sound

# Rename result
Rename: originalName$ + "_harmonic_enhanced"

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