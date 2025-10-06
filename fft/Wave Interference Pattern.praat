# ============================================================
# Praat AudioTools - Wave Interference Pattern.praat
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

form Wave Interference Pattern
    comment This script applies wave interference patterns to the spectrum
    comment WARNING: This process can have long runtime on long files
    comment due to FFT calculations
    comment Spectrum parameters:
    boolean fast_fourier yes
    comment Interference pattern parameters:
    positive frequency_cutoff 11000
    comment (frequency threshold for different processing)
    positive sine_divisor 800
    positive cosine_divisor 1200
    positive cosine_weight 0.5
    comment (weight of cosine component)
    comment High frequency attenuation:
    positive high_freq_multiplier 0.3
    comment (applied to frequencies above cutoff)
    comment Output options:
    positive scale_peak 0.87
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

# Apply wave interference pattern
Formula: "if col < 'frequency_cutoff' then self[1,col] * abs(sin(col/'sine_divisor') + 'cosine_weight' * cos(col/'cosine_divisor')) else self[1,col] * abs(sin(col/'sine_divisor') + 'cosine_weight' * cos(col/'cosine_divisor')) * 'high_freq_multiplier' fi"

# Convert back to sound
result = To Sound

# Rename result
Rename: originalName$ + "_interference"

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