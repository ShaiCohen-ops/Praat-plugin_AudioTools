# ============================================================
# Praat AudioTools - Advanced Poisson Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 reviewed (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Poisson-process granular synthesis. Each layer is a homogeneous
#   Poisson point process: inter-onset intervals are exponentially
#   distributed with rate lambda. Each point triggers a raised-cosine
#   windowed sinusoidal grain. Multiple rates create layered textures.
#
# Review changes v0.4:
#   - Preserves a true Poisson process and adds reproducible Random_seed.
#   - Randomize_parameters now controls rate jitter AND grain frequency,
#     duration and phase; Poisson timing remains stochastic by definition.
#   - Renamed misleading "Rhythmic" / "Chaotic" modes to accurately
#     describe steady-rate and broad Poisson scatter behaviour.
#   - Balances expected layer energy by sqrt(rate * mean grain duration),
#     so denser layers do not become hidden gain controls.
#   - Adds sample-rate / Nyquist guards and proportional frequency fitting
#     rather than piling clipped grains at Nyquist.
#   - Adds workload guards for extreme event counts.
#   - Rotating stereo is complementary equal-power.
#   - Stereo-wide filter bounds adapt to sample rate.
#   - Visualization uses the ACTUAL generated event realization and shows:
#       A) event raster,
#       B) normalized IOI density vs the Exp(1) Poisson prediction,
#       C) measured spectrogram with actual grain trajectories overlaid.
#   - QC reports expected vs realized point count, normalized IOI mean/CV,
#     frequency range, anti-alias fitting and seed.
# ============================================================

form Advanced Poisson Synthesis
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Standard Three Layer
        option Dense Cloud
        option Sparse Atmosphere
        option Poisson Pulse Field
        option Broad Scatter
        option Shimmering High
        option Deep Rumble

    comment === Basic Settings ===
    positive Duration_s 12
    integer Sample_rate_Hz 44100
    positive Base_frequency_Hz 100
    positive Frequency_range_Hz 300
    integer Number_of_layers 3

    comment === Poisson Rates ===
    positive Low_rate_Hz 3
    positive High_rate_Hz 15

    comment === Grain Settings ===
    positive Min_grain_duration_ms 30
    positive Max_grain_duration_ms 200

    comment === Synthesis Mode ===
    optionmenu Synthesis_mode 1
        option Rate Gradient
        option Dense Granular
        option Sparse Atmospheric
        option Steady-rate Poisson Pulses
        option Broad Poisson Scatter

    comment === Output ===
    positive Fade_time_s 2
    optionmenu Spatial_mode 1
        option Mono
        option Stereo Wide
        option Rotating
    comment Randomize OFF fixes rate jitter, grain frequency/duration/phase; Poisson timing remains random.
    boolean Randomize_parameters 1
    integer Random_seed 0
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================================
# 0. Presets
# ============================================================================
preset_name$ = "Custom"

if preset = 2
    duration_s = 12
    base_frequency_Hz = 100
    frequency_range_Hz = 300
    low_rate_Hz = 3
    high_rate_Hz = 15
    number_of_layers = 3
    min_grain_duration_ms = 100
    max_grain_duration_ms = 300
    synthesis_mode = 1
    spatial_mode = 1
    synthesis_mode$ = "Rate Gradient"
    preset_name$ = "Standard"
elsif preset = 3
    duration_s = 10
    base_frequency_Hz = 150
    frequency_range_Hz = 400
    low_rate_Hz = 10
    high_rate_Hz = 25
    number_of_layers = 4
    min_grain_duration_ms = 30
    max_grain_duration_ms = 80
    synthesis_mode = 2
    spatial_mode = 2
    synthesis_mode$ = "Dense Granular"
    preset_name$ = "DenseCloud"
elsif preset = 4
    duration_s = 20
    base_frequency_Hz = 80
    frequency_range_Hz = 500
    low_rate_Hz = 1
    high_rate_Hz = 5
    number_of_layers = 3
    min_grain_duration_ms = 300
    max_grain_duration_ms = 800
    synthesis_mode = 3
    spatial_mode = 3
    fade_time_s = 3
    synthesis_mode$ = "Sparse Atmospheric"
    preset_name$ = "Sparse"
