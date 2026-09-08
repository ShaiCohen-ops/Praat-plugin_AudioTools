# ============================================================
# Praat AudioTools - Spectral_Freeze.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 3.3 (2026) - reviewed
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral freeze — captures the spectrum at one or more moments
#   and sustains it via overlap-add synthesis with random or coherent phase.
#
#   v3: Multi-Freeze mode — captures spectra at N points and
#   crossfades between them, creating an evolving frozen texture.
#   Each freeze point is a "waypoint" in spectral space.
#
#   Modes:
#     Single  — freeze one moment (v2 behaviour)
#     Multi   — freeze N moments, crossfade between them
#
#   Parameters:
#   - Freeze time:   moment to capture (single mode)
#   - Freeze points: how many spectral waypoints (multi mode)
#   - Dwell:         how long to hold each waypoint
#   - Crossfade:     transition time between waypoints
#   - Loop:          cycle back to the first waypoint
#   - Duration:      total output length
#   - Window:        analysis window size (larger = smoother)
#   - Shimmer:       0 = static, 0.1-0.3 = breathing
#   - Fade in/out:   smooth the start and end
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v3.3:
#   AUDIO:
#   - Multi-freeze crossfades are energy-stable; dissimilar spectra no longer
#     collapse toward silence in the middle of a transition.
#   - Coherent multi-freeze gives every waypoint its own phase/frequency
#     trajectory and crossfades coherent streams with equal-power weights.
#   - Freeze times are true frame centres with safe edge padding; sounds shorter
#     than the FFT window are supported.
#   - Preserves mono/stereo/multichannel layouts; peak safety is global.
#   - Python writes FLOAT WAV.
#   PRAAT/QA:
#   - Unique temp/log paths, captured Python errors, effective FFT-window report.
#   - Multichannel visualisation uses strongest-RMS channels and Nyquist-safe Hz.
#
# Changelog v3.2:
#   - Phase mode: Coherent locks partials to their true frequencies for
#     a steady tonal freeze; Random keeps the diffuse texture
#   - Loop no longer holds the first waypoint twice at the seam
#   - Notes when Duration is shorter than one full waypoint pass
#
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")

# ---- PATHS ----
pluginDirRaw$ = preferencesDirectory$ + "/plugin_AudioTools/"
pluginDir$ = replace_regex$(pluginDirRaw$, "\\", "/", 0)

pythonScript$ = pluginDir$ + "py/spectral_freeze.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/spectral_freeze.py"
endif

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: spectral_freeze.py" + newline$
        ... + "Expected at: " + pluginDir$ + "py/" + newline$
        ... + "or next to this script."
endif

pythonScriptJ$ = replace_regex$(pythonScript$, "\\", "/", 0)

tempDirRaw$ = temporaryDirectory$ + "/"
tempDir$ = replace_regex$(tempDirRaw$, "\\", "/", 0)

runTag$       = string$(sound)
tempInput$    = tempDir$ + "freeze_" + runTag$ + "_input.wav"
tempOutput$   = tempDir$ + "freeze_" + runTag$ + "_output.wav"
tempLog$      = tempDir$ + "freeze_" + runTag$ + "_python.log"
probePy$      = tempDir$ + "freeze_" + runTag$ + "_probe.py"
probeMarker$  = tempDir$ + "freeze_" + runTag$ + "_probe.ok"

