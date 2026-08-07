# ============================================================
# Praat AudioTools - MatterGestureBridge.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.4 (2026)
#
# Changelog v1.4 (2026) -- second-round review repairs:
#   - JSON config now built as a string and written in one plain
#     writeFile (the multi-line continuation form parses on
#     6.4.42 -- probe-verified -- but has failed on other
#     versions; the library targets 6.3+, so portability wins).
#   - Patch_length_sec renamed Matter_continuity_sec: it is a
#     PERSISTENCE SCALE, monotone but content-dependent -- the
#     acceptance tolerance shortens runs when the gesture moves.
#     The measured mean run is reported in stats; no false
#     precision in the label.
#   - Gesture_amount is now a true MASTER on the engine side
#     (0 = gesture-free mosaic apart from duration); see the
#     engine changelog. Preset effective fracture/formant depths
#     shift by their amount factor -- audible but modest.
#   - Analysis ranges exposed (Pitch floor/ceiling, Formant
#     ceiling): the fixed 60-600 Hz / 5500 Hz vocal defaults are
#     a methodological limit for instrumental gestures.
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

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

gestureId    = selected("Sound")
gestureName$ = selected$("Sound")

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

matter_sound_file$ = chooseReadFile$: "Select Matter Sound file (long audio, 5-10 min recommended)"
if matter_sound_file$ = ""
    exitScript: "Operation cancelled."
endif
if not fileReadable(matter_sound_file$)
    exitScript: "Matter Sound file not found:" + newline$ + matter_sound_file$
endif

form Matter Gesture Bridge v1.4
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
    comment Matter continuity: persistence scale (measured mean run in stats)
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
    comment === Gesture Analysis Ranges (vocal defaults) ===
    positive Pitch_floor_Hz 60
    positive Pitch_ceiling_Hz 600
    positive Formant_ceiling_Hz 5500
    comment === Options ===
    integer Random_seed 1234
    boolean Reuse_cache 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

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

outputName$ = gestureName$ + "_MGB"
clearinfo
writeInfoLine:  "=== Matter Gesture Bridge v1.4 ==="
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
writeFile: intensityTxt$, "time" + tab$ + "intensity_db" + newline$
intFrames = Get number of frames
for i from 1 to intFrames
    t = Get time from frame number: i
    v = Get value at time: t, "Cubic"
    if v = undefined
        v = intMean
    endif
    appendFileLine: intensityTxt$, fixed$(t, 5) + tab$ + fixed$(v, 4)
endfor
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
writeFile: pitchTxt$, "time" + tab$ + "pitch_hz" + newline$
pitchFrames = Get number of frames
for i from 1 to pitchFrames
    t = Get time from frame number: i
    v = Get value at time: t, "Hertz", "Linear"
    if v = undefined
        v = 0
    endif
    appendFileLine: pitchTxt$, fixed$(t, 5) + tab$ + fixed$(v, 3)
endfor

selectObject: gestMono
sndDurMono = Get total duration
formantCeilingSafe = min(formant_ceiling_Hz, gestureSR / 2 - 100)
if formantCeilingSafe < 1200
    formantCeilingSafe = 1200
endif
writeFile: formantTxt$, "time" + tab$ + "f1" + tab$ + "f2" + tab$ + "f3" + tab$ + "f4" + tab$ + "valid" + newline$
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
        appendFileLine: formantTxt$, fixed$(t, 5) + tab$ + fixed$(f1, 2) + tab$ + fixed$(f2, 2) + tab$ + fixed$(f3, 2) + tab$ + fixed$(f4, 2) + tab$ + string$(valid)
    endfor
    removeObject: formantObj
else
    appendFileLine: formantTxt$, "0" + tab$ + "0" + tab$ + "0" + tab$ + "0" + tab$ + "0" + tab$ + "0"
endif
removeObject: pitchObj

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
cfg$ = cfg$ + "  ""gesture_dur"": " + fixed$(gestureDur,6) + "," + newline$
cfg$ = cfg$ + "  ""gesture_sr"": " + string$(gestureSR) + "," + newline$
cfg$ = cfg$ + "  ""gesture_rms"": " + fixed$(gestureRMS,6) + "," + newline$
cfg$ = cfg$ + "  ""gesture_mean_pitch"": " + fixed$(meanPitch,4) + "," + newline$
cfg$ = cfg$ + "  ""gesture_pitch_range"": " + fixed$(pitchRange,4) + "," + newline$
cfg$ = cfg$ + "  ""gesture_brightness"": " + fixed$(brightnessCOG,2) + "," + newline$
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

maxWait = 900
waited = 0
repeat
    sleep: 1
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
statMeanRun$ = "?"
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
    @parseStatLine: statsText$, "mean_run_frames="
    statMeanRun$ = parseStatLine.result$
    @parseStatLine: statsText$, "formant_valid_fraction="
    statFormantValid$ = parseStatLine.result$
    @parseStatLine: statsText$, "formant_contrast_db="
    statFormantContrast$ = parseStatLine.result$
    @parseStatLine: statsText$, "formant_injection_active="
    statFormantActive$ = parseStatLine.result$
    @parseStatLine: statsText$, "warning="
    warningStat$ = parseStatLine.result$
endif

if draw_visualization
    Erase all
    Select outer viewport: 0, 8, 0, 0.55
    Select inner viewport: 0, 8, 0, 0.55
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.7, "half", "##Matter Gesture Bridge v1.4##"
    Font size: 7
    Text: 0.5, "centre", 0.25, "half", gestureName$ + " | " + presetName$

    Select outer viewport: 0, 8, 0.7, 2.0
    Select inner viewport: 0.6, 7.7, 0.8, 1.9
    selectObject: gestureId
    Colour: "{0.55,0.55,0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Gesture"

    Select outer viewport: 0, 8, 2.1, 3.4
    Select inner viewport: 0.6, 7.7, 2.2, 3.3
    selectObject: resultObj
    Colour: "{0.4,0.2,0.65}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Result"

    Select outer viewport: 0, 8, 3.6, 5.2
    Select inner viewport: 0.6, 7.7, 3.7, 5.1
    selectObject: resultObj
    To Spectrogram: 0.03, min(5000,target_sample_rate/2), 0.002, 20, "Gaussian"
    visSpec = selected("Spectrogram")
    Paint: 0, 0, 0, min(5000,target_sample_rate/2), 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    removeObject: visSpec

    Select outer viewport: 0, 8, 5.35, 6.8
    Select inner viewport: 0.6, 7.7, 5.45, 6.7
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96,0.96,0.97}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text: 0.03, "left", 0.82, "half", "Frames=" + statNFrames$ + " | centroid r=" + statCenCorr$ + " | mean run=" + statMeanRun$
    Text: 0.03, "left", 0.58, "half", "Formant structural=" + fixed$(structPct,1) + "% | spectral valid=" + statFormantValid$ + " | contrast=" + statFormantContrast$ + " dB"
    Text: 0.03, "left", 0.34, "half", "Formant injection active=" + statFormantActive$ + " | RMS=" + statRMSOut$ + " | Peak=" + statPeak$
    if warningStat$ <> "" and warningStat$ <> "?"
        Colour: "{0.75,0.15,0.15}"
        Text: 0.03, "left", 0.10, "half", warningStat$
    endif
endif

appendInfoLine: ""
appendInfoLine: "=== Matter Gesture Bridge complete ==="
appendInfoLine: "Output: ", outputName$, " | ", fixed$(resultDur,2), " s"
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
