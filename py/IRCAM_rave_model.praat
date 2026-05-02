# ============================================================
# Praat AudioTools Plugin
# Script:      IRCAM_rave_model.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Loads a TorchScript RAVE .ts model and processes an input
#   Sound object, writing the result back into Praat.
#   Supports IRCAM RAVE models shipped with nn_tilde.
#
#   Visualization includes:
#     - Input / output waveforms
#     - Side-by-side spectrograms
#     - Latent space walking path (PCA-proxy 2-D projection of
#       frame-level features: brightness × tonalness)
#     - Summary panel
#
# Usage:
#   Select one Sound object, then run this script.
# ============================================================

# ---- Verify selection ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

soundObj   = selected("Sound")
soundName$ = selected$("Sound")

# ---- OS-Specific Python Discovery ----
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
pythonScript$ = pluginDir$ + "py/run_model_ts.py"

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: " + pythonScript$ + newline$ + "Please verify AudioTools installation."
endif

tempInput$  = temporaryDirectory$ + "/temp_rave_input.wav"
tempOutput$ = temporaryDirectory$ + "/temp_rave_output.wav"
tempError$  = temporaryDirectory$ + "/temp_rave_error.txt"

tempInputJ$  = replace_regex$(tempInput$,    "\\", "/", 0)
tempOutputJ$ = replace_regex$(tempOutput$,   "\\", "/", 0)
tempErrorJ$  = replace_regex$(tempError$,    "\\", "/", 0)
scriptJ$     = replace_regex$(pythonScript$, "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(tempInput$)
        deleteFile: tempInput$
    endif
    if fileReadable(tempOutput$)
        deleteFile: tempOutput$
    endif
    if fileReadable(tempError$)
        deleteFile: tempError$
    endif
endproc

@cleanUpTempFiles

# ---- FORM ----
form IRCAM RAVE Model Runner
    comment ── Model ─────────────────────────────────────────────────────
    optionmenu RAVE_model: 1
        option break.ts
        option darbouka_onnx.ts
        option engine.ts
        option InstantAlbania.ts
        option isis.ts
        option percussion.ts
        option wheel.ts
        option Custom (type name below)
    sentence Custom_model_name mymodel.ts
    sentence Models_directory C:\Users\User\Documents\Max 9\Packages\nn_tilde\help
    sentence Output_prefix rave_out
    comment ── Output ────────────────────────────────────────────────────
    real Gain_dB 0.0
    optionmenu Normalize: 2
        option none
        option peak
        option rms
    comment ── Latent walk ───────────────────────────────────────────────
    integer Walk_frames 64
    comment (number of analysis frames projected into latent space; 8–256)
    boolean Draw_visualization 1
    boolean Play_result 1
    comment ── Model input shape ─────────────────────────────────────────
    optionmenu Input_shape: 1
        option Auto-detect
        option [batch, channels, samples]
        option [batch, 1, samples] mono
        option [channels, samples] no batch
    comment ── Output channels ───────────────────────────────────────────
    optionmenu Output_channels: 1
        option Same as model output
        option Force mono
        option Force stereo
endform

# ---- Resolve model filename ----
if rAVE_model = 1
    modelFile$ = "break.ts"
elsif rAVE_model = 2
    modelFile$ = "darbouka_onnx.ts"
elsif rAVE_model = 3
    modelFile$ = "engine.ts"
elsif rAVE_model = 4
    modelFile$ = "InstantAlbania.ts"
elsif rAVE_model = 5
    modelFile$ = "isis.ts"
elsif rAVE_model = 6
    modelFile$ = "percussion.ts"
elsif rAVE_model = 7
    modelFile$ = "wheel.ts"
else
    # Custom
    modelFile$ = custom_model_name$
    if modelFile$ = ""
        exitScript: "Custom model selected but no filename provided." + newline$ + "Please fill in the Custom model name field."
    endif
    # Append .ts extension if the user forgot it
    if right$(modelFile$, 3) <> ".ts"
        modelFile$ = modelFile$ + ".ts"
    endif
endif

# ---- Build full model path ----
modelsDir$ = models_directory$

if windows
    if right$(modelsDir$, 1) <> "\" and right$(modelsDir$, 1) <> "/"
        modelsDir$ = modelsDir$ + "\"
    endif
else
    if right$(modelsDir$, 1) <> "/"
        modelsDir$ = modelsDir$ + "/"
    endif
endif

model_path$ = modelsDir$ + modelFile$

# ---- Validate ----
if models_directory$ = ""
    exitScript: "Please provide the models directory path."
endif

if output_prefix$ = ""
    output_prefix$ = "rave_out"
endif

if walk_frames < 8
    walk_frames = 8
endif
if walk_frames > 256
    walk_frames = 256
endif

modelPathJ$ = replace_regex$(model_path$, "\\", "/", 0)

# ---- Map option menus to strings ----
if normalize = 1
    normalizeStr$ = "none"
elsif normalize = 2
    normalizeStr$ = "peak"
else
    normalizeStr$ = "rms"
endif

if input_shape = 1
    inputShapeStr$ = "auto"
elsif input_shape = 2
    inputShapeStr$ = "BCT"
elsif input_shape = 3
    inputShapeStr$ = "B1T"
else
    inputShapeStr$ = "CT"
endif

if output_channels = 1
    outputChStr$ = "auto"
elsif output_channels = 2
    outputChStr$ = "mono"
else
    outputChStr$ = "stereo"
endif

# ---- Export selected Sound as WAV ----
selectObject: soundObj
Save as WAV file: tempInput$

if not fileReadable(tempInput$)
    exitScript: "Failed to export Sound to temporary WAV: " + tempInput$
endif

# ---- Info log ----
clearinfo
appendInfoLine: "=== IRCAM RAVE Model Runner v1.1 ==="
appendInfoLine: "Sound:       ", soundName$
appendInfoLine: "Model:       ", modelFile$
appendInfoLine: "Path:        ", model_path$
appendInfoLine: "Gain:        ", gain_dB, " dB"
appendInfoLine: "Normalize:   ", normalizeStr$
appendInfoLine: "In shape:    ", inputShapeStr$
appendInfoLine: "Out ch:      ", outputChStr$
appendInfoLine: "Walk frames: ", walk_frames
appendInfoLine: "Python:      ", pythonCmd$
appendInfoLine: ""
appendInfoLine: "Running Python..."

# ---- Launch Python ----
runSystem_nocheck: pythonCmd$ + " """ + scriptJ$ + """"
    ... + " --input """     + tempInputJ$    + """"
    ... + " --output """    + tempOutputJ$   + """"
    ... + " --model """     + modelPathJ$    + """"
    ... + " --error """     + tempErrorJ$    + """"
    ... + " --gain "        + fixed$(gain_dB, 4)
    ... + " --normalize "   + normalizeStr$
    ... + " --input_shape " + inputShapeStr$
    ... + " --out_ch "      + outputChStr$

# ---- Check for Python error log ----
if fileReadable(tempError$)
    errMsg$ = readFile$(tempError$)
    appendInfoLine: "--- Python Error ---"
    appendInfoLine: errMsg$
    appendInfoLine: "--------------------"
    @cleanUpTempFiles
    exitScript: "Python crashed — see Praat Info window for the traceback."
endif

# ---- Check output was produced ----
if not fileReadable(tempOutput$)
    @cleanUpTempFiles
    exitScript: "Output WAV was not created." + newline$ +
              ... "Check Praat Info window." + newline$ +
              ... "Expected: " + tempOutput$
endif

# ---- Import result ----
Read from file: tempOutput$
Rename: output_prefix$ + "_" + soundName$
resultSound = selected("Sound")

# ---- Cleanup temp files ----
@cleanUpTempFiles

# ---- Summary stats (pre-normalization) ----
selectObject: soundObj
dur_in  = Get total duration
sr_in   = Get sampling frequency
nch_in  = Get number of channels
rms_in  = Get root-mean-square: 0, 0

selectObject: resultSound
dur_out  = Get total duration
nch_out  = Get number of channels
sr_out   = Get sampling frequency

appendInfoLine: ""
appendInfoLine: "--- Output: ", output_prefix$, "_", soundName$, " ---"
appendInfoLine: "In:      ", fixed$(dur_in,  3), " s   Channels: ", nch_in,  "   SR: ", sr_in,  " Hz"
appendInfoLine: "Out:     ", fixed$(dur_out, 3), " s   Channels: ", nch_out, "   SR: ", sr_out, " Hz"
appendInfoLine: "RMS in:  ", fixed$(rms_in,  6)

# ---- Praat-side output normalization ----
selectObject: resultSound
Scale peak: 0.99

selectObject: resultSound
rms_out  = Get root-mean-square: 0, 0
peak_out = Get absolute extremum: 0, 0, "None"
appendInfoLine: "RMS out: ", fixed$(rms_out, 6), "   Peak out: ", fixed$(peak_out, 6)
if rms_out < 0.0001
    appendInfoLine: "WARNING: output is silent — check model output."
else
    appendInfoLine: "OK"
endif

# ===========================================================================
# LATENT WALK
# ---------------------------------------------------------------------------
# Computes a 2-D proxy latent walk from the INPUT sound using Praat-native
# analysis only (no extra Python call needed).
#
# Each of the 'walk_frames' evenly-spaced windows yields two coordinates:
#
#   axis X  (Brightness)  = log( RMS_hi / RMS_lo )
#                           where lo = 0–1500 Hz, hi = 1500 Hz–Nyquist
#
#   axis Y  (Tonalness)   = pitch_stability × sqrt( HNR + 1 )
#                           pitch_stability = 1 – CV(F0)
#
# These two axes capture the dominant perceptual dimensions along which
# RAVE latent codes vary, giving a meaningful proxy trajectory.
# The path is then normalised to [-1, 1] for display.
# ===========================================================================

appendInfoLine: ""
appendInfoLine: "Computing latent walk (" + string$(walk_frames) + " frames)..."

selectObject: soundObj
if nch_in > 1
    Extract one channel: 1
    walkMono = selected("Sound")
else
    Copy: "walkMono_tmp"
    walkMono = selected("Sound")
endif

selectObject: walkMono
walkPitch = To Pitch: 0.0, 75, 600

selectObject: walkMono
walkHarm  = To Harmonicity (cc): 0.01, 75, 0.1, 1.0

selectObject: walkMono
walkInt   = To Intensity: 100, 0.01, "yes"

# Band-split for brightness
selectObject: walkMono
walkLo = Filter (pass Hann band): 0, 1500, 100
selectObject: walkMono
walkHi = Filter (pass Hann band): 1500, 0, 100

frameStep = dur_in / walk_frames

# ---- Sample features at each frame ----
for iF from 0 to walk_frames - 1
    t1 = iF * frameStep
    t2 = t1 + frameStep
    if t2 > dur_in
        t2 = dur_in
    endif

    # Brightness: hi/lo RMS ratio (log)
    selectObject: walkLo
    loRMS = Get root-mean-square: t1, t2
    selectObject: walkHi
    hiRMS = Get root-mean-square: t1, t2
    if loRMS < 0.00001
        loRMS = 0.00001
    endif
    bright = hiRMS / loRMS
    if bright < 0.01
        bright = 0.01
    endif
    if bright > 100
        bright = 100
    endif
    wk_x_'iF' = ln(bright)

    # Tonalness: pitch stability × sqrt(HNR+1)
    selectObject: walkPitch
    pMean = Get mean: t1, t2, "Hertz"
    pStd  = Get standard deviation: t1, t2, "Hertz"
    if pMean = undefined or pMean = 0
        pStab = 0
    else
        if pStd = undefined
            pStd = 0
        endif
        pStab = 1 - min(1, pStd / (pMean + 0.001))
        if pStab < 0
            pStab = 0
        endif
    endif

    selectObject: walkHarm
    hVal = Get mean: t1, t2
    if hVal = undefined
        hVal = 0
    endif
    if hVal < 0
        hVal = 0
    endif

    wk_y_'iF' = pStab * sqrt(hVal + 1)
endfor

# ---- Normalise to [-1, 1] ----
wk_xMin = wk_x_0
wk_xMax = wk_x_0
wk_yMin = wk_y_0
wk_yMax = wk_y_0

for iF from 1 to walk_frames - 1
    if wk_x_'iF' < wk_xMin
        wk_xMin = wk_x_'iF'
    endif
    if wk_x_'iF' > wk_xMax
        wk_xMax = wk_x_'iF'
    endif
    if wk_y_'iF' < wk_yMin
        wk_yMin = wk_y_'iF'
    endif
    if wk_y_'iF' > wk_yMax
        wk_yMax = wk_y_'iF'
    endif
endfor

wk_xRange = wk_xMax - wk_xMin
wk_yRange = wk_yMax - wk_yMin
if wk_xRange < 0.0001
    wk_xRange = 1
endif
if wk_yRange < 0.0001
    wk_yRange = 1
endif

for iF from 0 to walk_frames - 1
    wk_x_'iF' = (wk_x_'iF' - wk_xMin) / wk_xRange * 2 - 1
    wk_y_'iF' = (wk_y_'iF' - wk_yMin) / wk_yRange * 2 - 1
endfor

removeObject: walkMono, walkPitch, walkHarm, walkInt, walkLo, walkHi

appendInfoLine: "  Walk computed."

# ===========================================================================
# VISUALIZATION
# ===========================================================================

resultName$ = output_prefix$ + "_" + soundName$

if draw_visualization
    appendInfoLine: "Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # ── Title ────────────────────────────────────────────────────────────
    Select outer viewport: 0, 8, 0, 0.60
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.70, "half", "##IRCAM RAVE: " + modelFile$ + "##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.15, "half",
        ... soundName$
        ... + "  |  normalize=" + normalizeStr$
        ... + "  |  gain=" + fixed$(gain_dB, 1) + " dB"
        ... + "  |  shape=" + inputShapeStr$

    # ── Input waveform ───────────────────────────────────────────────────
    Select outer viewport: 0, 8, 0.65, 1.50
    Select inner viewport: 0.55, 7.65, 0.70, 1.45
    selectObject: soundObj
    if nch_in > 1
        Extract one channel: 1
        vizIn = selected("Sound")
    else
        Copy: "vizIn"
        vizIn = selected("Sound")
    endif
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    removeObject: vizIn
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"

    # ── Output waveform ──────────────────────────────────────────────────
    Select outer viewport: 0, 8, 1.55, 2.40
    Select inner viewport: 0.55, 7.65, 1.60, 2.35
    selectObject: resultSound
    Colour: "{0.15, 0.45, 0.70}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"

    # ── Input spectrogram (left half) ────────────────────────────────────
    Select outer viewport: 0, 4.1, 2.50, 3.85
    Select inner viewport: 0.55, 3.85, 2.60, 3.75
    selectObject: soundObj
    if nch_in > 1
        Extract one channel: 1
        vizSpecIn = selected("Sound")
    else
        Copy: "vizSpecIn"
        vizSpecIn = selected("Sound")
    endif
    To Spectrogram: 0.02, 5000, 0.005, 20, "Gaussian"
    specIn = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    removeObject: specIn, vizSpecIn
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Input spectrogram"

    # ── Output spectrogram (right half) ──────────────────────────────────
    Select outer viewport: 4.1, 8, 2.50, 3.85
    Select inner viewport: 4.40, 7.65, 2.60, 3.75
    selectObject: resultSound
    if nch_out > 1
        Extract one channel: 1
        vizSpecOut = selected("Sound")
    else
        Copy: "vizSpecOut"
        vizSpecOut = selected("Sound")
    endif
    specStep = max(0.002, dur_out / 2000)
    To Spectrogram: 0.02, 5000, specStep, 20, "Gaussian"
    specOut = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    removeObject: specOut, vizSpecOut
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Output spectrogram"

    # ── Latent walk panel ────────────────────────────────────────────────
    # Occupies bottom-left 4 cm wide × 2 cm tall section
    Select outer viewport: 0, 8, 3.95, 6.60
    Select inner viewport: 0.75, 7.50, 4.05, 6.50

    Axes: -1.15, 1.15, -1.15, 1.15

    # Background
    Paint rectangle: "{0.96, 0.96, 0.99}", -1.15, 1.15, -1.15, 1.15

    # Faint zero-axes
    Colour: "{0.78, 0.78, 0.84}"
    Line width: 1
    Draw line: -1.15, 0, 1.15, 0
    Draw line: 0, -1.15, 0, 1.15

    # Trajectory drawn in 4 colour segments: navy → violet → magenta → orange
    # giving an intuitive "time arrow" even without a legend
    nSegs = 4

    for iSeg from 0 to nSegs - 1
        if iSeg = 0
            Colour: "{0.10, 0.20, 0.55}"
        elsif iSeg = 1
            Colour: "{0.40, 0.15, 0.65}"
        elsif iSeg = 2
            Colour: "{0.75, 0.20, 0.45}"
        else
            Colour: "{0.90, 0.50, 0.10}"
        endif
        Line width: 2

        segStart = round(iSeg * walk_frames / nSegs)
        segEnd   = round((iSeg + 1) * walk_frames / nSegs)
        if segEnd >= walk_frames
            segEnd = walk_frames - 1
        endif

        for iF from segStart to segEnd - 1
            iN = iF + 1
            Draw line: wk_x_'iF', wk_y_'iF', wk_x_'iN', wk_y_'iN'
        endfor
    endfor

    Line width: 1

    # Small dots at every frame, coloured by segment
    for iF from 0 to walk_frames - 1
        segIdx = floor(iF * nSegs / walk_frames)
        if segIdx >= nSegs
            segIdx = nSegs - 1
        endif
        if segIdx = 0
            dotCol$ = "{0.10, 0.20, 0.55}"
        elsif segIdx = 1
            dotCol$ = "{0.40, 0.15, 0.65}"
        elsif segIdx = 2
            dotCol$ = "{0.75, 0.20, 0.45}"
        else
            dotCol$ = "{0.90, 0.50, 0.10}"
        endif
        Paint circle (mm): dotCol$, wk_x_'iF', wk_y_'iF', 1.0
    endfor

    # Start (green) and end (red) markers
    iLast = walk_frames - 1
    Paint circle (mm): "{0.15, 0.70, 0.30}", wk_x_0,      wk_y_0,      2.8
    Paint circle (mm): "{0.80, 0.15, 0.15}", wk_x_'iLast', wk_y_'iLast', 2.8

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Tonalness →"
    Text bottom: "yes", "Brightness →"
    Text top: "no", "Latent walk — " + string$(walk_frames) + " frames  |  green = start  ·  red = end  |  dark → light = time"

    # ── Summary panel ────────────────────────────────────────────────────
    Select outer viewport: 0, 8, 6.70, 7.35
    Select inner viewport: 0.55, 7.65, 6.75, 7.30
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.78, "half", "##" + resultName$ + "##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.32, "half",
        ... "In: " + fixed$(dur_in, 2) + "s  " + string$(nch_in) + "ch  " + string$(sr_in) + " Hz"
        ... + "  |  Out: " + fixed$(dur_out, 2) + "s  " + string$(nch_out) + "ch  " + string$(sr_out) + " Hz"
        ... + "  |  RMS: " + fixed$(rms_in, 4) + " → " + fixed$(rms_out, 4) + "  Peak: " + fixed$(peak_out, 4)
        ... + "  |  Model: " + modelFile$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1

    appendInfoLine: "Visualization complete."
endif

appendInfoLine: ""
appendInfoLine: "Done."

selectObject: resultSound
if play_result
    Play
endif
