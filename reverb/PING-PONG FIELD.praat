# ============================================================
# Praat AudioTools - PING-PONG FIELD.praat
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

form Ping-Pong Field Stereo
    comment This script creates stereo ping-pong delays with high-frequency sparkle
    positive tail_duration_seconds 2
    natural number_of_echoes 90
    positive base_amplitude 0.25
    positive min_delay 0.02
    positive max_delay 1.20
    positive decay_factor 0.95
    positive ping_pong_offset 0.003
    positive jitter_amount 0.004
    positive hf_sparkle 0.3
    positive scale_every_n_iterations 20
    positive fadeout_duration 1.0
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
    Copy: "pingpong_field_left"
    
    for k from 1 to number_of_echoes
        t = min_delay + (max_delay - min_delay) * k / number_of_echoes
        
        if k mod 2 = 0
            off = ping_pong_offset
        else
            off = -ping_pong_offset
        endif
        
        delay = t + off + randomUniform(-jitter_amount, jitter_amount)
        
        if k mod 4 < 2
            sgn = 1
        else
            sgn = -1
        endif
        
        a = base_amplitude * (decay_factor ^ k) * (0.9 + 0.2 * randomUniform(0,1)) * sgn
        
        Formula: "if x > delay then self + a * ( self(x - delay) + 'hf_sparkle'*(self(x - delay) - self(x - delay - 1/sampling_rate)) ) else self fi"
        
        if k mod scale_every_n_iterations = 0
            Scale peak: 0.98
        endif
    endfor
    
    Scale peak: 0.98
    
    # Process right (different pattern)
    select Sound right_channel
    Copy: "pingpong_field_right"
    
    for k from 1 to number_of_echoes
        t = (min_delay + 0.002) + ((max_delay - 0.02) - (min_delay + 0.002)) * k / number_of_echoes
        
        if k mod 2 = 0
            off = -0.0025
        else
            off = 0.0025
        endif
        
        delay = t + off + randomUniform(-0.0035, 0.0035)
        
        if k mod 3 < 1.5
            sgn = 1
        else
            sgn = -1
        endif
        
        a = (base_amplitude - 0.01) * (0.94 ^ k) * (0.85 + 0.3 * randomUniform(0,1)) * sgn
        
        Formula: "if x > delay then self + a * ( self(x - delay) + 0.25*(self(x - delay) - self(x - delay - 1/sampling_rate)) ) else self fi"
        
        if k mod 25 = 0
            Scale peak: 0.98
        endif
    endfor
    
    Scale peak: 0.98
    
    # Combine
    select Sound pingpong_field_left
    plus Sound pingpong_field_right
    Combine to stereo
    Rename: original_sound$ + "_pingpong"
    
    removeObject: "Sound pingpong_field_left", "Sound pingpong_field_right"
    
else
    Copy: "pingpong_field"
    
    for k from 1 to number_of_echoes
        t = min_delay + (max_delay - min_delay) * k / number_of_echoes
        
        if k mod 2 = 0
            off = ping_pong_offset
        else
            off = -ping_pong_offset
        endif
        
        delay = t + off + randomUniform(-jitter_amount, jitter_amount)
        
        if k mod 4 < 2
            sgn = 1
        else
            sgn = -1
        endif
        
        a = base_amplitude * (decay_factor ^ k) * (0.9 + 0.2 * randomUniform(0,1)) * sgn
        
        Formula: "if x > delay then self + a * ( self(x - delay) + 'hf_sparkle'*(self(x - delay) - self(x - delay - 1/sampling_rate)) ) else self fi"
        
        if k mod scale_every_n_iterations = 0
            Scale peak: 0.98
        endif
    endfor
    
    Scale peak: 0.98
    Convert to stereo
    Rename: original_sound$ + "_pingpong"
    
    removeObject: "Sound pingpong_field"
endif

# Apply fadeout
select Sound 'original_sound$'_pingpong
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

select Sound 'original_sound$'_pingpong

if play_after_processing
    Play
endif