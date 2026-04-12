# ============================================================
# Praat AudioTools - Multichannel_to_Binaural.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Multichannel-to-binaural downmix via Spat5 virtual speakers.
#   Takes any multichannel Sound (mono to 24-channel 22.2) and
#   renders a stereo binaural output using HRTF convolution.
#
#   Single-stage pipeline: the input channels are treated as
#   speaker feeds at known positions, and spat5.virtualspeakers~
#   convolves each with the corresponding HRIR pair to produce
#   a binaural sum.
#
#   Supported layouts:
#     1 ch  — Mono (centre)
#     2 ch  — Stereo (L/R at +/-30 deg)
#     4 ch  — Quad (FL/FR/BL/BR)
#     5 ch  — 5.0 (L/R/C/Ls/Rs)
#     6 ch  — 5.1 (L/R/C/LFE/Ls/Rs)
#     8 ch  — 7.1 (L/R/C/LFE/Ls/Rs/Lss/Rss)
#    10 ch  — 7.1.2 (7.1 + TpFL/TpFR)
#    12 ch  — 7.1.4 (7.1 + TpFL/TpFR/TpBL/TpBR)
#    24 ch  — 22.2 (NHK full sphere)
#
# Dependencies:
#   Spat5 (IRCAM) — spat5.virtualspeakers~ command-line tool
#   Python 3
#
# Changelog:
#   v1.2 — Fix: tools_folder$ moved into the form so path is user-editable
#          Fix: Room_preset no longer overwrites Hrtf_preset room
#          Fix: log file preserved on render failure for diagnostics
#          Fix: log file deleted only on success
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
sourceName$ = selected$("Sound")
selectObject: original
numCh    = Get number of channels
duration = Get total duration
sr       = Get sampling frequency

# ---- FIXED PATHS (not user-editable) ----
helper_py$      = defaultDirectory$ + "/spat_binaural_bridge.py"
working_folder$ = defaultDirectory$ + "/"

# ---- FORM ----
form Multichannel to Binaural v1.2

    comment === SPAT5 TOOLS FOLDER ===
    comment Folder containing spat5.virtualspeakers~.exe
    sentence Tools_folder C:/Users/User/Documents/Max 9/Packages/spat5-x64/media/tools/

    comment === SPEAKER LAYOUT ===
    optionmenu Layout_preset: 1
        option "Auto-detect from channel count"
        option "2.0  --- Stereo"
        option "4.0  --- Quad"
        option "5.0  --- Surround (no LFE)"
        option "5.1  --- Surround + LFE"
        option "7.0  --- Surround 7ch"
        option "7.1  --- Surround 7.1"
        option "7.1.2 --- Surround + Height pair"
        option "7.1.4 --- Surround + Height quad"
        option "22.2 --- NHK Full Sphere (24 ch)"

    comment === HRTF / ROOM ===
    comment Room_preset is ignored unless Hrtf_preset is "SOFA custom / none"
    optionmenu Hrtf_preset: 1
        option "KEMAR / neutral"
        option "KEMAR / hall"
        option "KEMAR / studio"
        option "SOFA custom / none"
    sentence Sofa_file kemar
    real Itd_percent 100
    optionmenu Room_preset: 1
        option "none"
        option "hall"
        option "livingroom"
        option "studio"

    comment === OUTPUT ===
    real Pre_gain_db -6
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# tools_folder$ comes from the form field tools_folder$
# Praat names it lowercase with underscores automatically.

# ---- RESOLVE HRTF PRESET ----
# Room_preset only applies for Hrtf_preset 4 (custom SOFA).
# Presets 1-3 carry their own room setting which must not be overwritten.
if hrtf_preset = 1
    actualSOFA$ = "kemar"
    roomName$   = "none"
elsif hrtf_preset = 2
    actualSOFA$ = "kemar"
    roomName$   = "hall"
elsif hrtf_preset = 3
    actualSOFA$ = "kemar"
    roomName$   = "studio"
else
    # Custom SOFA: honour the Room_preset menu
    actualSOFA$ = sofa_file$
    if room_preset = 1
        roomName$ = "none"
    elsif room_preset = 2
        roomName$ = "hall"
    elsif room_preset = 3
        roomName$ = "livingroom"
    else
        roomName$ = "studio"
    endif
endif

