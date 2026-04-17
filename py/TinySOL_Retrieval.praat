# ============================================================
# Praat AudioTools - TinySOL_Retrieval.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.4 (2026) - Unified Cross-Platform Version
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   TinySOL Orchestration Retrieval
#
#   Exports the selected Sound to a temp WAV, passes it to the
#   Python backend (tinysol_retrieval.py) which:
#     1. Loads pre-computed .db descriptor files (mfcc, specenv,
#        moments, specpeaks, spectrum) — no full corpus recompute.
#     2. Parses TinySOL filenames to build a rich metadata index.
#     3. Analyses the target sound and computes comparable descriptors.
#     4. Retrieves the closest orchestral analogues by weighted
#        multi-descriptor distance.
#     5. Optionally blends 2-4 samples for a richer texture.
#     6. Returns a rendered WAV + a ranked results text file.
#   Praat then imports the WAV and displays the results summary.
#
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound     = selected("Sound")
soundName$ = selected$("Sound")

# ---- OS-SPECIFIC PYTHON DISCOVERY ----
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

# ---- PATHS & UNIFIED CROSS-PLATFORM FIX ----
pluginDirRaw$ = preferencesDirectory$ + "/plugin_AudioTools/"
pluginDir$ = replace_regex$(pluginDirRaw$, "\\", "/", 0)

pythonScript$ = pluginDir$ + "py/tinysol_retrieval.py"
if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/tinysol_retrieval.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: tinysol_retrieval.py" + newline$ + "Expected at: " + pluginDir$ + "py/ or next to this script."
endif

tempDirRaw$ = temporaryDirectory$ + "/"
tempDir$ = replace_regex$(tempDirRaw$, "\\", "/", 0)

runTag$    = replace_regex$(soundName$, "[^A-Za-z0-9_]", "_", 0) + "_" + replace_regex$(date$(), "[ :]", "_", 0)
runTag$    = replace_regex$(runTag$, "__+", "_", 0)

tempInput$   = tempDir$ + "tmp_" + runTag$ + "_input.wav"
tempParams$  = tempDir$ + "tmp_" + runTag$ + "_params.txt"
tempOutput$  = tempDir$ + "tmp_" + runTag$ + "_output.wav"
tempResults$ = tempDir$ + "tmp_" + runTag$ + "_results.txt"
doneFile$    = tempDir$ + "tmp_" + runTag$ + "_done.txt"
probePy$     = tempDir$ + "tmp_" + runTag$ + "_probe.py"
probeMarker$ = tempDir$ + "tmp_" + runTag$ + "_probe.ok"

