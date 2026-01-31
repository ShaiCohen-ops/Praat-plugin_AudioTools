# ============================================================
# Praat AudioTools - Gesture-Based_Hard_Quantization.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025) - Added visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Gesture-Based Hard Quantization - Segments a reference sound
#   and replaces each segment with the best-matching gesture from
#   a dictionary of sounds using k-best selection with repetition penalty.
#
# Changelog v1.0:
#   - Added comprehensive visualization
#   - Segment mapping timeline
#   - Gesture usage histogram
#   - Distance statistics display
# ============================================================

form Gesture Quantization v1.0
    comment === PRESETS ===
    optionmenu Preset: 2
        option Maximum Variety (k=10)
        option Balanced (k=7)
        option Coherent (k=3)
        option Minimal (k=1)
        option Custom
    comment === CUSTOM SETTINGS ===
    positive Number_of_segments 20
    positive K_best_matches 7
    positive Repetition_penalty 0.5
    comment === FEATURE EXTRACTION ===
    positive N_time_samples 50
    positive Pitch_floor 75
    positive Pitch_ceiling 600
    comment === AUDIO ===
    positive Target_sample_rate 44100
    comment === OUTPUT ===
    boolean Draw_visualization 1
    boolean Verbose_output 1
    boolean Play_result 1
endform

################################################################################
# APPLY PRESET
################################################################################

if preset = 1
    number_of_segments = 30
    k_best_matches = 10
    repetition_penalty = 0.8
    presetName$ = "MaxVariety"
elsif preset = 2
    number_of_segments = 20
    k_best_matches = 7
    repetition_penalty = 0.7
    presetName$ = "Balanced"
elsif preset = 3
    number_of_segments = 12
    k_best_matches = 3
    repetition_penalty = 0.3
    presetName$ = "Coherent"
elsif preset = 4
    number_of_segments = 8
    k_best_matches = 1
    repetition_penalty = 0.0
    presetName$ = "Minimal"
else
    presetName$ = "Custom"
endif

################################################################################
# DIRECTORY SELECTION
################################################################################

clearinfo

folder_path$ = chooseDirectory$: "Select folder containing sound files (first file = reference)"

if folder_path$ = ""
    exitScript: "No folder selected."
endif

if right$(folder_path$, 1) <> "/" and right$(folder_path$, 1) <> "\"
    folder_path$ = folder_path$ + "/"
endif

################################################################################
# HELPER PROCEDURES
################################################################################

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
    .nChannels = Get number of channels
    if .nChannels > 1
        .mono = Convert to mono
        removeObject: .soundID
        .soundID = .mono
    endif
    convertToMono.result = .soundID
endproc

procedure resampleIfNeeded: .soundID, .targetRate
    selectObject: .soundID
    .currentRate = Get sampling frequency
    if .currentRate <> .targetRate
        .resampled = Resample: .targetRate, 50
        removeObject: .soundID
        .soundID = .resampled
    endif
    resampleIfNeeded.result = .soundID
endproc

procedure extractFeatureVector: .soundID, .nSamples
    selectObject: .soundID
    .dur = Get total duration
    .start = Get start time
    .end = Get end time
    
    .pitch = To Pitch: 0.01, pitch_floor, pitch_ceiling
    
    selectObject: .soundID
    
    .intensityPitchFloor = 100
    .minDurForIntensity = 6.4 / .intensityPitchFloor
    
    if .dur < .minDurForIntensity
        .intensityPitchFloor = ceiling(6.4 / .dur) + 10
        if .intensityPitchFloor > 500
            .intensityPitchFloor = 500
        endif
    endif
    
    .intensity = To Intensity: .intensityPitchFloor, 0, "yes"
    
    .timeStep = .dur / (.nSamples - 1)
    if .timeStep <= 0
        .timeStep = .dur / 2
    endif
    
    for .i to .nSamples
        .time = .start + (.i - 1) * .timeStep
        if .time > .end
            .time = .end
        endif
        
        selectObject: .pitch
        .f0 = Get value at time: .time, "Hertz", "Linear"
        if .f0 = undefined
            .f0 = 0
        endif
        feature_vector_'.i' = .f0
        
        selectObject: .intensity
        .db = Get value at time: .time, "Cubic"
        if .db = undefined
            .db = 0
        endif
        .idx2 = .nSamples + .i
        feature_vector_'.idx2' = .db
    endfor
    
    removeObject: .pitch, .intensity
