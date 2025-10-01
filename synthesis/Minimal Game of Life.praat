form Minimal Game of Life
    real Duration 6.0
    real Sampling_frequency 44100
    integer Grid_size 8
    real Base_frequency 250
endform

echo Creating Minimal Game of Life...

total_steps = 20
step_duration = duration / total_steps
formula$ = "0"

for i to grid_size
    for j to grid_size
        if randomUniform(0,1) > 0.5
            current[i,j] = 1
        else
            current[i,j] = 0
        endif
    endfor
endfor

for step to total_steps
    step_time = (step-1) * step_duration
    
    for i to grid_size
        for j to grid_size
            if current[i,j] = 1
                freq = base_frequency + (i/grid_size) * 300
                amp = 0.6
                
                if step_time + step_duration > duration
                    current_dur = duration - step_time
                else
                    current_dur = step_duration
                endif
                
                if current_dur > 0.001
                    cell_formula$ = "if x >= " + string$(step_time) + " and x < " + string$(step_time + current_dur)
                    cell_formula$ = cell_formula$ + " then " + string$(amp)
                    cell_formula$ = cell_formula$ + " * sin(2*pi*" + string$(freq) + "*x)"
                    cell_formula$ = cell_formula$ + " else 0 fi"
                    
                    if formula$ = "0"
                        formula$ = cell_formula$
                    else
                        formula$ = formula$ + " + " + cell_formula$
                    endif
                endif
            endif
        endfor
    endfor
    
    if step < total_steps
        for i to grid_size
            for j to grid_size
                neighbors = 0
                
                for di from -1 to 1
                    for dj from -1 to 1
                        if di != 0 or dj != 0
                            ni = i + di
                            nj = j + dj
                            if ni >= 1 and ni <= grid_size and nj >= 1 and nj <= grid_size
                                neighbors = neighbors + current[ni,nj]
                            endif
                        endif
                    endfor
                endfor
                
                if current[i,j] = 1
                    if neighbors = 2 or neighbors = 3
                        next[i,j] = 1
                    else
                        next[i,j] = 0
                    endif
                else
                    if neighbors = 3
                        next[i,j] = 1
                    else
                        next[i,j] = 0
                    endif
                endif
            endfor
        endfor
        
        for i to grid_size
            for j to grid_size
                current[i,j] = next[i,j]
            endfor
        endfor
    endif
    
    if step mod 5 = 0
        echo Completed step 'step'/'total_steps'
    endif
endfor

Create Sound from formula... minimal_life 1 0 duration sampling_frequency 'formula$'
Scale peak... 0.9

echo Minimal Game of Life complete!