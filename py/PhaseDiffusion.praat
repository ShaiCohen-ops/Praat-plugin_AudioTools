# ============================================================
# Praat AudioTools - PhaseDiffusion.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 5.1 (2026) - Unified Cross-Platform Version
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   AI Phase Diffusion Engine — Paulstretch architecture with latent
#   autoencoder integration.  Trains a small neural network (NumpyAutoencoder)
#   from scratch on the input signal's own spectral patches, then uses the
#   learned latent space to guide phase and magnitude diffusion.
#
#   This script is part of the latent suite:
#   same NumpyAutoencoder + K-means++ + log-Mel pipeline as
#   latent_diffusion.py, latent_barycentric.py, latent_folding.py, etc.
#
#   Models:
#     PCA     — AE-weighted paulstretch.  Per-bin coherence weights come
#               from the autoencoder's reconstruction error: tonal / structured
#               frequency bands (low error) receive more phase randomisation.
#               Different signals produce genuinely different weight patterns.
#
#     AR      — AR(1) IIR magnitude smearing, gated by AE coherence.
#               Bins that are BOTH temporally sustained (high AR coeff)
#               AND spectrally structured (low AE error) get the heaviest
#               magnitude smear.  Noisy / transient bins are protected.
#
#     Latent  — Full latent-space diffusion.  Each event's latent vector Z
#               is walked toward its cluster centroid via temperature-annealed
#               gradient descent (same engine as latent_diffusion.py).
#               The decoded magnitude envelope of the diffused Z becomes the
#               spectral shape for that event's paulstretch window.
#               Result: each moment sounds like a blend of acoustically similar
#               moments from the same recording, navigated by temperature.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# ---- SELECTION CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

inputSound = selected("Sound")
inputName$ = selected$("Sound")

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

# ---- PATHS & UNIFIED CROSS-PLATFORM FIX ----
pluginDirRaw$ = preferencesDirectory$ + "/plugin_AudioTools/"
pluginDir$ = replace_regex$(pluginDirRaw$, "\\", "/", 0)

pythonScript$ = pluginDir$ + "py/phase_diffusion_ai.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/phase_diffusion_ai.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: phase_diffusion_ai.py" + newline$ + "Expected at: " + pluginDir$ + "py/ or next to this script."
endif

tempInput$   = temporaryDirectory$ + "/temp_phasediff_input.wav"
tempOutput$  = temporaryDirectory$ + "/temp_phasediff_output.wav"
statusFile$  = temporaryDirectory$ + "/temp_phasediff_status.ok"
probePy$     = temporaryDirectory$ + "/temp_phasediff_probe.py"
probeMarker$ = temporaryDirectory$ + "/temp_phasediff_probe.ok"

