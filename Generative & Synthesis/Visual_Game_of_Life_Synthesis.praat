# ============================================================
# Praat AudioTools - Visual_Game_of_Life_Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.1.1 (2026) - reviewed
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Conway Game of Life sonification.  The cellular state is evolved first,
#   then each live cell is mapped to a sinusoid for one generation.
#
# v1.1.1 review changes:
#   - Added runtime guards for maximum generations and stored Life states.
#
# v1.1 review changes:
#   - Exact Conway B3/S23 transition accounting: births, deaths, survivors.
#   - Exact state recurrence testing (periods 1..6) instead of population-only
#     pattern guesses.  A blinker is no longer misreported as stable.
#   - Fixed-dead boundary is the default historical/infinite-plane
#     approximation; toroidal wrapping remains optional in Edit details.
#   - Famous finite patterns are centered inside the requested grid.
#   - Corrected the LWSS preset to the canonical 9-cell, 5 x 4 phase.
#   - Random Soup supports an optional reproducible seed.
#   - Removed per-generation and per-channel normalization; one final scale
#     preserves generation-to-generation level and stereo balance.
#   - Stereo X mapping now uses constant-power panning.
#   - Diagonal-equal frequencies are aggregated before synthesis, preserving
#     the original coherent mapping while greatly reducing Formula calls.
#   - Process visualization: rule transition -> cellular/sonic score ->
#     Hann generation kernel and panning -> measured output.
#   - Compact main form; technical/animation controls moved to Edit details.
#   - Explicit Nyquist, duration, grid, and output validations.
# ============================================================

form Visual Game of Life Synthesis v1.1.1
    optionmenu Preset 1
        option Random Soup
        option Glider
        option Blinker
        option Pulsar
        option Glider Gun (Gosper)
        option R-pentomino
        option Acorn
        option Lightweight Spaceship

    integer Grid_size 24
    integer Number_of_generations 25
    positive Duration_s 5.0

    positive Base_frequency_Hz 200
    positive Frequency_range_Hz 600

    optionmenu Spatial_mode 1
        option Mono
        option Stereo constant-power X pan

    boolean Edit_details 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# ADVANCED DEFAULTS / OPTIONAL DETAILS
# ============================================================
sample_rate_Hz = 44100
output_peak = 0.9
random_fill_probability = 0.35
random_seed = 0
wrap_edges = 0
animate_evolution = 0
animation_delay_s = 0.08
audition_animation = 0

if edit_details
    beginPause: "Game of Life Synthesis v1.1.1 - Details"
        integer: "Sample rate (Hz)", sample_rate_Hz
        real: "Output peak (0..1]", output_peak
        real: "Random Soup live probability (0..1)", random_fill_probability
        integer: "Random seed (0 = unpredictable)", random_seed
        boolean: "Wrap edges (toroidal boundary)", wrap_edges
        boolean: "Animate evolution", animate_evolution
        real: "Animation delay (s)", animation_delay_s
        boolean: "Audition each animated generation", audition_animation
    endPause: "Run", 1
endif

# ============================================================
# VALIDATION / PRESET SIZE ADJUSTMENTS
# ============================================================
if grid_size < 2
    exitScript: "Grid size must be at least 2."
endif
if number_of_generations < 1
    exitScript: "Number of generations must be at least 1."
endif
if sample_rate_Hz < 2000
    exitScript: "Sample rate is too low."
endif
if output_peak <= 0 or output_peak > 1
    exitScript: "Output peak must be in (0, 1]."
endif
if random_fill_probability < 0 or random_fill_probability > 1
    exitScript: "Random Soup live probability must be in [0, 1]."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 or a positive integer."
endif
if animation_delay_s < 0
    exitScript: "Animation delay cannot be negative."
endif

preset_name$ = "Random Soup"
if preset = 2
    preset_name$ = "Glider"
    grid_size = max(grid_size, 8)
elsif preset = 3
    preset_name$ = "Blinker"
    grid_size = max(grid_size, 7)
elsif preset = 4
    preset_name$ = "Pulsar"
    grid_size = max(grid_size, 17)
elsif preset = 5
    preset_name$ = "Glider Gun"
    # The Gosper gun is 36 cells tall in the orientation used here.
    # Give it margin so the emitted glider does not immediately hit an edge.
    grid_size = max(grid_size, 52)
    number_of_generations = max(number_of_generations, 40)
elsif preset = 6
    preset_name$ = "R-pentomino"
    grid_size = max(grid_size, 9)
elsif preset = 7
    preset_name$ = "Acorn"
    grid_size = max(grid_size, 11)
elsif preset = 8
    preset_name$ = "LWSS"
    grid_size = max(grid_size, 10)
endif

# Runtime guards: this script stores every generation and later revisits the
# complete state history for recurrence testing, synthesis, and visualization.
maxGenerations = 1000
maxStoredStates = 1000000
cellsPerGrid = grid_size * grid_size
totalStoredStates = number_of_generations * cellsPerGrid

if number_of_generations > maxGenerations
    exitScript: "Requested " + string$(number_of_generations) + " generations. Maximum is " + string$(maxGenerations) + ". Reduce Number of generations."
endif
if totalStoredStates > maxStoredStates
    exitScript: "Requested state history would store " + string$(totalStoredStates) + " cells. Maximum is " + string$(maxStoredStates) + ". Reduce Grid size or Number of generations."
endif