# ---- RESOLVE LAYOUT ----
if layout_preset = 1
    if numCh = 1
        layoutToken$ = "mono"
    elsif numCh = 2
        layoutToken$ = "2.0"
    elsif numCh = 4
        layoutToken$ = "4.0"
    elsif numCh = 5
        layoutToken$ = "5.0"
    elsif numCh = 6
        layoutToken$ = "5.1"
    elsif numCh = 7
        layoutToken$ = "7.0"
    elsif numCh = 8
        layoutToken$ = "7.1"
    elsif numCh = 10
        layoutToken$ = "7.1.2"
    elsif numCh = 12
        layoutToken$ = "7.1.4"
    elsif numCh = 24
        layoutToken$ = "22.2"
    else
        exitScript: "Cannot auto-detect layout for " + string$(numCh) +
            ... " channels. Please select a layout manually."
    endif
elsif layout_preset = 2
    layoutToken$ = "2.0"
elsif layout_preset = 3
    layoutToken$ = "4.0"
elsif layout_preset = 4
    layoutToken$ = "5.0"
elsif layout_preset = 5
    layoutToken$ = "5.1"
elsif layout_preset = 6
    layoutToken$ = "7.0"
elsif layout_preset = 7
    layoutToken$ = "7.1"
elsif layout_preset = 8
    layoutToken$ = "7.1.2"
elsif layout_preset = 9
    layoutToken$ = "7.1.4"
else
    layoutToken$ = "22.2"
endif

# ---- GUARDS ----
if not fileReadable(helper_py$)
    exitScript: "Python helper not found: " + helper_py$
endif

# ---- NORMALISE FOLDER PATHS ----
if right$(tools_folder$, 1) <> "/" and right$(tools_folder$, 1) <> "\"
    tools_folder$ = tools_folder$ + "/"
endif
if right$(working_folder$, 1) <> "/" and right$(working_folder$, 1) <> "\"
    working_folder$ = working_folder$ + "/"
endif

# ---- TEMP FILES ----
inputWav$  = working_folder$ + "mcbin_input.wav"
outputWav$ = working_folder$ + "mcbin_output.wav"
logTxt$    = working_folder$ + "mcbin_log.txt"

# ---- INFO ----
writeInfoLine:  "=== Multichannel to Binaural v1.2 ==="
appendInfoLine: "Source:   ", sourceName$, "  (", numCh, " ch  /  ",
    ... fixed$(duration, 2), " s  @  ", sr, " Hz)"
appendInfoLine: "Layout:   ", layoutToken$
appendInfoLine: "HRTF:     ", actualSOFA$, "  ITD=", fixed$(itd_percent, 1), "%"
appendInfoLine: "Room:     ", roomName$
appendInfoLine: "Pre-gain: ", fixed$(pre_gain_db, 1), " dB"
appendInfoLine: "Tools:    ", tools_folder$
appendInfoLine: ""

# ---- PREP INPUT ----
deleteFile: inputWav$
deleteFile: outputWav$
deleteFile: logTxt$

selectObject: original
if pre_gain_db <> 0
    Copy: "__mcbin_work"
    workID = selected("Sound")
    Multiply: 10 ^ (pre_gain_db / 20)
    Save as WAV file: inputWav$
    removeObject: workID
else
    Save as WAV file: inputWav$
endif

# ---- DETERMINE PYTHON COMMAND ----
if macintosh or unix
    pythonCmd$ = "python3"
else
    pythonCmd$ = "python"
endif

# ---- RUN ----
appendInfoLine: "Rendering binaural..."

runSubprocess: pythonCmd$, helper_py$,
    ... inputWav$, outputWav$, logTxt$,
    ... tools_folder$, layoutToken$,
    ... actualSOFA$, string$(itd_percent), roomName$

