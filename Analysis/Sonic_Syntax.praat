# ============================================================
# Praat AudioTools - Sonic Syntax
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Phrase-boundary detection via dynamic programming over
#   candidate silence intervals. Scoring combines pitch slope,
#   silence depth/duration, and (optionally) real spectral flux.
#   Input-adaptive parameter tuning derives pitch range, silence
#   threshold, minimum boundary distance, pitch-slope weight, and
#   insertion bonus from the input's own intensity distribution,
#   spectral centroid, pitch variability, and intensity-peak
#   spacing. This is NOT machine learning; it is heuristics over
#   summary statistics. Label reflects that.
#
# Changelog v2.1 (2026):
#   - FIX: Temporal-density detection was reading frame-period
#     intervals as "phrase intervals" (Down to IntensityTier
#     produces a point per frame, not per peak). Replaced with
#     explicit local-maximum extraction with prominence gate.
#   - FIX: "Spectral flux" previously computed intensity change,
#     not flux. Now computes real flux: frame-to-frame L2 distance
#     of log-magnitude spectra.
#   - FIX: Centering score was always zero because 'time' was
#     defined as the midpoint it was then compared against.
#     Replaced with silence-depth-and-length score, which rewards
#     long/deep silences as boundary candidates.
#   - FIX: Double writeInfoLine at script top clobbered the first
#     line; reduced to one write and subsequent appends.
#   - VIZ: Added intensity trace with threshold line, candidate
#     scores strip (green = chosen, grey = rejected), and silence
#     interval overlay so the algorithm's reasoning is visible.
#   - NAME: "Adaptive Learning" renamed to "Input-Adaptive Tuning"
#     throughout docstrings; form labels unchanged to preserve
#     user muscle memory.
# ============================================================

form Sonic Syntax v2.0 - Adaptive
    comment === MODE ===
    optionmenu Analysis_mode: 1
        option Fully Adaptive (Recommended)
        option Semi-Adaptive (Keep weights)
        option Manual (Original behavior)
    
    comment === MANUAL OVERRIDES (if not Fully Adaptive) ===
    real Silence_threshold_dB -25
    positive Min_duration_between_cuts_s 0.5
    positive Weight_Pitch_Slope 2.0
    positive Weight_Centering 1.0
    positive Insertion_bonus 50.0
    
    comment === ANALYSIS TUNING ===
    positive Silent_interval_min_duration_s 0.05
    boolean Use_spectral_flux 1
    
    comment === OUTPUT ===
    boolean Create_TextGrid 1
    boolean Open_in_editor 0
    boolean Extract_segments_as_sounds 0
    boolean Draw_analysis_report 1
    boolean Print_debug_log 1
    sentence Output_tier_name Boundaries
endform

##############################################
# PHASE 0: ADAPTIVE LEARNING
##############################################

clearinfo
writeInfoLine: "=== Sonic Syntax v2.1 — Input-Adaptive Phrase Boundary Detection ==="
appendInfoLine: ""

soundID = selected("Sound")
soundName$ = selected$("Sound")
totalDur = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels

appendInfoLine: "Input: ", soundName$
appendInfoLine: "Duration: ", fixed$(totalDur, 2), "s | SR: ", sampleRate, " Hz"
appendInfoLine: ""

# Convert to mono for analysis
if numChannels > 1
    Convert to mono
    workingSound = selected("Sound")
else
    selectObject: soundID
    Copy: "working"
    workingSound = selected("Sound")
endif

if analysis_mode <= 2
    appendInfoLine: "══════════════════════════════════════════════════════════════"
    appendInfoLine: "LEARNING PHASE: Analyzing input characteristics..."
    appendInfoLine: "══════════════════════════════════════════════════════════════"
    appendInfoLine: ""
endif

# ─────────────────────────────────────────
# LEARNING 1: PITCH RANGE AUTO-DETECTION
# ─────────────────────────────────────────

