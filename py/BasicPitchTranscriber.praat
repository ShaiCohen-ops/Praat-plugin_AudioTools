# ============================================================
# Praat AudioTools - BasicPitchTranscriber.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2026)
#
# Changelog v0.4:
#   - Merge_repeated_notes: rejoins notes the MODEL split into repeated
#     onsets. Basic Pitch analyses ~2 s windows and re-decides note identity
#     in each, so a sustained note is re-attacked every 1.6400907 s (hop is
#     derived from the installed package, not hard-coded).
#     "window artifacts only" is the default and merges ONLY a repeat that
#     lands on that grid, is contiguous, and is no louder than the note
#     before it - all three. Verified against 15 strikes of one pitch every
#     0.40 s: all 15 survive. "any gap under N ms" collapsed that same test
#     to 1 note, so it is offered but never the default.
#   - FORM ARGUMENT ORDER CHANGED again: two new fields after Melodia_trick.
#
# Changelog v0.3:
#   - The MusicXML is now also kept as a Praat Strings object named
#     <Sound>_musicxml, so the score stays inside Praat and can be handed
#     straight to OM_Score_Transformer with no file on disk in between.
#     Raw file lines, so "Save as raw text file" reproduces the original.
#   - FORM ARGUMENT ORDER CHANGED: Create_musicxml_Strings is a new field
#     after Print_musicxml_to_info. Existing runScript calls need the extra
#     argument.
#
# Changelog v0.2:
#   - Engine v0.2 fixes over-full bars in the music21 backend; see the Python
#     header. Nothing in the Praat protocol changed.
#   - Time-axis ticks snap to a 1/2/5 x 10^k step via @niceStep. A step of
#     duration/8 printed labels like 0.6569 / 1.314 / 1.971.
#   - One mark left/bottom: the second argument is "write number", not "draw
#     tick". Every pitch and duration label was being drawn on top of the
#     numeric axis position.
#   - picSafe escapes take ONE trailing space, not two. Rendered at all four
#     positions on 6.4.06: one space is correct everywhere including
#     end-of-string; two leave a visible gap ("C# 6" instead of "C#6").
#
# Changelog v0.1:
#   - Initial release. Front end for basic_pitch_transcriber.py: exports the
#     selected Sound, runs Spotify's Basic Pitch (ICASSP 2022) polyphonic
#     transcriber through the house nocheck runSubprocess pattern, and brings
#     back a MusicXML score, a MIDI file and a note table.
#   - showPyLog: on failure the engine's own log tail is printed to the Info
#     window instead of a blind "check the terminal".
#   - Dependency probe runs the engine's own --selftest, which short-circuits
#     before argparse and uses importlib.util.find_spec rather than importing
#     basic_pitch: the probe costs a bare interpreter start instead of a
#     TensorFlow / ONNX model load, which would otherwise be paid twice.
#   - Notes arrive as a CSV read into a Table object, not as note_0=/note_1=
#     keys in stats.txt. The parseStatLine pattern re-scans the whole stats
#     string per key, so a 2000-note dump would be O(rows x length).
#   - Praat 7.0 full-trust guard: this script writes and deletes files, both
#     of which abort a 7.0 run without --FULL-TRUST. askForTrust() is called
#     behind a praatVersion test and is inert on 6.x.
#   - Picture-text sanitizer: note names contain "#", which is BOLD markup in
#     the Picture window and is SILENTLY SWALLOWED - "C#4" draws as a bold
#     "C4", losing the accidental. Verified on 6.4.06; "\# " renders the real
#     character, so every generated label is routed through @picSafe.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Basic Pitch Polyphonic Transcriber (Sound -> MusicXML)
#
#   Runs the selected Sound through Spotify's Basic Pitch, a lightweight
#   instrument-agnostic polyphonic transcription model, and returns a notated
#   score. The complete MusicXML is printed to the Info window and can be
#   saved to a path of your choosing; the detected notes are also offered back
#   as a Praat TextGrid, one interval tier per voice layer, so the
#   transcription can be edited as a score inside Praat itself.
#
#   Onset threshold, frame threshold and minimum note length are the model's
#   three sensitivity controls and are exposed directly, with presets for
#   common material.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
#   Model: Bittner, R. M., Bosch, J. J., Rubinstein, D., Meseguer-Brocal, G.,
#   & Ewert, S. (2022). A lightweight instrument-agnostic model for polyphonic
#   note transcription and multipitch estimation. ICASSP 2022.
#
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")

# ---- PRAAT 7.0 FULL-TRUST GUARD ----
# 7.0 aborts "Save as WAV file", "deleteFile" and subprocess calls without
# full trust. askForTrust() raises Praat's own permission dialog and grants
# trust for the rest of the run; it returns 1 automatically with no GUI, and
# the guard keeps 6.x from ever evaluating it.
if praatVersion >= 7000
    trusted = askForTrust()
    if not trusted
        exitScript: "This script needs permission to write temporary files."
    endif
endif

# ---- OS-Specific Python Discovery ----
if macintosh
    if fileReadable("/opt/homebrew/bin/python3")
        pythonCmd$ = "/opt/homebrew/bin/python3"
    elsif fileReadable("/Library/Frameworks/Python.framework/Versions/3.14/bin/python3")
        pythonCmd$ = "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3"
    elsif fileReadable("/usr/local/bin/python3")
        pythonCmd$ = "/usr/local/bin/python3"
    else
        pythonCmd$ = "python3"
    endif