elsif preset = 5
    duration_s = 15
    base_frequency_Hz = 120
    frequency_range_Hz = 200
    low_rate_Hz = 5
    high_rate_Hz = 12
    number_of_layers = 4
    min_grain_duration_ms = 80
    max_grain_duration_ms = 120
    randomize_parameters = 0
    synthesis_mode = 4
    spatial_mode = 1
    synthesis_mode$ = "Steady-rate Poisson Pulses"
    preset_name$ = "PoissonPulse"
elsif preset = 6
    duration_s = 12
    base_frequency_Hz = 100
    frequency_range_Hz = 600
    low_rate_Hz = 2
    high_rate_Hz = 20
    number_of_layers = 5
    min_grain_duration_ms = 50
    max_grain_duration_ms = 300
    synthesis_mode = 5
    spatial_mode = 2
    synthesis_mode$ = "Broad Poisson Scatter"
    preset_name$ = "BroadScatter"
elsif preset = 7
    duration_s = 10
    base_frequency_Hz = 800
    frequency_range_Hz = 1500
    low_rate_Hz = 8
    high_rate_Hz = 20
    number_of_layers = 4
    min_grain_duration_ms = 20
    max_grain_duration_ms = 60
    synthesis_mode = 2
    spatial_mode = 2
    synthesis_mode$ = "Dense Granular"
    preset_name$ = "Shimmering"
elsif preset = 8
    duration_s = 15
    base_frequency_Hz = 40
    frequency_range_Hz = 80
    low_rate_Hz = 2
    high_rate_Hz = 8
    number_of_layers = 3
    min_grain_duration_ms = 200
    max_grain_duration_ms = 500
    synthesis_mode = 3
    spatial_mode = 3
    fade_time_s = 3
    synthesis_mode$ = "Sparse Atmospheric"
    preset_name$ = "DeepRumble"
endif

# ============================================================================
# 1. Validation and derived limits
# ============================================================================
if sample_rate_Hz < 4000
    exitScript: "Sample rate must be at least 4000 Hz."
endif
if sample_rate_Hz > 384000
    exitScript: "Sample rate is implausibly high (>384 kHz)."
endif

if number_of_layers > 8
    number_of_layers = 8
endif
if number_of_layers < 1
    number_of_layers = 1
endif

if high_rate_Hz < low_rate_Hz
    swapRate = low_rate_Hz
    low_rate_Hz = high_rate_Hz
    high_rate_Hz = swapRate
endif

if max_grain_duration_ms < min_grain_duration_ms
    swapDur = min_grain_duration_ms
    min_grain_duration_ms = max_grain_duration_ms
    max_grain_duration_ms = swapDur
endif

minAllowedGrain_s = 8 / sample_rate_Hz
minGrain_s = max(min_grain_duration_ms / 1000, minAllowedGrain_s)
maxGrain_s = max(max_grain_duration_ms / 1000, minGrain_s)
meanGrain_s = 0.5 * (minGrain_s + maxGrain_s)

if fade_time_s > duration_s / 2
    fade_time_s = duration_s / 2
endif
if fade_time_s < 0
    fade_time_s = 0
endif

nyquist = sample_rate_Hz / 2
safeTop = 0.45 * sample_rate_Hz
safeBottom = max(20, sample_rate_Hz / 10000)

# Conservative workload estimate before creating any process.
if synthesis_mode = 1
    maxRateEstimate = high_rate_Hz
    if randomize_parameters
        maxRateEstimate = 1.2 * maxRateEstimate
    endif
elsif synthesis_mode = 2
    maxRateEstimate = 1.5 * high_rate_Hz
    if randomize_parameters
        maxRateEstimate = 1.3 * maxRateEstimate
    endif
elsif synthesis_mode = 3
    maxRateEstimate = 0.5 * low_rate_Hz
    if randomize_parameters
        maxRateEstimate = 1.4 * maxRateEstimate
    endif
elsif synthesis_mode = 4
    maxRateEstimate = 0.5 * (low_rate_Hz + high_rate_Hz)
    if randomize_parameters
        maxRateEstimate = 1.1 * maxRateEstimate
    endif
