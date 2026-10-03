# ============================================================
# Praat AudioTools Plugin
# Script:      IRCAM_rave_model.praat
# Author:      Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email:       shai.cohen@biu.ac.il
# Version:     1.5.1 (2026)
# License:     MIT License
# Repository:  https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Runs an IRCAM RAVE TorchScript model (.ts, as shipped with nn~) on the
#   selected Sound, or reports what a model exposes.
#
#   Actions:
#     Process sound                  forward() = RAVE encode -> decode
#     Latent transform               encode() -> one operation -> decode():
#                                    scale, offset, dimension gain, mute,
#                                    isolate, smooth, freeze, jitter
#     Diagnose this model            methods, nn~ *_params buffers, sample
#                                    rate, latent size; no audio needed
#     Diagnose all models in folder  the same for every .ts in the folder
#
#   The figure shows input and output (spectrograms on one dB scale,
#   waveforms) and the model's TRUE latent trajectory when the model has
#   encode(); otherwise a clearly labelled feature proxy computed from the
#   input (brightness x tonalness), which is not the model's latent space.
#
# Pipeline:
#   Praat  : Sound -> WAV + key=value parameter file
#   Python : load model -> metadata -> resample to the model rate if it
#            declares one -> forward() -> (resample back) -> normalise once
#            -> gain -> float WAV; optional encode() pass for the figure
#   Praat  : result, Info report, figure, cleanup, play
#
# Changelog v1.5.1:
#   - Engine 1.5.1: energy noise independent of the Jitter operation
#     (same Seed field). Wording of the dimension hint and of Mute.
#
# Changelog v1.5:
#   - Latent energy (controlled instability) after the latent operation:
#     Variation mode Off (default, identical every run) / Seeded /
#     New each run (seed reported for later reproduction); Jitter or
#     Smooth drift; amount relative to each dimension spread (or absolute);
#     target all / one / high-variance dimensions. Shown in a second small
#     dialog only when Variation mode is not Off. Operation "None" applies
#     energy to the untouched latent. The eight operations are unchanged.
#
# Changelog v1.4:
#   - Latent transform action (needs encode + decode, present in all eight
#     RAVE models per the v1.3 diagnostics): eight operations on the latent
#     exactly as encode() returns it. The figure overlays the latent before
#     (grey) and after (colour) the operation.
#   - Process sound (forward) unchanged.
#
# Changelog v1.3:
#   - Normalisation happens once, in Python. v1.2 ended with an
#     unconditional "Scale peak: 0.99", so "none" and "rms" were silently
#     turned into peak normalisation. Now:
#       none = model output untouched, peak = peak 0.99 (the v1.2 sound,
#       default), rms = -20 dBFS with a peak guard.
#   - Gain is applied after normalisation, so it is audible (in v1.2 it was
#     applied before and cancelled).
#   - Diagnose actions, so the interface can later be built on what the
#     installed models really expose.
#   - Sample rate: resampled to the model rate when the model declares one
#     (and back to the input rate), with a "use as is" option = v1.2.
#   - Float WAV interchange (was 16-bit), fast WAV I/O.
#   - "Latent walk" renamed: the v1.2 panel was a feature proxy from the
#     input, not RAVE's latent space. The real latent trajectory (encode)
#     is shown when available; the proxy is labelled as such otherwise.
#   - Short form; details behind "Advanced". Device option (cpu/auto/cuda).
#   - Parameters passed in a file; session-tagged temporary files; Praat 7
#     trust request.
#
# Requires: Praat 6.3+; Python 3 with torch (and numpy).
# ============================================================

version$ = "1.5.1"

nSel = numberOfSelected("Sound")
soundObj = 0
soundName$ = ""
if nSel = 1
    soundObj = selected("Sound")
    soundName$ = selected$("Sound")
endif

# ---- FORM ----
form: "IRCAM RAVE Model v1.5.1"
    optionmenu: "Rave model", 1
        option: "break.ts"
        option: "darbouka_onnx.ts"
        option: "engine.ts"
        option: "InstantAlbania.ts"
        option: "isis.ts"
        option: "percussion.ts"
        option: "wheel.ts"
        option: "Custom (type name below)"
    sentence: "Custom model name", "mymodel.ts"
    sentence: "Models directory", "C:\Users\User\Documents\Max 9\Packages\nn_tilde\help"
    optionmenu: "Action", 1
        option: "Process sound (forward)"
        option: "Latent transform (encode - operation - decode)"
        option: "Diagnose this model"
        option: "Diagnose all models in folder"
    real: "Gain (dB)", "0.0"
    optionmenu: "Normalize", 2
        option: "none (model output untouched)"
        option: "peak (to 0.99, v1.2 sound)"
        option: "rms (-20 dBFS, peak-guarded)"
    boolean: "Advanced settings", 0
    boolean: "Draw visualisation", 1
    boolean: "Play result", 1
endform

