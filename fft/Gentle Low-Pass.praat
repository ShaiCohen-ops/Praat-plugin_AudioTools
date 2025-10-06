# ============================================================
# Praat AudioTools - Gentle Low-Pass.praat
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

form Exponential Low-Pass Filter
    comment This script applies exponential roll-off to lower frequencies
    comment WARNING: This process can have long runtime on long files
    comment due to FFT calculations
    comment Spectrum parameters:
    boolean fast_fourier yes
    comment Filter parameters:
    positive frequency_cutoff 10000
    comment (frequencies below this are exponentially attenuated)
    positive decay_rate 5000
    comment (controls steepness: lower = steeper rolloff)
    comment Output options:
    positive scale_peak 0.90
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

# Apply exponential low-pass filter
# Frequencies below cutoff are attenuated exponentially
# exp(-col/decay_rate) creates smooth rolloff
Formula: "if col < 'frequency_cutoff' then self[1,col] * exp(-col/'decay_rate') else self[1,col] fi"

# Convert back to sound
result = To Sound

# Rename result
Rename: originalName$ + "_exp_lowpass"

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