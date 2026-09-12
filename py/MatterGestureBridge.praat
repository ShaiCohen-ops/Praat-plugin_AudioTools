# ============================================================
# Praat AudioTools - MatterGestureBridge.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.5 (2026)
#
# Changelog v1.5 (2026) -- verification, speed, visualization:
#
#   VERIFIED (measured, 8 s gesture against a 420 s Matter):
#   - The central claim holds.  Frame-wise correlation of the
#     RESULT against the GESTURE: intensity r = 0.94, brightness
#     r = 0.85 at Gesture_amount 0.65; both fall to ~0.00 at
#     amount 0, and the render is then bit-identical under a
#     scrambled pitch/formant track.  The conditioning is real
#     and the ablation is clean.
#
#   SOUND UNCHANGED.  v1.4's selection and fracture behaviour
#   is the default.  The speed work below is neutral to within
#   2 LSB at 16 bit (-84 dBFS, on 1.7% of samples) -- that is
#   the float32 STFT, and it is not separable from its 15.6x.
#
#   CORRECTED (no effect on the render):
#   - The whole-file To Spectrum on the gesture was dead work
#     (its result reached one log line and nothing else).
#     Removed; the centroid track already reports brightness.
#   - Praat 7.0 trust guard: writing the gesture WAV and
#     deleting temp files both abort on 7.0 without FULL TRUST,
#     so the script could not run at all on a 7.0 install.
#   - Descriptor export no longer opens, writes and closes the
#     file once per analysis frame.
#
#   DIAGNOSED, OFFERED, NOT IMPOSED.  Tick "Calibrated
#   continuity" in the More options dialog to get these; they
#   change the sound, and the v1.4 sound was preferred.
#   - Matter_continuity_sec is inert above 4 s: min(continuity,
#     4.0) freezes the acceptance tolerance, so 12 / 30 / 120 s
#     all give the same ~3.5 s mean run (6 seeds); below 4 s it
#     delivers about a third of its label.  It is a persistence
#     scale, not a duration.  The figure now reports the dial
#     and the achieved mean run side by side, so the reading is
#     available whichever path is used.
#   - Gesture_amount is silently a second continuity control:
#     the acceptance tolerance scales with it, moving the mean
#     run 17x across the knob's range.
#   - "Pitch-motion spectral fracture" fires on VOICING changes,
#     not pitch motion: 89% of the driving signal sits on the
#     27% of frames next to a voicing boundary, and the largest
#     "pitch motion" in the test file was an onset.  It is an
#     articulation effect, and a musical one -- the label is
#     what is wrong, not the result.
#
#   FASTER (same machine, same material):
#   - 8 s gesture:  8.1 s -> 2.9 s.   45 s gesture: 22.8 -> 9.0 s.
#   - Peak memory:  1.59 GB -> 0.53 GB.
#   - See the engine changelog for where the time went.
#
#   VISUALIZATION -- rebuilt around the selection path:
#     I   Gesture, with the two curves it actually drives.
#     II  MATTER SELECTION MAP: output time against position in
#         the Matter file, over the Matter's own brightness
#         profile.  Coherent runs read as diagonals, cuts as
#         vertical leaps.  This is the panel that shows what
#         this module does and no other module in the library
#         does.
#     III Requested against achieved brightness, with the
#         fracture and resonance-injection activity beneath it.
#     IV  Result spectrogram with the injected F1-F4 paths.
#
# Changelog v1.4 (2026) -- second-round review repairs:
#   - JSON config built as a string, written in one writeFile.
#   - Patch_length_sec renamed Matter_continuity_sec.
#   - Gesture_amount made a master on the engine side.
#   - Analysis ranges exposed (pitch floor/ceiling, formant
#     ceiling) instead of fixed vocal defaults.
#
# Changelog v1.3 (2026) -- external-review repairs (both sides):
#   - Description rewritten honestly: stochastic spectral
#     MOSAICING, no diffusion model, no training, no epochs.
#   - Engine: reversed pitch normalization corrected; brightness
#     made a real driver; formant injection made continuous;
#     selection memory reduced to O(M) per frame.
#   - Praat analysis uses a mono mixdown, matching the engine.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Matter Gesture Bridge — Stochastic Spectral Mosaicing
#
#   Structural cross-synthesis. The user selects one Sound object
#   (the Gesture) and chooses one long external audio file (the
#   Matter). The Python engine reorders the Matter's STFT frames
#   along the Gesture's motion -- relative intensity, time-varying
#   brightness, voiced pitch, and formant-like resonance
#   trajectories -- with run continuity, spectral granulation,
#   pitch-motion spectral fracture, and Griffin-Lim phase
#   reconstruction.
#
#   Result: a new Praat Sound object.
#
# Python engine:
#   plugin_AudioTools/py/matter_gesture_bridge.py
#
# Dependencies (Python):
#   pip install numpy soundfile
#   Strongly recommended: pip install scipy   (multithreaded FFT;
#   without it the Matter STFT runs single-core and ~15x slower)
#   Optional: pip install librosa  (higher-quality resampling)
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: Matter Gesture Bridge.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

gestureId    = selected("Sound")
gestureName$ = selected$("Sound")

# Praat 7.0 refuses to write or delete files without FULL TRUST, and this
# script does both. askForTrust() raises Praat's own permission dialog and
# grants trust for the rest of the run; it returns 1 automatically when there
# is no GUI. Guarded by version so 6.x never evaluates the call.
if praatVersion >= 7000
    trustGranted = askForTrust()
    if trustGranted = 0
        exitScript: "Matter Gesture Bridge needs permission to write temporary files."
    endif
