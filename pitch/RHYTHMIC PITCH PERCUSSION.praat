# ============================================================
# Praat AudioTools - RHYTHMIC PITCH PERCUSSION.praat
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

form Rhythmic Pitch Percussion
    comment This script creates percussive pitch hits with polyrhythms
    sentence rhythm_pattern 1_0_1_1_0_1_0_1_1_0_0_1
    comment (1=hit, 0=rest, underscore-separated)
    positive hit_strength 25
    positive decay_rate 6
    positive polyrhythm_factor 3
    positive ghost_hits 0.3
    positive timestep 0.005
    positive floor 50
    positive ceil 900
    natural npoints 600
    boolean play_after_processing 1
    boolean keep_intermediate_objects 0
endform

if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Parse rhythm pattern
rhythm$ = rhythm_pattern$
rhythm$ = replace$(rhythm$, "_", " ", 0)
n_beats = 0
repeat
    rhythm$ = rhythm$ + " "
    space_pos = index(rhythm$, " ")
    if space_pos > 1
        n_beats += 1
        beat$[n_beats] = left$(rhythm$, space_pos-1)
        rhythm$ = right$(rhythm$, length(rhythm$) - space_pos)
    endif
until space_pos <= 1

orig_sr = Get sampling frequency
Copy... rhythm_tmp
To Manipulation: timestep, floor, ceil
Extract pitch tier
Rename... rhythm_pitch
select PitchTier rhythm_pitch
Remove points between... 0 0
xmin = Get start time
xmax = Get end time
dur = xmax - xmin
beat_duration = dur / n_beats

for i from 0 to npoints-1
    t = xmin + (i / (npoints-1)) * dur
    
    beat_pos = ((t - xmin) / beat_duration)
    current_beat = floor(beat_pos) + 1
    beat_phase = beat_pos - floor(beat_pos)
    
    if current_beat <= n_beats
        beat_value = number(beat$[current_beat])
    else
        beat_value = 0
    endif
    
    pitch_shift = 0
    
    if beat_value > 0
        attack = exp(-decay_rate * 3 * beat_phase)
        body = 0.6 * exp(-decay_rate * 0.8 * beat_phase)
        tail = 0.2 * exp(-decay_rate * 0.3 * beat_phase)
        envelope = attack + body + tail
        
        fundamental_hit = hit_strength * envelope
        harmonic_hit = 0.4 * hit_strength * envelope * sin(beat_phase * 8 * pi)
        
        pitch_shift += fundamental_hit + harmonic_hit
    endif
    
    poly_beat_pos = beat_pos * polyrhythm_factor
    poly_phase = poly_beat_pos - floor(poly_beat_pos)
    if poly_phase < 0.1
        ghost_envelope = exp(-20 * poly_phase)
        ghost_hit = ghost_hits * hit_strength * ghost_envelope
        pitch_shift = pitch_shift + ghost_hit
    endif
    
    tension_base = sin(beat_pos * 2 * pi)
    tension_modulation = 1 + 0.3 * sin(beat_pos * 7 * pi)
    tension_wave = 0.8 * tension_base * tension_modulation
    pitch_shift = pitch_shift + tension_wave
    
    human_factor = randomUniform(0.95, 1.05)
    pitch_shift *= human_factor
    
    ratio = exp((ln(2)/12) * pitch_shift)
    Add point... t ratio
endfor

select Manipulation rhythm_tmp
plus PitchTier rhythm_pitch
Replace pitch tier
select Manipulation rhythm_tmp
Get resynthesis (overlap-add)
Rename... rhythm_result
Resample... 44100 50

if play_after_processing
    Play
endif

if not keep_intermediate_objects
    select Manipulation rhythm_tmp
    plus PitchTier rhythm_pitch
    Remove
endif