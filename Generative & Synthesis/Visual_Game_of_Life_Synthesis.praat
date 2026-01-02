# ============================================================
# Praat AudioTools - Visual_Game_of_Life_Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Conway's Game of Life with step-by-step visualization.
#   Watch the cellular automaton evolve in real-time, then hear the result.
#   Famous patterns included: Glider Gun, Pulsar, Glider, R-pentomino.
#
# Usage:
#   Run this script (no input sound required).
#   Watch the grid evolve in the Picture window.
#   Optionally hear each step as it's computed.
#   After visualization, the full synthesized sound plays.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit 
#   for Experimental Composition.
# ============================================================

form Visual Game of Life Synthesis
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
        option Stereo (position-based)
endform

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi
stepDuration = duration_s / number_of_generations

# === Info ===
writeInfoLine: "=============================================="
writeInfoLine: "  VISUAL GAME OF LIFE SYNTHESIS"
writeInfoLine: "  Conway's Game of Life → Sound"
writeInfoLine: "=============================================="
appendInfoLine: ""

# === Determine grid size based on preset FIRST ===
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

# === NOW initialize grid with correct size ===
for i to grid_size
    for j to grid_size
        cell[i, j] = 0
        oldCell[i, j] = 0
    endfor
endfor

# Center offset
cx = floor(grid_size / 2)
cy = floor(grid_size / 2)

# === Set up pattern ===
if preset = 1
    # Random Soup
    for i to grid_size
        for j to grid_size
            if randomUniform(0, 1) > 0.65
                cell[i, j] = 1
            endif
        endfor
    endfor

elsif preset = 2
    # Glider
    cell[2, 3] = 1
    cell[3, 4] = 1
    cell[4, 2] = 1
    cell[4, 3] = 1
    cell[4, 4] = 1

elsif preset = 3
    # Blinker (period 2)
    cell[cx, cy-1] = 1
    cell[cx, cy] = 1
    cell[cx, cy+1] = 1

elsif preset = 4
    # Pulsar (period 3)
    # Manually set the pulsar pattern
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
    # Gosper Glider Gun
    # Left block
    cell[5, 1] = 1
    cell[5, 2] = 1
    cell[6, 1] = 1
    cell[6, 2] = 1
    # Left part of gun
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
    # Right part of gun
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
    # Right block
    cell[3, 35] = 1
    cell[3, 36] = 1
    cell[4, 35] = 1
    cell[4, 36] = 1

elsif preset = 6
    # R-pentomino (chaotic methuselah)
    cell[cx, cy] = 1
    cell[cx+1, cy] = 1
    cell[cx-1, cy+1] = 1
    cell[cx, cy+1] = 1
    cell[cx, cy+2] = 1

elsif preset = 7
    # Acorn (long-lived methuselah)
    cell[cx-3, cy] = 1
    cell[cx-2, cy] = 1
    cell[cx-2, cy-2] = 1
    cell[cx, cy-1] = 1
    cell[cx+1, cy] = 1
    cell[cx+2, cy] = 1
    cell[cx+3, cy] = 1

elsif preset = 8
    # Lightweight Spaceship (LWSS)
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

# === Create output sound ===
outputSound = Create Sound from formula: "gol_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

# === Main loop: visualize and synthesize each generation ===
appendInfoLine: "=== VISUALIZING & SYNTHESIZING ==="
appendInfoLine: ""

