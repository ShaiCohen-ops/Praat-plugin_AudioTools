form Poisson Point Process Synthesis
    real Duration 10.0
    real Sampling_frequency 44100
    real Event_rate 8.0
    real Base_frequency 120
    real Frequency_spread 200
    real Grain_duration 0.1
    real Grain_duration_spread 0.05
endform

echo Building Poisson Point Process Synthesis using native Praat commands...

Create Poisson process: "poisson", 0, duration, event_rate
Rename: "poisson_points"

numberOfPoints = Get number of points
echo Found 'numberOfPoints' Poisson points

Create Sound from formula: "poisson_sound", 1, 0, duration, sampling_frequency, "0"

formula$ = "0"

for point to numberOfPoints
    selectObject: "PointProcess poisson_points"
    pointTime = Get time from index: point
    
    grain_freq = base_frequency + frequency_spread * (randomUniform(0,1) - 0.5)
    grain_dur = grain_duration + grain_duration_spread * (randomUniform(0,1) - 0.5)
    grain_dur = max(0.01, grain_dur)
    grain_amp = 0.6 * (0.7 + 0.3 * randomUniform(0,1))
    
    if pointTime + grain_dur > duration
        grain_dur = duration - pointTime
    endif
    
    if grain_dur > 0.005
        grain_formula$ = "if x >= " + string$(pointTime) + " and x < " + string$(pointTime + grain_dur)
        grain_formula$ = grain_formula$ + " then " + string$(grain_amp)
        grain_formula$ = grain_formula$ + " * sin(2*pi*" + string$(grain_freq) + "*x)"
        grain_formula$ = grain_formula$ + " * (1 - cos(2*pi*(x-" + string$(pointTime) + ")/" + string$(grain_dur) + "))/2"
        grain_formula$ = grain_formula$ + " else 0 fi"
        
        if formula$ = "0"
            formula$ = grain_formula$
        else
            formula$ = formula$ + " + " + grain_formula$
        endif
    endif
    
    if point mod 100 = 0
        echo Processed 'point'/'numberOfPoints' points...
    endif
endfor

selectObject: "Sound poisson_sound"
Remove

Create Sound from formula: "poisson_synthesis", 1, 0, duration, sampling_frequency, formula$
Scale peak: 0.9

selectObject: "PointProcess poisson_points"
Remove

echo Poisson Synthesis complete!
echo Total events: 'numberOfPoints'