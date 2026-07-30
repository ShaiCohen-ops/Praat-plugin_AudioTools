# ============================================================
# Praat AudioTools - Perceptual_Synchrony.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 3.1 (2026) - Alignment tier corrections
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Perceptual Synchrony over Physical Asynchrony v3.1
#   
#   Creates perceptual synchrony between two sounds by:
#   1. Detecting similar gesture shapes (PEAK, RISE, FALL, BLOOM, DROP)
#   2. Clustering gestures by temporal/structural similarity
#   3. OPTIONALLY time-warping Sound B to align with Sound A
#   4. Applying timbral binding effects at anchor points
#
# Changelog v3.1:
#   - Alignment tier: inter-anchor segments now form real plateaus
#     (leading point placed just after the previous anchor, so Praat no
#     longer silently drops a second point at an existing time)
#   - Alignment tier: feedback walk tracks achievedOut (where output time
#     has actually reached) instead of prevTimeA (where the anchor was
#     supposed to land), so a clamped segment is compensated by the next
#   - Alignment tier: the FINAL segment now holds finalStretch as a
#     plateau instead of ramping into it from the last anchor's factor
#   - Alignment tier: the segment guard has an else branch - an overshoot
#     compresses at the 0.5 floor and is accounted for, and a too-close
#     anchor is folded into the next segment instead of advancing
#     prevTimeB past unaccounted input time
#   - Alignment tier: clamp / overshoot / too-close counts and the
#     achieved-vs-target duration are now reported; tail clamps counted
#   - Clustering: gesture-pair candidates are deduplicated at append
#     time (overlapping local windows and the structural pass could
#     propose the same pair two or three times, and the greedy selector
#     only gated on per-gesture counts, so a duplicate could be selected
#     twice)
#   - Shape analysis: minIntBefore was computed by a test that could
#     never be true and kept its initial value for every gesture; it now
#     has its own pass
#
# Changelog v3.0:
#   - Refactored with procedures (reduced repetition)
#   - Added TRUE TIME-ALIGNMENT mode (duration tier warping)
#   - Two modes: "Enhance Only" vs "Align + Enhance"
#   - Improved documentation and code structure
#   - Fixed: lowercase variable prefixes for Praat compatibility
# ============================================================

# === INPUT VALIDATION ===
if numberOfSelected("Sound") <> 2
    exitScript: "Please select exactly TWO Sound objects."
endif

soundA = selected("Sound", 1)
soundB = selected("Sound", 2)
nameA$ = selected$("Sound", 1)
nameB$ = selected$("Sound", 2)

form Perceptual Synchrony 
    comment === Synchrony Mode ===
    optionmenu Sync_mode 2
        option Enhance Only (no time change)
        option Align + Enhance (warp B to A)
    comment === Analysis ===
    positive Frame_step_ms 10
    positive Min_gesture_duration_ms 80
    positive Max_gesture_duration_ms 2000
    real Gesture_threshold 0.12
    comment === Clustering ===
    optionmenu Clustering_mode 3
        option Local window (temporal proximity)
        option Structural role (normalized position)
        option Both (hybrid)
    positive Perceptual_window_ms 500
    real Min_confidence 0.35
    integer Max_clusters_per_gesture 2
    comment === Effect Intensity ===
    optionmenu Effect_preset 2
        option Subtle
        option Moderate
        option Aggressive
        option Extreme
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === APPLY EFFECT PRESET ===
if effect_preset = 1
    anchorBoostDB = 4.0
    anchorStampDB = 1.5
    outsideTiltDB = 1.0
    anchorWidth = 0.25
    outsideWidth = 0.4
    attackMs = 20
    releaseMs = 80
    presetName$ = "Subtle"
elsif effect_preset = 2
    anchorBoostDB = 8.0
    anchorStampDB = 3.0
    outsideTiltDB = 2.0
    anchorWidth = 0.15
    outsideWidth = 0.45
    attackMs = 15
    releaseMs = 100
    presetName$ = "Moderate"
elsif effect_preset = 3
    anchorBoostDB = 12.0
    anchorStampDB = 5.0
    outsideTiltDB = 3.0
    anchorWidth = 0.05
    outsideWidth = 0.5
    attackMs = 10
    releaseMs = 120
    presetName$ = "Aggressive"
else
    anchorBoostDB = 15.0
    anchorStampDB = 6.0
    outsideTiltDB = 4.0
    anchorWidth = 0.02
    outsideWidth = 0.55
    attackMs = 8
    releaseMs = 150
    presetName$ = "Extreme"
endif

# === GLOBAL PARAMETERS ===
frameStep = frame_step_ms / 1000
minGestureDur = min_gesture_duration_ms / 1000
maxGestureDur = max_gesture_duration_ms / 1000
perceptualWindow = perceptual_window_ms / 1000
attackSec = attackMs / 1000
releaseSec = releaseMs / 1000

# Tag weights
w_BRIGHT_RISE = 1.0
w_BRIGHT_FALL = 1.0
w_NOISE_BLOOM = 1.2
w_SPECTRAL_DROP = 1.2
w_ACCENT_PEAK = 1.5

# Tag thresholds
brightThresh = 0.2
noiseThresh = 0.12
dropThresh = -0.2
monotonThresh = 0.65
covarThresh = 0.4

# === SETUP ===
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  PERCEPTUAL SYNCHRONY v3.1"
writeInfoLine: "=============================================="
appendInfoLine: ""
if sync_mode = 1
    appendInfoLine: "Mode: ENHANCE ONLY (no time warping)"
else
    appendInfoLine: "Mode: ALIGN + ENHANCE (warp B to match A)"
endif
appendInfoLine: ""
appendInfoLine: "Sound A: ", nameA$
appendInfoLine: "Sound B: ", nameB$

selectObject: soundA
durationA = Get total duration
sampleRateA = Get sampling frequency

selectObject: soundB
durationB = Get total duration
sampleRateB = Get sampling frequency

appendInfoLine: "Duration A: ", fixed$(durationA, 3), " s"
appendInfoLine: "Duration B: ", fixed$(durationB, 3), " s"
appendInfoLine: "Effect preset: ", presetName$
appendInfoLine: ""

# ============================================================
# PROCEDURES
# ============================================================