for g to number_of_generations
    
    # === Count active cells ===
    activeCount = 0
    for i to grid_size
        for j to grid_size
            activeCount = activeCount + cell[i, j]
        endfor
    endfor
    
    # === VISUALIZATION ===
    Erase all
    
    # --- Title ---
    Select outer viewport: 0, 8, 0.3, 1.0
    Select inner viewport: 0, 8, 0.3, 1.0
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.75, "half", "Game of Life: " + preset_name$
    Font size: 11
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.5, "centre", 0.25, "half", "Generation " + string$(g) + " / " + string$(number_of_generations) + "  |  Active: " + string$(activeCount) + " cells"
    
    # --- Grid ---
    Select inner viewport: 0.8, 7.2, 1.2, 5.5
    Axes: 0, grid_size, 0, grid_size
    
    # Background
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, grid_size, 0, grid_size
    
    # Draw cells with position-based coloring
    for i to grid_size
        for j to grid_size
            if cell[i, j] = 1
                .hue = ((i + j) / (2 * grid_size))
                .r = 0.1 + 0.4 * .hue
                .g = 0.4 - 0.2 * .hue
                .b = 0.7 - 0.4 * .hue
                Colour: "{" + fixed$(.r, 2) + ", " + fixed$(.g, 2) + ", " + fixed$(.b, 2) + "}"
                Paint rectangle: "{" + fixed$(.r, 2) + ", " + fixed$(.g, 2) + ", " + fixed$(.b, 2) + "}", i-1, i, j-1, j
            endif
        endfor
    endfor
    
    # Grid lines
    Colour: "{0.75, 0.75, 0.75}"
    Line width: 1
    for i from 0 to grid_size
        Draw line: i, 0, i, grid_size
        Draw line: 0, i, grid_size, i
    endfor
    
    # Border
    Colour: "Black"
    Line width: 2
    Draw rectangle: 0, grid_size, 0, grid_size
    Line width: 1
    
    # --- Progress bar ---
    Select inner viewport: 0.8, 7.2, 5.7, 6.0
    Axes: 0, 1, 0, 1
    Colour: "{0.9, 0.9, 0.9}"
    Paint rectangle: "{0.9, 0.9, 0.9}", 0, 1, 0, 1
    progress = g / number_of_generations
    Colour: "{0.3, 0.6, 0.4}"
    Paint rectangle: "{0.3, 0.6, 0.4}", 0, progress, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    # === SYNTHESIZE this generation ===
    stepStart = (g - 1) * stepDuration
    stepEnd = g * stepDuration
    
    # Build formula for active cells
    chunkFormula$ = "0"
    cellCount = 0
    maxCells = 25
    
    for i to grid_size
        for j to grid_size
            if cell[i, j] = 1 and cellCount < maxCells
                # Frequency based on position
                freq = base_frequency_Hz + ((i + j - 2) / (2 * grid_size - 2)) * frequency_range_Hz
                
                # Amplitude scaled by active count
                amp = 0.4 / sqrt(max(1, activeCount))
                
                sStart$ = fixed$(stepStart, 5)
                sEnd$ = fixed$(stepEnd, 5)
                sFreq$ = fixed$(freq, 1)
                sAmp$ = fixed$(amp, 4)
                sDur$ = fixed$(stepDuration, 5)
                
                # Hanning envelope
                cellFormula$ = " + if x >= " + sStart$ + " and x < " + sEnd$ + " then " + sAmp$ + " * sin(twoPi * " + sFreq$ + " * x) * (1 - cos(twoPi * (x - " + sStart$ + ") / " + sDur$ + ")) / 2 else 0 fi"
                chunkFormula$ = chunkFormula$ + cellFormula$
                
                cellCount = cellCount + 1
            endif
        endfor
    endfor
    
    # Apply formula
    if chunkFormula$ <> "0"
        selectObject: outputSound
        Formula: "self + (" + chunkFormula$ + ")"
    endif
    
    # --- Play this step if requested ---
    if play_during_visualization and activeCount > 0
        # Create temporary sound for this step
        stepSound = Create Sound from formula: "step_" + uid$, 1, 0, stepDuration, sample_rate_Hz, chunkFormula$
        Scale peak: 0.7
        Play
        removeObject: stepSound
    endif
    
    # === Evolve to next generation ===
    if g < number_of_generations
        # Copy current state to temp
        for i to grid_size
            for j to grid_size
                oldCell[i, j] = cell[i, j]
            endfor
        endfor
        
        # Apply Game of Life rules
        for i to grid_size
            for j to grid_size
                # Count neighbors (toroidal wrap)
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
                
                # Conway's B3/S23 rules
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
    
    # Pause for visualization
    sleep: visualization_delay
    
    appendInfoLine: "  Gen ", g, ": ", activeCount, " cells"
