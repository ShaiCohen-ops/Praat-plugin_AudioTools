# ============================================================
# Praat AudioTools - MatterGestureBridge.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3 (2026)
#
# Changelog v1.3 (2026) -- external-review repairs (both sides):
#   - Description rewritten honestly: this is stochastic spectral
#     MOSAICING (no diffusion model, no training, no epochs);
#     "Diffusion steps" are Griffin-Lim phase-reconstruction
#     iterations and are now named so; Model epochs removed.
#   - Patch length is now REAL: average coherent Matter run
#     length (selection continuity), engine-side.
#   - Engine fixes: reversed pitch normalization corrected;
#     time-varying gesture brightness now genuinely drives
#     centroid matching; formant injection continuous (was
#     strided); selection memory O(M) per frame (no >1 GB
#     matrices on long Matter files).
#   - Praat analysis uses a MONO MIXDOWN (matching the engine's
#     channel averaging; channel 1 was analyzed before).
#   - Viz title strip on house geometry (was the collision form);
#     summary shows centroid-tracking r and mean run length;
#     warning line is now actually produced by the engine.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Matter Gesture Bridge — Stochastic Spectral Mosaicing
#
#   Structural cross-synthesis audio effect (stochastic spectral
#   mosaicing). The user selects one Sound object (the Gesture)
#   and chooses one long external audio file (the Matter).
#   The Python engine reorders the Matter's STFT frames along the
#   Gesture's motion -- relative intensity, time-varying
#   brightness, voiced pitch, and formant-like resonance
#   trajectories -- with Patch-length continuity, spectral
#   granulation, pitch-motion spectral fracture, and Griffin-Lim
#   phase reconstruction.
#
#   Result: a new Praat Sound object. 
#
# Python engine:
#   plugin_AudioTools/py/matter_gesture_bridge.py
#
# Dependencies (Python):
#   pip install numpy soundfile
#   Optional: pip install librosa, scipy (multithreaded FFT)
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: Matter Gesture Bridge.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

gestureId    = selected("Sound")
gestureName$ = selected$("Sound")

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

# ---- PATHS ----
pluginDir$    = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/matter_gesture_bridge.py"

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python engine: " + pythonScript$ + newline$ +
        ... "Please verify AudioTools installation."
endif

# ---- TEMP FILE PATHS (hidden from user) ----
gestureWav$   = temporaryDirectory$ + "/mgb_gesture.wav"
resultWav$    = temporaryDirectory$ + "/mgb_result.wav"
configJson$   = temporaryDirectory$ + "/mgb_config.json"
logFile$      = temporaryDirectory$ + "/mgb_log.txt"
doneFile$     = temporaryDirectory$ + "/mgb_done.txt"
statsFile$    = temporaryDirectory$ + "/mgb_stats.txt"
intensityTxt$ = temporaryDirectory$ + "/mgb_intensity.txt"
pitchTxt$     = temporaryDirectory$ + "/mgb_pitch.txt"
formantTxt$   = temporaryDirectory$ + "/mgb_formants.txt"

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(gestureWav$)
        deleteFile: gestureWav$
    endif
    if fileReadable(resultWav$)
        deleteFile: resultWav$
    endif
    if fileReadable(configJson$)
        deleteFile: configJson$
    endif
    if fileReadable(logFile$)
        deleteFile: logFile$
    endif
    if fileReadable(doneFile$)
        deleteFile: doneFile$
    endif
    if fileReadable(statsFile$)
        deleteFile: statsFile$
    endif
    if fileReadable(intensityTxt$)
        deleteFile: intensityTxt$
    endif
    if fileReadable(pitchTxt$)
        deleteFile: pitchTxt$
    endif
    if fileReadable(formantTxt$)
        deleteFile: formantTxt$
    endif
endproc

@cleanUpTempFiles

# ---- CHOOSE MATTER SOUND FILE ----
matter_sound_file$ = chooseReadFile$: "Select Matter Sound file (long audio, 5-10 min recommended)"
if matter_sound_file$ = ""
    exitScript: "Operation cancelled."
endif
if not fileReadable(matter_sound_file$)
    exitScript: "Matter Sound file not found:" + newline$ + matter_sound_file$
endif

