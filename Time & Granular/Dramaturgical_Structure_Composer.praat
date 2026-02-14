# ============================================================
# Praat AudioTools - Dramaturgical_Structure_Composer.praat
# Author: Shai Cohen
# Version: 4.0 (2025) - DRAMATURGICAL INTELLIGENCE REWRITE
# License: MIT License
#
# Description:
#   TRUE dramaturgical composition through:
#   - Spectral novelty detection (timbre changes)
#   - Actual silence detection (gaps in sound)
#   - Register tracking (pitch centroid)
#   - Texture classification (tonal/noise/sparse/dense)
#   - Structural operations (loop/reorder/silence/stretch/recall)
#
#   v4.0 improvements over v3.0:
#   - Macro-dynamics preserved (no per-block normalization)
#   - Optional tension arc envelope over full output
#   - Texture-aware crossfade durations (joints as structure)
#   - Form archetype reordering (arch/rondo/contrast/narrative)
#   - Transformed recalls (filtered, stretched, reversed, quieter)
#   - Context-aware silence placement (after peaks, before recalls)
#   - Bolder stretch ranges for Radical mode
#   - Optional noise-tail silences instead of digital zero
#
# This is NOT an FX processor. This reshapes musical form.
# ============================================================

form Dramaturgical Structure Composer v4.0
    comment === Analysis ===
    positive Min_section_duration_s 8
    positive Max_section_duration_s 90
    real Novelty_threshold 0.25
    real Silence_threshold_dB -45
    real Harmonicity_threshold 0.15
    positive Spectral_centroid_low_hz 500
    positive Spectral_centroid_high_hz 3000
    comment === Strategy & Form ===
    optionmenu Strategy: 2
        option Conservative (subtle reshaping)
        option Dramatic (major restructuring)
        option Radical (complete reimagining)
    optionmenu Reorder_mode: 3
        option None (keep original order)
        option Arch (build to peak, mirror down)
        option Contrast (maximize adjacent difference)
        option Rondo (refrain + episodes)
        option Narrative (dark-build-bright-recall-fade)
        option Random swap
    comment === Options ===
    boolean Allow_looping 1
    boolean Allow_long_silences 1
    boolean Allow_time_stretching 1
    boolean Allow_material_recall 1
    boolean Apply_tension_arc 1
    boolean Draw_visualization 1
    boolean Play_output 1
endform

beginPause: "Advanced Settings"
    comment: "=== Tension Arc ==="
    real: "Arc_peak_position", 0.65
    real: "Arc_exaggeration", 1.5
    comment: "=== Crossfades & Silence ==="
    optionMenu: "Crossfade_mode", 2
        option: "Fixed short (30 ms)"
        option: "Texture-aware (structural joints)"
    optionMenu: "Silence_mode", 2
        option: "Digital zero"
        option: "Noise tail from source"
    comment: "=== Recall Transformation ==="
    boolean: "Recall_apply_lowpass", 1
    boolean: "Recall_reduce_amplitude", 1
    boolean: "Recall_allow_reverse", 1
    real: "Recall_amplitude_factor", 0.7
    positive: "Recall_lowpass_hz", 2500
    comment: "=== Debug ==="
    boolean: "Keep_debug_objects", 0
    positive: "Min_silence_duration_s", 0.5
clicked = endPause: "Cancel", "OK", 2, 1
if clicked = 1
    exitScript()
endif

# ============================================================
# Helper Procedures
# ============================================================

procedure ensureMono: .soundObj
    selectObject: .soundObj
    .nChan = Get number of channels
    if .nChan > 1
        .mono = Convert to mono
        .result = .mono
        .wasConverted = 1
    else
        .result = .soundObj
        .wasConverted = 0
    endif
endproc

procedure computeSpectralCentroid: .soundObj, .startTime, .endTime
    selectObject: .soundObj
    .spectrum = To Spectrum: "yes"
    .centroid = Get centre of gravity: 2
    removeObject: .spectrum
endproc

procedure computeHarmonicity: .soundObj, .startTime, .endTime
    selectObject: .soundObj
    .dur = .endTime - .startTime
    .pitchFloor = 75
    .pitchCeiling = 600

    if .dur < 0.1
        .harmValue = 0
    else
        .harmObj = To Harmonicity (cc): 0.01, .pitchFloor, 0.1, 1.0
        .harmValue = Get mean: .startTime, .endTime
        if .harmValue = undefined
            .harmValue = 0
        endif
        removeObject: .harmObj
    endif
endproc

procedure computeRMS: .soundObj
    selectObject: .soundObj
    .rms = Get root-mean-square: 0, 0
    if .rms = undefined
        .rms = 0
    endif
endproc

procedure detectSilence: .soundObj
    selectObject: .soundObj
    .duration = Get total duration
    .intensityObj = To Intensity: 70, 0.01, "yes"

    .numSilences = 0
    .inSilence = 0
    .silenceStart = 0

    .numFrames = floor(.duration / 0.01)

    for .i from 1 to .numFrames
        .t = .i * 0.01
        selectObject: .intensityObj
        .db = Get value at time: .t, "Cubic"

        if .db = undefined
            .db = -100
        endif

        if .db < silence_threshold_dB
            if .inSilence = 0
                .silenceStart = .t
                .inSilence = 1
            endif
        else
            if .inSilence = 1
                .silDur = .t - .silenceStart
                if .silDur >= min_silence_duration_s
                    .numSilences = .numSilences + 1
                    silStart_'.numSilences' = .silenceStart
                    silEnd_'.numSilences' = .t
                endif
                .inSilence = 0
            endif
        endif
    endfor

    if .inSilence = 1
        .silDur = .duration - .silenceStart
        if .silDur >= min_silence_duration_s
            .numSilences = .numSilences + 1
            silStart_'.numSilences' = .silenceStart
            silEnd_'.numSilences' = .duration
        endif
    endif

    removeObject: .intensityObj
