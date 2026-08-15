# ============================================================
# Praat AudioTools - Cellular Automata Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.1 reviewed (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Sonification of cellular automata:
#   - Elementary CA (1D Wolfram rules 0..255)
#   - Conway's Game of Life (2D, B3/S23)
#   - Brian's Brain (2D, 3-state)
#
#   Each CA generation is mapped to a short additive sound state. Active
#   cells become oscillators whose frequencies are determined by cell
#   position. A short edge taper prevents clicks while avoiding the strong
#   full-Hann pumping of earlier versions.
#
# v0.4.1 reviewed:
#   - Fix: allocate ca_history# before storing 2D CA generations.
#   - No DSP or preset changes.
#
# v0.4 reviewed:
#   - Exact output duration via ceiling() generation count and a shortened
#     final generation; no trailing silent remainder for non-integer ratios.
#   - Frequency mapping corrected to span exactly Base..Base+Spread.
#   - Brian's Brain mapping no longer exceeds the requested frequency range.
#   - Nyquist-safe effective frequency spread derived from Sample_rate_Hz.
#   - Per-generation oscillator energy compensation uses 1/sqrt(N_active).
#   - Deterministic per-cell phase offsets reduce coherent pile-up when
#     multiple 2D cells project to nearby frequencies.
#   - Segment synthesis is local (short Sound per generation) instead of
#     repeatedly scanning the complete output Sound; substantially faster.
#   - Short 5 ms raised-cosine edge tapers replace full-segment Hann windows.
#   - Added Elementary initial-condition and boundary-mode controls.
#   - Rule 184 Traffic preset now uses random traffic + wrap boundaries;
#     a single seed on fixed boundaries simply leaves the finite grid.
#   - 2D presets use wrap boundaries to reduce artificial edge extinction.
#   - Brian's Brain preset uses a more sustainable 20x20 mixed-state seed.
#   - Added Random_seed (0 = unpredictable; positive = reproducible).
#   - RNG is restored to an unpredictable state after initialization.
#   - Stereo Wide now uses short decorrelation instead of spectral splitting.
#   - Rotating stereo is equal-power.
#   - Final normalization is guarded against all-silent output.
#   - Visualization rebuilt around the actual CA and actual sound mapping:
#       A) full 1D evolution or three true 2D snapshots,
#       B) actual active/firing density trajectory,
#       C) measured spectrogram + realized frequency centroid/range,
#       D) rule/mechanism diagram + compact QC.
# ============================================================

form Cellular Automata Synthesis v0.4
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

    comment === Finite-grid behavior ===
    optionmenu Boundary_mode 1
        option Fixed / zero outside
        option Wrap / toroidal
    optionmenu Elementary_initial_condition 1
        option Single centre cell
        option Random traffic (35 percent)
        option Alternating 1010
        option Random sparse (10 percent)
    integer Random_seed 0

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

# ===========================================================================
# 0. PRESETS
# ===========================================================================
preset_name$ = "Custom"

if preset = 2
    duration_s = 8.0
    grid_size = 32
    rule_type = 1
    rule_number = 30
    boundary_mode = 1
    elementary_initial_condition = 1
    segment_duration_s = 0.10
    base_frequency_Hz = 150
    frequency_spread_Hz = 200
    preset_name$ = "Rule30"

elsif preset = 3
    duration_s = 10.0
    grid_size = 40
    rule_type = 1
    rule_number = 110
    boundary_mode = 1
    elementary_initial_condition = 1
    segment_duration_s = 0.08
    base_frequency_Hz = 120
    frequency_spread_Hz = 250
    preset_name$ = "Rule110"

elsif preset = 4
    duration_s = 8.0
    grid_size = 32
    rule_type = 1
    rule_number = 90
    boundary_mode = 1
    elementary_initial_condition = 1
    segment_duration_s = 0.10
    base_frequency_Hz = 180
    frequency_spread_Hz = 180
    preset_name$ = "Rule90"

elsif preset = 5
    duration_s = 8.0
    grid_size = 32
    rule_type = 1
    rule_number = 184
    boundary_mode = 2
    elementary_initial_condition = 2
    segment_duration_s = 0.10
    base_frequency_Hz = 200
    frequency_spread_Hz = 150
    preset_name$ = "Rule184Traffic"

elsif preset = 6
    duration_s = 12.0
    grid_size = 18
    rule_type = 2
    rule_number = 0
    boundary_mode = 2
    segment_duration_s = 0.15
    base_frequency_Hz = 100
    frequency_spread_Hz = 300
    spatial_mode = 2
    preset_name$ = "GameOfLife"

elsif preset = 7
    duration_s = 10.0
    grid_size = 20
    rule_type = 3
    rule_number = 0
    boundary_mode = 2
    segment_duration_s = 0.12
    base_frequency_Hz = 130
    frequency_spread_Hz = 200
    spatial_mode = 3
    preset_name$ = "BriansBrain"
endif

# ===========================================================================
# 1. VALIDATION / CONSTANTS
# ===========================================================================
if duration_s <= 0
    exitScript: "Duration must be greater than zero."
