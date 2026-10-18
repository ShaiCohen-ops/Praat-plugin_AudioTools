# ============================================================
# Praat AudioTools Plugin
# Script:      AudioTools_CallResponse.praat
# Author:      Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version:     0.3.1 (2026) - Cleanup & Session Safety (Sonic Memory Upgrade from v0.2.0)
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

form: "AudioTools Call & Response 0.3.1"
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
    comment: "Preloaded corpus C: a folder of sound files (empty = none; read only)"
    sentence: "Corpus_C_folder", ""
    boolean: "Memory_settings", 0
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
version$ = "0.3.1"
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

# ---- Advanced dialog (GUI only; keep the box unticked for batch runs) ----
if advanced_settings
    beginPause: "Call & Response 0.3.1 - advanced"
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
if memory_settings and sonic_memory and source = 1
    memPage = 1
    while memPage > 0
        if memPage = 1
            beginPause: "Call & Response 0.3.1 - sonic memory"
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
            memClicked = endPause: "Cancel", "Limits...", "Start", 3, 1
            if memClicked = 1
                exitScript: "Cancelled."
            endif
            memPage = if memClicked = 2 then 2 else 0 fi
        else
            beginPause: "Call & Response 0.3.1 - memory limits"
                natural: "Max_generation", string$ (max_generation)
                natural: "Max_live_phrases", string$ (max_live_phrases)
                natural: "Max_processed_responses", string$ (max_processed_responses)
                positive: "Max_audio_memory_min", string$ (max_audio_memory_min)
                positive: "Max_item_s", string$ (max_item_s)
                natural: "Candidates", string$ (candidates)
                natural: "Cooldown_recalls", string$ (cooldown_recalls)
                integer: "Exclude_recent_phrases", string$ (exclude_recent_phrases)
                boolean: "Same_family_exclusion", same_family_exclusion
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
    .cdir$ = replace_regex$ (corpus_C_folder$, "^\s+|\s+$", "", 0)
    .cdir$ = replace_regex$ (.cdir$, "^""|""$", "", 0)
    .useC = use_preloaded_corpus_C and .cdir$ <> ""
    if .useC and sonic_memory and not folderExists (.cdir$)
        @cleanup
        exitScript: "Corpus_C_folder does not exist:" + newline$ + .cdir$
    endif
    if not .useC
        .cdir$ = "none"
    endif
    .praat$ = if praatExe$ = "" then "none" else praatExe$ fi
    .in$ = if input_device$ = "" then "default" else input_device$ fi
    .out$ = if output_device$ = "" then "default" else output_device$ fi
    .overflow$ = if overflow_policy = 1 then "drop_oldest" else "drop_newest" fi
    @log: "Engine: continuous, in '" + .in$ + "', out '" + .out$ + "', " + fixed$ (sample_rate, 0)
        ... + " Hz, pending <= " + string$ (max_pending_phrases) + ", responses <= "
        ... + string$ (max_pending_responses) + ", " + .overflow$
    # Ordinary blocking call: "launch" starts the engine DETACHED and returns
    # at once.  ("asynchronous runSubprocess" never ran the engine on Windows.)
    runSubprocess: python$, pyScript$, "launch", "--session", session$,
        ... "--script", .self$, "--praat", .praat$, "--plugin-root", pluginRoot$,
        ... "--force", force$, "--device", .in$, "--output-device", .out$,
        ... "--sr", fixed$ (sample_rate, 0), "--channels", string$ (channels),
        ... "--sensitivity", fixed$ (sensitivity_dB, 3), "--min-phrase", fixed$ (min_phrase_s, 3),
        ... "--end-silence", fixed$ (end_silence_s, 3), "--max-phrase", fixed$ (max_phrase_s, 3),
        ... "--preroll", fixed$ (preroll, 3), "--max-pending", string$ (max_pending_phrases),
        ... "--max-responses", string$ (max_pending_responses), "--overflow", .overflow$,
        ... "--max-response", fixed$ (max_response_s, 3), "--session-minutes", fixed$ (session_minutes, 3),
        ... "--idle-stop", fixed$ (idle_stop_s, 3), "--leak-guard", string$ (leakage_guard),
        ... "--play", string$ (play_response), "--debug-log", debugPath$,
        ... "--memory", string$ (sonic_memory), "--response-mode", .rm$,
        ... "--use-a", string$ (use_live_corpus_A), "--use-b", string$ (use_processed_corpus_B),
        ... "--use-c", string$ (.useC), "--corpus-c", .cdir$, "--sim-mode", .sim$,
        ... "--min-sim", fixed$ (minimum_similarity, 3), "--w-live", fixed$ (weight_A_live, 3),
        ... "--w-processed", fixed$ (weight_B_processed, 3), "--w-preloaded", fixed$ (weight_C_preloaded, 3),
        ... "--p-transform", fixed$ (weight_transform, 3), "--p-recall", fixed$ (weight_recall, 3),
        ... "--p-recall-transform", fixed$ (weight_recall_transform, 3),
        ... "--max-generation", string$ (max_generation), "--max-live", string$ (max_live_phrases),
        ... "--max-processed", string$ (max_processed_responses),
        ... "--max-ram-min", fixed$ (max_audio_memory_min, 3), "--max-item-s", fixed$ (max_item_s, 3),
        ... "--candidates", string$ (candidates), "--evolving", string$ (evolving_memory),
        ... "--layered", string$ (layered_response), "--recent-exclude", string$ (exclude_recent_phrases),
        ... "--cooldown", string$ (cooldown_recalls), "--same-family", string$ (same_family_exclusion)

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
    lastShown$ = ""
    engineState$ = "starting"
    st$ = newline$ + "state=starting" + newline$
    stopNote$ = ""
    while .running
        sleep (0.2)
        .now = clock ()
        if .now - .lastBeat >= 1
            writeFileLine: .aliveFile$, fixed$ (.now - .t0, 2)
            .lastBeat = .now
        endif
        .got = 0
        if fileReadable (.statusFile$)
            .raw$ = newline$ + readFile$ (.statusFile$)
            if index (.raw$, newline$ + "state=") > 0
                st$ = .raw$
                .got = 1
            endif
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
                writeFileLine: .stopFile$, "stop"
                .running = 0
            endif
        elsif .now - .t0 > 20
            # the engine writes its first status before any import, so this
            # means the engine process never ran at all
            engineState$ = "error"
            .how$ = "no launch record"
            if fileReadable (session$ + "/launch.txt")
                .how$ = "launched as " + replace$ (readFile$ (session$ + "/launch.txt"), newline$, " ", 0)
            endif
            stopNote$ = "the engine process never ran (no status file after 20 s; " + .how$ + ")"
            st$ = newline$ + "state=error" + newline$ + "message=" + stopNote$ + newline$
            writeFileLine: .stopFile$, "stop"
            .running = 0
        endif
        if .stopSent and .running and .now - .tStop > 15
            stopNote$ = "the engine did not confirm the stop within 15 s"
            .running = 0
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
            .frame$ = display$ + string$ (.lvq) + string$ (.stopSent)
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
                    writeFileLine: .stopFile$, "stop"
                    .stopSent = 1
                    .tStop = .now
                endif
            endif
        endif
    endwhile
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
        ... + "MODE: CONTINUOUS" + newline$
    if engineState$ = "starting"
        display$ = display$ + "STARTING: " + .msg$ + newline$
    elsif engineState$ = "running" and .stopping
        display$ = display$ + "STOPPING" + newline$
    elsif engineState$ = "running" or engineState$ = "stopping"
        if .phrase$ = "1"
            display$ = display$ + "LISTENING: ON - PHRASE DETECTED" + newline$
        else
            display$ = display$ + "LISTENING: ON" + newline$
        endif
        if .proc$ <> ""
            display$ = display$ + "PROCESSING: " + .proc$ + newline$
        endif
        if .play$ <> ""
            display$ = display$ + "PLAYING: " + .play$ + newline$
        endif
        if .proc$ = "" and .play$ = "" and .pend$ = "0"
            display$ = display$ + "READY" + newline$
        endif
        display$ = display$ + "PENDING: " + .pend$ + newline$
        @memoryLines
        display$ = display$ + memoryLines.txt$
        if .leak$ = "1"
            display$ = display$ + "WARNING: the microphone hears the answers - use headphones" + newline$
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
    @dtext: 50, 83, 18, "{0.35, 0.35, 0.50}", "MODE: CONTINUOUS"
    if engineState$ = "starting"
        @dtext: 50, 66, 30, "{0.35, 0.35, 0.50}", "STARTING..."
        @dtext: 50, 54, 14, "{0.35, 0.35, 0.50}", .msg$
    elsif engineState$ = "running" and not .stopping
        if .phrase$ = "1"
            @dtext: 50, 70, 34, "{0.85, 0.38, 0.18}", "##PHRASE DETECTED##"
        else
            @dtext: 50, 70, 34, "{0.15, 0.55, 0.25}", "##LISTENING: ON##"
        endif
        # input level bar, -60..0 dBFS
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
        if .proc$ <> ""
            @dtext: 50, 50, 26, "{0.20, 0.48, 0.75}", "PROCESSING: " + .proc$
        endif
        if .play$ <> ""
            @dtext: 50, 40, 26, "{0.48, 0.36, 0.72}", "PLAYING: " + .play$
        endif
        if .proc$ = "" and .play$ = "" and .pend$ = "0"
            @dtext: 50, 45, 26, "{0.35, 0.35, 0.50}", "READY"
        endif
        @dtext: 50, 32, 18, "{0.25, 0.25, 0.35}", "PENDING: " + .pend$ + "      ANSWERS: " + .done$
        @memoryLines
        if memoryLines.on$ = "on"
            .memTxt$ = "MEMORY:  A " + memoryLines.a$ + "  |  B " + memoryLines.b$ + "  |  C " + memoryLines.c$
            if memoryLines.line2$ <> ""
                .memTxt$ = .memTxt$ + "      " + memoryLines.line2$
            endif
            @dtext: 50, 26, 14, "{0.30, 0.30, 0.42}", .memTxt$
        endif
        if memoryLines.act$ <> ""
            @dtext: 50, 21.5, 14, "{0.30, 0.30, 0.42}", "ACTION: " + memoryLines.act$
        endif
        if .leak$ = "1"
            @dtext: 50, 77, 14, "{0.85, 0.38, 0.18}", "The microphone hears the answers - use headphones"
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
    if fileReadable (sumFile$)
        sm$ = newline$ + readFile$ (sumFile$)
    endif
    errFile$ = session$ + "/engine_stderr.txt"
    err$ = ""
    if engineState$ = "error" and fileReadable (errFile$)
        err$ = readFile$ (errFile$)
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