elsif windows
    pythonCmd$ = "python"
else
    pythonCmd$ = "python3"
endif

# ---- PATHS ----
pluginDir$    = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/basic_pitch_transcriber.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/basic_pitch_transcriber.py"
endif

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: basic_pitch_transcriber.py" + newline$
        ... + "Expected at: " + pluginDir$ + "py/" + newline$
        ... + "or next to this script."
endif

tempInput$   = temporaryDirectory$ + "/temp_bp_input.wav"
tempScore$   = temporaryDirectory$ + "/temp_bp_score.musicxml"
tempMidi$    = temporaryDirectory$ + "/temp_bp_score.mid"
tempNotes$   = temporaryDirectory$ + "/temp_bp_notes.csv"
tempStats$   = temporaryDirectory$ + "/temp_bp_stats.txt"
tempLog$     = temporaryDirectory$ + "/temp_bp_log.txt"
probeMarker$ = temporaryDirectory$ + "/temp_bp_probe.txt"

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(tempInput$)
        deleteFile: tempInput$
    endif
    if fileReadable(tempScore$)
        deleteFile: tempScore$
    endif
    if fileReadable(tempMidi$)
        deleteFile: tempMidi$
    endif
    if fileReadable(tempNotes$)
        deleteFile: tempNotes$
    endif
    if fileReadable(tempStats$)
        deleteFile: tempStats$
    endif
    if fileReadable(tempLog$)
        deleteFile: tempLog$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
endproc

@cleanUpTempFiles

# ---- FORM ----
form Basic Pitch Transcriber v0.4
    comment Basic Pitch (ICASSP 2022) sensitivity - lower thresholds find more notes
    optionmenu Preset: 3
        option Custom
        option Solo instrument (clean)
        option Polyphonic / piano
        option Sensitive (quiet or noisy)
        option Sparse (fewest notes)
    real Onset_threshold 0.5
    real Frame_threshold 0.3
    positive Minimum_note_length_ms 127.7
    comment Pitch range in Hz (0 = model default, full range)
    real Minimum_frequency_Hz 0
    real Maximum_frequency_Hz 0
    boolean Melodia_trick 1
    comment Rejoin notes the model split into repeated onsets
    optionmenu Merge_repeated_notes: 2
        option off
        option window artifacts only (safe)
        option any gap under N ms (destroys real repeats)
    positive Merge_gap_ms 120
    comment Notation
    positive Score_tempo_BPM 120
    optionmenu Quantize_grid: 3
        option 1/4
        option 1/8
        option 1/16
        option 1/32
    optionmenu Notation_backend: 1
        option auto (music21 if installed)
        option music21
        option builtin
    comment Output
    boolean Save_musicxml_to_file 0
    sentence Output_file_path
    boolean Print_musicxml_to_info 1
    boolean Create_musicxml_Strings 1
    boolean Create_note_TextGrid 1
    boolean Draw_visualization 1
    boolean Play_input_sound 0
endform

# ---- PRESET APPLICATION ----
if preset = 2
    # Solo instrument - a clean monophonic or near-monophonic line. Higher
    # thresholds, longer minimum note: suppresses the model's tendency to
    # split a sustained tone into repeated notes.
    onset_threshold = 0.60
    frame_threshold = 0.40
    minimum_note_length_ms = 120
    presetName$ = "SoloInstrument"
elsif preset = 3
    # Polyphonic / piano - the model's own published defaults, with a shorter
    # minimum note so inner-voice attacks are not merged.
    onset_threshold = 0.50
    frame_threshold = 0.30
    minimum_note_length_ms = 58
    presetName$ = "PolyphonicPiano"
elsif preset = 4
    # Sensitive - quiet, reverberant or noisy material. Expect false positives;
    # this is the setting to use when notes are being MISSED.
    onset_threshold = 0.30
    frame_threshold = 0.20
    minimum_note_length_ms = 80
    presetName$ = "Sensitive"
elsif preset = 5
    # Sparse - only the most confident events. Useful for extracting a
    # skeletal reduction rather than a faithful transcription.
    onset_threshold = 0.75
    frame_threshold = 0.55
    minimum_note_length_ms = 250
    presetName$ = "Sparse"
else
    presetName$ = "Custom"
endif

if merge_repeated_notes = 1
    mergeStr$ = "off"
elsif merge_repeated_notes = 3
    mergeStr$ = "gap"
else
    mergeStr$ = "grid"
endif

# ---- CLAMP VALUES ----
# The engine clamps again and reports what it changed; this pair keeps the
# Info header honest about what was actually requested.
if onset_threshold < 0.05
    onset_threshold = 0.05
endif
if onset_threshold > 0.95
    onset_threshold = 0.95
endif
if frame_threshold < 0.05
    frame_threshold = 0.05
endif
if frame_threshold > 0.95
    frame_threshold = 0.95
endif
if minimum_note_length_ms < 10
    minimum_note_length_ms = 10
endif
if minimum_frequency_Hz < 0
    minimum_frequency_Hz = 0
endif
if maximum_frequency_Hz < 0
    maximum_frequency_Hz = 0
endif
if score_tempo_BPM < 20
    score_tempo_BPM = 20
endif
if score_tempo_BPM > 400
    score_tempo_BPM = 400
endif

if quantize_grid = 1
    gridStr$ = "1/4"
elsif quantize_grid = 2
    gridStr$ = "1/8"
