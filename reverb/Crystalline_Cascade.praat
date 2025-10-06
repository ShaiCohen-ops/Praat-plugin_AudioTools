# ============================================================
# Praat AudioTools - Crystalline_Cascade.praat
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

form Quantum Flutter Stereo
    comment This script creates reverse exponential flutter with triple-layer texture
    positive tail_duration_seconds 2
    comment Poisson process:
    positive poisson_density 800
    positive pulse_width 0.08
    positive pulse_period 1200
    comment Modulation:
    positive exponential_base 120
    positive modulation_depth 0.6
    positive modulation_frequency 60
    comment Mix:
    positive convolution_mix 0.35
    positive layer2_amplitude 0.7
    positive scale_peak 0.88
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
    
    # Process left channel
    select Sound left_channel
    a_left = Copy: "soundObj_left"
    Create Poisson process: "quantum_poisson_left", 0, 4, poisson_density
    To Sound (pulse train): sampling_rate, 1, pulse_width, pulse_period
    Formula: "self * 'exponential_base'^((x-xmin)/(xmax-xmin)-1) * (1 + 'modulation_depth'*cos(2*pi*x*'modulation_frequency' + 10*sin(2*pi*x*3)))"
    select a_left
    plusObject: "Sound quantum_poisson_left"
    b_left = Convolve
    Multiply: convolution_mix
    
    # Process right channel
    select Sound right_channel
    a_right = Copy: "soundObj_right"
    Create Poisson process: "quantum_poisson_right", 0, 4, 850
    To Sound (pulse train): sampling_rate, 1, 0.075, 1250
    Formula: "self * 115^((x-xmin)/(xmax-xmin)-1) * (1 + 0.55*cos(2*pi*x*65 + 12*sin(2*pi*x*2.8)))"
    select a_right
    plusObject: "Sound quantum_poisson_right"
    b_right = Convolve
    Multiply: convolution_mix
    
    # Triple-layer left channel
    select a_left
    Copy: "a_layer2_left"
    Formula: "self * 'layer2_amplitude'"
    select a_left
    plusObject: "Sound a_layer2_left"
    plus b_left
    Combine to stereo
    Convert to mono
    Rename: "result_left"
    Scale peak: scale_peak
    
    # Triple-layer right channel
    select a_right
    Copy: "a_layer2_right"
    Formula: "self * 'layer2_amplitude'"
    select a_right
    plusObject: "Sound a_layer2_right"
    plus b_right
    Combine to stereo
    Convert to mono
    Rename: "result_right"
    Scale peak: scale_peak
    
    # Combine stereo channels
    selectObject: "Sound result_left"
    plusObject: "Sound result_right"
    Combine to stereo
    Rename: original_sound$ + "_quantum_flutter"
    
    # Cleanup temporary objects
    removeObject: "PointProcess quantum_poisson_left", "Sound quantum_poisson_left"
    removeObject: "PointProcess quantum_poisson_right", "Sound quantum_poisson_right"
    removeObject: "Sound a_layer2_left", "Sound a_layer2_right"
    removeObject: b_left, b_right, a_left, a_right
    removeObject: "Sound result_left", "Sound result_right"
    
else
    # Mono processing
    a = Copy: "soundObj"
    Create Poisson process: "quantum_poisson", 0, 4, poisson_density
    To Sound (pulse train): sampling_rate, 1, pulse_width, pulse_period
    Formula: "self * 'exponential_base'^((x-xmin)/(xmax-xmin)-1) * (1 + 'modulation_depth'*cos(2*pi*x*'modulation_frequency' + 10*sin(2*pi*x*3)))"
    select a
    plusObject: "Sound quantum_poisson"
    b = Convolve
    Multiply: convolution_mix
    
    select a
    Copy: "a_layer2"
    Formula: "self * 'layer2_amplitude'"
    select a
    plusObject: "Sound a_layer2"
    plus b
    Combine to stereo
    Convert to mono
    Rename: original_sound$ + "_quantum_flutter"
    Scale peak: scale_peak
    
    removeObject: "PointProcess quantum_poisson", "Sound quantum_poisson"
    removeObject: "Sound a_layer2", b, a
endif

# Cleanup temporary sounds
select Sound silent_tail
plus Sound extended_sound
if channels = 2
    plus Sound left_channel
    plus Sound right_channel
endif
Remove

select Sound 'original_sound$'_quantum_flutter

if play_after_processing
    Play
endif