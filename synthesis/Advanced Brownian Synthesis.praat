form Advanced Brownian Synthesis
    real Duration 8.0
    real Sampling_frequency 44100
    integer Number_voices 2
    real Base_frequency 150
    real Frequency_spread 100
    real Step_size 10
    boolean Enable_drift yes
    real Drift_force 0.1
endform

echo Creating 'number_voices' Brownian voices...

formula$ = "0"

for voice to number_voices
    echo Building voice 'voice'
    voice_freq = base_frequency + (voice-1) * frequency_spread
    voice_formula$ = "0"
    current_time = 0
    control_rate = 40
    time_step = 1/control_rate
    
    while current_time < duration
        segment_duration = min(time_step, duration - current_time)
        
        if segment_duration > 0.001
            brownian_step = randomGauss(0, 1) * step_size
            
            if enable_drift = 1
                drift = (base_frequency - voice_freq) * drift_force * time_step
                brownian_step = brownian_step + drift
            endif
            
            voice_freq = voice_freq + brownian_step
            voice_freq = max(30, min(5000, voice_freq))
            
            voice_amp = 0.6 / number_voices
            
            segment_formula$ = "if x >= " + string$(current_time) + " and x < " + string$(current_time + segment_duration)
            segment_formula$ = segment_formula$ + " then " + string$(voice_amp)
            segment_formula$ = segment_formula$ + " * sin(2*pi*" + string$(voice_freq) + "*x)"
            segment_formula$ = segment_formula$ + " else 0 fi"
            
            if voice_formula$ = "0"
                voice_formula$ = segment_formula$
            else
                voice_formula$ = voice_formula$ + " + " + segment_formula$
            endif
        endif
        
        current_time = current_time + time_step
    endwhile
    
    if formula$ = "0"
        formula$ = voice_formula$
    else
        formula$ = formula$ + " + " + voice_formula$
    endif
endfor

Create Sound from formula... advanced_brownian 1 0 duration sampling_frequency 'formula$'
Scale peak... 0.9

echo Advanced Brownian Synthesis complete!