endif
if sample_rate_Hz < 2000
    exitScript: "Sample rate must be at least 2000 Hz."
endif
if segment_duration_s <= 0
    exitScript: "Segment duration must be greater than zero."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 or a positive integer."
endif

if grid_size > 64
    grid_size = 64
endif
if grid_size < 8
    grid_size = 8
endif
if rule_type > 1 and grid_size > 24
    grid_size = 24
endif

if rule_type = 1
    if rule_number < 0 or rule_number > 255
        exitScript: "Elementary CA rule number must be between 0 and 255."
    endif
endif

nyquist = sample_rate_Hz / 2
safeTop = 0.45 * sample_rate_Hz
if base_frequency_Hz >= safeTop
    exitScript: "Base frequency is too high for this sample rate. Keep it below 45 percent of Sample_rate_Hz."
endif

effectiveBase = base_frequency_Hz
effectiveSpread = frequency_spread_Hz
antiAliasAdjusted = 0
if effectiveBase + effectiveSpread > safeTop
    effectiveSpread = safeTop - effectiveBase
    antiAliasAdjusted = 1
endif
if effectiveSpread <= 0
    exitScript: "No safe frequency spread remains at this sample rate."
endif
effectiveTop = effectiveBase + effectiveSpread

# Include the final partial generation rather than leaving a silent tail.
totalSegments = ceiling(duration_s / segment_duration_s)
if totalSegments < 1
    totalSegments = 1
endif
if totalSegments > 2000
    exitScript: "More than 2000 CA generations requested. Increase Segment_duration_s or reduce Duration_s."
endif

# The synthesis window is mostly flat; only a short edge ramp prevents clicks.
edgeFade = min(0.005, 0.20 * segment_duration_s)
if edgeFade <= 0
    edgeFade = segment_duration_s / 10
endif

twoPi = 2 * pi
goldenFrac = 0.618033988749895
uid$ = string$(randomInteger(10000, 99999))

if boundary_mode = 1
    boundaryName$ = "fixed"
else
    boundaryName$ = "wrap"
endif

if spatial_mode = 1
    spatialName$ = "mono"
elsif spatial_mode = 2
    spatialName$ = "stereo wide"
else
    spatialName$ = "rotating"
endif

# ===========================================================================
# 2. INFO
# ===========================================================================
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  CELLULAR AUTOMATA SYNTHESIS v0.4"
writeInfoLine: "=============================================="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", fixed$(duration_s, 3), " s"
appendInfoLine: "Grid: ", grid_size, " | generations: ", totalSegments
appendInfoLine: "Generation duration: ", fixed$(segment_duration_s * 1000, 1), " ms"
appendInfoLine: "Boundary: ", boundaryName$
appendInfoLine: "Frequency map: ", fixed$(effectiveBase, 1), " - ", fixed$(effectiveTop, 1), " Hz"
if antiAliasAdjusted
    appendInfoLine: "Nyquist guard reduced the requested frequency spread."
endif

if rule_type = 1
    appendInfoLine: "Elementary rule: ", rule_number
elsif rule_type = 2
    appendInfoLine: "Game of Life: B3/S23"
else
    appendInfoLine: "Brian's Brain: dead -> firing -> refractory -> dead"
endif
appendInfoLine: ""

# ===========================================================================
# 3. INITIALIZE CA
# ===========================================================================
# Reproducibility matters only when the initial state is random.
seedWasFixed = 0
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedWasFixed = 1
    seedLabel$ = "seed " + string$(random_seed)
else
    seedLabel$ = "seed random"
endif

if rule_type = 1
    for seg to totalSegments
        for cell to grid_size
            ca_state[seg, cell] = 0
        endfor
    endfor

    if elementary_initial_condition = 1
        centreCell = floor(grid_size / 2) + 1
        ca_state[1, centreCell] = 1
        initName$ = "single-centre"

    elsif elementary_initial_condition = 2
        for cell to grid_size
            if randomUniform(0, 1) < 0.35
                ca_state[1, cell] = 1
            endif
        endfor
        initName$ = "random-35pct"

    elsif elementary_initial_condition = 3
        for cell to grid_size
            if cell mod 2 = 1
                ca_state[1, cell] = 1
            endif
        endfor
        initName$ = "alternating"

    else
        for cell to grid_size
            if randomUniform(0, 1) < 0.10
                ca_state[1, cell] = 1
            endif
        endfor
        initName$ = "random-10pct"
    endif

else
    totalCells2D = grid_size * grid_size
    for i to grid_size
        for j to grid_size
            ca_current[i, j] = 0
            ca_next[i, j] = 0
        endfor
    endfor

    if rule_type = 2
        # Standard random live-cell seed.
        for i to grid_size
            for j to grid_size
                if randomUniform(0, 1) < 0.30
                    ca_current[i, j] = 1
                endif
            endfor
        endfor
        initName$ = "random-live-30pct"

    else
        # Brian's Brain: a denser firing field on a 20x20 preset is much less
        # likely to collapse immediately than the earlier 16x16 20/15 split.
        for i to grid_size
            for j to grid_size
                r = randomUniform(0, 1)
                if r < 0.22
                    ca_current[i, j] = 1
                elsif r < 0.32
                    ca_current[i, j] = 2
                endif
            endfor
        endfor
        initName$ = "mixed-22fire-10refractory"
    endif
