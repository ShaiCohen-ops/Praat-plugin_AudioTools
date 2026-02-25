# ============================================================
# Praat AudioTools - Granular_Attention_Resynth.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.0 (2025)
# License: MIT License
#
# Description:
#   Granular Attention Re-synthesis — grains compete for
#   being chosen (selection), not for gain.
#
#   CONCEPT:
#   ReLU + Softmax applied to GRAIN SELECTION, not filtering.
#   The source re-synthesizes itself from its own most
#   energetic (or most transient) moments. At high temperature
#   this becomes motif extraction / crystallized stutter.
#   At low temperature it becomes a textural self-remix.
#
#   PIPELINE:
#   1. Extract N candidate grains (sliding window, candHop)
#      scored by: RMS power, transient slope, or mixed
#   2. ReLU gate: grains below (meanScore + floor_dB) → score=0
#   3. Softmax with temperature α:
#        gated[i]  = score[i] * (score[i] above floor)
#        w[i]      = exp(gated[i] / meanGated * α)   (log-sum-exp)
#        prob[i]   = w[i] / Σw
#      → probability distribution over candidate grains
#   4. Build cumulative CDF for inverse-transform sampling
#   5. Synthesis: for each output hop position:
#        - draw grain index from CDF (weighted random)
#        - recency penalty: last 3 grains less likely to repeat
#        - apply Hanning window to selected grain copy
#        - optional pitch micro-jitter (resample ± semitones)
#        - optional time jitter (± ms)
#        - OLA: Shift times by outputPosition + jitter
#               Formula: outBuf += object[grainCopy]
#               hannEnv += object[hannGrainCopy]
#   6. Normalize by accumulated Hanning envelope (OLA correct)
#   7. Wet/dry blend
#
#   SCORE TYPES:
#   RMS      — energy competition: loudest events repeat
#   Transient — slope competition: attacks/onsets repeat
#   Mixed    — weighted blend: control transient_weight
#
#   MUSICAL EFFECTS BY α:
#   α 1-3:  gentle self-remix, all grains roughly equally chosen
#   α 5-10: energetic moments dominate, texture crystallizes
#   α 15+:  winner-take-most: a few grains repeat obsessively
#           → motif extraction, stutter loops, self-quotation
#
# Category: Granular / Composition / Experimental
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

srcID    = selected("Sound")
srcName$ = selected$("Sound")
selectObject: srcID
srcDur = Get total duration
srcSr  = Get sampling frequency
srcCh  = Get number of channels

if srcDur < 0.05
    exitScript: "Sound must be at least 50 ms."
endif

# ============================================================
# FORM
# ============================================================

form Granular Attention Re-synthesis v1.0
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Self-Remix      (gentle, textural, most grains used)
        option Crystallize     (high α, dense repeats, few grains)
        option Motif Extract   (very high α, stutter of strongest)
        option Onset Harvest   (transient score, attacks repeat)
        option Shimmer         (small grains, light jitter, low α)
        option Slabs            (large grains 300ms, slow mosaic)
        option Cloud            (very large grains 600ms, drifting layers)
    comment === Grain Parameters ===
    positive Grain_size_ms 150.0
    positive Synthesis_hop_ms 50.0
    comment Candidate density (ms between candidate grain starts)
    positive Candidate_hop_ms 20.0
    comment === Competition ===
    positive Temperature 1.0
    comment ReLU floor: dB above mean score (0=at mean, +6=strict, -6=open)
    real Floor_dB 0.0
    comment === Score Type ===
    optionmenu Score_type: 1
        option RMS            (energy: loudest grains repeat)
        option Transient      (slope: attacks/onsets repeat)
        option Mixed          (blend of RMS and Transient)
    real Transient_weight 0.5
    comment === Variation ===
    positive Time_jitter_ms 5.0
    real Pitch_jitter_semitones 0.0
    real Recency_penalty 0.5
    comment === Mix ===
    real Wet_percent 100.0
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================

presetName$ = "Custom"

