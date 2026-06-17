# ============================================================
# Praat AudioTools - Gesture-Based_Hard_Quantization.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3 (2026) - Output_duration (tiling) + typed folder path field
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Gesture-Based Hard Quantization - Segments a reference sound
#   and replaces each segment with the best-matching gesture from
#   a dictionary of sounds using k-best selection with repetition
#   penalty. Optionally generates 2-4 polyphonic voices, each with
#   independent selection parameters, panned across the stereo field.
#
#   PIPELINE:
#   1. Load folder (file 1 = reference, rest = gesture dictionary)
#   2. Preprocess all sounds (mono, resample, normalize intensity)
#   3. Extract pitch+intensity feature vectors from dictionary
#   4. Build global normalization ranges (reference + dictionary)
#   5. For each voice (1 to numVoices):
#      a. Segment reference into N equal parts
#      b. For each segment: extract features, find k-best match,
#         select randomly from top-k, apply repetition penalty
#      c. Replace each segment with matched gesture
#         (pad/Lengthen short gestures to exact segmentDur)
#      d. Apply 5ms fades + crossfade concatenation (no clicks)
#      e. Scale amplitude for voice blend
#   6. Pad all voices to same duration
#   7. Pan voices to stereo and sum (equal-power panning)
#   8. Normalize output
#
#   POLYPHONIC VOICE PROFILES:
#   Voice 1: Leader   - k=1 (deterministic, most coherent)
#   Voice 2: Shadow   - k=k_best, penalty phase-shifted by 1
#   Voice 3: Wander   - k=k_best*2, higher variety, penalty window=2
#   Voice 4: Scatter  - k=nDict (explores whole dictionary)
#
#   FIXES vs v1.0:
#   - Normalization range now includes reference sound
#   - Short gestures padded/Lengthened to exact segmentDur
#   - 5ms fades + Concatenate with overlap (no clicks)
#   - Dead code lines 692-693 removed
#   - Output waveform panel now labeled
#   - Recency penalty tracks last 3 choices per voice
#
# Category: Composition / Concatenative Synthesis
# ============================================================

# ============================================================
# FORM
# ============================================================

form Gesture Quantization v1.1
    comment === Preset ===
    optionmenu Preset: 2
        option Maximum Variety   (k=10, 4 voices)
        option Balanced          (k=7,  2 voices)
        option Coherent          (k=3,  1 voice)
        option Minimal           (k=1,  1 voice)
        option Custom
    comment === Segmentation ===
    positive Number_of_segments 20
    comment === Feature Matching ===
    positive K_best_matches 7
    positive Repetition_penalty 0.5
    comment === Polyphony ===
    optionmenu Num_voices: 2
        option 1 (mono)
        option 2 voices
        option 3 voices
        option 4 voices
    comment === Voice mix levels (dB, 0=unity) ===
    real Voice1_dB  0.0
    real Voice2_dB -3.0
    real Voice3_dB -5.0
    real Voice4_dB -7.0
    comment === Feature Extraction ===
    positive N_time_samples 50
    positive Pitch_floor 75
    positive Pitch_ceiling 600
    comment === Audio ===
    positive Target_sample_rate 44100
    comment === Input / Output ===
    sentence Folder_path
    comment (leave blank to get a chooser; first file = reference)
    real Output_duration 0
    comment (0 = match reference length; >0 = extend by tiling the reference)
    boolean Draw_visualization 1
    boolean Verbose_output 1
    boolean Play_result 1
endform

# ============================================================
# APPLY PRESET
# ============================================================

if preset = 1
    number_of_segments = 30
    k_best_matches     = 10
    repetition_penalty = 0.8
    num_voices         = 4
    presetName$        = "MaxVariety"
elsif preset = 2
    number_of_segments = 20
    k_best_matches     = 7
    repetition_penalty = 0.7
    num_voices         = 2
    presetName$        = "Balanced"
elsif preset = 3
    number_of_segments = 12
    k_best_matches     = 3
    repetition_penalty = 0.3
    num_voices         = 1
    presetName$        = "Coherent"
elsif preset = 4
    number_of_segments = 8
    k_best_matches     = 1
    repetition_penalty = 0.0
    num_voices         = 1
    presetName$        = "Minimal"
else
    presetName$        = "Custom"
endif

# num_voices from optionmenu is 1-4 (index), but preset may have set it
# If preset didn't set num_voices, use form value
if preset = 5
    num_voices = num_voices
endif

# ============================================================
# DIRECTORY SELECTION
# ============================================================

clearinfo

folder_path$ = folder_path$
if folder_path$ = ""
    folder_path$ = chooseDirectory$: "Select folder containing sound files (first file = reference)"
endif

if folder_path$ = ""
    exitScript: "No folder selected."
endif

if right$(folder_path$, 1) <> "/" and right$(folder_path$, 1) <> "\"
    folder_path$ = folder_path$ + "/"
endif

# ============================================================
# HELPER PROCEDURES
# ============================================================

procedure log: .message$
    if verbose_output
        appendInfoLine: .message$
    endif
endproc