# ---- ADVANCED (initialised first; the dialog only edits them) ----
input_shape = 1
output_channels = 1
sr_handling = 1
output_rate = 1
device = 1
show_latent = 1
output_prefix$ = "rave_out"
if advanced_settings
    beginPause: "RAVE — advanced settings"
        optionMenu: "Input shape", input_shape
            option: "Auto-detect"
            option: "[batch, channels, samples]"
            option: "[batch, 1, samples] mono"
            option: "[channels, samples] no batch"
        optionMenu: "Output channels", output_channels
            option: "Same as model output"
            option: "Force mono"
            option: "Force stereo"
        optionMenu: "Sr handling", sr_handling
            option: "Resample to the model rate (recommended)"
            option: "Use as is (v1.2 behaviour)"
        optionMenu: "Output rate", output_rate
            option: "Back to the input rate"
            option: "Keep the model rate"
        optionMenu: "Device", device
            option: "CPU"
            option: "Auto (CUDA if available)"
            option: "CUDA"
        boolean: "Show latent", show_latent
        sentence: "Output prefix", output_prefix$
    endPause: "Continue", 1
endif

# ---- LATENT TRANSFORM (only for that action) ----
latent_op = 1
latent_dim = 1
latent_amount = 1.5
smooth_ms = 200
freeze_pos = 0.5
freeze_dur = 5
latent_seed = 1
energy_mode = 1
energy_type = 2
energy_amount = 0.3
energy_smooth = 0.5
energy_target = 1
energy_dim = 1
energy_scale = 1
if action = 2
    beginPause: "RAVE — latent transform"
        comment: "encode() -> operation on the latent -> decode()"
        optionMenu: "Operation", latent_op
            option: "Scale all dimensions (x Amount)"
            option: "Offset (+ Amount; Dimension 0 = all)"
            option: "Dimension gain (x Amount)"
            option: "Mute dimension (set to 0)"
            option: "Isolate dimension (others 0)"
            option: "Smooth over time"
            option: "Freeze one frame"
            option: "Jitter (+ Amount x noise)"
            option: "None (energy layer only)"
        integer: "Dimension", string$(latent_dim)
        real: "Amount", string$(latent_amount)
        comment: "Dimension 1 is often the highest-variance dimension in PCA-ordered exports"
        positive: "Smoothing (ms)", string$(smooth_ms)
        real: "Freeze position (0-1)", string$(freeze_pos)
        positive: "Freeze duration (s)", string$(freeze_dur)
        integer: "Seed", string$(latent_seed)
        comment: "Variation: Off = identical result every run"
        optionMenu: "Variation mode", energy_mode
            option: "Off (deterministic)"
            option: "Seeded variation (reproducible)"
            option: "New variation each run"
    endPause: "Continue", 1
    latent_op = operation
    latent_dim = dimension
    latent_amount = amount
    smooth_ms = smoothing
    freeze_pos = freeze_position
    freeze_dur = freeze_duration
    latent_seed = seed
    energy_mode = variation_mode
    if energy_mode > 1
        beginPause: "RAVE — latent energy"
            comment: "Added after the operation: encode - operation - energy - decode"
            optionMenu: "Energy type", energy_type
                option: "Jitter (frame-to-frame grain)"
                option: "Smooth drift (organic motion)"
            real: "Energy amount (0-1)", string$(energy_amount)
            real: "Smoothness (0-1)", string$(energy_smooth)
            comment: "Smoothness (drift only): correlation time 0.05 s at 0 ... 5 s at 1"
            optionMenu: "Energy target", energy_target
                option: "All dimensions"
                option: "One dimension"
                option: "High-variance dimensions"
            integer: "Energy dimension", string$(energy_dim)
            optionMenu: "Energy scale", energy_scale
                option: "Relative to each dimension spread"
                option: "Absolute (latent units)"
        endPause: "Continue", 1
        energy_type = energy_type
        energy_amount = energy_amount
        energy_smooth = smoothness
        energy_target = energy_target
        energy_dim = energy_dimension
        energy_scale = energy_scale
        if energy_amount < 0 or energy_amount > 1 or energy_smooth < 0 or energy_smooth > 1
            exitScript: "Energy amount and Smoothness must be between 0 and 1."
        endif
    endif
endif

# ---- MODEL PATH ----
if rave_model <= 7
    modelFile$ = rave_model$
else
    modelFile$ = custom_model_name$
    if modelFile$ = ""
        exitScript: "Custom model selected but no file name given."
    endif
    if right$(modelFile$, 3) <> ".ts"
        modelFile$ = modelFile$ + ".ts"
    endif
endif
if models_directory$ = ""
    exitScript: "Please give the models directory."
