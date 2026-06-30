# ============================================================
# Praat AudioTools - Corpus_Concatenative_Codec.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.6 (2026) - Added Gesture-rhyme mode (hashed-bigram kinetic matching)
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

form Corpus Concatenative Synthesis (codec) v1.6
    comment ── Mode ──
    optionmenu Mode: 1
        option Match (synthesise from corpus)
        option Build corpus index
        option Draw (brightness contour -> corpus)
        option Gesture rhyme (hashed bigram kinetics)
    comment ── Codec (only used when BUILDING the index; match reuses the corpus codec) ──
    optionmenu Codec: 1
        option dac
        option mock
    comment ── Draw mode: output length + grain rate ──
    positive Draw_duration_s 4.0
    positive Grain_rate_ms 80
    comment ── Corpus paths ──
    sentence Corpus_index my_corpus
    comment Target audio (folder or file) - used to BUILD or AUTO-BUILD the index:
    sentence Corpus_audio C:/Users/User/Desktop/target_sounds
    comment ── Corpus grains (BUILD mode only - the corpus has no rhythm of its own) ──
    positive Grain_ms 150
    positive Hop_ms 75
    comment ── Matching preset (overrides the matching values below, unless Custom) ──
    optionmenu Match_preset: 1
        option Custom
        option Rhythmic (follow transients)
        option Textural (smeared / washed)
        option Faithful (track source closely)
        option Sparse (distinct granular stutter)
    comment ── Matching (MATCH mode) ──
    positive Onset_min_interval_ms 60
    comment Sub-window matching (lets a decaying/evolving segment match new corpus material as it changes, instead of one grain for the whole segment):
    positive Analysis_grain_ms 60
    positive Analysis_hop_ms 30
    real Energy_weight 1.0
    positive Crossfade_ms 20
    real Repeat_penalty 0.05
    comment ── Gesture rhyme mode (re-voice an abstract gesture by token-transition / bigram rhyming) ──
    real Bigram_weight 4.0
    real Hist_weight 0.5
    real Gesture_energy_weight 0.2
    integer Sequence_context 2
    boolean Import_textgrid 1
    boolean Play_result 1
endform

clearinfo

# ---- MATCH PRESET OVERRIDE ----
# Each preset sets the matching cluster (onset spacing, sub-window grid, energy
# weight, crossfade, repeat penalty). Custom (1) keeps the form values. Build
# params (Grain_ms / Hop_ms) are never touched - they belong to the corpus.
presetName$ = "Custom"
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

tempInput$  = tempDir$ + "ccc_input.wav"
tempOutput$ = tempDir$ + "ccc_output.wav"
tempMeta$   = tempDir$ + "ccc_meta.json"
tempTG$     = tempDir$ + "ccc_output.TextGrid"
tempTier$   = tempDir$ + "ccc_curve.RealTier"
tempLog$    = tempDir$ + "ccc_pylog.txt"
probeMarker$ = tempDir$ + "ccc_probe.txt"

# NOTE: no forward-slash / quoting conversions are needed for the command
# line below. We call Python via runSubprocess, which hands each argument
# to the executable directly (no shell involved), so backslashes, spaces,
# and quotes in paths are passed through verbatim and need no escaping.

# ---- CLEANUP (delete stale temps UP FRONT so a crashed run can't import old output) ----
@cleanUpTempFiles
# Same sweep also runs again at the END of a successful Match run (see
# "@cleanUpTempFiles" near the bottom) - by then ccc_output.wav has already
# been read into a Praat Sound object, so the on-disk copy (and the meta/
# TextGrid/log that went with it) is just leftover scratch, not data. Build
# mode never reaches that second call: it doesn't produce any ccc_* files in
# the first place, only the corpus index itself.

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
    else
        appendInfoLine: ""
        appendInfoLine: "Equivalent command (for reference):"
        appendInfoLine: buildCmd$
        @showPyLog
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
        ... "--repeat-penalty", string$(repeat_penalty)

    if not fileReadable(tempOutput$)
        @showPyLog
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
    gestureMeta$ = tempDir$ + sourceName$ + "_gesture_rhyme_meta.json"
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
    appendInfoLine: "Searching corpus for grains whose token-transition motion rhymes with the gesture..."

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
        ... "--log", tempLog$

    if not fileReadable(tempOutput$)
        @showPyLog
        exitScript: "Gesture rhyme failed - no output WAV produced." + newline$
            ... + "The Python error is shown in the Info window above." + newline$
            ... + "Common causes: missing corpus index (.json / _feats.npy), missing" + newline$
            ... + "grain audio files, incompatible feature layout, or source too short."
    endif

    Read from file: tempOutput$
    result = selected("Sound")
    Rename: sourceName$ + "_gesture_rhyme_" + codec$
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
appendInfoLine: "Codec: ", codec$
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
    exitScript: "Python backend failed - no output WAV produced." + newline$
        ... + "The Python error is printed in the Info window above." + newline$
        ... + "Common causes: codec not installed (encodec/dac), corpus index missing," + newline$
        ... + "or source selection too short."
endif

Read from file: tempOutput$
result = selected("Sound")
Rename: sourceName$ + "_concat_" + codec$

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
