# ============================================================
# Praat AudioTools - Vocoding.praat
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

form Noise Vocoder
    comment This script creates a noise vocoder effect
    comment Vocoder band parameters:
    natural number_of_bands 16
    positive lower_frequency_limit 50
    positive upper_frequency_limit 11000
    comment Intensity extraction:
    positive minimum_pitch 100
    positive time_step 0.1
    comment Filter parameters:
    positive filter_smoothing 50
    positive filter_edge_buffer 25
    comment (Hz to trim from band edges for smoothing)
    comment Noise generation:
    positive noise_amplitude 0.1
    comment Output options:
    boolean play_after_processing 1
    boolean keep_intermediate_objects 0
endform

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Get the source sound
s1 = selected("Sound", 1)
s1$ = selected$("Sound", 1)
t = Get total duration

# Calculate sampling rate
sr = 2 * upper_frequency_limit + 1000

# Clear info window
clearinfo

# Convert frequency limits to Bark scale
blowerLim = hertzToBark(lower_frequency_limit)
bupperLim = hertzToBark(upper_frequency_limit)
step = (bupperLim - blowerLim) / number_of_bands

# Process each frequency band
for i from 1 to number_of_bands
    # Add previous bands if not first iteration
    if i > 1
        j = i - 1
        select Sound band'j'
        Rename: "previous"
    endif
    
    # Calculate band limits
    bandUpper = blowerLim + i * step
    bandLower = bandUpper - step
    temp1 = round(barkToHertz(bandLower))
    temp2 = round(barkToHertz(bandUpper))
    
    # Print band information
    appendInfoLine: "Band ", i, " from ", temp1, " to ", temp2, " Hz"
    
    # Account for filter smoothing
    temp1 = temp1 + filter_edge_buffer
    temp2 = temp2 - filter_edge_buffer
    
    # Extract energy from source in this band
    select s1
    Filter (pass Hann band): temp1, temp2, filter_smoothing
    
    # Get overall RMS in band
    rms_SOURCE = Get root-mean-square: 0, 0
    Rename: "temp"
    
    # Extract intensity contour
    To Intensity: minimum_pitch, time_step, "yes"
    Down to IntensityTier
    
    # Create noise band
    Create Sound: "noise", 0, t, sr, "randomGauss(0, noise_amplitude)"
    Filter (pass Hann band): temp1, temp2, filter_smoothing
    
    # Apply intensity contour to noise
    plus IntensityTier temp
    Multiply: "no"
    
    # Adjust overall amplitude to match source
    rms_IS = Get root-mean-square: 0, 0
    Formula: "self * (rms_SOURCE / rms_IS)"
    Rename: "band'i'"
    
    # Add previous bands
    if i > 1
        Formula: "self[col] + Sound_previous[col]"
    endif
    
    # Clean up intermediate objects
    select all
    minus s1
    minus Sound band'i'
    Remove
endfor

# Select final result
select Sound band'number_of_bands'
Rename: s1$ + "_vocoded"

# Play if requested
if play_after_processing
    Play
endif

# Keep or remove intermediate objects
if not keep_intermediate_objects
    # The final sound is already renamed, so intermediate bands are removed
endif
