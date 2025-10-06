# ============================================================
# Praat AudioTools - Rich Formant Grains.praat
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

form Rich Formant Grains
    real Duration 7.0
    real Sampling_frequency 44100
    real Grain_density 40.0
    real Base_frequency 120
endform

echo Creating Rich Formant Grains...

total_grains = round(duration * grain_density)
formula$ = "0"

for grain to total_grains
    grain_time = randomUniform(0, duration - 0.15)
    
    # More nuanced vowel selection with weighted probabilities
    r = randomUniform(0,1)
    if r < 0.25
        f1 = 730  
# A
        f2 = 1090
        f3 = 2440
    elsif r < 0.45
        f1 = 270  
# I
        f2 = 2290
        f3 = 3010
    elsif r < 0.6
        f1 = 300  
# U
        f2 = 870
        f3 = 2240
    elsif r < 0.75
        f1 = 530  
# E
        f2 = 1840
        f3 = 2480
    else
        f1 = 570  
# O
        f2 = 840
        f3 = 2410
    endif
    
    grain_dur = 0.04 + 0.08 * randomUniform(0,1)
    grain_amp = 0.7 + 0.2 * randomUniform(0,1)
    
    # Add slight pitch variation to each grain
    pitch_variation = 0.9 + 0.2 * randomUniform(0,1)
    
    if grain_time + grain_dur > duration
        grain_dur = duration - grain_time
    endif
    
    if grain_dur > 0.001
        grain_formula$ = "if x >= " + string$(grain_time) + " and x < " + string$(grain_time + grain_dur)
        grain_formula$ = grain_formula$ + " then " + string$(grain_amp)
        grain_formula$ = grain_formula$ + " * (0.3*sin(2*pi*'base_frequency'*" + string$(pitch_variation) + "*x) + "
        grain_formula$ = grain_formula$ + "0.5*sin(2*pi*" + string$(f1) + "*x) + "
        grain_formula$ = grain_formula$ + "0.4*sin(2*pi*" + string$(f2) + "*x) + "
        grain_formula$ = grain_formula$ + "0.3*sin(2*pi*" + string$(f3) + "*x))"
        grain_formula$ = grain_formula$ + " * sin(pi*(x-" + string$(grain_time) + ")/" + string$(grain_dur) + ")"
        grain_formula$ = grain_formula$ + " else 0 fi"
        
        if formula$ = "0"
            formula$ = grain_formula$
        else
            formula$ = formula$ + " + " + grain_formula$
        endif
    endif
endfor

Create Sound from formula... rich_formant_grains 1 0 duration sampling_frequency 'formula$'
Scale peak... 0.9

echo Rich Formant Grains complete!