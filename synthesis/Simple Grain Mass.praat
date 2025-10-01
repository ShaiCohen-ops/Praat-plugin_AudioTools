form Simple Grain Mass
    real Duration 10.0
    real Sampling_frequency 44100
    real Grain_density 30.0
    real Base_frequency 180
endform

echo Creating Simple Grain Mass...

total_grains = round(duration * grain_density)
formula$ = "0"

for grain to total_grains
    grain_time = randomUniform(0, duration - 0.1)
    grain_freq = base_frequency * (0.5 + randomUniform(0,1))
    grain_dur = 0.05 + 0.1 * randomUniform(0,1)
    grain_amp = 0.7
    
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
    
    if grain mod 100 = 0
        echo Generated 'grain'/'total_grains' grains
    endif
endfor

Create Sound from formula... simple_grain_mass 1 0 duration sampling_frequency 'formula$'
Scale peak... 0.9

echo Simple Grain Mass complete!