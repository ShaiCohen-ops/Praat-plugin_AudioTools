form Simple Tier Control
    real Duration 6.0
    real Sampling_frequency 44100
    real Grain_density 20.0
    real Base_frequency 200
endform

echo Creating Simple Tier Control...

total_grains = round(duration * grain_density)
formula$ = "0"

Create PitchTier: "simple_pitch", 0, duration
Create IntensityTier: "simple_amp", 0, duration  
Create DurationTier: "simple_dur", 0, duration

points = 20
for i to points
    time = (i-1) * duration / (points-1)
    
    pitch_value = base_frequency * (0.7 + 0.6 * sin(2*pi*time/duration))
    selectObject: "PitchTier simple_pitch"
    Add point: time, pitch_value
    
    amp_value = 0.3 + 0.5 * (0.5 + 0.5 * cos(2*pi*time/duration))
    selectObject: "IntensityTier simple_amp"
    Add point: time, amp_value
    
    dur_value = 0.03 + 0.1 * (0.5 + 0.5 * sin(2*pi*time/duration * 2))
    selectObject: "DurationTier simple_dur"
    Add point: time, dur_value
endfor

for grain to total_grains
    grain_time = randomUniform(0, duration - 0.05)
    
    selectObject: "PitchTier simple_pitch"
    grain_freq = Get value at time: grain_time
    
    selectObject: "IntensityTier simple_amp"
    grain_amp = Get value at time: grain_time
    
    selectObject: "DurationTier simple_dur"
    grain_dur = Get value at time: grain_time
    
    if grain_time + grain_dur > duration
        grain_dur = duration - grain_time
    endif
    
    if grain_dur > 0.001
        grain_formula$ = "if x >= " + string$(grain_time) + " and x < " + string$(grain_time + grain_dur)
        grain_formula$ = grain_formula$ + " then " + string$(grain_amp)
        grain_formula$ = grain_formula$ + " * sin(2*pi*" + string$(grain_freq) + "*x)"
        grain_formula$ = grain_formula$ + " * sin(pi*(x-" + string$(grain_time) + ")/" + string$(grain_dur) + ")"
        grain_formula$ = grain_formula$ + " else 0 fi"
        
        if formula$ = "0"
            formula$ = grain_formula$
        else
            formula$ = formula$ + " + " + grain_formula$
        endif
    endif
endfor

Create Sound from formula: "simple_tier_control", 1, 0, duration, sampling_frequency, formula$
Scale peak: 0.9

selectObject: "PitchTier simple_pitch"
plusObject: "IntensityTier simple_amp" 
plusObject: "DurationTier simple_dur"
Remove

echo Simple Tier Control complete!