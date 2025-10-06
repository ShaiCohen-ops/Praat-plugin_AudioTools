# ============================================================
# Praat AudioTools - BREATHING_PITCH_WAVES.praat
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

form Breathing Pitch Waves Effect
    comment This script simulates emotional breathing with dramatic pitch swells
    comment Breathing parameters:
    positive breath_rate 0.3
    comment (breathing cycles per second)
    positive pitch_depth_semitones 18
    comment (pitch variation range)
    comment Flutter and chaos:
    positive micro_flutter 4
    positive emotional_intensity 2.5
    comment Pitch analysis:
    positive time_step 0.005
    positive minimum_pitch 50
    positive maximum_pitch 900
    comment Pitch tier resolution:
    natural number_of_points 350
    comment Resampling:
    positive output_sample_rate 44100
    positive resample_precision 50
    comment Output options:
    boolean play_after_processing 1
    boolean keep_intermediate_objects 0
endform

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

originalName$ = selected$("Sound")
orig_sr = Get sampling frequency

Copy: originalName$ + "_breath_tmp"
To Manipulation: time_step, minimum_pitch, maximum_pitch
Extract pitch tier
Rename: originalName$ + "_breath_pitch"

select PitchTier 'originalName$'_breath_pitch
Remove points between: 0, 0
xmin = Get start time
xmax = Get end time
dur = xmax - xmin

for i from 0 to number_of_points - 1
    t = xmin + (i / (number_of_points - 1)) * dur
    phase = (t - xmin) / dur * 2 * pi * breath_rate
    
    breath_fundamental = sin(phase)^3
    breath_harmonic = 0.6 * sin(phase * 2)^5
    breath_subharmonic = 0.3 * sin(phase * 0.5)^2
    breath_curve = breath_fundamental + breath_harmonic + breath_subharmonic
    
    flutter_phase = phase * 12
    chaos_phase = phase * 23.7
    flutter_component1 = sin(flutter_phase) * randomUniform(0.6, 1.4)
    flutter_component2 = 0.5 * sin(chaos_phase) * randomUniform(0.8, 1.2)
    flutter = micro_flutter * 0.15 * (flutter_component1 + flutter_component2)
    
    tremor = 0.8 * sin(phase * 7.3) * cos(phase * 2.1)
    gasp_trigger = sin(phase * 3)^8
    gasp = 3 * gasp_trigger * randomUniform(0.5, 1.5)
    
    time_factor = (t - xmin) / dur
    intensity_envelope = 1 + emotional_intensity * time_factor^1.5
    
    total_shift = pitch_depth_semitones * (breath_curve + flutter + tremor + gasp) * intensity_envelope
    ratio = exp((ln(2) / 12) * total_shift)
    
    Add point: t, ratio
endfor

select Manipulation 'originalName$'_breath_tmp
plus PitchTier 'originalName$'_breath_pitch
Replace pitch tier

select Manipulation 'originalName$'_breath_tmp
result = Get resynthesis (overlap-add)
Rename: originalName$ + "_breath_result"
Resample: output_sample_rate, resample_precision

if play_after_processing
    Play
endif

if not keep_intermediate_objects
    select Manipulation 'originalName$'_breath_tmp
    plus PitchTier 'originalName$'_breath_pitch
    Remove
endif

select Sound 'originalName$'_breath_result