procedure extractFeatures: .sound, .pfx$
    # Extracts intensity, centroid, slope for a sound
    # Stores in global arrays with prefix .pfx$
    
    selectObject: .sound
    .duration = Get total duration
    .numFrames = floor(.duration / frameStep)
    
    # Create analysis objects
    selectObject: .sound
    .intensity = To Intensity: 75, frameStep, "yes"
    
    selectObject: .sound
    .spectrogram = To Spectrogram: 0.025, 5000, frameStep, 20, "Gaussian"
    
    # Extract frame-by-frame features
    for .i from 1 to .numFrames
        .t = (.i - 0.5) * frameStep
        if .t > .duration
            .t = .duration - 0.001
        endif
        
        # Intensity
        selectObject: .intensity
        .intVal = Get value at time: .t, "Cubic"
        if .intVal = undefined
            .intVal = 0
        endif
        '.pfx$'_intensity[.i] = .intVal
        '.pfx$'_time[.i] = .t
        
        # Spectral features from spectrogram
        selectObject: .spectrogram
        .totalPower = 0
        .weightedSum = 0
        .lowPower = 0
        .highPower = 0
        
        .freq = 100
        while .freq <= 5000
            .power = Get power at: .t, .freq
            if .power <> undefined and .power > 0
                .totalPower = .totalPower + .power
                .weightedSum = .weightedSum + .freq * .power
                if .freq <= 1000
                    .lowPower = .lowPower + .power
                elsif .freq >= 2000
                    .highPower = .highPower + .power
                endif
            endif
            .freq = .freq + 100
        endwhile
        
        # Centroid
        if .totalPower > 0
            '.pfx$'_centroid[.i] = .weightedSum / .totalPower
        else
            '.pfx$'_centroid[.i] = 1000
        endif
        
        # Spectral slope (high/low ratio)
        if .lowPower > 0
            '.pfx$'_slope[.i] = .highPower / .lowPower
        else
            '.pfx$'_slope[.i] = 0
        endif
    endfor
    
    # Store for cleanup
    '.pfx$'_intensityObj = .intensity
    '.pfx$'_spectrogramObj = .spectrogram
    '.pfx$'_numFrames = .numFrames
    '.pfx$'_duration = .duration
    
    appendInfoLine: "  ", .pfx$, ": ", .numFrames, " frames"
endproc


procedure normalizeFeature: .arrayName$, .n, .outName$
    # Normalizes array using 95th percentile
    # Reads from .arrayName$[i], writes to .outName$[i]
    
    .numBins = 30
    .targetPct = 0.95
    
    # Find min/max
    .minVal = '.arrayName$'[1]
    .maxVal = '.arrayName$'[1]
    for .i from 2 to .n
        if '.arrayName$'[.i] < .minVal
            .minVal = '.arrayName$'[.i]
        endif
        if '.arrayName$'[.i] > .maxVal
            .maxVal = '.arrayName$'[.i]
        endif
    endfor
    .range = .maxVal - .minVal + 0.001
    
    # Build histogram
    for .b from 1 to .numBins
        .hist[.b] = 0
    endfor
    
    for .i from 1 to .n
        .binIdx = floor(('.arrayName$'[.i] - .minVal) / .range * .numBins) + 1
        if .binIdx > .numBins
            .binIdx = .numBins
        endif
        if .binIdx < 1
            .binIdx = 1
        endif
        .hist[.binIdx] = .hist[.binIdx] + 1
    endfor
    
    # Find 95th percentile bin
    .cumSum = 0
    .target95 = .n * .targetPct
    .pct95_bin = .numBins
    for .b from 1 to .numBins
        .cumSum = .cumSum + .hist[.b]
        if .cumSum >= .target95 and .pct95_bin = .numBins
            .pct95_bin = .b
        endif
    endfor
    
    .pct95 = .minVal + (.pct95_bin / .numBins) * .range
    if .pct95 - .minVal < 0.001
        .pct95 = .minVal + 0.001
    endif
    
    # Normalize to [0, 1]
    for .i from 1 to .n
        '.outName$'[.i] = ('.arrayName$'[.i] - .minVal) / (.pct95 - .minVal)
        if '.outName$'[.i] > 1
            '.outName$'[.i] = 1
        endif
        if '.outName$'[.i] < 0
            '.outName$'[.i] = 0
        endif
    endfor
endproc


procedure computeDerivatives: .pfx$, .n
    # Computes frame-to-frame derivatives
    
    '.pfx$'_dInt[1] = 0
    '.pfx$'_dCent[1] = 0
    '.pfx$'_dSlope[1] = 0
    
    for .i from 2 to .n
        '.pfx$'_dInt[.i] = '.pfx$'_normInt[.i] - '.pfx$'_normInt[.i-1]
        '.pfx$'_dCent[.i] = '.pfx$'_normCent[.i] - '.pfx$'_normCent[.i-1]
        '.pfx$'_dSlope[.i] = '.pfx$'_normSlope[.i] - '.pfx$'_normSlope[.i-1]
    endfor
endproc


procedure detectGestures: .pfx$, .n, .duration
    # Detects gestures based on derivative threshold
    
    .minFrames = floor(minGestureDur / frameStep)
    .maxFrames = floor(maxGestureDur / frameStep)
    
    .numGestures = 0
    .inGesture = 0
    .gestureStart = 0
    
    for .i from 2 to .n
        .totalChange = abs('.pfx$'_dCent[.i]) + abs('.pfx$'_dInt[.i]) + abs('.pfx$'_dSlope[.i])
        
        if .inGesture = 0
            if .totalChange > gesture_threshold
                .inGesture = 1
                .gestureStart = .i
            endif
        else
            .gestureDuration = .i - .gestureStart
            
            if .totalChange < gesture_threshold * 0.5 or .gestureDuration >= .maxFrames or .i = .n
                if .gestureDuration >= .minFrames
                    .numGestures = .numGestures + 1
                    .gestureEnd = .i
                    .g = .numGestures
                    
                    # Store times
                    '.pfx$'_gStart[.g] = '.pfx$'_time[.gestureStart]
                    '.pfx$'_gEnd[.g] = '.pfx$'_time[.gestureEnd]
                    '.pfx$'_gDur[.g] = '.pfx$'_gEnd[.g] - '.pfx$'_gStart[.g]
                    '.pfx$'_gNormPos[.g] = ('.pfx$'_gStart[.g] + '.pfx$'_gEnd[.g]) / 2 / .duration
                    
                    # Analyze shape
                    @analyzeGestureShape: .pfx$, .g, .gestureStart, .gestureEnd
                    
                    # Tag gesture
                    @tagGesture: .pfx$, .g
                endif
                .inGesture = 0
            endif
        endif
    endfor
    
    '.pfx$'_numGestures = .numGestures
endproc


