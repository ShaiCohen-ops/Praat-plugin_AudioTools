# ============================================================
# Praat AudioTools - TinySOL_Retrieval.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.11.6 (2026) - Fixed instrument ensemble, one channel per instrument, orchestration map
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
#     5. Selects a FIXED ensemble of 1-4 distinct instruments (Render mode)
#        and renders each instrument on its own channel.
#     6. Returns the channels (temporary exchange file) + a results text
#        file with the ranking (diagnostic) and the rendered channel map.
#   Praat imports ONE multichannel Sound (<name>_orchestrated), draws the
#   orchestration map and deletes every temporary file.
#
# Changelog v1.11.6 (2026):
#   - Frame mode: Render mode = number of instruments in the WHOLE result.
#     A global allocation (energy-weighted mean of each instrument's best
#     frame score, uncovered frames penalised) picks the fixed ensemble; each
#     instrument then gets its own Viterbi voice restricted to its samples.
#     Channels never change identity; an instrument may rest and re-enter.
#   - Fewer instruments than requested -> fewer channels + reason (Info).
#   - Layer selection option removed (it restored variable instruments).
#   - Events: under Spectral interpretation F0 changes never split events;
#     in Auto a pitch step needs a confirming frame and must not be a mere
#     decay without new energy (bell subharmonic case).  Partials that only
#     surface because others decayed are not "new partials".
#   - --verify-db: an empty/missing directory fails (exit 2), partial
#     availability is PARTIAL (exit 3), COMPLETE lists every checked table.
#   - Figure redesigned: header, source, ORCHESTRATION MAP (whole file:
#     channel table; frame-based: measured activity over time per channel),
#     rendered reference sum on the same scale, measured level summary.
#     Drawn only from the rendered channel map, never from ranking cards.
#
# Changelog v1.11.5 (2026):
#   - Multichannel in practice: layers are now DISTINCT instruments.  v1.11.4
#     gave one channel per distinct instrument, but the layers themselves were
#     the top-N samples (often N samples of one instrument) and frame mode
#     rendered a single voice, so most runs ended with a 1-channel Sound.
#   - Render_mode = number of instrument layers (best 1, blend 3 rank-
#     weighted, top2/3/4); default is now blend (3 instruments), also in the
#     presets.  Whole file: best-scoring entry of each instrument, in score
#     order.  Frame mode: one Viterbi voice per layer, each frame excluding
#     instruments already used by earlier voices (polyphonic events: also
#     uncovered chord notes first).  Voice 1 = the former single-voice path.
#   - Edit details > Layer selection: "Best scores" restores v1.11.4 layering.
#
# Changelog v1.11.4 (2026):
#   - OUTPUT: every run creates exactly ONE new Sound, <name>_orchestrated,
#     with one channel per distinct rendered instrument (channel map in the
#     Info window).  It is the only audio result: no mono/stereo preview, no
#     exported WAV, no saved report.  Python writes the channels to the usual
#     temporary output file; Praat reads it and deletes every temporary file.
#   - Removed: Stereo output, Pitch pan in stereo, Save multichannel WAV,
#     Multichannel destination, Save analysis report (it wrote to ~).
#   - Level matching is measured on the internal reference mix (sum of the
#     channels; never shown as an object) and applied as one gain to all.
#   - No instrument rendered (silent target, no match, ...) -> no Sound is
#     created and the reason is written to the Info window.
#   - Playback: 1-2 channels are played as they are; with more channels the
#     temporary reference mix is played (the Sound keeps all its channels).
#
# Changelog v1.11.3 (2026):
#   - LEVEL: the result is no longer peak-normalised to Render gain.  After
#     rendering and envelope transfer, the complete mix is measured with
#     BS.1770-4 K-weighted gated loudness (channel mean) and ONE scalar gain
#     matches it to the target.  Edit details > Final level matching:
#     Match target (attenuate only) [default] / Match target (bidirectional,
#     max +12 dB) / Off (manual peak gain = v1.11.2 behaviour).  In the
#     matching modes Render gain is a peak CEILING, never a target.
#   - MULTICHANNEL: optional 32-bit float WAV with one mono channel per
#     rendered instrument (stems built inside the renderer, same overlap-add
#     normalisation, same envelope curve and same master gain as the mix;
#     channels sum to the mono mix).  Existing files are never overwritten.
#   - Info window: target / rendered / final loudness, correction, peak,
#     channel map.  Retrieval, pitch and event logic unchanged.
#
# Changelog v1.11.2 (2026):
#   - FIX: a chord/bell/noise with no VERIFIED timbral descriptor (e.g. the
#     original Orchidea .db files, category C) rendered silence reported as
#     "no frame matches".  The backend now stops with the reason and the
#     --build-db command; Praat shows it as an error message.
#
# Changelog v1.11.1 (2026):
#   - PITCH CONFIDENCE: every frame now carries periodicity, harmonic-series
#     support (with the fundamental present), harmonic occupancy, tonality and
#     temporal consistency.  Only RELIABLE frames constrain pitch; no harmonic
#     series is invented from an uncertain F0; the last pitch is never reused
#     for an ambiguous frame.
#   - EVENTS: frames are grouped into acoustic events (onset energy, new
#     partials, pitch steps; decays, balance changes, vibrato and glides are
#     not boundaries).  Each event is Monophonic, Spectral (e.g. bell),
#     Polyphonic (e.g. chord), Unpitched or Ambiguous.  Only monophonic events
#     use the pitch gate + harmonic scoring; the others are retrieved
#     pitch-neutrally (polyphonic: restricted to the detected component notes).
#   - SELECTION: the per-frame persistence bonus is replaced by event-level
#     selection (Viterbi) with a switch cost, so momentary changes cannot flip
#     the sample, while new events and real pitch changes still can.
#   - RENDER: each event restarts the corpus sample (repeated attacks are
#     re-articulated); reading stays phase-coherent across selection changes.
#   - UI: Edit details > Pitch interpretation (Auto / Monophonic / Spectral);
#     REF-frame uses Auto.  The figure states the interpretation and no longer
#     shows an uncertain F0 as a note.
#
# Changelog v1.11.0 (2026):
#   - DESCRIPTOR VALIDITY: the backend accepts a TinySOL .db table only when
#     it can RECOMPUTE the stored vectors from corpus WAVs with a named
#     extraction contract (A = AudioTools, B = documented Orchidea definition).
#     Unverified tables (C) are excluded and reported, never scored silently.
#     Vector length alone no longer qualifies a database (v1.10.3 treated a
#     1024-value cepstral Orchidea envelope as if it were 1024 linear bands).
#     Build verified tables with:  python tinysol_retrieval.py --build-db ...
#   - CALIBRATED SCORES: each descriptor distance is divided by the median
#     distance between random corpus pairs, so 1.0 = "as far apart as a typical
#     pair of TinySOL notes" and the weights are genuinely relative.
#   - MOMENTS: level-dependent PMF floor removed (a -40 dB sine had 8000x the
#     kurtosis); robust log/asinh distance.  Default weight 0 until validated.
#   - SPECPEAKS: default weight 0 -- the stored representation (16 strongest
#     maxima without frequencies) was shown to encode duration on noisy or
#     vibrato sounds.  Still selectable in Edit details.
#   - MATCH THRESHOLD replaces Silence threshold: calibrated units, 0 = off in
#     both modes.  REF-orchids now really has the gate off (it set 1.0 before).
#   - RENDER: output duration = selected Sound by default (optional "Preserve
#     natural sample duration"); cut layers get a 20 ms fade; Render gain is a
#     peak target <= 1 (no clipping); highlighted cards = layers actually
#     rendered; silence reasons are explicit.
#   - FRAME MODE uses the same 4096/2048 descriptor contract as whole-file
#     mode; frame size must be >= 93 ms.
#   - Optional "Save analysis report" (JSON) -- removed again in v1.11.4.
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
form TinySOL Orchestration Retrieval v1.11.6
    optionmenu Preset: 1
        option Custom  (use fields as-is)
        option REF-whole  (whole-file reference preset)
        option REF-frame  (frame-based reference preset)
        option REF-orchids  (Orchidea-architecture preset)
        option Speech  (speech / vocal input)

    sentence DB_directory         D:/old D/waves/TinySOL_AT1_db
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
    optionmenu Render_mode: 2
        option best  (1 instrument = 1 channel)
        option blend  (3 instruments, rank-weighted)
        option top2  (2 instruments, equal mix)
        option top3  (3 instruments, equal mix)
        option top4  (4 instruments, equal mix)
    real Envelope_follow 0.85

    boolean Edit_details 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- ADVANCED DEFAULTS ----
