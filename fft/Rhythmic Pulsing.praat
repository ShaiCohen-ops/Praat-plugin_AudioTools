# ============================================================
# Praat AudioTools - Rhythmic Pulsing.praat
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

form Rhythmic Pulsing Spectral Effect
    comment This script applies rhythmic pulsing with high-frequency rolloff
    comment WARNING: This process can have long runtime on long files
    comment due to FFT calculations
    comment Spectrum parameters:
    boolean fast_fourier yes
    comment Pulsing parameters:
    positive frequency_cutoff 9000
    comment (transition point for high-frequency rolloff)
    positive pulse_center 0.5
    positive pulse_depth 0.5
    positive pulse_frequency_divisor 333
    comment (controls pulse spacing: higher = more frequent pulses)
    comment High-frequency rolloff parameters:
    positive rolloff_exponent 2
    comment (controls steepness of high-frequency attenuation)
    comment Output options:
    positive scale_peak 0.86
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
sampling_rate = Get sampling frequency

# Convert to spectrum
spectrum = To Spectrum: fast_fourier

# Apply rhythmic pulsing with high-frequency rolloff
Formula: "if col < 'frequency_cutoff' then self[1,col] * ('pulse_center' + 'pulse_depth' * cos(col/'pulse_frequency_divisor')) else self[1,col] * ('pulse_center' + 'pulse_depth' * cos(col/'pulse_frequency_divisor')) * (col/'frequency_cutoff')^(-'rolloff_exponent') fi"

# Convert back to sound
result = To Sound

# Rename result
Rename: originalName$ + "_rhythmic_pulsing"

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