procedure analyzeGestureShape: .pfx$, .g, .startFrame, .endFrame
    # Analyzes gesture shape
    
    .accumCent = 0
    .accumInt = 0
    .accumSlope = 0
    .risingCent = 0
    .fallingCent = 0
    .risingInt = 0
    .fallingInt = 0
    .covarFrames = 0
    .totalFrames = .endFrame - .startFrame + 1
    
    .maxIntFrame = .startFrame
    .maxIntVal = '.pfx$'_normInt[.startFrame]
    
    for .j from .startFrame to .endFrame
        .accumCent = .accumCent + '.pfx$'_dCent[.j]
        .accumInt = .accumInt + '.pfx$'_dInt[.j]
        .accumSlope = .accumSlope + '.pfx$'_dSlope[.j]
        
        if '.pfx$'_dCent[.j] > 0.01
            .risingCent = .risingCent + 1
        elsif '.pfx$'_dCent[.j] < -0.01
            .fallingCent = .fallingCent + 1
        endif
        
        if '.pfx$'_dInt[.j] > 0.01
            .risingInt = .risingInt + 1
        elsif '.pfx$'_dInt[.j] < -0.01
            .fallingInt = .fallingInt + 1
        endif
        
        if ('.pfx$'_dCent[.j] > 0.005 and '.pfx$'_dSlope[.j] > 0.005) or ('.pfx$'_dCent[.j] < -0.005 and '.pfx$'_dSlope[.j] < -0.005)
            .covarFrames = .covarFrames + 1
        endif
        
        if '.pfx$'_normInt[.j] > .maxIntVal
            .maxIntVal = '.pfx$'_normInt[.j]
            .maxIntFrame = .j
        endif
    endfor
    
    # v3.1 FIX: minIntBefore used to be tested inside the loop above with
    # "if .j < .maxIntFrame", but .maxIntFrame is assigned in that same
    # forward pass, so it always equals the current frame or an earlier
    # one - the condition could never be true and .minIntBefore kept its
    # initial value for every gesture. It now gets its own pass, mirroring
    # the .minIntAfter pass below.
    .minIntBefore = '.pfx$'_normInt[.startFrame]
    for .j from .startFrame to .maxIntFrame
        if '.pfx$'_normInt[.j] < .minIntBefore
            .minIntBefore = '.pfx$'_normInt[.j]
        endif
    endfor
    
    .minIntAfter = '.pfx$'_normInt[.endFrame]
    for .j from .maxIntFrame to .endFrame
        if '.pfx$'_normInt[.j] < .minIntAfter
            .minIntAfter = '.pfx$'_normInt[.j]
        endif
    endfor
    
    # Store shape features
    '.pfx$'_gCentChange[.g] = .accumCent
    '.pfx$'_gIntChange[.g] = .accumInt
    '.pfx$'_gSlopeChange[.g] = .accumSlope
    '.pfx$'_gCentMono[.g] = max(.risingCent, .fallingCent) / (.totalFrames + 0.001)
    '.pfx$'_gIntMono[.g] = max(.risingInt, .fallingInt) / (.totalFrames + 0.001)
    '.pfx$'_gCovar[.g] = .covarFrames / (.totalFrames + 0.001)
    
    if .risingCent > .fallingCent
        '.pfx$'_gCentDir[.g] = 1
    else
        '.pfx$'_gCentDir[.g] = -1
    endif
    if .risingInt > .fallingInt
        '.pfx$'_gIntDir[.g] = 1
    else
        '.pfx$'_gIntDir[.g] = -1
    endif
    
    .risePhase = .maxIntFrame - .startFrame
    .fallPhase = .endFrame - .maxIntFrame
    .peakContrast = .maxIntVal - max(.minIntBefore, .minIntAfter)
    
    if .risePhase >= 2 and .fallPhase >= 2 and .peakContrast > 0.15
        '.pfx$'_gPeakness[.g] = .peakContrast
    else
        '.pfx$'_gPeakness[.g] = 0
    endif
    
    '.pfx$'_gSalience[.g] = sqrt(.accumCent^2 + .accumInt^2 + .accumSlope^2)
endproc


procedure tagGesture: .pfx$, .g
    # Assigns perceptual tags
    
    '.pfx$'_tag_BR[.g] = 0
    '.pfx$'_tag_BF[.g] = 0
    '.pfx$'_tag_NB[.g] = 0
    '.pfx$'_tag_SD[.g] = 0
    '.pfx$'_tag_AP[.g] = 0
    
    if '.pfx$'_gCentChange[.g] > brightThresh and '.pfx$'_gCentMono[.g] > monotonThresh
        '.pfx$'_tag_BR[.g] = 1
    endif
    
    if '.pfx$'_gCentChange[.g] < -brightThresh and '.pfx$'_gCentMono[.g] > monotonThresh
        '.pfx$'_tag_BF[.g] = 1
    endif
    
    if '.pfx$'_gCentChange[.g] > noiseThresh and '.pfx$'_gSlopeChange[.g] > noiseThresh and '.pfx$'_gCovar[.g] > covarThresh
        '.pfx$'_tag_NB[.g] = 1
    endif
    
    if '.pfx$'_gCentChange[.g] < dropThresh and '.pfx$'_gSlopeChange[.g] < dropThresh and '.pfx$'_gCovar[.g] > covarThresh
        '.pfx$'_tag_SD[.g] = 1
    endif
    
    if '.pfx$'_gPeakness[.g] > 0.15
        '.pfx$'_tag_AP[.g] = 1
    endif
    
    '.pfx$'_gWeightedTags[.g] = '.pfx$'_tag_BR[.g] * w_BRIGHT_RISE + '.pfx$'_tag_BF[.g] * w_BRIGHT_FALL + '.pfx$'_tag_NB[.g] * w_NOISE_BLOOM + '.pfx$'_tag_SD[.g] * w_SPECTRAL_DROP + '.pfx$'_tag_AP[.g] * w_ACCENT_PEAK
    
    '.pfx$'_gTagCount[.g] = '.pfx$'_tag_BR[.g] + '.pfx$'_tag_BF[.g] + '.pfx$'_tag_NB[.g] + '.pfx$'_tag_SD[.g] + '.pfx$'_tag_AP[.g]
endproc


