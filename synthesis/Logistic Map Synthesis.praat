# ============================================================
# Praat AudioTools - Logistic Map Synthesis.praat
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

form Logistic Map Synthesis
    real Duration 8.0
    real Sampling_frequency 44100
    real Base_frequency 180
    real R_parameter 3.7
    real Initial_x 0.5
endform

echo Creating Logistic Map Synthesis...

control_rate = 100
time_step = 1/control_rate
total_points = round(duration * control_rate)
formula$ = "0"

logistic_x = initial_x

for i to total_points
    current_time = (i-1) * time_step
    
    logistic_x = r_parameter * logistic_x * (1 - logistic_x)
    current_freq = base_frequency * (0.5 + logistic_x)
    current_amp = 0.6 * logistic_x
    
    if current_time + time_step > duration
        current_dur = duration - current_time
    else
        current_dur = time_step
    endif
    
    if current_dur > 0.001
        segment_formula$ = "if x >= " + string$(current_time) + " and x < " + string$(current_time + current_dur)
        segment_formula$ = segment_formula$ + " then " + string$(current_amp)
        segment_formula$ = segment_formula$ + " * sin(2*pi*" + string$(current_freq) + "*x)"
        segment_formula$ = segment_formula$ + " else 0 fi"
        
        if formula$ = "0"
            formula$ = segment_formula$
        else
            formula$ = formula$ + " + " + segment_formula$
        endif
    endif
    
    if i mod 100 = 0
        echo Processed 'i'/'total_points' points, x='logistic_x:3'
    endif
endfor

Create Sound from formula... logistic_sound 1 0 duration sampling_frequency 'formula$'
Scale peak... 0.9

echo Logistic Map Synthesis complete!