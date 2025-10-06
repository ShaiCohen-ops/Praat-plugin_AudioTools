# ============================================================
# Praat AudioTools - canon_stereo.praat
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

# --- settings you can tweak
Resample: 44100, 50
override_sf = 49392    ; target nominal rate for the shifted copy (e.g., +7 semitones by rate)
resample_sf = 44100

# must have a Sound selected
if not selected ("Sound")
    exit ("please select a Sound object first.")
endif

# base mono
orig$ = selected$ ("Sound")
select Sound 'orig$'
Copy: "base"
Convert to mono
Rename: "base_mono"

# make one shifted mono copy
select Sound base_mono
Copy: "shift"
Override sampling frequency: 'override_sf'
Resample: 'resample_sf', 50
Convert to mono
Rename: "shift1"

# duplicate it so we can sum three layers on the Right
select Sound shift1
Copy: "shift2"
Copy: "shift3"

# sum the three shifted layers into a mono right_sum
select Sound shift1
plus Sound shift2
Combine to stereo
Rename: "tmpR"
select Sound tmpR
Convert to mono
Rename: "right_sum"

select Sound right_sum
plus Sound shift3
Combine to stereo
Rename: "tmpR"
select Sound tmpR
Convert to mono
Rename: "right_sum"

# left channel is just the base mono
select Sound base_mono
Rename: "left_sum"

# final stereo: Left = left_sum, Right = right_sum
select Sound left_sum
plus Sound right_sum
Combine to stereo
Rename: "canon_result"

# play
select Sound canon_result
Play

# keep only the original input and the output
select all
minusObject: "Sound 'orig$'"
minusObject: "Sound canon_result"
Remove