endif

if macintosh
    if fileReadable("/opt/homebrew/bin/python3")
        pythonCmd$ = "/opt/homebrew/bin/python3"
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

pluginDir$    = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/matter_gesture_bridge.py"
if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/matter_gesture_bridge.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python engine: matter_gesture_bridge.py"
endif

gestureWav$   = temporaryDirectory$ + "/mgb_gesture.wav"
resultWav$    = temporaryDirectory$ + "/mgb_result.wav"
configJson$   = temporaryDirectory$ + "/mgb_config.json"
logFile$      = temporaryDirectory$ + "/mgb_log.txt"
doneFile$     = temporaryDirectory$ + "/mgb_done.txt"
statsFile$    = temporaryDirectory$ + "/mgb_stats.txt"
intensityTxt$ = temporaryDirectory$ + "/mgb_intensity.txt"
pitchTxt$     = temporaryDirectory$ + "/mgb_pitch.txt"
formantTxt$   = temporaryDirectory$ + "/mgb_formants.txt"
traceTxt$     = temporaryDirectory$ + "/mgb_trace.txt"
matterTxt$    = temporaryDirectory$ + "/mgb_matter.txt"

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
    if fileReadable(traceTxt$)
        deleteFile: traceTxt$
    endif
    if fileReadable(matterTxt$)
        deleteFile: matterTxt$
    endif
endproc

@cleanUpTempFiles

matter_sound_file$ = chooseReadFile$: "Select Matter Sound file (long audio, 5-10 min recommended)"
if matter_sound_file$ = ""
    exitScript: "Operation cancelled."
endif
if not fileReadable(matter_sound_file$)
    exitScript: "Matter Sound file not found:" + newline$ + matter_sound_file$
endif

form Matter Gesture Bridge v1.5
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
    comment Matter continuity: persistence scale (measured mean run reported in the figure)
    positive Matter_continuity_sec 1.5
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
    boolean More_options 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Analysis ranges and the legacy switch live in a second dialog so the main
# form stays short enough to fit on screen. Every variable is pre-initialised,
# because on Praat 6.4.63 and 7.0 a beginPause block terminates a headless run
# silently rather than continuing with its defaults.
pitch_floor_Hz     = 60
pitch_ceiling_Hz   = 600
formant_ceiling_Hz = 5500
calibrated_continuity = 0
reuse_cache           = 0
if more_options
    beginPause: "Matter Gesture Bridge - analysis ranges"
        comment: "Gesture analysis ranges (the defaults are vocal)"
        positive: "Pitch floor Hz", "60"
        positive: "Pitch ceiling Hz", "600"
        positive: "Formant ceiling Hz", "5500"
        comment: "Engine"
        boolean: "Calibrated continuity", 0
        comment: "  (off = v1.4 sound. On, the run length matches its label"
        comment: "   in seconds, at some cost in gesture tracking.)"
        boolean: "Reuse cache", 0
        comment: "  (keeps a Matter STFT library on disk; large file)"
    endPause: "Continue", 1
endif

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

freezeT      = max(0.0, min(0.95, freeze_time))
gestureAmt   = max(0.0, min(1.0, gesture_amount))
intRoughness = max(0.0, min(1.0, intensity_roughness))
pitchNoise   = max(0.0, min(1.0, pitch_noise))
formantInj   = max(0.0, min(1.0, formant_injection))
chaosVal     = max(0.0, min(1.0, chaos))
if target_sample_rate < 8000
    target_sample_rate = 8000
endif
if griffin_Lim_iterations < 1
    griffin_Lim_iterations = 1
endif
if pitch_ceiling_Hz <= pitch_floor_Hz
    exitScript: "Pitch ceiling must be above pitch floor."
endif

outputName$ = gestureName$ + "_MGB"
clearinfo
writeInfoLine:  "=== Matter Gesture Bridge v1.5 ==="
appendInfoLine: "Gesture Sound:  ", gestureName$
appendInfoLine: "Matter file:    ", matter_sound_file$
appendInfoLine: "Preset:         ", presetName$
appendInfoLine: ""

selectObject: gestureId
gestureDur = Get total duration
gestureXmin = Get start time
gestureSR  = Get sampling frequency
gestureRMS = Get root-mean-square: 0, 0
nGestureCh = Get number of channels
Save as WAV file: gestureWav$

selectObject: gestureId
if nGestureCh > 1
    Convert to mono
    gestMono = selected("Sound")
else
    Copy: "mgb_gestmono"
    gestMono = selected("Sound")
endif

# ------------------------------------------------------------------
# Descriptor export.
#
# v1.4 called appendFileLine once per analysis frame, i.e. one file open,
# write and close per line -- a few thousand of them per run. On Linux that
# is cheap; on Windows with on-access virus scanning it is the kind of thing
# that turns a 3 s render into a visibly slow one. The lines are now
# accumulated in memory and flushed in blocks of 250.
# ------------------------------------------------------------------
flushEvery = 250

procedure openBuf: .path$, .header$
    buf$ = .header$ + newline$
    bufPath$ = .path$
    bufCount = 0
    writeFile: .path$, ""
endproc