if preset = 2
    grain_size_ms           = 60.0
    synthesis_hop_ms        = 30.0
    candidate_hop_ms        = 20.0
    temperature             = 3.0
    floor_dB                = -3.0
    score_type              = 1
    transient_weight        = 0.3
    time_jitter_ms          = 8.0
    pitch_jitter_semitones  = 0.0
    recency_penalty         = 0.3
    wet_percent             = 100.0
    presetName$             = "SelfRemix"
elsif preset = 3
    grain_size_ms           = 40.0
    synthesis_hop_ms        = 20.0
    candidate_hop_ms        = 15.0
    temperature             = 12.0
    floor_dB                = 3.0
    score_type              = 1
    transient_weight        = 0.2
    time_jitter_ms          = 3.0
    pitch_jitter_semitones  = 0.0
    recency_penalty         = 0.4
    wet_percent             = 100.0
    presetName$             = "Crystallize"
elsif preset = 4
    grain_size_ms           = 30.0
    synthesis_hop_ms        = 15.0
    candidate_hop_ms        = 10.0
    temperature             = 25.0
    floor_dB                = 6.0
    score_type              = 1
    transient_weight        = 0.0
    time_jitter_ms          = 1.0
    pitch_jitter_semitones  = 0.0
    recency_penalty         = 0.6
    wet_percent             = 100.0
    presetName$             = "MotifExtract"
elsif preset = 5
    grain_size_ms           = 50.0
    synthesis_hop_ms        = 25.0
    candidate_hop_ms        = 15.0
    temperature             = 8.0
    floor_dB                = 2.0
    score_type              = 2
    transient_weight        = 1.0
    time_jitter_ms          = 5.0
    pitch_jitter_semitones  = 0.0
    recency_penalty         = 0.4
    wet_percent             = 100.0
    presetName$             = "OnsetHarvest"
elsif preset = 6
    grain_size_ms           = 20.0
    synthesis_hop_ms        = 10.0
    candidate_hop_ms        = 10.0
    temperature             = 2.0
    floor_dB                = -6.0
    score_type              = 1
    transient_weight        = 0.2
    time_jitter_ms          = 4.0
    pitch_jitter_semitones  = 0.3
    recency_penalty         = 0.2
    wet_percent             = 85.0
    presetName$             = "Shimmer"
elsif preset = 7
    grain_size_ms           = 300.0
    synthesis_hop_ms        = 150.0
    candidate_hop_ms        = 50.0
    temperature             = 10.0
    floor_dB                = 2.0
    score_type              = 1
    transient_weight        = 0.0
    time_jitter_ms          = 15.0
    pitch_jitter_semitones  = 0.0
    recency_penalty         = 0.5
    wet_percent             = 100.0
    presetName$             = "Slabs"
elsif preset = 8
    grain_size_ms           = 600.0
    synthesis_hop_ms        = 300.0
    candidate_hop_ms        = 80.0
    temperature             = 4.0
    floor_dB                = -3.0
    score_type              = 3
    transient_weight        = 0.4
    time_jitter_ms          = 30.0
    pitch_jitter_semitones  = 0.0
    recency_penalty         = 0.3
    wet_percent             = 90.0
    presetName$             = "Cloud"
endif

# ============================================================
# CLAMPS + DERIVED PARAMETERS
# ============================================================

if grain_size_ms < 5.0
    grain_size_ms = 5.0
endif
if grain_size_ms > 1000.0
    grain_size_ms = 1000.0
endif
if synthesis_hop_ms < 1.0
    synthesis_hop_ms = 1.0
endif
# Enforce overlap: hop should be <= grain/2 for stable Hann OLA
if synthesis_hop_ms > grain_size_ms / 2
    synthesis_hop_ms = grain_size_ms / 2
endif
if candidate_hop_ms < 1.0
    candidate_hop_ms = 1.0
endif
if temperature < 0.01
    temperature = 0.01
endif
if transient_weight < 0.0
    transient_weight = 0.0
endif
if transient_weight > 1.0
    transient_weight = 1.0
endif
if time_jitter_ms < 0.0
    time_jitter_ms = 0.0
endif
if pitch_jitter_semitones < 0.0
    pitch_jitter_semitones = 0.0
