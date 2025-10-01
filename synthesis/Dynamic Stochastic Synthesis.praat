form Dynamic Stochastic Synthesis
    real Duration 8.0
    real Sampling_frequency 44100
    real Base_frequency 120
    real Initial_density 30
    real Final_density 150
    real Frequency_evolution_speed 1.0
endform

echo Building dynamic stochastic formula...

total_grains = round((initial_density + final_density)/2 * duration)
formula$ = "0"

for i to total_grains
    t = randomUniform(0, duration)
    normalized_time = t / duration
    
    current_density = initial_density + (final_density - initial_density) * normalized_time
    current_freq = base_frequency * (2^(frequency_evolution_speed * normalized_time))
    
    grain_freq = current_freq * (0.8 + 0.4 * randomUniform(0,1))
    grain_amp = 0.6 * (1 - normalized_time^0.7)
    grain_duration = 0.02 + 0.06 * randomUniform(0,1)
    
    grain_start = t
    grain_end = grain_start + grain_duration
    
    if grain_end > duration
        grain_duration = duration - grain_start
        grain_end = duration
    endif
    
    grain_formula$ = "if x >= " + string$(grain_start) + " and x < " + string$(grain_end)
    grain_formula$ = grain_formula$ + " then " + string$(grain_amp)
    grain_formula$ = grain_formula$ + " * sin(2*pi*" + string$(grain_freq) + "*x)"
    grain_formula$ = grain_formula$ + " * sin(pi*(x-" + string$(grain_start) + ")/" + string$(grain_duration) + ")"
    grain_formula$ = grain_formula$ + " else 0 fi"
    
    if i = 1
        formula$ = grain_formula$
    else
        formula$ = formula$ + " + " + grain_formula$
    endif
    
    if i mod 100 == 0
        echo Added 'i' of 'total_grains' grains...
    endif
endfor

echo Creating final sound...
Create Sound from formula... dss_result 1 0 duration sampling_frequency 'formula$'
Scale peak... 0.9

echo Dynamic Stochastic Synthesis complete!