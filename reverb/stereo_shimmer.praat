# ============================================================
# Praat AudioTools - stereo_shimmer.praat
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

form Stereo Shimmer
    comment This script creates shimmering delays with high-frequency enhancement
    positive tail_duration_seconds 2
    natural number_of_echoes 80
    positive base_amplitude 0.24
    positive min_delay 0.02
    positive max_delay 1.2
    positive decay_factor 0.95
    positive jitter_amount 0.012
    positive hf_enhancement 0.25
    positive scale_every_n 20
    boolean play_after_processing 1
endform

if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

originalName$ = selected$("Sound")
Copy: originalName$ + "_shimmer"

select Sound 'originalName$'_shimmer
sampling_rate = Get sample rate
channels = Get number of channels

# Create silent tail
if channels = 2
    Create Sound from formula: "silent_tail", 2, 0, tail_duration_seconds, sampling_rate, "0"
else
    Create Sound from formula: "silent_tail", 1, 0, tail_duration_seconds, sampling_rate, "0"
endif

select Sound 'originalName$'_shimmer
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
    for k from 1 to number_of_echoes
        delay = min_delay + (max_delay - min_delay) * k/number_of_echoes + randomUniform(-jitter_amount, jitter_amount)
        sgn = if (k mod 4 < 2) then 1 else -1 fi
        a = base_amplitude * (decay_factor ^ k) * sgn
        Formula: "if x > delay then self + a * self(x - delay) else self fi"
        if k mod scale_every_n = 0
            Scale peak: 0.98
        endif
    endfor
    Formula: "self + 'hf_enhancement'*(self - self(x - 1/44100))"
    Scale peak: 0.98
    
    # Process right (different jitter and phase)
    select Sound right_channel
    for k from 1 to number_of_echoes
        delay = min_delay + (max_delay - min_delay) * k/number_of_echoes + randomUniform(-0.015, 0.015)
        sgn = if ((k + 2) mod 4 < 2) then 1 else -1 fi
        a = base_amplitude * (0.94 ^ k) * sgn
        Formula: "if x > delay then self + a * self(x - delay) else self fi"
        if k mod scale_every_n = 0
            Scale peak: 0.98
        endif
    endfor
    Formula: "self + 0.23*(self - self(x - 1/44100))"
    Scale peak: 0.98
    
    # Combine
    select Sound left_channel
    plus Sound right_channel
    Combine to stereo
    Rename: originalName$ + "_shimmer_result"
    
    # Cleanup
    select Sound left_channel
    plus Sound right_channel
    plus Sound silent_tail
    Remove
    
else
    for k from 1 to number_of_echoes
        delay = min_delay + (max_delay - min_delay) * k/number_of_echoes + randomUniform(-jitter_amount, jitter_amount)
        sgn = if (k mod 4 < 2) then 1 else -1 fi
        a = base_amplitude * (decay_factor ^ k) * sgn
        Formula: "if x > delay then self + a * self(x - delay) else self fi"
        if k mod scale_every_n = 0
            Scale peak: 0.98
        endif
    endfor
    Formula: "self + 'hf_enhancement'*(self - self(x - 1/44100))"
    Scale peak: 0.98
    Rename: originalName$ + "_shimmer_result"
    
    select Sound silent_tail
    Remove
endif

select Sound 'originalName$'_shimmer_result

if play_after_processing
    Play
endif