endif
if pitch_jitter_semitones > 4.0
    pitch_jitter_semitones = 4.0
endif
if recency_penalty < 0.0
    recency_penalty = 0.0
endif
if recency_penalty > 1.0
    recency_penalty = 1.0
endif
if wet_percent < 0.0
    wet_percent = 0.0
endif
if wet_percent > 100.0
    wet_percent = 100.0
endif

grainDur    = grain_size_ms    / 1000.0
synthHop    = synthesis_hop_ms / 1000.0
candHop     = candidate_hop_ms / 1000.0
timeJitter  = time_jitter_ms   / 1000.0
wetLevel    = wet_percent / 100.0
dryLevel    = 1.0 - wetLevel

# ============================================================
# PREPARE MONO
# ============================================================

clearinfo
writeInfoLine:  "=================================================="
writeInfoLine:  "  Granular Attention Re-synthesis v1.0"
writeInfoLine:  "=================================================="
appendInfoLine: ""
appendInfoLine: "Source   : ", srcName$, "  (", fixed$(srcDur, 3), " s)"
appendInfoLine: "Preset   : ", presetName$
appendInfoLine: "Grain    : ", fixed$(grain_size_ms, 1), " ms  hop: ", fixed$(synthesis_hop_ms, 1), " ms"
appendInfoLine: "Temp α   : ", fixed$(temperature, 2)
appendInfoLine: "Floor    : mean + ", fixed$(floor_dB, 1), " dB"
if score_type = 1
    appendInfoLine: "Score    : RMS energy"
elsif score_type = 2
    appendInfoLine: "Score    : Transient slope"
else
    appendInfoLine: "Score    : Mixed (transient weight=", fixed$(transient_weight, 2), ")"
endif
appendInfoLine: "Jitter   : ±", fixed$(time_jitter_ms, 1), " ms  pitch: ±", fixed$(pitch_jitter_semitones, 2), " st"
appendInfoLine: ""

selectObject: srcID
if srcCh > 1
    monoSrc = Convert to mono
else
    monoSrc = Copy: "gar_mono"
endif
selectObject: monoSrc
Scale peak: 0.99

# ============================================================
# PHASE 1: EXTRACT + SCORE ALL CANDIDATE GRAINS
# ============================================================

appendInfoLine: "[1/4] Extracting and scoring candidate grains..."

nCandGrains = floor((srcDur - grainDur) / candHop) + 1
if nCandGrains < 2
    nCandGrains = 2
endif

appendInfoLine: "  Candidates: ", nCandGrains, "  (", fixed$(candHop * 1000, 1), " ms hop)"

rmsScore#     = zero#(nCandGrains)
grainStartTime# = zero#(nCandGrains)

for ii from 1 to nCandGrains
    tStart = (ii - 1) * candHop
    tEnd   = tStart + grainDur
    if tEnd > srcDur
        tEnd = srcDur
    endif
    grainStartTime#[ii] = tStart

    selectObject: monoSrc
    gSnd = Extract part: tStart, tEnd, "rectangular", 1, "no"
    selectObject: gSnd
    rms = Get root-mean-square: 0, 0
    removeObject: gSnd

    if rms < 1e-9
        rms = 1e-9
    endif
    rmsScore#[ii] = rms * rms
endfor

# Compute transient scores (first derivative of RMS energy)
transScore# = zero#(nCandGrains)
transScore#[1] = 0
for ii from 2 to nCandGrains
    diff = rmsScore#[ii] - rmsScore#[ii - 1]
    if diff < 0
        diff = -diff
    endif
    transScore#[ii] = diff
endfor

# Normalize transient scores to same range as RMS for mixing
maxTrans = transScore#[1]
for ii from 2 to nCandGrains
    if transScore#[ii] > maxTrans
        maxTrans = transScore#[ii]
    endif
endfor
maxRMS = rmsScore#[1]
for ii from 2 to nCandGrains
    if rmsScore#[ii] > maxRMS
        maxRMS = rmsScore#[ii]
    endif
endfor
if maxTrans < 1e-30
    maxTrans = 1e-30
