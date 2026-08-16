# ============================================================
# Praat AudioTools - Causal_Recomposer.praat
# Causal-model-guided offline grain recomposition
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# WHAT THIS DOES
#   This is a grain re-ordering processor, not a spectral filter
#   or a resynthesizer. It analyses overlapping source grains,
#   fits a compact predictive law between local intensity I and
#   spectral centroid C,
#
#       Chat(t) = f( z(I(t)) )           polynomial order 1-3
#       R(t)    = C(t) - Chat(t)
#
#   and uses one quantity derived from that model as a stable
#   sort key. The source is then reduced to one protected mono
#   grain pool and recomposed TWICE: left and right use the same
#   primary causal sort plus a few channel-specific local swaps.
#   That controlled difference creates stereo from recomposition itself.
#
#   IMPORTANT INTERPRETATION
#   The polynomial is a causal-model reading, not causal
#   identification from observational audio alone. "Lawful" and
#   "anomalous" therefore mean close to / far from this chosen
#   intensity-to-centroid model, not proof of a physical cause.
#
#   The synthesis stage does not filter or synthesize new
#   spectra. A mono source grain pool is extracted with a
#   rectangular window, then only splice edges are gain-tapered
#   for overlap-add. Left and right contain the same grain pool
#   but can place nearby-ranked grains in a slightly different
#   order. Where grains overlap, samples are mixed and normalized
#   by the same window sum.
#
# METHOD NOTES
#   - Analysis and synthesis share one mono grain pool. Multichannel
#     input is averaged to mono; if that average nearly cancels
#     relative to the strongest channel, the script safely falls
#     back to that strongest channel and reports the adjustment.
#   - Stereo divergence is NOT a delay effect. Both sides share the
#     same stable causal order; only the closest adjacent key pairs
#     can be swapped in one channel, chosen by a secondary feature.
#   - The intensity predictor is standardized before polynomial
#     fitting. This keeps order-2/3 normal equations numerically
#     much better conditioned while preserving the polynomial
#     family in the original intensity variable.
#   - If a requested polynomial fit is singular, the order is
#     reduced automatically; a constant model is the final
#     fallback for an intensity-uniform source.
#   - Sorting is stable in BOTH directions: equal keys retain
#     their original chronological order.
#   - Synthesis_overlap controls temporal density/output length.
#     Crossfade_ms controls the actual raised-cosine edge taper
#     and is capped to the available overlap and half a grain.
#
# ============================================================

# === Input Validation ===
nSelected = numberOfSelected("Sound")
if nSelected <> 1
    exitScript: "Please select exactly one Sound object."
endif

snd = selected("Sound")
sndName$ = selected$("Sound")

form Causal Recomposer v1.3
    optionmenu Preset: 1
        option Custom
        option Lawful to Anomalous
        option Anomalous to Lawful
        option Brightness Sweep
    optionmenu Sort_key: 1
        option Model residual magnitude  (lawful -> anomalous)
        option Predicted brightness Chat  (dark -> bright)
        option Signed model residual      (darker -> brighter than predicted)
        option Intensity                  (quiet -> loud)
    optionmenu Sort_direction: 1
        option Ascending
        option Descending
    positive Grain_size_ms 80
    real Analysis_overlap 0.5
    natural Causal_model_order 2
    real Synthesis_overlap 0.5
    real Crossfade_ms 15
    real Stereo_divergence_percent 20
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESET LOGIC
# ============================================================

if preset = 2
    sort_key = 1
    sort_direction = 1
    causal_model_order = 2
    grain_size_ms = 70
    analysis_overlap = 0.5
    synthesis_overlap = 0.4
    crossfade_ms = 20
    presetName$ = "LawfulToAnomalous"
elsif preset = 3
    sort_key = 1
    sort_direction = 2
    causal_model_order = 2
    grain_size_ms = 70
    analysis_overlap = 0.5
    synthesis_overlap = 0.4
    crossfade_ms = 20
    presetName$ = "AnomalousToLawful"
elsif preset = 4
    sort_key = 2
    sort_direction = 1
    causal_model_order = 1
    grain_size_ms = 90
    analysis_overlap = 0.5
    synthesis_overlap = 0.5
    crossfade_ms = 25
    presetName$ = "BrightnessSweep"
else
    presetName$ = "Custom"
endif

if causal_model_order > 3
    causal_model_order = 3
endif
if causal_model_order < 1
    causal_model_order = 1
endif

sortKeyName$ = "Model residual magnitude"
if sort_key = 2
    sortKeyName$ = "Predicted brightness (Chat)"
elsif sort_key = 3
    sortKeyName$ = "Signed model residual"
elsif sort_key = 4
    sortKeyName$ = "Intensity"
endif

sortDirName$ = "Ascending"
if sort_direction = 2
    sortDirName$ = "Descending"
endif

# ============================================================
# VALIDATION AND SETUP
# ============================================================
warnLines$ = ""

if analysis_overlap < 0
    analysis_overlap = 0
    warnLines$ = warnLines$ + "  ! Analysis overlap < 0 -> 0" + newline$
endif
if analysis_overlap > 0.9
    analysis_overlap = 0.9
    warnLines$ = warnLines$ + "  ! Analysis overlap > 0.9 -> 0.9" + newline$
endif
if synthesis_overlap < 0
    synthesis_overlap = 0
    warnLines$ = warnLines$ + "  ! Synthesis overlap < 0 -> 0" + newline$
endif
if synthesis_overlap > 0.9
    synthesis_overlap = 0.9
    warnLines$ = warnLines$ + "  ! Synthesis overlap > 0.9 -> 0.9" + newline$
endif
if crossfade_ms < 0
    crossfade_ms = 0
    warnLines$ = warnLines$ + "  ! Crossfade < 0 ms -> 0 ms" + newline$
endif
if stereo_divergence_percent < 0
    stereo_divergence_percent = 0
    warnLines$ = warnLines$ + "  ! Stereo divergence < 0 -> 0" + newline$
endif
if stereo_divergence_percent > 100
    stereo_divergence_percent = 100
    warnLines$ = warnLines$ + "  ! Stereo divergence > 100 -> 100" + newline$