# ---- FORM ----
form Matter Gesture Bridge v1.3
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Crystalline trace
        option Liminal cloud
        option Ghost matter
        option Volatile gesture
        option Deep freeze
        option Spectral breath
    comment === Rendering ===
    integer Target_sample_rate 44100
    integer Matter_excerpt_limit_sec 420
    comment Patch length: average coherent Matter run (selection continuity)
    positive Patch_length_sec 1.5
    integer Griffin_Lim_iterations 64
    comment === Synthesis Controls ===
    comment Freeze time: 0.0=crystallized  0.55=liminal cloud  0.95=ghost matter
    real Freeze_time 0.45
    comment Gesture conditioning amount (0.0-1.0)
    real Gesture_amount 0.65
    comment Spectral granulation: high=unstable/noisy, low=crystallized
    real Intensity_roughness 0.75
    comment Pitch-motion spectral fracture (0.0-1.0)
    real Pitch_noise 0.55
    comment Formant-like resonance injection (0.0-1.0)
    real Formant_injection 0.45
    comment Chaos / crystallization balance (0.0=crystallize, 1.0=chaos)
    real Chaos 0.50
    comment === Options ===
    integer Random_seed 1234
    boolean Reuse_cache 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- PRESETS ----
if preset = 2
    freeze_time = 0.10
    gesture_amount = 0.80
    intensity_roughness = 0.30
    pitch_noise = 0.25
    formant_injection = 0.60
    chaos = 0.15
    griffin_Lim_iterations = 80
    presetName$ = "CrystallineTrace"
elsif preset = 3
    freeze_time = 0.55
    gesture_amount = 0.65
    intensity_roughness = 0.65
    pitch_noise = 0.50
    formant_injection = 0.45
    chaos = 0.50
    griffin_Lim_iterations = 64
    presetName$ = "LiminalCloud"
elsif preset = 4
    freeze_time = 0.90
    gesture_amount = 0.40
    intensity_roughness = 0.85
    pitch_noise = 0.70
    formant_injection = 0.20
    chaos = 0.85
    griffin_Lim_iterations = 48
    presetName$ = "GhostMatter"
elsif preset = 5
    freeze_time = 0.35
    gesture_amount = 0.95
    intensity_roughness = 0.90
    pitch_noise = 0.80
    formant_injection = 0.35
    chaos = 0.75
    griffin_Lim_iterations = 64
    presetName$ = "VolatileGesture"
elsif preset = 6
    freeze_time = 0.05
    gesture_amount = 0.50
    intensity_roughness = 0.15
    pitch_noise = 0.10
    formant_injection = 0.80
    chaos = 0.05
    griffin_Lim_iterations = 96
    presetName$ = "DeepFreeze"
elsif preset = 7
    freeze_time = 0.60
    gesture_amount = 0.70
    intensity_roughness = 0.50
    pitch_noise = 0.60
    formant_injection = 0.55
    chaos = 0.40
    griffin_Lim_iterations = 64
    presetName$ = "SpectralBreath"
else
    presetName$ = "Custom"
endif

# ---- CLAMP CONTROLS ----
freezeT       = max(0.0, min(0.95, freeze_time))
gestureAmt    = max(0.0, min(1.0, gesture_amount))
intRoughness  = max(0.0, min(1.0, intensity_roughness))
pitchNoise    = max(0.0, min(1.0, pitch_noise))
formantInj    = max(0.0, min(1.0, formant_injection))
chaosVal      = max(0.0, min(1.0, chaos))

outputName$ = gestureName$ + "_MGB"

# ---- INFO HEADER ----
clearinfo
writeInfoLine:  "=== Matter Gesture Bridge v1.3 ==="
appendInfoLine: "Gesture Sound:  ", gestureName$
appendInfoLine: "Matter file:    ", matter_sound_file$
appendInfoLine: "Preset:         ", presetName$
appendInfoLine: "Output name:    ", outputName$, " (auto)"
appendInfoLine: "Target SR:      ", target_sample_rate, " Hz"
appendInfoLine: "Freeze time:    ", fixed$(freezeT, 2)
appendInfoLine: "Gesture amount: ", fixed$(gestureAmt, 2)
appendInfoLine: "Chaos balance:  ", fixed$(chaosVal, 2)
appendInfoLine: ""

# ============================================================
# STEP 1 — Export Gesture Sound to WAV
# ============================================================
appendInfoLine: "[1/5] Exporting Gesture Sound..."

