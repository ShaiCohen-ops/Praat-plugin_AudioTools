# ============================================================
# Praat AudioTools - Spectral_Morph.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 4.1 (2025) — Distribution-ready
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   CDP-style Spectral Morph — Python-powered STFT morphing.
#   Heavy DSP offloaded to spectral_morph.py via runSystem.
#   Praat handles UI, export, import, visualization.
#
#   Morph modes (Python):
#   1. Log magnitude     – geometric interp, preserves A phase
#   2. Full complex      – blends magnitude AND phase
#   3. Formant/envelope  – cepstral envelope morph, A excitation
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 2
    exitScript: "Please select exactly TWO Sound objects."
        ... + newline$ + "Sound 1 = A (source), Sound 2 = B (target)."
endif

soundA = selected("Sound", 1)
soundB = selected("Sound", 2)
nameA$ = selected$("Sound", 1)
nameB$ = selected$("Sound", 2)

# ---- PATHS (plugin-relative for distribution) ----
pluginDir$ = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/spectral_morph.py"


tempA$      = pluginDir$ + "morphA.wav"
tempB$      = pluginDir$ + "morphB.wav"
tempOutput$ = pluginDir$ + "morph_out.wav"

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: " + pythonScript$ + newline$
        ... + "Please verify AudioTools installation."
endif

# ---- FORM ----
form Spectral Morph v4.1
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Tonal Sustained (instruments, pads)
        option Percussive (drums, impacts)
        option Voice / Formant Morph
        option Texture Blend (ambience, noise)
        option Fast Preview (low quality, quick)
    comment === Morph Region (0 = full duration) ===
    real Start_morph_s 0
    real End_morph_s 0
    optionmenu Curve_type: 2
        option Linear
        option Cosine (smooth S-curve)
        option Full mix (fixed blend, no transition)
    real Mix_amount 0.5
    comment === Analysis ===
    positive Window_ms 60
    comment === Morph Mode ===
    optionmenu Morph_mode: 1
        option Log magnitude (preserve A phase)
        option Full complex (blend phase too)
        option Formant / envelope (CDP-style)
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_output 1
endform

# ---- PRESETS ----
if preset = 2
    window_ms  = 60
    morph_mode = 1
    curve_type = 2
    presetName$ = "TonalSustained"
elsif preset = 3
    window_ms  = 25
    morph_mode = 1
    curve_type = 1
    presetName$ = "Percussive"
elsif preset = 4
    window_ms  = 50
    morph_mode = 3
    curve_type = 2
    presetName$ = "VoiceFormant"
elsif preset = 5
    window_ms  = 80
    morph_mode = 2
    curve_type = 2
    presetName$ = "TextureBlend"
elsif preset = 6
    window_ms  = 120
    morph_mode = 1
    curve_type = 1
    presetName$ = "FastPreview"
else
    presetName$ = "Custom"
endif

window_s = window_ms / 1000

# ---- GET DURATIONS ----
selectObject: soundA
durA = Get total duration
srA  = Get sampling frequency
nchA = Get number of channels

selectObject: soundB
durB = Get total duration
srB  = Get sampling frequency
nchB = Get number of channels

commonDuration = max(durA, durB)

# Clamp morph region
if end_morph_s <= start_morph_s or end_morph_s <= 0
    end_morph_s = commonDuration
endif
if start_morph_s < 0
    start_morph_s = 0
endif
if end_morph_s > commonDuration
    end_morph_s = commonDuration
endif

# ---- MODE LABELS ----
if morph_mode = 1
    modeLabel$ = "Log magnitude"
elsif morph_mode = 2
    modeLabel$ = "Full complex"
else
    modeLabel$ = "Formant/envelope"
endif
if curve_type = 2
    curveLabel$ = "Cosine"
elsif curve_type = 3
    curveLabel$ = "FullMix(" + fixed$(mix_amount, 2) + ")"
else
    curveLabel$ = "Linear"
endif

# ---- INFO ----
clearinfo
writeInfoLine:  "=== Spectral Morph v4.1 (Python engine) ==="
appendInfoLine: "A: ", nameA$, "  (", fixed$(durA, 2), " s)"
appendInfoLine: "B: ", nameB$, "  (", fixed$(durB, 2), " s)"
appendInfoLine: "Preset:  ", presetName$
appendInfoLine: "Mode:    ", modeLabel$
appendInfoLine: "Curve:   ", curveLabel$
appendInfoLine: "Window:  ", fixed$(window_ms, 0), " ms"
appendInfoLine: "Region:  ", fixed$(start_morph_s, 2), " – ", fixed$(end_morph_s, 2), " s"
appendInfoLine: ""