procedure pushBuf: .line$
    buf$ = buf$ + .line$ + newline$
    bufCount += 1
    if bufCount >= flushEvery
        appendFile: bufPath$, buf$
        buf$ = ""
        bufCount = 0
    endif
endproc

procedure closeBuf
    if buf$ <> ""
        appendFile: bufPath$, buf$
        buf$ = ""
    endif
endproc

selectObject: gestMono
To Intensity: 100, 0.01, "yes"
intObj = selected("Intensity")
intMean = Get mean: 0, 0, "dB"
intMin  = Get minimum: 0, 0, "Parabolic"
intMax  = Get maximum: 0, 0, "Parabolic"
if intMean = undefined
    intMean = 60
    intMin = 50
    intMax = 70
endif
@openBuf: intensityTxt$, "time" + tab$ + "intensity_db"
intFrames = Get number of frames
for i from 1 to intFrames
    t = Get time from frame number: i
    v = Get value in frame: i
    if v = undefined
        v = intMean
    endif
    @pushBuf: fixed$(t, 5) + tab$ + fixed$(v, 4)
endfor
@closeBuf
removeObject: intObj

selectObject: gestMono
pitchObj = To Pitch: 0, pitch_floor_Hz, pitch_ceiling_Hz
meanPitch = Get mean: 0, 0, "Hertz"
minPitch  = Get minimum: 0, 0, "Hertz", "Parabolic"
maxPitch  = Get maximum: 0, 0, "Hertz", "Parabolic"
if meanPitch = undefined
    meanPitch = 0
    minPitch = 0
    maxPitch = 0
endif
pitchRange = maxPitch - minPitch
@openBuf: pitchTxt$, "time" + tab$ + "pitch_hz"
pitchFrames = Get number of frames
for i from 1 to pitchFrames
    t = Get time from frame number: i
    v = Get value in frame: i, "Hertz"
    if v = undefined
        v = 0
    endif
    @pushBuf: fixed$(t, 5) + tab$ + fixed$(v, 3)
endfor
@closeBuf

selectObject: gestMono
sndDurMono = Get total duration
formantCeilingSafe = min(formant_ceiling_Hz, gestureSR / 2 - 100)
if formantCeilingSafe < 1200
    formantCeilingSafe = 1200
endif
@openBuf: formantTxt$, "time" + tab$ + "f1" + tab$ + "f2" + tab$ + "f3" + tab$ + "f4" + tab$ + "valid"
structValidCount = 0
structTotal = 0
if sndDurMono > 0.08 and gestureSR >= 4000
    To Formant (burg): 0, 5, formantCeilingSafe, 0.025, 50
    formantObj = selected("Formant")
    frmFrames = Get number of frames
    for i from 1 to frmFrames
        t = Get time from frame number: i
        f1 = Get value at time: 1, t, "Hertz", "Linear"
        f2 = Get value at time: 2, t, "Hertz", "Linear"
        f3 = Get value at time: 3, t, "Hertz", "Linear"
        f4 = Get value at time: 4, t, "Hertz", "Linear"
        b1 = Get bandwidth at time: 1, t, "Hertz", "Linear"
        b2 = Get bandwidth at time: 2, t, "Hertz", "Linear"
        b3 = Get bandwidth at time: 3, t, "Hertz", "Linear"
        b4 = Get bandwidth at time: 4, t, "Hertz", "Linear"
        valid = 0
        if f1 <> undefined and f2 <> undefined and f3 <> undefined and f4 <> undefined and b1 <> undefined and b2 <> undefined and b3 <> undefined and b4 <> undefined
            if f1 > 80 and f1 < f2 and f2 < f3 and f3 < f4 and f2-f1 > 150 and f3-f2 > 250 and f4-f3 > 250 and f4-f1 > 1200
                if b1 > 20 and b2 > 20 and b3 > 20 and b4 > 20 and b1 < min(900, 0.70*f1) and b2 < min(1000, 0.70*f2) and b3 < min(1200, 0.70*f3) and b4 < min(1400, 0.70*f4)
                    valid = 1
                endif
            endif
        endif
        if f1 = undefined
            f1 = 0
        endif
        if f2 = undefined
            f2 = 0
        endif
        if f3 = undefined
            f3 = 0
        endif
        if f4 = undefined
            f4 = 0
        endif
        structTotal += 1
        structValidCount += valid
        @pushBuf: fixed$(t, 5) + tab$ + fixed$(f1, 2) + tab$ + fixed$(f2, 2) + tab$ + fixed$(f3, 2) + tab$ + fixed$(f4, 2) + tab$ + string$(valid)
    endfor
    removeObject: formantObj
else
    @pushBuf: "0" + tab$ + "0" + tab$ + "0" + tab$ + "0" + tab$ + "0" + tab$ + "0"
endif
@closeBuf
removeObject: pitchObj
removeObject: gestMono

if structTotal > 0
    structPct = 100 * structValidCount / structTotal
else
    structPct = 0
endif
appendInfoLine: "Gesture analysis: pitch mean ", fixed$(meanPitch,1), " Hz | structural formant frames ", fixed$(structPct,1), "%"

