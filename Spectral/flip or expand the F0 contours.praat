# ============================================================
# Praat AudioTools - flip or expand the F0 contours.praat
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

form F0 Contour Manipulation
    comment This script manipulates F0 contours using PSOLA
    comment Presets:
    optionmenu preset: 1
        option Default
        option Wide Pitch Range
        option Strong Expansion
        option Subtle Flattening
        option High Flatten Target
    comment Pitch analysis range:
    positive minimum_pitch 70
    positive maximum_pitch 250
    comment Manipulation method:
    optionmenu method 1
        option Flip F0 contour
        option Expand/Contract F0 contour
        option Flatten F0 contour
    comment Expansion/Contraction settings (for method 2):
    positive expansion_multiplier 1.3
    comment (values > 1 expand, < 1 contract)
    comment Flattening settings (for method 3):
    positive flatten_target 1
    comment (0 = use mean pitch, or specify Hz value)
    comment Output options:
    sentence output_suffix _f0_modified
    boolean play_after_processing 1
    boolean keep_intermediate_objects 0
endform

# Apply preset values
if preset = 2 ; Wide Pitch Range
    minimum_pitch = 50
    maximum_pitch = 400
elif preset = 3 ; Strong Expansion
    expansion_multiplier = 2.0
elif preset = 4 ; Subtle Flattening
    flatten_target = 0
elif preset = 5 ; High Flatten Target
    flatten_target = 200
endif

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Get the original sound
originalSound = selected("Sound")
soundName$ = selected$("Sound")

# Create manipulation object
manipulation = To Manipulation: 0.01, minimum_pitch, maximum_pitch

# Extract pitch tier
pitchTier = Extract pitch tier

# Get mean pitch
meanPitch = Get mean (points): 0, 0

# Apply the selected manipulation method
if method = 1
    # Flip F0 contour around the mean
    Formula: "meanPitch - (self - meanPitch)"
    
elsif method = 2
    # Expand/Contract F0 contour around the mean
    Formula: "meanPitch - ((meanPitch - self) * expansion_multiplier)"
    
elsif method = 3
    # Flatten F0 contour
    if flatten_target = 0
        target_level = meanPitch
    else
        target_level = flatten_target
    endif
    Formula: "target_level"
endif

# Replace pitch tier in manipulation object
select manipulation
plus pitchTier
Replace pitch tier

# Resynthesize sound
select manipulation
result = Get resynthesis (overlap-add)

# Rename result
Rename: soundName$ + output_suffix$

# Play if requested
if play_after_processing
    Play
endif

# Clean up intermediate objects unless requested to keep
if not keep_intermediate_objects
    select manipulation
    plus pitchTier
    Remove
endif
