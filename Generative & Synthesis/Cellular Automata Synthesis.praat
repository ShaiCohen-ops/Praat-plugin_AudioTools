# ============================================================
# Praat AudioTools - Cellular Automata Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Corrected
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Sonification of cellular automata:
#   - Elementary CA (1D Wolfram rules)
#   - Conway's Game of Life (2D)
#   - Brian's Brain (2D, 3-state)
#
# Usage:
#   Run this script (no input sound required).
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.2:
#   - Fixed rule bit extraction
#   - Added envelopes to all tones (no clicks)
#   - Added CA grid visualization
#   - Added spatial modes
#   - Modern syntax throughout
#   - Optimized 2D CA processing
# ============================================================

form Cellular Automata Synthesis
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Rule 30 Classic
        option Rule 110 Complex
        option Rule 90 Symmetric
        option Rule 184 Traffic
        option Game of Life
        option Brian's Brain
    
    comment === Basic Settings ===
    positive Duration_s 8.0
    integer Sample_rate_Hz 44100
    integer Grid_size 32
    
    comment === CA Type ===
    optionmenu Rule_type 1
        option Elementary CA (1D)
        option Game of Life (2D)
        option Brian's Brain (2D)
    integer Rule_number 30
    
    comment === Sound Mapping ===
    positive Segment_duration_s 0.1
    positive Base_frequency_Hz 150
    positive Frequency_spread_Hz 200
    
    comment === Output ===
    optionmenu Spatial_mode 1
        option Mono
        option Stereo Wide
        option Rotating
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
preset_name$ = "Custom"

if preset = 2
    # Rule 30 Classic (chaotic, good PRNG)
    duration_s = 8.0
    grid_size = 32
    rule_type = 1
    rule_number = 30
    segment_duration_s = 0.1
    base_frequency_Hz = 150
    frequency_spread_Hz = 200
    preset_name$ = "Rule30"
elsif preset = 3
    # Rule 110 Complex (Turing complete)
    duration_s = 10.0
    grid_size = 40
    rule_type = 1
    rule_number = 110
    segment_duration_s = 0.08
    base_frequency_Hz = 120
    frequency_spread_Hz = 250
    preset_name$ = "Rule110"
elsif preset = 4
    # Rule 90 Symmetric (Sierpinski triangle)
    duration_s = 8.0
    grid_size = 32
    rule_type = 1
    rule_number = 90
    segment_duration_s = 0.1
    base_frequency_Hz = 180
    frequency_spread_Hz = 180
    preset_name$ = "Rule90"
elsif preset = 5
    # Rule 184 Traffic
    duration_s = 8.0
    grid_size = 32
    rule_type = 1
    rule_number = 184
    segment_duration_s = 0.1
    base_frequency_Hz = 200
    frequency_spread_Hz = 150
    preset_name$ = "Rule184"
elsif preset = 6
    # Game of Life
    duration_s = 12.0
    grid_size = 16
    rule_type = 2
    rule_number = 0
    segment_duration_s = 0.15
    base_frequency_Hz = 100
    frequency_spread_Hz = 300
    spatial_mode = 2
    preset_name$ = "GameOfLife"
elsif preset = 7
    # Brian's Brain
    duration_s = 10.0
    grid_size = 16
    rule_type = 3
    rule_number = 0
    segment_duration_s = 0.12
    base_frequency_Hz = 130
    frequency_spread_Hz = 200
    spatial_mode = 3
    preset_name$ = "BrianBrain"
endif

# === Validation ===
if grid_size > 64
    grid_size = 64
endif
if grid_size < 8
    grid_size = 8
endif
# Reduce grid for 2D CAs to prevent explosion
if rule_type > 1 and grid_size > 20
    grid_size = 20
endif

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi
totalSegments = floor(duration_s / segment_duration_s)

# === Info ===
writeInfoLine: "=== Cellular Automata Synthesis ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Grid size: ", grid_size
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "Segments: ", totalSegments
if rule_type = 1
    appendInfoLine: "Rule: ", rule_number, " (Elementary CA)"
elsif rule_type = 2
    appendInfoLine: "Type: Game of Life"
else
    appendInfoLine: "Type: Brian's Brain"
endif
appendInfoLine: ""

# === Initialize CA state arrays ===
# For Elementary CA: ca[segment, cell]
# For 2D CAs: ca[i, j] (current state) and history stored per segment

if rule_type = 1
    # Elementary CA - 1D, store all generations
    for seg to totalSegments
        for cell to grid_size
            ca_state[seg, cell] = 0
        endfor
    endfor
    # Seed: single cell in center
    ca_state[1, floor(grid_size / 2)] = 1
