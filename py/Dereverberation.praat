# ============================================================
# Praat AudioTools - Dereverberation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.0 (2026) - Unified Cross-Platform Version
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Blind dereverberation using WPE (Weighted Prediction Error).
#   Removes room reverberation without knowing the room acoustics.
#   Powered by nara_wpe (pip install nara_wpe soundfile).
#
#   Parameters:
#   - Iterations:    more = stronger dereverberation (5-20)
#   - Delay:         WPE frame delay (2-5, default 3)
#   - Filter length: prediction filter size (10-30, longer = more reverb removed)
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
pluginDir$ = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/dereverberation.py"

tempInput$    = temporaryDirectory$ + "/temp_dereverb_input.wav"
tempOutput$   = temporaryDirectory$ + "/temp_dereverb_output.wav"
probeMarker$  = temporaryDirectory$ + "/temp_dereverb_probe.ok"

# Replace backslashes for the Python inline probe to prevent escape character crashes on Windows
probeMarkerJ$ = replace_regex$(probeMarker$, "\\", "/", 0)

# Verify Python script exists
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: " + pythonScript$ + newline$ + "Please verify AudioTools installation."
endif

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

# ---- PYTHON DEPENDENCY VALIDATION ----
probeCmd$ = pythonCmd$ + " -c ""import nara_wpe, soundfile; open('""" + probeMarkerJ$ + """', 'w').write('ok')"""
runSystem_nocheck: probeCmd$

if not fileReadable(probeMarker$)
    @cleanUpTempFiles
    exitScript: "Missing Python dependencies!" + newline$ + "Please open your terminal/command prompt and run: pip install nara_wpe soundfile"
endif

deleteFile: probeMarker$

# ---- FORM ----
form Blind Dereverberation (WPE) v2.0
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Light room (small reverb)
        option Medium room
        option Large hall (heavy reverb)
        option Maximum (very wet signal)
    comment === Parameters ===
    positive Iterations 10
    positive Delay 3
    positive Filter_length 15
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- PRESETS ----
if preset = 2
    iterations    = 5
    delay         = 2
    filter_length = 10
    presetName$   = "LightRoom"
elsif preset = 3
    iterations    = 10
    delay         = 3
    filter_length = 15
    presetName$   = "MediumRoom"
elsif preset = 4
    iterations    = 15
    delay         = 3
    filter_length = 20
    presetName$   = "LargeHall"
elsif preset = 5
    iterations    = 20
    delay         = 4
    filter_length = 30
    presetName$   = "Maximum"
else
    presetName$   = "Custom"
endif

# ---- INFO ----
clearinfo
writeInfoLine:  "=== Blind Dereverberation - WPE v2.0 ==="
appendInfoLine: "Input: ", soundName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Iterations:    ", iterations
appendInfoLine: "Delay:         ", delay
appendInfoLine: "Filter length: ", filter_length
appendInfoLine: ""

# ---- CAPTURE ORIGINAL STATS ----
selectObject: sound
dur = Get total duration
sr  = Get sampling frequency
nChannels = Get number of channels
rms_orig = Get root-mean-square: 0, 0

appendInfoLine: "Duration: ", fixed$(dur, 2), " s | SR: ", sr, " Hz | Channels: ", nChannels
appendInfoLine: ""

# ---- EXPORT ----
appendInfoLine: "[1/4] Exporting WAV..."

selectObject: sound
Save as WAV file: tempInput$

# ---- CALL PYTHON ----
appendInfoLine: "[2/4] Running WPE dereverberation..."