selectObject: gestureId
gestureDur = Get total duration
gestureSR  = Get sampling frequency
gestureRMS = Get root-mean-square: 0, 0
nGestureCh = Get number of channels

Save as WAV file: gestureWav$
appendInfoLine: "  Gesture: ", fixed$(gestureDur, 3), " s @ ", gestureSR, " Hz  RMS=", fixed$(gestureRMS, 5)

# ============================================================
# STEP 2 — Extract Gesture Descriptors (Praat-side controls)
# ============================================================
appendInfoLine: "[2/5] Extracting gesture controls..."

# ---- Convert to mono for analysis ----
# v1.3: mono MIXDOWN, matching the engine's channel averaging
# (channel 1 alone was analyzed before -- descriptors and audio
# could disagree on stereo gestures)
selectObject: gestureId
nGestCh = Get number of channels
if nGestCh > 1
    Convert to mono
    gestMono = selected("Sound")
else
    Copy: "mgb_gestmono"
    gestMono = selected("Sound")
endif

# ---- Intensity curve ----
selectObject: gestMono
To Intensity: 100, 0.01, "yes"
intObj = selected("Intensity")
intMean = Get mean: 0, 0, "dB"
intMin  = Get minimum: 0, 0, "Parabolic"
intMax  = Get maximum: 0, 0, "Parabolic"
if intMean = undefined
    intMean = 60
    intMin  = 50
    intMax  = 70
endif

# Write intensity sample points for Python — full duration, no frame ceiling.
writeFile: intensityTxt$, "time" + tab$ + "intensity_db" + newline$
selectObject: intObj
intFrames = Get number of frames
for ifr from 1 to intFrames
    t_int   = Get time from frame number: ifr
    val_int = Get value at time: t_int, "Cubic"
    if val_int = undefined
        val_int = intMean
    endif
    appendFileLine: intensityTxt$, fixed$(t_int, 4) + tab$ + fixed$(val_int, 3)
endfor

removeObject: intObj

# ---- Pitch curve ----
selectObject: gestMono
To Pitch: 0, 60, 600
pitchObj = selected("Pitch")
meanPitch = Get mean: 0, 0, "Hertz"
minPitch  = Get minimum: 0, 0, "Hertz", "Parabolic"
maxPitch  = Get maximum: 0, 0, "Hertz", "Parabolic"
if meanPitch = undefined
    meanPitch = 0
    minPitch  = 0
    maxPitch  = 0
endif
pitchRange = maxPitch - minPitch

# Write pitch sample points for Python — full duration, no frame ceiling.
writeFile: pitchTxt$, "time" + tab$ + "pitch_hz" + newline$
pitchFrames = Get number of frames
for pfr from 1 to pitchFrames
    t_pitch   = Get time from frame number: pfr
    val_pitch = Get value at time: t_pitch, "Hertz", "Linear"
    if val_pitch = undefined
        val_pitch = 0
    endif
    appendFileLine: pitchTxt$, fixed$(t_pitch, 4) + tab$ + fixed$(val_pitch, 2)
endfor

removeObject: pitchObj

# ---- Formant tracks F1-F4 ----
selectObject: gestMono
sndDurMono = Get total duration
f1mean = 500
f2mean = 1500
f3mean = 2500
f4mean = 3500

writeFile: formantTxt$, "time" + tab$ + "f1" + tab$ + "f2" + tab$ + "f3" + tab$ + "f4" + newline$

if sndDurMono > 0.1
    To Formant (burg): 0, 5, 5500, 0.025, 50
    formantObj = selected("Formant")
    frmFrames  = Get number of frames

    for ffr from 1 to frmFrames
        t_frm = Get time from frame number: ffr
        v_f1  = Get value at time: 1, t_frm, "Hertz", "Linear"
        v_f2  = Get value at time: 2, t_frm, "Hertz", "Linear"
        v_f3  = Get value at time: 3, t_frm, "Hertz", "Linear"
        v_f4  = Get value at time: 4, t_frm, "Hertz", "Linear"
        if v_f1 = undefined
            v_f1 = 500
        endif
        if v_f2 = undefined
            v_f2 = 1500
        endif
        if v_f3 = undefined
            v_f3 = 2500
        endif
        if v_f4 = undefined
            v_f4 = 3500
        endif
        appendFileLine: formantTxt$, fixed$(t_frm, 4) + tab$ + fixed$(v_f1, 1) + tab$ + fixed$(v_f2, 1) + tab$ + fixed$(v_f3, 1) + tab$ + fixed$(v_f4, 1)
    endfor

    removeObject: formantObj
