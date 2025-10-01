form Evolving Grain Mass
    real Duration 15.0
    real Sampling_frequency 44100
    real Initial_density 20.0
    real Final_density 60.0
    real Base_frequency 120
    real Frequency_evolution 2.0
    choice Evolution_type: 1
    button Density_growth
    button Frequency_sweep
    button Statistical_shift
endform

echo Creating Evolving Grain Mass...

total_grains = round(((initial_density + final_density)/2) * duration)
formula$ = "0"

if evolution_type = 1
    call DensityGrowth
elsif evolution_type = 2
    call FrequencySweep
else
    call StatisticalShift
endif

Create Sound from formula... evolving_grains 1 0 duration sampling_frequency 'formula$'
Scale peak... 0.9

echo Evolving Grain Mass complete!

procedure DensityGrowth
    for grain to total_grains
        normalized_time = (grain-1) / total_grains
        current_density = initial_density + (final_density - initial_density) * normalized_time
        
        grain_time = randomUniform(0, duration)
        grain_freq = base_frequency + 200 * randomGauss(0,1)
        grain_dur = 0.05 + 0.1 * randomUniform(0,1)
        grain_amp = 0.6
        
        time_probability = current_density / ((initial_density + final_density)/2)
        
        if randomUniform(0,1) < time_probability and grain_time + grain_dur <= duration
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
        
        if grain mod 200 = 0
            echo Processed 'grain'/'total_grains' grains
        endif
    endfor
endproc

procedure FrequencySweep
    for grain to total_grains
        grain_time = randomUniform(0, duration)
        normalized_time = grain_time / duration
        
        current_base_freq = base_frequency * (frequency_evolution ^ normalized_time)
        grain_freq = current_base_freq + 150 * randomGauss(0,1)
        grain_dur = 0.03 + 0.08 * randomUniform(0,1)
        grain_amp = 0.7 * (1 - normalized_time * 0.3)
        
        if grain_time + grain_dur <= duration
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
endproc

procedure StatisticalShift
    for grain to total_grains
        grain_time = randomUniform(0, duration)
        normalized_time = grain_time / duration
        
        if normalized_time < 0.33
            grain_freq = base_frequency + 100 * randomGauss(0,1)
            grain_dur = 0.1 + 0.15 * randomUniform(0,1)
            grain_amp = 0.8
        elsif normalized_time < 0.66
            grain_freq = base_frequency * 1.5 + 200 * randomUniform(0,1)
            grain_dur = 0.05 + 0.08 * randomUniform(0,1)
            grain_amp = 0.6
        else
            grain_freq = base_frequency * 2.0 + 300 * randomExponential(1)
            grain_dur = 0.02 + 0.04 * randomUniform(0,1)
            grain_amp = 0.4
        endif
        
        if grain_time + grain_dur <= duration
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
    endfor
endproc