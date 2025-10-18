# ============================================================
# Praat AudioTools - Stereo Delay Splitter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Delay or temporal structure script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Stereo Channel Processing
    optionmenu Preset: 1
        option "Default (L:2,4 | R:8,10)"
        option "Narrow Stereo (L:3,5 | R:6,8)"
        option "Wide Stereo (L:2,6 | R:12,18)"
        option "Alt Divisors (L:2,3 | R:9,15)"
        option "Custom"
    comment Left channel divisors (iterations 1-2):
    positive divisor_1 2
    positive divisor_2 4
    comment Right channel divisors (iterations 3-4):
    positive divisor_3 8
    positive divisor_4 10
    comment Left channel iteration range:
    natural left_start 1
    natural left_end 2
    comment Right channel iteration range:
    natural right_start 3
    natural right_end 4
    comment Output options:
    positive scale_peak 0.99
    boolean play_after_processing 1
endform

# Apply preset values if not Custom
if preset = 1
    # Default (L:2,4 | R:8,10)
    divisor_1 = 2
    divisor_2 = 4
    divisor_3 = 8
    divisor_4 = 10
    left_start = 1
    left_end   = 2
    right_start = 3
    right_end   = 4
elsif preset = 2
    # Narrow Stereo (L:3,5 | R:6,8)
    divisor_1 = 3
    divisor_2 = 5
    divisor_3 = 6
    divisor_4 = 8
    left_start = 1
    left_end   = 2
    right_start = 3
    right_end   = 4
elsif preset = 3
    # Wide Stereo (L:2,6 | R:12,18)
    divisor_1 = 2
    divisor_2 = 6
    divisor_3 = 12
    divisor_4 = 18
    left_start = 1
    left_end   = 2
    right_start = 3
    right_end   = 4
elsif preset = 4
    # Alt Divisors (L:2,3 | R:9,15)
    divisor_1 = 2
    divisor_2 = 3
    divisor_3 = 9
    divisor_4 = 15
    left_start = 1
    left_end   = 2
    right_start = 3
    right_end   = 4
endif

# Copy the sound object
Copy... soundObj

# Get the number of samples
a = Get number of samples

# Store divisors
d1 = divisor_1
d2 = divisor_2
d3 = divisor_3
d4 = divisor_4

# --- Left channel processing (channel 1) ---
select Sound soundObj
Extract one channel: 1
for k from left_start to left_end
    n = d'k'
    b = a / n
    Formula: "self[col+b] - self[col]"
endfor
Rename: "Left"

# --- Right channel processing (channel 2) ---
select Sound soundObj
Extract one channel: 2
for k from right_start to right_end
    n = d'k'
    b = a / n
    Formula: "self[col+b] - self[col]"
endfor
Rename: "Right"

# --- Combine back into stereo ---
select Sound Left
plus Sound Right
Combine to stereo
Rename: "soundObj_stereo"
Scale peak: scale_peak

# Clean up temporary objects
select Sound Left
plus Sound Right
plus Sound soundObj
Remove

# Play if requested
select Sound soundObj_stereo
if play_after_processing
    Play
endif
