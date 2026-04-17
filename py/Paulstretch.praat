# ============================================================
# Praat AudioTools - Paulstretch.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.1 (2026) - Unified Cross-Platform Version
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Paulstretch — extreme time-stretching via spectral smearing.
#   Randomizes FFT phases while preserving magnitudes, producing
#   smooth, evolving drone textures from any source material.
#   Powered by Python (numpy + soundfile).
#
#   Parameters:
#   - Stretch factor: multiplier on duration (2 = twice as long)
#   - Window size:    analysis window in seconds (larger = smoother)
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
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
pluginDir$ = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/paulstretch.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/paulstretch.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: paulstretch.py" + newline$ + "Expected at: " + pluginDir$ + "py/ or next to this script."
endif

tempInput$   = temporaryDirectory$ + "/paulstretch_input.wav"
tempOutput$  = temporaryDirectory$ + "/paulstretch_output.wav"
probeMarker$ = temporaryDirectory$ + "/paulstretch_probe.ok"

# Replace backslashes for the Python inline probe
probeMarkerJ$ = replace_regex$(probeMarker$, "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(tempInput$)
        deleteFile: tempInput$
    endif
    if fileReadable(tempOutput$)
        deleteFile: tempOutput$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
endproc

@cleanUpTempFiles

# ---- FORM ----
form Paulstretch v2.1
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Subtle stretch (2x)
        option Medium stretch (5x)
        option Deep stretch (10x)
        option Extreme drone (20x)
        option Frozen texture (50x)
    comment === Parameters ===
    positive Stretch 8.0
    positive Window_seconds 0.25
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- PRESETS ----
if preset = 2
    stretch = 2
    window_seconds = 0.15
    presetName$ = "SubtleStretch"
elsif preset = 3
    stretch = 5
    window_seconds = 0.25
    presetName$ = "MediumStretch"
elsif preset = 4
    stretch = 10
    window_seconds = 0.35
    presetName$ = "DeepStretch"
elsif preset = 5
    stretch = 20
    window_seconds = 0.5
    presetName$ = "ExtremeDrone"
elsif preset = 6
    stretch = 50
    window_seconds = 1.0
    presetName$ = "FrozenTexture"
else
    presetName$ = "Custom"
endif

# ---- INFO ----
clearinfo
writeInfoLine:  "=== Paulstretch v2.1 ==="
appendInfoLine: "Input: ", soundName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Stretch:  ", fixed$(stretch, 1), "x"
appendInfoLine: "Window:   ", fixed$(window_seconds, 3), " s"
appendInfoLine: ""

# ---- CAPTURE ORIGINAL STATS ----
selectObject: sound
dur = Get total duration
sr  = Get sampling frequency
nChannels = Get number of channels
rms_orig = Get root-mean-square: 0, 0

expectedDur = dur * stretch

appendInfoLine: "Duration: ", fixed$(dur, 2), " s | SR: ", sr, " Hz | Channels: ", nChannels
appendInfoLine: "Expected output: ~", fixed$(expectedDur, 1), " s"
appendInfoLine: ""

# ===========================================================================
# Stage 1 — Detect Python Dependencies
# ===========================================================================
appendInfoLine: "[1/4] Detecting Python dependencies..."

probeCmd$ = pythonCmd$ + " -c ""import numpy, scipy, soundfile; open('""" + probeMarkerJ$ + """', 'w').write('ok')"""
runSystem_nocheck: probeCmd$

if not fileReadable(probeMarker$)
    @cleanUpTempFiles
    exitScript: "Python not found or dependencies missing." + newline$ + "Please install: pip install numpy scipy soundfile"
endif

deleteFile: probeMarker$
appendInfoLine: "  Python found: ", pythonCmd$

# ===========================================================================
# Stage 2 — Export
# ===========================================================================
appendInfoLine: "[2/4] Exporting WAV..."

selectObject: sound
Save as WAV file: tempInput$

# ===========================================================================
# Stage 3 — Call Python
# ===========================================================================
appendInfoLine: "[3/4] Running Paulstretch (this may take a while)..."

pythonCall$ = pythonCmd$ + " """ + pythonScript$ + """"
    ... + " """ + tempInput$ + """"
    ... + " """ + tempOutput$ + """"
    ... + " " + fixed$(stretch, 4)
    ... + " " + fixed$(window_seconds, 4)

runSystem_nocheck: pythonCall$

# ---- VERIFY OUTPUT ----
if not fileReadable(tempOutput$)
    @cleanUpTempFiles
    exitScript: "Python Paulstretch failed." + newline$ + "Check the terminal/console for Python error messages."
endif

# ===========================================================================
# Stage 4 — Import Result
# ===========================================================================
appendInfoLine: "[4/4] Importing result..."

Read from file: tempOutput$
Rename: soundName$ + "_stretched"
resultSound = selected("Sound")

# ---- RESULT STATS ----
selectObject: resultSound
durOut = Get total duration
rms_out = Get root-mean-square: 0, 0

appendInfoLine: "Actual output: ", fixed$(durOut, 2), " s"

###############################################################################
# VISUALIZATION
###############################################################################

if draw_visualization
    appendInfoLine: "Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # === Title ===
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half", "##Paulstretch — Spectral Time Stretch##"
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -1.2, "half", soundName$ + " | " + presetName$ + " | " + fixed$(stretch, 1) + "x | Window: " + fixed$(window_seconds, 3) + " s"

    # === Input Waveform ===
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.7, 0.65, 1.35
    selectObject: sound
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Text top: "no", fixed$(dur, 2) + " s"

    # === Output Waveform ===
    Select outer viewport: 0, 8, 1.4, 2.2
    Select inner viewport: 0.6, 7.7, 1.45, 2.15
    selectObject: resultSound
    Colour: "{0.3, 0.6, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Stretched"
    Text bottom: "yes", "Time (s)"
    Text top: "no", fixed$(durOut, 2) + " s (" + fixed$(stretch, 1) + "x)"

    # === Original Spectrogram ===
    Select outer viewport: 0, 8, 2.3, 3.8
    Select inner viewport: 0.6, 7.7, 2.4, 3.7

    selectObject: sound
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
    Text top: "no", "Original Spectrogram"

    removeObject: specOrig, tmpOrig

    # === Stretched Spectrogram ===
    Select outer viewport: 0, 8, 3.8, 5.3
    Select inner viewport: 0.6, 7.7, 3.9, 5.2

    selectObject: resultSound
    if nChannels > 1
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
    Text top: "no", "Stretched Spectrogram"

    removeObject: specOut, tmpOut

    # === Spectral Centroid Comparison ===
    Select outer viewport: 0, 8, 5.4, 6.8
    Select inner viewport: 0.6, 7.7, 5.55, 6.7

    selectObject: sound
    if nChannels > 1
        Extract one channel: 1
        tmpOrigI = selected("Sound")
    else
        Copy: "tmpOrigI"
        tmpOrigI = selected("Sound")
    endif

    To Intensity: 100, 0, "yes"
    intOrig = selected("Intensity")

    intMin_orig = Get minimum: 0, 0, "Parabolic"
    intMax_orig = Get maximum: 0, 0, "Parabolic"

    selectObject: resultSound
    if nChannels > 1
        Extract one channel: 1
        tmpOutI = selected("Sound")
    else
        Copy: "tmpOutI"
        tmpOutI = selected("Sound")
    endif

    To Intensity: 100, 0, "yes"
    intOut = selected("Intensity")

    intMin_out = Get minimum: 0, 0, "Parabolic"
    intMax_out = Get maximum: 0, 0, "Parabolic"

    intMin = min(intMin_orig, intMin_out) - 5
    intMax = max(intMax_orig, intMax_out) + 5

    Axes: 0, 1, intMin, intMax
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, 1, intMin, intMax

    selectObject: intOrig
    Colour: "{0.6, 0.6, 0.6}"
    Line width: 2
    Draw: 0, 0, intMin, intMax, "no"

    selectObject: intOut
    Colour: "{0.3, 0.6, 0.5}"
    Line width: 2
    Draw: 0, 0, intMin, intMax, "no"

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "dB"
    Text bottom: "yes", "Relative time"
    Text top: "no", "Intensity Envelope: Grey = original | Green = stretched (own timescale)"

    removeObject: intOrig, tmpOrigI, intOut, tmpOutI

    # === Summary Panel ===
    Select outer viewport: 0, 8, 7.0, 8.0
    Select inner viewport: 0.6, 7.7, 7.1, 7.9

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.05, "left", 0.75, "half", "Paulstretch Parameters:"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.05, "left", 0.5, "half", "Stretch: " + fixed$(stretch, 1) + "x | Window: " + fixed$(window_seconds, 3) + " s"
    Text: 0.05, "left", 0.25, "half", "RMS original: " + fixed$(rms_orig, 4) + " | RMS stretched: " + fixed$(rms_out, 4)

    Font size: 7
    Colour: "Black"
    Text: 0.65, "left", 0.75, "half", "Signal Info:"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.65, "left", 0.5, "half", "In: " + fixed$(dur, 2) + " s | Out: " + fixed$(durOut, 2) + " s | SR: " + string$(sr) + " Hz"
    Text: 0.65, "left", 0.25, "half", "Channels: " + string$(nChannels) + " | Preset: " + presetName$

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
else
    appendInfoLine: "[4/4] Visualization skipped."
endif

# ---- CLEANUP AND SUMMARY ----
@cleanUpTempFiles

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", soundName$, "_stretched"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Duration: ", fixed$(dur, 2), " s → ", fixed$(durOut, 2), " s (", fixed$(stretch, 1), "x)"
appendInfoLine: "RMS original:  ", fixed$(rms_orig, 6)
appendInfoLine: "RMS stretched: ", fixed$(rms_out, 6)

selectObject: resultSound

if play_result
    Play
endif