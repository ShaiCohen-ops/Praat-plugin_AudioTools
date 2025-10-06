# ============================================================
# Praat AudioTools - Spectral_Drift.praat
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

form Spectral Drift Effect
    comment Apply spectral drift processing with frequency-dependent delays
    positive Tail_duration_(seconds) 0.5
    positive Number_of_drift_cycles 4
    positive Base_frequency_(Hz) 100
    positive Effect_strength 0.4
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
    
    drift_cycles = number_of_drift_cycles
    a = Get number of samples
    sample_rate = Get sampling frequency
    
    for cycle from 1 to drift_cycles
        base_freq = base_frequency * cycle
        delay_samples = sample_rate / base_freq
        drift_amount = randomUniform(0.5, 2.0)
        Formula: "self + 'effect_strength' * (self[col+'delay_samples'*'drift_amount'] - self[col]) * cos(2*pi*col*'base_freq'/'sample_rate')"
    endfor
    
    Scale peak: 0.99
    
    select Sound right_channel
    Copy: "soundObj_right"
    select Sound soundObj_right
    
    drift_cycles = number_of_drift_cycles
    a = Get number of samples
    sample_rate = Get sampling frequency
    
    for cycle from 1 to drift_cycles
        base_freq = base_frequency * 1.05 * cycle
        delay_samples = sample_rate / base_freq
        drift_amount = randomUniform(0.6, 1.9)
        Formula: "self + ('effect_strength'*0.95) * (self[col+'delay_samples'*'drift_amount'] - self[col]) * cos(2*pi*col*'base_freq'/'sample_rate')"
    endfor
    
    Scale peak: 0.99
    
    select Sound soundObj_left
    plus Sound soundObj_right
    Combine to stereo
    Rename: "spectral_drift_stereo"
    
    removeObject: "Sound soundObj_left"
    removeObject: "Sound soundObj_right"
    
else
    Copy: "soundObj"
    select Sound soundObj
    
    drift_cycles = number_of_drift_cycles
    a = Get number of samples
    sample_rate = Get sampling frequency
    
    for cycle from 1 to drift_cycles
        base_freq = base_frequency * cycle
        delay_samples = sample_rate / base_freq
        drift_amount = randomUniform(0.5, 2.0)
        Formula: "self + 'effect_strength' * (self[col+'delay_samples'*'drift_amount'] - self[col]) * cos(2*pi*col*'base_freq'/'sample_rate')"
    endfor
    
    Scale peak: 0.99
    Convert to stereo
    Rename: "spectral_drift_stereo"
    
    removeObject: "Sound soundObj"
endif

select Sound spectral_drift_stereo
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

select Sound spectral_drift_stereo
Play