else
    # 2D CA - current state
    for i to grid_size
        for j to grid_size
            ca_current[i, j] = 0
            ca_next[i, j] = 0
        endfor
    endfor
endif

# === Initialize 2D CAs with random state ===
if rule_type = 2
    # Game of Life - 30% density
    for i to grid_size
        for j to grid_size
            if randomUniform(0, 1) < 0.3
                ca_current[i, j] = 1
            endif
        endfor
    endfor
elsif rule_type = 3
    # Brian's Brain - mixed states
    for i to grid_size
        for j to grid_size
            r = randomUniform(0, 1)
            if r < 0.2
                ca_current[i, j] = 1
            elsif r < 0.35
                ca_current[i, j] = 2
            endif
        endfor
    endfor
endif

# === Evolve Elementary CA (all at once) ===
if rule_type = 1
    appendInfoLine: "Evolving Elementary CA..."
    for seg from 1 to totalSegments - 1
        for cell to grid_size
            # Get neighborhood
            if cell > 1
                left = ca_state[seg, cell - 1]
            else
                left = 0
            endif
            center = ca_state[seg, cell]
            if cell < grid_size
                right = ca_state[seg, cell + 1]
            else
                right = 0
            endif
            
            # Pattern index (0-7)
            pattern = 4 * left + 2 * center + right
            
            # Extract bit from rule number (FIXED)
            rule_bit = floor(rule_number / (2 ^ pattern)) mod 2
            
            ca_state[seg + 1, cell] = rule_bit
        endfor
    endfor
endif

# === Create output sound ===
outputSound = Create Sound from formula: "ca_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

# === Synthesize audio from CA ===
appendInfoLine: "Synthesizing audio..."

if rule_type = 1
    # === Elementary CA: efficient segment-based synthesis ===
    for seg to totalSegments
        segmentStart = (seg - 1) * segment_duration_s
        
        # Count active cells and build single formula per segment
        activeCells = 0
        for cell to grid_size
            if ca_state[seg, cell] = 1
                activeCells = activeCells + 1
            endif
        endfor
        
        if activeCells > 0
            # Build formula for this segment
            segFormula$ = "0"
            
            for cell to grid_size
                if ca_state[seg, cell] = 1
                    freq = base_frequency_Hz + (cell / grid_size) * frequency_spread_Hz
                    amp = 0.6 / sqrt(grid_size)
                    
                    freq$ = fixed$(freq, 2)
                    amp$ = fixed$(amp, 6)
                    segStart$ = fixed$(segmentStart, 6)
                    segEnd$ = fixed$(segmentStart + segment_duration_s, 6)
                    segDur$ = fixed$(segment_duration_s, 6)
                    
                    # Hanning envelope
                    segFormula$ = segFormula$ + " + if x >= " + segStart$ + " and x < " + segEnd$ + " then " + amp$ + " * sin(twoPi * " + freq$ + " * x) * (1 - cos(twoPi * (x - " + segStart$ + ") / " + segDur$ + ")) / 2 else 0 fi"
                endif
            endfor
            
            selectObject: outputSound
            Formula: "self + (" + segFormula$ + ")"
        endif
        
        # Progress
        if seg mod 10 = 0
            appendInfoLine: "  Segment ", seg, "/", totalSegments
        endif
    endfor

else
    # === 2D CAs: evolve and synthesize per segment ===
    for seg to totalSegments
        segmentStart = (seg - 1) * segment_duration_s
        
        # Count active cells
        activeCells = 0
        for i to grid_size
            for j to grid_size
                if ca_current[i, j] = 1
                    activeCells = activeCells + 1
                endif
            endfor
        endfor
        
        # Store for visualization (only first 64 segments)
        if seg <= 64
            ca_history_count[seg] = activeCells
        endif
        
        if activeCells > 0
            # Build formula for active cells
            segFormula$ = "0"
            cellCount = 0
            
            for i to grid_size
                for j to grid_size
                    if ca_current[i, j] = 1
                        cellCount = cellCount + 1
                        
                        # Map position to frequency
                        if rule_type = 2
                            # Game of Life: 2D frequency mapping
                            freq = base_frequency_Hz + ((i + j) / (2 * grid_size)) * frequency_spread_Hz
                        else
                            # Brian's Brain
                            freq = base_frequency_Hz + ((i * grid_size + j) / (grid_size * grid_size)) * frequency_spread_Hz
                        endif
                        
                        amp = 0.5 / max(10, sqrt(activeCells))
                        
                        freq$ = fixed$(freq, 2)
                        amp$ = fixed$(amp, 6)
                        segStart$ = fixed$(segmentStart, 6)
                        segEnd$ = fixed$(segmentStart + segment_duration_s, 6)
                        segDur$ = fixed$(segment_duration_s, 6)
                        
                        segFormula$ = segFormula$ + " + if x >= " + segStart$ + " and x < " + segEnd$ + " then " + amp$ + " * sin(twoPi * " + freq$ + " * x) * (1 - cos(twoPi * (x - " + segStart$ + ") / " + segDur$ + ")) / 2 else 0 fi"
                        
                        # Limit formula size
                        if cellCount >= 50
                            # Apply partial formula
                            selectObject: outputSound
                            Formula: "self + (" + segFormula$ + ")"
                            segFormula$ = "0"
                            cellCount = 0
                        endif
                    endif
                endfor
            endfor
            
            # Apply remaining formula
            if segFormula$ <> "0"
                selectObject: outputSound
                Formula: "self + (" + segFormula$ + ")"
            endif
        endif
        
        # Evolve to next generation
        if seg < totalSegments
            if rule_type = 2
                @evolveGameOfLife
            else
                @evolveBrianBrain
            endif
        endif
        
        # Progress
        if seg mod 10 = 0
            appendInfoLine: "  Segment ", seg, "/", totalSegments, " (", activeCells, " cells)"
        endif
    endfor