procedure computeTagOverlap: .gA, .gB
    # Computes weighted tag overlap between gesture a and b
    
    computeTagOverlap.wOverlap = 0
    
    if a_tag_BR[.gA] = 1 and b_tag_BR[.gB] = 1
        computeTagOverlap.wOverlap = computeTagOverlap.wOverlap + w_BRIGHT_RISE
    endif
    if a_tag_BF[.gA] = 1 and b_tag_BF[.gB] = 1
        computeTagOverlap.wOverlap = computeTagOverlap.wOverlap + w_BRIGHT_FALL
    endif
    if a_tag_NB[.gA] = 1 and b_tag_NB[.gB] = 1
        computeTagOverlap.wOverlap = computeTagOverlap.wOverlap + w_NOISE_BLOOM
    endif
    if a_tag_SD[.gA] = 1 and b_tag_SD[.gB] = 1
        computeTagOverlap.wOverlap = computeTagOverlap.wOverlap + w_SPECTRAL_DROP
    endif
    if a_tag_AP[.gA] = 1 and b_tag_AP[.gB] = 1
        computeTagOverlap.wOverlap = computeTagOverlap.wOverlap + w_ACCENT_PEAK
    endif
endproc


procedure computeShapeScore: .gA, .gB
    # Computes shape similarity
    
    computeShapeScore.score = 0
    
    if a_gCentDir[.gA] = b_gCentDir[.gB]
        computeShapeScore.score = computeShapeScore.score + 0.3
    endif
    if a_gIntDir[.gA] = b_gIntDir[.gB]
        computeShapeScore.score = computeShapeScore.score + 0.3
    endif
    
    computeShapeScore.score = computeShapeScore.score + 0.2 * (1 - abs(a_gCentMono[.gA] - b_gCentMono[.gB]))
    computeShapeScore.score = computeShapeScore.score + 0.2 * (1 - abs(a_gCovar[.gA] - b_gCovar[.gB]))
endproc


procedure computeConfidence: .gA, .gB, .wOverlap, .shapeScore
    # Computes overall confidence
    
    .totalW = a_gWeightedTags[.gA] + b_gWeightedTags[.gB]
    if .totalW - .wOverlap > 0.001
        .tagScore = .wOverlap / (.totalW - .wOverlap)
    else
        .tagScore = 1
    endif
    
    .maxSal = max(a_gSalience[.gA], b_gSalience[.gB])
    .minSal = min(a_gSalience[.gA], b_gSalience[.gB])
    if .maxSal > 0
        .salienceScore = .minSal / .maxSal
    else
        .salienceScore = 1
    endif
    
    .maxD = max(a_gDur[.gA], b_gDur[.gB])
    .minD = min(a_gDur[.gA], b_gDur[.gB])
    if .maxD > 0
        .durScore = .minD / .maxD
    else
        .durScore = 1
    endif
    
    computeConfidence.score = 0.30 * .tagScore + 0.30 * .shapeScore + 0.20 * .salienceScore + 0.20 * .durScore
endproc

# ============================================================
# v3.1 FIX: pair-level candidate deduplication
# ============================================================
# The local-window pass steps by half a window, so the same (gA, gB)
# pair falls inside two consecutive windows and used to be appended
# twice; in hybrid mode the structural pass could append it a third
# time. Nothing downstream compared pairs - the greedy selector only
# checks per-gesture counts (a_clusterCount / b_clusterCount) against
# Max_clusters_per_gesture, which defaults to 2. So a duplicate pair
# could be SELECTED twice: it consumed the gesture's remaining slot
# (blocking a genuinely different second match), inflated the reported
# cluster count, produced a zero-length warp segment at that anchor,
# and made STEP 8 apply timbral binding twice at the same point.
#
# Candidates are now merged by pair, keeping the highest-confidence
# occurrence and its mode / metrics.
procedure addCandidate: .gA, .gB, .conf, .mode$, .wOverlap, .shapeScore
    .existing = 0
    for .k from 1 to numCandidates
        if cand_gA[.k] = .gA and cand_gB[.k] = .gB
            .existing = .k
            .k = numCandidates
        endif
    endfor
    
    if .existing > 0
        nDupCandidates = nDupCandidates + 1
        if .conf > cand_conf[.existing]
            cand_conf[.existing] = .conf
            cand_mode$[.existing] = .mode$
            cand_wOverlap[.existing] = .wOverlap
            cand_shapeScore[.existing] = .shapeScore
        endif
    else
        numCandidates = numCandidates + 1
        cand_gA[numCandidates] = .gA
        cand_gB[numCandidates] = .gB
        cand_conf[numCandidates] = .conf
        cand_mode$[numCandidates] = .mode$
        cand_wOverlap[numCandidates] = .wOverlap
        cand_shapeScore[numCandidates] = .shapeScore
    endif
endproc


# ============================================================
# MAIN PIPELINE
# ============================================================

# === STEP 1: FEATURE EXTRACTION ===
appendInfoLine: "Extracting features..."

@extractFeatures: soundA, "a"
@extractFeatures: soundB, "b"

# === STEP 2: NORMALIZATION ===
appendInfoLine: "Normalizing features..."

@normalizeFeature: "a_intensity", a_numFrames, "a_normInt"
@normalizeFeature: "a_centroid", a_numFrames, "a_normCent"
@normalizeFeature: "a_slope", a_numFrames, "a_normSlope"

@normalizeFeature: "b_intensity", b_numFrames, "b_normInt"
@normalizeFeature: "b_centroid", b_numFrames, "b_normCent"
@normalizeFeature: "b_slope", b_numFrames, "b_normSlope"

# === STEP 3: DERIVATIVES ===
@computeDerivatives: "a", a_numFrames
@computeDerivatives: "b", b_numFrames

# === STEP 4: GESTURE DETECTION ===
appendInfoLine: "Detecting gestures..."

@detectGestures: "a", a_numFrames, durationA
@detectGestures: "b", b_numFrames, durationB

appendInfoLine: "  a: ", a_numGestures, " gestures | b: ", b_numGestures, " gestures"

# === STEP 5: CLUSTERING ===
appendInfoLine: "Finding clusters..."

globalDuration = max(durationA, durationB)
numCandidates = 0
nDupCandidates = 0

# Initialize cluster counts
for g from 1 to a_numGestures
    a_clusterCount[g] = 0
endfor
for g from 1 to b_numGestures
    b_clusterCount[g] = 0
endfor

# --- LOCAL WINDOW CLUSTERING ---
if clustering_mode = 1 or clustering_mode = 3
    windowStart = 0
    while windowStart < globalDuration
        windowEnd = windowStart + perceptualWindow
        
        for gA from 1 to a_numGestures
            if a_gTagCount[gA] > 0
                midA = (a_gStart[gA] + a_gEnd[gA]) / 2
                
                if midA >= windowStart and midA < windowEnd
                    for gB from 1 to b_numGestures
                        if b_gTagCount[gB] > 0
                            midB = (b_gStart[gB] + b_gEnd[gB]) / 2
                            
                            if midB >= windowStart and midB < windowEnd
                                @computeTagOverlap: gA, gB
                                wOverlap = computeTagOverlap.wOverlap
                                
                                if wOverlap > 0
                                    @computeShapeScore: gA, gB
                                    shapeScore = computeShapeScore.score
                                    
                                    @computeConfidence: gA, gB, wOverlap, shapeScore
                                    confidence = computeConfidence.score
                                    
                                    if confidence >= min_confidence
                                        @addCandidate: gA, gB, confidence, "LOCAL", wOverlap, shapeScore
                                    endif
                                endif
                            endif
                        endif
                    endfor
                endif
            endif
        endfor
        
        windowStart = windowStart + perceptualWindow * 0.5
    endwhile