tempInputJ$   = replace_regex$(tempInput$,   "\\", "/", 0)
tempOutputJ$  = replace_regex$(tempOutput$,  "\\", "/", 0)
tempLogJ$     = replace_regex$(tempLog$,     "\\", "/", 0)
probePyJ$     = replace_regex$(probePy$,     "\\", "/", 0)
probeMarkerJ$ = replace_regex$(probeMarker$, "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(tempInput$)
        deleteFile: tempInput$
    endif
    if fileReadable(tempOutput$)
        deleteFile: tempOutput$
    endif
    if fileReadable(tempLog$)
        deleteFile: tempLog$
    endif
    if fileReadable(probePy$)
        deleteFile: probePy$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
endproc

@cleanUpTempFiles

# ---- GET INPUT STATS ----
selectObject: sound
totalDuration = Get total duration
sr = Get sampling frequency
nChannels = Get number of channels

# ===========================================================================
# STAGE 0 — Python Probe (file-based, runs before form)
# ===========================================================================

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

writeFileLine: probePy$, "import sys"
appendFileLine: probePy$, "try:"
appendFileLine: probePy$, "    import numpy, soundfile"
appendFileLine: probePy$, "    with open(r'" + probeMarkerJ$ + "', 'w') as f: f.write('ok')"
appendFileLine: probePy$, "except ImportError:"
appendFileLine: probePy$, "    sys.exit(1)"

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

    runSystem_nocheck: tryCmd$ + " """ + probePyJ$ + """"

    if fileReadable(probeMarker$)
        pythonCmd$ = tryCmd$
        deleteFile: probeMarker$
        iCand = nCandidates + 1
    endif
endfor

deleteFile: probePy$

if pythonCmd$ = ""
    @cleanUpTempFiles
    exitScript: "Cannot find Python with numpy and soundfile." + newline$
        ... + "Install Python 3 and run:  pip install numpy soundfile"
endif

# ---- FORM ----
form Spectral Freeze v3.3
    optionmenu Preset: 1
        option Custom
        option Drone (static, pure)
        option Pad (soft breathing)
        option Shimmer (lively, unstable)
        option Long fade (cinematic)
        option Evolving Landscape (multi-freeze)
        option Vowel Drift (multi-freeze)
        option Frozen Spectral Loop (multi-freeze)
    optionmenu Freeze_mode: 1
        option Single freeze point
        option Multi-freeze (evolving texture)
    real Freeze_time_s 0.5
    integer Number_of_freeze_points 4
    real Crossfade_s 2.0
    real Dwell_s 1.5
    boolean Loop 0
    positive Duration_s 8.0
    positive Window_ms 80.0
    real Shimmer 0.15
    optionmenu Phase: 1
        option Random (diffuse)
        option Coherent (tonal)
    real Fade_in_s 0.5
    real Fade_out_s 1.0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- PRESETS ----
presetName$ = "Custom"
if preset = 2
    window_ms  = 120
    shimmer    = 0.0
    fade_in_s  = 0.1
    fade_out_s = 0.5
    freeze_mode = 1
    phase = 2
    presetName$ = "Drone"
elsif preset = 3
    window_ms  = 80
    shimmer    = 0.15
    fade_in_s  = 0.5
    fade_out_s = 1.0
    freeze_mode = 1
    phase = 1
    presetName$ = "Pad"
elsif preset = 4
    window_ms  = 40
    shimmer    = 0.4
    fade_in_s  = 0.1
    fade_out_s = 0.5
    freeze_mode = 1
    phase = 1
    presetName$ = "Shimmer"
elsif preset = 5
    window_ms  = 100
    shimmer    = 0.1
    fade_in_s  = 2.0
    fade_out_s = 3.0
    freeze_mode = 1
    phase = 2
    presetName$ = "LongFade"
elsif preset = 6
    window_ms  = 100
    shimmer    = 0.12
    fade_in_s  = 1.0
    fade_out_s = 2.0
    freeze_mode = 2
    number_of_freeze_points = 5
    crossfade_s = 3.0
    dwell_s = 2.0
    loop = 0
    duration_s = 20.0
    phase = 1
    presetName$ = "EvolvingLandscape"
elsif preset = 7
    window_ms  = 60
    shimmer    = 0.18
    fade_in_s  = 0.5
    fade_out_s = 1.0
    freeze_mode = 2
    number_of_freeze_points = 6
    crossfade_s = 1.5
    dwell_s = 0.8
    loop = 0
    duration_s = 12.0
    phase = 1
    presetName$ = "VowelDrift"
elsif preset = 8
    window_ms  = 80
    shimmer    = 0.08
    fade_in_s  = 0.3
    fade_out_s = 0.3
    freeze_mode = 2
    number_of_freeze_points = 3
    crossfade_s = 2.5
    dwell_s = 1.0
    loop = 1
    duration_s = 15.0
    phase = 1
    presetName$ = "FrozenSpectralLoop"
endif

# ---- CLAMP PARAMETERS ----
if freeze_time_s < 0
    freeze_time_s = 0
endif
if freeze_time_s > totalDuration
    freeze_time_s = totalDuration
endif
if number_of_freeze_points < 2
    number_of_freeze_points = 2
endif
if number_of_freeze_points > 20
    number_of_freeze_points = 20
endif
if crossfade_s < 0.1
    crossfade_s = 0.1
endif
if dwell_s < 0
    dwell_s = 0
endif
if shimmer < 0
    shimmer = 0
endif
if shimmer > 1
    shimmer = 1
endif
if fade_in_s < 0
    fade_in_s = 0
endif
if fade_out_s < 0
    fade_out_s = 0
endif

# Python rounds the requested analysis window up to a power of two.
requestedWindowSamples = round(window_ms / 1000 * sr)
if requestedWindowSamples < 1
    requestedWindowSamples = 1
endif
fftSamples = 64
while fftSamples < requestedWindowSamples
    fftSamples = fftSamples * 2
endwhile
effectiveWindowMs = 1000 * fftSamples / sr

# ---- BUILD FREEZE TIMES STRING (multi mode) ----
freezeTimesStr$ = ""
nFP = number_of_freeze_points

if freeze_mode = 2
    margin = totalDuration * 0.05
    if margin > 0.5
        margin = 0.5
    endif
    rangeStart = margin
    rangeEnd   = totalDuration - margin
    if rangeEnd <= rangeStart
        rangeStart = 0
        rangeEnd   = totalDuration
    endif
    span = rangeEnd - rangeStart

    for fp from 1 to nFP
        if nFP > 1
            fpTime = rangeStart + (fp - 1) * span / (nFP - 1)
        else
            fpTime = totalDuration / 2
        endif
        if fp > 1
            freezeTimesStr$ = freezeTimesStr$ + ","
        endif
        freezeTimesStr$ = freezeTimesStr$ + fixed$(fpTime, 4)
    endfor
endif

# ---- MODE LABEL ----
if freeze_mode = 1
    modeLabel$ = "Single"
else
    modeLabel$ = "Multi (" + string$(nFP) + " points)"
endif

# ---- PHASE MODE ----
if phase = 2
    phaseMode$ = "coherent"
else
    phaseMode$ = "random"
endif

# ---- INFO ----
clearinfo
writeInfoLine:  "=== Spectral Freeze v3.3 ==="
appendInfoLine: "Input: ", soundName$, "  (", fixed$(totalDuration, 3), "s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Mode:   ", modeLabel$
appendInfoLine: ""
if freeze_mode = 1
    appendInfoLine: "Freeze at:   ", fixed$(freeze_time_s, 3), " s"
else
    appendInfoLine: "Freeze pts:  ", freezeTimesStr$
    appendInfoLine: "Crossfade:   ", fixed$(crossfade_s, 2), " s"
    appendInfoLine: "Dwell:       ", fixed$(dwell_s, 2), " s"
    appendInfoLine: "Loop:        ", string$(loop)
    if loop = 0
        onePassDur = nFP * dwell_s + (nFP - 1) * crossfade_s
        if duration_s < onePassDur - 0.01
            appendInfoLine: "  NOTE: Duration (", fixed$(duration_s, 1), "s) < one pass (", fixed$(onePassDur, 1), "s); later waypoints not reached."
        endif
    endif
endif
appendInfoLine: "Duration:    ", fixed$(duration_s, 2), " s"
appendInfoLine: "Window:      requested ", fixed$(window_ms, 1), " ms  |  FFT ", fftSamples, " samples = ", fixed$(effectiveWindowMs, 1), " ms"
appendInfoLine: "Shimmer:     ", fixed$(shimmer, 2)
appendInfoLine: "Phase:       ", phaseMode$
appendInfoLine: "Fades:       in ", fixed$(fade_in_s, 2), " s  out ", fixed$(fade_out_s, 2), " s"
appendInfoLine: "Python:      ", pythonCmd$
appendInfoLine: ""

# ===========================================================================
# STAGE 1 — Export WAV
# ===========================================================================
appendInfoLine: "[1/4] Exporting WAV..."
selectObject: sound
Save as WAV file: tempInput$

# ===========================================================================
# STAGE 2 — Call Python
# ===========================================================================
appendInfoLine: "[2/4] Running spectral freeze engine..."

if freeze_mode = 1
    runSystem_nocheck: pythonCmd$ + " """ + pythonScriptJ$ + """"
        ... + " """ + tempInputJ$ + """"
        ... + " """ + tempOutputJ$ + """"
        ... + " " + fixed$(freeze_time_s, 6)
        ... + " " + fixed$(duration_s, 4)
        ... + " " + fixed$(window_ms, 2)
        ... + " " + fixed$(shimmer, 4)
        ... + " " + fixed$(fade_in_s, 4)
        ... + " " + fixed$(fade_out_s, 4)
        ... + " single"
        ... + " " + phaseMode$
        ... + " > """ + tempLogJ$ + """ 2>&1"
else
    runSystem_nocheck: pythonCmd$ + " """ + pythonScriptJ$ + """"
        ... + " """ + tempInputJ$ + """"
        ... + " """ + tempOutputJ$ + """"
        ... + " " + freezeTimesStr$
        ... + " " + fixed$(duration_s, 4)
        ... + " " + fixed$(window_ms, 2)
        ... + " " + fixed$(shimmer, 4)
        ... + " " + fixed$(fade_in_s, 4)
        ... + " " + fixed$(fade_out_s, 4)
        ... + " multi"
        ... + " " + fixed$(crossfade_s, 4)
        ... + " " + fixed$(dwell_s, 4)
        ... + " " + string$(loop)
        ... + " " + phaseMode$
        ... + " > """ + tempLogJ$ + """ 2>&1"
endif

# ===========================================================================
# STAGE 3 — Verify & Import
# ===========================================================================
if not fileReadable(tempOutput$)
    pyErr$ = ""
    if fileReadable(tempLog$)
        pyErr$ = readFile$(tempLog$)
    endif
    if pyErr$ = ""
        pyErr$ = "(no Python output captured)"
    endif
    @cleanUpTempFiles
    exitScript: "Python spectral freeze failed." + newline$ + newline$ + pyErr$
endif

appendInfoLine: "[3/4] Importing result..."

Read from file: tempOutput$
if freeze_mode = 1
    Rename: soundName$ + "_freeze"
else
    Rename: soundName$ + "_multiFreeze"
endif
resultSound = selected("Sound")

# ---- RESULT STATS ----
selectObject: resultSound
durOut = Get total duration
nChannelsOut = Get number of channels
rms_out = Get root-mean-square: 0, 0

selectObject: sound
rms_orig = Get root-mean-square: 0, 0

###############################################################################
# VISUALIZATION
###############################################################################

if draw_visualization
    appendInfoLine: "[4/4] Creating visualization..."

    # Use the strongest-RMS real channel for display only. Processing itself
    # preserves all channels in Python.
    if nChannels > 1
        bestInRms = -1
        monoInViz = 0
        for ch from 1 to nChannels
            selectObject: sound
            Extract one channel: ch
            cand = selected("Sound")
            candRms = Get root-mean-square: 0, 0
            if candRms > bestInRms
                if monoInViz <> 0
                    removeObject: monoInViz
                endif
                monoInViz = cand
                bestInRms = candRms
            else
                removeObject: cand
            endif
        endfor
    else
        selectObject: sound
        Copy: "freeze_input_viz"
        monoInViz = selected("Sound")
    endif

    if nChannelsOut > 1
        bestOutRms = -1
        monoOutViz = 0
        for ch from 1 to nChannelsOut
            selectObject: resultSound
            Extract one channel: ch
            cand = selected("Sound")
            candRms = Get root-mean-square: 0, 0
            if candRms > bestOutRms
                if monoOutViz <> 0
                    removeObject: monoOutViz
                endif
                monoOutViz = cand
                bestOutRms = candRms
            else
                removeObject: cand
            endif
        endfor
    else
        selectObject: resultSound
        Copy: "freeze_output_viz"
        monoOutViz = selected("Sound")
    endif

    vizMaxHz = sr / 2
    if vizMaxHz > 5000
        vizMaxHz = 5000
    endif

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # === Title ===
    Select outer viewport: 0, 8, 0, 0.78
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.74, "half", "##SPECTRAL FREEZE##"
    Font size: 7
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.22, "half", soundName$ + " | " + presetName$ + " | " + modeLabel$ + " | " + phaseMode$ + " | Shimmer " + fixed$(shimmer, 2)

    # === Input Waveform with freeze markers ===
    Select outer viewport: 0, 8, 0.88, 1.82
    Select inner viewport: 0.6, 7.7, 0.96, 1.76
    selectObject: monoInViz
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"

    if freeze_mode = 1
        Colour: "{0.8, 0.3, 0.3}"
        Line width: 2
        Draw line: freeze_time_s, -1, freeze_time_s, 1
        Line width: 1
    else
        for fp from 1 to nFP
            if nFP > 1
                fpTime = rangeStart + (fp - 1) * span / (nFP - 1)
            else
                fpTime = totalDuration / 2
            endif
            rCol = 0.2 + 0.6 * (fp - 1) / max(nFP - 1, 1)
            bCol = 0.8 - 0.6 * (fp - 1) / max(nFP - 1, 1)
            Colour: "{" + fixed$(rCol, 2) + ", 0.3, " + fixed$(bCol, 2) + "}"
            Line width: 2
            Draw line: fpTime, -1, fpTime, 1
            Line width: 1
            Font size: 5
            Text: fpTime, "centre", -0.85, "half", string$(fp)
        endfor
    endif

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Text top: "no", fixed$(totalDuration, 2) + " s"

    if freeze_mode = 1
        Font size: 6
        Colour: "{0.8, 0.3, 0.3}"
        freezeX = freeze_time_s / totalDuration
        if freezeX < 0.85
            Text: freeze_time_s, "left", 0.9, "half", " " + fixed$(freeze_time_s, 3) + "s"
        else
            Text: freeze_time_s, "right", 0.9, "half", fixed$(freeze_time_s, 3) + "s "
        endif
    endif

    # === Output Waveform ===
    Select outer viewport: 0, 8, 1.90, 2.72
    Select inner viewport: 0.6, 7.7, 1.97, 2.66
    selectObject: monoOutViz
    Colour: "{0.3, 0.6, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Frozen"
    Text top: "no", fixed$(durOut, 2) + " s"

    # === Input Spectrogram with freeze line(s) ===
    Select outer viewport: 0, 8, 2.84, 4.12
    Select inner viewport: 0.6, 7.7, 2.94, 4.03

    selectObject: monoInViz
    Copy: "tmpOrig"
    tmpOrig = selected("Sound")

    To Spectrogram: 0.005, vizMaxHz, 0.01, 20, "Gaussian"
    specOrig = selected("Spectrogram")
    Paint: 0, 0, 0, vizMaxHz, 100, "yes", 50, 6, 0, "no"

    if freeze_mode = 1
        Colour: "{0.8, 0.3, 0.3}"
        Line width: 2
        Draw line: freeze_time_s, 0, freeze_time_s, vizMaxHz
        Line width: 1
    else
        for fp from 1 to nFP
            if nFP > 1
                fpTime = rangeStart + (fp - 1) * span / (nFP - 1)
            else
                fpTime = totalDuration / 2
            endif
            rCol = 0.2 + 0.6 * (fp - 1) / max(nFP - 1, 1)
            bCol = 0.8 - 0.6 * (fp - 1) / max(nFP - 1, 1)
            Colour: "{" + fixed$(rCol, 2) + ", 0.3, " + fixed$(bCol, 2) + "}"
            Line width: 2
            Draw line: fpTime, 0, fpTime, vizMaxHz
            Line width: 1
        endfor
    endif

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    if freeze_mode = 1
        Text top: "no", "Original Spectrogram (red = freeze point)"
    else
        Text top: "no", "Original Spectrogram (lines = freeze waypoints)"
    endif

    removeObject: specOrig, tmpOrig

    # === Frozen Spectrogram ===
    Select outer viewport: 0, 8, 4.22, 5.48
    Select inner viewport: 0.6, 7.7, 4.31, 5.39

    selectObject: monoOutViz
    Copy: "tmpFreeze"
    tmpFreeze = selected("Sound")

    To Spectrogram: 0.005, vizMaxHz, 0.01, 20, "Gaussian"
    specFreeze = selected("Spectrogram")
    Paint: 0, 0, 0, vizMaxHz, 100, "yes", 50, 6, 0, "no"

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text top: "no", "Frozen Spectrogram"

    removeObject: specFreeze, tmpFreeze

    # === Frozen Frame Spectrum (snapshot) ===
    Select outer viewport: 0, 4, 5.66, 6.92
    Select inner viewport: 0.6, 3.7, 5.77, 6.82

    selectObject: monoInViz
    Copy: "tmpSlice"
    tmpSlice = selected("Sound")

    To Spectrogram: 0.005, vizMaxHz, 0.01, 20, "Gaussian"
    specSlice = selected("Spectrogram")

    if freeze_mode = 1
        sliceTime = freeze_time_s
    else
        sliceTime = rangeStart
    endif
    sliceSpec = To Spectrum (slice): sliceTime

    selectObject: sliceSpec
    Colour: "{0.4, 0.5, 0.8}"
    Line width: 2
    Draw: 0, vizMaxHz, 0, 0, "no"
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "dB/Hz"
    Text bottom: "yes", "Frequency (Hz)"
    if freeze_mode = 1
        Text top: "no", "Frozen Frame @ " + fixed$(freeze_time_s, 3) + "s"
    else
        Text top: "no", "First Waypoint @ " + fixed$(sliceTime, 3) + "s"
    endif

    removeObject: specSlice, sliceSpec, tmpSlice

    # === Output Intensity Envelope ===
    Select outer viewport: 4, 8, 5.66, 6.92
    Select inner viewport: 4.4, 7.7, 5.77, 6.82

    selectObject: monoOutViz
    Copy: "tmpOutI"
    tmpOutI = selected("Sound")

    To Intensity: 100, 0, "yes"
    intOut = selected("Intensity")

    Axes: 0, durOut, 30, 90
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, durOut, 30, 90

    selectObject: intOut
    Colour: "{0.3, 0.6, 0.5}"
    Line width: 2
    Draw: 0, 0, 0, 0, "no"
    Line width: 1

    if fade_in_s > 0
        Paint rectangle: "{0.9, 0.9, 0.95}", 0, fade_in_s, 30, 90
    endif
    if fade_out_s > 0
        Paint rectangle: "{0.9, 0.9, 0.95}", durOut - fade_out_s, durOut, 30, 90
    endif

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "dB"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Output Intensity (shaded = fade regions)"

    removeObject: intOut, tmpOutI

    # === Summary Panel ===
    Select outer viewport: 0, 8, 7.08, 8.0
    Select inner viewport: 0.6, 7.7, 7.17, 7.90

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.05, "left", 0.8, "half", "Freeze Parameters:"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    if freeze_mode = 1
        Text: 0.05, "left", 0.55, "half", "Freeze: " + fixed$(freeze_time_s, 3) + "s | FFT window: " + fixed$(effectiveWindowMs, 1) + "ms | Shimmer: " + fixed$(shimmer, 2)
    else
        Text: 0.05, "left", 0.55, "half", "Points: " + string$(nFP) + " | Xfade: " + fixed$(crossfade_s, 2) + "s | Dwell: " + fixed$(dwell_s, 2) + "s | Loop: " + string$(loop)
    endif
    Text: 0.05, "left", 0.3, "half", "Fade in: " + fixed$(fade_in_s, 2) + "s | Fade out: " + fixed$(fade_out_s, 2) + "s | RMS: " + fixed$(rms_out, 4)

    Font size: 7
    Colour: "Black"
    Text: 0.65, "left", 0.8, "half", "Signal Info:"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.65, "left", 0.55, "half", "In: " + fixed$(totalDuration, 2) + "s | Out: " + fixed$(durOut, 2) + "s | SR: " + string$(sr) + " Hz"
    Text: 0.65, "left", 0.3, "half", "Channels: " + string$(nChannels) + " -> " + string$(nChannelsOut) + " | Preset: " + presetName$

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"

    removeObject: monoInViz, monoOutViz
else
    appendInfoLine: "[4/4] Visualization skipped."
endif

# ===========================================================================
# CLEANUP & SUMMARY
# ===========================================================================
@cleanUpTempFiles

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
if freeze_mode = 1
    appendInfoLine: "Output: ", soundName$, "_freeze  (", fixed$(durOut, 2), "s)"
    appendInfoLine: "Frozen at: ", fixed$(freeze_time_s, 3), "s"
else
    appendInfoLine: "Output: ", soundName$, "_multiFreeze  (", fixed$(durOut, 2), "s)"
    appendInfoLine: "Waypoints: ", freezeTimesStr$
    appendInfoLine: "Crossfade: ", fixed$(crossfade_s, 2), "s  Dwell: ", fixed$(dwell_s, 2), "s  Loop: ", string$(loop)
endif
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "RMS original: ", fixed$(rms_orig, 6)
appendInfoLine: "RMS frozen:   ", fixed$(rms_out, 6)

selectObject: resultSound

if play_result
    Play
endif
