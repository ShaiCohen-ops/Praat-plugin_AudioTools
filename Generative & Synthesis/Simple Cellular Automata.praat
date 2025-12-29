# ============================================================
# Praat AudioTools - Simple Cellular Automata.praat
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

form Simple Cellular Automata
    real Duration 5.0
    real Sampling_frequency 44100
    integer Grid_size 30
    integer Rule_number 30
    real Base_frequency 200
    optionmenu Preset: 1
        option Custom
        option Rule 30 (Chaotic)
        option Rule 90 (Fractal)
        option Rule 110 (Complex)
        option Rule 184 (Traffic)
        option Rule 60 (Simple)
        option Rule 102 (Sparse)
        option Rule 150 (Noisy)
        option Rule 54 (Organic)
    optionmenu Spatial_mode: 1
        option Mono
        option Stereo Spread
        option Panning Evolution
        option Binaural CA
endform

echo Creating Simple Cellular Automata...

# Apply presets
if preset > 1
    if preset = 2
        # Rule 30 - Chaotic, unpredictable
        rule_number = 30
        grid_size = 35
        
    elsif preset = 3
        # Rule 90 - Fractal patterns
        rule_number = 90
        grid_size = 40
        
    elsif preset = 4
        # Rule 110 - Complex, Turing complete
        rule_number = 110
        grid_size = 30
        
    elsif preset = 5
        # Rule 184 - Traffic flow patterns
        rule_number = 184
        grid_size = 25
        
    elsif preset = 6
        # Rule 60 - Simple self-similar
        rule_number = 60
        grid_size = 20
        
    elsif preset = 7
        # Rule 102 - Sparse, musical
        rule_number = 102
        grid_size = 15
        
    elsif preset = 8
        # Rule 150 - Noisy, dense
        rule_number = 150
        grid_size = 45
        
    elsif preset = 9
        # Rule 54 - Organic, growing
        rule_number = 54
        grid_size = 30
    endif
endif

echo Using preset: 'preset'
echo Rule number: 'rule_number'

total_steps = 60
step_duration = duration / total_steps
formula$ = "0"

# Initialize arrays
for i to grid_size
    if i = round(grid_size/2)
        current[i] = 1
    else
        current[i] = 0
    endif
endfor

for step to total_steps
    step_time = (step-1) * step_duration
    
    # Generate sound for current state
    for cell to grid_size
        if current[cell] = 1
            # Map cell position to frequency and pan
            freq = base_frequency + (cell/grid_size) * 800
            pan_pos = (cell/grid_size) * 2 - 1  
# -1 to 1
            amp = 0.6 + 0.3 * (1 - abs(pan_pos))  
# Center cells louder
            dur = step_duration * 0.8
            
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
    
    # Compute next generation
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

Create Sound from formula: "ca_output", 1, 0, duration, sampling_frequency, formula$
Scale peak: 0.9

# ====== SPATIAL PROCESSING ======
select Sound ca_output

if spatial_mode = 1
    # MONO - Keep as is
    Rename: "cellular_automata_mono"
    output_sound = selected("Sound")
    
elsif spatial_mode = 2
    # STEREO SPREAD - Map cell position to stereo field
    Copy: "ca_left"
    left_sound = selected("Sound")
    
    select Sound ca_output
    Copy: "ca_right" 
    right_sound = selected("Sound")
    
    # Left channel emphasizes lower frequencies (left cells)
    select left_sound
    Formula: "self * 0.9"
    Filter (pass Hann band): 0, 3000, 100
    
    # Right channel emphasizes higher frequencies (right cells)
    select right_sound
    Formula: "self * 0.9"
    Filter (pass Hann band): 200, 6000, 100
    
    # Combine to stereo
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "cellular_automata_stereo"
    output_sound = selected("Sound")
    
    # Cleanup
    select left_sound
    plus right_sound
    Remove
    
elsif spatial_mode = 3
    # PANNING EVOLUTION - Pan evolves over time
    Copy: "ca_left"
    left_sound = selected("Sound")
    
    select Sound ca_output
    Copy: "ca_right"
    right_sound = selected("Sound")
    
    # Apply evolving panning
    pan_rate = 0.2
    select left_sound
    Formula: "self * (0.4 + 0.4 * cos(2*pi*pan_rate*x))"
    
    select right_sound
    Formula: "self * (0.4 + 0.4 * sin(2*pi*pan_rate*x))"
    
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "cellular_automata_panning"
    output_sound = selected("Sound")
    
    select left_sound
    plus right_sound
    Remove
    
elsif spatial_mode = 4
    # BINAURAL CA - Spatial simulation of CA evolution
    Copy: "ca_left"
    left_sound = selected("Sound")
    
    select Sound ca_output
    Copy: "ca_right"
    right_sound = selected("Sound")
    
    # Left channel: warm, centered evolution
    select left_sound
    Filter (pass Hann band): 50, 4000, 80
    Formula: "self * (0.7 + 0.2 * sin(2*pi*x*0.15))"
    
    # Right channel: bright, detailed evolution
    select right_sound
    Filter (pass Hann band): 100, 7000, 80
    Formula: "self * (0.6 + 0.3 * cos(2*pi*x*0.25))"
    
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "cellular_automata_binaural"
    output_sound = selected("Sound")
    
    select left_sound
    plus right_sound
    Remove
endif

select output_sound
Play

echo Cellular Automata complete!
echo Preset: 'preset' (Rule 'rule_number')
echo Spatial mode: 'spatial_mode'
echo Grid size: 'grid_size' cells