procedure normalizeIntensity: .soundID
    selectObject: .soundID
    Scale intensity: 70
endproc

procedure convertToMono: .soundID
    selectObject: .soundID
    .nCh = Get number of channels
    if .nCh > 1
        .mono = Convert to mono
        removeObject: .soundID
        .soundID = .mono
    endif
    convertToMono.result = .soundID
endproc

procedure resampleIfNeeded: .soundID, .targetRate
    selectObject: .soundID
    .curRate = Get sampling frequency
    if .curRate <> .targetRate
        .resampled = Resample: .targetRate, 50
        removeObject: .soundID
        .soundID = .resampled
    endif
    resampleIfNeeded.result = .soundID
endproc

# extractFeatureVector: writes into global feature_vector_1 ... feature_vector_(2*nSamples)
# First half = pitch (Hz), second half = intensity (dB)
procedure extractFeatureVector: .soundID, .nSamples
    selectObject: .soundID
    .dur   = Get total duration
    .tStart = Get start time
    .tEnd   = Get end time

    # Praat requires pitch_floor >= 3 / duration (same guard pattern as intensity)
    .effectivePitchFloor = pitch_floor
    .minAllowedPitchFloor = 3 / .dur
    if .effectivePitchFloor < .minAllowedPitchFloor
        .effectivePitchFloor = ceiling(.minAllowedPitchFloor) + 10
    endif
    if .effectivePitchFloor > pitch_ceiling - 1
        .effectivePitchFloor = pitch_ceiling - 1
    endif
    .pitch = To Pitch: 0.01, .effectivePitchFloor, pitch_ceiling

    selectObject: .soundID
    .iPitchFloor = 100
    .minDurForInt = 6.4 / .iPitchFloor
    if .dur < .minDurForInt
        .iPitchFloor = ceiling(6.4 / .dur) + 10
        if .iPitchFloor > 500
            .iPitchFloor = 500
        endif
    endif
    .intensity = To Intensity: .iPitchFloor, 0, "yes"

    .tStep = .dur / (.nSamples - 1)
    if .tStep <= 0
        .tStep = .dur / 2
    endif

    for .ii to .nSamples
        .t = .tStart + (.ii - 1) * .tStep
        if .t > .tEnd
            .t = .tEnd
        endif

        selectObject: .pitch
        .f0 = Get value at time: .t, "Hertz", "Linear"
        if .f0 = undefined
            .f0 = 0
        endif
        feature_vector_'.ii' = .f0

        selectObject: .intensity
        .db = Get value at time: .t, "Cubic"
        if .db = undefined
            .db = 0
        endif
        .idx2 = .nSamples + .ii
        feature_vector_'.idx2' = .db
    endfor

    removeObject: .pitch, .intensity
endproc

# normalizeFeatures: normalizes global feature_vector in place
procedure normalizeFeatures: .vectorLen, .minP, .maxP, .minD, .maxD
    for .ii to n_time_samples
        .val = feature_vector_'.ii'
        if .maxP > .minP
            feature_vector_'.ii' = (.val - .minP) / (.maxP - .minP)
        else
            feature_vector_'.ii' = 0
        endif
    endfor
    for .ii from n_time_samples + 1 to .vectorLen
        .val = feature_vector_'.ii'
        if .maxD > .minD
            feature_vector_'.ii' = (.val - .minD) / (.maxD - .minD)
        else
            feature_vector_'.ii' = 0
        endif
    endfor
endproc

# euclideanDistance: compares global feature_vector vs global dict_vector
procedure euclideanDistance: .vLen
    .dist = 0
    for .ii to .vLen
        .diff = feature_vector_'.ii' - dict_vector_'.ii'
        .dist = .dist + .diff * .diff
    endfor
    euclideanDistance.distance = sqrt(.dist)
endproc

# findKBestMatches: selects from dictionary, applies penalty for last 3 choices
# .voiceHistory_1/.voiceHistory_2/.voiceHistory_3 = recent indices for this voice
procedure findKBestMatches: .nPatterns, .k, .h1, .h2, .h3
    for .ii to .nPatterns
        candidate_dist_'.ii' = 10000
        candidate_idx_'.ii'  = .ii
    endfor

    for .dictIdx to .nPatterns
        for .jj to vectorLength
            dict_vector_'.jj' = dict_features_'.dictIdx'_'.jj'
        endfor
        @euclideanDistance: vectorLength
        .dist = euclideanDistance.distance

        # Recency penalty: last 3 choices get increasing penalty
        if .dictIdx = .h1 and repetition_penalty > 0
            .dist = .dist * (1 + repetition_penalty)
        endif
        if .dictIdx = .h2 and repetition_penalty > 0
            .dist = .dist * (1 + repetition_penalty * 0.6)
        endif
        if .dictIdx = .h3 and repetition_penalty > 0
            .dist = .dist * (1 + repetition_penalty * 0.3)
        endif

        candidate_dist_'.dictIdx' = .dist
    endfor

    # Partial selection sort to find top k
    for .ii to .k
        .minIdx  = .ii
        .minDist = candidate_dist_'.ii'
        for .jj from .ii + 1 to .nPatterns
            .testDist = candidate_dist_'.jj'
            if .testDist < .minDist
                .minDist = .testDist
                .minIdx  = .jj
            endif
        endfor
        if .minIdx <> .ii
            .tmpDist = candidate_dist_'.ii'
            .tmpIdx  = candidate_idx_'.ii'
            candidate_dist_'.ii'    = candidate_dist_'.minIdx'
            candidate_idx_'.ii'     = candidate_idx_'.minIdx'
            candidate_dist_'.minIdx' = .tmpDist
            candidate_idx_'.minIdx'  = .tmpIdx
        endif
    endfor

    if .k = 1
        findKBestMatches.selectedIndex    = candidate_idx_1
        findKBestMatches.selectedDistance = candidate_dist_1
    else
        .rChoice = randomInteger(1, .k)
        findKBestMatches.selectedIndex    = candidate_idx_'.rChoice'
        findKBestMatches.selectedDistance = candidate_dist_'.rChoice'
    endif
