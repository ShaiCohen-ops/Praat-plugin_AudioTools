# ============================================================
# Praat AudioTools - OM_Score_Transformer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2026)
#
# Changelog v0.3:
#   - Accepts a Praat Strings OBJECT as the score, not only a file path.
#     Select the <Sound>_musicxml object that BasicPitchTranscriber leaves in
#     the Objects list, set Score source to "Selected Strings object", and the
#     whole transcribe -> transform chain runs without a file on disk.
#     The Strings branch writes the object back to the parser's own temp file,
#     so both sources go through ONE parser - no second implementation.
#   - FORM ARGUMENT ORDER CHANGED: Score_source is a new FIRST field.
#     Existing runScript calls need the extra leading argument.
#
# Changelog v0.2 - SINGLE FILE, NO PYTHON:
#   - The MusicXML reader is now native Praat and om_score_io.py is gone.
#     This script has no dependencies at all: no Python, no music21, no pip.
#   - The parser is verified AGAINST music21 rather than by eye. Five cases,
#     all producing a byte-identical note table (start/end/midi):
#       chord1 6-part score (23 notes), single-line XML with no pretty
#       printing, single part with real chords and cross-barline ties,
#       two voices in one part via <backup>, and <divisions> changing
#       mid-part.
#   - LIMITATION: .mxl files are ZIP archives and Praat cannot unzip them.
#     Uncompressed .musicxml / .xml only. In MuseScore this is
#     File > Export > MusicXML, uncompressed. Caught by extension at the
#     start of the run so the message names the real cause.
#   - Leaving the score field blank and pressing OK opens the system file
#     chooser, so the path never has to be typed; a path that does not
#     resolve offers the chooser too. Batch-safe - under praat --run the
#     chooser returns empty immediately instead of blocking. The typed path
#     is trimmed of whitespace and of the surrounding quotes that Windows
#     "Copy as path" and macOS drag-to-terminal add, following the folder
#     handling in Bayesian_Drone_Weaver.
#
# Changelog v0.1:
#   - Initial release. Reads a MusicXML score, applies OpenMusic-style
#     symbolic operations to it, and synthesizes the result with a native
#     Praat additive harmonic bank. Companion to BasicPitchTranscriber:
#     that one goes audio -> score, this one goes score -> audio, and both
#     share the same start,end,midi,amp,voice note-table format.
#   - Python is used ONLY to read the MusicXML (music21 handles .mxl
#     archives, backup/forward voice interleaving and cross-barline ties).
#     Every transformation and all synthesis happen here in Praat, so the
#     compositional logic stays inspectable and editable.
#   - Distinct from OM_Rhythm_Tree_Slicer, which slices an AUDIO Sound by a
#     rhythm tree and never touches pitch. This one operates on a symbolic
#     score with real pitches. Shared operation names mean the same thing in
#     both scripts.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   OM Score Transformer (MusicXML -> transformation -> additive synthesis)
#
#   The score is flattened to a note table, put through a fixed and
#   documented chain of operations, and rendered by summing a harmonic bank
#   per note directly into the output buffer.
#
# OPERATION ORDER (fixed, and it matters):
#     1. FILTER  - duration, register and amplitude thresholds
#     2. PITCH   - transpose, then inversion about an axis
#     3. CHORD   - thin / arpeggiate / voice-lead, on simultaneity groups
#     4. ORDER   - retrograde or rotation of onset groups
#     5. TIME    - whole-score time scale, then note-length scale
#     6. SYNTH   - additive harmonic bank
#
#   Filtering runs first so later operations act only on material that
#   survives. Pitch runs before the chord stage so that thinning by register
#   and voice-leading both see the pitches you will actually hear. Time
#   scaling runs last so the factor means what it says regardless of what
#   came before.
#
# INTERPRETIVE CHOICES (documented rather than silently assumed):
#   - RETROGRADE mirrors the score about its own end: a note that ran
#     [t1,t2] becomes [end-t2, end-t1]. Durations are preserved exactly and
#     the total length is unchanged. This is a true retrograde, not a
#     reversal of the note LIST.
#   - ROTATION rotates onset GROUPS together with their inter-onset
#     intervals, then re-lays them end to end. Carrying the intervals is what
#     preserves the ONSET GRID: the sequence of inter-onset intervals in the
#     result is exactly a rotation of the original, and rotation by n groups
#     (or by 0) is the identity. Negative steps wrap.
#     The TOTAL LENGTH IS NOT PRESERVED, and cannot be: a note held longer
#     than its own group's inter-onset interval carries its duration with it,
#     so when that group moves later its tail extends past the old end.
#     Measured on a 14-group score with a 2 s note inside a 0.125 s group,
#     rotate 1 ran 5.25 s -> 10.375 s. OpenMusic's chord-seq rotation behaves
#     the same way. Truncating notes to their interval would preserve the
#     length but silently rewrite the durations, which is worse; the achieved
#     output duration is reported instead.
#   - ARPEGGIATE offsets chord members by a stride but never lets a member
#     start after the chord's own end, and it shortens each member so the
#     chord's end is preserved. An arpeggio that ran past the chord would
#     silently lengthen the piece.
#   - VOICE-LEAD re-octaves each chord member to the octave nearest the
#     previous chord, minimizing motion. It changes register, not pitch
#     class, so the harmony is untouched.
#   - TIME SCALE multiplies onsets AND durations (true augmentation /
#     diminution). NOTE LENGTH SCALE multiplies durations only, leaving
#     onsets fixed - that is articulation (legato / staccato), and it can
#     make notes overlap. They are separate fields because they are
#     separate musical ideas.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ============================================================

# ---- CAPTURE ANY SELECTED Strings OBJECT ----
# Must happen before anything else: the parser creates its own Strings
# object, which would otherwise be picked up as "the selection".
inputStrings = 0
inputStringsName$ = ""
if numberOfSelected("Strings") = 1
    inputStrings = selected("Strings")
    inputStringsName$ = selected$("Strings")
endif

# ---- PRAAT 7.0 FULL-TRUST GUARD ----
if praatVersion >= 7000
    trusted = askForTrust()
    if not trusted
        exitScript: "This script needs permission to write temporary files."
    endif
endif

# ---- PATHS ----
# One temp file only: the tag-normalized copy of the score that the parser
# reads back as a Strings object. It is deleted the moment it is read.
tempTags$ = temporaryDirectory$ + "/temp_omsc_tags.txt"
tempScoreFromStrings$ = temporaryDirectory$ + "/temp_omsc_fromstrings.musicxml"

procedure cleanUpTempFiles
    if fileReadable(tempTags$)
        deleteFile: tempTags$
    endif
    if fileReadable(tempScoreFromStrings$)
        deleteFile: tempScoreFromStrings$
    endif
