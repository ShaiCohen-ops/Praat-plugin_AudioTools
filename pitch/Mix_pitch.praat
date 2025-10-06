# ============================================================
# Praat AudioTools - Mix_pitch.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Pitch-based transformation script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Stereo Pitch Shift Effect
    comment This script creates stereo: original left, pitch-shifted right
    comment Pitch shift parameters:
    positive override_sample_rate 40000
    comment (changes pitch by altering sample rate)
    positive output_sample_rate 44100
    positive resample_precision 50
    comment Output options:
    boolean play_after_processing 1
endform

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Get original sound
orig$ = selected$("Sound")
select Sound 'orig$'

# Create two working copies
Copy: "wrk1"
Copy: "wrk2"

# wrk2: pitch shift via override + resample
select Sound wrk2
Override sampling frequency: override_sample_rate
Resample: output_sample_rate, resample_precision
w2$ = selected$("Sound")

# wrk1: resample to match output rate
select Sound wrk1
Resample: output_sample_rate, resample_precision
w1$ = selected$("Sound")

# Combine to stereo
select Sound 'w1$'
plus Sound 'w2$'
Combine to stereo
Rename: orig$ + "_stereo_shift"

# Play if requested
if play_after_processing
    Play
endif