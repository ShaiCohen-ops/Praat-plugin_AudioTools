# ============================================================
# Praat AudioTools - PraatPbind.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026) - Unified Cross-Platform Version
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   PraatPbind — Declarative Pattern Engine for Praat
#
#   PraatPbind integrates a SuperCollider-style event pattern system
#   (Pbind syntax) into Praat’s analysis–resynthesis workflow.
#
#   The system enables users to define event-based control structures
#   (Pseq, Prand, Pwrand, Pwhite, Pexprand, Pstutter, etc.) using a
#   compact one-line Pbind expression. These patterns are interpreted
#   by a Python engine and compiled into time-aligned PitchTier and
#   IntensityTier control curves.
#
#   Supported Pitch Domains:
#     - degree   (major scale index relative to baseHz)
#     - midinote (MIDI pitch)
#     - freq     (raw frequency in Hz)
#
#   Additional Controls:
#     - dur      (event spacing)
#     - amp      (linear amplitude)
#     - legato   (segment scaling for articulation)
#
#   PraatPbind functions as an offline, deterministic pattern engine
#   for algorithmic acoustic transformation and experimental composition.
#
# Citation:
#   Cohen, S. (2026). PraatPbind: A Declarative Pattern Engine for
#   Event-Driven Acoustic Resynthesis in Praat.
#   Praat AudioTools Plugin.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound       = selected("Sound")
soundName$  = selected$("Sound")

# ---- PATHS & UNIFIED CROSS-PLATFORM FIX ----
pluginDirRaw$ = preferencesDirectory$ + "/plugin_AudioTools/"
pluginDir$ = replace_regex$(pluginDirRaw$, "\\", "/", 0)

pythonScript$ = pluginDir$ + "py/PraatPbind.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/PraatPbind.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: PraatPbind.py" + newline$ + "Expected at: " + pluginDir$ + "py/ or next to this script."
endif

tempDirRaw$ = temporaryDirectory$ + "/"
tempDir$ = replace_regex$(tempDirRaw$, "\\", "/", 0)

tempAnalysis$  = tempDir$ + "temp_eventgen_analysis.csv"
tempPbind$     = tempDir$ + "temp_eventgen_pbind.txt"
tempPitchCsv$  = tempDir$ + "temp_eventgen_pitch.csv"
tempIntCsv$    = tempDir$ + "temp_eventgen_intensity.csv"
probePy$       = tempDir$ + "temp_eventgen_probe.py"
probeMarker$   = tempDir$ + "temp_eventgen_probe.ok"

