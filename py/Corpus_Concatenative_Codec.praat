# ============================================================
# Praat AudioTools - Corpus_Concatenative_Codec.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.9.3 (2026) - Fixed Build mode never cleaning up on success
#   v1.9.3: same class of bug as v1.9.2, but in Build corpus mode: the
#   success branch (index found on disk) printed its confirmation and fell
#   through to "goto END" without ever calling cleanUpTempFiles, so every
#   successful build left an empty ccc_pylog_<tag>.txt behind (Build mode
#   never creates tempInput$/tempOutput$/tempMeta$/tempTG$/tempTier$, so
#   only the log - and rarely tempCrash$ - could ever be present here, but
#   nothing removed even those). Fixed by adding the same @cleanUpTempFiles
#   call as the failure branch already had. The corpus index itself is not
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
#   Mode/Codec/Corpus paths/Import_textgrid/Play_result; right after it, a
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
#   You must build a corpus index once (Mode = Build corpus) before matching.
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

form Corpus Concatenative Synthesis (codec) v1.9.3
    comment ── Mode ──
    optionmenu Mode: 1
        option Match (synthesise from corpus)
        option Build corpus index
        option Draw (brightness contour -> corpus)
        option Gesture rhyme (hashed bigram kinetics)
    comment ── Codec (only used when BUILDING the index; match reuses the corpus codec) ──
    optionmenu Codec: 1
        option dac
        option encodec
        option mock
    comment ── Corpus paths ──
    sentence Corpus_index my_corpus
    comment Target audio (folder or file) - used to BUILD or AUTO-BUILD the index:
    sentence Corpus_audio C:/Users/User/Desktop/target_sounds
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
        comment: "Only used if Corpus_index doesn't exist yet and gets auto-built (the"
        comment: "corpus has no rhythm of its own, so it needs its own grain/hop size):"
        positive: "Grain ms", grain_ms
        positive: "Hop ms", hop_ms
    endPause: "Continue", 1

elsif mode = 2
    # ---- BUILD CORPUS MODE ----
    beginPause: "Build corpus index: grain settings"
        comment: "Corpus grains (the corpus has no rhythm of its own):"
        positive: "Grain ms", grain_ms
        positive: "Hop ms", hop_ms
    endPause: "Continue", 1

elsif mode = 3
    # ---- DRAW MODE ----
    beginPause: "Draw mode: output length + grain rate"
        positive: "Draw duration s", draw_duration_s
        positive: "Grain rate ms", grain_rate_ms
        comment: "Crossfade / repeat penalty:"
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
    python_exe$ = "python"
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

# Corpus index lives directly under the Praat preferences folder's corpus/
# subfolder unless an absolute path is given (a bare name like 'my_corpus'
# resolves there) - e.g. C:\Users\User\Praat\corpus\my_corpus.json
if startsWith(corpus_index$, "/") or index(corpus_index$, ":") > 0
    corpusIndexPath$ = corpus_index$
else
    corpusDir$ = preferencesDirectory$ + "/corpus/"
    createDirectory: corpusDir$
    corpusIndexPath$ = corpusDir$ + corpus_index$
endif
# Normalise to forward slashes so the path PYTHON writes and the path PRAAT
# checks are byte-identical (preferencesDirectory$ can return backslashes).
corpusIndexPath$ = replace_regex$(corpusIndexPath$, "\\", "/", 0)

