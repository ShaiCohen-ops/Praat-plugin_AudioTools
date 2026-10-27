# ============================================================
# Praat AudioTools - Corpus_Concatenative_Codec.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.16.6 (2026) - Argument file for Polyphonic Layers
#   v1.16.6: ROOT CAUSE of the Windows failure found - the backend received
#   only the first 1024 characters of its command line (mode 6 needs ~1200),
#   so --result was cut mid-path and --log lost. Mode 6 now writes its
#   arguments to a temporary file and passes "@file". Needs backend 1.8.3.
# Version: 1.16.5 (2026) - Single capturing backend call
#   v1.16.5: Polyphonic Layers calls the backend ONCE with runSubprocess$
#   (stdout captured) - on a reported Windows machine the plain call returned
#   before any backend file existed while the capturing call completed. The
#   backend (1.8.2) reports failures as "status error"; when the result is
#   missing the Info window shows the backend's own file report next to the
#   paths Praat expected and the ccc_* files Praat can see.
# Version: 1.16.4 (2026) - Write-visibility probe
#   v1.16.4: when the backend leaves no result and no log, a probe checks
#   whether files written by this Python are visible to Praat (Microsoft Store
#   Python redirects writes under AppData to a private copy), and the strict
#   re-run captures the backend's console output into the Info window.
# Version: 1.16.3 (2026) - Start-up failure diagnosis
#   v1.16.3: if the Polyphonic Layers backend leaves neither a result nor a
#   log (Python never reached its first line), the identical command is run
#   once more WITHOUT nocheck, so Praat's own error dialog reports the exact
#   reason instead of a generic "no result" message.
# Version: 1.16.2 (2026) - Backend version check
#   v1.16.2: at start-up the script checks that the corpus_concat_codec.py it
#   found (plugin_AudioTools/py/ first) is 1.8.1 or later and stops with the
#   exact path to replace if not - an older backend fails silently. If Python
#   writes no log at all, the failure message names the Python and backend used.
# Version: 1.16.1 (2026) - Windows argument fix
#   v1.16.1: optional file arguments are sent as "-" instead of an empty
#   string. Praat's runSubprocess on Windows drops empty arguments, which
#   broke Polyphonic Layers whenever stem export was off ("the backend
#   produced no result"), and would have broken Match, Gesture rhyme and
#   Continuation tail whenever Import TextGrid was off. Needs backend 1.8.1.
# Version: 1.16.0 (2026) - Corpus Polyphonic Layers (mode 6)
#   v1.16.0 adds a sixth mode. The selected mono Sound is analysed over its
#   WHOLE duration and gives rise to 1-3 additional voices built from the
#   existing corpus along the cached transition graph (backend v1.8.0,
#   subcommand polyphonic-layers), related to the phrase as Parallel,
#   Complementary or Independent. Every voice is exactly as long as the
#   source (identical sample count, rate and start time). Three short dialogs:
#   behaviour, space + level, output. The stereo mix is assembled HERE from
#   the untouched in-memory source plus the imported voices (equal-power
#   pan, source centred), with one common normalisation gain on the mix only;
#   the separate voice objects keep their pre-mix level. Optional DAW stems
#   are written by the backend as 32-bit float from a lossless 32-bit PCM
#   export of the source (Praat itself has no float WAV writer), never
#   overwriting an existing set. Modes 1-5 are unchanged. Needs backend 1.8.0.
# Version: 1.15.3 (2026) - Source-anchored loudness normalisation
#   v1.15.3: "Loudness match tail to source, then peak" no longer rescales
#   the whole result by its loudest sample (a peakier tail pushed the source
#   down 6.9 dB in a listening test). The backend (v1.7.4) now matches the
#   tail's loudness and caps its peaks at the source's own peak; here ONE
#   common gain brings the source peak to -1 dBFS and is applied to both
#   parts, so their balance is exactly the matched one. Needs backend v1.7.4.
# Version: 1.15.2 (2026) - Continuation normalisation
#   v1.15.2 adds "Normalize" to the second continuation dialog:
#     Off                     - source copied bit-exactly (v1.15.1 behaviour)
#     Peak, separately        - source part and tail part each scaled to
#                               -1 dBFS BEFORE the crossfade, so the join
#                               blends two equally normalised parts
#     Loudness match + peak (default) - tail scaled so its sustained body (envelope
#                               >= 0.5) has the RMS of the phrase's active
#                               sound, then the whole result peaks at -1 dBFS
#   Peak-matching equalises PEAKS, not loudness: measured on a flute phrase it
#   left the tail ~5 dB louder than the source (lower crest factor), so the
#   loudness option is the default.
#   A final guard rescales the whole result to -1 dBFS only if the crossfade
#   sum ever exceeds 0.999. Lengths stay sample-exact. Needs backend v1.7.3.
# Version: 1.15.1 (2026) - Continuation tail level
#   v1.15.1 adds "Tail level" to the second continuation dialog: Phrase level
#   (default) settles the continuation at the phrase's median active level,
#   rising from the join over 0.3 s, with the corpus grains' level swings
#   smoothed; Ending level keeps the v1.15.0 behaviour (match the faded end).
#   Requires corpus_concat_codec.py v1.7.2.
# Version: 1.15.0 (2026) - Corpus Continuation Tail (mode 5)
#   v1.15.0 adds a fifth mode that extends the selected (mono) Sound with a
#   continuation built from the existing analysed corpus. The Python backend
#   (corpus_concat_codec.py v1.7, subcommand continuation-tail) analyses the
#   phrase's ending, plans a grain sequence over a cached corpus TRANSITION
#   GRAPH (genuine chronological links + boundary-matched jumps), renders it,
#   applies the chosen envelope, and returns ONLY the tail buffer (crossfade
#   region + new material) as 32-bit float at the Sound's own sampling rate,
#   plus a small result file. The JOIN happens here, in memory, on the
#   untouched selected Sound: Extract part (sample-exact) of the source up to
#   the crossfade, a Formula crossfade over exactly xfade_samples, and the rest
#   of the tail, concatenated. Outside the crossfade the source samples are
#   copied bit-exactly; the output has exactly join_end + tail samples (both
#   integers computed with the same floor(x+0.5) rounding on both sides and
#   cross-checked here). Trailing silence is trimmed only when it is clearly
#   silent (option); the original Sound object is never modified.
#   The transition graph is a separate versioned sidecar next to the internal
#   corpus (current_corpus_graph.json/.npz), built once on first use and
#   rebuilt automatically when the corpus changes. Mode 5 never builds or
#   replaces the corpus. Modes 1-4 are unchanged.
# Version: 1.14.0 (2026) - Audible preview in the Draw Demo window
#   v1.14.0 adds Preview (P button / P key). It writes the current gesture
#   and runs exactly the same backend draw call as Render (same grain rate,
#   crossfade, repeat penalty, stretch setting) into a scratch WAV, plays it,
#   deletes it, and returns to editing - so what you hear IS the render. No
#   contour copy is saved for a preview; only Render saves one. The Demo
#   window shows "Previewing" while the backend runs and "Playing" while the
#   sound plays; Praat is busy for both (a preview of a long gesture plays in
#   full). Playback is non-fatal: if the audio device refuses, the message
#   line says so and editing continues. On Praat 7.0 each preview writes
#   files, so it is subject to the same trust prompt as Render.
# Version: 1.13.0 (2026) - Built-in gesture generators in the Draw Demo window
#   v1.13.0 adds a second button row to the Demo window. Every generator is an
#   ordinary edit: it rewrites the point list, stays click-editable, and U
#   undoes it. Sine / Triangle / Angular fill the whole duration with the
#   current "cycles" count (- / + buttons, 1..32) between the current
#   drawing's min and max (full 0..1 when the drawing is flat or spans less
#   than 0.02), so two end points set the floor and ceiling of the wave.
#   Sine starts and ends on the low value; Triangle alternates low/high
#   corners; Angular is a zigzag with random corner heights (low corners in
#   the bottom 45%, high corners in the top 45% of the range) and jittered
#   corner times - press it again for a new variant. "Faster x2" compresses
#   the CURRENT drawing into half the duration and plays it twice; "Slower
#   /2" keeps its first half and stretches it over the full duration, so the
#   two are exact inverses (up to a 0.01% step inserted where a repeat joins
#   two different values, because the contour holds one value per time).
#   The point list is capped at 400 points; Faster refuses beyond that.
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