# Used when Edit details is not opened.  Moments and spectral-peaks weights
# are 0 by default in v1.11.0 (see changelog); they remain editable.
frame_size_ms = 150
hop_size_ms = 75
pitch_tolerance_semitones = 2
number_of_results = 8
render_gain = 0.8
mFCC_weight = 0.25
specenv_weight = 0.20
moments_weight = 0
specpeaks_weight = 0
harmonic_weight = 0.35
speech_mode = 0
match_threshold = 0
preserve_natural_sample_duration = 0
pitch_interpretation = 1
final_level_matching = 1


# ---- APPLY PRESET ----
# Presets are applied before Edit details so the second dialog exposes the
# actual technical values that will be rendered and can override them knowingly.
# v1.11.0: moments/specpeaks are 0 in every preset (not validated), and the
# match gate is off (0): the v1.10.3 threshold values belonged to a score
# scale that no longer exists.
if preset = 2
    analysis_mode            = 1
    mFCC_weight              = 0.25
    specenv_weight           = 0.20
    moments_weight           = 0
    specpeaks_weight         = 0
    harmonic_weight          = 0.35
    preferred_dynamics       = 6
    render_mode              = 2
    match_threshold          = 0
    speech_mode              = 0
elsif preset = 3
    analysis_mode            = 2
    frame_size_ms            = 150
    hop_size_ms              = 75
    pitch_tolerance_semitones = 2
    pitch_interpretation     = 1
    mFCC_weight              = 0.25
    specenv_weight           = 0.20
    moments_weight           = 0
    specpeaks_weight         = 0
    harmonic_weight          = 0.35
    preferred_dynamics       = 6
    render_mode              = 2
    match_threshold          = 0
    speech_mode              = 0
elsif preset = 4
    analysis_mode            = 1
    mFCC_weight              = 0.20
    specenv_weight           = 0.30
    moments_weight           = 0
    specpeaks_weight         = 0
    harmonic_weight          = 0.35
    preferred_dynamics       = 6
    render_mode              = 2
    match_threshold          = 0
    speech_mode              = 0
elsif preset = 5
    analysis_mode            = 1
    mFCC_weight              = 0.45
    specenv_weight           = 0.30
    moments_weight           = 0
    specpeaks_weight         = 0
    harmonic_weight          = 0.00
    preferred_dynamics       = 6
    render_mode              = 2
    match_threshold          = 0
    speech_mode              = 1
endif

if edit_details
    beginPause: "TinySOL Retrieval v1.11.6 - Details"
        comment: "Frame analysis (frame size >= 93 ms = one descriptor window)"
        integer: "Frame size (ms)", frame_size_ms
        integer: "Hop size (ms)", hop_size_ms
        integer: "Pitch tolerance (semitones)", pitch_tolerance_semitones
        choice: "Pitch interpretation", pitch_interpretation
            option: "Auto (confidence-aware events)"
            option: "Monophonic (known single-line input)"
            option: "Spectral (no pitch constraints)"

        comment: "Retrieval / render"
        integer: "Number of ranked results", number_of_results
        real: "Render gain (peak ceiling, max 1)", render_gain
        boolean: "Preserve natural sample duration", preserve_natural_sample_duration
        choice: "Final level matching", final_level_matching
            option: "Match target (attenuate only)"
            option: "Match target (bidirectional)"
            option: "Off (manual peak gain)"

        comment: "Descriptor weights (relative; moments + peaks experimental)"
        real: "MFCC weight", mFCC_weight
        real: "Spectral-envelope weight", specenv_weight
        real: "Moments weight", moments_weight
        real: "Spectral-peaks weight", specpeaks_weight
        real: "Harmonic weight", harmonic_weight

        comment: "Match threshold: 1 = typical distance between two corpus notes"
        real: "Match threshold (0 = off)", match_threshold
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
if render_gain > 1
    render_gain = 1
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
if match_threshold < 0
    match_threshold = 0