elsif quantize_grid = 4
    gridStr$ = "1/32"
else
    gridStr$ = "1/16"
endif

if notation_backend = 2
    backendStr$ = "music21"
elsif notation_backend = 3
    backendStr$ = "builtin"
else
    backendStr$ = "auto"
endif

outPath$ = output_file_path$
if save_musicxml_to_file and outPath$ = ""
    exitScript: "Save to file is on but no output path was given." + newline$
        ... + "Enter a full path ending in .musicxml, or turn the option off."
endif

# ---- CAPTURE ORIGINAL STATS ----
selectObject: sound
dur       = Get total duration
tmin      = Get start time
tmax      = Get end time
sr        = Get sampling frequency
nChannels = Get number of channels

# ---- INFO ----
clearinfo
writeInfoLine:  "=== Basic Pitch Transcriber v0.4 ==="
appendInfoLine: "Input: ", soundName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Duration:      ", fixed$(dur, 2), " s | SR: ", sr, " Hz | Channels: ", nChannels
appendInfoLine: "Onset thr.:    ", fixed$(onset_threshold, 2)
appendInfoLine: "Frame thr.:    ", fixed$(frame_threshold, 2)
appendInfoLine: "Min note len.: ", fixed$(minimum_note_length_ms, 1), " ms"
if minimum_frequency_Hz > 0 or maximum_frequency_Hz > 0
    appendInfoLine: "Pitch range:   ", fixed$(minimum_frequency_Hz, 1), " - ", fixed$(maximum_frequency_Hz, 1), " Hz"
else
    appendInfoLine: "Pitch range:   model default (full range)"
endif
appendInfoLine: "Tempo / grid:  ", fixed$(score_tempo_BPM, 0), " BPM | ", gridStr$
appendInfoLine: "Notation:      ", backendStr$
appendInfoLine: ""

# ===========================================================================
# Stage 1 - Detect Python Dependencies
# ===========================================================================
appendInfoLine: "[1/5] Detecting Python dependencies..."

# The engine's own --selftest handles this: it short-circuits before argparse
# and uses find_spec instead of importing, so this probe does NOT pay for the
# TensorFlow / ONNX model load that "import basic_pitch" triggers.
nocheck runSubprocess: pythonCmd$, pythonScript$, "--selftest", probeMarker$

if not fileReadable(probeMarker$)
    @cleanUpTempFiles
    exitScript: "Python was not found, or could not run the engine." + newline$
        ... + "Tried: " + pythonCmd$ + newline$
        ... + "Install with: pip install basic-pitch music21"
endif

probeText$ = readFile$(probeMarker$)
deleteFile: probeMarker$

@parseStatLine: probeText$, "missing="
missingPkgs$ = parseStatLine.result$
@parseStatLine: probeText$, "optional="
optionalPkgs$ = parseStatLine.result$
@parseStatLine: probeText$, "python="
pyVersion$ = parseStatLine.result$

if missingPkgs$ <> "ok" and missingPkgs$ <> "?"
    @cleanUpTempFiles
    exitScript: "Missing Python packages: " + missingPkgs$ + newline$
        ... + "Install with: pip install basic-pitch music21"
endif

appendInfoLine: "  Python ", pyVersion$, " at ", pythonCmd$
appendInfoLine: "  Optional modules present: ", optionalPkgs$
if backendStr$ = "music21" and index(optionalPkgs$, "music21") = 0
    appendInfoLine: "  NOTE: music21 was requested but is not installed;"
    appendInfoLine: "        the engine will fall back to its built-in writer."
endif

# ===========================================================================
# Stage 2 - Export Sound
# ===========================================================================
appendInfoLine: "[2/5] Exporting temp WAV..."

selectObject: sound
Save as WAV file: tempInput$

if not fileReadable(tempInput$)
    @cleanUpTempFiles
    exitScript: "Could not write the temporary WAV file to:" + newline$ + tempInput$
endif

# ===========================================================================
# Stage 3 - Call Python
# ===========================================================================
appendInfoLine: "[3/5] Running Basic Pitch..."
appendInfoLine: "  Praat will be busy until the model finishes"
appendInfoLine: "  (first run also downloads / warms the model)."

# Remove any stale output from a PREVIOUS run before calling Python, so
# fileReadable below is a real success test rather than a leftover.
if fileReadable(tempScore$)
    deleteFile: tempScore$
endif
if fileReadable(tempStats$)
    deleteFile: tempStats$
endif
if fileReadable(tempNotes$)
    deleteFile: tempNotes$
endif

# no-shell call with separate arguments (house pattern); a runSystem shell
# string breaks on Windows paths containing spaces.
nocheck runSubprocess: pythonCmd$, pythonScript$,
    ... tempInput$, tempScore$, tempStats$,
    ... "--onset_threshold", fixed$(onset_threshold, 4),
    ... "--frame_threshold", fixed$(frame_threshold, 4),
    ... "--minimum_note_length_ms", fixed$(minimum_note_length_ms, 2),
    ... "--minimum_frequency_hz", fixed$(minimum_frequency_Hz, 2),
    ... "--maximum_frequency_hz", fixed$(maximum_frequency_Hz, 2),
    ... "--melodia_trick", string$(melodia_trick),
    ... "--merge_mode", mergeStr$,
    ... "--merge_gap_ms", fixed$(merge_gap_ms, 2),
    ... "--multiple_pitch_bends", "0",
    ... "--tempo_bpm", fixed$(score_tempo_BPM, 2),
    ... "--quantize_grid", gridStr$,
    ... "--notation_backend", backendStr$,
    ... "--work_title", soundName$,
    ... "--midi_out", tempMidi$,
    ... "--notes_csv", tempNotes$,
    ... "--log_file", tempLog$,
    ... "--cleanup"

