# ============================================================
# Praat AudioTools - Stepped Notch Filter.praat
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

form Stepped Notch Filter
    comment This script applies multiple notch filters at specified frequencies
    comment WARNING: This process can have long runtime on long files
    comment due to FFT calculations
    comment Spectrum parameters:
    boolean fast_fourier yes
    comment Notch 1 parameters:
    positive notch1_lower 2000
    positive notch1_upper 2200
    positive notch1_attenuation 0.1
    comment Notch 2 parameters:
    positive notch2_lower 5500
    positive notch2_upper 5800
    positive notch2_attenuation 0.2
    comment Global attenuation:
    positive overall_attenuation 0.7
    comment (applied to all non-notched frequencies)
    comment Output options:
    positive scale_peak 0.9
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

# Apply stepped notch filtering
Formula: "if col > 'notch1_lower' and col < 'notch1_upper' then self[1,col] * 'notch1_attenuation' else if col > 'notch2_lower' and col < 'notch2_upper' then self[1,col] * 'notch2_attenuation' else self[1,col] * 'overall_attenuation' fi fi"

# Convert back to sound
result = To Sound

# Rename result
Rename: originalName$ + "_notched"

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