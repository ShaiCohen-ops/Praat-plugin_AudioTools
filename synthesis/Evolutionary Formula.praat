# ============================================================
# Praat AudioTools - Evolutionary Formula.praat
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

form Evolutionary Formula
    real Duration 15.0
    real Sampling_frequency 44100
    real Base_frequency 80
    real Evolution_speed 1.0
endform

echo Creating Evolutionary Formula...

# This formula evolves through different regimes
formula$ = "("
formula$ = formula$ + "sin(2*pi*'base_frequency'*x * "
formula$ = formula$ + "(1 + 0.5*sin(2*pi*0.3*x) + 0.3*sin(2*pi*2*x))) * "
formula$ = formula$ + "(0.7 + 0.3*sin(2*pi*0.1*x)) + "

formula$ = formula$ + "0.8*sin(2*pi*'base_frequency'*1.333*x * "
formula$ = formula$ + "(1 + 0.4*sin(2*pi*0.5*x + 0.7*sin(2*pi*1.2*x)))) * "
formula$ = formula$ + "(0.6 + 0.4*sin(2*pi*0.07*x)) + "

formula$ = formula$ + "0.6*sin(2*pi*'base_frequency'*1.667*x * "
formula$ = formula$ + "(1 + 0.6*sin(2*pi*0.8*x + 1.2*sin(2*pi*0.4*x)))) * "
formula$ = formula$ + "(0.5 + 0.5*sin(2*pi*0.12*x)) + "

formula$ = formula$ + "0.4*sin(2*pi*'base_frequency'*2.0*x * "
formula$ = formula$ + "(1 + 0.7*sin(2*pi*1.1*x + 1.5*sin(2*pi*0.6*x)))) * "
formula$ = formula$ + "(0.4 + 0.6*sin(2*pi*0.15*x))"

formula$ = formula$ + ") * (0.8 + 0.2*sin(2*pi*0.02*x)) * "
formula$ = formula$ + "(1 - 0.3*x/'duration')"

Create Sound from formula... evolutionary 1 0 duration sampling_frequency 'formula$'
Scale peak... 0.8

echo Evolutionary Formula complete!