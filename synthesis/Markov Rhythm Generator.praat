# ============================================================
# Praat AudioTools - Markov Rhythm Generator.praat
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

form Markov Rhythm Generator
    real Duration 8.0
    real Sampling_frequency 44100
    integer Pattern_length 4
    real Tempo 120
    real Base_frequency 150
endform

echo Building Markov Rhythm Pattern...

beats_per_second = tempo / 60
beat_duration = 1 / beats_per_second
total_beats = round(duration * beats_per_second)

formula$ = "0"

rhythm_states = 4
current_rhythm = randomInteger(1, rhythm_states)

rhythm_pattern$[1] = "1000"
rhythm_pattern$[2] = "1010"
rhythm_pattern$[3] = "1100" 
rhythm_pattern$[4] = "1110"

for beat from 1 to total_beats
    current_pattern$ = rhythm_pattern$[current_rhythm]
    subdivisions = length(current_pattern$)
    
    for subdiv from 1 to subdivisions
        current_char$ = mid$(current_pattern$, subdiv, 1)
        
        if current_char$ = "1"
            start_time = (beat-1) * beat_duration + (subdiv-1) * (beat_duration/subdivisions)
            pulse_dur = beat_duration/subdivisions * 0.7
            
            pulse_formula$ = "if x >= " + string$(start_time) + " and x < " + string$(start_time + pulse_dur)
            pulse_formula$ = pulse_formula$ + " then 0.6 * sin(2*pi*" + string$(base_frequency) + "*x)"
            pulse_formula$ = pulse_formula$ + " * exp(-8*(x-" + string$(start_time) + ")/" + string$(pulse_dur) + ")"
            pulse_formula$ = pulse_formula$ + " else 0 fi"
            
            if formula$ = "0"
                formula$ = pulse_formula$
            else
                formula$ = formula$ + " + " + pulse_formula$
            endif
        endif
    endfor
    
    r = randomUniform(0,1)
    if r < 0.4
        current_rhythm = current_rhythm
    elsif r < 0.7
        current_rhythm = current_rhythm + 1
        if current_rhythm > rhythm_states
            current_rhythm = 1
        endif
    else
        current_rhythm = randomInteger(1, rhythm_states)
    endif
    
    if beat mod 16 = 0
        echo Generated 'beat'/'total_beats' beats...
    endif
endfor

echo Creating rhythm pattern...
Create Sound from formula... markov_rhythm 1 0 duration sampling_frequency 'formula$'

Scale peak... 0.9

echo Markov Rhythm complete!