# ============================================================
# Praat AudioTools - Dynamic Spectral Hole.praat
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

form Pitch-Based Spectral Notch
    comment This script creates a notch filter based on pitch analysis
    comment WARNING: This process can have long runtime on long files
    comment due to FFT calculations
    comment Pitch analysis parameters:
    positive time_step 0.1
    positive minimum_pitch 75
    positive maximum_pitch 600
    comment Notch range parameters:
    positive octave_multiplier 2
    comment (notch upper bound = mean pitch * multiplier)
    comment Notch attenuation:
    positive notch_attenuation 0.1
    comment (multiplier for frequencies within notch range)
    comment Spectrum parameters:
    boolean fast_fourier no
    comment Output options:
    positive scale_peak 0.99
    boolean play_after_processing 1
    boolean keep_intermediate_objects 0
endform

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Get the original sound
a = selected("Sound")
originalName$ = selected$("Sound")

# Extract pitch to determine notch range
c = To Pitch: time_step, minimum_pitch, maximum_pitch
lo = Get mean: 0, 0, "Hertz"
hi = lo * octave_multiplier

# Convert sound to spectrum
select a
d = To Spectrum: fast_fourier

# Apply notch filter in the pitch-based frequency range
Formula: "if x >= lo and x <= hi then self * 'notch_attenuation' else self fi"

# Convert back to sound
b = To Sound

# Rename result
Rename: originalName$ + "_pitch_notched"

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    select b
    Play
endif

# Clean up intermediate objects unless requested to keep
if not keep_intermediate_objects
    removeObject: c, d
endif

# Select final result
select b