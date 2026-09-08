# ============================================================
# Praat AudioTools - TinySOL_Retrieval.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.10.3 (2026) - Native Orchidea DB profile compatibility
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   TinySOL Orchestration Retrieval
#
#   Exports the selected Sound to a temp WAV, passes it to the
#   Python backend (tinysol_retrieval.py) which:
#     1. Loads pre-computed .db descriptor files (mfcc, specenv,
#        moments, specpeaks) — no full corpus recompute.
#     2. Parses TinySOL filenames to build a rich metadata index.
#     3. Analyses the target sound and computes comparable descriptors.
#     4. Retrieves the closest orchestral analogues by weighted
#        multi-descriptor distance.
#     5. Optionally blends 2-4 samples for a richer texture.
#     6. Returns a rendered WAV + a ranked results text file.
#   Praat then imports the WAV and displays the results summary.
#
# Changelog v1.10.3 (2026):
#   - DB COMPATIBILITY: Python resolves descriptor vector lengths directly from
#     the installed TinySOL/Orchidea .db files. Official profiles such as
#     specenv=1024 and specpeaks=120 no longer fail against AudioTools compact
#     dimensions; target analysis is generated at the database-native length.
#   - No zero-padding or silent descriptor disabling is used.
#
# Changelog v1.10.2 (2026):
#   - VIS: replaced the technical pipeline/descriptor display with a user-facing
#     orchestration view: selected-sound profile -> instrument choices -> rendered
#     result. Source duration/channels/rate/level/pitch are shown alongside the
#     ranked TinySOL choices (instrument, family, note, dynamic); retrieval score
#     is deliberately secondary. Frame mode labels the ranking as most-used
#     choices across the target.
#
# Changelog v1.10.1 (2026):
#   - FORM: compact first dialog keeps corpus/constraint and musical retrieval
#     controls visible on smaller screens; frame/DSP/descriptor/gating controls
#     moved to optional Edit details (defaults unchanged). Presets are applied
#     before the details dialog so technical values can be inspected/overridden.
#   - VIS: rebuilt around the actual retrieval process used across AudioTools:
#     target analysis + legal TinySOL domain -> weighted distance -> ranking ->
#     render/envelope transfer -> measured output. Top retrieved entries and
#     envelope-correlation QC are shown from the backend results file.
#
# Changelog v1.10 (2026):
#   - CORRECTNESS: backend validates active .db descriptor dimensions and never
#     silently zero-pads vectors; v1.10.3 extends this to native DB dimensions.
#   - CORRECTNESS: every candidate must contain every active descriptor; rankings
#     are no longer comparable scores built from different feature subsets.
#   - CORRECTNESS: target descriptor analysis is standardised to TinySOL's
#     44.1 kHz corpus rate while output preserves the target's own rate/length.
#   - PERFORMANCE: unused spectrum .db is no longer loaded.
#
# Changelog v1.9 (2026):
#   - MUSICAL: optional Envelope_follow transfers the target's smoothed macro-RMS
#     gesture onto the retrieved result. This reduces duration/envelope mismatch
#     between heterogeneous TinySOL samples without time-stretching or pitch shift.
#   - Envelope_follow=0 is exact v1.8 rendering; default 0.85. Backend reports
#     target-envelope correlation before/after transfer.
#
# Changelog v1.8 (2026):
#   - Python v1.8 backend: corrected F0/pitch-gate logic, silent-frame handling,
#     frame-mode silence gate, variant selection, speech pitch neutrality,
#     polyphase resampling, and strongest-channel target analysis.
#   - CORPUS: All families now includes official TinySOL Keyboards/Accordion;
#     added Keyboards-only filter. Family detection is path-based in Python.
#   - UI: All dynamics now means no dynamic preference penalty (previously it
#     still preferred pp/p/mf/ff and penalised f).
#   - UI: descriptor weights are relative; they are normalized internally and
#     need not sum to 1. At least one must be positive.
#   - VIS: representative strongest channels + shared waveform scale; 10 kHz
#     spectrogram ceiling where supported; title/subtitle viewport repaired.
#
# Changelog v1.5 (2026):
#   - FIX: The probe loop's "if pythonCmd$ = """ post-check at the
#     end was dead code: the OS-discovery block (lines 36-50) always
#     assigned pythonCmd$ to something non-empty, so total probe
#     failure couldn't be detected. Now pythonCmd$ is cleared
#     before the probe loop, and the early-discovery path (when
#     present) is prepended as the highest-priority candidate.
#     Total Python failure now produces the documented error.
#   - PORTABILITY: Replaced the for-loop early-break that mutated
#     the loop variable (iCand = nCandidates + 1) with a "found"
#     flag pattern. Loop-var mutation works in current Praat but
#     is documented as fragile across versions.
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