if not fileReadable(tempScore$) or not fileReadable(tempStats$)
    # showPyLog: surface the engine's own account of what went wrong
    if fileReadable(tempLog$)
        logText$ = readFile$(tempLog$)
        appendInfoLine: ""
        appendInfoLine: "--- Python engine log ---"
        appendInfoLine: logText$
        appendInfoLine: "-------------------------"
    endif
    @cleanUpTempFiles
    exitScript: "Basic Pitch transcription failed." + newline$
        ... + "See the engine log above (Info window)."
endif

# ===========================================================================
# Stage 4 - Read Stats
# ===========================================================================
appendInfoLine: "[4/5] Reading results..."

noteCount$      = "?"
polyMax$        = "?"
voicesUsed$     = "?"
unplaced$       = "0"
pitchMinName$   = "?"
pitchMaxName$   = "?"
noteDurMean$    = "?"
noteDurMin$     = "?"
noteDurMax$     = "?"
notesPerSec$    = "?"
ampMean$        = "?"
backendUsed$    = "?"
measures$       = "?"
truncated$      = "0"
xmlBytes$       = "?"
predictSec$     = "?"
notateSec$      = "?"
warningStat$    = ""
dumpTruncated$  = "no"

pitchMinMidi = 0
pitchMaxMidi = 0
nNotes   = 0
nPolyPts = 0
nHistPts = 0
histLo   = 0

statsText$ = readFile$(tempStats$)

@parseStatLine: statsText$, "note_count="
noteCount$ = parseStatLine.result$
@parseStatLine: statsText$, "polyphony_max="
polyMax$ = parseStatLine.result$
@parseStatLine: statsText$, "voices_used="
voicesUsed$ = parseStatLine.result$
@parseStatLine: statsText$, "notes_unplaced="
unplaced$ = parseStatLine.result$
@parseStatLine: statsText$, "pitch_min_name="
pitchMinName$ = parseStatLine.result$
@parseStatLine: statsText$, "pitch_max_name="
pitchMaxName$ = parseStatLine.result$
@parseStatLine: statsText$, "note_duration_mean="
noteDurMean$ = parseStatLine.result$
@parseStatLine: statsText$, "note_duration_min="
noteDurMin$ = parseStatLine.result$
@parseStatLine: statsText$, "note_duration_max="
noteDurMax$ = parseStatLine.result$
@parseStatLine: statsText$, "notes_per_second="
notesPerSec$ = parseStatLine.result$
@parseStatLine: statsText$, "amplitude_mean="
ampMean$ = parseStatLine.result$
@parseStatLine: statsText$, "notation_backend="
backendUsed$ = parseStatLine.result$
@parseStatLine: statsText$, "measures="
measures$ = parseStatLine.result$
@parseStatLine: statsText$, "chords_truncated="
truncated$ = parseStatLine.result$
@parseStatLine: statsText$, "musicxml_bytes="
xmlBytes$ = parseStatLine.result$
@parseStatLine: statsText$, "predict_seconds="
predictSec$ = parseStatLine.result$
@parseStatLine: statsText$, "notate_seconds="
notateSec$ = parseStatLine.result$
@parseStatLine: statsText$, "merged_onsets="
mergedOnsets$ = parseStatLine.result$
@parseStatLine: statsText$, "warning="
warningStat$ = parseStatLine.result$
@parseStatLine: statsText$, "note_dump_truncated="
dumpTruncated$ = parseStatLine.result$

@parseStatLine: statsText$, "pitch_min_midi="
if parseStatLine.result$ <> "?"
    pitchMinMidi = number(parseStatLine.result$)
endif
@parseStatLine: statsText$, "pitch_max_midi="
if parseStatLine.result$ <> "?"
    pitchMaxMidi = number(parseStatLine.result$)
endif
@parseStatLine: statsText$, "n_note_pts="
if parseStatLine.result$ <> "?"
    nNotes = number(parseStatLine.result$)
endif

# polyphony curve (small indexed dump - stays in stats.txt)
@parseStatLine: statsText$, "n_poly_pts="
if parseStatLine.result$ <> "?"
    nPolyPts = number(parseStatLine.result$)
endif
for iP from 0 to nPolyPts - 1
    @parseStatLine: statsText$, "poly_" + string$(iP) + "="
    pl_'iP' = number(parseStatLine.result$)
endfor

# pitch histogram (small indexed dump - stays in stats.txt)
@parseStatLine: statsText$, "hist_lo_midi="
if parseStatLine.result$ <> "?"
    histLo = number(parseStatLine.result$)
endif
@parseStatLine: statsText$, "n_hist_pts="
if parseStatLine.result$ <> "?"
    nHistPts = number(parseStatLine.result$)
endif
for iH from 0 to nHistPts - 1
    @parseStatLine: statsText$, "hist_" + string$(iH) + "="
    hs_'iH' = number(parseStatLine.result$)
endfor

# ---- Note table ----
# Read as a Table, not as indexed stats keys: parseStatLine scans the whole
# stats string per key, so a 2000-note dump would be O(rows x length).
noteTable = 0
if nNotes > 0 and fileReadable(tempNotes$)
    Read Table from comma-separated file: tempNotes$
    noteTable = selected("Table")
    Rename: soundName$ + "_bpnotes"
    nNotes = Get number of rows