form Corpus Concatenative Synthesis (codec) v1.16.6
    comment ── Mode ──
    optionmenu Mode: 1
        option Match (synthesise from corpus)
        option Build / replace corpus
        option Draw (brightness contour -> corpus)
        option Gesture rhyme (hashed bigram kinetics)
        option Corpus continuation tail
        option Corpus polyphonic layers
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

# Corpus continuation tail (mode 5) - defaults set BEFORE the pause dialogs
# so every field variable exists even where a pause auto-continues.
tail_duration_mode = 1
tail_percent = 50
tail_seconds = 4.0
continuation_mode = 1
continuation_strength = 75
trim_trailing_silence = 1
dynamic_envelope = 1
tail_level = 1
normalize = 3
join_crossfade_ms = 50
output_mode = 1
keep_metadata = 0

# Corpus polyphonic layers (mode 6) - own field names (no clash with mode 5)
number_of_new_voices = 2
polyphonic_relationship = 1
relationship_strength = 75
inter_voice_diversity = 50
refine_voices_jointly = 1
stereo_panning = 1
voice_1_pan = -60
voice_2_pan = 60
voice_3_pan = 0
voice_level_mode = 1
generated_voice_level_dB = -6
normalize_stereo_mix = 1
mix_peak_target_dB = -1
layer_output = 3
export_aligned_WAV_stems = 0
export_folder$ = ""
keep_layer_metadata = 0

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

elsif mode = 5
    # ---- CORPUS CONTINUATION TAIL ----
    beginPause: "Continuation tail (1/2): length + behaviour"
        optionMenu: "Tail duration mode", tail_duration_mode
            option: "Percentage of source duration"
            option: "Fixed duration in seconds"
        positive: "Tail percent", string$(tail_percent)
        positive: "Tail seconds", string$(tail_seconds)
        optionMenu: "Continuation mode", continuation_mode
            option: "Tight (follow the corpus, keep identity)"
            option: "Textural (statistical, drifting)"
        real: "Continuation strength", string$(continuation_strength)
        comment: "Strength 0-100: attachment to the source ending (100 = strongest)."
        integer: "Random seed", string$(random_seed)
    endPause: "Continue", 1

    beginPause: "Continuation tail (2/2): envelope + join + output"
        optionMenu: "Dynamic envelope", dynamic_envelope
            option: "Natural exponential decay"
            option: "Sustain and drop"
            option: "Tremolo decay"
            option: "Swell and fade"
        optionMenu: "Tail level", tail_level
            option: "Phrase level (rises from the join)"
            option: "Ending level (stays at the faded end)"
        positive: "Join crossfade ms", string$(join_crossfade_ms)
        boolean: "Trim trailing silence", trim_trailing_silence
        comment: "Trim cuts only CLEARLY silent material after the last sound."
        optionMenu: "Output mode", output_mode
            option: "Original + tail"
            option: "Tail only"
        optionMenu: "Normalize", normalize
            option: "Off (source untouched)"
            option: "Peak, source and tail separately"
            option: "Loudness match tail to source, then peak"
        boolean: "Keep metadata", keep_metadata
    endPause: "Continue", 1

elsif mode = 6
    # ---- CORPUS POLYPHONIC LAYERS ----
    beginPause: "Polyphonic layers (1/3): behaviour"
        natural: "Number of new voices", string$(number_of_new_voices)
        optionMenu: "Polyphonic relationship", polyphonic_relationship
            option: "Parallel (follow the phrase's behaviour)"
            option: "Complementary (answer and contrast)"
            option: "Independent (own trajectories)"
        real: "Relationship strength", string$(relationship_strength)
        real: "Inter voice diversity", string$(inter_voice_diversity)
        integer: "Random seed", string$(random_seed)
        boolean: "Refine voices jointly", refine_voices_jointly
    endPause: "Continue", 1

    beginPause: "Polyphonic layers (2/3): space + level"
        optionMenu: "Stereo panning", stereo_panning
            option: "Automatic stereo spread"
            option: "Manual pan positions"
        real: "Voice 1 pan", string$(voice_1_pan)
        real: "Voice 2 pan", string$(voice_2_pan)
        real: "Voice 3 pan", string$(voice_3_pan)
        optionMenu: "Voice level mode", voice_level_mode
            option: "Match source active RMS"
            option: "Keep corpus level"
        real: "Generated voice level dB", string$(generated_voice_level_dB)
        boolean: "Normalize stereo mix", normalize_stereo_mix
        real: "Mix peak target dB", string$(mix_peak_target_dB)
    endPause: "Continue", 1

    beginPause: "Polyphonic layers (3/3): output"
        optionMenu: "Layer output", layer_output
            option: "Stereo mix"
            option: "Separate voices"
            option: "Both"
        boolean: "Export aligned WAV stems", export_aligned_WAV_stems
        sentence: "Export folder", export_folder$
        comment: "Leave the folder empty to choose it in a dialog."
        boolean: "Keep layer metadata", keep_layer_metadata
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
# v1.16.2: the front-end and the backend must be installed TOGETHER. An older
# backend left in plugin_AudioTools/py/ fails silently (it rejects the new
# command line before it can write a log), so check its version up front.
backendText$ = readFile$(backend_script$)
if index(backendText$, "_OPTIONAL_PATH_ARGS") = 0 or index(backendText$, "def _expand_arg_files(") = 0
    exitScript: "The Python backend this script found is an OLDER version:" + newline$
        ... + backend_script$ + newline$ + newline$
        ... + "Corpus_Concatenative_Codec.praat 1.16.6 needs corpus_concat_codec.py 1.8.3 or later." + newline$
        ... + "Replace THAT file with the new corpus_concat_codec.py and run again."
endif
backendText$ = ""

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
# Scratch WAV for the Demo-window Preview button (deleted after each preview).
tempPreview$ = tempDir$ + "ccc_preview_" + runTag$ + ".wav"
tempLog$    = tempDir$ + "ccc_pylog_" + runTag$ + ".txt"
probeMarker$ = tempDir$ + "ccc_probe_" + runTag$ + ".txt"
tempBuildMarker$ = tempDir$ + "ccc_build_ok_" + runTag$ + ".txt"
# Continuation Tail: key/value join description written by the backend.
tempResult$ = tempDir$ + "ccc_result_" + runTag$ + ".txt"
# Polyphonic Layers: the backend writes <tag>_voice_<v>.wav into tempDir$.
polyTag$ = "ccc_poly_" + runTag$
tempArgs$ = tempDir$ + "ccc_args_" + runTag$ + ".txt"
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
    if fileReadable(tempPreview$)
        deleteFile: tempPreview$
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
    if fileReadable(tempResult$)
        deleteFile: tempResult$
    endif
    if fileReadable(tempArgs$)
        deleteFile: tempArgs$
    endif
    for cleanV from 1 to 3
        cleanVoice$ = tempDir$ + polyTag$ + "_voice_" + string$(cleanV) + ".wav"
        if fileReadable(cleanVoice$)
            deleteFile: cleanVoice$
        endif
        if fileReadable(cleanVoice$ + ".part.wav")
            deleteFile: cleanVoice$ + ".part.wav"
        endif
    endfor
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
    ddY1 = 30
    ddY2 = 86
    ddSX1 = 86
    ddSX2 = 96
    ddHitRadius = 2.0
    ddCycles = 2
    ddMaxPts = 400
    # Button table: ddBAct[k] is the action code handled by ddAction.
    # Row B (y 8.5-13.5): Undo 1, Reset 2, Stretch 3, Cancel 4, Render 5
    # Row A (y 15.5-20.5): Sine 7, Triangle 8, Angular 9, cycles- 10,
    #                      cycles+ 11, Faster 12, Slower 13
    ddNBtn = 0
    @ddAddBtn: 1, 3, 16, 8.5, 13.5
    @ddAddBtn: 2, 18, 31, 8.5, 13.5
    @ddAddBtn: 3, 33, 52, 8.5, 13.5
    @ddAddBtn: 14, 53.5, 62.5, 8.5, 13.5
    @ddAddBtn: 4, 64, 79, 8.5, 13.5
    @ddAddBtn: 5, 81, 97, 8.5, 13.5
    @ddAddBtn: 7, 3, 14, 15.5, 20.5
    @ddAddBtn: 8, 15.5, 26.5, 15.5, 20.5
    @ddAddBtn: 9, 28, 39, 15.5, 20.5
    @ddAddBtn: 10, 43, 47, 15.5, 20.5
    @ddAddBtn: 11, 57, 61, 15.5, 20.5
    @ddAddBtn: 12, 64, 79, 15.5, 20.5
    @ddAddBtn: 13, 81, 97, 15.5, 20.5
    @ddResetPoints
