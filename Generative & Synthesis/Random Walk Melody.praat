# ============================================================
# Praat AudioTools - Random Walk Melody.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Sound synthesis or generative algorithm script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Random Walk Melody
    real Duration 15.0
    real Sampling_frequency 44100
    real Note_duration 0.5
    real Base_frequency 220
    integer Scale_degrees 7
    real Step_probability 0.7
endform

echo Creating Random Walk Melody...

current_note = 1
current_time = 0
total_notes = round(duration / note_duration)
formula$ = "0"

scale_ratio1 = 1.0
scale_ratio2 = 9/8
scale_ratio3 = 5/4
scale_ratio4 = 4/3
scale_ratio5 = 3/2
scale_ratio6 = 5/3
scale_ratio7 = 15/8

for note to total_notes
    note_time = (note-1) * note_duration
    
    if note_time < duration
        note_dur = min(note_duration, duration - note_time)
        
        if note_dur > 0.01
            if current_note = 1
                current_freq = base_frequency * scale_ratio1
            elsif current_note = 2
                current_freq = base_frequency * scale_ratio2
            elsif current_note = 3
                current_freq = base_frequency * scale_ratio3
            elsif current_note = 4
                current_freq = base_frequency * scale_ratio4
            elsif current_note = 5
                current_freq = base_frequency * scale_ratio5
            elsif current_note = 6
                current_freq = base_frequency * scale_ratio6
            else
                current_freq = base_frequency * scale_ratio7
            endif
            
            note_formula$ = "if x >= " + string$(note_time) + " and x < " + string$(note_time + note_dur)
            note_formula$ = note_formula$ + " then 0.7 * sin(2*pi*" + string$(current_freq) + "*x)"
            note_formula$ = note_formula$ + " * (1 - cos(2*pi*(x-" + string$(note_time) + ")/" + string$(note_dur) + "))/2"
            note_formula$ = note_formula$ + " else 0 fi"
            
            if formula$ = "0"
                formula$ = note_formula$
            else
                formula$ = formula$ + " + " + note_formula$
            endif
        endif
        
        if randomUniform(0,1) < step_probability
            step = randomInteger(-2, 2)
            current_note = current_note + step
            current_note = max(1, min(scale_degrees, current_note))
        endif
    endif
    
    if note mod 20 = 0
        echo Generated 'note'/'total_notes' notes
    endif
endfor

Create Sound from formula... random_walk_melody 1 0 duration sampling_frequency 'formula$'
Scale peak... 0.9

echo Random Walk Melody complete!