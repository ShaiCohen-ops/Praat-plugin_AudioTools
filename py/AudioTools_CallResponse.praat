# ============================================================
# Praat AudioTools Plugin
# Script:      AudioTools_CallResponse.praat
# Author:      Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version:     0.4.12 (2026) - Performer display (from v0.4.11)
# License:     MIT License
# Repository:  https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Intelligent Musical Call & Response.  A performer plays phrases;
#   audiotools_call_response.py analyses each phrase and chooses ONE of six
#   existing AudioTools transformations plus gesture-derived parameters;
#   the transformation is rendered by that AudioTools script in Praat.
#
#     Paulstretch ............. stable harmonic material
#     Markov Soundscape Weaver  noisy / aperiodic material
#     MDS Space Navigator ..... discrete separable attacks
#     Spiral Pitch Dance ...... continuous glissando
#     8-Channel Speed Deviations complex envelope -> eight constant channel speeds
#     Percussive Groove Creator percussive events, changing density
#
# Source modes:
#   Live - continuous (v0.2.0, default)
#     This script starts ONE persistent Python engine (a blocking call to
#     "launch", which starts the engine detached and returns at once) and
#     then only polls its status file.  The engine keeps the microphone open the whole time:
#       capture -> detect + analyse -> render queue -> RENDER -> play queue -> PLAY
#     RENDER runs THIS SAME SCRIPT headless ("praat --run", render mode,
#     selected by the environment variable AUDIOTOOLS_CR_JOB), using the
#     same runT procedure as the other modes.  Python plays the WAV that
#     Praat rendered.  New phrases are recorded while answers are being
#     rendered and played; answers queue and play one after another.
#     Display + Stop: the Demo window (status, input level, STOP button;
#     Esc also stops).  The Info window gets the same short text whenever
#     it changes.  Praat itself is busy running this loop until you stop.
#   Live - turn-taking (v0.1.3)
#     Unchanged v0.1.3 behaviour: one blocking listen, render, Play.
#   Selected Sound(s) / Test all six / List audio devices
#     As in v0.1.3 (List now shows output devices too).
#
# Changelog v0.4.12 - Performer display (from v0.4.11):
#   The display now separates what the PERFORMER can do from what the
#   SYSTEM is doing (they are independent in continuous mode):
#     YOUR PERFORMANCE   STAY QUIET (calibrating)
#                        PLAY WHEN READY - start at any moment, also while
#                          answers sound
#                        RECORDING YOUR PHRASE - with a progress bar of the
#                          silence that will end it (End_silence_s); a long
#                          phrase split at Max_phrase_s says "keep playing"
#                        PHRASE CAPTURED - for 2 s after a phrase ended; it
#                          never blocks a new phrase
#     SYSTEM RESPONSE    processing / playing / voices / memory / action,
#                        "waiting for your phrase" when idle
#   READY is gone (it suggested waiting for the answers).  The memory map
#   shows the performance headline at the top.  Detection, memory and the
#   six engines are unchanged.
#
# Changelog v0.4.11 - Reliable phrase ends (from v0.4.10):
#   Engine: fixes phrases that never ended (v0.4.10 regression when the
#   mic noise rose just after calibration; and, in every version, a
#   calibration on digital silence).  Flat background is recognised and
#   learned; a held tone is never turned into background.  Display: the
#   DETECTOR line shows the last detector event for 3 s - "phrase end
#   (silence)", "split at Max_phrase_s (continues)", "noise ignored ..."
#   - so a split is no longer mistaken for the end of a gesture.
#
# Changelog v0.4.10 - Phrase detection (from v0.4.9):
#   Engine: crescendos are detected (the noise floor no longer follows the
#   playing), gradual entries are captured from where they begin, and a
#   phrase longer than Max_phrase_s is cut at a quiet point and continues
#   without loss.  Display: a DETECTOR line (input, start and end
#   thresholds, floor, accumulated quiet against End_silence_s), threshold
#   marks on the level meter (orange = start, grey = end), and READY is
#   no longer shown while a phrase is being recorded.
#
# Changelog v0.4.9 - Influence memory fixes (from v0.4.8):
#   Engine only: the coherence gate uses the retrieval's own similarity
#   (an unpitched phrase in Pitch mode was judged too similar), influence
#   arcs show each earlier phrase's real share of the chosen sound's score,
#   and the history ages from the time each phrase ENDED.  Form, dialogs
#   and defaults unchanged.
#
# Changelog v0.4.8 - Phrase-level influence memory (from v0.4.7):
#   The answer responds to the recent history of gestures: the previous
#   phrases also shape what is recalled, fading with their position and
#   with time (details in audiotools_call_response.py).  Memory_settings,
#   page "Limits & influence...": Influence_depth (1 = v0.4.7, default 3),
#   Influence_decay (0.5), Trend_weight (0 = off; > 0 also looks for where
#   the gesture is heading).  An earlier phrase counts only as far as it
#   resembles the last one: a sudden new idea starts a new history.
#   Map: earlier phrases' share = pale lilac
#   arcs.  MATCH shows "(n phrases)".  The main form is unchanged.
#
# Changelog v0.4.7 - Loudness balance (from v0.4.6):
#   Engine only (audiotools_call_response.py): Level_matching now measures
#   perceptual loudness with both stereo channels counted (decorrelated
#   stereo answers - Paulstretch, Markov, Speed Deviations - were 2-6 dB too
#   loud), keeps the loudest 100 ms of a sound <= 6 dB above its target
#   (Groove / MDS transients), and keeps each voice's peak <= 0.9 after
#   stereo placement.  One static gain per sound - no compression.  The
#   form, the dialogs and the six AudioTools scripts are unchanged.
#
# Changelog v0.4.6 - Memory map (from v0.4.5):
#   NEW memory map in the Demo window (default view when Sonic memory is
#   on; G switches between the map and the status view).  An arc diagram
#   in the spirit of the OMax / DYCI2 memory views, drawn from graph.tsv
#   written by the engine:
#     line ......... the memory: Corpus C left, the performance (phrases A,
#                    answers B, unstored phrases as light points) right
#     upper arcs ... similar sounds (colour = gesture class, paler = weaker)
#     lower arcs ... what happened: recall (purple), recall + transform
#                    (magenta), transformation phrase -> result (teal);
#                    thicker = closer match, paler = older
#     red ring ..... a sound that is sounding now; red tick = latest phrase
#   The map is redrawn only when it changes (not with the level bar).
#   Engine behaviour and the form are unchanged.
#
# Changelog v0.4.5 - Whole answers (from v0.4.4):
#   Answers and memory sounds are no longer cut before their natural end
#   (details in audiotools_call_response.py):
#   - memory layers: whole sounds by default (were random 60-100 %
#     excerpts with a random start).  NEW Playback_settings field
#     Layer_shape: "Whole sounds" | "Excerpts (onset -> natural end)".
#   - Corpus B keeps whole answers up to Max_response_s + 1.5 s (was the
#     first Max_item_s seconds, raw slice).  Max_item_s now applies to
#     live phrases and Corpus C segmentation only.
#   - playback cap Max_response_s + 1.5 s grace; a longer sound is cut at
#     its quietest point near the limit and faded.
#   - the log (Debug_log) names every voice's shape: whole / excerpt /
#     trimmed; the summary counts trimmed voices and excerpts.
#
# Changelog v0.4.4 - Engine arguments via file (from v0.4.3):
#   FIX (the real cause of "argument --w-preloaded: invalid float value: ''"
#     / "expected one argument"): the engine was started with one command
#     line of ~130 arguments (~2 KB on Windows).  runSubprocess cut it off
#     at about 1 KB, so arguments from there on were lost or emptied - with
#     a Corpus C path the cut fell in the middle (an error); without one it
#     could fall at the end and SILENTLY drop the last options (e.g.
#     Follow_live_input, Corpus_C_balance_dB, which then took defaults).
#     The arguments are now written to engine_args.txt in the session (one
#     per line, closed by #end) and launch reads them; Python starts the
#     engine with an argument list.  The v0.4.3 path normalisation stays
#     (still correct, but it was not the cause).
#
# Changelog v0.4.3 - Windows path fix (from v0.4.2):
#   FIX: a Corpus_C_folder (or praatExe$) ending in a backslash, e.g.
#     C:\Sounds\corpus\, broke the engine start ("argument --w-preloaded:
#     invalid float value: ''").  On Windows the final \ escapes the quote
#     Praat puts around the argument, so the next arguments are merged.
#     User-typed paths are now normalised before they are passed on:
#     spaces and quotes trimmed, \ -> / (Python accepts it), trailing /
#     removed (a drive root keeps it).  Nothing else changed.
#
# Changelog v0.4.2 - Performance presets (from v0.4.1):
#   Engine behaviour is unchanged.  NEW first form field Preset: one menu
#   choice sets the response mode, the Sonic memory settings and the
#   Playback settings for a typical way of playing.  "Custom" (default)
#   = exactly v0.4.1: form + dialogs.  A preset OVERRIDES Sonic_memory,
#   Response_mode, the Memory_settings values and the Playback_settings
#   values; Transformation, devices, phrase detection, Corpus_C_folder and
#   Advanced settings stay as set in the form.  Ticking Memory_settings /
#   Playback_settings opens the dialogs PRE-FILLED with the preset, to
#   fine-tune it.  Presets apply to continuous mode only.  Corpus presets
#   stop with a message when Corpus_C_folder is empty.
#   Display: MODE line shows the preset.  RENDER_FORM_ARGS gains one value.
#
# Changelog v0.4.1 - Corpus-only recall + adaptive level (from v0.4.0):
#   Analysis, classifier, the six transformations, retrieval, mixer,
#   spatialisation and session safety are unchanged.  Corpus C files are
#   still only read.  The main form has no new field.
#   NEW Response_mode "Corpus only - unprocessed recall": every answer is
#     a stored sound played as it is (envelope, level, placement only).
#     Without a qualified match the engine stays SILENT and keeps
#     listening - no Transform fallback, no passthrough.  No memory layers
#     and no background texture in this mode.  For answers from the
#     preloaded folder only, untick corpora A and B in Memory_settings.
#   NEW Playback_settings: Follow_live_input (off by default) moves the
#     answers' level with the performer's playing level, relative to the
#     session (K-weighted, +-Follow_range_dB, from the 3rd phrase; phrases
#     with strong speaker leakage are not counted).
#     Corpus_C_balance_dB adds gain to sounds from the preloaded corpus.
#   Display: VOICES line shows LEVEL +x dB when Follow_live_input is on;
#     ACTION shows "Silent (no corpus match)".
#   NOTE: Layered_response off does NOT remove memory layers in the other
#     modes - Polyphonic_density 0 (or Polyphony off) does.
#
# Changelog v0.4.0 - Polyphonic spatial playback (from v0.3.2):
#   The analysis, classifier, six transformations and their parameters,
#   Sonic Memory (corpora, retrieval, decisions) and the v0.3.1 / v0.3.2
#   session-safety rules are unchanged.  New is the PLAYBACK architecture:
#   POLYPHONY: answers no longer wait for each other.  Every answer is a
#     voice in a mixer (default max 4 voices): new gestures are answered
#     while earlier answers still sound.  Roles: response (foreground),
#     layer (a related or independent sound from memory entering 0.6-3.5 s
#     later, on the phrase's pulse if it is rhythmic, quieter, elsewhere in
#     space; probability = Polyphonic_density) and background.  Priority:
#     response > layer > background; a full mixer fades out (0.25 s) the
#     oldest background, then the oldest layer.  Polyphony off = the v0.3
#     one-answer-at-a-time order.
#   BACKGROUND: once there is material, a quiet (-33 dBFS) evolving texture
#     made from the performance's own sounds (memory + latest answers;
#     aligned overlapping grains, slow movement, gentle low-pass) keeps the
#     space from falling silent.  It recedes -9 dB while the performer
#     plays or two answers sound (-4.5 dB under one), returns over ~1.5 s,
#     crossfades into a new texture every 20-30 s.  Before the first sound
#     exists it stays silent (no synthetic noise); with a Corpus C folder it
#     starts at once.  It PAUSES while the microphone hears the speakers
#     strongly (leakage above -20 dB).
#   SPACE: equal-power panning of mono sources, preserved stereo sources
#     (mid/side width + equal-power balance), positions chosen away from
#     sounding voices, answers alternating sides, slow movement (two
#     incommensurate sines).  No decorrelation, no phase tricks (mono-safe),
#     |pan| <= 0.85.  Stereo_width, Spatial_movement, Pan_variation.
#   ENVELOPES: raised-cosine fade-in (30 ms, <= 15 % of the sound; 1 ms
#     anti-click ramp for transient starts - attacks are kept) and fade-out
#     (400 ms, <= 30 %; >= 0.5 s for an answer cut by Max_response_s);
#     smooth gain ramps for ducking and voice stealing; the whole mix fades
#     out (150 ms) before the engine stops.
#   LEVEL: optional level matching per role (-18 / -24 / -33 dBFS active
#     RMS), a peak limiter (ceiling -0.5 dBFS) on the sum.
#   LEAKAGE: the guard follows the LOUDER output channel; the phrase check
#     also fits the two channels separately (a voice panned to the speaker
#     the microphone hears best) and tolerates +-3 ms of clock drift; the
#     leak estimate decays only with evidence that the path is gone; extra
#     4 dB guard margin while only the background sounds.
#   UI: one new form field, Playback_settings (dialog: polyphony, max
#     voices, density, background + level, width, movement, pan variation,
#     fade-in/out, transients, level matching).  Display: VOICES line.
#
# Changelog v0.3.2 - Status-file robustness (from v0.3.1):
#   Musical behaviour, memory, retrieval, the six transformations and the
#   v0.3.1 session-safety rules are unchanged.
#   FIX (Windows error 13): Praat no longer stops when a read of status.txt
#     collides with the engine replacing it.  Status reads are guarded; a
#     failed or incomplete read (no end=1) is skipped and the last complete
#     status is kept.  Heartbeat and stop-request writes are guarded too.
#   FIX: "the engine process never ran" is reported only if NO complete
#     status was ever read.  An engine that did run but whose status stays
#     unreadable for 30 s is stopped with its own message.
#   FIX: the engine retries a status update that hits a locked file, logs
#     the first failure of a streak (with its cause) and the recovery,
#     counts failures (summary: status_write_failures) and retries the
#     FINAL status for up to 5 s.  No half-written .tmp file is left.
#   Cleanup after an unexpected Praat stop: unchanged v0.3.1 path - the
#     engine notices the missing heartbeat after 20 s and removes its own
#     session (only its own: PID + start time).
#
# Changelog v0.3.1 - Cleanup & Session Safety (from v0.3.0):
#   Only session lifecycle / deletion changed; musical behaviour, retrieval
#   and the six transformations are identical to v0.3.0.
#   FIX: cleanup no longer deletes a session whose engine is still running.
#     It waits for the engine (PID + process start time), and if the
#     engine is still alive it deletes NOTHING and reports CLEANUP
#     INCOMPLETE; the engine then removes its own session when it exits.
#   FIX: crash recovery never removes a session whose engine is alive,
#     however long it has been quiet; a reused PID (same number, different
#     start time) counts as dead.
#   FIX: this script no longer force-deletes files of a session folder
#     that Python's cleanup left in place; it shows CLEANUP INCOMPLETE.
#   Python cleanup commands return a non-zero exit code when something was
#     not removed (except with --report, used by this script).
#
# Changelog v0.3.0 - Sonic Memory Upgrade from v0.2.0:
#   NEW Sonic Memory (continuous mode): the engine keeps three corpora in
#     RAM - A live phrases, B processed responses (the Praat results, with
#     provenance and a generation limit), C a preloaded folder (read-only,
#     re-indexed at every start) - and answers each phrase with Transform
#     (v0.2), Recall (play a similar stored sound), Recall + Transform (a
#     similar stored sound rendered by one of the six transformations) or a
#     weighted Hybrid of the three.  Similarity: timbre, pitch gesture,
#     rhythm, envelope, hybrid or contrast; minimum similarity, cooldown and
#     self-exclusion; without a qualified match the answer is a Transform.
#   NEW form fields: Sonic_memory, Response_mode, Corpus_C_folder,
#     Memory_settings (dialog: corpora, similarity, corpus and action
#     weights, evolving memory, layered response; "Limits..." page:
#     generation, corpus sizes, audio memory, item length, candidates,
#     cooldown).  Display: MEMORY / RECALL / MATCH / ACTION lines.
#   NEW zero temporary files: the probe file lives outside the session and
#     is always deleted; the session folder is created only after Python is
#     found; the debug log lives INSIDE the session and is deleted with it
#     (its key events are shown in the Info window at the end); after the
#     engine stops, Python "cleanup" waits for the engine process, deletes
#     the session with retries, and this script verifies the folder is gone
#     before reporting "STOPPED - cleanup complete" (or lists what is left).
#     Abandoned sessions of crashed runs are removed at the next start;
#     active sessions of another Praat window are never touched.
#   PRESERVED: everything in v0.2.0 - continuous listening, the six
#     transformations and their exact arguments, render mode, MDS
#     visualisation flag, MAX MC preset, turn-taking, Selected Sound(s).
#     Sonic memory applies to continuous mode only.
#
# Changelog v0.2.0 - Continuous Listening Upgrade from v0.1.3:
#   PRESERVED: the six transformations and their exact positional
#     arguments (incl. 8-Channel Speed Deviations v0.7 preset
#     "MAX MC Deviate (fresh random every run)", MC varispeed, odd/even
#     MC stereo), runT validation/clamping, output identification by
#     watermark + name stem, runner-up fallback in automatic mode,
#     untransformed-phrase fallback, MDS v0.4.1 / MAX MC version guards,
#     minimal Info display, no Picture-window drawing, temp cleanup.
#   NEW: continuous mode (persistent engine, async launch, Demo-window
#     display with STOP, Praat heartbeat so the engine stops if Praat goes
#     away), headless render mode of this script, Output_device field,
#     optional Debug_log (v0.3.0: inside the session, deleted at the end), Advanced
#     dialog: sample rate, channels, queue limits, overflow policy, maximum
#     response length, session length, idle stop, leakage guard, playback.
#   ARCHITECTURE: the runner-up fallback moved into procedure
#     renderWithFallback, shared by turn-taking and render mode.
#     Max_response_s replaces the fixed 20 s cap (speeddev, Markov).
#   COMPATIBILITY: Source options are renumbered (continuous first);
#     Sample_rate, Channels and Play_response moved from the form to the
#     Advanced dialog (defaults unchanged: 44100, 1, on).  Continuous mode
#     requires Praat 6.4.34 or newer; turn-taking still runs on 6.3+.
#
# Installation:
#   plugin_AudioTools/Vector Chain/AudioTools_CallResponse.praat
#   plugin_AudioTools/py/audiotools_call_response.py
#   pip install numpy scipy soundfile sounddevice
#   Continuous mode also launches Praat headless: set praatExe$ below if
#   your Praat executable is not found automatically.
#   Sonic memory (v0.3.0): on by default in continuous mode.  For a
#   preloaded corpus, put the folder of your sound files in Corpus_C_folder
#   (any format libsndfile reads: wav, aiff, flac, ogg, mp3 ...); the files
#   are only READ, never changed, and re-indexed at every start.  Tick
#   Memory_settings for similarity mode, weights and limits.  The
#   Memory_settings and Advanced_settings dialogs are GUI-only: keep them
#   unticked when this script is run from another script.
#
# Presets (v0.4.2): pick one in the first form field; tick Memory_settings
#   / Playback_settings to see and fine-tune what it set.
#
# Testing without a microphone:
#   Select Sounds, Source = "Selected Sound(s)" (one answer per Sound, or
#   "Test all six").  python audiotools_call_response.py --self-test
#
# Notes:
#   - Praat 7: askForTrust() is requested once (temporary files, Python,
#     headless Praat).  Render children run with --FULL-TRUST.
#   - Use headphones or route the answers away from the microphone: the
#     engine estimates speaker->mic leakage and warns, but it does NOT
#     cancel echo.
#   - Unattended runs: set AUDIOTOOLS_CR_HEADLESS=1 to skip the Demo window
#     (stop by creating stop.request in the session folder, or via the
#     session / idle limits).
# ============================================================

