# ============================================================
# Praat AudioTools - Exponential Glide Up.praat
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

form Pitch Glide Up Effect
    comment This script creates an exponential pitch rise
    comment Pitch shift parameters:
    positive semitones_rise 7
    comment (total pitch rise in semitones)
    positive curve_steepness 3
    comment (higher = faster initial rise)
    comment Manipulation parameters:
    positive time_step 0.01
    positive minimum_pitch 50
    positive maximum_pitch 900
    comment Duration tier sampling:
    natural number_of_points 21
    comment Resampling:
    positive resample_precision 50
    comment Output options:
    boolean play_after_processing 1
    boolean keep_intermediate_objects 0
endform

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

originalName$ = selected$("Sound")
orig_sr = Get sampling frequency

# Calculate maximum pitch ratio
ratio_max = exp((ln(2) / 12) * semitones_rise)

# Create working copy and shift pitch globally
Copy: originalName$ + "_tmp"
Override sampling frequency: orig_sr * ratio_max

# Create manipulation for time-stretch correction
To Manipulation: time_step, minimum_pitch, maximum_pitch
Extract duration tier
Rename: originalName$ + "_dt"

# Clear existing points and get time range
select DurationTier 'originalName$'_dt
Remove points between: 0, 0
xmin = Get start time
xmax = Get end time
dur = xmax - xmin

# Sample exponential curve at evenly spaced times
for j from 0 to number_of_points - 1
    u = j / (number_of_points - 1)
    f = 1 + (ratio_max - 1) * (1 - exp(-curve_steepness * u)) / (1 - exp(-curve_steepness + 1e-9))
    d = ratio_max / f
    t = xmin + u * dur
    Add point: t, d
endfor

# Replace duration tier and resynthesize
select Manipulation 'originalName$'_tmp
plus DurationTier 'originalName$'_dt
Replace duration tier

select Manipulation 'originalName$'_tmp
result = Get resynthesis (overlap-add)
Rename: originalName$ + "_glideUp"
Resample: orig_sr, resample_precision

# Play if requested
if play_after_processing
    Play
endif

# Cleanup
if not keep_intermediate_objects
    select Manipulation 'originalName$'_tmp
    plus DurationTier 'originalName$'_dt
    Remove
endif

select Sound 'originalName$'_glideUp