endif

# ---- Resolve analysis mode ----
if analysis_mode = 1
    analysisStr$ = "whole_file"
else
    analysisStr$ = "frame_based"
endif

# ---- Clamp frame params ----
if frame_size_ms < 93
    frame_size_ms = 93
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
    moments_weight   = 0
    specpeaks_weight = 0
    harmonic_weight  = 0.00
endif

if pitch_interpretation = 2
    interpStr$ = "monophonic"
elsif pitch_interpretation = 3
    interpStr$ = "spectral"
else
    interpStr$ = "auto"
endif

if final_level_matching = 2
    levelStr$ = "bidirectional"
elsif final_level_matching = 3
    levelStr$ = "off"
else
    levelStr$ = "attenuate"
endif

if preserve_natural_sample_duration
    durationStr$ = "natural"
else
    durationStr$ = "target"
endif


weightSum = mFCC_weight + specenv_weight + moments_weight + specpeaks_weight + harmonic_weight
if weightSum <= 0
    @cleanUpTempFiles
    exitScript: "At least one descriptor weight must be greater than zero."
endif

# ---- INFO header ----
clearinfo
writeInfoLine:  "=== TinySOL Orchestration Retrieval v1.11.6 ==="
appendInfoLine: "Input:   ", soundName$
appendInfoLine: "DB dir:  ", dB_directory$
appendInfoLine: "Corpus:  ", corpus_root$
if preset = 2
    appendInfoLine: ">>> Preset: REF-whole applied <<<"
elsif preset = 3
    appendInfoLine: ">>> Preset: REF-frame applied <<<"
elsif preset = 4
    appendInfoLine: ">>> Preset: REF-orchids applied (hard MIDI filter, match gate off) <<<"
elsif preset = 5
    appendInfoLine: ">>> Preset: Speech applied (MFCC + spectral envelope only, no pitch scoring) <<<"
endif
appendInfoLine: ""
appendInfoLine: "Families:   ", familyStr$
appendInfoLine: "Dynamics:   ", dynDisplay$
appendInfoLine: "MIDI range: ", min_MIDI_pitch, " — ", max_MIDI_pitch
appendInfoLine: "Analysis:   ", analysisStr$
if analysis_mode = 2
    appendInfoLine: "Frame/hop:  ", frame_size_ms, " ms / ", hop_size_ms, " ms  pitch_tol: ±", pitch_tolerance_semitones, " st"
endif
appendInfoLine: "Pitch:      interpretation = ", interpStr$
if match_threshold > 0
    gateText$ = fixed$(match_threshold, 2)
else
    gateText$ = "off"
endif
appendInfoLine: "Level:      final level matching = ", levelStr$, "   (render gain = peak ", if levelStr$ = "off" then "target" else "ceiling" fi, ")"
appendInfoLine: "Render:     ", renderStr$, "  peak=", fixed$(render_gain, 2), "  output=one channel per instrument  envelope=", fixed$(envelope_follow, 2), "  duration=", durationStr$, "  match gate=", gateText$
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
appendFileLine: tempParams$, "analysis_mode=" + analysisStr$
appendFileLine: tempParams$, "frame_size_ms=" + string$(frame_size_ms)
appendFileLine: tempParams$, "hop_size_ms=" + string$(hop_size_ms)
appendFileLine: tempParams$, "pitch_tolerance=" + string$(pitch_tolerance_semitones)
appendFileLine: tempParams$, "match_threshold=" + string$(match_threshold)
appendFileLine: tempParams$, "speech_mode=" + string$(speech_mode)
appendFileLine: tempParams$, "duration_policy=" + durationStr$
appendFileLine: tempParams$, "pitch_interpretation=" + interpStr$
appendFileLine: tempParams$, "level_matching=" + levelStr$

# ===========================================================================
# Stage 3 — Run Python backend
# ===========================================================================
appendInfoLine: "[3/5] Running Python retrieval engine..."
appendInfoLine: "  (a few seconds: the .db files are verified against corpus WAVs"
appendInfoLine: "   and the score calibration is computed on every run)"
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
else
    @cleanUpTempFiles
    exitScript: "Python backend did not finish (no completion marker)." + newline$ + "Check the Praat Info window and verify paths."
endif

# ===========================================================================
# Stage 4 — Import result
# ===========================================================================
appendInfoLine: "[4/5] Importing result..."

# The temporary output holds ONE channel per rendered instrument.  It is
# absent when no instrument was rendered: then no Sound is created.
resultSound = 0
refMix = 0
nChRes = 0
dur_out = 0
rms_out = 0
if fileReadable(tempOutput$)
    Read from file: tempOutput$
    resultSound = selected("Sound")
    Rename: soundName$ + "_orchestrated"
    nChRes = Get number of channels
    # Internal reference mix (sum of channels) for statistics, drawing and,
    # with > 2 channels, playback.  Temporary: removed before the script ends.
    if nChRes > 1
        Copy: "tinysol_tmp_copy"
        tmpCopy = selected("Sound")
        Convert to mono
        refMix = selected("Sound")
        Formula: "self * " + string$(nChRes)
        removeObject: tmpCopy
    else
        Copy: "tinysol_tmp_mix"
        refMix = selected("Sound")
    endif
    selectObject: refMix
    dur_out = Get total duration
    rms_out = Get root-mean-square: 0, 0