runTag$    = replace_regex$(soundName$, "[^A-Za-z0-9_]", "_", 0) + "_" + string$(sound) + "_" + replace_regex$(date$(), "[ :]", "_", 0)
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

# ---- COMPACT FORM ----
form TinySOL Orchestration Retrieval v1.10.3
    optionmenu Preset: 1
        option Custom  (use fields as-is)
        option REF-whole  (whole-file reference preset)
        option REF-frame  (frame-based reference preset)
        option REF-orchids  (Orchidea-architecture preset)
        option Speech  (speech / vocal input)

    sentence DB_directory         D:/old D/waves/TinySOL_2020
    sentence Corpus_root          D:/old D/waves/TinySOL_2020/TinySOL

    optionmenu Instrument_families: 1
        option All families
        option Brass only
        option Strings only
        option Winds only
        option Brass + Strings
        option Brass + Winds
        option Strings + Winds
        option Keyboards only
    sentence Specific_instruments (empty = all)
    integer Min_MIDI_pitch 36
    integer Max_MIDI_pitch 96
    optionmenu Preferred_dynamics: 3
        option pp
        option p
        option mf
        option ff
        option pp + mf
        option mf + ff
        option All dynamics

    optionmenu Analysis_mode: 1
        option Whole file  (average timbre)
        option Frame-based  (follows pitch + dynamics)
    optionmenu Render_mode: 1
        option best  (single best match)
        option blend  (top-3 rank-weighted mix)
        option top2  (top-2 equal mix)
        option top3  (top-3 equal mix)
        option top4  (top-4 equal mix)
    real Envelope_follow 0.85

    boolean Edit_details 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- ADVANCED DEFAULTS ----
# These preserve the v1.9 behaviour when Edit details is not opened.
frame_size_ms = 150
hop_size_ms = 75
pitch_tolerance_semitones = 2
pitch_pan_in_stereo = 0
number_of_results = 8
render_gain = 0.8
mFCC_weight = 0.25
specenv_weight = 0.20
moments_weight = 0.05
specpeaks_weight = 0.15
harmonic_weight = 0.35
stereo_output = 0
speech_mode = 0
silence_threshold = 2.0

# ---- APPLY PRESET ----
# Presets are applied before Edit details so the second dialog exposes the
# actual technical values that will be rendered and can override them knowingly.
if preset = 2
    analysis_mode            = 1
    mFCC_weight              = 0.25
    specenv_weight           = 0.20
    moments_weight           = 0.05
    specpeaks_weight         = 0.15
    harmonic_weight          = 0.35
    preferred_dynamics       = 6
    render_mode              = 1
    stereo_output            = 0
    pitch_pan_in_stereo      = 0
    silence_threshold        = 1.0
    speech_mode              = 0
elsif preset = 3
    analysis_mode            = 2
    frame_size_ms            = 150
    hop_size_ms              = 75
    pitch_tolerance_semitones = 2
    mFCC_weight              = 0.25
    specenv_weight           = 0.20
    moments_weight           = 0.05
    specpeaks_weight         = 0.15
    harmonic_weight          = 0.35
    preferred_dynamics       = 6
    render_mode              = 1
    stereo_output            = 0
    pitch_pan_in_stereo      = 0
    silence_threshold        = 1.0
    speech_mode              = 0
elsif preset = 4
    analysis_mode            = 1
    mFCC_weight              = 0.20
    specenv_weight           = 0.30
    moments_weight           = 0.05
    specpeaks_weight         = 0.10
    harmonic_weight          = 0.35
    preferred_dynamics       = 6
    render_mode              = 1
    stereo_output            = 0
    pitch_pan_in_stereo      = 0
    silence_threshold        = 1.0
    speech_mode              = 0
elsif preset = 5
    analysis_mode            = 1
    mFCC_weight              = 0.45
    specenv_weight           = 0.30
    moments_weight           = 0.10
    specpeaks_weight         = 0.15
    harmonic_weight          = 0.00
    preferred_dynamics       = 6
    render_mode              = 1
    stereo_output            = 0
    pitch_pan_in_stereo      = 0
    silence_threshold        = 2.0
    speech_mode              = 1
endif