# Enforce forward slashes for all temporary paths passed to python
pythonScriptJ$ = replace_regex$(pythonScript$, "\\", "/", 0)
tempInputJ$    = replace_regex$(tempInput$, "\\", "/", 0)
tempOutputJ$   = replace_regex$(tempOutput$, "\\", "/", 0)
statusFileJ$   = replace_regex$(statusFile$, "\\", "/", 0)
probePyJ$      = replace_regex$(probePy$, "\\", "/", 0)
probeMarkerJ$  = replace_regex$(probeMarker$, "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(tempInput$)
        deleteFile: tempInput$
    endif
    if fileReadable(tempOutput$)
        deleteFile: tempOutput$
    endif
    if fileReadable(statusFile$)
        deleteFile: statusFile$
    endif
    if fileReadable(probePy$)
        deleteFile: probePy$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
endproc

@cleanUpTempFiles

# ---- FORM ----
form AI Phase Diffusion v5.1
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Veil
        option Spectral Fog
        option Ambient Wash
        option Drone Cloud
        option Stutter Field
        option Formant Ghost
        option Phase Plasma
        option Void
        option Latent Drift
        option Latent Morph
        option Latent Deep
    comment === Core Parameters ===
    real    Diffusion_amount 0.70
    integer Diffusion_steps  30
    integer Window_size      8192
    integer Hop_size         2048
    real    Mag_smear        1.0
    comment === Model ===
    optionmenu Model: 1
        option Phase PCA
        option Phase AR
        option Latent
    comment === Autoencoder ===
    integer Latent_size   8
    integer Train_steps   150
    integer N_clusters    4
    real    Temperature   1.0
    comment === Options ===
    boolean Preserve_transients 1
    boolean Draw_visualization  1
    boolean Play_result         1
    boolean Debug               0
endform

# ---- PRESET APPLICATION ----
if preset = 2
    diffusion_amount    = 0.30
    diffusion_steps     = 20
    window_size         = 8192
    hop_size            = 2048
    mag_smear           = 0.4
    model               = 1
    latent_size         = 6
    train_steps         = 100
    n_clusters          = 3
    temperature         = 1.0
    preserve_transients = 1
    presetName$         = "Veil"
elsif preset = 3
    diffusion_amount    = 0.60
    diffusion_steps     = 30
    window_size         = 8192
    hop_size            = 2048
    mag_smear           = 1.0
    model               = 1
    latent_size         = 8
    train_steps         = 150
    n_clusters          = 4
    temperature         = 1.0
    preserve_transients = 1
    presetName$         = "SpectralFog"
elsif preset = 4
    diffusion_amount    = 0.80
    diffusion_steps     = 30
    window_size         = 16384
    hop_size            = 4096
    mag_smear           = 1.2
    model               = 1
    latent_size         = 8
    train_steps         = 150
    n_clusters          = 4
    temperature         = 1.0
    preserve_transients = 1
    presetName$         = "AmbientWash"
elsif preset = 5
    diffusion_amount    = 0.95
    diffusion_steps     = 30
    window_size         = 32768
    hop_size            = 8192
    mag_smear           = 1.8
    model               = 2
    latent_size         = 8
    train_steps         = 150
    n_clusters          = 4
    temperature         = 1.0
    preserve_transients = 0
    presetName$         = "DroneCloud"
elsif preset = 6
    diffusion_amount    = 0.70
    diffusion_steps     = 20
    window_size         = 2048
    hop_size            = 512
    mag_smear           = 0.8
    model               = 1
    latent_size         = 6
    train_steps         = 100
    n_clusters          = 3
    temperature         = 1.0
    preserve_transients = 1
    presetName$         = "StutterField"
elsif preset = 7
    diffusion_amount    = 0.55
    diffusion_steps     = 30
    window_size         = 8192
    hop_size            = 2048
    mag_smear           = 2.0
    model               = 2
    latent_size         = 8
    train_steps         = 150
    n_clusters          = 4
    temperature         = 1.0
    preserve_transients = 1
    presetName$         = "FormantGhost"
elsif preset = 8
    diffusion_amount    = 1.00
    diffusion_steps     = 30
    window_size         = 16384
    hop_size            = 4096
    mag_smear           = 1.5
    model               = 1
    latent_size         = 8
    train_steps         = 150
    n_clusters          = 4
    temperature         = 1.0
    preserve_transients = 0
    presetName$         = "PhasePlasma"
elsif preset = 9
    diffusion_amount    = 1.00
    diffusion_steps     = 50
    window_size         = 32768
    hop_size            = 8192
    mag_smear           = 2.0
    model               = 2
    latent_size         = 12
    train_steps         = 200
    n_clusters          = 6
    temperature         = 2.0
    preserve_transients = 0
    presetName$         = "Void"
elsif preset = 10
    diffusion_amount    = 0.50
    diffusion_steps     = 20
    window_size         = 8192
    hop_size            = 2048
    mag_smear           = 1.0
    model               = 3
    latent_size         = 8
    train_steps         = 150
    n_clusters          = 4
    temperature         = 0.5
    preserve_transients = 1
    presetName$         = "LatentDrift"
elsif preset = 11
    diffusion_amount    = 0.75
    diffusion_steps     = 40
    window_size         = 8192
    hop_size            = 2048
    mag_smear           = 1.0
    model               = 3
    latent_size         = 8
    train_steps         = 200
    n_clusters          = 5
    temperature         = 1.5
    preserve_transients = 1
    presetName$         = "LatentMorph"
elsif preset = 12
    diffusion_amount    = 1.00
    diffusion_steps     = 60
    window_size         = 16384
    hop_size            = 4096
    mag_smear           = 1.2
    model               = 3
    latent_size         = 12
    train_steps         = 250
    n_clusters          = 6
    temperature         = 3.0
    preserve_transients = 0
    presetName$         = "LatentDeep"
else
    presetName$ = "Custom"
endif

# ---- CLAMP ----
if diffusion_amount < 0
    diffusion_amount = 0
endif
if diffusion_amount > 1
    diffusion_amount = 1
endif
if diffusion_steps < 1
    diffusion_steps = 1
endif
if diffusion_steps > 200
    diffusion_steps = 200
endif
if window_size < 256
    window_size = 256
endif
if hop_size < 1
    hop_size = 1
endif
if hop_size > window_size / 2
    hop_size = window_size / 2
endif
if latent_size < 2
    latent_size = 2
endif
if latent_size > 32
    latent_size = 32
endif
if train_steps < 10
    train_steps = 10
endif
if train_steps > 500
    train_steps = 500
endif
if n_clusters < 2
    n_clusters = 2
endif
if n_clusters > 8
    n_clusters = 8
endif
if temperature < 0.05
    temperature = 0.05
endif

# ---- MODEL LABELS ----
if model = 1
    modelName$  = "pca"
    modelLabel$ = "Phase PCA"
    modelCol$   = "{0.2, 0.5, 0.8}"
elsif model = 2
    modelName$  = "ar"
    modelLabel$ = "Phase AR"
    modelCol$   = "{0.7, 0.3, 0.5}"
elsif model = 3
    modelName$  = "latent"
    modelLabel$ = "Latent"
    modelCol$   = "{0.2, 0.65, 0.45}"
endif

# ---- STATS ----
selectObject: inputSound
dur       = Get total duration
sr        = Get sampling frequency
nChannels = Get number of channels
rms_orig  = Get root-mean-square: 0, 0
winMs     = window_size / sr * 1000

# ---- INFO HEADER ----
clearinfo
writeInfoLine:  "=== AI Phase Diffusion v5.1 ==="
appendInfoLine: "Input:    ", inputName$
appendInfoLine: "Preset:   ", presetName$
appendInfoLine: "Model:    ", modelLabel$
appendInfoLine: "Duration: ", fixed$(dur, 2), " s  |  SR: ", sr, " Hz  |  Ch: ", nChannels
appendInfoLine: ""
appendInfoLine: "── Diffusion ──────────────────────────────────────────"
appendInfoLine: "  diffusion_amount : ", fixed$(diffusion_amount, 3)
appendInfoLine: "  diffusion_steps  : ", diffusion_steps, "  (latent: gradient steps)"
appendInfoLine: "  window_size      : ", window_size, " smp (", fixed$(winMs, 1), " ms)"
appendInfoLine: "  hop_size         : ", hop_size, " smp"
appendInfoLine: "  mag_smear        : ", fixed$(mag_smear, 2)
appendInfoLine: "  preserve_transients: ", if preserve_transients then "YES" else "NO" fi
appendInfoLine: "── Autoencoder ────────────────────────────────────────"
appendInfoLine: "  latent_size : ", latent_size
appendInfoLine: "  train_steps : ", train_steps
appendInfoLine: "  n_clusters  : ", n_clusters
appendInfoLine: "  temperature : ", fixed$(temperature, 3), "  (latent model)"
appendInfoLine: "────────────────────────────────────────────────────────"
appendInfoLine: ""

# ===========================================================================
# Stage 1 — Detect Python Dependencies
# ===========================================================================
appendInfoLine: "[1/4] Detecting Python dependencies..."

pyCode$ = "import sys" + newline$
pyCode$ = pyCode$ + "try:" + newline$
pyCode$ = pyCode$ + "    import numpy, soundfile" + newline$
pyCode$ = pyCode$ + "    with open('" + probeMarkerJ$ + "', 'w') as f:" + newline$
pyCode$ = pyCode$ + "        f.write('ok')" + newline$
pyCode$ = pyCode$ + "except Exception as e:" + newline$
pyCode$ = pyCode$ + "    print('Missing dependencies:', e)" + newline$
writeFile: probePy$, pyCode$

probeCmd$ = pythonCmd$ + " """ + probePyJ$ + """"
runSystem_nocheck: probeCmd$

if not fileReadable(probeMarker$)
    @cleanUpTempFiles
    exitScript: "Python not found or dependencies missing." + newline$ + "Please install: pip install numpy scipy soundfile"
endif

deleteFile: probeMarker$
deleteFile: probePy$
appendInfoLine: "  Python found: ", pythonCmd$

# ===========================================================================
# Stage 2 — Export Source Audio
# ===========================================================================
appendInfoLine: ""
appendInfoLine: "[2/4] Exporting input WAV..."
selectObject: inputSound
Save as WAV file: tempInput$

# ===========================================================================
# Stage 3 — Call Python Engine
# ===========================================================================
appendInfoLine: ""
appendInfoLine: "[3/4] Running AI Phase Diffusion v5.1..."

pythonCall$ = pythonCmd$ + " """ + pythonScriptJ$ + """"
    ... + " """ + tempInputJ$  + """"
    ... + " """ + tempOutputJ$ + """"
    ... + " --model "              + modelName$
    ... + " --diffusion-amount "   + fixed$(diffusion_amount, 6)
    ... + " --diffusion-steps "    + string$(diffusion_steps)
    ... + " --window-size "        + string$(window_size)
    ... + " --hop-size "           + string$(hop_size)
    ... + " --mag-smear "          + fixed$(mag_smear, 6)
    ... + " --latent-size "        + string$(latent_size)
    ... + " --train-steps "        + string$(train_steps)
    ... + " --n-clusters "         + string$(n_clusters)
    ... + " --temperature "        + fixed$(temperature, 6)
    ... + " --seed 42"
    ... + " --status-file """ + statusFileJ$ + """"

if preserve_transients
    pythonCall$ = pythonCall$ + " --preserve-transients"
endif
if debug
    pythonCall$ = pythonCall$ + " --debug"
endif

appendInfoLine: "── Python command ──────────────────────────────────────"
appendInfoLine: "  ", pythonCall$
appendInfoLine: "────────────────────────────────────────────────────────"

runSystem_nocheck: pythonCall$

# ---- CHECK SUCCESS ----
if not fileReadable(statusFile$)
    @cleanUpTempFiles
    exitScript: "Python Phase Diffusion engine failed." + newline$ + "Check terminal for error details."
endif

appendInfoLine: ""
appendInfoLine: "████ PYTHON OK ████"

# ===========================================================================
# Stage 4 — Import Result
# ===========================================================================
appendInfoLine: ""
appendInfoLine: "[4/4] Importing result..."
if not fileReadable(tempOutput$)
    @cleanUpTempFiles
    exitScript: "Output WAV not found: " + tempOutput$
endif

Read from file: tempOutput$
resultSound = selected("Sound")
resultName$ = inputName$ + "_phasediff"
Rename: resultName$
appendInfoLine: "  Result: ", resultName$

selectObject: resultSound
rms_out = Get root-mean-square: 0, 0
durOut  = Get total duration

###############################################################################
# VISUALIZATION
###############################################################################

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # === Title ===
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##AI Phase Diffusion  v5.1##"
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -1.3, "half",
        ... inputName$ + "  |  " + presetName$ + "  |  " + modelLabel$
        ... + "  |  amount=" + fixed$(diffusion_amount, 2)
        ... + "  |  latent=" + string$(latent_size)
        ... + "  |  clusters=" + string$(n_clusters)

    # === Original waveform ===
    Select outer viewport: 0, 8, 0.55, 1.35
    Select inner viewport: 0.6, 7.7, 0.6, 1.3
    selectObject: inputSound
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Text top: "no", fixed$(dur, 2) + " s  |  " + string$(nChannels) + " ch  |  " + string$(sr) + " Hz"

    # === Diffused waveform ===
    Select outer viewport: 0, 8, 1.35, 2.15
    Select inner viewport: 0.6, 7.7, 1.4, 2.1
    selectObject: resultSound
    Colour: modelCol$
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Diffused"
    Text bottom: "yes", "Time (s)"

    # === Original spectrogram ===
    Select outer viewport: 0, 8, 2.2, 3.45
    Select inner viewport: 0.6, 7.7, 2.3, 3.35

    selectObject: inputSound
    if nChannels > 1
        Extract one channel: 1
        tmpOrig = selected("Sound")
    else
        Copy: "tmpOrig"
        tmpOrig = selected("Sound")
    endif
    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    specOrig = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text top: "no", "Original spectrogram"
    removeObject: specOrig, tmpOrig

    # === Diffused spectrogram ===
    Select outer viewport: 0, 8, 3.45, 4.7
    Select inner viewport: 0.6, 7.7, 3.55, 4.6

    selectObject: resultSound
    if nChannels > 1
        Extract one channel: 1
        tmpDiff = selected("Sound")
    else
        Copy: "tmpDiff"
        tmpDiff = selected("Sound")
    endif
    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    specDiff = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Diffused spectrogram  (" + modelLabel$ + ")"
    removeObject: specDiff, tmpDiff

    # === Intensity comparison ===
    Select outer viewport: 0, 8, 4.8, 5.7
    Select inner viewport: 0.6, 7.7, 4.9, 5.6

    Axes: 0, dur, 30, 90
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, dur, 30, 90

    selectObject: inputSound
    if nChannels > 1
        Extract one channel: 1
        tmpOrigI = selected("Sound")
    else
        Copy: "tmpOrigI"
        tmpOrigI = selected("Sound")
    endif
    To Intensity: 100, 0, "yes"
    intOrig = selected("Intensity")
    selectObject: intOrig
    Colour: "{0.65, 0.65, 0.65}"
    Line width: 2
    Draw: 0, 0, 0, 0, "no"
    removeObject: intOrig, tmpOrigI

    selectObject: resultSound
    if nChannels > 1
        Extract one channel: 1
        tmpDiffI = selected("Sound")
    else
        Copy: "tmpDiffI"
        tmpDiffI = selected("Sound")
    endif
    To Intensity: 100, 0, "yes"
    intDiff = selected("Intensity")
    selectObject: intDiff
    Colour: modelCol$
    Line width: 2
    Draw: 0, 0, 0, 0, "no"
    removeObject: intDiff, tmpDiffI

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "dB"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Intensity  (grey = original  |  colour = diffused)"

    # === Latent / AE info panel ===
    Select outer viewport: 0, 8, 5.8, 6.75
    Select inner viewport: 0.6, 7.7, 5.9, 6.65

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.93, 0.94, 0.97}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.89, "half", "##Autoencoder / Latent Space##"

    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.68, "half",
        ... "Architecture: log-Mel (" + string$(40) + " bands) → hidden → latent(" + string$(latent_size) + ") → hidden → reconstruct"
    Text: 0.02, "left", 0.48, "half",
        ... "Training: " + string$(train_steps) + " steps  |  Adam + denoising + L2 reg  |  leaky ReLU"

    if model = 3
        Colour: "{0.15, 0.55, 0.35}"
        Text: 0.02, "left", 0.28, "half",
            ... "Latent model: " + string$(n_clusters) + " k-means++ clusters  |  temperature=" + fixed$(temperature, 2)
            ...  + "  |  " + string$(diffusion_steps) + " gradient steps per event"
        Text: 0.02, "left", 0.08, "half",
            ... "Each event Z walked toward cluster centroid → decoded → magnitude envelope for paulstretch"
    else
        Colour: "{0.3, 0.3, 0.3}"
        Text: 0.02, "left", 0.28, "half",
            ... "Coherence weights: AE reconstruction error projected → " + string$(window_size / 2 + 1) + " FFT bins"
        Text: 0.02, "left", 0.08, "half",
            ... "Low AE error (structured bins) → targeted diffusion  |  High error (noise bins) → protected"
    endif

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # === Parameter / summary panel ===
    Select outer viewport: 0, 8, 6.8, 7.75
    Select inner viewport: 0.6, 7.7, 6.9, 7.65

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.88, "half", "##Preset: " + presetName$ + "##"

    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.65, "half",
        ... "model: " + modelLabel$
        ... + "  |  amount: " + fixed$(diffusion_amount, 2)
        ... + "  |  steps: " + string$(diffusion_steps)
        ... + "  |  smear: " + fixed$(mag_smear, 2)
    Text: 0.02, "left", 0.44, "half",
        ... "window: " + string$(window_size) + " (" + fixed$(winMs, 1) + " ms)"
        ... + "  |  hop: " + string$(hop_size)
        ... + "  |  trans: " + if preserve_transients then "protected" else "free" fi
    Text: 0.02, "left", 0.23, "half",
        ... "RMS: " + fixed$(rms_orig, 4) + " → " + fixed$(rms_out, 4)
        ... + "  (" + fixed$(rms_out / (rms_orig + 0.000001), 2) + "x)"
        ... + "  |  dur: " + fixed$(dur, 2) + " s  |  " + string$(sr) + " Hz"

    Colour: "Black"
    Text: 0.62, "left", 0.88, "half", "##Latent##"
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.62, "left", 0.65, "half",
        ... "latent_size: " + string$(latent_size)
    Text: 0.62, "left", 0.44, "half",
        ... "train_steps: " + string$(train_steps)
    Text: 0.62, "left", 0.23, "half",
        ... "clusters: " + string$(n_clusters)
        ... + "  T=" + fixed$(temperature, 2)

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    appendInfoLine: "  Visualization drawn."

else
    appendInfoLine: "[4/4] Visualization skipped."
endif

# ---- PLAY ----
if play_result
    selectObject: resultSound
    Play
endif

# ---- CLEANUP ----
@cleanUpTempFiles

# ---- SUMMARY ----
appendInfoLine: ""
appendInfoLine: "════════════════════════════════════════════════════"
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "  Output       : ", resultName$
appendInfoLine: "  Preset       : ", presetName$
appendInfoLine: "  Model        : ", modelLabel$, " (", modelName$, ")"
appendInfoLine: "  Amount       : ", fixed$(diffusion_amount, 3)
appendInfoLine: "  Window       : ", window_size, " smp (", fixed$(winMs, 1), " ms)"
appendInfoLine: "  Hop          : ", hop_size
appendInfoLine: "  Steps        : ", diffusion_steps
appendInfoLine: "  Smear        : ", fixed$(mag_smear, 2)
appendInfoLine: "  Transients   : ", if preserve_transients then "protected" else "free" fi
appendInfoLine: "── Autoencoder ─────────────────────────────────────"
appendInfoLine: "  Latent size  : ", latent_size
appendInfoLine: "  Train steps  : ", train_steps
appendInfoLine: "  Clusters     : ", n_clusters
appendInfoLine: "  Temperature  : ", fixed$(temperature, 3)
appendInfoLine: "── Signal ──────────────────────────────────────────"
appendInfoLine: "  RMS          : ", fixed$(rms_orig, 4), " → ", fixed$(rms_out, 4),
    ... "  (", fixed$(rms_out / (rms_orig + 0.000001), 2), "x)"
appendInfoLine: "════════════════════════════════════════════════════"

selectObject: resultSound