form Advanced Poisson Synthesis
    real Duration 12.0
    real Sampling_frequency 44100
    real Low_rate 3.0
    real High_rate 15.0
    real Base_frequency 100
    real Frequency_range 300
    boolean Enable_layered_processes yes
endform

echo Building Advanced Poisson Synthesis...

Create Poisson process: "poisson_low", 0, duration, low_rate
Create Poisson process: "poisson_high", 0, duration, high_rate

if enable_layered_processes
    Create Poisson process: "poisson_mid", 0, duration, (low_rate + high_rate)/2
endif

formula$ = "0"

# Process low rate events
selectObject: "PointProcess poisson_low"
numberLow = Get number of points
echo Low rate process: 'numberLow' points

for point to numberLow
    pointTime = Get time from index: point
    grain_freq = base_frequency + frequency_range * randomUniform(0,1)
    grain_dur = 0.2 + 0.3 * randomUniform(0,1)
    grain_amp = 0.8
    
    # Inline grain addition (no procedure)
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
endfor

# Process high rate events  
selectObject: "PointProcess poisson_high"
numberHigh = Get number of points
echo High rate process: 'numberHigh' points

for point to numberHigh
    pointTime = Get time from index: point
    grain_freq = base_frequency * 2 + frequency_range * randomUniform(0,1)
    grain_dur = 0.05 + 0.1 * randomUniform(0,1)
    grain_amp = 0.4
    
    # Inline grain addition (no procedure)
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
endfor

if enable_layered_processes
    selectObject: "PointProcess poisson_mid"
    numberMid = Get number of points
    echo Mid rate process: 'numberMid' points
    
    for point to numberMid
        pointTime = Get time from index: point
        grain_freq = base_frequency * 1.5 + frequency_range * randomUniform(0,1)
        grain_dur = 0.1 + 0.15 * randomUniform(0,1)
        grain_amp = 0.6
        
        # Inline grain addition (no procedure)
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
    endfor
endif

Create Sound from formula: "advanced_poisson", 1, 0, duration, sampling_frequency, formula$
Scale peak: 0.9

# Cleanup
selectObject: "PointProcess poisson_low"
plusObject: "PointProcess poisson_high"
if enable_layered_processes
    plusObject: "PointProcess poisson_mid"
endif
Remove

echo Advanced Poisson Synthesis complete!
echo Total events: 'numberLow + numberHigh + numberMid'