endfor

# === Fade in/out ===
selectObject: outputSound
Formula: "if x < 0.02 then self * (x / 0.02) else self fi"
Formula: "if x > duration_s - 0.02 then self * ((duration_s - x) / 0.02) else self fi"

# === Spatial processing ===
if spatial_mode = 2
    appendInfoLine: ""
    appendInfoLine: "Creating stereo..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Filter (pass Hann band): 0, base_frequency_Hz + frequency_range_Hz * 0.5, 100
    leftFiltered = selected("Sound")
    removeObject: leftSound
    leftSound = leftFiltered
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Filter (pass Hann band): base_frequency_Hz, base_frequency_Hz + frequency_range_Hz * 1.5, 100
    rightFiltered = selected("Sound")
    removeObject: rightSound
    rightSound = rightFiltered
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "gol_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound
else
    selectObject: outputSound
    Rename: "gol_" + preset_name$
endif

# === Normalize ===
selectObject: outputSound
Scale peak: 0.9

# === Final visualization: Spectrogram ===
appendInfoLine: ""
appendInfoLine: "=== FINAL RESULT ==="

Erase all

# Title
Select outer viewport: 0, 8, 0.3, 1.0
Select inner viewport: 0, 8, 0.3, 1.0
Axes: 0, 1, 0, 1
Font size: 14
Colour: "Black"
Text: 0.5, "centre", 0.75, "half", "Game of Life Sonification: " + preset_name$
Font size: 10
Colour: "{0.4, 0.4, 0.4}"
Text: 0.5, "centre", 0.25, "half", string$(number_of_generations) + " generations → " + fixed$(duration_s, 1) + " seconds"

# Spectrogram
Select outer viewport: 0, 8, 1.2, 5.0
Select inner viewport: 0.6, 7.4, 1.3, 4.9

if spatial_mode > 1
    selectObject: outputSound
    Extract one channel: 1
    monoSpec = selected("Sound")
else
    selectObject: outputSound
    Copy: "temp_spec"
    monoSpec = selected("Sound")
endif

selectObject: monoSpec
maxFreqSpec = base_frequency_Hz + frequency_range_Hz * 1.3
To Spectrogram: 0.03, maxFreqSpec, 0.005, 20, "Gaussian"
spec = selected("Spectrogram")
Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"

removeObject: monoSpec, spec

Select inner viewport: 0.6, 7.4, 1.3, 4.9
Axes: 0, duration_s, 0, maxFreqSpec
Colour: "White"
Marks left: 5, "yes", "yes", "no"
Marks bottom every: 1, 1, "yes", "yes", "no"
Text bottom: "yes", "Time (s)"
Text left: "yes", "Frequency (Hz)"

# Footer
Select outer viewport: 0, 8, 5.1, 5.6
Select inner viewport: 0, 8, 5.1, 5.6
Axes: 0, 1, 0, 1
Font size: 8
Colour: "{0.4, 0.4, 0.4}"
Text: 0.5, "centre", 0.5, "half", "Base: " + fixed$(base_frequency_Hz, 0) + " Hz | Range: " + fixed$(frequency_range_Hz, 0) + " Hz | Grid: " + string$(grid_size) + "×" + string$(grid_size)

# === Play final result ===
if play_final_result
    appendInfoLine: ""
    appendInfoLine: "Playing final result..."
    selectObject: outputSound
    Play
endif

# === Final selection ===
selectObject: outputSound

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  Created: ", selected$("Sound")
appendInfoLine: "=============================================="