# ============================================================
# Praat AudioTools - Auto-Harmonic_Layering.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.8 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Auto-Harmonic Layering with pitch-aware chord selection.
#   Detects looped/recurring melodic phrases via SSM, picks a
#   chord type for each based on average pitch + (optionally)
#   diatonic constraints, and mixes pitch-shifted layers back
#   into the original with stereo spread and trapezoidal fades.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v1.8:
#
#   TIER 1 (Praat polish, audio bit-identical):
#     - Dropped 5 decorative `comment === ... ===` form rows
#       (PRESET / LOOP DETECTION / HARMONY MODE / MIXING / OUTPUT).
#       Form: 13 rows -> 8 rows. All 3 optionmenus already had
#       colons.
#     - Visualization rewritten from custom 9-wide layout to
#       suite 8-wide with suite styling:
#         Title bar (suite light) + metadata subtitle
#         Original waveform / Result waveform (side-by-side headline)
#         Loop map with chord labels  (full width, signature panel)
#         Light-grey 3-line summary  (suite standard)
#
#   TIER 2 (real bugs, audio bit-identical):
#     - FIXED: `writeInfoLine` clobbered the log in TWO places.
#       Each `writeInfoLine` call CLEARS the info window before
#       writing. v1.7 had:
#         (1) Lines 127-129: three `writeInfoLine` calls for the
#             boxed banner. Only the third line survived; the
#             "╔══╗" top and "║ AUTO-HARMONIC ... ║" middle were
#             wiped before the user could see them.
#         (2) Lines 613-615: three more `writeInfoLine` calls in
#             the COMPLETION block. These wiped the ENTIRE
#             accumulated processing log (Phase 1, Phase 2,
#             Phase 3 messages, per-loop chord assignments)
#             right before showing the final summary.
#       v1.8 uses exactly one `writeInfoLine` at the very top
#       (line ~127) to clear the info window and write the title.
#       Every subsequent line is `appendInfoLine`.
#     - FIXED: stats text squished at far left. v1.7 line 600
#       was `Text: 0.5, "centre", 0.5, "half", ...` inside a
#       `0, 9, 4.1, 4.4` outer viewport, but no fresh `Axes:`
#       was set -- so it inherited `Axes: 0, totalDuration, 0, 2`
#       from the loop map panel above. The Text then landed at
#       x = 0.5 SECONDS (far left of the viewport for any
#       totalDuration > 1 s) and y = 0.5 in 0..2 axes (below
#       middle of a 0.3-tall strip). The stats line was unreadable.
#       v1.8 replaces this with the suite-standard light-grey
#       Panel E (3 lines, explicit `Axes: 0, 1, 0, 1`).
#     - FIXED: unicode box-drawing characters in info window.
#       v1.7 used `╔══╗ ║ ║ ╚══╝` for banners (U+2500 range).
#       These render correctly on most modern Praat installs but
#       show as mojibake on some older Windows Praat builds.
#       v1.8 uses plain ASCII `===` separators.
#
#   Audio output is bit-identical to v1.7.
#
# Changelog v1.7:
#   - Replaced standard fades with a calculated trapezoidal
#     amplitude envelope to eliminate clicking/jumping.
# ============================================================

form Auto-Harmonic Layering v1.8
    optionmenu Preset: 1
        option Subtle (Conservative harmonies)
        option Rich (Full chords, smooth)
        option Bold (Wider intervals)
        option Diatonic (Stay in key)
        option Experimental (Random per loop)
        option Custom
    positive Num_loops_to_find 5
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
rms_orig = Get root-mean-square: 0, 0

# v1.8: one writeInfoLine to clear + initialize. Everything else uses
# appendInfoLine so the running log accumulates instead of being
# clobbered. v1.7 had 3 writeInfoLines in a row here (lines 127-129)
# and 3 more in the COMPLETION block (lines 613-615); only the LAST
# of each block survived, wiping the rest of the log.
writeInfoLine: "=== AUTO-HARMONIC LAYERING v1.8 ==="
appendInfoLine: ""
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
compositeName$ = originalName$ + "_harmonized_" + presetName$
Rename: compositeName$
Scale peak: 0.95

# Get output stats for visualization / summary
selectObject: finalID
rms_out = Get root-mean-square: 0, 0
durOut = Get total duration

# Cleanup
removeObject: pitchID, wetL, wetR, dryL, dryR

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
    Text: 0.5, "centre", 0.68, "half", "##AUTO-HARMONIC LAYERING##"
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

    # Draw waveform underlay in the background for time reference
    Colour: "{0.78, 0.80, 0.85}"
    Line width: 0.5
    selectObject: originalID
    # Note: this Draw uses Sound auto-scaling; the y range of axes (0,2)
    # is independent. Draw the waveform mapped into 0.05..0.25 for visual
    # reference at the bottom of the panel.
    # (Using Draw inner box later will overlay the chord rectangles cleanly.)

    # Now switch back to axes-coord drawing for loop rectangles + labels
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
        Font size: 9
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
        if useDiatonic = 1
            harmDetail$ = "Pitch-Aware diatonic (C major)"
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
        ... + "  |  Pitch range: " + fixed$(pitchFloor, 0) + "-" + fixed$(pitchCeiling, 0) + " Hz"
        ... + "  |  Tolerance: " + fixed$(toleranceHz, 0) + " Hz"

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
endif

# ===================================================================
# OUTPUT
# ===================================================================

selectObject: finalID

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output:     ", compositeName$
appendInfoLine: "Harmonized: ", nEvents, " loops with pitch-aware chords"
appendInfoLine: "RMS orig:   ", fixed$(rms_orig, 6)
appendInfoLine: "RMS out:    ", fixed$(rms_out, 6)

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