endif

# All stochastic initialization is now complete. Do not leave Praat's global
# random generator in a fixed deterministic state.
if seedWasFixed
    random_initializeSafelyAndUnpredictably ()
endif

appendInfoLine: "Initial condition: ", initName$
if rule_type > 1 or elementary_initial_condition = 2 or elementary_initial_condition = 4
    appendInfoLine: "Randomness: ", seedLabel$
endif
appendInfoLine: ""

# ===========================================================================
# 4. EVOLVE ELEMENTARY CA
# ===========================================================================
if rule_type = 1 and totalSegments > 1
    appendInfoLine: "Evolving Elementary CA..."

    for seg from 1 to totalSegments - 1
        for cell to grid_size
            if boundary_mode = 2
                if cell = 1
                    left = ca_state[seg, grid_size]
                else
                    left = ca_state[seg, cell - 1]
                endif

                center = ca_state[seg, cell]

                if cell = grid_size
                    right = ca_state[seg, 1]
                else
                    right = ca_state[seg, cell + 1]
                endif
            else
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
            endif

            pattern = 4 * left + 2 * center + right
            rule_bit = floor(rule_number / (2 ^ pattern)) mod 2
            ca_state[seg + 1, cell] = rule_bit
        endfor
    endfor
endif

# ===========================================================================
# 5. SYNTHESIZE GENERATIONS
# ===========================================================================
appendInfoLine: "Synthesizing CA generations..."

segSound# = zero#(totalSegments)
activeCount# = zero#(totalSegments)
refractoryCount# = zero#(totalSegments)
freqMean# = zero#(totalSegments)
freqMin# = zero#(totalSegments)
freqMax# = zero#(totalSegments)

# 2D rules need a flattened history vector for the three QC snapshots.
# Allocate it before the synthesis loop; elementary CA stores its complete
# evolution in ca_state[,] and therefore does not need this history.
if rule_type > 1
    historySize = totalSegments * grid_size * grid_size
    ca_history# = zero#(historySize)
else
    # Keep the symbol defined globally so procedures can reference the same
    # variable namespace safely even though the 1D branch never reads it.
    ca_history# = zero#(1)
endif

meanDensitySum = 0
maxDensity = 0
firstExtinction = 0
globalFreqMin = effectiveTop
globalFreqMax = effectiveBase

