form Chaotic Granular Synthesis
    real Duration 10.0
    real Sampling_frequency 44100
    real Base_frequency 120
    real Grain_density 20
    optionmenu Chaos_Type: 1
    option Logistic Map
    option Henon Map
endform

echo Creating Chaotic Granular Synthesis...

total_grains = round(duration * grain_density)
formula$ = "0"

# Fixed: Use the correct variable name from the form
if chaos_Type = 1
    r = 3.7
    chaos_x = 0.5
else
    a = 1.4
    b = 0.3
    chaos_x = 0.1
    chaos_y = 0.1
endif

for grain to total_grains
    grain_time = randomUniform(0, duration - 0.2)
    grain_dur = 0.05 + 0.1 * randomUniform(0,1)
    
    if chaos_Type = 1
        chaos_x = r * chaos_x * (1 - chaos_x)
        grain_freq = base_frequency * (0.3 + 1.4 * chaos_x)
    else
        new_x = 1 - a * chaos_x * chaos_x + chaos_y
        chaos_y = b * chaos_x
        chaos_x = new_x
        grain_freq = base_frequency * (0.5 + chaos_x)
    endif
    
    grain_amp = 0.7
    
    if grain_time + grain_dur > duration
        grain_dur = duration - grain_time
    endif
    
    if grain_dur > 0.001
        grain_formula$ = "if x >= " + string$(grain_time) + " and x < " + string$(grain_time + grain_dur)
        grain_formula$ = grain_formula$ + " then " + string$(grain_amp)
        grain_formula$ = grain_formula$ + " * sin(2*pi*" + string$(grain_freq) + "*x)"
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

Create Sound from formula... chaotic_grains 1 0 duration sampling_frequency 'formula$'
Scale peak... 0.9

echo Chaotic Granular Synthesis complete!