endif

# --- STRUCTURAL CLUSTERING ---
if clustering_mode = 2 or clustering_mode = 3
    posTol = 0.15
    
    for gA from 1 to a_numGestures
        if a_gTagCount[gA] > 0
            for gB from 1 to b_numGestures
                if b_gTagCount[gB] > 0
                    posDiff = abs(a_gNormPos[gA] - b_gNormPos[gB])
                    
                    if posDiff < posTol
                        @computeTagOverlap: gA, gB
                        wOverlap = computeTagOverlap.wOverlap
                        
                        if wOverlap > 0.5
                            @computeShapeScore: gA, gB
                            shapeScore = computeShapeScore.score
                            
                            posScore = 1 - posDiff / posTol
                            
                            maxSal = max(a_gSalience[gA], b_gSalience[gB])
                            minSal = min(a_gSalience[gA], b_gSalience[gB])
                            if maxSal > 0
                                salienceScore = minSal / maxSal
                            else
                                salienceScore = 1
                            endif
                            
                            confidence = 0.35 * shapeScore + 0.30 * salienceScore + 0.35 * posScore
                            
                            if confidence >= min_confidence * 0.9
                                @addCandidate: gA, gB, confidence, "STRUCT", wOverlap, shapeScore
                            endif
                        endif
                    endif
                endif
            endfor
        endif
    endfor
endif

appendInfoLine: "  Candidates: ", numCandidates, " (", nDupCandidates, " duplicate pair proposals merged)"

# === STEP 6: GREEDY SELECTION ===
appendInfoLine: "Selecting best matches..."

for i from 1 to numCandidates
    cand_selected[i] = 0
endfor

numClusters = 0
confCutoff = min_confidence + 0.05

for pass from 1 to numCandidates
    bestIdx = 0
    bestConf = -1
    
    for i from 1 to numCandidates
        if cand_selected[i] = 0 and cand_conf[i] > bestConf
            gA = cand_gA[i]
            gB = cand_gB[i]
            
            if a_clusterCount[gA] < max_clusters_per_gesture and b_clusterCount[gB] < max_clusters_per_gesture
                bestIdx = i
                bestConf = cand_conf[i]
            endif
        endif
    endfor
    
    if bestIdx > 0 and bestConf >= confCutoff
        cand_selected[bestIdx] = 1
        numClusters = numClusters + 1
        
        gA = cand_gA[bestIdx]
        gB = cand_gB[bestIdx]
        
        cluster_gA[numClusters] = gA
        cluster_gB[numClusters] = gB
        cluster_conf[numClusters] = cand_conf[bestIdx]
        cluster_mode$[numClusters] = cand_mode$[bestIdx]
        
        a_clusterCount[gA] = a_clusterCount[gA] + 1
        b_clusterCount[gB] = b_clusterCount[gB] + 1
        
        midA = (a_gStart[gA] + a_gEnd[gA]) / 2
        midB = (b_gStart[gB] + b_gEnd[gB]) / 2
        appendInfoLine: "  #", numClusters, " [", cluster_mode$[numClusters], "] a", gA, "(", fixed$(midA, 2), "s) <-> b", gB, "(", fixed$(midB, 2), "s) conf:", fixed$(cluster_conf[numClusters], 2)
    else
        pass = numCandidates
    endif
endfor

appendInfoLine: ""
appendInfoLine: "  TOTAL CLUSTERS: ", numClusters

# ============================================================
# STEP 7: TIME ALIGNMENT (if enabled)
# ============================================================