endproc

@cleanUpTempFiles

# ---- FORM ----
form OM Score Transformer v0.3
    comment === Score ===
    optionmenu Score_source: 1
        option File on disk
        option Selected Strings object
    comment (File: leave blank to pick with a dialog. Uncompressed .musicxml or .xml)
    sentence Score_file 
    comment Tempo (0 = use the tempo written in the score)
    real Tempo_bpm 0
    comment --- 1. Filter ---
    real Min_note_duration_s 0
    integer Lowest_midi 0
    integer Highest_midi 127
    comment --- 2. Pitch ---
    integer Transpose_semitones 0
    optionmenu Invert_mode: 1
        option none
        option about fixed axis
        option about mean pitch
    integer Invert_axis_midi 60
    comment --- 3. Chord operations ---
    optionmenu Chord_mode: 1
        option none
        option arpeggiate up
        option arpeggiate down
        option arpeggiate up-down
        option thin (keep highest)
        option thin (keep lowest)
        option thin (keep outer)
        option voice-lead
    positive Arpeggio_stride_ms 70
    natural Keep_per_chord 3
    comment --- 4. Order ---
    optionmenu Order_mode: 1
        option none
        option retrograde
        option rotate groups
    integer Rotate_steps 1
    comment --- 5. Time ---
    positive Time_scale 1.0
    positive Note_length_scale 1.0
    comment --- 6. Synthesis / output ---
    boolean Edit_synthesis_settings 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- SYNTHESIS DEFAULTS (overridable in the pause dialog) ----
# beginPause keeps the main form short; the dialog is pre-filled with these
# so the settings stay inspectable rather than hidden. Under
# praat --run the block auto-continues with these defaults.
harmonics = 6
spectral_tilt = 1.0
attack_ms = 15
release_ms = 150
decay_per_second = 0.8
sampling_rate = 44100
peak_ceiling = 0.95

if edit_synthesis_settings
    beginPause: "Additive synthesis settings"
        comment: "Each note is a bank of harmonics with amplitude 1/k^tilt"
        natural: "Harmonics", 6
        real: "Spectral tilt", 1.0
        positive: "Attack ms", 15
        positive: "Release ms", 150
        real: "Decay per second", 0.8
        positive: "Sampling rate", 44100
        positive: "Peak ceiling", 0.95
    endPause: "Render", 1
endif

# ---- VALIDATE ----
# ---- SCORE INPUT ----
# Two sources: a file on disk, or a Strings object already in the Objects
# list (as produced by BasicPitchTranscriber). The Strings branch writes the
# object back out to the same temp file the parser reads, so BOTH paths run
# through exactly one parser - no second implementation to keep in sync.
useStrings = 0
if score_source = 2
    if inputStrings = 0
        @cleanUpTempFiles
        exitScript: "Score source is ""Selected Strings object"" but exactly one" + newline$
            ... + "Strings object was not selected before running the script." + newline$ + newline$
            ... + "Select the <Sound>" + "_musicxml object produced by" + newline$
            ... + "BasicPitchTranscriber, or switch the source to ""File on disk""."
    endif
    useStrings = 1
    selectObject: inputStrings
    nInLines = Get number of strings
    if nInLines < 1
        @cleanUpTempFiles
        exitScript: "The selected Strings object is empty."
    endif
    selectObject: inputStrings
    Save as raw text file: tempScoreFromStrings$
    score_file$ = tempScoreFromStrings$