endif

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
renderedCount$   = "?"
descStatus$      = "?"
effWeights$      = "?"
legalCandidates$ = "?"
silenceReason$   = ""
interpLabel$     = "?"
lvTarget$        = "?"
lvRendered$      = "?"
lvRequested$     = "?"
lvApplied$       = "?"
lvFinal$         = "?"
lvRemaining$     = "?"
lvPeakBefore$    = "?"
lvPeakAfter$     = "?"
lvLimited$       = "0"
outChannels$     = "0"
channelMap$      = ""
channelSum$      = "?"
interpClass$     = "?"
nEvents$         = "?"
pitchChanges$    = "?"
sampleChanges$   = "?"
silenceRendered$ = "0"
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
    @parseStatLine: resultText$, "rendered_count="
    renderedCount$ = parseStatLine.result$
    @parseStatLine: resultText$, "descriptor_status="
    descStatus$ = parseStatLine.result$
    @parseStatLine: resultText$, "effective_weights="
    effWeights$ = parseStatLine.result$
    @parseStatLine: resultText$, "legal_candidates="
    legalCandidates$ = parseStatLine.result$
    @parseStatLine: resultText$, "target_lkfs="
    lvTarget$ = parseStatLine.result$
    @parseStatLine: resultText$, "rendered_lkfs="
    lvRendered$ = parseStatLine.result$
    @parseStatLine: resultText$, "requested_db="
    lvRequested$ = parseStatLine.result$
    @parseStatLine: resultText$, "applied_db="
    lvApplied$ = parseStatLine.result$
    @parseStatLine: resultText$, "final_lkfs="
    lvFinal$ = parseStatLine.result$
    @parseStatLine: resultText$, "remaining_db="
    lvRemaining$ = parseStatLine.result$
    @parseStatLine: resultText$, "peak_before="
    lvPeakBefore$ = parseStatLine.result$
    @parseStatLine: resultText$, "peak_after="
    lvPeakAfter$ = parseStatLine.result$
    @parseStatLine: resultText$, "ceiling_limited="
    lvLimited$ = parseStatLine.result$
    @parseStatLine: resultText$, "out_channels="
    outChannels$ = parseStatLine.result$
    @parseStatLine: resultText$, "channel_map="
    channelMap$ = parseStatLine.result$
    @parseStatLine: resultText$, "channel_sum_check="
    channelSum$ = parseStatLine.result$
    @parseStatLine: resultText$, "interpretation_label="
    interpLabel$ = parseStatLine.result$
    @parseStatLine: resultText$, "interpretation_class="
    interpClass$ = parseStatLine.result$
    @parseStatLine: resultText$, "n_events="
    nEvents$ = parseStatLine.result$
    @parseStatLine: resultText$, "pitch_changes="
    pitchChanges$ = parseStatLine.result$
    @parseStatLine: resultText$, "sample_changes="
    sampleChanges$ = parseStatLine.result$

    @parseStatLine: resultText$, "silence_rendered="
    silenceRendered$ = parseStatLine.result$
    @parseStatLine: resultText$, "silence_reason="
    silenceReason$ = parseStatLine.result$
    if silenceRendered$ = "1"
        if silenceReason$ = "silent_target"
            silenceFlag$ = "  [SILENCE - silent target]"
        elsif silenceReason$ = "frame_unmatched"
            silenceFlag$ = "  [SILENCE - no frame matches]"
        elsif silenceReason$ = "no_legal_candidates"
            silenceFlag$ = "  [SILENCE - no legal candidates]"
        elsif silenceReason$ = "no_valid_descriptors"
            silenceFlag$ = "  [SILENCE - no valid descriptor comparison]"
        elsif silenceReason$ = "render_failed"
            silenceFlag$ = "  [SILENCE - samples could not be loaded]"
        else
            silenceFlag$ = "  [SILENCE - best score above match threshold]"
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


# ---- v1.11.6 orchestration protocol: the RENDERED channels ----
# Everything drawn below comes from the chanN_* lines, which Python writes from
# the final rendered stems.  Ranking lines are used only in the Info window.
instrRequested$ = "?"
instrRendered$ = "0"
instrNote$ = ""
if resultText$ <> ""
    @parseStatLine: resultText$, "instruments_requested="
    instrRequested$ = parseStatLine.result$
    @parseStatLine: resultText$, "instruments_rendered="
    instrRendered$ = parseStatLine.result$
    @parseStatLine: resultText$, "instruments_note="
    instrNote$ = parseStatLine.result$
    if instrNote$ = "?"
        instrNote$ = ""
    endif
endif
for iCh from 1 to nChRes
    @chanField: iCh, "name"
    chName$[iCh] = chanField.v$
    @chanField: iCh, "family"
    chFamily$[iCh] = chanField.v$
    @chanField: iCh, "notes"
    chNotes$[iCh] = chanField.v$
    @chanField: iCh, "dyn"
    chDyn$[iCh] = chanField.v$
    @chanField: iCh, "score"
    chScore$[iCh] = chanField.v$
    @chanField: iCh, "samples"
    chSamples$[iCh] = chanField.v$
    @chanField: iCh, "files"
    chFiles$[iCh] = chanField.v$
    @chanField: iCh, "active_s"
    chActive$[iCh] = chanField.v$
    @chanField: iCh, "activity"
    chActivity$[iCh] = chanField.v$
    @chanField: iCh, "notespans"
    chSpans$[iCh] = chanField.v$
    @chanField: iCh, "units"
    chUnits$[iCh] = chanField.v$
endfor