# Enforce forward slashes for all temporary paths passed to python
pythonScriptJ$ = replace_regex$(pythonScript$, "\\", "/", 0)
tempInputJ$    = replace_regex$(tempInput$, "\\", "/", 0)
tempParamsJ$   = replace_regex$(tempParams$, "\\", "/", 0)
tempOutputJ$   = replace_regex$(tempOutput$, "\\", "/", 0)
tempResultsJ$  = replace_regex$(tempResults$, "\\", "/", 0)
doneFileJ$     = replace_regex$(doneFile$, "\\", "/", 0)
probePyJ$      = replace_regex$(probePy$, "\\", "/", 0)
probeMarkerJ$  = replace_regex$(probeMarker$, "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(tempInput$)
        deleteFile: tempInput$
    endif
    if fileReadable(tempParams$)
        deleteFile: tempParams$
    endif
    if fileReadable(tempOutput$)
        deleteFile: tempOutput$
    endif
    if fileReadable(tempResults$)
        deleteFile: tempResults$
    endif
    if fileReadable(doneFile$)
        deleteFile: doneFile$
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
form TinySOL Orchestration Retrieval v1.4
    # ── Preset  ───────────────────────────────────────────────────────
    optionmenu Preset: 1
        option Custom  (use fields as-is)
        option REF-whole  (whole-file reference preset)
        option REF-frame  (frame-based reference preset)
        option REF-orchids  (Orchidea-architecture preset)
        option Speech  (speech / vocal input — no harmonic matching)

    # ── Corpus paths ─────────────────────────────────────────────────
    sentence DB_directory         D:/old D/waves/TinySOL_2020
    sentence Corpus_root          D:/old D/waves/TinySOL_2020/TinySOL

    # ── Instrument / family constraints ──────────────────────────────
    optionmenu Instrument_families: 1
        option All families
        option Brass only
        option Strings only
        option Winds only
        option Brass + Strings
        option Brass + Winds
        option Strings + Winds

    sentence Specific_instruments 

    # ── Pitch range (MIDI) ───────────────────────────────────────────
    integer Min_MIDI_pitch 36
    integer Max_MIDI_pitch 96

    # ── Dynamics ────────────────────────────────────────────────────
    optionmenu Preferred_dynamics: 3
        option pp
        option p
        option mf
        option ff
        option pp + mf
        option mf + ff
        option All dynamics

    # ── Analysis mode ────────────────────────────────────────────────
    optionmenu Analysis_mode: 1
        option Whole file  (average timbre)
        option Frame-based  (follows pitch + dynamics)

    integer Frame_size_ms 150
    integer Hop_size_ms 75
    integer Pitch_tolerance_semitones 2
    boolean Pitch_pan_in_stereo 0

    # ── Retrieval & render ───────────────────────────────────────────
    integer Number_of_results 8

    optionmenu Render_mode: 1
        option best              (single best match)
        option blend             (top-3 rank-weighted mix)
        option top2              (top-2 equal mix)
        option top3              (top-3 equal mix)
        option top4              (top-4 equal mix)

    real Render_gain 0.8

    # ── Descriptor weights  (must sum to ~1.0) ───────────────────────
    real MFCC_weight    0.25
    real Specenv_weight 0.20
    real Moments_weight 0.05
    real Specpeaks_weight 0.15
    real Harmonic_weight 0.35

    boolean Draw_visualization 1
    boolean Play_result 1
    boolean Stereo_output 0
    boolean Speech_mode 0
    # ── Match quality gate ───────────────────────────────────────────
    real Silence_threshold 2.0
endform

# Sanitize input paths from the UI to ensure forward slashes
dB_directory$ = replace_regex$(dB_directory$, "\\", "/", 0)
corpus_root$  = replace_regex$(corpus_root$, "\\", "/", 0)

# ---- APPLY PRESET ----
if preset = 2
    analysisStr$             = "whole_file"
    analysis_mode            = 1
    mFCC_weight              = 0.25
    specenv_weight           = 0.20
    moments_weight           = 0.05
    specpeaks_weight         = 0.15
    harmonic_weight          = 0.35
    dynStr$                  = "mf,ff"
    preferred_dynamics       = 6
    render_mode              = 1
    renderStr$               = "best"
    stereo_output            = 0
    pitch_pan_in_stereo      = 0
    draw_visualization       = 1
    silence_threshold        = 1.0
elsif preset = 3
    analysisStr$             = "frame_based"
    analysis_mode            = 2
    frame_size_ms            = 150
    hop_size_ms              = 75
    pitch_tolerance_semitones = 2
    mFCC_weight              = 0.25
    specenv_weight           = 0.20
    moments_weight           = 0.05
    specpeaks_weight         = 0.15
    harmonic_weight          = 0.35
    dynStr$                  = "mf,ff"
    preferred_dynamics       = 6
    render_mode              = 1
    renderStr$               = "best"
    stereo_output            = 0
    pitch_pan_in_stereo      = 0
    draw_visualization       = 1
    silence_threshold        = 1.0
elsif preset = 4
    analysisStr$             = "whole_file"
    analysis_mode            = 1
    mFCC_weight              = 0.20
    specenv_weight           = 0.30
    moments_weight           = 0.05
    specpeaks_weight         = 0.10
    harmonic_weight          = 0.35
    dynStr$                  = "mf,ff"
    preferred_dynamics       = 6
    render_mode              = 1
    renderStr$               = "best"
    stereo_output            = 0
    pitch_pan_in_stereo      = 0
    draw_visualization       = 1
    silence_threshold        = 1.0
endif

if preset = 5
    analysisStr$             = "whole_file"
    analysis_mode            = 1
    mFCC_weight              = 0.45
    specenv_weight           = 0.30
    moments_weight           = 0.10
    specpeaks_weight         = 0.15
    harmonic_weight          = 0.00
    dynStr$                  = "mf,ff"
    preferred_dynamics       = 6
    render_mode              = 1
    renderStr$               = "best"
    stereo_output            = 0
    pitch_pan_in_stereo      = 0
    draw_visualization       = 1
    silence_threshold        = 2.0
    speech_mode              = 1
endif

# ---- CLAMP numerical inputs ----
if min_MIDI_pitch < 0
    min_MIDI_pitch = 0
endif
if min_MIDI_pitch > 127
    min_MIDI_pitch = 127
endif
if max_MIDI_pitch < min_MIDI_pitch
    max_MIDI_pitch = min_MIDI_pitch
endif
if max_MIDI_pitch > 127
    max_MIDI_pitch = 127
endif
if number_of_results < 1
    number_of_results = 1
endif
if number_of_results > 32
    number_of_results = 32
endif
if render_gain <= 0
    render_gain = 0.01
endif
if render_gain > 2
    render_gain = 2
endif
if mFCC_weight < 0
    mFCC_weight = 0
endif
if specenv_weight < 0
    specenv_weight = 0
endif
if moments_weight < 0
    moments_weight = 0
endif
if specpeaks_weight < 0
    specpeaks_weight = 0
endif
if harmonic_weight < 0
    harmonic_weight = 0
endif
if silence_threshold < 0
    silence_threshold = 0
endif
if silence_threshold > 2
    silence_threshold = 2
endif

# ---- Resolve analysis mode ----
if analysis_mode = 1
    analysisStr$ = "whole_file"
else
    analysisStr$ = "frame_based"
endif

# ---- Clamp frame params ----
if frame_size_ms < 50
    frame_size_ms = 50
endif
if frame_size_ms > 500
    frame_size_ms = 500
endif
if hop_size_ms < 10
    hop_size_ms = 10
endif
if hop_size_ms > frame_size_ms
    hop_size_ms = frame_size_ms
endif
if pitch_tolerance_semitones < 0
    pitch_tolerance_semitones = 0
endif
if pitch_tolerance_semitones > 12
    pitch_tolerance_semitones = 12
endif

# ---- Resolve instrument families string ----
if instrument_families = 1
    familyStr$ = "Brass,Strings,Winds"
elsif instrument_families = 2
    familyStr$ = "Brass"
elsif instrument_families = 3
    familyStr$ = "Strings"
elsif instrument_families = 4
    familyStr$ = "Winds"
elsif instrument_families = 5
    familyStr$ = "Brass,Strings"
elsif instrument_families = 6
    familyStr$ = "Brass,Winds"
else
    familyStr$ = "Strings,Winds"
endif

# ---- Resolve dynamics string ----
if preferred_dynamics = 1
    dynStr$ = "pp"
elsif preferred_dynamics = 2
    dynStr$ = "p"
elsif preferred_dynamics = 3
    dynStr$ = "mf"
elsif preferred_dynamics = 4
    dynStr$ = "ff"
elsif preferred_dynamics = 5
    dynStr$ = "pp,mf"
elsif preferred_dynamics = 6
    dynStr$ = "mf,ff"
else
    dynStr$ = "pp,p,mf,ff"
endif

# ---- Resolve render mode string ----
if render_mode = 1
    renderStr$ = "best"
elsif render_mode = 2
    renderStr$ = "blend"
elsif render_mode = 3
    renderStr$ = "top2"
elsif render_mode = 4
    renderStr$ = "top3"
else
    renderStr$ = "top4"
endif

# ---- INFO header ----
clearinfo
writeInfoLine:  "=== TinySOL Orchestration Retrieval v1.4 ==="
appendInfoLine: "Input:   ", soundName$
appendInfoLine: "DB dir:  ", dB_directory$
appendInfoLine: "Corpus:  ", corpus_root$
if preset = 2
    appendInfoLine: ">>> Preset: REF-whole applied <<<"
elsif preset = 3
    appendInfoLine: ">>> Preset: REF-frame applied <<<"
elsif preset = 4
    appendInfoLine: ">>> Preset: REF-orchids applied (hard MIDI filter, silence gate disabled) <<<"
elsif preset = 5
    appendInfoLine: ">>> Preset: Speech applied (harmonic=0, silence gate raised) <<<"
endif
appendInfoLine: ""
appendInfoLine: "Families:   ", familyStr$
appendInfoLine: "Dynamics:   ", dynStr$
appendInfoLine: "MIDI range: ", min_MIDI_pitch, " — ", max_MIDI_pitch
appendInfoLine: "Analysis:   ", analysisStr$
if analysis_mode = 2
    appendInfoLine: "Frame/hop:  ", frame_size_ms, " ms / ", hop_size_ms, " ms  pitch_tol: ±", pitch_tolerance_semitones, " st"
endif
appendInfoLine: "Render:     ", renderStr$, "  gain=", fixed$(render_gain, 2), "  stereo=", stereo_output, "  silence_threshold=", fixed$(silence_threshold, 2)
appendInfoLine: "Weights:    mfcc=", fixed$(mFCC_weight, 2),
    ... "  specenv=", fixed$(specenv_weight, 2),
    ... "  moments=", fixed$(moments_weight, 2),
    ... "  specpeaks=", fixed$(specpeaks_weight, 2),
    ... "  harmonic=", fixed$(harmonic_weight, 2)
appendInfoLine: ""

# ---- Original sound stats ----
selectObject: sound
dur       = Get total duration
sr        = Get sampling frequency
nChannels = Get number of channels
rms_orig  = Get root-mean-square: 0, 0

# ===========================================================================
# Stage 0 — Early Python Dependency Probe
# ===========================================================================
appendInfoLine: "[0/5] Detecting Python dependencies..."

writeFileLine: probePy$, "import sys"
appendFileLine: probePy$, "try:"
appendFileLine: probePy$, "    import numpy, scipy, soundfile"
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
    exitScript: "Cannot find Python 3 installation with required packages." + newline$ + "Tried: python3, python, py" + newline$ + "Please install: pip install numpy scipy soundfile"
endif

appendInfoLine: "  Python found: ", pythonCmd$

# ===========================================================================
# Stage 1 — Export target WAV
# ===========================================================================
appendInfoLine: "[1/5] Exporting target audio..."
selectObject: sound
Save as WAV file: tempInput$

# ===========================================================================
# Stage 2 — Write params file
# ===========================================================================
appendInfoLine: "[2/5] Writing parameter file..."
deleteFile: tempParams$

# Build descriptor weight string
descWeightStr$ = "mfcc:" + string$(mFCC_weight)
    ... + ",specenv:" + string$(specenv_weight)
    ... + ",moments:" + string$(moments_weight)
    ... + ",specpeaks:" + string$(specpeaks_weight)
    ... + ",harmonic:" + string$(harmonic_weight)

# Write params (key=value, one per line)
writeFileLine: tempParams$, "db_dir=" + dB_directory$
appendFileLine: tempParams$, "corpus_root=" + corpus_root$
appendFileLine: tempParams$, "allowed_families=" + familyStr$
appendFileLine: tempParams$, "allowed_instruments=" + specific_instruments$
appendFileLine: tempParams$, "min_midi=" + string$(min_MIDI_pitch)
appendFileLine: tempParams$, "max_midi=" + string$(max_MIDI_pitch)
appendFileLine: tempParams$, "preferred_dynamics=" + dynStr$
appendFileLine: tempParams$, "max_layers=4"
appendFileLine: tempParams$, "descriptor_weights=" + descWeightStr$
appendFileLine: tempParams$, "n_results=" + string$(number_of_results)
appendFileLine: tempParams$, "render_mode=" + renderStr$
appendFileLine: tempParams$, "render_gain=" + string$(render_gain)
appendFileLine: tempParams$, "stereo_output=" + string$(stereo_output)
appendFileLine: tempParams$, "analysis_mode=" + analysisStr$
appendFileLine: tempParams$, "frame_size_ms=" + string$(frame_size_ms)
appendFileLine: tempParams$, "hop_size_ms=" + string$(hop_size_ms)
appendFileLine: tempParams$, "pitch_tolerance=" + string$(pitch_tolerance_semitones)
appendFileLine: tempParams$, "pitch_pan_stereo=" + string$(pitch_pan_in_stereo)
appendFileLine: tempParams$, "silence_threshold=" + string$(silence_threshold)
appendFileLine: tempParams$, "speech_mode=" + string$(speech_mode)

# ===========================================================================
# Stage 3 — Run Python backend
# ===========================================================================
appendInfoLine: "[3/5] Running Python retrieval engine..."
appendInfoLine: "  (this may take a few seconds on first run while the"
appendInfoLine: "   corpus index is built from the .db files)"
appendInfoLine: ""

pythonCall$ = pythonCmd$ + " """ + pythonScriptJ$ + """"
    ... + " """ + tempInputJ$   + """"
    ... + " """ + tempParamsJ$  + """"
    ... + " """ + tempOutputJ$  + """"
    ... + " """ + tempResultsJ$ + """"
    ... + " """ + doneFileJ$    + """"

runSystem_nocheck: pythonCall$

# ---- Check done file for status ----
if fileReadable(doneFile$)
    doneStatus$ = readFile$(doneFile$)
    if index(doneStatus$, "ERROR") > 0
        @cleanUpTempFiles
        exitScript: "Python backend reported an error:" + newline$ + doneStatus$
    endif
elsif not fileReadable(tempOutput$)
    @cleanUpTempFiles
    exitScript: "Python backend did not produce output WAV." + newline$ + "Check the Praat Info window and verify paths."
endif

# ===========================================================================
# Stage 4 — Import result
# ===========================================================================
appendInfoLine: "[4/5] Importing result..."

Read from file: tempOutput$
resultSound = selected("Sound")
Rename: soundName$ + "_orchestrated"

# ---- Output stats ----
selectObject: resultSound
dur_out   = Get total duration
rms_out   = Get root-mean-square: 0, 0

# ===========================================================================
# Stage 5 — Parse results file + display
# ===========================================================================
appendInfoLine: "[5/5] Reading retrieval results..."
appendInfoLine: ""

bestMatch$     = "?"
bestScore$     = "?"
nCandidates$   = "?"
renderMode$    = "?"
chosenCount$   = "?"
silenceFlag$   = ""

if fileReadable(tempResults$)
    resultText$ = readFile$(tempResults$)

    # Extract scalar stats using the parseStatLine procedure
    @parseStatLine: resultText$, "n_candidates="
    nCandidates$ = parseStatLine.result$

    @parseStatLine: resultText$, "render_mode="
    renderMode$ = parseStatLine.result$

    @parseStatLine: resultText$, "chosen_count="
    chosenCount$ = parseStatLine.result$

    @parseStatLine: resultText$, "silence_rendered="
    if parseStatLine.result$ = "1"
        silenceFlag$ = "  [SILENCE — score > threshold]"
    endif

    # Parse top-ranked match from the CSV section
    csvStart = index(resultText$, newline$ + "1,")
    if csvStart > 0
        lineStart = csvStart + 1
        tailText$ = mid$(resultText$, lineStart, length(resultText$) - lineStart + 1)
        nlPos = index(tailText$, newline$)
        if nlPos > 0
            firstLine$ = left$(tailText$, nlPos - 1)
        else
            firstLine$ = tailText$
        endif

        nCommas = 0
        fieldCount = 0
        fieldStr$ = firstLine$

        # field 1 = rank
        p = index(fieldStr$, ",")
        if p > 0
            f1$ = left$(fieldStr$, p - 1)
            fieldStr$ = mid$(fieldStr$, p + 1, length(fieldStr$) - p)
        endif
        # field 2 = score
        p = index(fieldStr$, ",")
        if p > 0
            bestScore$ = left$(fieldStr$, p - 1)
            fieldStr$ = mid$(fieldStr$, p + 1, length(fieldStr$) - p)
        endif
        # field 3 = family
        p = index(fieldStr$, ",")
        if p > 0
            bf$ = left$(fieldStr$, p - 1)
            fieldStr$ = mid$(fieldStr$, p + 1, length(fieldStr$) - p)
        endif
        # field 4 = instrument
        p = index(fieldStr$, ",")
        if p > 0
            bi$ = left$(fieldStr$, p - 1)
            fieldStr$ = mid$(fieldStr$, p + 1, length(fieldStr$) - p)
        endif
        # field 5 = note
        p = index(fieldStr$, ",")
        if p > 0
            bn$ = left$(fieldStr$, p - 1)
            fieldStr$ = mid$(fieldStr$, p + 1, length(fieldStr$) - p)
        endif
        # field 6 = midi  (skip)
        p = index(fieldStr$, ",")
        if p > 0
            fieldStr$ = mid$(fieldStr$, p + 1, length(fieldStr$) - p)
        endif
        # field 7 = dynamic
        p = index(fieldStr$, ",")
        if p > 0
            bd$ = left$(fieldStr$, p - 1)
            fieldStr$ = mid$(fieldStr$, p + 1, length(fieldStr$) - p)
        endif

        bestMatch$ = bf$ + " " + bi$ + " " + bn$ + " " + bd$
    endif
endif

# ===========================================================================
# Visualization (optional)
# ===========================================================================
if draw_visualization
    appendInfoLine: "Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # ----------------------------------------------------------
    # Title
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##TinySOL Orchestration Retrieval v1.4##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.25, "half",
        ... soundName$ + "  |  " + analysisStr$
        ... + "  |  " + renderStr$
        ... + "  |  " + familyStr$

    # ----------------------------------------------------------
    # Input waveform
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.52, 1.32
    Select inner viewport: 0.55, 7.65, 0.57, 1.27
    selectObject: sound
    if nChannels > 1
        Extract one channel: 1
        vizIn = selected("Sound")
    else
        Copy: "vizIn"
        vizIn = selected("Sound")
    endif
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    removeObject: vizIn
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"

    # ----------------------------------------------------------
    # Output waveform
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 1.36, 2.16
    Select inner viewport: 0.55, 7.65, 1.41, 2.11
    selectObject: resultSound
    nChRes = Get number of channels
    if nChRes > 1
        Extract one channel: 1
        vizOutL = selected("Sound")
        Colour: "{0.15, 0.50, 0.35}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        selectObject: resultSound
        Extract one channel: 2
        vizOutR = selected("Sound")
        Colour: "{0.35, 0.55, 0.15}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        removeObject: vizOutL, vizOutR
    else
        selectObject: resultSound
        Colour: "{0.15, 0.50, 0.35}"
        Draw: 0, 0, 0, 0, "no", "Curve"
    endif
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # Input spectrogram
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.1, 2.24, 3.64
    Select inner viewport: 0.55, 3.85, 2.34, 3.54
    selectObject: sound
    if nChannels > 1
        Extract one channel: 1
        vizSpecIn = selected("Sound")
    else
        Copy: "vizSpecIn"
        vizSpecIn = selected("Sound")
    endif
    To Spectrogram: 0.02, 5000, 0.005, 20, "Gaussian"
    specOrig = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    removeObject: specOrig, vizSpecIn
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Target spectrogram"

    # ----------------------------------------------------------
    # Output spectrogram
    # ----------------------------------------------------------
    Select outer viewport: 4.1, 8, 2.24, 3.64
    Select inner viewport: 4.40, 7.65, 2.34, 3.54
    selectObject: resultSound
    if nChRes > 1
        Extract one channel: 1
        vizSpecOut = selected("Sound")
    else
        Copy: "vizSpecOut"
        vizSpecOut = selected("Sound")
    endif
    To Spectrogram: 0.02, 5000, 0.005, 20, "Gaussian"
    specRes = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    removeObject: specRes, vizSpecOut
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Orchestrated spectrogram"

    # ----------------------------------------------------------
    # Retrieval results panel
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 3.74, 5.04
    Select inner viewport: 0.55, 7.65, 3.80, 4.98
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.96}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.90, "half", "##Retrieval Results##"

    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.72, "half",
        ... "Best match:  " + bestMatch$ + "   score=" + bestScore$ + silenceFlag$

    if analysis_mode = 2
        Text: 0.02, "left", 0.54, "half",
            ... "Frames: " + nCandidates$
            ... + "  |  Matched: " + chosenCount$
            ... + "  |  Mode: frame_based"
            ... + "  |  Gain: " + fixed$(render_gain, 2)
    else
        Text: 0.02, "left", 0.54, "half",
            ... "Candidates: " + nCandidates$
            ... + "  |  Layers: " + chosenCount$
            ... + "  |  Mode: " + renderMode$
            ... + "  |  Gain: " + fixed$(render_gain, 2)
    endif

    Text: 0.02, "left", 0.36, "half",
        ... "Families: " + familyStr$
        ... + "  |  Dynamics: " + dynStr$
        ... + "  |  MIDI: " + string$(min_MIDI_pitch) + "–" + string$(max_MIDI_pitch)

    Text: 0.02, "left", 0.18, "half",
        ... "Weights:  mfcc=" + fixed$(mFCC_weight, 2)
        ... + "  specenv=" + fixed$(specenv_weight, 2)
        ... + "  moments=" + fixed$(moments_weight, 2)
        ... + "  specpeaks=" + fixed$(specpeaks_weight, 2)
        ... + "  harmonic=" + fixed$(harmonic_weight, 2)

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # ----------------------------------------------------------
    # Summary panel
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.14, 5.74
    Select inner viewport: 0.55, 7.65, 5.20, 5.68
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.78, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.32, "half",
        ... "Target: " + fixed$(dur, 2) + "s  RMS=" + fixed$(rms_orig, 4)
        ... + "  |  Output: " + fixed$(dur_out, 2) + "s  RMS=" + fixed$(rms_out, 4)
        ... + "  |  " + analysisStr$
        ... + "  |  " + renderStr$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ===========================================================================
# Final Cleanup
# ===========================================================================
@cleanUpTempFiles

# ===========================================================================
# Summary
# ===========================================================================

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", soundName$, "_orchestrated"
appendInfoLine: ""
appendInfoLine: "Best match:     ", bestMatch$, silenceFlag$
appendInfoLine: "Match score:    ", bestScore$, "  (lower = closer)"
if analysis_mode = 2
    appendInfoLine: "Frames analyzed:", nCandidates$
    appendInfoLine: "Frames matched: ", chosenCount$
    appendInfoLine: "Render mode:    frame_based"
else
    appendInfoLine: "Candidates:     ", nCandidates$
    appendInfoLine: "Layers used:    ", chosenCount$
    appendInfoLine: "Render mode:    ", renderMode$
endif
appendInfoLine: ""
appendInfoLine: "Target:         ", fixed$(dur, 2), " s  RMS=", fixed$(rms_orig, 4)
appendInfoLine: "Output:         ", fixed$(dur_out, 2), " s  RMS=", fixed$(rms_out, 4)

selectObject: resultSound

if play_result
    Play
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
        if .nlPos = 0
            .nlPos = index(.rest$, unicode$(10))
        endif
        if .nlPos > 0
            .result$ = left$(.rest$, .nlPos - 1)
        else
            .result$ = .rest$
        endif
        if length(.result$) > 0
            if right$(.result$, 1) = unicode$(13)
                .result$ = left$(.result$, length(.result$) - 1)
            endif
        endif
    endif
endproc