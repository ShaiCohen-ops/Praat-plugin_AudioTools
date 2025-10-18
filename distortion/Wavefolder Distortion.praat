# ============================================================
# Praat AudioTools - Wavefolder Distortion.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Wavefolder Distortion script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# Wavefolder Distortion 

form Wavefolder Distortion
    optionmenu Preset: 1
        option "Default (balanced)"
        option "Gentle Fold"
        option "Aggressive Fold"
        option "Lo-Fi Harsh"
        option "Custom"
    positive Number_of_folds 4
    positive Drive 2.5
    positive Symmetry 0.7
    positive Bit_reduction 8
    positive High_pass_filter 100
    boolean Normalize 1
endform

# Apply preset values if not Custom
if preset = 1
    # Default (balanced)
    number_of_folds = 4
    drive = 2.5
    symmetry = 0.7
    bit_reduction = 8
    high_pass_filter = 100
    normalize = 1
elsif preset = 2
    # Gentle Fold
    number_of_folds = 2
    drive = 1.6
    symmetry = 0.8
    bit_reduction = 12
    high_pass_filter = 80
    normalize = 1
elsif preset = 3
    # Aggressive Fold
    number_of_folds = 6
    drive = 4.0
    symmetry = 0.6
    bit_reduction = 6
    high_pass_filter = 120
    normalize = 1
elsif preset = 4
    # Lo-Fi Harsh
    number_of_folds = 5
    drive = 3.0
    symmetry = 0.65
    bit_reduction = 4
    high_pass_filter = 150
    normalize = 1
endif

# Check if a sound is selected
if !selected("Sound")
    beginPause("No sound selected")
        comment("Please select a sound object first")
    endPause("OK", 1)
    exitScript()
endif

sound = selected("Sound")
original_name$ = selected$("Sound")

# Create working copy
select sound
Copy: "temp_wavefolded"

# Apply wavefolding distortion
Formula: "sin(self * drive * 10) * 0.8"

for i from 1 to number_of_folds
    Formula: "if self > symmetry then symmetry - (self - symmetry) else self fi"
    Formula: "if self < -symmetry then -symmetry - (self + symmetry) else self fi"
    Formula: "self * 1.2"
endfor

# Apply bit reduction
Formula: "round(self * bit_reduction) / bit_reduction"

# Apply high-pass filter using a different method
Filter (formula): "if x < high_pass_filter then 0 else self fi"

# Normalize if requested
if normalize
    Scale peak: 0.9
endif

# Final naming
Rename: "'original_name$'_wavefolded"
Play

# Clean up temporary objects
select Sound temp_wavefolded
Remove

# Select the final result
select Sound 'original_name$'_wavefolded