endif
if maxRMS < 1e-30
    maxRMS = 1e-30
endif

# Build combined score
rawScore# = zero#(nCandGrains)
for ii from 1 to nCandGrains
    rmsN   = rmsScore#[ii]   / maxRMS
    transN = transScore#[ii] / maxTrans
    if score_type = 1
        rawScore#[ii] = rmsN
    elsif score_type = 2
        rawScore#[ii] = transN
    else
        rawScore#[ii] = rmsN * (1 - transient_weight) + transN * transient_weight
    endif
endfor

# ============================================================
# PHASE 2: RELU + SOFTMAX COMPETITION
# ============================================================

appendInfoLine: "[2/4] Computing grain selection probabilities..."

# Mean of raw scores in linear space
sumS = 0
for ii from 1 to nCandGrains
    sumS = sumS + rawScore#[ii]
endfor
meanScore = sumS / nCandGrains
if meanScore < 1e-30
    meanScore = 1e-30
endif

# Floor in same (normalized linear) units
# floor_dB offset → multiplicative threshold = 10^(floor_dB/10)
floorFactor = 10 ^ (floor_dB / 10)
floorValue  = meanScore * floorFactor

# ReLU gate: zero out grains below floor
gated# = zero#(nCandGrains)
nActive = 0
for ii from 1 to nCandGrains
    if rawScore#[ii] >= floorValue
        gated#[ii] = rawScore#[ii]
        nActive     = nActive + 1
    endif
endfor

# If all suppressed, open gate fully
if nActive = 0
    for ii from 1 to nCandGrains
        gated#[ii] = rawScore#[ii]
    endfor
    nActive = nCandGrains
endif

# Softmax on linear gated scores, normalised by meanScore
# log-sum-exp: subtract max before exponentiation
maxGated = gated#[1]
for ii from 2 to nCandGrains
    if gated#[ii] > maxGated
        maxGated = gated#[ii]
    endif
endfor
if maxGated < 1e-30
    maxGated = 1e-30
endif

