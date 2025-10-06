# ============================================================
# Praat AudioTools - Intensity_Rhythmic_Gating.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Dynamic range or envelope control script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Intensity Rhythmic Gating
    comment This script creates rhythmic gating patterns in intensity
    comment Intensity extraction parameters:
    positive minimum_pitch 100
    positive time_step 0.1
    boolean subtract_mean yes
    comment Gating parameters:
    positive gate_frequency 8
    positive minimum_level 0.3
    positive maximum_level 1.0
    comment (effective range will be minimum_level to minimum_level + gate_depth)
    comment Multiply parameters:
    boolean scale_intensities yes
    comment Output options:
    boolean play_after_processing 1
    boolean keep_intermediate_objects 0
endform

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Store original sound
a = selected("Sound")
originalName$ = selected$("Sound")

# Copy the sound
b = Copy: originalName$ + "_gated"

# Extract intensity
To Intensity: minimum_pitch, time_step, subtract_mean

# Calculate gate depth
gate_depth = maximum_level - minimum_level

# Apply rhythmic gating formula
Formula: "self * ('minimum_level' + 'gate_depth' * (sin(x * 'gate_frequency') > 0))"

# Convert to IntensityTier
c = Down to IntensityTier

# Select sound and intensity tier, then multiply
select a
plus c
Multiply: scale_intensities

# Rename result
Rename: originalName$ + "_result"

# Play if requested
if play_after_processing
    Play
endif

# Clean up intermediate objects unless requested to keep
if not keep_intermediate_objects
    select b
    Remove
    select c
    Remove
endif