endproc

procedure normalizeFeatures: .vectorLength, .minPitch, .maxPitch, .minDB, .maxDB
    for .i to n_time_samples
        .val = feature_vector_'.i'
        if .maxPitch > .minPitch
            feature_vector_'.i' = (.val - .minPitch) / (.maxPitch - .minPitch)
        else
            feature_vector_'.i' = 0
        endif
    endfor
    
    for .i from n_time_samples + 1 to .vectorLength
        .val = feature_vector_'.i'
        if .maxDB > .minDB
            feature_vector_'.i' = (.val - .minDB) / (.maxDB - .minDB)
        else
            feature_vector_'.i' = 0
        endif
    endfor
endproc

procedure euclideanDistance: .vectorLength
    .distance = 0
    for .i to .vectorLength
        .fv = feature_vector_'.i'
        .dv = dict_vector_'.i'
        .diff = .fv - .dv
        .distance = .distance + .diff * .diff
    endfor
    euclideanDistance.distance = sqrt(.distance)
endproc

procedure findKBestMatches: .nPatterns, .k, .lastChoice
    for .i to .nPatterns
        candidate_dist_'.i' = 10000
        candidate_idx_'.i' = .i
    endfor
    
    for .dictIdx to .nPatterns
        for .j to vectorLength
            dict_vector_'.j' = dict_features_'.dictIdx'_'.j'
        endfor
        
        @euclideanDistance: vectorLength
        .dist = euclideanDistance.distance
        
        if .dictIdx = .lastChoice and repetition_penalty > 0
            .dist = .dist * (1 + repetition_penalty)
        endif
        
        candidate_dist_'.dictIdx' = .dist
    endfor
    
    for .i to .k
        .minIdx = .i
        .minDist = candidate_dist_'.i'
        
        for .j from .i + 1 to .nPatterns
            .testDist = candidate_dist_'.j'
            if .testDist < .minDist
                .minDist = .testDist
                .minIdx = .j
            endif
        endfor
        
        if .minIdx <> .i
            .tempDist = candidate_dist_'.i'
            .tempIdx = candidate_idx_'.i'
            candidate_dist_'.i' = candidate_dist_'.minIdx'
            candidate_idx_'.i' = candidate_idx_'.minIdx'
            candidate_dist_'.minIdx' = .tempDist
            candidate_idx_'.minIdx' = .tempIdx
        endif
    endfor
    
    if .k = 1
        findKBestMatches.selectedIndex = candidate_idx_1
        findKBestMatches.selectedDistance = candidate_dist_1
    else
        .randomChoice = randomInteger(1, .k)
        findKBestMatches.selectedIndex = candidate_idx_'.randomChoice'
        findKBestMatches.selectedDistance = candidate_dist_'.randomChoice'
    endif
endproc

################################################################################
# MAIN SCRIPT
################################################################################

if verbose_output
    appendInfoLine: "═══════════════════════════════════════════════════════"
    appendInfoLine: "  Gesture-Based Hard Quantization v1.0"
    appendInfoLine: "═══════════════════════════════════════════════════════"
    appendInfoLine: ""
    appendInfoLine: "Preset: ", presetName$
    appendInfoLine: "  • Segments: ", number_of_segments
    appendInfoLine: "  • K-best: ", k_best_matches
    appendInfoLine: "  • Repetition penalty: ", fixed$(repetition_penalty, 2)
    appendInfoLine: ""
endif

@log: "Reading folder: " + folder_path$
fileList = Create Strings as file list: "fileList", folder_path$ + "*.wav"
nFiles = Get number of strings

