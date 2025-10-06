# ============================================================
# Praat AudioTools - Granular_Displacement.praat
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

form Granular Displacement
    comment This script applies different delays to time segments
    positive tail_duration_seconds 2
    natural number_of_grains 8
    comment Delay range (in samples):
    positive delay_min 10
    positive delay_divisor 4
    comment (max delay = grain_size / divisor)
    comment Amplitude range:
    positive amplitude_min 0.2
    positive amplitude_max 0.8
    positive scale_peak 0.99
    boolean play_after_processing 1
endform

if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

original_sound$ = selected$("Sound")
select Sound 'original_sound$'
sampling_rate = Get sample rate
channels = Get number of channels

# Create silent tail
if channels = 2
    Create Sound from formula: "silent_tail", 2, 0, tail_duration_seconds, sampling_rate, "0"
else
    Create Sound from formula: "silent_tail", 1, 0, tail_duration_seconds, sampling_rate, "0"
endif

# Concatenate
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
    
    # Process left
    select Sound left_channel
    Copy: "soundObj_left"
    a = Get number of samples
    grain_size = a / number_of_grains
    for grain from 1 to number_of_grains
        grain_delay = randomUniform(delay_min, grain_size/delay_divisor)
        grain_amplitude = randomUniform(amplitude_min, amplitude_max)
        start_sample = (grain - 1) * grain_size + 1
        end_sample = grain * grain_size
        Formula (part): start_sample, end_sample, 1, 1, "self + 'grain_amplitude' * (self[col+'grain_delay'] - self[col])"
    endfor
    Scale peak: scale_peak
    
    # Process right (slightly different parameters)
    select Sound right_channel
    Copy: "soundObj_right"
    a = Get number of samples
    grain_size = a / number_of_grains
    for grain from 1 to number_of_grains
        grain_delay = randomUniform(15, grain_size/3.5)
        grain_amplitude = randomUniform(0.15, 0.75)
        start_sample = (grain - 1) * grain_size + 1
        end_sample = grain * grain_size
        Formula (part): start_sample, end_sample, 1, 1, "self + 'grain_amplitude' * (self[col+'grain_delay'] - self[col])"
    endfor
    Scale peak: scale_peak
    
    # Combine
    select Sound soundObj_left
    plus Sound soundObj_right
    Combine to stereo
    Rename: original_sound$ + "_granular"
    
    removeObject: "Sound soundObj_left", "Sound soundObj_right"
    
else
    Copy: "soundObj"
    a = Get number of samples
    grain_size = a / number_of_grains
    for grain from 1 to number_of_grains
        grain_delay = randomUniform(delay_min, grain_size/delay_divisor)
        grain_amplitude = randomUniform(amplitude_min, amplitude_max)
        start_sample = (grain - 1) * grain_size + 1
        end_sample = grain * grain_size
        Formula (part): start_sample, end_sample, 1, 1, "self + 'grain_amplitude' * (self[col+'grain_delay'] - self[col])"
    endfor
    Scale peak: scale_peak
    Convert to stereo
    Rename: original_sound$ + "_granular"
    
    removeObject: "Sound soundObj"
endif

# Cleanup
select Sound silent_tail
plus Sound extended_sound
if channels = 2
    plus Sound left_channel
    plus Sound right_channel
endif
Remove

select Sound 'original_sound$'_granular

if play_after_processing
    Play
endif