# ---- TEMP / OUTPUT PATHS ----
# These are deleted at the START of every run AND again at the END of a
# successful Match run (see cleanUpTempFiles), so nothing lingers once a run
# finishes. Rather than leaving them buried in the OS temp folder, put them
# right next to the corpus index - e.g. if Corpus_index points into
# target_sounds, these land there too automatically.
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
tempTier$   = tempDir$ + "ccc_curve_" + runTag$ + ".RealTier"
tempLog$    = tempDir$ + "ccc_pylog_" + runTag$ + ".txt"
probeMarker$ = tempDir$ + "ccc_probe_" + runTag$ + ".txt"

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
# doesn't produce any ccc_* files in the first place, only the corpus index
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
    if fileReadable(tempTier$)
        deleteFile: tempTier$
    endif
    if fileReadable(tempLog$)
        deleteFile: tempLog$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
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
# BUILD CORPUS MODE
# ============================================================
if mode = 2
    appendInfoLine: "=== Building corpus index ==="
    appendInfoLine: "Codec: ", codec$
    appendInfoLine: "Target audio: ", corpus_audio$
    appendInfoLine: "Index: ", corpusIndexPath$
    appendInfoLine: "This may take a while (encoding every grain)..."

    buildCmd$ = python_exe$ + " " + backend_script$ + " build-corpus --codec " + codec$
        ... + " --corpus-audio " + corpus_audio$ + " --index " + corpusIndexPath$
        ... + " --grain-ms " + string$(grain_ms) + " --hop-ms " + string$(hop_ms)

    # IMPORTANT: if an OLD index already exists at this path, a build that
    # FAILS (wrong corpus_audio path, missing codec dependency, any Python
    # exception) leaves that old file completely untouched - it's still
    # "readable" on disk even though THIS run never wrote it. Checking only
    # fileReadable() afterwards can't tell "freshly built" apart from "old
    # file nothing touched", so it would print success and silently send you
    # into Match mode against stale data. Fix: delete the old index files
    # (and the old grains folder) BEFORE running build-corpus, so afterwards
    # fileReadable() can only be true if THIS run actually wrote them.
    if fileReadable(corpusIndexPath$ + ".json")
        deleteFile: corpusIndexPath$ + ".json"
    endif
    if fileReadable(corpusIndexPath$ + "_feats.npy")
        deleteFile: corpusIndexPath$ + "_feats.npy"
    endif

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
        ... "--log", tempLog$

    if fileReadable(corpusIndexPath$ + ".json")
        appendInfoLine: ""
        appendInfoLine: "Corpus index built: ", corpusIndexPath$, ".json"
        appendInfoLine: "You can now run Match mode on a selected Sound."
        # Only tempLog$ (and, rarely, tempCrash$) can exist at this point -
        # build mode never touches tempInput$/tempOutput$/tempMeta$/tempTG$/
        # tempTier$ - but this branch never cleaned up either of them, so
        # every successful build left an empty ccc_pylog_<tag>.txt behind.
        # The corpus index itself is untouched: it isn't part of this list.
        @cleanUpTempFiles
    else
        appendInfoLine: ""
        appendInfoLine: "Equivalent command (for reference):"
        appendInfoLine: buildCmd$
        @showPyLog
        @cleanUpTempFiles
        exitScript: "Corpus build failed - no index produced." + newline$
            ... + "The Python error is printed in the Info window above." + newline$
            ... + "Note: any PREVIOUS index at this path was deleted before this attempt,"
            ... + newline$ + "so Match mode will also fail until a build succeeds - this is"
            ... + newline$ + "intentional, so a failed rebuild can never be mistaken for a fresh one."
    endif
    # build mode ends here
    goto END
endif

# ============================================================
# DRAW MODE - draw a brightness contour; the corpus voices it
# ============================================================
if mode = 3
    # index must exist (draw needs the corpus's per-grain brightness)
    if not fileReadable(corpusIndexPath$ + ".json")
        exitScript: "No corpus index found at: " + corpusIndexPath$ + ".json" + newline$
            ... + "Build a corpus first (Build mode, or run Match once to auto-build)."
    endif

    # Create an empty RealTier for the user to draw on. The value axis is the
    # brightness target: low = dark/low corpus grains, high = bright/high ones.
    Create RealTier: "ccc_curve", 0, draw_duration_s
    tier = selected("RealTier")
    # Seed two anchor points so the editor has a visible 0..1 value range to
    # draw within (an empty tier gives the editor no vertical scale). The user
    # can drag, delete, or add to these freely - only the curve SHAPE matters,
    # since the Python side normalises the drawn values to their own range.
    Add point: 0, 0
    Add point: draw_duration_s, 1

    # Let the user draw. Editing the RealTier opens the draw window; the pause
    # lets them add/drag points before we read the curve back.
    View & Edit
    beginPause: "Draw your brightness contour"
        comment: "Draw a curve in the RealTier editor (click to add points,"
        comment: "drag to shape). Value axis = brightness: low picks dark/low"
        comment: "corpus grains, high picks bright/high ones."
        comment: "Click Continue when your gesture is ready."
    endPause: "Continue", 1

    selectObject: tier
    Save as text file: tempTier$
    removeObject: tier

    if not fileReadable(tempTier$)
        exitScript: "Could not export the drawn RealTier."
    endif

    appendInfoLine: "=== Draw mode (brightness contour) ==="
    appendInfoLine: "Corpus: ", corpusIndexPath$
    appendInfoLine: "Duration: ", string$(draw_duration_s), " s   Grain rate: ", string$(grain_rate_ms), " ms"
    appendInfoLine: "Synthesising..."

    nocheck runSubprocess: python_exe$, backend_script$, "draw",
        ... "--tier", tempTier$,
        ... "--output", tempOutput$,
        ... "--index", corpusIndexPath$,
        ... "--metadata", tempMeta$,
        ... "--textgrid", tempTG$,
        ... "--duration", string$(draw_duration_s),
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

    Read from file: tempOutput$
    drawResult = selected("Sound")
    Rename: "drawn_concat"
    appendInfoLine: "Imported result: drawn_concat"

    if import_textgrid and fileReadable(tempTG$)
        Read from file: tempTG$
        Rename: "drawn_grains"
    endif

    # Clean the scratch files (tier/output/meta/TextGrid/log/probe). This was
    # previously missing on the success path - every Draw run silently left
    # ccc_curve_<tag>.RealTier, ccc_output_<tag>.wav/.TextGrid, ccc_meta_<tag>.json
    # and ccc_pylog_<tag>.txt behind in the corpus folder forever, since only
    # the failure branch above cleaned up.
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
        exitScript: "Gesture rhyme needs an existing corpus index." + newline$
            ... + "None found at: " + corpusIndexPath$ + ".json" + newline$
            ... + "Build one first (Build corpus index mode); gesture mode never builds."
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
            ... + "grain audio files, an OBSOLETE index schema (rebuild it - Build corpus" + newline$
            ... + "index mode), or source too short."
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