# ---- EXPORT BOTH SOUNDS ----
appendInfoLine: "[1/5] Exporting WAVs..."

selectObject: soundA
Save as WAV file: tempA$

selectObject: soundB
Save as WAV file: tempB$

# ---- DETECT PYTHON ----
appendInfoLine: "[2/4] Detecting Python..."

probeMarker$ = pluginDir$ + "temp_morph_pyprobe.ok"

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

pythonCmd$ = ""
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

    probeCode$ = "import numpy,soundfile; open(r'" + probeMarker$ + "','w').write('ok')"
    runSystem_nocheck: tryCmd$ + " -c """ + probeCode$ + """"

    if fileReadable(probeMarker$)
        pythonCmd$ = tryCmd$
        deleteFile: probeMarker$
        appendInfoLine: "  Python found: ", pythonCmd$
    endif
    if pythonCmd$ <> ""
        iCand = nCandidates + 1
    endif
endfor

if pythonCmd$ = ""
    deleteFile: tempA$
    deleteFile: tempB$
    exitScript: "Cannot find Python with required packages." + newline$
        ... + "Install: pip install numpy soundfile"
endif

# ---- CALL PYTHON ----
appendInfoLine: "[3/4] Running Python morphing engine..."

runSystem: pythonCmd$ + " """ + pythonScript$ + """"
    ... + " """ + tempA$ + """"
    ... + " """ + tempB$ + """"
    ... + " """ + tempOutput$ + """"
    ... + " " + fixed$(window_s, 6)
    ... + " " + fixed$(start_morph_s, 6)
    ... + " " + fixed$(end_morph_s, 6)
    ... + " " + string$(morph_mode)
    ... + " " + string$(curve_type)
    ... + " " + fixed$(mix_amount, 4)

# ---- VERIFY OUTPUT ----
if not fileReadable(tempOutput$)
    deleteFile: tempA$
    deleteFile: tempB$
    exitScript: "Python spectral morph failed." + newline$
        ... + "Possible causes:" + newline$
        ... + "  - numpy or soundfile not installed" + newline$
        ... + "  - scipy needed for sample rate conversion" + newline$
        ... + "  - Python not found in PATH" + newline$
        ... + "Check the terminal/console for Python error messages."
endif

# ---- IMPORT RESULT ----
appendInfoLine: "[4/5] Importing result..."

Read from file: tempOutput$
Rename: nameA$ + "_morph_" + nameB$
finalOutput = selected("Sound")
outputDuration = Get total duration
rms_out = Get root-mean-square: 0, 0

appendInfoLine: "  Output: ", fixed$(outputDuration, 2), " s"

# ---- CLEANUP TEMP FILES ----
deleteFile: tempA$
deleteFile: tempB$
deleteFile: tempOutput$
if fileReadable(probeMarker$)
    deleteFile: probeMarker$
endif

###############################################################################
# VISUALIZATION
###############################################################################

if draw_visualization

    selectObject: soundA
    if nchA > 1
        monoA_viz = Convert to mono
    else
        monoA_viz = Copy: "monoA_viz"
    endif

    selectObject: soundB
    if nchB > 1
        monoB_viz = Convert to mono
    else
        monoB_viz = Copy: "monoB_viz"
    endif

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # === Title ===
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half", "##Spectral Morph v4.1##"
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -0.6, "half", nameA$ + " → " + nameB$ + " | " + presetName$ + " | " + modeLabel$

    # === Sound A waveform ===
    Select outer viewport: 0, 4, 0.6, 1.4
    Select inner viewport: 0.6, 3.7, 0.7, 1.35
    selectObject: monoA_viz
    Colour: "{0.3, 0.5, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "A"
    Text top: "no", nameA$

    # === Sound B waveform ===
    Select outer viewport: 4, 8, 0.6, 1.4
    Select inner viewport: 4.4, 7.7, 0.7, 1.35
    selectObject: monoB_viz
    Colour: "{0.8, 0.4, 0.3}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "B"
    Text top: "no", nameB$

    # === Morph curve ===
    Select outer viewport: 0, 8, 1.5, 2.6
    Select inner viewport: 0.6, 7.7, 1.6, 2.5
    Axes: 0, commonDuration, -0.05, 1.1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, commonDuration, -0.05, 1.1
    Paint rectangle: "{0.92, 0.95, 1.0}", start_morph_s, end_morph_s, -0.05, 1.1
    Colour: "{0.2, 0.2, 0.7}"
    Line width: 2.5
    vizPoints = 100
    vizStep = commonDuration / vizPoints
    prevT = 0
    prevU = (0 - start_morph_s) / (end_morph_s - start_morph_s)
    if prevU < 0
        prevU = 0
    endif
    if prevU > 1
        prevU = 1
    endif
    if curve_type = 2
        prevM = 0.5 - 0.5 * cos(pi * prevU)
    elsif curve_type = 3
        prevM = mix_amount
    else
        prevM = prevU
    endif
    for vp from 1 to vizPoints
        curT = vp * vizStep
        curU = (curT - start_morph_s) / (end_morph_s - start_morph_s)
        if curU < 0
            curU = 0
        endif
        if curU > 1
            curU = 1
        endif
        if curve_type = 2
            curM = 0.5 - 0.5 * cos(pi * curU)
        elsif curve_type = 3
            curM = mix_amount
        else
            curM = curU
        endif
        Draw line: prevT, prevM, curT, curM
        prevT = curT
        prevM = curM
    endfor
    Line width: 1
    Colour: "{0.3, 0.5, 0.8}"
    Text: 0, "left", 1.05, "half", "A"
    Colour: "{0.8, 0.4, 0.3}"
    Text: commonDuration, "right", 1.05, "half", "B"
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: 0, 0, commonDuration, 0
    Draw line: 0, 1, commonDuration, 1
    Solid line
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Morph (0–1)"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Morph Curve (" + curveLabel$ + ") – " + modeLabel$

    # === Spectrogram A ===
    Select outer viewport: 0, 4, 2.7, 3.9
    Select inner viewport: 0.6, 3.7, 2.8, 3.8
    selectObject: monoA_viz
    To Spectrogram: 0.005, 8000, 0.002, 20, "Gaussian"
    specgramA = selected("Spectrogram")
    Paint: 0, 0, 0, 8000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text top: "no", "A Spectrogram"
    removeObject: specgramA

    # === Spectrogram B ===
    Select outer viewport: 4, 8, 2.7, 3.9
    Select inner viewport: 4.4, 7.7, 2.8, 3.8
    selectObject: monoB_viz
    To Spectrogram: 0.005, 8000, 0.002, 20, "Gaussian"
    specgramB = selected("Spectrogram")
    Paint: 0, 0, 0, 8000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text top: "no", "B Spectrogram"
    removeObject: specgramB

    # === Output waveform ===
    Select outer viewport: 0, 8, 4.0, 4.8
    Select inner viewport: 0.6, 7.7, 4.1, 4.75
    selectObject: finalOutput
    Colour: "{0.4, 0.6, 0.4}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Out"
    Text top: "no", "Morphed Output | " + fixed$(outputDuration, 2) + " s"

    # === Output spectrogram ===
    Select outer viewport: 0, 8, 4.9, 6.1
    Select inner viewport: 0.6, 7.7, 5.0, 6.0
    selectObject: finalOutput
    To Spectrogram: 0.005, 8000, 0.002, 20, "Gaussian"
    specgramOut = selected("Spectrogram")
    Paint: 0, 0, 0, 8000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Output Spectrogram"
    removeObject: specgramOut

    # === Summary Panel ===
    Select outer viewport: 0, 8, 6.2, 7.0
    Select inner viewport: 0.6, 7.7, 6.3, 6.95
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.85, "half", "Summary:"
    Font size: 6
    Colour: "{0.3, 0.3, 0.35}"
    Text: 0.02, "left", 0.62, "half", "A: " + nameA$ + " (" + fixed$(durA, 2) + "s)  |  B: " + nameB$ + " (" + fixed$(durB, 2) + "s)  |  Out: " + fixed$(outputDuration, 2) + "s"
    Text: 0.02, "left", 0.38, "half", modeLabel$ + "  |  " + curveLabel$ + "  |  " + fixed$(window_ms, 0) + "ms window"
    Text: 0.02, "left", 0.15, "half", "Morph: " + fixed$(start_morph_s, 2) + " – " + fixed$(end_morph_s, 2) + "s  |  Preset: " + presetName$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    removeObject: monoA_viz, monoB_viz
    Font size: 10
    Colour: "Black"
else
    appendInfoLine: "[5/5] Visualization skipped."
endif

# ---- FINISH ----
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", nameA$, "_morph_", nameB$
appendInfoLine: "Duration: ", fixed$(outputDuration, 2), " s"
appendInfoLine: "Mode: ", modeLabel$, " | Curve: ", curveLabel$
appendInfoLine: "RMS: ", fixed$(rms_out, 6)

selectObject: finalOutput

if play_output
    Play
endif