endproc

procedure ddAddBtn: .act, .x1, .x2, .y1, .y2
    ddNBtn = ddNBtn + 1
    ddBAct[ddNBtn] = .act
    ddBx1[ddNBtn] = .x1
    ddBx2[ddNBtn] = .x2
    ddBy1[ddNBtn] = .y1
    ddBy2[ddNBtn] = .y2
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
        ... + "  ·  " + string$(ddN) + " points  ·  cycles " + string$(ddCycles)
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
    # smaller dots once a generator has filled the list, so the curve stays legible
    .dot = if ddN > 60 then 0.6 else 1.2 fi
    for .i to ddN
        if .i = ddSel
            demo Paint circle (mm): {0.85, 0.15, 0.15}, ddT[.i], ddV[.i], 3.2
            demo Paint circle (mm): {1.00, 1.00, 1.00}, ddT[.i], ddV[.i], 2.0
        endif
        demo Paint circle (mm): {0.10, 0.10, 0.10}, ddT[.i], ddV[.i], .dot
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
    @ddVP: 0, 100, 1.5, 22, 0, 100, 1.5, 22
    demo Paint rectangle: {0.94, 0.94, 0.94}, 0, 100, 1.5, 22
    for .k to ddNBtn
        .a = ddBAct[.k]
        .col# = {1.00, 1.00, 1.00}
        if .a = 1
            .lab$ = "Undo (U)"
        elsif .a = 2
            .lab$ = "Reset (R)"
        elsif .a = 3
            .lab$ = "Stretch (S): " + .stretchTxt$
            .col# = if ddStretch then {0.82, 0.88, 0.97} else {1.00, 1.00, 1.00} fi
        elsif .a = 4
            .lab$ = "Cancel (Esc)"
            .col# = {0.98, 0.88, 0.88}
        elsif .a = 5
            .lab$ = "##Render (Enter)##"
            .col# = {0.86, 0.94, 0.86}
        elsif .a = 7
            .lab$ = "Sine"
            .col# = {0.96, 0.95, 0.90}
        elsif .a = 8
            .lab$ = "Triangle"
            .col# = {0.96, 0.95, 0.90}
        elsif .a = 9
            .lab$ = "Angular"
            .col# = {0.96, 0.95, 0.90}
        elsif .a = 10
            .lab$ = "−"
        elsif .a = 11
            .lab$ = "+"
        elsif .a = 14
            .lab$ = "Preview (P)"
            .col# = {0.99, 0.93, 0.85}
        elsif .a = 12
            .lab$ = "Same wave faster ×2"
            .col# = {0.96, 0.95, 0.90}
        else
            .lab$ = "Same wave slower ÷2"
            .col# = {0.96, 0.95, 0.90}
        endif
        demo Paint rectangle: .col#, ddBx1[.k], ddBx2[.k], ddBy1[.k], ddBy2[.k]
        demo Colour: "Black"
        demo Draw rectangle: ddBx1[.k], ddBx2[.k], ddBy1[.k], ddBy2[.k]
        demo Text: (ddBx1[.k] + ddBx2[.k]) / 2, "centre", (ddBy1[.k] + ddBy2[.k]) / 2, "half", .lab$
    endfor
    demo Text: 52, "centre", 18, "half", "cycles " + string$(ddCycles)
    demo Font size: 10
    @ddVP: 0, 100, 1.5, 22, 0, 100, 1.5, 22
    demo Text: 50, "centre", 6.2, "half",
        ... "click empty space: add point  ·  click a point, then click elsewhere: move it  ·  shift-click a point: delete  ·  end points move vertically only"
    demo Text: 50, "centre", 3.6, "half",
        ... "generators span your drawing's lowest..highest value (full range if flat)  ·  faster/slower transform the current drawing  ·  U undoes any of them"
    @ddVP: 0, 100, 1.5, 22, 0, 100, 1.5, 22
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
            for .k to ddNBtn
                if .px >= ddBx1[.k] and .px <= ddBx2[.k] and .py >= ddBy1[.k] and .py <= ddBy2[.k]
                    .hit = ddBAct[.k]
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
        elsif .k$ = "p" or .k$ = "P"
            @ddAction: 14
        elsif .k$ = "+" or .k$ = "="
            @ddAction: 11
        elsif .k$ = "-"
            @ddAction: 10
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
    elsif .a >= 7 and .a <= 9
        @ddPushUndo
        @ddRange
        if .a = 7
            @ddGenSine
        elsif .a = 8
            @ddGenTriangle
        else
            @ddGenAngular
        endif
        @ddCommitNew
    elsif .a = 10
        ddCycles = max(1, ddCycles - 1)
    elsif .a = 11
        ddCycles = min(32, ddCycles + 1)
    elsif .a = 12
        if 2 * ddN > ddMaxPts
            ddMsg$ = "too many points for Faster (max " + string$(ddMaxPts) + ")"
        else
            @ddPushUndo
            @ddFaster
            @ddCommitNew
        endif
    elsif .a = 13
        @ddPushUndo
        @ddSlower
        @ddCommitNew
    elsif .a = 14
        @ddPreview
    endif
endproc

procedure ddStatusFrame: .text$
    # overwrite the control panel with a one-line status; used while Praat
    # is busy (backend running / sound playing) so the window is not mute
    demo Font size: 12
    @ddVP: 0, 100, 1.5, 22, 0, 100, 1.5, 22
    demo Paint rectangle: {0.94, 0.94, 0.94}, 0, 100, 1.5, 22
    demo Colour: "Black"
    demo Text: 50, "centre", 11.5, "half", .text$
    @ddVP: 0, 100, 1.5, 22, 0, 100, 1.5, 22
    demo Draw inner box
    demoShow()
endproc

procedure ddPreview
    # Same backend call and parameters as Render, minus the persistent
    # contour copy / metadata / TextGrid, so the preview is the render.
    @ddStatusFrame: "##Previewing…## rendering the current gesture (Praat is busy)"
    @ddWriteContour: tempDrawn$
    if fileReadable(tempPreview$)
        deleteFile: tempPreview$
    endif
    .t0 = stopwatch
    nocheck runSubprocess: python_exe$, backend_script$, "draw",
        ... "--contour", tempDrawn$,
        ... "--output", tempPreview$,
        ... "--index", corpusIndexPath$,
        ... "--duration", "0",
        ... "--grain-rate-ms", string$(grain_rate_ms),
        ... "--xfade-ms", string$(crossfade_ms),
        ... "--repeat-penalty", string$(repeat_penalty),
        ... "--log", tempLog$
    .tRender = stopwatch
    if fileReadable(tempPreview$)
        Read from file: tempPreview$
        .snd = selected("Sound")
        .dur = Get total duration
        @ddStatusFrame: "##Playing preview…## " + fixed$(.dur, 1) + " s (rendered in " + fixed$(.tRender, 1) + " s)"
        selectObject: .snd
        nocheck Play
        removeObject: .snd
        deleteFile: tempPreview$
        ddMsg$ = "previewed " + fixed$(.dur, 1) + " s (render " + fixed$(.tRender, 1) + " s)"
    else
        @showPyLog
        ddMsg$ = "preview failed - the Python error is in the Info window"
    endif
