# ============================================================
# Praat AudioTools - QUANTUM_PITCH_JUMPS.praat
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

form Quantum Pitch Jumps Effect
    comment This script creates dramatic quantum-like pitch leaps with glitches
    comment Quantum parameters:
    natural quantum_levels 12
    positive jump_probability 0.4
    comment (0-1: probability of quantum jumps)
    positive glitch_probability 0.15
    comment (0-1: probability of glitch events)
    comment Energy modulation:
    positive energy_min 0.5
    positive energy_max 2.0
    comment Glitch deviation range:
    real glitch_min_semitones -2
    real glitch_max_semitones 3
    comment Quantum uncertainty:
    positive uncertainty_min 0.98
    positive uncertainty_max 1.02
    comment Pitch analysis:
    positive time_step 0.005
    positive minimum_pitch 50
    positive maximum_pitch 900
    comment Resolution:
    natural number_of_steps 80
    comment Output:
    positive output_sample_rate 44100
    positive resample_precision 50
    boolean play_after_processing 1
    boolean keep_intermediate_objects 0
endform

if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

originalName$ = selected$("Sound")
orig_sr = Get sampling frequency

# Define harmonic ratios with microtones
ratios# = {1, 16/15, 9/8, 6/5, 5/4, 4/3, 7/5, 3/2, 8/5, 5/3, 16/9, 15/8, 2}

Copy: originalName$ + "_quantum_tmp"
To Manipulation: time_step, minimum_pitch, maximum_pitch
Extract pitch tier
Rename: originalName$ + "_quantum_pitch"

select PitchTier 'originalName$'_quantum_pitch
Remove points between: 0, 0
xmin = Get start time
xmax = Get end time
dur = xmax - xmin

current_level = 1
energy_level = 1

for i from 0 to number_of_steps - 1
    t = xmin + (i / (number_of_steps - 1)) * dur
    
    # Quantum tunnel events
    if randomUniform(0, 1) < jump_probability
        current_level = randomInteger(1, quantum_levels)
        energy_level = randomUniform(energy_min, energy_max)
    endif
    
    # Glitch events
    glitch_factor = 0
    if randomUniform(0, 1) < glitch_probability
        glitch_factor = randomUniform(glitch_min_semitones, glitch_max_semitones)
    endif
    
    ratio_index = ((current_level - 1) mod size(ratios#)) + 1
    base_ratio = ratios#[ratio_index]
    
    # Apply energy modulation and glitches
    glitch_multiplier = exp((ln(2) / 12) * glitch_factor)
    final_ratio = base_ratio * energy_level * glitch_multiplier
    
    # Add quantum uncertainty
    uncertainty = randomUniform(uncertainty_min, uncertainty_max)
    final_ratio = final_ratio * uncertainty
    
    Add point: t, final_ratio
endfor

select Manipulation 'originalName$'_quantum_tmp
plus PitchTier 'originalName$'_quantum_pitch
Replace pitch tier

select Manipulation 'originalName$'_quantum_tmp
result = Get resynthesis (overlap-add)
Rename: originalName$ + "_quantum_result"
Resample: output_sample_rate, resample_precision

if play_after_processing
    Play
endif

if not keep_intermediate_objects
    select Manipulation 'originalName$'_quantum_tmp
    plus PitchTier 'originalName$'_quantum_pitch
    Remove
endif

select Sound 'originalName$'_quantum_result