endproc

# buildVoice: runs full selection+assembly for one voice
# .vIdx      = voice number (1-4)
# .kForVoice = k_best to use for this voice
# .penScale  = multiplier on repetition_penalty for this voice
# writes: voiceSound_'vIdx' (Sound ID), voiceDist_'vIdx'_'segIdx' (distances)
procedure buildVoice: .vIdx, .kForVoice, .penScale
    @log: "  Voice " + string$(.vIdx) + ": k=" + string$(.kForVoice) +
        ... "  penalty_scale=" + fixed$(.penScale, 1)

    # Clamp k to dictionary size
    .kUse = .kForVoice
    if .kUse > nDictSounds
        .kUse = nDictSounds
    endif
    if .kUse < 1
        .kUse = 1
    endif

    # History ring (last 3 choices)
    .hist1 = 0
    .hist2 = 0
    .hist3 = 0

    # Stagger starting history for variety among voices
    if .vIdx = 2
        .hist1 = randomInteger(1, nDictSounds)
    elsif .vIdx = 3
        .hist1 = randomInteger(1, nDictSounds)
        .hist2 = randomInteger(1, nDictSounds)
    elsif .vIdx = 4
        .hist1 = randomInteger(1, nDictSounds)
        .hist2 = randomInteger(1, nDictSounds)
        .hist3 = randomInteger(1, nDictSounds)
    endif

    # Temporarily scale repetition_penalty
    savedPenalty = repetition_penalty
    repetition_penalty = repetition_penalty * .penScale

    hasOutput = 0
    currentOutput = 0

    for .segIdx to segmentsToGenerate
        # tile the reference cyclically when generating more than N segments
        .refSegIdx = ((.segIdx - 1) mod number_of_segments) + 1
        .segStart = refStart + (.refSegIdx - 1) * segmentDur
        .segEnd   = .segStart + segmentDur

        selectObject: refSound
        .seg = Extract part: .segStart, .segEnd, "rectangular", 1, "no"

        @extractFeatureVector: .seg, n_time_samples
        @normalizeFeatures: vectorLength, globalMinPitch, globalMaxPitch, globalMinDB, globalMaxDB
        removeObject: .seg

        @findKBestMatches: nDictSounds, .kUse, .hist1, .hist2, .hist3

        .bestIdx  = findKBestMatches.selectedIndex
        .bestDist = findKBestMatches.selectedDistance

        # Store per-voice distance + match index for stats/visualization
        voiceDist_'.vIdx'_'.segIdx' = .bestDist
        voiceMatch_'.vIdx'_'.segIdx' = .bestIdx

        # Update history ring
        .hist3 = .hist2
        .hist2 = .hist1
        .hist1 = .bestIdx

        # Get gesture sound
        .dictSoundIdx = .bestIdx + 1
        .gestureSound = soundID_'.dictSoundIdx'

        selectObject: .gestureSound
        .gestureDur = Get total duration
        .gestureStart = Get start time

        # Extract exactly segmentDur from gesture
        if .gestureDur >= segmentDur
            # Gesture is long enough: extract front
            .piece = Extract part: .gestureStart, .gestureStart + segmentDur, "rectangular", 1, "no"
        else
            # Gesture too short: Lengthen to fit
            .fullCopy = Copy: "gest_short"
            selectObject: .fullCopy
            .lenFactor = segmentDur / .gestureDur
            if .lenFactor > 8.0
                .lenFactor = 8.0
            endif
            Lengthen (overlap-add): 75, 600, .lenFactor
            .stretched = selected("Sound")
            removeObject: .fullCopy
            # Now trim to exact segmentDur (must select the stretched
            # sound first - removeObject above cleared the selection)
            selectObject: .stretched
            .piece = Extract part: 0, segmentDur, "rectangular", 1, "no"
            removeObject: .stretched
        endif

        # 5ms click-prevention fades on each piece
        selectObject: .piece
        .pieceDur = Get total duration
        .fadeSec = 0.005
        if .fadeSec > .pieceDur * 0.15
            .fadeSec = .pieceDur * 0.15
        endif
        if .fadeSec > 0.0005
            .fsStr$ = fixed$(.fadeSec, 8)
            Formula: "if x - xmin < " + .fsStr$ +
                ... " then self * ((x - xmin) / " + .fsStr$ + ")" +
                ... " else self fi"
            Formula: "if xmax - x < " + .fsStr$ +
                ... " then self * ((xmax - x) / " + .fsStr$ + ")" +
                ... " else self fi"
        endif

        # Concatenate
        if hasOutput = 0
            selectObject: .piece
            currentOutput = Copy: "voice_asm"
            removeObject: .piece
            hasOutput = 1
        else
            selectObject: currentOutput
            plusObject: .piece
            .xfSec = 0.01
            if .xfSec > segmentDur * 0.2
                .xfSec = segmentDur * 0.2
            endif
            .newAsm = Concatenate with overlap: .xfSec
            removeObject: currentOutput, .piece
            currentOutput = .newAsm
        endif
    endfor

    # Restore penalty
    repetition_penalty = savedPenalty

    # Scale amplitude for voice blend
    if .vIdx = 1
        .voiceDB = voice1_dB
    elsif .vIdx = 2
        .voiceDB = voice2_dB
    elsif .vIdx = 3
        .voiceDB = voice3_dB
    else
        .voiceDB = voice4_dB
    endif
    .ampScale = 10 ^ (.voiceDB / 20)

    selectObject: currentOutput
    Formula: "self * " + fixed$(.ampScale, 6)

    voiceSound_'.vIdx' = currentOutput