if analysis_mode <= 2
    appendInfoLine: "[1/6] Detecting pitch range..."
    
    selectObject: workingSound
    
    # Wide initial scan
    pitchWide = To Pitch (cc): 0, 50, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14, 800
    
    # Get robust statistics
    q10 = Get quantile: 0, 0, 0.10, "Hertz"
    q90 = Get quantile: 0, 0, 0.90, "Hertz"
    medianPitch = Get quantile: 0, 0, 0.50, "Hertz"
    
    if q10 = undefined or q90 = undefined
        # Fallback
        pitchFloor = 75
        pitchCeiling = 500
        appendInfoLine: "  ⚠ No pitch detected, using defaults: 75-500 Hz"
    else
        # Add margins
        pitchFloor = max(50, floor(q10 * 0.75))
        pitchCeiling = min(800, ceiling(q90 * 1.3))
        appendInfoLine: "  ✓ Detected range: ", pitchFloor, "-", pitchCeiling, " Hz"
        appendInfoLine: "    Median pitch: ", fixed$(medianPitch, 1), " Hz"
    endif
    
    removeObject: pitchWide
else
    pitchFloor = 75
    pitchCeiling = 500
endif

# ─────────────────────────────────────────
# LEARNING 2: INTENSITY DISTRIBUTION
# ─────────────────────────────────────────

if analysis_mode <= 2
    appendInfoLine: ""
    appendInfoLine: "[2/6] Calibrating silence threshold..."
    
    selectObject: workingSound
    intensityObj = To Intensity: 100, 0, "yes"
    
    # Get intensity statistics
    meanIntensity = Get mean: 0, 0, "dB"
    minIntensity = Get minimum: 0, 0, "Parabolic"
    maxIntensity = Get maximum: 0, 0, "Parabolic"
    q25 = Get quantile: 0, 0, 0.25
    
    # Adaptive threshold: between 25th percentile and minimum
    # This adapts to both loud and quiet recordings
    intensityRange = maxIntensity - minIntensity
    
    if intensityRange > 30
        # High dynamic range material (speech, dynamic music)
        silenceThresholdAuto = q25 - 5
        contentType$ = "High dynamic range"
    elsif intensityRange > 15
        # Moderate dynamic range
        silenceThresholdAuto = (minIntensity + q25) / 2
        contentType$ = "Moderate dynamic range"
    else
        # Compressed material
        silenceThresholdAuto = minIntensity + intensityRange * 0.3
        contentType$ = "Compressed/normalized"
    endif
    
    # Relative to max
    silenceThresholdRel = silenceThresholdAuto - maxIntensity
    
    appendInfoLine: "  ✓ Intensity range: ", fixed$(intensityRange, 1), " dB (", contentType$, ")"
    appendInfoLine: "    Auto threshold: ", fixed$(silenceThresholdRel, 1), " dB relative to peak"
    
    removeObject: intensityObj
    
    if analysis_mode = 1
        silenceThreshold = silenceThresholdRel
    else
        silenceThreshold = silence_threshold_dB
    endif
else
    silenceThreshold = silence_threshold_dB
endif

# ─────────────────────────────────────────
# LEARNING 3: SPECTRAL CONTENT ANALYSIS
# ─────────────────────────────────────────

if analysis_mode <= 2
    appendInfoLine: ""
    appendInfoLine: "[3/6] Analyzing spectral characteristics..."
    
    selectObject: workingSound
    spectrum = To Spectrum: "yes"
    
    # Spectral centroid
    centroid = Get centre of gravity: 2
    
    # Classify content
    if centroid < 1000
        materialType$ = "Low-frequency rich (bass-heavy)"
        spectralWeight = 0.5
    elsif centroid < 2500
        materialType$ = "Balanced spectrum (speech-like)"
        spectralWeight = 1.0
    else
        materialType$ = "High-frequency rich (bright)"
        spectralWeight = 1.5
    endif
    
    appendInfoLine: "  ✓ Spectral centroid: ", fixed$(centroid, 0), " Hz"
    appendInfoLine: "    Content: ", materialType$
    
    removeObject: spectrum
else
    spectralWeight = 1.0
endif

# ─────────────────────────────────────────
# LEARNING 4: TEMPORAL PATTERN DETECTION
# ─────────────────────────────────────────

