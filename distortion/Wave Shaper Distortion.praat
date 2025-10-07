# ============================================================
# Praat AudioTools - Wave Shaper Distortion.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Wave Shaper Distortion script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# Wave Shaper Distortion - Mathematical waveform reshaping

form Wave Shaper Distortion
    choice Shape: 1
        option Hyperbolic Tangent (soft)
        option Sine Fold (warm)
        option Arc Tangent (smooth)
        option Polynomial (aggressive)
        option Absolute Value (digital)
        option Square Law (fuzzy)
    positive Drive 2.0
    positive Mix 80
    boolean Normalize 1
endform

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
Copy: "wet_signal"

# Apply drive to wet signal
Formula: "self * drive"

# Apply selected wave shaping function
if shape = 1
    # Hyperbolic Tangent - soft clipping
    Formula: "tanh(self * 2) / 2"
    shape_name$ = "tanh"
elsif shape = 2
    # Sine Fold - warm folding
    Formula: "sin(self * 3) * 0.8"
    shape_name$ = "sinefold"
elsif shape = 3
    # Arc Tangent - smooth saturation
    Formula: "2 * arctan(self * 2) / pi"
    shape_name$ = "arctan"
elsif shape = 4
    # Polynomial - aggressive distortion
    Formula: "self - (self * self * self) * 0.3"
    shape_name$ = "polynomial"
elsif shape = 5
    # Absolute Value - digital rectification
    Formula: "if self > 0 then self else -self fi"
    shape_name$ = "absolute"
elsif shape = 6
    # Square Law - fuzzy distortion
    Formula: "self * (if self > 0 then self else -self fi)"
    shape_name$ = "squarelaw"
endif

# Mix with dry signal if needed
if mix < 100
    select sound
    Copy: "dry_signal"
    select Sound wet_signal
    wet_level = mix / 100
    dry_level = 1 - wet_level
    Formula: "(self * wet_level) + (Sound_dry_signal[] * dry_level)"
    
    # Clean up dry signal
    select Sound dry_signal
    Remove
endif

# Normalize if requested
if normalize
    select Sound wet_signal
    Scale peak: 0.9
endif

# Final naming
Rename: "'original_name$'_shaped_'shape_name$'"
Play

# Select the final result
select Sound 'original_name$'_shaped_'shape_name$'