if nFiles < 2
    removeObject: fileList
    exitScript: "Error: Need at least 2 sound files (1 reference + 1 dictionary)"
endif

@log: "Found " + string$(nFiles) + " sound files"
@log: ""

vectorLength = 2 * n_time_samples
nDictSounds = nFiles - 1

for .i to nDictSounds
    for .j to vectorLength
        dict_features_'.i'_'.j' = 0
    endfor
endfor

################################################################################
# LOAD AND PREPROCESS ALL SOUNDS
################################################################################

@log: "Loading and preprocessing sounds..."
@log: ""

minPitch = 10000
maxPitch = 0
minDB = 10000
maxDB = -10000

for fileIdx to nFiles
    selectObject: fileList
    filename$ = Get string: fileIdx
    filepath$ = folder_path$ + filename$
    
    @log: "Loading: " + filename$
    
    sound = Read from file: filepath$
    
    @convertToMono: sound
    sound = convertToMono.result
    
    @resampleIfNeeded: sound, target_sample_rate
    sound = resampleIfNeeded.result
    
    @normalizeIntensity: sound
    
    soundID_'fileIdx' = sound
    
    selectObject: sound
    soundName_'fileIdx'$ = selected$("Sound")
    
    @log: "  Preprocessed: " + soundName_'fileIdx'$
endfor

@log: ""

################################################################################
# EXTRACT DICTIONARY FEATURES
################################################################################

@log: "Building gesture dictionary (" + string$(nDictSounds) + " gestures)..."
@log: ""

for dictIdx to nDictSounds
    soundIdx = dictIdx + 1
    sound = soundID_'soundIdx'
    
    @log: "  Dictionary " + string$(dictIdx) + ": " + soundName_'soundIdx'$
    
    @extractFeatureVector: sound, n_time_samples
    
    for j to vectorLength
        fv = feature_vector_'j'
        dict_features_'dictIdx'_'j' = fv
        
        if j <= n_time_samples
            if fv > 0
                if fv < minPitch
                    minPitch = fv
                endif
                if fv > maxPitch
                    maxPitch = fv
                endif
            endif
        else
            if fv < minDB
                minDB = fv
            endif
            if fv > maxDB
                maxDB = fv
            endif
        endif
    endfor
endfor

@log: ""
@log: "Normalization ranges:"
@log: "  Pitch: " + fixed$(minPitch, 1) + " - " + fixed$(maxPitch, 1) + " Hz"
@log: "  Intensity: " + fixed$(minDB, 1) + " - " + fixed$(maxDB, 1) + " dB"
@log: ""

@log: "Normalizing dictionary features..."
for dictIdx to nDictSounds
    for j to vectorLength
        feature_vector_'j' = dict_features_'dictIdx'_'j'
    endfor
    
    @normalizeFeatures: vectorLength, minPitch, maxPitch, minDB, maxDB
    
    for j to vectorLength
        dict_features_'dictIdx'_'j' = feature_vector_'j'
    endfor
endfor

@log: "Dictionary ready."
@log: ""

################################################################################
# SEGMENT REFERENCE SOUND
################################################################################

@log: "Processing reference sound: " + soundName_1$
@log: "Segmenting into " + string$(number_of_segments) + " equal parts..."
@log: ""

refSound = soundID_1
selectObject: refSound
refDur = Get total duration
refStart = Get start time
segmentDur = refDur / number_of_segments

@log: "Segment duration: " + fixed$(segmentDur, 3) + " seconds"
@log: ""

for segIdx to number_of_segments
    bestMatch_'segIdx' = 0
    bestDistance_'segIdx' = 10000
endfor

lastChoice = 0

################################################################################
# FIND CLOSEST MATCH FOR EACH SEGMENT
################################################################################

@log: "Finding closest dictionary matches..."
@log: ""

