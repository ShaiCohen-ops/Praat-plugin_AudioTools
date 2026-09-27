# ============================================================
# Praat AudioTools - Corpus_Concatenative_Codec.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.12.0 (2026) - Draw moved from the RealTier editor to the Demo window
#   v1.12.0 replaces the interactive RealTier editor with a Demo-window drawing
#   surface. Reason: the old flow opened a RealTier editor, held the script in
#   a pause window while the editor was live, then removed the RealTier (which
#   destroys its editor) and immediately blocked Praat in runSubprocess. That
#   editor-lifetime sequence is the only part of Draw that could take Praat
#   down, and Draw runs from a saved contour file never went through it.
#   The Demo window owns no Praat object, so nothing is destroyed underneath
#   the user. New behaviour:
#     - click adds a point; click a point to select it, click again to move
#       it there; shift-click deletes; U undo, S stretch toggle, R reset,
#       Enter render, Esc cancel - every action also has an on-screen button
#       (Demo-window key codes differ per platform; the buttons always work).
#     - the corpus's own brightness distribution (log spectral centroid of
#       every grain, read from the index JSON) is shown as a density strip
#       and as shaded bands; brightness ranges with NO grains are tinted red.
#     - an orange step line previews which grain brightness each grain-rate
#       step will snap to (nearest grain; the repeat penalty is not included).
#     - VALUE SEMANTICS CHANGE: the drawing axis is now absolute 0..1 on the
#       corpus's normalised log-brightness scale. The old RealTier path always
#       min/max-stretched whatever was drawn to 0..1 in Python. That legacy
#       behaviour is still available as "Stretch drawn range" (dialog field or
#       S key), and the preview shows the stretched result when it is on.
#     - Praat writes the drawn gesture directly as a corpus_draw_contour file,
#       so the backend's --tier/RealTier path is no longer used by this script
#       (the Python backend is unchanged and still accepts --tier).
#     - closing the Demo window while drawing stops the script (Praat's own
#       Demo-window behaviour); no objects or temp files exist at that point.
#   The Contour file source and the whole synthesis path are unchanged.
# Version: 1.11.0 (2026) - Reusable Draw contours
#   v1.11.0 keeps the RealTier editor as the interactive Draw interface, but
#   no longer lets the gesture disappear when the editor closes. Every Draw
#   run is converted to a compact normalized time->brightness contour file
#   and saved persistently under preferencesDirectory$/corpus/draw_contours/.
#   Draw can also load one of these contour files directly, bypassing the
#   editor for exact replay, batch work, controlled comparisons, or a future
#   gesture library. The synthesis path itself is otherwise unchanged.
# Version: 1.10.0 (2026) - Single corpus-source path + internal transactional corpus cache
#   v1.10.0 removes Corpus_index from the user form. The user supplies only
#   the corpus audio source; the analysed corpus is stored internally at
#   preferencesDirectory$/corpus/current_corpus. Build/auto-build calls the
#   backend with --atomic, so a complete new corpus is built in staging and
#   replaces the previous analysis only after success. A failed rebuild leaves
#   the previous successful corpus intact.
# Version: 1.9.3.1 (2026) - Default corpus index path set to C:/Users/User/Praat/corpus/my_corpus
# Version: 1.9.3 (2026) - Fixed Build mode never cleaning up on success
#   v1.9.3: same class of bug as v1.9.2, but in Build corpus mode: the
#   success branch (index found on disk) printed its confirmation and fell
#   through to "goto END" without ever calling cleanUpTempFiles, so every
#   successful build left an empty ccc_pylog_<tag>.txt behind (Build mode
#   never creates tempInput$/tempOutput$/tempMeta$/tempTG$/tempDrawn$, so
#   only the log - and rarely tempCrash$ - could ever be present here, but
#   nothing removed even those). Fixed by adding the same @cleanUpTempFiles
#   call as the failure branch already had. The internal corpus cache itself is not
#   affected - it was never part of cleanUpTempFiles's file list.
# Version: 1.9.2 (2026) - Fixed Draw mode never cleaning up on success
#   v1.9.2: Draw mode's success path went straight from importing the result
#   (and its TextGrid) to Play/goto END - unlike Match and Gesture rhyme, it
#   never called cleanUpTempFiles at all, so EVERY successful Draw run left
#   ccc_curve_<tag>.RealTier, ccc_output_<tag>.wav/.TextGrid,
#   ccc_meta_<tag>.json and ccc_pylog_<tag>.txt behind in the corpus folder
#   permanently (the v1.9.1 fix below only covered the FAILURE branch and
#   the fixed-name crash file, not this). Fixed by adding the same
#   @cleanUpTempFiles call Match/Gesture rhyme already make, right after the
#   result/TextGrid are read in and before Play.
# Version: 1.9.1 (2026) - Fixed a temp-folder cleanup gap (crash-dump file)
#   v1.9.1: the Python backend writes a FIXED-name crash dump
#   (corpus_concat_crash.txt) into the corpus folder whenever it hits an
#   uncaught exception (its traceback was always ALSO teed into the per-run
#   --log file, so nothing new is lost by deleting it) - but this script's
#   cleanUpTempFiles procedure never knew that file existed, so it was never
#   deleted and just sat in e.g. C:\Users\User\Praat\corpus permanently.
#   Most noticeable in Gesture rhyme mode since it has the most failure
#   modes (requires a pre-built index, obsolete-schema errors, etc.), but
#   the same gap existed in every mode. Fixed by: (1) adding that path to
#   cleanUpTempFiles, and (2) calling cleanUpTempFiles immediately after
#   every @showPyLog / before every exitScript on a failed run, instead of
#   only on success - previously a failed run skipped cleanup entirely and
#   relied on a future run's start-of-run sweep to catch it, which only
#   works for this fixed-name file, not the per-run-tagged ones.
# Version: 1.9 (2026) - Shortened the form to fit smaller screens
#   v1.9: the single form used to show all ~25 fields from every mode at
#   once, which no longer fit on a laptop screen. The form now only asks for
#   Mode/Codec/Corpus audio source/Import_textgrid/Play_result; right after it, a
#   short beginPause/endPause dialog (or two, for Match and Gesture rhyme)
#   shows only the fields relevant to the chosen Mode. No field was removed
#   and no default value changed - this is a layout change only.
#   v1.8 fix pass: Gesture rhyme's random-baseline ablation (already supported
#   by the Python backend) is now exposed in the form as Random_baseline /
#   Random_seed and passed through to the backend - previously it was only
#   reachable by running the Python script directly. Default Analysis_grain_ms
#   / Analysis_hop_ms raised from 60/30 to 150/45 to match the backend's new
#   defaults (a 60ms window can starve some codecs' bigram features of real
#   transitions - see the backend's own n_token_frames warning). Failure
#   messages for Match/Build/Gesture-rhyme now explicitly mention an obsolete
#   index schema as a possible cause, since the backend's v1.4-era indexes are
#   no longer feature-compatible with this version (per-codebook bigram
#   bucket count/hash changed) and must be rebuilt.
#   v1.7 fix pass: added encodec to the Codec menu (backend already supported
#   it); Matching preset no longer silently overrides Gesture rhyme's shared
#   params; per-run temp filenames (avoids collisions between overlapping
#   runs); result object names no longer imply a codec that may not have
#   been the one actually used; provenance-metadata filenames are sanitised;
#   Draw mode now sends --log like every other mode; weight/penalty fields
#   are clamped to non-negative to match the backend.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Corpus-Based Concatenative Synthesis using a neural audio codec
#   (EnCodec or DAC) as the matching token space.
#
#   Select a Sound. The script exports it to a temp WAV and calls a Python
#   backend (corpus_concat_codec.py) which: detects onsets in the source,
#   subdivides each onset-bounded segment into a fine grid of analysis
#   sub-windows (so a decaying/evolving span of audio isn't forced to match
#   one static corpus grain for its whole duration), encodes each
#   sub-window into codec tokens, compares them against a pre-encoded
#   corpus of grains (timbre AND loudness), selects the nearest-matching
#   corpus grain for each sub-window, and places it so the output's
#   rhythm/timing tracks the source's, built from the TARGET corpus
#   material (crossfaded) - only each segment's first sub-window (the one
#   carrying the actual attack) is peak-aligned to the source onset; later
#   sub-windows tile forward continuously. The output WAV is read back as a
#   new Sound, with an optional TextGrid marking which corpus grain each
#   sub-window came from.
#
#   You build/replace the analysed corpus once (Mode = Build / replace corpus) before matching.
#
#   GESTURE RHYME mode (Mode = Gesture rhyme) re-voices an ABSTRACT kinetic
#   gesture - accelerating clicks, a bouncing ball, an explosive attack
#   decaying into hiss, a microtonal dive, tremolo flutter - using corpus
#   grains whose codec-token TRANSITION structure (hashed bigrams) rhymes
#   with the source, NOT whose timbre matches. It weights the bigram section
#   high and the histogram/energy sections low, so a click-train can be
#   voiced by speech syllables or field recordings that simply move the same
#   way frame-to-frame. It requires an existing index and never builds one.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Corpus Concatenative Synthesis (codec) v1.12.0
    comment ── Mode ──
    optionmenu Mode: 1
        option Match (synthesise from corpus)
        option Build / replace corpus
        option Draw (brightness contour -> corpus)
        option Gesture rhyme (hashed bigram kinetics)
    comment ── Codec (only used when BUILDING the index; match reuses the corpus codec) ──
    optionmenu Codec: 1
        option dac
        option encodec
        option mock
    comment ── Corpus audio source ──
    comment Folder or file analysed by Build; Match auto-builds it only if no corpus exists yet:
    sentence Corpus_audio C:/Users/user/Praat_Corpus_Audio
    boolean Import_textgrid 1
    boolean Play_result 1
