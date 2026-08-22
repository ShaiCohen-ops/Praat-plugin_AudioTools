# ============================================================
# Praat AudioTools - Auto-Harmonic_Layering.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.9.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Auto-Harmonic Layering with pitch-aware chord selection.
#   Detects recurring pitched regions with a pitch self-similarity
#   matrix (SSM), chooses harmony intervals from the region's
#   average pitch and preset, and mixes pitch-shifted harmony
#   voices back into the original with stereo spread and smooth
#   trapezoidal fades. Diatonic presets estimate a global major
#   or minor key from pitch-class statistics. Experimental mode
#   chooses a chord type independently for each detected region.
#
# Notes:
#   - Input may be mono or stereo; harmony analysis/resynthesis is mono.
#   - Dry_level and Wet_level are linear gains. The result is NOT peak
#     normalized, so their numerical meaning is preserved.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v1.9.4: removed duplicate generic Summary strip and tightened Picture page spacing; DSP/analysis unchanged.
# Changelog v1.9.3: visualization standardization only - unified typography, summary/full-page Picture framing; DSP/analysis unchanged.
# Changelog v1.9.3:
#   - FIXED runtime error in Table cell reads. `Get value:` is not
#     a valid Table query command, so Praat parsed `Get` as a formula
#     symbol. Reads now use documented direct Table access:
#       object [tableID, rowIndex, "start_frame"]
#       object [tableID, rowIndex, "length_frames"]
#
# Changelog v1.9.1:
#   - FIXED runtime error: object[pitchID].x1 is not a supported
#     object[] formula attribute. Uses the Pitch query commands
#     Get time from frame: 1 and Get time step instead.
#   - Replaced object[wetL].nx with Get number of samples for
#     query-command consistency.
#
# Changelog v1.9:
#   - FIXED SSM candidate scoring: score is accumulated from matching
#     cells, not from the first non-matching cell that ends a run.
#   - FIXED end-of-diagonal runs: valid runs that reach the last SSM
#     cell are now stored instead of silently discarded.
#   - SSM tolerance is now expressed in semitones, so similarity has
#     consistent musical meaning across low and high registers.
#   - FIXED Experimental preset: it now actually chooses a random chord
#     type independently for each detected region.
#   - Diatonic presets now estimate major/minor key from a chroma
#     histogram and keep both generated harmony voices in that scale.
#   - FIXED voice leading: octave placement now minimizes motion between
#     successive harmony voices while preserving chord pitch classes.
#   - FIXED temporal voice-leading order: selected regions are sorted by
#     start time before harmony generation.
#   - FIXED pitch shifting: uses Manipulation -> PitchTier scaling ->
#     overlap-add directly; removed sampling-rate/duration-tier workaround.
#   - FIXED stereoSpread: 0 = centered voices, 1 = hard opposite sides,
#     with constant-power panning in between.
#   - FIXED harmony mixing: removed Combine-to-stereo/Convert-to-mono
#     averaging that unintentionally weighted chord tones unequally.
#   - Removed per-note Scale peak and final Scale peak normalization,
#     which previously destroyed source dynamics and Dry/Wet semantics.
#   - Stereo sources are downmixed only for pitch analysis/harmony
#     synthesis; the original stereo channels remain the dry signal.
#   - Removed a visualization comment that claimed a waveform underlay
#     was drawn in the loop map when no Draw command actually existed.
# ============================================================

form Auto-Harmonic Layering v1.9.4
    optionmenu Preset: 1
        option Subtle (Conservative harmonies)
        option Rich (Full chords, smooth)
        option Bold (Wider intervals)
        option Diatonic (Automatic key)
        option Experimental (Random per loop)
        option Custom (Neutral analysis defaults)
    natural Num_loops_to_find 5
    positive Min_loop_duration 0.4
    optionmenu Harmony_style: 1
        option Pitch-Aware (Analyzes melody)
        option Fixed Chord Type
    optionmenu Fixed_chord_if_used: 3
        option Octaves
        option Fifths
        option Major
        option Minor
        option Sus4
    real Dry_level 0.75
    real Wet_level 0.45
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ===================================================================
# PRESET CONFIGURATION
# ===================================================================

if preset = 1
    presetName$ = "Subtle"
    pitchFloor = 75
    pitchCeiling = 600
    toleranceST = 0.45
    stereoSpread = 0.35
    fadeMs = 35
    useDiatonic = 0
    voiceLeading = 1
