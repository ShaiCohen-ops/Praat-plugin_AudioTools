form Advanced Chaotic Modulation
    real Duration 12.0
    real Sampling_frequency 44100
    real Base_frequency 150
    boolean Use_logistic_freq yes
    boolean Use_lorenz_amp yes
    boolean Use_henon_filter yes
    real Chaos_intensity 0.7
endform

echo Creating Advanced Chaotic Modulation...

control_rate = 150
time_step = 1/control_rate
total_points = round(duration * control_rate)
formula$ = "0"

logistic_r = 3.7
logistic_x = 0.5

lorenz_x = 1.0
lorenz_y = 1.0
lorenz_z = 1.0
lorenz_sigma = 10.0
lorenz_rho = 28.0
lorenz_beta = 2.666

henon_x = 0.1
henon_y = 0.1
henon_a = 1.4
henon_b = 0.3

for i to total_points
    current_time = (i-1) * time_step
    
    if use_logistic_freq = 1
        logistic_x = logistic_r * logistic_x * (1 - logistic_x)
        freq_mod = base_frequency * (1 + chaos_intensity * (logistic_x - 0.5))
    else
        freq_mod = base_frequency
    endif
    
    if use_lorenz_amp = 1
        lorenz_dx = lorenz_sigma * (lorenz_y - lorenz_x)
        lorenz_dy = lorenz_x * (lorenz_rho - lorenz_z) - lorenz_y
        lorenz_dz = lorenz_x * lorenz_y - lorenz_beta * lorenz_z
        
        lorenz_x = lorenz_x + lorenz_dx * 0.01
        lorenz_y = lorenz_y + lorenz_dy * 0.01
        lorenz_z = lorenz_z + lorenz_dz * 0.01
        
        amp_mod = 0.5 + 0.3 * (lorenz_z / 30)
    else
        amp_mod = 0.6
    endif
    
    if use_henon_filter = 1
        henon_x_new = 1 - henon_a * henon_x * henon_x + henon_y
        henon_y_new = henon_b * henon_x
        henon_x = henon_x_new
        henon_y = henon_y_new
        
        filter_mod = 0.5 + 0.5 * henon_x
    else
        filter_mod = 1.0
    endif
    
    if current_time + time_step > duration
        current_dur = duration - current_time
    else
        current_dur = time_step
    endif
    
    if current_dur > 0.001
        segment_formula$ = "if x >= " + string$(current_time) + " and x < " + string$(current_time + current_dur)
        segment_formula$ = segment_formula$ + " then " + string$(amp_mod)
        segment_formula$ = segment_formula$ + " * sin(2*pi*" + string$(freq_mod) + "*x)"
        segment_formula$ = segment_formula$ + " * " + string$(filter_mod)
        segment_formula$ = segment_formula$ + " else 0 fi"
        
        if formula$ = "0"
            formula$ = segment_formula$
        else
            formula$ = formula$ + " + " + segment_formula$
        endif
    endif
    
    if i mod 150 = 0
        echo Processed 'i'/'total_points' points
    endif
endfor

Create Sound from formula... advanced_chaos 1 0 duration sampling_frequency 'formula$'
Scale peak... 0.9

echo Advanced Chaotic Modulation complete!