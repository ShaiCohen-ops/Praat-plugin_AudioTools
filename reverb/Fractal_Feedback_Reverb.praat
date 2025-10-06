# ============================================================
# Praat AudioTools - Fractal_Feedback_Reverb.praat
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

form Fractal Feedback Reverb
    comment This script creates complex reverb with chaotic delay patterns
    positive tail_duration_seconds 2
    natural iterations 32
    positive seed_delay 0.08
    positive chaos_factor 1.8
    natural memory_depth 4
    positive amplitude_base 0.18
    positive secondary_amplitude_factor 0.75
    positive modulation_frequency 30
    boolean play_after_processing 1
endform

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
    Copy: "reverb_copy_left"
    
    for i from 1 to iterations
        primary_delay = seed_delay * (chaos_factor ^ (i mod memory_depth))
        secondary_delay = primary_delay / chaos_factor
        amp1 = amplitude_base * (1 - i/iterations) * randomUniform(0.6, 1.4)
        amp2 = amp1 * secondary_amplitude_factor
        Formula: "self + amp1 * self(x - primary_delay)"
        Formula: "self + amp2 * self(x - secondary_delay) * cos(2*pi*x*'modulation_frequency')"
    endfor
    
    # Process right (slightly different parameters)
    select Sound right_channel
    Copy: "reverb_copy_right"
    
    for i from 1 to iterations
        primary_delay = (seed_delay + 0.002) * ((chaos_factor + 0.02) ^ (i mod memory_depth))
        secondary_delay = primary_delay / (chaos_factor + 0.02)
        amp1 = amplitude_base * (1 - i/iterations) * randomUniform(0.55, 1.35)
        amp2 = amp1 * (secondary_amplitude_factor - 0.03)
        Formula: "self + amp1 * self(x - primary_delay)"
        Formula: "self + amp2 * self(x - secondary_delay) * cos(2*pi*x*28)"
    endfor
    
    # Combine
    select Sound reverb_copy_left
    plus Sound reverb_copy_right
    Combine to stereo
    Rename: original_sound$ + "_fractal_reverb"
    
    removeObject: "Sound reverb_copy_left", "Sound reverb_copy_right"
    
else
    Copy: "reverb_copy"
    
    for i from 1 to iterations
        primary_delay = seed_delay * (chaos_factor ^ (i mod memory_depth))
        secondary_delay = primary_delay / chaos_factor
        amp1 = amplitude_base * (1 - i/iterations) * randomUniform(0.6, 1.4)
        amp2 = amp1 * secondary_amplitude_factor
        Formula: "self + amp1 * self(x - primary_delay)"
        Formula: "self + amp2 * self(x - secondary_delay) * cos(2*pi*x*'modulation_frequency')"
    endfor
    
    Convert to stereo
    Rename: original_sound$ + "_fractal_reverb"
    
    removeObject: "Sound reverb_copy"
endif

# Cleanup
select Sound silent_tail
plus Sound extended_sound
if channels = 2
    plus Sound left_channel
    plus Sound right_channel
endif
Remove

select Sound 'original_sound$'_fractal_reverb

if play_after_processing
    Play
endif