# ============================================================
# Praat AudioTools - Simple Poisson Sound.praat
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

form Simple Poisson Sound
    real Duration 6.0
    real Sampling_frequency 44100
    real Points_per_second 10.0
    real Base_frequency 200
endform

echo Creating Poisson process...
Create Poisson process: "points", 0, duration, points_per_second

selectObject: "PointProcess points"
numberOfPoints = Get number of points
echo Found 'numberOfPoints' Poisson points

formula$ = "0"

for point to numberOfPoints
    selectObject: "PointProcess points"
    pointTime = Get time from index: point
    
    freq = base_frequency * (0.8 + 0.4 * randomUniform(0,1))
    dur = 0.1
    amp = 0.7
    
    if pointTime + dur <= duration
        event_formula$ = "if x >= " + string$(pointTime) + " and x < " + string$(pointTime + dur)
        event_formula$ = event_formula$ + " then " + string$(amp)
        event_formula$ = event_formula$ + " * sin(2*pi*" + string$(freq) + "*x)"
        event_formula$ = event_formula$ + " * sin(pi*(x-" + string$(pointTime) + ")/" + string$(dur) + ")"
        event_formula$ = event_formula$ + " else 0 fi"
        
        if formula$ = "0"
            formula$ = event_formula$
        else
            formula$ = formula$ + " + " + event_formula$
        endif
    endif
endfor

Create Sound from formula: "simple_poisson", 1, 0, duration, sampling_frequency, formula$
Scale peak: 0.9

selectObject: "PointProcess points"
Remove

echo Simple Poisson Sound complete!