for segIdx to number_of_segments
    segStart = refStart + (segIdx - 1) * segmentDur
    segEnd = segStart + segmentDur
    
    selectObject: refSound
    segment = Extract part: segStart, segEnd, "rectangular", 1, "no"
    
    @extractFeatureVector: segment, n_time_samples
    @normalizeFeatures: vectorLength, minPitch, maxPitch, minDB, maxDB
    
    @findKBestMatches: nDictSounds, k_best_matches, lastChoice
    
    bestIdx = findKBestMatches.selectedIndex
    minDist = findKBestMatches.selectedDistance
    
    bestMatch_'segIdx' = bestIdx
    bestDistance_'segIdx' = minDist
    
    lastChoice = bestIdx
    
    matchSoundIdx = bestIdx + 1
    
    if k_best_matches > 1
        @log: "  Segment " + string$(segIdx) + " → " + soundName_'matchSoundIdx'$ + " (dist: " + fixed$(minDist, 4) + ")"
    else
        @log: "  Segment " + string$(segIdx) + " → " + soundName_'matchSoundIdx'$ + " (deterministic)"
    endif
    
    removeObject: segment
endfor

@log: ""

################################################################################
# CONSTRUCT OUTPUT SOUND
################################################################################

@log: "Building quantized output sound..."
@log: ""

for segIdx to number_of_segments
    dictIdx = bestMatch_'segIdx'
    soundIdx = dictIdx + 1
    sound = soundID_'soundIdx'
    
    selectObject: sound
    dictDur = Get total duration
    dictStart = Get start time
    
    if dictDur >= segmentDur
        extractedPart = Extract part: dictStart, dictStart + segmentDur, "rectangular", 1, "no"
    else
        extractedPart = Copy: "temp_segment"
    endif
    
    if segIdx = 1
        selectObject: extractedPart
        output = Copy: "quantized"
        removeObject: extractedPart
    else
        selectObject: output
        plusObject: extractedPart
        temp = Concatenate
        removeObject: output, extractedPart
        output = temp
    endif
endfor

selectObject: output
outputName$ = "gesture_quantized_" + presetName$ + "_" + soundName_1$
outputName$ = replace$(outputName$, " ", "_", 0)
Rename: outputName$

selectObject: output
outputDur = Get total duration

@log: "Output sound created: " + outputName$
@log: "Output duration: " + fixed$(outputDur, 3) + " seconds"
@log: ""

################################################################################
# STATISTICS
################################################################################

# Calculate statistics for visualization
sumDist = 0
statMinDist = bestDistance_1
statMaxDist = bestDistance_1

for segIdx to number_of_segments
    dist = bestDistance_'segIdx'
    sumDist = sumDist + dist
    if dist < statMinDist
        statMinDist = dist
    endif
    if dist > statMaxDist
        statMaxDist = dist
    endif
endfor
meanDist = sumDist / number_of_segments

sumSqDiff = 0
for segIdx to number_of_segments
    dist = bestDistance_'segIdx'
    diff = dist - meanDist
    sumSqDiff = sumSqDiff + diff * diff
endfor
stdDist = sqrt(sumSqDiff / number_of_segments)

# Count gesture usage
for dictIdx to nDictSounds
    gestureCount_'dictIdx' = 0
endfor

uniqueCount = 0
maxUsage = 0
for dictIdx to nDictSounds
    count = 0
    for segIdx to number_of_segments
        if bestMatch_'segIdx' = dictIdx
            count = count + 1
        endif
    endfor
    gestureCount_'dictIdx' = count
    if count > 0
        uniqueCount = uniqueCount + 1
    endif
    if count > maxUsage
        maxUsage = count
    endif
endfor

diversityPercent = (uniqueCount / nDictSounds) * 100

################################################################################
# VISUALIZATION
################################################################################