endproc

# ----------------------------------------------------------
# Texture-aware crossfade lookup
# fromTex and toTex: 1=tonal,2=sparse,3=bright,4=dark,5=noise
# Returns duration in seconds
# ----------------------------------------------------------
procedure getCrossfadeDuration: .fromTex, .toTex
    if crossfade_mode = 1
        # Fixed short mode
        .duration = 0.03
    else
        # Texture-aware mode
        # Default medium
        .duration = 0.3

        # Tonal → Tonal: long blend
        if .fromTex = 1 and .toTex = 1
            .duration = 1.5
        # Tonal → anything else: medium-long
        elsif .fromTex = 1
            .duration = 0.8
        # Anything → Tonal: medium fade-in
        elsif .toTex = 1
            .duration = 0.6
        endif

        # Sparse involved: shorter (let the space breathe)
        if .fromTex = 2 or .toTex = 2
            .duration = 0.15
        endif

        # Dense/noise → Silence or Sparse: hard cut (dramatic)
        if (.fromTex = 5 or .fromTex = 3) and (.toTex = 2)
            .duration = 0.01
        endif

        # Silence → anything: slow fade-in (anticipation)
        # (silence has texture code 0 in our timeline)
        if .fromTex = 0
            .duration = 1.5
        endif

        # Anything → Silence: medium-short (let it cut)
        if .toTex = 0
            .duration = 0.08
        endif

        # Noise → Noise: medium
        if .fromTex = 5 and .toTex = 5
            .duration = 0.4
        endif

        # Maximum contrast pairs: short for impact
        if (.fromTex = 4 and .toTex = 3) or (.fromTex = 3 and .toTex = 4)
            .duration = 0.05
        endif
    endif
endproc

# ----------------------------------------------------------
# Compute "texture distance" between two sections
# Used for contrast-based reordering
# ----------------------------------------------------------
procedure textureDistance: .tex1, .tex2, .cent1, .cent2, .rms1, .rms2
    # Texture code distance (0-4 range)
    .texDiff = abs(.tex1 - .tex2)
    # Centroid distance (normalize to 0-1 by dividing by 5000)
    .centDiff = abs(.cent1 - .cent2) / 5000
    # RMS distance (normalize)
    .maxRms = max(.rms1, .rms2)
    if .maxRms > 0
        .rmsDiff = abs(.rms1 - .rms2) / .maxRms
    else
        .rmsDiff = 0
    endif
    .distance = .texDiff * 0.4 + .centDiff * 0.3 + .rmsDiff * 0.3
endproc


# ============================================================
# Strategy Settings
# ============================================================

if strategy = 1
    loop_probability = 0.2
    silence_insert_probability = 0.15
    stretch_probability = 0.2
    recall_probability = 0.25
    max_operations = 3
    silence_duration_range_s = 2
    stretch_factor_min = 0.7
    stretch_factor_max = 1.4
    strategyName$ = "Conservative"
elsif strategy = 2
    loop_probability = 0.4
    silence_insert_probability = 0.35
    stretch_probability = 0.4
    recall_probability = 0.4
    max_operations = 6
    silence_duration_range_s = 8
    stretch_factor_min = 0.4
    stretch_factor_max = 2.5
    strategyName$ = "Dramatic"
else
    loop_probability = 0.6
    silence_insert_probability = 0.5
    stretch_probability = 0.5
    recall_probability = 0.6
    max_operations = 10
    silence_duration_range_s = 20
    stretch_factor_min = 0.25
    stretch_factor_max = 4.0
    strategyName$ = "Radical"
endif

# ============================================================
# Input Validation
# ============================================================

nSelected = numberOfSelected("Sound")
if nSelected <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

inputSound = selected("Sound")
selectObject: inputSound
inputName$ = selected$("Sound")
inputDuration = Get total duration
inputChannels = Get number of channels
sampleRate = Get sampling frequency

if inputDuration < 20
    exitScript: "Sound too short (< 20 s). Need longer material for structural analysis."
endif

writeInfoLine: "=============================================="
appendInfoLine: "  Dramaturgical Structure Composer v4.0"
appendInfoLine: "=============================================="
appendInfoLine: "Input: ", inputName$
appendInfoLine: "Duration: ", fixed$(inputDuration, 2), " s"
appendInfoLine: "Strategy: ", strategyName$
appendInfoLine: "Reorder mode: ", reorder_mode
appendInfoLine: ""

# ============================================================
# Convert to Mono
# ============================================================

selectObject: inputSound
if inputChannels > 1
    workSound = Convert to mono
else
    workSound = Copy: "work_sound"
endif

# ============================================================
# STEP 1: DETECT SILENCES
# ============================================================
appendInfoLine: "[1/7] Detecting structural silences..."

@detectSilence: workSound
numDetectedSilences = detectSilence.numSilences

appendInfoLine: "  Found ", numDetectedSilences, " silence(s)"

# ============================================================
# STEP 2: SPECTRAL NOVELTY SECTION DETECTION
# ============================================================
appendInfoLine: "[2/7] Detecting sections via spectral novelty..."

selectObject: workSound
spectrogram = To Spectrogram: 0.01, 5000, 0.002, 20, "Gaussian"

analysisStep = 0.1
numAnalysisFrames = floor(inputDuration / analysisStep)

spectralNovelty# = zero# (numAnalysisFrames)
prevSpectrum# = zero# (100)