else
    maxRateEstimate = high_rate_Hz
    if randomize_parameters
        maxRateEstimate = 1.5 * maxRateEstimate
    endif
endif

conservativeExpected = duration_s * number_of_layers * maxRateEstimate
if conservativeExpected > 25000
    exitScript: "Settings may generate more than 25,000 grains. Reduce duration, layers, or Poisson rates."
endif

# ============================================================================
# 2. Randomness, constants, bookkeeping
# ============================================================================
# UID is drawn BEFORE research seeding so object naming does not consume the
# reproducible DSP random stream.
uid$ = string$(randomInteger(10000, 99999))

if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
endif

twoPi = 2 * pi
grainsPerChunk = 25
maxGeneratedPoints = 30000

totalPoints = 0
totalGrains = 0
expectedTotal = 0
antiAliasFits = 0

minFreqReal = 1e30
maxFreqReal = 0
sumGrainDur = 0

# Normalized IOI z = lambda * delta_t should follow Exp(1).
nHistBins = 20
histMaxZ = 5
histBinWidth = histMaxZ / nHistBins
for bin to nHistBins
    histCount[bin] = 0
endfor
histUsed = 0
histOverflow = 0
nIntervals = 0
sumNormIOI = 0
sumNormIOI2 = 0

# ============================================================================
# 3. Info and output canvas
# ============================================================================
writeInfoLine: "=== Advanced Poisson Synthesis ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "Layers: ", number_of_layers
appendInfoLine: "Mode: ", synthesis_mode$
if random_seed > 0
    appendInfoLine: "Seed: ", random_seed, " (reproducible)"
else
    appendInfoLine: "Seed: 0 (unpredictable)"
endif
appendInfoLine: ""

outputSound = Create Sound from formula: "poisson_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