endif

appendInfoLine: "  ", noteCount$, " notes | max polyphony ", polyMax$, " | ", measures$, " measures"

# ===========================================================================
# Stage 5 - MusicXML: print, and save if requested
# ===========================================================================
appendInfoLine: "[5/5] MusicXML..."

xmlText$ = readFile$(tempScore$)

savedPath$ = "not saved"
if save_musicxml_to_file
    writeFile: outPath$, xmlText$
    if fileReadable(outPath$)
        savedPath$ = outPath$
        appendInfoLine: "  Saved to: ", outPath$
    else
        savedPath$ = "SAVE FAILED"
        appendInfoLine: "  WARNING: could not write to: ", outPath$
    endif
endif

# ===========================================================================
# MusicXML as a Praat Strings object
# ===========================================================================
# Keeps the score inside Praat as a first-class object, so it can be fed
# straight to OM_Score_Transformer without ever touching the disk. Raw file
# LINES, not tag-per-line: this way "Save as raw text file" reproduces the
# original score (Praat adds one trailing newline, which XML ignores), and
# the transformer does its own tag splitting internally.
xmlStrings = 0
if create_musicxml_Strings
    Read Strings from raw text file: tempScore$
    xmlStrings = selected("Strings")
    Rename: soundName$ + "_musicxml"
    nXmlLines = Get number of strings
    appendInfoLine: "  Strings object: ", nXmlLines, " lines"
endif

# ===========================================================================
# Note TextGrid
# ===========================================================================
# One interval tier per allocated voice layer. Praat interval tiers cannot
# hold overlapping intervals, so the engine assigns each note to the first
# layer that is free at its onset; notes beyond the layer cap are reported
# rather than force-fitted (which would corrupt the boundaries).
textgrid = 0
tgNotes = 0
if create_note_TextGrid and nNotes > 0
    nVoices = number(voicesUsed$)
    if nVoices < 1
        nVoices = 1
    endif
    tierNames$ = ""
    for v from 1 to nVoices
        tierNames$ = tierNames$ + "voice" + string$(v)
        if v < nVoices
            tierNames$ = tierNames$ + " "
        endif
    endfor
    textgrid = Create TextGrid: tmin, tmax, tierNames$, ""
    Rename: soundName$ + "_bpnotes"

    for r from 1 to nNotes
        selectObject: noteTable
        nStart = Get value: r, "start"
        nEnd   = Get value: r, "end"
        nVoice = Get value: r, "voice"
        nName$ = Get value: r, "name"
        if nVoice >= 0 and nVoice < nVoices
            tier = nVoice + 1
            nStart = tmin + nStart
            nEnd   = tmin + nEnd
            if nEnd > tmax
                nEnd = tmax
            endif
            if nStart < tmax and nEnd > nStart
                selectObject: textgrid
                @addInterval: tier, nStart, nEnd, nName$
                tgNotes = tgNotes + addInterval.placed
            endif
        endif
    endfor
    appendInfoLine: "  TextGrid: ", tgNotes, " intervals across ", nVoices, " tiers"
endif