endif
modelsDir$ = replace$(models_directory$, "\", "/", 0)
if right$(modelsDir$, 1) <> "/"
    modelsDir$ = modelsDir$ + "/"
endif
modelPath$ = modelsDir$ + modelFile$
if action <> 4 and not fileReadable(modelPath$)
    exitScript: "Model not found: " + modelPath$
endif
if action <= 2 and nSel <> 1
    exitScript: "Processing needs exactly one selected Sound (diagnose actions need none)."
endif
if output_prefix$ = ""
    output_prefix$ = "rave_out"
endif

# ---- PRAAT 7 TRUST ----
if praatVersion >= 7000
    trustOK = askForTrust()
    if not trustOK
        exitScript: "The RAVE runner needs permission to write temporary files and run Python."
    endif
endif

# ---- PATHS / TEMP ----
pluginDir$ = replace$(preferencesDirectory$, "\", "/", 0) + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/run_model_ts.py"
if not fileReadable(pythonScript$)
    pythonScript$ = replace$(defaultDirectory$, "\", "/", 0) + "/run_model_ts.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find run_model_ts.py (expected in " + pluginDir$ + "py/ or next to this script)."
endif
tmpDir$ = replace$(temporaryDirectory$, "\", "/", 0) + "/"
sessionTag$ = replace_regex$(date$(), "[^0-9]", "", 0) + "_" + string$(randomInteger(100000, 999999))
tmp$ = tmpDir$ + "rave_" + sessionTag$ + "_"
tempInput$ = tmp$ + "input.wav"
tempOutput$ = tmp$ + "output.wav"
tempError$ = tmp$ + "error.txt"
manifestFile$ = tmp$ + "manifest.txt"
latentFile$ = tmp$ + "latent.txt"
latentInFile$ = tmp$ + "latent_in.txt"
paramFile$ = tmp$ + "params.txt"

procedure cleanUp
    if fileReadable(latentInFile$)
        deleteFile: latentInFile$
    endif
    for .k from 1 to 6
        if .k = 1
            .f$ = tempInput$
        elsif .k = 2
            .f$ = tempOutput$
        elsif .k = 3
            .f$ = tempError$
        elsif .k = 4
            .f$ = manifestFile$
        elsif .k = 5
            .f$ = latentFile$
        else
            .f$ = paramFile$
        endif
        if fileReadable(.f$)
            deleteFile: .f$
        endif
    endfor
endproc

# ---- PYTHON WITH TORCH (probe, as in v1.2) ----
probePy$ = tmp$ + "probe.py"
probeOK$ = tmp$ + "probe.ok"
writeFileLine: probePy$, "import sys"
appendFileLine: probePy$, "import torch"
appendFileLine: probePy$, "open(sys.argv[1], ""w"").write(""ok"")"
nCand = 0
if macintosh
    nCand = nCand + 1
    candidate'nCand'$ = "/opt/homebrew/bin/python3"
    nCand = nCand + 1
    candidate'nCand'$ = "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3"
    nCand = nCand + 1
    candidate'nCand'$ = "/usr/local/bin/python3"
    nCand = nCand + 1
    candidate'nCand'$ = "python3"
elsif windows
    nCand = nCand + 1
    candidate'nCand'$ = "python"
    nCand = nCand + 1
    candidate'nCand'$ = "py"
else
    nCand = nCand + 1
    candidate'nCand'$ = "python3"
    nCand = nCand + 1
    candidate'nCand'$ = "python"
endif
pythonCmd$ = ""
triedList$ = ""
for iCand to nCand
    thisCandidate$ = candidate'iCand'$
    triedList$ = triedList$ + "  - " + thisCandidate$ + newline$
    if pythonCmd$ = ""
        isBare = (thisCandidate$ = "python3") or (thisCandidate$ = "python") or (thisCandidate$ = "py")
        if isBare or fileReadable(thisCandidate$)
            nocheck runSubprocess: thisCandidate$, probePy$, probeOK$
            if fileReadable(probeOK$)
                pythonCmd$ = thisCandidate$
                deleteFile: probeOK$
            endif
        endif
    endif
endfor
deleteFile: probePy$
if pythonCmd$ = ""
    exitScript: "No Python with PyTorch (torch) found." + newline$ + "Tried:" + newline$ + triedList$ + "Fix: pip install torch numpy"
endif

# ---- PARAMETERS ----
if action = 1
    actionTok$ = "process"
elsif action = 2
    actionTok$ = "latent"
elsif action = 3
    actionTok$ = "diagnose"
else
    actionTok$ = "diagnose_folder"
endif
if latent_op = 1
    opTok$ = "scale"
elsif latent_op = 2
    opTok$ = "offset"
elsif latent_op = 3
    opTok$ = "dim_gain"
elsif latent_op = 4
    opTok$ = "mute"
elsif latent_op = 5
    opTok$ = "isolate"
elsif latent_op = 6
    opTok$ = "smooth"
elsif latent_op = 7
    opTok$ = "freeze"
elsif latent_op = 8
    opTok$ = "jitter"
else
    opTok$ = "none"
endif
energyModeTok$ = "off"
if energy_mode = 2
    energyModeTok$ = "seeded"
elsif energy_mode = 3
    energyModeTok$ = "fresh"
endif
energyTypeTok$ = "drift"
if energy_type = 1
    energyTypeTok$ = "jitter"
endif
energyTargetTok$ = "all"
if energy_target = 2
    energyTargetTok$ = "one"
elsif energy_target = 3
    energyTargetTok$ = "high_variance"
endif
energyScaleTok$ = "relative"
if energy_scale = 2
    energyScaleTok$ = "absolute"
endif
normTok$ = "peak"
if normalize = 1
    normTok$ = "none"
elsif normalize = 3
    normTok$ = "rms"
endif
shapeTok$ = "auto"
if input_shape = 2
    shapeTok$ = "BCT"
elsif input_shape = 3
    shapeTok$ = "B1T"
elsif input_shape = 4
    shapeTok$ = "CT"
endif
outChTok$ = "auto"
if output_channels = 2
    outChTok$ = "mono"
elsif output_channels = 3
    outChTok$ = "stereo"
endif
srTok$ = "resample"
if sr_handling = 2
    srTok$ = "as_is"
endif
outRateTok$ = "input"
if output_rate = 2
    outRateTok$ = "model"
endif
deviceTok$ = "cpu"
if device = 2
    deviceTok$ = "auto"
elsif device = 3
    deviceTok$ = "cuda"
endif

if action <= 2
    selectObject: soundObj
    dur_in = Get total duration
    sr_in = Get sampling frequency
    nch_in = Get number of channels
    Save as WAV file: tempInput$
endif

writeFileLine: paramFile$, "action=" + actionTok$
appendFileLine: paramFile$, "input=" + tempInput$
appendFileLine: paramFile$, "output=" + tempOutput$
appendFileLine: paramFile$, "model=" + modelPath$
appendFileLine: paramFile$, "models_dir=" + modelsDir$
appendFileLine: paramFile$, "error=" + tempError$
appendFileLine: paramFile$, "manifest=" + manifestFile$
appendFileLine: paramFile$, "latent_csv=" + latentFile$
appendFileLine: paramFile$, "gain=" + string$(gain)
appendFileLine: paramFile$, "normalize=" + normTok$
appendFileLine: paramFile$, "input_shape=" + shapeTok$
appendFileLine: paramFile$, "out_ch=" + outChTok$
appendFileLine: paramFile$, "sr_mode=" + srTok$
appendFileLine: paramFile$, "out_rate=" + outRateTok$
appendFileLine: paramFile$, "device=" + deviceTok$
appendFileLine: paramFile$, "latent_viz=" + string$(show_latent)
appendFileLine: paramFile$, "latent_in_csv=" + latentInFile$
appendFileLine: paramFile$, "latent_op=" + opTok$
appendFileLine: paramFile$, "latent_dim=" + string$(latent_dim)
appendFileLine: paramFile$, "latent_amount=" + string$(latent_amount)
appendFileLine: paramFile$, "smooth_ms=" + string$(smooth_ms)
appendFileLine: paramFile$, "freeze_pos=" + string$(freeze_pos)
appendFileLine: paramFile$, "freeze_dur=" + string$(freeze_dur)
appendFileLine: paramFile$, "seed=" + string$(latent_seed)
appendFileLine: paramFile$, "energy_mode=" + energyModeTok$
appendFileLine: paramFile$, "energy_type=" + energyTypeTok$
appendFileLine: paramFile$, "energy_amount=" + string$(energy_amount)
appendFileLine: paramFile$, "energy_smooth=" + string$(energy_smooth)
appendFileLine: paramFile$, "energy_target=" + energyTargetTok$
appendFileLine: paramFile$, "energy_dim=" + string$(energy_dim)
appendFileLine: paramFile$, "energy_scale=" + energyScaleTok$

writeInfoLine: "=== IRCAM RAVE Model v", version$, " ==="
if action <= 2
    appendInfoLine: "Sound:   ", soundName$, "  (", fixed$(dur_in, 2), " s, ", sr_in, " Hz, ", nch_in, " ch)"
    appendInfoLine: "Model:   ", modelPath$
elsif action = 3
    appendInfoLine: "Diagnose: ", modelPath$
else
    appendInfoLine: "Diagnose folder: ", modelsDir$
endif
appendInfoLine: "Python:  ", pythonCmd$
appendInfoLine: "Running..."
nocheck runSubprocess: pythonCmd$, pythonScript$, paramFile$

if fileReadable(tempError$)
    appendInfoLine: ""
    appendInfoLine: "--- Python error ---"
    appendInfoLine: readFile$(tempError$)
    @cleanUp
    exitScript: "The RAVE runner failed — see the Info window."
endif

man$ = ""
if fileReadable(manifestFile$)
    man$ = newline$ + readFile$(manifestFile$)
endif
procedure man: .key$
    .s$ = extractLine$(man$, newline$ + .key$ + "=")
endproc

# report lines (model description) — shown for every action
appendInfoLine: ""
repRest$ = man$
while index(repRest$, newline$ + "report=") > 0
    repP = index(repRest$, newline$ + "report=")
    repRest$ = mid$(repRest$, repP + 8, length(repRest$))
    repE = index(repRest$, newline$)
    if repE = 0
        repE = length(repRest$) + 1
    endif
    appendInfoLine: left$(repRest$, repE - 1)
    repRest$ = mid$(repRest$, repE, length(repRest$))
endwhile

if action >= 3
    @cleanUp
    appendInfoLine: "Diagnostics only — no audio processed."
    exitScript: ""
endif

if not fileReadable(tempOutput$)
    @cleanUp
    exitScript: "Output WAV was not created — see the Info window."
endif

resultSound = Read from file: tempOutput$
Rename: output_prefix$ + "_" + soundName$
dur_out = Get total duration
sr_out = Get sampling frequency
nch_out = Get number of channels
rms_out = Get root-mean-square: 0, 0
peak_out = Get absolute extremum: 0, 0, "None"

@man: "sr_handling"
srHandling$ = man.s$
@man: "normalisation"
normDone$ = man.s$
@man: "rms_note"
rmsNote$ = man.s$
@man: "warning"
warn$ = man.s$
@man: "latent_viz"
latentNote$ = man.s$
@man: "model_sr"
modelSR$ = man.s$
@man: "latent_size"
latentSize$ = man.s$
@man: "methods"
methods$ = man.s$
@man: "device"
devUsed$ = man.s$
@man: "input_tensor"
inTensor$ = man.s$
@man: "latent_op_desc"
opDesc$ = man.s$
@man: "latent_rule"
opRule$ = man.s$
@man: "freeze_time"
freezeT$ = man.s$
@man: "energy"
energyDesc$ = man.s$
@man: "energy_seed"
energySeed$ = man.s$

appendInfoLine: "--- Processing ---"
if action = 2
    appendInfoLine: "  latent transform: ", opDesc$
    appendInfoLine: "    rule: ", opRule$
    appendInfoLine: "  energy: ", energyDesc$
    if energy_mode = 3
        appendInfoLine: "    (new variation: enter seed ", energySeed$, " in Seeded mode to reproduce this result)"
    endif
endif
appendInfoLine: "  sample rate: ", srHandling$
appendInfoLine: "  input tensor: ", inTensor$, "   device: ", devUsed$
appendInfoLine: "  normalisation: ", normDone$, "   gain after it: ", fixed$(gain, 1), " dB"
if rmsNote$ <> ""
    appendInfoLine: "  ", rmsNote$
endif
if warn$ <> ""
    appendInfoLine: "  WARNING: ", warn$
endif
appendInfoLine: "  figure: ", latentNote$
appendInfoLine: ""
appendInfoLine: "Result: ", output_prefix$, "_", soundName$, "  ", fixed$(dur_out, 3), " s, ", nch_out, " ch, ", sr_out, " Hz, peak ", fixed$(peak_out, 4), ", RMS ", fixed$(rms_out, 5)
if rms_out < 0.0001
    appendInfoLine: "WARNING: output is (nearly) silent — check the model."
endif

hasLatent = fileReadable(latentFile$)
if draw_visualisation
    @drawFigure
endif
@cleanUp
selectObject: resultSound
if play_result
    Play
endif

# ============================================================
# FIGURE
# ============================================================
procedure sanitize: .s$
    .s$ = replace$(.s$, "\", "\bs", 0)
    .s$ = replace$(.s$, "_", "\_ ", 0)
    .s$ = replace$(.s$, "%", "\% ", 0)
    .s$ = replace$(.s$, "#", "\# ", 0)
    .s$ = replace$(.s$, "^", "\^ ", 0)
    .out$ = .s$
endproc

procedure niceStep: .span, .n
    .raw = .span / .n
    if .raw <= 0
        .raw = 1
    endif
    .p = 10 ^ floor(log10(.raw))
    .m = .raw / .p
    if .m < 1.5
        .step = .p
    elsif .m < 3.5
        .step = 2 * .p
    elsif .m < 7.5
        .step = 5 * .p
    else
        .step = 10 * .p
    endif
endproc

procedure railLabel: .y0, .y1, .name$
    Font size: 7
    Select inner viewport: 0.6, 7.7, .y0, .y1
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text special: -0.068, "centre", 0.5, "bottom", "Helvetica", 7, "90", .name$
endproc

procedure dimColour: .i
    .rgb$ = "{0.20, 0.40, 0.80}"
    if .i = 2
        .rgb$ = "{0.85, 0.35, 0.15}"
    elsif .i = 3
        .rgb$ = "{0.15, 0.60, 0.35}"
    elsif .i = 4
        .rgb$ = "{0.60, 0.25, 0.70}"
    elsif .i = 5
        .rgb$ = "{0.85, 0.65, 0.10}"
    elsif .i = 6
        .rgb$ = "{0.10, 0.65, 0.75}"
    elsif .i = 7
        .rgb$ = "{0.75, 0.20, 0.45}"
    elsif .i >= 8
        .rgb$ = "{0.45, 0.45, 0.45}"
    endif
endproc

procedure paintSpec: .snd, .x0, .x1, .y0, .y1, .setScale
    selectObject: .snd
    .d = Get total duration
    .mono = Convert to mono
    .spec = To Spectrogram: 0.02, 5000, max(0.002, .d / 1000), 20, "Gaussian"
    if .setScale
        .mat = To Matrix
        .pmax = Get maximum
        removeObject: .mat
        specMaxDb = 10 * log10(max(.pmax, 1e-30) / 4e-10)
    endif
    selectObject: .spec
    Select inner viewport: .x0, .x1, .y0, .y1
    Paint: 0, 0, 0, 5000, specMaxDb, "no", 50, 6, 0, "no"
    removeObject: .spec, .mono
endproc

procedure drawFigure
    Erase all
    Line width: 1
    t0 = 0.10
    t1 = 0.60
    a0 = 0.95
    a1 = 2.45
    w0 = 2.95
    w1 = 3.75
    l0 = 4.25
    l1 = 6.55
    s0 = 7.15
    s1 = 8.20
    canvasH = 8.30

    Font size: 13
    Select inner viewport: 0.6, 7.7, t0, t1
    Axes: 0, 1, 0, 1
    Colour: "Black"
    @sanitize: modelFile$
    Text: 0.5, "centre", 0.72, "half", "##IRCAM RAVE — " + sanitize.out$ + "##"
    Font size: 7
    Select inner viewport: 0.6, 7.7, t0, t1
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.42}"
    if action = 2
        .eTag$ = ""
        if energy_mode > 1
            .eTag$ = "   |   + energy (seed " + energySeed$ + ")"
        endif
        @sanitize: soundName$ + "   |   latent: " + opDesc$ + .eTag$ + "   |   model rate " + modelSR$
    else
        @sanitize: soundName$ + "   |   model rate " + modelSR$ + "   |   " + normDone$
    endif
    Text: 0.5, "centre", 0.18, "half", sanitize.out$

    # spectrograms, shared dB scale (input sets it)
    Font size: 7
    @paintSpec: soundObj, 0.6, 3.95, a0, a1, 1
    Select inner viewport: 0.6, 3.95, a0, a1
    Axes: 0, dur_in, 0, 5000
    Colour: "Black"
    Text top: "no", "##Input## (" + fixed$(dur_in, 2) + " s)"
    Select inner viewport: 0.6, 3.95, a0, a1
    Axes: 0, dur_in, 0, 5000
    Draw inner box
    @niceStep: dur_in, 4
    Marks bottom every: 1, niceStep.step, "yes", "yes", "no"
    Marks left every: 1, 1000, "yes", "yes", "no"
    @paintSpec: resultSound, 4.35, 7.7, a0, a1, 0
    Select inner viewport: 4.35, 7.7, a0, a1
    Axes: 0, dur_out, 0, 5000
    Colour: "Black"
    Text top: "no", "##Output## — input dB scale (" + fixed$(dur_out, 2) + " s)"
    Select inner viewport: 4.35, 7.7, a0, a1
    Axes: 0, dur_out, 0, 5000
    Draw inner box
    @niceStep: dur_out, 4
    Marks bottom every: 1, niceStep.step, "yes", "yes", "no"
    @railLabel: a0, a1, "Freq (Hz)"

    # waveforms overlaid on a shared axis
    .tSpan = max(dur_in, dur_out)
    selectObject: soundObj
    .m1 = Get absolute extremum: 0, 0, "None"
    .wR = max(.m1, peak_out, 1e-6) * 1.05
    Select inner viewport: 0.6, 7.7, w0, w1
    Axes: 0, .tSpan, -.wR, .wR
    Paint rectangle: "{0.98, 0.98, 0.99}", 0, .tSpan, -.wR, .wR
    selectObject: soundObj
    .mono1 = Convert to mono
    Shift times to: "start time", 0
    Select inner viewport: 0.6, 7.7, w0, w1
    Colour: "{0.72, 0.72, 0.76}"
    Draw: 0, .tSpan, -.wR, .wR, "no", "Curve"
    removeObject: .mono1
    selectObject: resultSound
    .mono2 = Convert to mono
    Select inner viewport: 0.6, 7.7, w0, w1
    Colour: "{0.20, 0.40, 0.80}"
    Draw: 0, .tSpan, -.wR, .wR, "no", "Curve"
    removeObject: .mono2
    Select inner viewport: 0.6, 7.7, w0, w1
    Axes: 0, .tSpan, -.wR, .wR
    Colour: "Black"
    Text top: "no", "##Waveforms## — grey input, blue output (after normalisation and gain)"
    Select inner viewport: 0.6, 7.7, w0, w1
    Axes: 0, .tSpan, -.wR, .wR
    Draw inner box
    @niceStep: .tSpan, 8
    Marks bottom every: 1, niceStep.step, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    @railLabel: w0, w1, "Wave"

    if hasLatent
        @drawTrueLatent
    else
        @drawFeatureProxy
    endif

    # summary
    Font size: 7
    Select inner viewport: 0.6, 7.7, s0, s1
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Text: 0.012, "left", 0.86, "half", "##Summary##"
    Font size: 6
    Select inner viewport: 0.6, 7.7, s0, s1
    Axes: 0, 1, 0, 1
    Colour: "{0.25, 0.25, 0.28}"
    @sanitize: "Model " + modelFile$ + "  |  methods: " + methods$ + "  |  latent size: " + latentSize$ + "  |  device " + devUsed$
    Text: 0.012, "left", 0.64, "half", sanitize.out$
    @sanitize: "Sample rate: " + srHandling$
    Text: 0.012, "left", 0.46, "half", sanitize.out$
    @sanitize: "Level: " + normDone$ + ", then gain " + fixed$(gain, 1) + " dB  |  peak " + fixed$(peak_out, 3) + ", RMS " + fixed$(rms_out, 4) + "  |  " + string$(nch_out) + " ch, " + string$(sr_out) + " Hz"
    Text: 0.012, "left", 0.28, "half", sanitize.out$
    .lp$ = "Latent panel: " + latentNote$
    if action = 2
        .lp$ = "Latent: " + opDesc$ + "  |  energy: " + energyDesc$
    endif
    @sanitize: .lp$
    Text: 0.012, "left", 0.11, "half", sanitize.out$
    Select inner viewport: 0.6, 7.7, s0, s1
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 10
    Select outer viewport: 0, 8, 0, canvasH
endproc

procedure drawTrueLatent
    # rows: time, z1 .. zK (model encode(), first dims carry most variance in
    # RAVE exports with latent PCA)
    .mx = Read Matrix from raw text file: latentFile$
    .nr = Get number of rows
    .nc = Get number of columns
    .k = min(.nc - 1, 8)
    .tEnd = Get value in cell: .nr, 1
    .tEnd = max(.tEnd, 1e-3)
    .lo = 1e9
    .hi = -1e9
    for .r to .nr
        for .c from 2 to .k + 1
            .v = Get value in cell: .r, .c
            .lo = min(.lo, .v)
            .hi = max(.hi, .v)
        endfor
    endfor
    hasIn = fileReadable(latentInFile$)
    if hasIn
        .mi = Read Matrix from raw text file: latentInFile$
        .nri = Get number of rows
        .ti = Get value in cell: .nri, 1
        .tEnd = max(.tEnd, .ti)
        for .r to .nri
            for .c from 2 to .k + 1
                .v = Get value in cell: .r, .c
                .lo = min(.lo, .v)
                .hi = max(.hi, .v)
            endfor
        endfor
        selectObject: .mx
    endif
    .pad = max((.hi - .lo) * 0.08, 1e-3)
    # left: dimension curves over time
    Select inner viewport: 0.6, 4.6, l0, l1
    Axes: 0, .tEnd, .lo - .pad, .hi + .pad
    Paint rectangle: "{0.98, 0.98, 0.99}", 0, .tEnd, .lo - .pad, .hi + .pad
    if hasIn
        selectObject: .mi
        Line width: 1
        for .c from 2 to .k + 1
            Colour: "{0.80, 0.80, 0.84}"
            .xa = Get value in cell: 1, 1
            .ya = Get value in cell: 1, .c
            for .r from 2 to .nri
                .xb = Get value in cell: .r, 1
                .yb = Get value in cell: .r, .c
                Draw line: .xa, .ya, .xb, .yb
                .xa = .xb
                .ya = .yb
            endfor
        endfor
        selectObject: .mx
    endif
    Line width: 1.2
    for .c from 2 to .k + 1
        @dimColour: .c - 1
        Colour: dimColour.rgb$
        .xa = Get value in cell: 1, 1
        .ya = Get value in cell: 1, .c
        for .r from 2 to .nr
            .xb = Get value in cell: .r, 1
            .yb = Get value in cell: .r, .c
            Draw line: .xa, .ya, .xb, .yb
            .xa = .xb
            .ya = .yb
        endfor
    endfor
    Line width: 1
    Select inner viewport: 0.6, 4.6, l0, l1
    Axes: 0, .tEnd, .lo - .pad, .hi + .pad
    Colour: "Black"
    if hasIn
        Text top: "no", "##Latent before (grey) and after (colour)## — first " + string$(.k) + " of " + string$(.nc - 1) + " dims"
    else
        Text top: "no", "##True latent trajectory## — encode(), first " + string$(.k) + " of " + string$(.nc - 1) + " dims"
    endif
    Select inner viewport: 0.6, 4.6, l0, l1
    Axes: 0, .tEnd, .lo - .pad, .hi + .pad
    Draw inner box
    @niceStep: .tEnd, 4
    Marks bottom every: 1, niceStep.step, "yes", "yes", "no"
    @niceStep: .hi - .lo + 2 * .pad, 4
    Marks left every: 1, niceStep.step, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    @railLabel: l0, l1, "Latent"
    # right: z1 x z2 path, colour = time
    if .nc >= 3
        .x0 = 1e9
        .x1 = -1e9
        .y0 = 1e9
        .y1 = -1e9
        for .r to .nr
            .a = Get value in cell: .r, 2
            .b = Get value in cell: .r, 3
            .x0 = min(.x0, .a)
            .x1 = max(.x1, .a)
            .y0 = min(.y0, .b)
            .y1 = max(.y1, .b)
        endfor
        .px = max((.x1 - .x0) * 0.08, 1e-3)
        .py = max((.y1 - .y0) * 0.08, 1e-3)
        Select inner viewport: 5.2, 7.7, l0, l1
        Axes: .x0 - .px, .x1 + .px, .y0 - .py, .y1 + .py
        Paint rectangle: "{0.98, 0.98, 0.99}", .x0 - .px, .x1 + .px, .y0 - .py, .y1 + .py
        Line width: 1.4
        .xa = Get value in cell: 1, 2
        .ya = Get value in cell: 1, 3
        for .r from 2 to .nr
            .xb = Get value in cell: .r, 2
            .yb = Get value in cell: .r, 3
            .u = (.r - 1) / max(.nr - 1, 1)
            Colour: "{" + fixed$(0.20 + 0.70 * .u, 3) + ", 0.40, " + fixed$(0.80 - 0.70 * .u, 3) + "}"
            Draw line: .xa, .ya, .xb, .yb
            .xa = .xb
            .ya = .yb
        endfor
        Line width: 1
        .fx = Get value in cell: 1, 2
        .fy = Get value in cell: 1, 3
        Paint circle (mm): "{0.15, 0.70, 0.30}", .fx, .fy, 2
        .lx = Get value in cell: .nr, 2
        .ly = Get value in cell: .nr, 3
        Paint circle (mm): "{0.80, 0.15, 0.15}", .lx, .ly, 2
        Select inner viewport: 5.2, 7.7, l0, l1
        Axes: .x0 - .px, .x1 + .px, .y0 - .py, .y1 + .py
        Colour: "Black"
        if hasIn
            Text top: "no", "##z1 × z2 after the transform## — blue→orange = time"
        else
            Text top: "no", "##z1 × z2## — blue→orange = time"
        endif
        Select inner viewport: 5.2, 7.7, l0, l1
        Axes: .x0 - .px, .x1 + .px, .y0 - .py, .y1 + .py
        Draw inner box
        Text bottom: "yes", "z1"
        Text left: "yes", "z2"
    endif
    removeObject: .mx
    if hasIn
        removeObject: .mi
    endif
endproc

procedure drawFeatureProxy
    # v1.2's panel, now labelled for what it is: two features of the INPUT
    # (brightness = log hi/lo band RMS, tonalness = pitch stability x
    # sqrt(HNR+1)), NOT the model's latent space.
    .nF = 64
    selectObject: soundObj
    .mono = Convert to mono
    .pitch = To Pitch: 0, 75, 600
    selectObject: .mono
    .harm = To Harmonicity (cc): 0.01, 75, 0.1, 1.0
    selectObject: .mono
    .lo = Filter (pass Hann band): 0, 1500, 100
    selectObject: .mono
    .hi = Filter (pass Hann band): 1500, 0, 100
    .step = dur_in / .nF
    selectObject: .mono
    .t00 = Get start time
    for zi from 0 to .nF - 1
        .ta = .t00 + zi * .step
        .tb = .ta + .step
        selectObject: .lo
        .rl = Get root-mean-square: .ta, .tb
        selectObject: .hi
        .rh = Get root-mean-square: .ta, .tb
        .br = min(100, max(0.01, .rh / max(.rl, 1e-5)))
        px_'zi' = ln(.br)
        selectObject: .pitch
        .pm = Get mean: .ta, .tb, "Hertz"
        .ps = Get standard deviation: .ta, .tb, "Hertz"
        .stab = 0
        if .pm <> undefined and .pm > 0
            if .ps = undefined
                .ps = 0
            endif
            .stab = max(0, 1 - min(1, .ps / (.pm + 0.001)))
        endif
        selectObject: .harm
        .hv = Get mean: .ta, .tb
        if .hv = undefined or .hv < 0
            .hv = 0
        endif
        py_'zi' = .stab * sqrt(.hv + 1)
    endfor
    removeObject: .mono, .pitch, .harm, .lo, .hi
    .x0 = px_0
    .x1 = px_0
    .y0 = py_0
    .y1 = py_0
    for zi to .nF - 1
        .x0 = min(.x0, px_'zi')
        .x1 = max(.x1, px_'zi')
        .y0 = min(.y0, py_'zi')
        .y1 = max(.y1, py_'zi')
    endfor
    .px = max((.x1 - .x0) * 0.08, 1e-3)
    .py = max((.y1 - .y0) * 0.08, 1e-3)
    Select inner viewport: 0.6, 7.7, l0, l1
    Axes: .x0 - .px, .x1 + .px, .y0 - .py, .y1 + .py
    Paint rectangle: "{0.98, 0.98, 0.99}", .x0 - .px, .x1 + .px, .y0 - .py, .y1 + .py
    Line width: 1.4
    for zi to .nF - 1
        zj = zi - 1
        .u = zi / (.nF - 1)
        Colour: "{" + fixed$(0.20 + 0.70 * .u, 3) + ", 0.40, " + fixed$(0.80 - 0.70 * .u, 3) + "}"
        Draw line: px_'zj', py_'zj', px_'zi', py_'zi'
    endfor
    Line width: 1
    Select inner viewport: 0.6, 7.7, l0, l1
    Axes: .x0 - .px, .x1 + .px, .y0 - .py, .y1 + .py
    Colour: "Black"
    Text top: "no", "##Input feature proxy (NOT the model latent space)## — brightness × tonalness, 64 frames, blue→orange = time"
    Select inner viewport: 0.6, 7.7, l0, l1
    Axes: .x0 - .px, .x1 + .px, .y0 - .py, .y1 + .py
    Draw inner box
    Text bottom: "yes", "Brightness (log hi/lo band RMS)"
    @railLabel: l0, l1, "Tonalness"
endproc