stepDuration = duration_s / number_of_generations
if stepDuration * sample_rate_Hz < 8
    exitScript: "Each generation must contain at least 8 samples. Increase duration or sample rate, or reduce generations."
endif

nyquist = sample_rate_Hz / 2
highest_frequency = base_frequency_Hz + frequency_range_Hz
if highest_frequency >= 0.95 * nyquist
    exitScript: "Highest mapped frequency (" + fixed$(highest_frequency, 2) + " Hz) must be below 95% of Nyquist (" + fixed$(0.95 * nyquist, 2) + " Hz)."
endif

uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi
diagCount = 2 * grid_size - 1

if wrap_edges
    boundary_name$ = "Toroidal"
else
    boundary_name$ = "Fixed dead"
endif

# ============================================================
# INITIALIZE GRID
# ============================================================
for i to grid_size
    for j to grid_size
        cell[i, j] = 0
        oldCell[i, j] = 0
    endfor
endfor

# Use a reproducible RNG only for stochastic initialization.
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
endif

if preset = 1
    for i to grid_size
        for j to grid_size
            if randomUniform(0, 1) < random_fill_probability
                cell[i, j] = 1
            endif
        endfor
    endfor

elsif preset = 2
    # Glider, centered; bounding box 3 x 3.
    x0 = floor((grid_size - 3) / 2)
    y0 = floor((grid_size - 3) / 2)
    cell[x0+1, y0+2] = 1
    cell[x0+2, y0+3] = 1
    cell[x0+3, y0+1] = 1
    cell[x0+3, y0+2] = 1
    cell[x0+3, y0+3] = 1

elsif preset = 3
    # Blinker, centered.
    cx = floor((grid_size + 1) / 2)
    cy = floor((grid_size + 1) / 2)
    cell[cx, cy-1] = 1
    cell[cx, cy] = 1
    cell[cx, cy+1] = 1

elsif preset = 4
    # Pulsar, centered; original coordinates span 3..15 => 13 x 13.
    x0 = floor((grid_size - 13) / 2)
    y0 = floor((grid_size - 13) / 2)
    # Coordinates below are the original pattern minus 2.
    for .k to 3
        cell[x0+1, y0+2+.k] = 1
        cell[x0+1, y0+8+.k] = 1
        cell[x0+6, y0+2+.k] = 1
        cell[x0+6, y0+8+.k] = 1
        cell[x0+8, y0+2+.k] = 1
        cell[x0+8, y0+8+.k] = 1
        cell[x0+13, y0+2+.k] = 1
        cell[x0+13, y0+8+.k] = 1
    endfor
    for .r from 3 to 5
        cell[x0+.r, y0+1] = 1
        cell[x0+.r, y0+6] = 1
        cell[x0+.r, y0+8] = 1
        cell[x0+.r, y0+13] = 1
    endfor
    for .r from 9 to 11
        cell[x0+.r, y0+1] = 1
        cell[x0+.r, y0+6] = 1
        cell[x0+.r, y0+8] = 1
        cell[x0+.r, y0+13] = 1
    endfor

elsif preset = 5
    # Gosper glider gun, same orientation as v1.0, centered in its 9 x 36 box.
    x0 = floor((grid_size - 9) / 2)
    y0 = floor((grid_size - 36) / 2)
    cell[x0+5, y0+1] = 1
    cell[x0+5, y0+2] = 1
    cell[x0+6, y0+1] = 1
    cell[x0+6, y0+2] = 1
    cell[x0+5, y0+11] = 1
    cell[x0+6, y0+11] = 1
    cell[x0+7, y0+11] = 1
    cell[x0+4, y0+12] = 1
    cell[x0+8, y0+12] = 1
    cell[x0+3, y0+13] = 1
    cell[x0+9, y0+13] = 1
    cell[x0+3, y0+14] = 1
    cell[x0+9, y0+14] = 1
    cell[x0+6, y0+15] = 1
    cell[x0+4, y0+16] = 1
    cell[x0+8, y0+16] = 1
    cell[x0+5, y0+17] = 1
    cell[x0+6, y0+17] = 1
    cell[x0+7, y0+17] = 1
    cell[x0+6, y0+18] = 1
    cell[x0+3, y0+21] = 1
    cell[x0+4, y0+21] = 1
    cell[x0+5, y0+21] = 1
    cell[x0+3, y0+22] = 1
    cell[x0+4, y0+22] = 1
    cell[x0+5, y0+22] = 1
    cell[x0+2, y0+23] = 1
    cell[x0+6, y0+23] = 1
    cell[x0+1, y0+25] = 1
    cell[x0+2, y0+25] = 1
    cell[x0+6, y0+25] = 1
    cell[x0+7, y0+25] = 1
    cell[x0+3, y0+35] = 1
    cell[x0+3, y0+36] = 1
    cell[x0+4, y0+35] = 1
    cell[x0+4, y0+36] = 1

elsif preset = 6
    cx = floor((grid_size + 1) / 2)
    cy = floor((grid_size + 1) / 2)
    cell[cx, cy] = 1
    cell[cx+1, cy] = 1
    cell[cx-1, cy+1] = 1
    cell[cx, cy+1] = 1
    cell[cx, cy+2] = 1

elsif preset = 7
    cx = floor((grid_size + 1) / 2)
    cy = floor((grid_size + 1) / 2)
    cell[cx-3, cy] = 1
    cell[cx-2, cy] = 1
    cell[cx-2, cy-2] = 1
    cell[cx, cy-1] = 1
    cell[cx+1, cy] = 1
    cell[cx+2, cy] = 1
    cell[cx+3, cy] = 1