if sync_mode = 2 and numClusters > 0
    appendInfoLine: ""
    appendInfoLine: "Creating time-aligned version of B..."
    
    selectObject: soundB
    manipulation = To Manipulation: 0.01, 75, 600
    
    selectObject: manipulation
    Extract duration tier
    durationTier = selected("DurationTier")
    
    selectObject: durationTier
    numPoints = Get number of points
    p = numPoints
    while p >= 1
        Remove point: p
        p = p - 1
    endwhile
    
    # Sort clusters by B time
    for c from 1 to numClusters
        clusterOrder[c] = c
        clusterBTime[c] = (b_gStart[cluster_gB[c]] + b_gEnd[cluster_gB[c]]) / 2
    endfor
    
    for i from 1 to numClusters - 1
        for j from i + 1 to numClusters
            if clusterBTime[clusterOrder[i]] > clusterBTime[clusterOrder[j]]
                temp = clusterOrder[i]
                clusterOrder[i] = clusterOrder[j]
                clusterOrder[j] = temp
            endif
        endfor
    endfor
    
    # ========================================================
    # v3.1 CRITICAL FIX 1: duplicate tier times were discarded
    # ========================================================
    # v3.0 added a point at midB for segment i, then a point at
    # prevTimeB == midB for segment i+1. Praat SILENTLY DROPS the
    # second point at an existing time - verified on 6.4.42: four
    # Add point calls at 0.2 / 0.5 / 0.5 / 0.8 produced three points,
    # and the value at 0.5 stayed 1.500 rather than the 0.700 added
    # afterwards.
    # So the intended piecewise-constant plateau never formed. The tier
    # ramped LINEARLY from f_i to f_{i+1} instead, making the achieved
    # segment duration segmentB * (f_i + f_{i+1})/2 rather than
    # segmentB * f_{i+1} = segmentA. Anchors landed wrong by an amount
    # set by the neighbouring factor. Each segment's leading point now
    # sits just AFTER the previous anchor, so no two points share a
    # time and the plateau is real.
    #
    # v3.1 CRITICAL FIX 2: the error used to accumulate. v3.0 carried
    # prevTimeA - where the anchor was SUPPOSED to land - so once a
    # segment hit the [0.5, 2.0] clamp every later anchor inherited the
    # drift with no feedback. achievedOut tracks where output time has
    # ACTUALLY reached, so a clamped segment is compensated by the next.
    #
    # v3.1 CRITICAL FIX 3: the segment guard had no else branch. When it
    # failed, no tier point was added and achievedOut froze - but
    # prevTimeB still advanced to midB, so every later factor was
    # computed against a stale output time. The neededOut <= 0 case is
    # exactly an overshoot after a clamped segment, i.e. the situation
    # the achievedOut feedback exists to correct, so the hole sat at the
    # stress case. Overshoot now compresses at the 0.5 floor and is
    # accounted for; a too-short segment (duplicate or near-duplicate
    # anchor) is folded into the next one by leaving prevTimeB alone
    # rather than skipping past unaccounted input time.
    prevTimeB = 0
    achievedOut = 0
    nClamped = 0
    nOvershoot = 0
    nTooClose = 0

    selectObject: durationTier

    for i from 1 to numClusters
        c = clusterOrder[i]
        gA = cluster_gA[c]
        gB = cluster_gB[c]

        midA = (a_gStart[gA] + a_gEnd[gA]) / 2
        midB = (b_gStart[gB] + b_gEnd[gB]) / 2

        segmentB = midB - prevTimeB
        neededOut = midA - achievedOut

        if segmentB > 0.01
            if neededOut > 0
                stretchFactor = neededOut / segmentB
            else
                # Output time has already passed this anchor. Compress as
                # hard as the clamp allows so the next segments can catch
                # up, and keep accounting for it.
                stretchFactor = 0.5
                nOvershoot += 1
            endif

            if stretchFactor < 0.5
                stretchFactor = 0.5
                nClamped += 1
            endif
            if stretchFactor > 2.0
                stretchFactor = 2.0
                nClamped += 1
            endif

            leadEps = segmentB * 0.02
            if leadEps > 0.002
                leadEps = 0.002
            endif
            if leadEps < 0.0002
                leadEps = 0.0002
            endif
            leadT = prevTimeB + leadEps
            if leadT < midB - 0.0002
                Add point: leadT, stretchFactor
            endif

            Add point: midB, stretchFactor

            achievedOut = achievedOut + stretchFactor * segmentB
            prevTimeB = midB
        else
            # Anchor sits within 10 ms of the previous one (typically a
            # duplicate pair). Leave prevTimeB where it is so the input
            # time is absorbed by the next segment instead of vanishing
            # from the accounting.
            nTooClose += 1
        endif
    endfor
    
    if prevTimeB < durationB - 0.01
        remainingB = durationB - prevTimeB
        # v3.1: measured from where output time has ACTUALLY reached.
        # v3.0 used prevTimeA, the intended anchor position, which no
        # longer exists now that the walk tracks achieved time.
        remainingA = durationA - achievedOut
        
        if remainingB > 0.01 and remainingA > 0.01
            finalStretch = remainingA / remainingB
            if finalStretch < 0.5
                finalStretch = 0.5
                nClamped += 1
            endif
            if finalStretch > 2.0
                finalStretch = 2.0
                nClamped += 1
            endif
            
            # v3.1 CRITICAL FIX 4: the tail used to get a single point at
            # durationB - 0.01, so the tier interpolated linearly from the
            # last anchor's factor across the WHOLE tail rather than
            # holding finalStretch. The achieved tail was therefore about
            # remainingB * (f_last + finalStretch) / 2, not
            # remainingB * finalStretch - the same defect FIX 1 removed
            # from the inter-anchor segments, left in place at the end.
            # The tail now gets the same lead-point-plus-plateau shape.
            tailEps = remainingB * 0.02
            if tailEps > 0.002
                tailEps = 0.002
            endif
            if tailEps < 0.0002
                tailEps = 0.0002
            endif
            tailT = prevTimeB + tailEps
            tailEnd = durationB - 0.01
            if tailT < tailEnd - 0.0002
                Add point: tailT, finalStretch
            endif
            Add point: tailEnd, finalStretch
            
            achievedOut = achievedOut + finalStretch * remainingB
        endif
    endif
    
    # v3.1: the clamp count and the achieved-vs-target figure were tracked
    # but never printed, so a drifting alignment was invisible at runtime.
    # achievedOut is the tier's own model of output time; the resynthesised
    # duration is reported separately below so tier error and resynthesis
    # error can be told apart.
    appendInfoLine: "  Alignment tier: target ", fixed$(durationA, 4), " s | tier estimate ", fixed$(achievedOut, 4), " s | est. error ", fixed$((achievedOut - durationA) * 1000, 1), " ms"
    appendInfoLine: "  Anchors: ", numClusters, " | clamped=", nClamped, " overshoot=", nOvershoot, " too-close=", nTooClose
    
    selectObject: manipulation
    plusObject: durationTier
    Replace duration tier
    
    selectObject: manipulation
    warpedB = Get resynthesis (overlap-add)
    Rename: "B_warped"
    
    warpedDur = Get total duration
    appendInfoLine: "  Time-warped B created: ", fixed$(warpedDur, 4), " s (A: ", fixed$(durationA, 4), " s, residual ", fixed$((warpedDur - durationA) * 1000, 1), " ms)"
    
    soundB_processed = warpedB
    
    removeObject: manipulation, durationTier
else
    selectObject: soundB
    soundB_processed = Copy: "B_processed"
endif

# ============================================================
# STEP 8: RESYNTHESIS (timbral binding)
# ============================================================

appendInfoLine: ""
appendInfoLine: "Applying timbral binding effects..."

selectObject: soundA
srA = Get sampling frequency

selectObject: soundB_processed
srB = Get sampling frequency
durB_proc = Get total duration

if srA <> srB
    selectObject: soundB_processed
    temp = Resample: srA, 50
    removeObject: soundB_processed
    soundB_processed = temp
endif

minDur = min(durationA, durB_proc)

selectObject: soundA
Extract part: 0, minDur, "rectangular", 1, "no"
partA = selected("Sound")

selectObject: soundB_processed
Extract part: 0, minDur, "rectangular", 1, "no"
partB = selected("Sound")

Create Sound from formula: "maskA", 1, 0, minDur, srA, "0"
maskA = selected("Sound")

Create Sound from formula: "maskB", 1, 0, minDur, srA, "0"
maskB = selected("Sound")

