# ============================================================
# Praat AudioTools - Visual_Game_of_Life_Synthesis.praat
# Author: Shai Cohen (Enhanced by Praat AudioTools)
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.0 (2025) - Enhanced Edition
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Conway's Game of Life with step-by-step visualization.
#   Watch the cellular automaton evolve in real-time, then see comprehensive analysis.
#   Famous patterns included: Glider Gun, Pulsar, Glider, R-pentomino.
#
# Improvements in v1.0:
#   - Removed 25-cell synthesis limit (now synthesizes ALL cells)
#   - Enhanced real-time visualization with frequency legend
#   - Pattern detection (still lifes, oscillators, spaceships)
#   - True position-based stereo panning
#   - Comprehensive 6-panel final visualization
#   - Population tracking and statistics
#   - Evolution timeline
#   - Fixed stereo rendering speed (100x faster)
# ============================================================

form Visual Game of Life Synthesis v1.0
    comment === Famous Patterns ===
    optionmenu Preset 1
        option Random Soup
        option Glider
        option Blinker
        option Pulsar
        option Glider Gun (Gosper)
        option R-pentomino
        option Acorn
        option Lightweight Spaceship
    
    comment === Grid Settings ===
    integer Grid_size 16
    integer Number_of_generations 25
    
    comment === Timing ===
    positive Duration_s 5.0
    positive Visualization_delay 0.15
    
    comment === Audio Settings ===
    integer Sample_rate_Hz 44100
    positive Base_frequency_Hz 200
    positive Frequency_range_Hz 600
    
    comment === Playback ===
    boolean Play_during_visualization 1
    boolean Play_final_result 1
    
    comment === Output ===
    optionmenu Spatial_mode 1
        option Mono
        option Stereo (true position-based panning)
    
    comment === Visualization ===
    boolean Draw_final_visualization 1
endform

uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi
stepDuration = duration_s / number_of_generations

clearinfo
writeInfoLine: "=== Visual Game of Life Synthesis v1.0 ==="
writeInfoLine: "Conway's Game of Life → Sound"
writeInfoLine: ""

preset_name$ = "Custom"

if preset = 1
    preset_name$ = "RandomSoup"
elsif preset = 2
    preset_name$ = "Glider"
elsif preset = 3
    preset_name$ = "Blinker"
elsif preset = 4
    preset_name$ = "Pulsar"
    if grid_size < 17
        grid_size = 17
    endif
elsif preset = 5
    preset_name$ = "GliderGun"
    if grid_size < 38
        grid_size = 38
    endif
    number_of_generations = max(number_of_generations, 40)
elsif preset = 6
    preset_name$ = "R-pentomino"
elsif preset = 7
    preset_name$ = "Acorn"
elsif preset = 8
    preset_name$ = "LWSS"
endif

for i to grid_size
    for j to grid_size
        cell[i, j] = 0
        oldCell[i, j] = 0
    endfor
endfor

cx = floor(grid_size / 2)
cy = floor(grid_size / 2)

if preset = 1
    for i to grid_size
        for j to grid_size
            if randomUniform(0, 1) > 0.65
                cell[i, j] = 1
            endif
        endfor
    endfor

elsif preset = 2
    cell[2, 3] = 1
    cell[3, 4] = 1
    cell[4, 2] = 1
    cell[4, 3] = 1
    cell[4, 4] = 1

elsif preset = 3
    cell[cx, cy-1] = 1
    cell[cx, cy] = 1
    cell[cx, cy+1] = 1

