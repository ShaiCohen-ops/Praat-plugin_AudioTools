# ============================================================
# Praat AudioTools - Bit Crusher (8-Bit Arcade).praat
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

form Spectral Quantization
    comment This script applies low-bit quantization to the spectrum
    comment WARNING: This process can have long runtime on long files
    comment due to FFT calculations
    comment Spectrum parameters:
    boolean fast_fourier no
    comment (use "no" for precise control)
    comment Quantization frequency range:
    positive lower_frequency 200
    positive upper_frequency 3000
    comment Quantization parameters:
    positive quantization_steps 2
    comment (number of quantization levels: lower = more extreme)
    comment Outside range attenuation:
    positive outside_range_multiplier 0.5
    comment (applied to frequencies outside the range)
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

# Apply spectral quantization
# Frequencies within range are quantized, outside range are attenuated
Formula: "if x >= 'lower_frequency' and x <= 'upper_frequency' then self * (round('quantization_steps' * (x - 'lower_frequency') / ('upper_frequency' - 'lower_frequency')) / 'quantization_steps') else self * 'outside_range_multiplier' fi"

# Convert back to sound
result = To Sound

# Rename result
Rename: originalName$ + "_spectral_quantized"

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