endproc

# ============================================================
# LOAD AND PREPROCESS
# ============================================================

if verbose_output
    appendInfoLine: "════════════════════════════════════════════════════════"
    appendInfoLine: "  Gesture-Based Hard Quantization v1.1"
    appendInfoLine: "════════════════════════════════════════════════════════"
    appendInfoLine: ""
    appendInfoLine: "Preset:   ", presetName$
    appendInfoLine: "Voices:   ", num_voices
    appendInfoLine: "Segments: ", number_of_segments
    appendInfoLine: "K-best:   ", k_best_matches
    appendInfoLine: "Penalty:  ", fixed$(repetition_penalty, 2)
    appendInfoLine: ""
endif

@log: "Reading folder: " + folder_path$
fileList = Create Strings as file list: "fileList", folder_path$ + "*.wav"
nFiles = Get number of strings

if nFiles < 2
    removeObject: fileList
    exitScript: "Need at least 2 .wav files (1 reference + 1 dictionary)."
endif

@log: "Found " + string$(nFiles) + " sound files"
@log: ""

vectorLength  = 2 * n_time_samples
nDictSounds   = nFiles - 1

# Initialize dict feature storage
for .ii to nDictSounds
    for .jj to vectorLength
        dict_features_'.ii'_'.jj' = 0
    endfor
endfor

@log: "Loading and preprocessing..."
@log: ""

for fileIdx to nFiles
    selectObject: fileList
    filename$  = Get string: fileIdx
    filepath$  = folder_path$ + filename$
    @log: "  [" + string$(fileIdx) + "/" + string$(nFiles) + "] " + filename$
    sound = Read from file: filepath$
    @convertToMono: sound
    sound = convertToMono.result
    @resampleIfNeeded: sound, target_sample_rate
    sound = resampleIfNeeded.result
    @normalizeIntensity: sound
    soundID_'fileIdx' = sound
    selectObject: sound
    soundName_'fileIdx'$ = selected$("Sound")
endfor
@log: ""

# ============================================================
# EXTRACT FEATURES — DICTIONARY + REFERENCE (global ranges)
# ============================================================

@log: "Building gesture dictionary (" + string$(nDictSounds) + " gestures)..."
@log: ""

# Global normalization ranges include ALL sounds (fix v1.0)
globalMinPitch = 10000
globalMaxPitch = 0
globalMinDB    = 10000
globalMaxDB    = -10000

# Extract features for dictionary sounds
for dictIdx to nDictSounds
    soundIdx = dictIdx + 1
    @log: "  Dict " + string$(dictIdx) + ": " + soundName_'soundIdx'$
    @extractFeatureVector: soundID_'soundIdx', n_time_samples
    for jj to vectorLength
        fv = feature_vector_'jj'
        dict_features_'dictIdx'_'jj' = fv
        if jj <= n_time_samples
            if fv > 0
                if fv < globalMinPitch
                    globalMinPitch = fv
                endif
                if fv > globalMaxPitch
                    globalMaxPitch = fv
                endif
            endif
        else
            if fv < globalMinDB
                globalMinDB = fv
            endif
            if fv > globalMaxDB
                globalMaxDB = fv
            endif
        endif
    endfor
endfor

# Also scan reference to widen ranges (fix: was excluded in v1.0)
@extractFeatureVector: soundID_1, n_time_samples
for jj to vectorLength
    fv = feature_vector_'jj'
    if jj <= n_time_samples
        if fv > 0
            if fv < globalMinPitch
                globalMinPitch = fv
            endif
            if fv > globalMaxPitch
                globalMaxPitch = fv
            endif
        endif
    else
        if fv < globalMinDB
            globalMinDB = fv
        endif
        if fv > globalMaxDB
            globalMaxDB = fv
        endif
    endif