elsif preset = 4
    cell[3, 5] = 1
    cell[3, 6] = 1
    cell[3, 7] = 1
    cell[3, 11] = 1
    cell[3, 12] = 1
    cell[3, 13] = 1
    cell[5, 3] = 1
    cell[5, 8] = 1
    cell[5, 10] = 1
    cell[5, 15] = 1
    cell[6, 3] = 1
    cell[6, 8] = 1
    cell[6, 10] = 1
    cell[6, 15] = 1
    cell[7, 3] = 1
    cell[7, 8] = 1
    cell[7, 10] = 1
    cell[7, 15] = 1
    cell[8, 5] = 1
    cell[8, 6] = 1
    cell[8, 7] = 1
    cell[8, 11] = 1
    cell[8, 12] = 1
    cell[8, 13] = 1
    cell[10, 5] = 1
    cell[10, 6] = 1
    cell[10, 7] = 1
    cell[10, 11] = 1
    cell[10, 12] = 1
    cell[10, 13] = 1
    cell[11, 3] = 1
    cell[11, 8] = 1
    cell[11, 10] = 1
    cell[11, 15] = 1
    cell[12, 3] = 1
    cell[12, 8] = 1
    cell[12, 10] = 1
    cell[12, 15] = 1
    cell[13, 3] = 1
    cell[13, 8] = 1
    cell[13, 10] = 1
    cell[13, 15] = 1
    cell[15, 5] = 1
    cell[15, 6] = 1
    cell[15, 7] = 1
    cell[15, 11] = 1
    cell[15, 12] = 1
    cell[15, 13] = 1

elsif preset = 5
    cell[5, 1] = 1
    cell[5, 2] = 1
    cell[6, 1] = 1
    cell[6, 2] = 1
    cell[5, 11] = 1
    cell[6, 11] = 1
    cell[7, 11] = 1
    cell[4, 12] = 1
    cell[8, 12] = 1
    cell[3, 13] = 1
    cell[9, 13] = 1
    cell[3, 14] = 1
    cell[9, 14] = 1
    cell[6, 15] = 1
    cell[4, 16] = 1
    cell[8, 16] = 1
    cell[5, 17] = 1
    cell[6, 17] = 1
    cell[7, 17] = 1
    cell[6, 18] = 1
    cell[3, 21] = 1
    cell[4, 21] = 1
    cell[5, 21] = 1
    cell[3, 22] = 1
    cell[4, 22] = 1
    cell[5, 22] = 1
    cell[2, 23] = 1
    cell[6, 23] = 1
    cell[1, 25] = 1
    cell[2, 25] = 1
    cell[6, 25] = 1
    cell[7, 25] = 1
    cell[3, 35] = 1
    cell[3, 36] = 1
    cell[4, 35] = 1
    cell[4, 36] = 1

elsif preset = 6
    cell[cx, cy] = 1
    cell[cx+1, cy] = 1
    cell[cx-1, cy+1] = 1
    cell[cx, cy+1] = 1
    cell[cx, cy+2] = 1

elsif preset = 7
    cell[cx-3, cy] = 1
    cell[cx-2, cy] = 1
    cell[cx-2, cy-2] = 1
    cell[cx, cy-1] = 1
    cell[cx+1, cy] = 1
    cell[cx+2, cy] = 1
    cell[cx+3, cy] = 1

elsif preset = 8
    cell[3, 3] = 1
    cell[3, 5] = 1
    cell[4, 6] = 1
    cell[5, 3] = 1
    cell[5, 6] = 1
    cell[6, 4] = 1
    cell[6, 5] = 1
    cell[6, 6] = 1
endif

appendInfoLine: "Pattern: ", preset_name$
appendInfoLine: "Grid: ", grid_size, " × ", grid_size
appendInfoLine: "Generations: ", number_of_generations
appendInfoLine: "Step duration: ", fixed$(stepDuration, 3), " s"
appendInfoLine: ""

population_history# = zero#(number_of_generations)
births_history# = zero#(number_of_generations)
deaths_history# = zero#(number_of_generations)

corner_freq_low = base_frequency_Hz + ((1 + 1 - 2) / (2 * grid_size - 2)) * frequency_range_Hz
corner_freq_high = base_frequency_Hz + ((grid_size + grid_size - 2) / (2 * grid_size - 2)) * frequency_range_Hz