endif

# === Apply fade ===
selectObject: outputSound
Formula: "if x < 0.02 then self * (x / 0.02) else self fi"
Formula: "if x > duration_s - 0.02 then self * ((duration_s - x) / 0.02) else self fi"

# === Spatial Processing ===
if spatial_mode = 2
    appendInfoLine: "Creating stereo width..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Filter (pass Hann band): 0, 3000, 100
    leftFiltered = selected("Sound")
    removeObject: leftSound
    leftSound = leftFiltered
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Filter (pass Hann band): 150, 8000, 100
    rightFiltered = selected("Sound")
    removeObject: rightSound
    rightSound = rightFiltered
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "ca_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound
    
elsif spatial_mode = 3
    appendInfoLine: "Creating rotating stereo..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * (0.6 + 0.4 * cos(twoPi * 0.15 * x))"
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * (0.6 + 0.4 * sin(twoPi * 0.15 * x))"
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "ca_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound
else
    selectObject: outputSound
    Rename: "ca_" + preset_name$
endif

# === Normalize ===
if normalize_output
    selectObject: outputSound
    Scale peak: 0.9
endif

# === Visualization ===
if draw_visualization
    appendInfoLine: "Drawing visualization..."
    @drawCAVisualization
endif

# === Play ===
if play_result
    selectObject: outputSound
    Play
endif

# === Final Selection ===
selectObject: outputSound

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# ==============================================================================
# Procedure: evolveGameOfLife
# ==============================================================================
procedure evolveGameOfLife
    # Apply Conway's rules: B3/S23
    for .i to grid_size
        for .j to grid_size
            .neighbors = 0
            
            # Count live neighbors
            for .di from -1 to 1
                for .dj from -1 to 1
                    if .di <> 0 or .dj <> 0
                        .ni = .i + .di
                        .nj = .j + .dj
                        if .ni >= 1 and .ni <= grid_size and .nj >= 1 and .nj <= grid_size
                            .neighbors = .neighbors + ca_current[.ni, .nj]
                        endif
                    endif
                endfor
            endfor
            
            # Apply rules
            if ca_current[.i, .j] = 1
                # Survival: 2 or 3 neighbors
                if .neighbors = 2 or .neighbors = 3
                    ca_next[.i, .j] = 1
                else
                    ca_next[.i, .j] = 0
                endif
            else
                # Birth: exactly 3 neighbors
                if .neighbors = 3
                    ca_next[.i, .j] = 1
                else
                    ca_next[.i, .j] = 0
                endif
            endif
        endfor
    endfor
    
    # Copy next to current
    for .i to grid_size
        for .j to grid_size
            ca_current[.i, .j] = ca_next[.i, .j]
        endfor
    endfor
endproc

