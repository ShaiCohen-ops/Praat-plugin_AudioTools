form Random Walk Rhythm
    real Duration 8.0
    real Sampling_frequency 44100
    real Tempo 120
    integer Steps_per_beat 4
    real Base_frequency 180
    real Frequency_step 50
    real Probability_up 0.4
    real Probability_down 0.4
endform

echo Creating Random Walk Rhythm...

beats_per_second = tempo / 60
beat_duration = 1 / beats_per_second
step_duration = beat_duration / steps_per_beat
total_steps = round(duration / step_duration)

current_freq = base_frequency
formula$ = "0"

for step to total_steps
    step_time = (step-1) * step_duration
    
    if step_time < duration
        event_duration = step_duration * 0.8
        if step_time + event_duration > duration
            event_duration = duration - step_time
        endif
        
        if event_duration > 0.001
            event_formula$ = "if x >= " + string$(step_time) + " and x < " + string$(step_time + event_duration)
            event_formula$ = event_formula$ + " then 0.8 * sin(2*pi*" + string$(current_freq) + "*x)"
            event_formula$ = event_formula$ + " * exp(-15*(x-" + string$(step_time) + ")/" + string$(event_duration) + ")"
            event_formula$ = event_formula$ + " else 0 fi"
            
            if formula$ = "0"
                formula$ = event_formula$
            else
                formula$ = formula$ + " + " + event_formula$
            endif
        endif
        
        r = randomUniform(0,1)
        if r < probability_up
            current_freq = current_freq + frequency_step
        elsif r < probability_up + probability_down
            current_freq = current_freq - frequency_step
        endif
        
        current_freq = max(80, min(1500, current_freq))
    endif
    
    if step mod 50 = 0
        echo Processed 'step'/'total_steps' steps
    endif
endfor

Create Sound from formula... random_walk_rhythm 1 0 duration sampling_frequency 'formula$'
Scale peak... 0.9

echo Random Walk Rhythm complete!