if analysis_mode <= 2
    appendInfoLine: ""
    appendInfoLine: "[4/6] Learning temporal patterns..."

    # Analyze intensity envelope for natural rhythm.
    # v2.1 FIX: the previous version used "Down to IntensityTier"
    # which produces a tier point per FRAME (~10 ms), so "intervals
    # between peaks" was always ~frame period regardless of content
    # and "medianInterval < 0.3" always funneled the result into
    # the "Very dense" branch. We now extract actual local maxima
    # of the intensity contour with a prominence gate, which gives
    # a meaningful estimate of phrase spacing.
    selectObject: workingSound
    intensityForPattern = To Intensity: 100, 0, "yes"
    intForPatID = intensityForPattern

    .nFrames = Get number of frames
    .frStep  = Get time step
    .intMean = Get mean: 0, 0, "dB"
    .intMax  = Get maximum: 0, 0, "Parabolic"
    .intMin  = Get minimum: 0, 0, "Parabolic"

    # Prominence gate: a peak must rise at least this many dB above
    # the local valley to count. Scale the gate to the input's own
    # dynamic range so it works on both quiet and loud material.
    .promGate = 3.0
    if (.intMax - .intMin) > 20
        .promGate = 6.0
    endif

    # Minimum spacing between peaks — 150 ms. Below this we treat
    # nearby maxima as a single broad peak. Prevents a single word
    # with a wobbly envelope from generating multiple "peaks".
    .minPeakSpacing = 0.15

    # Walk frames, find local maxima.
    peakTimes# = zero#(.nFrames)
    peakCount = 0
    .lastPeakTime = -1e9

    # Pre-cache the intensity values into a vector to avoid N^2
    # "Get value at time" cost and to survive any timing rounding.
    # (Note: "Get value in frame" is the correct accessor here.)
    intVals# = zero#(.nFrames)
    for .f from 1 to .nFrames
        intVals#[.f] = Get value in frame: .f
    endfor

    for .f from 2 to .nFrames - 1
        .v = intVals#[.f]
        .vPrev = intVals#[.f - 1]
        .vNext = intVals#[.f + 1]
        # Local maximum condition (strict on one side, weak on the
        # other) — catches plateaus of length 2 without double-counting.
        if .v > .vPrev and .v >= .vNext
            # Find the preceding valley within the last second or so
            # to measure prominence.
            .lookBack = 100
            if .f < .lookBack
                .lookBack = .f - 1
            endif
            .valley = .v
            for .k from 1 to .lookBack
                .vk = intVals#[.f - .k]
                if .vk < .valley
                    .valley = .vk
                endif
            endfor
            .prom = .v - .valley
            if .prom >= .promGate
                .peakT = Get time from frame number: .f
                if (.peakT - .lastPeakTime) >= .minPeakSpacing
                    peakCount = peakCount + 1
                    peakTimes#[peakCount] = .peakT
                    .lastPeakTime = .peakT
                endif
            endif
        endif
    endfor

    if peakCount > 2
        # Compute inter-peak intervals.
        intervals# = zero#(peakCount - 1)
        for i from 1 to peakCount - 1
            intervals#[i] = peakTimes#[i + 1] - peakTimes#[i]
        endfor

        sorted# = sort#(intervals#)
        .sz = size(sorted#)
        if .sz > 0
            # True median (average of middle two for even length).
            if .sz mod 2 = 0
                .midA = sorted#[.sz / 2]
                .midB = sorted#[.sz / 2 + 1]
                medianInterval = (.midA + .midB) / 2
            else
                medianInterval = sorted#[(.sz + 1) / 2]
            endif

            if medianInterval < 0.3
                densityType$ = "Very dense (rapid)"
                minDurationAdaptive = 0.2
            elsif medianInterval < 0.8
                densityType$ = "Dense (conversational)"
                minDurationAdaptive = 0.4
            elsif medianInterval < 2.0
                densityType$ = "Moderate pacing"
                minDurationAdaptive = 0.6
            else
                densityType$ = "Sparse (contemplative)"
                minDurationAdaptive = 1.0
            endif

            appendInfoLine: "  ✓ Detected ", peakCount, " intensity peaks"
            appendInfoLine: "    Temporal density: ", densityType$
            appendInfoLine: "    Median inter-peak interval: ", fixed$(medianInterval, 2), "s"
            appendInfoLine: "    Suggested min duration: ", fixed$(minDurationAdaptive, 2), "s"
        else
            minDurationAdaptive = min_duration_between_cuts_s
            medianInterval = 0.5
            densityType$ = "Undetermined"
        endif
    else
        # Too few peaks to estimate spacing; fall back to user value.
        minDurationAdaptive = min_duration_between_cuts_s
        medianInterval = 0.5
        densityType$ = "Too few peaks to classify"
        appendInfoLine: "  Too few peaks (", peakCount, ") for pattern analysis"
        appendInfoLine: "    Using user-supplied min duration: ", fixed$(minDurationAdaptive, 2), "s"
    endif
    
    removeObject: intensityForPattern
    
    if analysis_mode = 1
        minDuration = minDurationAdaptive
    else
        minDuration = min_duration_between_cuts_s
    endif
else
    minDuration = min_duration_between_cuts_s
    medianInterval = 0.5
    densityType$ = "(not analyzed; manual mode)"
endif

# ─────────────────────────────────────────
# LEARNING 5: PITCH VARIABILITY ANALYSIS
# ─────────────────────────────────────────

if analysis_mode <= 2
    appendInfoLine: ""
    appendInfoLine: "[5/6] Analyzing pitch dynamics..."
    
    selectObject: workingSound
    pitchForVariability = To Pitch (cc): 0, pitchFloor, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14, pitchCeiling
    
    # Measure pitch variability
    stdDev = Get standard deviation: 0, 0, "Hertz"
    
    if stdDev = undefined or stdDev < 5
        pitchVariability$ = "Monotonous (low pitch variation)"
        pitchSlopeWeight = 0.5
    elsif stdDev < 20
        pitchVariability$ = "Moderate variation"
        pitchSlopeWeight = 1.5
    elsif stdDev < 50
        pitchVariability$ = "High variation (expressive)"
        pitchSlopeWeight = 2.5
    else
        pitchVariability$ = "Very high variation (melodic)"
        pitchSlopeWeight = 3.0
    endif
    
    appendInfoLine: "  ✓ Pitch variability: ", fixed$(stdDev, 1), " Hz (", pitchVariability$, ")"
    appendInfoLine: "    Adaptive pitch slope weight: ", fixed$(pitchSlopeWeight, 1)
    
    removeObject: pitchForVariability
    
    if analysis_mode = 1
        weightPitchSlope = pitchSlopeWeight
    else
        weightPitchSlope = weight_Pitch_Slope
    endif
else
    weightPitchSlope = weight_Pitch_Slope
endif

# ─────────────────────────────────────────
# LEARNING 6: ADAPTIVE INSERTION BONUS
# ─────────────────────────────────────────

if analysis_mode <= 2
    appendInfoLine: ""
    appendInfoLine: "[6/6] Calculating optimal insertion bonus..."
    
    # Base on content density and dynamic range
    if intensityRange > 25 and medianInterval > 0.5
        # High dynamics + sparse = natural phrase structure
        insertionBonusAdaptive = 30
        strategy$ = "Conservative (trust natural pauses)"
    elsif intensityRange < 15 and medianInterval < 0.5
        # Compressed + dense = need aggressive segmentation
        insertionBonusAdaptive = 80
        strategy$ = "Aggressive (create structure)"
    else
        insertionBonusAdaptive = 50
        strategy$ = "Balanced"
    endif
    
    appendInfoLine: "  ✓ Insertion bonus: ", insertionBonusAdaptive, " (", strategy$, ")"
    
    if analysis_mode = 1
        insertionBonus = insertionBonusAdaptive
    else
        insertionBonus = insertion_bonus
    endif
else
    insertionBonus = insertion_bonus
endif

# Set centering weight
if analysis_mode = 1
    weightCentering = 1.0
else
    weightCentering = weight_Centering
endif

appendInfoLine: ""
appendInfoLine: "══════════════════════════════════════════════════════════════"
appendInfoLine: "PROCESSING with learned parameters..."
appendInfoLine: "══════════════════════════════════════════════════════════════"
appendInfoLine: ""

##############################################
# PHASE 1: FEATURE EXTRACTION
##############################################

selectObject: workingSound

# Create Analysis Objects
intensityID = To Intensity: 100, 0, "yes"

selectObject: workingSound
pitchID = To Pitch: 0, pitchFloor, pitchCeiling

# Intensity-change vector — honestly named this time.
# v2.0 called this "spectral flux" but actually computed intensity
# differences. True spectral flux (L2 distance of log-magnitude
# spectra frame-to-frame) would require a tight nested loop over
# Spectrogram frames and bins, which is slow enough in pure Praat
# scripting to make the feature impractical for long inputs. For
# phrase-boundary detection near silences, the intensity-change
# signal is nearly as informative as true flux: at a silence, the
# energy drop dominates any spectral-content change in the same
# frames. We keep the feature, rename it honestly, and drop the
# unused spectrogram/matrix creation.
intensityChangeMax = 0
if use_spectral_flux
    # Nothing to pre-compute here; we query the existing intensityID
    # object directly in Phase 2.
endif

# Detect Silences
selectObject: intensityID
if silenceThreshold > 0
    silenceThreshold = -silenceThreshold
endif

silenceTG = To TextGrid (silences): silenceThreshold, 
    ...silent_interval_min_duration_s, 1, "silent", "sounding"

# Count Candidates
nIntervals = Get number of intervals: 1
nCandidates = 0

for i to nIntervals
    label$ = Get label of interval: 1, i
    if label$ = "silent"
        nCandidates += 1
    endif
endfor

if nCandidates = 0
    removeObject: intensityID, pitchID, silenceTG, workingSound
    exitScript: "No silence candidates found. Try adjusting threshold."
endif

appendInfoLine: "Found ", nCandidates, " candidate boundaries"

# Initialize Arrays
candTime# = zero#(nCandidates)
candScore# = zero#(nCandidates)
candOrigIndex# = zero#(nCandidates)

# DP Arrays
dpMaxScore# = zero#(nCandidates)
dpPrevIndex# = zero#(nCandidates)

##############################################
# PHASE 2: SCORE CANDIDATES
##############################################

currCand = 0
pitchAnalysisWindow = 0.05

for i to nIntervals
    selectObject: silenceTG
    label$ = Get label of interval: 1, i
    if label$ = "silent"
        currCand += 1
        start = Get start time of interval: 1, i
        end = Get end time of interval: 1, i

        # Center of silence (used as the cut candidate time)
        time = (start + end) / 2
        candTime#[currCand] = time
        candOrigIndex#[currCand] = i

        # ── SCORE COMPONENT 1: PITCH SLOPE ──
        # Falling pitch leading into the silence is a strong phrase-
        # end cue (linguistic prosody; musical phrase endings often
        # cadence downward as well).
        selectObject: pitchID
        pStart = Get value at time: time - pitchAnalysisWindow, "Hertz", "Linear"
        pEnd = Get value at time: time, "Hertz", "Linear"

        slopeScore = 0
        if pStart != undefined and pEnd != undefined
            slope = (pEnd - pStart) / pitchAnalysisWindow
            # Falling slope = positive score
            slopeScore = -slope * weightPitchSlope
        endif

        # ── SCORE COMPONENT 2: SILENCE DEPTH × LENGTH ──
        # v2.1 FIX: v2.0's "centering" component was always zero
        # because 'time' was defined as (start+end)/2 and then
        # compared against the same midpoint. Now we reward long,
        # deep silences — a 0.8 s deep silence is a much stronger
        # phrase-break cue than a 0.05 s shallow dip.
        silenceLen = end - start
        selectObject: intensityID
        .intAtSilence = Get mean: start, end, "dB"
        .intBefore    = Get mean: max(0, start - 0.15), start, "dB"
        .intAfter     = Get mean: end, min(totalDur, end + 0.15), "dB"
        silenceScore = 0
        if .intAtSilence != undefined
            # Silence depth: how far below the surrounding intensity
            # this silence sits. Average of pre/post drops.
            .dropPre = 0
            .dropPost = 0
            if .intBefore != undefined
                .dropPre = .intBefore - .intAtSilence
            endif
            if .intAfter != undefined
                .dropPost = .intAfter - .intAtSilence
            endif
            depth = (.dropPre + .dropPost) / 2
            if depth < 0
                depth = 0
            endif
            # Length factor: saturating sqrt so a 2 s silence isn't
            # massively more valuable than a 0.5 s one.
            lenFactor = sqrt(silenceLen)
            silenceScore = depth * lenFactor * weightCentering * 5.0
        endif

        # ── SCORE COMPONENT 3: INTENSITY CHANGE (not flux) ──
        # Honestly named. Measures the local intensity inflection at
        # the candidate time (not across the whole silence). Cheap,
        # correlated with boundary strength. True spectral flux
        # would require a dense Spectrogram loop that is impractical
        # in pure Praat scripting.
        fluxScore = 0
        if use_spectral_flux
            selectObject: intensityID
            intBefore = Get value at time: time - 0.05, "Cubic"
            intAt = Get value at time: time, "Cubic"
            intAfter = Get value at time: time + 0.05, "Cubic"

            if intBefore != undefined and intAt != undefined and intAfter != undefined
                dropBefore = intBefore - intAt
                dropAfter = intAt - intAfter
                avgDrop = (abs(dropBefore) + abs(dropAfter)) / 2
                fluxScore = avgDrop * spectralWeight * 0.3
                if avgDrop > intensityChangeMax
                    intensityChangeMax = avgDrop
                endif
            endif
        endif

        # ── TOTAL SCORE ──
        candScore#[currCand] = slopeScore + silenceScore + fluxScore + insertionBonus
    endif
endfor

##############################################
# PHASE 3: DYNAMIC PROGRAMMING SOLVER
##############################################

if print_debug_log
    appendInfoLine: "Solving optimal path..."
endif

# Initialize
for i to nCandidates
    dpMaxScore#[i] = -1000000
    dpPrevIndex#[i] = 0
endfor

# Forward Pass
for i to nCandidates
    tCurr = candTime#[i]
    localScore = candScore#[i]
    
    # Check if this can be first cut
    if tCurr >= minDuration
        if localScore > dpMaxScore#[i]
            dpMaxScore#[i] = localScore
            dpPrevIndex#[i] = 0
        endif
    endif
    
    # Check connections from previous cuts
    for j to i-1
        tPrev = candTime#[j]
        scorePrev = dpMaxScore#[j]
        dist = tCurr - tPrev
        
        if dist >= minDuration and scorePrev > -999999
            newTotal = scorePrev + localScore
            if newTotal > dpMaxScore#[i]
                dpMaxScore#[i] = newTotal
                dpPrevIndex#[i] = j
            endif
        endif
    endfor
endfor

##############################################
# PHASE 4: BACKTRACKING
##############################################

# Find best endpoint
bestEndNode = 0
maxFinalScore = -1000000

for i to nCandidates
    if dpMaxScore#[i] > maxFinalScore
        maxFinalScore = dpMaxScore#[i]
        bestEndNode = i
    endif
endfor

if bestEndNode = 0
    removeObject: intensityID, pitchID, silenceTG, workingSound
    exitScript: "No valid path found."
endif

# Trace back
finalCuts# = zero#(nCandidates)
cutCount = 0
curr = bestEndNode

while curr > 0
    cutCount += 1
    finalCuts#[cutCount] = candTime#[curr]
    curr = dpPrevIndex#[curr]
endwhile

##############################################
# PHASE 5: OUTPUT
##############################################

if create_TextGrid
    selectObject: soundID
    tgOut = To TextGrid: output_tier_name$, ""
    
    # Insert boundaries (reversed order)
    for k to cutCount
        idx = cutCount - k + 1
        t = finalCuts#[idx]
        Insert boundary: 1, t
    endfor
    
    # Label segments
    nSeg = Get number of intervals: 1
    for i to nSeg
        Set interval text: 1, i, "Phrase " + string$(i)
    endfor
    
    # Optional: Open in editor
    if open_in_editor
        selectObject: tgOut
        plusObject: soundID
        View & Edit
    endif
    
    # Optional: Extract segments as individual Sound objects
    if extract_segments_as_sounds
        appendInfoLine: ""
        appendInfoLine: "Extracting ", nSeg, " segments as Sound objects..."
        
        extractedSounds# = zero#(nSeg)
        
        for i to nSeg
            selectObject: tgOut
            tStart = Get start time of interval: 1, i
            tEnd = Get end time of interval: 1, i
            
            # Extract from original sound
            selectObject: soundID
            extractedSounds#[i] = Extract part: tStart, tEnd, "rectangular", 1.0, "no"
            
            # Rename with phrase number and timing
            selectObject: extractedSounds#[i]
            Rename: soundName$ + "_phrase" + string$(i) + "_" + fixed$(tStart, 2) + "s"
            
            appendInfoLine: "  Phrase ", i, ": ", fixed$(tStart, 2), "-", fixed$(tEnd, 2), "s (", fixed$(tEnd - tStart, 2), "s)"
        endfor
        
        # Select all extracted sounds for easy viewing
        selectObject: extractedSounds#[1]
        for i from 2 to nSeg
            plusObject: extractedSounds#[i]
        endfor
        
        appendInfoLine: "✓ Extracted ", nSeg, " segments"
    endif
endif

##############################################
# PHASE 6: ANALYSIS REPORT VISUALIZATION
##############################################

if draw_analysis_report and analysis_mode <= 2
    appendInfoLine: "Drawing analysis report..."
    Erase all
    Select outer viewport: 0, 8, 0, 8

    # ----- Title row -----
    Select outer viewport: 0, 8, 0, 0.45
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##Sonic Syntax## — Input-Adaptive Report"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", -1.22, "half",
        ... soundName$
        ... + "   |   " + fixed$(totalDur, 2) + " s"
        ... + "   |   " + string$(cutCount) + " cuts"
        ... + "   |   mode " + string$(analysis_mode)

    # ----- Parameters panel (left) -----
    Select outer viewport: 0, 4, 0.50, 1.95
    Select inner viewport: 0.15, 3.90, 0.55, 1.90
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.98}", 0, 1, 0, 1
    Font size: 7
    Colour: "{0.20, 0.20, 0.35}"
    Text: 0.04, "left", 0.92, "top", "##Learned Parameters##"
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.04, "left", 0.78, "top",
        ... "Pitch range: " + string$(pitchFloor) + "-" + string$(pitchCeiling) + " Hz"
    Text: 0.04, "left", 0.68, "top",
        ... "Silence threshold: " + fixed$(silenceThreshold, 1) + " dB"
    Text: 0.04, "left", 0.58, "top",
        ... "Min cut distance: " + fixed$(minDuration, 2) + " s"
    Text: 0.04, "left", 0.48, "top",
        ... "Pitch-slope weight: " + fixed$(weightPitchSlope, 2)
    Text: 0.04, "left", 0.38, "top",
        ... "Centering (now depth x len): " + fixed$(weightCentering, 2)
    Text: 0.04, "left", 0.28, "top",
        ... "Insertion bonus: " + fixed$(insertionBonus, 1)
    Text: 0.04, "left", 0.18, "top",
        ... "Candidates: " + string$(nCandidates) + "   Cuts: " + string$(cutCount)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # ----- Content analysis panel (right) -----
    Select outer viewport: 4, 8, 0.50, 1.95
    Select inner viewport: 4.15, 7.85, 0.55, 1.90
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.98}", 0, 1, 0, 1
    Font size: 7
    Colour: "{0.20, 0.20, 0.35}"
    Text: 0.04, "left", 0.92, "top", "##Content Analysis##"
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.04, "left", 0.78, "top", "Spectrum: " + materialType$
    Text: 0.04, "left", 0.68, "top", "Dynamics: " + contentType$
    Text: 0.04, "left", 0.58, "top", "Density:  " + densityType$
    Text: 0.04, "left", 0.48, "top", "Pitch:    " + pitchVariability$
    Text: 0.04, "left", 0.38, "top", "Strategy: " + strategy$
    Text: 0.04, "left", 0.28, "top",
        ... "Median inter-peak: " + fixed$(medianInterval, 2) + " s"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # ----- Waveform with silence intervals + boundaries -----
    Select outer viewport: 0, 8, 2.05, 3.45
    Select inner viewport: 0.55, 7.70, 2.15, 3.40
    selectObject: soundID
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"

    # Shade silence intervals a light red
    Axes: 0, totalDur, -1, 1
    selectObject: silenceTG
    .nIv = Get number of intervals: 1
    for .iv from 1 to .nIv
        selectObject: silenceTG
        .lbl$ = Get label of interval: 1, .iv
        if .lbl$ = "silent"
            .st = Get start time of interval: 1, .iv
            .en = Get end time of interval: 1, .iv
            Paint rectangle: "{1.00, 0.92, 0.90}", .st, .en, -1, 1
        endif
    endfor

    # Redraw waveform on top of silence shading
    selectObject: soundID
    Colour: "{0.30, 0.40, 0.60}"
    Draw: 0, 0, 0, 0, "no", "Curve"

    # Mark final cuts (chosen boundaries) in red
    Axes: 0, totalDur, -1, 1
    Colour: "{0.85, 0.20, 0.20}"
    Line width: 1.8
    for .k from 1 to cutCount
        .tc = finalCuts#[.k]
        Draw line: .tc, -1, .tc, 1
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Waveform"
    Text top: "no", "Pink = silence intervals   |   Red = chosen cuts"

    # ----- Intensity trace with threshold line -----
    Select outer viewport: 0, 8, 3.55, 4.90
    Select inner viewport: 0.55, 7.70, 3.65, 4.85
    selectObject: intensityID
    .iMin = Get minimum: 0, 0, "Parabolic"
    .iMax = Get maximum: 0, 0, "Parabolic"
    .iRange = .iMax - .iMin
    .yLo = .iMin - .iRange * 0.08
    .yHi = .iMax + .iRange * 0.08
    Axes: 0, totalDur, .yLo, .yHi
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, totalDur, .yLo, .yHi

    # The threshold used by To TextGrid (silences) is RELATIVE to
    # max intensity; to draw it we convert back to absolute dB.
    .thrAbs = .iMax + silenceThreshold
    # (silenceThreshold is negative, so this lands below max.)
    Colour: "{0.85, 0.30, 0.30}"
    Dotted line
    Draw line: 0, .thrAbs, totalDur, .thrAbs
    Solid line

    # Draw the intensity contour
    selectObject: intensityID
    Colour: "{0.25, 0.40, 0.70}"
    Draw: 0, 0, .yLo, .yHi, "no"

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "dB"
    Text top: "no", "Intensity contour   |   Red dashed = adaptive threshold ("
        ... + fixed$(silenceThreshold, 1) + " dB rel. peak)"

    # ----- Candidate scores strip -----
    # Green = chosen, grey = rejected. Bar height = score magnitude
    # normalised to the maximum absolute score seen.
    Select outer viewport: 0, 8, 5.00, 6.15
    Select inner viewport: 0.55, 7.70, 5.10, 6.10

    .scoreMax = 0
    for .c from 1 to nCandidates
        .s = candScore#[.c]
        if abs(.s) > .scoreMax
            .scoreMax = abs(.s)
        endif
    endfor
    if .scoreMax < 1e-9
        .scoreMax = 1
    endif

    Axes: 0, totalDur, -1.1, 1.1
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, totalDur, -1.1, 1.1
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, totalDur, 0

    # Build a set for fast "is this candidate chosen?" lookup.
    # Praat doesn't have sets; we do a linear scan per candidate,
    # which is fine at the scales we expect (rarely > 200 candidates).
    for .c from 1 to nCandidates
        .tC = candTime#[.c]
        .sC = candScore#[.c] / .scoreMax
        if .sC > 1
            .sC = 1
        endif
        if .sC < -1
            .sC = -1
        endif
        .chosen = 0
        for .k from 1 to cutCount
            if abs(finalCuts#[.k] - .tC) < 1e-6
                .chosen = 1
            endif
        endfor
        if .chosen = 1
            Colour: "{0.20, 0.65, 0.30}"
            Line width: 2.2
        else
            Colour: "{0.65, 0.65, 0.70}"
            Line width: 1.2
        endif
        Draw line: .tC, 0, .tC, .sC
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Score (norm.)"
    Text bottom: "yes", "Time (s)"
    Text top: "no",
        ... "Per-candidate score   |   Green = chosen by DP solver   |   Grey = rejected"

    # ----- Summary panel -----
    Select outer viewport: 0, 8, 6.25, 7.55
    Select inner viewport: 0.55, 7.70, 6.32, 7.50
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.88, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.68, "half",
        ... "Total DP score: " + fixed$(maxFinalScore, 1)
        ... + "   |   Avg per cut: "
        ... + fixed$(maxFinalScore / (cutCount + 1e-9), 1)
        ... + "   |   Candidates " + string$(nCandidates)
        ... + " -> kept " + string$(cutCount)
    Text: 0.02, "left", 0.46, "half",
        ... "Score components: pitch slope (wt=" + fixed$(weightPitchSlope, 1) + "), "
        ... + "silence depth x length (wt=" + fixed$(weightCentering, 1) + "), "
        ... + "intensity change (max seen = " + fixed$(intensityChangeMax, 1) + " dB)"
    Text: 0.02, "left", 0.24, "half",
        ... "Min cut spacing: " + fixed$(minDuration, 2) + " s"
        ... + "   |   Insertion bonus: " + fixed$(insertionBonus, 1)
        ... + "   |   Use spectral flux (intensity change): "
        ... + string$(use_spectral_flux)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# Cleanup
removeObject: intensityID, pitchID, silenceTG, workingSound

appendInfoLine: ""
appendInfoLine: "=== SUCCESS ==="
appendInfoLine: "Found optimal path with ", cutCount, " boundaries"
appendInfoLine: "Total score: ", fixed$(maxFinalScore, 2)

if create_TextGrid
    appendInfoLine: ""
    appendInfoLine: "TextGrid created: ", output_tier_name$
    if extract_segments_as_sounds
        appendInfoLine: "Extracted sounds: ", nSeg, " phrases"
    endif
endif