else
    # Canonical lightweight spaceship (LWSS), 9 cells in a 5 x 4 box.
    # RLE phase: bo2bo$o$o3bo$4o!
    x0 = floor((grid_size - 5) / 2)
    y0 = floor((grid_size - 4) / 2)
    cell[x0+2, y0+1] = 1
    cell[x0+5, y0+1] = 1
    cell[x0+1, y0+2] = 1
    cell[x0+1, y0+3] = 1
    cell[x0+5, y0+3] = 1
    cell[x0+1, y0+4] = 1
    cell[x0+2, y0+4] = 1
    cell[x0+3, y0+4] = 1
    cell[x0+4, y0+4] = 1
endif

if random_seed > 0
    random_initializeSafelyAndUnpredictably ()
endif

# ============================================================
# EVOLVE FIRST, STORE EXACT STATES AND TRANSITIONS
# ============================================================
population_history# = zero#(number_of_generations)
births_history# = zero#(number_of_generations)
deaths_history# = zero#(number_of_generations)
survivors_history# = zero#(number_of_generations)
repeat_period# = zero#(number_of_generations)
cellHistory# = zero#(number_of_generations * cellsPerGrid)

total_cells_stored = 0
max_population = 0
max_turnover = -1
snapshot_generation = 1

for g to number_of_generations
    activeCount = 0

    # Store the current board exactly.
    for i to grid_size
        for j to grid_size
            histIndex = (g - 1) * cellsPerGrid + (i - 1) * grid_size + j
            cellHistory#[histIndex] = cell[i, j]
            if cell[i, j] = 1
                activeCount = activeCount + 1
            endif
        endfor
    endfor

    population_history#[g] = activeCount
    total_cells_stored = total_cells_stored + activeCount
    if activeCount > max_population
        max_population = activeCount
    endif

    # Exact recurrence test against up to six previous boards.
    if g > 1
        maxPeriodTest = min(6, g - 1)
        for .p to maxPeriodTest
            if repeat_period#[g] = 0
                sameState = 1
                for i to grid_size
                    for j to grid_size
                        idxNow = (g - 1) * cellsPerGrid + (i - 1) * grid_size + j
                        idxOld = (g - .p - 1) * cellsPerGrid + (i - 1) * grid_size + j
                        if cellHistory#[idxNow] <> cellHistory#[idxOld]
                            sameState = 0
                        endif
                    endfor
                endfor
                if sameState
                    repeat_period#[g] = .p
                endif
            endif
        endfor
    endif

    if g < number_of_generations
        # Copy current state.
        for i to grid_size
            for j to grid_size
                oldCell[i, j] = cell[i, j]
            endfor
        endfor

        births = 0
        deaths = 0
        survivors = 0

        # Conway B3/S23 update.
        for i to grid_size
            for j to grid_size
                neighbors = 0
                for di from -1 to 1
                    for dj from -1 to 1
                        if di <> 0 or dj <> 0
                            ni = i + di
                            nj = j + dj

                            if wrap_edges
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
                            else
                                if ni >= 1 and ni <= grid_size and nj >= 1 and nj <= grid_size
                                    neighbors = neighbors + oldCell[ni, nj]
                                endif
                            endif
                        endif
                    endfor
                endfor

                newState = 0
                if oldCell[i, j] = 1
                    if neighbors = 2 or neighbors = 3
                        newState = 1
                        survivors = survivors + 1
                    else
                        deaths = deaths + 1
                    endif
                else
                    if neighbors = 3
                        newState = 1
                        births = births + 1
                    endif
                endif
                cell[i, j] = newState
            endfor
        endfor

        births_history#[g + 1] = births
        deaths_history#[g + 1] = deaths
        survivors_history#[g + 1] = survivors

        turnover = births + deaths
        if turnover > max_turnover
            max_turnover = turnover
            snapshot_generation = g + 1
        endif
    endif
endfor

if number_of_generations = 1
    snapshot_generation = 1
endif

# Summary statistics from exact transitions.
avg_population = 0
total_births = 0
total_deaths = 0
total_survivors = 0
for g to number_of_generations
    avg_population = avg_population + population_history#[g]
    total_births = total_births + births_history#[g]
    total_deaths = total_deaths + deaths_history#[g]
    total_survivors = total_survivors + survivors_history#[g]
endfor
avg_population = avg_population / number_of_generations

final_period = repeat_period#[number_of_generations]
if population_history#[number_of_generations] = 0
    final_status$ = "Extinct"
elsif final_period = 1
    final_status$ = "Exact still life"
elsif final_period > 1
    final_status$ = "Exact period-" + string$(final_period) + " recurrence"
else
    final_status$ = "Evolving / no exact period <= 6"
endif

# ============================================================
# INFO
# ============================================================
clearinfo
writeInfoLine: "=== Visual Game of Life Synthesis v1.1.1 ==="
appendInfoLine: "Pattern: ", preset_name$
appendInfoLine: "Grid / generations: ", grid_size, " x ", grid_size, " / ", number_of_generations
appendInfoLine: "Boundary: ", boundary_name$
appendInfoLine: "Rule: Conway B3/S23"
appendInfoLine: "Generation duration: ", fixed$(stepDuration, 6), " s"
appendInfoLine: "Frequency mapping: diagonal i+j -> ", fixed$(base_frequency_Hz, 2), "..", fixed$(highest_frequency, 2), " Hz"
if spatial_mode = 2
    appendInfoLine: "Spatial mapping: X position -> constant-power L/R pan"