# ==============================================================================
# Procedure: evolveBrianBrain
# ==============================================================================
procedure evolveBrianBrain
    # States: 0=dead, 1=firing, 2=refractory
    for .i to grid_size
        for .j to grid_size
            if ca_current[.i, .j] = 0
                # Dead cell: fires if exactly 2 firing neighbors
                .neighbors = 0
                for .di from -1 to 1
                    for .dj from -1 to 1
                        if .di <> 0 or .dj <> 0
                            .ni = .i + .di
                            .nj = .j + .dj
                            if .ni >= 1 and .ni <= grid_size and .nj >= 1 and .nj <= grid_size
                                if ca_current[.ni, .nj] = 1
                                    .neighbors = .neighbors + 1
                                endif
                            endif
                        endif
                    endfor
                endfor
                
                if .neighbors = 2
                    ca_next[.i, .j] = 1
                else
                    ca_next[.i, .j] = 0
                endif
            elsif ca_current[.i, .j] = 1
                # Firing -> refractory
                ca_next[.i, .j] = 2
            else
                # Refractory -> dead
                ca_next[.i, .j] = 0
            endif
        endfor
    endfor
    
    # Copy next to current
    for .i to grid_size
        for .j to grid_size
            ca_current[.i, .j] = ca_next[.i, .j]
        endfor
    endfor
endproc

# ==============================================================================
# Procedure: drawCAVisualization
# ==============================================================================
procedure drawCAVisualization
    
    Erase all
    
    .leftMargin = 0.6
    .rightMargin = 6.5
    
    # === Title ===
    Select outer viewport: 0, 7, 0, 0.5
    Font size: 12
    Colour: "Black"
    if rule_type = 1
        Text top: "no", "Cellular Automata: Rule " + string$(rule_number)
    elsif rule_type = 2
        Text top: "no", "Cellular Automata: Game of Life"
    else
        Text top: "no", "Cellular Automata: Brian's Brain"
    endif
    
    # === CA Grid (for Elementary CA) ===
    if rule_type = 1
        Select outer viewport: 0, 7, 0.6, 3.0
        Colour: "{0.9, 0.9, 0.9}"
        Draw inner box
        
        Select inner viewport: .leftMargin, .rightMargin, 0.7, 2.9
        
        # Draw CA grid as image
        .displaySegs = min(totalSegments, 80)
        Axes: 0, grid_size, .displaySegs, 0
        
        for .seg to .displaySegs
            for .cell to grid_size
                if ca_state[.seg, .cell] = 1
                    Paint rectangle: "Black", .cell - 1, .cell, .seg - 1, .seg
                endif
            endfor
        endfor
        
        Select outer viewport: 0, .leftMargin, 0.6, 3.0
        Colour: "Black"
        Font size: 9
        Text: 0.5, "centre", 0.5, "half", "Time"
        
        Select inner viewport: .leftMargin, .rightMargin, 0.7, 2.9
        Axes: 0, grid_size, .displaySegs, 0
        Colour: "Black"
        Text bottom: "yes", "Cell Position"
    endif
    
    # === Spectrogram ===
    if rule_type = 1
        Select outer viewport: 0, 7, 3.1, 5.5
    else
        Select outer viewport: 0, 7, 0.6, 4.5
    endif
    Colour: "{0.85, 0.85, 0.85}"
    Draw inner box
    
    if rule_type = 1
        Select inner viewport: .leftMargin, .rightMargin, 3.2, 5.4
    else
        Select inner viewport: .leftMargin, .rightMargin, 0.7, 4.4
    endif
    
    # Get mono for spectrogram
    if spatial_mode > 1
        selectObject: outputSound
        Extract one channel: 1
        .monoForSpec = selected("Sound")
    else
        selectObject: outputSound
        Copy: "temp_for_spec"
        .monoForSpec = selected("Sound")
    endif
    
    selectObject: .monoForSpec
    .maxFreqSpec = min(4000, base_frequency_Hz + frequency_spread_Hz * 1.5)
    
    To Spectrogram: 0.03, .maxFreqSpec, 0.005, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    
    removeObject: .monoForSpec, .spec
    
    # Axis labels
    if rule_type = 1
        Select outer viewport: 0, .leftMargin, 3.1, 5.5
    else
        Select outer viewport: 0, .leftMargin, 0.6, 4.5
    endif
    Colour: "Black"
    Font size: 9
    Text: 0.5, "centre", 0.5, "half", "Hz"
    
    if rule_type = 1
        Select inner viewport: .leftMargin, .rightMargin, 3.2, 5.4
    else
        Select inner viewport: .leftMargin, .rightMargin, 0.7, 4.4
    endif
    Axes: 0, duration_s, 0, .maxFreqSpec
    Colour: "White"
    Marks left: 4, "yes", "yes", "no"
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    
    # === Footer ===
    if rule_type = 1
        Select outer viewport: 0, 7, 5.6, 6.0
    else
        Select outer viewport: 0, 7, 4.6, 5.0
    endif
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    .paramText$ = "Grid: " + string$(grid_size) + " | Segment: " + fixed$(segment_duration_s * 1000, 0) + " ms | Base: " + fixed$(base_frequency_Hz, 0) + " Hz"
    Text top: "no", .paramText$
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc