# ============================================================
# Praat AudioTools - SPIRAL_PITCH_DANCE.praat
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

form Spiral Pitch Dance
    comment This script creates spiraling pitch movements with acceleration
    natural spirals 5
    positive semitone_range 24
    positive timestep 0.005
    positive floor 50
    positive ceil 900
    natural npoints 200
    boolean play_after_processing 1
    boolean keep_intermediate_objects 0
endform

if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

orig_sr = Get sampling frequency
Copy... spiral_tmp
To Manipulation: timestep, floor, ceil
Extract pitch tier
Rename... spiral_pitch
select PitchTier spiral_pitch
Remove points between... 0 0
xmin = Get start time
xmax = Get end time
dur = xmax - xmin

for i from 0 to npoints-1
    t = xmin + (i / (npoints-1)) * dur
    
    spiral_pos = i / (npoints-1)
    frequency = spirals * spiral_pos^1.5 * 3 * pi
    
    envelope1 = (1 - spiral_pos^0.3)
    envelope2 = 0.3 * sin(spiral_pos * 4 * pi)^2
    amplitude = semitone_range * (envelope1 + envelope2)
    
    fundamental = sin(frequency)
    harmonic = 0.4 * sin(frequency * 2.5)
    tremolo = 1 + 0.2 * sin(spiral_pos * 16 * pi)
    
    pitch_shift_st = amplitude * (fundamental + harmonic) * tremolo
    ratio = exp((ln(2)/12) * pitch_shift_st)
    
    Add point... t ratio
endfor

select Manipulation spiral_tmp
plus PitchTier spiral_pitch
Replace pitch tier
select Manipulation spiral_tmp
Get resynthesis (overlap-add)
Rename... spiral_result
Resample... 44100 50

if play_after_processing
    Play
endif

if not keep_intermediate_objects
    select Manipulation spiral_tmp
    plus PitchTier spiral_pitch
    Remove
endif