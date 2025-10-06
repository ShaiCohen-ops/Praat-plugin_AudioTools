# ============================================================
# Praat AudioTools - Spectral_Decay.praat
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

form Spectral Decay Reverb Effect
    comment Apply spectral decay reverb using Poisson process convolution
    positive Tail_duration_(seconds) 2.0
    positive Impulse_duration_(seconds) 3.0
    positive Poisson_density_(events/s) 2000
    positive Decay_base 110
    positive Wet_level 0.25
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
    Create Poisson process: "spectral_poisson_left", 0, impulse_duration, poisson_density
    selectObject: "PointProcess spectral_poisson_left"
    To Sound (pulse train): sampling_rate, 1, 0.035, 2800
    Rename: "impulse_left"
    selectObject: "Sound impulse_left"
    Formula: "self * 'decay_base'^(-(x-xmin)/(xmax-xmin)) * (1 + 0.7*sin(2*pi*x*150 + (x-xmin)*20))"
    
    # Convolve left channel with left impulse
    select a_left
    plusObject: "Sound impulse_left"
    b_left = Convolve
    Filter (pass Hann band): 100, 4000, 100
    Multiply: wet_level
    
    # Process right channel with different spectral characteristics
    select Sound right_channel
    a_right = Copy: "soundObj_right"
    
    # Create and process right impulse
    Create Poisson process: "spectral_poisson_right", 0, impulse_duration*0.93, poisson_density*0.95
    selectObject: "PointProcess spectral_poisson_right"
    To Sound (pulse train): sampling_rate, 1, 0.032, 2600
    Rename: "impulse_right"
    selectObject: "Sound impulse_right"
    Formula: "self * ('decay_base'*0.95)^(-(x-xmin)/(xmax-xmin)) * (1 + 0.65*sin(2*pi*x*140 + (x-xmin)*22))"
    
    # Convolve right channel with right impulse
    select a_right
    plusObject: "Sound impulse_right"
    b_right = Convolve
    Filter (pass Hann band): 120, 3800, 90
    Multiply: wet_level*0.92
    
    # Combine original with processed for each channel
    select a_left
    plusObject: b_left
    Combine to stereo
    Convert to mono
    Rename: "result_left"
    
    select a_right
    plusObject: b_right
    Combine to stereo
    Convert to mono
    Rename: "result_right"
    
    # Combine left and right channels to final stereo
    selectObject: "Sound result_left"
    plusObject: "Sound result_right"
    Combine to stereo
    Rename: "spectral_decay_stereo"
    
    # Cleanup
    removeObject: "Sound impulse_left"
    removeObject: "Sound impulse_right"
    removeObject: "PointProcess spectral_poisson_left"
    removeObject: "PointProcess spectral_poisson_right"
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
    Create Poisson process: "spectral_poisson", 0, impulse_duration, poisson_density
    selectObject: "PointProcess spectral_poisson"
    To Sound (pulse train): sampling_rate, 1, 0.035, 2800
    Rename: "impulse"
    selectObject: "Sound impulse"
    Formula: "self * 'decay_base'^(-(x-xmin)/(xmax-xmin)) * (1 + 0.7*sin(2*pi*x*150 + (x-xmin)*20))"
    
    # Convolve with impulse
    select a
    plusObject: "Sound impulse"
    b = Convolve
    Filter (pass Hann band): 100, 4000, 100
    Multiply: wet_level
    
    select a
    plusObject: b
    Combine to stereo
    Convert to mono
    Rename: "spectral_decay_stereo"
    
    removeObject: "Sound impulse"
    removeObject: "PointProcess spectral_poisson"
    removeObject: b
    removeObject: a
endif

# Apply fadeout
select Sound spectral_decay_stereo
total_duration = Get total duration
fade_duration = fadeout_duration
fade_start = total_duration - fade_duration

Formula: "if x > 'fade_start' then self * (0.5 + 0.5 * cos(pi * (x - 'fade_start') / 'fade_duration')) else self fi"

Scale peak: 0.99

# Final cleanup
select Sound silent_tail
plus Sound extended_sound
if channels = 2
    plus Sound left_channel
    plus Sound right_channel
endif
Remove

select Sound spectral_decay_stereo
Play