# Corpus index needed for matching. If it doesn't exist yet, build it now
# (one-time slow pass: encodes every corpus grain). Subsequent runs reuse the
# saved index and are fast.
if not fileReadable(corpusIndexPath$ + ".json")
    if corpus_audio$ = "" or not (fileReadable(corpus_audio$) or fileReadable(corpus_audio$ + "/"))
        # corpus_audio may be a folder; fileReadable on a folder is unreliable,
        # so only hard-fail when the field is clearly empty.
        if corpus_audio$ = ""
            exitScript: "No corpus index found and no target audio given." + newline$
                ... + "Set 'Corpus audio' to your target sound(s)/folder so the index can be built,"
                ... + newline$ + "or run in 'Build corpus index' mode first."
        endif
    endif

    appendInfoLine: "=== No corpus index found - building it now (one time) ==="
    appendInfoLine: "Target audio: ", corpus_audio$
    appendInfoLine: "This encodes every grain and may take a while..."

    autoBuildCmd$ = python_exe$ + " " + backend_script$ + " build-corpus --codec " + codec$
        ... + " --corpus-audio " + corpus_audio$ + " --index " + corpusIndexPath$
        ... + " --grain-ms " + string$(grain_ms) + " --hop-ms " + string$(hop_ms)

    nocheck runSubprocess: python_exe$, backend_script$,
        ... "build-corpus",
        ... "--codec", codec$,
        ... "--corpus-audio", corpus_audio$,
        ... "--index", corpusIndexPath$,
        ... "--grain-ms", string$(grain_ms),
        ... "--hop-ms", string$(hop_ms),
        ... "--log", tempLog$

    if not fileReadable(corpusIndexPath$ + ".json")
        appendInfoLine: ""
        appendInfoLine: "Command that was run:"
        appendInfoLine: autoBuildCmd$
        appendInfoLine: ""
        appendInfoLine: "Expected index at: ", corpusIndexPath$, ".json"
        @showPyLog
        @cleanUpTempFiles
        exitScript: "Auto-build of the corpus index failed - no index produced." + newline$
            ... + "The exact command and Python error are printed in the Info window above." + newline$
            ... + "Compare that command to one that works in a terminal."
    endif
    appendInfoLine: "Corpus index built: ", corpusIndexPath$, ".json"
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
appendInfoLine: "Corpus: ", corpusIndexPath$
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
        ... + "Common causes: codec not installed (encodec/dac), corpus index missing," + newline$
        ... + "an OBSOLETE index schema (rebuild it - Build corpus index mode), or" + newline$
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
# longer needed. Only the corpus index (my_corpus.json / _feats.npy /
# _grains/) survives, since that's what's needed to run again.) ----
@cleanUpTempFiles

# ---- PLAY ----
if play_result
    selectObject: result
    Play
endif

selectObject: result

label END
