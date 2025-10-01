form Fast Game of Life Synthesis
    real Duration 8.0
    real Sampling_frequency 44100
    integer Grid_size 12
    real Base_frequency 200
    integer Total_steps 30
endform

echo Pre-computing Game of Life...

step_duration = duration / total_steps
formula$ = "0"

call PrecomputeGameOfLife

for step to total_steps
    step_time = (step-1) * step_duration
    active_count = 0
    
    for i to grid_size
        for j to grid_size
            if ca[step,i,j] = 1
                active_count = active_count + 1
                freq = base_frequency + ((i+j)/(2*grid_size)) * 400
                amp = 0.5 / grid_size
                
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
    
    if step mod 5 = 0
        echo Rendered step 'step'/'total_steps', Active cells: 'active_count'
    endif
endfor

Create Sound from formula... fast_game_of_life 1 0 duration sampling_frequency 'formula$'
Scale peak... 0.9

echo Fast Game of Life Synthesis complete!

procedure PrecomputeGameOfLife
    for i to grid_size
        for j to grid_size
            if randomUniform(0,1) > 0.7
                ca[1,i,j] = 1
            else
                ca[1,i,j] = 0
            endif
        endfor
    endfor

    for step from 2 to total_steps
        for i to grid_size
            for j to grid_size
                neighbors = 0
                
                for di from -1 to 1
                    for dj from -1 to 1
                        if di != 0 or dj != 0
                            ni = i + di
                            nj = j + dj
                            if ni >= 1 and ni <= grid_size and nj >= 1 and nj <= grid_size
                                neighbors = neighbors + ca[step-1,ni,nj]
                            endif
                        endif
                    endfor
                endfor
                
                if ca[step-1,i,j] = 1
                    if neighbors < 2 or neighbors > 3
                        ca[step,i,j] = 0
                    else
                        ca[step,i,j] = 1
                    endif
                else
                    if neighbors = 3
                        ca[step,i,j] = 1
                    else
                        ca[step,i,j] = 0
                    endif
                endif
            endfor
        endfor
        
        if step mod 10 = 0
            echo Pre-computed step 'step'/'total_steps'
        endif
    endfor
endproc