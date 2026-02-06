# ============================================================
# Praat AudioTools - Auto-Harmonic_Layering.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.7 (2025) - Smooth Envelope Fix
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Auto-Harmonic Layering with pitch-aware chord selection.
#   v1.7 Fix: Replaced standard fades with a calculated 
#   trapezoidal amplitude envelope to eliminate clicking/jumping.
# ============================================================

form Auto-Harmonic Layering v1.7
    comment === PRESET (controls most parameters) ===
    optionmenu Preset: 1
        option Subtle (Conservative harmonies)
        option Rich (Full chords, smooth)
        option Bold (Wider intervals)
        option Diatonic (Stay in key)
        option Experimental (Random per loop)
        option Custom
    
    comment === LOOP DETECTION ===
    positive Num_loops_to_find 5
    positive Min_loop_duration 0.4
    
    comment === HARMONY MODE ===
    optionmenu Harmony_style: 1
        option Pitch-Aware (Analyzes melody)
        option Fixed Chord Type
    optionmenu Fixed_chord_if_used: 3
        option Octaves
        option Fifths
        option Major
        option Minor
        option Sus4
    
    comment === MIXING ===
    real Dry_level 0.75
    real Wet_level 0.45
    
    comment === OUTPUT ===
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
    toleranceHz = 40
    stereoSpread = 0.5
    fadeMs = 30
    useDiatonic = 0
    voiceLeading = 1
elsif preset = 2
    presetName$ = "Rich"
    pitchFloor = 75
    pitchCeiling = 600
    toleranceHz = 50
    stereoSpread = 0.7
    fadeMs = 50
    useDiatonic = 1
    voiceLeading = 1
elsif preset = 3
    presetName$ = "Bold"
    pitchFloor = 60
    pitchCeiling = 700
    toleranceHz = 60
    stereoSpread = 0.9
    fadeMs = 20
    useDiatonic = 0
    voiceLeading = 0
elsif preset = 4
    presetName$ = "Diatonic"
    pitchFloor = 75
    pitchCeiling = 600
    toleranceHz = 30
    stereoSpread = 0.6
    fadeMs = 60
    useDiatonic = 1
    voiceLeading = 1
elsif preset = 5
    presetName$ = "Experimental"
    pitchFloor = 50
    pitchCeiling = 800
    toleranceHz = 70
    stereoSpread = 0.8
    fadeMs = 15
    useDiatonic = 0
    voiceLeading = 0
else
    presetName$ = "Custom"
    pitchFloor = 75
    pitchCeiling = 600
    toleranceHz = 50
    stereoSpread = 0.7
    fadeMs = 30
    useDiatonic = 0
    voiceLeading = 1
endif

fadeDuration = fadeMs / 1000

# ===================================================================
# PHASE 1: FIND LOOPS
# ===================================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

selectObject: originalID
totalDuration = Get total duration
originalSR = Get sampling frequency