endform

clearinfo

# ---- MODE-SPECIFIC SETTINGS (v1.9) ----
# The old v1.8 form put all ~25 fields (every mode's parameters at once) on
# one screen, which no longer fits on a laptop display. This form now only
# asks the few fields every mode needs (above); everything else first gets a
# sensible default here, then - right below - a short beginPause/endPause
# dialog (or two) shows ONLY the fields that matter for the Mode chosen
# above, so nothing is hidden, it's just no longer all on screen at once.
# Defaults below match the old v1.8 form's defaults exactly.

# Corpus grains (Build mode; also used if Match auto-builds a missing index)
grain_ms = 150
hop_ms = 75

# Draw mode
draw_duration_s = 4.0
grain_rate_ms = 80
draw_source = 1
contour_file$ = ""
stretch_drawn_range = 0

# Matching preset + matching (Match mode; some also shared by Draw/Gesture)
match_preset = 1
onset_min_interval_ms = 60
analysis_grain_ms = 150
analysis_hop_ms = 45
energy_weight = 1.0
crossfade_ms = 20
repeat_penalty = 0.05

# Gesture rhyme mode
bigram_weight = 4.0
hist_weight = 0.5
gesture_energy_weight = 0.2
sequence_context = 2
random_baseline = 0
random_seed = 1234

if mode = 1
    # ---- MATCH MODE ----
    beginPause: "Match mode (1/3): preset"
        comment: "Matching preset (overrides the matching values on the next screen, unless Custom):"
        optionMenu: "Match preset", 1
            option: "Custom"
            option: "Rhythmic (follow transients)"
            option: "Textural (smeared / washed)"
            option: "Faithful (track source closely)"
            option: "Sparse (distinct granular stutter)"
    endPause: "Continue", 1

    beginPause: "Match mode (2/3): matching parameters"
        comment: "Sub-window matching (lets a decaying/evolving segment match new corpus"
        comment: "material as it changes, instead of one grain for the whole segment):"
        positive: "Onset min interval ms", onset_min_interval_ms
        positive: "Analysis grain ms", analysis_grain_ms
        positive: "Analysis hop ms", analysis_hop_ms
        real: "Energy weight", energy_weight
        positive: "Crossfade ms", crossfade_ms
        real: "Repeat penalty", repeat_penalty
    endPause: "Continue", 1

    beginPause: "Match mode (3/3): auto-build grains"
        comment: "Only used if no corpus has been built yet and Match auto-builds it (the"
        comment: "corpus has no rhythm of its own, so it needs its own grain/hop size):"
        positive: "Grain ms", grain_ms
        positive: "Hop ms", hop_ms
    endPause: "Continue", 1

elsif mode = 2
    # ---- BUILD CORPUS MODE ----
    beginPause: "Build / replace corpus: grain settings"
        comment: "Corpus grains (the corpus has no rhythm of its own):"
        positive: "Grain ms", grain_ms
        positive: "Hop ms", hop_ms
    endPause: "Continue", 1

elsif mode = 3
    # ---- DRAW MODE ----
    beginPause: "Draw mode: gesture source + synthesis"
        optionMenu: "Draw source", draw_source
            option: "Interactive (Demo window)"
            option: "Contour file"
        sentence: "Contour file", contour_file$
        comment: "Interactive: draw in the Demo window; the gesture is auto-saved as a contour file."
        comment: "Contour file: paste a saved corpus_draw_contour path; its own duration is reused."
        positive: "Draw duration s", draw_duration_s
        positive: "Grain rate ms", grain_rate_ms
        boolean: "Stretch drawn range", stretch_drawn_range
        comment: "Stretch = legacy behaviour: the drawn min..max is expanded to the full 0..1 range."
        positive: "Crossfade ms", crossfade_ms
        real: "Repeat penalty", repeat_penalty
    endPause: "Continue", 1

elsif mode = 4
    # ---- GESTURE RHYME MODE ----
    beginPause: "Gesture rhyme (1/2): bigram kinetics"
        comment: "Re-voice an abstract gesture by token-transition / bigram rhyming:"
        real: "Bigram weight", bigram_weight
        real: "Hist weight", hist_weight
        real: "Gesture energy weight", gesture_energy_weight
        comment: "Sequence_context is context SMOOTHING (unordered mean over preceding"
        comment: "sub-windows), not an order-aware sequence model:"
        integer: "Sequence context", sequence_context
        comment: "Random baseline (ablation): ignore all distance matching and pick a"
        comment: "uniformly random corpus grain for every sub-window:"
        boolean: "Random baseline", random_baseline
        integer: "Random seed", random_seed
    endPause: "Continue", 1

    beginPause: "Gesture rhyme (2/2): shared matching params"
        comment: "Sub-window grid + crossfade/repeat penalty (shared with Match mode):"
        positive: "Onset min interval ms", onset_min_interval_ms
        positive: "Analysis grain ms", analysis_grain_ms
        positive: "Analysis hop ms", analysis_hop_ms
        positive: "Crossfade ms", crossfade_ms
        real: "Repeat penalty", repeat_penalty
    endPause: "Continue", 1
endif

# ---- MATCH PRESET OVERRIDE (MATCH MODE ONLY) ----
# Each preset sets the matching cluster (onset spacing, sub-window grid, energy
# weight, crossfade, repeat penalty). Custom (1) keeps the form values. Build
# params (Grain_ms / Hop_ms) are never touched - they belong to the corpus.
# Gated to mode = 1 (Match): the form labels this "Matching preset (MATCH
# mode)" but it used to apply unconditionally, silently overriding Gesture
# rhyme's (and Draw's) onset/analysis/crossfade/repeat-penalty values too.
presetName$ = "Custom"
if mode = 1
    if match_preset = 2
        presetName$ = "Rhythmic"
        onset_min_interval_ms = 40
        analysis_grain_ms = 40
        analysis_hop_ms = 20
        energy_weight = 1.5
        crossfade_ms = 10
        repeat_penalty = 0.10
    elsif match_preset = 3
        presetName$ = "Textural"
        onset_min_interval_ms = 120
        analysis_grain_ms = 120
        analysis_hop_ms = 60
        energy_weight = 0.5
        crossfade_ms = 60
        repeat_penalty = 0.02
    elsif match_preset = 4
        presetName$ = "Faithful"
        onset_min_interval_ms = 60
        analysis_grain_ms = 50
        analysis_hop_ms = 25
        energy_weight = 1.0
        crossfade_ms = 20
        repeat_penalty = 0.15
    elsif match_preset = 5
        presetName$ = "Sparse"
        onset_min_interval_ms = 80
        analysis_grain_ms = 100
        analysis_hop_ms = 80
        energy_weight = 1.0
        crossfade_ms = 15
        repeat_penalty = 0.30
    endif
elsif match_preset <> 1
    appendInfoLine: "Note: Matching preset is a MATCH-mode-only control and is being ignored in this mode."
endif

# ---- NON-NEGATIVE GUARD (mirrors the Python backend's _nonneg_float) ----
# These are declared "real" (not "positive") because 0 is a valid and
# meaningful value (e.g. Energy_weight = 0 means pure timbre matching), but
# a NEGATIVE value would silently invert what the parameter is meant to do
# (e.g. negative Repeat_penalty would REWARD repeating the same grain).
if energy_weight < 0
    appendInfoLine: "Warning: Energy_weight was negative; clamped to 0."
    energy_weight = 0
endif
if repeat_penalty < 0
    appendInfoLine: "Warning: Repeat_penalty was negative; clamped to 0."
    repeat_penalty = 0