endfor

@log: ""
@log: "Global normalization ranges:"
@log: "  Pitch: " + fixed$(globalMinPitch, 1) + " - " + fixed$(globalMaxPitch, 1) + " Hz"
@log: "  Intensity: " + fixed$(globalMinDB, 1) + " - " + fixed$(globalMaxDB, 1) + " dB"
@log: ""

# Normalize dictionary features
@log: "Normalizing dictionary features..."
for dictIdx to nDictSounds
    for jj to vectorLength
        feature_vector_'jj' = dict_features_'dictIdx'_'jj'
    endfor
    @normalizeFeatures: vectorLength, globalMinPitch, globalMaxPitch, globalMinDB, globalMaxDB
    for jj to vectorLength
        dict_features_'dictIdx'_'jj' = feature_vector_'jj'
    endfor
endfor
@log: "Dictionary ready."
@log: ""

# ============================================================
# REFERENCE SETUP
# ============================================================

refSound   = soundID_1
selectObject: refSound
refDur     = Get total duration
refStart   = Get start time
segmentDur = refDur / number_of_segments

# number_of_segments analyses the reference. If Output_duration > 0 we
# GENERATE more segments than the reference has, tiling the reference
# cyclically (segment i reads reference region ((i-1) mod N)), so a short
# reference can drive a long output. The matching still evolves per pass
# (recency penalty + k-best randomness), so it is not a literal loop.
segmentsToGenerate = number_of_segments
if output_duration > 0
    segmentsToGenerate = ceiling(output_duration / segmentDur)
    if segmentsToGenerate < 1
        segmentsToGenerate = 1
    endif
endif

@log: "Reference: " + soundName_1$
@log: "  Duration:     " + fixed$(refDur, 3) + " s"
@log: "  Analysis segs:" + string$(number_of_segments)
@log: "  Segment dur:  " + fixed$(segmentDur, 3) + " s"
if output_duration > 0
    @log: "  Output target:" + fixed$(output_duration, 2) + " s -> " +
        ... string$(segmentsToGenerate) + " segments (tiled)"
endif
@log: ""

# ============================================================
# BUILD VOICES
# ============================================================

@log: "Building " + string$(num_voices) + " voice(s)..."
@log: ""

# Voice profiles:
# Voice 1: Leader   - k=1, penalty=1.0x (deterministic)
# Voice 2: Shadow   - k=k_best, penalty=1.0x (staggered history)
# Voice 3: Wander   - k=k_best*2, penalty=1.3x (wider search)
# Voice 4: Scatter  - k=nDict, penalty=1.5x (full dictionary)

for vv to num_voices
    if vv = 1
        .kV = 1
        .pS = 1.0
    elsif vv = 2
        .kV = k_best_matches
        .pS = 1.0
    elsif vv = 3
        .kV = k_best_matches * 2
        .pS = 1.3
    else
        .kV = nDictSounds
        .pS = 1.5
    endif
    @buildVoice: vv, .kV, .pS
    @log: ""
endfor

# ============================================================
# COMPUTE STATISTICS (Voice 1 = representative)
# ============================================================

sumDist     = 0
statMinDist = voiceDist_1_1
statMaxDist = voiceDist_1_1

for segIdx to segmentsToGenerate
    dist = voiceDist_1_'segIdx'
    sumDist = sumDist + dist
    if dist < statMinDist
        statMinDist = dist
    endif
    if dist > statMaxDist
        statMaxDist = dist
    endif
endfor
meanDist = sumDist / segmentsToGenerate

sumSqDiff = 0
for segIdx to segmentsToGenerate
    diff = voiceDist_1_'segIdx' - meanDist
    sumSqDiff = sumSqDiff + diff * diff
endfor
stdDist = sqrt(sumSqDiff / segmentsToGenerate)

# Gesture usage (voice 1): count how often each dictionary gesture was
# chosen, how many distinct gestures were used, and the peak reuse.
for dictIdx to nDictSounds
    gestureCount_'dictIdx' = 0
endfor
for segIdx to segmentsToGenerate
    m = voiceMatch_1_'segIdx'
    if m >= 1 and m <= nDictSounds
        gestureCount_'m' = gestureCount_'m' + 1
    endif
endfor
uniqueCount = 0
maxUsage    = 0
for dictIdx to nDictSounds
    c = gestureCount_'dictIdx'
    if c > 0
        uniqueCount = uniqueCount + 1
    endif
    if c > maxUsage
        maxUsage = c
    endif
endfor

# ============================================================
# MIX VOICES TO OUTPUT
# ============================================================

@log: "Mixing " + string$(num_voices) + " voice(s) to output..."

# Pan positions — always defined for all 4 slots so viz never hits unknown variable
panPos_1 = 0.0
panPos_2 = 0.0
panPos_3 = 0.0
panPos_4 = 0.0

