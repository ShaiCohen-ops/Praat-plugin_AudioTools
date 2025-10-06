# ============================================================
# Praat AudioTools - Morphing_Resonance.praat
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

form Morphing Resonance Stereo
    comment This script creates frequency-morphing resonance with chorus
    positive tail_duration_seconds 2
    positive poisson_density 1800
    positive pulse_width 0.055
    positive pulse_period 2200
    positive exponential_base 85
    positive modulation_depth 0.5
    positive frequency_start 220
    positive frequency_range 880
    positive convolution_mix 0.32
    positive chorus_mix 0.3
    positive chorus_delay_seconds 0.01
    positive fadeout_duration 1.0
    positive scale_peak 0.9
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
    a_left = Copy: "soundObj_left"
    Create Poisson process: "morph_poisson_left", 0, 4.5, poisson_density
    To Sound (pulse train): sampling_rate, 1, pulse_width, pulse_period
    Formula: "self * 'exponential_base'^(-(x-xmin)/(xmax-xmin)) * (1 + 'modulation_depth'*sin(2*pi*x*('frequency_start' + 'frequency_range'*(x-xmin)/(xmax-xmin))) * exp(-3*(x-xmin)/(xmax-xmin)))"
    select a_left
    plusObject: "Sound morph_poisson_left"
    b_left = Convolve
    Multiply: convolution_mix
    
    select b_left
    Copy: "b_chorus_left"
    Formula: "0.7*(self + 'chorus_mix'*self[col, 1-'chorus_delay_seconds'*sampling_rate])"
    
    select a_left
    plusObject: "Sound b_chorus_left"
    Combine to stereo
    Convert to mono
    Rename: "result_left"
    Scale peak: scale_peak
    
    # Process right (slightly different)
    select Sound right_channel
    a_right = Copy: "soundObj_right"
    Create Poisson process: "morph_poisson_right", 0, 4.3, 1750
    To Sound (pulse train): sampling_rate, 1, 0.05, 2100
    Formula: "self * 80^(-(x-xmin)/(xmax-xmin)) * (1 + 0.45*sin(2*pi*x*(240 + 800*(x-xmin)/(xmax-xmin))) * exp(-2.8*(x-xmin)/(xmax-xmin)))"
    select a_right
    plusObject: "Sound morph_poisson_right"
    b_right = Convolve
    Multiply: 0.30
    
    select b_right
    Copy: "b_chorus_right"
    Formula: "0.7*(self + 0.25*self[col, 1-0.008*sampling_rate])"
    
    select a_right
    plusObject: "Sound b_chorus_right"
    Combine to stereo
    Convert to mono
    Rename: "result_right"
    Scale peak: scale_peak
    
    # Combine
    selectObject: "Sound result_left"
    plusObject: "Sound result_right"
    Combine to stereo
    Rename: original_sound$ + "_morphing"
    
    # Cleanup
    removeObject: "PointProcess morph_poisson_left", "Sound morph_poisson_left"
    removeObject: "PointProcess morph_poisson_right", "Sound morph_poisson_right"
    removeObject: "Sound b_chorus_left", "Sound b_chorus_right"
    removeObject: b_left, b_right, a_left, a_right
    removeObject: "Sound result_left", "Sound result_right"
    
else
    a = Copy: "soundObj"
    Create Poisson process: "morph_poisson", 0, 4.5, poisson_density
    To Sound (pulse train): sampling_rate, 1, pulse_width, pulse_period
    Formula: "self * 'exponential_base'^(-(x-xmin)/(xmax-xmin)) * (1 + 'modulation_depth'*sin(2*pi*x*('frequency_start' + 'frequency_range'*(x-xmin)/(xmax-xmin))) * exp(-3*(x-xmin)/(xmax-xmin)))"
    select a
    plusObject: "Sound morph_poisson"
    b = Convolve
    Multiply: convolution_mix
    
    select b
    Copy: "b_chorus"
    Formula: "0.7*(self + 'chorus_mix'*self[col, 1-'chorus_delay_seconds'*sampling_rate])"
    
    select a
    plusObject: "Sound b_chorus"
    Combine to stereo
    Convert to mono
    Rename: original_sound$ + "_morphing"
    Scale peak: scale_peak
    
    removeObject: "PointProcess morph_poisson", "Sound morph_poisson"
    removeObject: "Sound b_chorus", b, a
endif

# Apply fadeout
select Sound 'original_sound$'_morphing
total_duration = Get total duration
fade_start = total_duration - fadeout_duration
Formula: "if x > fade_start then self * (0.5 + 0.5 * cos(pi * (x - fade_start) / 'fadeout_duration')) else self fi"

# Cleanup
select Sound silent_tail
plus Sound extended_sound
if channels = 2
    plus Sound left_channel
    plus Sound right_channel
endif
Remove

select Sound 'original_sound$'_morphing

if play_after_processing
    Play
endif