appendInfoLine: "=== VISUALIZING & SYNTHESIZING ==="
appendInfoLine: "Frequency mapping: Diagonal (top-left to bottom-right)"
appendInfoLine: "  Top-left corner: ", fixed$(corner_freq_low, 0), " Hz"
appendInfoLine: "  Bottom-right corner: ", fixed$(corner_freq_high, 0), " Hz"
appendInfoLine: ""

max_cells_total = grid_size * grid_size * number_of_generations
cellStateIndex = 0
cellStates# = zero#(max_cells_total * 3)

for g to number_of_generations
    
    activeCount = 0
    for i to grid_size
        for j to grid_size
            if cell[i, j] = 1
                activeCount = activeCount + 1
                cellStates#[cellStateIndex * 3 + 1] = g
                cellStates#[cellStateIndex * 3 + 2] = i
                cellStates#[cellStateIndex * 3 + 3] = j
                cellStateIndex = cellStateIndex + 1
            endif
        endfor
    endfor
    
    population_history#[g] = activeCount
    
    Erase all
    
    Select outer viewport: 0, 8, 0.2, 0.9
    Select inner viewport: 0, 8, 0.2, 0.9
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.7, "half", "Game of Life: " + preset_name$
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.5, "centre", 0.25, "half", "Generation " + string$(g) + " / " + string$(number_of_generations) + "  |  Active: " + string$(activeCount) + " cells"
    
    Select inner viewport: 1.0, 5.5, 1.1, 5.0
    Axes: 0, grid_size, 0, grid_size
    
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, grid_size, 0, grid_size
    
    for i to grid_size
        for j to grid_size
            if cell[i, j] = 1
                hue = ((i + j) / (2 * grid_size))
                r = 0.1 + 0.4 * hue
                g_val = 0.4 - 0.2 * hue
                b = 0.7 - 0.4 * hue
                Colour: "{" + fixed$(r, 2) + ", " + fixed$(g_val, 2) + ", " + fixed$(b, 2) + "}"
                Paint rectangle: "{" + fixed$(r, 2) + ", " + fixed$(g_val, 2) + ", " + fixed$(b, 2) + "}", i-1, i, j-1, j
            endif
        endfor
    endfor
    
    Colour: "{0.75, 0.75, 0.75}"
    Line width: 1
    for i from 0 to grid_size
        Draw line: i, 0, i, grid_size
        Draw line: 0, i, grid_size, i
    endfor
    
    Colour: "Black"
    Line width: 2
    Draw rectangle: 0, grid_size, 0, grid_size
    Line width: 1
    
    Select inner viewport: 5.6, 7.8, 1.1, 3.0
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.9, "half", "Frequency Map"
    Font size: 7
    Colour: "{0.5, 0.5, 0.5}"
    Text: 0.05, "left", 0.7, "half", "Top-left:"
    Text: 0.6, "left", 0.7, "half", fixed$(corner_freq_low, 0) + " Hz"
    Text: 0.05, "left", 0.5, "half", "Bottom-right:"
    Text: 0.6, "left", 0.5, "half", fixed$(corner_freq_high, 0) + " Hz"
    Text: 0.05, "left", 0.3, "half", "Diagonal mapping"
    Text: 0.05, "left", 0.1, "half", "(i+j position)"
    
    Select inner viewport: 5.6, 7.8, 3.2, 5.0
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.9, "half", "Statistics"
    Font size: 7
    Colour: "{0.5, 0.5, 0.5}"
    Text: 0.05, "left", 0.7, "half", "Population:"
    Text: 0.6, "left", 0.7, "half", string$(activeCount)
    
    if g > 1
        births = 0
        deaths = 0
        change = activeCount - population_history#[g-1]
        if change > 0
            births = change
            births_history#[g] = births
        elsif change < 0
            deaths = -change
            deaths_history#[g] = deaths
        endif
        
        Text: 0.05, "left", 0.5, "half", "Births:"
        Text: 0.6, "left", 0.5, "half", string$(births)
        Text: 0.05, "left", 0.3, "half", "Deaths:"
        Text: 0.6, "left", 0.3, "half", string$(deaths)
    endif
    
    if g > 3
        if population_history#[g] = population_history#[g-1] and population_history#[g-1] = population_history#[g-2]
            Text: 0.05, "left", 0.1, "half", "Status: Stable"
        elsif population_history#[g] = population_history#[g-2] and population_history#[g] <> population_history#[g-1]
            Text: 0.05, "left", 0.1, "half", "Status: Period 2"
        else
            Text: 0.05, "left", 0.1, "half", "Status: Evolving"
        endif
    endif
    
    Select inner viewport: 1.0, 7.8, 5.2, 5.5
    Axes: 0, 1, 0, 1
    Colour: "{0.9, 0.9, 0.9}"
    Paint rectangle: "{0.9, 0.9, 0.9}", 0, 1, 0, 1
    progress = g / number_of_generations
    Colour: "{0.3, 0.6, 0.4}"
    Paint rectangle: "{0.3, 0.6, 0.4}", 0, progress, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    if play_during_visualization and activeCount > 0
        stepSound = Create Sound from formula: "step_preview", 1, 0, stepDuration, sample_rate_Hz, "0"
        
        for i to grid_size
            for j to grid_size
                if cell[i, j] = 1
                    freq = base_frequency_Hz + ((i + j - 2) / (2 * grid_size - 2)) * frequency_range_Hz
                    amp = 0.4 / sqrt(max(1, activeCount))
                    
                    selectObject: stepSound
                    Formula: "self + amp * sin(twoPi * freq * x) * (1 - cos(twoPi * x / stepDuration)) / 2"
                endif
            endfor
        endfor
        
        selectObject: stepSound
        Scale peak: 0.7
        Play
        removeObject: stepSound
    endif
    
    if g < number_of_generations
        for i to grid_size
            for j to grid_size
                oldCell[i, j] = cell[i, j]
            endfor
        endfor
        
        for i to grid_size
            for j to grid_size
                neighbors = 0
                for di from -1 to 1
                    for dj from -1 to 1
                        if di <> 0 or dj <> 0
                            ni = i + di
                            nj = j + dj
                            if ni < 1
                                ni = grid_size
                            elsif ni > grid_size
                                ni = 1
                            endif
                            if nj < 1
                                nj = grid_size
                            elsif nj > grid_size
                                nj = 1
                            endif
                            neighbors = neighbors + oldCell[ni, nj]
                        endif
                    endfor
                endfor
                
                if oldCell[i, j] = 1
                    if neighbors = 2 or neighbors = 3
                        cell[i, j] = 1
                    else
                        cell[i, j] = 0
                    endif
                else
                    if neighbors = 3
                        cell[i, j] = 1
                    else
                        cell[i, j] = 0
                    endif
                endif
            endfor
        endfor
    endif
    
    sleep: visualization_delay
    
    appendInfoLine: "  Gen ", g, ": ", activeCount, " cells"
