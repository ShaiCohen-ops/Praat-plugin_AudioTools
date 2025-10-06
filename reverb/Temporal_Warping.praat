# ============================================================
# Praat AudioTools - Temporal_Warping.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Reverberation or diffusion script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Temporal Warping Effect
    comment Apply temporal warping with progressive time displacement
    positive Tail_duration_(seconds) 3.0
    positive Number_of_warp_stages 6
    positive Max_displacement_factor 0.1
    positive Warp_strength 0.3
    positive Fadeout_duration_(seconds) 1.2
endform

original_sound$ = selected$("Sound")
select Sound 'original_sound$'
original_duration = Get total duration
sampling_rate = Get sample rate
channels = Get number of channels

tail_duration = tail_duration
if channels = 2
    Create Sound from formula: "silent_tail", 2, 0, tail_duration, sampling_rate, "0"
else
    Create Sound from formula: "silent_tail", 1, 0, tail_duration, sampling_rate, "0"
endif

select Sound 'original_sound$'
plus Sound silent_tail
Concatenate
Rename: "extended_sound"

select Sound extended_sound

if channels = 2
    Extract one channel: 1
    Rename: "left_channel"
    select Sound extended_sound
    Extract one channel: 2
    Rename: "right_channel"
    
    select Sound left_channel
    Copy: "soundObj_left"
    select Sound soundObj_left
    
    warp_stages = number_of_warp_stages
    a = Get number of samples
    
    for stage from 1 to warp_stages
        warp_factor = stage / warp_stages
        max_displacement = a * max_displacement_factor * warp_factor
        time_curve = sin(pi * stage / warp_stages)
        displacement = max_displacement * randomUniform(0.3, 1.0) * time_curve
        Formula: "self * (1 - 'warp_factor' * 0.1) + 'warp_factor' * 'warp_strength' * (self[col+'displacement'] - self[col])"
    endfor
    
    Scale peak: 0.99
    
    select Sound right_channel
    Copy: "soundObj_right"
    select Sound soundObj_right
    
    warp_stages = number_of_warp_stages
    a = Get number of samples
    
    for stage from 1 to warp_stages
        warp_factor = stage / warp_stages
        max_displacement = a * max_displacement_factor * 1.1 * warp_factor
        time_curve = sin(pi * (stage + 0.5) / warp_stages)
        displacement = max_displacement * randomUniform(0.25, 0.95) * time_curve
        Formula: "self * (1 - 'warp_factor' * 0.12) + 'warp_factor' * ('warp_strength'*0.93) * (self[col+'displacement'] - self[col])"
    endfor
    
    Scale peak: 0.99
    
    select Sound soundObj_left
    plus Sound soundObj_right
    Combine to stereo
    Rename: "temporal_warping_stereo"
    
    removeObject: "Sound soundObj_left"
    removeObject: "Sound soundObj_right"
    
else
    Copy: "soundObj"
    select Sound soundObj
    
    warp_stages = number_of_warp_stages
    a = Get number of samples
    
    for stage from 1 to warp_stages
        warp_factor = stage / warp_stages
        max_displacement = a * max_displacement_factor * warp_factor
        time_curve = sin(pi * stage / warp_stages)
        displacement = max_displacement * randomUniform(0.3, 1.0) * time_curve
        Formula: "self * (1 - 'warp_factor' * 0.1) + 'warp_factor' * 'warp_strength' * (self[col+'displacement'] - self[col])"
    endfor
    
    Scale peak: 0.99
    Convert to stereo
    Rename: "temporal_warping_stereo"
    
    removeObject: "Sound soundObj"
endif

select Sound temporal_warping_stereo
total_duration = Get total duration
fade_duration = fadeout_duration
fade_start = total_duration - fade_duration

Formula: "if x > 'fade_start' then self * (0.5 + 0.5 * cos(pi * (x - 'fade_start') / 'fade_duration')) else self fi"

select Sound silent_tail
plus Sound extended_sound
if channels = 2
    plus Sound left_channel
    plus Sound right_channel
endif
Remove

select Sound temporal_warping_stereo
Play