for seg to totalSegments
    segmentStart = (seg - 1) * segment_duration_s
    thisSegDur = min(segment_duration_s, duration_s - segmentStart)
    if thisSegDur <= 0
        thisSegDur = 1 / sample_rate_Hz
    endif
    thisEdge = min(edgeFade, 0.20 * thisSegDur)

    # Store actual 2D state history before the generation is advanced.
    if rule_type > 1
        for i to grid_size
            for j to grid_size
                flatIndex = (i - 1) * grid_size + j
                histIndex = (seg - 1) * grid_size * grid_size + flatIndex
                ca_history#[histIndex] = ca_current[i, j]
            endfor
        endfor
    endif

    activeCells = 0
    refractoryCells = 0

    if rule_type = 1
        for cell to grid_size
            if ca_state[seg, cell] = 1
                activeCells = activeCells + 1
            endif
        endfor
    else
        for i to grid_size
            for j to grid_size
                if ca_current[i, j] = 1
                    activeCells = activeCells + 1
                elsif rule_type = 3 and ca_current[i, j] = 2
                    refractoryCells = refractoryCells + 1
                endif
            endfor
        endfor
    endif

    activeCount#[seg] = activeCells
    refractoryCount#[seg] = refractoryCells

    if rule_type = 1
        totalCellsForDensity = grid_size
    else
        totalCellsForDensity = grid_size * grid_size
    endif
    density = activeCells / totalCellsForDensity
    meanDensitySum = meanDensitySum + density
    maxDensity = max(maxDensity, density)
    if activeCells = 0 and firstExtinction = 0
        firstExtinction = seg
    endif

    Create Sound from formula: "ca_gen_" + uid$, 1, 0, thisSegDur, sample_rate_Hz, "0"
    thisSegmentSound = selected("Sound")
    segSound#[seg] = thisSegmentSound

    if activeCells > 0
        # Energy compensation keeps CA density primarily a spectral-density
        # control rather than an accidental hidden gain control.
        ampPerCell = 0.65 / sqrt(activeCells)
        segFormula$ = "0"
        batchCount = 0
        freqSum = 0
        thisFreqMin = effectiveTop
        thisFreqMax = effectiveBase

        if rule_type = 1
            for cell to grid_size
                if ca_state[seg, cell] = 1
                    if grid_size > 1
                        u = (cell - 1) / (grid_size - 1)
                    else
                        u = 0
                    endif
                    freq = effectiveBase + u * effectiveSpread
                    cellIndex = cell
                    phaseCycles = cellIndex * goldenFrac - floor(cellIndex * goldenFrac)
                    phase = twoPi * phaseCycles

                    freqSum = freqSum + freq
                    thisFreqMin = min(thisFreqMin, freq)
                    thisFreqMax = max(thisFreqMax, freq)
                    globalFreqMin = min(globalFreqMin, freq)
                    globalFreqMax = max(globalFreqMax, freq)

                    freq$ = fixed$(freq, 6)
                    phase$ = fixed$(phase, 8)
                    amp$ = fixed$(ampPerCell, 8)
                    start$ = fixed$(segmentStart, 8)
                    dur$ = fixed$(thisSegDur, 8)
                    edge$ = fixed$(thisEdge, 8)

                    tone$ = amp$ + " * sin(2*pi*" + freq$ + "*(x+" + start$ + ") + " + phase$ + ")"
                    env$ = "if x < " + edge$ + " then 0.5-0.5*cos(pi*x/" + edge$ + ") else if x > " + dur$ + "-" + edge$ + " then 0.5-0.5*cos(pi*(" + dur$ + "-x)/" + edge$ + ") else 1 fi fi"
                    segFormula$ = segFormula$ + " + (" + tone$ + ") * (" + env$ + ")"
                    batchCount = batchCount + 1

                    if batchCount >= 50
                        selectObject: thisSegmentSound
                        Formula: "self + (" + segFormula$ + ")"
                        segFormula$ = "0"
                        batchCount = 0
                    endif
                endif
            endfor

        else
            for i to grid_size
                for j to grid_size
                    if ca_current[i, j] = 1
                        cellIndex = (i - 1) * grid_size + j

                        if rule_type = 2
                            # A near-injective 2D projection that uses both axes
                            # while spanning exactly 0..1.
                            denom2D = (grid_size - 1) * (1 + sqrt(2))
                            u = ((i - 1) + sqrt(2) * (j - 1)) / denom2D
                        else
                            # Brian's Brain: corrected row-major map 0..1.
                            u = (cellIndex - 1) / (grid_size * grid_size - 1)
                        endif

                        freq = effectiveBase + u * effectiveSpread
                        phaseCycles = cellIndex * goldenFrac - floor(cellIndex * goldenFrac)
                        phase = twoPi * phaseCycles

                        freqSum = freqSum + freq
                        thisFreqMin = min(thisFreqMin, freq)
                        thisFreqMax = max(thisFreqMax, freq)
                        globalFreqMin = min(globalFreqMin, freq)
                        globalFreqMax = max(globalFreqMax, freq)

                        freq$ = fixed$(freq, 6)
                        phase$ = fixed$(phase, 8)
                        amp$ = fixed$(ampPerCell, 8)
                        start$ = fixed$(segmentStart, 8)
                        dur$ = fixed$(thisSegDur, 8)
                        edge$ = fixed$(thisEdge, 8)

                        tone$ = amp$ + " * sin(2*pi*" + freq$ + "*(x+" + start$ + ") + " + phase$ + ")"
                        env$ = "if x < " + edge$ + " then 0.5-0.5*cos(pi*x/" + edge$ + ") else if x > " + dur$ + "-" + edge$ + " then 0.5-0.5*cos(pi*(" + dur$ + "-x)/" + edge$ + ") else 1 fi fi"
                        segFormula$ = segFormula$ + " + (" + tone$ + ") * (" + env$ + ")"
                        batchCount = batchCount + 1

                        if batchCount >= 50
                            selectObject: thisSegmentSound
                            Formula: "self + (" + segFormula$ + ")"
                            segFormula$ = "0"
                            batchCount = 0
                        endif
                    endif
                endfor
            endfor
        endif

        if segFormula$ <> "0"
            selectObject: thisSegmentSound
            Formula: "self + (" + segFormula$ + ")"
        endif

        freqMean#[seg] = freqSum / activeCells
        freqMin#[seg] = thisFreqMin
        freqMax#[seg] = thisFreqMax
    endif

    # Advance 2D CAs only after the current generation has been sonified and
    # stored for visualization.
    if rule_type > 1 and seg < totalSegments
        if rule_type = 2
            @evolveGameOfLife
        else
            @evolveBrianBrain
        endif
    endif

    if seg mod 20 = 0 or seg = totalSegments
        appendInfoLine: "  Generation ", seg, "/", totalSegments, " | active: ", activeCells
    endif
endfor

meanDensity = meanDensitySum / totalSegments

# Concatenate the short generation Sounds. Because each segment was created in
# chronological order, Praat's object-list order is chronological as well.
selectObject: segSound#[1]
for seg from 2 to totalSegments
    plusObject: segSound#[seg]
endfor
Concatenate
outputSound = selected("Sound")
Rename: "ca_mono_" + preset_name$

for seg to totalSegments
    removeObject: segSound#[seg]
endfor

# Exact endpoint safety: a short global fade catches any numerical residue.
selectObject: outputSound
finalFade = min(0.01, 0.10 * duration_s)
fadeOutStart = duration_s - finalFade
Formula: "if x < finalFade then self*(x/finalFade) else if x > fadeOutStart then self*((duration_s-x)/finalFade) else self fi fi"

