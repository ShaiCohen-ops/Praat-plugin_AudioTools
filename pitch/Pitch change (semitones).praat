# ============================================================
# Praat AudioTools - Pitch change (semitones).praat
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

form Pitch change (semitones)
    real note_semitone 4
endform

# Assumes a Sound is selected
Copy... tmp_src

# Ratios & rates
fs = Get sampling frequency
semitone_ratio = 2 ^ (1/12)
note_ratio = semitone_ratio ^ note_semitone
newfs = fs * note_ratio

# Speed shift via metadata override
select Sound tmp_src
Override sampling frequency... 'newfs'

# Preserve duration via Manipulation + DurationTier
To Manipulation... 0.01 75 600
Extract duration tier
Add point... 0 'note_ratio'
select Manipulation tmp_src
plus DurationTier tmp_src
Replace duration tier
select Manipulation tmp_src
Get resynthesis (overlap-add)
Rename... pitch_shifted

# Return to original sampling rate
select Sound pitch_shifted
Resample... 'fs' 50

# Clean up working objects
select DurationTier tmp_src
Remove
select Manipulation tmp_src
Remove
select Sound tmp_src
Remove

# Listen
select Sound pitch_shifted
Play