# ===========================================================================
# Visualization (optional) -- v1.11.6 orchestration-centred figure
#   A header | B source | C orchestration map (largest) | D rendered sum | level
# Layout is computed in inches: the canvas is addressed with
# Axes 0..8 (x) and H..0 (y, downwards), so every coordinate below is a
# distance from the top-left corner of the figure.
# ===========================================================================
if draw_visualization
    appendInfoLine: "Drawing visualization..."

    # Representative input channel: the strongest one.
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
    selectObject: vizIn
    inPeak = Get absolute extremum: 0, 0, "none"
    outPeak = 0
    if refMix <> 0
        selectObject: refMix
        outPeak = Get absolute extremum: 0, 0, "none"
    endif
    wavePeak = 1.05 * max(inPeak, outPeak)
    if wavePeak < 0.000001
        wavePeak = 1
    endif
    tMax = max(dur, dur_out)
    @niceStep: tMax
    tStep = niceStep.step

    # ---- geometry (inches) ----
    xL = 0.6
    xR = 7.7
    xT = 2.55
    nRows = max(1, nChRes)
    if analysis_mode = 2
        rowH = 0.46
    else
        rowH = 0.40
    endif
    ySrcHead = 1.02
    ySrc0 = 1.18
    ySrc1 = 2.02
    yMapHead = 2.52
    if analysis_mode = 2 and resultSound <> 0
        yRows0 = 2.70
    else
        yRows0 = 2.92
    endif
    yRows1 = yRows0 + nRows * rowH
    if analysis_mode = 2 and resultSound <> 0
        yMapEnd = yRows1 + 0.42
    else
        yMapEnd = yRows1 + 0.12
    endif
    if resultSound <> 0
        yOutHead = yMapEnd + 0.38
        yOut0 = yOutHead + 0.16
        yOut1 = yOut0 + 0.84
        ySum0 = yOut1 + 0.50
    else
        ySum0 = yMapEnd + 0.30
    endif
    ySum1 = ySum0 + 0.46
    figH = ySum1 + 0.18

    # ---- labels (Picture-safe) ----
    displaySoundName$ = replace$(soundName$, "_", " ", 0)
    @pictureSafe: displaySoundName$
    displaySoundName$ = pictureSafe.result$
    @pictureSafe: interpLabel$
    interpViz$ = pictureSafe.result$
    if analysis_mode = 2
        modeViz$ = "Frame-based"
    else
        modeViz$ = "Whole file"
    endif
    if resultSound <> 0
        countViz$ = string$(nChRes) + " instrument" + if nChRes = 1 then "" else "s" fi
        if instrRequested$ <> "?" and instrRequested$ <> string$(nChRes)
            countViz$ = countViz$ + " (" + instrRequested$ + " requested)"
        endif
    else
        countViz$ = "no instrument rendered"
    endif

    Erase all
    Font size: 10
    Select outer viewport: 0, 8, 0, figH
    @canvas

    # ---- A. header ----
    Colour: "Black"
    @fs: 13
    Text: xL, "left", 0.36, "half", "##TinySOL Orchestration Retrieval##"
    @fs: 9.5
    Colour: "{0.30, 0.30, 0.38}"
    Text: xL, "left", 0.66, "half", displaySoundName$ + "   |   " + modeViz$ + "   |   " + countViz$

    # ---- B. source sound ----
    @heading: ySrcHead, "Source sound", fixed$(dur, 2) + " s   |   " + interpViz$
    @dbfs: rms_orig
    srcRmsViz$ = dbfs.r$
    @sideLines: ySrc0, ySrc1, string$(nChannels) + " ch   " + string$(sr) + " Hz", "RMS " + srcRmsViz$
    Font size: 8
    Select inner viewport: xT, xR, ySrc0, ySrc1
    selectObject: vizIn
    Colour: "{0.45, 0.45, 0.45}"
    Draw: 0, tMax, -wavePeak, wavePeak, "no", "Curve"
    Colour: "Black"
    Axes: 0, tMax, -wavePeak, wavePeak
    Draw inner box
    Marks bottom every: 1, tStep, "yes", "yes", "no"
    @canvas

    # ---- C. orchestration map ----
    if resultSound = 0
        @heading: yMapHead, "Orchestration map", "no instrument channel"
        Paint rectangle: "{0.97, 0.97, 0.97}", xL, xR, yRows0 - 0.12, yRows1
        Colour: "{0.25, 0.25, 0.25}"
        @fs: 9.5
        reasonViz$ = replace$(replace$(silenceFlag$, "  [SILENCE - ", "", 1), "]", "", 1)
        if reasonViz$ = ""
            reasonViz$ = "the backend produced no instrument audio"
        endif
        @pictureSafe: reasonViz$
        Text: xL + 0.15, "left", 0.5 * (yRows0 - 0.12 + yRows1), "half", "No orchestral instrument was rendered:  " + pictureSafe.result$
        Colour: "Black"
        Draw rectangle: xL, xR, yRows0 - 0.12, yRows1
    elsif analysis_mode = 2
        @heading: yMapHead, "Orchestration map", "when each instrument sounds (measured on its rendered channel)"
        labelsDrawn = 0
        for iCh from 1 to nChRes
            @mapRowFrame: iCh
        endfor
        Font size: 8
        Select inner viewport: xT, xR, yRows0, yRows1
        Axes: 0, tMax, 0, 1
        Colour: "{0.55, 0.55, 0.55}"
        Marks bottom every: 1, tStep, "yes", "yes", "yes"
        Colour: "Black"
        Draw inner box
        @canvas
        @fs: 8
        Colour: "{0.40, 0.40, 0.40}"
        Text: xR, "right", yRows1 + 0.32, "half", "Time (s)"
        if labelsDrawn
            Text: xL, "left", yRows1 + 0.32, "half", "Labels: TinySOL sample note"
        elsif interpClass$ <> "monophonic"
            Text: xL, "left", yRows1 + 0.32, "half", "Sample notes listed in the Info window"
        endif
    else
        @heading: yMapHead, "Orchestration map", "rendered instruments, one channel each"
        @fs: 8.5
        Colour: "{0.40, 0.40, 0.40}"
        yHdr = yRows0 - 0.14
        Text: xL + 0.05, "left", yHdr, "half", "Ch"
        Text: xL + 0.62, "left", yHdr, "half", "Instrument"
        Text: 3.05, "left", yHdr, "half", "Family"
        Text: 4.15, "left", yHdr, "half", "Pitch"
        Text: 5.25, "left", yHdr, "half", "Dynamic"
        Text: 6.30, "left", yHdr, "half", "Score"
        Text: xR - 0.05, "right", yHdr, "half", "Samples"
        Colour: "{0.70, 0.70, 0.70}"
        Draw line: xL, yRows0, xR, yRows0
        for iCh from 1 to nChRes
            @mapRowWhole: iCh
        endfor
        Colour: "{0.70, 0.70, 0.70}"
        Draw line: xL, yRows1, xR, yRows1
    endif

    # ---- D. rendered result (internal reference sum) ----
    if resultSound <> 0
        @heading: yOutHead, "Rendered result", "internal reference sum of the " + string$(nChRes) + " channel(s), same amplitude scale as the source"
        @dbfs: rms_out
        @sideLines: yOut0, yOut1, string$(nChRes) + " channel" + if nChRes = 1 then "" else "s" fi, "RMS " + dbfs.r$
        Font size: 8
        Select inner viewport: xT, xR, yOut0, yOut1
        selectObject: refMix
        Colour: "{0.13, 0.45, 0.32}"
        Draw: 0, tMax, -wavePeak, wavePeak, "no", "Curve"
        Colour: "Black"
        Axes: 0, tMax, -wavePeak, wavePeak
        Draw inner box
        Marks bottom every: 1, tStep, "yes", "yes", "no"
        @canvas
    endif

    # ---- level summary ----
    Paint rectangle: "{0.94, 0.94, 0.94}", xL, xR, ySum0, ySum1
    Colour: "Black"
    Draw rectangle: xL, xR, ySum0, ySum1
    yMid = 0.5 * (ySum0 + ySum1)
    @fs: 9.5
    Text: xL + 0.12, "left", yMid, "half", "##Level##"
    @fs: 9
    Colour: "{0.20, 0.20, 0.20}"
    if resultSound <> 0
        levelViz$ = "Target " + lvTarget$ + " LKFS     Output " + lvFinal$ + " LKFS     correction " + lvApplied$ + " dB     peak " + lvPeakAfter$
        if lvLimited$ = "1"
            levelViz$ = levelViz$ + " (ceiling)"
        endif
    else
        levelViz$ = "Target RMS " + srcRmsViz$ + "     no output"
    endif
    Text: xL + 0.75, "left", yMid, "half", levelViz$
    Colour: "{0.40, 0.40, 0.40}"
    @fs: 8
    Text: xR - 0.12, "right", yMid, "half", "details: Info window"

    removeObject: vizIn
    Colour: "Black"
    @fs: 10
    Line width: 1
    # Leave the full canvas selected so Save/Copy exports the whole figure.
    Select outer viewport: 0, 8, 0, figH
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
if resultSound <> 0
    appendInfoLine: "Output: Sound ", soundName$, "_orchestrated  (", nChRes, " channel(s), one per instrument)"