form: "AudioTools Call & Response 0.4.12"
    optionmenu: "Preset", 1
        option: "Custom (form and dialogs)"
        option: "Classic transform (v0.2)"
        option: "Transform + ambience"
        option: "Hybrid memory (default)"
        option: "Echo memory (recall own phrases)"
        option: "Corpus only - hybrid match"
        option: "Corpus only - timbre match"
        option: "Corpus only - pitch gesture match"
        option: "Corpus only - rhythm match"
        option: "Corpus only - contrast (most different)"
        option: "Corpus re-composed (corpus + transform)"
        option: "Dense ensemble"
        option: "Sparse / intimate"
        option: "Ambient bed"
        option: "Percussive / rhythmic"
    optionmenu: "Source", 1
        option: "Live - continuous (v0.2)"
        option: "Live - turn-taking (v0.1.3)"
        option: "Selected Sound(s)"
        option: "List audio devices"
    optionmenu: "Transformation", 1
        option: "Automatic (gesture classifier)"
        option: "Paulstretch"
        option: "Markov Soundscape Weaver"
        option: "MDS Space Navigator"
        option: "Spiral Pitch Dance"
        option: "8-Channel Speed Deviations (MAX MC)"
        option: "Percussive Groove Creator"
        option: "Test all six (selected Sounds)"
    natural: "Cycles", "4"
    sentence: "Input_device", "default"
    sentence: "Output_device", "default"
    positive: "Sensitivity_dB", "9"
    positive: "Min_phrase_s", "0.5"
    positive: "End_silence_s", "0.6"
    positive: "Max_phrase_s", "12"
    comment: "Sonic memory (continuous mode)"
    boolean: "Sonic_memory", 1
    optionmenu: "Response_mode", 1
        option: "Hybrid (transform / recall / recall + transform)"
        option: "Transform only (v0.2)"
        option: "Recall"
        option: "Recall + Transform"
        option: "Corpus only - unprocessed recall"
    sentence: "Corpus_C_folder", ""
    boolean: "Memory_settings", 0
    boolean: "Playback_settings", 0
    boolean: "Debug_log", 0
    boolean: "Advanced_settings", 0
endform
# The headless renderer passes one value per field above: keep
# RENDER_FORM_ARGS in audiotools_call_response.py in the same order.

# ---- EDIT IF YOUR PYTHON IS NON-STANDARD (empty = auto-detect only) ----
pyCandidate1$ = "C:/Users/user/praat_ddsp_env/Scripts/python.exe"
# ---- Praat executable for headless rendering in continuous mode --------
# Empty = auto-detect.  The executable itself or the folder containing it.
praatExe$ = ""
# ------------------------------------------------------------------------
waitTimeout = 30
preroll = 0.25
version$ = "0.4.12"
diagnostics = 0

# ---- Advanced settings: defaults (also used when the dialog is skipped) ----
sample_rate = 44100
channels = 1
max_pending_phrases = 3
max_pending_responses = 3
overflow_policy = 1
max_response_s = 20
session_minutes = 60
idle_stop_s = 300
leakage_guard = 1
play_response = 1
maxResponse = max_response_s

# ---- Playback settings (v0.4.0): defaults (also used when the dialog is skipped) ----
polyphony = 1
max_voices = 4
polyphonic_density = 0.5
background_layer = 1
background_level_dB = -33
stereo_width = 1.0
spatial_movement = 0.3
pan_variation = 0.5
fade_in_ms = 30
fade_out_ms = 400
preserve_transients = 1
level_matching = 1
follow_live_input = 0
follow_range_dB = 9
corpus_C_balance_dB = 0
layer_shape = 1

# ---- Sonic memory settings: defaults (also used when the dialog is skipped) ----
use_live_corpus_A = 1
use_processed_corpus_B = 1
use_preloaded_corpus_C = 1
similarity_mode = 1
minimum_similarity = 0.45
weight_A_live = 40
weight_B_processed = 30
weight_C_preloaded = 30
weight_transform = 40
weight_recall = 30
weight_recall_transform = 30
evolving_memory = 0
layered_response = 0
max_generation = 2
max_live_phrases = 100
max_processed_responses = 100
max_audio_memory_min = 30
max_item_s = 15
candidates = 5
cooldown_recalls = 4
exclude_recent_phrases = 2
same_family_exclusion = 0
influence_depth = 3
influence_decay = 0.5
trend_weight = 0
renderJob$ = environment$ ("AUDIOTOOLS_CR_JOB")
renderMode = renderJob$ <> ""
headless = environment$ ("AUDIOTOOLS_CR_HEADLESS") = "1"

# ---- Praat 7 trust (file writing, deletion, subprocess) ----
if praatVersion >= 7000
    trustGranted = askForTrust ()
    if not trustGranted
        exitScript: "Call & Response needs FULL TRUST (it writes temporary audio and runs Python)."
    endif
endif
hasClock = praatVersion >= 6434

# ---- Six transformations: fixed whitelist, ids never taken from Python ----
nT = 6
tId$[1] = "paulstretch"
tId$[2] = "markov"
tId$[3] = "mds"
tId$[4] = "spiral"
tId$[5] = "speeddev"
tId$[6] = "groove"
tDisplay$[1] = "Paulstretch"
tDisplay$[2] = "Markov Soundscape Weaver"
tDisplay$[3] = "MDS Space Navigator"
tDisplay$[4] = "Spiral Pitch Dance"
tDisplay$[5] = "8-Channel Speed Deviations (MAX MC)"
tDisplay$[6] = "Percussive Groove Creator"
tRel$[1] = "Time & Granular/Paulstretch.praat"
tRel$[2] = "AI & Adaptive/Markov_Soundscape_Weaver.praat"
tRel$[3] = "Time & Granular/MDS_Space_Navigator.praat"
tRel$[4] = "Pitch/Spiral_Pitch_Dance.praat"
tRel$[5] = "Spatial & Surround/8-channel_speed_deviations.praat"
tRel$[6] = "Time & Granular/Percussive Audio Groove Creator.praat"
# name stem each script appends to its input name (verified in source)
tStem$[1] = "_PS_"
tStem$[2] = "_MarkovWeave_"
tStem$[3] = "_reordered"
tStem$[4] = "_spiral_"
tStem$[5] = "_speed_MCstereo_MAX_MC_Deviate"
tStem$[6] = "_groove_"

log$ = ""
currentStatus$ = "AudioTools Call & Response"
displayCore$ = ""
# v0.4.6 memory map (Demo window): view 1 = map, 0 = status; G toggles
graphView = 1
graphTable = 0
graphVer$ = ""

# ============================================================
# RENDER MODE (headless child launched by the continuous engine)
#   Reads one job file, renders it with the SAME runT / fallback code as
#   the other modes, saves a 32-bit WAV and a result file, and exits.
# ============================================================
if renderMode
    meta$ = newline$ + readFile$ (renderJob$)
    @getStr: "result"
    resFile$ = getStr.v$
    @getStr: "out"
    outFile$ = getStr.v$
    @getStr: "wav"
    inFile$ = getStr.v$
    @getStr: "job_id"
    tag$ = getStr.v$
    @getStr: "plugin_root"
    pluginRoot$ = getStr.v$
    @getStr: "max_response"
    maxResponse = number (getStr.v$)
    if maxResponse = undefined
        maxResponse = 20
    endif
    @getStr: "selected"
    sel$ = getStr.v$
    @getStr: "ranking"
    ranking$ = getStr.v$
    @getStr: "mode"
    isAuto = getStr.v$ = "auto"
    for i to nT
        tPath$[i] = pluginRoot$ + "/" + tRel$[i]
    endfor
    @detectSupport
    selK = 0
    for k to nT
        if sel$ = tId$[k]
            selK = k
        endif
    endfor
    rStatus$ = "fail"
    rUsed$ = ""
    rMsg$ = ""
    rSec = 0
    if selK = 0
        rMsg$ = "selected transformation '" + sel$ + "' is not in the whitelist"
    elsif not fileReadable (inFile$)
        rMsg$ = "phrase WAV missing: " + inFile$
    else
        phrase = Read from file: inFile$
        Rename: "crq_" + tag$
        @renderWithFallback: selK, phrase, tag$, isAuto, ranking$
        rSec = renderWithFallback.sec
        rMsg$ = renderWithFallback.msg$
        if renderWithFallback.answer
            selectObject: renderWithFallback.answer
            Save as 32-bit WAV file: outFile$
            rStatus$ = "ok"
            rUsed$ = renderWithFallback.usedId$
        endif
    endif
    rLog$ = replace$ (replace$ (log$, newline$, " | ", 0), "=", ":", 0)
    writeFileLine: resFile$, "status=" + rStatus$
    appendFileLine: resFile$, "used=" + rUsed$
    appendFileLine: resFile$, "msg=" + replace$ (rMsg$, newline$, " ", 0)
    appendFileLine: resFile$, "sec=" + fixed$ (rSec, 3)
    appendFileLine: resFile$, "log=" + rLog$
    appendFileLine: resFile$, "end=1"
    exitScript: ""
endif