if num_voices = 1
    # Mono output - just rename voice 1
    selectObject: voiceSound_1
    peakV = Get absolute extremum: 0, 0, "None"
    if peakV > 0
        Scale peak: 0.95
    endif
    outputName$ = "gesture_quant_" + presetName$ + "_" + soundName_1$
    outputName$ = replace$(outputName$, " ", "_", 0)
    Rename: outputName$
    outputSound = selected("Sound")
    outputDur   = Get total duration

else
    # Find longest voice duration for padding
    maxVoiceDur = 0
    for vv to num_voices
        selectObject: voiceSound_'vv'
        vDur = Get total duration
        if vDur > maxVoiceDur
            maxVoiceDur = vDur
        endif
    endfor

    # Pad all voices to maxVoiceDur
    for vv to num_voices
        selectObject: voiceSound_'vv'
        vDur = Get total duration
        padNeeded = maxVoiceDur - vDur
        if padNeeded > 0.005
            Create Sound from formula: "pad", 1, 0, padNeeded, target_sample_rate, "0"
            padSnd = selected("Sound")
            selectObject: voiceSound_'vv'
            plusObject: padSnd
            paddedVoice = Concatenate
            removeObject: voiceSound_'vv', padSnd
            voiceSound_'vv' = paddedVoice
        endif
    endfor

    if num_voices = 2
        panPos_1 = -0.55
        panPos_2 =  0.55
    elsif num_voices = 3
        panPos_1 = -0.70
        panPos_2 =  0.00
        panPos_3 =  0.70
    else
        panPos_1 = -0.75
        panPos_2 = -0.25
        panPos_3 =  0.25
        panPos_4 =  0.75
    endif

    # Create stereo sum (start with zeros at maxVoiceDur)
    Create Sound from formula: "gq_L", 1, 0, maxVoiceDur, target_sample_rate, "0"
    leftAcc = selected("Sound")
    Create Sound from formula: "gq_R", 1, 0, maxVoiceDur, target_sample_rate, "0"
    rightAcc = selected("Sound")

    # Equal-power pan and add each voice
    for vv to num_voices
        panP = panPos_'vv'
        # Equal-power: angle in [0, pi/2]
        panNorm = (panP + 1) / 2
        lGain   = cos(panNorm * pi / 2)
        rGain   = sin(panNorm * pi / 2)

        # Scale voice to L channel contribution
        selectObject: voiceSound_'vv'
        lChan = Copy: "gq_lc"
        selectObject: lChan
        Formula: "self * " + fixed$(lGain, 6)

        selectObject: voiceSound_'vv'
        rChan = Copy: "gq_rc"
        selectObject: rChan
        Formula: "self * " + fixed$(rGain, 6)

        # Add to accumulators
        selectObject: leftAcc
        Formula: "self + object[lChan]"
        selectObject: rightAcc
        Formula: "self + object[rChan]"

        removeObject: lChan, rChan
    endfor

    # Combine to stereo
    selectObject: leftAcc
    plusObject: rightAcc
    Combine to stereo
    stereoOut = selected("Sound")
    removeObject: leftAcc, rightAcc

    selectObject: stereoOut
    peakV = Get absolute extremum: 0, 0, "None"
    if peakV > 0
        Scale peak: 0.95
    endif

    outputName$ = "gesture_quant_" + presetName$ + "_" + string$(num_voices) + "v_" + soundName_1$
    outputName$ = replace$(outputName$, " ", "_", 0)
    Rename: outputName$
    outputSound = stereoOut
    outputDur   = Get total duration

    # Remove voice intermediates
    for vv to num_voices
        removeObject: voiceSound_'vv'
    endfor
endif

@log: "Output: " + outputName$
@log: "Duration: " + fixed$(outputDur, 2) + " s"
@log: ""

# ============================================================
# VERBOSE STATISTICS
# ============================================================