# ===========================================================================
# 6. SPATIAL RENDER
# ===========================================================================
if spatial_mode = 2
    appendInfoLine: "Creating decorrelated stereo width..."
    sourceMonoID = outputSound

    selectObject: sourceMonoID
    Copy: "ca_left_" + uid$
    leftSound = selected("Sound")

    decorrelationDelay = min(0.007, 0.25 * segment_duration_s)
    Create Sound from formula: "ca_right_" + uid$, 1, 0, duration_s, sample_rate_Hz, "object(sourceMonoID, x - decorrelationDelay, 1)"
    rightSound = selected("Sound")

    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "ca_" + preset_name$

    removeObject: sourceMonoID, leftSound, rightSound
    outputSound = stereoSound

elsif spatial_mode = 3
    appendInfoLine: "Creating equal-power rotating stereo..."
    sourceMonoID = outputSound

    selectObject: sourceMonoID
    Copy: "ca_left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * sqrt(0.5 - 0.5*sin(2*pi*0.15*x))"

    selectObject: sourceMonoID
    Copy: "ca_right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * sqrt(0.5 + 0.5*sin(2*pi*0.15*x))"

    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "ca_" + preset_name$

    removeObject: sourceMonoID, leftSound, rightSound
    outputSound = stereoSound

else
    selectObject: outputSound
    Rename: "ca_" + preset_name$
endif

# ===========================================================================
# 7. OUTPUT LEVEL / QC
# ===========================================================================
selectObject: outputSound
preNormPeak = Get absolute extremum: 0, 0, "None"
if normalize_output and preNormPeak > 0
    Scale peak: 0.90
endif

selectObject: outputSound
finalPeak = Get absolute extremum: 0, 0, "None"
finalRMS = Get root-mean-square: 0, 0
finalDuration = Get total duration
finalChannels = Get number of channels

if firstExtinction > 0
    extinctionTime = (firstExtinction - 1) * segment_duration_s
else
    extinctionTime = -1
endif

# ===========================================================================
# 8. VISUALIZATION
# ===========================================================================
if draw_visualization
    appendInfoLine: "Drawing visualization..."
    @drawCAVisualization
endif

# ===========================================================================
# 9. FINAL INFO / PLAY
# ===========================================================================
appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=============================================="
appendInfoLine: "Output duration: ", fixed$(finalDuration, 4), " s"
appendInfoLine: "Mean active density: ", fixed$(100 * meanDensity, 1), " percent"
appendInfoLine: "Maximum active density: ", fixed$(100 * maxDensity, 1), " percent"
if firstExtinction > 0
    appendInfoLine: "First silent generation: ", firstExtinction, " (", fixed$(extinctionTime, 3), " s)"
else
    appendInfoLine: "No silent generation occurred."
endif
appendInfoLine: "Realized sounding range: ", fixed$(globalFreqMin, 1), " - ", fixed$(globalFreqMax, 1), " Hz"
appendInfoLine: "Peak: ", fixed$(finalPeak, 3), " | RMS: ", fixed$(finalRMS, 4)
appendInfoLine: "Spatial: ", spatialName$

if play_result
    selectObject: outputSound
    Play
endif

selectObject: outputSound


# ===========================================================================
# PROCEDURE: GAME OF LIFE B3/S23
# ===========================================================================
procedure evolveGameOfLife
    for .i to grid_size
        for .j to grid_size
            .neighbors = 0

            for .di from -1 to 1
                for .dj from -1 to 1
                    if .di <> 0 or .dj <> 0
                        .ni = .i + .di
                        .nj = .j + .dj

                        if boundary_mode = 2
                            if .ni < 1
                                .ni = grid_size
                            elsif .ni > grid_size
                                .ni = 1
                            endif
                            if .nj < 1
                                .nj = grid_size
                            elsif .nj > grid_size
                                .nj = 1
                            endif
                            .neighbors = .neighbors + ca_current[.ni, .nj]
                        else
                            if .ni >= 1 and .ni <= grid_size and .nj >= 1 and .nj <= grid_size
                                .neighbors = .neighbors + ca_current[.ni, .nj]
                            endif
                        endif
                    endif
                endfor
            endfor

            if ca_current[.i, .j] = 1
                if .neighbors = 2 or .neighbors = 3
                    ca_next[.i, .j] = 1
                else
                    ca_next[.i, .j] = 0
                endif
            else
                if .neighbors = 3
                    ca_next[.i, .j] = 1
                else
                    ca_next[.i, .j] = 0
                endif
            endif
        endfor
    endfor

    for .i to grid_size
        for .j to grid_size
            ca_current[.i, .j] = ca_next[.i, .j]
        endfor
    endfor
endproc