# ============================================================================
# 4. Generate each independent Poisson layer
# ============================================================================
for layer to number_of_layers
    appendInfoLine: "Layer ", layer, "/", number_of_layers, "..."

    # ---- Layer rate ---------------------------------------------------------
    if synthesis_mode = 1
        # Rate gradient from low to high across layers.
        layerRate = low_rate_Hz + (high_rate_Hz - low_rate_Hz) * (layer - 1) / max(1, number_of_layers - 1)
        if randomize_parameters
            layerRate = layerRate * (0.8 + 0.4 * randomUniform(0, 1))
        endif
        modeAmp = 1.5
    elsif synthesis_mode = 2
        layerRate = high_rate_Hz * 1.5
        if randomize_parameters
            layerRate = layerRate * (0.7 + 0.6 * randomUniform(0, 1))
        endif
        modeAmp = 1.2
    elsif synthesis_mode = 3
        layerRate = low_rate_Hz * 0.5
        if randomize_parameters
            layerRate = layerRate * (0.6 + 0.8 * randomUniform(0, 1))
        endif
        modeAmp = 2.0
    elsif synthesis_mode = 4
        layerRate = (low_rate_Hz + high_rate_Hz) / 2
        if randomize_parameters
            layerRate = layerRate * (0.9 + 0.2 * randomUniform(0, 1))
        endif
        modeAmp = 1.8
    else
        if randomize_parameters
            layerRate = low_rate_Hz + (high_rate_Hz - low_rate_Hz) * randomUniform(0, 1)
            layerRate = layerRate * (0.5 + randomUniform(0, 1))
        else
            layerRate = (low_rate_Hz + high_rate_Hz) / 2
        endif
        modeAmp = 1.5
    endif

    layerRate = max(layerRate, 0.001)
    layerRateUsed[layer] = layerRate
    expectedLayer = layerRate * duration_s
    expectedTotal = expectedTotal + expectedLayer

    # Expected-energy balancing: for a stationary grain cloud, expected
    # overlap is approximately lambda * E[duration].  Compensating by the
    # square root keeps density from acting as a hidden level control.
    overlapExpectation = max(layerRate * meanGrain_s, 0.05)
    layerGain = modeAmp / (number_of_layers * sqrt(overlapExpectation))

    # ---- True homogeneous Poisson process ----------------------------------
    poissonProc = Create Poisson process: "poisson_" + uid$ + "_L" + string$(layer), 0, duration_s, layerRate
    numPoints = Get number of points
    layerCount[layer] = numPoints
    totalPoints = totalPoints + numPoints

    if totalPoints > maxGeneratedPoints
        removeObject: poissonProc, outputSound
        if random_seed > 0
            random_initializeSafelyAndUnpredictably ()
        endif
        exitScript: "A Poisson realization exceeded 30,000 points. Reduce rate, duration, or layers."
    endif

    appendInfoLine: "  lambda: ", fixed$(layerRate, 2), " Hz | expected ", fixed$(expectedLayer, 1), " | realized ", numPoints

    # ---- IOI statistics from the actual process ----------------------------
    prevPointTime = -1
    for pt to numPoints
        selectObject: poissonProc
        pointTime = Get time from index: pt

        if prevPointTime >= 0
            normIOI = layerRate * (pointTime - prevPointTime)
            nIntervals = nIntervals + 1
            sumNormIOI = sumNormIOI + normIOI
            sumNormIOI2 = sumNormIOI2 + normIOI * normIOI

            if normIOI < histMaxZ
                histBin = floor(normIOI / histBinWidth) + 1
                histBin = min(max(histBin, 1), nHistBins)
                histCount[histBin] = histCount[histBin] + 1
                histUsed = histUsed + 1
            else
                histOverflow = histOverflow + 1
            endif
        endif
        prevPointTime = pointTime
    endfor

    # ---- Render grains in compact formula chunks ---------------------------
    chunkStart = 1
    while chunkStart <= numPoints
        chunkEnd = min(chunkStart + grainsPerChunk - 1, numPoints)
        chunkFormula$ = "0"

        for pt from chunkStart to chunkEnd
            selectObject: poissonProc
            pointTime = Get time from index: pt

            # Randomize_parameters controls grain parameters. The Poisson
            # arrival times remain stochastic even when this is OFF.
            if randomize_parameters
                uFreq = randomUniform(0, 1)
                uFreq2 = randomUniform(0, 1)
                uDur = randomUniform(0, 1)
                grainPhase = twoPi * randomUniform(0, 1)
            else
                uFreq = 0.5
                uFreq2 = 0.5
                uDur = 0.5
                grainPhase = 0
            endif

            # Raw frequency field and its theoretical range for this layer.
            if synthesis_mode = 1
                rawMin = base_frequency_Hz
                rawMax = base_frequency_Hz + frequency_range_Hz
                rawFreq = rawMin + frequency_range_Hz * uFreq
            elsif synthesis_mode = 2
                rawMin = base_frequency_Hz * (0.5 + layer * 0.3)
                rawMax = rawMin + frequency_range_Hz
                rawFreq = rawMin + frequency_range_Hz * uFreq
            elsif synthesis_mode = 3
                rawMin = base_frequency_Hz * (0.3 + layer * 0.4)
                rawMax = rawMin + 0.5 * frequency_range_Hz
                rawFreq = rawMin + 0.5 * frequency_range_Hz * uFreq
            elsif synthesis_mode = 4
                rawMin = base_frequency_Hz * layer
                rawMax = rawMin + 0.3 * frequency_range_Hz
                rawFreq = rawMin + 0.3 * frequency_range_Hz * uFreq
            else
                rawMin = 0.5 * base_frequency_Hz
                rawMax = 2.5 * base_frequency_Hz + frequency_range_Hz
                rawFreq = base_frequency_Hz * (0.5 + 2 * uFreq2) + frequency_range_Hz * uFreq
            endif

            # Fit the whole requested field proportionally into a safe band.
            # This avoids a pile-up caused by hard clamping at Nyquist.
            grainFreq = rawFreq
            if rawMax > safeTop
                if rawMax > safeBottom
                    fitScale = (safeTop - safeBottom) / (rawMax - safeBottom)
                    fitScale = min(max(fitScale, 0), 1)
                    grainFreq = safeBottom + (rawFreq - safeBottom) * fitScale
                else
                    grainFreq = safeBottom
                endif
                antiAliasFits = antiAliasFits + 1
            endif
            grainFreq = min(max(grainFreq, safeBottom), safeTop)

            grainDur = minGrain_s + (maxGrain_s - minGrain_s) * uDur
            if pointTime + grainDur > duration_s
                grainDur = duration_s - pointTime
            endif

            # Require at least four samples after end truncation.
            if grainDur >= 4 / sample_rate_Hz
                grainAmp = layerGain

                totalGrains = totalGrains + 1
                eventTime[totalGrains] = pointTime
                eventDur[totalGrains] = grainDur
                eventFreq[totalGrains] = grainFreq
                eventLayer[totalGrains] = layer

                minFreqReal = min(minFreqReal, grainFreq)
                maxFreqReal = max(maxFreqReal, grainFreq)
                sumGrainDur = sumGrainDur + grainDur

                sTime$ = fixed$(pointTime, 7)
                sEnd$ = fixed$(pointTime + grainDur, 7)
                sAmp$ = fixed$(grainAmp, 8)
                sFreq$ = fixed$(grainFreq, 4)
                sDur$ = fixed$(grainDur, 7)
                sPhase$ = fixed$(grainPhase, 7)

                grainTerm$ = " + if x >= " + sTime$ + " and x < " + sEnd$ + " then " + sAmp$ + " * sin(twoPi * " + sFreq$ + " * (x - " + sTime$ + ") + " + sPhase$ + ") * (1 - cos(twoPi * (x - " + sTime$ + ") / " + sDur$ + ")) / 2 else 0 fi"
                chunkFormula$ = chunkFormula$ + grainTerm$
            endif
        endfor

        selectObject: outputSound
        Formula: "self + (" + chunkFormula$ + ")"
        chunkStart = chunkEnd + 1
    endwhile

    removeObject: poissonProc