else
    appendInfoLine: "Output: none - no orchestral instrument was rendered", silenceFlag$
endif
appendInfoLine: ""
appendInfoLine: "Instruments:    ", instrRendered$, " rendered of ", instrRequested$, " requested (render mode ", renderStr$, ")"
if instrNote$ <> ""
    appendInfoLine: "                ", instrNote$
endif
if analysis_mode = 2
    @parseStatLine: resultText$, "voice_frames="
    appendInfoLine: "Voice frames:   ", parseStatLine.result$, "   (frames in which each selected instrument has a legal sample)"
endif
appendInfoLine: "Top-ranked:     ", bestMatch$, silenceFlag$, "   (retrieval ranking, diagnostic)"
appendInfoLine: "Match score:    ", bestScore$, "  (calibrated: 0 = identical, 1 = typical pair of corpus notes)"
appendInfoLine: "Descriptors:    ", descStatus$, "   (A/B = verified, C = excluded, -off = not scored)"
appendInfoLine: "Eff. weights:   ", effWeights$
appendInfoLine: "Interpretation: ", interpLabel$
if analysis_mode = 2
    appendInfoLine: "Frames analyzed:", nCandidates$
    appendInfoLine: "Frames matched: ", chosenCount$
    appendInfoLine: "Events:         ", nEvents$, "   orchestral pitch changes: ", pitchChanges$, "   sample changes: ", sampleChanges$
    appendInfoLine: "Render mode:    frame_based"
else
    appendInfoLine: "Candidates:     ", nCandidates$, " ranked of ", legalCandidates$, " legal"
    appendInfoLine: "Layers rendered:", renderedCount$
    appendInfoLine: "Render mode:    ", renderMode$
endif
if index(descStatus$, "C") > 0
    appendInfoLine: ""
    appendInfoLine: "NOTE: one or more descriptor tables could not be verified and were NOT scored."
    appendInfoLine: "      Build verified tables (originals untouched) with:"
    appendInfoLine: "      python tinysol_retrieval.py --build-db ""<corpus_root>"" ""<new empty folder>"""
endif
appendInfoLine: ""
appendInfoLine: "Target:         ", fixed$(dur, 2), " s  RMS=", fixed$(rms_orig, 4)
if resultSound <> 0
    appendInfoLine: "Output:         ", fixed$(dur_out, 2), " s  RMS=", fixed$(rms_out, 4), " (sum of channels)  (duration policy: ", durationStr$, ")"
endif
appendInfoLine: ""
appendInfoLine: "Level (", levelStr$, ", K-weighted gated loudness, LKFS channel mean):"
appendInfoLine: "  target ", lvTarget$, "   rendered ", lvRendered$, "   final ", lvFinal$, "   remaining ", lvRemaining$, " dB"
appendInfoLine: "  correction requested ", lvRequested$, " dB, applied ", lvApplied$, " dB   peak ", lvPeakBefore$, " -> ", lvPeakAfter$, if lvLimited$ = "1" then "   [limited by peak ceiling]" else "" fi
if resultSound <> 0
    appendInfoLine: ""
    appendInfoLine: "Channels (", outChannels$, "):  ", channelMap$, "   [sum vs. reference mix: max error ", channelSum$, "]"
    for iCh from 1 to nChRes
        appendInfoLine: "  Ch ", iCh, "  ", chName$[iCh], " (", chFamily$[iCh], ")   notes ", chNotes$[iCh], "   dyn ", chDyn$[iCh], "   score ", chScore$[iCh], "   ", chUnits$[iCh], "   active ", chActive$[iCh], " s"
        appendInfoLine: "        activity (s): ", chActivity$[iCh]
        if analysis_mode = 2
            appendInfoLine: "        sample notes (s): ", chSpans$[iCh]
        endif
        appendInfoLine: "        samples (", chSamples$[iCh], "): ", chFiles$[iCh]
    endfor