else
    # Trim first, exactly as Bayesian_Drone_Weaver does for its folder field.
    # A path that arrives by drag-and-drop or copy-paste routinely carries
    # leading/trailing whitespace, and on Windows and macOS it often arrives
    # WRAPPED IN QUOTES ("Copy as path" / drag into a terminal). Untrimmed, all
    # of those make fileReadable fail on a path that is actually fine.
    #
    # DOUBLE quotes only. A single quote cannot appear in a Praat string literal
    # here: Praat treats 'x' as variable interpolation and pairs the quote with
    # the next one it finds - even across two separate string literals - so a
    # regex containing an apostrophe throws "Unknown variable" at parse time.
    # Paths wrapped in single quotes must be unwrapped by hand.
    # Leaving the field blank and pressing OK opens the system file dialog, so
    # the path never has to be typed. Also offered when a typed path does not
    # resolve, which is the other way this field goes wrong.
    #
    # Batch-safe: under `praat --run` with no GUI, chooseReadFile$ returns an
    # empty string IMMEDIATELY rather than blocking (verified 6.4.06), so an
    # automated run with a blank path exits with a clear message instead of
    # hanging forever waiting on a dialog nobody can see.
    score_file$ = replace_regex$(score_file$, "^[ \t]+", "", 0)
    score_file$ = replace_regex$(score_file$, "[ \t]+$", "", 0)
    score_file$ = replace_regex$(score_file$, "^""", "", 0)
    score_file$ = replace_regex$(score_file$, """$", "", 0)
    score_file$ = replace_regex$(score_file$, "^[ \t]+", "", 0)
    score_file$ = replace_regex$(score_file$, "[ \t]+$", "", 0)

    if score_file$ = ""
        score_file$ = chooseReadFile$: "Select a MusicXML score (.musicxml or .xml)"
        if score_file$ = ""
            exitScript: "No score file selected."
        endif
    elsif not fileReadable(score_file$)
        typedPath$ = score_file$
        score_file$ = chooseReadFile$: "Cannot open that path - select a MusicXML score"
        if score_file$ = ""
            exitScript: "Cannot read the score file:" + newline$ + typedPath$
        endif
    endif

    if not fileReadable(score_file$)
        exitScript: "Cannot read the score file:" + newline$ + score_file$
    endif

    # .mxl is a ZIP archive and Praat cannot unzip it. Caught here by extension
    # so the user gets the real reason, rather than a confusing "no notes found"
    # after the parser reads binary rubbish.
    if right$(score_file$, 4) = ".mxl" or right$(score_file$, 4) = ".MXL"
        exitScript: "That is a compressed MusicXML file (.mxl), which is a ZIP" + newline$
            ... + "archive - Praat cannot unzip it." + newline$ + newline$
            ... + "Re-export it uncompressed:" + newline$
            ... + "  MuseScore:  File > Export > MusicXML, uncompressed" + newline$
            ... + "  Finale/Sibelius: choose .musicxml rather than .mxl"
    endif
    if lowest_midi > highest_midi
        exitScript: "Lowest MIDI (" + string$(lowest_midi) + ") is above highest MIDI ("
            ... + string$(highest_midi) + ")."
    endif
    if harmonics < 1
        harmonics = 1
    endif
    if harmonics > 24
        harmonics = 24
    endif
    if sampling_rate < 8000
        sampling_rate = 8000
    endif
    if peak_ceiling <= 0 or peak_ceiling > 1
        peak_ceiling = 0.95
    endif
endif

if useStrings = 1
    scoreName$ = inputStringsName$
else
    scoreName$ = replace_regex$(score_file$, "^.*[/\\]", "", 0)
    scoreName$ = replace_regex$(scoreName$, "\.[^.]*$", "", 0)
endif
if scoreName$ = ""
    scoreName$ = "score"
endif

# ---- CHAIN DESCRIPTION (used in the report and the summary panel) ----
filterStr$ = "no filter"
if min_note_duration_s > 0 or lowest_midi > 0 or highest_midi < 127
    filterStr$ = "filter"
endif
pitchStr$ = "no pitch op"
if transpose_semitones <> 0 and invert_mode > 1
    pitchStr$ = "invert+transpose"
elsif transpose_semitones <> 0
    pitchStr$ = "transpose " + string$(transpose_semitones)
elsif invert_mode > 1
    pitchStr$ = "invert"
endif
if chord_mode = 1
    chordStr$ = "no chord op"
elsif chord_mode = 2
    chordStr$ = "arp up"
elsif chord_mode = 3
    chordStr$ = "arp down"
elsif chord_mode = 4
    chordStr$ = "arp up-down"
elsif chord_mode = 5
    chordStr$ = "thin high"
elsif chord_mode = 6
    chordStr$ = "thin low"
elsif chord_mode = 7
    chordStr$ = "thin outer"
else
    chordStr$ = "voice-lead"
endif
if order_mode = 2
    orderStr$ = "retrograde"
elsif order_mode = 3
    orderStr$ = "rotate " + string$(rotate_steps)
else
    orderStr$ = "no order op"
endif
timeStr$ = "time x" + fixed$(time_scale, 2) + " len x" + fixed$(note_length_scale, 2)

# ---- INFO ----
clearinfo
writeInfoLine:  "=== OM Score Transformer v0.3 ==="
appendInfoLine: "Score: ", scoreName$
appendInfoLine: ""

# ===========================================================================
# Stage 1 - Read the score (native Praat MusicXML parser)
# ===========================================================================
if useStrings = 1
    appendInfoLine: "[1/5] Reading MusicXML from Strings object ", inputStringsName$, "..."
else
    appendInfoLine: "[1/5] Reading MusicXML..."
endif

@parseMusicXML: score_file$, tempo_bpm

if pxN < 1
    @cleanUpTempFiles
    exitScript: "No notes found in the score." + newline$
        ... + "If this is a .mxl file, re-export it as uncompressed .musicxml:" + newline$
        ... + ".mxl is a ZIP archive and Praat cannot unzip it."
endif

srcCount$   = string$(pxN)
tempoStat$  = fixed$(pxTempo, 3)
tempoSrc$   = pxTempoSrc$
partsStat$  = string$(pxParts)
readWarning$ = pxWarn$
srcDuration = 0
for i from 1 to pxN
    if px1_'i' > srcDuration
        srcDuration = px1_'i'
    endif
endfor

appendInfoLine: "  ", srcCount$, " notes | ", partsStat$, " part(s) | ",
    ... tempoStat$, " BPM (", tempoSrc$, ")"

nSrc = pxN

# ---- Load into arrays (all transformations work on these) ----
for i from 1 to nSrc
    s0_'i' = px0_'i'
    s1_'i' = px1_'i'
    sp_'i' = pxp_'i'
    sa_'i' = pxa_'i'
    # working copy
    t0_'i' = s0_'i'
    t1_'i' = s1_'i'
    tp_'i' = sp_'i'
    ta_'i' = sa_'i'
    live_'i' = 1
endfor
nN = nSrc

# ===========================================================================
# Stage 2 - Transformations
# ===========================================================================
appendInfoLine: "[2/5] Applying transformations..."

# ---- 1. FILTER ----
nFiltered = 0
for i from 1 to nN
    if live_'i' = 1
        dur = t1_'i' - t0_'i'
        if dur < min_note_duration_s
            live_'i' = 0
            nFiltered = nFiltered + 1
        elsif tp_'i' < lowest_midi or tp_'i' > highest_midi
            live_'i' = 0
            nFiltered = nFiltered + 1
        endif
    endif
endfor
@compact
if nN < 1
    @cleanUpTempFiles
    exitScript: "The filter removed every note. Loosen the duration or register limits."
endif
if nFiltered > 0
    appendInfoLine: "  filter:    removed ", nFiltered, " note(s), ", nN, " remain"
endif

# ---- 2. PITCH ----
nClamped = 0
if invert_mode > 1
    if invert_mode = 3
        pSum = 0
        for i from 1 to nN
            pSum = pSum + tp_'i'
        endfor
        axis = round(pSum / nN)
    else
        axis = invert_axis_midi
    endif
else
    axis = invert_axis_midi
endif

for i from 1 to nN
    p = tp_'i'
    if invert_mode > 1
        p = 2 * axis - p
    endif
    p = p + transpose_semitones
    if p < 0
        p = p + 12 * ceiling((0 - p) / 12)
        nClamped = nClamped + 1
    endif
    if p > 127
        p = p - 12 * ceiling((p - 127) / 12)
        nClamped = nClamped + 1
    endif
    tp_'i' = p
endfor
if invert_mode > 1
    appendInfoLine: "  invert:    about MIDI ", axis
endif
if transpose_semitones <> 0
    appendInfoLine: "  transpose: ", transpose_semitones, " semitones"
endif
if nClamped > 0
    appendInfoLine: "  NOTE:      ", nClamped, " note(s) octave-folded back into 0-127"
endif

# ---- 3. CHORD OPERATIONS ----
# Simultaneity groups: notes whose onsets agree to within groupTol.
groupTol = 0.012
nChordOps = 0
if chord_mode > 1
    @buildGroups
    if chord_mode >= 5 and chord_mode <= 7
        @thinChords
    elsif chord_mode = 8
        @voiceLead
    else
        @arpeggiate
    endif
    @compact
endif

# ---- 4. ORDER ----
if order_mode = 2
    # Retrograde: mirror about the score end. Durations preserved exactly.
    endT = 0
    for i from 1 to nN
        if t1_'i' > endT
            endT = t1_'i'
        endif
    endfor
    for i from 1 to nN
        a = endT - t1_'i'
        b = endT - t0_'i'
        t0_'i' = a
        t1_'i' = b
    endfor
    appendInfoLine: "  order:     retrograde"
elsif order_mode = 3
    @rotateGroups
endif

# ---- 5. TIME ----
if time_scale <> 1.0
    for i from 1 to nN
        t0_'i' = t0_'i' * time_scale
        t1_'i' = t1_'i' * time_scale
    endfor
    appendInfoLine: "  time:      scale ", fixed$(time_scale, 3)
endif
if note_length_scale <> 1.0
    minLen = 0.01
    for i from 1 to nN
        d = (t1_'i' - t0_'i') * note_length_scale
        if d < minLen
            d = minLen
        endif
        t1_'i' = t0_'i' + d
    endfor
    appendInfoLine: "  length:    scale ", fixed$(note_length_scale, 3)
endif

# ---- Result extent ----
outStart = t0_1
outEnd = t1_1
pLo = tp_1
pHi = tp_1
for i from 1 to nN
    if t0_'i' < outStart
        outStart = t0_'i'
    endif
    if t1_'i' > outEnd
        outEnd = t1_'i'
    endif
    if tp_'i' < pLo
        pLo = tp_'i'
    endif
    if tp_'i' > pHi
        pHi = tp_'i'
    endif
endfor
# Normalize the time domain to 0 and give the release tail room to decay.
for i from 1 to nN
    t0_'i' = t0_'i' - outStart
    t1_'i' = t1_'i' - outStart
endfor
outDur = outEnd - outStart + release_ms / 1000 + 0.05
if outDur < 0.2
    outDur = 0.2
endif

appendInfoLine: "  result:    ", nN, " notes | ", fixed$(outDur, 2), " s | MIDI ",
    ... pLo, "-", pHi

# ===========================================================================
# Stage 3 - Additive synthesis
# ===========================================================================
appendInfoLine: "[3/5] Synthesizing (", harmonics, " harmonics)..."

result = Create Sound from formula: scoreName$ + "_OM", 1, 0, outDur,
    ... sampling_rate, "0"

atk = attack_ms / 1000
rel = release_ms / 1000

for i from 1 to nN
    nStart = t0_'i'
    nEnd = t1_'i' + rel
    if nEnd > outDur
        nEnd = outDur
    endif
    freq = 440 * 2 ^ ((tp_'i' - 69) / 12)
    # Above Nyquist a harmonic aliases straight back down as a spurious low
    # tone, so the bank is truncated per note rather than per score.
    kMax = harmonics
    while kMax > 1 and kMax * freq >= sampling_rate / 2
        kMax = kMax - 1
    endwhile

    @bankFormula: freq, kMax, spectral_tilt, nStart
    amp = ta_'i'

    # Trapezoidal attack/release plus exponential decay, all written as a
    # function of (x - start) so no branching is needed: Formula (part) only
    # ever evaluates inside the note's own window.
    env$ = "min(1,(x-" + fixed$(nStart, 6) + ")/" + fixed$(atk, 6) + ")"
        ... + "*min(1,(" + fixed$(nEnd, 6) + "-x)/" + fixed$(rel, 6) + ")"
        ... + "*exp(-" + fixed$(decay_per_second, 6) + "*(x-" + fixed$(nStart, 6) + "))"

    selectObject: result
    Formula (part): nStart, nEnd, 1, 1,
        ... "self + " + fixed$(amp, 6) + "*" + env$ + "*(" + bankFormula.out$ + ")"
endfor

# ---- Attenuate-only peak ceiling ----
# Scale peak would AMPLIFY a quiet render up to the ceiling, erasing the
# dynamic level the note amplitudes established. This only ever turns down.
selectObject: result
rawPeak = Get absolute extremum: 0, 0, "None"
gain = 1
if rawPeak > peak_ceiling and rawPeak > 0
    gain = peak_ceiling / rawPeak
    Formula: "self * " + fixed$(gain, 8)
endif
outPeak = Get absolute extremum: 0, 0, "None"
outRms = Get root-mean-square: 0, 0

appendInfoLine: "  peak ", fixed$(rawPeak, 4), " -> ", fixed$(outPeak, 4),
    ... " (gain ", fixed$(gain, 4), ")"

# ===========================================================================
# Stage 4 - Visualization
# ===========================================================================
appendInfoLine: "[4/5] Drawing..."

if draw_visualization
    Erase all
    axLo = pLo - 2
    axHi = pHi + 2
    for i from 1 to nSrc
        if s0_'i' < 0
            s0_'i' = 0
        endif
    endfor
    srcLo = sp_1
    srcHi = sp_1
    srcEnd = 0
    for i from 1 to nSrc
        if sp_'i' < srcLo
            srcLo = sp_'i'
        endif
        if sp_'i' > srcHi
            srcHi = sp_'i'
        endif
        if s1_'i' > srcEnd
            srcEnd = s1_'i'
        endif
    endfor
    if srcLo - 2 < axLo
        axLo = srcLo - 2
    endif
    if srcHi + 2 > axHi
        axHi = srcHi + 2
    endif
    if axHi - axLo < 12
        axHi = axLo + 12
    endif
    axT = outDur
    if srcEnd > axT
        axT = srcEnd
    endif
    @niceStep: axT, 8
    tStep = niceStep.out

    # === Title ===
    Font size: 14
    Select inner viewport: 0.6, 7.7, 0.05, 0.45
    Axes: 0, 1, 0, 1
    Colour: "{0.20, 0.20, 0.40}"
    @picSafe: "OM Score Transformer v0.3 - " + scoreName$
    Text: 0.5, "centre", 0.5, "half", picSafe.out$
    Colour: "Black"

    # === Original score ===
    Font size: 6
    Select outer viewport: 0, 8, 0.60, 2.30
    Select inner viewport: 0.6, 7.7, 0.70, 2.20
    Axes: 0, axT, axLo, axHi
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, axT, axLo, axHi
    @octaveLines: axLo, axHi, axT
    minW = axT / 900
    for i from 1 to nSrc
        x1 = s0_'i'
        x2 = s1_'i'
        if x2 - x1 < minW
            x2 = x1 + minW
        endif
        Paint rectangle: "{0.55, 0.55, 0.62}", x1, x2, sp_'i' - 0.42, sp_'i' + 0.42
    endfor
    Select inner viewport: 0.6, 7.7, 0.70, 2.20
    Axes: 0, axT, axLo, axHi
    Draw inner box
    Marks bottom every: 1, tStep, "no", "yes", "no"
    @octaveMarks: axLo, axHi
    Select inner viewport: 0.6, 7.7, 0.70, 2.20
    Axes: 0, 1, 0, 1
    Text: 0.01, "left", 1.03, "half", "Original score (" + srcCount$ + " notes)"

    # === Transformed score ===
    Font size: 6
    Select outer viewport: 0, 8, 2.30, 4.00
    Select inner viewport: 0.6, 7.7, 2.40, 3.90
    Axes: 0, axT, axLo, axHi
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, axT, axLo, axHi
    @octaveLines: axLo, axHi, axT
    for i from 1 to nN
        x1 = t0_'i'
        x2 = t1_'i'
        if x2 - x1 < minW
            x2 = x1 + minW
        endif
        a = ta_'i'
        if a > 1
            a = 1
        endif
        if a < 0
            a = 0
        endif
        cr = 0.20 + 0.65 * a
        cg = 0.35 - 0.15 * a
        cb = 0.75 - 0.55 * a
        Paint rectangle: "{" + fixed$(cr, 2) + ", " + fixed$(cg, 2) + ", "
            ... + fixed$(cb, 2) + "}", x1, x2, tp_'i' - 0.42, tp_'i' + 0.42
    endfor
    Select inner viewport: 0.6, 7.7, 2.40, 3.90
    Axes: 0, axT, axLo, axHi
    Draw inner box
    Marks bottom every: 1, tStep, "no", "yes", "no"
    @octaveMarks: axLo, axHi
    Select inner viewport: 0.6, 7.7, 2.40, 3.90
    Axes: 0, 1, 0, 1
    Text: 0.01, "left", 1.03, "half", "Transformed (" + string$(nN) + " notes)"

    # === Rendered waveform ===
    Font size: 6
    Select outer viewport: 0, 8, 4.00, 4.95
    Select inner viewport: 0.6, 7.7, 4.10, 4.85
    wAbs = outPeak
    if wAbs < 1e-6
        wAbs = 1e-6
    endif
    selectObject: result
    Colour: "{0.20, 0.40, 0.75}"
    Draw: 0, axT, -wAbs, wAbs, "no", "curve"
    Colour: "Black"
    Select inner viewport: 0.6, 7.7, 4.10, 4.85
    Axes: 0, axT, -wAbs, wAbs
    Draw inner box
    Marks bottom every: 1, tStep, "no", "yes", "no"
    Select inner viewport: 0.6, 7.7, 4.10, 4.85
    Axes: 0, 1, 0, 1
    Text: 0.01, "left", 1.10, "half", "Rendered waveform"

    # === Spectrogram of the render ===
    Font size: 6
    Select outer viewport: 0, 8, 5.25, 6.60
    Select inner viewport: 0.6, 7.7, 5.35, 6.45
    specMax = sampling_rate / 2
    if specMax > 6000
        specMax = 6000
    endif
    selectObject: result
    To Spectrogram: 0.03, specMax, 0.002, 20, "Gaussian"
    specObj = selected("Spectrogram")
    Paint: 0, axT, 0, specMax, 100, "yes", 50, 6, 0, "no"
    removeObject: specObj
    Select inner viewport: 0.6, 7.7, 5.35, 6.45
    Axes: 0, axT, 0, specMax
    Draw inner box
    Marks bottom every: 1, tStep, "yes", "yes", "no"
    Marks left every: 1, 1000, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    Select inner viewport: 0.6, 7.7, 5.35, 6.45
    Axes: 0, 1, 0, 1
    Text: 0.01, "left", 1.08, "half", "Rendered spectrogram (Hz)"

    # === Summary ===
    Font size: 7
    Select inner viewport: 0.6, 7.7, 7.05, 7.90
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Text: 0.02, "left", 0.90, "half", "Summary:"

    Font size: 6
    Select inner viewport: 0.6, 7.7, 7.05, 7.90
    Axes: 0, 1, 0, 1
    Colour: "{0.30, 0.30, 0.30}"
    @picSafe: "Notes: " + srcCount$ + " -> " + string$(nN) + " | Filtered: "
        ... + string$(nFiltered) + " | Chord ops: " + string$(nChordOps)
        ... + " | Tempo: " + tempoStat$ + " BPM (" + tempoSrc$ + ")"
    Text: 0.02, "left", 0.74, "half", picSafe.out$
    @picSafe: "Chain: " + filterStr$ + " -> " + pitchStr$ + " -> " + chordStr$
        ... + " -> " + orderStr$ + " -> " + timeStr$
    Text: 0.02, "left", 0.58, "half", picSafe.out$
    @picSafe: "Synth: " + string$(harmonics) + " harmonics | tilt "
        ... + fixed$(spectral_tilt, 2) + " | atk " + string$(attack_ms)
        ... + " ms | rel " + string$(release_ms) + " ms | decay "
        ... + fixed$(decay_per_second, 2) + "/s | " + string$(sampling_rate) + " Hz"
    Text: 0.02, "left", 0.42, "half", picSafe.out$
    @picSafe: "Output: " + fixed$(outDur, 2) + " s | peak " + fixed$(rawPeak, 3)
        ... + " -> " + fixed$(outPeak, 3) + " (gain " + fixed$(gain, 3)
        ... + ") | RMS " + fixed$(outRms, 4)
    Text: 0.02, "left", 0.26, "half", picSafe.out$
    if readWarning$ <> "none" and readWarning$ <> "?" and readWarning$ <> ""
        Colour: "{0.80, 0.20, 0.20}"
        @picSafe: "Warn: " + readWarning$
        Text: 0.02, "left", 0.08, "half", picSafe.out$
    endif

    Colour: "Black"
    Select inner viewport: 0.6, 7.7, 7.05, 7.90
    Axes: 0, 1, 0, 1
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
    Select outer viewport: 0, 8, 0, 8
endif

# ===========================================================================
# Stage 5 - Report
# ===========================================================================
appendInfoLine: "[5/5] Done."

@cleanUpTempFiles

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output:        ", scoreName$, "_OM"
appendInfoLine: "Source notes:  ", srcCount$
appendInfoLine: "Result notes:  ", nN
appendInfoLine: "Filtered out:  ", nFiltered
appendInfoLine: "Chord ops:     ", nChordOps
appendInfoLine: "Chain:         ", filterStr$, " -> ", pitchStr$, " -> ", chordStr$,
    ... " -> ", orderStr$, " -> ", timeStr$
appendInfoLine: "Source dur.:   ", fixed$(srcDuration, 3), " s"
appendInfoLine: "Output dur.:   ", fixed$(outDur, 3), " s"
appendInfoLine: "Pitch range:   MIDI ", pLo, " - ", pHi
appendInfoLine: "Harmonics:     ", harmonics, " (tilt ", fixed$(spectral_tilt, 2), ")"
appendInfoLine: "Peak:          ", fixed$(rawPeak, 4), " -> ", fixed$(outPeak, 4),
    ... " (gain ", fixed$(gain, 4), ")"
appendInfoLine: "RMS:           ", fixed$(outRms, 4)
if readWarning$ <> "none" and readWarning$ <> "?" and readWarning$ <> ""
    appendInfoLine: "WARNING:       ", readWarning$
endif

selectObject: result
if play_result
    Play
endif

# ===========================================================================
# Procedures
# ===========================================================================

# NOTE ON INDEXING INSIDE PROCEDURES
# Praat's 'x' interpolation does NOT resolve procedure-local (dotted)
# variables: arr_'.k' silently yields nothing rather than erroring, so an
# array loop written with .k reads garbage. Nor does it accept an expression
# in the quotes - arr_'j+1' fails and the index must be precomputed. Both
# verified on 6.4.06. Every array index below is therefore a plain global
# (z-prefixed to keep it out of the main body's namespace) and every
# neighbour index is computed into its own variable first.

# Drop every note whose live flag is 0, closing the gaps in the arrays.
procedure compact
    zk = 0
    for zi from 1 to nN
        if live_'zi' = 1
            zk = zk + 1
            zva = t0_'zi'
            zvb = t1_'zi'
            zvc = tp_'zi'
            zvd = ta_'zi'
            t0_'zk' = zva
            t1_'zk' = zvb
            tp_'zk' = zvc
            ta_'zk' = zvd
            live_'zk' = 1
        endif
    endfor
    nN = zk
endproc

# Sort by onset, then descending pitch, and mark simultaneity groups.
# Praat's "and" is not guaranteed to short-circuit, so the inner loop uses an
# explicit flag rather than "while zj >= 1 and t0_'zj' > ..." - the latter
# would evaluate t0_0 on the last pass.
procedure buildGroups
    for zi from 2 to nN
        za = t0_'zi'
        zb = t1_'zi'
        zc = tp_'zi'
        zd = ta_'zi'
        zj = zi - 1
        zgo = 1
        while zgo = 1
            if zj < 1
                zgo = 0
            else
                zprev = t0_'zj'
                zpp = tp_'zj'
                zswap = 0
                if zprev > za + 1e-12
                    zswap = 1
                elsif abs(zprev - za) <= 1e-12 and zpp < zc
                    zswap = 1
                endif
                if zswap = 1
                    zj1 = zj + 1
                    zvb = t1_'zj'
                    zvd = ta_'zj'
                    t0_'zj1' = zprev
                    t1_'zj1' = zvb
                    tp_'zj1' = zpp
                    ta_'zj1' = zvd
                    zj = zj - 1
                else
                    zgo = 0
                endif
            endif
        endwhile
        zj1 = zj + 1
        t0_'zj1' = za
        t1_'zj1' = zb
        tp_'zj1' = zc
        ta_'zj1' = zd
    endfor

    nGroups = 0
    zi = 1
    while zi <= nN
        nGroups = nGroups + 1
        gStart_'nGroups' = zi
        zj = zi
        zbase = t0_'zi'
        zgo = 1
        while zgo = 1
            if zj >= nN
                zgo = 0
            else
                zn = zj + 1
                zt = t0_'zn'
                if zt - zbase <= groupTol
                    zj = zj + 1
                else
                    zgo = 0
                endif
            endif
        endwhile
        gCount_'nGroups' = zj - zi + 1
        zi = zj + 1
    endwhile
endproc

# Keep only Keep_per_chord members of each group. Groups are sorted high to
# low inside the group, so "highest" is the head of the run.
procedure thinChords
    for zg from 1 to nGroups
        zs = gStart_'zg'
        zc = gCount_'zg'
        if zc > keep_per_chord
            ztop = floor(keep_per_chord / 2)
            zbot = keep_per_chord - ztop
            for zk from 0 to zc - 1
                zidx = zs + zk
                zkeep = 0
                if chord_mode = 5
                    if zk < keep_per_chord
                        zkeep = 1
                    endif
                elsif chord_mode = 6
                    if zk >= zc - keep_per_chord
                        zkeep = 1
                    endif
                else
                    if zk < ztop
                        zkeep = 1
                    elsif zk >= zc - zbot
                        zkeep = 1
                    endif
                endif
                if zkeep = 0
                    live_'zidx' = 0
                    nChordOps = nChordOps + 1
                endif
            endfor
        endif
    endfor
endproc

# Offset chord members in time. The chord's END is preserved: a member that
# enters late is shortened, never pushed past the chord, so arpeggiation can
# never lengthen the piece.
procedure arpeggiate
    zstride = arpeggio_stride_ms / 1000
    for zg from 1 to nGroups
        zs = gStart_'zg'
        zc = gCount_'zg'
        if zc > 1
            zgEnd = 0
            for zk from 0 to zc - 1
                zidx = zs + zk
                zte = t1_'zidx'
                if zte > zgEnd
                    zgEnd = zte
                endif
            endfor
            for zk from 0 to zc - 1
                zidx = zs + zk
                if chord_mode = 2
                    # up: the group runs high -> low, so reverse the rank
                    zorder = zc - 1 - zk
                elsif chord_mode = 3
                    zorder = zk
                else
                    if zk mod 2 = 0
                        zorder = zc - 1 - floor(zk / 2)
                    else
                        zorder = floor(zk / 2)
                    endif
                endif
                zt0 = t0_'zidx'
                zt1 = t1_'zidx'
                znew = zt0 + zorder * zstride
                if znew > zgEnd - 0.02
                    znew = zgEnd - 0.02
                endif
                if znew < zt0
                    znew = zt0
                endif
                if zt1 < znew + 0.02
                    zt1 = znew + 0.02
                endif
                t0_'zidx' = znew
                t1_'zidx' = zt1
                nChordOps = nChordOps + 1
            endfor
        endif
    endfor
endproc

# Re-octave each chord member to the octave nearest the previous chord's
# centre. Pitch CLASS is never changed, so the harmony is untouched.
procedure voiceLead
    zprev = undefined
    for zg from 1 to nGroups
        zs = gStart_'zg'
        zc = gCount_'zg'
        if zprev <> undefined
            for zk from 0 to zc - 1
                zidx = zs + zk
                zp = tp_'zidx'
                zbest = zp
                zbestD = abs(zp - zprev)
                for zoct from -3 to 3
                    zcand = zp + 12 * zoct
                    if zcand >= 0 and zcand <= 127
                        zd = abs(zcand - zprev)
                        if zd < zbestD
                            zbestD = zd
                            zbest = zcand
                        endif
                    endif
                endfor
                if zbest <> zp
                    tp_'zidx' = zbest
                    nChordOps = nChordOps + 1
                endif
            endfor
        endif
        zsum = 0
        for zk from 0 to zc - 1
            zidx = zs + zk
            zsum = zsum + tp_'zidx'
        endfor
        zprev = zsum / zc
    endfor
endproc

# Rotate onset GROUPS together with their inter-onset intervals, then re-lay
# them end to end. This preserves the ONSET GRID (the IOI sequence of the
# result is a rotation of the original) but NOT the total length: a note held
# longer than its own group's IOI carries its duration with it, so its tail
# extends past the old end when that group moves later. See the header.
procedure rotateGroups
    @buildGroups
    if nGroups > 1
        zend = 0
        for zi from 1 to nN
            zte = t1_'zi'
            if zte > zend
                zend = zte
            endif
        endfor
        for zg from 1 to nGroups
            zs = gStart_'zg'
            zoff = t0_'zs'
            goff_'zg' = zoff
            if zg < nGroups
                zg1 = zg + 1
                zns = gStart_'zg1'
                znt = t0_'zns'
                ioi_'zg' = znt - zoff
            else
                ioi_'zg' = zend - zoff
            endif
        endfor

        zr = rotate_steps mod nGroups
        if zr < 0
            zr = zr + nGroups
        endif

        zcursor = 0
        for zk from 0 to nGroups - 1
            zg = ((zk + zr) mod nGroups) + 1
            zs = gStart_'zg'
            zc = gCount_'zg'
            zoff = goff_'zg'
            zshift = zcursor - zoff
            for zm from 0 to zc - 1
                zidx = zs + zm
                zt0 = t0_'zidx'
                zt1 = t1_'zidx'
                t0_'zidx' = zt0 + zshift
                t1_'zidx' = zt1 + zshift
            endfor
            zcursor = zcursor + ioi_'zg'
        endfor
        appendInfoLine: "  order:     rotate ", zr, " of ", nGroups, " groups"
    endif
endproc

# Build the harmonic-bank part of a note's formula string.
# Harmonics carry a Schroeder phase, phi_k = -pi*k*(k-1)/N, instead of all
# starting at zero. With zero phase every partial peaks together, so a note's
# crest factor is sum(1/k^tilt) - 2.45 at 6 harmonics - and a chord multiplies
# that again. Since the output is normalized by an attenuate-only ceiling, a
# high crest factor is paid for directly in loudness: the same music comes
# back quieter for no musical reason. Schroeder phase is the standard
# minimum-crest-factor choice and is deterministic, so renders stay
# reproducible without needing a seed. It does not change the spectrum.
procedure bankFormula: .freq, .kMax, .tilt, .t0
    .out$ = ""
    for .k from 1 to .kMax
        .a = 1 / (.k ^ .tilt)
        .ph = -pi * .k * (.k - 1) / .kMax
        if .k > 1
            .out$ = .out$ + "+"
        endif
        .out$ = .out$ + fixed$(.a, 6) + "*sin(2*pi*" + fixed$(.freq * .k, 6)
            ... + "*(x-" + fixed$(.t0, 6) + ")+" + fixed$(.ph, 6) + ")"
    endfor
endproc

procedure octaveLines: .lo, .hi, .t
    Colour: "{0.85, 0.85, 0.90}"
    for .m from .lo to .hi
        if .m mod 12 = 0
            Draw line: 0, .m, .t, .m
        endif
    endfor
    Colour: "Black"
endproc

procedure octaveMarks: .lo, .hi
    for .m from .lo to .hi
        if .m mod 12 = 0
            @midiName: .m
            @picSafe: midiName.out$
            One mark left: .m, "no", "yes", "no", picSafe.out$
        endif
    endfor
endproc

procedure parseStatLine: .text$, .key$
    .result$ = "?"
    .pos = index(.text$, .key$)
    if .pos > 0
        .start = .pos + length(.key$)
        .rest$ = mid$(.text$, .start, length(.text$) - .start + 1)
        .nlPos = index(.rest$, newline$)
        if .nlPos > 0
            .result$ = left$(.rest$, .nlPos - 1)
        else
            .result$ = .rest$
        endif
    endif
endproc

# Picture-window markup escapes. "#" is BOLD, "_" SUBSCRIPT, "%" ITALIC and
# "^" SUPERSCRIPT, and each is SWALLOWED raw - "C#4" draws as a bold "C4".
# One trailing space is correct in every position including end-of-string
# (rendered and checked on 6.4.06); two leave a visible gap.
procedure picSafe: .s$
    .out$ = replace$(.s$, "\", "\bs ", 0)
    .out$ = replace$(.out$, "#", "\# ", 0)
    .out$ = replace$(.out$, "_", "\_ ", 0)
    .out$ = replace$(.out$, "%", "\% ", 0)
    .out$ = replace$(.out$, "^", "\^ ", 0)
endproc

procedure niceStep: .span, .target
    .raw = .span / .target
    .mag = 10 ^ floor(log10(.raw))
    .norm = .raw / .mag
    if .norm < 1.5
        .out = 1 * .mag
    elsif .norm < 3
        .out = 2 * .mag
    elsif .norm < 7
        .out = 5 * .mag
    else
        .out = 10 * .mag
    endif
endproc

procedure midiName: .midi
    .pc = .midi mod 12
    .oct = floor(.midi / 12) - 1
    if .pc = 0
        .n$ = "C"
    elsif .pc = 1
        .n$ = "C#"
    elsif .pc = 2
        .n$ = "D"
    elsif .pc = 3
        .n$ = "D#"
    elsif .pc = 4
        .n$ = "E"
    elsif .pc = 5
        .n$ = "F"
    elsif .pc = 6
        .n$ = "F#"
    elsif .pc = 7
        .n$ = "G"
    elsif .pc = 8
        .n$ = "G#"
    elsif .pc = 9
        .n$ = "A"
    elsif .pc = 10
        .n$ = "A#"
    else
        .n$ = "B"
    endif
    .out$ = .n$ + string$(.oct)
endproc

procedure parseMusicXML: .file$, .tempoOverride
    .raw$ = readFile$(.file$)
    # Praat has no index() with a start offset, so a scan of the raw string
    # would be O(n^2) via repeated mid$. Instead put every tag on its own line
    # and read the result back as a Strings object: one pass, O(n).
    .norm$ = replace$(.raw$, "<", newline$ + "<", 0)
    writeFile: tempTags$, .norm$
    Read Strings from raw text file: tempTags$
    pxStrings = selected("Strings")
    deleteFile: tempTags$
    .nLines = Get number of strings

    pxN = 0
    pxParts = 0
    pxTempo = 0
    pxWarn$ = "none"
    pxTempoSrc$ = "score"
    pxOpen = 0

    divisions = 1
    cursor = 0
    prevOnset = 0
    partIndex = -1
    mode = 0
    inNote = 0
    nDur = 0
    nStep$ = ""
    nAlter = 0
    nOct = 4
    nVoice = 1
    nChord = 0
    nRest = 0
    nGrace = 0
    nTieStart = 0
    nTieStop = 0
    nAmp = 0.7

    for li from 1 to .nLines
        selectObject: pxStrings
        line$ = Get string: li
        if left$(line$, 1) = "<"

            if left$(line$, 6) = "<part " and left$(line$, 11) <> "<part-name>"
                partIndex = partIndex + 1
                pxParts = pxParts + 1
                cursor = 0
                prevOnset = 0
                divisions = 1

            elsif left$(line$, 11) = "<divisions>"
                divisions = extractNumber(line$, ">")
                if divisions <= 0
                    divisions = 1
                endif

            elsif left$(line$, 12) = "<per-minute>"
                if pxTempo <= 0
                    pxTempo = extractNumber(line$, ">")
                endif

            elsif left$(line$, 7) = "<sound "
                clean$ = replace$(line$, """", " ", 0)
                cand = extractNumber(clean$, "tempo=")
                if cand <> undefined and cand > 0 and pxTempo <= 0
                    pxTempo = cand
                endif

            elsif left$(line$, 7) = "<backup"
                mode = 1
            elsif left$(line$, 8) = "<forward"
                mode = 2

            elsif left$(line$, 6) = "<note>" or left$(line$, 6) = "<note "
                mode = 3
                inNote = 1
                nDur = 0
                nStep$ = ""
                nAlter = 0
                nOct = 4
                nVoice = 1
                nChord = 0
                nRest = 0
                nGrace = 0
                nTieStart = 0
                nTieStop = 0
                nAmp = 0.7
                if index(line$, "dynamics=") > 0
                    clean$ = replace$(line$, """", " ", 0)
                    dy = extractNumber(clean$, "dynamics=")
                    if dy <> undefined and dy > 0
                        nAmp = dy / 100
                        if nAmp > 1
                            nAmp = 1
                        endif
                    endif
                endif

            elsif left$(line$, 6) = "<chord"
                nChord = 1
            elsif left$(line$, 5) = "<rest"
                nRest = 1
            elsif left$(line$, 6) = "<grace"
                nGrace = 1
            elsif left$(line$, 6) = "<step>"
                nStep$ = extractWord$(line$, ">")
            elsif left$(line$, 7) = "<alter>"
                nAlter = extractNumber(line$, ">")
            elsif left$(line$, 8) = "<octave>"
                nOct = extractNumber(line$, ">")
            elsif left$(line$, 7) = "<voice>"
                nVoice = extractNumber(line$, ">")

            elsif left$(line$, 5) = "<tie "
                # "<tied " is the NOTATIONS element and must not be counted:
                # it duplicates every tie and would double the matching.
                if index(line$, "start") > 0
                    nTieStart = 1
                endif
                if index(line$, "stop") > 0
                    nTieStop = 1
                endif

            elsif left$(line$, 10) = "<duration>"
                # Convert to QUARTER NOTES immediately, using the divisions in
                # force right now. Accumulating the cursor in raw division
                # units breaks the moment <divisions> changes mid-part: the
                # earlier total is silently reinterpreted at the new scale.
                # Measured on a score that switched 4 -> 24 at bar 2, a note
                # that belongs at 4.0 s landed at 0.67 s.
                dv = extractNumber(line$, ">") / divisions
                if mode = 1
                    cursor = cursor - dv
                elsif mode = 2
                    cursor = cursor + dv
                else
                    nDur = dv
                endif

            elsif left$(line$, 7) = "</note>"
                @emitNote
                inNote = 0
                mode = 0
            elsif left$(line$, 9) = "</backup>"
                mode = 0
            elsif left$(line$, 10) = "</forward>"
                mode = 0
            endif
        endif
    endfor

    removeObject: pxStrings

    if .tempoOverride > 0
        pxTempo = .tempoOverride
        pxTempoSrc$ = "form override"
    endif
    if pxTempo <= 0
        pxTempo = 120
        pxTempoSrc$ = "default 120"
        pxWarn$ = "no tempo in score; assumed 120 BPM"
    endif

    # divisions -> seconds, applied after the whole file is read so a tempo
    # mark appearing late still governs the whole score
    secPerQuarter = 60 / pxTempo
    for i from 1 to pxN
        px0_'i' = px0_'i' * secPerQuarter
        px1_'i' = px1_'i' * secPerQuarter
    endfor
    if pxOpen > 0
        pxWarn$ = string$(pxOpen) + " unmatched tie(s); treated as separate notes"
    endif
endproc

procedure emitNote
    if inNote = 1 and nGrace = 0
        # A <chord/> note sounds with the PREVIOUS note and must not advance
        # the cursor - the first note of the chord already did.
        if nChord = 1
            onsetQ = prevOnset
        else
            onsetQ = cursor
            cursor = cursor + nDur
            prevOnset = onsetQ
        endif

        if nRest = 0 and nStep$ <> ""
            @stepToSemis: nStep$
            midi = (nOct + 1) * 12 + stepToSemis.out + nAlter
            startQ = onsetQ
            endQ = onsetQ + nDur
            key = partIndex * 100000 + nVoice * 1000 + midi

            matched = 0
            if nTieStop = 1 and pxOpen > 0
                for k from 1 to pxOpen
                    if matched = 0
                        if pxOkey_'k' = key
                            idx = pxOidx_'k'
                            px1_'idx' = endQ
                            matched = 1
                            hitK = k
                        endif
                    endif
                endfor
                if matched = 1 and nTieStart = 0
                    # close: shuffle the tail of the open list down one
                    for k from hitK to pxOpen - 1
                        k1 = k + 1
                        pxOkey_'k' = pxOkey_'k1'
                        pxOidx_'k' = pxOidx_'k1'
                    endfor
                    pxOpen = pxOpen - 1
                endif
            endif

            if matched = 0
                pxN = pxN + 1
                px0_'pxN' = startQ
                px1_'pxN' = endQ
                pxp_'pxN' = midi
                pxa_'pxN' = nAmp
                pxv_'pxN' = partIndex
                if nTieStart = 1
                    pxOpen = pxOpen + 1
                    pxOkey_'pxOpen' = key
                    pxOidx_'pxOpen' = pxN
                endif
            endif
        endif
    endif
endproc

procedure stepToSemis: .s$
    if .s$ = "C"
        .out = 0
    elsif .s$ = "D"
        .out = 2
    elsif .s$ = "E"
        .out = 4
    elsif .s$ = "F"
        .out = 5
    elsif .s$ = "G"
        .out = 7
    elsif .s$ = "A"
        .out = 9
    else
        .out = 11
    endif
endproc