# ============================================================
# PRESETS (v0.4.2) - applied BEFORE the dialogs, so a ticked
# Memory_settings / Playback_settings box opens them pre-filled.
# Each preset starts from the v0.4.1 defaults, then changes only what
# makes it different.  Option numbers:
#   response_mode   1 hybrid  2 transform  3 recall  4 recall+transform
#                   5 corpus only
#   similarity_mode 1 hybrid  2 timbre  3 pitch  4 rhythm  5 envelope
#                   6 contrast
# ============================================================
presetName$ = preset$
presetNeedsC = 0
if preset > 1 and source = 1
    # common base for every preset = the v0.4.1 defaults
    sonic_memory = 1
    response_mode = 1
    use_live_corpus_A = 1
    use_processed_corpus_B = 1
    use_preloaded_corpus_C = 1
    similarity_mode = 1
    minimum_similarity = 0.45
    weight_A_live = 40
    weight_B_processed = 30
    weight_C_preloaded = 30
    weight_transform = 40
    weight_recall = 30
    weight_recall_transform = 30
    evolving_memory = 0
    layered_response = 0
    max_generation = 2
    candidates = 5
    cooldown_recalls = 4
    exclude_recent_phrases = 2
    same_family_exclusion = 0
    polyphony = 1
    max_voices = 4
    polyphonic_density = 0.5
    background_layer = 1
    background_level_dB = -33
    stereo_width = 1.0
    spatial_movement = 0.3
    pan_variation = 0.5
    fade_in_ms = 30
    fade_out_ms = 400
    preserve_transients = 1
    level_matching = 1
    follow_live_input = 0
    follow_range_dB = 9
    corpus_C_balance_dB = 0
    layer_shape = 1
    influence_depth = 3
    influence_decay = 0.5
    trend_weight = 0

    if preset = 2
        # Classic transform (v0.2): one transformed answer at a time, nothing else
        sonic_memory = 0
        response_mode = 2
        polyphony = 0
        background_layer = 0
        spatial_movement = 0
    elsif preset = 3
        # Transform + ambience: transformed answers over a texture of the answers
        response_mode = 2
        polyphonic_density = 0
        background_level_dB = -30
        follow_live_input = 1
    elsif preset = 4
        # Hybrid memory (default): the v0.4.1 defaults unchanged
    elsif preset = 5
        # Echo memory: answers recalled from your own earlier phrases / answers
        response_mode = 3
        use_preloaded_corpus_C = 0
        minimum_similarity = 0.5
        cooldown_recalls = 3
        polyphonic_density = 0.3
        follow_live_input = 1
    elsif preset >= 6 and preset <= 10
        # Corpus only: answers = preloaded sounds as they are, silence otherwise
        presetNeedsC = 1
        response_mode = 5
        use_live_corpus_A = 0
        use_processed_corpus_B = 0
        use_preloaded_corpus_C = 1
        weight_C_preloaded = 100
        cooldown_recalls = 2
        polyphonic_density = 0
        background_layer = 0
        follow_live_input = 1
        if preset = 6
            # Live-tested value for Corpus only - hybrid match;
            # all other presets retain their own similarity thresholds.
            similarity_mode = 1
            minimum_similarity = 0.25
        elsif preset = 7
            similarity_mode = 2
            minimum_similarity = 0.5
        elsif preset = 8
            similarity_mode = 3
            minimum_similarity = 0.4
        elsif preset = 9
            similarity_mode = 4
            minimum_similarity = 0.4
            fade_in_ms = 5
            fade_out_ms = 150
        else
            # contrast: score = 1 - similarity must reach the minimum
            similarity_mode = 6
            minimum_similarity = 0.3
        endif
    elsif preset = 11
        # Corpus re-composed: a similar corpus sound rendered by one of the six
        response_mode = 4
        presetNeedsC = 1
        use_live_corpus_A = 0
        use_processed_corpus_B = 0
        weight_C_preloaded = 100
        max_generation = 1
        polyphonic_density = 0.3
        follow_live_input = 1
    elsif preset = 12
        # Dense ensemble: many voices, layers on every answer, wide movement
        max_voices = 6
        polyphonic_density = 0.9
        layered_response = 1
        spatial_movement = 0.6
        pan_variation = 0.8
        background_level_dB = -30
        candidates = 8
        follow_live_input = 1
    elsif preset = 13
        # Sparse / intimate: few voices, narrow image, long releases
        max_voices = 2
        polyphonic_density = 0.15
        background_layer = 0
        stereo_width = 0.6
        spatial_movement = 0.1
        pan_variation = 0.2
        fade_out_ms = 800
        cooldown_recalls = 6
        follow_live_input = 1
    elsif preset = 14
        # Ambient bed: a present background, slow soft entries, moving space
        polyphonic_density = 0.6
        background_level_dB = -27
        spatial_movement = 0.6
        fade_in_ms = 300
        fade_out_ms = 1500
        preserve_transients = 0
        evolving_memory = 1
    elsif preset = 15
        # Percussive / rhythmic: rhythm matching, attacks kept, short tails,
        # layers land on the phrase's own pulse
        similarity_mode = 4
        polyphonic_density = 0.4
        background_layer = 0
        fade_in_ms = 5
        fade_out_ms = 150
        preserve_transients = 1
        pan_variation = 0.8
    endif

    # a preset that recalls from the preloaded corpus needs its folder
    presetCdir$ = replace_regex$ (corpus_C_folder$, "^\s+|\s+$", "", 0)
    if presetNeedsC and presetCdir$ = ""
        exitScript: "Preset """ + preset$ + """ answers from the preloaded corpus:" + newline$
            ... + "set Corpus_C_folder in the form to the folder of your sound files."
    endif
elsif preset > 1
    presetName$ = "Custom (form and dialogs)"
endif

# ---- Advanced dialog (GUI only; keep the box unticked for batch runs) ----
if advanced_settings
    beginPause: "Call & Response 0.4.12 - advanced"
        comment: "Audio"
        positive: "Sample_rate", string$ (sample_rate)
        natural: "Channels", string$ (channels)
        boolean: "Play_response", play_response
        comment: "Continuous mode"
        natural: "Max_pending_phrases", string$ (max_pending_phrases)
        natural: "Max_pending_responses", string$ (max_pending_responses)
        optionmenu: "Overflow_policy", overflow_policy
            option: "Drop oldest pending job"
            option: "Reject the newest job"
        positive: "Max_response_s", string$ (max_response_s)
        positive: "Session_minutes", string$ (session_minutes)
        real: "Idle_stop_s", string$ (idle_stop_s)
        boolean: "Leakage_guard", leakage_guard
    clicked = endPause: "Cancel", "Start", 2, 1
    if clicked = 1
        exitScript: "Cancelled."
    endif
    maxResponse = max_response_s
endif

# ---- Sonic memory dialog (continuous mode) ----
# ---- Playback dialog (v0.4.0, continuous mode) ----
if playback_settings and source = 1
    beginPause: "Call & Response 0.4.12 - playback"
        comment: "Polyphony"
        boolean: "Polyphony", polyphony
        natural: "Max_voices", string$ (max_voices)
        real: "Polyphonic_density", string$ (polyphonic_density)
        optionmenu: "Layer_shape", layer_shape
            option: "Whole sounds"
            option: "Excerpts (onset -> natural end)"
        boolean: "Background_layer", background_layer
        real: "Background_level_dB", string$ (background_level_dB)
        comment: "Space (0..1)"
        real: "Stereo_width", string$ (stereo_width)
        real: "Spatial_movement", string$ (spatial_movement)
        real: "Pan_variation", string$ (pan_variation)
        comment: "Envelopes and level"
        positive: "Fade_in_ms", string$ (fade_in_ms)
        positive: "Fade_out_ms", string$ (fade_out_ms)
        boolean: "Preserve_transients", preserve_transients
        boolean: "Level_matching", level_matching
        boolean: "Follow_live_input", follow_live_input
        positive: "Follow_range_dB", string$ (follow_range_dB)
        real: "Corpus_C_balance_dB", string$ (corpus_C_balance_dB)
    pbClicked = endPause: "Cancel", "Start", 2, 1
    if pbClicked = 1
        exitScript: "Cancelled."
    endif
    corpus_C_balance_dB = min (12, max (-12, corpus_C_balance_dB))
    follow_range_dB = min (18, follow_range_dB)
endif

if memory_settings and sonic_memory and source = 1
    memPage = 1
    while memPage > 0
        if memPage = 1
            beginPause: "Call & Response 0.4.12 - sonic memory"
                comment: "Corpora (C also needs Corpus_C_folder in the main form)"
                boolean: "Use_live_corpus_A", use_live_corpus_A
                boolean: "Use_processed_corpus_B", use_processed_corpus_B
                boolean: "Use_preloaded_corpus_C", use_preloaded_corpus_C
                optionmenu: "Similarity_mode", similarity_mode
                    option: "Hybrid"
                    option: "Timbre"
                    option: "Pitch gesture"
                    option: "Rhythm"
                    option: "Envelope"
                    option: "Contrast (most different)"
                real: "Minimum_similarity", string$ (minimum_similarity)
                comment: "Corpus weights (relative; an empty corpus passes its share on)"
                real: "Weight_A_live", string$ (weight_A_live)
                real: "Weight_B_processed", string$ (weight_B_processed)
                real: "Weight_C_preloaded", string$ (weight_C_preloaded)
                comment: "Hybrid response mode: action weights"
                real: "Weight_transform", string$ (weight_transform)
                real: "Weight_recall", string$ (weight_recall)
                real: "Weight_recall_transform", string$ (weight_recall_transform)
                boolean: "Evolving_memory", evolving_memory
                boolean: "Layered_response", layered_response
            memClicked = endPause: "Cancel", "Limits & influence...", "Start", 3, 1
            if memClicked = 1
                exitScript: "Cancelled."
            endif
            memPage = if memClicked = 2 then 2 else 0 fi
        else
            beginPause: "Call & Response 0.4.12 - memory limits and influence"
                natural: "Max_generation", string$ (max_generation)
                natural: "Max_live_phrases", string$ (max_live_phrases)
                natural: "Max_processed_responses", string$ (max_processed_responses)
                positive: "Max_audio_memory_min", string$ (max_audio_memory_min)
                positive: "Max_item_s", string$ (max_item_s)
                natural: "Candidates", string$ (candidates)
                natural: "Cooldown_recalls", string$ (cooldown_recalls)
                integer: "Exclude_recent_phrases", string$ (exclude_recent_phrases)
                boolean: "Same_family_exclusion", same_family_exclusion
                comment: "Influence of earlier phrases (1 = last phrase only)"
                natural: "Influence_depth", string$ (influence_depth)
                real: "Influence_decay", string$ (influence_decay)
                real: "Trend_weight", string$ (trend_weight)
            memClicked = endPause: "Cancel", "Back", "Start", 3, 1
            if memClicked = 1
                exitScript: "Cancelled."
            endif
            memPage = if memClicked = 2 then 1 else 0 fi
        endif
    endwhile
endif

# ---- Source flags (v0.2.0 numbering) ----
continuous = source = 1
isLive = source <= 2
isSel = source = 3
isDev = source = 4

# ---- Validate source / mode combinations ----
sweep = transformation = 8
if isLive and sweep
    exitScript: "'Test all six' works on selected Sounds only - set Source to Selected Sound(s)."
endif
if continuous and praatVersion < 6434
    exitScript: "Continuous mode needs Praat 6.4.34 or newer (clock and sleep functions)." + newline$
        ... + "This is Praat " + praatVersion$ + ". Update Praat, or use 'Live - turn-taking (v0.1.3)'."
endif
if isSel
    nSel = numberOfSelected ("Sound")
    if nSel < 1
        exitScript: "Source is Selected Sound(s): select at least one Sound object."
    endif
    for i to nSel
        selSound[i] = selected ("Sound", i)
    endfor
endif

# ---- Plugin root ----
pluginRoot$ = ""
cand1$ = preferencesDirectory$ + "/plugin_AudioTools"
cand2$ = defaultDirectory$ + "/.."
cand3$ = defaultDirectory$
for i to 3
    c$ = cand'i'$
    if pluginRoot$ = "" and fileReadable (c$ + "/" + tRel$[1])
        pluginRoot$ = c$
    endif
endfor
pluginRoot$ = replace_regex$ (pluginRoot$, "[/\\][^/\\]+[/\\]\.\.$", "", 0)
if pluginRoot$ = ""
    exitScript: "Cannot find the AudioTools plugin root (looked for " + tRel$[1] + ") in:" + newline$
        ... + cand1$ + newline$ + cand2$ + newline$ + cand3$
endif
missing$ = ""
for i to nT
    tPath$[i] = pluginRoot$ + "/" + tRel$[i]
    if not fileReadable (tPath$[i])
        missing$ = missing$ + "  " + tPath$[i] + newline$
    endif
endfor

pyScript$ = pluginRoot$ + "/py/audiotools_call_response.py"
if not fileReadable (pyScript$)
    pyScript$ = defaultDirectory$ + "/audiotools_call_response.py"
endif
if not fileReadable (pyScript$)
    exitScript: "Cannot find audiotools_call_response.py in " + pluginRoot$ + "/py/ or next to this script."
endif

# ---- Session folder: RAM-backed where available, never the home folder ----
base$ = ""
if unix and folderExists ("/dev/shm")
    base$ = "/dev/shm"
endif
if base$ = "" and windows
    base$ = environment$ ("TEMP")
endif
if base$ = ""
    base$ = environment$ ("TMPDIR")
endif
if base$ = "" and not windows
    base$ = "/tmp"
endif
if base$ = "" or not folderExists (base$)
    base$ = temporaryDirectory$
endif
base$ = replace_regex$ (base$, "[/\\]+$", "", 0)
sessionId$ = replace_regex$ (date$ (), "[^0-9]", "", 0) + "_" + string$ (randomInteger (1000, 9999))
# v0.3.0: the folder itself is created only after Python has been found
session$ = base$ + "/AudioTools_CR_" + sessionId$
cleanupReport$ = ""
cleanupDone = 0

@detectSupport

# ---- Native MDS visualization control: fail closed on older installations ----
# MDS Space Navigator v0.4.1 has a trailing Draw_visualization boolean.
# Do not invoke older MDS scripts: they always draw in the Picture window.
# ---- MAX MC preset exists only in Speed Deviations v0.7+ ----
# A plain version string is not sufficient: check the actual option label
# to prevent running a different mode on an older installed script.
procedure detectSupport
    mdsSupportsHeadless = 0
    if fileReadable (tPath$[3])
        .t$ = readFile$ (tPath$[3])
        if index (.t$, "boolean Draw_visualization 1") > 0
            mdsSupportsHeadless = 1
        endif
    endif
    speedSupportsMAXMC = 0
    if fileReadable (tPath$[5])
        .t$ = readFile$ (tPath$[5])
        if index (.t$, "MAX MC Deviate (fresh random every run)") > 0
            speedSupportsMAXMC = 1
        endif
    endif
endproc

# ---- Python discovery (no shell; file-based probe) ----
nPy = 0
if pyCandidate1$ <> ""
    nPy += 1
    pyC$[nPy] = pyCandidate1$
endif
if macintosh
    nPy += 1
    pyC$[nPy] = "/opt/homebrew/bin/python3"
    nPy += 1
    pyC$[nPy] = "/usr/local/bin/python3"
    nPy += 1
    pyC$[nPy] = "/Library/Frameworks/Python.framework/Versions/Current/bin/python3"
    nPy += 1
    pyC$[nPy] = "python3"
elsif windows
    nPy += 1
    pyC$[nPy] = "python"
    nPy += 1
    pyC$[nPy] = "py"
    nPy += 1
    pyC$[nPy] = "python3"
else
    nPy += 1
    pyC$[nPy] = "python3"
    nPy += 1
    pyC$[nPy] = "python"
endif

# v0.3.0: the probe file lives OUTSIDE the session and is always deleted
probe$ = base$ + "/AudioTools_CR_probe_" + sessionId$ + ".txt"
python$ = ""
probeReport$ = ""
engineVersion$ = ""
liveFlag$ = if isSel then "" else "--live" fi
for i to nPy
    if python$ = ""
        p$ = pyC$[i]
        isBare = p$ = "python" or p$ = "python3" or p$ = "py"
        if isBare or fileReadable (p$)
            if fileReadable (probe$)
                deleteFile: probe$
            endif
            if liveFlag$ = ""
                nocheck runSubprocess: p$, pyScript$, "probe", "--out", probe$
            else
                nocheck runSubprocess: p$, pyScript$, "probe", "--out", probe$, liveFlag$
            endif
            if fileReadable (probe$)
                pr$ = newline$ + readFile$ (probe$)
                deleteFile: probe$
                st$ = extractLine$ (pr$, newline$ + "status=")
                engineVersion$ = extractLine$ (pr$, newline$ + "engine_version=")
                if st$ = "ok"
                    python$ = p$
                else
                    probeReport$ = probeReport$ + "  " + p$ + ": missing "
                        ... + extractLine$ (pr$, newline$ + "missing=") + newline$
                endif
            endif
        endif
    endif
endfor
if python$ = ""
    @cleanup
    exitScript: "No usable Python found." + newline$ + probeReport$
        ... + "Install: pip install numpy scipy soundfile sounddevice" + newline$
        ... + "or set pyCandidate1$ at the top of this script."
endif

# ---- The Python file must be the same version as this script ----
if engineVersion$ <> version$
    foundV$ = if engineVersion$ = "" then "an older version (0.1.x)" else "version " + engineVersion$ fi
    @cleanup
    exitScript: "audiotools_call_response.py is " + foundV$ + ", but this script is " + version$ + "." + newline$
        ... + "Replace the Python file at:" + newline$ + pyScript$
endif

# ---- Crash recovery: remove ABANDONED sessions of earlier runs (never an
#      active session of another Praat window), then create this session ----
nocheck runSubprocess: python$, pyScript$, "cleanup-stale", "--base", base$
createFolder: session$
if not folderExists (session$)
    exitScript: "Cannot create the session folder " + session$
endif

# ---- Device list mode ----
if isDev
    devFile$ = session$ + "/devices.txt"
    nocheck runSubprocess: python$, pyScript$, "devices", "--out", devFile$
    if fileReadable (devFile$)
        writeInfoLine: readFile$ (devFile$)
    else
        writeInfoLine: "Device query failed - is sounddevice / PortAudio installed?"
    endif
    @cleanup
    exitScript: ""
endif

# ============================================================
# PERFORMER DISPLAY: two lines maximum, always the current state.
# Child scripts may write verbose Info messages; restore this text after
# their runScript returns.  Detailed reports are never printed by default.
# ============================================================
procedure log: .line$
    log$ = log$ + .line$ + newline$
endproc
procedure status: .stage$, .detail$
    # render mode (headless child) has no performer display
    if not renderMode
        currentStatus$ = "AudioTools  |  " + string$ (cyc) + "/" + string$ (nTurns)
            ... + "  |  " + .stage$
        if .detail$ <> ""
            currentStatus$ = currentStatus$ + newline$ + .detail$
        endif
        writeInfoLine: currentStatus$
    endif
endproc
procedure restoreInfo
    if not renderMode
        writeInfoLine: currentStatus$
    endif
endproc

procedure cleanup
    # v0.3.0: delete EVERYTHING this run created and verify it.  Python
    # "cleanup" waits for this session's engine process, removes the folder
    # with bounded retries (Windows file locks) and prints one line.
    if fileReadable (probe$)
        deleteFile: probe$
    endif
    cleanupReport$ = ""
    .n$ = ""
    .out$ = ""
    if folderExists (session$) and python$ <> ""
        if praatVersion >= 6427
            .out$ = runSubprocess$ (python$, pyScript$, "cleanup", "--session", session$, "--report")
            .n$ = extractWord$ (.out$, "files=")
        else
            nocheck runSubprocess: python$, pyScript$, "cleanup", "--session", session$
        endif
    endif
    if folderExists (session$)
        # v0.3.1: never force-delete here - the folder may belong to an
        # engine that is still running.  Report what Python reported.
        if index (.out$, "CLEANUP INCOMPLETE") > 0
            cleanupReport$ = mid$ (.out$, index (.out$, "CLEANUP INCOMPLETE"), 400)
            cleanupReport$ = replace$ (cleanupReport$, newline$, " ", 0)
        else
            .left$# = fileNames$# (session$ + "/*")
            .list$ = ""
            for .i to min (size (.left$#), 5)
                .list$ = .list$ + " " + .left$# [.i]
            endfor
            cleanupReport$ = "CLEANUP INCOMPLETE - remaining: " + session$ + " (" + string$ (size (.left$#))
                ... + " file(s):" + .list$ + ")"
        endif
    elsif .n$ <> ""
        cleanupReport$ = "cleanup complete (" + .n$ + " temporary files removed)"
    else
        cleanupReport$ = "cleanup complete"
    endif
    cleanupDone = 1
endproc

procedure now
    if hasClock
        .t = clock ()
    else
        .t = undefined
    endif
endproc

procedure fmt: .v, .nd
    if .v = undefined
        .s$ = "n/a"
    else
        .s$ = fixed$ (.v, .nd)
    endif
endproc

# ---- metadata access: meta$ holds the decision file, newline-prefixed ----
procedure getStr: .key$
    .v$ = extractLine$ (meta$, newline$ + .key$ + "=")
endproc

# numeric parameter, validated and clamped against the child's own limits
procedure num: .key$, .default, .lo, .hi
    @getStr: .key$
    .v = number (getStr.v$)
    if .v = undefined
        .v = .default
        clampNotes$ = clampNotes$ + .key$ + " missing->" + string$ (.default) + "  "
    elsif .v < .lo or .v > .hi
        .old = .v
        .v = min (.hi, max (.lo, .v))
        clampNotes$ = clampNotes$ + .key$ + " " + string$ (.old) + "->" + string$ (.v) + "  "
    endif
endproc

procedure s: .v
    .s$ = fixed$ (.v, 6)
endproc

# ============================================================
# RUN ONE TRANSFORMATION  (whitelisted index .k on Sound .src)
#   sets runT.result (0 = failed), runT.msg$, runT.sec
# ============================================================
procedure runT: .k, .src, .tag$
    .result = 0
    .msg$ = ""
    .sec = 0
    .bail = 0
    .haveWork = 0
    clampNotes$ = ""
    .id$ = tId$[.k]
    if not fileReadable (tPath$[.k])
        .msg$ = "script missing: " + tPath$[.k]
        .bail = 1
    elsif .id$ = "mds" and not mdsSupportsHeadless
        .msg$ = "MDS v0.4.1+ required (Draw_visualization toggle is missing)"
        .bail = 1
    elsif .id$ = "speeddev" and not speedSupportsMAXMC
        .msg$ = "8-Channel Speed Deviations v0.7+ required (MAX MC Deviate preset missing)"
        .bail = 1
    endif

    # ---- work copy with a unique name (child output names derive from it) ----
    if .bail = 0
        selectObject: .src
        .srcDur = Get total duration
        .srcSR = Get sampling frequency
        .workName$ = "crin_" + .tag$ + "_" + .id$
        .work = Copy: .workName$
        .haveWork = 1
        @num: "seed", 1, 1, 2000000000
        .seed = round (num.v)
    endif

    # ---- per-script argument build (exact form order, verified in source) ----
    if .bail = 0 and .id$ = "paulstretch"
        @num: "p_paulstretch_crop_start", 0, 0, .srcDur
        .c0 = num.v
        @num: "p_paulstretch_crop_end", .srcDur, 0, .srcDur
        .c1 = num.v
        if .c1 - .c0 > 0.3 and (.c0 > 0.001 or .c1 < .srcDur - 0.001)
            selectObject: .work
            .tmp = Extract part: .c0, .c1, "rectangular", 1, "no"
            removeObject: .work
            .work = .tmp
            Rename: .workName$
            clampNotes$ = clampNotes$ + "input cropped to " + fixed$ (.c0, 2) + "-" + fixed$ (.c1, 2) + " s  "
        endif
        @num: "p_paulstretch_stretch", 4, 1.25, 6
        @s: num.v
        .a3$ = s.s$
        @num: "p_paulstretch_window", 0.25, 0.05, 1
        @s: num.v
        .a4$ = s.s$
        @num: "p_paulstretch_overlap", 75, 50, 90
        @s: num.v
        .a5$ = s.s$
        @num: "p_paulstretch_stereo", 1, 0, 1
        .a6$ = string$ (round (num.v))
        @num: "p_paulstretch_phase_offset", 0.3, 0, 1
        @s: num.v
        .a7$ = s.s$
        .args$ = "Custom | Balanced (downsample to 22 kHz) | " + .a3$ + " | " + .a4$
            ... + " | " + .a5$ + " | " + .a6$ + " | " + .a7$ + " | 0 | 0"
    elsif .bail = 0 and .id$ = "markov"
        @num: "p_markov_grain_ms", 80, 20, 200
        .g = num.v
        @num: "p_markov_states", 5, 2, 8
        .kk = round (num.v)
        # script rules: duration >= 4 grains, nGrains >= 2 x states
        if .srcDur < 4 * .g / 1000
            .g = 1000 * .srcDur / 4 * 0.95
            clampNotes$ = clampNotes$ + "grain shortened to " + fixed$ (.g, 1) + " ms  "
        endif
        .nG = floor ((.srcDur - .g / 1000) / (.g / 1000 * 0.5)) + 1
        while .kk > 2 and .nG < 2 * .kk
            .kk -= 1
        endwhile
        if .nG < 2 * .kk or .g < 20
            .msg$ = "phrase too short for Markov analysis (" + string$ (.nG) + " grains)"
            .bail = 1
        endif
        @num: "p_markov_randomness", 0.2, 0, 1
        @s: num.v
        .rnd$ = s.s$
        @num: "p_markov_out_dur", 8, 1, maxResponse
        @s: num.v
        .od$ = s.s$
        @num: "p_markov_density_var", 0, 0, 1
        @s: num.v
        .dv$ = s.s$
        @num: "p_markov_decorrelation", 0.3, -1, 1
        @s: num.v
        .dc$ = s.s$
        @s: .g
        .gs$ = s.s$
        .args$ = "Manual | " + .gs$ + " | 0.5 | " + string$ (.kk) + " | First Order | "
            ... + .rnd$ + " | " + .od$ + " | 0.5 | 0 | 0.1 | " + .dv$ + " | " + .dc$
            ... + " | " + string$ (.seed) + " | 0 | 0"
    elsif .bail = 0 and .id$ = "mds"
        @num: "p_mds_silence_threshold_db", 25, 5, 60
        @s: num.v
        .th$ = s.s$
        @num: "p_mds_min_silent", 0.1, 0.02, 1
        @s: num.v
        .ms$ = s.s$
        @num: "p_mds_min_sounding", 0.1, 0.02, 1
        @s: num.v
        .mn$ = s.s$
        @num: "p_mds_between", 0.1, 0.01, 1
        @s: num.v
        .bw$ = s.s$
        .args$ = .th$ + " | " + .ms$ + " | " + .mn$ + " | MFCC (Timbre/Spectral Shape) | 5500 | 5 | 12"
            ... + " | Nearest neighbor chain (most similar next) | " + .bw$ + " | 0 | 0"
    elsif .bail = 0 and .id$ = "spiral"
        @num: "p_spiral_spirals", 2, 1, 3
        .sp$ = string$ (round (num.v))
        @num: "p_spiral_semitones", 6, 3, 12
        @s: num.v
        .st$ = s.s$
        @num: "p_spiral_acceleration", 1.5, 1, 2
        @s: num.v
        .ac$ = s.s$
        @num: "p_spiral_floor", 75, 50, 400
        .fl = num.v
        @num: "p_spiral_ceiling", 800, 100, 1200
        .ce = min (num.v, 0.449 * .srcSR)
        if .ce <= .fl * 1.5
            .ce = min (0.449 * .srcSR, .fl * 4)
        endif
        @s: .fl
        .fl$ = s.s$
        @s: .ce
        .ce$ = s.s$
        .args$ = "Manual (configure below) | " + .sp$ + " | " + .st$ + " | " + .ac$
            ... + " | 0.005 | " + .fl$ + " | " + .ce$ + " | 0 | 0"
    elsif .bail = 0 and .id$ = "speeddev"
        # Child v0.7 preset MAX MC Deviate overrides Mode, Processing engine,
        # Output format, Random seed and speed bounds.  Only deviation d
        # remains under our control. Eight constant channel speed factors
        # are freshly drawn in [1-d,1+d] on every run; duration = D/s.
        @num: "p_speeddev_deviation", 0.15, 0.0, 0.45
        .deviation = num.v
        # Hard cap: the slowest possible channel plays at 1-d. Ensure
        # worst-case answer duration cannot exceed Max_response_s.
        if .srcDur >= maxResponse
            .bail = 1
            .msg$ = "MAX MC source must be shorter than " + fixed$ (maxResponse, 1) + " s (duration cap)"
        endif
        .safeMax = max (0, min (0.45, 1 - .srcDur / maxResponse))
        if .deviation > .safeMax
            clampNotes$ = clampNotes$ + "speed deviation reduced for the duration cap  "
            .deviation = .safeMax
        endif
        @s: .deviation
        .dv$ = s.s$
        @s: .srcSR
        .sr$ = s.s$
        .args$ = "MAX MC Deviate (fresh random every run) | Random deviation | "
            ... + "MC-style varispeed (pitch follows speed) | " + .dv$ + " | 0.85 0.88 0.91 0.94 1.06 1.09 1.12 1.15"
            ... + " | 0.80 | 1.20 | 0 | 75 600 | 0 | " + .sr$
            ... + " | MC stereo mix (L: odd Ch1/3/5/7, R: even Ch2/4/6/8) | 0.95 | 0 | 0"
    elsif .bail = 0 and .id$ = "groove"
        @num: "p_groove_bars", 2, 1, 4
        .b = round (num.v)
        .bars$ = if .b = 1 then "1 bar" else if .b = 2 then "2 bars" else "4 bars" fi fi
        @getStr: "p_groove_pattern"
        .pat$ = getStr.v$
        if .pat$ <> "Standard 4/4" and .pat$ <> "Syncopated Funk" and .pat$ <> "Breakbeat"
            ... and .pat$ <> "Half-time Feel" and .pat$ <> "Double-time Feel" and .pat$ <> "Sparse Minimal"
            clampNotes$ = clampNotes$ + "pattern '" + .pat$ + "' not allowed -> Standard 4/4  "
            .pat$ = "Standard 4/4"
        endif
        @num: "p_groove_tempo", 100, 60, 180
        @s: num.v
        .te$ = s.s$
        @num: "p_groove_onset_thr_db", -20, -40, 0
        @s: num.v
        .ot$ = s.s$
        @num: "p_groove_min_silence", 0.05, 0.02, 0.2
        @s: num.v
        .si$ = s.s$
        @num: "p_groove_density", 0.6, 0, 1
        @s: num.v
        .dn$ = s.s$
        .args$ = .bars$ + " | " + .pat$ + " | " + .te$ + " | " + .ot$ + " | " + .si$
            ... + " | 0.15 | " + .dn$ + " | 0.12 | 0.002 | 0.05 | 1.2 | 1 | 0 | 0"
    endif

    if .bail = 0
        if diagnostics
            @log: "    " + .id$ + " args: " + .args$
        endif
        if clampNotes$ <> ""
            @log: "    validated: " + clampNotes$
        endif
        # watermark: every object the child creates has a higher id
        .mark = Create Sound from formula: "crmark", 1, 0, 0.001, 1000, "0"
        removeObject: .mark
        random_initializeWithSeedUnsafelyButPredictably (.seed)
        selectObject: .work
        @now
        .t0 = now.t
        if .id$ = "paulstretch"
            nocheck runScript: tPath$[.k], "Custom", "Balanced (downsample to 22 kHz)",
                ... .a3$, .a4$, .a5$, .a6$, .a7$, "0", "0"
        elsif .id$ = "markov"
            nocheck runScript: tPath$[.k], "Manual", .gs$, "0.5", string$ (.kk), "First Order",
                ... .rnd$, .od$, "0.5", "0", "0.1", .dv$, .dc$, string$ (.seed), "0", "0"
        elsif .id$ = "mds"
            # Play_result = 0; Draw_visualization = 0 (11th argument).
            nocheck runScript: tPath$[.k], .th$, .ms$, .mn$, "MFCC (Timbre/Spectral Shape)",
                ... "5500", "5", "12", "Nearest neighbor chain (most similar next)", .bw$, "0", "0"
        elsif .id$ = "spiral"
            nocheck runScript: tPath$[.k], "Manual (configure below)", .sp$, .st$, .ac$,
                ... "0.005", .fl$, .ce$, "0", "0"
        elsif .id$ = "speeddev"
            # v0.7 preset 8 forces random constant-per-channel MC varispeed,
            # odd/even MC stereo, and a fresh random seed each time.
            # 15 positional args; pitch range is checked but ignored by MC engine.
            nocheck runScript: tPath$[.k], "MAX MC Deviate (fresh random every run)",
                ... "Random deviation", "MC-style varispeed (pitch follows speed)",
                ... .dv$, "0.85 0.88 0.91 0.94 1.06 1.09 1.12 1.15",
                ... "0.80", "1.20", "0", "75 600", "0", .sr$,
                ... "MC stereo mix (L: odd Ch1/3/5/7, R: even Ch2/4/6/8)",
                ... "0.95", "0", "0"
        elsif .id$ = "groove"
            nocheck runScript: tPath$[.k], .bars$, .pat$, .te$, .ot$, .si$, "0.15", .dn$,
                ... "0.12", "0.002", "0.05", "1.2", "1", "0", "0"
        endif
        @now
        .sec = if hasClock then now.t - .t0 else undefined fi
        random_initializeSafelyAndUnpredictably ()
        @restoreInfo

        # ---- identify the output: newer than the watermark AND named by
        #      this child from this work copy; everything else it left is removed
        .prefix$ = "Sound " + .workName$ + tStem$[.k]
        .found = 0
        select all
        .nAll = numberOfSelected ()
        for .i to .nAll
            .ids[.i] = selected (.i)
        endfor
        for .i to .nAll
            if .ids[.i] > .mark
                selectObject: .ids[.i]
                .nm$ = selected$ ()
                if left$ (.nm$, length (.prefix$)) = .prefix$ and .ids[.i] > .found
                    .found = .ids[.i]
                endif
            endif
        endfor
        .leftovers = 0
        for .i to .nAll
            if .ids[.i] > .mark and .ids[.i] <> .found
                removeObject: .ids[.i]
                .leftovers += 1
            endif
        endfor
        if .leftovers > 0
            @log: "    removed " + string$ (.leftovers) + " object(s) left by the child script"
        endif
        removeObject: .work
        .haveWork = 0

        if .found = 0
            .msg$ = "no output Sound named " + .workName$ + tStem$[.k] + "... (the script stopped with an error)"
        else
            selectObject: .found
            .dur = Get total duration
            .rms = Get root-mean-square: 0, 0
            .pk = Get absolute extremum: 0, 0, "None"
            if .dur <= 0 or .rms = undefined or .pk = undefined
                .msg$ = "output is invalid"
                removeObject: .found
            elsif .rms < 1e-5
                .msg$ = "output is silent (rms " + fixed$ (.rms, 7) + ")"
                removeObject: .found
            else
                .result = .found
                .msg$ = "ok " + fixed$ (.dur, 2) + " s, rms " + fixed$ (20 * log10 (.rms), 1) + " dBFS"
            endif
        endif
    endif
    if .haveWork
        removeObject: .work
    endif
endproc

# ============================================================
# RENDER WITH FALLBACK (turn-taking, selected Sounds and render mode)
#   runs whitelisted transformation .k; in automatic mode, if it fails,
#   tries the first other eligible candidate from the ranking (logged).
#   sets .answer (0 = failed), .usedId$, .sec, .msg$
# ============================================================
procedure renderWithFallback: .k, .phrase, .tag$, .automatic, .ranking$
    .answer = 0
    .usedId$ = "passthrough"
    .sec = 0
    @getStr: "score_" + tId$[.k]
    @log: "TRANSFORMING with " + tId$[.k] + " (score " + getStr.v$ + ")"
    @status: "PROCESSING", tDisplay$[.k]
    @runT: .k, .phrase, .tag$
    .sec = runT.sec
    .msg$ = tId$[.k] + ": " + runT.msg$
    @log: "  " + .msg$
    if runT.result
        .answer = runT.result
        .usedId$ = tId$[.k]
    elsif .automatic
        # automatic mode: next eligible candidate above threshold, logged
        .rest$ = .ranking$ + ","
        .tried = 0
        while .answer = 0 and .rest$ <> ""
            .c = index (.rest$, ",")
            .cand$ = left$ (.rest$, .c - 1)
            .rest$ = mid$ (.rest$, .c + 1, length (.rest$) - .c)
            .kk = 0
            for .k2 to nT
                if .cand$ = tId$[.k2] and .cand$ <> tId$[.k]
                    .kk = .k2
                endif
            endfor
            if .kk > 0 and .tried = 0
                .tried = 1
                @log: "FALLBACK: " + tId$[.k] + " failed, trying runner-up " + tId$[.kk]
                @status: "PROCESSING", tDisplay$[.kk]
                @runT: .kk, .phrase, .tag$ + "b"
                .sec = .sec + runT.sec
                .msg$ = .msg$ + " | fallback " + tId$[.kk] + ": " + runT.msg$
                @log: "  " + tId$[.kk] + ": " + runT.msg$
                if runT.result
                    .answer = runT.result
                    .usedId$ = tId$[.kk]
                endif
            endif
        endwhile
    endif
endproc

# ============================================================
# ONE TURN: load phrase, run the chosen transformation(s), play
# (uses the session globals; called once per question)
# ============================================================
procedure turn
    # ---- load phrase (the musician's audio is kept, never modified) ----
    if isLive
        phrase = Read from file: qwav$
        Rename: "crq_" + tag$
    else
        selectObject: selSound[cyc]
        phrase = Copy: "crq_" + tag$
    endif
    selectObject: phrase
    qDur = Get total duration
    @log: "Phrase " + fixed$ (qDur, 2) + " s   " + extractLine$ (meta$, newline$ + "morphology=")
    if isLive
        @log: "  ended by " + extractLine$ (meta$, newline$ + "ended_by=") + ", noise floor "
            ... + extractLine$ (meta$, newline$ + "noise_floor_dbfs=") + " dBFS, false triggers "
            ... + extractLine$ (meta$, newline$ + "false_triggers=")
    endif
    # Detailed report remains a Python-side artifact; do not flood the performer UI.

    # ---- which transformations to run ----
    sel$ = extractLine$ (meta$, newline$ + "selected=")
    ranking$ = extractLine$ (meta$, newline$ + "ranking=")
    nRun = 0
    if sweep
        for k to nT
            nRun += 1
            runK[nRun] = k
        endfor
    else
        selK = 0
        for k to nT
            if sel$ = tId$[k]
                selK = k
            endif
        endfor
        if selK > 0
            nRun = 1
            runK[1] = selK
        endif
    endif
    ambiguous$ = extractLine$ (meta$, newline$ + "ambiguous=")
    if ambiguous$ <> "" and not diagnostics
        @log: "  ambiguous decision: " + ambiguous$
    endif
    warning$ = extractLine$ (meta$, newline$ + "warning=")
    if warning$ <> ""
        @log: "  " + warning$
    endif

    # ---- answer(s) ----
    for r to max (nRun, 1)
        answer = 0
        usedId$ = "passthrough"
        praatSec = 0
        if nRun = 0
            @log: "No transformation reached its confidence threshold - answering with the phrase itself."
        else
            k = runK[r]
            if sweep
                @getStr: "score_" + tId$[k]
                @log: "TRANSFORMING with " + tId$[k] + " (score " + getStr.v$ + ")"
                @status: "PROCESSING", tDisplay$[k]
                @runT: k, phrase, tag$
                praatSec = runT.sec
                @log: "  " + tId$[k] + ": " + runT.msg$
                if runT.result
                    answer = runT.result
                    usedId$ = tId$[k]
                endif
            else
                isAuto = transformation = 1
                @renderWithFallback: k, phrase, tag$, isAuto, ranking$
                answer = renderWithFallback.answer
                usedId$ = renderWithFallback.usedId$
                praatSec = renderWithFallback.sec
            endif
            if answer = 0 and not sweep
                @log: "No valid output - answering with the untransformed phrase (logged fallback)."
            endif
        endif
        if answer = 0 and sweep
            # test sweep: a failed pairing is reported, not answered
            @log: "  (no answer object for " + tId$[k] + ")"
            summary$ = summary$ + "  " + tag$ + "  " + tId$[k] + "   FAILED: " + runT.msg$ + newline$
        else
            if answer = 0
                selectObject: phrase
                answer = Copy: "cra_" + tag$ + "_passthrough"
            else
                selectObject: answer
                Rename: "cra_" + tag$ + "_" + usedId$
            endif
            selectObject: answer
            aDur = Get total duration

            # ---- timing ----
            @now
            tPlay = now.t
            tEnd = number (extractLine$ (meta$, newline$ + "t_phrase_end_epoch="))
            tWritten = number (extractLine$ (meta$, newline$ + "t_written_epoch="))
            detect = number (extractLine$ (meta$, newline$ + "t_detect_delay="))
            pyFeat = number (extractLine$ (meta$, newline$ + "t_features="))
            pySel = number (extractLine$ (meta$, newline$ + "t_select="))
            total = undefined
            handoff = undefined
            if hasClock and tEnd <> undefined
                if abs (tPlay - tEnd) < 3600
                    total = tPlay - tEnd
                endif
            endif
            if hasClock and tWritten <> undefined
                if abs (tBack - tWritten) < 3600
                    handoff = tBack - tWritten
                endif
            endif
            @fmt: detect, 3
            d$ = fmt.s$
            @fmt: pyFeat + pySel, 3
            p$ = fmt.s$
            @fmt: praatSec, 2
            q$ = fmt.s$
            @fmt: handoff, 3
            h$ = fmt.s$
            @fmt: total, 2
            tt$ = fmt.s$
            @log: "Timing: end detection " + d$ + " s | python analysis " + p$ + " s | python exit "
                ... + h$ + " s | Praat render " + q$ + " s | phrase end -> answer " + tt$ + " s"
            nDone += 1
            summary$ = summary$ + "  " + tag$ + "  " + usedId$ + "   in " + fixed$ (qDur, 2) + " s -> out "
                ... + fixed$ (aDur, 2) + " s   delay " + tt$ + " s" + newline$

            if play_response
                # The final chosen process can differ from the first candidate.
                .chosenName$ = "Original phrase"
                for .p to nT
                    if usedId$ = tId$[.p]
                        .chosenName$ = tDisplay$[.p]
                    endif
                endfor
                @status: "PLAYING", .chosenName$ + "  (" + fixed$ (aDur, 1) + " s)"
                selectObject: answer
                Play
            endif
        endif
    endfor
endproc

# ============================================================
# CONTINUOUS MODE (v0.2.0): launch the persistent engine (detached),
# then poll its status file.  Display: Demo window (refreshed every
# 0.2 s, STOP button, Esc or S) + Info window on every change.
# ============================================================
procedure continuousSession
    .self$ = defaultDirectory$ + "/AudioTools_CallResponse.praat"
    if not fileReadable (.self$)
        .self$ = pluginRoot$ + "/Vector Chain/AudioTools_CallResponse.praat"
    endif
    if not fileReadable (.self$)
        @cleanup
        exitScript: "Cannot locate AudioTools_CallResponse.praat for headless rendering." + newline$
            ... + "Keep this script in plugin_AudioTools/Vector Chain/ under its original name."
    endif
    # v0.3.0: the debug log lives INSIDE the session and is deleted with it
    debugPath$ = if debug_log then session$ + "/engine_debug.log" else "none" fi
    # ---- sonic memory arguments ----
    .rm$ = "hybrid"
    if not sonic_memory or response_mode = 2
        .rm$ = "transform"
    elsif response_mode = 3
        .rm$ = "recall"
    elsif response_mode = 4
        .rm$ = "recall_transform"
    elsif response_mode = 5
        .rm$ = "corpus_only"
    endif
    .sim$ = "hybrid"
    if similarity_mode = 2
        .sim$ = "timbre"
    elsif similarity_mode = 3
        .sim$ = "pitch"
    elsif similarity_mode = 4
        .sim$ = "rhythm"
    elsif similarity_mode = 5
        .sim$ = "envelope"
    elsif similarity_mode = 6
        .sim$ = "contrast"
    endif
    @argPath: corpus_C_folder$
    .cdir$ = argPath.p$
    .useC = use_preloaded_corpus_C and .cdir$ <> ""
    if .useC and sonic_memory and not folderExists (.cdir$)
        @cleanup
        exitScript: "Corpus_C_folder does not exist:" + newline$ + .cdir$
    endif
    if not .useC
        .cdir$ = "none"
    endif
    @argPath: praatExe$
    .praat$ = if argPath.p$ = "" then "none" else argPath.p$ fi
    .in$ = if input_device$ = "" then "default" else input_device$ fi
    .out$ = if output_device$ = "" then "default" else output_device$ fi
    .overflow$ = if overflow_policy = 1 then "drop_oldest" else "drop_newest" fi
    @log: "Engine: continuous, in '" + .in$ + "', out '" + .out$ + "', " + fixed$ (sample_rate, 0)
        ... + " Hz, pending <= " + string$ (max_pending_phrases) + ", responses <= "
        ... + string$ (max_pending_responses) + ", " + .overflow$
    # Ordinary blocking call: "launch" starts the engine DETACHED and returns
    # at once.  ("asynchronous runSubprocess" never ran the engine on Windows.)
    # v0.4.4: the engine arguments go through a FILE (one per line).  A
    # long command line was cut off by runSubprocess on Windows (arguments
    # after about 1 KB were lost or emptied).  The last line marks a
    # complete file; Python starts the engine with a proper argument list.
    argsFile$ = session$ + "/engine_args.txt"
    writeFileLine: argsFile$, "# AudioTools Call & Response engine arguments"
    appendFileLine: argsFile$, "--session"
    appendFileLine: argsFile$, session$
    appendFileLine: argsFile$, "--script"
    appendFileLine: argsFile$, .self$
    appendFileLine: argsFile$, "--praat"
    appendFileLine: argsFile$, .praat$
    appendFileLine: argsFile$, "--plugin-root"
    appendFileLine: argsFile$, pluginRoot$
    appendFileLine: argsFile$, "--force"
    appendFileLine: argsFile$, force$
    appendFileLine: argsFile$, "--device"
    appendFileLine: argsFile$, .in$
    appendFileLine: argsFile$, "--output-device"
    appendFileLine: argsFile$, .out$
    appendFileLine: argsFile$, "--sr"
    appendFileLine: argsFile$, fixed$ (sample_rate, 0)
    appendFileLine: argsFile$, "--channels"
    appendFileLine: argsFile$, string$ (channels)
    appendFileLine: argsFile$, "--sensitivity"
    appendFileLine: argsFile$, fixed$ (sensitivity_dB, 3)
    appendFileLine: argsFile$, "--min-phrase"
    appendFileLine: argsFile$, fixed$ (min_phrase_s, 3)
    appendFileLine: argsFile$, "--end-silence"
    appendFileLine: argsFile$, fixed$ (end_silence_s, 3)
    appendFileLine: argsFile$, "--max-phrase"
    appendFileLine: argsFile$, fixed$ (max_phrase_s, 3)
    appendFileLine: argsFile$, "--preroll"
    appendFileLine: argsFile$, fixed$ (preroll, 3)
    appendFileLine: argsFile$, "--max-pending"
    appendFileLine: argsFile$, string$ (max_pending_phrases)
    appendFileLine: argsFile$, "--max-responses"
    appendFileLine: argsFile$, string$ (max_pending_responses)
    appendFileLine: argsFile$, "--overflow"
    appendFileLine: argsFile$, .overflow$
    appendFileLine: argsFile$, "--max-response"
    appendFileLine: argsFile$, fixed$ (max_response_s, 3)
    appendFileLine: argsFile$, "--session-minutes"
    appendFileLine: argsFile$, fixed$ (session_minutes, 3)
    appendFileLine: argsFile$, "--idle-stop"
    appendFileLine: argsFile$, fixed$ (idle_stop_s, 3)
    appendFileLine: argsFile$, "--leak-guard"
    appendFileLine: argsFile$, string$ (leakage_guard)
    appendFileLine: argsFile$, "--play"
    appendFileLine: argsFile$, string$ (play_response)
    appendFileLine: argsFile$, "--debug-log"
    appendFileLine: argsFile$, debugPath$
    appendFileLine: argsFile$, "--memory"
    appendFileLine: argsFile$, string$ (sonic_memory)
    appendFileLine: argsFile$, "--response-mode"
    appendFileLine: argsFile$, .rm$
    appendFileLine: argsFile$, "--use-a"
    appendFileLine: argsFile$, string$ (use_live_corpus_A)
    appendFileLine: argsFile$, "--use-b"
    appendFileLine: argsFile$, string$ (use_processed_corpus_B)
    appendFileLine: argsFile$, "--use-c"
    appendFileLine: argsFile$, string$ (.useC)
    appendFileLine: argsFile$, "--corpus-c"
    appendFileLine: argsFile$, .cdir$
    appendFileLine: argsFile$, "--sim-mode"
    appendFileLine: argsFile$, .sim$
    appendFileLine: argsFile$, "--min-sim"
    appendFileLine: argsFile$, fixed$ (minimum_similarity, 3)
    appendFileLine: argsFile$, "--w-live"
    appendFileLine: argsFile$, fixed$ (weight_A_live, 3)
    appendFileLine: argsFile$, "--w-processed"
    appendFileLine: argsFile$, fixed$ (weight_B_processed, 3)
    appendFileLine: argsFile$, "--w-preloaded"
    appendFileLine: argsFile$, fixed$ (weight_C_preloaded, 3)
    appendFileLine: argsFile$, "--p-transform"
    appendFileLine: argsFile$, fixed$ (weight_transform, 3)
    appendFileLine: argsFile$, "--p-recall"
    appendFileLine: argsFile$, fixed$ (weight_recall, 3)
    appendFileLine: argsFile$, "--p-recall-transform"
    appendFileLine: argsFile$, fixed$ (weight_recall_transform, 3)
    appendFileLine: argsFile$, "--max-generation"
    appendFileLine: argsFile$, string$ (max_generation)
    appendFileLine: argsFile$, "--max-live"
    appendFileLine: argsFile$, string$ (max_live_phrases)
    appendFileLine: argsFile$, "--max-processed"
    appendFileLine: argsFile$, string$ (max_processed_responses)
    appendFileLine: argsFile$, "--max-ram-min"
    appendFileLine: argsFile$, fixed$ (max_audio_memory_min, 3)
    appendFileLine: argsFile$, "--max-item-s"
    appendFileLine: argsFile$, fixed$ (max_item_s, 3)
    appendFileLine: argsFile$, "--candidates"
    appendFileLine: argsFile$, string$ (candidates)
    appendFileLine: argsFile$, "--evolving"
    appendFileLine: argsFile$, string$ (evolving_memory)
    appendFileLine: argsFile$, "--layered"
    appendFileLine: argsFile$, string$ (layered_response)
    appendFileLine: argsFile$, "--recent-exclude"
    appendFileLine: argsFile$, string$ (exclude_recent_phrases)
    appendFileLine: argsFile$, "--cooldown"
    appendFileLine: argsFile$, string$ (cooldown_recalls)
    appendFileLine: argsFile$, "--same-family"
    appendFileLine: argsFile$, string$ (same_family_exclusion)
    appendFileLine: argsFile$, "--polyphony"
    appendFileLine: argsFile$, string$ (polyphony)
    appendFileLine: argsFile$, "--max-voices"
    appendFileLine: argsFile$, string$ (max_voices)
    appendFileLine: argsFile$, "--density"
    appendFileLine: argsFile$, fixed$ (polyphonic_density, 3)
    appendFileLine: argsFile$, "--background"
    appendFileLine: argsFile$, string$ (background_layer)
    appendFileLine: argsFile$, "--background-db"
    appendFileLine: argsFile$, fixed$ (background_level_dB, 2)
    appendFileLine: argsFile$, "--stereo-width"
    appendFileLine: argsFile$, fixed$ (stereo_width, 3)
    appendFileLine: argsFile$, "--movement"
    appendFileLine: argsFile$, fixed$ (spatial_movement, 3)
    appendFileLine: argsFile$, "--pan-variation"
    appendFileLine: argsFile$, fixed$ (pan_variation, 3)
    appendFileLine: argsFile$, "--fade-in-ms"
    appendFileLine: argsFile$, fixed$ (fade_in_ms, 2)
    appendFileLine: argsFile$, "--fade-out-ms"
    appendFileLine: argsFile$, fixed$ (fade_out_ms, 2)
    appendFileLine: argsFile$, "--preserve-transients"
    appendFileLine: argsFile$, string$ (preserve_transients)
    appendFileLine: argsFile$, "--level-match"
    appendFileLine: argsFile$, string$ (level_matching)
    appendFileLine: argsFile$, "--follow-input"
    appendFileLine: argsFile$, string$ (follow_live_input)
    appendFileLine: argsFile$, "--follow-range"
    appendFileLine: argsFile$, fixed$ (follow_range_dB, 2)
    appendFileLine: argsFile$, "--corpus-c-db"
    appendFileLine: argsFile$, fixed$ (corpus_C_balance_dB, 2)
    appendFileLine: argsFile$, "--influence-depth"
    appendFileLine: argsFile$, string$ (max (1, min (8, influence_depth)))
    appendFileLine: argsFile$, "--influence-decay"
    appendFileLine: argsFile$, fixed$ (max (0, min (1, influence_decay)), 3)
    appendFileLine: argsFile$, "--trend-weight"
    appendFileLine: argsFile$, fixed$ (max (0, min (1, trend_weight)), 3)
    appendFileLine: argsFile$, "--layer-shape"
    appendFileLine: argsFile$, if layer_shape = 2 then "excerpt" else "whole" fi
    appendFileLine: argsFile$, "#end"
    runSubprocess: python$, pyScript$, "launch", "--args-file", argsFile$

    .statusFile$ = session$ + "/status.txt"
    .stopFile$ = session$ + "/stop.request"
    .aliveFile$ = session$ + "/praat_alive.txt"
    .t0 = clock ()
    .lastFrame$ = ""
    .lastBeat = -10
    .running = 1
    .stopSent = 0
    .tStop = 0
    .lastMsg$ = ""
    .tChange = .t0
    .everGot = 0
    .lastGood = .t0
    statusReadFailures = 0
    lastShown$ = ""
    engineState$ = "starting"
    st$ = newline$ + "state=starting" + newline$
    stopNote$ = ""
    while .running
        sleep (0.2)
        .now = clock ()
        if .now - .lastBeat >= 1
            # v0.3.2: a failed heartbeat write (file briefly locked) is
            # simply retried next second - it never stops the session
            nocheck writeFileLine: .aliveFile$, fixed$ (.now - .t0, 2)
            .lastBeat = .now
        endif
        # v0.3.2: the engine replaces status.txt up to 10x per second; on
        # Windows a read can collide with that (error 13).  A failed or
        # incomplete read is ignored and the last complete status is kept.
        .got = 0
        @safeRead: .statusFile$
        if safeRead.ok
            .raw$ = newline$ + safeRead.text$
            if index (.raw$, newline$ + "state=") > 0 and index (.raw$, newline$ + "end=1") > 0
                st$ = .raw$
                .got = 1
            endif
        endif
        if .got
            .everGot = 1
            .lastGood = .now
        elsif fileReadable (.statusFile$) or .everGot
            statusReadFailures += 1
        endif
        if .got
            engineState$ = extractLine$ (st$, newline$ + "state=")
            .msgNow$ = extractLine$ (st$, newline$ + "message=")
            if .msgNow$ <> .lastMsg$
                .lastMsg$ = .msgNow$
                .tChange = .now
            endif
            if engineState$ = "stopped" or engineState$ = "error"
                .running = 0
            elsif engineState$ = "starting" and .now - .tChange > 60
                # v0.3.0: a start-up stage (e.g. indexing a large Corpus C,
                # which reports its progress) is an error only when the
                # engine's status has not changed for 60 s
                engineState$ = "error"
                stopNote$ = "the engine start-up stalled for 60 s ("
                    ... + .msgNow$ + ")"
                st$ = newline$ + "state=error" + newline$ + "message=" + stopNote$ + newline$
                nocheck writeFileLine: .stopFile$, "stop"
                .running = 0
            endif
        elsif .everGot and .now - .lastGood > 30
            # v0.3.2: the engine did run, but no complete status could be
            # read for 30 s (not a start-up failure)
            engineState$ = "error"
            stopNote$ = "the engine status could not be read for 30 s (" + string$ (statusReadFailures)
                ... + " failed reads)"
            st$ = newline$ + "state=error" + newline$ + "message=" + stopNote$ + newline$
            nocheck writeFileLine: .stopFile$, "stop"
            .running = 0
        elsif not .everGot and .now - .t0 > 20
            # the engine writes its first status before any import, so this
            # means the engine process never ran at all
            engineState$ = "error"
            .how$ = "no launch record"
            @safeRead: session$ + "/launch.txt"
            if safeRead.ok
                .how$ = "launched as " + replace$ (safeRead.text$, newline$, " ", 0)
            endif
            stopNote$ = "the engine process never ran (no status file after 20 s; " + .how$ + ")"
            st$ = newline$ + "state=error" + newline$ + "message=" + stopNote$ + newline$
            nocheck writeFileLine: .stopFile$, "stop"
            .running = 0
        endif
        if .stopSent and .running and .now - .tStop > 15
            stopNote$ = "the engine did not confirm the stop within 15 s"
            .running = 0
        endif
        if not headless
            @stField: "graph"
            if stField.v$ <> "" and stField.v$ <> "off" and stField.v$ <> "0"
                ... and stField.v$ <> graphVer$
                @readGraph: session$ + "/graph.tsv"
                if readGraph.ok
                    graphVer$ = stField.v$
                endif
            endif
        endif
        @buildDisplay: .stopSent and .running
        if display$ <> lastShown$
            writeInfoLine: display$
            lastShown$ = display$
        endif
        if not headless
            # redraw only when the picture changes (level bar in 2 dB steps)
            @stField: "input_db"
            .lv = number (stField.v$)
            .lvq = if .lv = undefined then -99 else round (.lv / 2) fi
            if graphView and graphTable
                .frame$ = displayCore$ + "|map " + graphVer$ + "|" + string$ (.stopSent)
            else
                .frame$ = display$ + string$ (.lvq) + string$ (.stopSent) + "|status"
            endif
            if .frame$ <> .lastFrame$
                @drawDemo: .stopSent and .running
                .lastFrame$ = .frame$
            else
                demoShow ()
            endif
            if .running and not .stopSent
                # (1) Linux: demoShow has already handled a click -> flag only
                @demoStopHit
                .hit = demoStopHit.hit
                # (2) all platforms: demoPeekInput delivers clicks/keys and keeps
                #     Windows from flagging Praat as "Not responding".  Praat 7.0
                #     then shows "Mouse click not completely handled"; after OK
                #     the click is still reported (verified in Praat 7.0 source
                #     and GUI test) and the session stops.
                if not .hit
                    demo Font size: 10
                    demo Select inner viewport: 0, 100, 0, 100
                    demo Axes: 0, 100, 0, 100
                    if demoPeekInput ()
                        @demoStopHit
                        .hit = demoStopHit.hit
                    endif
                endif
                if .hit
                    nocheck writeFileLine: .stopFile$, "stop"
                    .stopSent = 1
                    .tStop = .now
                endif
            endif
        endif
    endwhile
    if graphTable
        removeObject: graphTable
        graphTable = 0
    endif
endproc

procedure demoStopHit
    .hit = 0
    demo Font size: 10
    demo Select inner viewport: 0, 100, 0, 100
    demo Axes: 0, 100, 0, 100
    if demoClicked ()
        .hit = demoClickedIn (36, 64, 3, 13)
    elsif demoKeyPressed ()
        .key$ = demoKey$ ()
        .hit = .key$ = unicode$ (27) or .key$ = "s" or .key$ = "S"
        if .key$ = "g" or .key$ = "G"
            graphView = 1 - graphView
        endif
    endif
endproc

procedure argPath: .in$
    # v0.4.3: a path typed by the user, made safe as a subprocess argument.
    # On Windows a trailing backslash escapes the closing quote of the
    # argument and merges the following arguments.  Forward slashes work
    # for Python and Praat on every platform.
    .p$ = replace_regex$ (.in$, "^\s+|\s+$", "", 0)
    .p$ = replace_regex$ (.p$, "^""|""$", "", 0)
    .p$ = replace$ (.p$, "\", "/", 0)
    if not (length (.p$) = 3 and right$ (.p$, 2) = ":/") and .p$ <> "/"
        .p$ = replace_regex$ (.p$, "/+$", "", 0)
    endif
endproc

procedure safeRead: .path$
    # v0.3.2: read a text file WITHOUT stopping the script when the read
    # fails (Windows sharing violation / error 13, file being replaced,
    # missing file).  .ok = 0 on failure.  Uses a temporary Strings object
    # (removed at once); the Objects-window selection is cleared.
    .ok = 0
    .text$ = ""
    selectObject ( )
    nocheck Read Strings from raw text file: .path$
    if numberOfSelected ("Strings") = 1
        .n = Get number of strings
        for .i to .n
            .line$ = Get string: .i
            .text$ = .text$ + .line$ + newline$
        endfor
        Remove
        .ok = 1
    endif
endproc

procedure stField: .key$
    .v$ = extractLine$ (st$, newline$ + .key$ + "=")
endproc

procedure buildDisplay: .stopping
    @stField: "playing"
    .play$ = stField.v$
    @stField: "processing"
    .proc$ = stField.v$
    @stField: "pending"
    .pend$ = stField.v$
    @stField: "phrase"
    .phrase$ = stField.v$
    @stField: "leak_warning"
    .leak$ = stField.v$
    @stField: "message"
    .msg$ = stField.v$
    display$ = "AudioTools Call & Response v" + version$ + newline$ + newline$
        ... + "MODE: CONTINUOUS   PRESET: " + presetName$ + newline$
    if engineState$ = "starting"
        display$ = display$ + "STARTING: " + .msg$ + newline$
    elsif engineState$ = "running" and .stopping
        display$ = display$ + "STOPPING" + newline$
    elsif engineState$ = "running" or engineState$ = "stopping"
        # v0.4.12: the performer's side first, then the system's side
        @perfState
        display$ = display$ + newline$ + "YOUR PERFORMANCE: " + perfState.head$ + newline$
            ... + "  " + perfState.sub$ + newline$ + newline$
        @responseLine
        display$ = display$ + "SYSTEM RESPONSE (independent): " + responseLine.txt$ + newline$
        display$ = display$ + "PENDING: " + .pend$ + newline$
        @voiceLine
        if voiceLine.txt$ <> ""
            display$ = display$ + voiceLine.txt$ + newline$
        endif
        @memoryLines
        display$ = display$ + memoryLines.txt$
        if .leak$ = "1"
            display$ = display$ + "WARNING: the microphone hears the answers - use headphones" + newline$
        endif
        displayCore$ = display$
        @detLine
        if detLine.txt$ <> ""
            display$ = display$ + detLine.txt$ + newline$
        endif
        if detLine.last$ <> ""
            display$ = display$ + detLine.last$ + newline$
        endif
    elsif not cleanupDone
        # v0.3.0: never report STOPPED before the temporary files are gone
        display$ = display$ + "STOPPING - removing temporary files" + newline$
    else
        .why$ = if stopNote$ <> "" then stopNote$ else .msg$ fi
        if engineState$ = "error"
            display$ = display$ + "STOPPED - ERROR: " + .why$ + newline$
        else
            display$ = display$ + "STOPPED - " + .why$ + newline$
        endif
        display$ = display$ + cleanupReport$ + newline$
    endif
endproc

procedure perfState
    # v0.4.12: what the performer can do now, from the detector's state
    .head$ = "PLAY WHEN READY"
    .sub$ = "The microphone is listening - start at any moment, also while answers sound."
    .short$ = "start at any moment"
    .col$ = "{0.15, 0.55, 0.25}"
    .kind$ = "ready"
    .q = 0
    .es = 0.6
    @stField: "det_state"
    .ds$ = stField.v$
    @stField: "det_event"
    .ev$ = stField.v$
    @stField: "det_event_age"
    .age = number (stField.v$)
    if .age = undefined
        .age = 99
    endif
    @stField: "quiet_s"
    .q = number (stField.v$)
    @stField: "end_silence"
    .es = number (stField.v$)
    if .q = undefined
        .q = 0
    endif
    if .es = undefined
        .es = 0.6
    endif
    if .ds$ = "calibrating"
        .head$ = "STAY QUIET"
        .sub$ = "Measuring the room for a moment - then play whenever you like."
        .short$ = "measuring the room"
        .col$ = "{0.35, 0.35, 0.50}"
        .kind$ = "calibrating"
    elsif .ds$ = "phrase"
        .head$ = "RECORDING YOUR PHRASE"
        .sub$ = "Stop playing for " + fixed$ (.es, 1) + " s when your gesture is complete."
        .short$ = "stop for " + fixed$ (.es, 1) + " s to end it"
        if index (.ev$, "split at") = 1 and .age <= 2
            .sub$ = "Long phrase: split at Max_phrase_s - keep playing, it continues."
            .short$ = "long phrase split - keep playing"
        endif
        .col$ = "{0.85, 0.38, 0.18}"
        .kind$ = "recording"
    elsif .ds$ = "done" or (index (.ev$, "phrase end") = 1 and .age <= 2)
        .head$ = "PHRASE CAPTURED"
        .sub$ = "The answer is coming - you can play again at any time."
        .short$ = "play again any time"
        .col$ = "{0.20, 0.48, 0.75}"
        .kind$ = "captured"
    elsif index (.ev$, "noise ignored") = 1 and .age <= 2
        .sub$ = "Background noise was ignored - play when ready."
    elsif index (.ev$, "too short") = 1 and .age <= 2
        .sub$ = "That was too short for a phrase - play when ready."
    endif
endproc

procedure responseLine
    # v0.4.12: the system's side, one line
    @stField: "playing"
    .play$ = stField.v$
    @stField: "processing"
    .proc$ = stField.v$
    @stField: "pending"
    .pend$ = stField.v$
    .txt$ = ""
    if .proc$ <> ""
        .txt$ = "PROCESSING: " + .proc$
    endif
    if .play$ <> ""
        .txt$ = if .txt$ = "" then "" else .txt$ + "   |   " fi + "PLAYING: " + .play$
    endif
    if .txt$ = ""
        .txt$ = if .pend$ = "0" or .pend$ = "" then "Silent - waiting for your phrase" else "Preparing an answer" fi
    endif
endproc

procedure detLine
    # v0.4.10: the detector in its own terms (rounded so the Info window
    # is not rewritten on every 0.1 dB)
    .txt$ = ""
    .last$ = ""
    @stField: "on_db"
    .on = number (stField.v$)
    if .on <> undefined
        @stField: "input_db"
        .in = number (stField.v$)
        @stField: "off_db"
        .off = number (stField.v$)
        @stField: "floor_db"
        .fl = number (stField.v$)
        @stField: "quiet_s"
        .q$ = stField.v$
        @stField: "end_silence"
        .es$ = stField.v$
        .in$ = if .in = undefined or .in < -99 then "-99" else fixed$ (.in, 0) fi
        .txt$ = "DETECTOR: input " + .in$ + " dB  |  start " + fixed$ (.on, 0) + "  |  end "
            ... + fixed$ (.off, 0) + "  |  floor " + fixed$ (.fl, 0) + "  |  quiet " + .q$ + " / " + .es$ + " s"
        # v0.4.11: the last detector event, for 3 s
        @stField: "det_event"
        .ev$ = stField.v$
        @stField: "det_event_age"
        .age = number (stField.v$)
        if .ev$ <> "" and .age <> undefined
            if .age <= 3
                .last$ = "LAST: " + .ev$
            endif
        endif
    endif
endproc

procedure voiceLine
    # v0.4.0: "VOICES: 3/4 (2 responses, 1 layer, background)"
    .txt$ = ""
    @stField: "voices"
    .n$ = stField.v$
    if .n$ = ""
        .n$ = "0"
    endif
    @stField: "max_voices"
    .mx$ = stField.v$
    @stField: "voices_fg"
    .fg$ = stField.v$
    @stField: "voices_sec"
    .sec$ = stField.v$
    @stField: "background"
    .bg$ = stField.v$
    @stField: "polyphony"
    if stField.v$ = "on"
        .s1$ = if .fg$ = "1" then "" else "s" fi
        .s2$ = if .sec$ = "1" then "" else "s" fi
        .txt$ = "VOICES: " + .n$ + "/" + .mx$ + " (" + .fg$ + " response" + .s1$ + ", "
            ... + .sec$ + " layer" + .s2$ + ", background " + .bg$ + ")"
    endif
    # v0.4.1: level offset when Follow_live_input is on
    @stField: "level_offset"
    if stField.v$ <> "" and stField.v$ <> "off"
        .lvl$ = "LEVEL: " + stField.v$ + " dB (follows input)"
        .txt$ = if .txt$ = "" then .lvl$ else .txt$ + "   " + .lvl$ fi
    endif
endproc

procedure memoryLines
    @stField: "memory"
    .on$ = stField.v$
    .txt$ = ""
    .line2$ = ""
    if .on$ = "on"
        @stField: "mem_live"
        .a$ = stField.v$
        @stField: "mem_processed"
        .b$ = stField.v$
        @stField: "mem_preloaded"
        .c$ = stField.v$
        .txt$ = "MEMORY: A " + .a$ + " | B " + .b$ + " | C " + .c$ + newline$
        @stField: "recall"
        .r$ = stField.v$
        @stField: "match"
        .m$ = stField.v$
        if .r$ <> ""
            .line2$ = "RECALL: " + .r$ + "   MATCH: " + .m$
            .txt$ = .txt$ + .line2$ + newline$
        endif
    elsif .on$ = "off"
        .txt$ = "MEMORY: OFF (Transform only)" + newline$
    endif
    @stField: "action"
    .act$ = stField.v$
    if .act$ <> ""
        .txt$ = .txt$ + "ACTION: " + .act$ + newline$
    endif
endproc

procedure dtext: .x, .y, .size, .colour$, .txt$
    demo Font size: .size
    demo Select inner viewport: 0, 100, 0, 100
    demo Axes: 0, 100, 0, 100
    demo Colour: .colour$
    demo Text: .x, "centre", .y, "half", .txt$
endproc

procedure drawDemo: .stopping
    if graphView and graphTable and engineState$ = "running" and not .stopping
        @drawGraphView
    else
        @drawStatusView: .stopping
    endif
endproc

procedure readGraph: .path$
    # v0.4.6: graph.tsv -> a Table (replaces the previous one).  Like
    # safeRead, a read that collides with the engine replacing the file is
    # simply skipped (.ok = 0) and the previous map stays.
    .ok = 0
    selectObject ( )
    nocheck Read Table from tab-separated file: .path$
    if numberOfSelected ("Table") = 1
        .new = selected ("Table")
        .nc = Get number of columns
        if .nc = 9
            if graphTable
                removeObject: graphTable
            endif
            graphTable = .new
            .ok = 1
        else
            removeObject: .new
        endif
    endif
endproc

procedure ltext: .x, .y, .size, .colour$, .txt$
    demo Font size: .size
    demo Select inner viewport: 0, 100, 0, 100
    demo Axes: 0, 100, 0, 100
    demo Colour: .colour$
    demo Text: .x, "left", .y, "half", .txt$
endproc

procedure drawGraphView
    # v0.4.6 memory map.  graph.tsv rows arrive in drawing order: regions,
    # similarity arcs (weakest first), action arcs (oldest first), points,
    # latest-phrase tick.  x and point sizes are 0..1 of the drawing width.
    .gx0 = 4
    .gw = 92
    .y0 = 51
    .h = 27
    demo Erase all
    demo Font size: 10
    demo Select inner viewport: 0, 100, 0, 100
    demo Axes: 0, 100, 0, 100
    demo Paint rectangle: "{0.97, 0.97, 0.97}", 0, 100, 0, 100
    @dtext: 50, 95, 18, "{0.20, 0.20, 0.30}", "##AudioTools Call & Response " + version$ + "##   memory map"
    # v0.4.12: the performer's state first, the system's response below it
    @perfState
    @dtext: 50, 89, 14, perfState.col$, "##" + perfState.head$ + "##  -  " + perfState.short$
    @responseLine
    .pl$ = responseLine.txt$
    if length (.pl$) > 110
        .pl$ = left$ (.pl$, 107) + "..."
    endif
    @dtext: 50, 84.5, 10, "{0.48, 0.36, 0.72}", "SYSTEM RESPONSE:  " + .pl$
    demo Select inner viewport: 0, 100, 0, 100
    demo Axes: 0, 100, 0, 100
    selectObject: graphTable
    .n = Get number of rows
    .based = 0
    for .i to .n
        selectObject: graphTable
        .k$ = Get value: .i, "kind"
        .x1 = Get value: .i, "x1"
        .x2 = Get value: .i, "x2"
        .side = Get value: .i, "side"
        .w = Get value: .i, "width"
        .r = Get value: .i, "r"
        .g = Get value: .i, "g"
        .b = Get value: .i, "b"
        .col$ = "{" + fixed$ (.r, 3) + ", " + fixed$ (.g, 3) + ", " + fixed$ (.b, 3) + "}"
        if .k$ <> "region" and not .based
            demo Colour: "{0.55, 0.55, 0.60}"
            demo Line width: 1
            demo Draw line: .gx0, .y0, .gx0 + .gw, .y0
            .based = 1
        endif
        if .k$ = "region"
            .lab$ = Get value: .i, "label"
            demo Paint rectangle: .col$, .gx0 + .gw * .x1, .gx0 + .gw * .x2, .y0 - .h - 1, .y0 + .h + 1
            @dtext: .gx0 + .gw * (.x1 + .x2) / 2, .y0 - .h - 3.5, 10, "{0.40, 0.40, 0.48}", .lab$
        elsif .k$ = "edge"
            .xa = .gx0 + .gw * min (.x1, .x2)
            .xb = .gx0 + .gw * max (.x1, .x2)
            .rad = (.xb - .xa) / 2
            if .rad > 0.02
                .c = (.xa + .xb) / 2
                .hh = .h * sqrt ((.xb - .xa) / .gw)
                .steps = max (10, min (64, round (.rad * 3)))
                demo Colour: .col$
                demo Line width: .w
                demo Draw function: .xa, .xb, .steps, fixed$ (.y0, 3) + " + " + fixed$ (.side * .hh, 4)
                    ... + " * sqrt (max (0, 1 - ((x - " + fixed$ (.c, 4) + ") / " + fixed$ (.rad, 4) + ")^2))"
            endif
        elsif .k$ = "node"
            .xx = .gx0 + .gw * .x1
            .rr = max (0.15, .gw * .x2)
            demo Paint circle: .col$, .xx, .y0, .rr
            if .side = 1
                demo Colour: "{0.85, 0.15, 0.15}"
                demo Line width: 2.5
                demo Draw circle: .xx, .y0, .rr + 0.9
            endif
        elsif .k$ = "live"
            .xx = .gx0 + .gw * .x1
            demo Colour: "{0.80, 0.20, 0.20}"
            demo Line width: 3
            demo Draw line: .xx, .y0 - 3.5, .xx, .y0 + 3.5
        endif
    endfor
    demo Line width: 1
    # legend: two rows of coloured words above the STOP button
    @ltext: 3, 17.5, 10, "{0.40, 0.40, 0.48}", "Upper arcs - similar:"
    @ltext: 19, 17.5, 10, "{0.20, 0.40, 0.80}", "Paulstretch"
    @ltext: 29, 17.5, 10, "{0.55, 0.60, 0.20}", "Markov"
    @ltext: 37, 17.5, 10, "{0.90, 0.55, 0.15}", "MDS"
    @ltext: 43, 17.5, 10, "{0.75, 0.25, 0.65}", "Spiral"
    @ltext: 50, 17.5, 10, "{0.15, 0.60, 0.55}", "Speed Deviations"
    @ltext: 64, 17.5, 10, "{0.80, 0.25, 0.25}", "Groove"
    @ltext: 72, 17.5, 10, "{0.50, 0.50, 0.55}", "untransformed"
    @ltext: 3, 14.5, 10, "{0.40, 0.40, 0.48}", "Lower arcs - actions:"
    @ltext: 19, 14.5, 10, "{0.45, 0.20, 0.60}", "recall"
    @ltext: 26, 14.5, 10, "{0.80, 0.30, 0.65}", "recall + transform"
    @ltext: 40, 14.5, 10, "{0.15, 0.62, 0.55}", "transformation"
    @ltext: 52, 14.5, 10, "{0.66, 0.58, 0.80}", "earlier phrases (influence)"
    @ltext: 2, 8, 10, "{0.40, 0.40, 0.48}", "Points:"
    @ltext: 7, 8, 10, "{0.20, 0.40, 0.80}", "A phrase"
    @ltext: 14, 8, 10, "{0.85, 0.45, 0.15}", "B answer"
    @ltext: 21.5, 8, 10, "{0.45, 0.45, 0.50}", "C corpus"
    @ltext: 29, 8, 10, "{0.85, 0.15, 0.15}", "sounding"
    # STOP button (same place as in the status view) + hint
    demo Font size: 10
    demo Select inner viewport: 0, 100, 0, 100
    demo Axes: 0, 100, 0, 100
    demo Paint rectangle: "{0.80, 0.25, 0.25}", 36, 64, 3, 13
    @dtext: 50, 8, 20, "{1.00, 1.00, 1.00}", "##STOP##  (Esc / S)"
    @dtext: 84, 8, 11, "{0.35, 0.35, 0.50}", "G: status view"
    demoShow ()
endproc

procedure drawStatusView: .stopping
    @stField: "playing"
    .play$ = stField.v$
    @stField: "processing"
    .proc$ = stField.v$
    @stField: "pending"
    .pend$ = stField.v$
    @stField: "phrase"
    .phrase$ = stField.v$
    @stField: "input_db"
    .lv = number (stField.v$)
    @stField: "leak_warning"
    .leak$ = stField.v$
    @stField: "message"
    .msg$ = stField.v$
    @stField: "done"
    .done$ = stField.v$
    demo Erase all
    demo Font size: 10
    demo Select inner viewport: 0, 100, 0, 100
    demo Axes: 0, 100, 0, 100
    demo Paint rectangle: "{0.97, 0.97, 0.97}", 0, 100, 0, 100
    @dtext: 50, 92, 26, "{0.20, 0.20, 0.30}", "##AudioTools Call & Response " + version$ + "##"
    .msz = if length (presetName$) > 20 then 14 else 18 fi
    @dtext: 50, 85.5, .msz, "{0.35, 0.35, 0.50}", "MODE: CONTINUOUS   |   " + presetName$
    if engineState$ = "starting"
        @dtext: 50, 66, 30, "{0.35, 0.35, 0.50}", "STARTING..."
        @dtext: 50, 54, 14, "{0.35, 0.35, 0.50}", .msg$
    elsif engineState$ = "running" and not .stopping
        # ---- v0.4.12: YOUR PERFORMANCE ----
        @perfState
        @dtext: 50, 77.5, 11, "{0.40, 0.40, 0.48}", "YOUR PERFORMANCE"
        @dtext: 50, 71.5, 30, perfState.col$, "##" + perfState.head$ + "##"
        @dtext: 50, 66, 13, perfState.col$, perfState.sub$
        # input level bar, -60..0 dBFS, with the detector's thresholds
        if .lv = undefined
            .lv = -120
        endif
        .fill = max (0, min (1, (.lv + 60) / 60))
        demo Font size: 10
        demo Select inner viewport: 0, 100, 0, 100
        demo Axes: 0, 100, 0, 100
        demo Paint rectangle: "{0.86, 0.86, 0.86}", 25, 75, 60, 62.5
        if .fill > 0
            demo Paint rectangle: "{0.15, 0.55, 0.25}", 25, 25 + 50 * .fill, 60, 62.5
        endif
        @stField: "on_db"
        .onT = number (stField.v$)
        @stField: "off_db"
        .offT = number (stField.v$)
        if .onT <> undefined and .offT <> undefined
            demo Line width: 2
            demo Colour: "{0.55, 0.55, 0.60}"
            .xt = 25 + 50 * max (0, min (1, (.offT + 60) / 60))
            demo Draw line: .xt, 59, .xt, 63.5
            demo Colour: "{0.90, 0.50, 0.15}"
            .xt = 25 + 50 * max (0, min (1, (.onT + 60) / 60))
            demo Draw line: .xt, 59, .xt, 63.5
            demo Line width: 1
        endif
        @detLine
        if detLine.txt$ <> ""
            @dtext: 50, 56.8, 10, "{0.45, 0.45, 0.52}", detLine.txt$
        endif
        if perfState.kind$ = "recording"
            # progress of the silence that will end the phrase
            .frac = max (0, min (1, perfState.q / max (perfState.es, 0.05)))
            demo Font size: 10
            demo Select inner viewport: 0, 100, 0, 100
            demo Axes: 0, 100, 0, 100
            demo Paint rectangle: "{0.90, 0.88, 0.86}", 35, 65, 52, 53.5
            if .frac > 0
                demo Paint rectangle: "{0.85, 0.38, 0.18}", 35, 35 + 30 * .frac, 52, 53.5
            endif
            @dtext: 50, 50, 10, "{0.45, 0.45, 0.52}", "end silence " + fixed$ (perfState.q, 1)
                ... + " / " + fixed$ (perfState.es, 1) + " s"
        endif
        # ---- v0.4.12: SYSTEM RESPONSE (independent of the performer) ----
        demo Font size: 10
        demo Select inner viewport: 0, 100, 0, 100
        demo Axes: 0, 100, 0, 100
        demo Colour: "{0.80, 0.80, 0.84}"
        demo Draw line: 15, 46.5, 85, 46.5
        @dtext: 50, 44.3, 11, "{0.40, 0.40, 0.48}", "SYSTEM RESPONSE  -  independent of your playing"
        @responseLine
        .psz = if length (responseLine.txt$) > 70 then 13 else if length (responseLine.txt$) > 40 then 16 else 20 fi fi
        .rcol$ = if .proc$ = "" and .play$ = "" then "{0.45, 0.45, 0.52}" else "{0.48, 0.36, 0.72}" fi
        @dtext: 50, 39.5, .psz, .rcol$, responseLine.txt$
        @voiceLine
        if voiceLine.txt$ <> ""
            @dtext: 50, 34.5, 13, "{0.48, 0.36, 0.72}", voiceLine.txt$
        endif
        @dtext: 50, 30.5, 13, "{0.25, 0.25, 0.35}", "PENDING: " + .pend$ + "      ANSWERS: " + .done$
        @memoryLines
        if memoryLines.on$ = "on"
            .memTxt$ = "MEMORY:  A " + memoryLines.a$ + "  |  B " + memoryLines.b$ + "  |  C " + memoryLines.c$
            if memoryLines.line2$ <> ""
                .memTxt$ = .memTxt$ + "      " + memoryLines.line2$
            endif
            @dtext: 50, 26.5, 13, "{0.30, 0.30, 0.42}", .memTxt$
        endif
        if memoryLines.act$ <> ""
            @dtext: 50, 22.5, 13, "{0.30, 0.30, 0.42}", "ACTION: " + memoryLines.act$
        endif
        if .leak$ = "1"
            @dtext: 50, 81, 12, "{0.85, 0.38, 0.18}", "The microphone hears the answers - use headphones"
        endif
    elsif .stopping or not cleanupDone
        @dtext: 50, 60, 30, "{0.85, 0.38, 0.18}", "STOPPING..."
        @dtext: 50, 50, 14, "{0.35, 0.35, 0.50}", "removing temporary files"
    else
        .why$ = if stopNote$ <> "" then stopNote$ else .msg$ fi
        @dtext: 50, 66, 30, "{0.80, 0.25, 0.25}", "##STOPPED##"
        @dtext: 50, 52, 16, "{0.25, 0.25, 0.35}", .why$
        @dtext: 50, 42, 16, "{0.25, 0.25, 0.35}", "Answers: " + .done$
        @dtext: 50, 34, 14, "{0.25, 0.25, 0.35}", cleanupReport$
    endif
    if engineState$ = "running" or engineState$ = "starting"
        demo Font size: 10
        demo Select inner viewport: 0, 100, 0, 100
        demo Axes: 0, 100, 0, 100
        demo Paint rectangle: "{0.80, 0.25, 0.25}", 36, 64, 3, 13
        @dtext: 50, 8, 20, "{1.00, 1.00, 1.00}", "##STOP##  (Esc / S)"
        @dtext: 50, 16, 11, "{0.35, 0.35, 0.50}", "If Praat then reports ""Mouse click not completely handled"", press OK - the session stops."
        if graphTable
            @dtext: 84, 8, 11, "{0.35, 0.35, 0.50}", "G: memory map"
        endif
    endif
    demoShow ()
endproc

# ============================================================
# SESSION
# ============================================================
clearinfo
@log: "=== AudioTools Call & Response " + version$ + " ==="
if transformation = 1
    modeName$ = "automatic"
elsif sweep
    modeName$ = "test all six"
else
    modeName$ = "manual: " + tId$[transformation - 1]
endif
srcName$ = if continuous then "live continuous" else if isLive then "live turn-taking" else "selected Sound(s)" fi fi
@log: "Source: " + srcName$ + "   Mode: " + modeName$ + "   Python: " + python$
@log: "Preset: " + presetName$
@log: "Plugin: " + pluginRoot$
@log: "Session: " + session$
if missing$ <> ""
    @log: "WARNING - missing processing scripts:" + newline$ + missing$
endif
if isLive
    @log: "Listening: " + fixed$ (sample_rate, 0) + " Hz, " + string$ (channels) + " ch, device '"
        ... + input_device$ + "', sensitivity " + fixed$ (sensitivity_dB, 1) + " dB, end silence "
        ... + fixed$ (end_silence_s, 2) + " s, phrase " + fixed$ (min_phrase_s, 2) + "-"
        ... + fixed$ (max_phrase_s, 1) + " s, timeout " + string$ (waitTimeout) + " s"
    nTurns = cycles
else
    nTurns = nSel
endif
if not hasClock
    @log: "(Praat < 6.4.34: no clock(), so Praat-side timings are not reported)"
endif
summary$ = ""
nDone = 0
force$ = "auto"
if transformation >= 2 and transformation <= 7
    force$ = tId$[transformation - 1]
endif

if continuous
    @continuousSession
    # ---- read the hand-over files, THEN delete everything, THEN report ----
    sumFile$ = session$ + "/summary.txt"
    sm$ = ""
    @safeRead: sumFile$
    if safeRead.ok
        sm$ = newline$ + safeRead.text$
    endif
    errFile$ = session$ + "/engine_stderr.txt"
    err$ = ""
    if engineState$ = "error" and fileReadable (errFile$)
        @safeRead: errFile$
        err$ = safeRead.text$
    endif
    @cleanup
    @buildDisplay: 0
    if not headless
        @drawDemo: 0
    endif
    final$ = display$
    if sm$ <> ""
        final$ = final$ + "phrases=" + extractLine$ (sm$, newline$ + "phrases=") + newline$
        mm$ = extractLine$ (sm$, newline$ + "memory ")
        if mm$ <> ""
            final$ = final$ + "memory " + mm$ + newline$
        endif
        pb$ = extractLine$ (sm$, newline$ + "playback ")
        if pb$ <> ""
            final$ = final$ + "playback " + pb$ + newline$
        endif
        sw$ = extractLine$ (sm$, newline$ + "status_write_failures=")
        if sw$ <> "" and sw$ <> "0"
            final$ = final$ + "status file: " + sw$ + " delayed write(s) by the engine (recovered)" + newline$
        endif
        dl$ = extractLine$ (sm$, newline$ + "delay ")
        if dl$ <> ""
            final$ = final$ + "delay " + dl$ + newline$
        endif
        lk$ = extractLine$ (sm$, newline$ + "leakage estimate ")
        if lk$ <> ""
            final$ = final$ + "leakage estimate " + lk$ + newline$
        endif
    endif
    if sm$ <> "" and (debug_log or engineState$ = "error")
        # the debug log was deleted with the session: show its key events
        evTxt$ = ""
        evRest$ = sm$
        evPos = index (evRest$, newline$ + "event ")
        while evPos > 0
            evRest$ = mid$ (evRest$, evPos + 1, length (evRest$))
            evTxt$ = evTxt$ + "  " + extractLine$ (newline$ + evRest$, newline$ + "event ") + newline$
            evPos = index (evRest$, newline$ + "event ")
        endwhile
        evRest$ = sm$
        evPos = index (evRest$, newline$ + "stderr ")
        while evPos > 0
            evRest$ = mid$ (evRest$, evPos + 1, length (evRest$))
            err$ = err$ + extractLine$ (newline$ + evRest$, newline$ + "stderr ") + newline$
            evPos = index (evRest$, newline$ + "stderr ")
        endwhile
        if length (evTxt$) > 4000
            evTxt$ = "..." + right$ (evTxt$, 4000)
        endif
        if evTxt$ <> ""
            final$ = final$ + newline$ + "Session events:" + newline$ + evTxt$
        endif
    endif
    if err$ <> ""
        if length (err$) > 1500
            err$ = "..." + right$ (err$, 1500)
        endif
        if err$ <> ""
            final$ = final$ + newline$ + "Python engine error output:" + newline$ + err$ + newline$
        endif
    endif
    if statusReadFailures > 0
        final$ = final$ + "status file: " + string$ (statusReadFailures)
            ... + " incomplete or blocked read(s) skipped (last good status kept)" + newline$
    endif
    writeInfoLine: final$
    exitScript: ""
endif

cyc = 0
stopSession = 0
while cyc < nTurns and not stopSession
    cyc += 1
    tag$ = right$ ("00" + string$ (cyc), 3)
    decision$ = session$ + "/decision_" + tag$ + ".txt"
    report$ = session$ + "/report_" + tag$ + ".txt"
    qwav$ = session$ + "/q_" + tag$ + ".wav"
    @log: ""
    @log: "--- Turn " + string$ (cyc) + " / " + string$ (nTurns) + " ---"

    # ---- question ----
    if isLive
        @status: "LISTENING", "Play a phrase"
        @log: "LISTENING... play a phrase (the Praat window is frozen until it ends)"
        nocheck runSubprocess: python$, pyScript$, "listen", "--session", session$,
            ... "--cycle", string$ (cyc), "--force", force$, "--device", input_device$,
            ... "--sr", fixed$ (sample_rate, 0), "--channels", string$ (channels),
            ... "--sensitivity", fixed$ (sensitivity_dB, 3), "--min-phrase", fixed$ (min_phrase_s, 3),
            ... "--end-silence", fixed$ (end_silence_s, 3), "--max-phrase", fixed$ (max_phrase_s, 3),
            ... "--preroll", fixed$ (preroll, 3), "--timeout", string$ (waitTimeout),
            ... "--max-response", fixed$ (maxResponse, 3)
    else
        selectObject: selSound[cyc]
        qName$ = selected$ ("Sound")
        Save as 32-bit WAV file: qwav$
        @status: "ANALYZING", qName$
        @log: "Analysing selected Sound '" + qName$ + "'"
        nocheck runSubprocess: python$, pyScript$, "analyze", "--session", session$,
            ... "--cycle", string$ (cyc), "--force", force$, "--input", qwav$,
            ... "--max-response", fixed$ (maxResponse, 3)
    endif
    @now
    tBack = now.t

    # ---- decision ----
    status$ = "missing"
    if fileReadable (decision$)
        meta$ = newline$ + readFile$ (decision$)
        if extractLine$ (meta$, newline$ + "end=") = "1"
            status$ = extractLine$ (meta$, newline$ + "status=")
        else
            status$ = "incomplete"
        endif
    endif
    turnOk = 1
    if status$ = "missing" or status$ = "incomplete"
        @log: "Python terminated unexpectedly (decision file " + status$ + ")."
        @status: "ERROR", "Python did not return a valid decision"
        turnOk = 0
        stopSession = 1
    elsif status$ <> "ok"
        @log: "Python: " + status$ + " - " + extractLine$ (meta$, newline$ + "message=")
        @status: "STOPPED", status$
        turnOk = 0
        # live: timeout / silent input / device error end the session safely;
        # selected Sounds: skip this one and continue with the next
        if isLive
            stopSession = 1
        endif
    endif
    if turnOk
        @status: "SELECTING", "Choosing transformation"
        @turn
        if nRun = 0
            @status: "READY", "Original phrase (no matching transformation)"
        else
            readyName$ = "Original phrase"
            for readyIx to nT
                if usedId$ = tId$[readyIx]
                    readyName$ = tDisplay$[readyIx]
                endif
            endfor
            @status: "READY", readyName$
        endif
    endif
endwhile

@log: ""
@log: "=== Session summary: " + string$ (nDone) + " answer(s) ==="
@log: "Objects: crq_NNN = recorded questions, cra_NNN_<transformation> = answers."
@cleanup
if nDone > 0 and not stopSession
    @status: "DONE", string$ (nDone) + " response(s) completed"
elsif nDone = 0 and not stopSession
    @status: "DONE", "No response generated"
endif
