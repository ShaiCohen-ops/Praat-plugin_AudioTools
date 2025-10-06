# ============================================================
# Praat AudioTools - Cellular Automata Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Sound synthesis or generative algorithm script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Cellular Automata Synthesis
    real Duration 8.0
    real Sampling_frequency 44100
    integer Grid_size 32
    choice Rule_type: 1
    button Elementary_CA
    button Game_of_Life
    button Brian_Brain
    integer Rule_number 30
    real Segment_duration 0.1
    real Base_frequency 150
    real Frequency_spread 200
endform

echo Creating Cellular Automata Synthesis...

total_segments = round(duration / segment_duration)
formula$ = "0"

if rule_type = 1
    echo Using Elementary CA Rule 'rule_number'
    call ElementaryCA
elsif rule_type = 2
    echo Using Game of Life
    call GameOfLife
else
    echo Using Brian's Brain
    call BrianBrain
endif

Create Sound from formula... ca_sound 1 0 duration sampling_frequency 'formula$'
Scale peak... 0.9

echo Cellular Automata Synthesis complete!

procedure ElementaryCA
    for i to grid_size
        if i = round(grid_size/2)
            ca[1,i] = 1
        else
            ca[1,i] = 0
        endif
    endfor

    for segment to total_segments
        segment_time = (segment-1) * segment_duration
        
        for cell to grid_size
            if ca[segment,cell] = 1
                freq = base_frequency + (cell/grid_size) * frequency_spread
                amp = 0.6
                dur = segment_duration
                
                if segment_time + dur > duration
                    dur = duration - segment_time
                endif
                
                if dur > 0.001
                    cell_formula$ = "if x >= " + string$(segment_time) + " and x < " + string$(segment_time + dur)
                    cell_formula$ = cell_formula$ + " then " + string$(amp)
                    cell_formula$ = cell_formula$ + " * sin(2*pi*" + string$(freq) + "*x)"
                    cell_formula$ = cell_formula$ + " * (1 - cos(2*pi*(x-" + string$(segment_time) + ")/" + string$(dur) + "))/2"
                    cell_formula$ = cell_formula$ + " else 0 fi"
                    
                    if formula$ = "0"
                        formula$ = cell_formula$
                    else
                        formula$ = formula$ + " + " + cell_formula$
                    endif
                endif
            endif
        endfor
        
        if segment < total_segments
            for cell to grid_size
                left = 0
                center = 0
                right = 0
                
                if cell > 1
                    left = ca[segment,cell-1]
                endif
                
                center = ca[segment,cell]
                
                if cell < grid_size
                    right = ca[segment,cell+1]
                endif
                
                pattern = 4 * left + 2 * center + right
                rule_bit = (rule_number mod (2^(pattern+1))) div (2^pattern)
                ca[segment+1,cell] = rule_bit
            endfor
        endif
        
        if segment mod 10 = 0
            echo Processed 'segment'/'total_segments' segments
        endif
    endfor
endproc

procedure GameOfLife
    for i to grid_size
        for j to grid_size
            if randomUniform(0,1) > 0.7
                ca[i,j] = 1
            else
                ca[i,j] = 0
            endif
        endfor
    endfor

    for segment to total_segments
        segment_time = (segment-1) * segment_duration
        
        active_cells = 0
        for i to grid_size
            for j to grid_size
                if ca[i,j] = 1
                    active_cells = active_cells + 1
                    freq_x = base_frequency + (i/grid_size) * frequency_spread
                    freq_y = base_frequency/2 + (j/grid_size) * frequency_spread/2
                    freq = (freq_x + freq_y) / 2
                    amp = 0.4 / grid_size
                    dur = segment_duration
                    
                    if segment_time + dur > duration
                        dur = duration - segment_time
                    endif
                    
                    if dur > 0.001
                        cell_formula$ = "if x >= " + string$(segment_time) + " and x < " + string$(segment_time + dur)
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
        
        if segment < total_segments
            for i to grid_size
                for j to grid_size
                    neighbors = 0
                    
                    for di from -1 to 1
                        for dj from -1 to 1
                            if di != 0 or dj != 0
                                ni = i + di
                                nj = j + dj
                                if ni >= 1 and ni <= grid_size and nj >= 1 and nj <= grid_size
                                    neighbors = neighbors + ca[ni,nj]
                                endif
                            endif
                        endfor
                    endfor
                    
                    if ca[i,j] = 1
                        if neighbors < 2 or neighbors > 3
                            next_ca[i,j] = 0
                        else
                            next_ca[i,j] = 1
                        endif
                    else
                        if neighbors = 3
                            next_ca[i,j] = 1
                        else
                            next_ca[i,j] = 0
                        endif
                    endif
                endfor
            endfor
            
            for i to grid_size
                for j to grid_size
                    ca[i,j] = next_ca[i,j]
                endfor
            endfor
        endif
        
        if segment mod 5 = 0
            echo Segment 'segment'/'total_segments', Active cells: 'active_cells'
        endif
    endfor
endproc

procedure BrianBrain
    for i to grid_size
        for j to grid_size
            r = randomUniform(0,1)
            if r < 0.3
                ca[i,j] = 1
            elsif r < 0.5
                ca[i,j] = 2
            else
                ca[i,j] = 0
            endif
        endfor
    endfor

    for segment to total_segments
        segment_time = (segment-1) * segment_duration
        
        for i to grid_size
            for j to grid_size
                if ca[i,j] = 1
                    freq = base_frequency + ((i+j)/(2*grid_size)) * frequency_spread
                    amp = 0.5 / grid_size
                    dur = segment_duration
                    
                    if segment_time + dur > duration
                        dur = duration - segment_time
                    endif
                    
                    if dur > 0.001
                        cell_formula$ = "if x >= " + string$(segment_time) + " and x < " + string$(segment_time + dur)
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
        
        if segment < total_segments
            for i to grid_size
                for j to grid_size
                    neighbors = 0
                    
                    for di from -1 to 1
                        for dj from -1 to 1
                            if di != 0 or dj != 0
                                ni = i + di
                                nj = j + dj
                                if ni >= 1 and ni <= grid_size and nj >= 1 and nj <= grid_size
                                    if ca[ni,nj] = 1
                                        neighbors = neighbors + 1
                                    endif
                                endif
                            endif
                        endfor
                    endfor
                    
                    if ca[i,j] = 0
                        if neighbors = 2
                            next_ca[i,j] = 1
                        else
                            next_ca[i,j] = 0
                        endif
                    elsif ca[i,j] = 1
                        next_ca[i,j] = 2
                    else
                        next_ca[i,j] = 0
                    endif
                endfor
            endfor
            
            for i to grid_size
                for j to grid_size
                    ca[i,j] = next_ca[i,j]
                endfor
            endfor
        endif
        
        if segment mod 5 = 0
            echo Processed 'segment'/'total_segments' segments
        endif
    endfor
endproc