form Simple Cellular Automata
    real Duration 6.0
    real Sampling_frequency 44100
    integer Grid_size 20
    integer Rule_number 30
    real Base_frequency 200
endform

echo Creating Simple Cellular Automata...

total_steps = 50
step_duration = duration / total_steps
formula$ = "0"

for i to grid_size
    if i = round(grid_size/2)
        current[i] = 1
    else
        current[i] = 0
    endif
endfor

for step to total_steps
    step_time = (step-1) * step_duration
    
    for cell to grid_size
        if current[cell] = 1
            freq = base_frequency + (cell/grid_size) * 300
            amp = 0.7
            dur = step_duration * 0.9
            
            if step_time + dur > duration
                dur = duration - step_time
            endif
            
            if dur > 0.001
                cell_formula$ = "if x >= " + string$(step_time) + " and x < " + string$(step_time + dur)
                cell_formula$ = cell_formula$ + " then " + string$(amp)
                cell_formula$ = cell_formula$ + " * sin(2*pi*" + string$(freq) + "*x)"
                cell_formula$ = cell_formula$ + " * sin(pi*(x-" + string$(step_time) + ")/" + string$(dur) + ")"
                cell_formula$ = cell_formula$ + " else 0 fi"
                
                if formula$ = "0"
                    formula$ = cell_formula$
                else
                    formula$ = formula$ + " + " + cell_formula$
                endif
            endif
        endif
    endfor
    
    if step < total_steps
        for cell to grid_size
            left_neighbor = 0
            right_neighbor = 0
            
            if cell > 1
                left_neighbor = current[cell-1]
            endif
            
            if cell < grid_size
                right_neighbor = current[cell+1]
            endif
            
            center = current[cell]
            
            pattern = 4 * left_neighbor + 2 * center + right_neighbor
            rule_power = 2 ^ pattern
            rule_value = (rule_number mod (2 * rule_power)) div rule_power
            next[cell] = rule_value
        endfor
        
        for cell to grid_size
            current[cell] = next[cell]
        endfor
    endif
    
    if step mod 10 = 0
        echo Completed 'step'/'total_steps' steps
    endif
endfor

Create Sound from formula... simple_ca 1 0 duration sampling_frequency 'formula$'
Scale peak... 0.9

echo Simple Cellular Automata complete!