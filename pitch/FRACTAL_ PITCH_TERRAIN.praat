# ============================================================
# Praat AudioTools - FRACTAL_ PITCH_TERRAIN.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Pitch-based transformation script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Fractal Pitch Terrain Effect
    comment This script creates complex self-similar pitch landscapes
    comment Fractal parameters:
    natural iterations 6
    positive base_frequency 1.5
    positive amplitude_decay 0.55
    positive chaos_factor 0.3
    comment Wave mixing:
    positive sine_mix 0.7
    positive square_mix 0.3
    comment Frequency progression:
    positive frequency_multiplier 2.618
    comment (golden ratio)
    positive phase_increment 0.33
    comment Pitch scaling:
    positive pitch_depth 15
    positive drift_amplitude 2
    positive drift_frequency 0.7
    comment Time evolution:
    positive time_evolution_power 2
    positive time_evolution_strength 0.5
    comment Pitch analysis:
    positive time_step 0.005
    positive minimum_pitch 50
    positive maximum_pitch 900
    comment Pitch tier resolution:
    natural number_of_points 500
    comment Output:
    positive output_sample_rate 44100
    positive resample_precision 50
    boolean play_after_processing 1
    boolean keep_intermediate_objects 0
endform

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

originalName$ = selected$("Sound")
orig_sr = Get sampling frequency

Copy: originalName$ + "_fractal_tmp"
To Manipulation: time_step, minimum_pitch, maximum_pitch
Extract pitch tier
Rename: originalName$ + "_fractal_pitch"

select PitchTier 'originalName$'_fractal_pitch
Remove points between: 0, 0
xmin = Get start time
xmax = Get end time
dur = xmax - xmin

for i from 0 to number_of_points - 1
    t = xmin + (i / (number_of_points - 1)) * dur
    u = (t - xmin) / dur
    
    pitch_sum = 0
    current_amplitude = 1
    current_frequency = base_frequency
    current_phase = 0
    
    for iteration from 1 to iterations
        wave_phase = (u + current_phase) * current_frequency * 2 * pi
        sine_component = sin(wave_phase)
        
        if sin(wave_phase) > 0
            square_component = 1
        else
            square_component = -1
        endif
        
        combined_wave = sine_mix * sine_component + square_mix * square_component
        
        chaos_phase = wave_phase * 2.3
        chaos_component = chaos_factor * sin(chaos_phase) * randomUniform(0.9, 1.1)
        
        layer_value = current_amplitude * (combined_wave + chaos_component)
        pitch_sum = pitch_sum + layer_value
        
        current_amplitude = current_amplitude * amplitude_decay
        current_frequency = current_frequency * frequency_multiplier
        current_phase = current_phase + phase_increment * iteration
    endfor
    
    time_factor = 1 + time_evolution_strength * u ^ time_evolution_power
    final_pitch = pitch_depth * pitch_sum * time_factor
    
    drift = drift_amplitude * sin(u * drift_frequency * pi) * u * u
    final_pitch = final_pitch + drift
    
    ratio = exp((ln(2) / 12) * final_pitch)
    Add point: t, ratio
endfor

select Manipulation 'originalName$'_fractal_tmp
plus PitchTier 'originalName$'_fractal_pitch
Replace pitch tier

select Manipulation 'originalName$'_fractal_tmp
result = Get resynthesis (overlap-add)
Rename: originalName$ + "_fractal_result"
Resample: output_sample_rate, resample_precision

if play_after_processing
    Play
endif

if not keep_intermediate_objects
    select Manipulation 'originalName$'_fractal_tmp
    plus PitchTier 'originalName$'_fractal_pitch
    Remove
endif

select Sound 'originalName$'_fractal_result