softNum# = zero#(nCandGrains)
softSum  = 0
for ii from 1 to nCandGrains
    arg = (gated#[ii] - maxGated) / meanScore * temperature
    if arg < -500
        arg = -500
    endif
    sw = exp(arg)
    softNum#[ii] = sw
    softSum       = softSum + sw
endfor
if softSum < 1e-30
    softSum = 1e-30
endif

prob# = zero#(nCandGrains)
for ii from 1 to nCandGrains
    prob#[ii] = softNum#[ii] / softSum
endfor

# Build cumulative distribution for inverse-transform sampling
cdf# = zero#(nCandGrains)
cdf#[1] = prob#[1]
for ii from 2 to nCandGrains
    cdf#[ii] = cdf#[ii - 1] + prob#[ii]
endfor
# Ensure last bin sums exactly to 1.0
cdf#[nCandGrains] = 1.0

appendInfoLine: "  Active grains: ", nActive, "/", nCandGrains
appendInfoLine: "  Mean score: ", fixed$(meanScore, 6),
    ... "  Floor: ", fixed$(floorValue, 6)

# ============================================================
# HELPER: DRAW GRAIN FROM CDF WITH RECENCY PENALTY
# Returns: selectedGrainIdx (1-based)
# Uses globals: cdf#, prob#, nCandGrains, recency_penalty
# Recency state: lastGrain1, lastGrain2, lastGrain3
# ============================================================

procedure drawGrain
    # Build penalized CDF
    penSum = 0
    for .ii from 1 to nCandGrains
        penP = prob#[.ii]
        if .ii = lastGrain1
            penP = penP * (1 - recency_penalty)
        endif
        if .ii = lastGrain2
            penP = penP * (1 - recency_penalty * 0.6)
        endif
        if .ii = lastGrain3
            penP = penP * (1 - recency_penalty * 0.3)
        endif
        if penP < 0
            penP = 0
        endif
        penProb_'.ii' = penP
        penSum = penSum + penP
    endfor
    if penSum < 1e-30
        penSum = 1e-30
    endif

    # Walk CDF until cumulative sum exceeds uniform random draw
    r = randomUniform(0, 1)
    cumP = 0
    selected = nCandGrains
    for .ii from 1 to nCandGrains
        cumP = cumP + penProb_'.ii' / penSum
        if cumP >= r and selected = nCandGrains
            selected = .ii
        endif
    endfor

    drawGrain.index = selected

    # Update recency ring
    lastGrain3 = lastGrain2
    lastGrain2 = lastGrain1
    lastGrain1 = selected
endproc

# ============================================================
# PHASE 3: SYNTHESIS — Concatenate with overlap
# ============================================================
# Architecture: collect all windowed grains, then call
# Praat's built-in Concatenate with overlap ONCE.
# Avoids all manual OLA/envelope accumulation complexity.
# Output length = nOutputHops * synthHop + (grainDur - synthHop)
# trimmed to srcDur.
# ============================================================

appendInfoLine: "[3/4] Synthesizing output..."

nOutputHops = floor(srcDur / synthHop) + 1
overlapDur  = grainDur - synthHop
if overlapDur < 0
    overlapDur = 0
endif

# Recency state
lastGrain1 = 0
lastGrain2 = 0
lastGrain3 = 0

# Per-hop grain choice log for visualization
chosenGrain# = zero#(nOutputHops)

appendInfoLine: "  Hops: ", nOutputHops,
    ... "  overlap per grain: ", fixed$(overlapDur * 1000, 1), " ms"

for hop from 1 to nOutputHops
    # Select grain
    @drawGrain
    chosen = drawGrain.index
    chosenGrain#[hop] = chosen

    # Extract grain with Hanning window applied by Praat
    origStart = grainStartTime#[chosen]
    tGEnd = origStart + grainDur
    if tGEnd > srcDur
        tGEnd = srcDur
    endif
    selectObject: monoSrc
    grainCopy = Extract part: origStart, tGEnd, "Hanning", 1, "no"

    # Pitch micro-jitter: resample then trim/pad back to exact grainDur
    # so all grains have identical length for uniform-hop concatenation
    if pitch_jitter_semitones > 0.001
        pitchShift = randomUniform(-pitch_jitter_semitones, pitch_jitter_semitones)
        # Shift pitch UP by shifting SR down (and vice versa)
        shiftFactor = 2 ^ (pitchShift / 12)
        interpSr = round(srcSr / shiftFactor)
        if interpSr < 1000
            interpSr = 1000
        endif
        if interpSr > 200000
            interpSr = 200000
        endif
        selectObject: grainCopy
        pitched = Resample: interpSr, 10
        removeObject: grainCopy
        # Override SR back to srcSr: pitch shifted, duration unchanged
        selectObject: pitched
        Override sampling frequency: srcSr
        grainCopy = pitched
    endif

    # Store grain ID for later concatenation
    grainID_'hop' = grainCopy

    if hop mod 50 = 0
        appendInfoLine: "  Grain ", hop, "/", nOutputHops,
            ... "  (", fixed$(100 * hop / nOutputHops, 0), "%)"
    endif
endfor

appendInfoLine: "  Grain ", nOutputHops, "/", nOutputHops, " (100%)"

# --- Single Concatenate with overlap ---
# Select all grains (stored IDs), then Praat does one O(n) C-level concat
selectObject: grainID_1
for hop from 2 to nOutputHops
    plusObject: grainID_'hop'
endfor

appendInfoLine: "  Concatenating with ", fixed$(overlapDur * 1000, 1), " ms overlap..."
concatResult = Concatenate with overlap: overlapDur

# Cleanup all grain copies
for hop from 1 to nOutputHops
    removeObject: grainID_'hop'
endfor

# Trim to srcDur (concat may be slightly longer)
selectObject: concatResult
concatDur = Get total duration
if concatDur > srcDur
    trimmed = Extract part: 0, srcDur, "rectangular", 1, "no"
    removeObject: concatResult
    concatResult = trimmed
endif

# ============================================================
# WET / DRY MIX
# ============================================================

if dryLevel > 0.001
    selectObject: monoSrc
    dryCopy  = Copy: "gar_dry"

    # Pad dry to match concatResult duration if needed
    selectObject: concatResult
    wetDur = Get total duration
    selectObject: dryCopy
    dryDur = Get total duration
    if abs(wetDur - dryDur) > 0.005
        if dryDur < wetDur
            Create Sound from formula: "dry_pad", 1, 0, wetDur - dryDur, srcSr, "0"
            padSnd = selected("Sound")
            selectObject: dryCopy
            plusObject: padSnd
            paddedDry = Concatenate
            removeObject: dryCopy, padSnd
            dryCopy = paddedDry
        else
            selectObject: dryCopy
            trimDry = Extract part: 0, wetDur, "rectangular", 1, "no"
            removeObject: dryCopy
            dryCopy = trimDry
        endif
    endif

    wetStr$ = fixed$(wetLevel, 6)
    dryStr$ = fixed$(dryLevel, 6)
    dryID$  = string$(dryCopy)
    selectObject: concatResult
    Formula: "self * " + wetStr$ + " + object[" + dryID$ + "] * " + dryStr$
    removeObject: dryCopy
endif

# ============================================================
# FINALIZE
# ============================================================

selectObject: concatResult
peakVal = Get absolute extremum: 0, 0, "None"
if peakVal > 0.001
    Scale peak: 0.99
endif
outputName$ = srcName$ + "_GAR_" + presetName$
Rename: outputName$
resultID  = selected("Sound")
resultDur = Get total duration

removeObject: monoSrc

appendInfoLine: ""
appendInfoLine: "Output: ", outputName$
appendInfoLine: "Duration: ", fixed$(resultDur, 3), " s"

# ============================================================
# GRAIN USAGE STATISTICS
# ============================================================

for ii from 1 to nCandGrains
    usageCount_'ii' = 0
endfor
for hop from 1 to nOutputHops
    idx = chosenGrain#[hop]
    if idx >= 1 and idx <= nCandGrains
        usageCount_'idx' = usageCount_'idx' + 1
    endif
endfor

maxUsage    = 0
usedGrains  = 0
for ii from 1 to nCandGrains
    c = usageCount_'ii'
    if c > 0
        usedGrains = usedGrains + 1
    endif
    if c > maxUsage
        maxUsage    = c
        maxUsageIdx = ii
    endif
endfor

appendInfoLine: ""
appendInfoLine: "Unique grains used : ", usedGrains, "/", nCandGrains
appendInfoLine: "Most-used grain    : #", maxUsageIdx,
    ... " at t=", fixed$(grainStartTime#[maxUsageIdx], 3), " s  (used ", maxUsage, " times)"

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization = 1

    selectObject: srcID
    srcPeak = Get absolute extremum: 0, 0, "None"
    if srcPeak < 0.001
        srcPeak = 0.001
    endif
    ampMax = srcPeak * 1.15

    Erase all

    # === TITLE ===
    Select outer viewport: 0, 8, 0, 0.46
    Axes: 0, 1, 0, 1
    Font size: 11
    Colour: "Black"
    Text: 0.5, "centre", 0.73, "half", "##Granular Attention Re-synthesis v1.0##"
    Font size: 7.5
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -0.08, "half",
        ... "[" + presetName$ + "]  " + srcName$
        ... + "  |  α=" + fixed$(temperature, 1)
        ... + "  floor=mean+" + fixed$(floor_dB, 0) + "dB"
        ... + "  grain=" + fixed$(grain_size_ms, 0) + "ms"
        ... + "  hop=" + fixed$(synthesis_hop_ms, 0) + "ms"
        ... + "  unique=" + string$(usedGrains) + "/" + string$(nCandGrains)

    # === Panel 1: Input waveform ===
    Select outer viewport: 0, 8, 0.50, 1.33
    Select inner viewport: 0.58, 7.65, 0.55, 1.28
    Axes: 0, srcDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, srcDur, -ampMax, ampMax
    Colour: "{0.80, 0.80, 0.80}"
    Draw line: 0, 0, srcDur, 0
    selectObject: srcID
    Colour: "{0.45, 0.50, 0.58}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"
    Text top: "no", "Original waveform"

    # === Panel 2: Output waveform ===
    Select outer viewport: 0, 8, 1.36, 2.18
    Select inner viewport: 0.58, 7.65, 1.41, 2.13
    Axes: 0, resultDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, resultDur, -ampMax, ampMax
    Colour: "{0.80, 0.80, 0.80}"
    Draw line: 0, 0, resultDur, 0
    selectObject: resultID
    Colour: "{0.22, 0.50, 0.68}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text top: "no", outputName$
    Text bottom: "yes", "Time (s)"

    # === Panel 3: Grain score landscape + probability ===
    Select outer viewport: 0, 8, 2.25, 3.22
    Select inner viewport: 0.58, 7.65, 2.30, 3.17

    # Normalise scores for display
    maxRawScore = rawScore#[1]
    minRawScore = rawScore#[1]
    for ii from 2 to nCandGrains
        if rawScore#[ii] > maxRawScore
            maxRawScore = rawScore#[ii]
        endif
        if rawScore#[ii] < minRawScore
            minRawScore = rawScore#[ii]
        endif
    endfor
    rawRange = maxRawScore - minRawScore
    if rawRange < 1e-10
        rawRange = 1e-10
    endif

    maxProb = prob#[1]
    for ii from 2 to nCandGrains
        if prob#[ii] > maxProb
            maxProb = prob#[ii]
        endif
    endfor
    if maxProb < 1e-10
        maxProb = 1e-10
    endif

    Axes: 0, srcDur, -0.08, 1.30
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, srcDur, -0.08, 1.30

    # Floor line
    floorNorm = (floorValue - minRawScore) / rawRange
    if floorNorm < 0
        floorNorm = 0
    endif
    if floorNorm > 1
        floorNorm = 1
    endif
    Colour: "{0.88, 0.55, 0.18}"
    Dotted line
    Draw line: 0, floorNorm, srcDur, floorNorm
    Solid line
    Font size: 5
    Text: srcDur * 0.01, "left", floorNorm + 0.04, "half",
        ... "ReLU floor"

    # Score bars (grey)
    for ii from 1 to nCandGrains
        x = grainStartTime#[ii]
        h = (rawScore#[ii] - minRawScore) / rawRange
        Colour: "{0.78, 0.78, 0.84}"
        Draw line: x, 0, x, h
    endfor

    # Probability overlay (blue, scaled to same axis)
    Colour: "{0.20, 0.48, 0.75}"
    Line width: 1.5
    for ii from 2 to nCandGrains
        x1 = grainStartTime#[ii - 1]
        x2 = grainStartTime#[ii]
        y1 = prob#[ii - 1] / maxProb
        y2 = prob#[ii]     / maxProb
        Draw line: x1, y1, x2, y2
    endfor
    Line width: 1

    # Usage count: size of circle = how often this grain was chosen
    if maxUsage > 0
        for ii from 1 to nCandGrains
            c = usageCount_'ii'
            if c > 0
                x = grainStartTime#[ii]
                r = c / maxUsage * 1.4 + 0.3
                Colour: "{0.85, 0.38, 0.18}"
                Paint circle (mm): "{0.85, 0.38, 0.18}", x, prob#[ii] / maxProb, r
            endif
        endfor
    endif

    Font size: 5
    Colour: "{0.78, 0.78, 0.84}"
    Text: srcDur * 0.79, "left", 1.22, "half", "score"
    Colour: "{0.20, 0.48, 0.75}"
    Text: srcDur * 0.79, "left", 1.10, "half", "probability"
    Colour: "{0.85, 0.38, 0.18}"
    Text: srcDur * 0.79, "left", 0.98, "half", "usage (size)"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Score"
    Text top: "no", "Grain score / probability / usage   (orange dot = chosen, size = frequency)"

    # === Panel 4: Grain selection sequence ===
    Select outer viewport: 0, 8, 3.28, 4.22
    Select inner viewport: 0.58, 7.65, 3.33, 4.17

    dispHops = nOutputHops
    if dispHops > 200
        dispHops = 200
    endif

    Axes: 0, dispHops + 1, 0, nCandGrains + 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, dispHops + 1, 0, nCandGrains + 1

    # Color by score value
    for hop from 1 to dispHops
        idx = chosenGrain#[hop]
        if idx >= 1 and idx <= nCandGrains
            scoreFrac = (rawScore#[idx] - minRawScore) / rawRange
            cR = 0.15 + scoreFrac * 0.65
            cG = 0.45 + scoreFrac * 0.15
            cB = 0.80 - scoreFrac * 0.58
            Paint rectangle: "{" + fixed$(cR, 2) + "," + fixed$(cG, 2) + "," + fixed$(cB, 2) + "}",
                ... hop - 0.48, hop + 0.48, idx - 0.48, idx + 0.48
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Grain #"
    Text bottom: "yes", "Output hop"
    Text top: "no", "Grain selection sequence  (blue=low score  orange=high score)"

    # === Panel 5: Usage histogram ===
    Select outer viewport: 0, 4, 4.28, 5.10
    Select inner viewport: 0.55, 3.75, 4.33, 5.05
    Axes: 0, nCandGrains + 1, 0, maxUsage * 1.15
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, nCandGrains + 1, 0, maxUsage * 1.15

    meanUsage = nOutputHops / nCandGrains
    Colour: "{0.85, 0.85, 0.85}"
    Dotted line
    Draw line: 0, meanUsage, nCandGrains + 1, meanUsage
    Solid line

    for ii from 1 to nCandGrains
        c = usageCount_'ii'
        if c > 0
            scoreFrac = (rawScore#[ii] - minRawScore) / rawRange
            cR = 0.15 + scoreFrac * 0.65
            cG = 0.45 + scoreFrac * 0.15
            cB = 0.80 - scoreFrac * 0.58
            Paint rectangle: "{" + fixed$(cR, 2) + "," + fixed$(cG, 2) + "," + fixed$(cB, 2) + "}",
                ... ii - 0.45, ii + 0.45, 0, c
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Count"
    Text bottom: "yes", "Grain #"
    Text top: "no", "Usage histogram  (dashed = uniform mean)"

    # === Panel 6: Stats ===
    Select outer viewport: 4, 8, 4.28, 5.10
    Select inner viewport: 4.18, 7.65, 4.33, 5.05
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.04, "left", 0.90, "half", "##Granular Attention Re-synthesis v1.0##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.38}"
    Text: 0.04, "left", 0.71, "half",
        ... "Preset: " + presetName$
        ... + "  |  α=" + fixed$(temperature, 1)
        ... + "  floor=mean+" + fixed$(floor_dB, 0) + "dB"
    Text: 0.04, "left", 0.53, "half",
        ... "Grain=" + fixed$(grain_size_ms, 0) + "ms"
        ... + "  hop=" + fixed$(synthesis_hop_ms, 0) + "ms"
        ... + "  cand=" + string$(nCandGrains)
        ... + "  active=" + string$(nActive)
    Text: 0.04, "left", 0.35, "half",
        ... "Unique used: " + string$(usedGrains) + "/" + string$(nCandGrains)
        ... + "  (" + fixed$(100 * usedGrains / nCandGrains, 0) + "%)"
    Text: 0.04, "left", 0.17, "half",
        ... "Top grain: #" + string$(maxUsageIdx)
        ... + "  t=" + fixed$(grainStartTime#[maxUsageIdx], 2) + "s"
        ... + "  used " + string$(maxUsage) + "×"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================
# OUTPUT
# ============================================================

selectObject: resultID

appendInfoLine: ""
appendInfoLine: "=================================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=================================================="
appendInfoLine: "Output  : ", outputName$
appendInfoLine: "Duration: ", fixed$(resultDur, 3), " s"
appendInfoLine: "Preset  : ", presetName$
appendInfoLine: "α / floor: ", fixed$(temperature, 2), " / mean+", fixed$(floor_dB, 1), " dB"
appendInfoLine: "Hops    : ", nOutputHops
appendInfoLine: "Unique grains used: ", usedGrains, "/", nCandGrains

if play_result = 1
    Play
endif
