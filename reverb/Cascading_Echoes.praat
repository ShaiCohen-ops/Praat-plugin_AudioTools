# ============================================================
# Praat AudioTools - Cascading_Echoes.praat
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

form Cascading Echoes
    optionmenu Preset: 1
        option "Default (balanced)"
        option "Short & Tight"
        option "Long Ambient Tail"
        option "Wide Stereo Delay"
        option "Custom"
    comment This script creates cascading echo effects with random delays
    positive tail_duration_seconds 1
    natural iterations 5
    comment Delay range (in samples):
    positive delay_min 50
    positive delay_max 500
    comment Stereo parameters (for right channel):
    positive stereo_delay_min 60
    positive stereo_delay_max 550
    comment Amplitude decay:
    positive decay_left 0.8
    positive decay_right 0.75
    boolean play_after_processing 1
endform

# Apply preset values if not Custom
if preset = 1
    # Default (balanced)
    tail_duration_seconds = 1
    iterations = 5
    delay_min = 50
    delay_max = 500
    stereo_delay_min = 60
    stereo_delay_max = 550
    decay_left = 0.8
    decay_right = 0.75
    play_after_processing = 1
elsif preset = 2
    # Short & Tight
    tail_duration_seconds = 0.5
    iterations = 3
    delay_min = 30
    delay_max = 180
    stereo_delay_min = 35
    stereo_delay_max = 220
    decay_left = 0.9
    decay_right = 0.88
    play_after_processing = 1
elsif preset = 3
    # Long Ambient Tail
    tail_duration_seconds = 2.5
    iterations = 7
    delay_min = 120
    delay_max = 1200
    stereo_delay_min = 150
    stereo_delay_max = 1500
    decay_left = 0.85
    decay_right = 0.82
    play_after_processing = 1
elsif preset = 4
    # Wide Stereo Delay
    tail_duration_seconds = 1.5
    iterations = 6
    delay_min = 60
    delay_max = 600
    stereo_delay_min = 200
    stereo_delay_max = 1800
    decay_left = 0.78
    decay_right = 0.72
    play_after_processing = 1
endif

if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Get original sound
original_sound$ = selected$("Sound")
select Sound 'original_sound$'

# Get original properties
original_duration = Get total duration
sampling_rate = Get sample rate
channels = Get number of channels

# Create silent tail
if channels = 2
    Create Sound from formula: "silent_tail", 2, 0, tail_duration_seconds, sampling_rate, "0"
else
    Create Sound from formula: "silent_tail", 1, 0, tail_duration_seconds, sampling_rate, "0"
endif

# Concatenate original with tail
select Sound 'original_sound$'
plus Sound silent_tail
Concatenate
Rename: "extended_sound"

select Sound extended_sound

if channels = 2
    # Extract channels for stereo processing
    Extract one channel: 1
    Rename: "left_channel"
    select Sound extended_sound
    Extract one channel: 2
    Rename: "right_channel"
    
    # Process left channel
    select Sound left_channel
    a = Get number of samples
    for k from 1 to iterations
        delay = randomUniform(delay_min, delay_max)
        amplitude = decay_left^k
        Formula: "self + 'amplitude' * (self[col+'delay'] - self[col])"
    endfor
    Scale peak: 0.99
    
    # Process right channel with different parameters
    select Sound right_channel
    a = Get number of samples
    for k from 1 to iterations
        delay = randomUniform(stereo_delay_min, stereo_delay_max)
        amplitude = decay_right^k
        Formula: "self + 'amplitude' * (self[col+'delay'] - self[col])"
    endfor
    Scale peak: 0.99
    
    # Combine back to stereo
    select Sound left_channel
    plus Sound right_channel
    Combine to stereo
    Rename: original_sound$ + "_cascading_echoes"
    
    # Clean up
    select Sound left_channel
    plus Sound right_channel
    plus Sound silent_tail
    plus Sound extended_sound
    Remove
    
else
    # Mono processing
    a = Get number of samples
    for k from 1 to iterations
        delay = randomUniform(delay_min, delay_max)
        amplitude = decay_left^k
        Formula: "self + 'amplitude' * (self[col+'delay'] - self[col])"
    endfor
    Scale peak: 0.99
    Rename: original_sound$ + "_cascading_echoes"
    
    select Sound silent_tail
    Remove
endif

select Sound 'original_sound$'_cascading_echoes

if play_after_processing
    Play
endif