pyCmd$ = pythonCmd$ + " """ + pythonScript$ + """ """ + tempInput$ + """ """ + tempOutput$ + """ " + string$(iterations) + " " + string$(delay) + " " + string$(filter_length)

runSystem_nocheck: pyCmd$

# ---- VERIFY OUTPUT ----
if not fileReadable(tempOutput$)
    @cleanUpTempFiles
    exitScript: "Python dereverberation failed. Please check the Praat info window or system terminal for errors."
endif

# ---- IMPORT RESULT ----
appendInfoLine: "[3/4] Importing result..."

Read from file: tempOutput$
Rename: soundName$ + "_dry"
resultSound = selected("Sound")

# ---- RESULT STATS ----
selectObject: resultSound
rms_dry = Get root-mean-square: 0, 0

###############################################################################
# VISUALIZATION
###############################################################################

if draw_visualization
    appendInfoLine: "[4/4] Creating visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # === Title ===
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half", "##Blind Dereverberation — WPE##"
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -1.2, "half", soundName$ + " | " + presetName$ + " | Iter: " + string$(iterations) + " | Taps: " + string$(filter_length)

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
    Text left: "yes", "Dry"
    Text bottom: "yes", "Time (s)"

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

    # === Dereverberated Spectrogram ===
    Select outer viewport: 0, 8, 3.8, 5.3
    Select inner viewport: 0.6, 7.7, 3.9, 5.2

    selectObject: resultSound
    if nChannels > 1
        Extract one channel: 1
        tmpDry = selected("Sound")
    else
        Copy: "tmpDry"
        tmpDry = selected("Sound")
    endif

    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    specDry = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Dereverberated Spectrogram"

    removeObject: specDry, tmpDry

    # === Intensity Comparison ===
    Select outer viewport: 0, 8, 5.4, 6.8
    Select inner viewport: 0.6, 7.7, 5.55, 6.7

    Axes: 0, dur, 30, 90
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, dur, 30, 90

    # Original intensity (grey)
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

    selectObject: intOrig
    Colour: "{0.6, 0.6, 0.6}"
    Line width: 2
    Draw: 0, 0, 0, 0, "no"

    removeObject: intOrig, tmpOrigI

    # Dereverberated intensity (teal)
    selectObject: resultSound
    if nChannels > 1
        Extract one channel: 1
        tmpDryI = selected("Sound")
    else
        Copy: "tmpDryI"
        tmpDryI = selected("Sound")
    endif

    To Intensity: 100, 0, "yes"
    intDry = selected("Intensity")

    selectObject: intDry
    Colour: "{0.3, 0.6, 0.5}"
    Line width: 2
    Draw: 0, 0, 0, 0, "no"

    removeObject: intDry, tmpDryI

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "dB"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Intensity: Grey = original | Green = dereverberated"

    # === Summary Panel ===
    Select outer viewport: 0, 8, 7.0, 8.0
    Select inner viewport: 0.6, 7.7, 7.1, 7.9

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.05, "left", 0.75, "half", "WPE Parameters:"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.05, "left", 0.5, "half", "Iterations: " + string$(iterations) + " | Delay: " + string$(delay) + " | Filter length: " + string$(filter_length)
    Text: 0.05, "left", 0.25, "half", "RMS original: " + fixed$(rms_orig, 4) + " | RMS dry: " + fixed$(rms_dry, 4) + " | Ratio: " + fixed$(rms_dry / rms_orig, 3) + "x"

    Font size: 7
    Colour: "Black"
    Text: 0.65, "left", 0.75, "half", "Signal Info:"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.65, "left", 0.5, "half", "Duration: " + fixed$(dur, 2) + " s | SR: " + string$(sr) + " Hz"
    Text: 0.65, "left", 0.25, "half", "Channels: " + string$(nChannels) + " | Preset: " + presetName$

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
else
    appendInfoLine: "[4/4] Visualization skipped."
endif

# ---- CLEANUP ----
@cleanUpTempFiles

# ---- SUMMARY ----
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", soundName$, "_dry"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "RMS original: ", fixed$(rms_orig, 6)
appendInfoLine: "RMS dry:      ", fixed$(rms_dry, 6)
appendInfoLine: "RMS ratio:    ", fixed$(rms_dry / rms_orig, 3), "x"

selectObject: resultSound

if play_result
    Play
endif