endproc

# ---- generators / transforms (v1.13.0) ----
# All of them build a new list in ddNT[]/ddNV[] (ddNN points, sorted, first
# point at t = 0 and last at t = ddDur) and ddCommitNew swaps it in.

procedure ddCommitNew
    ddN = ddNN
    for .i to ddNN
        ddT[.i] = ddNT[.i]
        ddV[.i] = ddNV[.i]
    endfor
    ddSel = 0
endproc

procedure ddRange
    # generator range = the current drawing's min..max (full 0..1 if flat)
    ddLo = ddV[1]
    ddHi = ddV[1]
    for .i to ddN
        ddLo = min(ddLo, ddV[.i])
        ddHi = max(ddHi, ddV[.i])
    endfor
    if ddHi - ddLo < 0.02
        ddLo = 0
        ddHi = 1
    endif
endproc

procedure ddGenSine
    # starts and ends on the low value; point density drops for many cycles
    # so the list stays under ddMaxPts
    .per = max(8, min(24, floor((ddMaxPts - 1) / ddCycles)))
    .n = ddCycles * .per
    ddNN = 0
    for .i from 0 to .n
        ddNN = ddNN + 1
        ddNT[ddNN] = .i / .n * ddDur
        ddNV[ddNN] = ddLo + (ddHi - ddLo) * (1 - cos(2 * pi * ddCycles * .i / .n)) / 2
    endfor
endproc

procedure ddGenTriangle
    .n = 2 * ddCycles
    ddNN = 0
    for .i from 0 to .n
        ddNN = ddNN + 1
        ddNT[ddNN] = .i / .n * ddDur
        ddNV[ddNN] = if .i mod 2 = 0 then ddLo else ddHi fi
    endfor
endproc

procedure ddGenAngular
    # zigzag: alternating low/high corners at random heights, corner times
    # jittered by up to +-30% of the corner spacing
    .n = 2 * ddCycles
    .sp = ddDur / .n
    .span = ddHi - ddLo
    ddNN = 0
    for .i from 0 to .n
        ddNN = ddNN + 1
        if .i = 0
            ddNT[ddNN] = 0
        elsif .i = .n
            ddNT[ddNN] = ddDur
        else
            ddNT[ddNN] = .i * .sp + randomUniform(-0.3, 0.3) * .sp
        endif
        if .i mod 2 = 0
            ddNV[ddNN] = ddLo + randomUniform(0, 0.45) * .span
        else
            ddNV[ddNN] = ddLo + randomUniform(0.55, 1) * .span
        endif
    endfor
endproc

procedure ddFaster
    # the current drawing compressed into [0, dur/2] and played twice
    .half = ddDur / 2
    .eps = 1e-4 * ddDur
    ddNN = 0
    for .i to ddN
        .t = ddT[.i] / 2
        .keep = 1
        if .i = ddN
            # join: the repeat starts at dur/2 with the first value; if the
            # values differ, end the first copy just before the join
            if abs(ddV[ddN] - ddV[1]) < 1e-9
                .keep = 0
            else
                .t = .half - .eps
                if .t <= ddNT[ddNN]
                    .keep = 0
                endif
            endif
        endif
        if .keep
            ddNN = ddNN + 1
            ddNT[ddNN] = .t
            ddNV[ddNN] = ddV[.i]
        endif
    endfor
    for .i to ddN
        ddNN = ddNN + 1
        ddNT[ddNN] = (ddT[.i] + ddDur) / 2
        ddNV[ddNN] = ddV[.i]
    endfor
endproc

procedure ddSlower
    # the first half of the current drawing stretched over the full duration
    .half = ddDur / 2
    ddNN = 0
    for .i to ddN
        if ddT[.i] < .half * (1 - 1e-9)
            ddNN = ddNN + 1
            ddNT[ddNN] = 2 * ddT[.i]
            ddNV[ddNN] = ddV[.i]
        endif
    endfor
    # A kept point within 0.1% of the half is the end of a Faster copy (the
    # step Faster inserts before a join) - it becomes the end point, so its
    # value survives; otherwise the end value is interpolated at the half.
    if ddNT[ddNN] > ddDur * (1 - 1e-3)
        ddNT[ddNN] = ddDur
    else
        @ddInterpRaw: .half
        ddNN = ddNN + 1
        ddNT[ddNN] = ddDur
        ddNV[ddNN] = ddInterpRawV
    endif
endproc