elsif preset = 2
    presetName$ = "Rich"
    pitchFloor = 75
    pitchCeiling = 600
    toleranceST = 0.75
    stereoSpread = 0.70
    fadeMs = 50
    useDiatonic = 1
    voiceLeading = 1
elsif preset = 3
    presetName$ = "Bold"
    pitchFloor = 60
    pitchCeiling = 700
    toleranceST = 1.00
    stereoSpread = 0.90
    fadeMs = 20
    useDiatonic = 0
    voiceLeading = 0
elsif preset = 4
    presetName$ = "Diatonic"
    pitchFloor = 75
    pitchCeiling = 600
    toleranceST = 0.60
    stereoSpread = 0.60
    fadeMs = 60
    useDiatonic = 1
    voiceLeading = 1
elsif preset = 5
    presetName$ = "Experimental"
    pitchFloor = 50
    pitchCeiling = 800
    toleranceST = 1.25
    stereoSpread = 0.80
    fadeMs = 15
    useDiatonic = 0
    voiceLeading = 0
else
    presetName$ = "Custom"
    pitchFloor = 75
    pitchCeiling = 600
    toleranceST = 0.75
    stereoSpread = 0.70
    fadeMs = 30
    useDiatonic = 0
    voiceLeading = 1
endif

fadeDuration = fadeMs / 1000

# ===================================================================
# PHASE 1: FIND RECURRING PITCHED REGIONS
# ===================================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

selectObject: originalID
totalDuration = Get total duration
originalSR = Get sampling frequency
numChannels = Get number of channels
rms_orig = Get root-mean-square: 0, 0

if numChannels < 1 or numChannels > 2
    exitScript: "Auto-Harmonic Layering v1.9.4 supports mono or stereo Sound objects."
endif

# Use a mono analysis/harmony source. Preserve the original channels for dry mix.
selectObject: originalID
if numChannels = 1
    analysisID = Copy: "AHL_analysisMono"
else
    analysisID = Convert to mono
    Rename: "AHL_analysisMono"
endif

