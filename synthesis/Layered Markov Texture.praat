form Layered Markov Texture
    real Duration 10.0
    real Sampling_frequency 44100
    integer Layers 3
    real Base_frequency 80
    real Layer_spacing 1.5
    real Density_per_layer 3.0
    boolean Enable_cross_layer_influence yes
endform

echo Building Layered Markov Texture...

final_formula$ = "0"

for layer from 1 to layers
    echo Building layer 'layer' of 'layers'...
    
    layer_freq = base_frequency * (layer_spacing^(layer-1))
    states = 4 + layer
    current_state = randomInteger(1, states)
    total_events = round(duration * density_per_layer)
    
    formula_layer$ = "0"
    current_time = 0
    event_count = 0
    
    for state from 1 to states
        state_freq[state] = layer_freq * (1.2^(state-1))
        state_dur[state] = 0.1 + (state/states) * 0.3
        state_amp[state] = (0.3/layers) + (state/states) * (0.4/layers)
    endfor
    
    while current_time < duration and event_count < total_events
        event_count = event_count + 1
        
        current_freq = state_freq[current_state]
        current_dur = state_dur[current_state] * (0.8 + 0.4 * randomUniform(0,1))
        current_amp = state_amp[current_state]
        
        if current_time + current_dur > duration
            current_dur = duration - current_time
        endif
        
        if current_dur > 0.01
            event_formula$ = "if x >= " + string$(current_time) + " and x < " + string$(current_time + current_dur)
            event_formula$ = event_formula$ + " then " + string$(current_amp)
            event_formula$ = event_formula$ + " * sin(2*pi*" + string$(current_freq) + "*x)"
            event_formula$ = event_formula$ + " * (1 - cos(2*pi*(x-" + string$(current_time) + ")/" + string$(current_dur) + "))/2"
            event_formula$ = event_formula$ + " else 0 fi"
            
            if formula_layer$ = "0"
                formula_layer$ = event_formula$
            else
                formula_layer$ = formula_layer$ + " + " + event_formula$
            endif
        endif
        
        current_time = current_time + current_dur
        
        r = randomUniform(0,1)
        if r < 0.5
            current_state = current_state
        elsif r < 0.8
            current_state = current_state + 1
            if current_state > states
                current_state = 1
            endif
        else
            current_state = current_state - 1
            if current_state < 1
                current_state = states
            endif
        endif
    endwhile
    
    if final_formula$ = "0"
        final_formula$ = formula_layer$
    else
        final_formula$ = final_formula$ + " + " + formula_layer$
    endif
    
    echo Layer 'layer' complete: 'event_count' events
endfor

echo Creating layered sound...
Create Sound from formula... layered_markov 1 0 duration sampling_frequency 'final_formula$'

Scale peak... 0.9

echo Layered Markov Texture complete!