# ===========================================================================
# Visualization
# ===========================================================================
if draw_visualization
    Erase all
    @niceStep: tmax - tmin, 8
    tStep = niceStep.out

    # Panel geometry note: Font size is issued BEFORE every Select inner
    # viewport, because Praat derives the viewport margins from the CURRENT
    # font size - a later font change silently re-derives a wider inner
    # viewport and shifts everything outward.

    # === Title ===
    Font size: 14
    Select inner viewport: 0.6, 7.7, 0.05, 0.45
    Axes: 0, 1, 0, 1
    Colour: "{0.20, 0.20, 0.40}"
    @picSafe: "Basic Pitch Transcriber v0.4 - " + soundName$
    Text: 0.5, "centre", 0.5, "half", picSafe.out$
    Colour: "Black"

    # === Input waveform (shares the time axis; ticks only) ===
    selectObject: sound
    wMax = Get maximum: 0, 0, "None"
    wMin = Get minimum: 0, 0, "None"
    wAbs = wMax
    if abs(wMin) > wAbs
        wAbs = abs(wMin)
    endif
    if wAbs < 1e-6
        wAbs = 1e-6
    endif
    Font size: 6
    Select outer viewport: 0, 8, 0.60, 1.70
    Select inner viewport: 0.6, 7.7, 0.70, 1.60
    selectObject: sound
    Colour: "{0.20, 0.40, 0.75}"
    Draw: tmin, tmax, -wAbs, wAbs, "no", "curve"
    Colour: "Black"
    Select inner viewport: 0.6, 7.7, 0.70, 1.60
    Axes: tmin, tmax, -wAbs, wAbs
    Draw inner box
    Marks bottom every: 1, tStep, "no", "yes", "no"
    Select inner viewport: 0.6, 7.7, 0.70, 1.60
    Axes: 0, 1, 0, 1
    Text: 0.01, "left", 1.06, "half", "Input waveform"

    # === Piano roll (shares the time axis; ticks only) ===
    Font size: 6
    Select outer viewport: 0, 8, 1.70, 4.10
    Select inner viewport: 0.6, 7.7, 1.80, 4.00
    if nNotes > 0
        rollLo = pitchMinMidi - 2
        rollHi = pitchMaxMidi + 2
        if rollHi - rollLo < 12
            rollHi = rollLo + 12
        endif
        Axes: tmin, tmax, rollLo, rollHi
        Paint rectangle: "{0.97, 0.97, 0.99}", tmin, tmax, rollLo, rollHi

        # octave guide lines behind the notes
        Colour: "{0.85, 0.85, 0.90}"
        for m from rollLo to rollHi
            if m mod 12 = 0
                Draw line: tmin, m, tmax, m
            endif
        endfor
        Colour: "Black"

        # Give every note real world-coordinate extent: a rectangle thinner
        # than a device pixel is dropped by the on-screen renderer even though
        # it survives a 300-dpi export.
        minW = (tmax - tmin) / 900
        for r from 1 to nNotes
            selectObject: noteTable
            nStart = Get value: r, "start"
            nEnd   = Get value: r, "end"
            nMidi  = Get value: r, "midi"
            nAmp   = Get value: r, "amp"
            x1 = tmin + nStart
            x2 = tmin + nEnd
            if x2 - x1 < minW
                x2 = x1 + minW
            endif
            if nAmp > 1
                nAmp = 1
            endif
            if nAmp < 0
                nAmp = 0
            endif
            # quiet -> blue, loud -> warm red
            cr = 0.20 + 0.65 * nAmp
            cg = 0.35 - 0.15 * nAmp
            cb = 0.75 - 0.55 * nAmp
            Paint rectangle: "{" + fixed$(cr, 2) + ", " + fixed$(cg, 2)
                ... + ", " + fixed$(cb, 2) + "}", x1, x2, nMidi - 0.42, nMidi + 0.42
        endfor

        Select inner viewport: 0.6, 7.7, 1.80, 4.00
        Axes: tmin, tmax, rollLo, rollHi
        Draw inner box
        Marks bottom every: 1, tStep, "no", "yes", "no"
        # label only the octave Cs, so the rail never reads 61.37
        for m from rollLo to rollHi
            if m mod 12 = 0
                @midiName: m
                @picSafe: midiName.out$
                One mark left: m, "no", "yes", "no", picSafe.out$
            endif
        endfor
        Select inner viewport: 0.6, 7.7, 1.80, 4.00
        Axes: 0, 1, 0, 1
        Text: 0.01, "left", 1.025, "half", "Detected notes - colour = amplitude (blue quiet, red loud)"
    else
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.97, 0.97, 0.99}", 0, 1, 0, 1
        Font size: 7
        Colour: "{0.50, 0.50, 0.50}"
        Text: 0.5, "centre", 0.5, "half", "(no notes detected)"
        Colour: "Black"
        Select inner viewport: 0.6, 7.7, 1.80, 4.00
        Axes: 0, 1, 0, 1
        Draw inner box
    endif

    # === Polyphony over time (last time-axis panel; numbers here) ===
    Font size: 6
    Select outer viewport: 0, 8, 4.10, 5.05
    Select inner viewport: 0.6, 7.7, 4.20, 4.95
    if nPolyPts > 1
        pMax = pl_0
        for iP from 1 to nPolyPts - 1
            if pl_'iP' > pMax
                pMax = pl_'iP'
            endif
        endfor
        if pMax < 1
            pMax = 1
        endif
        Axes: tmin, tmax, 0, pMax * 1.15
        Paint rectangle: "{0.97, 0.97, 0.99}", tmin, tmax, 0, pMax * 1.15
        Colour: "{0.35, 0.55, 0.35}"
        Line width: 1
        pStep = (tmax - tmin) / (nPolyPts - 1)
        for iP from 0 to nPolyPts - 1
            xa = tmin + iP * pStep
            xb = xa + pStep
            if xb > tmax
                xb = tmax
            endif
            Paint rectangle: "{0.45, 0.65, 0.45}", xa, xb, 0, pl_'iP'
        endfor
        Colour: "Black"
        Select inner viewport: 0.6, 7.7, 4.20, 4.95
        Axes: tmin, tmax, 0, pMax * 1.15
        Draw inner box
        Marks bottom every: 1, tStep, "yes", "yes", "no"
        pTick = 1
        if pMax > 8
            pTick = ceiling(pMax / 6)
        endif
        Marks left every: 1, pTick, "yes", "yes", "no"
        Text bottom: "yes", "Time (s)"
        Select inner viewport: 0.6, 7.7, 4.20, 4.95
        Axes: 0, 1, 0, 1
        Text: 0.01, "left", 1.10, "half", "Simultaneous notes"
    else
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.97, 0.97, 0.99}", 0, 1, 0, 1
        Select inner viewport: 0.6, 7.7, 4.20, 4.95
        Axes: 0, 1, 0, 1
        Draw inner box
    endif

    # === Pitch-class distribution (left) ===
    Font size: 6
    Select outer viewport: 0, 4, 5.45, 6.60
    Select inner viewport: 0.7, 3.75, 5.60, 6.45
    for k from 0 to 11
        pc_'k' = 0
    endfor
    pcMax = 0
    if nHistPts > 0
        for iH from 0 to nHistPts - 1
            k = (histLo + iH) mod 12
            pc_'k' = pc_'k' + hs_'iH'
        endfor
        for k from 0 to 11
            if pc_'k' > pcMax
                pcMax = pc_'k'
            endif
        endfor
    endif
    if pcMax < 1
        pcMax = 1
    endif
    Axes: 0, 12, 0, pcMax * 1.18
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, 12, 0, pcMax * 1.18
    for k from 0 to 11
        Paint rectangle: "{0.45, 0.35, 0.65}", k + 0.12, k + 0.88, 0, pc_'k'
    endfor
    Select inner viewport: 0.7, 3.75, 5.60, 6.45
    Axes: 0, 12, 0, pcMax * 1.18
    Draw inner box
    pcTick = 1
    if pcMax > 10
        pcTick = ceiling(pcMax / 5)
    endif
    Marks left every: 1, pcTick, "yes", "yes", "no"
    for k from 0 to 11
        @midiName: 60 + k
        pcLabel$ = left$(midiName.out$, length(midiName.out$) - 1)
        @picSafe: pcLabel$
        One mark bottom: k + 0.5, "no", "yes", "no", picSafe.out$
    endfor
    Select inner viewport: 0.7, 3.75, 5.60, 6.45
    Axes: 0, 1, 0, 1
    Text: 0.01, "left", 1.10, "half", "Pitch-class distribution"

    # === Note-duration distribution (right) ===
    Font size: 6
    Select outer viewport: 4, 8, 5.45, 6.60
    Select inner viewport: 4.65, 7.70, 5.60, 6.45
    nBins = 10
    for b from 1 to nBins
        db_'b' = 0
    endfor
    dbMax = 0
    dLo = 0.02
    dHi = 4.0
    if nNotes > 0
        dLo = number(noteDurMin$)
        dHi = number(noteDurMax$)
        if dLo <= 0 or dLo = undefined
            dLo = 0.01
        endif
        if dHi <= dLo or dHi = undefined
            dHi = dLo * 2
        endif
        logLo = log10(dLo)
        logHi = log10(dHi)
        for r from 1 to nNotes
            selectObject: noteTable
            nStart = Get value: r, "start"
            nEnd   = Get value: r, "end"
            d = nEnd - nStart
            if d < dLo
                d = dLo
            endif
            b = floor((log10(d) - logLo) / (logHi - logLo) * nBins) + 1
            if b < 1
                b = 1
            endif
            if b > nBins
                b = nBins
            endif
            db_'b' = db_'b' + 1
        endfor
        for b from 1 to nBins
            if db_'b' > dbMax
                dbMax = db_'b'
            endif
        endfor
    endif
    if dbMax < 1
        dbMax = 1
    endif
    Axes: 0, nBins, 0, dbMax * 1.18
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, nBins, 0, dbMax * 1.18
    for b from 1 to nBins
        Paint rectangle: "{0.28, 0.50, 0.72}", b - 0.88, b - 0.12, 0, db_'b'
    endfor
    Select inner viewport: 4.65, 7.70, 5.60, 6.45
    Axes: 0, nBins, 0, dbMax * 1.18
    Draw inner box
    dbTick = 1
    if dbMax > 10
        dbTick = ceiling(dbMax / 5)
    endif
    Marks left every: 1, dbTick, "yes", "yes", "no"
    One mark bottom: 0.35, "no", "yes", "no", fixed$(dLo, 2)
    One mark bottom: nBins / 2, "no", "yes", "no", fixed$(10 ^ ((log10(dLo) + log10(dHi)) / 2), 2)
    One mark bottom: nBins - 0.35, "no", "yes", "no", fixed$(dHi, 2)
    Text bottom: "yes", "Note duration (s, log bins)"
    Select inner viewport: 4.65, 7.70, 5.60, 6.45
    Axes: 0, 1, 0, 1
    Text: 0.01, "left", 1.10, "half", "Note-duration distribution"

    # === Summary Panel ===
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
    @picSafe: "Notes: " + noteCount$ + " (" + notesPerSec$ + "/s) | Range: "
        ... + pitchMinName$ + " - " + pitchMaxName$ + " | Max polyphony: " + polyMax$
        ... + " | Voices: " + voicesUsed$
    Text: 0.02, "left", 0.74, "half", picSafe.out$
    @picSafe: "Preset: " + presetName$ + " | Onset: " + fixed$(onset_threshold, 2)
        ... + " | Frame: " + fixed$(frame_threshold, 2) + " | Min len: "
        ... + fixed$(minimum_note_length_ms, 0) + " ms | Melodia: " + string$(melodia_trick)
    Text: 0.02, "left", 0.58, "half", picSafe.out$
    @picSafe: "Score: " + measures$ + " bars | " + fixed$(score_tempo_BPM, 0)
        ... + " BPM | grid " + gridStr$ + " | backend " + backendUsed$
        ... + " | " + xmlBytes$ + " bytes"
    Text: 0.02, "left", 0.42, "half", picSafe.out$
    @picSafe: "Note dur.: mean " + noteDurMean$ + " s (" + noteDurMin$ + " - "
        ... + noteDurMax$ + ") | Inference: " + predictSec$ + " s | Notation: "
        ... + notateSec$ + " s"
    Text: 0.02, "left", 0.26, "half", picSafe.out$

    if warningStat$ <> "?" and warningStat$ <> "" and warningStat$ <> "none"
        Colour: "{0.80, 0.20, 0.20}"
        @picSafe: "Warn: " + warningStat$
        Text: 0.02, "left", 0.08, "half", picSafe.out$
    endif

    Colour: "Black"
    Select inner viewport: 0.6, 7.7, 7.05, 7.90
    Axes: 0, 1, 0, 1
    Draw rectangle: 0, 1, 0, 1
    Font size: 10

    # A Save / Copy from the Picture window exports the CURRENT viewport
    # selection, not the whole picture - without this the export is cropped
    # to the summary strip.
    Select outer viewport: 0, 8, 0, 8