endfor

# Restore Praat's global RNG after all stochastic DSP draws.
if random_seed > 0
    random_initializeSafelyAndUnpredictably ()
endif

# ============================================================================
# 5. Statistical QC
# ============================================================================
if nIntervals > 0
    meanNormIOI = sumNormIOI / nIntervals
    varNormIOI = max(0, sumNormIOI2 / nIntervals - meanNormIOI * meanNormIOI)
    sdNormIOI = sqrt(varNormIOI)
    if meanNormIOI > 0
        cvNormIOI = sdNormIOI / meanNormIOI
    else
        cvNormIOI = undefined
    endif
else
    meanNormIOI = undefined
    cvNormIOI = undefined
endif

if expectedTotal > 0
    countZ = (totalPoints - expectedTotal) / sqrt(expectedTotal)
else
    countZ = undefined
endif

if totalGrains > 0
    meanDurReal = sumGrainDur / totalGrains
else
    meanDurReal = 0
    minFreqReal = 0
endif

appendInfoLine: ""
appendInfoLine: "Poisson points: ", totalPoints, " | expected: ", fixed$(expectedTotal, 1), " | count z: ", fixed$(countZ, 2)
appendInfoLine: "Rendered grains: ", totalGrains
if nIntervals > 0
    appendInfoLine: "Normalized IOI lambda*dt: mean ", fixed$(meanNormIOI, 3), " | CV ", fixed$(cvNormIOI, 3), " | Exp(1) target = 1, 1"
endif
appendInfoLine: "Anti-alias frequency fits: ", antiAliasFits

# ============================================================================
# 6. Global fade
# ============================================================================
appendInfoLine: "Applying envelope..."
if fade_time_s > 0
    selectObject: outputSound
    Formula: "if x < fade_time_s then self * (x / fade_time_s) else self fi"
    fadeOutStart = duration_s - fade_time_s
    Formula: "if x > fadeOutStart then self * ((duration_s - x) / fade_time_s) else self fi"
endif

# ============================================================================
# 7. Spatial processing
# ============================================================================
if spatial_mode = 2
    appendInfoLine: "Creating sample-rate-aware stereo width..."

    leftTop = min(4000, safeTop)
    rightLow = min(200, 0.1 * safeTop)
    rightTop = min(8000, safeTop)
    smoothHz = min(100, 0.1 * leftTop)

    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Filter (pass Hann band): 0, leftTop, smoothHz
    leftFiltered = selected("Sound")
    removeObject: leftSound
    leftSound = leftFiltered

    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Filter (pass Hann band): rightLow, rightTop, smoothHz
    rightFiltered = selected("Sound")
    removeObject: rightSound
    rightSound = rightFiltered

    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "poisson_" + preset_name$

    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound

