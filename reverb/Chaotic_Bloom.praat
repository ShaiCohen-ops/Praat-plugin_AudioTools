# ============================================================
# Praat AudioTools - Chaotic_Bloom.praat
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

form Chaotic Bloom Stereo
    optionmenu Preset: 1
        option "Default (balanced)"
        option "Dense Bloom"
        option "Sparse Bloom"
        option "Wide Stereo Shimmer"
        option "Custom"
    comment This script creates chaotic blooming textures with stereo imaging
    positive tail_duration_seconds 2
    comment Poisson process parameters:
    positive poisson_density 3000
    comment (events per second)
    positive pulse_train_amplitude 1
    positive pulse_train_width 0.04
    positive pulse_train_period 2500
    comment Convolution mix:
    positive mix_amplitude 0.4
    comment Output:
    positive scale_peak 0.85
    boolean play_after_processing 1
endform

# Apply preset values if not Custom
if preset = 1
    # Default (balanced)
    tail_duration_seconds = 2
    poisson_density = 3000
    pulse_train_amplitude = 1
    pulse_train_width = 0.04
    pulse_train_period = 2500
    mix_amplitude = 0.4
    scale_peak = 0.85
    play_after_processing = 1
elsif preset = 2
    # Dense Bloom (more events, thicker tail)
    tail_duration_seconds = 3
    poisson_density = 4500
    pulse_train_amplitude = 1.1
    pulse_train_width = 0.05
    pulse_train_period = 2200
    mix_amplitude = 0.5
    scale_peak = 0.85
    play_after_processing = 1
elsif preset = 3
    # Sparse Bloom (fewer, cleaner events)
    tail_duration_seconds = 1.5
    poisson_density = 1800
    pulse_train_amplitude = 0.9
    pulse_train_width = 0.03
    pulse_train_period = 2800
    mix_amplitude = 0.3
    scale_peak = 0.85
    play_after_processing = 1
elsif preset = 4
    # Wide Stereo Shimmer (longer tail, lighter mix)
    tail_duration_seconds = 2.5
    poisson_density = 3200
    pulse_train_amplitude = 1.0
    pulse_train_width = 0.035
    pulse_train_period = 2600
    mix_amplitude = 0.35
    scale_peak = 0.85
    play_after_processing = 1
endif

if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

original_sound$ = selected$("Sound")
select Sound 'original_sound$'

original_duration = Get total duration
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
    Create Poisson process: "chaos_poisson_left", 0, 6, poisson_density
    To Sound (pulse train): sampling_rate, pulse_train_amplitude, pulse_train_width, pulse_train_period
    Formula: "self * (sin(pi*(x-xmin)/(xmax-xmin))^2) * 80^(-(x-xmin)/(xmax-xmin)) * (1 + 0.8*sin(2*pi*x*200*(x-xmin)/(xmax-xmin)))"
    select a_left
    plusObject: "Sound chaos_poisson_left"
    b_left = Convolve
    Multiply: mix_amplitude
    
    # Process right
    select Sound right_channel
    a_right = Copy: "soundObj_right"
    Create Poisson process: "chaos_poisson_right", 0, 6, 3200
    To Sound (pulse train): sampling_rate, pulse_train_amplitude, 0.035, 2600
    Formula: "self * (sin(pi*(x-xmin)/(xmax-xmin))^2) * 75^(-(x-xmin)/(xmax-xmin)) * (1 + 0.75*sin(2*pi*x*180*(x-xmin)/(xmax-xmin)))"
    select a_right
    plusObject: "Sound chaos_poisson_right"
    b_right = Convolve
    Multiply: 0.38
    
    # Panning
    select a_left
    Copy: "a_pan_left"
    Formula: "self * (0.5 + 0.5*sin(2*pi*(x-xmin)*2))"
    selectObject: b_left
    Copy: "b_pan_left"
    Formula: "self * (0.5 - 0.5*sin(2*pi*(x-xmin)*2))"
    
    select a_right
    Copy: "a_pan_right"
    Formula: "self * (0.5 - 0.5*sin(2*pi*(x-xmin)*1.8))"
    selectObject: b_right
    Copy: "b_pan_right"
    Formula: "self * (0.5 + 0.5*sin(2*pi*(x-xmin)*1.8))"
    
    # Mix channels
    selectObject: "Sound a_pan_left"
    plusObject: "Sound b_pan_left"
    Combine to stereo
    Convert to mono
    Rename: "final_left"
    
    selectObject: "Sound a_pan_right"
    plusObject: "Sound b_pan_right"
    Combine to stereo
    Convert to mono
    Rename: "final_right"
    
    # Final stereo
    selectObject: "Sound final_left"
    plusObject: "Sound final_right"
    Combine to stereo
    Scale peak: scale_peak
    Rename: original_sound$ + "_chaotic_bloom"
    
    # Cleanup
    removeObject: "PointProcess chaos_poisson_left", "Sound chaos_poisson_left"
    removeObject: "PointProcess chaos_poisson_right", "Sound chaos_poisson_right"
    removeObject: "Sound a_pan_left", "Sound b_pan_left"
    removeObject: "Sound a_pan_right", "Sound b_pan_right"
    removeObject: b_left, b_right, a_left, a_right
    removeObject: "Sound final_left", "Sound final_right"
    
else
    a = Copy: "soundObj"
    Create Poisson process: "chaos_poisson", 0, 6, poisson_density
    To Sound (pulse train): sampling_rate, pulse_train_amplitude, pulse_train_width, pulse_train_period
    Formula: "self * (sin(pi*(x-xmin)/(xmax-xmin))^2) * 80^(-(x-xmin)/(xmax-xmin)) * (1 + 0.8*sin(2*pi*x*200*(x-xmin)/(xmax-xmin)))"
    select a
    plusObject: "Sound chaos_poisson"
    b = Convolve
    Multiply: mix_amplitude
    
    select a
    plusObject: b
    Combine to stereo
    Convert to mono
    Scale peak: scale_peak
    Rename: original_sound$ + "_chaotic_bloom"
    
    removeObject: "PointProcess chaos_poisson", "Sound chaos_poisson", b, a
endif

select Sound silent_tail
plus Sound extended_sound
if channels = 2
    plus Sound left_channel
    plus Sound right_channel
endif
Remove

select Sound 'original_sound$'_chaotic_bloom

if play_after_processing
    Play
endif