endif
if bigram_weight < 0
    appendInfoLine: "Warning: Bigram_weight was negative; clamped to 0."
    bigram_weight = 0
endif
if hist_weight < 0
    appendInfoLine: "Warning: Hist_weight was negative; clamped to 0."
    hist_weight = 0
endif
if gesture_energy_weight < 0
    appendInfoLine: "Warning: Gesture_energy_weight was negative; clamped to 0."
    gesture_energy_weight = 0
endif
if random_seed < 0
    appendInfoLine: "Warning: Random_seed was negative (numpy's RNG rejects that); clamped to 0."
    random_seed = 0
endif

# ---- PLATFORM / PYTHON (auto-discovery, no form field) ----
# Probe known install locations per OS before falling back to a bare
# 'python'/'python3' on PATH. Same pattern as NeuralResynthesisVocoder.praat,
# so behaviour (and any future fix) stays consistent across the AudioTools
# scripts that shell out to Python.
if macintosh
    if fileReadable("/opt/homebrew/bin/python3")
        python_exe$ = "/opt/homebrew/bin/python3"
    elsif fileReadable("/Library/Frameworks/Python.framework/Versions/3.14/bin/python3")
        python_exe$ = "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3"
    elsif fileReadable("/usr/local/bin/python3")
        python_exe$ = "/usr/local/bin/python3"
    else
        python_exe$ = "python3"
    endif