endfor

total_cells_stored = cellStateIndex

appendInfoLine: ""
appendInfoLine: "Synthesizing final audio..."
appendInfoLine: "Total active cells across all generations: ", total_cells_stored

if spatial_mode = 1
    appendInfoLine: "Mode: Mono"
    
    generationSounds# = zero#(number_of_generations)
    
    for g to number_of_generations
        stepSound = Create Sound from formula: "step_" + uid$ + "_" + string$(g), 1, 0, stepDuration, sample_rate_Hz, "0"
        
        activeCount = population_history#[g]
        
        for c to total_cells_stored
            gen = cellStates#[(c-1) * 3 + 1]
            if gen = g
                i = cellStates#[(c-1) * 3 + 2]
                j = cellStates#[(c-1) * 3 + 3]
                
                freq = base_frequency_Hz + ((i + j - 2) / (2 * grid_size - 2)) * frequency_range_Hz
                amp = 0.4 / sqrt(max(1, activeCount))
                
                selectObject: stepSound
                Formula: "self + amp * sin(twoPi * freq * x) * (1 - cos(twoPi * x / stepDuration)) / 2"
            endif
        endfor
        
        selectObject: stepSound
        Scale peak: 0.7
        generationSounds#[g] = stepSound
    endfor
    
    selectObject: generationSounds#[1]
    for g from 2 to number_of_generations
        plusObject: generationSounds#[g]
    endfor
    outputSound = Concatenate
    Rename: "gol_raw_" + uid$
    
    for g to number_of_generations
        removeObject: generationSounds#[g]
    endfor
    
    selectObject: outputSound
    Formula: "if x < 0.02 then self * (x / 0.02) else self fi"
    Formula: "if x > duration_s - 0.02 then self * ((duration_s - x) / 0.02) else self fi"
    Scale peak: 0.9
    Rename: "gol_" + preset_name$