else
    appendFileLine: formantTxt$, "0.0" + tab$ + "500" + tab$ + "1500" + tab$ + "2500" + tab$ + "3500"
endif

# ---- Spectral centre of gravity (brightness proxy) ----
selectObject: gestMono
brightnessCOG = 2000
if sndDurMono > 0.05
    To Spectrum: "yes"
    specObj = selected("Spectrum")
    brightnessCOG = Get centre of gravity: 2
    if brightnessCOG = undefined
        brightnessCOG = 2000
    endif
    removeObject: specObj
endif

removeObject: gestMono

appendInfoLine: "  Intensity mean: ", fixed$(intMean, 1), " dB  range: ", fixed$(intMax - intMin, 1), " dB"
appendInfoLine: "  Pitch mean:     ", fixed$(meanPitch, 1), " Hz  range: ", fixed$(pitchRange, 1), " Hz"
appendInfoLine: "  Brightness COG: ", fixed$(brightnessCOG, 0), " Hz"

# ============================================================
# STEP 3 — Write Config JSON
# ============================================================
appendInfoLine: "[3/5] Writing config..."

# Forward-slash paths for cross-platform JSON safety
matterPathJ$   = replace_regex$(matter_sound_file$, "\\", "/", 0)
gestureWavJ$   = replace_regex$(gestureWav$,        "\\", "/", 0)
resultWavJ$    = replace_regex$(resultWav$,          "\\", "/", 0)
logFileJ$      = replace_regex$(logFile$,            "\\", "/", 0)
doneFileJ$     = replace_regex$(doneFile$,           "\\", "/", 0)
statsFileJ$    = replace_regex$(statsFile$,          "\\", "/", 0)
intensityJ$    = replace_regex$(intensityTxt$,       "\\", "/", 0)
pitchJ$        = replace_regex$(pitchTxt$,           "\\", "/", 0)
formantJ$      = replace_regex$(formantTxt$,         "\\", "/", 0)

reuseCache = reuse_cache