matterPathJ$ = replace_regex$(matter_sound_file$, "\\", "/", 0)
gestureWavJ$ = replace_regex$(gestureWav$, "\\", "/", 0)
resultWavJ$  = replace_regex$(resultWav$, "\\", "/", 0)
logFileJ$    = replace_regex$(logFile$, "\\", "/", 0)
doneFileJ$   = replace_regex$(doneFile$, "\\", "/", 0)
statsFileJ$  = replace_regex$(statsFile$, "\\", "/", 0)
intensityJ$  = replace_regex$(intensityTxt$, "\\", "/", 0)
pitchJ$      = replace_regex$(pitchTxt$, "\\", "/", 0)
formantJ$    = replace_regex$(formantTxt$, "\\", "/", 0)
traceJ$      = replace_regex$(traceTxt$, "\\", "/", 0)
matterJ$     = replace_regex$(matterTxt$, "\\", "/", 0)

if draw_visualization
    wantTrace$ = traceJ$
    wantProfile$ = matterJ$
else
    wantTrace$ = ""
    wantProfile$ = ""
endif

cfg$ = "{" + newline$
cfg$ = cfg$ + "  ""matter_wav"": """ + matterPathJ$ + """," + newline$
cfg$ = cfg$ + "  ""gesture_wav"": """ + gestureWavJ$ + """," + newline$
cfg$ = cfg$ + "  ""result_wav"": """ + resultWavJ$ + """," + newline$
cfg$ = cfg$ + "  ""log_file"": """ + logFileJ$ + """," + newline$
cfg$ = cfg$ + "  ""done_file"": """ + doneFileJ$ + """," + newline$
cfg$ = cfg$ + "  ""stats_file"": """ + statsFileJ$ + """," + newline$
cfg$ = cfg$ + "  ""intensity_txt"": """ + intensityJ$ + """," + newline$
cfg$ = cfg$ + "  ""pitch_txt"": """ + pitchJ$ + """," + newline$
cfg$ = cfg$ + "  ""formant_txt"": """ + formantJ$ + """," + newline$
cfg$ = cfg$ + "  ""trace_txt"": """ + wantTrace$ + """," + newline$
cfg$ = cfg$ + "  ""matter_profile_txt"": """ + wantProfile$ + """," + newline$
cfg$ = cfg$ + "  ""target_sr"": " + string$(target_sample_rate) + "," + newline$
cfg$ = cfg$ + "  ""train_limit_sec"": " + string$(matter_excerpt_limit_sec) + "," + newline$
cfg$ = cfg$ + "  ""continuity_sec"": " + fixed$(matter_continuity_sec,4) + "," + newline$
cfg$ = cfg$ + "  ""gl_iterations"": " + string$(griffin_Lim_iterations) + "," + newline$
cfg$ = cfg$ + "  ""freeze_t"": " + fixed$(freezeT,4) + "," + newline$
cfg$ = cfg$ + "  ""gesture_amount"": " + fixed$(gestureAmt,4) + "," + newline$
cfg$ = cfg$ + "  ""intensity_roughness"": " + fixed$(intRoughness,4) + "," + newline$
cfg$ = cfg$ + "  ""pitch_noise"": " + fixed$(pitchNoise,4) + "," + newline$
cfg$ = cfg$ + "  ""formant_injection"": " + fixed$(formantInj,4) + "," + newline$
cfg$ = cfg$ + "  ""chaos"": " + fixed$(chaosVal,4) + "," + newline$
cfg$ = cfg$ + "  ""seed"": " + string$(random_seed) + "," + newline$
cfg$ = cfg$ + "  ""reuse_cache"": " + string$(reuse_cache) + "," + newline$
cfg$ = cfg$ + "  ""legacy_v14_selection"": " + string$(1 - calibrated_continuity) + "," + newline$
cfg$ = cfg$ + "  ""gesture_dur"": " + fixed$(gestureDur,6) + "," + newline$
cfg$ = cfg$ + "  ""gesture_sr"": " + string$(gestureSR) + "," + newline$
cfg$ = cfg$ + "  ""gesture_rms"": " + fixed$(gestureRMS,6) + "," + newline$
cfg$ = cfg$ + "  ""gesture_mean_pitch"": " + fixed$(meanPitch,4) + "," + newline$
cfg$ = cfg$ + "  ""gesture_pitch_range"": " + fixed$(pitchRange,4) + "," + newline$
cfg$ = cfg$ + "  ""gesture_int_mean"": " + fixed$(intMean,4) + "," + newline$
cfg$ = cfg$ + "  ""gesture_int_range"": " + fixed$(intMax-intMin,4) + newline$
cfg$ = cfg$ + "}" + newline$
writeFile: configJson$, cfg$

if windows
    cmd$ = "start /b " + pythonCmd$ + " """ + pythonScript$ + """ """ + configJson$ + """ > NUL 2>&1"
else
    cmd$ = pythonCmd$ + " """ + pythonScript$ + """ """ + configJson$ + """ > /dev/null 2>&1 &"
endif
runSystem_nocheck: cmd$

# Poll at 0.25 s: the v1.4 one-second tick added up to a second of dead wait to
# a render that now takes about three.
maxWait = 3600
waited = 0
repeat
    sleep: 0.25
    waited += 1
until fileReadable(doneFile$) or waited >= maxWait

if not fileReadable(doneFile$)
    @cleanUpTempFiles
    exitScript: "Timed out waiting for Python engine."
endif
if not fileReadable(resultWav$)
    err$ = "Python engine did not produce output."
    if fileReadable(logFile$)
        err$ = err$ + newline$ + readFile$(logFile$)
    endif
    @cleanUpTempFiles
    exitScript: err$
endif

resultObj = Read from file: resultWav$
Shift times by: gestureXmin
Rename: outputName$
selectObject: resultObj
resultDur = Get total duration
resultRMS = Get root-mean-square: 0, 0

statNFrames$ = "?"
statPeak$ = "?"
statRMSOut$ = "?"
statCenCorr$ = "?"
statRmsCorr$ = "?"
statMeanRun$ = "?"
statRunAsked$ = "?"
statNRuns$ = "?"
statMatterDur$ = "?"
statCoverage$ = "?"
statFracture$ = "?"
statMode$ = "?"
statFormantValid$ = "?"
statFormantContrast$ = "?"
statFormantActive$ = "?"
warningStat$ = ""
if fileReadable(statsFile$)
    statsText$ = readFile$(statsFile$)
    @parseStatLine: statsText$, "n_frames="
    statNFrames$ = parseStatLine.result$
    @parseStatLine: statsText$, "peak="
    statPeak$ = parseStatLine.result$
    @parseStatLine: statsText$, "rms_out="
    statRMSOut$ = parseStatLine.result$
    @parseStatLine: statsText$, "sel_centroid_corr="
    statCenCorr$ = parseStatLine.result$
    @parseStatLine: statsText$, "rms_corr="
    statRmsCorr$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_run_sec="
    statMeanRun$ = parseStatLine.result$
    @parseStatLine: statsText$, "continuity_requested_sec="
    statRunAsked$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_runs="
    statNRuns$ = parseStatLine.result$
    @parseStatLine: statsText$, "matter_dur="
    statMatterDur$ = parseStatLine.result$
    @parseStatLine: statsText$, "matter_coverage_pct="
    statCoverage$ = parseStatLine.result$
    @parseStatLine: statsText$, "fracture_active_pct="
    statFracture$ = parseStatLine.result$
    @parseStatLine: statsText$, "engine_mode="
    statMode$ = parseStatLine.result$
    @parseStatLine: statsText$, "formant_valid_fraction="
    statFormantValid$ = parseStatLine.result$
    @parseStatLine: statsText$, "formant_contrast_db="
    statFormantContrast$ = parseStatLine.result$
    @parseStatLine: statsText$, "formant_injection_active="
    statFormantActive$ = parseStatLine.result$
    @parseStatLine: statsText$, "warning="
    warningStat$ = parseStatLine.result$
endif

# ==================================================================
# VISUALIZATION
#
# Canvas 8 x 8.6 in, inner viewports on the 0.60 / 7.70 house grid.
#
# Geometry notes that this layout depends on:
#   - Font size must be set BEFORE Select inner viewport; Praat derives the
#     inner margins from the current font size, so a later change silently
#     shifts the drawing frame outward.
#   - Text: and Draw inner box both leave the frame on the OUTER viewport, so
#     Select inner viewport + Axes are re-issued between groups.
#   - Panel names are placed with Text special against a shared labelX rather
#     than Text left:, which would align them to whatever frame is current.
#   - The script ends by re-selecting the whole canvas, so Save as PNG and the
#     Picture window's own Save/Copy get the full figure, not the last panel.
# ==================================================================
canvasH = 8.6
labelX = -0.035

procedure panelName: .top, .bottom, .name$
    Font size: 7
    Select inner viewport: 0.6, 7.7, .top, .bottom
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text special: labelX, "centre", 0.5, "bottom", "Helvetica", 7, "90", .name$
endproc

if draw_visualization
    Erase all
    Line width: 1

    # ---------- title ----------
    Font size: 12
    Select inner viewport: 0, 8, 0.05, 0.52
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half", "##Matter Gesture Bridge##"
    Font size: 7
    Select inner viewport: 0, 8, 0.05, 0.52
    Axes: 0, 1, 0, 1
    safeName$ = replace$(gestureName$, "_", "\_ ", 0)
    Text: 0.5, "centre", 0.20, "half", safeName$ + "  |  " + presetName$ + "  |  gesture " + fixed$(gestureDur,2) + " s over " + statMatterDur$ + " s of Matter"

    # ---------- I. gesture and the curves it drives ----------
    gTop = 0.72
    gBot = 1.92
    Font size: 6
    Select outer viewport: 0, 8, gTop - 0.10, gBot + 0.10
    Select inner viewport: 0.6, 7.7, gTop, gBot
    selectObject: gestureId
    gMax = Get maximum: 0, 0, "None"
    gMin = Get minimum: 0, 0, "None"
    gAbs = max(abs(gMax), abs(gMin))
    if gAbs <= 0
        gAbs = 1
    endif
    Colour: "{0.62,0.62,0.66}"
    Draw: 0, 0, -gAbs, gAbs, "no", "Curve"
    Colour: "Black"
    Select inner viewport: 0.6, 7.7, gTop, gBot
    Axes: 0, 1, 0, 1
    Draw inner box
    @panelName: gTop, gBot, "Gesture"

    # ---------- read the engine trace ----------
    haveTrace = 0
    if fileReadable(traceTxt$)
        traceTab = Read Table from tab-separated file: traceTxt$
        nTrace = Get number of rows
        if nTrace > 1
            haveTrace = 1
        endif
    endif
    haveMatter = 0
    if fileReadable(matterTxt$)
        matterTab = Read Table from tab-separated file: matterTxt$
        nMatter = Get number of rows
        if nMatter > 1
            haveMatter = 1
        endif
    endif

    if haveTrace
        selectObject: traceTab
        tOutMax = Get maximum: "t_out"
        cenLo   = Get minimum: "tgt_cen"
        cenHi   = Get maximum: "tgt_cen"
        selCenLo = Get minimum: "sel_cen"
        selCenHi = Get maximum: "sel_cen"
        cenLo = min(cenLo, selCenLo)
        cenHi = max(cenHi, selCenHi)
        if cenHi <= cenLo
            cenHi = cenLo + 1
        endif
        rmsLo = Get minimum: "tgt_rms"
        rmsHi = Get maximum: "tgt_rms"
        if rmsHi <= rmsLo
            rmsHi = rmsLo + 1
        endif
        mattLo = Get minimum: "t_matter"
        mattHi = Get maximum: "t_matter"
        if tOutMax <= 0
            tOutMax = gestureDur
        endif

        # ----- overlay the two driving curves on the gesture panel -----
        Font size: 6
        Select inner viewport: 0.6, 7.7, gTop, gBot
        Axes: 0, tOutMax, 0, 1
        Line width: 1.5
        Colour: "{0.20,0.40,0.80}"
        for i from 2 to nTrace
            x0 = Get value: i - 1, "t_out"
            x1 = Get value: i, "t_out"
            y0 = Get value: i - 1, "tgt_rms"
            y1 = Get value: i, "tgt_rms"
            Draw line: x0, 0.06 + 0.88 * (y0 - rmsLo) / (rmsHi - rmsLo), x1, 0.06 + 0.88 * (y1 - rmsLo) / (rmsHi - rmsLo)
        endfor
        Colour: "{0.85,0.45,0.10}"
        for i from 2 to nTrace
            x0 = Get value: i - 1, "t_out"
            x1 = Get value: i, "t_out"
            y0 = Get value: i - 1, "tgt_cen"
            y1 = Get value: i, "tgt_cen"
            Draw line: x0, 0.06 + 0.88 * (y0 - cenLo) / (cenHi - cenLo), x1, 0.06 + 0.88 * (y1 - cenLo) / (cenHi - cenLo)
        endfor
        Line width: 1
        Select inner viewport: 0.6, 7.7, gTop, gBot
        Axes: 0, 1, 0, 1
        Colour: "{0.20,0.40,0.80}"
        Text: 0.012, "left", 0.94, "half", "loudness demand"
        Colour: "{0.85,0.45,0.10}"
        Text: 0.225, "left", 0.94, "half", "brightness demand"
        Colour: "Black"

        # ---------- II. the selection map ----------
        mTop = 2.22
        mBot = 4.32
        Font size: 6
        Select outer viewport: 0, 8, mTop - 0.12, mBot + 0.55
        Select inner viewport: 0.6, 7.7, mTop, mBot
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.985,0.985,0.99}", 0, 1, 0, 1

        # Matter brightness profile as a background field: each horizontal band
        # is one slice of the Matter file, shaded by its own brightness. The
        # path is then legible as a choice among alternatives rather than a
        # line on an empty axis.
        if haveMatter
            selectObject: matterTab
            pLo = Get minimum: "centroid"
            pHi = Get maximum: "centroid"
            if pHi <= pLo
                pHi = pLo + 1
            endif
            matterEnd = Get maximum: "t_matter"
            if matterEnd <= 0
                matterEnd = 1
            endif
            Select inner viewport: 0.6, 7.7, mTop, mBot
            Axes: 0, 1, 0, matterEnd
            bandH = matterEnd / nMatter
            for i from 1 to nMatter
                tm = Get value: i, "t_matter"
                cv = Get value: i, "centroid"
                sh = (cv - pLo) / (pHi - pLo)
                gg = 0.995 - 0.160 * sh
                bb = 0.995 - 0.085 * sh
                Paint rectangle: "{'gg','gg','bb'}", 0, 1, tm - bandH/2, tm + bandH/2 + bandH*0.02
            endfor
            selectObject: traceTab
        endif

        Select inner viewport: 0.6, 7.7, mTop, mBot
        Axes: 0, tOutMax, 0, matterEnd
        # the path itself: continuous inside a run, a marked leap between runs
        Line width: 2.4
        prevT = Get value: 1, "t_out"
        prevM = Get value: 1, "t_matter"
        nCuts = 0
        for i from 2 to nTrace
            xt = Get value: i, "t_out"
            xm = Get value: i, "t_matter"
            nr = Get value: i, "newrun"
            if nr = 1
                Colour: "{0.80,0.20,0.25}"
                Line width: 0.8
                Dotted line
                Draw line: prevT, prevM, xt, xm
                Solid line
                Line width: 2.4
                nCuts += 1
            else
                Colour: "{0.25,0.15,0.55}"
                Draw line: prevT, prevM, xt, xm
            endif
            prevT = xt
            prevM = xm
        endfor
        # run starts, so the grain of the mosaic is countable
        Colour: "{0.80,0.20,0.25}"
        for i from 1 to nTrace
            nr = Get value: i, "newrun"
            if nr = 1
                xt = Get value: i, "t_out"
                xm = Get value: i, "t_matter"
                Paint circle (mm): "{0.80,0.20,0.25}", xt, xm, 0.8
            endif
        endfor
        Line width: 1
        Colour: "Black"
        Select inner viewport: 0.6, 7.7, mTop, mBot
        Axes: 0, tOutMax, 0, matterEnd
        Draw inner box
        mStep = 60
        if matterEnd < 90
            mStep = 15
        elsif matterEnd < 240
            mStep = 30
        endif
        Marks left every: 1, mStep, "yes", "yes", "no"
        Marks bottom every: 1, max(1, round(tOutMax/8)), "yes", "yes", "no"
        Font size: 6
        Select inner viewport: 0.6, 7.7, mTop, mBot
        Axes: 0, 1, 0, 1
        Text bottom: "yes", "Output time (s)"
        @panelName: mTop, mBot, "Position in Matter (s)"
        Select inner viewport: 0.6, 7.7, mTop, mBot
        Axes: 0, 1, 0, 1
        Colour: "{0.25,0.15,0.55}"
        Text: 0.012, "left", 0.955, "half", "coherent run"
        Colour: "{0.80,0.20,0.25}"
        Text: 0.145, "left", 0.955, "half", "cut (" + string$(nCuts) + ")"
        Colour: "{0.45,0.45,0.50}"
        Text: 0.988, "right", 0.955, "half", "shading = Matter brightness"
        Colour: "Black"

        # ---------- III. requested vs achieved brightness ----------
        tTop = 4.92
        tBot = 5.92
        Font size: 6
        Select outer viewport: 0, 8, tTop - 0.12, tBot + 0.12
        Select inner viewport: 0.6, 7.7, tTop, tBot
        Axes: 0, tOutMax, cenLo, cenHi
        Paint rectangle: "{0.985,0.985,0.99}", 0, tOutMax, cenLo, cenHi
        Colour: "{0.34,0.44,0.60}"
        Line width: 1
        for i from 2 to nTrace
            x0 = Get value: i - 1, "t_out"
            x1 = Get value: i, "t_out"
            y0 = Get value: i - 1, "sel_cen"
            y1 = Get value: i, "sel_cen"
            Draw line: x0, y0, x1, y1
        endfor
        Colour: "{0.85,0.45,0.10}"
        Line width: 1.8
        for i from 2 to nTrace
            x0 = Get value: i - 1, "t_out"
            x1 = Get value: i, "t_out"
            y0 = Get value: i - 1, "tgt_cen"
            y1 = Get value: i, "tgt_cen"
            Draw line: x0, y0, x1, y1
        endfor
        Line width: 1
        Colour: "Black"
        Select inner viewport: 0.6, 7.7, tTop, tBot
        Axes: 0, tOutMax, cenLo, cenHi
        Draw inner box
        # Label in kHz: Praat prints a five-digit Hz mark as 10^4, which reads
        # as an exponent rather than a frequency.
        cStep = 0.5
        if cenHi - cenLo > 6000
            cStep = 2
        elsif cenHi - cenLo > 2500
            cStep = 1
        endif
        Marks left every: 1000, cStep, "yes", "yes", "no"
        Font size: 6
        Select inner viewport: 0.6, 7.7, tTop, tBot
        Axes: 0, 1, 0, 1
        Colour: "{0.85,0.45,0.10}"
        Text: 0.012, "left", 0.93, "half", "requested"
        Colour: "{0.34,0.44,0.60}"
        Text: 0.115, "left", 0.93, "half", "achieved"
        Colour: "Black"
        Text: 0.988, "right", 0.93, "half", "r = " + statCenCorr$
        @panelName: tTop, tBot, "Brightness (kHz)"

        # ---------- III b. what else happened to those frames ----------
        aTop = 5.98
        aBot = 6.30
        Font size: 6
        Select inner viewport: 0.6, 7.7, aTop, aBot
        Axes: 0, tOutMax, 0, 2
        Paint rectangle: "{0.985,0.985,0.99}", 0, tOutMax, 0, 2
        dt = tOutMax / max(1, nTrace - 1)
        for i from 1 to nTrace
            xt = Get value: i, "t_out"
            fc = Get value: i, "fconf"
            fr = Get value: i, "fracture"
            if fc > 0
                sh = 0.80 - 0.35 * min(1, fc)
                Paint rectangle: "{0.95,'sh',0.32}", xt, xt + dt*1.05, 1.06, 1.94
            endif
            if fr > 0
                Paint rectangle: "{0.35,0.55,0.80}", xt, xt + dt*1.05, 0.06, 0.94
            endif
        endfor
        Colour: "Black"
        Select inner viewport: 0.6, 7.7, aTop, aBot
        Axes: 0, tOutMax, 0, 2
        Draw inner box
        Font size: 5
        Select inner viewport: 0.6, 7.7, aTop, aBot
        Axes: 0, 1, 0, 1
        Paint rectangle: "{1,1,1}", 0.004, 0.128, 0.55, 0.96
        Paint rectangle: "{1,1,1}", 0.004, 0.105, 0.06, 0.46
        Colour: "Black"
        Text: 0.012, "left", 0.755, "half", "resonance injection"
        Text: 0.012, "left", 0.255, "half", "pitch fracture"
        @panelName: aTop, aBot, "Active"

    endif
    if haveMatter
        removeObject: matterTab
    endif

    # ---------- IV. result ----------
    sTop = 6.62
    sBot = 7.72
    Font size: 6
    Select outer viewport: 0, 8, sTop - 0.12, sBot + 0.55
    Select inner viewport: 0.6, 7.7, sTop, sBot
    selectObject: resultObj
    specTop = min(5000, target_sample_rate/2)
    To Spectrogram: 0.03, specTop, 0.002, 20, "Gaussian"
    visSpec = selected("Spectrogram")
    Paint: 0, 0, 0, specTop, 100, "yes", 50, 6, 0, "no"
    removeObject: visSpec

    # The resonance trajectories the engine actually injected, over the result
    # they were injected into -- drawn only on the frames whose confidence
    # passed, so a disabled injection shows as an empty panel rather than as a
    # confident-looking curve over nothing.
    if haveTrace
        selectObject: traceTab
        Select inner viewport: 0.6, 7.7, sTop, sBot
        Axes: 0, tOutMax, 0, specTop
        Line width: 1.4
        Colour: "{1.0,0.72,0.16}"
        drewFormants = 0
        for k from 1 to 4
            col$ = "f" + string$(k)
            for i from 2 to nTrace
                c0 = Get value: i - 1, "fconf"
                c1 = Get value: i, "fconf"
                if c0 > 0 and c1 > 0
                    y0 = Get value: i - 1, col$
                    y1 = Get value: i, col$
                    if y0 > 0 and y1 > 0 and y0 < specTop and y1 < specTop
                        x0 = Get value: i - 1, "t_out"
                        x1 = Get value: i, "t_out"
                        Draw line: x0, y0, x1, y1
                        drewFormants = 1
                    endif
                endif
            endfor
        endfor
        Line width: 1
        removeObject: traceTab
    else
        drewFormants = 0
    endif

    Colour: "Black"
    Select inner viewport: 0.6, 7.7, sTop, sBot
    Axes: 0, resultDur, 0, specTop
    Draw inner box
    Marks left every: 1000, 1, "yes", "yes", "no"
    Marks bottom every: 1, max(1, round(resultDur/8)), "yes", "yes", "no"
    Font size: 6
    Select inner viewport: 0.6, 7.7, sTop, sBot
    Axes: 0, 1, 0, 1
    Text bottom: "yes", "Time (s)"
    if drewFormants
        Paint rectangle: "{1,1,1}", 0.862, 0.988, 0.855, 0.945
        Colour: "{0.85,0.55,0.05}"
        Text: 0.982, "right", 0.90, "half", "injected F1-F4"
        Colour: "Black"
    endif
    @panelName: sTop, sBot, "Result (kHz)"

    # ---------- summary ----------
    Font size: 7
    Select inner viewport: 0.6, 7.7, 8.00, 8.55
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94,0.94,0.94}", 0, 1, 0, 1
    Colour: "Black"
    Select inner viewport: 0.6, 7.7, 8.00, 8.55
    Axes: 0, 1, 0, 1
    Draw inner box
    Select inner viewport: 0.6, 7.7, 8.00, 8.55
    Axes: 0, 1, 0, 1
    Text: 0.02, "left", 0.82, "half", "Frames " + statNFrames$ + "  |  runs " + statNRuns$ + "  |  mean run " + statMeanRun$ + " s (dial " + statRunAsked$ + ")  |  Matter used " + statCoverage$ + "\%  |  engine " + statMode$
    Text: 0.02, "left", 0.50, "half", "Tracking: brightness r " + statCenCorr$ + "  |  loudness r " + statRmsCorr$ + "  |  fracture active " + statFracture$ + "\%   |  resonance " + statFormantActive$ + " (valid " + statFormantValid$ + ", contrast " + statFormantContrast$ + " dB)"
    if warningStat$ <> "" and warningStat$ <> "?"
        Colour: "{0.75,0.15,0.15}"
        Text: 0.02, "left", 0.18, "half", "Warning: " + warningStat$
        Colour: "Black"
    else
        Text: 0.02, "left", 0.18, "half", "Output " + fixed$(resultDur,2) + " s  |  peak " + statPeak$ + "  |  RMS " + statRMSOut$ + "  |  structural formant frames " + fixed$(structPct,1) + "\% "
    endif

    # Leave the whole canvas selected, or Save as PNG (from here or from the
    # Picture window) crops to the summary strip.
    Select outer viewport: 0, 8, 0, canvasH
endif

appendInfoLine: ""
appendInfoLine: "=== Matter Gesture Bridge complete ==="
appendInfoLine: "Output: ", outputName$, " | ", fixed$(resultDur,2), " s"
appendInfoLine: "Continuity: dial ", statRunAsked$, ", achieved mean run ", statMeanRun$, " s over ", statNRuns$, " runs"
appendInfoLine: "Gesture tracking: brightness r ", statCenCorr$, " | loudness r ", statRmsCorr$
appendInfoLine: "Matter coverage: ", statCoverage$, "% of ", statMatterDur$, " s"
appendInfoLine: "Formant structural frames: ", fixed$(structPct,1), "%"
appendInfoLine: "Formant spectral-valid fraction: ", statFormantValid$
appendInfoLine: "Median resonance contrast: ", statFormantContrast$, " dB"
appendInfoLine: "Formant injection active: ", statFormantActive$
if warningStat$ <> "" and warningStat$ <> "?"
    appendInfoLine: "WARNING: ", warningStat$
endif

@cleanUpTempFiles
selectObject: resultObj
if play_result
    Play
endif

procedure parseStatLine: .text$, .key$
    .result$ = "?"
    .pos = index(.text$, .key$)
    if .pos > 0
        .start = .pos + length(.key$)
        .rest$ = mid$(.text$, .start, length(.text$) - .start + 1)
        .nl = index(.rest$, newline$)
        if .nl > 0
            .result$ = left$(.rest$, .nl - 1)
        else
            .result$ = .rest$
        endif
    endif
endproc
