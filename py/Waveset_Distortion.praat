# ============================================================
# Praat AudioTools - Waveset_Distortion.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   CDP-style waveset distortion — segments audio at zero crossings
#   and applies per-waveset transformations. Python-powered for speed.
#
#   Types:
#   1. Repeat     – repeat each waveset N times (octave down at 2x)
#   2. Skip       – randomly drop wavesets (thinning/gating)
#   3. Reverse    – flip each waveset (buzzy/harsh)
#   4. Stretch    – resample each waveset longer (pitch down)
#   5. Compress   – resample each waveset shorter (pitch up)
#   6. Randomize  – shuffle waveset order (scramble)
#   7. Amplitude  – alternate loud/quiet wavesets (tremolo)
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")

# ---- PATHS (plugin-relative for distribution) ----
pluginDir$ = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/waveset_distortion.py"


tempInput$  = pluginDir$ + "wsd_input.wav"
tempOutput$ = pluginDir$ + "wsd_output.wav"

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: " + pythonScript$ + newline$
        ... + "Please verify AudioTools installation."
endif

# ---- ORIGINAL STATS ----
selectObject: sound
dur = Get total duration
sr  = Get sampling frequency
nChannels = Get number of channels
rms_orig = Get root-mean-square: 0, 0

# ---- FORM ----
form Waveset Distortion v2.0
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Octave Down (repeat x2)
        option Stutter (repeat x4)
        option Thin / Gate (skip)
        option Buzz (reverse all)
        option Pitch Shift Down (stretch)
        option Pitch Shift Up (compress)
        option Scramble (randomize)
        option Tremolo (amplitude)
    comment === Type ===
    optionmenu Type: 1
        option Repeat
        option Skip
        option Reverse
        option Stretch
        option Compress
        option Randomize
        option Amplitude
    comment === Amount ===
    positive Amount 2.0
    boolean Preserve_length 0
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- PRESETS ----
if preset = 2
    type = 1
    amount = 2
    preserve_length = 0
    presetName$ = "OctaveDown"
elsif preset = 3
    type = 1
    amount = 4
    preserve_length = 1
    presetName$ = "Stutter"
elsif preset = 4
    type = 2
    amount = 3
    preserve_length = 0
    presetName$ = "ThinGate"
elsif preset = 5
    type = 3
    amount = 1
    preserve_length = 1
    presetName$ = "Buzz"
elsif preset = 6
    type = 4
    amount = 1.5
    preserve_length = 0
    presetName$ = "PitchDown"
elsif preset = 7
    type = 5
    amount = 1.5
    preserve_length = 0
    presetName$ = "PitchUp"
elsif preset = 8
    type = 6
    amount = 0.8
    preserve_length = 1
    presetName$ = "Scramble"
elsif preset = 9
    type = 7
    amount = 3
    preserve_length = 1
    presetName$ = "Tremolo"
else
    presetName$ = "Custom"
endif

# ---- TYPE LABELS ----
if type = 1
    typeLabel$ = "Repeat"
elsif type = 2
    typeLabel$ = "Skip"
elsif type = 3
    typeLabel$ = "Reverse"
elsif type = 4
    typeLabel$ = "Stretch"
elsif type = 5
    typeLabel$ = "Compress"
elsif type = 6
    typeLabel$ = "Randomize"
else
    typeLabel$ = "Amplitude"
endif

# ---- INFO ----
clearinfo
writeInfoLine:  "=== Waveset Distortion v2.0 (Python engine) ==="
appendInfoLine: "Input: ", soundName$, "  (", fixed$(dur, 2), "s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Type:            ", typeLabel$
appendInfoLine: "Amount:          ", fixed$(amount, 2)
appendInfoLine: "Preserve length: ", preserve_length
appendInfoLine: ""

# ---- EXPORT ----
appendInfoLine: "[1/4] Exporting WAV..."

selectObject: sound
Save as WAV file: tempInput$

# ---- CALL PYTHON ----
appendInfoLine: "[2/4] Running Python engine..."

pythonCmd$ = "python"
if windows
    pythonCmd$ = "py"
endif

