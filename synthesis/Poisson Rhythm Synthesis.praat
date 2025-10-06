# ============================================================
# Praat AudioTools - Poisson Rhythm Synthesis.praat
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

form Poisson Rhythm Synthesis
    real Duration 8.0
    real Sampling_frequency 44100
    real Beat_rate 2.0
    real Subdivision_rate 8.0
    real Base_frequency 150
    real Percussive_decay 0.1
endform

echo Building Poisson Rhythm...

Create Poisson process: "main_beats", 0, duration, beat_rate
Create Poisson process: "subdivisions", 0, duration, subdivision_rate

selectObject: "PointProcess main_beats"
numberBeats = Get number of points
selectObject: "PointProcess subdivisions"  
numberSubs = Get number of points

formula$ = "0"

# Add main beats
selectObject: "PointProcess main_beats"
for beat to numberBeats
    beatTime = Get time from index: beat
    
    # Inline drum event (no procedure)
    event_dur = 0.15
    if beatTime + event_dur > duration
        event_dur = duration - beatTime
    endif
    
    if event_dur > 0.005
        event_formula$ = "if x >= " + string$(beatTime) + " and x < " + string$(beatTime + event_dur)
        event_formula$ = event_formula$ + " then 0.8"
        event_formula$ = event_formula$ + " * sin(2*pi*" + string$(base_frequency) + "*x)"
        event_formula$ = event_formula$ + " * exp(-" + string$(1/percussive_decay) + "*(x-" + string$(beatTime) + ")/" + string$(event_dur) + ")"
        event_formula$ = event_formula$ + " else 0 fi"
        
        if formula$ = "0"
            formula$ = event_formula$
        else
            formula$ = formula$ + " + " + event_formula$
        endif
    endif
endfor

# Add subdivisions
selectObject: "PointProcess subdivisions"
for sub to numberSubs
    subTime = Get time from index: sub
    
    # Inline drum event (no procedure)
    event_dur = 0.08
    if subTime + event_dur > duration
        event_dur = duration - subTime
    endif
    
    if event_dur > 0.005
        event_formula$ = "if x >= " + string$(subTime) + " and x < " + string$(subTime + event_dur)
        event_formula$ = event_formula$ + " then 0.5"
        event_formula$ = event_formula$ + " * sin(2*pi*" + string$(base_frequency * 1.5) + "*x)"
        event_formula$ = event_formula$ + " * exp(-" + string$(1/percussive_decay) + "*(x-" + string$(subTime) + ")/" + string$(event_dur) + ")"
        event_formula$ = event_formula$ + " else 0 fi"
        
        if formula$ = "0"
            formula$ = event_formula$
        else
            formula$ = formula$ + " + " + event_formula$
        endif
    endif
endfor

Create Sound from formula: "poisson_rhythm", 1, 0, duration, sampling_frequency, formula$
Scale peak: 0.9

selectObject: "PointProcess main_beats"
plusObject: "PointProcess subdivisions"
Remove

echo Poisson Rhythm complete!
echo Main beats: 'numberBeats', Subdivisions: 'numberSubs'