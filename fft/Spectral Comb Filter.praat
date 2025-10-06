# ============================================================
# Praat AudioTools - Spectral Comb Filter.praat
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

form Spectral Comb Filter
    comment This script applies a comb filter pattern in the frequency domain
    comment WARNING: This process can have long runtime on long files
    comment due to FFT calculations
    comment Spectrum parameters:
    boolean fast_fourier yes
    comment Comb filter parameters:
    positive comb_frequency_divisor 100
    comment (controls spacing of comb teeth: higher = closer spacing)
    positive comb_center 0.5
    positive comb_depth 0.5
    comment (amplitude varies between center-depth and center+depth)
    comment Output options:
    positive scale_peak 0.88
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

# Apply spectral comb filter
Formula: "self[1,col] * ('comb_center' + 'comb_depth' * sin(col/'comb_frequency_divisor'))"

# Convert back to sound
result = To Sound

# Rename result
Rename: originalName$ + "_spectral_comb"

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