endif

selectObject: snd
dur = Get total duration
fs = Get sampling frequency
nChannels = Get number of channels

# Quantize all temporal synthesis geometry to the source sample grid.
# This keeps shifted grain samples aligned with output samples.
grainSamples = round((grain_size_ms / 1000) * fs)
if grainSamples < 2
    grainSamples = 2
endif
grainSec = grainSamples / fs
effectiveGrainMs = 1000 * grainSec

analysisStepSamples = round(grainSamples * (1 - analysis_overlap))
if analysisStepSamples < 1
    analysisStepSamples = 1
endif
analysisStepSec = analysisStepSamples / fs

synthStepSamples = round(grainSamples * (1 - synthesis_overlap))
if synthStepSamples < 1
    synthStepSamples = 1
endif
synthStepSec = synthStepSamples / fs
overlapSamples = grainSamples - synthStepSamples
overlapSec = overlapSamples / fs

requestedFadeSamples = round((crossfade_ms / 1000) * fs)
effectiveFadeSamples = requestedFadeSamples
if effectiveFadeSamples > overlapSamples
    effectiveFadeSamples = overlapSamples
    warnLines$ = warnLines$ + "  ! Crossfade exceeds synthesis overlap -> capped to overlap" + newline$
endif
if effectiveFadeSamples > floor(grainSamples / 2)
    effectiveFadeSamples = floor(grainSamples / 2)
    warnLines$ = warnLines$ + "  ! Crossfade exceeds half a grain -> capped to half-grain" + newline$
endif
if synthesis_overlap = 0 and crossfade_ms > 0
    effectiveFadeSamples = 0
    warnLines$ = warnLines$ + "  ! Synthesis overlap is 0 -> crossfade taper disabled" + newline$
endif
if effectiveFadeSamples < 0
    effectiveFadeSamples = 0
endif
effectiveFadeSec = effectiveFadeSamples / fs
effectiveFadeMs = 1000 * effectiveFadeSec

if dur < grainSec * 4
    exitScript: "Sound too short for the requested grain size."
endif

# Build the mono grain pool used by BOTH analysis and synthesis.
# Average channels first, but protect against severe anti-phase collapse.
strongestCh = 1
strongestRms = -1
for ch from 1 to nChannels
    selectObject: snd
    tmpCh = Extract one channel: ch
    tmpRms = Get root-mean-square: 0, 0
    if tmpRms > strongestRms
        strongestRms = tmpRms
        strongestCh = ch
    endif
    removeObject: tmpCh
endfor

selectObject: snd
workSnd = Convert to mono
Rename: "CausalMono"
monoMethod$ = "channel average"
selectObject: workSnd
monoRms = Get root-mean-square: 0, 0

if nChannels > 1 and strongestRms > 0 and monoRms < 0.1 * strongestRms
    removeObject: workSnd
    selectObject: snd
    workSnd = Extract one channel: strongestCh
    Rename: "CausalMono"
    selectObject: workSnd
    monoRms = Get root-mean-square: 0, 0
    monoMethod$ = "strongest channel fallback"
    warnLines$ = warnLines$ + "  ! Channel average nearly cancelled -> mono pool uses strongest channel " + string$(strongestCh) + newline$
endif

clearinfo
writeInfoLine: "=== Causal Recomposer v1.3 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Sound: ", sndName$, "  (", fixed$(dur, 2), " s, ", nChannels, " ch)"
appendInfoLine: "Mono grain pool: ", monoMethod$, " | RMS ", fixed$(monoRms,4)
appendInfoLine: "Grain: ", fixed$(effectiveGrainMs, 3), " ms effective | Analysis overlap: ", fixed$(analysis_overlap * 100, 0), "%"
appendInfoLine: "Requested model order: ", causal_model_order
appendInfoLine: "Sort key: ", sortKeyName$, " | Direction: ", sortDirName$
appendInfoLine: "Synthesis overlap: ", fixed$(synthesis_overlap * 100, 0), "% | Crossfade: ", fixed$(effectiveFadeMs, 1), " ms effective"
appendInfoLine: "Generated stereo divergence: ", fixed$(stereo_divergence_percent,1), "% (nearest-rank local swaps)"
appendInfoLine: "Interpretation: model-guided residual, not causal identification from a single recording."
if warnLines$ <> ""
    appendInfoLine: ""
    appendInfoLine: "Adjustments:"
    appendInfo: warnLines$
endif
appendInfoLine: ""

# ------------------------------------------------------------
# PHASE 1: LOCAL INTENSITY AND SPECTRAL CENTROID
# ------------------------------------------------------------
appendInfoLine: "Phase 1: analyzing local intensity and spectral centroid..."

selectObject: workSnd
intensityObj = To Intensity: 75, 0, "yes"

nGrains = floor((dur - grainSec) / analysisStepSec) + 1
if nGrains < causal_model_order + 3
    removeObject: workSnd, intensityObj
    exitScript: "Not enough grains to fit a stable model at this grain size."
endif

grain_time# = zero#(nGrains)
feat_I# = zero#(nGrains)
feat_C# = zero#(nGrains)
undefinedIntensityCount = 0

for i from 1 to nGrains
    t = grainSec / 2 + (i - 1) * analysisStepSec
    if t > dur - grainSec / 2
        t = dur - grainSec / 2
    endif
    grain_time#[i] = t

    selectObject: intensityObj
    ii = Get value at time: t, "Cubic"
    if ii = undefined
        ii = -300
        undefinedIntensityCount += 1
    endif
    feat_I#[i] = ii

    selectObject: workSnd
    g1 = Extract part: max(0, t - grainSec / 2), min(dur, t + grainSec / 2), "Hanning", 1, "no"
    sp1 = To Spectrum: "yes"
    cc = Get centre of gravity: 2
    if cc = undefined
        cc = 0
    endif
    feat_C#[i] = cc
    removeObject: g1, sp1
endfor

appendInfoLine: "  ", nGrains, " grains analyzed"
if undefinedIntensityCount > 0
    appendInfoLine: "  Note: ", undefinedIntensityCount, " undefined intensity values were floored to -300 dB."