endif

# ---- Playback (never alters or removes the result) ----
if play_result and resultSound <> 0
    if nChRes <= 2
        selectObject: resultSound
        nocheck Play
    else
        appendInfoLine: "Playback: ", nChRes, " channels are played as their sum (temporary mix); the Sound keeps all ", nChRes, " channels."
        selectObject: refMix
        nocheck Play
    endif
endif

# ---- Remove temporary objects; leave only the new Sound selected ----
if refMix <> 0
    removeObject: refMix
endif
if resultSound <> 0
    selectObject: resultSound
else
    selectObject: sound
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

procedure fs: .size
    # Praat re-derives the viewport when the font size changes, so the
    # inch-based canvas mapping is restored after every font change.
    Font size: .size
    @canvas
endproc

procedure canvas
    # Whole figure as world coordinates in inches, y downwards.
    Select inner viewport: 0, 8, 0, figH
    Axes: 0, 8, figH, 0
endproc

procedure heading: .y, .title$, .detail$
    Colour: "Black"
    @fs: 10.5
    Text: xL, "left", .y, "half", "##" + .title$ + "##"
    if .detail$ <> ""
        @fs: 9
        Colour: "{0.40, 0.40, 0.40}"
        # details start at the time-plot column, so they line up across panels
        Text: xT, "left", .y, "half", .detail$
    endif
    Colour: "Black"
endproc

procedure sideLines: .y0, .y1, .a$, .b$
    # Two short facts in the column left of a time-aligned plot.
    @fs: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: xL, "left", .y0 + 0.30 * (.y1 - .y0), "half", .a$
    Text: xL, "left", .y0 + 0.62 * (.y1 - .y0), "half", .b$
    Colour: "Black"
endproc

procedure dbfs: .rms
    if .rms > 0
        .r$ = fixed$(20 * log10(.rms), 1) + " dBFS"
    else
        .r$ = "silence"
    endif
endproc

procedure niceStep: .t
    if .t <= 0.6
        .step = 0.1
    elsif .t <= 1.5
        .step = 0.25
    elsif .t <= 3
        .step = 0.5
    elsif .t <= 8
        .step = 1
    elsif .t <= 20
        .step = 2
    elsif .t <= 50
        .step = 5
    elsif .t <= 120
        .step = 10
    else
        .step = 30
    endif
endproc

procedure chanField: .c, .key$
    @parseStatLine: resultText$, "chan" + string$(.c) + "_" + .key$ + "="
    .v$ = parseStatLine.result$
endproc

procedure familyColour: .fam$
    if .fam$ = "Brass"
        .rgb$ = "{0.78, 0.42, 0.13}"
    elsif .fam$ = "Strings"
        .rgb$ = "{0.20, 0.42, 0.72}"
    elsif .fam$ = "Winds"
        .rgb$ = "{0.20, 0.55, 0.32}"
    elsif .fam$ = "Keyboards"
        .rgb$ = "{0.52, 0.32, 0.62}"
    else
        .rgb$ = "{0.45, 0.45, 0.45}"
    endif
endproc

procedure displayName: .raw$, .maxChars
    # '_' in TinySOL folder names becomes a space; over-long names are
    # shortened (never shrunk in font size); markup characters are escaped.
    .r$ = replace$(.raw$, "_", " ", 0)
    if .r$ = "?" or .r$ = ""
        .r$ = "(unknown)"
    endif
    if length(.r$) > .maxChars
        .r$ = left$(.r$, .maxChars - 2) + ".."
    endif
    @pictureSafe: .r$
    .r$ = pictureSafe.result$
endproc

procedure rowFrame: .c
    # background band + channel number and instrument name (two lines)
    .y0 = yRows0 + (.c - 1) * rowH
    .y1 = .y0 + rowH
    if .c mod 2 = 1
        Paint rectangle: "{0.965, 0.965, 0.965}", xL, xR, .y0, .y1
    endif
    @familyColour: chFamily$[.c]
    Paint rectangle: familyColour.rgb$, xL, xL + 0.06, .y0 + 0.06, .y1 - 0.06
    Colour: "{0.35, 0.35, 0.35}"
    @fs: 9
    Text: xL + 0.13, "left", 0.5 * (.y0 + .y1), "half", string$(.c)
    Colour: "Black"
endproc