elsif spatial_mode = 3
    appendInfoLine: "Creating equal-power rotating stereo..."

    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * cos(0.25 * pi * (1 + sin(twoPi * 0.25 * x)))"

    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * sin(0.25 * pi * (1 + sin(twoPi * 0.25 * x)))"

    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "poisson_" + preset_name$

    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound
else
    selectObject: outputSound
    Rename: "poisson_" + preset_name$
endif

# ============================================================================
# 8. Output normalization / measurement
# ============================================================================
selectObject: outputSound
preNormPeak = Get absolute extremum: 0, 0, "Sinc70"

if normalize_output and preNormPeak > 0
    Scale peak: 0.9
endif

selectObject: outputSound
outputPeak = Get absolute extremum: 0, 0, "Sinc70"
outputRms = Get root-mean-square: 0, 0

if not normalize_output and outputPeak > 1
    appendInfoLine: "WARNING: peak ", fixed$(outputPeak, 3), " exceeds 1; playback/file export may clip."
endif

# ============================================================================
# 9. Visualization, playback, final selection
# ============================================================================
if draw_visualization
    appendInfoLine: "Drawing research visualization..."
    @drawPoissonQC: duration_s
endif

if play_result
    selectObject: outputSound
    Play
endif

selectObject: outputSound
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# =============================================================================
# Procedure: drawPoissonQC
# =============================================================================
procedure drawPoissonQC: .duration

    # Palette
    .ink$ = "{0.18, 0.20, 0.24}"
    .blue$ = "{0.16, 0.42, 0.68}"
    .rust$ = "{0.72, 0.32, 0.20}"
    .grey$ = "{0.50, 0.52, 0.56}"
    .light$ = "{0.965, 0.968, 0.972}"
    .grid$ = "{0.84, 0.85, 0.87}"

    Erase all
    Select outer viewport: 0, 8, 0, 8
    Axes: 0, 1, 0, 1
    Black
    Plain line
    Line width: 1

    # -------------------------------------------------------------------------
    # Header
    # -------------------------------------------------------------------------
    Select outer viewport: 0.35, 7.75, 0.08, 0.62
    Select inner viewport: 0.35, 7.75, 0.08, 0.62
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: .ink$
    Text: 0.5, "centre", 0.68, "half", "##Advanced Poisson Synthesis##"
    Font size: 8
    Colour: .grey$
    Text: 0.5, "centre", 0.12, "half", preset_name$ + "   |   " + synthesis_mode$ + "   |   " + string$(number_of_layers) + " layers   |   " + fixed$(.duration, 2) + " s"

    Select outer viewport: 0.45, 7.65, 0.66, 0.94
    Select inner viewport: 0.45, 7.65, 0.66, 0.94
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: .grey$
    Text: 0.5, "centre", 0.5, "half", "Poisson claim:   lambda * Delta t ~ Exp(1)   |   each point triggers a raised-cosine sinusoidal grain"

    # -------------------------------------------------------------------------
    # Panel A title: actual event raster
    # -------------------------------------------------------------------------
    Select outer viewport: 0.55, 7.65, 1.03, 1.29
    Select inner viewport: 0.55, 7.65, 1.03, 1.29
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: .ink$
    Text: 0, "left", 0.5, "half", "##A  Actual Poisson event realization##"
    Font size: 7
    Colour: .grey$
    Text: 1, "right", 0.5, "half", "ticks = rendered grains; rows = independent layers"

    Select outer viewport: 0.55, 7.65, 1.34, 2.83
    Select inner viewport: 0.78, 7.55, 1.42, 2.72
    Axes: 0, .duration, 0.5, number_of_layers + 0.5

    # light horizontal guides
    Colour: .grid$
    Line width: 0.5
    for .layer to number_of_layers
        Draw line: 0, .layer, .duration, .layer
    endfor

    # actual rendered events
    Colour: .blue$
    Line width: 1
    .drawStride = max(1, ceiling(totalGrains / 1200))
    for .i to totalGrains
        if .i - floor(.i / .drawStride) * .drawStride = 0 or .drawStride = 1
            .ey = eventLayer[.i]
            Draw line: eventTime[.i], .ey - 0.24, eventTime[.i], .ey + 0.24
        endif
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 8
    Marks left every: 1, 1, "yes", "yes", "no"
    Marks bottom every: 1, max(0.5, .duration / 8), "yes", "yes", "no"
    Font size: 9
    Text left: "yes", "Layer"
    Text bottom: "yes", "Time (s)"

    # -------------------------------------------------------------------------
    # Panel B title: normalized IOI density
    # -------------------------------------------------------------------------
    Select outer viewport: 0.55, 7.65, 3.05, 3.31
    Select inner viewport: 0.55, 7.65, 3.05, 3.31
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: .ink$
    Text: 0, "left", 0.5, "half", "##B  Poisson timing QC##"
    Font size: 7
    Colour: .grey$
    Text: 1, "right", 0.5, "half", "measured normalized IOIs vs theoretical Exp(1)"

    .histMaxDensity = 0
    if histUsed > 0
        for .bin to nHistBins
            .density = histCount[.bin] / (histUsed * histBinWidth)
            .histMaxDensity = max(.histMaxDensity, .density)
        endfor
    endif
    .histY = max(1.15, 1.12 * .histMaxDensity)

    Select outer viewport: 0.55, 7.65, 3.36, 4.89
    Select inner viewport: 0.78, 7.55, 3.44, 4.78
    Axes: 0, histMaxZ, 0, .histY

    # measured histogram
    if histUsed > 0
        Colour: "{0.72, 0.80, 0.88}"
        for .bin to nHistBins
            .x0 = (.bin - 1) * histBinWidth
            .x1 = .bin * histBinWidth
            .density = histCount[.bin] / (histUsed * histBinWidth)
            Paint rectangle: "{0.72, 0.80, 0.88}", .x0, .x1, 0, .density
        endfor
    endif

    # theoretical exponential density exp(-z)
    Colour: .rust$
    Line width: 1.5
    .prevX = 0
    .prevY = 1
    for .k from 1 to 100
        .zx = histMaxZ * .k / 100
        .zy = exp(-.zx)
        Draw line: .prevX, .prevY, .zx, .zy
        .prevX = .zx
        .prevY = .zy
    endfor

    # measured mean marker
    if nIntervals > 0 and meanNormIOI <> undefined
        Colour: .blue$
        Line width: 1.5
        Draw line: meanNormIOI, 0, meanNormIOI, .histY
        Line width: 1
    endif

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 8
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Marks left every: 1, 0.25, "yes", "yes", "no"
    Font size: 9
    Text bottom: "yes", "Normalized interval  lambda * Delta t"
    Text left: "yes", "Density"

    # manual legend in data coordinates
    Font size: 7
    Colour: .rust$
    Text: 4.85, "right", 0.94 * .histY, "half", "model  exp(-z)"
    Colour: .blue$
    Text: 4.85, "right", 0.80 * .histY, "half", "blue = measured mean"

    # -------------------------------------------------------------------------
    # Panel C title: measured spectrogram + actual grain model
    # -------------------------------------------------------------------------
    Select outer viewport: 0.55, 7.65, 5.10, 5.36
    Select inner viewport: 0.55, 7.65, 5.10, 5.36
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: .ink$
    Text: 0, "left", 0.5, "half", "##C  Model -> measurement##"
    Font size: 7
    Colour: .grey$
    Text: 1, "right", 0.5, "half", "measured spectrogram with actual grain frequencies and durations"

    # Representative channel: choose the stronger channel by RMS.
    selectObject: outputSound
    .nch = Get number of channels
    if .nch > 1
        Extract one channel: 1
        .ch1 = selected("Sound")
        .rms1 = Get root-mean-square: 0, 0

        selectObject: outputSound
        Extract one channel: 2
        .ch2 = selected("Sound")
        .rms2 = Get root-mean-square: 0, 0

        if .rms2 > .rms1
            removeObject: .ch1
            .disp = .ch2
            .channelLabel$ = "R"
        else
            removeObject: .ch2
            .disp = .ch1
            .channelLabel$ = "L"
        endif
    else
        selectObject: outputSound
        Copy: "disp_" + uid$
        .disp = selected("Sound")
        .channelLabel$ = "mono"
    endif

    if maxFreqReal > 0
        .specTop = min(safeTop, max(1000, 1.25 * maxFreqReal))
    else
        .specTop = min(safeTop, 2000)
    endif

    Select outer viewport: 0.55, 7.65, 5.41, 7.08
    Select inner viewport: 0.78, 7.55, 5.49, 6.97
    selectObject: .disp
    To Spectrogram: 0.03, .specTop, 0.005, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: .spec

    # IMPORTANT: Paint/Text can alter Picture state; reselect viewport and axes.
    Select inner viewport: 0.78, 7.55, 5.49, 6.97
    Axes: 0, .duration, 0, .specTop

    # Overlay actual rendered grain trajectories, subsampled only for legibility.
    Colour: .rust$
    Line width: 1
    .grainStride = max(1, ceiling(totalGrains / 450))
    for .i to totalGrains
        if .i - floor(.i / .grainStride) * .grainStride = 0 or .grainStride = 1
            if eventFreq[.i] <= .specTop
                Draw line: eventTime[.i], eventFreq[.i], min(.duration, eventTime[.i] + eventDur[.i]), eventFreq[.i]
            endif
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 8
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, max(0.5, .duration / 8), "yes", "yes", "no"
    Font size: 9
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Frequency (Hz)"

    # channel label / overlay explanation
    Font size: 7
    Colour: .rust$
    Text: 0.98 * .duration, "right", 0.94 * .specTop, "half", "rust = generated grains"
    Colour: .grey$
    Text: 0.98 * .duration, "right", 0.84 * .specTop, "half", "display channel: " + .channelLabel$

    removeObject: .disp

    # -------------------------------------------------------------------------
    # Bottom QC dashboard
    # -------------------------------------------------------------------------
    if spatial_mode = 2
        .spatial$ = "Stereo Wide"
    elsif spatial_mode = 3
        .spatial$ = "Rotating"
    else
        .spatial$ = "Mono"
    endif

    if random_seed > 0
        .seed$ = string$(random_seed)
    else
        .seed$ = "random"
    endif

    Select outer viewport: 0.45, 7.65, 7.30, 7.88
    Select inner viewport: 0.45, 7.65, 7.30, 7.88
    Axes: 0, 1, 0, 1
    Paint rectangle: .light$, 0, 1, 0, 1
    Colour: "{0.78, 0.79, 0.81}"
    Draw inner box

    Font size: 7
    Colour: .ink$
    if nIntervals > 0
        .line1$ = "POISSON QC   N=" + string$(totalPoints) + "  E[N]=" + fixed$(expectedTotal, 1) + "  count z=" + fixed$(countZ, 2) + "   |   mean(lambda dt)=" + fixed$(meanNormIOI, 3) + "  CV=" + fixed$(cvNormIOI, 3) + "   [target 1, 1]"
    else
        .line1$ = "POISSON QC   N=" + string$(totalPoints) + "  E[N]=" + fixed$(expectedTotal, 1) + "  count z=" + fixed$(countZ, 2) + "   |   too few intervals for IOI QC"
    endif
    Text: 0.02, "left", 0.68, "half", .line1$

    if totalGrains > 0
        .freq$ = fixed$(minFreqReal, 0) + "-" + fixed$(maxFreqReal, 0) + " Hz"
    else
        .freq$ = "no rendered grains"
    endif
    .line2$ = "RENDER   grains=" + string$(totalGrains) + "   |   f=" + .freq$ + "   |   mean dur=" + fixed$(1000 * meanDurReal, 1) + " ms   |   " + .spatial$ + "   |   peak=" + fixed$(outputPeak, 3) + "   |   AA fits=" + string$(antiAliasFits) + "   |   seed=" + .seed$
    Colour: .grey$
    Text: 0.02, "left", 0.28, "half", .line2$

    Font size: 10
    Colour: "Black"
    Line width: 1
endproc