# Enforce forward slashes for all temporary paths passed to python
pythonScriptJ$  = replace_regex$(pythonScript$, "\\", "/", 0)
tempAnalysisJ$  = replace_regex$(tempAnalysis$, "\\", "/", 0)
tempPbindJ$     = replace_regex$(tempPbind$, "\\", "/", 0)
tempPitchCsvJ$  = replace_regex$(tempPitchCsv$, "\\", "/", 0)
tempIntCsvJ$    = replace_regex$(tempIntCsv$, "\\", "/", 0)
probePyJ$       = replace_regex$(probePy$, "\\", "/", 0)
probeMarkerJ$   = replace_regex$(probeMarker$, "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(tempAnalysis$)
        deleteFile: tempAnalysis$
    endif
    if fileReadable(tempPbind$)
        deleteFile: tempPbind$
    endif
    if fileReadable(tempPitchCsv$)
        deleteFile: tempPitchCsv$
    endif
    if fileReadable(tempIntCsv$)
        deleteFile: tempIntCsv$
    endif
    if fileReadable(probePy$)
        deleteFile: probePy$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
endproc

@cleanUpTempFiles

# ---- FORM ----
form EventGen — Pbind Resynthesis v1.1
    optionmenu Preset: 2
        option Custom
        option MajorUp
        option RandomWalk
        option Pulses
        option MidiMelody
        option RawFreq
        option LegatoPhrase
        option WeightedChord
        option Stutter
    text Pbind Pbind(degree=Pseq([0,1,2,4,7],inf), dur=0.25, amp=Pwhite(0.1,0.5,inf))
    positive BaseHz 220
    integer Seed 42
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- PRESET OVERRIDE ----
if preset = 2
    pbind$ = "Pbind(degree=Pseq([0,1,2,4,7],inf), dur=0.25, amp=Pwhite(0.1,0.5,inf))"
    presetName$ = "MajorUp"
elsif preset = 3
    pbind$ = "Pbind(degree=Pseq([0,1,2,3,4,5,6],inf), dur=0.15, amp=Pwhite(0.2,0.6,inf))"
    presetName$ = "RandomWalk"
elsif preset = 4
    pbind$ = "Pbind(degree=Pseq([0,0,7,0,0,4],inf), dur=0.10, amp=Pwhite(0.05,0.9,inf))"
    presetName$ = "Pulses"
elsif preset = 5
    pbind$ = "Pbind(midinote=Pseq([60,62,64,65,67,69],inf), dur=0.2, amp=Pwhite(0.3,0.7,inf))"
    presetName$ = "MidiMelody"
elsif preset = 6
    pbind$ = "Pbind(freq=Pwhite(200,800,inf), dur=0.1, amp=0.4)"
    presetName$ = "RawFreq"
elsif preset = 7
    pbind$ = "Pbind(degree=Pseq([0,2,4,7],inf), dur=0.3, amp=Pwhite(0.3,0.7,inf), legato=0.6)"
    presetName$ = "LegatoPhrase"
elsif preset = 8
    pbind$ = "Pbind(degree=Pwrand([0,4,7],[0.5,0.3,0.2],inf), dur=0.2, amp=Pwhite(0.2,0.6,inf))"
    presetName$ = "WeightedChord"
elsif preset = 9
    pbind$ = "Pbind(degree=Pstutter(Pseq([0,4,7],inf),3), dur=0.1, amp=Pwhite(0.2,0.7,inf))"
    presetName$ = "Stutter"
else
    pbind$ = pbind$
    presetName$ = "Custom"
endif

# ---- ORIGINAL STATS ----
selectObject: sound
dur = Get total duration
sr  = Get sampling frequency

# ---- INFO ----
clearinfo
writeInfoLine:  "=== EventGen — Pbind Resynthesis v1.1 ==="
appendInfoLine: "Input:   ", soundName$
appendInfoLine: "Preset:  ", presetName$
appendInfoLine: "Pbind:   ", pbind$
appendInfoLine: "BaseHz:  ", baseHz
appendInfoLine: "Seed:    ", seed
appendInfoLine: ""
appendInfoLine: "Duration: ", fixed$(dur, 3), " s | SR: ", sr, " Hz"
appendInfoLine: ""

# ===========================================================================
# STAGE 1: Detect Python Dependencies
# ===========================================================================
appendInfoLine: "[1/4] Detecting Python..."

writeFileLine: probePy$, "import sys"
appendFileLine: probePy$, "try:"
appendFileLine: probePy$, "    import csv, re, math, random, argparse"
appendFileLine: probePy$, "    with open(r'" + probeMarkerJ$ + "', 'w') as f: f.write('ok')"
appendFileLine: probePy$, "except ImportError:"
appendFileLine: probePy$, "    sys.exit(1)"

if windows
    nCandidates = 4
    candidate1$ = "python"
    candidate2$ = "py"
    candidate3$ = "py -3"
    candidate4$ = "python3"
else
    nCandidates = 3
    candidate1$ = "python3"
    candidate2$ = "python"
    candidate3$ = "py"
    candidate4$ = ""
endif

pythonCmd$ = ""
for iCand from 1 to nCandidates
    if iCand = 1
        tryCmd$ = candidate1$
    elsif iCand = 2
        tryCmd$ = candidate2$
    elsif iCand = 3
        tryCmd$ = candidate3$
    else
        tryCmd$ = candidate4$
    endif

    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif

    runSystem_nocheck: tryCmd$ + " """ + probePyJ$ + """"

    if fileReadable(probeMarker$)
        pythonCmd$ = tryCmd$
        deleteFile: probeMarker$
        iCand = nCandidates + 1 ; Break early
    endif
endfor

deleteFile: probePy$

if pythonCmd$ = ""
    @cleanUpTempFiles
    exitScript: "Cannot find Python 3 installation." + newline$ + "Tried: python3, python, py"
endif

appendInfoLine: "  Python found: ", pythonCmd$

# ===========================================================================
# STAGE 2: Write Analysis CSV & Pbind Text File
# ===========================================================================
appendInfoLine: "[2/4] Writing analysis and Pbind files..."

writeFileLine: tempAnalysis$, "duration_seconds,sampling_rate"
appendFileLine: tempAnalysis$, string$(dur) + "," + string$(sr)

writeFileLine: tempPbind$, pbind$

# ===========================================================================
# STAGE 3: Run Python Engine
# ===========================================================================
appendInfoLine: "[3/4] Running Python Pbind engine..."

pythonCall$ = pythonCmd$ + " """ + pythonScriptJ$ + """"
    ... + " """ + tempAnalysisJ$ + """"
    ... + " """ + tempPbindJ$ + """"
    ... + " """ + tempPitchCsvJ$ + """"
    ... + " """ + tempIntCsvJ$ + """"
    ... + " --baseHz " + fixed$(baseHz, 6)
    ... + " --seed " + string$(seed)

runSystem_nocheck: pythonCall$

if not fileReadable(tempPitchCsv$) or not fileReadable(tempIntCsv$)
    @cleanUpTempFiles
    exitScript: "Python EventGen engine failed to produce CSV outputs." + newline$ + "Check terminal for errors."
endif

# ===========================================================================
# STAGE 4: Build Tiers & Resynthesize
# ===========================================================================
appendInfoLine: "[4/4] Resynthesizing..."

Create PitchTier: "generatedPitch", 0, dur
pitchTier = selected("PitchTier")

Read Strings from raw text file: tempPitchCsv$
pitchStrings = selected("Strings")
nPitchLines  = Get number of strings

nStoredPitch = 0
midiMin =  999
midiMax = -999

for iLine from 2 to nPitchLines
    selectObject: pitchStrings
    lineStr$ = Get string: iLine
    lineStr$ = replace$(lineStr$, " ", "", 0)
    if lineStr$ <> ""
        commaPos = index(lineStr$, ",")
        if commaPos > 0
            ptTime$ = left$(lineStr$, commaPos - 1)
            ptHz$   = mid$(lineStr$, commaPos + 1, length(lineStr$) - commaPos)
            ptTime  = number(ptTime$)
            ptHz    = number(ptHz$)
            if ptHz > 0 and ptTime >= 0 and ptTime <= dur
                selectObject: pitchTier
                Add point: ptTime, ptHz
                nStoredPitch = nStoredPitch + 1
                ptTime_'nStoredPitch' = ptTime
                ptHz_'nStoredPitch'   = ptHz
                midiVal = 69 + 12 * log2(ptHz / 440)
                if midiVal < midiMin
                    midiMin = midiVal
                endif
                if midiVal > midiMax
                    midiMax = midiVal
                endif
            endif
        endif
    endif
endfor
removeObject: pitchStrings

Create IntensityTier: "generatedIntensity", 0, dur
intensityTier = selected("IntensityTier")

Read Strings from raw text file: tempIntCsv$
intStrings = selected("Strings")
nIntLines  = Get number of strings

nStoredInt = 0
dbMin =  999
dbMax = -999

for iLine from 2 to nIntLines
    selectObject: intStrings
    lineStr$ = Get string: iLine
    lineStr$ = replace$(lineStr$, " ", "", 0)
    if lineStr$ <> ""
        commaPos = index(lineStr$, ",")
        if commaPos > 0
            ptTime$ = left$(lineStr$, commaPos - 1)
            ptDb$   = mid$(lineStr$, commaPos + 1, length(lineStr$) - commaPos)
            ptTime  = number(ptTime$)
            ptDb    = number(ptDb$)
            if ptTime >= 0 and ptTime <= dur
                selectObject: intensityTier
                Add point: ptTime, ptDb
                nStoredInt = nStoredInt + 1
                itTime_'nStoredInt' = ptTime
                itDb_'nStoredInt'   = ptDb
                if ptDb < dbMin
                    dbMin = ptDb
                endif
                if ptDb > dbMax
                    dbMax = ptDb
                endif
            endif
        endif
    endif
endfor
removeObject: intStrings

# Resynthesis via Manipulation overlap-add
selectObject: sound
To Manipulation: 0.01, 75, 600
manip = selected("Manipulation")

selectObject: manip
plusObject: pitchTier
Replace pitch tier

selectObject: manip
Get resynthesis (overlap-add)
synthSound = selected("Sound")

selectObject: synthSound
plusObject: intensityTier
Multiply
resultSound = selected("Sound")
removeObject: synthSound

selectObject: resultSound
Rename: soundName$ + "_eventgen"

removeObject: pitchTier, intensityTier, manip

###############################################################################
# STAGE 5: VISUALIZATION
###############################################################################

if draw_visualization
    appendInfoLine: "Drawing visualization..."

    nEvents = nStoredPitch / 2

    midiDispMin = floor(midiMin) - 3
    midiDispMax = ceiling(midiMax) + 3

    if dbMin = 999
        dbMin = 50
    endif
    if dbMax = -999
        dbMax = 80
    endif
    dbSpan = dbMax - dbMin
    if dbSpan < 5
        dbSpan = 5
    endif
    dbDispMin = dbMin - dbSpan * 0.15
    dbDispMax = dbMax + dbSpan * 0.15

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # ── Title ───────────────────────────────────────────────────────────────
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half", "##EventGen — Pbind Resynthesis##"
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -1.2, "half", soundName$ + "  |  " + presetName$ + "  |  BaseHz=" + fixed$(baseHz,1) + "  |  Seed=" + string$(seed)

    # ── Original waveform with event markers ────────────────────────────────
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.7, 0.65, 1.45
    selectObject: sound
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Colour: "{0.80, 0.30, 0.30}"
    Line width: 1
    Axes: 0, dur, -1, 1
    iP = 1
    while iP <= nStoredPitch
        evT = ptTime_'iP'
        if evT > 0 and evT < dur
            Draw line: evT, -0.85, evT, 0.85
        endif
        iP = iP + 2
    endwhile
    Line width: 1
    Text top: "no", string$(nEvents) + " events  |  " + fixed$(dur, 2) + " s"

    # ── Output waveform ──────────────────────────────────────────────────────
    Select outer viewport: 0, 8, 1.5, 2.4
    Select inner viewport: 0.6, 7.7, 1.55, 2.35
    selectObject: resultSound
    Colour: "{0.25, 0.45, 0.80}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "EventGen"
    Text bottom: "yes", "Time (s)"

    # ── Pitch contour panel — MIDI grid + coloured step lines ────────────────
    Select outer viewport: 0, 8, 2.5, 5.85
    Select inner viewport: 0.70, 7.7, 2.60, 5.75
    Axes: 0, dur, midiDispMin, midiDispMax

    Paint rectangle: "{0.97, 0.97, 0.99}", 0, dur, midiDispMin, midiDispMax

    # Grid lines
    for midiLine from midiDispMin to midiDispMax
        noteClass = midiLine - 12 * floor(midiLine / 12)
        if noteClass = 0
            Colour: "{0.55, 0.55, 0.72}"
            Line width: 1.8
            Draw line: 0, midiLine, dur, midiLine
        elsif noteClass = 7
            Colour: "{0.80, 0.80, 0.90}"
            Line width: 0.7
            Draw line: 0, midiLine, dur, midiLine
        else
            Colour: "{0.91, 0.91, 0.95}"
            Line width: 0.3
            Draw line: 0, midiLine, dur, midiLine
        endif
    endfor

    # Note name labels
    Font size: 6
    for midiLine from midiDispMin to midiDispMax
        noteClass = midiLine - 12 * floor(midiLine / 12)
        if noteClass = 0
            @getMidiNoteName: midiLine
            Colour: "{0.40, 0.40, 0.58}"
            Text: -dur * 0.018, "right", midiLine, "half", getMidiNoteName.fullName$
        endif
    endfor

    # Step lines: pairs (iP, iP+1) = one event
    iP = 1
    while iP <= nStoredPitch - 1
        iP2 = iP + 1
        t1  = ptTime_'iP'
        t2  = ptTime_'iP2'
        hz  = ptHz_'iP'

        if hz > 0
            midi = 69 + 12 * log2(hz / 440)
            db   = itDb_'iP'

            @mapToRange: db, dbMin, dbMax, 0.35, 1.0
            brightness = mapToRange.result

            @pitchHeightToRGB: midi, brightness, midiDispMin, midiDispMax
            colStr$ = "{" + string$(pitchHeightToRGB.red) + ", " + string$(pitchHeightToRGB.green) + ", " + string$(pitchHeightToRGB.blue) + "}"

            # Horizontal step
            Colour: colStr$
            Line width: 3.5
            Draw line: t1, midi, t2, midi

            # Onset dot
            Paint circle: colStr$, t1, midi, 0.12

            # Vertical connector to next step
            iNext = iP + 2
            if iNext <= nStoredPitch - 1
                nextHz = ptHz_'iNext'
                if nextHz > 0
                    nextMidi = 69 + 12 * log2(nextHz / 440)
                    Colour: "{0.68, 0.68, 0.76}"
                    Line width: 0.8
                    Draw line: t2, midi, t2, nextMidi
                endif
            endif
        endif
        iP = iP + 2
    endwhile

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text left: "yes", "MIDI"
    Text top: "no", "Pitch contour  (color = pitch height  •  brightness = amplitude)"

    # ── Amplitude bar panel ───────────────────────────────────────────────────
    Select outer viewport: 0, 8, 5.95, 6.85
    Select inner viewport: 0.70, 7.7, 6.05, 6.75
    Axes: 0, dur, dbDispMin, dbDispMax

    Paint rectangle: "{0.96, 0.96, 0.98}", 0, dur, dbDispMin, dbDispMax

    meanDb = (dbMin + dbMax) / 2
    Colour: "{0.72, 0.72, 0.80}"
    Line width: 0.8
    Draw line: 0, meanDb, dur, meanDb

    iI = 1
    while iI <= nStoredInt - 1
        iI2 = iI + 1
        t1  = itTime_'iI'
        t2  = itTime_'iI2'
        db  = itDb_'iI'
        hz  = ptHz_'iI'
        if hz > 0
            midi = 69 + 12 * log2(hz / 440)
            @mapToRange: db, dbMin, dbMax, 0.35, 1.0
            brightness = mapToRange.result
            @pitchHeightToRGB: midi, brightness, midiDispMin, midiDispMax
            colStr$ = "{" + string$(pitchHeightToRGB.red) + ", " + string$(pitchHeightToRGB.green) + ", " + string$(pitchHeightToRGB.blue) + "}"
            Paint rectangle: colStr$, t1, t2, dbDispMin, db
        endif
        iI = iI + 2
    endwhile

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text left: "yes", "dB"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Amplitude (dB)"

    # ── Summary panel ─────────────────────────────────────────────────────────
    Select outer viewport: 0, 8, 6.95, 8.0
    Select inner viewport: 0.6, 7.7, 7.05, 7.90
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.90, "half", "Summary:"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.68, "half", "Preset: " + presetName$ + "  |  BaseHz=" + fixed$(baseHz,1) + " Hz  |  Seed=" + string$(seed)
    Text: 0.02, "left", 0.46, "half", "Events: " + string$(nEvents) + "  |  Duration: " + fixed$(dur,2) + " s  |  MIDI range: " + string$(floor(midiMin)) + "-" + string$(ceiling(midiMax))
    Text: 0.02, "left", 0.24, "half", "dB range: " + fixed$(dbMin,1) + "-" + fixed$(dbMax,1) + "  |  Points: " + string$(nStoredPitch) + " pitch  /  " + string$(nStoredInt) + " intensity"
    Font size: 5
    Colour: "{0.40, 0.40, 0.52}"
    Text: 0.02, "left", 0.07, "half", pbind$

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"

    appendInfoLine: "  Visualization complete."
endif

# ===========================================================================
# CLEANUP
# ===========================================================================
@cleanUpTempFiles

# ===========================================================================
# SUMMARY
# ===========================================================================

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", soundName$, "_eventgen"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Pbind:  ", pbind$
appendInfoLine: "BaseHz: ", baseHz, " Hz | Seed: ", seed
appendInfoLine: "Events: ", nStoredPitch / 2, " | Pitch pts: ", nStoredPitch, " | Intensity pts: ", nStoredInt

selectObject: resultSound

if play_result
    Play
endif

# ===========================================================================
# PROCEDURES
# ===========================================================================

procedure mapToRange: .value, .fromMin, .fromMax, .toMin, .toMax
    if .fromMax <= .fromMin
        .result = .toMin
    else
        .clamped = max(.fromMin, min(.fromMax, .value))
        .result = .toMin + (.clamped - .fromMin) / (.fromMax - .fromMin) * (.toMax - .toMin)
    endif
endproc

procedure getMidiNoteName: .midi
    .noteClass = .midi - 12 * floor(.midi / 12)
    .octave    = floor(.midi / 12) - 1
    if .noteClass = 0
        .noteName$ = "C"
    elsif .noteClass = 1
        .noteName$ = "C#"
    elsif .noteClass = 2
        .noteName$ = "D"
    elsif .noteClass = 3
        .noteName$ = "D#"
    elsif .noteClass = 4
        .noteName$ = "E"
    elsif .noteClass = 5
        .noteName$ = "F"
    elsif .noteClass = 6
        .noteName$ = "F#"
    elsif .noteClass = 7
        .noteName$ = "G"
    elsif .noteClass = 8
        .noteName$ = "G#"
    elsif .noteClass = 9
        .noteName$ = "A"
    elsif .noteClass = 10
        .noteName$ = "A#"
    elsif .noteClass = 11
        .noteName$ = "B"
    endif
    .fullName$ = .noteName$ + string$(.octave)
endproc

procedure pitchHeightToRGB: .midi, .brightness, .midiMin, .midiMax
    @mapToRange: .midi, .midiMin, .midiMax, 0, 1
    .hue = (1 - mapToRange.result) * 240

    .s = 0.88
    .v = .brightness
    .c = .v * .s
    .x = .c * (1 - abs(((.hue / 60) mod 2) - 1))
    .m = .v - .c

    if .hue < 60
        .r = .c
        .g = .x
        .b = 0
    elsif .hue < 120
        .r = .x
        .g = .c
        .b = 0
    elsif .hue < 180
        .r = 0
        .g = .c
        .b = .x
    elsif .hue < 240
        .r = 0
        .g = .x
        .b = .c
    elsif .hue < 300
        .r = .x
        .g = 0
        .b = .c
    else
        .r = .c
        .g = 0
        .b = .x
    endif

    .red   = .r + .m
    .green = .g + .m
    .blue  = .b + .m
endproc