if draw_visualization
    @log: "Creating visualization..."
    
    Erase all
    Select outer viewport: 0, 8, 0, 8
    
    # === Title ===
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half", "##Gesture-Based Hard Quantization##"
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.2, "centre", -1., "half", presetName$ + " | k=" + string$(k_best_matches) + " | " + string$(nDictSounds) + " gestures"
    
    # === Reference Waveform ===
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.7, 0.7, 1.45
    selectObject: refSound
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Reference"
    Text top: "no", soundName_1$
    
    # === Output Waveform ===
    Select outer viewport: 0, 8, 1.5, 2.4
    Select inner viewport: 0.6, 7.7, 1.6, 2.35
    selectObject: output
    Colour: "{0.4, 0.6, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Axes: 0, 1, 0, 1
    Text: 0.5, "centre", -0.08, "top", "Time (s)"
        
    # === Segment Mapping Timeline ===
    Select outer viewport: 0, 8, 2.5, 3.8
    Select inner viewport: 0.6, 7.7, 2.7, 3.7
    
    Axes: 0, number_of_segments, 0, nDictSounds + 1
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, number_of_segments, 0, nDictSounds + 1
    
    # Draw mapping bars
    for segIdx to number_of_segments
        dictIdx = bestMatch_'segIdx'
        dist = bestDistance_'segIdx'
        
        # Color by distance (green=good, red=poor)
        distNorm = (dist - statMinDist) / (statMaxDist - statMinDist + 0.001)
        r = 0.4 + distNorm * 0.4
        g = 0.7 - distNorm * 0.3
        b = 0.4
        
        Paint rectangle: "{" + fixed$(r, 2) + ", " + fixed$(g, 2) + ", " + fixed$(b, 2) + "}", segIdx - 1, segIdx, dictIdx - 0.4, dictIdx + 0.4
    endfor
    
    # Draw grid lines
    Colour: "{0.85, 0.85, 0.85}"
    for dictIdx to nDictSounds
        Draw line: 0, dictIdx, number_of_segments, dictIdx
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Gesture #"
    Text bottom: "yes", "Segment"
    Text top: "no", "Segment → Gesture Mapping (green=close, orange=far)"
    
    # === Gesture Usage Histogram ===
    Select outer viewport: 0, 4, 3.9, 5.4
    Select inner viewport: 0.6, 3.7, 4.1, 5.3
    
    if maxUsage < 1
        maxUsage = 1
    endif
    
    Axes: 0, nDictSounds + 1, 0, maxUsage + 1
    Paint rectangle: "{0.98, 0.98, 0.97}", 0, nDictSounds + 1, 0, maxUsage + 1
    
    # Draw bars
    barW = 0.7
    for dictIdx to nDictSounds
        count = gestureCount_'dictIdx'
        if count > 0
            Paint rectangle: "{0.5, 0.65, 0.7}", dictIdx - barW/2, dictIdx + barW/2, 0, count
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Usage"
    Text bottom: "yes", "Gesture #"
    Text top: "no", "Gesture Usage (" + string$(uniqueCount) + "/" + string$(nDictSounds) + " used)"
    
    # === Distance Distribution ===
    Select outer viewport: 4, 8, 3.9, 5.4
    Select inner viewport: 4.4, 7.7, 4.1, 5.3
    
    Axes: 0, number_of_segments + 1, 0, statMaxDist * 1.15
    Paint rectangle: "{0.97, 0.98, 0.97}", 0, number_of_segments + 1, 0, statMaxDist * 1.15
    
    # Mean line
    Colour: "{0.8, 0.8, 0.8}"
    Dashed line
    Draw line: 0, meanDist, number_of_segments + 1, meanDist
    Solid line
    
    # Distance points
    Colour: "{0.5, 0.6, 0.7}"
    for segIdx to number_of_segments
        dist = bestDistance_'segIdx'
        Paint circle: "{0.5, 0.6, 0.7}", segIdx, dist, 0.2
    endfor
    
    # Connect points
    Line width: 1
    for segIdx from 2 to number_of_segments
        prevDist = bestDistance_'segIdx' - bestDistance_1
        prevDist = bestDistance_'segIdx' - 1
        
        # Get previous distance
        prevIdx = segIdx - 1
        d1 = bestDistance_'prevIdx'
        d2 = bestDistance_'segIdx'
        Draw line: prevIdx, d1, segIdx, d2
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Distance"
    Text bottom: "yes", "Segment"
    Text top: "no", "Match Distance (mean=" + fixed$(meanDist, 3) + ")"
    
    # === Summary Panel ===
    Select outer viewport: 0, 8, 5.5, 6.4
    Axes: 0, 1, 0, 1
    
    Paint rectangle: "{0.95, 0.97, 0.95}", 0, 1, 0, 1
    
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.8, "half", "##Statistics##"
    
    Font size: 6
    Colour: "{0.3, 0.3, 0.4}"
    
    Text: 0.12, "centre", 0.45, "half", "Segments: " + string$(number_of_segments)
    Text: 0.32, "centre", 0.45, "half", "Seg dur: " + fixed$(segmentDur * 1000, 0) + "ms"
    Text: 0.52, "centre", 0.45, "half", "K-best: " + string$(k_best_matches)
    Text: 0.72, "centre", 0.45, "half", "Penalty: " + fixed$(repetition_penalty, 2)
    Text: 0.92, "centre", 0.45, "half", "Diversity: " + fixed$(diversityPercent, 0) + "%"
    
    Text: 0.20, "centre", 0.15, "half", "Dist mean: " + fixed$(meanDist, 3)
    Text: 0.45, "centre", 0.15, "half", "Dist std: " + fixed$(stdDist, 3)
    Text: 0.70, "centre", 0.15, "half", "Range: " + fixed$(statMinDist, 3) + "-" + fixed$(statMaxDist, 3)
    
    Font size: 10
    Colour: "Black"
