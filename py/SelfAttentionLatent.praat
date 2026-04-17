# ============================================================
# Praat AudioTools - SelfAttentionLatent.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026) - Unified Cross-Platform Version
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Self-Attention Latent Navigation Engine
#   Part of Praat AudioTools plugin
#
# Pipeline:
#   1. User selects audio file
#   2. Praat segments into events → writes temp events.csv
#   3. Praat calls Python (self_attention_latent.py)
#   4. Python: VAE encode → self-attention → plan (in memory) → mix → output.wav
#   5. Praat loads output.wav, shows visualization, deletes temp files
#
# No plan.csv is ever written.
# Only output.wav persists after execution.
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")

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

pythonScript$ = pluginDir$ + "py/self_attention_latent.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/self_attention_latent.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: self_attention_latent.py" + newline$ + "Expected at: " + pluginDir$ + "py/ or next to this script."
endif

tempDirRaw$ = temporaryDirectory$ + "/"
tempDir$ = replace_regex$(tempDirRaw$, "\\", "/", 0)

tempWav$     = tempDir$ + "temp_sal_input.wav"
eventsCSV$   = tempDir$ + "temp_sal_events.csv"
output_wav$  = tempDir$ + "temp_sal_output.wav"
stats_txt$   = tempDir$ + "temp_sal_stats.txt"
probePy$     = tempDir$ + "temp_sal_probe.py"
probeMarker$ = tempDir$ + "temp_sal_probe.ok"