procedure ddInterpRaw: .t
    # like ddInterp but on the DRAWN values ddV[] (not the stretched ddE[])
    ddInterpRawV = ddV[ddN]
    .done = 0
    for .i to ddN - 1
        if .done = 0
            .i1 = .i + 1
            if .t <= ddT[.i1]
                .span = ddT[.i1] - ddT[.i]
                if .span > 0
                    ddInterpRawV = ddV[.i] + (ddV[.i1] - ddV[.i]) * (.t - ddT[.i]) / .span
                else
                    ddInterpRawV = ddV[.i1]
                endif
                .done = 1
            endif
        endif
    endfor
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
    @ddVP: 0, 100, 1.5, 22, 0, 100, 1.5, 22
    demo Paint rectangle: {0.94, 0.94, 0.94}, 0, 100, 1.5, 22
    demo Colour: "Black"
    demo Text: 50, "centre", 11.5, "half",
        ... "##Rendering…## Praat is busy until the synthesis finishes; progress and results go to the Info window."
    @ddVP: 0, 100, 1.5, 22, 0, 100, 1.5, 22
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

    textgridArg$ = "-"
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
# CORPUS CONTINUATION TAIL MODE (v1.15.0)
# The backend returns only the tail buffer; the join is done HERE on the
# untouched selected Sound, so the original samples outside the crossfade
# are copied exactly and every length is an exact sample count.
# ============================================================
if mode = 5
    if numberOfSelected("Sound") <> 1
        exitScript: "Corpus Continuation Tail: please select exactly one Sound (the phrase to extend)."
    endif
    source = selected("Sound")
    sourceName$ = selected$("Sound")
    selectObject: source
    srcChannels = Get number of channels
    if srcChannels <> 1
        exitScript: "Corpus Continuation Tail works on MONO Sounds only." + newline$
            ... + "This Sound has " + string$(srcChannels) + " channels. Convert it to mono"
            ... + " (or extract one channel) first - nothing was changed."
    endif
    srcSR = Get sampling frequency
    srcN = Get number of samples
    srcDur = Get total duration
    srcDt = Get sampling period
    srcX1 = Get time from sample number: 1
    srcLeft = srcX1 - 0.5 * srcDt

    if not fileReadable(corpusIndexPath$ + ".json")
        exitScript: "No analysed corpus is available yet." + newline$
            ... + "Run Build / replace corpus first. Continuation Tail uses the existing" + newline$
            ... + "corpus and never builds or replaces it."
    endif

    # ---- validate the dialog values before calling Python ----
    if tail_duration_mode = 1
        if tail_percent <= 0 or tail_percent > 1000
            exitScript: "Tail percent must be between 0 and 1000 (got " + string$(tail_percent) + ")."
        endif
        tailEstimate = srcDur * tail_percent / 100
        durArg$ = "percent"
    else
        if tail_seconds <= 0
            exitScript: "Tail seconds must be positive."
        endif
        tailEstimate = tail_seconds
        durArg$ = "seconds"
    endif
    if tailEstimate > 300
        exitScript: "The requested tail (" + fixed$(tailEstimate, 1) + " s) exceeds the 300 s limit."
    endif
    if continuation_strength < 0 or continuation_strength > 100
        appendInfoLine: "Note: Continuation strength clamped to 0..100."
        continuation_strength = max(0, min(100, continuation_strength))
    endif
    if join_crossfade_ms > 2000
        appendInfoLine: "Note: Join crossfade limited to 2000 ms."
        join_crossfade_ms = 2000
    endif
    if random_seed < 0
        random_seed = 0
    endif
    contArg$ = if continuation_mode = 1 then "tight" else "textural" fi
    if dynamic_envelope = 1
        envArg$ = "exp-decay"
    elsif dynamic_envelope = 2
        envArg$ = "sustain-drop"
    elsif dynamic_envelope = 3
        envArg$ = "tremolo-decay"
    else
        envArg$ = "swell-fade"
    endif
    outArg$ = if output_mode = 1 then "original+tail" else "tail-only" fi
    levelArg$ = if tail_level = 1 then "phrase" else "ending" fi
    if normalize = 1
        normArg$ = "off"
    elsif normalize = 2
        normArg$ = "peak"
    else
        normArg$ = "loudness"
    endif

    # Metadata is scratch unless the user asked to keep it.
    metaPath$ = tempMeta$
    if keep_metadata
        metaDir$ = corpusDir$ + "continuation_meta/"
        createDirectory: metaDir$
        safeSourceName$ = replace_regex$(sourceName$, "[\\/:*?""<>|]", "_", 0)
        metaPath$ = metaDir$ + safeSourceName$ + "_" + runTag$ + ".json"
    endif
    textgridArg$ = "-"
    if import_textgrid
        textgridArg$ = tempTG$
    endif

    selectObject: source
    Save as WAV file: tempInput$
    if not fileReadable(tempInput$)
        @cleanUpTempFiles
        exitScript: "Could not export the selected Sound to a temp WAV."
    endif

    appendInfoLine: "=== Corpus Continuation Tail ==="
    appendInfoLine: "Source: ", sourceName$, "  (", fixed$(srcDur, 3), " s, ", string$(srcSR), " Hz)"
    appendInfoLine: "Corpus: ", corpusIndexPath$
    appendInfoLine: "Mode: ", contArg$, "   strength ", string$(continuation_strength),
        ... "   envelope ", envArg$, "   level ", levelArg$, "   crossfade ", string$(join_crossfade_ms), " ms"
    if not fileReadable(corpusIndexPath$ + "_graph.json")
        appendInfoLine: "No transition graph yet - it is built once now from the corpus grains"
        appendInfoLine: "(one codec pass per grain; this can take minutes for a large corpus)."
    endif
    appendInfoLine: "Calling Python backend..."

    nocheck runSubprocess: python_exe$, backend_script$,
        ... "continuation-tail",
        ... "--input", tempInput$,
        ... "--output", tempOutput$,
        ... "--result", tempResult$,
        ... "--index", corpusIndexPath$,
        ... "--duration-mode", durArg$,
        ... "--tail-percent", string$(tail_percent),
        ... "--tail-seconds", string$(tail_seconds),
        ... "--continuation-mode", contArg$,
        ... "--continuation-strength", string$(continuation_strength),
        ... "--envelope", envArg$,
        ... "--tail-level", levelArg$,
        ... "--normalize", normArg$,
        ... "--xfade-ms", string$(join_crossfade_ms),
        ... "--output-mode", outArg$,
        ... "--trim-silence", string$(trim_trailing_silence),
        ... "--seed", string$(random_seed),
        ... "--metadata", metaPath$,
        ... "--textgrid", textgridArg$,
        ... "--log", tempLog$

    if not fileReadable(tempOutput$) or not fileReadable(tempResult$)
        @showPyLog
        @cleanUpTempFiles
        exitScript: "Continuation Tail failed - the backend produced no tail." + newline$
            ... + "The Python error is shown in the Info window above." + newline$
            ... + "Common causes: obsolete corpus index (rebuild it), missing grain files," + newline$
            ... + "a silent or very short source, or a codec package that is not installed."
    endif

    # ---- read the join description ----
    res$ = readFile$(tempResult$)
    resSR = extractNumber(res$, "sample_rate ")
    resSrcN = extractNumber(res$, "source_samples ")
    joinEnd = extractNumber(res$, "join_end_sample ")
    xfN = extractNumber(res$, "xfade_samples ")
    nTail = extractNumber(res$, "new_tail_samples ")
    bufN = extractNumber(res$, "buffer_samples ")
    joinRho = extractNumber(res$, "join_rho ")
    predPeak = extractNumber(res$, "predicted_peak ")
    trimmedN = extractNumber(res$, "trimmed_samples ")
    srcActRms = extractNumber(res$, "source_active_rms ")
    tailBodyRms = extractNumber(res$, "tail_body_rms ")
    resErr$ = ""
    if resSR = undefined or joinEnd = undefined or xfN = undefined or nTail = undefined or bufN = undefined or joinRho = undefined
        resErr$ = "the result file is incomplete"
    elsif resSR <> srcSR
        resErr$ = "sampling rate mismatch (" + string$(resSR) + " vs " + string$(srcSR) + " Hz)"
    elsif resSrcN <> srcN
        resErr$ = "source length mismatch (" + string$(resSrcN) + " vs " + string$(srcN) + " samples)"
    elsif joinEnd < 2 or joinEnd > srcN
        resErr$ = "join point out of range"
    elsif xfN < 1 or xfN >= joinEnd or xfN > nTail
        resErr$ = "crossfade length out of range"
    elsif bufN <> xfN + nTail
        resErr$ = "tail buffer length does not equal crossfade + new samples"
    endif
    if resErr$ = ""
        # independent recomputation of the new-material length (same rounding
        # as the backend: floor(x + 0.5), which is Praat's round())
        if tail_duration_mode = 1
            expectTail = round(joinEnd * tail_percent / 100)
        else
            expectTail = round(tail_seconds * srcSR)
        endif
        if expectTail <> nTail
            resErr$ = "tail length " + string$(nTail) + " differs from the expected " + string$(expectTail)
        endif
    endif
    if resErr$ <> ""
        @showPyLog
        @cleanUpTempFiles
        exitScript: "Continuation Tail: inconsistent backend result - " + resErr$ + "." + newline$
            ... + "Nothing was joined; the selected Sound is unchanged."
    endif

    Read from file: tempOutput$
    tailRaw = selected("Sound")
    tailN = Get number of samples
    tailSR = Get sampling frequency
    tailCh = Get number of channels
    if tailN <> bufN or tailSR <> srcSR or tailCh <> 1
        removeObject: tailRaw
        @cleanUpTempFiles
        exitScript: "Continuation Tail: the tail file has " + string$(tailN) + " samples at "
            ... + string$(tailSR) + " Hz (" + string$(tailCh) + " ch); expected "
            ... + string$(bufN) + " at " + string$(srcSR) + " Hz mono."
    endif
    tailX1 = Get time from sample number: 1
    tailLeft = tailX1 - 0.5 * srcDt

    # ---- optional normalisation gains (applied to COPIES before the join) ----
    normTarget = 10 ^ (-1 / 20)
    gainSrc = 1
    gainTail = 1
    if normalize = 2
        selectObject: tailRaw
        tailPeak = Get absolute extremum: 0, 0, "None"
        selectObject: source
        srcPeak = Get absolute extremum: srcLeft, srcLeft + joinEnd * srcDt, "None"
        if srcPeak > 1e-9
            gainSrc = normTarget / srcPeak
        endif
        if tailPeak > 1e-9
            gainTail = normTarget / tailPeak
        endif
    elsif normalize = 3
        # the backend already matched the tail's loudness in SOURCE units and
        # kept its peaks at or below the source peak: one common gain for both
        selectObject: source
        srcPeak = Get absolute extremum: srcLeft, srcLeft + joinEnd * srcDt, "None"
        if srcPeak > 1e-9
            gainSrc = normTarget / srcPeak
        endif
        gainTail = gainSrc
    endif
    if gainTail <> 1
        selectObject: tailRaw
        Formula: "self * " + fixed$(gainTail, 12)
    endif

    # NOTE: Concatenate joins the selected Sounds in OBJECT-LIST order (i.e.
    # creation order), not in the order they were selected - so the head,
    # the overlap and the new material are extracted in exactly that order.
    if output_mode = 1
        # ---- head: source samples 1 .. joinEnd - xfN (bit-exact copy) ----
        headN = joinEnd - xfN
        selectObject: source
        srcHead = Extract part: srcLeft, srcLeft + headN * srcDt, "rectangular", 1, "no"
        gotHeadN = Get number of samples
        if gainSrc <> 1
            Formula: "self * " + fixed$(gainSrc, 12)
        endif
        # ---- overlap: source samples headN+1 .. joinEnd crossfaded with tail 1 .. xfN ----
        selectObject: source
        srcOverlap = Extract part: srcLeft + headN * srcDt, srcLeft + joinEnd * srcDt, "rectangular", 1, "no"
        gotOvN = Get number of samples
        if gainSrc <> 1
            Formula: "self * " + fixed$(gainSrc, 12)
        endif
        # ---- the new material: tail samples xfN+1 .. bufN (created LAST) ----
        selectObject: tailRaw
        tailRest = Extract part: tailLeft + xfN * srcDt, tailLeft + bufN * srcDt, "rectangular", 1, "no"
        restN = Get number of samples
        if gotHeadN <> headN or gotOvN <> xfN or restN <> nTail
            removeObject: tailRaw, tailRest, srcHead, srcOverlap
            @cleanUpTempFiles
            exitScript: "Continuation Tail: sample-exact extraction failed (head " + string$(gotHeadN)
                ... + "/" + string$(headN) + ", overlap " + string$(gotOvN) + "/" + string$(xfN)
                ... + ", tail " + string$(restN) + "/" + string$(nTail) + ")."
        endif
        # a = cos^2, b = sin^2 at sample centres; c corrects for the measured
        # correlation (1 for identical material, equal-power for unrelated) -
        # the same law the backend used to predict and limit the join peak.
        xf$ = string$(xfN)
        rho$ = fixed$(joinRho, 9)
        aa$ = "cos(pi/2*(col-0.5)/" + xf$ + ")^2"
        bb$ = "sin(pi/2*(col-0.5)/" + xf$ + ")^2"
        selectObject: srcOverlap
        Formula: "(self*" + aa$ + " + object[" + string$(tailRaw) + ", 1, col]*" + bb$ + ")"
            ... + " / sqrt((" + aa$ + ")^2 + (" + bb$ + ")^2 + 2*" + rho$ + "*" + aa$ + "*" + bb$ + ")"
        selectObject: srcHead, srcOverlap, tailRest
        result = Concatenate
        # belt and braces: the head must be the source's own first sample
        concatFirst = Get value at sample number: 1, 1
        selectObject: srcHead
        headFirst = Get value at sample number: 1, 1
        if concatFirst <> headFirst
            removeObject: result, srcHead, srcOverlap, tailRest, tailRaw
            @cleanUpTempFiles
            exitScript: "Continuation Tail: concatenation order check failed - nothing was joined."
        endif
        removeObject: srcHead, srcOverlap, tailRest
        expectN = joinEnd + nTail
        resultName$ = sourceName$ + "_continuation_tail"
    else
        selectObject: tailRaw
        tailRest = Extract part: tailLeft + xfN * srcDt, tailLeft + bufN * srcDt, "rectangular", 1, "no"
        restN = Get number of samples
        result = tailRest
        expectN = nTail
        resultName$ = sourceName$ + "_tail_only"
    endif
    removeObject: tailRaw
    selectObject: result
    Rename: resultName$
    normNote$ = ""
    if normalize > 1
        resPeak = Get absolute extremum: 0, 0, "None"
        if resPeak > 0.999
            if resPeak > 1e-9
                Formula: "self * " + fixed$(normTarget / resPeak, 12)
                normNote$ = " (whole result scaled to -1 dBFS)"
            endif
        endif
    endif
    resultN = Get number of samples
    if resultN <> expectN
        appendInfoLine: "WARNING: result has ", resultN, " samples, expected ", expectN, "."
    endif

    appendInfoLine: ""
    appendInfoLine: "Imported result: ", resultName$, "  (", string$(resultN), " samples = ",
        ... fixed$(resultN / srcSR, 4), " s)"
    if trimmedN > 0
        appendInfoLine: "Trailing silence trimmed before the join: ", fixed$(trimmedN / srcSR, 3),
            ... " s (effective source ", fixed$(joinEnd / srcSR, 3), " s)"
    endif
    if normalize = 2
        appendInfoLine: "Normalised separately: source ", fixed$(20 * log10(gainSrc), 2), " dB, tail ",
            ... fixed$(20 * log10(gainTail), 2), " dB", normNote$
    elsif normalize = 3
        appendInfoLine: "Loudness matched in the backend; common gain ", fixed$(20 * log10(gainSrc), 2),
            ... " dB (source peak -> -1 dBFS)", normNote$
    endif
    appendInfoLine: "New material: ", fixed$(nTail / srcSR, 3), " s   crossfade: ",
        ... fixed$(xfN / srcSR * 1000, 1), " ms   join correlation: ", fixed$(joinRho, 3)
    if predPeak <> undefined and predPeak > 1
        appendInfoLine: "Note: predicted peak ", fixed$(predPeak, 3), " (the source itself exceeds full scale)."
    endif

    if import_textgrid and fileReadable(tempTG$)
        Read from file: tempTG$
        Rename: resultName$ + "_grains"
        appendInfoLine: "Imported grain TextGrid (S start, C chronological, J graph jump, F fallback)."
    endif
    if keep_metadata and fileReadable(metaPath$)
        appendInfoLine: "Metadata kept: ", metaPath$
    endif

    @cleanUpTempFiles

    if play_result
        selectObject: result
        Play
    endif
    selectObject: result
    goto END