procedure mapRowFrame: .c
    @rowFrame: .c
    .y0 = rowFrame.y0
    .y1 = rowFrame.y1
    @displayName: chName$[.c], 17
    @fs: 9.5
    Colour: "Black"
    Text: xL + 0.36, "left", .y0 + 0.36 * rowH, "half", "##" + displayName.r$ + "##"
    @fs: 8
    Colour: "{0.40, 0.40, 0.40}"
    .sub$ = chFamily$[.c]
    if .sub$ = "?"
        .sub$ = ""
    endif
    if chActive$[.c] <> "?" and chActive$[.c] <> ""
        .sub$ = .sub$ + if .sub$ = "" then "" else "   " fi + fixed$(number(chActive$[.c]), 1) + " s active"
    endif
    @pictureSafe: .sub$
    Text: xL + 0.36, "left", .y0 + 0.72 * rowH, "half", pictureSafe.result$
    # activity bars (measured on the final channel audio)
    @familyColour: chFamily$[.c]
    .b0 = .y0 + 0.10
    .b1 = .y1 - 0.10
    .scale = (xR - xT) / tMax
    .act$ = chActivity$[.c]
    .nSeg = 0
    while .act$ <> "" and .act$ <> "?"
        .p = index(.act$, ";")
        if .p > 0
            .seg$ = left$(.act$, .p - 1)
            .act$ = mid$(.act$, .p + 1, length(.act$) - .p)
        else
            .seg$ = .act$
            .act$ = ""
        endif
        .d = index(.seg$, "-")
        if .d > 0
            .ta = number(left$(.seg$, .d - 1))
            .tb = number(mid$(.seg$, .d + 1, length(.seg$) - .d))
            if .ta <> undefined and .tb <> undefined and .tb > .ta
                .xa = xT + .ta * .scale
                .xb = min(xR, xT + .tb * .scale)
                Paint rectangle: familyColour.rgb$, .xa, .xb, .b0, .b1
                .nSeg = .nSeg + 1
            endif
        endif
    endwhile
    if .nSeg = 0
        @fs: 8
        Colour: "{0.45, 0.45, 0.45}"
        Text: xT + 0.08, "left", 0.5 * (.b0 + .b1), "half", "(no activity data)"
    else
        @noteMarks: .c, .b0, .b1, .scale
    endif
    Colour: "Black"
endproc

procedure noteMarks: .c, .b0, .b1, .scale
    # Note changes: thin white boundaries inside the bars; note names only for a
    # reliably monophonic interpretation and only where the segment is wide
    # enough for the label (no forced labels in short segments).
    .sp$ = chSpans$[.c]
    .first = 1
    while .sp$ <> "" and .sp$ <> "?"
        .p = index(.sp$, ";")
        if .p > 0
            .seg$ = left$(.sp$, .p - 1)
            .sp$ = mid$(.sp$, .p + 1, length(.sp$) - .p)
        else
            .seg$ = .sp$
            .sp$ = ""
        endif
        .colon = index(.seg$, ":")
        .d = index(.seg$, "-")
        if .colon > 0 and .d > 0 and .d < .colon
            .ta = number(left$(.seg$, .d - 1))
            .tb = number(mid$(.seg$, .d + 1, .colon - .d - 1))
            .note$ = mid$(.seg$, .colon + 1, length(.seg$) - .colon)
            if .ta <> undefined and .tb <> undefined
                .xa = xT + .ta * .scale
                .xb = min(xR, xT + .tb * .scale)
                if .first = 0
                    Colour: "White"
                    Line width: 1.5
                    Draw line: .xa, .b0, .xa, .b1
                    Line width: 1
                endif
                .first = 0
                if interpClass$ = "monophonic" and .xb - .xa >= 0.09 * length(.note$) + 0.12
                    @pictureSafe: .note$
                    @fs: 8
                    Colour: "White"
                    Text: 0.5 * (.xa + .xb), "centre", 0.5 * (.b0 + .b1), "half", "##" + pictureSafe.result$ + "##"
                    labelsDrawn = 1
                endif
            endif
        endif
    endwhile
    Colour: "Black"
endproc

procedure mapRowWhole: .c
    @rowFrame: .c
    .ym = 0.5 * (rowFrame.y0 + rowFrame.y1)
    @displayName: chName$[.c], 22
    @fs: 9.5
    Colour: "Black"
    Text: xL + 0.62, "left", .ym, "half", "##" + displayName.r$ + "##"
    @fs: 9.5
    Colour: "{0.20, 0.20, 0.20}"
    @pictureSafe: chFamily$[.c]
    Text: 3.05, "left", .ym, "half", pictureSafe.result$
    # pitch: up to three sample notes, the rest is in the Info window
    .notes$ = chNotes$[.c]
    .shown$ = ""
    .k = 0
    while .notes$ <> "" and .notes$ <> "?" and .k < 3
        .p = index(.notes$, " ")
        if .p > 0
            .n$ = left$(.notes$, .p - 1)
            .notes$ = mid$(.notes$, .p + 1, length(.notes$) - .p)
        else
            .n$ = .notes$
            .notes$ = ""
        endif
        .shown$ = .shown$ + if .k > 0 then " " else "" fi + .n$
        .k = .k + 1
    endwhile
    if .notes$ <> "" and .notes$ <> "?"
        .shown$ = .shown$ + " .."
    endif
    if .shown$ = ""
        .shown$ = "-"
    endif
    @pictureSafe: .shown$
    Text: 4.15, "left", .ym, "half", pictureSafe.result$
    .dyn$ = chDyn$[.c]
    if .dyn$ = "?" or .dyn$ = ""
        .dyn$ = "-"
    endif
    @pictureSafe: .dyn$
    Text: 5.25, "left", .ym, "half", "%%" + pictureSafe.result$ + "%%"
    .sc$ = chScore$[.c]
    if .sc$ = "?" or .sc$ = ""
        .sc$ = "-"
    endif
    Text: 6.30, "left", .ym, "half", .sc$
    .ns$ = chSamples$[.c]
    if .ns$ = "?"
        .ns$ = "-"
    endif
    Text: xR - 0.05, "right", .ym, "half", .ns$
    Colour: "Black"
endproc

procedure pictureSafe: .s$
    # '#' (bold), '_' (subscript), '%' (italic), '^' (superscript) are Picture
    # markup; each escape consumes one following space.
    .result$ = replace$(.s$, "#", "\# ", 0)
    .result$ = replace$(.result$, "_", "\_ ", 0)
    .result$ = replace$(.result$, "%", "\% ", 0)
    .result$ = replace$(.result$, "^", "\^ ", 0)
endproc

procedure parseStatLine: .text$, .key$
    # Match keys at the start of a line so that one key can never be found
    # inside another (e.g. "silence_reason=" inside a warning text).
    .result$ = "?"
    .pos = index(.text$, newline$ + .key$)
    if .pos > 0
        .pos = .pos + length(newline$)
    else
        .pos = index(.text$, .key$)
    endif
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