# Enforce forward slashes for all temporary paths passed to python
pythonScriptJ$ = replace_regex$(pythonScript$, "\\", "/", 0)
tempWavJ$      = replace_regex$(tempWav$, "\\", "/", 0)
eventsCSVJ$    = replace_regex$(eventsCSV$, "\\", "/", 0)
output_wavJ$   = replace_regex$(output_wav$, "\\", "/", 0)
stats_txtJ$    = replace_regex$(stats_txt$, "\\", "/", 0)
probePyJ$      = replace_regex$(probePy$, "\\", "/", 0)
probeMarkerJ$  = replace_regex$(probeMarker$, "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(tempWav$)
        deleteFile: tempWav$
    endif
    if fileReadable(eventsCSV$)
        deleteFile: eventsCSV$
    endif
    if fileReadable(output_wav$)
        deleteFile: output_wav$
    endif
    if fileReadable(stats_txt$)
        deleteFile: stats_txt$
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
form Self-Attention Latent Navigation v1.1
    comment ── Preset ───────────────────────────────────────────────────
    optionmenu Preset: 1
        option Custom
        option Gentle drift
        option Vocal texture
        option Fragmented echo
        option Deep mutation
        option Rhythmic grid
        option Spectral smear
        option Chaotic plasma
    comment ── Segmentation ──────────────────────────────────────────────
    optionmenu Segmentation_method: 1
        option Silences
        option Equal_intervals
    positive Silence_threshold_(dB) 25.0
    positive Min_event_duration_(s) 0.05
    positive Min_silence_duration_(s) 0.03
    positive Interval_size_(s) 0.25

    comment ── VAE / Latent ───────────────────────────────────────────────
    integer Latent_size 8
    integer Random_seed 42

    comment ── Self-attention ────────────────────────────────────────────
    integer Attention_heads 4

    comment ── Navigation plan ───────────────────────────────────────────
    integer Plan_steps 72
    positive Duration_scale 1.0
    real Duration_jitter 0.0
    positive Energy_scale 1.0
    real Energy_jitter 0.0

    comment ── Output duration ───────────────────────────────────────────
    real Target_duration_(s) 0.0

    comment ── Pitch / Normalize ─────────────────────────────────────────
    optionmenu Pitch_mode: 2
        option off
        option preserve_f0
        option preserve_spectral_envelope
    optionmenu Normalize_mode: 3
        option none
        option peak
        option rms

    comment ── Misc ──────────────────────────────────────────────────────
    boolean Load_output 1
    boolean Show_visualization 1
    boolean Play_result 1
endform

# ── Presets ────────────────────────────────────────────────────────────────
if preset = 2
    segmentation_method  = 1
    silence_threshold    = 25.0
    min_event_duration   = 0.05
    min_silence_duration = 0.03
    interval_size        = 0.25
    latent_size          = 8
    attention_heads      = 4
    plan_steps           = 24
    duration_scale       = 1.0
    duration_jitter      = 0.05
    energy_scale         = 1.0
    energy_jitter        = 0.0
    pitch_mode           = 2
    normalize_mode       = 3
    presetName$          = "GentleDrift"
elsif preset = 3
    segmentation_method  = 1
    silence_threshold    = 20.0
    min_event_duration   = 0.03
    min_silence_duration = 0.02
    interval_size        = 0.1
    latent_size          = 12
    attention_heads      = 8
    plan_steps           = 48
    duration_scale       = 0.8
    duration_jitter      = 0.1
    energy_scale         = 1.0
    energy_jitter        = 0.05
    pitch_mode           = 2
    normalize_mode       = 3
    presetName$          = "VocalTexture"
elsif preset = 4
    segmentation_method  = 1
    silence_threshold    = 15.0
    min_event_duration   = 0.02
    min_silence_duration = 0.01
    interval_size        = 0.1
    latent_size          = 8
    attention_heads      = 4
    plan_steps           = 96
    duration_scale       = 0.5
    duration_jitter      = 0.3
    energy_scale         = 0.8
    energy_jitter        = 0.2
    pitch_mode           = 2
    normalize_mode       = 3
    presetName$          = "FragmentedEcho"
elsif preset = 5
    segmentation_method  = 1
    silence_threshold    = 25.0
    min_event_duration   = 0.05
    min_silence_duration = 0.03
    interval_size        = 0.25
    latent_size          = 24
    attention_heads      = 8
    plan_steps           = 72
    duration_scale       = 1.2
    duration_jitter      = 0.15
    energy_scale         = 1.1
    energy_jitter        = 0.1
    pitch_mode           = 3
    normalize_mode       = 3
    presetName$          = "DeepMutation"
elsif preset = 6
    segmentation_method  = 2
    silence_threshold    = 25.0
    min_event_duration   = 0.05
    min_silence_duration = 0.03
    interval_size        = 0.125
    latent_size          = 8
    attention_heads      = 4
    plan_steps           = 64
    duration_scale       = 1.0
    duration_jitter      = 0.02
    energy_scale         = 1.0
    energy_jitter        = 0.05
    pitch_mode           = 1
    normalize_mode       = 2
    presetName$          = "RhythmicGrid"
elsif preset = 7
    segmentation_method  = 1
    silence_threshold    = 30.0
    min_event_duration   = 0.1
    min_silence_duration = 0.05
    interval_size        = 0.5
    latent_size          = 16
    attention_heads      = 4
    plan_steps           = 36
    duration_scale       = 1.5
    duration_jitter      = 0.2
    energy_scale         = 0.9
    energy_jitter        = 0.1
    pitch_mode           = 3
    normalize_mode       = 3
    presetName$          = "SpectralSmear"
elsif preset = 8
    segmentation_method  = 1
    silence_threshold    = 10.0
    min_event_duration   = 0.02
    min_silence_duration = 0.01
    interval_size        = 0.1
    latent_size          = 32
    attention_heads      = 16
    plan_steps           = 120
    duration_scale       = 1.0
    duration_jitter      = 0.5
    energy_scale         = 1.0
    energy_jitter        = 0.4
    pitch_mode           = 1
    normalize_mode       = 3
    presetName$          = "ChaoticPlasma"
else
    presetName$ = "Custom"
endif

# ── pitch mode string ──────────────────────────────────────────────────────
if pitch_mode = 1
    pitchStr$ = "off"
elsif pitch_mode = 2
    pitchStr$ = "preserve_f0"
else
    pitchStr$ = "preserve_spectral_envelope"
endif

# ── normalize mode string ─────────────────────────────────────────────────
if normalize_mode = 1
    normStr$ = "none"
elsif normalize_mode = 2
    normStr$ = "peak"
else
    normStr$ = "rms"
endif

# ── Clamp parameters ─────────────────────────────────────────────────────
if attention_heads < 1
    attention_heads = 1
endif
if attention_heads > 16
    attention_heads = 16
endif
if plan_steps < 8
    plan_steps = 8
endif
if latent_size < 2
    latent_size = 2
endif
if latent_size > 32
    latent_size = 32
endif

# ═════════════════════════════════════════════════════════════════════════════
# Stage 0 — Early Python Dependency Probe
# ═════════════════════════════════════════════════════════════════════════════
clearinfo
appendInfoLine: "=== Self-Attention Latent Navigation ==="
appendInfoLine: "Input:  ", soundName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "[0/4] Detecting Python dependencies..."

writeFileLine: probePy$, "import sys"
appendFileLine: probePy$, "try:"
appendFileLine: probePy$, "    import numpy, scipy, soundfile"
appendFileLine: probePy$, "    with open(r'" + probeMarkerJ$ + "', 'w') as f: f.write('ok')"
appendFileLine: probePy$, "except ImportError:"
appendFileLine: probePy$, "    sys.exit(1)"

if windows
    nCandidates = 4
    candidate1$ = "python"
    candidate2$ = "py"
    candidate3$ = "py -3"
    candidate4$ = "python3"
else
    nCandidates = 3
    candidate1$ = "python3"
    candidate2$ = "python"
    candidate3$ = "py"
    candidate4$ = ""
endif

for iCand from 1 to nCandidates
    if iCand = 1
        tryCmd$ = candidate1$
    elsif iCand = 2
        tryCmd$ = candidate2$
    elsif iCand = 3
        tryCmd$ = candidate3$
    else
        tryCmd$ = candidate4$
    endif

    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif

    runSystem_nocheck: tryCmd$ + " """ + probePyJ$ + """"

    if fileReadable(probeMarker$)
        pythonCmd$ = tryCmd$
        deleteFile: probeMarker$
        iCand = nCandidates + 1 ; Break early
    endif
endfor

deleteFile: probePy$

if pythonCmd$ = ""
    @cleanUpTempFiles
    exitScript: "Cannot find Python 3 installation with required packages." + newline$ + "Tried: python3, python, py" + newline$ + "Please install: pip install numpy scipy soundfile"
endif

appendInfoLine: "  Python found: ", pythonCmd$

# ═════════════════════════════════════════════════════════════════════════════
# Stage 1 — Load / prepare the Sound
# ═════════════════════════════════════════════════════════════════════════════
appendInfoLine: "[1/4] Loading and preparing audio..."

selectObject: sound
dur = Get total duration

# Write as wav so Python can read it reliably
Save as WAV file: tempWav$

# ═════════════════════════════════════════════════════════════════════════════
# Stage 2 — Segmentation → events.csv
# ═════════════════════════════════════════════════════════════════════════════
appendInfoLine: "[2/4] Segmenting audio..."

selectObject: sound
tg = To TextGrid (silences): 100, 0, -silence_threshold, min_silence_duration, min_event_duration, "silent", "sounding"

selectObject: tg
nInt = Get number of intervals: 1

# Write events CSV
writeFileLine: eventsCSV$, "start_time,end_time,label,duration"

n_events = 0
for i from 1 to nInt
    selectObject: tg
    lab$ = Get label of interval: 1, i
    if segmentation_method = 1
        # Silences method: keep "sounding" intervals
        isEvent = (lab$ = "sounding")
    else
        # Equal intervals: keep everything above min duration
        isEvent = 1
    endif

    if isEvent
        st = Get start time of interval: 1, i
        en = Get end time of interval: 1, i
        evDur = en - st
        if evDur >= min_event_duration
            appendFileLine: eventsCSV$, fixed$(st, 6), ",",
                ... fixed$(en, 6), ",", lab$, ",", fixed$(evDur, 6)
            n_events = n_events + 1
        endif
    endif
endfor

removeObject: tg

if n_events < 2
    # Fall back to equal intervals
    appendInfoLine: "  Warning: too few events from silence detection, using equal intervals"
    writeFileLine: eventsCSV$, "start_time,end_time,label,duration"
    n_events = 0
    t = 0
    while t < dur - interval_size
        en = min(t + interval_size, dur)
        appendFileLine: eventsCSV$, fixed$(t, 6), ",", fixed$(en, 6), ",", "interval", ",", fixed$(en-t, 6)
        n_events = n_events + 1
        t = t + interval_size
    endwhile
endif

appendInfoLine: "  Events: " + string$(n_events)

# ═════════════════════════════════════════════════════════════════════════════
# Stage 3 — Call Python
# ═════════════════════════════════════════════════════════════════════════════
appendInfoLine: "[3/4] Running Python engine..."

targetDurArg$ = ""
if target_duration > 0
    targetDurArg$ = " --duration " + string$(target_duration)
endif

cmd$ = pythonCmd$ + " """ + pythonScriptJ$ + """"
    ... + " """ + tempWavJ$ + """"
    ... + " """ + eventsCSVJ$ + """"
    ... + " """ + output_wavJ$ + """"
    ... + " """ + stats_txtJ$ + """"
    ... + " --latent_size " + string$(latent_size)
    ... + " --seed " + string$(random_seed)
    ... + " --attn_heads " + string$(attention_heads)
    ... + " --plan_steps " + string$(plan_steps)
    ... + " --plan_dur_scale " + string$(duration_scale)
    ... + " --plan_dur_jitter " + string$(duration_jitter)
    ... + " --plan_eng_scale " + string$(energy_scale)
    ... + " --plan_eng_jitter " + string$(energy_jitter)
    ... + " --pitch_mode " + pitchStr$
    ... + " --normalize_mode " + normStr$
    ... + targetDurArg$
    ... + " --cleanup"

runSystem_nocheck: cmd$

if not fileReadable(stats_txt$)
    @cleanUpTempFiles
    exitScript: "Python engine failed. Check terminal for error details."
endif

# ═════════════════════════════════════════════════════════════════════════════
# Stage 4 — Read stats & Load Output
# ═════════════════════════════════════════════════════════════════════════════
appendInfoLine: "[4/4] Finalizing results..."

# Stats parsing helper
procedure parseStatLine: .text$, .key$
    .result$ = "?"
    .kl = length(.key$)
    .pos = index(.text$, .key$)
    if .pos > 0
        .start = .pos + .kl
        .rest$ = mid$(.text$, .start, length(.text$) - .start + 1)
        .nl    = index(.rest$, newline$)
        if .nl > 0
            .result$ = left$(.rest$, .nl - 1)
        else
            .result$ = .rest$
        endif
    endif
endproc

nEventsStat$    = "?"
nStepsStat$     = "?"
nExecStat$      = "?"
outDurStat$     = "?"
attnHeadsStat$  = "?"
attnEntropyStat$ = "?"
pitchModeStat$  = "?"
normModeStat$   = "?"
rmsInputStat$   = "?"
rmsOutputStat$  = "?"
vaeLossStat$    = "?"
driftStat$      = "?"
mutateStat$     = "?"
returnStat$     = "?"
settleStat$     = "?"

if fileReadable(stats_txt$)
    statsText$ = readFile$(stats_txt$)

    @parseStatLine: statsText$, "n_events="
    nEventsStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_plan_steps="
    nStepsStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_executed="
    nExecStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "output_duration="
    outDurStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "attn_heads="
    attnHeadsStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "attn_entropy="
    attnEntropyStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "pitch_mode="
    pitchModeStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "normalize_mode="
    normModeStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "rms_input="
    rmsInputStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "rms_output="
    rmsOutputStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "vae_loss_final="
    vaeLossStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "mode_drift="
    driftStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "mode_mutate="
    mutateStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "mode_return="
    returnStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "mode_settle="
    settleStat$ = parseStatLine.result$
endif

haveOutput = 0
if load_output and fileReadable(output_wav$)
    outSound = Read from file: output_wav$
    Rename: soundName$ + "_sal"
    appendInfoLine: "  Loaded output as: " + soundName$ + "_sal"
    haveOutput = 1
endif

@cleanUpTempFiles

# ═════════════════════════════════════════════════════════════════════════════
# Visualization
# ═════════════════════════════════════════════════════════════════════════════
if show_visualization
    appendInfoLine: "  Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # === Title ===
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half", "##Self-Attention Latent Navigation##"
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -1.2, "half", soundName$ + " | heads=" + attnHeadsStat$ + " | steps=" + nStepsStat$ + " | z=" + string$(latent_size)

    # === Phase bar ===
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.7, 0.65, 1.35
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.9, 0.9, 0.9}", 0, 1, 0, 1

    nTotal = number(nStepsStat$)
    if nTotal > 0 and nTotal != undefined
        nd = number(driftStat$);  if nd = undefined then nd = 0 endif
        nm = number(mutateStat$); if nm = undefined then nm = 0 endif
        nr = number(returnStat$); if nr = undefined then nr = 0 endif
        ns = number(settleStat$); if ns = undefined then ns = 0 endif

        xd = nd / nTotal
        xm = xd + nm / nTotal
        xr = xm + nr / nTotal
        xs = xr + ns / nTotal

        Paint rectangle: "{0.3, 0.8, 0.9}",  0,  xd, 0, 1
        Paint rectangle: "{0.9, 0.85, 0.3}", xd, xm, 0, 1
        Paint rectangle: "{0.9, 0.55, 0.2}", xm, xr, 0, 1
        Paint rectangle: "{0.3, 0.75, 0.4}", xr, xs, 0, 1

        Font size: 8
        Colour: "Black"
        if xd > 0.08
            Text: xd/2, "centre", 0.5, "half", "drift " + driftStat$
        endif
        if (xm - xd) > 0.08
            Text: (xd+xm)/2, "centre", 0.5, "half", "mutate " + mutateStat$
        endif
        if (xr - xm) > 0.08
            Text: (xm+xr)/2, "centre", 0.5, "half", "return " + returnStat$
        endif
        if (xs - xr) > 0.08
            Text: (xr+xs)/2, "centre", 0.5, "half", "settle " + settleStat$
        endif
    endif

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Phases"
    Text top: "no", "Navigation plan: " + nStepsStat$ + " steps / " + nExecStat$ + " executed"

    # === Original waveform ===
    Select outer viewport: 0, 8, 1.5, 2.3
    Select inner viewport: 0.6, 7.7, 1.55, 2.25
    selectObject: sound
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"

    # === Output waveform ===
    if haveOutput
        Select outer viewport: 0, 8, 2.3, 3.1
        Select inner viewport: 0.6, 7.7, 2.35, 3.05
        selectObject: outSound
        Colour: "{0.3, 0.6, 0.5}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Output"
        Text bottom: "yes", "Time (s)"
    endif

    # === Original spectrogram ===
    Select outer viewport: 0, 8, 3.2, 4.5
    Select inner viewport: 0.6, 7.7, 3.3, 4.4
    selectObject: sound
    if numberOfSelected("Sound") > 0
        nChannels = Get number of channels
    else
        nChannels = 1
    endif
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
    Text left: "yes", "Freq (Hz)"
    Text top: "no", "Original spectrogram"
    removeObject: specOrig, tmpOrig

    # === Output spectrogram ===
    if haveOutput
        Select outer viewport: 0, 8, 4.5, 5.8
        Select inner viewport: 0.6, 7.7, 4.6, 5.7
        selectObject: outSound
        outChans = Get number of channels
        if outChans > 1
            Extract one channel: 1
            tmpOut = selected("Sound")
        else
            Copy: "tmpOut"
            tmpOut = selected("Sound")
        endif
        To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
        specOut = selected("Spectrogram")
        Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Freq (Hz)"
        Text bottom: "yes", "Time (s)"
        Text top: "no", "Output spectrogram"
        removeObject: specOut, tmpOut
    endif

    # === Summary panel ===
    Select outer viewport: 0, 8, 6.0, 7.0
    Select inner viewport: 0.6, 7.7, 6.1, 6.9
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.82, "half", "##Run statistics##"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.60, "half", "Events: " + nEventsStat$ + " | Steps: " + nStepsStat$ + " / " + nExecStat$ + " executed | Output: " + outDurStat$ + " s"
    Text: 0.02, "left", 0.40, "half", "Attention heads: " + attnHeadsStat$ + " | Entropy: " + attnEntropyStat$ + " nats | VAE loss: " + vaeLossStat$
    Text: 0.02, "left", 0.20, "half", "Pitch: " + pitchModeStat$ + " | Normalize: " + normModeStat$ + " | RMS: " + rmsInputStat$ + " → " + rmsOutputStat$

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # === Footer ===
    Select outer viewport: 0, 8, 7.1, 7.6
    Select inner viewport: 0.6, 7.7, 7.15, 7.55
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.5, 0.5, 0.5}"
    Text: 0.5, "centre", 0.5, "half", "w_j ∝ (1/dist_j^p) · (A[i,j]^q)   |   Pure NumPy · No external models"

    Font size: 10
    Colour: "Black"
else
    appendInfoLine: "  Visualization skipped."
endif

# ═════════════════════════════════════════════════════════════════════════════
# Text log
# ═════════════════════════════════════════════════════════════════════════════
appendInfoLine: ""
appendInfoLine: "══════════════════════════════════════════"
appendInfoLine: "Self-Attention Latent — Run Summary"
appendInfoLine: "══════════════════════════════════════════"
appendInfoLine: "Input:       ", soundName$
appendInfoLine: "Preset:      ", presetName$
appendInfoLine: "Output:      ", soundName$, "_sal (Praat object)"
appendInfoLine: "Events:      ", nEventsStat$
appendInfoLine: "Plan:        ", nStepsStat$, " steps  (", nExecStat$, " executed)"
appendInfoLine: "Phases:      drift=", driftStat$, "  mutate=", mutateStat$,
    ... "  return=", returnStat$, "  settle=", settleStat$
appendInfoLine: "Attention:   heads=", attnHeadsStat$, "  entropy=", attnEntropyStat$, " nats"
appendInfoLine: "VAE loss:    ", vaeLossStat$
appendInfoLine: "Output dur:  ", outDurStat$, " s"
appendInfoLine: "Pitch mode:  ", pitchModeStat$
appendInfoLine: "Normalize:   ", normModeStat$, "  RMS: ", rmsInputStat$, " → ", rmsOutputStat$
appendInfoLine: "══════════════════════════════════════════"
appendInfoLine: ""

if play_result and haveOutput
    selectObject: outSound
    Play
endif