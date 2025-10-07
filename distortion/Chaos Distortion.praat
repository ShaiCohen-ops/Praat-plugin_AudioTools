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
    positive Drive 3.0
    positive Fold_count 3
    positive Bit_crush 6
    positive Sample_rate_reduction 30
    boolean Add_noise 1
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