# ===========================================================================
# PROCEDURE: BRIAN'S BRAIN
# ===========================================================================
procedure evolveBrianBrain
    for .i to grid_size
        for .j to grid_size
            if ca_current[.i, .j] = 0
                .neighbors = 0
                for .di from -1 to 1
                    for .dj from -1 to 1
                        if .di <> 0 or .dj <> 0
                            .ni = .i + .di
                            .nj = .j + .dj

                            if boundary_mode = 2
                                if .ni < 1
                                    .ni = grid_size
                                elsif .ni > grid_size
                                    .ni = 1
                                endif
                                if .nj < 1
                                    .nj = grid_size
                                elsif .nj > grid_size
                                    .nj = 1
                                endif
                                if ca_current[.ni, .nj] = 1
                                    .neighbors = .neighbors + 1
                                endif
                            else
                                if .ni >= 1 and .ni <= grid_size and .nj >= 1 and .nj <= grid_size
                                    if ca_current[.ni, .nj] = 1
                                        .neighbors = .neighbors + 1
                                    endif
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
                ca_next[.i, .j] = 2
            else
                ca_next[.i, .j] = 0
            endif
        endfor
    endfor

    for .i to grid_size
        for .j to grid_size
            ca_current[.i, .j] = ca_next[.i, .j]
        endfor
    endfor
endproc


