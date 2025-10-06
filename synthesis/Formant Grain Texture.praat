# ============================================================
# Praat AudioTools - Formant Grain Texture.praat
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

form Formant Grain Texture
    real Duration 6.0
    real Sampling_frequency 44100
    real Grain_density 30.0
    real Base_frequency 100
endform

echo Creating Formant Grain Texture...

total_grains = round(duration * grain_density)
formula$ = "0"

for grain to total_grains
    grain_time = randomUniform(0, duration - 0.2)
    
    # Random vowel formants for each grain
    vowel_choice = randomInteger(1, 5)
    if vowel_choice = 1
        f1 = 730
        f2 = 1090
        f3 = 2440
    elsif vowel_choice = 2
        f1 = 270
        f2 = 2290
        f3 = 3010
    elsif vowel_choice = 3
        f1 = 300
        f2 = 870
        f3 = 2240
    elsif vowel_choice = 4
        f1 = 530
        f2 = 1840
        f3 = 2480
    else
        f1 = 570
        f2 = 840
        f3 = 2410
    endif
    
    grain_dur = 0.05 + 0.1 * randomUniform(0,1)
    grain_amp = 0.8
    
    if grain_time + grain_dur > duration
        grain_dur = duration - grain_time
    endif
    
    if grain_dur > 0.001
        grain_formula$ = "if x >= " + string$(grain_time) + " and x < " + string$(grain_time + grain_dur)
        grain_formula$ = grain_formula$ + " then " + string$(grain_amp)
        grain_formula$ = grain_formula$ + " * (0.3*sin(2*pi*'base_frequency'*x) + "
        grain_formula$ = grain_formula$ + "0.5*sin(2*pi*" + string$(f1) + "*x) + "
        grain_formula$ = grain_formula$ + "0.4*sin(2*pi*" + string$(f2) + "*x) + "
        grain_formula$ = grain_formula$ + "0.3*sin(2*pi*" + string$(f3) + "*x))"
        grain_formula$ = grain_formula$ + " * (1 - cos(2*pi*(x-" + string$(grain_time) + ")/" + string$(grain_dur) + "))/2"
        grain_formula$ = grain_formula$ + " else 0 fi"
        
        if formula$ = "0"
            formula$ = grain_formula$
        else
            formula$ = formula$ + " + " + grain_formula$
        endif
    endif
    
    if grain mod 50 = 0
        echo Generated 'grain'/'total_grains' grains
    endif
endfor

Create Sound from formula... formant_grains 1 0 duration sampling_frequency 'formula$'
Scale peak... 0.9

echo Formant Grain Texture complete!