endif

# ------------------------------------------------------------
# PHASE 2: STANDARDIZED POLYNOMIAL MODEL
#   z(I) = (I - meanI) / sdI
#   Chat = a0 + a1*z + ... + ak*z^k
# ------------------------------------------------------------
appendInfoLine: "Phase 2: fitting standardized intensity -> centroid model..."

meanI = 0
meanC = 0
minI = feat_I#[1]
maxI = feat_I#[1]
minC = feat_C#[1]
maxC = feat_C#[1]
for i from 1 to nGrains
    meanI += feat_I#[i]
    meanC += feat_C#[i]
    if feat_I#[i] < minI
        minI = feat_I#[i]
    endif
    if feat_I#[i] > maxI
        maxI = feat_I#[i]
    endif
    if feat_C#[i] < minC
        minC = feat_C#[i]
    endif
    if feat_C#[i] > maxC
        maxC = feat_C#[i]
    endif
endfor
meanI = meanI / nGrains
meanC = meanC / nGrains

varI = 0
for i from 1 to nGrains
    varI += (feat_I#[i] - meanI)^2
endfor
if nGrains > 1
    varI = varI / (nGrains - 1)
endif
sdI = sqrt(max(0, varI))

zI# = zero#(nGrains)
if sdI > 1e-9
    for i from 1 to nGrains
        zI#[i] = (feat_I#[i] - meanI) / sdI
    endfor
endif

requestedOrder = causal_model_order
effectiveOrder = requestedOrder
fitSolved = 0

if sdI <= 1e-9
    effectiveOrder = 0
else
    while effectiveOrder >= 1 and fitSolved = 0
        nCoef = effectiveOrder + 1
        aug## = zero##(nCoef, nCoef + 1)

        for row from 1 to nCoef
            for col from 1 to nCoef
                p = (row - 1) + (col - 1)
                s = 0
                for i from 1 to nGrains
                    s += zI#[i] ^ p
                endfor
                aug##[row, col] = s
            endfor
            s = 0
            for i from 1 to nGrains
                s += zI#[i] ^ (row - 1) * feat_C#[i]
            endfor
            aug##[row, nCoef + 1] = s
        endfor

        fitOK = 1
        for col from 1 to nCoef
            if fitOK = 1
                pivotRow = col
                pivotVal = abs(aug##[col, col])
                for r from col + 1 to nCoef
                    if abs(aug##[r, col]) > pivotVal
                        pivotVal = abs(aug##[r, col])
                        pivotRow = r
                    endif
                endfor

                if pivotVal < 1e-10
                    fitOK = 0
                else
                    if pivotRow <> col
                        for c from 1 to nCoef + 1
                            tmp = aug##[col, c]
                            aug##[col, c] = aug##[pivotRow, c]
                            aug##[pivotRow, c] = tmp
                        endfor
                    endif

                    pivot = aug##[col, col]
                    for c from 1 to nCoef + 1
                        aug##[col, c] = aug##[col, c] / pivot
                    endfor

                    for r from 1 to nCoef
                        if r <> col
                            factor = aug##[r, col]
                            for c from 1 to nCoef + 1
                                aug##[r, c] = aug##[r, c] - factor * aug##[col, c]
                            endfor
                        endif
                    endfor
                endif
            endif
        endfor

        if fitOK = 1
            fitSolved = 1
        else
            effectiveOrder -= 1
        endif
    endwhile
endif

if effectiveOrder = 0
    nCoef = 1
    coef# = zero#(1)
    coef#[1] = meanC
    if requestedOrder > 0
        warnLines$ = warnLines$ + "  ! Intensity variation/model rank insufficient -> constant centroid model" + newline$
    endif
else
    nCoef = effectiveOrder + 1
    coef# = zero#(nCoef)
    for row from 1 to nCoef
        coef#[row] = aug##[row, nCoef + 1]
    endfor
    if effectiveOrder < requestedOrder
        warnLines$ = warnLines$ + "  ! Singular requested polynomial -> reduced model order to " + string$(effectiveOrder) + newline$
    endif
endif

feat_Chat# = zero#(nGrains)
feat_R# = zero#(nGrains)
sumSqTot = 0
sumSqRes = 0

for i from 1 to nGrains
    if effectiveOrder = 0
        val = meanC
    else
        val = 0
        zPower = 1
        for c from 1 to nCoef
            val += coef#[c] * zPower
            zPower *= zI#[i]
        endfor
    endif
    feat_Chat#[i] = val
    feat_R#[i] = feat_C#[i] - val
    sumSqRes += feat_R#[i]^2
    sumSqTot += (feat_C#[i] - meanC)^2
endfor

if sumSqTot > 0
    rSquared = 1 - sumSqRes / sumSqTot
else
    rSquared = 0
endif
residualRms = sqrt(sumSqRes / nGrains)

appendInfoLine: "  effective model order = ", effectiveOrder
appendInfoLine: "  fit R^2 = ", fixed$(rSquared, 3), " | residual RMS = ", fixed$(residualRms, 1), " Hz"

# ------------------------------------------------------------
# PHASE 3: PRIMARY SORT + CONTROLLED DUAL-STEREO LOCAL SWAPS
# Both channels first receive EXACTLY the same stable causal order.
# Stereo divergence then swaps only adjacent grains with the smallest
# primary-key gaps. This keeps the primary law intact globally while
# allowing a small number of near-equivalent grains to differ L/R.
# ------------------------------------------------------------
appendInfoLine: "Phase 3: computing base causal order + subtle stereo divergence..."

sortKey# = zero#(nGrains)
for i from 1 to nGrains
    if sort_key = 1
        sortKey#[i] = abs(feat_R#[i])
    elsif sort_key = 2
        sortKey#[i] = feat_Chat#[i]
    elsif sort_key = 3
        sortKey#[i] = feat_R#[i]
    else
        sortKey#[i] = feat_I#[i]
    endif
endfor

# Secondary measured cue decides WHICH channel gets each local swap.
# It does not change which pairs are eligible: eligibility comes only
# from closeness in the primary causal sort key.
secondary# = zero#(nGrains)
secondaryName$ = "signed residual"
if sort_key = 3
    secondaryName$ = "standardized intensity"
    for i from 1 to nGrains
        secondary#[i] = zI#[i]
    endfor
else
    for i from 1 to nGrains
        secondary#[i] = feat_R#[i]
    endfor
endif

secMaxAbs = 0
for i from 1 to nGrains
    if abs(secondary#[i]) > secMaxAbs
        secMaxAbs = abs(secondary#[i])
    endif
endfor
if secMaxAbs < 1e-12 and sort_key <> 3
    secondaryName$ = "standardized intensity fallback"
    for i from 1 to nGrains
        secondary#[i] = zI#[i]
    endfor
    secMaxAbs = 0
    for i from 1 to nGrains
        if abs(secondary#[i]) > secMaxAbs
            secMaxAbs = abs(secondary#[i])
        endif
    endfor
endif

# Stable base sort.
permBase# = zero#(nGrains)
for i from 1 to nGrains
    permBase#[i] = i
endfor
for i from 2 to nGrains
    currentIdx = permBase#[i]
    currentVal = sortKey#[currentIdx]
    j = i
    keepMoving = 1
    while j > 1 and keepMoving = 1
        previousIdx = permBase#[j - 1]
        previousVal = sortKey#[previousIdx]
        shouldShift = 0
        if sort_direction = 1
            if previousVal > currentVal
                shouldShift = 1
            endif
        else
            if previousVal < currentVal
                shouldShift = 1
            endif
        endif
        if shouldShift = 1
            permBase#[j] = previousIdx
            j -= 1
        else
            keepMoving = 0
        endif
    endwhile
    permBase#[j] = currentIdx
endfor

permL# = zero#(nGrains)
permR# = zero#(nGrains)
baseRank# = zero#(nGrains)
for g from 1 to nGrains
    permL#[g] = permBase#[g]
    permR#[g] = permBase#[g]
    baseRank#[permBase#[g]] = g
endfor

# Candidate swap gaps in causal-rank order. Smaller gap means the
# two adjacent grains are more interchangeable under the chosen law.
pairGap# = zero#(nGrains - 1)
for g from 1 to nGrains - 1
    a = permBase#[g]
    b = permBase#[g + 1]
    pairGap#[g] = abs(sortKey#[a] - sortKey#[b])
endfor

# Maximum design: at divergence=100, swap up to one quarter of the
# grains (non-overlapping pairs). Default 20 stays deliberately subtle.
targetPairs = floor((stereo_divergence_percent / 100) * nGrains / 4)
maxPairs = floor(nGrains / 2)
if targetPairs > maxPairs
    targetPairs = maxPairs
endif
if targetPairs < 0
    targetPairs = 0
endif

usedRank# = zero#(nGrains)
actualPairs = 0
for swapNo from 1 to targetPairs
    bestPos = 0
    bestGap = 1e300
    for g from 1 to nGrains - 1
        if usedRank#[g] = 0 and usedRank#[g + 1] = 0
            if pairGap#[g] < bestGap
                bestGap = pairGap#[g]
                bestPos = g
            endif
        endif
    endfor

    if bestPos > 0
        a = permBase#[bestPos]
        b = permBase#[bestPos + 1]

        # Deterministic channel choice from the secondary feature.
        # Ties alternate by swap number to keep the field balanced.
        swapLeft = 0
        if secondary#[a] < secondary#[b]
            swapLeft = 1
        elsif secondary#[a] = secondary#[b]
            if swapNo mod 2 = 1
                swapLeft = 1
            endif
        endif

        if swapLeft = 1
            permL#[bestPos] = b
            permL#[bestPos + 1] = a
        else
            permR#[bestPos] = b
            permR#[bestPos + 1] = a
        endif

        usedRank#[bestPos] = 1
        usedRank#[bestPos + 1] = 1
        actualPairs += 1
    endif
endfor

# Measured dual-permutation statistics.
dispSum = 0
adjBreaksL = 0
adjBreaksR = 0
stereoDifferent = 0
stereoRankSepSum = 0
for g from 1 to nGrains
    if nGrains > 1
        dispSum += 0.5 * (abs(permL#[g] - g) + abs(permR#[g] - g)) / (nGrains - 1)
        stereoRankSepSum += abs(baseRank#[permL#[g]] - baseRank#[permR#[g]]) / (nGrains - 1)
    endif
    if permL#[g] <> permR#[g]
        stereoDifferent += 1
    endif
    if g > 1
        if abs(permL#[g] - permL#[g - 1]) <> 1
            adjBreaksL += 1
        endif
        if abs(permR#[g] - permR#[g - 1]) <> 1
            adjBreaksR += 1
        endif
    endif
endfor
meanDisplacementPct = 100 * dispSum / nGrains
stereoDifferentPct = 100 * stereoDifferent / nGrains
stereoOrderSeparationPct = 100 * stereoRankSepSum / nGrains
if nGrains > 1
    adjacencyBreakPct = 50 * (adjBreaksL + adjBreaksR) / (nGrains - 1)
else
    adjacencyBreakPct = 0
endif

appendInfoLine: "  stereo cue = ", secondaryName$, " | local swap pairs = ", actualPairs
appendInfoLine: "  L/R differing positions = ", fixed$(stereoDifferentPct,1), "% | mean causal-rank separation = ", fixed$(stereoOrderSeparationPct,3), "%"

# ------------------------------------------------------------
# PHASE 4: DUAL MONO-POOL RECOMPOSITION -> GENERATED STEREO
# Both channels use the same source pool and splice law. Only the
# model-guided grain order differs slightly between L and R.
# ------------------------------------------------------------
appendInfoLine: "Phase 4: recomposing mono source pool into generated stereo..."

outDur = (nGrains - 1) * synthStepSec + grainSec
outBuf = Create Sound from formula: "cr_out", 2, 0, outDur, fs, "0"
outWin = Create Sound from formula: "cr_win", 1, 0, outDur, fs, "0"

for g from 1 to nGrains
    outStart = (g - 1) * synthStepSec
    outEnd = outStart + grainSec

    # LEFT process
    srcIdx = permL#[g]
    srcT = grain_time#[srcIdx]
    t1src = max(0, srcT - grainSec / 2)
    t2src = min(dur, srcT + grainSec / 2)
    selectObject: workSnd
    grainL = Extract part: t1src, t2src, "rectangular", 1, "no"
    Rename: "cr_grainL"
    if effectiveFadeSec > 0
        selectObject: grainL
        Formula: "if x < 'effectiveFadeSec' then self * (0.5 - 0.5*cos(pi*x/'effectiveFadeSec')) else if x > xmax - 'effectiveFadeSec' then self * (0.5 - 0.5*cos(pi*(xmax-x)/'effectiveFadeSec')) else self fi fi"
    endif
    selectObject: grainL
    Shift times to: "start time", outStart
    selectObject: outBuf
    Formula (part): max(0, outStart), min(outDur, outEnd), 1, 1,
        ... "self + object (""Sound cr_grainL"", x, 1)"

    # RIGHT process
    srcIdx = permR#[g]
    srcT = grain_time#[srcIdx]
    t1src = max(0, srcT - grainSec / 2)
    t2src = min(dur, srcT + grainSec / 2)
    selectObject: workSnd
    grainR = Extract part: t1src, t2src, "rectangular", 1, "no"
    Rename: "cr_grainR"
    if effectiveFadeSec > 0
        selectObject: grainR
        Formula: "if x < 'effectiveFadeSec' then self * (0.5 - 0.5*cos(pi*x/'effectiveFadeSec')) else if x > xmax - 'effectiveFadeSec' then self * (0.5 - 0.5*cos(pi*(xmax-x)/'effectiveFadeSec')) else self fi fi"
    endif
    selectObject: grainR
    Shift times to: "start time", outStart
    selectObject: outBuf
    Formula (part): max(0, outStart), min(outDur, outEnd), 2, 2,
        ... "self + object (""Sound cr_grainR"", x, 1)"

    # The overlap geometry is identical on both sides, so one
    # measured denominator normalizes both channels.
    selectObject: outWin
    if effectiveFadeSec > 0
        Formula (part): max(0, outStart), min(outDur, outEnd), 1, 1,
            ... "self + if x-'outStart' < 'effectiveFadeSec' then 0.5 - 0.5*cos(pi*(x-'outStart')/'effectiveFadeSec') else if x-'outStart' > 'grainSec'-'effectiveFadeSec' then 0.5 - 0.5*cos(pi*('grainSec'-(x-'outStart'))/'effectiveFadeSec') else 1 fi fi"
    else
        Formula (part): max(0, outStart), min(outDur, outEnd), 1, 1, "self + 1"
    endif

    removeObject: grainL, grainR
endfor

selectObject: outBuf
Formula: "if object (""Sound cr_win"", x, 0) > 1e-6 then self / object (""Sound cr_win"", x, 0) else 0 fi"
Rename: sndName$ + "_causal_recomposed_stereo"
removeObject: outWin

selectObject: outBuf
outChannels = Get number of channels
outPeak = Get absolute extremum: 0, 0, "None"
outRms = Get root-mean-square: 0, 0

# ============================================================
# VISUALIZATION
# v1.3: simplified mechanism-first 2x2 layout with generated stereo.
# Each panel answers one question and uses measured data only.
# ============================================================
if draw_visualization
    appendInfoLine: "Drawing simplified process visualization..."

    # Measured mono source and generated stereo MID/SIDE.
    vizSrc = workSnd
    selectObject: vizSrc
    srcPeak = Get absolute extremum: 0, 0, "None"
    srcRms = Get root-mean-square: 0, 0

    selectObject: outBuf
    vizL = Extract one channel: 1
    Rename: "cr_viz_left"
    selectObject: outBuf
    vizR = Extract one channel: 2
    Rename: "cr_viz_right"

    vizMid = Create Sound from formula: "cr_viz_mid", 1, 0, outDur, fs,
        ... "(object (""Sound cr_viz_left"", x, 1) + object (""Sound cr_viz_right"", x, 1)) / 2"
    vizSide = Create Sound from formula: "cr_viz_side", 1, 0, outDur, fs,
        ... "(object (""Sound cr_viz_left"", x, 1) - object (""Sound cr_viz_right"", x, 1)) / 2"

    selectObject: vizMid
    vizOutPeak = Get absolute extremum: 0, 0, "None"
    vizOutRms = Get root-mean-square: 0, 0
    midRms = vizOutRms
    selectObject: vizSide
    sideRms = Get root-mean-square: 0, 0
    if midRms > 1e-12 and sideRms > 1e-12
        sideMidDb = 20 * log10(sideRms / midRms)
    elsif sideRms <= 1e-12
        sideMidDb = -300
    else
        sideMidDb = 60
    endif
    if sideMidDb < -100
        sideMidLabel$ = "mono"
    else
        sideMidLabel$ = fixed$(sideMidDb,1) + " dB"
    endif

    # Spectral-shape QC compares the mono grain pool to stereo MID.
    # Each LTAS is mean-removed, so D measures shape change rather
    # than overall level.
    selectObject: vizSrc
    srcSpec = To Spectrum: "yes"
    srcGlobalCentroid = Get centre of gravity: 2
    To Ltas (1-to-1)
    srcLtas = selected("Ltas")

    selectObject: vizMid
    outSpec = To Spectrum: "yes"
    outGlobalCentroid = Get centre of gravity: 2
    To Ltas (1-to-1)
    outLtas = selected("Ltas")

    specFmin = 50
    specFmax = min(16000, 0.45 * fs)
    if specFmax <= specFmin * 1.2
        specFmin = max(1, specFmax / 5)
    endif
    logFmin = log10(specFmin)
    logFmax = log10(specFmax)
    nSpecPoints = 72
    specFreq# = zero#(nSpecPoints)
    srcShape# = zero#(nSpecPoints)
    outShape# = zero#(nSpecPoints)
    specDelta# = zero#(nSpecPoints)
    meanSrcShape = 0
    meanOutShape = 0

    for q from 1 to nSpecPoints
        frac = (q - 1) / (nSpecPoints - 1)
        freq = specFmin * (specFmax / specFmin)^frac
        specFreq#[q] = freq
        bandLo = max(specFmin, freq / 1.04)
        bandHi = min(specFmax, freq * 1.04)
        if bandHi <= bandLo
            bandHi = min(specFmax, bandLo + 1)
        endif
        selectObject: srcLtas
        sdb = Get mean: bandLo, bandHi, "dB"
        selectObject: outLtas
        odb = Get mean: bandLo, bandHi, "dB"
        if sdb = undefined
            sdb = -300
        endif
        if odb = undefined
            odb = -300
        endif
        srcShape#[q] = sdb
        outShape#[q] = odb
        meanSrcShape += sdb
        meanOutShape += odb
    endfor
    meanSrcShape = meanSrcShape / nSpecPoints
    meanOutShape = meanOutShape / nSpecPoints

    specDiffMax = 0
    shapeSq = 0
    for q from 1 to nSpecPoints
        srcShape#[q] = srcShape#[q] - meanSrcShape
        outShape#[q] = outShape#[q] - meanOutShape
        specDelta#[q] = outShape#[q] - srcShape#[q]
        if abs(specDelta#[q]) > specDiffMax
            specDiffMax = abs(specDelta#[q])
        endif
        shapeSq += specDelta#[q]^2
    endfor
    shapeRmseDb = sqrt(shapeSq / nSpecPoints)
    specDiffRange = 5 * ceiling((specDiffMax + 1) / 5)
    if specDiffRange < 10
        specDiffRange = 10
    endif

    centroidDelta = outGlobalCentroid - srcGlobalCentroid
    durationRatio = outDur / dur

    # Round linear tick spacing.
    procedure crVizStep: .range, .target
        .raw = .range / .target
        .mag = 10 ^ floor(log10(max(1e-12, .raw)))
        .n = .raw / .mag
        if .n < 1.5
            .step = 1 * .mag
        elsif .n < 3.5
            .step = 2 * .mag
        elsif .n < 7.5
            .step = 5 * .mag
        else
            .step = 10 * .mag
        endif
    endproc

    Erase all

    # ---------------- Header ----------------
    Select outer viewport: 0, 8, 0, 0.42
    Select inner viewport: 0, 8, 0, 0.42
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.62, "half", "Causal Recomposer v1.3 - " + presetName$

    Select outer viewport: 0, 8, 0.43, 0.72
    Select inner viewport: 0, 8, 0.43, 0.72
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.34,0.34,0.40}"
    Text: 0.5, "centre", 0.58, "half", "mono grain pool -> one causal sort -> subtle L/R local swaps -> stereo overlap-add"

    # ========================================================
    # A  MODEL
    # ========================================================
    Select outer viewport: 0.18, 3.92, 0.84, 1.10
    Select inner viewport: 0.18, 3.92, 0.84, 1.10
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.01, "left", 0.72, "half", "A  MODEL - measured intensity -> centroid law"
    Font size: 6
    Colour: "{0.35,0.35,0.40}"
    Text: 0.01, "left", 0.18, "half", "R2 " + fixed$(rSquared,3) + " | residual RMS " + fixed$(residualRms,0) + " Hz"

    iPad = max(1, 0.04 * (maxI - minI))
    cPad = max(50, 0.08 * (maxC - minC))
    plotIMin = minI - iPad
    plotIMax = maxI + iPad
    plotCMin = max(0, minC - cPad)
    plotCMax = maxC + cPad
    for i from 1 to nGrains
        if feat_Chat#[i] < plotCMin
            plotCMin = max(0, feat_Chat#[i] - cPad)
        endif
        if feat_Chat#[i] > plotCMax
            plotCMax = feat_Chat#[i] + cPad
        endif
    endfor
    if plotIMax <= plotIMin
        plotIMax = plotIMin + 1
    endif
    if plotCMax <= plotCMin
        plotCMax = plotCMin + 100
    endif

    Select outer viewport: 0.18, 3.92, 1.11, 3.12
    Select inner viewport: 0.62, 3.78, 1.22, 2.94
    Axes: plotIMin, plotIMax, plotCMin, plotCMax
    Paint rectangle: "{0.975,0.975,0.978}", plotIMin, plotIMax, plotCMin, plotCMax

    # Fit curve first.
    Colour: "{0.78,0.28,0.22}"
    Line width: 2
    nCurve = 120
    for q from 1 to nCurve
        i0 = minI + (maxI - minI) * (q - 1) / nCurve
        i1 = minI + (maxI - minI) * q / nCurve
        if effectiveOrder = 0
            c0 = meanC
            c1 = meanC
        else
            z0 = (i0 - meanI) / sdI
            z1 = (i1 - meanI) / sdI
            c0 = 0
            c1 = 0
            zPow0 = 1
            zPow1 = 1
            for c from 1 to nCoef
                c0 += coef#[c] * zPow0
                c1 += coef#[c] * zPow1
                zPow0 *= z0
                zPow1 *= z1
            endfor
        endif
        Draw line: i0, c0, i1, c1
    endfor
    Line width: 1

    # Measured grains. No residual stems: one visual claim only.
    pointStride = ceiling(nGrains / 120)
    if pointStride < 1
        pointStride = 1
    endif
    for i from 1 to nGrains
        if (i - 1) mod pointStride = 0
            Paint circle (mm): "{0.26,0.46,0.76}", feat_I#[i], feat_C#[i], 0.48
        endif
    endfor
    Select inner viewport: 0.62, 3.78, 1.22, 2.94
    Axes: plotIMin, plotIMax, plotCMin, plotCMax
    Colour: "Black"
    Draw inner box
    Font size: 5
    @crVizStep: plotIMax - plotIMin, 5
    Marks bottom every: 1, crVizStep.step, "yes", "yes", "no"
    @crVizStep: plotCMax - plotCMin, 5
    Marks left every: 1, crVizStep.step, "yes", "yes", "no"
    Font size: 6
    Text bottom: "yes", "intensity (dB)"
    Text left: "yes", "centroid (Hz)"

    # ========================================================
    # B  ORDER
    # ========================================================
    Select outer viewport: 4.08, 7.82, 0.84, 1.10
    Select inner viewport: 4.08, 7.82, 0.84, 1.10
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.01, "left", 0.72, "half", "B  STEREO ORDER - actual L/R output -> source position"
    Font size: 6
    Colour: "{0.35,0.35,0.40}"
    Text: 0.01, "left", 0.18, "half", "blue L | red R | positions differ " + fixed$(stereoDifferentPct,1) + "\% | rank separation " + fixed$(stereoOrderSeparationPct,3) + "\%"

    Select outer viewport: 4.08, 7.82, 1.11, 3.12
    Select inner viewport: 4.55, 7.68, 1.22, 2.94
    Axes: 0, 100, 0, 100
    Paint rectangle: "{0.975,0.975,0.978}", 0, 100, 0, 100

    # Grey diagonal = unchanged chronology.
    Colour: "{0.76,0.76,0.79}"
    Line width: 1
    Draw line: 0, 0, 100, 100

    # LEFT actual permutation.
    Colour: "{0.26,0.48,0.78}"
    Line width: 1.5
    for g from 2 to nGrains
        x0 = 100 * (g - 2) / (nGrains - 1)
        x1 = 100 * (g - 1) / (nGrains - 1)
        y0 = 100 * (permL#[g - 1] - 1) / (nGrains - 1)
        y1 = 100 * (permL#[g] - 1) / (nGrains - 1)
        Draw line: x0, y0, x1, y1
    endfor

    # RIGHT actual permutation.
    Colour: "{0.78,0.28,0.22}"
    Line width: 1.3
    for g from 2 to nGrains
        x0 = 100 * (g - 2) / (nGrains - 1)
        x1 = 100 * (g - 1) / (nGrains - 1)
        y0 = 100 * (permR#[g - 1] - 1) / (nGrains - 1)
        y1 = 100 * (permR#[g] - 1) / (nGrains - 1)
        Draw line: x0, y0, x1, y1
    endfor
    Line width: 1

    Select inner viewport: 4.55, 7.68, 1.22, 2.94
    Axes: 0, 100, 0, 100
    Colour: "Black"
    Draw inner box
    Font size: 5
    Marks bottom every: 1, 20, "yes", "yes", "no"
    Marks left every: 1, 20, "yes", "yes", "no"
    Font size: 6
    Text bottom: "yes", "output position (\%)"
    Text left: "yes", "source position (\%)"

    # ========================================================
    # C  SPLICE
    # ========================================================
    Select outer viewport: 0.18, 3.92, 3.30, 3.56
    Select inner viewport: 0.18, 3.92, 3.30, 3.56
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.01, "left", 0.72, "half", "C  SPLICE - actual edge taper + OLA denominator"
    Font size: 6
    Colour: "{0.35,0.35,0.40}"
    Text: 0.01, "left", 0.18, "half", "blue = one source-grain gain | red = normalization weight | fade " + fixed$(effectiveFadeMs,1) + " ms | hop " + fixed$(1000*synthStepSec,1) + " ms"

    geomXmax = grainSec + 2 * synthStepSec
    geomMax = 1
    for q from 0 to 220
        tq = geomXmax * q / 220
        wsum = 0
        for kk from 0 to 12
            ws = kk * synthStepSec
            localT = tq - ws
            if localT >= 0 and localT <= grainSec
                if effectiveFadeSec > 0
                    if localT < effectiveFadeSec
                        w = 0.5 - 0.5*cos(pi*localT/effectiveFadeSec)
                    elsif localT > grainSec - effectiveFadeSec
                        w = 0.5 - 0.5*cos(pi*(grainSec-localT)/effectiveFadeSec)
                    else
                        w = 1
                    endif
                else
                    w = 1
                endif
                wsum += w
            endif
        endfor
        if wsum > geomMax
            geomMax = wsum
        endif
    endfor
    geomYmax = max(1.15, 1.10 * geomMax)

    Select outer viewport: 0.18, 3.92, 3.57, 5.48
    Select inner viewport: 0.62, 3.78, 3.68, 5.30
    Axes: 0, 1000*geomXmax, 0, geomYmax
    Paint rectangle: "{0.975,0.975,0.978}", 0, 1000*geomXmax, 0, geomYmax

    # One actual local grain gain window.
    Colour: "{0.26,0.48,0.78}"
    Line width: 2
    nDraw = 160
    for q from 1 to nDraw
        t0 = grainSec * (q - 1) / nDraw
        t1 = grainSec * q / nDraw
        if effectiveFadeSec > 0
            if t0 < effectiveFadeSec
                w0 = 0.5 - 0.5*cos(pi*t0/effectiveFadeSec)
            elsif t0 > grainSec - effectiveFadeSec
                w0 = 0.5 - 0.5*cos(pi*(grainSec-t0)/effectiveFadeSec)
            else
                w0 = 1
            endif
            if t1 < effectiveFadeSec
                w1 = 0.5 - 0.5*cos(pi*t1/effectiveFadeSec)
            elsif t1 > grainSec - effectiveFadeSec
                w1 = 0.5 - 0.5*cos(pi*(grainSec-t1)/effectiveFadeSec)
            else
                w1 = 1
            endif
        else
            w0 = 1
            w1 = 1
        endif
        Draw line: 1000*t0, w0, 1000*t1, w1
    endfor

    # Red = actual normalization denominator from the overlap pattern.
    Colour: "{0.78,0.28,0.22}"
    Line width: 1.5
    for q from 1 to 220
        t0 = geomXmax * (q - 1) / 220
        t1 = geomXmax * q / 220
        sum0 = 0
        sum1 = 0
        for kk from 0 to 12
            ws = kk * synthStepSec
            u0 = t0 - ws
            u1 = t1 - ws
            if u0 >= 0 and u0 <= grainSec
                if effectiveFadeSec > 0
                    if u0 < effectiveFadeSec
                        w0 = 0.5 - 0.5*cos(pi*u0/effectiveFadeSec)
                    elsif u0 > grainSec - effectiveFadeSec
                        w0 = 0.5 - 0.5*cos(pi*(grainSec-u0)/effectiveFadeSec)
                    else
                        w0 = 1
                    endif
                else
                    w0 = 1
                endif
                sum0 += w0
            endif
            if u1 >= 0 and u1 <= grainSec
                if effectiveFadeSec > 0
                    if u1 < effectiveFadeSec
                        w1 = 0.5 - 0.5*cos(pi*u1/effectiveFadeSec)
                    elsif u1 > grainSec - effectiveFadeSec
                        w1 = 0.5 - 0.5*cos(pi*(grainSec-u1)/effectiveFadeSec)
                    else
                        w1 = 1
                    endif
                else
                    w1 = 1
                endif
                sum1 += w1
            endif
        endfor
        Draw line: 1000*t0, sum0, 1000*t1, sum1
    endfor
    Line width: 1

    Select inner viewport: 0.62, 3.78, 3.68, 5.30
    Axes: 0, 1000*geomXmax, 0, geomYmax
    Colour: "Black"
    Draw inner box
    Font size: 5
    @crVizStep: 1000*geomXmax, 5
    Marks bottom every: 1, crVizStep.step, "yes", "yes", "no"
    @crVizStep: geomYmax, 4
    Marks left every: 1, crVizStep.step, "yes", "yes", "no"
    Font size: 6
    Text bottom: "yes", "time (ms)"
    Text left: "yes", "gain / weight"

    # ========================================================
    # D  CHECK
    # ========================================================
    Select outer viewport: 4.08, 7.82, 3.30, 3.56
    Select inner viewport: 4.08, 7.82, 3.30, 3.56
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.01, "left", 0.72, "half", "D  CHECK - stereo MID spectral-shape difference"
    Font size: 6
    Colour: "{0.35,0.35,0.40}"
    Text: 0.01, "left", 0.18, "half", "MID - mono source | shape RMSE " + fixed$(shapeRmseDb,2) + " dB | SIDE/MID " + sideMidLabel$

    Select outer viewport: 4.08, 7.82, 3.57, 5.48
    Select inner viewport: 4.55, 7.68, 3.68, 5.30
    Axes: logFmin, logFmax, -specDiffRange, specDiffRange
    Paint rectangle: "{0.975,0.975,0.978}", logFmin, logFmax, -specDiffRange, specDiffRange
    # Quiet reference band around zero.
    bandRef = min(3, specDiffRange)
    Paint rectangle: "{0.94,0.94,0.95}", logFmin, logFmax, -bandRef, bandRef
    Colour: "{0.60,0.60,0.64}"
    Draw line: logFmin, 0, logFmax, 0

    Colour: "{0.26,0.48,0.78}"
    Line width: 1.8
    for q from 2 to nSpecPoints
        Draw line: log10(specFreq#[q-1]), specDelta#[q-1], log10(specFreq#[q]), specDelta#[q]
    endfor
    Line width: 1

    Select inner viewport: 4.55, 7.68, 3.68, 5.30
    Axes: logFmin, logFmax, -specDiffRange, specDiffRange
    Colour: "Black"
    Draw inner box
    Font size: 5
    Marks left every: 1, max(5, specDiffRange/2), "yes", "yes", "no"
    freqTicks# = {50,100,200,500,1000,2000,5000,10000,16000}
    for k from 1 to size(freqTicks#)
        ft = freqTicks#[k]
        if ft >= specFmin and ft <= specFmax
            if ft >= 1000
                flab$ = fixed$(ft/1000,1) + "k"
            else
                flab$ = fixed$(ft,0)
            endif
            One mark bottom: log10(ft), "no", "yes", "no", flab$
        endif
    endfor
    Font size: 6
    Text bottom: "yes", "frequency (Hz, log)"
    Text left: "yes", "MID - mono source (dB)"

    # ---------------- Bottom summary ----------------
    Select outer viewport: 0.18, 7.82, 5.67, 6.18
    Select inner viewport: 0.18, 7.82, 5.67, 6.18
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.965,0.965,0.970}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text: 0.02, "left", 0.67, "half", "SORT  " + sortKeyName$ + " / " + sortDirName$ + "     GRAINS  " + string$(nGrains) + "     GENERATED STEREO  " + fixed$(stereo_divergence_percent,0) + "\%"
    Font size: 6
    Colour: "{0.35,0.35,0.40}"
    Text: 0.02, "left", 0.24, "half", "mono pool " + monoMethod$ + " | stereo " + fixed$(stereo_divergence_percent,0) + "\% | rank sep " + fixed$(stereoOrderSeparationPct,3) + "\% | SIDE/MID " + sideMidLabel$

    removeObject: vizL, vizR, vizMid, vizSide, srcSpec, outSpec, srcLtas, outLtas
endif

# ============================================================
# OUTPUT
# ============================================================
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Effective model order: ", effectiveOrder, " (requested ", requestedOrder, ")"
appendInfoLine: "Fit R^2: ", fixed$(rSquared, 3), " | residual RMS: ", fixed$(residualRms, 1), " Hz"
appendInfoLine: "Mean permutation displacement (L/R average): ", fixed$(meanDisplacementPct, 1), "%"
appendInfoLine: "L/R differing output positions: ", fixed$(stereoDifferentPct,1), "% | mean causal-rank separation: ", fixed$(stereoOrderSeparationPct,3), "%"
appendInfoLine: "Broken source adjacencies: ", fixed$(adjacencyBreakPct, 1), "%"
appendInfoLine: "Effective crossfade: ", fixed$(effectiveFadeMs, 1), " ms"
appendInfoLine: "Output channels: ", outChannels, " generated from mono grain pool (source had ", nChannels, " ch)"
appendInfoLine: "Output duration: ", fixed$(outDur, 2), " s  (source ", fixed$(dur, 2), " s)"
appendInfoLine: "Output peak: ", fixed$(outPeak, 4), " | RMS: ", fixed$(outRms, 4)
if warnLines$ <> ""
    appendInfoLine: ""
    appendInfoLine: "Adjustments made during processing:"
    appendInfo: warnLines$
endif

removeObject: workSnd, intensityObj
selectObject: outBuf

if play_result
    appendInfoLine: "Playing..."
    Play
endif