endif

################################################################################
# VERBOSE STATISTICS
################################################################################

if verbose_output
    appendInfoLine: "════════════════════════════════════════════════════════"
    appendInfoLine: "  SUMMARY STATISTICS"
    appendInfoLine: "════════════════════════════════════════════════════════"
    appendInfoLine: ""
    appendInfoLine: "Preset: ", presetName$
    appendInfoLine: "Reference sound: ", soundName_1$
    appendInfoLine: "Dictionary size: ", nDictSounds, " gestures"
    appendInfoLine: ""
    appendInfoLine: "Parameters:"
    appendInfoLine: "  • Segments: ", number_of_segments
    appendInfoLine: "  • Segment duration: ", fixed$(segmentDur, 3), " s"
    appendInfoLine: "  • K-best matches: ", k_best_matches
    appendInfoLine: "  • Repetition penalty: ", fixed$(repetition_penalty, 2)
    appendInfoLine: ""
    appendInfoLine: "Distance Statistics:"
    appendInfoLine: "  Mean: ", fixed$(meanDist, 4)
    appendInfoLine: "  Std:  ", fixed$(stdDist, 4)
    appendInfoLine: "  Min:  ", fixed$(statMinDist, 4)
    appendInfoLine: "  Max:  ", fixed$(statMaxDist, 4)
    appendInfoLine: ""
    
    appendInfoLine: "Gesture Usage:"
    for dictIdx to nDictSounds
        count = gestureCount_'dictIdx'
        if count > 0
            soundIdx = dictIdx + 1
            appendInfoLine: "  ", soundName_'soundIdx'$, ": ", count, "x"
        endif
    endfor
    
    appendInfoLine: ""
    appendInfoLine: "Diversity: ", uniqueCount, "/", nDictSounds, " gestures (", fixed$(diversityPercent, 1), "%)"
    appendInfoLine: ""
    appendInfoLine: "════════════════════════════════════════════════════════"
endif

################################################################################
# CLEANUP
################################################################################

@log: "Cleaning up..."

for i to nFiles
    removeObject: soundID_'i'
endfor

removeObject: fileList

@log: "Done."
@log: ""

################################################################################
# SELECT OUTPUT AND PLAY
################################################################################

selectObject: output

appendInfoLine: "Output: ", outputName$

if play_result
    appendInfoLine: "Playing..."
    Play
endif