# ===========================================================================
# PROCEDURE: RESEARCH-GRADE VISUALIZATION
# ===========================================================================
procedure drawCAVisualization
    .leftViewport = 0.82
    .rightViewport = 7.55
    .bg$ = "{0.975, 0.975, 0.978}"
    .grid$ = "{0.78, 0.78, 0.80}"
    .stateCol$ = "{0.16, 0.16, 0.18}"
    .refrCol$ = "{0.60, 0.60, 0.64}"
    .modelCol$ = "{0.15, 0.42, 0.80}"
    .rangeCol$ = "{0.72, 0.36, 0.24}"

    if duration_s <= 4
        .tTick = 0.5
    elsif duration_s <= 10
        .tTick = 1
    elsif duration_s <= 30
        .tTick = 5
    else
        .tTick = 10
    endif

    Erase all

    # -----------------------------------------------------------------------
    # HEADER
    # -----------------------------------------------------------------------
    Select inner viewport: 0.20, 7.80, 0.06, 0.34
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    if rule_type = 1
        Text: 0.5, "centre", 0.55, "half", "CELLULAR AUTOMATA SYNTHESIS | RULE " + string$(rule_number)
    elsif rule_type = 2
        Text: 0.5, "centre", 0.55, "half", "CELLULAR AUTOMATA SYNTHESIS | GAME OF LIFE"
    else
        Text: 0.5, "centre", 0.55, "half", "CELLULAR AUTOMATA SYNTHESIS | BRIAN'S BRAIN"
    endif

    Select inner viewport: 0.35, 7.65, 0.38, 0.70
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.34, 0.34, 0.38}"
    Text: 0.5, "centre", 0.70, "half",
        ... "preset " + preset_name$ + " | grid " + string$(grid_size)
        ... + " | " + string$(totalSegments) + " generations | " + fixed$(segment_duration_s * 1000, 1) + " ms each | " + boundaryName$
    Text: 0.5, "centre", 0.22, "half",
        ... "frequency map " + fixed$(effectiveBase, 0) + "-" + fixed$(effectiveTop, 0) + " Hz | " + spatialName$

    # -----------------------------------------------------------------------
    # PANEL A TITLE
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35, 7.65, 0.78, 1.00
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    if rule_type = 1
        Text: 0.5, "centre", 0.52, "half", "A  ACTUAL CA EVOLUTION | active cells across the complete rendered duration"
    else
        Text: 0.5, "centre", 0.52, "half", "A  ACTUAL CA STATES | first, middle and final rendered generations"
    endif

    if rule_type = 1
        # Downsample only for display if the run is very long; every displayed
        # column represents the midpoint generation of its complete time block.
        .displayCols = min(totalSegments, 200)
        Select inner viewport: .leftViewport, .rightViewport, 1.06, 2.45
        Axes: 0, duration_s, 0.5, grid_size + 0.5
        Paint rectangle: .bg$, 0, duration_s, 0.5, grid_size + 0.5

        for .d to .displayCols
            .segIndex = round((.d - 0.5) * totalSegments / .displayCols + 0.5)
            .segIndex = min(totalSegments, max(1, .segIndex))
            .x0 = (.d - 1) * duration_s / .displayCols
            .x1 = .d * duration_s / .displayCols

            for .cell to grid_size
                if ca_state[.segIndex, .cell] = 1
                    Paint rectangle: .stateCol$, .x0, .x1, .cell - 0.5, .cell + 0.5
                endif
            endfor
        endfor

        Colour: "Black"
        Draw inner box
        Marks left: 4, "yes", "yes", "no"
        Marks bottom every: 1, .tTick, "no", "yes", "yes"
        Font size: 6
        Text left: "yes", "Cell"

    else
        .snap1 = 1
        .snap2 = max(1, round(totalSegments / 2))
        .snap3 = totalSegments

        # Snapshot 1
        Select inner viewport: 0.78, 2.75, 1.08, 2.43
        Axes: 0.5, grid_size + 0.5, grid_size + 0.5, 0.5
        Paint rectangle: .bg$, 0.5, grid_size + 0.5, 0.5, grid_size + 0.5
        for .i to grid_size
            for .j to grid_size
                .flat = (.i - 1) * grid_size + .j
                .idx = (.snap1 - 1) * grid_size * grid_size + .flat
                .state = ca_history#[.idx]
                if .state = 1
                    Paint rectangle: .stateCol$, .j - 0.5, .j + 0.5, .i - 0.5, .i + 0.5
                elsif .state = 2
                    Paint rectangle: .refrCol$, .j - 0.5, .j + 0.5, .i - 0.5, .i + 0.5
                endif
            endfor
        endfor
        Colour: "Black"
        Draw inner box
        Font size: 5
        Text top: "no", "g1"

        # Snapshot 2
        Select inner viewport: 3.02, 4.99, 1.08, 2.43
        Axes: 0.5, grid_size + 0.5, grid_size + 0.5, 0.5
        Paint rectangle: .bg$, 0.5, grid_size + 0.5, 0.5, grid_size + 0.5
        for .i to grid_size
            for .j to grid_size
                .flat = (.i - 1) * grid_size + .j
                .idx = (.snap2 - 1) * grid_size * grid_size + .flat
                .state = ca_history#[.idx]
                if .state = 1
                    Paint rectangle: .stateCol$, .j - 0.5, .j + 0.5, .i - 0.5, .i + 0.5
                elsif .state = 2
                    Paint rectangle: .refrCol$, .j - 0.5, .j + 0.5, .i - 0.5, .i + 0.5
                endif
            endfor
        endfor
        Colour: "Black"
        Draw inner box
        Font size: 5
        Text top: "no", "g" + string$(.snap2)

        # Snapshot 3
        Select inner viewport: 5.26, 7.23, 1.08, 2.43
        Axes: 0.5, grid_size + 0.5, grid_size + 0.5, 0.5
        Paint rectangle: .bg$, 0.5, grid_size + 0.5, 0.5, grid_size + 0.5
        for .i to grid_size
            for .j to grid_size
                .flat = (.i - 1) * grid_size + .j
                .idx = (.snap3 - 1) * grid_size * grid_size + .flat
                .state = ca_history#[.idx]
                if .state = 1
                    Paint rectangle: .stateCol$, .j - 0.5, .j + 0.5, .i - 0.5, .i + 0.5
                elsif .state = 2
                    Paint rectangle: .refrCol$, .j - 0.5, .j + 0.5, .i - 0.5, .i + 0.5
                endif
            endfor
        endfor
        Colour: "Black"
        Draw inner box
        Font size: 5
        Text top: "no", "g" + string$(.snap3)
    endif

    # -----------------------------------------------------------------------
    # PANEL B TITLE
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35, 7.65, 2.58, 2.80
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    if rule_type = 3
        Text: 0.5, "centre", 0.52, "half", "B  ACTIVITY TRAJECTORY | firing density (solid) and refractory density (dotted)"
    else
        Text: 0.5, "centre", 0.52, "half", "B  ACTIVITY TRAJECTORY | active-cell density that controls spectral population"
    endif

    Select inner viewport: .leftViewport, .rightViewport, 2.86, 4.02
    Axes: 0, duration_s, 0, 1
    Paint rectangle: .bg$, 0, duration_s, 0, 1
    Colour: .grid$
    Dotted line
    Draw line: 0, 0.25, duration_s, 0.25
    Draw line: 0, 0.50, duration_s, 0.50
    Draw line: 0, 0.75, duration_s, 0.75

    Plain line
    Colour: .modelCol$
    Line width: 1.2
    for .seg from 2 to totalSegments
        .t1 = min(duration_s, (.seg - 1.5) * segment_duration_s)
        .t2 = min(duration_s, (.seg - 0.5) * segment_duration_s)
        if rule_type = 1
            .den1 = activeCount#[.seg - 1] / grid_size
            .den2 = activeCount#[.seg] / grid_size
        else
            .den1 = activeCount#[.seg - 1] / (grid_size * grid_size)
            .den2 = activeCount#[.seg] / (grid_size * grid_size)
        endif
        Draw line: .t1, .den1, .t2, .den2
    endfor

    if rule_type = 3
        Colour: .rangeCol$
        Dotted line
        Line width: 1
        for .seg from 2 to totalSegments
            .t1 = min(duration_s, (.seg - 1.5) * segment_duration_s)
            .t2 = min(duration_s, (.seg - 0.5) * segment_duration_s)
            .den1 = refractoryCount#[.seg - 1] / (grid_size * grid_size)
            .den2 = refractoryCount#[.seg] / (grid_size * grid_size)
            Draw line: .t1, .den1, .t2, .den2
        endfor
        Plain line
    endif

    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, .tTick, "no", "yes", "yes"
    Font size: 6
    Text left: "yes", "Density"

    # -----------------------------------------------------------------------
    # PANEL C TITLE
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35, 7.65, 4.15, 4.37
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.52, "half", "C  MODEL -> MEASUREMENT | measured spectrum-time field with realized frequency guide"

    # Representative channel: avoid stereo fold-down cancellation.
    selectObject: outputSound
    .nCh = Get number of channels
    if .nCh = 1
        Copy: "ca_viz_mono"
        .vizSound = selected("Sound")
    else
        selectObject: outputSound
        Extract one channel: 1
        .ch1 = selected("Sound")
        .rms1 = Get root-mean-square: 0, 0

        selectObject: outputSound
        Extract one channel: 2
        .ch2 = selected("Sound")
        .rms2 = Get root-mean-square: 0, 0

        if .rms2 > .rms1
            .vizSound = .ch2
            removeObject: .ch1
        else
            .vizSound = .ch1
            removeObject: .ch2
        endif
    endif

    .specTop = min(0.45 * sample_rate_Hz, max(500, 1.15 * effectiveTop))
    .specStep = max(0.005, duration_s / 1400)
    selectObject: .vizSound
    .spec = To Spectrogram: 0.03, .specTop, .specStep, 20, "Gaussian"

    Select inner viewport: .leftViewport, .rightViewport, 4.43, 5.67
    selectObject: .spec
    Paint: 0, 0, 0, .specTop, 100, 1, 50, 6, 0, 0

    Axes: 0, duration_s, 0, .specTop
    Colour: .rangeCol$
    Dotted line
    Line width: 0.8
    for .seg from 2 to totalSegments
        if activeCount#[.seg - 1] > 0 and activeCount#[.seg] > 0
            .t1 = min(duration_s, (.seg - 1.5) * segment_duration_s)
            .t2 = min(duration_s, (.seg - 0.5) * segment_duration_s)
            Draw line: .t1, freqMin#[.seg - 1], .t2, freqMin#[.seg]
            Draw line: .t1, freqMax#[.seg - 1], .t2, freqMax#[.seg]
        endif
    endfor

    Colour: .modelCol$
    Plain line
    Line width: 1.2
    for .seg from 2 to totalSegments
        if activeCount#[.seg - 1] > 0 and activeCount#[.seg] > 0
            .t1 = min(duration_s, (.seg - 1.5) * segment_duration_s)
            .t2 = min(duration_s, (.seg - 0.5) * segment_duration_s)
            Draw line: .t1, freqMean#[.seg - 1], .t2, freqMean#[.seg]
        endif
    endfor

    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, .tTick, "no", "yes", "yes"
    Font size: 6
    Text left: "yes", "Frequency (Hz)"
    Text bottom: "yes", "Time (s)"

    removeObject: .vizSound, .spec

    # -----------------------------------------------------------------------
    # PANEL D: MECHANISM
    # -----------------------------------------------------------------------
    Select inner viewport: 0.55, 7.45, 5.82, 6.53
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.955, 0.955, 0.960}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.50, "centre", 0.80, "half", "CA STATE[n]  ->  active cells  ->  f(cell)  ->  additive generation  ->  spatial render"

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    if rule_type = 1
        Text: 0.50, "centre", 0.50, "half", "pattern = 4L + 2C + R; next = bit(pattern) of Rule " + string$(rule_number)
    elsif rule_type = 2
        Text: 0.50, "centre", 0.50, "half", "Game of Life: birth at 3 neighbours; survive at 2 or 3"
    else
        Text: 0.50, "centre", 0.50, "half", "Brian's Brain: dead + 2 firing neighbours -> firing -> refractory -> dead"
    endif
    Text: 0.50, "centre", 0.23, "half", "f = f0 + u(cell) * spread; oscillator gain = 0.65 / sqrt(Nactive)"

    Colour: "{0.55, 0.55, 0.58}"
    Draw rectangle: 0, 1, 0, 1

    # -----------------------------------------------------------------------
    # SUMMARY / QC
    # -----------------------------------------------------------------------
    Select inner viewport: 0.55, 7.45, 6.67, 7.72
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.93, 0.93, 0.935}", 0, 1, 0, 1

    if firstExtinction > 0
        .ext$ = "first silent g" + string$(firstExtinction) + " at " + fixed$(extinctionTime, 2) + " s"
    else
        .ext$ = "no silent generation"
    endif

    if antiAliasAdjusted
        .aa$ = "Nyquist-adjusted"
    else
        .aa$ = "requested range intact"
    endif

    Font size: 6
    Colour: "{0.25, 0.25, 0.25}"
    Text: 0.02, "left", 0.77, "half",
        ... "CA  |  mean active " + fixed$(100 * meanDensity, 1) + " pct"
        ... + "  |  max " + fixed$(100 * maxDensity, 1) + " pct"
        ... + "  |  " + .ext$

    Text: 0.02, "left", 0.50, "half",
        ... "MAPPING  |  realized " + fixed$(globalFreqMin, 0) + "-" + fixed$(globalFreqMax, 0) + " Hz"
        ... + "  |  " + .aa$ + "  |  edge taper " + fixed$(1000 * edgeFade, 1) + " ms"

    Text: 0.02, "left", 0.23, "half",
        ... "OUTPUT  |  peak " + fixed$(finalPeak, 3)
        ... + "  |  RMS " + fixed$(finalRMS, 4)
        ... + "  |  " + string$(finalChannels) + " ch  |  " + spatialName$ + "  |  " + seedLabel$

    Colour: "{0.52, 0.52, 0.54}"
    Draw rectangle: 0, 1, 0, 1

    Colour: "Black"
    Line width: 1
    Font size: 10
endproc
