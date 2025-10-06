# ============================================================
# Praat AudioTools - Temporal_Erosion.praat
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

form Temporal Erosion Effect
    comment Apply temporal erosion reverb with logarithmic decay
    positive Tail_duration_(seconds) 3.0
    positive Impulse_duration_(seconds) 5.0
    positive Poisson_density_(events/s) 2500
    positive Wet_level 0.28
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
    
    # Process left channel
    select Sound left_channel
    a_left = Copy: "soundObj_left"
    
    # Create and process left impulse
    Create Poisson process: "erosion_poisson_left", 0, impulse_duration, poisson_density
    selectObject: "PointProcess erosion_poisson_left"
    To Sound (pulse train): sampling_rate, 1, 0.02, 4000
    Rename: "impulse_left"
    selectObject: "Sound impulse_left"
    Formula: "self * (1 - log10(1 + 9*(x-xmin)/(xmax-xmin))) * randomGauss(1, 0.3)"
    
    # Convolve left channel with left impulse
    select a_left
    plusObject: "Sound impulse_left"
    b_left = Convolve
    Multiply: wet_level
    Filter (pass Hann band): 100, 8000, 100
    
    # Process right channel with different erosion characteristics
    select Sound right_channel
    a_right = Copy: "soundObj_right"
    
    # Create and process right impulse
    Create Poisson process: "erosion_poisson_right", 0, impulse_duration*0.96, poisson_density*0.92
    selectObject: "PointProcess erosion_poisson_right"
    To Sound (pulse train): sampling_rate, 1, 0.018, 3800
    Rename: "impulse_right"
    selectObject: "Sound impulse_right"
    Formula: "self * (1 - log10(1 + 8.5*(x-xmin)/(xmax-xmin))) * randomGauss(1, 0.35)"
    
    # Convolve right channel with right impulse
    select a_right
    plusObject: "Sound impulse_right"
    b_right = Convolve
    Multiply: wet_level*0.93
    Filter (pass Hann band): 120, 7500, 90
    
    # Combine original with processed for each channel
    select a_left
    plusObject: b_left
    Combine to stereo
    Convert to mono
    Rename: "result_left"
    Scale peak: 0.92
    
    select a_right
    plusObject: b_right
    Combine to stereo
    Convert to mono
    Rename: "result_right"
    Scale peak: 0.92
    
    # Combine left and right channels to final stereo
    selectObject: "Sound result_left"
    plusObject: "Sound result_right"
    Combine to stereo
    Rename: "temporal_erosion_stereo"
    
    # Cleanup
    removeObject: "Sound impulse_left"
    removeObject: "Sound impulse_right"
    removeObject: "PointProcess erosion_poisson_left"
    removeObject: "PointProcess erosion_poisson_right"
    removeObject: b_left
    removeObject: b_right
    removeObject: a_left
    removeObject: a_right
    removeObject: "Sound result_left"
    removeObject: "Sound result_right"
    
else
    # Mono processing
    a = Copy: "soundObj"
    
    # Create and process impulse
    Create Poisson process: "erosion_poisson", 0, impulse_duration, poisson_density
    selectObject: "PointProcess erosion_poisson"
    To Sound (pulse train): sampling_rate, 1, 0.02, 4000
    Rename: "impulse"
    selectObject: "Sound impulse"
    Formula: "self * (1 - log10(1 + 9*(x-xmin)/(xmax-xmin))) * randomGauss(1, 0.3)"
    
    # Convolve with impulse
    select a
    plusObject: "Sound impulse"
    b = Convolve
    Multiply: wet_level
    Filter (pass Hann band): 100, 8000, 100
    
    select a
    plusObject: b
    Combine to stereo
    Convert to mono
    Rename: "temporal_erosion_stereo"
    Scale peak: 0.92
    
    removeObject: "Sound impulse"
    removeObject: "PointProcess erosion_poisson"
    removeObject: b
    removeObject: a
endif

# Apply fadeout
select Sound temporal_erosion_stereo
total_duration = Get total duration
fade_duration = fadeout_duration
fade_start = total_duration - fade_duration

Formula: "if x > 'fade_start' then self * (0.5 + 0.5 * cos(pi * (x - 'fade_start') / 'fade_duration')) else self fi"

# Final cleanup
select Sound silent_tail
plus Sound extended_sound
if channels = 2
    plus Sound left_channel
    plus Sound right_channel
endif
Remove

select Sound temporal_erosion_stereo
Play