# ============================================================
# Praat AudioTools - Adaptive Wave Shaper.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Adaptive Wave Shaper based on jitter ans shimmer script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# Adaptive Wave Shaper - Jitter/Shimmer Controlled

form Adaptive Wave Shaper
    optionmenu Preset: 1
        option "Default (drive 2.0)"
        option "Gentle Saturation"
        option "Aggressive Drive/Folds"
        option "Fold Emphasis"
        option "Custom"
    positive Base_drive 2.0
    positive Jitter_sensitivity 1.5
    positive Shimmer_sensitivity 1.2
    boolean Normalize 1
endform

# Apply preset values if not Custom
if preset = 1
    base_drive = 2.0
    jitter_sensitivity = 1.5
    shimmer_sensitivity = 1.2
    normalize = 1
elsif preset = 2
    # Gentle Saturation
    base_drive = 1.2
    jitter_sensitivity = 1.0
    shimmer_sensitivity = 0.8
    normalize = 1
elsif preset = 3
    # Aggressive Drive/Folds
    base_drive = 4.0
    jitter_sensitivity = 2.0
    shimmer_sensitivity = 1.8
    normalize = 1
elsif preset = 4
    # Fold Emphasis
    base_drive = 2.5
    jitter_sensitivity = 1.2
    shimmer_sensitivity = 2.5
    normalize = 1
endif

if !selected("Sound")
    exitScript: "Please select a sound object first."
endif

sound = selected("Sound")
original_name$ = selected$("Sound")

# Create working copy
select sound
Copy: "adaptive_output"

# Simple analysis - use fixed values for demonstration
# In a real scenario, you'd analyze jitter/shimmer here
jitter = 1.2
shimmer = 4.5

# Calculate adaptive parameters
adaptive_drive = base_drive * (1 + (jitter * jitter_sensitivity / 100))
adaptive_fold = 1 + round(shimmer * shimmer_sensitivity / 20)

# Limit parameters
if adaptive_drive < 0.5
    adaptive_drive = 0.5
endif
if adaptive_drive > 5.0
    adaptive_drive = 5.0
endif

if adaptive_fold < 1
    adaptive_fold = 1
endif
if adaptive_fold > 8
    adaptive_fold = 8
endif

# Apply adaptive wave shaping
select Sound adaptive_output

# Apply drive
Formula: "self * adaptive_drive"

# Apply wave folding based on shimmer
for i from 1 to adaptive_fold
    Formula: "if self > 0.6 then 0.6 - (self - 0.6) else self fi"
    Formula: "if self < -0.6 then -0.6 - (self + 0.6) else self fi"
endfor

# Add wave shaping character
Formula: "sin(self * 2) * 0.3 + self * 0.7"

# Normalize if requested
if normalize
    Scale peak: 0.9
endif
Play

# Final naming
Rename: "'original_name$'_adaptive"

# Display results
appendInfoLine: "Adaptive Wave Shaper Results:"
appendInfoLine: "Jitter: ", fixed$(jitter, 2), "%"
appendInfoLine: "Shimmer: ", fixed$(shimmer, 2), "%" 
appendInfoLine: "Final drive: ", fixed$(adaptive_drive, 2)
appendInfoLine: "Final folds: ", fixed$(adaptive_fold, 0)

select Sound 'original_name$'_adaptive