writeInfoLine: "=== AUTO-HARMONIC LAYERING v1.9.4 ==="
appendInfoLine: ""
appendInfoLine: "Source: ", originalName$, " (", fixed$(totalDuration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "--- Phase 1: Analyzing Pitch & Recurrence ---"

# 1. Extract pitch from mono analysis signal.
selectObject: analysisID
timeStep = 0.05
To Pitch: timeStep, pitchFloor, pitchCeiling
pitchID = selected("Pitch")
numFrames = Get number of frames
pitchX1 = Get time from frame: 1
pitchDx = Get time step

if numFrames < 2
    removeObject: pitchID, analysisID
    exitScript: "Sound is too short for recurrence analysis."
endif

pitchVals# = zero#(numFrames)
voicedFrames = 0
for i to numFrames
    val = Get value in frame: i, "Hertz"
    if val = undefined
        val = 0
    else
        voicedFrames += 1
    endif
    pitchVals#[i] = val
endfor

if voicedFrames = 0
    removeObject: pitchID, analysisID
    exitScript: "No voiced pitch was detected in the selected pitch range."
endif

# 2. Store pitch values in a Matrix for formula-based SSM construction.
Create simple Matrix: "AHL_PitchData", numFrames, 1, "0"
dataID = selected("Matrix")
for i to numFrames
    Set value: i, 1, pitchVals#[i]
endfor

# 3. Build pitch SSM. Similarity falls linearly from 1 to 0 across
# toleranceST semitones. Unvoiced pairs are 0.
appendInfoLine: "Building pitch self-similarity matrix..."
Create simple Matrix: "AHL_SSM", numFrames, numFrames, "0"
ssmID = selected("Matrix")

Formula: "if Matrix_AHL_PitchData[row, 1] > 0 and Matrix_AHL_PitchData[col, 1] > 0 then if abs(12*log2(Matrix_AHL_PitchData[row, 1] / Matrix_AHL_PitchData[col, 1])) < " + string$(toleranceST) + " then 1 - abs(12*log2(Matrix_AHL_PitchData[row, 1] / Matrix_AHL_PitchData[col, 1])) / " + string$(toleranceST) + " else 0 fi else 0 fi"

# 4. Find diagonal runs away from the main diagonal. A run means that
# two regions separated by 'gap' have similar frame-by-frame pitch.
Create Table with column names: "AHL_candidates", 0, "start_frame length_frames gap_frames score"
tableID = selected("Table")

frameRate = 1 / pitchDx
minLen = max(1, ceiling(min_loop_duration * frameRate))
maxGap = numFrames - minLen
gap = minLen
step = 1
if numFrames > 2000
    step = 2
endif

appendInfoLine: "Searching for recurring regions..."

selectObject: ssmID
while gap <= maxGap
    pathLen = 0
    pathStart = 0
    pathScore = 0
    searchLimit = numFrames - gap

    for i to searchLimit
        j = i + gap
        val = Get value in cell: i, j

        if val > 0
            if pathLen = 0
                pathStart = i
                pathScore = 0
            endif
            pathLen += 1
            pathScore += val
        else
            if pathLen >= minLen
                selectObject: tableID
                Append row
                rowN = Get number of rows
                Set numeric value: rowN, "start_frame", pathStart
                Set numeric value: rowN, "length_frames", pathLen
                Set numeric value: rowN, "gap_frames", gap
                Set numeric value: rowN, "score", pathScore
                selectObject: ssmID
            endif
            pathLen = 0
            pathStart = 0
            pathScore = 0
        endif
    endfor

    # Flush a valid run that reaches the end of this diagonal.
    if pathLen >= minLen
        selectObject: tableID
        Append row
        rowN = Get number of rows
        Set numeric value: rowN, "start_frame", pathStart
        Set numeric value: rowN, "length_frames", pathLen
        Set numeric value: rowN, "gap_frames", gap
        Set numeric value: rowN, "score", pathScore
        selectObject: ssmID
    endif

    gap += step
endwhile

# 5. Select strongest non-overlapping regions.
selectObject: tableID
nRows = Get number of rows
if nRows = 0
    removeObject: dataID, ssmID, tableID, pitchID, analysisID
    exitScript: "No recurring pitched regions found. Try a shorter minimum duration or another preset."
endif

Sort rows: "score"

maxLoops = num_loops_to_find
loopStart# = zero#(maxLoops)
loopEnd# = zero#(maxLoops)
loopPitch# = zero#(maxLoops)
loopMidi# = zero#(maxLoops)

loopsFound = 0
rowIndex = nRows
while loopsFound < num_loops_to_find and rowIndex > 0
    selectObject: tableID
    startF = round(object [tableID, rowIndex, "start_frame"])
    lenF = round(object [tableID, rowIndex, "length_frames"])

    t1 = max(0, pitchX1 + (startF - 1) * pitchDx - 0.5 * pitchDx)
    lastF = min(numFrames, startF + lenF - 1)
    t2 = min(totalDuration, pitchX1 + (lastF - 1) * pitchDx + 0.5 * pitchDx)
    dur = t2 - t1

    isOverlap = 0
    for k to loopsFound
        if t1 < loopEnd#[k] and t2 > loopStart#[k]
            isOverlap = 1
        endif
    endfor

    if isOverlap = 0 and t2 > t1
        sumMidi = 0
        countPitch = 0
        endF = min(numFrames, startF + lenF - 1)
        for fr from startF to endF
            if pitchVals#[fr] > 0
                sumMidi += 69 + 12 * log2(pitchVals#[fr] / 440)
                countPitch += 1
            endif
        endfor

        if countPitch > 0
            loopsFound += 1
            loopStart#[loopsFound] = t1
            loopEnd#[loopsFound] = t2
            loopMidi#[loopsFound] = sumMidi / countPitch
            loopPitch#[loopsFound] = 440 * 2 ^ ((loopMidi#[loopsFound] - 69) / 12)
        endif
    endif
    rowIndex -= 1
endwhile

if loopsFound = 0
    removeObject: dataID, ssmID, tableID, pitchID, analysisID
    exitScript: "Recurring regions were found, but none contained usable voiced pitch."
endif

# Sort selected regions chronologically. This matters for voice leading.
if loopsFound > 1
    for a to loopsFound - 1
        for b from a + 1 to loopsFound
            if loopStart#[b] < loopStart#[a]
                temp = loopStart#[a]
                loopStart#[a] = loopStart#[b]
                loopStart#[b] = temp

                temp = loopEnd#[a]
                loopEnd#[a] = loopEnd#[b]
                loopEnd#[b] = temp

                temp = loopPitch#[a]
                loopPitch#[a] = loopPitch#[b]
                loopPitch#[b] = temp

                temp = loopMidi#[a]
                loopMidi#[a] = loopMidi#[b]
                loopMidi#[b] = temp
            endif
        endfor
    endfor
endif

appendInfoLine: "Found ", loopsFound, " non-overlapping recurring regions"
removeObject: dataID, ssmID, tableID

# ===================================================================
# PHASE 2: KEY ESTIMATION + CHORD SELECTION
# ===================================================================

appendInfoLine: ""
appendInfoLine: "--- Phase 2: Selecting Harmony ---"

keyName$ = "n/a"
keyMode$ = "n/a"
keyTonic = 0
keyMode = 1
scaleMask# = zero#(12)

# Lightweight Krumhansl-Schmuckler-style profile matching. We use
# pitch-class counts from all voiced frames and choose the best of
# 12 major + 12 minor rotations.
if harmony_style = 1 and useDiatonic = 1
    chromaCounts# = zero#(12)
    for i to numFrames
        if pitchVals#[i] > 0
            midiFrame = round(69 + 12 * log2(pitchVals#[i] / 440))
            pc = midiFrame mod 12
            chromaCounts#[pc + 1] += 1
        endif
    endfor

    majorProfile# = { 6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88 }
    minorProfile# = { 6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17 }

    bestScore = -1e30
    for tonic from 0 to 11
        scoreMaj = 0
        scoreMin = 0
        for pc from 0 to 11
            rel = pc - tonic
            if rel < 0
                rel += 12
            endif
            scoreMaj += chromaCounts#[pc + 1] * majorProfile#[rel + 1]
            scoreMin += chromaCounts#[pc + 1] * minorProfile#[rel + 1]
        endfor
        if scoreMaj > bestScore
            bestScore = scoreMaj
            keyTonic = tonic
            keyMode = 1
        endif
        if scoreMin > bestScore
            bestScore = scoreMin
            keyTonic = tonic
            keyMode = 2
        endif
    endfor

    if keyTonic = 0
        keyName$ = "C"
    elsif keyTonic = 1
        keyName$ = "C#"
    elsif keyTonic = 2
        keyName$ = "D"
    elsif keyTonic = 3
        keyName$ = "D#"
    elsif keyTonic = 4
        keyName$ = "E"
    elsif keyTonic = 5
        keyName$ = "F"
    elsif keyTonic = 6
        keyName$ = "F#"
    elsif keyTonic = 7
        keyName$ = "G"
    elsif keyTonic = 8
        keyName$ = "G#"
    elsif keyTonic = 9
        keyName$ = "A"
    elsif keyTonic = 10
        keyName$ = "A#"
    else
        keyName$ = "B"
    endif

    if keyMode = 1
        keyMode$ = "major"
    else
        keyMode$ = "minor"
    endif

    for pc from 0 to 11
        rel = pc - keyTonic
        if rel < 0
            rel += 12
        endif
        if keyMode = 1
            if rel = 0 or rel = 2 or rel = 4 or rel = 5 or rel = 7 or rel = 9 or rel = 11
                scaleMask#[pc + 1] = 1
            endif
        else
            if rel = 0 or rel = 2 or rel = 3 or rel = 5 or rel = 7 or rel = 8 or rel = 10
                scaleMask#[pc + 1] = 1
            endif
        endif
    endfor

    appendInfoLine: "Estimated key: ", keyName$, " ", keyMode$
endif

interval2# = zero#(loopsFound)
interval3# = zero#(loopsFound)
chordName$# = empty$#(loopsFound)

for i to loopsFound
    avgPitch = loopPitch#[i]
    midiNote = round(loopMidi#[i])
    chromaClass = midiNote mod 12

    if harmony_style = 2
        if fixed_chord_if_used = 1
            interval2#[i] = 12
            interval3#[i] = 24
            chordName$#[i] = "Oct"
        elsif fixed_chord_if_used = 2
            interval2#[i] = 7
            interval3#[i] = 12
            chordName$#[i] = "5th"
        elsif fixed_chord_if_used = 3
            interval2#[i] = 4
            interval3#[i] = 7
            chordName$#[i] = "Maj"
        elsif fixed_chord_if_used = 4
            interval2#[i] = 3
            interval3#[i] = 7
            chordName$#[i] = "Min"
        else
            interval2#[i] = 5
            interval3#[i] = 7
            chordName$#[i] = "Sus4"
        endif

    elsif preset = 5
        # Experimental really is random per detected region.
        randomChord = randomInteger(1, 6)
        if randomChord = 1
            interval2#[i] = 12
            interval3#[i] = 24
            chordName$#[i] = "Oct"
        elsif randomChord = 2
            interval2#[i] = 7
            interval3#[i] = 12
            chordName$#[i] = "5th"
        elsif randomChord = 3
            interval2#[i] = 4
            interval3#[i] = 7
            chordName$#[i] = "Maj"
        elsif randomChord = 4
            interval2#[i] = 3
            interval3#[i] = 7
            chordName$#[i] = "Min"
        elsif randomChord = 5
            interval2#[i] = 5
            interval3#[i] = 7
            chordName$#[i] = "Sus4"
        else
            interval2#[i] = 3
            interval3#[i] = 6
            chordName$#[i] = "Dim"
        endif

    elsif useDiatonic = 1
        # Choose scale tones nearest a third and a fifth above the
        # melody pitch. Both generated voices are therefore in the
        # estimated scale, even when the melody note itself is chromatic.
        bestDist2 = 1e30
        bestDist3 = 1e30
        bestInt2 = 4
        bestInt3 = 7
        for candidateInt from 1 to 11
            targetPc = (chromaClass + candidateInt) mod 12
            if scaleMask#[targetPc + 1] = 1
                dist2 = abs(candidateInt - 4)
                if dist2 < bestDist2
                    bestDist2 = dist2
                    bestInt2 = candidateInt
                endif
                dist3 = abs(candidateInt - 7)
                if dist3 < bestDist3
                    bestDist3 = dist3
                    bestInt3 = candidateInt
                endif
            endif
        endfor
        if bestInt3 = bestInt2
            # Pick another in-key tone nearest a fifth if a tie occurred.
            bestDist3 = 1e30
            for candidateInt from 1 to 11
                targetPc = (chromaClass + candidateInt) mod 12
                if scaleMask#[targetPc + 1] = 1 and candidateInt <> bestInt2
                    dist3 = abs(candidateInt - 7)
                    if dist3 < bestDist3
                        bestDist3 = dist3
                        bestInt3 = candidateInt
                    endif
                endif
            endfor
        endif
        interval2#[i] = bestInt2
        interval3#[i] = bestInt3

        if bestInt2 = 4 and bestInt3 = 7
            chordName$#[i] = "Maj"
        elsif bestInt2 = 3 and bestInt3 = 7
            chordName$#[i] = "Min"
        elsif bestInt2 = 3 and bestInt3 = 6
            chordName$#[i] = "Dim"
        elsif bestInt2 = 5 and bestInt3 = 7
            chordName$#[i] = "Sus4"
        else
            chordName$#[i] = "Key"
        endif

    elsif preset = 3
        # Bold preset uses genuinely wider/open intervals.
        if avgPitch < 180
            interval2#[i] = 7
            interval3#[i] = 19
            chordName$#[i] = "Open5"
        elsif avgPitch < 320
            interval2#[i] = 5
            interval3#[i] = 12
            chordName$#[i] = "Open4"
        else
            interval2#[i] = 12
            interval3#[i] = 19
            chordName$#[i] = "Oct5"
        endif

    else
        # General pitch-aware mapping for Subtle / Custom.
        if avgPitch < 150
            interval2#[i] = 7
            interval3#[i] = 12
            chordName$#[i] = "5th"
        elsif avgPitch < 250
            interval2#[i] = 3
            interval3#[i] = 7
            chordName$#[i] = "Min"
        elsif avgPitch < 350
            interval2#[i] = 4
            interval3#[i] = 7
            chordName$#[i] = "Maj"
        else
            interval2#[i] = 12
            interval3#[i] = 19
            chordName$#[i] = "Oct5"
        endif
    endif
endfor

# True pitch-class-preserving voice leading. Only octave placement is
# changed; chord quality/pitch classes stay intact.
renderInt2# = zero#(loopsFound)
renderInt3# = zero#(loopsFound)
prevVoice2 = undefined
prevVoice3 = undefined

for i to loopsFound
    base2 = interval2#[i]
    base3 = interval3#[i]
    renderInt2#[i] = base2
    renderInt3#[i] = base3

    if voiceLeading = 1 and i > 1
        bestCost = 1e30
        best2 = base2
        best3 = base3
        for oct2 from -1 to 1
            cand2 = base2 + 12 * oct2
            for oct3 from -1 to 1
                cand3 = base3 + 12 * oct3
                v2 = loopMidi#[i] + cand2
                v3 = loopMidi#[i] + cand3
                if cand2 <> 0 and cand3 <> 0 and cand2 <> cand3 and v2 < v3
                    cost = abs(v2 - prevVoice2) + abs(v3 - prevVoice3)
                    if cost < bestCost
                        bestCost = cost
                        best2 = cand2
                        best3 = cand3
                    endif
                endif
            endfor
        endfor
        renderInt2#[i] = best2
        renderInt3#[i] = best3
    endif

    prevVoice2 = loopMidi#[i] + renderInt2#[i]
    prevVoice3 = loopMidi#[i] + renderInt3#[i]

    appendInfoLine: "  Region ", i, ": ", fixed$(loopPitch#[i], 1), " Hz -> ", chordName$#[i], " (", renderInt2#[i], ", ", renderInt3#[i], " st)"
endfor

# ===================================================================
# PHASE 3: GENERATE + MIX HARMONY VOICES
# ===================================================================

appendInfoLine: ""
appendInfoLine: "--- Phase 3: Generating Harmonies ---"

# Full-duration mono wet buffers.
selectObject: originalID
wetL = Create Sound from formula: "AHL_wetL", 1, 0, totalDuration, originalSR, "0"
wetR = Create Sound from formula: "AHL_wetR", 1, 0, totalDuration, originalSR, "0"
selectObject: wetL
wetSamples = Get number of samples

nEvents = 0
for i to loopsFound
    t1 = loopStart#[i]
    t2 = loopEnd#[i]

    # Harmonies are synthesized from the mono analysis source. The dry
    # signal later retains the original mono/stereo channels.
    selectObject: analysisID
    loopSegment = Extract part: t1, t2, "rectangular", 1.0, "no"

    int2 = renderInt2#[i]
    int3 = renderInt3#[i]

    @generateSmoothChord: loopSegment, int2, int3, stereoSpread, pitchFloor, pitchCeiling
    harmL = generateSmoothChord.leftOut
    harmR = generateSmoothChord.rightOut

    selectObject: harmL
    durH = Get total duration
    nH = Get number of samples
    safeFade = min(fadeDuration, durH / 2)

    if safeFade > 0
        fadeStr$ = fixed$(safeFade, 9)
        durStr$ = fixed$(durH, 9)
        selectObject: harmL
        Formula: "self * (if x < " + fadeStr$ + " then x/" + fadeStr$ + " else if x > " + durStr$ + " - " + fadeStr$ + " then (" + durStr$ + " - x)/" + fadeStr$ + " else 1 fi fi)"
        selectObject: harmR
        Formula: "self * (if x < " + fadeStr$ + " then x/" + fadeStr$ + " else if x > " + durStr$ + " - " + fadeStr$ + " then (" + durStr$ + " - x)/" + fadeStr$ + " else 1 fi fi)"
    endif

    # Add by exact sample index into full-duration buffers. Out-of-range
    # tails are clipped at the destination end rather than indexing past it.
    startSample = round(t1 * originalSR) + 1
    endSample = min(wetSamples, startSample + nH - 1)

    if startSample <= wetSamples and endSample >= startSample
        selectObject: wetL
        Formula: "if col >= " + string$(startSample) + " and col <= " + string$(endSample) + " then self + object[" + string$(harmL) + ", 1, col - " + string$(startSample) + " + 1] else self fi"
        selectObject: wetR
        Formula: "if col >= " + string$(startSample) + " and col <= " + string$(endSample) + " then self + object[" + string$(harmR) + ", 1, col - " + string$(startSample) + " + 1] else self fi"
        nEvents += 1
    endif

    removeObject: loopSegment, harmL, harmR
    appendInfoLine: "  Mixed region ", i, " at ", fixed$(t1, 2), " s"
endfor

# Apply user wet gain once, after all harmony events are summed.
selectObject: wetL
Formula: "self * " + string$(wet_level)
selectObject: wetR
Formula: "self * " + string$(wet_level)

# Create dry output channels while preserving original stereo content.
if numChannels = 1
    selectObject: originalID
    dryL = Copy: "AHL_dryL"
    selectObject: originalID
    dryR = Copy: "AHL_dryR"
else
    selectObject: originalID
    dryL = Extract one channel: 1
    Rename: "AHL_dryL"
    selectObject: originalID
    dryR = Extract one channel: 2
    Rename: "AHL_dryR"
endif

selectObject: dryL
Formula: "self * " + string$(dry_level)
selectObject: dryR
Formula: "self * " + string$(dry_level)

# Dry + wet. Use explicit row/column access so the operation is unambiguous.
selectObject: dryL
Formula: "self + object[" + string$(wetL) + ", 1, col]"
selectObject: dryR
Formula: "self + object[" + string$(wetR) + ", 1, col]"

selectObject: dryL, dryR
Combine to stereo
finalID = selected("Sound")
compositeName$ = originalName$ + "_harmonized_" + presetName$
Rename: compositeName$

# Do not normalize: Dry_level and Wet_level remain real linear gains.
selectObject: finalID
rms_out = Get root-mean-square: 0, 0
durOut = Get total duration

removeObject: pitchID, analysisID, wetL, wetR, dryL, dryR

###############################################################################
# VISUALIZATION  (8 x 8 canvas, suite styling)
# Title bar (suite light) + metadata subtitle
# Panel A: Original waveform   (left half, headline)
# Panel B: Result waveform     (right half, headline)
# Panel C: Loop map with chord labels  (full width, signature)
# Panel D: Light-grey 3-line summary
###############################################################################

if draw_visualization
    Erase all
    Select outer viewport: 0, 8, 0, 8
    Black
    Plain line

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##AUTO-HARMONIC LAYERING v1.9.4##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    if harmony_style = 1
        harmStyleStr$ = "Pitch-Aware"
    else
        harmStyleStr$ = "Fixed Chord"
    endif
    Text: 0.5, "centre", -0.22, "half",
        ... originalName$
        ... + "  |  " + presetName$
        ... + "  |  " + string$(loopsFound) + " loops"
        ... + "  |  " + harmStyleStr$
        ... + "  |  Voice leading: " + string$(voiceLeading)

    # ----------------------------------------------------------
    # PANEL A (left): ORIGINAL WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 2.30
    Select inner viewport: 0.55, 4.00, 0.95, 2.18

    selectObject: originalID
    Colour: "{0.55, 0.55, 0.60}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Original waveform"
    Font size: 6
    Text left: "yes", "Amp"

    # ----------------------------------------------------------
    # PANEL B (right): RESULT WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 2.30
    Select inner viewport: 4.55, 7.75, 0.95, 2.18

    selectObject: finalID
    Colour: "{0.30, 0.55, 0.70}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Harmonized waveform"
    Font size: 6
    Text left: "yes", "Amp"

    # ----------------------------------------------------------
    # PANEL C: LOOP MAP WITH CHORD LABELS  (full width, signature)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 2.40, 5.40
    Select inner viewport: 0.55, 7.72, 2.60, 5.30

    Axes: 0, totalDuration, 0, 2
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, totalDuration, 0, 2

    # Draw loop rectangles and labels in time coordinates.
    Axes: 0, totalDuration, 0, 2

    for i to loopsFound
        # Loop region rectangle (mid-band of the panel)
        Paint rectangle: "{0.60, 0.78, 0.92}", loopStart#[i], loopEnd#[i], 0.50, 1.55

        # Loop boundary lines (subtle)
        Colour: "{0.30, 0.55, 0.75}"
        Line width: 1
        Draw line: loopStart#[i], 0.50, loopStart#[i], 1.55
        Draw line: loopEnd#[i], 0.50, loopEnd#[i], 1.55

        # Chord label (large, centered)
        midT = (loopStart#[i] + loopEnd#[i]) / 2
        Colour: "Black"
        Font size: 7
        Text: midT, "centre", 1.20, "half", chordName$#[i]

        # Pitch label (smaller, below chord)
        Font size: 6
        Colour: "{0.30, 0.30, 0.35}"
        Text: midT, "centre", 0.85, "half", fixed$(loopPitch#[i], 0) + " Hz"

        # Loop index label (small, top)
        Font size: 6
        Colour: "{0.50, 0.50, 0.55}"
        Text: midT, "centre", 1.75, "half", "loop " + string$(i)
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Loop map with chord labels  (color = harmonized region)"
    Font size: 6
    Text left: "yes", "Loops"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL D: SUMMARY BAR  (suite standard light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.50, 6.20
    Select inner viewport: 0.55, 7.72, 5.57, 6.15
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"

    if harmony_style = 1
        if preset = 5
            harmDetail$ = "Experimental random per region"
        elsif useDiatonic = 1
            harmDetail$ = "Pitch-Aware diatonic (" + keyName$ + " " + keyMode$ + ")"
        else
            harmDetail$ = "Pitch-Aware non-diatonic"
        endif
    else
        if fixed_chord_if_used = 1
            harmDetail$ = "Fixed Octaves"
        elsif fixed_chord_if_used = 2
            harmDetail$ = "Fixed 5ths"
        elsif fixed_chord_if_used = 3
            harmDetail$ = "Fixed Major"
        elsif fixed_chord_if_used = 4
            harmDetail$ = "Fixed Minor"
        else
            harmDetail$ = "Fixed Sus4"
        endif
    endif

    Text: 0.02, "left", 0.82, "half",
        ... "##" + presetName$ + "##"
        ... + "  Loops: " + string$(loopsFound) + " of " + string$(num_loops_to_find) + " requested"
        ... + "  |  Harmonized events: " + string$(nEvents)
        ... + "  |  " + harmDetail$
        ... + "  |  Voice leading: " + string$(voiceLeading)

    Text: 0.02, "left", 0.50, "half",
        ... "Dry: " + fixed$(dry_level, 2)
        ... + "  |  Wet: " + fixed$(wet_level, 2)
        ... + "  |  Spread: " + fixed$(stereoSpread, 2)
        ... + "  |  Fade: " + string$(fadeMs) + " ms"
        ... + "  |  Pitch range: " + fixed$(pitchFloor, 0) + "-" + fixed$(pitchCeiling, 0) + " st"
        ... + "  |  Tolerance: " + fixed$(toleranceST, 2) + " st"

    Text: 0.02, "left", 0.18, "half",
        ... "Output: " + compositeName$
        ... + "  |  Duration: " + fixed$(durOut, 2) + " s"
        ... + "  |  RMS orig: " + fixed$(rms_orig, 4)
        ... + "  |  RMS out: " + fixed$(rms_out, 4)
        ... + "  |  SR: " + fixed$(originalSR / 1000, 1) + " kHz"

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1

    # Restore full Picture page immediately below the detailed summary.
    pageHeight = 6.30
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# ===================================================================
# OUTPUT
# ===================================================================

selectObject: finalID

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output:     ", compositeName$
appendInfoLine: "Harmonized: ", nEvents, " recurring regions"
appendInfoLine: "RMS orig:   ", fixed$(rms_orig, 6)
appendInfoLine: "RMS out:    ", fixed$(rms_out, 6)

if play_result
    Play
endif

selectObject: finalID

# ===================================================================
# PROCEDURE: Generate Smooth Chord (two harmony voices; dry carries root)
# ===================================================================

procedure generateSmoothChord: .srcID, .int2, .int3, .spread, .pitchFloor, .pitchCeiling
    selectObject: .srcID
    .fs = Get sampling frequency

    # Voice 2: canonical pitch-tier modification. This preserves duration
    # and changes only voiced pitch targets used by overlap-add resynthesis.
    selectObject: .srcID
    .manip2 = To Manipulation: 0.01, .pitchFloor, .pitchCeiling
    selectObject: .manip2
    .tier2 = Extract pitch tier
    .ratio2 = 2 ^ (.int2 / 12)
    selectObject: .tier2
    Formula: "self * " + string$(.ratio2)
    selectObject: .manip2, .tier2
    Replace pitch tier
    selectObject: .manip2
    .n2 = Get resynthesis (overlap-add)
    removeObject: .manip2, .tier2

    # Voice 3.
    selectObject: .srcID
    .manip3 = To Manipulation: 0.01, .pitchFloor, .pitchCeiling
    selectObject: .manip3
    .tier3 = Extract pitch tier
    .ratio3 = 2 ^ (.int3 / 12)
    selectObject: .tier3
    Formula: "self * " + string$(.ratio3)
    selectObject: .manip3, .tier3
    Replace pitch tier
    selectObject: .manip3
    .n3 = Get resynthesis (overlap-add)
    removeObject: .manip3, .tier3

    # Constant-power stereo panning.
    # spread = 0 -> both voices centered (L=R=sqrt(1/2))
    # spread = 1 -> voice 2 hard left, voice 3 hard right.
    .spreadSafe = min(1, max(0, .spread))
    .angle2 = (1 - .spreadSafe) * pi / 4
    .angle3 = (1 + .spreadSafe) * pi / 4
    .panL2 = cos(.angle2)
    .panR2 = sin(.angle2)
    .panL3 = cos(.angle3)
    .panR3 = sin(.angle3)

    # Preserve source dynamics. Relative chord-voice gains are linear
    # multipliers; there is no per-note peak normalization.
    .gain2 = 0.75
    .gain3 = 0.60

    selectObject: .n2
    .leftOut = Copy: "AHL_harmL"
    Formula: "self * " + string$(.gain2 * .panL2) + " + object[" + string$(.n3) + ", 1, col] * " + string$(.gain3 * .panL3)

    selectObject: .n2
    .rightOut = Copy: "AHL_harmR"
    Formula: "self * " + string$(.gain2 * .panR2) + " + object[" + string$(.n3) + ", 1, col] * " + string$(.gain3 * .panR3)

    removeObject: .n2, .n3

    .leftOut = .leftOut
    .rightOut = .rightOut
endproc
