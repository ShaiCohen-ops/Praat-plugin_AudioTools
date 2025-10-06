# ============================================================
# Praat AudioTools - Basic Mirror.praat
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

form Spectral Mirroring
    comment This script mirrors the lower half of the spectrum
    comment WARNING: This process can have long runtime on long files
    comment due to FFT calculations
    comment Spectrum parameters:
    boolean fast_fourier yes
    comment Mirroring parameters:
    positive cutoff_divisor 2
    comment (2 = mirror below nyquist/2, 4 = mirror below nyquist/4)
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

# Calculate Nyquist frequency
nyquist = sampling_rate / 2

# Calculate cutoff frequency
cutoff = nyquist / cutoff_divisor

# Apply spectral mirroring formula
Formula: "if col < cutoff then self[1,col] + self[1,nyquist-col] else self[1,col] fi"

# Convert back to sound
result = To Sound

# Rename result
Rename: originalName$ + "_spectral_mirrored"

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