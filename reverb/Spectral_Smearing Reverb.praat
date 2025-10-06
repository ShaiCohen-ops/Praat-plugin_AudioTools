# ============================================================
# Praat AudioTools - Spectral_Smearing Reverb.praat
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

form Spectral Smearing Effect
    comment Apply frequency-dependent smearing reverb
    positive Tail_duration_(seconds) 1.5
    positive Number_of_frequency_bands 20
    positive Time_stretch_factor 0.6
    positive Base_amplitude 0.35
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
    Copy: "reverb_copy_left"
    select Sound reverb_copy_left
    
    freq_bands = number_of_frequency_bands
    time_stretch = time_stretch_factor
    
    for band from 1 to freq_bands
        center_freq = 80 * (2 ^ (band/2.5))
        delay_time = time_stretch * (1/sqrt (center_freq/80))
        freq_response = (1/(1+((center_freq - 600)/800)^2))
        amplitude = base_amplitude * freq_response * randomUniform (0.7, 1.3)
        mod_freq = center_freq / 15
        Formula: "self + 'amplitude' * self(x - 'delay_time') * (0.3 + 0.7*cos(2*pi*x*'mod_freq'))"
    endfor
    
    # Process right channel with different spectral characteristics
    select Sound right_channel
    Copy: "reverb_copy_right"
    select Sound reverb_copy_right
    
    freq_bands = number_of_frequency_bands
    time_stretch = time_stretch_factor * 0.92
    
    for band from 1 to freq_bands
        center_freq = 85 * (2 ^ (band/2.3))
        delay_time = time_stretch * (1/sqrt (center_freq/85))
        freq_response = (1/(1+((center_freq - 650)/750)^2))
        amplitude = base_amplitude * 0.94 * freq_response * randomUniform (0.65, 1.35)
        mod_freq = center_freq / 18
        Formula: "self + 'amplitude' * self(x - 'delay_time') * (0.25 + 0.75*cos(2*pi*x*'mod_freq'))"
    endfor
    
    # Combine left and right channels to stereo
    select Sound reverb_copy_left
    plus Sound reverb_copy_right
    Combine to stereo
    Rename: "spectral_smearing_stereo"
    
    # Cleanup
    removeObject: "Sound reverb_copy_left"
    removeObject: "Sound reverb_copy_right"
    
else
    # Mono processing
    Copy: "reverb_copy"
    select Sound reverb_copy
    
    freq_bands = number_of_frequency_bands
    time_stretch = time_stretch_factor
    
    for band from 1 to freq_bands
        center_freq = 80 * (2 ^ (band/2.5))
        delay_time = time_stretch * (1/sqrt (center_freq/80))
        freq_response = (1/(1+((center_freq - 600)/800)^2))
        amplitude = base_amplitude * freq_response * randomUniform (0.7, 1.3)
        mod_freq = center_freq / 15
        Formula: "self + 'amplitude' * self(x - 'delay_time') * (0.3 + 0.7*cos(2*pi*x*'mod_freq'))"
    endfor
    
    Convert to stereo
    Rename: "spectral_smearing_stereo"
    
    removeObject: "Sound reverb_copy"
endif

# Apply fadeout
select Sound spectral_smearing_stereo
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

select Sound spectral_smearing_stereo
Play