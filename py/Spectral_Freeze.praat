# ============================================================
# Praat AudioTools - Spectral_Freeze.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 3.0 (2026) - Multi-Freeze mode
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral freeze — captures the spectrum at one or more moments
#   and sustains it via phase randomization OLA.
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
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")

# ---- PATHS ----
pluginDir$ = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/spectral_freeze.py"

tempInput$  = pluginDir$ + "freeze_input.wav"
tempOutput$ = pluginDir$ + "freeze_output.wav"

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: " + pythonScript$ + newline$
        ... + "Please verify AudioTools installation."
endif

# ---- GET INPUT STATS ----
selectObject: sound
totalDuration = Get total duration
sr = Get sampling frequency
nChannels = Get number of channels

# ---- FORM ----
form Spectral Freeze v3.0
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Drone (static, pure)
        option Pad (soft breathing)
        option Shimmer (lively, unstable)
        option Long fade (cinematic)
        option Evolving Landscape (multi-freeze)
        option Vowel Drift (multi-freeze)
        option Frozen Glissando (multi-freeze, loop)
    comment === Mode ===
    optionmenu Freeze_mode: 1
        option Single freeze point
        option Multi-freeze (evolving texture)
    comment === Single-freeze point (seconds) ===
    real Freeze_time_s 0.5
    comment === Multi-freeze settings ===
    positive Number_of_freeze_points 4
    real Crossfade_s 2.0
    real Dwell_s 1.5
    boolean Loop 0
    comment === Output ===
    positive Duration_s 8.0
    comment === Analysis ===
    positive Window_ms 80.0
    comment === Character ===
    real Shimmer 0.15
    comment === Fades ===
    real Fade_in_s 0.5
    real Fade_out_s 1.0
    comment === Display ===
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
    presetName$ = "Drone"
elsif preset = 3
    window_ms  = 80
    shimmer    = 0.15
    fade_in_s  = 0.5
    fade_out_s = 1.0
    freeze_mode = 1
    presetName$ = "Pad"
elsif preset = 4
    window_ms  = 40
    shimmer    = 0.4
    fade_in_s  = 0.1
    fade_out_s = 0.5
    freeze_mode = 1
    presetName$ = "Shimmer"
elsif preset = 5
    window_ms  = 100
    shimmer    = 0.1
    fade_in_s  = 2.0
    fade_out_s = 3.0
    freeze_mode = 1
    presetName$ = "LongFade"
elsif preset = 6
    # Evolving Landscape: spread waypoints evenly, long crossfades
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
    presetName$ = "EvolvingLandscape"
elsif preset = 7
    # Vowel Drift: closely spaced points, short dwell, medium crossfade
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
    presetName$ = "VowelDrift"
elsif preset = 8
    # Frozen Glissando: looping through waypoints
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
    presetName$ = "FrozenGlissando"
endif

# ---- CLAMP PARAMETERS ----
if freeze_time_s < 0
    freeze_time_s = 0
endif
if freeze_time_s > totalDuration - 0.01
    freeze_time_s = totalDuration - 0.01
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

# ---- BUILD FREEZE TIMES STRING (multi mode) ----
# Auto-distribute freeze points evenly across the source
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

# ---- INFO ----
clearinfo
writeInfoLine:  "=== Spectral Freeze v3.0 ==="
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
endif
appendInfoLine: "Duration:    ", fixed$(duration_s, 2), " s"
appendInfoLine: "Window:      ", fixed$(window_ms, 0), " ms"
appendInfoLine: "Shimmer:     ", fixed$(shimmer, 2)
appendInfoLine: "Fades:       in ", fixed$(fade_in_s, 2), " s  out ", fixed$(fade_out_s, 2), " s"
appendInfoLine: ""

# ---- EXPORT ----
appendInfoLine: "[1/4] Exporting WAV..."
selectObject: sound
Save as WAV file: tempInput$

# ---- CALL PYTHON ----
appendInfoLine: "[2/4] Running spectral freeze engine..."

pythonCmd$ = "python3"
if windows
    pythonCmd$ = "py"
endif