if verbose_output
    appendInfoLine: "════════════════════════════════════════════════════════"
    appendInfoLine: "  SUMMARY STATISTICS"
    appendInfoLine: "════════════════════════════════════════════════════════"
    appendInfoLine: ""
    appendInfoLine: "Preset:    ", presetName$
    appendInfoLine: "Reference: ", soundName_1$
    appendInfoLine: "Dictionary:", nDictSounds, " gestures"
    appendInfoLine: "Voices:    ", num_voices
    appendInfoLine: ""
    appendInfoLine: "Parameters:"
    appendInfoLine: "  Segments:         ", number_of_segments
    appendInfoLine: "  Segment duration: ", fixed$(segmentDur, 3), " s"
    appendInfoLine: "  K-best (voice 1): 1 (deterministic leader)"
    if num_voices > 1
        appendInfoLine: "  K-best (voice 2): ", k_best_matches
    endif
    if num_voices > 2
        appendInfoLine: "  K-best (voice 3): ", k_best_matches * 2
    endif
    if num_voices > 3
        appendInfoLine: "  K-best (voice 4): ", nDictSounds, " (full dict)"
    endif
    appendInfoLine: "  Repetition penalty: ", fixed$(repetition_penalty, 2)
    appendInfoLine: ""
    appendInfoLine: "Voice 1 Distance Statistics:"
    appendInfoLine: "  Mean: ", fixed$(meanDist, 4)
    appendInfoLine: "  Std:  ", fixed$(stdDist,  4)
    appendInfoLine: "  Min:  ", fixed$(statMinDist, 4)
    appendInfoLine: "  Max:  ", fixed$(statMaxDist, 4)
    appendInfoLine: ""
    appendInfoLine: "Voice 1 Gesture Usage:"
    appendInfoLine: "  Distinct gestures used: ", uniqueCount, " / ", nDictSounds
    appendInfoLine: "  Most-reused gesture:    ", maxUsage, " segment(s)"
    appendInfoLine: ""
    appendInfoLine: "════════════════════════════════════════════════════════"
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    @log: "Drawing visualization..."

    selectObject: refSound
    refPeak = Get absolute extremum: 0, 0, "None"
    if refPeak < 0.001
        refPeak = 0.001
    endif
    ampMax = refPeak * 1.15

    Erase all

    # === TITLE ===
    Select outer viewport: 0, 8, 0, 0.48
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.70, "half", "##Gesture-Based Hard Quantization v1.1##"
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -0.15, "half",
        ... "[" + presetName$ + "]  " + soundName_1$
        ... + "  |  " + string$(num_voices) + " voice(s)"
        ... + "  |  k=" + string$(k_best_matches)
        ... + "  |  " + string$(nDictSounds) + " gestures"
        ... + "  |  " + string$(number_of_segments) + " seg"

    # === PANEL 1: Reference waveform ===
    Select outer viewport: 0, 8, 0.52, 1.35
    Select inner viewport: 0.60, 7.65, 0.57, 1.30
    Axes: 0, refDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, refDur, -ampMax, ampMax
    Colour: "{0.80, 0.80, 0.80}"
    Draw line: 0, 0, refDur, 0
    # Segment boundary lines
    for segIdx to segmentsToGenerate - 1
        bTime = refStart + segIdx * segmentDur
        Colour: "{0.72, 0.78, 0.88}"
        Dotted line
        Draw line: bTime, -ampMax, bTime, ampMax
        Solid line
    endfor
    selectObject: refSound
    Colour: "{0.45, 0.50, 0.58}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Reference"
    Text top: "no", "Input  (dotted = segment boundaries)"

    # === PANEL 2: Output waveform ===
    Select outer viewport: 0, 8, 1.38, 2.20
    Select inner viewport: 0.60, 7.65, 1.43, 2.15
    Axes: 0, outputDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, outputDur, -ampMax, ampMax
    Colour: "{0.80, 0.80, 0.80}"
    Draw line: 0, 0, outputDur, 0
    selectObject: outputSound
    Colour: "{0.25, 0.55, 0.45}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text top: "no", "Quantized output  (" + string$(num_voices) + " voice(s))"
    Text bottom: "yes", "Time (s)"

    # === PANEL 3: Segment → Gesture mapping (voice 1) ===
    Select outer viewport: 0, 8, 2.28, 3.32
    Select inner viewport: 0.60, 7.65, 2.33, 3.27
    Axes: 0, segmentsToGenerate, 0, nDictSounds + 1
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, segmentsToGenerate, 0, nDictSounds + 1

    # Horizontal grid lines per gesture
    for dictIdx to nDictSounds
        Colour: "{0.88, 0.88, 0.88}"
        Draw line: 0, dictIdx, segmentsToGenerate, dictIdx
    endfor

    # Colored bars per segment (color = match distance quality)
    for segIdx to segmentsToGenerate
        dist     = voiceDist_1_'segIdx'
        distNorm = (dist - statMinDist) / (statMaxDist - statMinDist + 0.001)
        cR = 0.35 + distNorm * 0.45
        cG = 0.72 - distNorm * 0.32
        cB = 0.35
        cRs$ = fixed$(cR, 2)
        cGs$ = fixed$(cG, 2)
        cBs$ = fixed$(cB, 2)
        # Use distance as y position (approximation - proportional to distance)
        yPos = 1 + distNorm * (nDictSounds - 1)
        Paint rectangle: "{" + cRs$ + "," + cGs$ + "," + cBs$ + "}",
            ... segIdx - 1, segIdx, yPos - 0.4, yPos + 0.4
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Distance"
    Text bottom: "yes", "Segment"
    Text top: "no", "Voice 1 match distances  (green=close  orange=far)"

    # === PANEL 4: Per-voice distance comparison (if >1 voice) ===
    Select outer viewport: 0, 4, 3.40, 4.45
    Select inner viewport: 0.55, 3.75, 3.45, 4.40

    if statMaxDist < 0.001
        statMaxDist = 1
    endif
    Axes: 0, segmentsToGenerate + 1, 0, statMaxDist * 1.2
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, segmentsToGenerate + 1, 0, statMaxDist * 1.2

    # Mean line
    Colour: "{0.80, 0.80, 0.80}"
    Dotted line
    Draw line: 0, meanDist, segmentsToGenerate + 1, meanDist
    Solid line

    # Voice colors
    vc_1R = 0.25
    vc_1G = 0.50
    vc_1B = 0.75
    vc_2R = 0.80
    vc_2G = 0.40
    vc_2B = 0.20
    vc_3R = 0.25
    vc_3G = 0.65
    vc_3B = 0.40
    vc_4R = 0.65
    vc_4G = 0.25
    vc_4B = 0.65

    for vv to num_voices
        cR$ = fixed$(vc_'vv'R, 2)
        cG$ = fixed$(vc_'vv'G, 2)
        cB$ = fixed$(vc_'vv'B, 2)
        Colour: "{" + cR$ + "," + cG$ + "," + cB$ + "}"
        Line width: 1.2
        for segIdx from 2 to segmentsToGenerate
            prevIdx = segIdx - 1
            d1 = voiceDist_'vv'_'prevIdx'
            d2 = voiceDist_'vv'_'segIdx'
            Draw line: prevIdx, d1, segIdx, d2
        endfor
        Line width: 1
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Distance"
    Text bottom: "yes", "Segment"
    Text top: "no", "Match distances by voice"

    # Legend
    if num_voices > 1
        Font size: 5
        xLeg = segmentsToGenerate * 0.65
        yLeg = statMaxDist * 1.15
        yStep = statMaxDist * 0.10
        for vv to num_voices
            cR$ = fixed$(vc_'vv'R, 2)
            cG$ = fixed$(vc_'vv'G, 2)
            cB$ = fixed$(vc_'vv'B, 2)
            Colour: "{" + cR$ + "," + cG$ + "," + cB$ + "}"
            Text: xLeg, "left", yLeg - (vv - 1) * yStep, "half", "V" + string$(vv)
        endfor
    endif

    # === PANEL 5: Pan positions (if >1 voice) ===
    if num_voices > 1
    Select outer viewport: 4, 8, 3.40, 4.45
    Select inner viewport: 4.20, 7.65, 3.45, 4.40
    Axes: 0, num_voices + 1, -1.1, 1.1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, num_voices + 1, -1.1, 1.1

    # Center line
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, num_voices + 1, 0
    # L/R labels
    Font size: 6
    Colour: "{0.65, 0.65, 0.65}"
    Text: 0.15, "left", -0.95, "half", "L"
    Text: 0.15, "left",  0.95, "half", "R"

    for vv to num_voices
        panP = panPos_'vv'
        cR$ = fixed$(vc_'vv'R, 2)
        cG$ = fixed$(vc_'vv'G, 2)
        cB$ = fixed$(vc_'vv'B, 2)
        Paint rectangle: "{" + cR$ + "," + cG$ + "," + cB$ + "}",
            ... vv - 0.35, vv + 0.35, 0, panP
        Font size: 6
        Colour: "Black"
        if panP >= 0
            labelY = panP + 0.08
        else
            labelY = panP - 0.08
        endif
        Text: vv, "centre", labelY, "half", fixed$(panP, 2)
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Pan"
    Text bottom: "yes", "Voice"
    Text top: "no", "Voice pan positions (L=-1  R=+1)"
    endif

    # === PANEL 6: Statistics ===
    Select outer viewport: 0, 8, 4.52, 5.20
    Select inner viewport: 0.40, 7.75, 4.57, 5.15
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.87, "half", "##Gesture-Based Hard Quantization v1.1##"
    Font size: 6
    Colour: "{0.35, 0.35, 0.40}"
    Text: 0.02, "left", 0.65, "half",
        ... "Reference: " + soundName_1$
        ... + "  |  Preset: " + presetName$
        ... + "  |  Voices: " + string$(num_voices)
        ... + "  |  Dict: " + string$(nDictSounds) + " gestures"
    Text: 0.02, "left", 0.44, "half",
        ... "Segments: " + string$(number_of_segments)
        ... + "  |  Seg dur: " + fixed$(segmentDur * 1000, 0) + " ms"
        ... + "  |  K-best: " + string$(k_best_matches)
        ... + "  |  Penalty: " + fixed$(repetition_penalty, 2)
    Text: 0.02, "left", 0.23, "half",
        ... "V1 dist: mean=" + fixed$(meanDist, 3)
        ... + "  std=" + fixed$(stdDist, 3)
        ... + "  min=" + fixed$(statMinDist, 3)
        ... + "  max=" + fixed$(statMaxDist, 3)
        ... + "  |  Output: " + outputName$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1

    @log: "  Visualization complete."
endif

# ============================================================
# CLEANUP
# ============================================================

@log: "Cleaning up..."

for ii to nFiles
    removeObject: soundID_'ii'
endfor
removeObject: fileList

# ============================================================
# OUTPUT
# ============================================================

selectObject: outputSound

appendInfoLine: ""
appendInfoLine: "════════════════════════════════════════════════════════"
appendInfoLine: "  COMPLETE"
appendInfoLine: "════════════════════════════════════════════════════════"
appendInfoLine: "Output:   ", outputName$
appendInfoLine: "Duration: ", fixed$(outputDur, 2), " s"
appendInfoLine: "Voices:   ", num_voices
if num_voices = 1
    appendInfoLine: "Channels: 1 (mono)"
else
    appendInfoLine: "Channels: 2 (stereo)"
endif

if play_result
    Play
endif