elsif windows
    # Prefer the dedicated codec environment. Build the path from USERPROFILE
    # so the script is not tied to one Windows account name.
    userProfile$ = environment$("USERPROFILE")
    if userProfile$ <> ""
        userProfile$ = replace$(userProfile$, "\", "/", 0)
        codecPython$ = userProfile$ + "/praat_codec_env/Scripts/python.exe"
    else
        codecPython$ = ""
    endif
    if codecPython$ <> "" and fileReadable(codecPython$)
        python_exe$ = codecPython$
    else
        # Compatibility fallback for installations that have not created
        # praat_codec_env yet.
        python_exe$ = "python"
    endif
else
    python_exe$ = "python3"
endif

pluginDir$     = preferencesDirectory$ + "/plugin_AudioTools/"
backend_script$ = pluginDir$ + "py/corpus_concat_codec.py"
if not fileReadable(backend_script$)
    backend_script$ = defaultDirectory$ + "/corpus_concat_codec.py"
endif
if not fileReadable(backend_script$)
    exitScript: "Cannot find corpus_concat_codec.py." + newline$
        ... + "Expected at: " + pluginDir$ + "py/  or next to this script."
endif

# Internal corpus cache location. This is intentionally NOT exposed in the
# form: the user chooses only the audio source. One successful Build replaces
# the previous analysed corpus. Using preferencesDirectory$ keeps this portable
# across users/platforms (on this Windows machine it resolves to
# C:/Users/user/AppData/Roaming/Praat/corpus/current_corpus).
corpusDir$ = preferencesDirectory$ + "/corpus/"
createDirectory: corpusDir$
# Persistent Draw gestures live beside (not inside) the replaceable corpus index.
# They are intentional user data, so cleanUpTempFiles never touches them.
drawContourDir$ = corpusDir$ + "draw_contours/"
createDirectory: drawContourDir$
corpusIndexPath$ = corpusDir$ + "current_corpus"
# Normalise to forward slashes so the path PYTHON writes and the path PRAAT
# checks are byte-identical (preferencesDirectory$ can return backslashes).
corpusIndexPath$ = replace_regex$(corpusIndexPath$, "\\", "/", 0)

# ---- TEMP / OUTPUT PATHS ----
# These are deleted at the START of every run AND again at the END of a
# successful Match run (see cleanUpTempFiles), so nothing lingers once a run
# finishes. Rather than leaving them buried in the OS temp folder, put them
# right next to the internal corpus cache, so they stay inside Praat's own
# corpus working area rather than beside user-owned source audio.
slashPos = rindex(corpusIndexPath$, "/")
if slashPos > 0
    tempDir$ = left$(corpusIndexPath$, slashPos)
else
    tempDir$ = temporaryDirectory$ + "/"
endif
createDirectory: tempDir$

# Per-run tag (timestamp + random suffix) so concurrent/overlapping runs
# never share ccc_input.wav / ccc_output.wav etc. Previously every run used
# the exact same fixed filenames, so two runs started close together (or a
# second run launched before a slow previous one finished) could read back
# each other's output.
runTag$ = replace_regex$(date$(), "[^0-9A-Za-z]", "_", 0) + "_" + string$(randomInteger(1, 999999))

tempInput$  = tempDir$ + "ccc_input_" + runTag$ + ".wav"
tempOutput$ = tempDir$ + "ccc_output_" + runTag$ + ".wav"
tempMeta$   = tempDir$ + "ccc_meta_" + runTag$ + ".json"
tempTG$     = tempDir$ + "ccc_output_" + runTag$ + ".TextGrid"
# Scratch copy of the gesture drawn in the Demo window (corpus_draw_contour
# format). The backend reads it with --contour and writes the persistent copy
# to usedContour$, so this one is deleted at cleanup like the other scratch files.
tempDrawn$  = tempDir$ + "ccc_drawn_" + runTag$ + ".txt"
tempLog$    = tempDir$ + "ccc_pylog_" + runTag$ + ".txt"
probeMarker$ = tempDir$ + "ccc_probe_" + runTag$ + ".txt"
tempBuildMarker$ = tempDir$ + "ccc_build_ok_" + runTag$ + ".txt"
# Persistent, normalized Draw trajectory actually used by this run. Unlike the
# scratch drawn-gesture file (tempDrawn$), this is NOT deleted at cleanup: it is the reusable
# compositional gesture / reproducibility record.
usedContour$ = drawContourDir$ + "draw_contour_" + runTag$ + ".txt"

# The Python backend also writes a CRASH DUMP with a FIXED name (no run tag,
# since main()'s top-level exception handler doesn't know about runTag$) to
# the same folder as --log (i.e. tempDir$) whenever it hits an uncaught
# exception - see corpus_concat_codec.py's "corpus_concat_crash.txt". The
# traceback it contains is also already teed into tempLog$, so nothing is
# lost by deleting it; it previously wasn't in this cleanup list at all,
# so it just sat in the corpus folder forever once written.
tempCrash$  = tempDir$ + "corpus_concat_crash.txt"

# NOTE: no forward-slash / quoting conversions are needed for the command
# line below. We call Python via runSubprocess, which hands each argument
# to the executable directly (no shell involved), so backslashes, spaces,
# and quotes in paths are passed through verbatim and need no escaping.

# ---- CLEANUP (harmless up-front sweep) ----
# With per-run unique filenames (runTag$ above), this call can't find
# anything from the CURRENT run yet, so it's effectively a no-op except in
# the rare case fileReadable somehow matched anyway. Note the tradeoff this
# introduces versus the previous fixed-filename scheme: a crashed PREVIOUS
# run (different runTag$) is no longer auto-swept here, since its filenames
# don't match this run's. Its ccc_*_<oldTag>.* files are harmless orphans
# (never read by anything once their run ends) but will accumulate in
# tempDir$ over many crashed runs; delete them by hand periodically if that
# matters. The one exception is tempCrash$ (corpus_concat_crash.txt): it has
# NO run tag, so a PREVIOUS run's crash dump - which the failure branches
# below now also clean up immediately, but which could still be left behind
# by e.g. a killed process - IS caught right here, every run.
@cleanUpTempFiles
# The end-of-run sweep (see the second "@cleanUpTempFiles" near the bottom,
# after a successful Match run) is the one that matters: by then
# ccc_output_<runTag$>.wav has already been read into a Praat Sound object,
# so the on-disk copy (and the meta/TextGrid/log that went with it) is just
# leftover scratch, not data. Build mode never reaches that second call: it
# doesn't produce any ccc_* files in the first place, only the internal corpus cache
# itself.

procedure cleanUpTempFiles
    if fileReadable(tempInput$)
        deleteFile: tempInput$
    endif
    if fileReadable(tempOutput$)
        deleteFile: tempOutput$
    endif
    if fileReadable(tempMeta$)
        deleteFile: tempMeta$
    endif
    if fileReadable(tempTG$)
        deleteFile: tempTG$
    endif
    if fileReadable(tempDrawn$)
        deleteFile: tempDrawn$
    endif
    if fileReadable(tempLog$)
        deleteFile: tempLog$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
    if fileReadable(tempBuildMarker$)
        deleteFile: tempBuildMarker$
    endif
    if fileReadable(tempCrash$)
        deleteFile: tempCrash$
    endif
endproc

# Print the Python stderr log (written directly by Python via --log, since
# runSubprocess doesn't go through a shell and so can't use a 2> redirect)
# to the Info window, so the actual error is visible instead of a generic
# "it failed" message.
procedure showPyLog
    if fileReadable(tempLog$)
        Read Strings from raw text file: tempLog$
        .logId = selected("Strings")
        .n = Get number of strings
        if .n > 0
            appendInfoLine: ""
            appendInfoLine: "----- Python error output -----"
            for .i to .n
                selectObject: .logId
                .line$ = Get string: .i
                appendInfoLine: "  ", .line$
            endfor
            appendInfoLine: "-------------------------------"
        endif
        removeObject: .logId
    endif
endproc

# ============================================================
# DRAW MODE - Demo-window gesture surface (v1.12.0)
# All state lives in globals prefixed "dd" so nothing collides with the rest
# of the script. The Demo window is 0..100 in both directions with y pointing
# UP; every hit test is done in those percent units, with the full-window
# viewport re-selected first so demoX()/demoY() return percent coordinates.
# ============================================================

procedure ddLoadCorpusBrightness: .jsonPath$
    # Same brightness scale as the backend's draw(): log spectral centroid of
    # every grain, normalised to 0..1 over the corpus. The index JSON is
    # tokenised on its "centroid_hz" keys (one token per grain), so the scan
    # is one pass regardless of how many other fields each grain carries.
    .raw$ = readFile$(.jsonPath$)
    .raw$ = replace$(.raw$, "@", "", 0)
    .raw$ = replace$(.raw$, """centroid_hz"":", "@", 0)
    Create Strings as tokens: .raw$, "@"
    .strId = selected("Strings")
    .nTok = Get number of strings
    ddNG = 0
    ddLogC# = zero#(max(1, .nTok - 1))
    for .i from 2 to .nTok
        selectObject: .strId
        .tok$ = Get string: .i
        .c = extractNumber(.tok$, "")
        if .c <> undefined
            ddNG = ddNG + 1
            ddLogC#[ddNG] = ln(max(.c, 1e-6))
        endif
    endfor
    removeObject: .strId
    if ddNG = 0
        exitScript: "This corpus index has no per-grain brightness data (built with an" + newline$
            ... + "older version). Rebuild the corpus to use Draw mode."
    endif
    .cmin = ddLogC#[1]
    .cmax = ddLogC#[1]
    for .i to ddNG
        .cmin = min(.cmin, ddLogC#[.i])
        .cmax = max(.cmax, ddLogC#[.i])
    endfor
    ddBright# = zero#(ddNG)
    for .i to ddNG
        ddBright#[.i] = (ddLogC#[.i] - .cmin) / (.cmax - .cmin + 1e-9)
    endfor
    ddCentroidMin = exp(.cmin)
    ddCentroidMax = exp(.cmax)

    # density histogram of grain brightness, used for the strip and bands
    ddNB = 40
    ddHist# = zero#(ddNB)
    for .i to ddNG
        .b = min(ddNB, floor(ddBright#[.i] * ddNB) + 1)
        ddHist#[.b] = ddHist#[.b] + 1
    endfor
    ddHistMax = max(ddHist#)
    ddEmptyBins = 0
    for .b to ddNB
        if ddHist#[.b] = 0
            ddEmptyBins = ddEmptyBins + 1
        endif
    endfor
endproc

procedure ddInit: .dur, .rateMs, .stretch
    ddDur = .dur
    ddStep = max(0.001, .rateMs / 1000)
    ddStretch = .stretch
    ddState = 0
    ddSel = 0
    ddUndoDepth = 0
    ddUndoMax = 60
    ddMsg$ = ""
    # geometry (Demo-window percent units, y up)
    ddX1 = 8
    ddX2 = 82
    ddY1 = 27
    ddY2 = 86
    ddSX1 = 86
    ddSX2 = 96
    ddHitRadius = 2.0
    # buttons: 1 Undo, 2 Reset, 3 Stretch, 4 Cancel, 5 Render
    ddBy1 = 8
    ddBy2 = 14
    ddBx1[1] = 3
    ddBx2[1] = 16
    ddBx1[2] = 18
    ddBx2[2] = 31
    ddBx1[3] = 33
    ddBx2[3] = 52
    ddBx1[4] = 64
    ddBx2[4] = 79
    ddBx1[5] = 81
    ddBx2[5] = 97
    @ddResetPoints
endproc

procedure ddResetPoints
    # same starting gesture as the old RealTier default: a dark-to-bright ramp
    ddN = 2
    ddT[1] = 0
    ddV[1] = 0
    ddT[2] = ddDur
    ddV[2] = 1
    ddSel = 0
endproc

procedure ddPushUndo
    if ddUndoDepth >= ddUndoMax
        for .k to ddUndoMax - 1
            .kn = .k + 1
            ddUN[.k] = ddUN[.kn]
            for .i to ddUN[.k]
                ddUT[.k, .i] = ddUT[.kn, .i]
                ddUV[.k, .i] = ddUV[.kn, .i]
            endfor
        endfor
        ddUndoDepth = ddUndoMax - 1
    endif
    ddUndoDepth = ddUndoDepth + 1
    ddUN[ddUndoDepth] = ddN
    for .i to ddN
        ddUT[ddUndoDepth, .i] = ddT[.i]
        ddUV[ddUndoDepth, .i] = ddV[.i]
    endfor
endproc

procedure ddUndo
    if ddUndoDepth = 0
        ddMsg$ = "nothing to undo"
    else
        ddN = ddUN[ddUndoDepth]
        for .i to ddN
            ddT[.i] = ddUT[ddUndoDepth, .i]
            ddV[.i] = ddUV[ddUndoDepth, .i]
        endfor
        ddUndoDepth = ddUndoDepth - 1
        ddSel = 0
    endif
endproc

procedure ddInsert: .t, .v
    # sorted insert; a point at (numerically) the same time is replaced,
    # because a tier holds one value per time
    .eps = 1e-6 * ddDur
    .found = 0
    for .i to ddN
        if abs(ddT[.i] - .t) < .eps
            .found = .i
        endif
    endfor
    if .found > 0
        ddV[.found] = .v
    else
        .pos = ddN + 1
        for .i to ddN
            if .pos = ddN + 1
                if ddT[.i] > .t
                    .pos = .i
                endif
            endif
        endfor
        for .j to ddN - .pos + 1
            .src = ddN - .j + 1
            ddT[.src + 1] = ddT[.src]
            ddV[.src + 1] = ddV[.src]
        endfor
        ddT[.pos] = .t
        ddV[.pos] = .v
        ddN = ddN + 1
    endif
endproc

procedure ddDelete: .k
    for .i from .k to ddN - 1
        ddT[.i] = ddT[.i + 1]
        ddV[.i] = ddV[.i + 1]
    endfor
    ddN = ddN - 1
endproc

procedure ddInteriorTime: .t
    # interior points never land on (or beyond) the locked end points
    .eps = 0.002 * ddDur
    ddIT = min(max(.t, .eps), ddDur - .eps)
endproc

procedure ddMovePoint: .k, .t, .v
    @ddPushUndo
    if .k = 1 or .k = ddN
        # end points are locked in time, free in value
        ddV[.k] = .v
    else
        @ddDelete: .k
        @ddInteriorTime: .t
        @ddInsert: ddIT, .v
    endif
endproc

procedure ddNearest: .px, .py
    ddNear = 0
    ddNearDist = 1e30
    for .i to ddN
        .x = ddX1 + ddT[.i] / ddDur * (ddX2 - ddX1)
        .y = ddY1 + ddV[.i] * (ddY2 - ddY1)
        .d = sqrt((.x - .px) ^ 2 + (.y - .py) ^ 2)
        if .d < ddNearDist
            ddNearDist = .d
            ddNear = .i
        endif
    endfor
endproc

procedure ddEffective
    # ddE[] = the values actually written to the contour file. Without
    # stretch they are the drawn values; with stretch they reproduce the
    # legacy RealTier behaviour (drawn min..max -> 0..1, flat -> 0.5).
    .vmin = ddV[1]
    .vmax = ddV[1]
    for .i to ddN
        .vmin = min(.vmin, ddV[.i])
        .vmax = max(.vmax, ddV[.i])
    endfor
    for .i to ddN
        if ddStretch
            if .vmax - .vmin > 1e-9
                ddE[.i] = (ddV[.i] - .vmin) / (.vmax - .vmin)
            else
                ddE[.i] = 0.5
            endif
        else
            ddE[.i] = ddV[.i]
        endif
    endfor
endproc

procedure ddInterp: .t
    # linear interpolation of ddE[], held flat beyond the ends (= np.interp)
    if .t <= ddT[1]
        ddInterpV = ddE[1]
    elsif .t >= ddT[ddN]
        ddInterpV = ddE[ddN]
    else
        .done = 0
        for .i to ddN - 1
            if .done = 0
                .i1 = .i + 1
                if .t <= ddT[.i1]
                    .span = ddT[.i1] - ddT[.i]
                    if .span > 0
                        ddInterpV = ddE[.i] + (ddE[.i1] - ddE[.i]) * (.t - ddT[.i]) / .span
                    else
                        ddInterpV = ddE[.i1]
                    endif
                    .done = 1
                endif
            endif
        endfor
    endif
endproc

procedure ddNiceStep: .raw
    .p = 10 ^ floor(log10(.raw))
    .m = .raw / .p
    if .m < 1.5
        ddNice = .p
    elsif .m < 3.5
        ddNice = 2 * .p
    elsif .m < 7.5
        ddNice = 5 * .p
    else
        ddNice = 10 * .p
    endif
endproc

procedure ddVP: .x1, .x2, .y1, .y2, .ax1, .ax2, .ay1, .ay2
    # Font size must already be set: Praat derives the drawing frame from
    # the font size current at selection time.
    demo Select inner viewport: .x1, .x2, .y1, .y2
    demo Axes: .ax1, .ax2, .ay1, .ay2
endproc

procedure ddRedraw
    @ddEffective
    demo Erase all
    demo Colour: "Black"
    demo Line width: 1

    # ---- title strip ----
    demo Font size: 16
    @ddVP: 0, 100, 91, 99, 0, 1, 0, 1
    demo Text: 0.5, "centre", 0.70, "half", "##Corpus Concatenative Codec — Draw brightness contour##"
    demo Font size: 11
    @ddVP: 0, 100, 91, 99, 0, 1, 0, 1
    .stretchTxt$ = if ddStretch then "on" else "off" fi
    .sub$ = string$(ddNG) + " corpus grains  ·  " + fixed$(ddDur, 2) + " s  ·  grain rate "
        ... + fixed$(ddStep * 1000, 0) + " ms  ·  stretch " + .stretchTxt$
        ... + "  ·  " + string$(ddN) + " points"
    if ddSel > 0
        .sub$ = .sub$ + "  ·  point " + string$(ddSel) + " selected: click where it should go"
    endif
    if ddMsg$ <> ""
        .sub$ = .sub$ + "  ·  " + ddMsg$
    endif
    demo Text: 0.5, "centre", 0.18, "half", .sub$

    # ---- legend line above the main panel ----
    demo Font size: 10
    @ddVP: ddX1, ddX2, ddY2 + 0.5, 90.5, 0, 1, 0, 1
    demo Colour: {0.20, 0.40, 0.80}
    demo Text: 0.0, "left", 0.5, "half", "blue: your gesture"
    demo Colour: {0.90, 0.50, 0.10}
    demo Text: 0.2, "left", 0.5, "half", "orange: grain brightness each step will select"
    demo Colour: {0.45, 0.45, 0.45}
    demo Text: 0.62, "left", 0.5, "half", "shading: grain density"
    demo Colour: {0.80, 0.25, 0.25}
    demo Text: 0.83, "left", 0.5, "half", "red: no grains"
    demo Colour: "Black"

    # ---- main panel: density bands ----
    demo Font size: 10
    @ddVP: ddX1, ddX2, ddY1, ddY2, 0, ddDur, 0, 1
    for .b to ddNB
        .y0 = (.b - 1) / ddNB
        .y1 = .b / ddNB
        if ddHist#[.b] = 0
            demo Paint rectangle: {0.99, 0.90, 0.90}, 0, ddDur, .y0, .y1
        else
            .g = sqrt(ddHist#[.b] / ddHistMax)
            .col# = {1.00, 1.00, 1.00} - 0.30 * .g * {0.80, 0.60, 0.20}
            demo Paint rectangle: .col#, 0, ddDur, .y0, .y1
        endif
    endfor
    demo Colour: {0.75, 0.75, 0.75}
    demo Dotted line
    for .q to 3
        demo Draw line: 0, .q / 4, ddDur, .q / 4
    endfor
    demo Solid line

    # ---- preview: nearest grain brightness per grain-rate step ----
    # Mirrors the backend's selection without the repeat penalty.
    demo Colour: {0.90, 0.50, 0.10}
    demo Line width: 1.5
    .nSteps = max(1, round(ddDur / ddStep))
    .prevB = 0
    for .k from 0 to .nSteps - 1
        .t0 = .k * ddStep
        if .t0 < ddDur
            .t1 = min(ddDur, .t0 + ddStep)
            @ddInterp: .t0
            .d# = abs#(ddBright# - ddInterpV)
            .b = ddBright#[imin(.d#)]
            demo Draw line: .t0, .b, .t1, .b
            if .k > 0
                demo Draw line: .t0, .prevB, .t0, .b
            endif
            .prevB = .b
        endif
    endfor

    # ---- the drawn gesture ----
    if ddStretch
        # thin dashed curve = what stretch actually sends to the backend
        demo Colour: {0.20, 0.40, 0.80}
        demo Line width: 1
        demo Dashed line
        for .i to ddN - 1
            demo Draw line: ddT[.i], ddE[.i], ddT[.i + 1], ddE[.i + 1]
        endfor
        demo Solid line
    endif
    demo Colour: {0.20, 0.40, 0.80}
    demo Line width: 2.5
    for .i to ddN - 1
        demo Draw line: ddT[.i], ddV[.i], ddT[.i + 1], ddV[.i + 1]
    endfor
    demo Line width: 1
    for .i to ddN
        if .i = ddSel
            demo Paint circle (mm): {0.85, 0.15, 0.15}, ddT[.i], ddV[.i], 3.2
            demo Paint circle (mm): {1.00, 1.00, 1.00}, ddT[.i], ddV[.i], 2.0
        endif
        demo Paint circle (mm): {0.10, 0.10, 0.10}, ddT[.i], ddV[.i], 1.2
    endfor
    demo Colour: "Black"
    @ddVP: ddX1, ddX2, ddY1, ddY2, 0, ddDur, 0, 1
    demo Draw inner box
    @ddVP: ddX1, ddX2, ddY1, ddY2, 0, ddDur, 0, 1
    demo Marks left every: 1, 0.25, "yes", "yes", "no"
    @ddNiceStep: ddDur / 5
    demo Marks bottom every: 1, ddNice, "yes", "yes", "no"
    demo Text left: "yes", "brightness (0 dark, 1 bright)"
    demo Text bottom: "yes", "time (s)"

    # ---- corpus density strip ----
    demo Font size: 10
    @ddVP: ddSX1, ddSX2, ddY1, ddY2, 0, 1, 0, 1
    for .b to ddNB
        .y0 = (.b - 1) / ddNB
        .y1 = .b / ddNB
        if ddHist#[.b] = 0
            demo Paint rectangle: {0.99, 0.90, 0.90}, 0, 1, .y0, .y1
        else
            demo Paint rectangle: {0.20, 0.40, 0.80}, 0, ddHist#[.b] / ddHistMax, .y0, .y1
        endif
    endfor
    @ddVP: ddSX1, ddSX2, ddY1, ddY2, 0, 1, 0, 1
    demo Draw inner box
    @ddVP: ddSX1, ddSX2, ddY1, ddY2, 0, 1, 0, 1
    demo Text: 0.5, "centre", 1.01, "bottom", fixed$(ddCentroidMax, 0) + " Hz"
    demo Text: 0.5, "centre", -0.015, "top", fixed$(ddCentroidMin, 0) + " Hz"
    demo Text: 0.5, "centre", -0.075, "top", "corpus grains"

    # ---- control panel (grey), axes = percent units ----
    demo Font size: 11
    @ddVP: 0, 100, 1.5, 17.5, 0, 100, 1.5, 17.5
    demo Paint rectangle: {0.94, 0.94, 0.94}, 0, 100, 1.5, 17.5
    for .k to 5
        if .k = 1
            .lab$ = "Undo (U)"
            .col# = {1.00, 1.00, 1.00}
        elsif .k = 2
            .lab$ = "Reset (R)"
            .col# = {1.00, 1.00, 1.00}
        elsif .k = 3
            .lab$ = "Stretch (S): " + .stretchTxt$
            .col# = if ddStretch then {0.82, 0.88, 0.97} else {1.00, 1.00, 1.00} fi
        elsif .k = 4
            .lab$ = "Cancel (Esc)"
            .col# = {0.98, 0.88, 0.88}
        else
            .lab$ = "##Render (Enter)##"
            .col# = {0.86, 0.94, 0.86}
        endif
        demo Paint rectangle: .col#, ddBx1[.k], ddBx2[.k], ddBy1, ddBy2
        demo Colour: "Black"
        demo Draw rectangle: ddBx1[.k], ddBx2[.k], ddBy1, ddBy2
        demo Text: (ddBx1[.k] + ddBx2[.k]) / 2, "centre", (ddBy1 + ddBy2) / 2, "half", .lab$
    endfor
    demo Font size: 10
    @ddVP: 0, 100, 1.5, 17.5, 0, 100, 1.5, 17.5
    demo Text: 50, "centre", 4.5, "half",
        ... "click empty space: add point  ·  click a point, then click elsewhere: move it  ·  shift-click a point: delete  ·  end points move vertically only"
    @ddVP: 0, 100, 1.5, 17.5, 0, 100, 1.5, 17.5
    demo Draw inner box
    demoShow()
endproc

procedure ddHandleInput
    demo Select inner viewport: 0, 100, 0, 100
    demo Axes: 0, 100, 0, 100
    ddMsg$ = ""
    if demoClicked()
        .px = demoX()
        .py = demoY()
        .shift = demoShiftKeyPressed()
        if .px >= ddX1 - 1.5 and .px <= ddX2 + 1.5 and .py >= ddY1 - 1.5 and .py <= ddY2 + 1.5
            @ddClickPanel: .px, .py, .shift
        else
            .hit = 0
            for .k to 5
                if .px >= ddBx1[.k] and .px <= ddBx2[.k] and .py >= ddBy1 and .py <= ddBy2
                    .hit = .k
                endif
            endfor
            if .hit > 0
                @ddAction: .hit
            endif
        endif
    elsif demoKeyPressed()
        # Key codes differ per platform (Enter is 13 on Windows/macOS but
        # 65293 on Linux/GTK), so all known variants are accepted; the
        # on-screen buttons are the platform-independent route.
        .k$ = demoKey$()
        if .k$ = "u" or .k$ = "U"
            @ddAction: 1
        elsif .k$ = "r" or .k$ = "R"
            @ddAction: 2
        elsif .k$ = "s" or .k$ = "S"
            @ddAction: 3
        elsif .k$ = unicode$(27)
            @ddAction: 4
        elsif .k$ = unicode$(13) or .k$ = unicode$(10) or .k$ = unicode$(65293) or .k$ = unicode$(65421)
            @ddAction: 5
        elsif .k$ = "x" or .k$ = "X" or .k$ = unicode$(8) or .k$ = unicode$(127)
            ... or .k$ = unicode$(65288) or .k$ = unicode$(65535)
            @ddAction: 6
        endif
    endif
endproc

procedure ddAction: .a
    if .a = 1
        @ddUndo
    elsif .a = 2
        @ddPushUndo
        @ddResetPoints
        ddMsg$ = "reset to the default ramp (U undoes)"
    elsif .a = 3
        ddStretch = 1 - ddStretch
    elsif .a = 4
        ddState = 2
    elsif .a = 5
        ddState = 1
    elsif .a = 6
        if ddSel > 1 and ddSel < ddN
            @ddPushUndo
            @ddDelete: ddSel
            ddSel = 0
        elsif ddSel > 0
            ddMsg$ = "end points cannot be deleted"
        else
            ddMsg$ = "select a point first"
        endif
    endif
endproc

procedure ddClickPanel: .px, .py, .shift
    .t = min(max((.px - ddX1) / (ddX2 - ddX1) * ddDur, 0), ddDur)
    .v = min(max((.py - ddY1) / (ddY2 - ddY1), 0), 1)
    @ddNearest: .px, .py
    .near = if ddNearDist <= ddHitRadius then ddNear else 0 fi
    if .shift
        if .near > 1 and .near < ddN
            @ddPushUndo
            @ddDelete: .near
            ddSel = 0
        elsif .near > 0
            ddMsg$ = "end points cannot be deleted"
        else
            ddMsg$ = "shift-click ON a point to delete it"
        endif
    elsif ddSel > 0
        if .near = ddSel
            ddSel = 0
        elsif .near > 0
            ddSel = .near
        else
            @ddMovePoint: ddSel, .t, .v
            ddSel = 0
        endif
    elsif .near > 0
        ddSel = .near
    else
        @ddPushUndo
        @ddInteriorTime: .t
        @ddInsert: ddIT, .v
    endif
endproc

procedure ddShowRendering
    # last frame before Praat blocks in runSubprocess, so the window does not
    # look frozen mid-edit
    demo Font size: 12
    @ddVP: 0, 100, 1.5, 17.5, 0, 100, 1.5, 17.5
    demo Paint rectangle: {0.94, 0.94, 0.94}, 0, 100, 1.5, 17.5
    demo Colour: "Black"
    demo Text: 50, "centre", 9.5, "half",
        ... "##Rendering…## Praat is busy until the synthesis finishes; progress and results go to the Info window."
    @ddVP: 0, 100, 1.5, 17.5, 0, 100, 1.5, 17.5
    demo Draw inner box
    demoShow()
endproc

procedure ddWriteContour: .path$
    # Writes the corpus_draw_contour 1 format read by the backend's
    # read_draw_contour(); values are the EFFECTIVE (post-stretch) ones.
    @ddEffective
    .src$ = if ddStretch then "praat_demo_window (stretched)" else "praat_demo_window" fi
    .txt$ = "# Praat AudioTools - Corpus Concatenative Codec Draw contour" + newline$
    .txt$ = .txt$ + "# time_s normalized_brightness   (0=dark, 1=bright)" + newline$
    .txt$ = .txt$ + "# source: " + .src$ + newline$
    .txt$ = .txt$ + "format corpus_draw_contour 1" + newline$
    .txt$ = .txt$ + "duration " + fixed$(ddDur, 6) + newline$
    .txt$ = .txt$ + "[CURVE]" + newline$
    for .i to ddN
        # rounding first keeps fixed$ from printing long tails for tiny values
        .t = round(ddT[.i] * 1e6) / 1e6
        .v = round(ddE[.i] * 1e6) / 1e6
        .txt$ = .txt$ + fixed$(.t, 6) + " " + fixed$(.v, 6) + newline$
    endfor
    writeFile: .path$, .txt$
endproc


# ============================================================
# BUILD CORPUS MODE
# ============================================================
if mode = 2
    appendInfoLine: "=== Building / replacing corpus ==="
    appendInfoLine: "Codec: ", codec$
    appendInfoLine: "Target audio: ", corpus_audio$
    appendInfoLine: "Internal corpus cache: ", corpusIndexPath$
    appendInfoLine: "This may take a while (encoding every grain)..."

    buildCmd$ = python_exe$ + " " + backend_script$ + " build-corpus --codec " + codec$
        ... + " --corpus-audio " + corpus_audio$ + " --index " + corpusIndexPath$
        ... + " --grain-ms " + string$(grain_ms) + " --hop-ms " + string$(hop_ms)
        ... + " --atomic"

    # Transactional rebuild: the backend builds the complete new corpus in a
    # sibling staging directory. Only after JSON + feature matrix + grain audio
    # all exist does it replace the live corpus. If building fails, the previous
    # successful corpus stays untouched and Match can continue using it.

    # runSubprocess hands each argument to Python directly (no shell), so
    # there is no quoting to get wrong; nocheck stops Praat from halting the
    # script on a nonzero exit code (we check for the index file ourselves).
    nocheck runSubprocess: python_exe$, backend_script$,
        ... "build-corpus",
        ... "--codec", codec$,
        ... "--corpus-audio", corpus_audio$,
        ... "--index", corpusIndexPath$,
        ... "--grain-ms", string$(grain_ms),
        ... "--hop-ms", string$(hop_ms),
        ... "--atomic",
        ... "--success-marker", tempBuildMarker$,
        ... "--log", tempLog$

    if fileReadable(tempBuildMarker$) and fileReadable(corpusIndexPath$ + ".json")
        appendInfoLine: ""
        appendInfoLine: "Corpus analysis built/replaced successfully."
        appendInfoLine: "Internal cache: ", corpusIndexPath$, ".json"
        appendInfoLine: "You can now run Match mode on a selected Sound."
        # Only tempLog$ (and, rarely, tempCrash$) can exist at this point -
        # build mode never touches tempInput$/tempOutput$/tempMeta$/tempTG$/
        # tempDrawn$ - but this branch never cleaned up either of them, so
        # every successful build left an empty ccc_pylog_<tag>.txt behind.
        # The corpus index itself is untouched: it isn't part of this list.
        @cleanUpTempFiles
    else
        appendInfoLine: ""
        appendInfoLine: "Equivalent command (for reference):"
        appendInfoLine: buildCmd$
        @showPyLog
        @cleanUpTempFiles
        exitScript: "Corpus build failed - the new analysis was not installed." + newline$
            ... + "The Python error is printed in the Info window above." + newline$
            ... + "If a previous successful corpus existed, it was left intact and can still be used by Match."
    endif
    # build mode ends here
    goto END
endif

# ============================================================
# DRAW MODE - a brightness contour navigates the corpus
# The gesture is drawn in the Demo window (v1.12.0; previously the RealTier
# editor) and written straight to the explicit, persistent representation:
# time -> normalized brightness. A saved contour can be loaded directly for
# exact replay / batch work.
# ============================================================
if mode = 3
    # index must exist (Draw needs the corpus's per-grain brightness)
    if not fileReadable(corpusIndexPath$ + ".json")
        exitScript: "No analysed corpus is available yet." + newline$
            ... + "Run Build / replace corpus first (or run Match once to auto-build)."
    endif

    drawSourceArg$ = ""
    drawSourcePath$ = ""
    drawBackendDuration$ = "0"

    if draw_source = 1
        # ---- INTERACTIVE (DEMO WINDOW) ----
        # v1.12.0: replaces the RealTier editor. Nothing in this branch creates
        # a Praat object, so there is no editor whose lifetime the script has
        # to manage, and nothing is destroyed underneath the user before the
        # blocking runSubprocess call below.
        @ddLoadCorpusBrightness: corpusIndexPath$ + ".json"
        @ddInit: draw_duration_s, grain_rate_ms, stretch_drawn_range
        demoWindowTitle: "Corpus Concatenative Codec - Draw brightness contour"

        # The wait stays at the TOP LEVEL of the script, not inside a
        # procedure: demoWaitForInput suspends the interpreter and resumes it
        # at this very line when the user clicks or types in the Demo window.
        # Closing the Demo window here stops the script (Praat's own
        # behaviour); no objects or temp files exist yet at this point.
        while ddState = 0
            @ddRedraw
            ddDummy = demoWaitForInput()
            @ddHandleInput
        endwhile

        if ddState = 2
            @cleanUpTempFiles
            exitScript: "Draw cancelled - nothing was rendered."
        endif

        @ddShowRendering
        @ddWriteContour: tempDrawn$
        if not fileReadable(tempDrawn$)
            @cleanUpTempFiles
            exitScript: "Could not write the drawn contour to:" + newline$ + tempDrawn$
        endif

        # The drawn gesture is handed over in the same corpus_draw_contour
        # format a saved contour uses. It carries its own duration
        # (= Draw duration s), so the backend is told not to stretch it.
        drawSourceArg$ = "--contour"
        drawSourcePath$ = tempDrawn$
        drawBackendDuration$ = "0"

    else
        # ---- SAVED CONTOUR FILE ----
        # This bypasses the editor entirely. The file stores the normalized
        # time->brightness trajectory that a previous Draw run actually used.
        if contour_file$ = ""
            exitScript: "Draw source is Contour file, but no contour file path was supplied."
        endif
        if not fileReadable(contour_file$)
            exitScript: "Cannot read Draw contour file:" + newline$ + contour_file$
        endif
        drawSourceArg$ = "--contour"
        drawSourcePath$ = contour_file$
        # 0 tells the backend to preserve the contour file's stored duration.
        drawBackendDuration$ = "0"
    endif

    appendInfoLine: "=== Draw mode (brightness contour) ==="
    appendInfoLine: "Corpus: ", corpusIndexPath$
    if draw_source = 1
        appendInfoLine: "Gesture source: Interactive (Demo window)",
            ... if ddStretch then "   [stretched to 0..1]" else "" fi
        appendInfoLine: "Duration: ", string$(draw_duration_s), " s   Grain rate: ", string$(grain_rate_ms), " ms"
    else
        appendInfoLine: "Gesture source: saved contour file"
        appendInfoLine: "Contour: ", contour_file$
        appendInfoLine: "Duration: stored in contour file   Grain rate: ", string$(grain_rate_ms), " ms"
    endif
    appendInfoLine: "Normalized contour copy: ", usedContour$
    appendInfoLine: "Synthesising..."

    nocheck runSubprocess: python_exe$, backend_script$, "draw",
        ... drawSourceArg$, drawSourcePath$,
        ... "--contour-out", usedContour$,
        ... "--output", tempOutput$,
        ... "--index", corpusIndexPath$,
        ... "--metadata", tempMeta$,
        ... "--textgrid", tempTG$,
        ... "--duration", drawBackendDuration$,
        ... "--grain-rate-ms", string$(grain_rate_ms),
        ... "--xfade-ms", string$(crossfade_ms),
        ... "--repeat-penalty", string$(repeat_penalty),
        ... "--log", tempLog$

    if not fileReadable(tempOutput$)
        @showPyLog
        @cleanUpTempFiles
        exitScript: "Draw synthesis failed - no output produced." + newline$
            ... + "Any Python error is shown in the Info window above."
    endif

    if not fileReadable(usedContour$)
        @showPyLog
        @cleanUpTempFiles
        exitScript: "Draw synthesis produced audio but did not save its normalized contour." + newline$
            ... + "The run was stopped because the Draw gesture would not be reproducible."
    endif

    Read from file: tempOutput$
    drawResult = selected("Sound")
    Rename: "drawn_concat"
    appendInfoLine: "Imported result: drawn_concat"
    appendInfoLine: "Reusable Draw contour saved: ", usedContour$

    if import_textgrid and fileReadable(tempTG$)
        Read from file: tempTG$
        Rename: "drawn_grains"
    endif

    # Scratch drawn-gesture/output/meta/TextGrid/log files are temporary. The saved
    # normalized contour under draw_contours/ is intentional persistent data.
    @cleanUpTempFiles

    if play_result
        selectObject: drawResult
        Play
    endif
    selectObject: drawResult
    goto END
endif

# ============================================================
# GESTURE RHYME MODE - re-voice an abstract kinetic gesture by codec-token
# transition (hashed-bigram) rhyming. The source may be an abstract dictionary
# of kinetic shapes (accelerating clicks, a bouncing ball, an explosive attack
# decaying into hiss, a microtonal dive, tremolo flutter) rather than a phrase.
# The system ignores literal sound identity as much as possible and searches
# the EXISTING corpus for grains whose token-transition structure follows the
# same internal movement: a click-train can be voiced by speech syllables,
# field recordings, or instrument noises that simply move the same way.
# This mode never builds or reslices the corpus - it requires an existing index.
# ============================================================
if mode = 4
    if numberOfSelected("Sound") <> 1
        exitScript: "Gesture rhyme: please select exactly one Sound (the abstract gesture source)."
    endif
    source = selected("Sound")
    sourceName$ = selected$("Sound")

    # Existing index REQUIRED - gesture mode never builds the corpus.
    if not fileReadable(corpusIndexPath$ + ".json")
        exitScript: "Gesture rhyme needs an analysed corpus." + newline$
            ... + "Run Build / replace corpus first; gesture mode never builds."
    endif

    selectObject: source
    Save as WAV file: tempInput$
    if not fileReadable(tempInput$)
        exitScript: "Could not export the selected Sound to a temp WAV."
    endif

    # Persist the provenance metadata under a SOURCE-NAMED file (not the shared
    # ccc_meta.json that cleanUpTempFiles deletes), so it survives the run for
    # studying which unrelated corpus grains voiced each gesture.
    # Sanitize before using it in a FILENAME - Sound object names are free
    # text and can contain characters (/ \ : ? * " < > |) that are illegal
    # or path-breaking on at least one OS. The Sound object itself keeps its
    # real name; only the on-disk metadata filename is sanitized.
    safeSourceName$ = replace_regex$(sourceName$, "[\\/:*?""<>|]", "_", 0)
    gestureMeta$ = tempDir$ + safeSourceName$ + "_gesture_rhyme_meta.json"
    if fileReadable(gestureMeta$)
        deleteFile: gestureMeta$
    endif

    appendInfoLine: "=== Gesture Rhyme (hashed-bigram kinetics) ==="
    appendInfoLine: "Source gesture: ", sourceName$
    appendInfoLine: "Corpus: ", corpusIndexPath$
    appendInfoLine: "Bigram weight: ", string$(bigram_weight),
        ... "   Hist weight: ", string$(hist_weight),
        ... "   Energy weight: ", string$(gesture_energy_weight),
        ... "   Sequence context: ", string$(sequence_context)
    if random_baseline
        appendInfoLine: "Random baseline ABLATION active (seed ", string$(random_seed),
            ... ") - distance matching is IGNORED; corpus grains are chosen uniformly at random."
    else
        appendInfoLine: "Searching corpus for grains whose token-transition motion rhymes with the gesture..."
    endif

    textgridArg$ = ""
    if import_textgrid
        textgridArg$ = tempTG$
    endif

    # runSubprocess passes each argument straight to Python (no shell), so no
    # quoting is needed; nocheck stops Praat halting on a nonzero exit - we
    # check for the output WAV ourselves and show the Python log if missing.
    nocheck runSubprocess: python_exe$, backend_script$,
        ... "gesture-rhyme",
        ... "--codec", codec$,
        ... "--input", tempInput$,
        ... "--output", tempOutput$,
        ... "--index", corpusIndexPath$,
        ... "--metadata", gestureMeta$,
        ... "--textgrid", textgridArg$,
        ... "--bigram-weight", string$(bigram_weight),
        ... "--hist-weight", string$(hist_weight),
        ... "--energy-weight", string$(gesture_energy_weight),
        ... "--analysis-grain-ms", string$(analysis_grain_ms),
        ... "--analysis-hop-ms", string$(analysis_hop_ms),
        ... "--onset-min-interval-ms", string$(onset_min_interval_ms),
        ... "--xfade-ms", string$(crossfade_ms),
        ... "--repeat-penalty", string$(repeat_penalty),
        ... "--sequence-context", string$(sequence_context),
        ... "--random-baseline", string$(random_baseline),
        ... "--seed", string$(random_seed),
        ... "--log", tempLog$

    if not fileReadable(tempOutput$)
        @showPyLog
        @cleanUpTempFiles
        exitScript: "Gesture rhyme failed - no output WAV produced." + newline$
            ... + "The Python error is shown in the Info window above." + newline$
            ... + "Common causes: missing corpus index (.json / _feats.npy), missing" + newline$
            ... + "grain audio files, an OBSOLETE index schema (rebuild it with Build / replace" + newline$
            ... + "corpus), or source too short."
    endif

    Read from file: tempOutput$
    result = selected("Sound")
    Rename: sourceName$ + "_gesture_rhyme"
    appendInfoLine: ""
    appendInfoLine: "Imported result: ", selected$("Sound")

    if import_textgrid and fileReadable(tempTG$)
        Read from file: tempTG$
        Rename: sourceName$ + "_gesture_rhyme_grains"
        appendInfoLine: "Imported grain TextGrid."
    endif

    if fileReadable(gestureMeta$)
        appendInfoLine: "Provenance metadata (which corpus grains voiced each gesture):"
        appendInfoLine: "  ", gestureMeta$
    endif

    # Clean the shared scratch (input/output/TextGrid/log/probe). The source-
    # named gestureMeta$ has a different name and is intentionally preserved.
    @cleanUpTempFiles

    if play_result
        selectObject: result
        Play
    endif
    selectObject: result
    goto END
endif

# ============================================================
# MATCH MODE
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object (the source selection)."
endif
source = selected("Sound")
sourceName$ = selected$("Sound")

# An analysed corpus is needed for matching. If none exists yet, build it now
# from the single Corpus_audio source field. Subsequent runs reuse the internal
# cache and are fast until the user explicitly runs Build / replace corpus.
if not fileReadable(corpusIndexPath$ + ".json")
    if corpus_audio$ = "" or not (fileReadable(corpus_audio$) or fileReadable(corpus_audio$ + "/"))
        # corpus_audio may be a folder; fileReadable on a folder is unreliable,
        # so only hard-fail when the field is clearly empty.
        if corpus_audio$ = ""
            exitScript: "No analysed corpus exists and no corpus audio source was given." + newline$
                ... + "Set 'Corpus audio' to your target sound(s)/folder, or run Build / replace corpus first."
        endif
    endif

    appendInfoLine: "=== No analysed corpus found - building it now (one time) ==="
    appendInfoLine: "Target audio: ", corpus_audio$
    appendInfoLine: "This encodes every grain and may take a while..."

    autoBuildCmd$ = python_exe$ + " " + backend_script$ + " build-corpus --codec " + codec$
        ... + " --corpus-audio " + corpus_audio$ + " --index " + corpusIndexPath$
        ... + " --grain-ms " + string$(grain_ms) + " --hop-ms " + string$(hop_ms)
        ... + " --atomic"

    nocheck runSubprocess: python_exe$, backend_script$,
        ... "build-corpus",
        ... "--codec", codec$,
        ... "--corpus-audio", corpus_audio$,
        ... "--index", corpusIndexPath$,
        ... "--grain-ms", string$(grain_ms),
        ... "--hop-ms", string$(hop_ms),
        ... "--atomic",
        ... "--success-marker", tempBuildMarker$,
        ... "--log", tempLog$

    if not fileReadable(tempBuildMarker$) or not fileReadable(corpusIndexPath$ + ".json")
        appendInfoLine: ""
        appendInfoLine: "Command that was run:"
        appendInfoLine: autoBuildCmd$
        appendInfoLine: ""
        appendInfoLine: "Expected internal cache at: ", corpusIndexPath$, ".json"
        @showPyLog
        @cleanUpTempFiles
        exitScript: "Auto-build of the corpus failed - no new corpus was installed." + newline$
            ... + "The exact command and Python error are printed in the Info window above." + newline$
            ... + "Compare that command to one that works in a terminal."
    endif
    appendInfoLine: "Corpus analysis built: ", corpusIndexPath$, ".json"
    appendInfoLine: "(future runs will reuse it and start immediately)"
    appendInfoLine: ""
endif

# ---- EXPORT SELECTION TO TEMP WAV ----
selectObject: source
Save as WAV file: tempInput$
if not fileReadable(tempInput$)
    exitScript: "Could not export the selected Sound to a temp WAV."
endif

appendInfoLine: "=== Corpus Concatenative Synthesis ==="
appendInfoLine: "Source: ", sourceName$
appendInfoLine: "Codec requested: ", codec$, " (the corpus index's OWN codec is always used if it differs - see the Python warning below if so)"
appendInfoLine: "Internal corpus cache: ", corpusIndexPath$
appendInfoLine: "Preset: ", presetName$

# ---- BUILD COMMAND ----
# Pass --textgrid as an empty string when not requested; the Python backend
# already treats an empty/falsy value as "no TextGrid", so we don't need two
# separate runSubprocess call variants for the optional argument.
textgridArg$ = ""
if import_textgrid
    textgridArg$ = tempTG$
endif

appendInfoLine: "Calling Python backend..."

# runSubprocess passes each argument straight to Python with no shell in
# between, so no quoting is needed and Windows can't mangle the line.
# nocheck keeps Praat from halting on a nonzero exit code; we check for the
# output WAV ourselves and show the Python log if it's missing.
nocheck runSubprocess: python_exe$, backend_script$,
    ... "match",
    ... "--codec", codec$,
    ... "--input", tempInput$,
    ... "--output", tempOutput$,
    ... "--index", corpusIndexPath$,
    ... "--metadata", tempMeta$,
    ... "--textgrid", textgridArg$,
    ... "--xfade-ms", string$(crossfade_ms),
    ... "--repeat-penalty", string$(repeat_penalty),
    ... "--onset-min-interval-ms", string$(onset_min_interval_ms),
    ... "--analysis-grain-ms", string$(analysis_grain_ms),
    ... "--analysis-hop-ms", string$(analysis_hop_ms),
    ... "--energy-weight", string$(energy_weight),
    ... "--log", tempLog$

# ---- CHECK + IMPORT OUTPUT ----
if not fileReadable(tempOutput$)
    @showPyLog
    @cleanUpTempFiles
    exitScript: "Python backend failed - no output WAV produced." + newline$
        ... + "The Python error is printed in the Info window above." + newline$
        ... + "Common causes: codec not installed (encodec/dac), analysed corpus missing," + newline$
        ... + "an OBSOLETE index schema (rebuild it with Build / replace corpus), or" + newline$
        ... + "source selection too short."
endif

Read from file: tempOutput$
result = selected("Sound")
Rename: sourceName$ + "_concat"

appendInfoLine: ""
appendInfoLine: "Imported result: ", selected$("Sound")

# ---- OPTIONAL TEXTGRID ----
if import_textgrid and fileReadable(tempTG$)
    Read from file: tempTG$
    Rename: sourceName$ + "_grains"
    appendInfoLine: "Imported grain TextGrid."
endif

# ---- REPORT METADATA ----
if fileReadable(tempMeta$)
    appendInfoLine: "Metadata written (grain provenance): ", tempMeta$
endif

# ---- CLEANUP (run is done; Praat now holds the result in memory, so the
# on-disk scratch copies - input/output/meta/TextGrid/log/probe - are no
# longer needed. Only the internal corpus cache (current_corpus.json /
# _feats.npy / _grains/) survives, since that's what's needed to run again.) ----
@cleanUpTempFiles

# ---- PLAY ----
if play_result
    selectObject: result
    Play
endif

selectObject: result

label END