if freeze_mode = 1
    # Single mode
    runSystem: pythonCmd$ + " """ + pythonScript$ + """"
        ... + " """ + tempInput$ + """"
        ... + " """ + tempOutput$ + """"
        ... + " " + fixed$(freeze_time_s, 6)
        ... + " " + fixed$(duration_s, 4)
        ... + " " + fixed$(window_ms, 2)
        ... + " " + fixed$(shimmer, 4)
        ... + " " + fixed$(fade_in_s, 4)
        ... + " " + fixed$(fade_out_s, 4)
        ... + " single"
else
    # Multi mode
    runSystem: pythonCmd$ + " """ + pythonScript$ + """"
        ... + " """ + tempInput$ + """"
        ... + " """ + tempOutput$ + """"
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
endif

# ---- VERIFY OUTPUT ----
if not fileReadable(tempOutput$)
    deleteFile: tempInput$
    exitScript: "Python spectral freeze failed." + newline$
        ... + "Possible causes:" + newline$
        ... + "  - numpy or soundfile not installed" + newline$
        ... + "  - Python not found in PATH" + newline$
        ... + "Check the terminal/console for Python error messages."
endif

# ---- IMPORT RESULT ----
appendInfoLine: "[3/4] Importing result..."

Read from file: tempOutput$
if freeze_mode = 1
    Rename: soundName$ + "_freeze"
else
    Rename: soundName$ + "_multiFreeze"
endif
resultSound = selected("Sound")

# ---- CLEANUP TEMP FILES ----
deleteFile: tempInput$
deleteFile: tempOutput$

# ---- RESULT STATS ----
selectObject: resultSound
durOut = Get total duration
rms_out = Get root-mean-square: 0, 0

selectObject: sound
rms_orig = Get root-mean-square: 0, 0

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
    Text: 0.5, "centre", 0.6, "half", "##Spectral Freeze v3.0##"
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -1.2, "half", soundName$ + " | " + presetName$ + " | " + modeLabel$ + " | Shimmer: " + fixed$(shimmer, 2)

    # === Input Waveform with freeze markers ===
    Select outer viewport: 0, 8, 0.6, 1.6
    Select inner viewport: 0.6, 7.7, 0.65, 1.55
    selectObject: sound
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"

    # Draw freeze point markers
    if freeze_mode = 1
        # Single: red vertical line
        Colour: "{0.8, 0.3, 0.3}"
        Line width: 2
        Draw line: freeze_time_s, -1, freeze_time_s, 1
        Line width: 1
    else
        # Multi: coloured markers for each waypoint
        for fp from 1 to nFP
            if nFP > 1
                fpTime = rangeStart + (fp - 1) * span / (nFP - 1)
            else
                fpTime = totalDuration / 2
            endif
            # Colour gradient from blue to red across waypoints
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

    # Freeze time label (single mode)
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
    Select outer viewport: 0, 8, 1.6, 2.4
    Select inner viewport: 0.6, 7.7, 1.65, 2.35
    selectObject: resultSound
    Colour: "{0.3, 0.6, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Frozen"
    Text bottom: "yes", "Time (s)"
    Text top: "no", fixed$(durOut, 2) + " s"

    # === Input Spectrogram with freeze line(s) ===
    Select outer viewport: 0, 8, 2.5, 3.8
    Select inner viewport: 0.6, 7.7, 2.6, 3.7

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

    if freeze_mode = 1
        Colour: "{0.8, 0.3, 0.3}"
        Line width: 2
        Draw line: freeze_time_s, 0, freeze_time_s, 5000
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
            Draw line: fpTime, 0, fpTime, 5000
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
    Select outer viewport: 0, 8, 3.8, 5.1
    Select inner viewport: 0.6, 7.7, 3.9, 5.0

    selectObject: resultSound
    Copy: "tmpFreeze"
    tmpFreeze = selected("Sound")

    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    specFreeze = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Frozen Spectrogram"

    removeObject: specFreeze, tmpFreeze

    # === Frozen Frame Spectrum (snapshot) ===
    Select outer viewport: 0, 4, 5.2, 6.8
    Select inner viewport: 0.6, 3.7, 5.35, 6.7

    selectObject: sound
    if nChannels > 1
        Extract one channel: 1
        tmpSlice = selected("Sound")
    else
        Copy: "tmpSlice"
        tmpSlice = selected("Sound")
    endif

    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    specSlice = selected("Spectrogram")

    if freeze_mode = 1
        sliceTime = freeze_time_s
    else
        # Show first waypoint spectrum
        sliceTime = rangeStart
    endif
    sliceSpec = To Spectrum (slice): sliceTime

    selectObject: sliceSpec
    Colour: "{0.4, 0.5, 0.8}"
    Line width: 2
    Draw: 0, 5000, 0, 0, "no"
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
    Select outer viewport: 4, 8, 5.2, 6.8
    Select inner viewport: 4.4, 7.7, 5.35, 6.7

    selectObject: resultSound
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
    Select outer viewport: 0, 8, 7.0, 8.0
    Select inner viewport: 0.6, 7.7, 7.1, 7.9

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.05, "left", 0.8, "half", "Freeze Parameters:"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    if freeze_mode = 1
        Text: 0.05, "left", 0.55, "half", "Freeze: " + fixed$(freeze_time_s, 3) + "s | Window: " + fixed$(window_ms, 0) + "ms | Shimmer: " + fixed$(shimmer, 2)
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
    Text: 0.65, "left", 0.3, "half", "Channels: " + string$(nChannels) + " | Preset: " + presetName$

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
