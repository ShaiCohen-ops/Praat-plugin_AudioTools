# ============================================================
# Praat AudioTools - Subtle Random Texture.praat
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

form Random Spectral Variation
    comment This script adds random variations to the frequency spectrum
    comment WARNING: This process can have long runtime on long files
    comment due to FFT calculations
    comment Spectrum parameters:
    boolean fast_fourier yes
    comment Random variation parameters:
    positive frequency_cutoff 10000
    comment (frequencies below this get random variation)
    positive variation_center 0.8
    positive variation_depth 0.2
    positive variation_min 0.5
    positive variation_max 1.0
    comment (each frequency bin is multiplied by center + depth * randomUniform(min, max))
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
sampling_rate = Get sampling frequency

# Convert to spectrum
spectrum = To Spectrum: fast_fourier

# Apply random spectral variation
Formula: "if col < 'frequency_cutoff' then self[1,col] * ('variation_center' + 'variation_depth' * randomUniform('variation_min', 'variation_max')) else self[1,col] fi"

# Convert back to sound
result = To Sound

# Rename result
Rename: originalName$ + "_spectral_varied"

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