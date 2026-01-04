# ============================================================
# Praat AudioTools - Chaos Distortion.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Chaos Distortion script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# Chaos Distortion - Multiple distortion effects combined

form Chaos Distortion
    optionmenu Preset: 1
        option "Default (balanced)"
        option "Gentle Grit"
        option "Heavy Crush"
        option "Lo-Fi Glitch"
        option "Clean Boost"
        option "Custom"
    positive Drive 3.0
    positive Fold_count 3
    positive Bit_crush 6
    positive Sample_rate_reduction 30
    boolean Add_noise 1
    boolean Normalize 1
endform

# Apply preset values if not Custom
if preset = 1
    # Default (balanced)
    drive = 3.0
    fold_count = 3
    bit_crush = 6
    sample_rate_reduction = 30
    add_noise = 1
    normalize = 1
elsif preset = 2
    # Gentle Grit
    drive = 1.6
    fold_count = 1
    bit_crush = 8
    sample_rate_reduction = 85
    add_noise = 0
    normalize = 1
elsif preset = 3
    # Heavy Crush
    drive = 4.5
    fold_count = 5
    bit_crush = 4
    sample_rate_reduction = 40
    add_noise = 1
    normalize = 1
elsif preset = 4
    # Lo-Fi Glitch
    drive = 2.2
    fold_count = 2
    bit_crush = 3
    sample_rate_reduction = 20
    add_noise = 1
    normalize = 1
elsif preset = 5
    # Clean Boost
    drive = 1.25
    fold_count = 0
    bit_crush = 12
    sample_rate_reduction = 100
    add_noise = 0
    normalize = 1
endif

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
Copy: "chaos_temp"

# Apply wave folding distortion
Formula: "self * drive"
for i from 1 to fold_count
    Formula: "if self > 0.7 then 0.7 - (self - 0.7) else self fi"
    Formula: "if self < -0.7 then -0.7 - (self + 0.7) else self fi"
endfor

# Apply bit crushing
levels = 2 ^ bit_crush
Formula: "round(self * levels) / levels"

# Apply sample rate reduction
current_rate = Get sample rate
new_rate = current_rate * (sample_rate_reduction / 100)
if new_rate < 1000
    new_rate = 1000
endif
Resample: new_rate, 50
Resample: current_rate, 50

# Add noise if requested
if add_noise
    Formula: "self + (randomUniform(-0.1, 0.1) * 0.3)"
endif

# Normalize if requested
if normalize
    Scale peak: 0.9
endif

# Final naming
Rename: "'original_name$'_chaos"
Play

# Clean up
select Sound chaos_temp
Remove

# Select the final result
select Sound 'original_name$'_chaos
