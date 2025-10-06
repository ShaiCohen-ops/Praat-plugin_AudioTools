# ============================================================
# Praat AudioTools - PITCH_MORPHING_BETWEEN_TARGETS.praat
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

form Pitch Morphing Between Targets
    comment This script morphs pitch through multiple target values
    sentence target_pitches 0_12_-8_15_-12_20_5_-5
    comment (underscore-separated semitone values)
    comment Morphing behavior:
    positive morph_smoothness 1.5
    comment (higher = smoother transitions)
    positive overshoot_factor 0.4
    comment (elastic overshoot amount)
    comment Dynamics:
    positive tension_strength 0.1
    positive vibrato_amount 0.3
    positive vibrato_frequency 25
    comment Pitch analysis:
    positive time_step 0.005
    positive minimum_pitch 50
    positive maximum_pitch 900
    comment Resolution:
    natural number_of_points 300
    comment Output:
    positive output_sample_rate 44100
    positive resample_precision 50
    boolean play_after_processing 1
    boolean keep_intermediate_objects 0
endform

if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

originalName$ = selected$("Sound")
orig_sr = Get sampling frequency

# Parse target pitches
targets$ = target_pitches$ + " "
targets$ = replace$(targets$, "_", " ", 0)
n_targets = 0

repeat
    space_pos = index(targets$, " ")
    if space_pos > 1
        n_targets += 1
        target_val$[n_targets] = left$(targets$, space_pos - 1)
        targets$ = right$(targets$, length(targets$) - space_pos)
    endif
until space_pos <= 1

Copy: originalName$ + "_morph_tmp"
To Manipulation: time_step, minimum_pitch, maximum_pitch
Extract pitch tier
Rename: originalName$ + "_morph_pitch"

select PitchTier 'originalName$'_morph_pitch
Remove points between: 0, 0
xmin = Get start time
xmax = Get end time
dur = xmax - xmin

for i from 0 to number_of_points - 1
    t = xmin + (i / (number_of_points - 1)) * dur
    u = (t - xmin) / dur * (n_targets - 1)
    
    target_low = floor(u) + 1
    target_high = target_low + 1
    
    if target_high > n_targets
        target_high = n_targets
        target_low = n_targets
    endif
    
    fraction = u - floor(u)
    elastic_curve = fraction^morph_smoothness / (fraction^morph_smoothness + (1 - fraction)^morph_smoothness)
    overshoot = overshoot_factor * sin(fraction * pi) * (1 - fraction) * fraction
    smooth_fraction = elastic_curve + overshoot
    
    pitch_low = number(target_val$[target_low])
    pitch_high = number(target_val$[target_high])
    
    pitch_distance = abs(pitch_high - pitch_low)
    tension = 1 + tension_strength * pitch_distance * sin(fraction * 3 * pi)
    
    interpolated_pitch = pitch_low + smooth_fraction * (pitch_high - pitch_low)
    vibrato = vibrato_amount * sin(fraction * vibrato_frequency * pi) * (1 - abs(2 * fraction - 1))
    
    final_pitch = interpolated_pitch * tension + vibrato
    ratio = exp((ln(2) / 12) * final_pitch)
    
    Add point: t, ratio
endfor

select Manipulation 'originalName$'_morph_tmp
plus PitchTier 'originalName$'_morph_pitch
Replace pitch tier

select Manipulation 'originalName$'_morph_tmp
result = Get resynthesis (overlap-add)
Rename: originalName$ + "_morph_result"
Resample: output_sample_rate, resample_precision

if play_after_processing
    Play
endif

if not keep_intermediate_objects
    select Manipulation 'originalName$'_morph_tmp
    plus PitchTier 'originalName$'_morph_pitch
    Remove
endif

select Sound 'originalName$'_morph_result