# ---- IMPORT RESULT ----
if fileReadable(outputWav$)
    Read from file: outputWav$
    result = selected("Sound")
    Rename: sourceName$ + "_binaural"

    selectObject: result
    actual_dur = Get total duration

    appendInfoLine: "Done. Output: ", sourceName$ + "_binaural"

    # Delete temp files only on success; log survives on failure.
    deleteFile: inputWav$
    deleteFile: outputWav$
    deleteFile: logTxt$

    # ---- VISUALIZATION ----
    if draw_visualization
        Erase all
        Select outer viewport: 0, 8, 0, 8

        # Title
        Select outer viewport: 0, 8, 0, 0.65
        Axes: 0, 1, 0, 1
        Font size: 12
        Colour: "Black"
        Text: 0.5, "centre", 0.65, "half", "##Multichannel to Binaural##"
        Font size: 7
        Colour: "{0.35, 0.35, 0.52}"
        Text: 0.5, "centre", -0.25, "half",
            ... sourceName$
            ... + "  |  " + string$(numCh) + " ch -> binaural"
            ... + "  |  layout: " + layoutToken$
            ... + "  |  HRTF: " + actualSOFA$

        # Input waveform (first 2 channels)
        Select outer viewport: 0, 8, 0.70, 2.00
        Select inner viewport: 0.55, 7.65, 0.78, 1.92
        selectObject: original
        if numCh > 1
            Extract one channel: 1
            vizIn = selected("Sound")
        else
            Copy: "vizIn"
            vizIn = selected("Sound")
        endif
        Colour: "{0.55, 0.55, 0.55}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        if numCh > 1
            selectObject: original
            Extract one channel: 2
            vizIn2 = selected("Sound")
            Colour: "{0.75, 0.75, 0.75}"
            Draw: 0, 0, 0, 0, "no", "Curve"
            removeObject: vizIn2
        endif
        removeObject: vizIn
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Input"
        Text top: "no", "Input (" + string$(numCh) + " ch, showing ch 1" +
            ... if numCh > 1 then " + 2" else "" fi + ")"

        # Output binaural waveform
        Select outer viewport: 0, 8, 2.05, 3.50
        Select inner viewport: 0.55, 7.65, 2.15, 3.42
        selectObject: result
        Extract one channel: 1
        vizOutL = selected("Sound")
        Colour: "{0.25, 0.50, 0.82}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        removeObject: vizOutL

        selectObject: result
        Extract one channel: 2
        vizOutR = selected("Sound")
        Colour: "{0.82, 0.45, 0.25}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        removeObject: vizOutR

        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Output"
        Text bottom: "yes", "Time (s)"
        Text top: "no", "Binaural output  (blue = L ear,  orange = R ear)"

        # Info panel
        Select outer viewport: 0, 8, 3.60, 4.70
        Select inner viewport: 0.55, 7.65, 3.68, 4.62
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1

        Font size: 7
        Colour: "Black"
        Text: 0.02, "left", 0.82, "half", "##Processing Parameters##"

        Font size: 6
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.05, "left", 0.60, "half",
            ... "Input: " + string$(numCh) + " channels  |  Layout: " + layoutToken$
        Text: 0.05, "left", 0.38, "half",
            ... "HRTF: " + actualSOFA$ + "  |  ITD: " + fixed$(itd_percent, 0) + "%  |  Room: " + roomName$
        Text: 0.05, "left", 0.16, "half",
            ... "Pre-gain: " + fixed$(pre_gain_db, 1) + " dB  |  SR: " + string$(sr) + " Hz"

        Colour: "Black"
        Draw rectangle: 0, 1, 0, 1

        # Summary bar
        Select outer viewport: 0, 8, 4.80, 5.40
        Select inner viewport: 0.55, 7.65, 4.86, 5.34
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
        Font size: 7
        Colour: "Black"
        Text: 0.02, "left", 0.72, "half", "##" + sourceName$ + "_binaural##"
        Font size: 6
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.02, "left", 0.28, "half",
            ... string$(numCh) + " ch -> 2 ch binaural"
            ... + "  |  " + layoutToken$
            ... + "  |  " + fixed$(actual_dur, 2) + " s"
            ... + "  |  " + actualSOFA$
            ... + "  |  room: " + roomName$
        Colour: "Black"
        Draw rectangle: 0, 1, 0, 1

        Font size: 10
        Colour: "Black"
        Line width: 1
    endif

    # ---- PLAY ----
    if play_result
        selectObject: result
        asynchronous Play
    endif

    selectObject: result

else
    appendInfoLine: "ERROR: Binaural render failed."
    appendInfoLine: "Log preserved at: ", logTxt$
    if fileReadable(logTxt$)
        appendInfoLine: ""
        appendInfoLine: "=== Spat5 log ==="
        appendInfoLine: readFile$(logTxt$)
    endif
    # Do NOT delete logTxt$ on failure -- leave it for diagnostics.
    deleteFile: inputWav$
    deleteFile: outputWav$
endif