endif

# ===========================================================================
# MusicXML dump to the Info window
# ===========================================================================
if print_musicxml_to_info
    appendInfoLine: ""
    appendInfoLine: "=== MusicXML (", xmlBytes$, " bytes) ==="
    # One call, not a per-line loop: the whole score is a single string.
    appendInfoLine: xmlText$
    appendInfoLine: "=== END MusicXML ==="
endif

# ===========================================================================
# Cleanup & Summary
# ===========================================================================
@cleanUpTempFiles

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Notes detected:  ", noteCount$
appendInfoLine: "Pitch range:     ", pitchMinName$, " - ", pitchMaxName$,
    ... " (MIDI ", pitchMinMidi, "-", pitchMaxMidi, ")"
appendInfoLine: "Merge mode:      ", mergeStr$, " (", mergedOnsets$, " onsets rejoined)"
appendInfoLine: "Max polyphony:   ", polyMax$
appendInfoLine: "Voice layers:    ", voicesUsed$
if number(unplaced$) > 0
    appendInfoLine: "Unplaced notes:  ", unplaced$, " (beyond the voice-layer cap)"
endif
if dumpTruncated$ = "yes"
    appendInfoLine: "NOTE:            note table truncated for display;"
    appendInfoLine: "                 the MusicXML score contains every note."