for i from 1 to numAnalysisFrames
    t = i * analysisStep

    selectObject: spectrogram
    currentSpectrum# = zero# (100)

    for freqBin from 1 to 100
        freq = freqBin * 50
        power = Get power at: t, freq
        if power = undefined
            power = 0
        endif
        currentSpectrum#[freqBin] = power
    endfor

    if i > 1
        difference = 0
        for freqBin from 1 to 100
            diff = abs(currentSpectrum#[freqBin] - prevSpectrum#[freqBin])
            difference = difference + diff
        endfor
        spectralNovelty#[i] = difference / 100
    endif

    prevSpectrum# = currentSpectrum#
endfor

removeObject: spectrogram

# Find section boundaries from novelty peaks
numSections = 0
sectionBoundaries# = zero# (200)
sectionBoundaries#[1] = 0
numSections = 1

for i from 2 to numAnalysisFrames - 1
    if spectralNovelty#[i] > novelty_threshold
        if spectralNovelty#[i] > spectralNovelty#[i-1] and spectralNovelty#[i] > spectralNovelty#[i+1]
            t = i * analysisStep
            if numSections = 1 or (t - sectionBoundaries#[numSections]) > min_section_duration_s
                numSections = numSections + 1
                sectionBoundaries#[numSections] = t
            endif
        endif
    endif
endfor

numSections = numSections + 1
sectionBoundaries#[numSections] = inputDuration

appendInfoLine: "  Detected ", numSections - 1, " section(s)"

# ============================================================
# STEP 3: ANALYZE EACH SECTION (with RMS preservation)
# ============================================================
appendInfoLine: "[3/7] Analyzing section characteristics..."

globalMaxRms = 0

for s from 1 to numSections - 1
    secStart_'s' = sectionBoundaries#[s]
    secEnd_'s' = sectionBoundaries#[s + 1]
    secDur_'s' = secEnd_'s' - secStart_'s'

    if secDur_'s' > max_section_duration_s
        secEnd_'s' = secStart_'s' + max_section_duration_s
        secDur_'s' = max_section_duration_s
    endif

    selectObject: workSound
    Extract part: secStart_'s', secEnd_'s', "Hanning", 1, "no"
    sectionSound = selected("Sound")

    @computeSpectralCentroid: sectionSound, 0, secDur_'s'
    secCentroid_'s' = computeSpectralCentroid.centroid

    @computeHarmonicity: sectionSound, 0, secDur_'s'
    secHarm_'s' = computeHarmonicity.harmValue

    @computeRMS: sectionSound
    secRms_'s' = computeRMS.rms

    if secRms_'s' > globalMaxRms
        globalMaxRms = secRms_'s'
    endif

    selectObject: sectionSound
    secEnergy_'s' = Get energy: 0, 0

    # Classify texture (1=tonal, 2=sparse, 3=bright, 4=dark, 5=noise)
    if secHarm_'s' > harmonicity_threshold
        secTexture_'s' = 1
    elsif secEnergy_'s' < 0.001
        secTexture_'s' = 2
    elsif secCentroid_'s' > spectral_centroid_high_hz
        secTexture_'s' = 3
    elsif secCentroid_'s' < spectral_centroid_low_hz
        secTexture_'s' = 4
    else
        secTexture_'s' = 5
    endif

    secSound_'s' = sectionSound

    textureCode = secTexture_'s'
    if textureCode = 1
        textureName$ = "tonal"
    elsif textureCode = 2
        textureName$ = "sparse"
    elsif textureCode = 3
        textureName$ = "bright"
    elsif textureCode = 4
        textureName$ = "dark"
    else
        textureName$ = "noise"
    endif

    appendInfoLine: "  Section ", s, ": ", fixed$(secStart_'s', 1), "-", fixed$(secEnd_'s', 1),
    ... "s | ", textureName$,
    ... " | centroid=", fixed$(secCentroid_'s', 0), "Hz",
    ... " | RMS=", fixed$(secRms_'s', 4)
endfor

actualNumSections = numSections - 1

# ============================================================
# STEP 4: FORM ARCHETYPE REORDERING
# ============================================================
appendInfoLine: ""
appendInfoLine: "[4/7] Applying form archetype..."

# Build section order array
# sectionOrder_N holds the original section index for position N
for s from 1 to actualNumSections
    sectionOrder_'s' = s
endfor

if reorder_mode = 1
    # None - keep original order
    appendInfoLine: "  Keeping original order."

elsif reorder_mode = 2
    # Arch form: sort by RMS to build toward peak, then mirror down
    appendInfoLine: "  Arch form: building to peak at ~", fixed$(arc_peak_position * 100, 0), "%"

    # Sort section indices by RMS (ascending)
    for i from 1 to actualNumSections
        rmsSortIdx_'i' = i
    endfor
    # Simple bubble sort by RMS
    for i from 1 to actualNumSections - 1
        for j from 1 to actualNumSections - i
            jNext = j + 1
            idxJ = rmsSortIdx_'j'
            idxJNext = rmsSortIdx_'jNext'
            if secRms_'idxJ' > secRms_'idxJNext'
                rmsSortIdx_'j' = idxJNext
                rmsSortIdx_'jNext' = idxJ
            endif
        endfor
    endfor

    # Place in arch: quietest at edges, loudest near peak position
    peakIdx = max(1, round(actualNumSections * arc_peak_position))
    leftCount = peakIdx
    rightCount = actualNumSections - peakIdx

    # Fill from loudest (end of sorted) placing at peak, then alternating outward
    for i from 1 to actualNumSections
        archPos_'i' = 0
    endfor

    # Start from the loudest and place at peak, then alternate left/right
    sortPos = actualNumSections
    placedLeft = 0
    placedRight = 0
    archPos_'peakIdx' = rmsSortIdx_'sortPos'
    sortPos = sortPos - 1

    leftSlot = peakIdx - 1
    rightSlot = peakIdx + 1
    toggle = 1

    while sortPos >= 1
        if toggle = 1 and leftSlot >= 1
            archPos_'leftSlot' = rmsSortIdx_'sortPos'
            leftSlot = leftSlot - 1
            sortPos = sortPos - 1
            toggle = 0
        elsif toggle = 0 and rightSlot <= actualNumSections
            archPos_'rightSlot' = rmsSortIdx_'sortPos'
            rightSlot = rightSlot + 1
            sortPos = sortPos - 1
            toggle = 1
        elsif leftSlot >= 1
            archPos_'leftSlot' = rmsSortIdx_'sortPos'
            leftSlot = leftSlot - 1
            sortPos = sortPos - 1
        elsif rightSlot <= actualNumSections
            archPos_'rightSlot' = rmsSortIdx_'sortPos'
            rightSlot = rightSlot + 1
            sortPos = sortPos - 1
        else
            sortPos = sortPos - 1
        endif
    endwhile

    for s from 1 to actualNumSections
        sectionOrder_'s' = archPos_'s'
    endfor

elsif reorder_mode = 3
    # Contrast maximization: greedy - always pick the most different next section
    appendInfoLine: "  Contrast maximization: maximizing adjacent texture difference"

    for s from 1 to actualNumSections
        contrastUsed_'s' = 0
    endfor

    # Start with the section that has the lowest centroid (darkest)
    bestStart = 1
    bestCent = secCentroid_1
    for s from 2 to actualNumSections
        if secCentroid_'s' < bestCent
            bestCent = secCentroid_'s'
            bestStart = s
        endif
    endfor

    sectionOrder_1 = bestStart
    contrastUsed_'bestStart' = 1

    for pos from 2 to actualNumSections
        prevPos = pos - 1
        prevSec = sectionOrder_'prevPos'
        bestNext = 0
        bestDist = -1

        for candidate from 1 to actualNumSections
            if contrastUsed_'candidate' = 0
                @textureDistance: secTexture_'prevSec', secTexture_'candidate',
                ... secCentroid_'prevSec', secCentroid_'candidate',
                ... secRms_'prevSec', secRms_'candidate'
                if textureDistance.distance > bestDist
                    bestDist = textureDistance.distance
                    bestNext = candidate
                endif
            endif
        endfor

        if bestNext > 0
            sectionOrder_'pos' = bestNext
            contrastUsed_'bestNext' = 1
        endif
    endfor

elsif reorder_mode = 4
    # Rondo: pick most distinctive section as refrain, interleave
    appendInfoLine: "  Rondo: selecting refrain and interleaving episodes"

    # Find the most "distinctive" section (highest harmonicity or most extreme centroid)
    refrainIdx = 1
    bestScore = 0
    for s from 1 to actualNumSections
        score = abs(secHarm_'s') + abs(secCentroid_'s' - 1500) / 1500
        if score > bestScore
            bestScore = score
            refrainIdx = s
        endif
    endfor

    appendInfoLine: "    Refrain = section ", refrainIdx

    # Build order: refrain, episode, refrain, episode, ...
    orderPos = 0
    episodeList# = zero# (actualNumSections)
    numEpisodes = 0
    for s from 1 to actualNumSections
        if s <> refrainIdx
            numEpisodes = numEpisodes + 1
            episodeList#[numEpisodes] = s
        endif
    endfor

    for ep from 1 to numEpisodes
        # Refrain
        orderPos = orderPos + 1
        sectionOrder_'orderPos' = refrainIdx
        # Episode
        orderPos = orderPos + 1
        epIdx = episodeList#[ep]
        sectionOrder_'orderPos' = epIdx
    endfor
    # Final refrain
    orderPos = orderPos + 1
    sectionOrder_'orderPos' = refrainIdx

    # Update actual count (rondo adds extra refrains)
    actualNumSections = orderPos

elsif reorder_mode = 5
    # Narrative: dark/low → building → bright/high → recall of opening → fade
    appendInfoLine: "  Narrative arc: dark → build → bright → recall → fade"

    # Sort by centroid (proxy for register/brightness)
    for i from 1 to actualNumSections
        centSortIdx_'i' = i
    endfor
    for i from 1 to actualNumSections - 1
        for j from 1 to actualNumSections - i
            jNext = j + 1
            idxJ = centSortIdx_'j'
            idxJNext = centSortIdx_'jNext'
            if secCentroid_'idxJ' > secCentroid_'idxJNext'
                centSortIdx_'j' = idxJNext
                centSortIdx_'jNext' = idxJ
            endif
        endfor
    endfor

    # Place: darkest first, brightest at ~70%, then recall darkest, end with sparse/quiet
    for s from 1 to actualNumSections
        sectionOrder_'s' = centSortIdx_'s'
    endfor

    # Append a recall of the opening section at the end
    actualNumSections = actualNumSections + 1
    sectionOrder_'actualNumSections' = centSortIdx_1

elsif reorder_mode = 6
    # Random swap (legacy behavior)
    appendInfoLine: "  Random swap"
    if actualNumSections >= 3
        numSwaps = randomInteger(1, max(1, floor(actualNumSections / 2)))
        for sw from 1 to numSwaps
            s1 = randomInteger(1, actualNumSections)
            s2 = randomInteger(1, actualNumSections)
            if s1 <> s2
                temp = sectionOrder_'s1'
                sectionOrder_'s1' = sectionOrder_'s2'
                sectionOrder_'s2' = temp
                appendInfoLine: "    Swapped positions ", s1, " ↔ ", s2
            endif
        endfor
    endif
endif

# Log the reordered sequence
appendInfoLine: "  Final order: "
order$ = "  "
for s from 1 to actualNumSections
    order$ = order$ + string$(sectionOrder_'s')
    if s < actualNumSections
        order$ = order$ + " → "
    endif
endfor
appendInfoLine: order$

# ============================================================
# STEP 5: PLAN ADDITIONAL OPERATIONS
# ============================================================
appendInfoLine: ""
appendInfoLine: "[5/7] Planning additional operations..."

numOperations = 0

for initIdx from 1 to 50
    opType_'initIdx' = 0
    opTarget_'initIdx' = 0
    opParam1_'initIdx' = 0
    opParam2_'initIdx' = 0
endfor

# Loop operation (on the reordered timeline)
if allow_looping and randomUniform(0, 1) < loop_probability and actualNumSections >= 2
    targetPos = randomInteger(1, actualNumSections)
    targetSec = sectionOrder_'targetPos'

    if secDur_'targetSec' >= 15 and secDur_'targetSec' <= 60
        numOperations = numOperations + 1
        opType_'numOperations' = 1
        opTarget_'numOperations' = targetPos
        opParam1_'numOperations' = randomInteger(2, 3)
        appendInfoLine: "  [LOOP] Position ", targetPos, " (section ", targetSec, ") × ", opParam1_'numOperations'
    endif
endif

# Context-aware silence insertion
# Insert after the highest-energy section, or before a recall
if allow_long_silences and randomUniform(0, 1) < silence_insert_probability
    # Find the position with highest RMS in the reordered timeline
    bestSilencePos = 1
    bestSilenceRms = 0
    for pos from 1 to actualNumSections - 1
        posSection = sectionOrder_'pos'
        if secRms_'posSection' > bestSilenceRms
            bestSilenceRms = secRms_'posSection'
            bestSilencePos = pos
        endif
    endfor

    # Scale silence duration to energy contrast
    nextPos = bestSilencePos + 1
    if nextPos <= actualNumSections
        nextSec = sectionOrder_'nextPos'
        peakSec = sectionOrder_'bestSilencePos'
        contrast = secRms_'peakSec' - secRms_'nextSec'
        if contrast < 0
            contrast = 0
        endif
        # Higher contrast → longer silence (3s base + up to silence_duration_range_s)
        silDuration = 3 + contrast / max(globalMaxRms, 0.001) * silence_duration_range_s
    else
        silDuration = 3 + randomUniform(0, 1) * silence_duration_range_s * 0.5
    endif

    numOperations = numOperations + 1
    opType_'numOperations' = 3
    opTarget_'numOperations' = bestSilencePos
    opParam1_'numOperations' = silDuration
    appendInfoLine: "  [SILENCE] Insert ", fixed$(silDuration, 1), "s after position ", bestSilencePos, " (post-peak breath)"
endif

# Time stretch - target sections with actual timbral content
if allow_time_stretching and randomUniform(0, 1) < stretch_probability and actualNumSections >= 2
    # Prefer tonal, bright, or noise sections (avoid stretching sparse)
    bestStretchPos = 0
    for pos from 1 to actualNumSections
        posSection = sectionOrder_'pos'
        posTex = secTexture_'posSection'
        if posTex <> 2
            if bestStretchPos = 0 or randomUniform(0, 1) < 0.4
                bestStretchPos = pos
            endif
        endif
    endfor

    if bestStretchPos = 0
        bestStretchPos = randomInteger(1, actualNumSections)
    endif

    # Choose factor from strategy range
    if randomUniform(0, 1) < 0.5
        stretchFactor = 1.0 + randomUniform(0, 1) * (stretch_factor_max - 1.0)
        direction$ = "slower"
    else
        stretchFactor = stretch_factor_min + randomUniform(0, 1) * (1.0 - stretch_factor_min)
        direction$ = "faster"
    endif

    numOperations = numOperations + 1
    opType_'numOperations' = 4
    opTarget_'numOperations' = bestStretchPos
    opParam1_'numOperations' = stretchFactor
    appendInfoLine: "  [STRETCH] Position ", bestStretchPos, " → ", fixed$(stretchFactor, 2), "× (", direction$, ")"
endif

# Material recall with transformation
if allow_material_recall and randomUniform(0, 1) < recall_probability and actualNumSections >= 3
    sourcePos = randomInteger(1, max(1, actualNumSections - 2))
    targetPosition = randomInteger(min(sourcePos + 1, actualNumSections), actualNumSections)

    numOperations = numOperations + 1
    opType_'numOperations' = 5
    opTarget_'numOperations' = sourcePos
    opParam1_'numOperations' = targetPosition
    appendInfoLine: "  [RECALL] Echo of position ", sourcePos, " after position ", targetPosition, " (transformed)"
endif

if numOperations > max_operations
    appendInfoLine: "  (limiting to ", max_operations, " operations)"
    numOperations = max_operations
endif

appendInfoLine: "  Total: ", numOperations, " additional operation(s)"

# ============================================================
# STEP 6: BUILD TIMELINE & EXECUTE
# ============================================================
appendInfoLine: ""
appendInfoLine: "[6/7] Building and assembling timeline..."

# Build initial timeline from reordered sections
maxTimelineItems = 200
for init from 1 to maxTimelineItems
    timelineType_'init' = 0
    timelineSectionIdx_'init' = 0
    timelineParam_'init' = 0
endfor

numTimelineItems = 0

for s from 1 to actualNumSections
    numTimelineItems = numTimelineItems + 1
    timelineType_'numTimelineItems' = 0
    timelineSectionIdx_'numTimelineItems' = sectionOrder_'s'
    timelineParam_'numTimelineItems' = 0
endfor

# Apply operations to timeline
for op from 1 to numOperations
    opType = opType_'op'
    opTarget = opTarget_'op'
    opParam1 = opParam1_'op'

    if opType = 1
        # Loop: insert copies after target position
        loopCount = opParam1
        insertPos = min(opTarget, numTimelineItems)

        if insertPos > 0
            targetSecIdx = timelineSectionIdx_'insertPos'
            newNumItems = numTimelineItems + loopCount - 1
            for t from 1 to insertPos
                newType_'t' = timelineType_'t'
                newIdx_'t' = timelineSectionIdx_'t'
                newParam_'t' = timelineParam_'t'
            endfor

            for rep from 1 to loopCount - 1
                repPos = insertPos + rep
                newType_'repPos' = 0
                newIdx_'repPos' = targetSecIdx
                newParam_'repPos' = 0
            endfor

            for t from insertPos + 1 to numTimelineItems
                newPos = t + loopCount - 1
                newType_'newPos' = timelineType_'t'
                newIdx_'newPos' = timelineSectionIdx_'t'
                newParam_'newPos' = timelineParam_'t'
            endfor

            for t from 1 to newNumItems
                timelineType_'t' = newType_'t'
                timelineSectionIdx_'t' = newIdx_'t'
                timelineParam_'t' = newParam_'t'
            endfor
            numTimelineItems = newNumItems
        endif

    elsif opType = 3
        # Silence: insert after target position
        insertPos = min(opTarget, numTimelineItems)

        if insertPos > 0
            newNumItems = numTimelineItems + 1

            for t from 1 to insertPos
                newType_'t' = timelineType_'t'
                newIdx_'t' = timelineSectionIdx_'t'
                newParam_'t' = timelineParam_'t'
            endfor

            silPos = insertPos + 1
            newType_'silPos' = 3
            newIdx_'silPos' = 0
            newParam_'silPos' = opParam1

            for t from insertPos + 1 to numTimelineItems
                newPos = t + 1
                newType_'newPos' = timelineType_'t'
                newIdx_'newPos' = timelineSectionIdx_'t'
                newParam_'newPos' = timelineParam_'t'
            endfor

            for t from 1 to newNumItems
                timelineType_'t' = newType_'t'
                timelineSectionIdx_'t' = newIdx_'t'
                timelineParam_'t' = newParam_'t'
            endfor
            numTimelineItems = newNumItems
        endif

    elsif opType = 4
        # Time stretch: mark position for stretching
        stretchPos = min(opTarget, numTimelineItems)
        if stretchPos > 0
            timelineType_'stretchPos' = 4
            timelineParam_'stretchPos' = opParam1
        endif

    elsif opType = 5
        # Recall: insert transformed copy after target position
        sourcePos = min(opTarget, numTimelineItems)
        afterPos = min(opParam1, numTimelineItems)

        if sourcePos > 0 and afterPos > 0
            sourceSec = timelineSectionIdx_'sourcePos'
            newNumItems = numTimelineItems + 1

            for t from 1 to afterPos
                newType_'t' = timelineType_'t'
                newIdx_'t' = timelineSectionIdx_'t'
                newParam_'t' = timelineParam_'t'
            endfor

            recallPos = afterPos + 1
            newType_'recallPos' = 5
            newIdx_'recallPos' = sourceSec
            newParam_'recallPos' = 0

            for t from afterPos + 1 to numTimelineItems
                newPos = t + 1
                newType_'newPos' = timelineType_'t'
                newIdx_'newPos' = timelineSectionIdx_'t'
                newParam_'newPos' = timelineParam_'t'
            endfor

            for t from 1 to newNumItems
                timelineType_'t' = newType_'t'
                timelineSectionIdx_'t' = newIdx_'t'
                timelineParam_'t' = newParam_'t'
            endfor
            numTimelineItems = newNumItems
        endif
    endif
endfor

# ----------------------------------------------------------
# Extract noise tail from source for organic silences
# ----------------------------------------------------------
if silence_mode = 2
    # Get a short segment from near the end of the source, filter it down
    selectObject: workSound
    tailStart = max(0, inputDuration - 2.0)
    Extract part: tailStart, inputDuration, "Hanning", 1, "no"
    noiseTailRaw = selected("Sound")

    # Heavy low-pass to get just rumble/ambience
    selectObject: noiseTailRaw
    Filter (pass Hann band): 0, 400, 50
    noiseTailFiltered = selected("Sound")
    removeObject: noiseTailRaw

    # Scale very quiet
    selectObject: noiseTailFiltered
    Scale peak: 0.02
    noiseTailTemplate = noiseTailFiltered
    noiseTailDur = Get total duration
endif

# ----------------------------------------------------------
# Assemble timeline items into Sound objects
# ----------------------------------------------------------

for t from 1 to numTimelineItems
    itemType = timelineType_'t'
    secIdx = timelineSectionIdx_'t'
    param = timelineParam_'t'

    # Safety: skip invalid entries
    if secIdx < 1 and itemType <> 3
        Create Sound from formula: "skip_'t'", 1, 0, 0.01, sampleRate, "0"
        timelineSound_'t' = selected("Sound")
        timelineTexture_'t' = 0

    elsif itemType = 0 or itemType = 4
        # Regular section or stretched section
        selectObject: secSound_'secIdx'
        Copy: "timeline_item_'t'"
        itemSound = selected("Sound")

        if itemType = 4
            # Apply time stretch
            selectObject: itemSound
            itemDur = Get total duration
            pitchFloor = 75
            if itemDur > 0
                safePitchFloor = max(pitchFloor, 3.0 / itemDur + 5)
                To Manipulation: 0.01, safePitchFloor, 600
                manipObj = selected("Manipulation")
                Extract duration tier
                durTier = selected("DurationTier")
                Add point: 0, param
                selectObject: manipObj
                plusObject: durTier
                Replace duration tier
                selectObject: manipObj
                Get resynthesis (overlap-add)
                stretched = selected("Sound")
                removeObject: manipObj, durTier, itemSound
                itemSound = stretched
            endif
        endif

        # v4.0: NO per-block normalization - preserve original dynamics
        # Only apply a gentle safety limiter if peak exceeds 1.0
        selectObject: itemSound
        peakAbs = Get absolute extremum: 0, 0, "None"
        if peakAbs > 1.0
            Scale peak: 0.99
        endif

        timelineSound_'t' = itemSound
        timelineTexture_'t' = secTexture_'secIdx'

    elsif itemType = 5
        # RECALL: transformed copy of a section
        selectObject: secSound_'secIdx'
        Copy: "recall_item_'t'"
        itemSound = selected("Sound")

        # Optional reverse
        if recall_allow_reverse and randomUniform(0, 1) < 0.35
            selectObject: itemSound
            Reverse
            appendInfoLine: "    Recall at position ", t, ": reversed"
        endif

        # Optional low-pass filter (sounds "distant" / "remembered")
        if recall_apply_lowpass
            selectObject: itemSound
            Filter (pass Hann band): 0, recall_lowpass_hz, 200
            filteredRecall = selected("Sound")
            removeObject: itemSound
            itemSound = filteredRecall
        endif

        # Reduce amplitude (it's an echo, not a repetition)
        if recall_reduce_amplitude
            selectObject: itemSound
            Multiply: recall_amplitude_factor
        endif

        # Safety limiter
        selectObject: itemSound
        peakAbs = Get absolute extremum: 0, 0, "None"
        if peakAbs > 1.0
            Scale peak: 0.99
        endif

        timelineSound_'t' = itemSound
        timelineTexture_'t' = secTexture_'secIdx'

    elsif itemType = 3
        # Silence
        silDur = param

        if silence_mode = 2 and silDur > 0.1
            # Build organic silence from noise tail
            selectObject: noiseTailTemplate
            Copy: "organic_silence_'t'"
            orgSil = selected("Sound")

            # If needed, extend by concatenating copies
            selectObject: orgSil
            currentSilDur = Get total duration
            while currentSilDur < silDur
                selectObject: orgSil, noiseTailTemplate
                Concatenate
                temp = selected("Sound")
                removeObject: orgSil
                orgSil = temp
                selectObject: orgSil
                currentSilDur = Get total duration
            endwhile

            # Trim to exact duration
            selectObject: orgSil
            Extract part: 0, silDur, "Hanning", 1, "no"
            trimmedSil = selected("Sound")
            removeObject: orgSil

            # Apply fade envelope
            selectObject: trimmedSil
            fadeDur = min(0.5, silDur * 0.2)
            Fade in: 0, 0, fadeDur, "yes"
            Fade out: 0, silDur, -fadeDur, "yes"

            timelineSound_'t' = trimmedSil
        else
            Create Sound from formula: "silence_'t'", 1, 0, silDur, sampleRate, "0"
            timelineSound_'t' = selected("Sound")
        endif

        timelineTexture_'t' = 0
    endif
endfor

# ----------------------------------------------------------
# Concatenate with texture-aware crossfades
# ----------------------------------------------------------
appendInfoLine: "  Concatenating with texture-aware crossfades..."

selectObject: timelineSound_1
finalOutput = Copy: "assembling"

for t from 2 to numTimelineItems
    tPrev = t - 1
    fromTex = timelineTexture_'tPrev'
    toTex = timelineTexture_'t'

    @getCrossfadeDuration: fromTex, toTex
    targetCrossfade = getCrossfadeDuration.duration

    selectObject: finalOutput
    currentDur = Get total duration
    selectObject: timelineSound_'t'
    nextDur = Get total duration

    minDur = min(currentDur, nextDur)
    safeCrossfade = min(targetCrossfade, minDur * 0.4)

    if safeCrossfade > 0.002 and currentDur > safeCrossfade * 2 and nextDur > safeCrossfade * 2
        selectObject: finalOutput, timelineSound_'t'
        Concatenate with overlap: safeCrossfade
        temp = selected("Sound")
        removeObject: finalOutput
        finalOutput = temp
    else
        selectObject: finalOutput, timelineSound_'t'
        Concatenate
        temp = selected("Sound")
        removeObject: finalOutput
        finalOutput = temp
    endif
endfor

# Cleanup timeline sounds
for t from 1 to numTimelineItems
    removeObject: timelineSound_'t'
endfor

# Cleanup noise tail template if created
if silence_mode = 2
    removeObject: noiseTailTemplate
endif

# ============================================================
# STEP 7: TENSION ARC ENVELOPE
# ============================================================
appendInfoLine: "[7/7] Applying tension arc..."

selectObject: finalOutput
outputDuration = Get total duration

if apply_tension_arc
    # Build a macro-dynamic envelope that shapes the whole piece
    # Arc peaks at arc_peak_position, with exaggeration factor
    #
    # The envelope MULTIPLIES existing dynamics, so:
    #   - sections that were quiet stay relatively quieter
    #   - sections that were loud stay relatively louder
    #   - but the overall shape follows the arc
    #
    # arc_exaggeration > 1 increases the dynamic range
    # arc_exaggeration = 1 preserves it
    # arc_exaggeration < 1 compresses it (not recommended)

    selectObject: finalOutput
    Formula: ~ self * (0.3 + 0.7 * (if x/outputDuration <= arc_peak_position then x/outputDuration/arc_peak_position else 1-(x/outputDuration-arc_peak_position)/(1-arc_peak_position) fi) ^ (1/arc_exaggeration))

    appendInfoLine: "  Applied tension arc (peak at ", fixed$(arc_peak_position * 100, 0), "%, exaggeration=", fixed$(arc_exaggeration, 1), ")"
else
    appendInfoLine: "  Tension arc: off"
endif

selectObject: finalOutput
Rename: "DramaturgicalComposer_v4_out"

# Final safety limiter only (no normalization)
peakAbs = Get absolute extremum: 0, 0, "None"
if peakAbs > 1.0
    Scale peak: 0.99
endif

finalOutput = selected("Sound")
outputDuration = Get total duration

appendInfoLine: ""
appendInfoLine: "  Output: ", fixed$(outputDuration, 2), " s (input was ", fixed$(inputDuration, 2), " s)"

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: "Creating visualization..."

    Erase all

    # --- Title ---
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half", "##Dramaturgical Structure Composer v4.0##"
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"

    if reorder_mode = 2
        reorderLabel$ = "Arch"
    elsif reorder_mode = 3
        reorderLabel$ = "Contrast"
    elsif reorder_mode = 4
        reorderLabel$ = "Rondo"
    elsif reorder_mode = 5
        reorderLabel$ = "Narrative"
    elsif reorder_mode = 6
        reorderLabel$ = "Random"
    else
        reorderLabel$ = "None"
    endif

    Text: 0.5, "centre", -0.6, "half", inputName$ + " | " + strategyName$ + " | " + reorderLabel$ + " | " + string$(actualNumSections) + " sections, " + string$(numOperations) + " ops"

    # --- Original sections ---
    Select outer viewport: 0, 8, 0.6, 2.0
    Select inner viewport: 0.6, 7.7, 0.7, 1.9

    Axes: 0, inputDuration, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, inputDuration, 0, 1

    origNumSections = numSections - 1
    for s from 1 to origNumSections
        sStart = secStart_'s'
        sEnd = secEnd_'s'
        textureCode = secTexture_'s'

        if textureCode = 1
            Paint rectangle: "{0.7, 0.9, 1.0}", sStart, sEnd, 0, 1
        elsif textureCode = 5
            Paint rectangle: "{1.0, 0.9, 0.7}", sStart, sEnd, 0, 1
        elsif textureCode = 2
            Paint rectangle: "{0.9, 0.9, 0.9}", sStart, sEnd, 0, 1
        elsif textureCode = 3
            Paint rectangle: "{1.0, 1.0, 0.8}", sStart, sEnd, 0, 1
        else
            Paint rectangle: "{0.8, 0.8, 0.9}", sStart, sEnd, 0, 1
        endif

        # Show RMS as bar height
        if globalMaxRms > 0
            rmsHeight = secRms_'s' / globalMaxRms
        else
            rmsHeight = 0.5
        endif
        Colour: "{0.3, 0.3, 0.5}"
        Paint rectangle: "{0.3, 0.3, 0.5}", sStart + 0.5, sEnd - 0.5, 0, rmsHeight * 0.3

        Colour: "Black"
        Line width: 2
        Draw line: sStart, 0, sStart, 1
        Line width: 1

        # Section number label
        Font size: 6
        midT = (sStart + sEnd) / 2
        Text: midT, "centre", 0.85, "half", string$(s)
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Detected Sections (color=texture, bar=energy)"

    # --- Output waveform ---
    Select outer viewport: 0, 8, 2.1, 3.3
    Select inner viewport: 0.6, 7.7, 2.2, 3.2

    selectObject: finalOutput
    Colour: "{0.3, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"

    arcLabel$ = ""
    if apply_tension_arc
        arcLabel$ = " | arc=" + fixed$(arc_peak_position, 2)
    endif
    Text top: "no", fixed$(outputDuration, 2) + " s | " + string$(numOperations) + " ops" + arcLabel$

    # --- Tension arc overlay ---
    if apply_tension_arc
        Select outer viewport: 0, 8, 3.4, 4.2
        Select inner viewport: 0.6, 7.7, 3.5, 4.1
        Axes: 0, 1, 0, 1

        Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1

        Colour: "{0.8, 0.3, 0.3}"
        Line width: 2
        numDrawPoints = 100
        for dp from 1 to numDrawPoints - 1
            x1 = (dp - 1) / numDrawPoints
            x2 = dp / numDrawPoints

            if x1 <= arc_peak_position
                y1 = x1 / arc_peak_position
            else
                y1 = 1.0 - (x1 - arc_peak_position) / (1.0 - arc_peak_position)
            endif
            y1 = y1 ^ (1.0 / arc_exaggeration)
            y1 = 0.3 + 0.7 * y1

            if x2 <= arc_peak_position
                y2 = x2 / arc_peak_position
            else
                y2 = 1.0 - (x2 - arc_peak_position) / (1.0 - arc_peak_position)
            endif
            y2 = y2 ^ (1.0 / arc_exaggeration)
            y2 = 0.3 + 0.7 * y2

            Draw line: x1, y1, x2, y2
        endfor

        Line width: 1
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Arc"
        Text top: "no", "Tension arc envelope (peak at " + fixed$(arc_peak_position * 100, 0) + "%)"
    endif

    Font size: 10
    Colour: "Black"
endif

# ============================================================
# CLEANUP
# ============================================================

if keep_debug_objects = 0
    removeObject: workSound
    for s from 1 to numSections - 1
        removeObject: secSound_'s'
    endfor
endif

selectObject: finalOutput

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=============================================="

if play_output
    Play
endif