if edit_details
    beginPause: "TinySOL Retrieval v1.10.1 - Details"
        comment: "Frame analysis"
        integer: "Frame size (ms)", frame_size_ms
        integer: "Hop size (ms)", hop_size_ms
        integer: "Pitch tolerance (semitones)", pitch_tolerance_semitones
        boolean: "Pitch pan in stereo", pitch_pan_in_stereo

        comment: "Retrieval / render"
        integer: "Number of ranked results", number_of_results
        real: "Render gain", render_gain
        boolean: "Stereo output", stereo_output

        comment: "Descriptor weights (relative)"
        real: "MFCC weight", mFCC_weight
        real: "Spectral-envelope weight", specenv_weight
        real: "Moments weight", moments_weight
        real: "Spectral-peaks weight", specpeaks_weight
        real: "Harmonic weight", harmonic_weight

        comment: "Quality / special mode"
        real: "Silence threshold (2 = disabled)", silence_threshold
        boolean: "Speech mode", speech_mode
    clicked = endPause: "Cancel", "Run", 2, 1
    if clicked = 1
        exitScript: "Cancelled."
    endif
endif

# Sanitize input paths from the UI to ensure forward slashes
dB_directory$ = replace_regex$(dB_directory$, "\\", "/", 0)
corpus_root$  = replace_regex$(corpus_root$, "\\", "/", 0)

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
if envelope_follow < 0
    envelope_follow = 0
endif
if envelope_follow > 1
    envelope_follow = 1
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
    familyStr$ = "Brass,Strings,Winds,Keyboards"
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
elsif instrument_families = 7
    familyStr$ = "Strings,Winds"
else
    familyStr$ = "Keyboards"
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
    # Empty list = no dynamic preference penalty: truly "All dynamics".
    dynStr$ = ""
endif

dynDisplay$ = dynStr$
if preferred_dynamics = 7
    dynDisplay$ = "All"
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

# Speech mode uses the backend's speech-optimised profile and disables
# harmonic/pitch scoring there. Mirror the weights here so the Info panel is honest.
if speech_mode
    mFCC_weight      = 0.45
    specenv_weight   = 0.30
    moments_weight   = 0.10
    specpeaks_weight = 0.15
    harmonic_weight  = 0.00
endif

weightSum = mFCC_weight + specenv_weight + moments_weight + specpeaks_weight + harmonic_weight
if weightSum <= 0
    @cleanUpTempFiles
    exitScript: "At least one descriptor weight must be greater than zero."
endif

# ---- INFO header ----
clearinfo
writeInfoLine:  "=== TinySOL Orchestration Retrieval v1.10.3 ==="
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
appendInfoLine: "Dynamics:   ", dynDisplay$
appendInfoLine: "MIDI range: ", min_MIDI_pitch, " — ", max_MIDI_pitch
appendInfoLine: "Analysis:   ", analysisStr$
if analysis_mode = 2
    appendInfoLine: "Frame/hop:  ", frame_size_ms, " ms / ", hop_size_ms, " ms  pitch_tol: ±", pitch_tolerance_semitones, " st"
endif
appendInfoLine: "Render:     ", renderStr$, "  gain=", fixed$(render_gain, 2), "  stereo=", stereo_output, "  envelope=", fixed$(envelope_follow, 2), "  silence_threshold=", fixed$(silence_threshold, 2)
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

# v1.5: Save the OS-discovery value as a candidate0 (highest priority),
# then clear pythonCmd$ so the post-probe check can detect total failure.
# The OS-discovery block at the top set pythonCmd$ to a path like
# /opt/homebrew/bin/python3 if available — if that path passes the
# probe, it's preferred over the generic "python3" name (which may
# resolve to a different Python on Mac).
earlyDiscovered$ = pythonCmd$
pythonCmd$ = ""

if windows
    nCandidates = 5
    candidate1$ = earlyDiscovered$
    candidate2$ = "python"
    candidate3$ = "py"
    candidate4$ = "py -3"
    candidate5$ = "python3"
else
    nCandidates = 4
    candidate1$ = earlyDiscovered$
    candidate2$ = "python3"
    candidate3$ = "python"
    candidate4$ = "py"
    candidate5$ = ""
endif

