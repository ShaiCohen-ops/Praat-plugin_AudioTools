# ============================================================
# Praat AudioTools - Non-Linear Frequency Folding.praat
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

form Spectral Knots - Non-Linear Frequency Folding
    comment This script applies non-linear frequency folding with modulation
    comment WARNING: This process can have long runtime on long files
    comment due to FFT calculations
    comment Spectrum parameters:
    boolean fast_fourier yes
    comment Low frequency preservation:
    positive low_freq_threshold 100
    comment (frequencies below this are preserved unchanged)
    comment Folding parameters:
    positive folding_period 1000
    comment (period for frequency folding in Hz)
    comment Modulation parameters:
    positive sine_modulation_divisor 300
    positive cosine_modulation_divisor 150
    comment (control the interference pattern)
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
sampling_rate = Get sampling frequency

# Convert to spectrum
spectrum = To Spectrum: fast_fourier

# Apply spectral knots with non-linear frequency folding
# Low frequencies preserved, high frequencies folded and modulated
Formula: "if col < 'low_freq_threshold' then self[1,col] else self[1, abs(col - 2 * round(col/'folding_period') * 'folding_period')] * (sin(col/'sine_modulation_divisor') + cos(col/'cosine_modulation_divisor'))^2 fi"

# Convert back to sound
result = To Sound

# Rename result
Rename: originalName$ + "_spectral_knots"

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