writeInfoLine: "╔══════════════════════════════════════════════════════════════╗"
writeInfoLine: "║      AUTO-HARMONIC LAYERING v1.7 (Smooth Envelope)           ║"
writeInfoLine: "╚══════════════════════════════════════════════════════════════╝"
appendInfoLine: "Source: ", originalName$, " (", fixed$(totalDuration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "--- Phase 1: Analyzing Pitch & Loops ---"

# 1. Extract Pitch
selectObject: originalID
timeStep = 0.05
To Pitch: timeStep, pitchFloor, pitchCeiling
pitchID = selected("Pitch")
numFrames = Get number of frames

# Store pitch values
pitchVals# = zero#(numFrames)
for i to numFrames
    val = Get value in frame: i, "Hertz"
    if val = undefined
        val = 0
    endif
    pitchVals#[i] = val
endfor

# 2. Create pitch matrix for SSM
Create simple Matrix: "ThePitchData", numFrames, 1, "0"
dataID = selected("Matrix")

for i to numFrames
    Set value: i, 1, pitchVals#[i]
endfor

# 3. Build Self-Similarity Matrix
appendInfoLine: "Building self-similarity matrix..."
Create simple Matrix: "SSM", numFrames, numFrames, "0"
ssmID = selected("Matrix")

Formula: "if Matrix_ThePitchData[row, 1] > 0 and Matrix_ThePitchData[col, 1] > 0 and abs(Matrix_ThePitchData[row, 1] - Matrix_ThePitchData[col, 1]) < " + string$(toleranceHz) + " then 1 - (abs(Matrix_ThePitchData[row, 1] - Matrix_ThePitchData[col, 1]) / " + string$(toleranceHz) + ") else 0 fi"

# 4. Find loop candidates
Create Table with column names: "candidates", 0, "start_frame length_frames gap_frames score"
tableID = selected("Table")

selectObject: ssmID
frameRate = 1 / timeStep
minLen = round(min_loop_duration * frameRate)
maxGap = numFrames - minLen
gap = minLen
step = 1

if numFrames > 2000
    step = 2
endif

appendInfoLine: "Searching for loops..."

while gap <= maxGap
    pathLen = 0
    pathStart = 0
    searchLimit = numFrames - gap
    
    for i to searchLimit
        j = i + gap
        val = Get value in cell: i, j
        
        if val > 0.5
            if pathLen = 0
                pathStart = i
            endif
            pathLen += 1
        else
            if pathLen >= minLen
                selectObject: tableID
                Append row
                row = Get number of rows
                Set numeric value: row, "start_frame", pathStart
                Set numeric value: row, "length_frames", pathLen
                Set numeric value: row, "gap_frames", gap
                Set numeric value: row, "score", pathLen * val
                selectObject: ssmID
            endif
            pathLen = 0
        endif
    endfor
    gap += step
endwhile

# 5. Select best non-overlapping loops
selectObject: tableID
nRows = Get number of rows

if nRows = 0
    removeObject: dataID, ssmID, tableID, pitchID
    exitScript: "No loops found. Try adjusting parameters."
endif

Sort rows: "score"

# Arrays for loop data
maxLoops = num_loops_to_find
loopStart# = zero#(maxLoops)
loopEnd# = zero#(maxLoops)
loopPitch# = zero#(maxLoops)

loopsFound = 0
rowIndex = nRows

while loopsFound < num_loops_to_find and rowIndex > 0
    selectObject: tableID
    startF = Get value: rowIndex, "start_frame"
    lenF = Get value: rowIndex, "length_frames"
    
    t1 = (startF - 1) * timeStep
    dur = lenF * timeStep
    t2 = t1 + dur
    
    # Check overlap
    isOverlap = 0
    for k to loopsFound
        if t1 < loopEnd#[k] and t2 > loopStart#[k]
            isOverlap = 1
        endif
    endfor
    
    if isOverlap = 0
        loopsFound += 1
        loopStart#[loopsFound] = t1
        loopEnd#[loopsFound] = t2
        
        # Calculate average pitch for this loop
        sumPitch = 0
        countPitch = 0
        startFrame = round(t1 / timeStep) + 1
        endFrame = round(t2 / timeStep)
        
        for fr from startFrame to endFrame
            if fr >= 1 and fr <= numFrames
                if pitchVals#[fr] > 0
                    sumPitch += pitchVals#[fr]
                    countPitch += 1
                endif
            endif
        endfor
        
        if countPitch > 0
            loopPitch#[loopsFound] = sumPitch / countPitch
        else
            loopPitch#[loopsFound] = 200
        endif
    endif
    rowIndex -= 1
endwhile

appendInfoLine: "Found ", loopsFound, " loops"

removeObject: dataID, ssmID, tableID

# ===================================================================
# PHASE 2: PITCH-AWARE CHORD SELECTION
# ===================================================================

appendInfoLine: ""
appendInfoLine: "--- Phase 2: Analyzing Harmony ---"

chordType# = zero#(loopsFound)
interval2# = zero#(loopsFound)
interval3# = zero#(loopsFound)
chordName$# = empty$#(loopsFound)

for i to loopsFound
    if harmony_style = 1
        # Pitch-Aware mode
        avgPitch = loopPitch#[i]
        
        # Convert to MIDI note number
        midiNote = round(69 + 12 * log2(avgPitch / 440))
        # Get chroma class: 0=C, 1=C#, 2=D, etc.
        chromaClass = midiNote mod 12
        
        if useDiatonic = 1
            # Diatonic harmonization (C major scale)
            if chromaClass = 0 or chromaClass = 7
                # C or G - use major
                interval2#[i] = 4
                interval3#[i] = 7
                chordName$#[i] = "Maj"
            elsif chromaClass = 2 or chromaClass = 9
                # D or A - use minor
                interval2#[i] = 3
                interval3#[i] = 7
                chordName$#[i] = "Min"
            elsif chromaClass = 4
                # E - use minor
                interval2#[i] = 3
                interval3#[i] = 7
                chordName$#[i] = "Min"
            elsif chromaClass = 5
                # F - use major
                interval2#[i] = 4
                interval3#[i] = 7
                chordName$#[i] = "Maj"
            elsif chromaClass = 11
                # B - use diminished
                interval2#[i] = 3
                interval3#[i] = 6
                chordName$#[i] = "Dim"
            else
                # Default to fifth
                interval2#[i] = 7
                interval3#[i] = 12
                chordName$#[i] = "5th"
            endif
        else
            # Non-diatonic: choose based on pitch height
            if avgPitch < 150
                # Low pitch - use wider intervals
                interval2#[i] = 7
                interval3#[i] = 12
                chordName$#[i] = "5th"
            elsif avgPitch < 250
                # Mid-low - minor
                interval2#[i] = 3
                interval3#[i] = 7
                chordName$#[i] = "Min"
            elsif avgPitch < 350
                # Mid - major
                interval2#[i] = 4
                interval3#[i] = 7
                chordName$#[i] = "Maj"
            else
                # High - octaves
                interval2#[i] = 12
                interval3#[i] = 19
                chordName$#[i] = "Oct"
            endif
        endif
    else
        # Fixed chord type mode
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
    endif
    
    appendInfoLine: "  Loop ", i, ": ", fixed$(loopPitch#[i], 1), " Hz -> ", chordName$#[i], " (", interval2#[i], ", ", interval3#[i], " st)"
endfor

# ===================================================================
# PHASE 3: GENERATE HARMONIES (SMOOTH ENVELOPE MIX)
# ===================================================================

appendInfoLine: ""
appendInfoLine: "--- Phase 3: Generating Harmonies ---"

# Create empty mix buffers (Full Duration)
selectObject: originalID
wetL = Create Sound from formula: "wetL", 1, 0, totalDuration, originalSR, "0"
wetR = Create Sound from formula: "wetR", 1, 0, totalDuration, originalSR, "0"

nEvents = 0
prevInt2 = 0
prevInt3 = 0

for i to loopsFound
    t1 = loopStart#[i]
    t2 = loopEnd#[i]
    
    # Extract loop segment
    selectObject: originalID
    loopSegment = Extract part: t1, t2, "rectangular", 1.0, "no"
    
    # Voice leading logic
    int2 = interval2#[i]
    int3 = interval3#[i]
    
    if voiceLeading = 1 and i > 1
        if abs(int2 - prevInt2) > 5
            if int2 = 4 and int3 = 7
                int2 = 3
                int3 = 8
            elsif int2 = 3 and int3 = 7
                int2 = 4
                int3 = 9
            endif
        endif
    endif
    prevInt2 = int2
    prevInt3 = int3
    
    # Generate chord
    @generateSmoothChord: loopSegment, int2, int3, stereoSpread, fadeDuration
    harmL = generateSmoothChord.leftOut
    harmR = generateSmoothChord.rightOut
    
    # === SMOOTH FADE ENVELOPE ===
    # This formula creates a trapezoidal volume shape:
    # 0 -> 1 (Fade In), Stay at 1, 1 -> 0 (Fade Out)
    
    # Calculate safe fade duration (ensure we don't fade more than half the duration)
    selectObject: harmL
    durH = Get total duration
    safeFade = fadeDuration
    if safeFade > durH / 2
        safeFade = durH / 2
    endif
    
    fadeStr$ = fixed$(safeFade, 6)
    durStr$ = fixed$(durH, 6)
    
    selectObject: harmL
    Formula: "self * (if x < " + fadeStr$ + " then x/" + fadeStr$ + " else if x > " + durStr$ + " - " + fadeStr$ + " then (" + durStr$ + " - x)/" + fadeStr$ + " else 1 fi fi)"

    selectObject: harmR
    Formula: "self * (if x < " + fadeStr$ + " then x/" + fadeStr$ + " else if x > " + durStr$ + " - " + fadeStr$ + " then (" + durStr$ + " - x)/" + fadeStr$ + " else 1 fi fi)"

    # === ROBUST POSITIONING ===
    
    selectObject: harmL
    Rename: "HarmL"
    
    selectObject: harmR
    Rename: "HarmR"
    
    # Calculate start sample index for the main track
    startSample = round(t1 * originalSR) + 1
    
    # Mix Left
    selectObject: wetL
    # Formula (part): startTime, endTime, scaling, scaling, formula
    Formula (part): t1, t1 + durH, 1, 1, "self + Sound_HarmL[col - " + string$(startSample) + " + 1]"
    
    # Mix Right
    selectObject: wetR
    Formula (part): t1, t1 + durH, 1, 1, "self + Sound_HarmR[col - " + string$(startSample) + " + 1]"
    
    removeObject: loopSegment, harmL, harmR
    nEvents += 1
    
    appendInfoLine: "  Mixed loop ", i, " at ", fixed$(t1, 2), "s"
endfor

# Scale wet mix
selectObject: wetL
Formula: "self * " + string$(wet_level)

selectObject: wetR
Formula: "self * " + string$(wet_level)

# Create dry channels
selectObject: originalID
numChannels = Get number of channels

if numChannels = 1
    dryL = Copy: "dryL"
    selectObject: originalID
    dryR = Copy: "dryR"
else
    Extract one channel: 1
    dryL = selected("Sound")
    selectObject: originalID
    Extract one channel: 2
    dryR = selected("Sound")
endif

# Scale dry
selectObject: dryL
Formula: "self * " + string$(dry_level)

selectObject: dryR
Formula: "self * " + string$(dry_level)

# MIX DRY + WET
selectObject: dryL
Formula: "self + object[" + string$(wetL) + "]"

selectObject: dryR
Formula: "self + object[" + string$(wetR) + "]"

# Create final stereo
selectObject: dryL, dryR
Combine to stereo
finalID = selected("Sound")
Rename: originalName$ + "_harmonized_" + presetName$
Scale peak: 0.95

# Cleanup
removeObject: pitchID, wetL, wetR, dryL, dryR

# ===================================================================
# VISUALIZATION
# ===================================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 9, 0.1, 0.6
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Auto-Harmonic Layering v1.7## | " + originalName$
    
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.15, "half", "Preset: " + presetName$ + " | Loops: " + string$(loopsFound) + " | Voice Leading: " + string$(voiceLeading)
    
    # Waveforms
    Select outer viewport: 0, 9, 0.7, 1.6
    Select inner viewport: 0.5, 8.7, 0.8, 1.5
    selectObject: originalID
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Dry"
    
    Select outer viewport: 0, 9, 1.7, 2.6
    Select inner viewport: 0.5, 8.7, 1.8, 2.5
    selectObject: finalID
    Colour: "{0.4, 0.6, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Result"
    Text bottom: "yes", "Time (s)"
    
    # Loop map with chords
    Select outer viewport: 0, 9, 2.8, 4.0
    Select inner viewport: 0.5, 8.7, 2.9, 3.9
    
    Axes: 0, totalDuration, 0, 2
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, totalDuration, 0, 2
    
    for i to loopsFound
        # Loop region
        Paint rectangle: "{0.6, 0.75, 0.9}", loopStart#[i], loopEnd#[i], 0.3, 1.7
        
        # Chord label
        Colour: "Black"
        Font size: 7
        midT = (loopStart#[i] + loopEnd#[i]) / 2
        Text: midT, "centre", 1.0, "half", chordName$#[i]
        Font size: 6
        Text: midT, "centre", 0.6, "half", fixed$(loopPitch#[i], 0) + "Hz"
    endfor
    
    Colour: "Black"
    Draw inner box
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Loops"
    
    # Stats
    Select outer viewport: 0, 9, 4.1, 4.4
    Font size: 7
    Colour: "{0.3, 0.3, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Harmonized: " + string$(nEvents) + " events | Dry: " + fixed$(dry_level, 2) + " | Wet: " + fixed$(wet_level, 2) + " | Spread: " + fixed$(stereoSpread, 2) + " | Fade: " + string$(fadeMs) + "ms"
    
    Font size: 10
    Colour: "Black"
endif

# ===================================================================
# OUTPUT
# ===================================================================

selectObject: finalID

appendInfoLine: ""
appendInfoLine: "╔══════════════════════════════════════════════════════════════╗"
appendInfoLine: "║                       COMPLETE                               ║"
appendInfoLine: "╚══════════════════════════════════════════════════════════════╝"
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Harmonized: ", nEvents, " loops with pitch-aware chords"

if play_result
    Play
endif

selectObject: finalID

# ===================================================================
# PROCEDURE: Generate Smooth Chord
# ===================================================================

procedure generateSmoothChord: .srcID, .int2, .int3, .spread, .fade
    selectObject: .srcID
    .fs = Get sampling frequency
    .dur = Get total duration
    
    .semitone = 2 ^ (1/12)
    
    # Root
    selectObject: .srcID
    .root = Copy: "root"
    
    # Note 2
    selectObject: .srcID
    .note2 = Copy: "n2_temp"
    .ratio2 = .semitone ^ .int2
    Override sampling frequency: .fs * .ratio2
    .manip2 = To Manipulation: 0.01, 75, 600
    .dur2 = Extract duration tier
    selectObject: .dur2
    Add point: 0, .ratio2
    selectObject: .manip2, .dur2
    Replace duration tier
    selectObject: .manip2
    .res2 = Get resynthesis (overlap-add)
    selectObject: .res2
    .n2 = Resample: .fs, 50
    Scale peak: 0.7
    removeObject: .note2, .manip2, .dur2, .res2
    
    # Note 3
    selectObject: .srcID
    .note3 = Copy: "n3_temp"
    .ratio3 = .semitone ^ .int3
    Override sampling frequency: .fs * .ratio3
    .manip3 = To Manipulation: 0.01, 75, 600
    .dur3 = Extract duration tier
    selectObject: .dur3
    Add point: 0, .ratio3
    selectObject: .manip3, .dur3
    Replace duration tier
    selectObject: .manip3
    .res3 = Get resynthesis (overlap-add)
    selectObject: .res3
    .n3 = Resample: .fs, 50
    Scale peak: 0.5
    removeObject: .note3, .manip3, .dur3, .res3
    
    # Stereo panning
    .panL2 = 1 - .spread * 0.6
    .panR2 = 0.4 + .spread * 0.6
    .panL3 = 0.4 + .spread * 0.6
    .panR3 = 1 - .spread * 0.6
    
    # Build channels
    selectObject: .root
    .rootL = Copy: "rootL"
    .rootR = Copy: "rootR"
    
    selectObject: .n2
    .n2L = Copy: "n2L"
    .n2R = Copy: "n2R"
    
    selectObject: .n3
    .n3L = Copy: "n3L"
    .n3R = Copy: "n3R"
    
    # Pan
    selectObject: .n2L
    Formula: "self * " + string$(.panL2)
    selectObject: .n2R
    Formula: "self * " + string$(.panR2)
    selectObject: .n3L
    Formula: "self * " + string$(.panL3)
    selectObject: .n3R
    Formula: "self * " + string$(.panR3)
    
    # Mix left
    selectObject: .rootL, .n2L
    .tmp1 = Combine to stereo
    .mix1 = Convert to mono
    removeObject: .tmp1
    selectObject: .mix1, .n3L
    .tmp2 = Combine to stereo
    .leftOut = Convert to mono
    Rename: "harmL"
    removeObject: .tmp2, .mix1
    
    # Mix right
    selectObject: .rootR, .n2R
    .tmp3 = Combine to stereo
    .mix2 = Convert to mono
    removeObject: .tmp3
    selectObject: .mix2, .n3R
    .tmp4 = Combine to stereo
    .rightOut = Convert to mono
    Rename: "harmR"
    removeObject: .tmp4, .mix2
    
    # Cleanup
    removeObject: .root, .rootL, .rootR, .n2, .n2L, .n2R, .n3, .n3L, .n3R
    
    .leftOut = .leftOut
    .rightOut = .rightOut
endproc