endif

# ============================================================
# CORPUS POLYPHONIC LAYERS MODE (v1.16.0)
# The backend returns 1-3 mono voices of exactly N samples; the stereo mix
# is assembled HERE from the untouched in-memory source.
# ============================================================
if mode = 6
    if numberOfSelected("Sound") <> 1
        exitScript: "Corpus Polyphonic Layers: please select exactly one Sound (the source phrase)."
    endif
    source = selected("Sound")
    sourceName$ = selected$("Sound")
    selectObject: source
    srcChannels = Get number of channels
    if srcChannels <> 1
        exitScript: "Corpus Polyphonic Layers works on MONO Sounds only." + newline$
            ... + "This Sound has " + string$(srcChannels) + " channels. Convert it to mono"
            ... + " (or extract one channel) first - nothing was changed."
    endif
    srcSR = Get sampling frequency
    srcN = Get number of samples
    srcDur = Get total duration
    srcXmin = Get start time
    srcPeakIn = Get absolute extremum: 0, 0, "None"

    if not fileReadable(corpusIndexPath$ + ".json")
        exitScript: "No analysed corpus is available yet." + newline$
            ... + "Run Build / replace corpus first. Polyphonic Layers uses the existing" + newline$
            ... + "corpus and never builds or replaces it."
    endif

    # ---- validate the dialog values before calling Python ----
    if number_of_new_voices < 1 or number_of_new_voices > 3
        exitScript: "Number of new voices must be 1, 2 or 3 (got " + string$(number_of_new_voices) + ")."
    endif
    nVoices = number_of_new_voices
    relationship_strength = max(0, min(100, relationship_strength))
    inter_voice_diversity = max(0, min(100, inter_voice_diversity))
    voice_1_pan = max(-100, min(100, voice_1_pan))
    voice_2_pan = max(-100, min(100, voice_2_pan))
    voice_3_pan = max(-100, min(100, voice_3_pan))
    if random_seed < 0
        random_seed = 0
    endif
    if generated_voice_level_dB < -40 or generated_voice_level_dB > 12
        exitScript: "Generated voice level must be between -40 and +12 dB."
    endif
    if mix_peak_target_dB < -40 or mix_peak_target_dB > 0
        exitScript: "Mix peak target must be between -40 and 0 dBFS."
    endif
    if polyphonic_relationship = 1
        relArg$ = "parallel"
    elsif polyphonic_relationship = 2
        relArg$ = "complementary"
    else
        relArg$ = "independent"
    endif
    panArg$ = if stereo_panning = 1 then "auto" else "manual" fi
    levelArg$ = if voice_level_mode = 1 then "match" else "corpus" fi
    if layer_output = 1
        layerArg$ = "mix"
    elsif layer_output = 2
        layerArg$ = "voices"
    else
        layerArg$ = "both"
    endif
    wantMix = layer_output = 1 or layer_output = 3
    wantVoices = layer_output = 2 or layer_output = 3

    # ---- optional DAW stem folder (asked for only when export is on) ----
    exportDir$ = ""
    if export_aligned_WAV_stems
        exportDir$ = export_folder$
        if exportDir$ = ""
            exportDir$ = chooseFolder$ ("Choose a folder for the aligned WAV stems")
        endif
        if exportDir$ = ""
            appendInfoLine: "Note: no export folder chosen - stems were not exported."
        endif
    endif

    # Metadata is scratch unless the user asked to keep it.
    metaPath$ = tempMeta$
    if keep_layer_metadata
        metaDir$ = corpusDir$ + "polyphonic_meta/"
        createDirectory: metaDir$
        safeSourceName$ = replace_regex$(sourceName$, "[\\/:*?""<>|]", "_", 0)
        metaPath$ = metaDir$ + safeSourceName$ + "_" + runTag$ + ".json"
    endif
    textgridArg$ = "-"
    if import_textgrid
        textgridArg$ = tempTG$
    endif
    # Windows drops EMPTY arguments from runSubprocess: "-" means "no file"
    exportArg$ = if exportDir$ = "" then "-" else exportDir$ fi

    # 32-bit PCM is lossless for 16/24-bit material (Praat has no float WAV
    # writer); the backend analyses it and, if asked, writes float32 stems.
    selectObject: source
    Save as 32-bit WAV file: tempInput$
    if not fileReadable(tempInput$)
        @cleanUpTempFiles
        exitScript: "Could not export the selected Sound to a temp WAV."
    endif

    appendInfoLine: "=== Corpus Polyphonic Layers ==="
    appendInfoLine: "Source: ", sourceName$, "  (", fixed$(srcDur, 3), " s, ", string$(srcN), " samples, ",
        ... string$(srcSR), " Hz)"
    appendInfoLine: "Relationship: ", relArg$, "   voices ", string$(nVoices), "   strength ",
        ... string$(relationship_strength), "   diversity ", string$(inter_voice_diversity),
        ... "   seed ", string$(random_seed)
    if not fileReadable(corpusIndexPath$ + "_graph.json")
        appendInfoLine: "No transition graph yet - it is built once now from the corpus grains."
    endif
    appendInfoLine: "Calling Python backend..."

    # ONE call that captures stdout (v1.16.5). A plain runSubprocess gives the
    # child no stdout under GUI Praat on Windows, and on a reported machine it
    # returned before any backend file existed, while this capturing form ran
    # the backend to completion. The backend now reports its own failures as
    # "status error" and exits 0, so this call does not abort the script.
    # Arguments go through a file (v1.16.6): on a reported Windows machine the
    # child received only the first 1024 characters of its command line,
    # silently cutting --result and --log. "@file" keeps the call short.
    polyArgs$ = ""
    polyArgs$ = polyArgs$ + "polyphonic-layers" + newline$
    polyArgs$ = polyArgs$ + "--input" + newline$
    polyArgs$ = polyArgs$ + tempInput$ + newline$
    polyArgs$ = polyArgs$ + "--index" + newline$
    polyArgs$ = polyArgs$ + corpusIndexPath$ + newline$
    polyArgs$ = polyArgs$ + "--output-dir" + newline$
    polyArgs$ = polyArgs$ + tempDir$ + newline$
    polyArgs$ = polyArgs$ + "--run-tag" + newline$
    polyArgs$ = polyArgs$ + polyTag$ + newline$
    polyArgs$ = polyArgs$ + "--voices" + newline$
    polyArgs$ = polyArgs$ + string$(nVoices) + newline$
    polyArgs$ = polyArgs$ + "--relationship" + newline$
    polyArgs$ = polyArgs$ + relArg$ + newline$
    polyArgs$ = polyArgs$ + "--relationship-strength" + newline$
    polyArgs$ = polyArgs$ + string$(relationship_strength) + newline$
    polyArgs$ = polyArgs$ + "--inter-voice-diversity" + newline$
    polyArgs$ = polyArgs$ + string$(inter_voice_diversity) + newline$
    polyArgs$ = polyArgs$ + "--seed" + newline$
    polyArgs$ = polyArgs$ + string$(random_seed) + newline$
    polyArgs$ = polyArgs$ + "--refine" + newline$
    polyArgs$ = polyArgs$ + string$(refine_voices_jointly) + newline$
    polyArgs$ = polyArgs$ + "--level-mode" + newline$
    polyArgs$ = polyArgs$ + levelArg$ + newline$
    polyArgs$ = polyArgs$ + "--voice-level-db" + newline$
    polyArgs$ = polyArgs$ + string$(generated_voice_level_dB) + newline$
    polyArgs$ = polyArgs$ + "--pan-mode" + newline$
    polyArgs$ = polyArgs$ + panArg$ + newline$
    polyArgs$ = polyArgs$ + "--pan-1" + newline$
    polyArgs$ = polyArgs$ + string$(voice_1_pan) + newline$
    polyArgs$ = polyArgs$ + "--pan-2" + newline$
    polyArgs$ = polyArgs$ + string$(voice_2_pan) + newline$
    polyArgs$ = polyArgs$ + "--pan-3" + newline$
    polyArgs$ = polyArgs$ + string$(voice_3_pan) + newline$
    polyArgs$ = polyArgs$ + "--normalize-mix" + newline$
    polyArgs$ = polyArgs$ + string$(normalize_stereo_mix) + newline$
    polyArgs$ = polyArgs$ + "--mix-target-db" + newline$
    polyArgs$ = polyArgs$ + string$(mix_peak_target_dB) + newline$
    polyArgs$ = polyArgs$ + "--output-mode" + newline$
    polyArgs$ = polyArgs$ + layerArg$ + newline$
    polyArgs$ = polyArgs$ + "--export-dir" + newline$
    polyArgs$ = polyArgs$ + exportArg$ + newline$
    polyArgs$ = polyArgs$ + "--export-name" + newline$
    polyArgs$ = polyArgs$ + sourceName$ + newline$
    polyArgs$ = polyArgs$ + "--export-mix" + newline$
    polyArgs$ = polyArgs$ + string$(wantMix) + newline$
    polyArgs$ = polyArgs$ + "--metadata" + newline$
    polyArgs$ = polyArgs$ + metaPath$ + newline$
    polyArgs$ = polyArgs$ + "--textgrid" + newline$
    polyArgs$ = polyArgs$ + textgridArg$ + newline$
    polyArgs$ = polyArgs$ + "--result" + newline$
    polyArgs$ = polyArgs$ + tempResult$ + newline$
    polyArgs$ = polyArgs$ + "--log" + newline$
    polyArgs$ = polyArgs$ + tempLog$ + newline$
    writeFile: tempArgs$, polyArgs$
    polyOut$ = runSubprocess$ (python_exe$, backend_script$, "@" + tempArgs$)
    # Praat bug (6.4.63 / 7.0): an EMPTY runSubprocess$ result crashes index()
    # and appendInfoLine; replace it by a literal before using it.
    if length(polyOut$) = 0
        polyOut$ = "(no console output)"
    endif
    if index(polyOut$, "CCC_POLY_STATUS") = 0
        appendInfoLine: "Backend console output (no status line):"
        appendInfoLine: polyOut$
    endif

    polyErr$ = ""
    if not fileReadable(tempResult$)
        polyErr$ = "the backend produced no result"
    else
        res$ = readFile$(tempResult$)
        resSR = extractNumber(res$, "sample_rate ")
        resN = extractNumber(res$, "samples ")
        resV = extractNumber(res$, "voices ")
        gSL = extractNumber(res$, "source_gain_L ")
        gSR = extractNumber(res$, "source_gain_R ")
        mixGain = extractNumber(res$, "mix_gain ")
        mixPeakBefore = extractNumber(res$, "mix_peak_before ")
        if index(res$, "status error") > 0
            polyErr$ = "the backend reported an error (exit code "
                ... + string$(extractNumber(res$, "exit_code ")) + ")"
        elsif resSR = undefined or resN = undefined or resV = undefined or gSL = undefined or mixGain = undefined
            polyErr$ = "the result file is incomplete"
        elsif resSR <> srcSR or resN <> srcN or resV <> nVoices
            polyErr$ = "result does not match the source (" + string$(resN) + " samples at "
                ... + string$(resSR) + " Hz, " + string$(resV) + " voices)"
        endif
        for v from 1 to nVoices
            gL'v' = extractNumber(res$, "gain_L_" + string$(v) + " ")
            gR'v' = extractNumber(res$, "gain_R_" + string$(v) + " ")
            pan'v' = extractNumber(res$, "pan_" + string$(v) + " ")
            if polyErr$ = ""
                if not fileReadable(tempDir$ + polyTag$ + "_voice_" + string$(v) + ".wav")
                    polyErr$ = "voice " + string$(v) + " was not written"
                elsif gL'v' = undefined or gR'v' = undefined
                    polyErr$ = "pan gains missing for voice " + string$(v)
                endif
            endif
        endfor
    endif
    if polyErr$ <> ""
        @showPyLog
        if not fileReadable(tempResult$)
            # show both views: where the backend says it wrote, and where
            # Praat looked
            appendInfoLine: ""
            appendInfoLine: "Backend report:"
            appendInfoLine: polyOut$
            appendInfoLine: "Praat expected the result at: ", tempResult$
            appendInfoLine: "Praat expected the log at:    ", tempLog$
            seen = Create Strings as file list: "ccc_seen", tempDir$ + "ccc_*"
            nSeen = Get number of strings
            appendInfoLine: "ccc_* files Praat sees in ", tempDir$, ": ", nSeen
            for iSeen to min(nSeen, 12)
                selectObject: seen
                seenName$ = Get string: iSeen
                appendInfoLine: "   ", seenName$
            endfor
            removeObject: seen
            appendInfoLine: "Python:  ", python_exe$
            appendInfoLine: "Backend: ", backend_script$
        endif
        @cleanUpTempFiles
        exitScript: "Polyphonic Layers failed - " + polyErr$ + "." + newline$
            ... + "The Python error (if any) is shown in the Info window above." + newline$
            ... + "Nothing was created; the selected Sound is unchanged."
    endif

    # ---- import the voices (each must be mono, N samples, source rate) ----
    for v from 1 to nVoices
        Read from file: tempDir$ + polyTag$ + "_voice_" + string$(v) + ".wav"
        voice'v' = selected("Sound")
        vN = Get number of samples
        vSR = Get sampling frequency
        vCh = Get number of channels
        if vN <> srcN or vSR <> srcSR or vCh <> 1
            for u from 1 to v
                removeObject: voice'u'
            endfor
            @cleanUpTempFiles
            exitScript: "Polyphonic Layers: voice " + string$(v) + " has " + string$(vN) + " samples at "
                ... + string$(vSR) + " Hz (" + string$(vCh) + " ch); expected " + string$(srcN)
                ... + " at " + string$(srcSR) + " Hz mono."
        endif
        # same timeline origin as the source
        Shift times to: "start time", srcXmin
        Rename: sourceName$ + "_poly_voice_" + string$(v)
    endfor

    # ---- stereo mix: untouched source (centre) + voices, equal-power pan ----
    mix = 0
    if wantMix or play_result
        selectObject: source
        mix = Copy: sourceName$ + "_polyphonic_mix"
        Convert to stereo
        mixStereo = selected("Sound")
        removeObject: mix
        mix = mixStereo
        Rename: sourceName$ + "_polyphonic_mix"
        mixL$ = "self * gSL"
        mixR$ = "self * gSR"
        for v from 1 to nVoices
            vid$ = string$(voice'v')
            mixL$ = mixL$ + " + gL" + string$(v) + " * object[" + vid$ + ", 1, col]"
            mixR$ = mixR$ + " + gR" + string$(v) + " * object[" + vid$ + ", 1, col]"
        endfor
        Formula: "if row = 1 then " + mixL$ + " else " + mixR$ + " fi"
        # one COMMON gain for the whole mix (relative voice balance preserved)
        if mixGain <> 1
            Formula: "self * mixGain"
        endif
        mixPeak = Get absolute extremum: 0, 0, "None"
        mixN = Get number of samples
        if mixN <> srcN
            appendInfoLine: "WARNING: mix has ", mixN, " samples, expected ", srcN, "."
        endif
    endif

    # ---- separate source object (bit-exact copy; the original is untouched) ----
    srcCopy = 0
    if wantVoices
        selectObject: source
        srcCopy = Copy: sourceName$ + "_source"
    endif

    appendInfoLine: ""
    for v from 1 to nVoices
        vrms = extractNumber(res$, "voice_rms_" + string$(v) + " ")
        appendInfoLine: "Voice ", v, ": pan ", fixed$(pan'v', 0), "   active RMS ",
            ... fixed$(20 * log10(max(vrms, 1e-10)), 1), " dBFS"
    endfor
    srcRms = extractNumber(res$, "source_active_rms ")
    appendInfoLine: "Source active RMS ", fixed$(20 * log10(max(srcRms, 1e-10)), 1), " dBFS (centre)"
    if mix
        appendInfoLine: "Stereo mix: peak before normalisation ", fixed$(20 * log10(max(mixPeakBefore, 1e-10)), 2),
            ... " dBFS, common gain ", fixed$(20 * log10(mixGain), 2), " dB -> peak ",
            ... fixed$(20 * log10(max(mixPeak, 1e-10)), 2), " dBFS"
    endif
    if srcPeakIn > 1
        appendInfoLine: "Note: the source exceeds full scale (", fixed$(srcPeakIn, 3),
            ... "); its 32-bit export (analysis and stems) is clipped."
    endif
    exportSet$ = extractLine$(res$, "export_set ")
    if exportDir$ <> "" and exportSet$ <> ""
        appendInfoLine: "Exported aligned 32-bit float stems: ", exportDir$, "/", exportSet$, "_*.wav"
    endif

    if import_textgrid and fileReadable(tempTG$)
        Read from file: tempTG$
        Shift times to: "start time", srcXmin
        Rename: sourceName$ + "_poly_layers"
        polyTG = selected("TextGrid")
        appendInfoLine: "Imported TextGrid (tiers: source analysis + one per voice; S start, C chronological,"
        appendInfoLine: "J graph jump, F fallback, empty = rest)."
    else
        polyTG = 0
    endif
    if keep_layer_metadata and fileReadable(metaPath$)
        appendInfoLine: "Metadata kept: ", metaPath$
    endif

    @cleanUpTempFiles

    if play_result
        selectObject: mix
        Play
    endif
    # objects the user did not ask for are removed
    if not wantVoices
        for v from 1 to nVoices
            removeObject: voice'v'
        endfor
    endif
    if not wantMix and mix
        removeObject: mix
        mix = 0
    endif
    if mix
        selectObject: mix
        if wantVoices
            plusObject: srcCopy
        endif
    else
        selectObject: srcCopy
    endif
    if wantVoices
        for v from 1 to nVoices
            plusObject: voice'v'
        endfor
    endif
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
textgridArg$ = "-"
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
