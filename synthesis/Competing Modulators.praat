# ============================================================
# Praat AudioTools - Competing Modulators.praat
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

form Competing Modulators
    real Duration 10.0
    real Sampling_frequency 44100
    real Base_frequency 120
    real Modulation_intensity 0.5
    integer Number_voices 4
endform

echo Creating Competing Modulators...

formula$ = "("

for voice to number_voices
    voice_amp = 1.0 / number_voices
    voice_ratio = 0.5 + (voice-1) * 0.3
    
    # Each voice has different modulation characteristics
    if voice = 1
        # Brownian-like modulation
        voice_formula$ = "'voice_amp' * sin(2*pi*'base_frequency'*'voice_ratio'*x * "
        voice_formula$ = voice_formula$ + "(1 + 'modulation_intensity'*0.3*(sin(2*pi*0.2*x) + 0.2*sin(2*pi*1.7*x))))"
        
    elsif voice = 2
        # Chaotic modulation
        voice_formula$ = "'voice_amp' * sin(2*pi*'base_frequency'*'voice_ratio'*x * "
        voice_formula$ = voice_formula$ + "(1 + 'modulation_intensity'*0.4*sin(2*pi*3*x + 2*sin(2*pi*0.8*x))))"
        
    elsif voice = 3
        # Random walk simulation
        voice_formula$ = "'voice_amp' * sin(2*pi*'base_frequency'*'voice_ratio'*x * "
        voice_formula$ = voice_formula$ + "(1 + 'modulation_intensity'*0.5*(x/'duration')*sin(2*pi*5*x)))"
        
    else
        # Exponential processes
        voice_formula$ = "'voice_amp' * sin(2*pi*'base_frequency'*'voice_ratio'*x * "
        voice_formula$ = voice_formula$ + "exp(-0.5*'modulation_intensity'*sin(2*pi*2*x)))"
    endif
    
    if voice = 1
        formula$ = formula$ + voice_formula$
    else
        formula$ = formula$ + " + " + voice_formula$
    endif
endfor

formula$ = formula$ + ") * (0.6 + 0.4*sin(2*pi*0.1*x))"

Create Sound from formula... competing_modulators 1 0 duration sampling_frequency 'formula$'
Scale peak... 0.9

echo Competing Modulators complete!