runSystem: pythonCmd$ + " """ + pythonScript$ + """"
    ... + " """ + tempInput$ + """"
    ... + " """ + tempOutput$ + """"
    ... + " " + string$(type)
    ... + " " + fixed$(amount, 6)
    ... + " " + string$(preserve_length)

# ---- VERIFY OUTPUT ----
if not fileReadable(tempOutput$)
    deleteFile: tempInput$
    exitScript: "Python waveset distortion failed." + newline$
        ... + "Possible causes:" + newline$
        ... + "  - numpy or soundfile not installed" + newline$
        ... + "  - Python not found in PATH" + newline$
        ... + "Check the terminal/console for Python error messages."
endif

# ---- IMPORT RESULT ----
appendInfoLine: "[3/4] Importing result..."

Read from file: tempOutput$
Rename: soundName$ + "_WSD_" + typeLabel$
resultSound = selected("Sound")

# ---- CLEANUP TEMP FILES ----
deleteFile: tempInput$
deleteFile: tempOutput$

# ---- RESULT STATS ----
selectObject: resultSound
durOut = Get total duration
rms_out = Get root-mean-square: 0, 0

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
    Text: 0.5, "centre", 0.6, "half", "##Waveset Distortion — " + typeLabel$ + "##"
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -1.2, "half", soundName$ + " | " + presetName$ + " | Amount: " + fixed$(amount, 2)

    # === Input Waveform ===
    Select outer viewport: 0, 8, 0.6, 1.6
    Select inner viewport: 0.6, 7.7, 0.65, 1.55
    selectObject: sound
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Text top: "no", fixed$(dur, 2) + " s"

    # === Output Waveform ===
    Select outer viewport: 0, 8, 1.6, 2.6
    Select inner viewport: 0.6, 7.7, 1.65, 2.55
    selectObject: resultSound
    Colour: "{0.3, 0.6, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "WSD"
    Text bottom: "yes", "Time (s)"
    Text top: "no", fixed$(durOut, 2) + " s (" + typeLabel$ + ")"

    # === Original Spectrogram ===
    Select outer viewport: 0, 4, 2.7, 4.5
    Select inner viewport: 0.6, 3.7, 2.85, 4.4

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
    Text left: "yes", "Hz"
    Text top: "no", "Original Spectrogram"
    removeObject: specOrig, tmpOrig

    # === Output Spectrogram ===
    Select outer viewport: 4, 8, 2.7, 4.5
    Select inner viewport: 4.4, 7.7, 2.85, 4.4

    selectObject: resultSound
    Copy: "tmpOut"
    tmpOut = selected("Sound")

    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    specOut = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text top: "no", "Distorted Spectrogram"
    removeObject: specOut, tmpOut

    # === Waveform Zoom (first 50ms) — shows waveset-level effect ===
    zoomEnd = min(0.05, dur)
    zoomEndOut = min(0.05, durOut)

    # Original zoom
    Select outer viewport: 0, 4, 4.6, 6.2
    Select inner viewport: 0.6, 3.7, 4.75, 6.1
    Paint rectangle: "{0.98, 0.98, 0.98}", 0, 0, 0, 0

    selectObject: sound
    if nChannels > 1
        Extract one channel: 1
        tmpOrigZ = selected("Sound")
    else
        Copy: "tmpOrigZ"
        tmpOrigZ = selected("Sound")
    endif

    selectObject: tmpOrigZ
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, zoomEnd, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Zoom: Original (0–50 ms)"
    removeObject: tmpOrigZ

    # Distorted zoom
    Select outer viewport: 4, 8, 4.6, 6.2
    Select inner viewport: 4.4, 7.7, 4.75, 6.1
    Paint rectangle: "{0.98, 0.98, 0.98}", 0, 0, 0, 0

    selectObject: resultSound
    Colour: "{0.3, 0.6, 0.5}"
    Draw: 0, zoomEndOut, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Zoom: Distorted (0–50 ms)"

    # === Summary Panel ===
    Select outer viewport: 0, 8, 6.4, 7.4
    Select inner viewport: 0.6, 7.7, 6.5, 7.3

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.05, "left", 0.75, "half", "WSD Parameters:"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.05, "left", 0.5, "half", "Type: " + typeLabel$ + " | Amount: " + fixed$(amount, 2) + " | Preserve length: " + string$(preserve_length)
    Text: 0.05, "left", 0.25, "half", "RMS orig: " + fixed$(rms_orig, 4) + " | RMS out: " + fixed$(rms_out, 4)

    Font size: 7
    Colour: "Black"
    Text: 0.65, "left", 0.75, "half", "Signal Info:"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.65, "left", 0.5, "half", "In: " + fixed$(dur, 2) + "s | Out: " + fixed$(durOut, 2) + "s | Ratio: " + fixed$(durOut / dur, 2) + "x"
    Text: 0.65, "left", 0.25, "half", "SR: " + string$(sr) + " Hz | Preset: " + presetName$

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
else
    appendInfoLine: "[4/4] Visualization skipped."
endif

# ---- SUMMARY ----
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", soundName$, "_WSD_", typeLabel$
appendInfoLine: "Duration: ", fixed$(dur, 2), "s → ", fixed$(durOut, 2), "s (", fixed$(durOut / dur, 2), "x)"
appendInfoLine: "RMS original: ", fixed$(rms_orig, 6)
appendInfoLine: "RMS output:   ", fixed$(rms_out, 6)

selectObject: resultSound

if play_result
    Play
endif