writeFile: configJson$,
    ... "{" + newline$ +
    ... "  ""matter_wav"":       """ + matterPathJ$   + """," + newline$ +
    ... "  ""gesture_wav"":      """ + gestureWavJ$   + """," + newline$ +
    ... "  ""result_wav"":       """ + resultWavJ$    + """," + newline$ +
    ... "  ""log_file"":         """ + logFileJ$      + """," + newline$ +
    ... "  ""done_file"":        """ + doneFileJ$     + """," + newline$ +
    ... "  ""stats_file"":       """ + statsFileJ$    + """," + newline$ +
    ... "  ""intensity_txt"":    """ + intensityJ$    + """," + newline$ +
    ... "  ""pitch_txt"":        """ + pitchJ$        + """," + newline$ +
    ... "  ""formant_txt"":      """ + formantJ$      + """," + newline$ +
    ... "  ""target_sr"":        "  + string$(target_sample_rate)          + "," + newline$ +
    ... "  ""train_limit_sec"":  "  + string$(matter_excerpt_limit_sec)    + "," + newline$ +
    ... "  ""patch_sec"":        "  + fixed$(patch_length_sec, 4)          + "," + newline$ +
    ... "  ""gl_iterations"":    "  + string$(griffin_Lim_iterations)      + "," + newline$ +
    ... "  ""freeze_t"":         "  + fixed$(freezeT,      4)              + "," + newline$ +
    ... "  ""gesture_amount"":   "  + fixed$(gestureAmt,   4)              + "," + newline$ +
    ... "  ""intensity_roughness"": " + fixed$(intRoughness, 4)            + "," + newline$ +
    ... "  ""pitch_noise"":      "  + fixed$(pitchNoise,   4)              + "," + newline$ +
    ... "  ""formant_injection"": "  + fixed$(formantInj,  4)              + "," + newline$ +
    ... "  ""chaos"":            "  + fixed$(chaosVal,     4)              + "," + newline$ +
    ... "  ""seed"":             "  + string$(random_seed)                 + "," + newline$ +
    ... "  ""reuse_cache"":      "  + string$(reuseCache)                  + "," + newline$ +
    ... "  ""gesture_dur"":      "  + fixed$(gestureDur,   6)              + "," + newline$ +
    ... "  ""gesture_sr"":       "  + string$(gestureSR)                   + "," + newline$ +
    ... "  ""gesture_rms"":      "  + fixed$(gestureRMS,   6)              + "," + newline$ +
    ... "  ""gesture_mean_pitch"": " + fixed$(meanPitch,   4)              + "," + newline$ +
    ... "  ""gesture_pitch_range"": " + fixed$(pitchRange, 4)              + "," + newline$ +
    ... "  ""gesture_brightness"": " + fixed$(brightnessCOG, 2)            + "," + newline$ +
    ... "  ""gesture_int_mean"": "   + fixed$(intMean,     4)              + "," + newline$ +
    ... "  ""gesture_int_range"": "  + fixed$(intMax - intMin, 4)          + newline$ +
    ... "}" + newline$

appendInfoLine: "  Config written: ", configJson$

# ============================================================
# STEP 4 — Launch Python Engine
# ============================================================
appendInfoLine: "[4/5] Launching Python engine (this may take a moment)..."

configJsonQ$ = replace_regex$(configJson$, "\\", "/", 0)

if windows
    cmd$ = "start /b " + pythonCmd$ + " """ + pythonScript$ + """ """ + configJsonQ$ + """ > """ + logFile$ + """ 2>&1"
else
    cmd$ = pythonCmd$ + " """ + pythonScript$ + """ """ + configJson$ + """ > """ + logFile$ + """ 2>&1 &"
endif

runSystem_nocheck: cmd$

# ---- Poll for done file ----
maxWait = 900
waited  = 0
gotDone = 0

repeat
    sleep: 1
    waited += 1
    if fileReadable(doneFile$)
        gotDone = 1
    endif
until gotDone = 1 or waited >= maxWait

# Surface log (hidden on success, shown on error)
if fileReadable(logFile$)
    logContent$ = readFile$(logFile$)
    if index(logContent$, "ERROR") > 0 or index(logContent$, "error") > 0
        appendInfoLine: ""
        appendInfoLine: "--- Engine log ---"
        appendInfoLine: logContent$
    endif
endif

if waited >= maxWait and gotDone = 0
    @cleanUpTempFiles
    exitScript: "Timed out waiting for Python engine (15 min limit)." + newline$ +
        ... "Check Python environment and Matter file accessibility."
endif

if not fileReadable(resultWav$)
    if fileReadable(logFile$)
        logContent$ = readFile$(logFile$)
        @cleanUpTempFiles
        exitScript: "Result WAV not produced. Engine log:" + newline$ + logContent$
    else
        @cleanUpTempFiles
        exitScript: "Result WAV not produced. No log available."
    endif
endif

# ---- Check for error status ----
doneContent$ = readFile$(doneFile$)
if index(doneContent$, "error") > 0
    if fileReadable(logFile$)
        logContent$ = readFile$(logFile$)
        @cleanUpTempFiles
        exitScript: "Engine reported an error:" + newline$ + logContent$
    endif
endif

# ============================================================
# STEP 5 — Import Result into Praat
# ============================================================
appendInfoLine: "[5/5] Importing result..."

resultObj = Read from file: resultWav$
Rename: outputName$

selectObject: resultObj
resultDur    = Get total duration
resultRMS    = Get root-mean-square: 0, 0

# ============================================================
# Read Stats
# ============================================================
statGestureDur$  = "?"
statResultDur$   = "?"
statNFrames$     = "?"
statPeak$        = "?"
statRMSOut$      = "?"
statFreeze$      = "?"
statChaos$       = "?"
statGestureAmt$  = "?"
statSeed$        = "?"
statGLIters$     = "?"
statMatterFile$  = "?"
statCacheHit$    = "?"
statIntMean$     = "?"
statIntRange$    = "?"
statPitchMean$   = "?"
statPitchRange$  = "?"
statBrightness$  = "?"
statCenCorr$     = "?"
statMeanRun$     = "?"
warningStat$     = ""

if fileReadable(statsFile$)
    statsText$ = readFile$(statsFile$)
    @parseStatLine: statsText$, "gesture_dur="
    statGestureDur$ = parseStatLine.result$
    @parseStatLine: statsText$, "result_dur="
    statResultDur$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_frames="
    statNFrames$ = parseStatLine.result$
    @parseStatLine: statsText$, "peak="
    statPeak$ = parseStatLine.result$
    @parseStatLine: statsText$, "rms_out="
    statRMSOut$ = parseStatLine.result$
    @parseStatLine: statsText$, "freeze_t="
    statFreeze$ = parseStatLine.result$
    @parseStatLine: statsText$, "chaos="
    statChaos$ = parseStatLine.result$
    @parseStatLine: statsText$, "gesture_amount="
    statGestureAmt$ = parseStatLine.result$
    @parseStatLine: statsText$, "seed="
    statSeed$ = parseStatLine.result$
    @parseStatLine: statsText$, "gl_iters="
    statGLIters$ = parseStatLine.result$
    @parseStatLine: statsText$, "matter_file="
    statMatterFile$ = parseStatLine.result$
    @parseStatLine: statsText$, "cache_hit="
    statCacheHit$ = parseStatLine.result$
    @parseStatLine: statsText$, "int_mean="
    statIntMean$ = parseStatLine.result$
    @parseStatLine: statsText$, "int_range="
    statIntRange$ = parseStatLine.result$
    @parseStatLine: statsText$, "pitch_mean="
    statPitchMean$ = parseStatLine.result$
    @parseStatLine: statsText$, "pitch_range="
    statPitchRange$ = parseStatLine.result$
    @parseStatLine: statsText$, "brightness="
    statBrightness$ = parseStatLine.result$
    @parseStatLine: statsText$, "sel_centroid_corr="
    statCenCorr$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_run_frames="
    statMeanRun$ = parseStatLine.result$
    @parseStatLine: statsText$, "warning="
    warningStat$ = parseStatLine.result$
    if warningStat$ = "?"
        warningStat$ = ""
    endif
endif

###############################################################################
# VISUALIZATION
###############################################################################

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # === Title (v1.3: house geometry -- the old subtitle at
    # y = -1.2 was the margin-compression collision form) ===
    Select outer viewport: 0, 8, 0, 0.5
    Select inner viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half", "##Matter Gesture Bridge v1.3##"
    Font size: 7
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.24, "half", gestureName$ + " | " + presetName$ + " | freeze=" + fixed$(freezeT, 2) + " chaos=" + fixed$(chaosVal, 2) + " gesture=" + fixed$(gestureAmt, 2)

    # === Original Waveform ===
    Select outer viewport: 0, 8, 0.6, 1.6
    Select inner viewport: 0.6, 7.7, 0.65, 1.55
    selectObject: gestureId
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Gesture"
    Text top: "no", "Gesture Sound — " + fixed$(gestureDur, 2) + " s @ " + string$(gestureSR) + " Hz"

    # === Result Waveform ===
    Select outer viewport: 0, 8, 1.6, 2.6
    Select inner viewport: 0.6, 7.7, 1.65, 2.55
    selectObject: resultObj
    Colour: "{0.4, 0.2, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Result"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "MGB Result — " + fixed$(resultDur, 2) + " s  RMS=" + fixed$(resultRMS, 4)

    # === Gesture Spectrogram ===
    Select outer viewport: 0, 8, 2.7, 3.85
    Select inner viewport: 0.6, 7.7, 2.8, 3.75
    selectObject: gestureId
    if nGestureCh > 1
        Convert to mono
        tmpGestMono = selected("Sound")
    else
        Copy: "tmpGestMono"
        tmpGestMono = selected("Sound")
    endif
    To Spectrogram: 0.03, 5000, 0.002, 20, "Gaussian"
    specGest = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Hz"
    Text top: "no", "Gesture spectrogram"
    removeObject: specGest, tmpGestMono

    # === Result Spectrogram ===
    Select outer viewport: 0, 8, 3.85, 5.0
    Select inner viewport: 0.6, 7.7, 3.95, 4.9
    selectObject: resultObj
    Copy: "tmpResultMono"
    tmpResultMono = selected("Sound")
    To Spectrogram: 0.03, 5000, 0.002, 20, "Gaussian"
    specResult = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Result spectrogram"
    removeObject: specResult, tmpResultMono

    # === Gesture Controls Panel (intensity + pitch over time) ===
    Select outer viewport: 0, 8, 5.1, 6.3
    Select inner viewport: 0.6, 7.7, 5.2, 6.2

    Axes: 0, gestureDur, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, gestureDur, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Controls"
    Text top: "no", "Gesture controls — intensity (grey) | pitch (purple) | formant F1 (green)"
    Text bottom: "yes", "Time (s)"

    # Read and plot intensity curve
    if fileReadable(intensityTxt$)
        intText$ = readFile$(intensityTxt$)
        # Find min/max for normalisation
        iMin_plot = intMean - (intMax - intMin) * 0.5 - 5
        iMax_plot = intMax + 5
        iRange_plot = iMax_plot - iMin_plot
        if iRange_plot < 1
            iRange_plot = 1
        endif

        Colour: "{0.6, 0.6, 0.6}"
        Line width: 1.5
        prevT_plot = -1
        prevV_plot = 0
        # Walk the file line by line via index search
        lineStart = index(intText$, newline$) + 1
        nCharsInt = length(intText$)
        iPlotLine = 0
        plotPos = lineStart
        repeat
            nlPos = index(mid$(intText$, plotPos, nCharsInt - plotPos + 1), newline$)
            if nlPos > 0
                oneLine$ = mid$(intText$, plotPos, nlPos - 1)
                plotPos = plotPos + nlPos
            else
                oneLine$ = mid$(intText$, plotPos, nCharsInt - plotPos + 1)
                plotPos = nCharsInt + 1
            endif
            tabPos = index(oneLine$, tab$)
            if tabPos > 0
                tVal = number(left$(oneLine$, tabPos - 1))
                vVal = number(mid$(oneLine$, tabPos + 1, length(oneLine$) - tabPos))
                vNorm = (vVal - iMin_plot) / iRange_plot
                vNorm = max(0.02, min(0.98, vNorm))
                if prevT_plot >= 0
                    Draw line: prevT_plot, prevV_plot, tVal, vNorm
                endif
                prevT_plot = tVal
                prevV_plot = vNorm
            endif
            iPlotLine = iPlotLine + 1
        until plotPos > nCharsInt or iPlotLine > 5000
        Line width: 1
    endif

    # Plot pitch curve
    if fileReadable(pitchTxt$)
        pitchText$ = readFile$(pitchTxt$)
        pMax_plot = maxPitch
        if pMax_plot < 1
            pMax_plot = 600
        endif

        Colour: "{0.5, 0.2, 0.6}"
        Line width: 1.5
        prevT_plot = -1
        prevV_plot = 0
        lineStart = index(pitchText$, newline$) + 1
        nCharsPitch = length(pitchText$)
        iPlotLine = 0
        plotPos = lineStart
        repeat
            nlPos = index(mid$(pitchText$, plotPos, nCharsPitch - plotPos + 1), newline$)
            if nlPos > 0
                oneLine$ = mid$(pitchText$, plotPos, nlPos - 1)
                plotPos = plotPos + nlPos
            else
                oneLine$ = mid$(pitchText$, plotPos, nCharsPitch - plotPos + 1)
                plotPos = nCharsPitch + 1
            endif
            tabPos = index(oneLine$, tab$)
            if tabPos > 0
                tVal = number(left$(oneLine$, tabPos - 1))
                vVal = number(mid$(oneLine$, tabPos + 1, length(oneLine$) - tabPos))
                if vVal > 10
                    vNorm = min(0.98, vVal / pMax_plot)
                    if prevT_plot >= 0 and prevV_plot > 0
                        Draw line: prevT_plot, prevV_plot, tVal, vNorm
                    endif
                    prevT_plot = tVal
                    prevV_plot = vNorm
                else
                    prevT_plot = tVal
                    prevV_plot = 0
                endif
            endif
            iPlotLine = iPlotLine + 1
        until plotPos > nCharsPitch or iPlotLine > 5000
        Line width: 1
    endif

    # Plot F1 formant curve
    if fileReadable(formantTxt$)
        formText$ = readFile$(formantTxt$)
        Colour: "{0.2, 0.6, 0.3}"
        Line width: 1
        prevT_plot = -1
        prevV_plot = 0
        lineStart = index(formText$, newline$) + 1
        nCharsForm = length(formText$)
        iPlotLine = 0
        plotPos = lineStart
        repeat
            nlPos = index(mid$(formText$, plotPos, nCharsForm - plotPos + 1), newline$)
            if nlPos > 0
                oneLine$ = mid$(formText$, plotPos, nlPos - 1)
                plotPos = plotPos + nlPos
            else
                oneLine$ = mid$(formText$, plotPos, nCharsForm - plotPos + 1)
                plotPos = nCharsForm + 1
            endif
            # time tab f1 tab f2 tab f3 tab f4
            tabPos = index(oneLine$, tab$)
            if tabPos > 0
                tVal = number(left$(oneLine$, tabPos - 1))
                rest$ = mid$(oneLine$, tabPos + 1, length(oneLine$) - tabPos)
                tabPos2 = index(rest$, tab$)
                if tabPos2 > 0
                    vVal = number(left$(rest$, tabPos2 - 1))
                else
                    vVal = number(rest$)
                endif
                vNorm = max(0.02, min(0.98, vVal / 1000))
                if prevT_plot >= 0
                    Draw line: prevT_plot, prevV_plot, tVal, vNorm
                endif
                prevT_plot = tVal
                prevV_plot = vNorm
            endif
            iPlotLine = iPlotLine + 1
        until plotPos > nCharsForm or iPlotLine > 5000
        Line width: 1
    endif

    Colour: "Black"

    # === Summary Panel ===
    Select outer viewport: 0, 8, 6.4, 8.0
    Select inner viewport: 0.6, 7.7, 6.5, 7.9

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.92, "half", "Summary:"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.76, "half", "Preset=" + presetName$ + " | Frames=" + statNFrames$ + " | Griffin-Lim iters=" + statGLIters$ + " | Cache=" + statCacheHit$ + " | centroid r=" + statCenCorr$ + " | run=" + statMeanRun$ + " frames"
    Text: 0.02, "left", 0.57, "half", "freeze=" + statFreeze$ + " | chaos=" + statChaos$ + " | gesture=" + statGestureAmt$ + " | seed=" + statSeed$
    Text: 0.02, "left", 0.38, "half", "Gesture: " + fixed$(gestureDur, 2) + "s  RMS=" + fixed$(gestureRMS, 4) + " | Result: " + fixed$(resultDur, 2) + "s  RMS=" + statRMSOut$ + "  Peak=" + statPeak$
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.02, "left", 0.19, "half", "Int mean=" + statIntMean$ + " dB  range=" + statIntRange$ + " dB | Pitch mean=" + statPitchMean$ + " Hz  range=" + statPitchRange$ + " Hz | Bright=" + statBrightness$ + " Hz"

    if warningStat$ <> "?" and warningStat$ <> ""
        Colour: "{0.8, 0.2, 0.2}"
        Text: 0.02, "left", 0.04, "half", "Warn: " + warningStat$
    endif

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
endif

# ============================================================
# Cleanup temp files
# ============================================================
@cleanUpTempFiles

# ============================================================
# Final info summary
# ============================================================
appendInfoLine: ""
appendInfoLine: "=== Matter Gesture Bridge complete ==="
appendInfoLine: "Output Sound: ", outputName$, " (", fixed$(resultDur, 2), " s)"
appendInfoLine: "Preset:       ", presetName$
appendInfoLine: "Gesture:      ", gestureName$
appendInfoLine: ""
appendInfoLine: "Freeze time:    ", fixed$(freezeT, 2), "  Chaos: ", fixed$(chaosVal, 2), "  Gesture: ", fixed$(gestureAmt, 2)
appendInfoLine: "Roughness:      ", fixed$(intRoughness, 2), "  Pitch noise: ", fixed$(pitchNoise, 2), "  Formant inj: ", fixed$(formantInj, 2)
appendInfoLine: ""
appendInfoLine: "Frames:         ", statNFrames$
appendInfoLine: "Griffin-Lim:    ", statGLIters$, " iterations"
appendInfoLine: "Centroid r:     ", statCenCorr$, "   Mean run: ", statMeanRun$, " frames"
appendInfoLine: "Cache hit:      ", statCacheHit$
appendInfoLine: "RMS result:     ", statRMSOut$
appendInfoLine: "Peak:           ", statPeak$

if warningStat$ <> "?" and warningStat$ <> ""
    appendInfoLine: ""
    appendInfoLine: "WARNING: ", warningStat$
endif

selectObject: resultObj

if play_result
    Play
endif

# ============================================================
# Procedures
# ============================================================
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