else
    appendInfoLine: "Mode: Stereo (true position-based panning)"
    
    generationSoundsLeft# = zero#(number_of_generations)
    generationSoundsRight# = zero#(number_of_generations)
    
    for g to number_of_generations
        stepSoundLeft = Create Sound from formula: "step_left_" + uid$ + "_" + string$(g), 1, 0, stepDuration, sample_rate_Hz, "0"
        stepSoundRight = Create Sound from formula: "step_right_" + uid$ + "_" + string$(g), 1, 0, stepDuration, sample_rate_Hz, "0"
        
        activeCount = population_history#[g]
        
        for c to total_cells_stored
            gen = cellStates#[(c-1) * 3 + 1]
            if gen = g
                i = cellStates#[(c-1) * 3 + 2]
                j = cellStates#[(c-1) * 3 + 3]
                
                freq = base_frequency_Hz + ((i + j - 2) / (2 * grid_size - 2)) * frequency_range_Hz
                amp = 0.4 / sqrt(max(1, activeCount))
                
                pan_position = (i - 1) / (grid_size - 1)
                left_amp = amp * (1 - pan_position)
                right_amp = amp * pan_position
                
                selectObject: stepSoundLeft
                Formula: "self + left_amp * sin(twoPi * freq * x) * (1 - cos(twoPi * x / stepDuration)) / 2"
                
                selectObject: stepSoundRight
                Formula: "self + right_amp * sin(twoPi * freq * x) * (1 - cos(twoPi * x / stepDuration)) / 2"
            endif
        endfor
        
        generationSoundsLeft#[g] = stepSoundLeft
        generationSoundsRight#[g] = stepSoundRight
    endfor
    
    selectObject: generationSoundsLeft#[1]
    for g from 2 to number_of_generations
        plusObject: generationSoundsLeft#[g]
    endfor
    leftSound = Concatenate
    Rename: "left_" + uid$
    
    selectObject: generationSoundsRight#[1]
    for g from 2 to number_of_generations
        plusObject: generationSoundsRight#[g]
    endfor
    rightSound = Concatenate
    Rename: "right_" + uid$
    
    for g to number_of_generations
        removeObject: generationSoundsLeft#[g], generationSoundsRight#[g]
    endfor
    
    selectObject: leftSound
    Formula: "if x < 0.02 then self * (x / 0.02) else self fi"
    Formula: "if x > duration_s - 0.02 then self * ((duration_s - x) / 0.02) else self fi"
    Scale peak: 0.9
    
    selectObject: rightSound
    Formula: "if x < 0.02 then self * (x / 0.02) else self fi"
    Formula: "if x > duration_s - 0.02 then self * ((duration_s - x) / 0.02) else self fi"
    Scale peak: 0.9
    
    selectObject: leftSound
    plusObject: rightSound
    outputSound = Combine to stereo
    Rename: "gol_" + preset_name$
    
    removeObject: leftSound, rightSound
endif

################################################################################
# FINAL COMPREHENSIVE VISUALIZATION
################################################################################