if numClusters > 0
    boostLin = 10 ^ (anchorBoostDB / 20)
    
    for c from 1 to numClusters
        gA = cluster_gA[c]
        gB = cluster_gB[c]
        conf = cluster_conf[c]
        
        confScaled = conf * conf
        effectBoost = 1 + (boostLin - 1) * confScaled
        
        startA = a_gStart[gA]
        endA = a_gEnd[gA]
        
        if sync_mode = 2
            startB = startA
            endB = endA
        else
            startB = b_gStart[gB]
            endB = b_gEnd[gB]
        endif
        
        if startA < 0
            startA = 0
        endif
        if endA > minDur
            endA = minDur
        endif
        if startB < 0
            startB = 0
        endif
        if endB > minDur
            endB = minDur
        endif
        
        if endA - startA > 0.001
            selectObject: partA
            Formula (part): startA, endA, 1, 1, ~ self * (if (x - startA) < attackSec then (1 + (effectBoost - 1) * ((x - startA) / attackSec)) else (if (endA - x) < releaseSec then (1 + (effectBoost - 1) * ((endA - x) / releaseSec)) else effectBoost fi) fi)
            
            selectObject: maskA
            Formula (part): startA, endA, 1, 1, ~ 1
        endif
        
        if endB - startB > 0.001
            selectObject: partB
            Formula (part): startB, endB, 1, 1, ~ self * (if (x - startB) < attackSec then (1 + (effectBoost - 1) * ((x - startB) / attackSec)) else (if (endB - x) < releaseSec then (1 + (effectBoost - 1) * ((endB - x) / releaseSec)) else effectBoost fi) fi)
            
            selectObject: maskB
            Formula (part): startB, endB, 1, 1, ~ 1
        endif
    endfor
endif

# Timbral stamp
selectObject: partA
filteredA = Filter (pass Hann band): 2000, 4500, 500
Scale peak: 0.5

selectObject: partB
filteredB = Filter (pass Hann band): 2000, 4500, 500
Scale peak: 0.5

stampGain = 10 ^ (anchorStampDB / 20) - 1

selectObject: partA
Formula: ~ self + object[filteredA] * object[maskA] * stampGain

selectObject: partB
Formula: ~ self + object[filteredB] * object[maskB] * stampGain

removeObject: filteredA, filteredB

# Differential tilt
tiltGain = 10 ^ (outsideTiltDB / 20)

selectObject: partA
Formula: ~ self * (if object[maskA] < 0.5 then (1 + (tiltGain - 1) * 0.3) else 1 fi)

selectObject: partB
Formula: ~ self * (if object[maskB] < 0.5 then (1 / (1 + (tiltGain - 1) * 0.3)) else 1 fi)

selectObject: partA
Scale peak: 0.75

selectObject: partB
Scale peak: 0.75

# Stereo mix
Create Sound from formula: "panEnvA", 1, 0, minDur, srA, ~ outsideWidth - (outsideWidth - anchorWidth) * object[maskA]
panEnvA = selected("Sound")

Create Sound from formula: "panEnvB", 1, 0, minDur, srA, ~ outsideWidth - (outsideWidth - anchorWidth) * object[maskB]
panEnvB = selected("Sound")

Create Sound from formula: "LEFT", 1, 0, minDur, srA, "0"
leftCh = selected("Sound")
Formula: ~ object[partA] * (0.5 + object[panEnvA]) + object[partB] * (0.5 - object[panEnvB])

Create Sound from formula: "RIGHT", 1, 0, minDur, srA, "0"
rightCh = selected("Sound")
Formula: ~ object[partA] * (0.5 - object[panEnvA]) + object[partB] * (0.5 + object[panEnvB])

selectObject: leftCh
plusObject: rightCh
stereoMix = Combine to stereo

if sync_mode = 2
    Rename: "PerceptualSync_ALIGNED_" + nameA$ + "_" + nameB$
else
    Rename: "PerceptualSync_ENHANCED_" + nameA$ + "_" + nameB$
endif

Scale peak: 0.95