endif
appendInfoLine: "Note duration:   mean ", noteDurMean$, " s (", noteDurMin$, " - ", noteDurMax$, ")"
appendInfoLine: "Notes/second:    ", notesPerSec$
appendInfoLine: "Mean amplitude:  ", ampMean$
appendInfoLine: ""
appendInfoLine: "Score measures:  ", measures$
appendInfoLine: "Notation:        ", backendUsed$
if backendUsed$ = "builtin" and number(truncated$) > 0
    appendInfoLine: "Chords cut:      ", truncated$, " (built-in writer is a chordal reduction;"
    appendInfoLine: "                 install music21 for real voice engraving)"
endif
appendInfoLine: "MusicXML size:   ", xmlBytes$, " bytes"
if xmlStrings > 0
    appendInfoLine: "Strings object:  ", soundName$, "_musicxml (feed to OM Score Transformer)"
endif
appendInfoLine: "Saved to:        ", savedPath$
appendInfoLine: "Inference time:  ", predictSec$, " s"
appendInfoLine: "Notation time:   ", notateSec$, " s"

if warningStat$ <> "?" and warningStat$ <> "" and warningStat$ <> "none"
    appendInfoLine: "WARNING:         ", warningStat$
endif

# ---- Final selection ----
selectObject: sound
if textgrid > 0
    plusObject: textgrid
endif
if noteTable > 0
    plusObject: noteTable
endif
if xmlStrings > 0
    plusObject: xmlStrings
endif

if play_input_sound
    selectObject: sound
    Play
    if textgrid > 0
        selectObject: sound
        plusObject: textgrid
    endif
endif

# ===========================================================================
# Procedures
# ===========================================================================
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

# Picture-window text markup escapes. "#" is BOLD, "_" is SUBSCRIPT, "%" is
# ITALIC and "^" is SUPERSCRIPT, and each is SWALLOWED when it reaches a Text
# command raw - "C#4" draws as a bold "C4" with the accidental gone. The
# escapes consume the single space that terminates them, and that one space
# is correct in EVERY position including end-of-string - rendered and checked
# on 6.4.06 at all four combinations. Two spaces leave a visible gap ("C# 6").
procedure picSafe: .s$
    .out$ = replace$(.s$, "\", "\bs ", 0)
    .out$ = replace$(.out$, "#", "\# ", 0)
    .out$ = replace$(.out$, "_", "\_ ", 0)
    .out$ = replace$(.out$, "%", "\% ", 0)
    .out$ = replace$(.out$, "^", "\^ ", 0)
endproc

# A data-derived tick step prints labels like 0.6569 / 1.314 / 1.971. Snap to
# the nearest 1/2/5 x 10^k so a time axis reads in round numbers.
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

# Praat tiers are sorted SETS: a second boundary at a time that already holds
# one is silently discarded, and Insert boundary ERRORS on an exact duplicate.
# Both boundaries are therefore tested before being written.
procedure addInterval: .tier, .t1, .t2, .label$
    .placed = 0
    .i1 = Get interval at time: .tier, .t1
    .s1 = Get start time of interval: .tier, .i1
    if abs(.s1 - .t1) > 1e-9
        .e1 = Get end time of interval: .tier, .i1
        if .t1 < .e1 - 1e-9
            Insert boundary: .tier, .t1
        endif
    endif
    .i2 = Get interval at time: .tier, .t2
    .s2 = Get start time of interval: .tier, .i2
    if abs(.s2 - .t2) > 1e-9
        .e2 = Get end time of interval: .tier, .i2
        if .t2 < .e2 - 1e-9
            Insert boundary: .tier, .t2
        endif
    endif
    .idx = Get interval at time: .tier, .t1 + (.t2 - .t1) / 2
    .cur$ = Get label of interval: .tier, .idx
    if .cur$ = ""
        Set interval text: .tier, .idx, .label$
        .placed = 1
    endif
endproc