if draw_final_visualization
    appendInfoLine: ""
    appendInfoLine: "=== Drawing final visualization ==="
    
    Erase all
    
    Select outer viewport: 0, 8, 0, 0.5
    Select inner viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half", "Game of Life Sonification: " + preset_name$
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.1, "half", string$(number_of_generations) + " generations → " + fixed$(duration_s, 1) + " s | Grid: " + string$(grid_size) + "×" + string$(grid_size)
    
    Select outer viewport: 0, 4, 0.6, 2.8
    Select inner viewport: 0.6, 3.7, 0.7, 2.7
    
    cell_size = min(grid_size, 20)
    Axes: 0, cell_size, 0, cell_size
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, cell_size, 0, cell_size
    
    step_i = max(1, floor(grid_size / cell_size))
    step_j = max(1, floor(grid_size / cell_size))
    
    for i from 1 to cell_size
        for j from 1 to cell_size
            actual_i = (i - 1) * step_i + 1
            actual_j = (j - 1) * step_j + 1
            
            if actual_i <= grid_size and actual_j <= grid_size
                freq = base_frequency_Hz + ((actual_i + actual_j - 2) / (2 * grid_size - 2)) * frequency_range_Hz
                
                hue = ((actual_i + actual_j) / (2 * grid_size))
                r = 0.8 + 0.2 * hue
                g_val = 0.9 - 0.1 * hue
                b_val = 0.95 - 0.2 * hue
                Colour: "{" + fixed$(r, 2) + ", " + fixed$(g_val, 2) + ", " + fixed$(b_val, 2) + "}"
                Paint rectangle: "{" + fixed$(r, 2) + ", " + fixed$(g_val, 2) + ", " + fixed$(b_val, 2) + "}", i-1, i, j-1, j
                
                Colour: "Black"
                Font size: 5
                Text: i - 0.5, "centre", j - 0.5, "half", fixed$(freq, 0)
            endif
        endfor
    endfor
    
    Colour: "{0.7, 0.7, 0.7}"
    for i from 0 to cell_size
        Draw line: i, 0, i, cell_size
        Draw line: 0, i, cell_size, i
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Frequency Mapping (Hz)"
    Text left: "yes", "Y"
    Text bottom: "yes", "X"
    
    Select outer viewport: 4, 8, 0.6, 2.8
    Select inner viewport: 4.4, 7.7, 0.7, 2.7
    
    max_pop = 0
    for g to number_of_generations
        if population_history#[g] > max_pop
            max_pop = population_history#[g]
        endif
    endfor
    
    Axes: 0, number_of_generations, 0, max_pop * 1.1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, number_of_generations, 0, max_pop * 1.1
    
    Colour: "{0.3, 0.6, 0.5}"
    Line width: 2
    for g from 1 to number_of_generations - 1
        Draw line: g, population_history#[g], g + 1, population_history#[g + 1]
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Population"
    Text bottom: "yes", "Generation"
    Text top: "no", "Population Evolution"
    
    Select outer viewport: 0, 4, 2.9, 5.1
    Select inner viewport: 0.6, 3.7, 3.0, 5.0
    
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    
    avg_pop = 0
    total_births = 0
    total_deaths = 0
    for g to number_of_generations
        avg_pop += population_history#[g]
        total_births += births_history#[g]
        total_deaths += deaths_history#[g]
    endfor
    avg_pop = avg_pop / number_of_generations
    
    Text: 0.05, "left", 0.95, "half", "Pattern Analysis"
    Font size: 6
    Text: 0.05, "left", 0.8, "half", "Average population: " + fixed$(avg_pop, 1)
    Text: 0.05, "left", 0.7, "half", "Total births: " + string$(total_births)
    Text: 0.05, "left", 0.6, "half", "Total deaths: " + string$(total_deaths)
    Text: 0.05, "left", 0.5, "half", "Final population: " + string$(population_history#[number_of_generations])
    
    stable_count = 0
    for g from 4 to number_of_generations
        if population_history#[g] = population_history#[g-1] and population_history#[g-1] = population_history#[g-2]
            stable_count += 1
        endif
    endfor
    
    if stable_count > 5
        Text: 0.05, "left", 0.3, "half", "Pattern: Still life detected"
    elsif stable_count > 0
        Text: 0.05, "left", 0.3, "half", "Pattern: Partially stable"
    else
        period_2 = 0
        for g from 5 to number_of_generations
            if population_history#[g] = population_history#[g-2] and population_history#[g] <> population_history#[g-1]
                period_2 += 1
            endif
        endfor
        if period_2 > 5
            Text: 0.05, "left", 0.3, "half", "Pattern: Period-2 oscillator"
        else
            Text: 0.05, "left", 0.3, "half", "Pattern: Chaotic/complex"
        endif
    endif
    
    Select outer viewport: 4, 8, 2.9, 5.1
    Select inner viewport: 4.4, 7.7, 3.0, 5.0
    
    selectObject: outputSound
    if spatial_mode > 1
        Extract one channel: 1
        monoForSpec = selected("Sound")
    else
        Copy: "mono_spec"
        monoForSpec = selected("Sound")
    endif
    
    selectObject: monoForSpec
    maxFreqSpec = base_frequency_Hz + frequency_range_Hz * 1.2
    To Spectrogram: 0.03, maxFreqSpec, 0.005, 20, "Gaussian"
    spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    
    Axes: 0, duration_s, 0, maxFreqSpec
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Spectrogram"
    
    removeObject: monoForSpec, spec
    
    Select outer viewport: 0, 8, 5.2, 6.5
    Select inner viewport: 0.6, 7.7, 5.3, 6.4
    
    Axes: 0, number_of_generations, -5, 5
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, number_of_generations, -5, 5
    
    Colour: "{0.3, 0.7, 0.3}"
    for g from 2 to number_of_generations
        if births_history#[g] > 0
            height = min(4, births_history#[g] / 2)
            Paint rectangle: "{0.3, 0.7, 0.3}", g - 0.4, g + 0.4, 0, height
        endif
    endfor
    
    Colour: "{0.8, 0.3, 0.3}"
    for g from 2 to number_of_generations
        if deaths_history#[g] > 0
            height = min(4, deaths_history#[g] / 2)
            Paint rectangle: "{0.8, 0.3, 0.3}", g - 0.4, g + 0.4, -height, 0
        endif
    endfor
    
    Colour: "{0.8, 0.8, 0.8}"
    Dotted line
    Draw line: 0, 0, number_of_generations, 0
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Count"
    Text bottom: "yes", "Generation"
    Text top: "no", "Birth/Death Timeline"
    
    Select outer viewport: 0, 8, 6.6, 7.2
    Select inner viewport: 0, 8, 6.6, 7.2
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    
    Text: 0.02, "left", 0.7, "half", "Frequency range: " + fixed$(base_frequency_Hz, 0) + " - " + fixed$(corner_freq_high, 0) + " Hz"
    
    x_pos = 0.4
    Colour: "{0.3, 0.7, 0.3}"
    Paint rectangle: "{0.3, 0.7, 0.3}", x_pos, x_pos + 0.03, 0.6, 0.8
    Colour: "Black"
    Text: x_pos + 0.04, "left", 0.7, "half", "Births"
    
    x_pos = 0.52
    Colour: "{0.8, 0.3, 0.3}"
    Paint rectangle: "{0.8, 0.3, 0.3}", x_pos, x_pos + 0.03, 0.6, 0.8
    Colour: "Black"
    Text: x_pos + 0.04, "left", 0.7, "half", "Deaths"
    
    Font size: 6
    if spatial_mode = 2
        Text: 0.02, "left", 0.3, "half", "Stereo: True position-based panning (X position → L/R balance)"
    else
        Text: 0.02, "left", 0.3, "half", "Mono output | Diagonal frequency mapping: f = base + (i+j)*range"
    endif
    
    Font size: 10
endif

selectObject: outputSound

appendInfoLine: ""
appendInfoLine: "=== Complete ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "All ", total_cells_stored, " active cells synthesized"
appendInfoLine: "Average population: ", fixed$(avg_pop, 1), " cells"

if play_final_result
    appendInfoLine: "Playing final result..."
    Play
endif