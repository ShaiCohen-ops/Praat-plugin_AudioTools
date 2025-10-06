# ============================================================
# Praat AudioTools - Dynamic Vowel Transitions.praat
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

form Dynamic Vowel Transitions
    real Duration 4.0
    real Sampling_frequency 44100
    choice Transition: 1
    button A_to_I
    button I_to_U
    button U_to_A
    button All_vowels
endform

echo Creating Dynamic Vowel Transitions...

if transition = 1
    # A to I transition
    start_f1 = 730
    start_f2 = 1090
    start_f3 = 2440
    end_f1 = 270
    end_f2 = 2290
    end_f3 = 3010
    transition_name$ = "A_to_I"
elsif transition = 2
    # I to U transition
    start_f1 = 270
    start_f2 = 2290
    start_f3 = 3010
    end_f1 = 300
    end_f2 = 870
    end_f3 = 2240
    transition_name$ = "I_to_U"
elsif transition = 3
    # U to A transition
    start_f1 = 300
    start_f2 = 870
    start_f3 = 2240
    end_f1 = 730
    end_f2 = 1090
    end_f3 = 2440
    transition_name$ = "U_to_A"
else
    # Cycle through all vowels
    start_f1 = 730
    start_f2 = 1090
    start_f3 = 2440
    end_f1 = 730
    end_f2 = 1090
    end_f3 = 2440
    transition_name$ = "All_vowels"
endif

if transition = 4
    # Complex cycle through all vowels
    formula$ = "("
    formula$ = formula$ + "0.4*sin(2*pi*120*x) + "
    formula$ = formula$ + "0.6*sin(2*pi*(400 + 400*sin(2*pi*0.25*x))*x) + "  # F1 varies
    formula$ = formula$ + "0.5*sin(2*pi*(1000 + 1500*(0.5+0.5*sin(2*pi*0.2*x)))*x) + "  # F2 varies
    formula$ = formula$ + "0.3*sin(2*pi*(2000 + 1500*(0.5+0.5*sin(2*pi*0.15*x)))*x)"  # F3 varies
    formula$ = formula$ + ") * (0.7 + 0.3*sin(2*pi*0.1*x)) * exp(-0.1*x/'duration')"
else
    # Smooth transition between two vowels
    formula$ = "("
    formula$ = formula$ + "0.4*sin(2*pi*120*x) + "
    formula$ = formula$ + "0.6*sin(2*pi*('start_f1' + ('end_f1'-'start_f1')*(x/'duration'))*x) + "
    formula$ = formula$ + "0.5*sin(2*pi*('start_f2' + ('end_f2'-'start_f2')*(x/'duration'))*x) + "
    formula$ = formula$ + "0.3*sin(2*pi*('start_f3' + ('end_f3'-'start_f3')*(x/'duration'))*x)"
    formula$ = formula$ + ") * (0.8 + 0.2*sin(2*pi*0.3*x)) * exp(-0.2*x/'duration')"
endif

Create Sound from formula... 'transition_name$' 1 0 duration sampling_frequency 'formula$'
Scale peak... 0.9

echo Dynamic Vowel Transition 'transition_name$' complete!