found = 0
for iCand from 1 to nCandidates
    if found = 0
        if iCand = 1
            tryCmd$ = candidate1$
        elsif iCand = 2
            tryCmd$ = candidate2$
        elsif iCand = 3
            tryCmd$ = candidate3$
        elsif iCand = 4
            tryCmd$ = candidate4$
        else
            tryCmd$ = candidate5$
        endif

        # Skip empty candidate slot (Linux candidate5)
        if tryCmd$ <> ""
            if fileReadable(probeMarker$)
                deleteFile: probeMarker$
            endif

            runSystem_nocheck: tryCmd$ + " """ + probePyJ$ + """"

            if fileReadable(probeMarker$)
                pythonCmd$ = tryCmd$
                deleteFile: probeMarker$
                found = 1
            endif
        endif
    endif
endfor

deleteFile: probePy$

if pythonCmd$ = ""
    @cleanUpTempFiles
    exitScript: "Cannot find Python 3 installation with required packages." + newline$ + "Tried: " + earlyDiscovered$ + ", python3, python, py" + newline$ + "Please install: pip install numpy scipy soundfile"
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
appendFileLine: tempParams$, "envelope_follow=" + string$(envelope_follow)
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

bestMatch$       = "?"
bestScore$       = "?"
rank2Match$      = "?"
rank2Score$      = "?"
rank3Match$      = "?"
rank3Score$      = "?"
rank4Match$      = "?"
rank4Score$      = "?"
nCandidates$     = "?"
renderMode$      = "?"
chosenCount$     = "?"
envCorrBefore$   = "?"
envCorrAfter$    = "?"
rank1Usage$      = "?"
rank2Usage$      = "?"
rank3Usage$      = "?"
rank4Usage$      = "?"
silenceFlag$     = ""
resultText$      = ""

if fileReadable(tempResults$)
    resultText$ = readFile$(tempResults$)

    @parseStatLine: resultText$, "n_candidates="
    nCandidates$ = parseStatLine.result$
    @parseStatLine: resultText$, "render_mode="
    renderMode$ = parseStatLine.result$
    @parseStatLine: resultText$, "chosen_count="
    chosenCount$ = parseStatLine.result$
    @parseStatLine: resultText$, "envelope_corr_before="
    envCorrBefore$ = parseStatLine.result$
    @parseStatLine: resultText$, "envelope_corr_after="
    envCorrAfter$ = parseStatLine.result$
    @parseStatLine: resultText$, "rank1_usage_pct="
    rank1Usage$ = parseStatLine.result$
    @parseStatLine: resultText$, "rank2_usage_pct="
    rank2Usage$ = parseStatLine.result$
    @parseStatLine: resultText$, "rank3_usage_pct="
    rank3Usage$ = parseStatLine.result$
    @parseStatLine: resultText$, "rank4_usage_pct="
    rank4Usage$ = parseStatLine.result$

    @parseStatLine: resultText$, "silence_rendered="
    silenceRendered$ = parseStatLine.result$
    @parseStatLine: resultText$, "silence_reason="
    silenceReason$ = parseStatLine.result$
    if silenceRendered$ = "1"
        if silenceReason$ = "silent_target"
            silenceFlag$ = "  [SILENCE - silent target]"
        elsif silenceReason$ = "frame_unmatched"
            silenceFlag$ = "  [SILENCE - no frame matches]"
        else
            silenceFlag$ = "  [SILENCE - score > threshold]"
        endif
    endif

    @parseRankLine: resultText$, 1
    bestMatch$ = parseRankLine.match$
    bestScore$ = parseRankLine.score$
    rank1Family$ = parseRankLine.family$
    rank1Inst$ = parseRankLine.inst$
    rank1Note$ = parseRankLine.note$
    rank1Dyn$ = parseRankLine.dyn$
    @parseRankLine: resultText$, 2
    rank2Match$ = parseRankLine.match$
    rank2Score$ = parseRankLine.score$
    rank2Family$ = parseRankLine.family$
    rank2Inst$ = parseRankLine.inst$
    rank2Note$ = parseRankLine.note$
    rank2Dyn$ = parseRankLine.dyn$
    @parseRankLine: resultText$, 3
    rank3Match$ = parseRankLine.match$
    rank3Score$ = parseRankLine.score$
    rank3Family$ = parseRankLine.family$
    rank3Inst$ = parseRankLine.inst$
    rank3Note$ = parseRankLine.note$
    rank3Dyn$ = parseRankLine.dyn$
    @parseRankLine: resultText$, 4
    rank4Match$ = parseRankLine.match$
    rank4Score$ = parseRankLine.score$
    rank4Family$ = parseRankLine.family$
    rank4Inst$ = parseRankLine.inst$
    rank4Note$ = parseRankLine.note$
    rank4Dyn$ = parseRankLine.dyn$
endif


# Safe defaults for visualization when a results file is missing or incomplete.
if bestMatch$ = "?"
    rank1Family$ = "?"
    rank1Inst$ = "?"
    rank1Note$ = "?"
    rank1Dyn$ = "?"
    rank2Family$ = "?"
    rank2Inst$ = "?"
    rank2Note$ = "?"
    rank2Dyn$ = "?"
    rank3Family$ = "?"
    rank3Inst$ = "?"
    rank3Note$ = "?"
    rank3Dyn$ = "?"
    rank4Family$ = "?"
    rank4Inst$ = "?"
    rank4Note$ = "?"
    rank4Dyn$ = "?"
endif

# ===========================================================================
# Visualization (optional)
# ===========================================================================
if draw_visualization
    appendInfoLine: "Drawing visualization..."

    # Representative real channels: strongest RMS input and output channels.
    analysisChannel = 1
    bestVizRms = -1
    for ch from 1 to nChannels
        selectObject: sound
        chObj = Extract one channel: ch
        chRms = Get root-mean-square: 0, 0
        if chRms > bestVizRms
            bestVizRms = chRms
            analysisChannel = ch
        endif
        removeObject: chObj
    endfor

    selectObject: sound
    if nChannels > 1
        vizIn = Extract one channel: analysisChannel
    else
        Copy: "tinysol_viz_input"
        vizIn = selected("Sound")
    endif

    selectObject: resultSound
    nChRes = Get number of channels
    resultChannel = 1
    bestOutRms = -1
    for ch from 1 to nChRes
        selectObject: resultSound
        chObj = Extract one channel: ch
        chRms = Get root-mean-square: 0, 0
        if chRms > bestOutRms
            bestOutRms = chRms
            resultChannel = ch
        endif
        removeObject: chObj
    endfor
    selectObject: resultSound
    if nChRes > 1
        vizOut = Extract one channel: resultChannel
    else
        Copy: "tinysol_viz_output"
        vizOut = selected("Sound")
    endif

    # Shared waveform amplitude scale.
    selectObject: vizIn
    inPeak = Get absolute extremum: 0, 0, "none"
    selectObject: vizOut
    outPeak = Get absolute extremum: 0, 0, "none"
    wavePeak = 1.05 * max(inPeak, outPeak)
    if wavePeak < 0.000001
        wavePeak = 1
    endif

    # User-facing source profile. Pitch is descriptive only; retrieval continues
    # to use the backend's own validated analysis.
    sourcePitch$ = "No stable pitch"
    pitchCeiling = min(3000, 0.45 * sr)
    if pitchCeiling > 50
        selectObject: vizIn
        sourcePitchObj = To Pitch: 0.0, 50, pitchCeiling
        selectObject: sourcePitchObj
        sourcePitchHz = Get quantile: 0, 0, 0.5, "Hertz"
        if sourcePitchHz <> undefined
            sourceMidi = 69 + 12 * ln(sourcePitchHz / 440) / ln(2)
            sourcePitch$ = fixed$(sourcePitchHz, 1) + " Hz  (~MIDI " + fixed$(sourceMidi, 1) + ")"
        endif
        removeObject: sourcePitchObj
    endif

    if rms_orig > 0
        sourceLevelDb = 20 * ln(rms_orig) / ln(10)
        sourceLevel$ = fixed$(sourceLevelDb, 1) + " dBFS RMS"
    else
        sourceLevel$ = "silence"
    endif
    if rms_out > 0
        outputLevelDb = 20 * ln(rms_out) / ln(10)
        outputLevel$ = fixed$(outputLevelDb, 1) + " dBFS RMS"
    else
        outputLevel$ = "silence"
    endif

    displaySoundName$ = replace$(soundName$, "_", " ", 0)
    if instrument_families = 1
        familyViz$ = "All families"
    elsif instrument_families = 5
        familyViz$ = "Brass + Strings"
    elsif instrument_families = 6
        familyViz$ = "Brass + Winds"
    elsif instrument_families = 7
        familyViz$ = "Strings + Winds"
    else
        familyViz$ = familyStr$
    endif

    # How many ranked whole-file choices actually enter the selected render mode.
    usedRanks = 1
    if analysis_mode = 1
        if render_mode = 2
            usedRanks = 3
        elsif render_mode = 3
            usedRanks = 2
        elsif render_mode = 4
            usedRanks = 3
        elsif render_mode = 5
            usedRanks = 4
        endif
    endif

    Erase all
    Select outer viewport: 0, 8, 0, 7.2

    # ----------------------------------------------------------
    # Header
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.58
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half", "##TinySOL Orchestration Retrieval##"
    Font size: 6.3
    Colour: "{0.35, 0.35, 0.48}"
    Text: 0.5, "centre", -1.24, "half",
        ... displaySoundName$ + "  |  search: " + familyViz$ + "  |  MIDI "
        ... + string$(min_MIDI_pitch) + "-" + string$(max_MIDI_pitch)

    # ----------------------------------------------------------
    # SELECTED SOUND: waveform + compact profile card
    # ----------------------------------------------------------
    Select outer viewport: 0, 5.15, 0.72, 2.18
    Select inner viewport: 0.55, 4.98, 0.82, 2.05
    selectObject: vizIn
    Colour: "{0.53, 0.53, 0.53}"
    Draw: 0, 0, -wavePeak, wavePeak, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Selected sound"
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"

    Select outer viewport: 5.25, 8, 0.72, 2.18
    Select inner viewport: 5.35, 7.88, 0.82, 2.05
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1
    Colour: "Black"
    Font size: 7.2
    Text: 0.05, "left", 0.88, "half", "##Sound profile##"
    Font size: 5.8
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.05, "left", 0.68, "half", "Duration   " + fixed$(dur, 2) + " s"
    Text: 0.05, "left", 0.51, "half", "Channels   " + string$(nChannels) + "   |   " + string$(sr) + " Hz"
    Text: 0.05, "left", 0.34, "half", "Level      " + sourceLevel$
    Text: 0.05, "left", 0.17, "half", "Pitch      " + sourcePitch$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # ----------------------------------------------------------
    # INSTRUMENT CHOICES: musical result of retrieval
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 2.34, 4.45
    Select inner viewport: 0.45, 7.75, 2.46, 4.32
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.975, 0.975, 0.975}", 0, 1, 0, 1
    Colour: "Black"
    Font size: 8
    if analysis_mode = 2
        Text: 0.02, "left", 0.92, "half", "##Instrument choices across the sound##"
        Font size: 5.3
        Colour: "{0.36, 0.36, 0.36}"
        Text: 0.98, "right", 0.92, "half", "ranked by frame usage"
    else
        Text: 0.02, "left", 0.92, "half", "##Instrument choices##"
        Font size: 5.3
        Colour: "{0.36, 0.36, 0.36}"
        Text: 0.98, "right", 0.92, "half", "highlighted = used in render"
    endif

    # Four user-facing choice cards. Colour indicates participation in the render,
    # not descriptor value; scores remain secondary text only.
    c1x0 = 0.02
    c1x1 = 0.245
    c2x0 = 0.265
    c2x1 = 0.49
    c3x0 = 0.51
    c3x1 = 0.735
    c4x0 = 0.755
    c4x1 = 0.98
    cy0 = 0.12
    cy1 = 0.78

    if analysis_mode = 2 or usedRanks >= 1
        Paint rectangle: "{0.90, 0.96, 0.93}", c1x0, c1x1, cy0, cy1
    else
        Paint rectangle: "{0.95, 0.95, 0.95}", c1x0, c1x1, cy0, cy1
    endif
    if analysis_mode = 2 or usedRanks >= 2
        Paint rectangle: "{0.90, 0.96, 0.93}", c2x0, c2x1, cy0, cy1
    else
        Paint rectangle: "{0.95, 0.95, 0.95}", c2x0, c2x1, cy0, cy1
    endif
    if analysis_mode = 2 or usedRanks >= 3
        Paint rectangle: "{0.90, 0.96, 0.93}", c3x0, c3x1, cy0, cy1
    else
        Paint rectangle: "{0.95, 0.95, 0.95}", c3x0, c3x1, cy0, cy1
    endif
    if analysis_mode = 2 or usedRanks >= 4
        Paint rectangle: "{0.90, 0.96, 0.93}", c4x0, c4x1, cy0, cy1
    else
        Paint rectangle: "{0.95, 0.95, 0.95}", c4x0, c4x1, cy0, cy1
    endif

    # Card borders
    Colour: "{0.45, 0.45, 0.45}"
    Draw rectangle: c1x0, c1x1, cy0, cy1
    Draw rectangle: c2x0, c2x1, cy0, cy1
    Draw rectangle: c3x0, c3x1, cy0, cy1
    Draw rectangle: c4x0, c4x1, cy0, cy1

    # Rank 1
    Colour: "Black"
    Font size: 6.2
    Text: c1x0 + 0.018, "left", 0.70, "half", "#1"
    Font size: 8.0
    Text: 0.5 * (c1x0 + c1x1), "centre", 0.57, "half", rank1Inst$
    Font size: 5.3
    Colour: "{0.32, 0.32, 0.32}"
    Text: 0.5 * (c1x0 + c1x1), "centre", 0.43, "half", rank1Family$
    Text: 0.5 * (c1x0 + c1x1), "centre", 0.30, "half", rank1Note$ + "   " + rank1Dyn$
    if analysis_mode = 2 and rank1Usage$ <> "?"
        Text: 0.5 * (c1x0 + c1x1), "centre", 0.18, "half", rank1Usage$ + "% of matched frames"
    else
        Text: 0.5 * (c1x0 + c1x1), "centre", 0.18, "half", "distance " + bestScore$
    endif

    # Rank 2
    Colour: "Black"
    Font size: 6.2
    Text: c2x0 + 0.018, "left", 0.70, "half", "#2"
    Font size: 8.0
    Text: 0.5 * (c2x0 + c2x1), "centre", 0.57, "half", rank2Inst$
    Font size: 5.3
    Colour: "{0.32, 0.32, 0.32}"
    Text: 0.5 * (c2x0 + c2x1), "centre", 0.43, "half", rank2Family$
    Text: 0.5 * (c2x0 + c2x1), "centre", 0.30, "half", rank2Note$ + "   " + rank2Dyn$
    if analysis_mode = 2 and rank2Usage$ <> "?"
        Text: 0.5 * (c2x0 + c2x1), "centre", 0.18, "half", rank2Usage$ + "% of matched frames"
    else
        Text: 0.5 * (c2x0 + c2x1), "centre", 0.18, "half", "distance " + rank2Score$
    endif

    # Rank 3
    Colour: "Black"
    Font size: 6.2
    Text: c3x0 + 0.018, "left", 0.70, "half", "#3"
    Font size: 8.0
    Text: 0.5 * (c3x0 + c3x1), "centre", 0.57, "half", rank3Inst$
    Font size: 5.3
    Colour: "{0.32, 0.32, 0.32}"
    Text: 0.5 * (c3x0 + c3x1), "centre", 0.43, "half", rank3Family$
    Text: 0.5 * (c3x0 + c3x1), "centre", 0.30, "half", rank3Note$ + "   " + rank3Dyn$
    if analysis_mode = 2 and rank3Usage$ <> "?"
        Text: 0.5 * (c3x0 + c3x1), "centre", 0.18, "half", rank3Usage$ + "% of matched frames"
    else
        Text: 0.5 * (c3x0 + c3x1), "centre", 0.18, "half", "distance " + rank3Score$
    endif

    # Rank 4
    Colour: "Black"
    Font size: 6.2
    Text: c4x0 + 0.018, "left", 0.70, "half", "#4"
    Font size: 8.0
    Text: 0.5 * (c4x0 + c4x1), "centre", 0.57, "half", rank4Inst$
    Font size: 5.3
    Colour: "{0.32, 0.32, 0.32}"
    Text: 0.5 * (c4x0 + c4x1), "centre", 0.43, "half", rank4Family$
    Text: 0.5 * (c4x0 + c4x1), "centre", 0.30, "half", rank4Note$ + "   " + rank4Dyn$
    if analysis_mode = 2 and rank4Usage$ <> "?"
        Text: 0.5 * (c4x0 + c4x1), "centre", 0.18, "half", rank4Usage$ + "% of matched frames"
    else
        Text: 0.5 * (c4x0 + c4x1), "centre", 0.18, "half", "distance " + rank4Score$
    endif

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # ----------------------------------------------------------
    # RENDERED RESULT: waveform + concise result card
    # ----------------------------------------------------------
    Select outer viewport: 0, 5.15, 4.62, 6.08
    Select inner viewport: 0.55, 4.98, 4.72, 5.95
    selectObject: vizOut
    Colour: "{0.15, 0.50, 0.35}"
    Draw: 0, 0, -wavePeak, wavePeak, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Rendered result  [same amplitude scale]"
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"

    Select outer viewport: 5.25, 8, 4.62, 6.08
    Select inner viewport: 5.35, 7.88, 4.72, 5.95
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.97, 0.95}", 0, 1, 0, 1
    Colour: "Black"
    Font size: 7.2
    Text: 0.05, "left", 0.88, "half", "##Rendered orchestration##"
    Font size: 5.7
    Colour: "{0.28, 0.28, 0.28}"
    if analysis_mode = 2
        Text: 0.05, "left", 0.68, "half", "Frames matched   " + chosenCount$ + " / " + nCandidates$
        Text: 0.05, "left", 0.51, "half", "Primary choice   " + rank1Inst$ + "  " + rank1Note$ + "  " + rank1Dyn$
    else
        Text: 0.05, "left", 0.68, "half", "Render           " + renderMode$
        Text: 0.05, "left", 0.51, "half", "Primary choice   " + rank1Inst$ + "  " + rank1Note$ + "  " + rank1Dyn$
    endif
    Text: 0.05, "left", 0.34, "half", "Duration         " + fixed$(dur_out, 2) + " s"
    Text: 0.05, "left", 0.17, "half", "Level            " + outputLevel$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # ----------------------------------------------------------
    # Small footer: only information useful for interpretation
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.22, 6.92
    Select inner viewport: 0.45, 7.75, 6.30, 6.84
    Axes: 0, 1, 0, 1
    Font size: 5.6
    Colour: "{0.34, 0.34, 0.34}"
    if analysis_mode = 2
        Text: 0.02, "left", 0.66, "half",
            ... "Frame-based retrieval  |  frame " + string$(frame_size_ms) + " ms  |  hop "
            ... + string$(hop_size_ms) + " ms  |  pitch tolerance +/-" + string$(pitch_tolerance_semitones) + " st"
    else
        Text: 0.02, "left", 0.66, "half",
            ... "Whole-file retrieval  |  " + nCandidates$ + " legal TinySOL candidates  |  preferred dynamics: " + dynDisplay$
    endif
    if envelope_follow > 0
        Text: 0.02, "left", 0.26, "half",
            ... "Target envelope follow " + fixed$(envelope_follow, 2) + "  |  output " + string$(nChRes) + " channel(s)" + silenceFlag$
    else
        Text: 0.02, "left", 0.26, "half",
            ... "No target-envelope transfer  |  output " + string$(nChRes) + " channel(s)" + silenceFlag$
    endif

    removeObject: vizIn, vizOut

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
procedure parseRankLine: .text$, .rank
    .match$ = "?"
    .score$ = "?"
    .family$ = "?"
    .inst$ = "?"
    .note$ = "?"
    .dyn$ = "?"
    .needle$ = newline$ + string$(.rank) + ","
    .pos = index(.text$, .needle$)
    if .pos = 0
        .needle$ = unicode$(10) + string$(.rank) + ","
        .pos = index(.text$, .needle$)
    endif
    if .pos > 0
        .lineStart = .pos + 1
        .tail$ = mid$(.text$, .lineStart, length(.text$) - .lineStart + 1)
        .nl = index(.tail$, newline$)
        if .nl > 0
            .line$ = left$(.tail$, .nl - 1)
        else
            .line$ = .tail$
        endif

        .field$ = .line$
        # rank
        .p = index(.field$, ",")
        if .p > 0
            .field$ = mid$(.field$, .p + 1, length(.field$) - .p)
        endif
        # score
        .p = index(.field$, ",")
        if .p > 0
            .score$ = left$(.field$, .p - 1)
            .field$ = mid$(.field$, .p + 1, length(.field$) - .p)
        endif
        # family
        .p = index(.field$, ",")
        if .p > 0
            .family$ = left$(.field$, .p - 1)
            .field$ = mid$(.field$, .p + 1, length(.field$) - .p)
        endif
        # instrument
        .p = index(.field$, ",")
        if .p > 0
            .inst$ = left$(.field$, .p - 1)
            .field$ = mid$(.field$, .p + 1, length(.field$) - .p)
        endif
        # note
        .p = index(.field$, ",")
        if .p > 0
            .note$ = left$(.field$, .p - 1)
            .field$ = mid$(.field$, .p + 1, length(.field$) - .p)
        endif
        # midi skip
        .p = index(.field$, ",")
        if .p > 0
            .field$ = mid$(.field$, .p + 1, length(.field$) - .p)
        endif
        # dynamic
        .p = index(.field$, ",")
        if .p > 0
            .dyn$ = left$(.field$, .p - 1)
        else
            .dyn$ = .field$
        endif
        .match$ = .family$ + " " + .inst$ + " " + .note$ + " " + .dyn$
    endif
endproc

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