else
    appendInfoLine: "Spatial mapping: mono"
endif
appendInfoLine: "Average / max population: ", fixed$(avg_population, 2), " / ", max_population
appendInfoLine: "Exact births / deaths / survivals: ", total_births, " / ", total_deaths, " / ", total_survivors
appendInfoLine: "Final status: ", final_status$
if random_seed > 0 and preset = 1
    appendInfoLine: "Random seed: ", random_seed, " (reproducible soup)"
endif
appendInfoLine: ""
appendInfoLine: "Synthesizing all live-cell states..."

# ============================================================
# SYNTHESIS
# Aggregate cells on the same diagonal before rendering because they share
# exactly the same frequency and local phase in the original mapping.
# ============================================================
generationSounds# = zero#(number_of_generations)
generationSoundsLeft# = zero#(number_of_generations)
generationSoundsRight# = zero#(number_of_generations)
stepDuration$ = fixed$(stepDuration, 12)

for g to number_of_generations
    activeCount = population_history#[g]
    amp = 0
    if activeCount > 0
        amp = 0.4 / sqrt(activeCount)
    endif

    if spatial_mode = 1
        diagGain# = zero#(diagCount)

        for i to grid_size
            for j to grid_size
                histIndex = (g - 1) * cellsPerGrid + (i - 1) * grid_size + j
                if cellHistory#[histIndex] = 1
                    d = i + j - 1
                    diagGain#[d] = diagGain#[d] + amp
                endif
            endfor
        endfor

        stepSound = Create Sound from formula: "gol_step_" + uid$ + "_" + string$(g), 1, 0, stepDuration, sample_rate_Hz, "0"

        chunkFormula$ = ""
        chunkTerms = 0
        for d to diagCount
            if abs(diagGain#[d]) > 0
                freq = base_frequency_Hz + ((d - 1) / (diagCount - 1)) * frequency_range_Hz
                term$ = fixed$(diagGain#[d], 12) + "*sin(2*pi*" + fixed$(freq, 8) + "*x)"
                if chunkFormula$ = ""
                    chunkFormula$ = term$
                else
                    chunkFormula$ = chunkFormula$ + " + " + term$
                endif
                chunkTerms = chunkTerms + 1

                if chunkTerms >= 18
                    selectObject: stepSound
                    Formula: "self + ((1-cos(2*pi*x/" + stepDuration$ + "))/2) * (" + chunkFormula$ + ")"
                    chunkFormula$ = ""
                    chunkTerms = 0
                endif
            endif
        endfor
        if chunkFormula$ <> ""
            selectObject: stepSound
            Formula: "self + ((1-cos(2*pi*x/" + stepDuration$ + "))/2) * (" + chunkFormula$ + ")"
        endif

        generationSounds#[g] = stepSound

    else
        diagLeft# = zero#(diagCount)
        diagRight# = zero#(diagCount)

        for i to grid_size
            pan = (i - 1) / (grid_size - 1)
            leftPan = cos(0.5 * pi * pan)
            rightPan = sin(0.5 * pi * pan)
            for j to grid_size
                histIndex = (g - 1) * cellsPerGrid + (i - 1) * grid_size + j
                if cellHistory#[histIndex] = 1
                    d = i + j - 1
                    diagLeft#[d] = diagLeft#[d] + amp * leftPan
                    diagRight#[d] = diagRight#[d] + amp * rightPan
                endif
            endfor
        endfor

        stepLeft = Create Sound from formula: "gol_L_" + uid$ + "_" + string$(g), 1, 0, stepDuration, sample_rate_Hz, "0"
        stepRight = Create Sound from formula: "gol_R_" + uid$ + "_" + string$(g), 1, 0, stepDuration, sample_rate_Hz, "0"

        leftFormula$ = ""
        rightFormula$ = ""
        chunkTerms = 0
        for d to diagCount
            if abs(diagLeft#[d]) > 0 or abs(diagRight#[d]) > 0
                freq = base_frequency_Hz + ((d - 1) / (diagCount - 1)) * frequency_range_Hz
                termL$ = fixed$(diagLeft#[d], 12) + "*sin(2*pi*" + fixed$(freq, 8) + "*x)"
                termR$ = fixed$(diagRight#[d], 12) + "*sin(2*pi*" + fixed$(freq, 8) + "*x)"
                if leftFormula$ = ""
                    leftFormula$ = termL$
                    rightFormula$ = termR$
                else
                    leftFormula$ = leftFormula$ + " + " + termL$
                    rightFormula$ = rightFormula$ + " + " + termR$
                endif
                chunkTerms = chunkTerms + 1

                if chunkTerms >= 18
                    selectObject: stepLeft
                    Formula: "self + ((1-cos(2*pi*x/" + stepDuration$ + "))/2) * (" + leftFormula$ + ")"
                    selectObject: stepRight
                    Formula: "self + ((1-cos(2*pi*x/" + stepDuration$ + "))/2) * (" + rightFormula$ + ")"
                    leftFormula$ = ""
                    rightFormula$ = ""
                    chunkTerms = 0
                endif
            endif
        endfor
        if leftFormula$ <> ""
            selectObject: stepLeft
            Formula: "self + ((1-cos(2*pi*x/" + stepDuration$ + "))/2) * (" + leftFormula$ + ")"
            selectObject: stepRight
            Formula: "self + ((1-cos(2*pi*x/" + stepDuration$ + "))/2) * (" + rightFormula$ + ")"
        endif

        generationSoundsLeft#[g] = stepLeft
        generationSoundsRight#[g] = stepRight
    endif
endfor

if spatial_mode = 1
    selectObject: generationSounds#[1]
    for g from 2 to number_of_generations
        plusObject: generationSounds#[g]
    endfor
    outputSound = Concatenate
    Rename: "gol_" + preset_name$

    for g to number_of_generations
        removeObject: generationSounds#[g]
    endfor
else
    selectObject: generationSoundsLeft#[1]
    for g from 2 to number_of_generations
        plusObject: generationSoundsLeft#[g]
    endfor
    leftSound = Concatenate
    Rename: "gol_left_" + uid$

    selectObject: generationSoundsRight#[1]
    for g from 2 to number_of_generations
        plusObject: generationSoundsRight#[g]
    endfor
    rightSound = Concatenate
    Rename: "gol_right_" + uid$

    for g to number_of_generations
        removeObject: generationSoundsLeft#[g], generationSoundsRight#[g]
    endfor

    selectObject: leftSound
    plusObject: rightSound
    outputSound = Combine to stereo
    Rename: "gol_" + preset_name$
    removeObject: leftSound, rightSound
endif

# One final common gain operation.  This preserves temporal and stereo balance.
selectObject: outputSound
preNormPeak = Get absolute extremum: 0, 0, "None"
preNormRMS = Get root-mean-square: 0, 0
if preNormPeak > 0
    Scale peak: output_peak
endif
outputSound = selected("Sound")
finalPeak = Get absolute extremum: 0, 0, "None"
finalRMS = Get root-mean-square: 0, 0

appendInfoLine: "Pre-normalization peak/RMS: ", fixed$(preNormPeak, 5), " / ", fixed$(preNormRMS, 5)
appendInfoLine: "Final peak/RMS: ", fixed$(finalPeak, 5), " / ", fixed$(finalRMS, 5)
appendInfoLine: "Total live-cell states rendered: ", total_cells_stored

# Optional animation uses the already-computed exact state history.
if animate_evolution
    for g to number_of_generations
        @drawAnimationFrame: g

        if audition_animation
            t0 = (g - 1) * stepDuration
            t1 = min(duration_s, g * stepDuration)
            selectObject: outputSound
            Extract part: t0, t1, "rectangular", 1, "no"
            previewSound = selected("Sound")
            Play
            removeObject: previewSound
        elsif animation_delay_s > 0
            sleep: animation_delay_s
        endif
    endfor
endif

if draw_visualization
    @drawVisualization
endif

if play_result
    selectObject: outputSound
    Play
endif

selectObject: outputSound
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# ==============================================================================
# Procedure: drawAnimationFrame
# ==============================================================================
procedure drawAnimationFrame: .g
    Erase all

    Select outer viewport: 0, 8, 0.05, 0.40
    Select inner viewport: 0.20, 7.80, 0.08, 0.36
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "Game of Life: " + preset_name$
    Font size: 8
    Colour: "{0.35, 0.35, 0.35}"
    Text: 0.5, "centre", 0.18, "half", "Generation " + string$(.g) + " / " + string$(number_of_generations) + " | live=" + string$(population_history#[.g]) + " | B3/S23"

    Select outer viewport: 0, 6.1, 0.50, 6.15
    Select inner viewport: 0.55, 5.85, 0.65, 5.95
    Axes: 0, grid_size, 0, grid_size
    Paint rectangle: "{0.965, 0.965, 0.965}", 0, grid_size, 0, grid_size

    for .i to grid_size
        for .j to grid_size
            .idx = (.g - 1) * cellsPerGrid + (.i - 1) * grid_size + .j
            if cellHistory#[.idx] = 1
                if .g > 1
                    .idxPrev = (.g - 2) * cellsPerGrid + (.i - 1) * grid_size + .j
                else
                    .idxPrev = .idx
                endif
                if .g > 1 and cellHistory#[.idxPrev] = 0
                    Paint rectangle: "{0.35, 0.68, 0.45}", .i-1, .i, .j-1, .j
                else
                    Paint rectangle: "{0.28, 0.43, 0.62}", .i-1, .i, .j-1, .j
                endif
            endif
        endfor
    endfor

    if grid_size <= 32
        Colour: "{0.82, 0.82, 0.82}"
        Line width: 0.5
        for .i from 0 to grid_size
            Draw line: .i, 0, .i, grid_size
            Draw line: 0, .i, grid_size, .i
        endfor
    endif
    Colour: "Black"
    Line width: 1
    Draw inner box

    Select outer viewport: 6.15, 8, 0.70, 3.05
    Select inner viewport: 6.30, 7.80, 0.85, 2.90
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.92, "half", "Transition"
    Font size: 8
    Colour: "{0.35, 0.35, 0.35}"
    Text: 0.02, "left", 0.70, "half", "Births: " + string$(births_history#[.g])
    Text: 0.02, "left", 0.53, "half", "Deaths: " + string$(deaths_history#[.g])
    Text: 0.02, "left", 0.36, "half", "Survivors: " + string$(survivors_history#[.g])
    if repeat_period#[.g] > 0
        Text: 0.02, "left", 0.16, "half", "Exact repeat: p=" + string$(repeat_period#[.g])
    else
        Text: 0.02, "left", 0.16, "half", "Exact repeat: none <= 6"
    endif

    Select outer viewport: 6.15, 8, 3.20, 5.55
    Select inner viewport: 6.30, 7.80, 3.35, 5.40
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.92, "half", "Sound map"
    Font size: 7
    Colour: "{0.35, 0.35, 0.35}"
    Text: 0.02, "left", 0.70, "half", "diag(i+j) -> frequency"
    if spatial_mode = 2
        Text: 0.02, "left", 0.52, "half", "X -> constant-power pan"
    else
        Text: 0.02, "left", 0.52, "half", "mono output"
    endif
    Text: 0.02, "left", 0.34, "half", "one Hann window / generation"
    Text: 0.02, "left", 0.16, "half", fixed$(base_frequency_Hz, 0) + ".." + fixed$(highest_frequency, 0) + " Hz"
endproc

# ==============================================================================
# Procedure: drawVisualization
# ==============================================================================
procedure drawVisualization
    Erase all

    # Every text strip gets an explicit inner viewport.  Praat Picture retains
    # viewport/axes state, so this avoids title and QC collisions.

    # ---------------- Title ----------------
    Select outer viewport: 0, 8, 0.04, 0.34
    Select inner viewport: 0.20, 7.80, 0.06, 0.31
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.50, "half", "Visual Game of Life Sonification: " + preset_name$

    # ---------------- Process strip ----------------
    Select outer viewport: 0, 8, 0.36, 0.64
    Select inner viewport: 0.22, 7.78, 0.39, 0.61
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.5, "centre", 0.50, "half", "B3/S23 update  ->  live-cell coordinates  ->  diagonal pitch + X pan  ->  Hann generation kernel  ->  sum"

    # ---------------- Panel A title ----------------
    Select outer viewport: 0, 8, 0.70, 0.91
    Select inner viewport: 0.12, 7.88, 0.72, 0.89
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.50, "half", "A  Cellular transition: exact births, survivals and deaths from an actual generation"

    # ---------------- Panel A1: transition board ----------------
    Select outer viewport: 0, 4.05, 0.94, 3.05
    Select inner viewport: 0.52, 3.78, 1.05, 2.82
    Axes: 0, grid_size, 0, grid_size
    Paint rectangle: "{0.965, 0.965, 0.965}", 0, grid_size, 0, grid_size

    .sg = snapshot_generation
    for .i to grid_size
        for .j to grid_size
            .idxNow = (.sg - 1) * cellsPerGrid + (.i - 1) * grid_size + .j
            .now = cellHistory#[.idxNow]
            .prev = 0
            if .sg > 1
                .idxPrev = (.sg - 2) * cellsPerGrid + (.i - 1) * grid_size + .j
                .prev = cellHistory#[.idxPrev]
            endif

            if .now = 1 and .prev = 0
                Paint rectangle: "{0.30, 0.68, 0.42}", .i-1, .i, .j-1, .j
            elsif .now = 1 and .prev = 1
                Paint rectangle: "{0.32, 0.46, 0.64}", .i-1, .i, .j-1, .j
            elsif .now = 0 and .prev = 1
                Colour: "{0.78, 0.32, 0.28}"
                Draw line: .i-0.82, .j-0.82, .i-0.18, .j-0.18
                Draw line: .i-0.82, .j-0.18, .i-0.18, .j-0.82
            endif
        endfor
    endfor

    if grid_size <= 28
        Colour: "{0.84, 0.84, 0.84}"
        Line width: 0.5
        for .i from 0 to grid_size
            Draw line: .i, 0, .i, grid_size
            Draw line: 0, .i, grid_size, .i
        endfor
    endif
    Colour: "Black"
    Line width: 1
    Draw inner box

    # Board title / legend in its own strip.
    Select outer viewport: 0, 4.05, 2.84, 3.07
    Select inner viewport: 0.52, 3.78, 2.86, 3.04
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.50, "half", "Gen " + string$(.sg) + ": green=birth  blue=survivor  red X=death"

    # ---------------- Panel A2: population / turnover ----------------
    Select outer viewport: 4.05, 8, 0.94, 3.05
    Select inner viewport: 4.52, 7.68, 1.08, 2.78
    .maxMetric = max_population
    for .g to number_of_generations
        .maxMetric = max(.maxMetric, births_history#[.g])
        .maxMetric = max(.maxMetric, deaths_history#[.g])
    endfor
    .maxMetric = max(1, .maxMetric)
    Axes: 1, max(2, number_of_generations), 0, 1.10 * .maxMetric
    Paint rectangle: "{0.965, 0.965, 0.965}", 1, max(2, number_of_generations), 0, 1.10 * .maxMetric

    # Birth/death stems behind the population curve.
    for .g from 2 to number_of_generations
        if births_history#[.g] > 0
            Colour: "{0.30, 0.68, 0.42}"
            Draw line: .g - 0.10, 0, .g - 0.10, births_history#[.g]
        endif
        if deaths_history#[.g] > 0
            Colour: "{0.78, 0.32, 0.28}"
            Draw line: .g + 0.10, 0, .g + 0.10, deaths_history#[.g]
        endif
    endfor

    Colour: "{0.20, 0.25, 0.30}"
    Line width: 2
    for .g from 1 to number_of_generations - 1
        Draw line: .g, population_history#[.g], .g + 1, population_history#[.g + 1]
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Select inner viewport: 4.52, 7.68, 1.08, 2.78
    Axes: 1, max(2, number_of_generations), 0, 1.10 * .maxMetric
    Marks bottom every: 1, max(1, floor(number_of_generations / 5)), "yes", "yes", "no"
    Marks left every: 1, max(1, floor(.maxMetric / 4)), "yes", "yes", "no"
    Font size: 7
    Text bottom: "yes", "Generation"
    Text left: "yes", "Count"

    Select outer viewport: 4.05, 8, 2.84, 3.07
    Select inner viewport: 4.52, 7.68, 2.86, 3.04
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.50, "half", "black=population   green=births   red=deaths"

    # ---------------- Panel B title ----------------
    Select outer viewport: 0, 8, 3.12, 3.34
    Select inner viewport: 0.12, 7.88, 3.14, 3.31
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.50, "half", "B  Life-to-sound score: live cells become diagonal-frequency partials for one generation"

    # ---------------- Panel B: sonification score ----------------
    Select outer viewport: 0, 8, 3.37, 5.15
    Select inner viewport: 0.72, 7.62, 3.48, 4.94
    Axes: 0, duration_s, base_frequency_Hz, highest_frequency
    Paint rectangle: "{0.965, 0.965, 0.965}", 0, duration_s, base_frequency_Hz, highest_frequency

    for .g to number_of_generations
        .t0 = (.g - 1) * stepDuration
        .t1 = min(duration_s, .g * stepDuration)
        .diagCountLive# = zero#(diagCount)
        .diagBirth# = zero#(diagCount)

        for .i to grid_size
            for .j to grid_size
                .idx = (.g - 1) * cellsPerGrid + (.i - 1) * grid_size + .j
                if cellHistory#[.idx] = 1
                    .d = .i + .j - 1
                    .diagCountLive#[.d] = .diagCountLive#[.d] + 1
                    if .g > 1
                        .idxP = (.g - 2) * cellsPerGrid + (.i - 1) * grid_size + .j
                        if cellHistory#[.idxP] = 0
                            .diagBirth#[.d] = .diagBirth#[.d] + 1
                        endif
                    endif
                endif
            endfor
        endfor

        for .d to diagCount
            if .diagCountLive#[.d] > 0
                .f = base_frequency_Hz + ((.d - 1) / (diagCount - 1)) * frequency_range_Hz
                .lw = min(4, 0.8 + 0.38 * .diagCountLive#[.d])
                Colour: "{0.28, 0.42, 0.60}"
                Line width: .lw
                Draw line: .t0, .f, .t1, .f
                if .diagBirth#[.d] > 0
                    Colour: "{0.30, 0.68, 0.42}"
                    Paint circle (mm): "{0.30, 0.68, 0.42}", .t0 + 0.08 * stepDuration, .f, min(1.8, 0.9 + 0.15 * .diagBirth#[.d])
                endif
            endif
        endfor
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.72, 7.62, 3.48, 4.94
    Axes: 0, duration_s, base_frequency_Hz, highest_frequency
    Marks bottom every: 1, max(duration_s / 5, stepDuration), "yes", "yes", "no"
    Marks left every: 1, max(1, frequency_range_Hz / 4), "yes", "yes", "no"
    Font size: 7
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Frequency (Hz)"

    Select outer viewport: 0, 8, 4.96, 5.18
    Select inner viewport: 0.72, 7.62, 4.98, 5.15
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.32, 0.32, 0.32}"
    Text: 0.02, "left", 0.50, "half", "line thickness = cells sharing that diagonal/frequency; green onset mark = at least one newly born cell"

    # ---------------- Panel C title ----------------
    Select outer viewport: 0, 8, 5.24, 5.45
    Select inner viewport: 0.12, 7.88, 5.26, 5.42
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.50, "half", "C  Audio mapping: one Hann generation kernel; X position controls stereo power"

    # ---------------- Panel C1: Hann kernel ----------------
    Select outer viewport: 0, 4, 5.48, 6.66
    Select inner viewport: 0.70, 3.65, 5.58, 6.45
    Axes: 0, stepDuration, 0, 1.05
    Paint rectangle: "{0.965, 0.965, 0.965}", 0, stepDuration, 0, 1.05
    Colour: "{0.22, 0.46, 0.68}"
    Line width: 2
    .prevX = 0
    .prevY = 0
    for .k from 1 to 120
        .x = (.k / 120) * stepDuration
        .y = (1 - cos(twoPi * .x / stepDuration)) / 2
        Draw line: .prevX, .prevY, .x, .y
        .prevX = .x
        .prevY = .y
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.70, 3.65, 5.58, 6.45
    Axes: 0, stepDuration, 0, 1.05
    Font size: 7
    Text bottom: "yes", "Local generation time"
    Text left: "yes", "w(t)"

    Select outer viewport: 0, 4, 6.44, 6.69
    Select inner viewport: 0.70, 3.65, 6.46, 6.66
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.5, "centre", 0.50, "half", "w(t) = [1 - cos(2*pi*t/Tgen)] / 2"

    # ---------------- Panel C2: panning / mono ----------------
    Select outer viewport: 4, 8, 5.48, 6.66
    Select inner viewport: 4.45, 7.65, 5.58, 6.45
    Axes: 0, 1, 0, 1.05
    Paint rectangle: "{0.965, 0.965, 0.965}", 0, 1, 0, 1.05

    if spatial_mode = 2
        .px0 = 0
        .l0 = 1
        .r0 = 0
        for .k from 1 to 100
            .p = .k / 100
            .lg = cos(0.5 * pi * .p)
            .rg = sin(0.5 * pi * .p)
            Colour: "{0.25, 0.45, 0.72}"
            Draw line: .px0, .l0, .p, .lg
            Colour: "{0.74, 0.38, 0.26}"
            Draw line: .px0, .r0, .p, .rg
            .px0 = .p
            .l0 = .lg
            .r0 = .rg
        endfor
        Colour: "{0.68, 0.68, 0.68}"
        Dotted line
        Draw line: 0, sqrt(0.5), 1, sqrt(0.5)
        Solid line
    else
        Colour: "{0.35, 0.35, 0.35}"
        Line width: 2
        Draw line: 0, 1, 1, 1
        Line width: 1
    endif
    Colour: "Black"
    Draw inner box
    Select inner viewport: 4.45, 7.65, 5.58, 6.45
    Axes: 0, 1, 0, 1.05
    Font size: 7
    Text bottom: "yes", "Normalized X position"
    Text left: "yes", "Gain"

    Select outer viewport: 4, 8, 6.44, 6.69
    Select inner viewport: 4.45, 7.65, 6.46, 6.66
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    if spatial_mode = 2
        Text: 0.5, "centre", 0.50, "half", "L=cos(pi*p/2), R=sin(pi*p/2); L^2+R^2=1"
    else
        Text: 0.5, "centre", 0.50, "half", "Mono: X position does not alter output gain"
    endif

    # ---------------- Panel D title ----------------
    Select outer viewport: 0, 8, 6.74, 6.95
    Select inner viewport: 0.12, 7.88, 6.76, 6.92
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.50, "half", "D  Measured output"

    # ---------------- Panel D: output waveform ----------------
    .yr = max(1, 1.08 * finalPeak)
    if spatial_mode = 1
        Select outer viewport: 0, 8, 6.98, 7.88
        Select inner viewport: 0.72, 7.62, 7.07, 7.68
        Axes: 0, duration_s, -.yr, .yr
        Paint rectangle: "{0.965, 0.965, 0.965}", 0, duration_s, -.yr, .yr
        selectObject: outputSound
        Colour: "{0.20, 0.35, 0.52}"
        Draw: 0, duration_s, -.yr, .yr, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Select inner viewport: 0.72, 7.62, 7.07, 7.68
        Axes: 0, duration_s, -.yr, .yr
        Font size: 7
        Text bottom: "yes", "Time (s)"
        Text left: "yes", "Amplitude"
    else
        selectObject: outputSound
        Extract one channel: 1
        .left = selected("Sound")
        selectObject: outputSound
        Extract one channel: 2
        .right = selected("Sound")

        Select outer viewport: 0, 8, 6.98, 7.43
        Select inner viewport: 0.72, 7.62, 7.04, 7.31
        Axes: 0, duration_s, -.yr, .yr
        Paint rectangle: "{0.965, 0.965, 0.965}", 0, duration_s, -.yr, .yr
        selectObject: .left
        Colour: "{0.25, 0.45, 0.72}"
        Draw: 0, duration_s, -.yr, .yr, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Select inner viewport: 0.72, 7.62, 7.04, 7.31
        Axes: 0, duration_s, -.yr, .yr
        Font size: 7
        Text left: "yes", "L"

        Select outer viewport: 0, 8, 7.44, 7.88
        Select inner viewport: 0.72, 7.62, 7.50, 7.76
        Axes: 0, duration_s, -.yr, .yr
        Paint rectangle: "{0.965, 0.965, 0.965}", 0, duration_s, -.yr, .yr
        selectObject: .right
        Colour: "{0.74, 0.38, 0.26}"
        Draw: 0, duration_s, -.yr, .yr, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Select inner viewport: 0.72, 7.62, 7.50, 7.76
        Axes: 0, duration_s, -.yr, .yr
        Font size: 7
        Text left: "yes", "R"
        Text bottom: "yes", "Time (s)"

        removeObject: .left, .right
    endif

    # ---------------- QC strip: two rows x three fields ----------------
    Select outer viewport: 0, 8, 7.94, 8.54
    Select inner viewport: 0.20, 7.80, 7.98, 8.50
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    Font size: 6.5
    Colour: "{0.24, 0.24, 0.24}"

    Text: 0.02, "left", 0.70, "half", "Grid: " + string$(grid_size) + "x" + string$(grid_size) + " | " + boundary_name$
    Text: 0.35, "left", 0.70, "half", "Population avg/max: " + fixed$(avg_population, 1) + "/" + string$(max_population)
    Text: 0.69, "left", 0.70, "half", "Births/deaths: " + string$(total_births) + "/" + string$(total_deaths)

    Text: 0.02, "left", 0.25, "half", "Pitch: " + fixed$(base_frequency_Hz, 0) + ".." + fixed$(highest_frequency, 0) + " Hz"
    Text: 0.35, "left", 0.25, "half", "Final: " + final_status$
    Text: 0.69, "left", 0.25, "half", "Peak/RMS: " + fixed$(finalPeak, 3) + "/" + fixed$(finalRMS, 3)
endproc
