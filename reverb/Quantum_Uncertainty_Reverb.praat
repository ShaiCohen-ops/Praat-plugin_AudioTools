# ============================================================
# Praat AudioTools - Quantum_Uncertainty_Reverb.praat
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

form Quantum Uncertainty Stereo
    comment This script simulates quantum state collapse in reverb delays
    positive tail_duration_seconds 1
    natural quantum_states 35
    positive uncertainty_stddev 0.35
    positive collapse_threshold 0.65
    comment (probability threshold for state collapse vs superposition)
    positive base_amplitude 0.25
    positive time_mean 0.18
    positive min_delay_offset 0.02
    positive state_decay_min 0.7
    positive state_decay_range 0.3
    natural substates 4
    positive substate_jitter 0.015
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
    Copy: "reverb_copy_left"
    
    for state from 1 to quantum_states
        time_uncertainty = randomGauss(time_mean, uncertainty_stddev)
        amplitude_precision = 1 / (1 + abs(time_uncertainty))
        state_decay = state_decay_min + state_decay_range * (quantum_states - state) / quantum_states
        probability = randomUniform(0, 1)
        
        if probability > collapse_threshold
            delay = abs(time_uncertainty) + min_delay_offset
            amp = base_amplitude * amplitude_precision * state_decay * 0.8
            Formula: "self + amp * self(x - delay)"
        else
            for sub from 1 to substates
                sub_delay = abs(time_uncertainty) + randomGauss(0, substate_jitter) + min_delay_offset
                sub_amp = base_amplitude * amplitude_precision * state_decay * 0.5 / sub
                Formula: "self + sub_amp * self(x - sub_delay)"
            endfor
        endif
    endfor
    
    # Process right (different parameters)
    select Sound right_channel
    Copy: "reverb_copy_right"
    
    for state from 1 to quantum_states
        time_uncertainty = randomGauss(0.16, 0.38)
        amplitude_precision = 1 / (1 + abs(time_uncertainty))
        state_decay = 0.65 + 0.35 * (quantum_states - state) / quantum_states
        probability = randomUniform(0, 1)
        
        if probability > 0.62
            delay = abs(time_uncertainty) + 0.025
            amp = 0.23 * amplitude_precision * state_decay * 0.75
            Formula: "self + amp * self(x - delay)"
        else
            for sub from 1 to substates
                sub_delay = abs(time_uncertainty) + randomGauss(0, 0.018) + 0.025
                sub_amp = 0.23 * amplitude_precision * state_decay * 0.45 / sub
                Formula: "self + sub_amp * self(x - sub_delay)"
            endfor
        endif
    endfor
    
    # Combine
    select Sound reverb_copy_left
    plus Sound reverb_copy_right
    Combine to stereo
    Rename: original_sound$ + "_quantum_uncertainty"
    
    removeObject: "Sound reverb_copy_left", "Sound reverb_copy_right"
    
else
    Copy: "reverb_copy"
    
    for state from 1 to quantum_states
        time_uncertainty = randomGauss(time_mean, uncertainty_stddev)
        amplitude_precision = 1 / (1 + abs(time_uncertainty))
        state_decay = state_decay_min + state_decay_range * (quantum_states - state) / quantum_states
        probability = randomUniform(0, 1)
        
        if probability > collapse_threshold
            delay = abs(time_uncertainty) + min_delay_offset
            amp = base_amplitude * amplitude_precision * state_decay * 0.8
            Formula: "self + amp * self(x - delay)"
        else
            for sub from 1 to substates
                sub_delay = abs(time_uncertainty) + randomGauss(0, substate_jitter) + min_delay_offset
                sub_amp = base_amplitude * amplitude_precision * state_decay * 0.5 / sub
                Formula: "self + sub_amp * self(x - sub_delay)"
            endfor
        endif
    endfor
    
    Convert to stereo
    Rename: original_sound$ + "_quantum_uncertainty"
    
    removeObject: "Sound reverb_copy"
endif

# Apply fadeout
select Sound 'original_sound$'_quantum_uncertainty
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

select Sound 'original_sound$'_quantum_uncertainty

if play_after_processing
    Play
endif