# Cleanup
removeObject: partA, partB, maskA, maskB, panEnvA, panEnvB, leftCh, rightCh
removeObject: a_intensityObj, a_spectrogramObj, b_intensityObj, b_spectrogramObj
removeObject: soundB_processed

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Creating visualization..."
    
    Erase all
    
    if sync_mode = 2
        modeText$ = "ALIGN+ENHANCE"
    else
        modeText$ = "ENHANCE ONLY"
    endif
    
    # Title
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 11
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Perceptual Synchrony v3.1## | " + modeText$ + " | Clusters: " + string$(numClusters)
    
    # Sound A
    Select outer viewport: 0, 8, 0.6, 1.8
    Select inner viewport: 1.0, 7.8, 0.7, 1.7
    
    Axes: 0, durationA, 0, 1
    
    Colour: "{0.96, 0.97, 1.0}"
    Paint rectangle: "{0.96, 0.97, 1.0}", 0, durationA, 0, 1
    
    Colour: "{0.2, 0.5, 0.8}"
    Line width: 1.5
    for i from 2 to a_numFrames
        Draw line: a_time[i-1], a_normCent[i-1], a_time[i], a_normCent[i]
    endfor
    
    Colour: "{0.8, 0.4, 0.2}"
    Line width: 1
    for i from 2 to a_numFrames
        Draw line: a_time[i-1], a_normInt[i-1], a_time[i], a_normInt[i]
    endfor
    
    for g from 1 to a_numGestures
        if a_gTagCount[g] > 0
            if a_tag_AP[g] = 1
                colour$ = "{0.9, 0.25, 0.25}"
            elsif a_tag_NB[g] = 1
                colour$ = "{0.9, 0.7, 0.15}"
            elsif a_tag_BR[g] = 1
                colour$ = "{0.2, 0.75, 0.3}"
            elsif a_tag_BF[g] = 1
                colour$ = "{0.3, 0.55, 0.8}"
            else
                colour$ = "{0.6, 0.3, 0.7}"
            endif
            
            Colour: colour$
            Paint rectangle: colour$, a_gStart[g], a_gEnd[g], 0.92, 0.98
            
            if a_clusterCount[g] > 0
                Colour: "Black"
                Line width: 2
                Draw line: a_gStart[g], 0.90, a_gEnd[g], 0.90
            endif
        endif
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    
    Font size: 8
    Select outer viewport: 0, 1.0, 0.6, 1.8
    Axes: 0, 1, 0, 1
    Colour: "{0.3, 0.5, 0.8}"
    Text: 0.95, "right", 0.7, "half", "Sound A"
    Font size: 6
    Text: 0.95, "right", 0.4, "half", nameA$
    
    # Sound B
    Select outer viewport: 0, 8, 1.9, 3.1
    Select inner viewport: 1.0, 7.8, 2.0, 3.0
    
    Axes: 0, durationB, 0, 1
    
    Colour: "{1.0, 0.97, 0.96}"
    Paint rectangle: "{1.0, 0.97, 0.96}", 0, durationB, 0, 1
    
    Colour: "{0.5, 0.3, 0.7}"
    Line width: 1.5
    for i from 2 to b_numFrames
        Draw line: b_time[i-1], b_normCent[i-1], b_time[i], b_normCent[i]
    endfor
    
    Colour: "{0.7, 0.4, 0.5}"
    Line width: 1
    for i from 2 to b_numFrames
        Draw line: b_time[i-1], b_normInt[i-1], b_time[i], b_normInt[i]
    endfor
    
    for g from 1 to b_numGestures
        if b_gTagCount[g] > 0
            if b_tag_AP[g] = 1
                colour$ = "{0.9, 0.25, 0.25}"
            elsif b_tag_NB[g] = 1
                colour$ = "{0.9, 0.7, 0.15}"
            elsif b_tag_BR[g] = 1
                colour$ = "{0.2, 0.75, 0.3}"
            elsif b_tag_BF[g] = 1
                colour$ = "{0.3, 0.55, 0.8}"
            else
                colour$ = "{0.6, 0.3, 0.7}"
            endif
            
            Colour: colour$
            Paint rectangle: colour$, b_gStart[g], b_gEnd[g], 0.92, 0.98
            
            if b_clusterCount[g] > 0
                Colour: "Black"
                Line width: 2
                Draw line: b_gStart[g], 0.90, b_gEnd[g], 0.90
            endif
        endif
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    
    Font size: 8
    Select outer viewport: 0, 1.0, 1.9, 3.1
    Axes: 0, 1, 0, 1
    Colour: "{0.5, 0.3, 0.7}"
    Text: 0.95, "right", 0.7, "half", "Sound B"
    Font size: 6
    Text: 0.95, "right", 0.4, "half", nameB$
    
    # Cluster connections
    Select outer viewport: 0, 8, 3.2, 4.4
    Select inner viewport: 1.0, 7.8, 3.3, 4.3
    
    globalDur = max(durationA, durationB)
    Axes: 0, globalDur, 0, 2
    
    Colour: "{0.98, 0.98, 0.98}"
    Paint rectangle: "{0.98, 0.98, 0.98}", 0, globalDur, 0, 2
    
    Colour: "{0.3, 0.5, 0.8}"
    Line width: 2
    Draw line: 0, 1.75, durationA, 1.75
    
    Colour: "{0.5, 0.3, 0.7}"
    Draw line: 0, 0.25, durationB, 0.25
    
    for c from 1 to numClusters
        gA = cluster_gA[c]
        gB = cluster_gB[c]
        conf = cluster_conf[c]
        
        midA = (a_gStart[gA] + a_gEnd[gA]) / 2
        midB = (b_gStart[gB] + b_gEnd[gB]) / 2
        
        lineW = 0.5 + conf * 3
        
        if cluster_mode$[c] = "LOCAL"
            Colour: "{0.2, 0.7, 0.35}"
        else
            Colour: "{0.85, 0.5, 0.2}"
        endif
        
        Line width: lineW
        Draw line: midA, 1.75, midB, 0.25
        
        Font size: 5
        Colour: "{0.3, 0.3, 0.3}"
        Text: (midA + midB) / 2, "centre", 1.0, "half", string$(c)
    endfor
    
    Colour: "Black"
    Line width: 0.5
    Draw inner box
    
    Font size: 8
    Select outer viewport: 0, 1.0, 3.2, 4.4
    Axes: 0, 1, 0, 1
    Colour: "{0.3, 0.3, 0.35}"
    Text: 0.95, "right", 0.6, "half", "Clusters"
    Font size: 6
    Colour: "{0.5, 0.5, 0.55}"
    Text: 0.95, "right", 0.35, "half", string$(numClusters) + " links"
    
    # Legend
    Select outer viewport: 0, 8, 4.5, 5.2
    Axes: 0, 1, 0, 1
    
    Font size: 6
    
    Colour: "{0.9, 0.25, 0.25}"
    Paint rectangle: "{0.9, 0.25, 0.25}", 0.02, 0.05, 0.5, 0.8
    Colour: "Black"
    Text: 0.06, "left", 0.65, "half", "PEAK"
    
    Colour: "{0.9, 0.7, 0.15}"
    Paint rectangle: "{0.9, 0.7, 0.15}", 0.12, 0.15, 0.5, 0.8
    Text: 0.16, "left", 0.65, "half", "BLOOM"
    
    Colour: "{0.2, 0.75, 0.3}"
    Paint rectangle: "{0.2, 0.75, 0.3}", 0.24, 0.27, 0.5, 0.8
    Text: 0.28, "left", 0.65, "half", "RISE"
    
    Colour: "{0.3, 0.55, 0.8}"
    Paint rectangle: "{0.3, 0.55, 0.8}", 0.35, 0.38, 0.5, 0.8
    Text: 0.39, "left", 0.65, "half", "FALL"
    
    Colour: "{0.6, 0.3, 0.7}"
    Paint rectangle: "{0.6, 0.3, 0.7}", 0.46, 0.49, 0.5, 0.8
    Text: 0.50, "left", 0.65, "half", "DROP"
    
    Colour: "{0.2, 0.7, 0.35}"
    Text: 0.02, "left", 0.2, "half", "— LOCAL"
    Colour: "{0.85, 0.5, 0.2}"
    Text: 0.12, "left", 0.2, "half", "— STRUCT"
    
    Font size: 5
    Colour: "{0.4, 0.4, 0.45}"
    Text: 0.60, "left", 0.75, "half", "Boost: +" + string$(anchorBoostDB) + "dB"
    Text: 0.60, "left", 0.45, "half", "Stamp: +" + string$(anchorStampDB) + "dB"
    Text: 0.60, "left", 0.15, "half", "Preset: " + presetName$
    
    Text: 0.80, "left", 0.75, "half", "Mode: " + modeText$
    Text: 0.80, "left", 0.45, "half", "Window: " + string$(perceptual_window_ms) + "ms"
    Text: 0.80, "left", 0.15, "half", "Min conf: " + fixed$(min_confidence, 2)
    
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# OUTPUT
# ============================================================

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "  Mode: ", modeText$
appendInfoLine: "  Gestures: a=", a_numGestures, " b=", b_numGestures
appendInfoLine: "  Clusters: ", numClusters
appendInfoLine: ""
appendInfoLine: "  Effect preset: ", presetName$
appendInfoLine: "    Anchor boost: +", anchorBoostDB, " dB"
appendInfoLine: "    Timbral stamp: +", anchorStampDB, " dB (2-4kHz)"
appendInfoLine: "    Stereo: anchor=", anchorWidth, " / outside=", outsideWidth
appendInfoLine: ""

selectObject: stereoMix

if play_result
    appendInfoLine: "Playing..."
    Play
endif

appendInfoLine: "Done!"