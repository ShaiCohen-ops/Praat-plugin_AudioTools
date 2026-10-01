# ============================================================
# Praat AudioTools - Paulstretch.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.3 (2026) - Story-telling figure (library standard)
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
# Changelog v2.3 (2026) - figure only; processing unchanged:
#   The figure now explains WHAT Paulstretch does instead of only showing
#   before/after plots. Five steps, top to bottom:
#     1 Source          waveform in coloured segments, with one analysis
#                       window drawn to scale on top
#     2 Time map        both sounds on ONE absolute time axis; each source
#                       segment fans out to the stretched segment it
#                       becomes (the stretch made visible). Uses the exact
#                       frame mapping of paulstretch.py: the window that
#                       starts at source time p is laid down at p*stretch,
#                       so t_out = (t_src - w/2)*stretch + w/2 - output
#                       material sits about half a window (source time)
#                       earlier than a plain t*stretch would suggest.
#     3 New realization the output waveform in the same segment colours
#     4 What is kept    spectrograms side by side (each on its own time
#                       axis), and the long-term spectrum of both overlaid
#                       with the measured deviation in dB
#     5 What is lost    intensity envelopes on SOURCE time, the output
#                       placed where each frame was taken from. Reported:
#                       how well the output follows the source envelope
#                       smoothed over one window (r), and how much source
#                       envelope detail is faster than the window (dB rms)
#                       - the part replaced by random-phase texture
#   Library standard: 8 in canvas, inner viewports 0.6-7.7, ##bold## title
#   at font 12 with a font 7 subtitle, labels at font 6-7, panel ground
#   {0.97, 0.97, 0.97}, Draw inner box after every panel, grey
#   {0.94, 0.94, 0.94} summary strip; ends on the full canvas so PNG export
#   is not cropped. Spectrogram time step scales with duration so very long
#   (50x) outputs stay quick to draw.
#   Also: Praat 7 asks for full trust once (guarded, inert on Praat 6).
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
form Paulstretch v2.3
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
    integer Random_seed 0
    comment 0 = new random realization; non-zero = reproducible
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
writeInfoLine:  "=== Paulstretch v2.3 ==="
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

# Praat 7 gates system commands and file writes behind full trust.
if praatVersion >= 7000
    trustOk = askForTrust ()
    if trustOk = 0
        exitScript: "Paulstretch runs Python and writes temporary WAV files; Praat 7 needs FULL TRUST for that."
    endif
endif

# ===========================================================================
# Stage 1 — Detect Python Dependencies
# ===========================================================================
appendInfoLine: "[1/4] Detecting Python dependencies..."

probeCmd$ = pythonCmd$ + " -c ""import numpy, soundfile; open('""" + probeMarkerJ$ + """', 'w').write('ok')"""
runSystem_nocheck: probeCmd$

if not fileReadable(probeMarker$)
    @cleanUpTempFiles
    exitScript: "Python not found or dependencies missing." + newline$ + "Please install: pip install numpy soundfile"
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
    ... + " " + fixed$(stretch, 6)
    ... + " " + fixed$(window_seconds, 6)

if random_seed <> 0
    pythonCall$ = pythonCall$ + " " + string$(random_seed)
endif

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
actualStretch = durOut / dur
durationError = abs(durOut - expectedDur)

appendInfoLine: "Actual output: ", fixed$(durOut, 6), " s"
appendInfoLine: "Measured ratio: ", fixed$(actualStretch, 6), "x"
if durationError > max(0.002, 2 / sr)
    appendInfoLine: "WARNING: duration differs from target by ", fixed$(durationError, 6), " s"
endif

###############################################################################
# VISUALIZATION
###############################################################################

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    @drawStory
else
    appendInfoLine: "[4/4] Visualization skipped."
endif

# ---- CLEANUP AND SUMMARY ----
@cleanUpTempFiles

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", soundName$, "_stretched"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Duration: ", fixed$(dur, 2), " s → ", fixed$(durOut, 6), " s | requested ", fixed$(stretch, 2), "x | measured ", fixed$(actualStretch, 6), "x"
appendInfoLine: "RMS original:  ", fixed$(rms_orig, 6)
appendInfoLine: "RMS stretched: ", fixed$(rms_out, 6)

selectObject: resultSound

if play_result
    Play
endif
# ===========================================================================
# STORY FIGURE (v2.3)
# Drawing-frame rules used throughout: Font size BEFORE Select inner
# viewport; re-select the inner viewport before curves and before Draw inner
# box (Text and Draw inner box leave the frame on the outer viewport).
# ===========================================================================
procedure sanitize: .s$
    .s$ = replace$(.s$, "\", "\bs", 0)
    .s$ = replace$(.s$, "_", "\_ ", 0)
    .s$ = replace$(.s$, "%", "\% ", 0)
    .s$ = replace$(.s$, "#", "\# ", 0)
    .s$ = replace$(.s$, "^", "\^ ", 0)
    san$ = .s$
endproc

procedure niceStep: .span, .nTicks
    .raw = .span / .nTicks
    .p = 10 ^ floor(log10(max(.raw, 1e-9)))
    .m = .raw / .p
    if .m < 1.5
        niceStep = .p
    elsif .m < 3.5
        niceStep = 2 * .p
    elsif .m < 7.5
        niceStep = 5 * .p
    else
        niceStep = 10 * .p
    endif
endproc

procedure segColour: .k
    # six light tints, repeating; same tint = same stretch of source material
    .j = ((.k - 1) mod 6) + 1
    if .j = 1
        segCol$ = "{0.80, 0.86, 0.97}"
    elsif .j = 2
        segCol$ = "{0.97, 0.86, 0.75}"
    elsif .j = 3
        segCol$ = "{0.82, 0.93, 0.82}"
    elsif .j = 4
        segCol$ = "{0.95, 0.82, 0.88}"
    elsif .j = 5
        segCol$ = "{0.90, 0.88, 0.75}"
    else
        segCol$ = "{0.84, 0.82, 0.95}"
    endif
endproc

procedure drawWave: .snd, .t1, .y1, .y2, .range, .col$, .nSeg, .mapped
    # waveform on its own time axis 0.. .t1, over tinted segments; for the
    # output (.mapped = 1) the segment edges follow the exact frame mapping
    Font size: 7
    Select inner viewport: 0.6, 7.7, .y1, .y2
    Axes: 0, .t1, -.range, .range
    for .k to .nSeg
        @segColour: .k
        .ea = (.k - 1) * .t1 / .nSeg
        .eb = .k * .t1 / .nSeg
        if .mapped
            @outTime: (.k - 1) * dur / .nSeg
            .ea = if .k = 1 then 0 else outTime fi
            @outTime: .k * dur / .nSeg
            .eb = if .k = .nSeg then .t1 else outTime fi
        endif
        Paint rectangle: segCol$, .ea, .eb, -.range, .range
    endfor
    selectObject: .snd
    Colour: .col$
    Draw: 0, .t1, -.range, .range, "no", "Curve"
endproc

procedure outTime: .a
    # paulstretch.py lays the window that STARTS at source time p down at
    # output time p*stretch, so window centres map as
    #   t_out = (t_src - w/2) * stretch + w/2
    outTime = min(durOut, max(0, (.a - window_seconds / 2) * stretch + window_seconds / 2))
endproc

procedure srcTime: .t
    srcTime = (.t - window_seconds / 2) / stretch + window_seconds / 2
endproc

procedure drawStory
    .nSeg = 6
    .colSrc$ = "{0.30, 0.33, 0.45}"
    .colOut$ = "{0.15, 0.50, 0.45}"
    .canvasH = 8.80

    # mono analysis copies (the figure describes the sum of the channels)
    selectObject: sound
    if nChannels > 1
        .src = Convert to mono
    else
        .src = Copy: "storySrc"
    endif
    selectObject: resultSound
    if nChannels > 1
        .out = Convert to mono
    else
        .out = Copy: "storyOut"
    endif
    selectObject: .src
    .pkS = Get absolute extremum: 0, 0, "None"
    selectObject: .out
    .pkO = Get absolute extremum: 0, 0, "None"
    .rangeS = max(.pkS, 1e-6)
    .rangeO = max(.pkO, 1e-6)

    @sanitize: soundName$
    .name$ = san$

    Erase all

    # === TITLE ==========================================================
    Font size: 12
    Select inner viewport: 0.6, 7.7, 0.02, 0.36
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Paulstretch - " + fixed$(stretch, 1) + "x time stretch##"
    Font size: 7
    Select inner viewport: 0.6, 7.7, 0.36, 0.56
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.5, "half", .name$ + "  |  every " + fixed$(window_seconds, 3)
        ... + " s window keeps its magnitude spectrum, gets random phases, and is laid down "
        ... + fixed$(stretch, 1) + "x further apart"

    # === 1 SOURCE =======================================================
    @drawWave: .src, dur, 0.90, 1.55, .rangeS, .colSrc$, .nSeg, 0
    # one analysis window, to scale, centred at 25 % of the source
    .wc = 0.25 * dur
    .w2 = window_seconds / 2
    Select inner viewport: 0.6, 7.7, 0.90, 1.55
    Axes: 0, dur, -.rangeS, .rangeS
    Colour: "{0.85, 0.30, 0.10}"
    Line width: 2
    .np = 80
    for .i to .np
        .xa = .wc - .w2 + (.i - 1) / .np * window_seconds
        .xb = .wc - .w2 + .i / .np * window_seconds
        .ha = 0.5 - 0.5 * cos(2 * pi * (.i - 1) / .np)
        .hb = 0.5 - 0.5 * cos(2 * pi * .i / .np)
        if .xa >= 0 and .xb <= dur
            Draw line: .xa, 0.95 * .rangeS * .ha, .xb, 0.95 * .rangeS * .hb
        endif
    endfor
    Line width: 1
    Colour: "Black"
    Text top: "no", "##1  Source##  " + fixed$(dur, 2) + " s in " + string$(.nSeg)
        ... + " coloured segments;  orange = one analysis window (" + fixed$(window_seconds, 3) + " s) to scale"
    Select inner viewport: 0.6, 7.7, 0.90, 1.55
    Axes: 0, dur, -.rangeS, .rangeS
    Draw inner box
    @niceStep: dur, 6
    Marks bottom every: 1, niceStep, "yes", "yes", "no"

    # === 2 TIME MAP =====================================================
    # both sounds on one absolute axis: source bar on top, output below,
    # each source segment fanned out to the segment it becomes
    Font size: 7
    Select inner viewport: 0.6, 7.7, 2.05, 2.75
    Axes: 0, durOut, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, durOut, 0, 1
    for .k to .nSeg
        @segColour: .k
        .sa = (.k - 1) * dur / .nSeg
        .sb = .k * dur / .nSeg
        @outTime: .sa
        .oa = outTime
        @outTime: .sb
        .ob = outTime
        if .k = 1
            .oa = 0
        endif
        if .k = .nSeg
            .ob = durOut
        endif
        Paint rectangle: segCol$, .sa, .sb, 0.80, 0.97
        Paint rectangle: segCol$, .oa, .ob, 0.03, 0.20
        # fill the fan with closely spaced lines (no polygon fill in Praat)
        Colour: segCol$
        Line width: 1
        .nf = 60
        for .f from 0 to .nf
            .u = .f / .nf
            Draw line: .sa + .u * (.sb - .sa), 0.80, .oa + .u * (.ob - .oa), 0.20
        endfor
        Colour: "{0.55, 0.55, 0.60}"
        Draw line: .sa, 0.80, .oa, 0.20
    endfor
    Colour: "{0.55, 0.55, 0.60}"
    Draw line: dur, 0.80, durOut, 0.20
    Colour: "Black"
    Text: dur + 0.01 * durOut, "left", 0.885, "half", "source  " + fixed$(dur, 2) + " s"
    Text: 0.99 * durOut, "right", 0.115, "half", "stretched  " + fixed$(durOut, 2) + " s  (" + fixed$(actualStretch, 3) + "x measured)"
    Select inner viewport: 0.6, 7.7, 2.05, 2.75
    Axes: 0, durOut, 0, 1
    Colour: "Black"
    Text top: "no", "##2  Time map##  both on one time axis: each source segment becomes a segment "
        ... + fixed$(stretch, 1) + "x longer (window centres mapped exactly)"
    Select inner viewport: 0.6, 7.7, 2.05, 2.75
    Axes: 0, durOut, 0, 1
    Draw inner box
    @niceStep: durOut, 8
    Marks bottom every: 1, niceStep, "yes", "yes", "no"

    # === 3 NEW REALIZATION ==============================================
    @drawWave: .out, durOut, 3.20, 3.85, .rangeO, .colOut$, .nSeg, 1
    Colour: "Black"
    Text top: "no", "##3  New realization##  " + fixed$(durOut, 2) + " s, same segment colours (own time axis)"
    Select inner viewport: 0.6, 7.7, 3.20, 3.85
    Axes: 0, durOut, -.rangeO, .rangeO
    Draw inner box
    @niceStep: durOut, 8
    Marks bottom every: 1, niceStep, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"

    # === 4 WHAT IS KEPT: spectra =========================================
    .fMax = min(5000, sr / 2)
    for .side to 2
        if .side = 1
            selectObject: .src
            .tEnd = dur
            .x1 = 0.6
            .x2 = 3.95
            .cap$ = "##Source##  spectrogram"
        else
            selectObject: .out
            .tEnd = durOut
            .x1 = 4.35
            .x2 = 7.7
            .cap$ = "##Stretched##  spectrogram"
        endif
        .ts = max(0.002, .tEnd / 1500)
        .spg = To Spectrogram: 0.005, .fMax, .ts, 20, "Gaussian"
        Font size: 7
        Select inner viewport: .x1, .x2, 4.62, 5.55
        Axes: 0, .tEnd, 0, .fMax
        Paint: 0, 0, 0, .fMax, 100, "yes", 50, 6, 0, "no"
        removeObject: .spg
        Colour: "Black"
        Text top: "no", .cap$ + " (0-" + fixed$(.fMax / 1000, 0) + " kHz, own time axis)"
        Select inner viewport: .x1, .x2, 4.62, 5.55
        Axes: 0, .tEnd, 0, .fMax
        Draw inner box
        @niceStep: .tEnd, 4
        Marks bottom every: 1, niceStep, "yes", "yes", "no"
        Marks left every: 1, 1000, "yes", "yes", "no"
        if .side = 1
            Text left: "yes", "Hz"
        endif
    endfor
    Font size: 7
    Select inner viewport: 0.6, 7.7, 4.30, 4.42
    Axes: 0, 1, 0, 1
    Colour: "{0.15, 0.15, 0.15}"
    Text: 0, "left", 0.5, "half", "##4  What is kept##  - the magnitude spectrum of every window survives; only its timing is spread out"

    # === 4b long-term spectrum + 5 what is lost (envelopes) =============
    selectObject: .src
    .ltS = To Ltas: 50
    selectObject: .out
    .ltO = To Ltas: 50
    selectObject: .ltS
    .nb = Get number of bins
    # dB per bin, level-aligned (output is peak-normalized), bins above 50 Hz
    .vMax = -1e9
    .vMin = 1e9
    .sumD = 0
    .sumD2 = 0
    .cnt = 0
    for .b to .nb
        selectObject: .ltS
        .f = Get frequency from bin number: .b
        .a = Get value in bin: .b
        selectObject: .ltO
        .c = Get value in bin: .b
        ltF[.b] = .f
        ltA[.b] = .a
        ltC[.b] = .c
        if .f >= 50 and .a <> undefined and .c <> undefined
            .vMax = max(.vMax, .a, .c)
            .vMin = min(.vMin, .a, .c)
        endif
    endfor
    # offset that aligns the two curves, then deviation over the top 40 dB
    for .b to .nb
        if ltF[.b] >= 50 and ltA[.b] <> undefined and ltC[.b] <> undefined and ltA[.b] > .vMax - 40
            .sumD = .sumD + (ltC[.b] - ltA[.b])
            .cnt = .cnt + 1
        endif
    endfor
    .off = 0
    if .cnt > 0
        .off = .sumD / .cnt
    endif
    .dev2 = 0
    for .b to .nb
        if ltF[.b] >= 50 and ltA[.b] <> undefined and ltC[.b] <> undefined and ltA[.b] > .vMax - 40
            .dev2 = .dev2 + (ltC[.b] - .off - ltA[.b]) ^ 2
        endif
    endfor
    ltDev = 0
    if .cnt > 0
        ltDev = sqrt(.dev2 / .cnt)
    endif
    .yHi = .vMax + 3
    .yLo = max(.vMin, .vMax - 60) - 3
    .fLo = 50
    .fHi = ltF[.nb]
    Font size: 7
    Select inner viewport: 0.6, 3.95, 6.12, 7.07
    Axes: log10(.fLo), log10(.fHi), .yLo, .yHi
    Paint rectangle: "{0.97, 0.97, 0.97}", log10(.fLo), log10(.fHi), .yLo, .yHi
    Colour: "Black"
    Text top: "no", "##Long-term spectrum##  grey = source, green = stretched (level-aligned)"
    for .curve to 2
        Select inner viewport: 0.6, 3.95, 6.12, 7.07
        Axes: log10(.fLo), log10(.fHi), .yLo, .yHi
        if .curve = 1
            Colour: "{0.60, 0.60, 0.65}"
            Line width: 3
        else
            Colour: .colOut$
            Line width: 1
        endif
        for .b from 2 to .nb
            if ltF[.b - 1] >= .fLo and ltA[.b] <> undefined and ltA[.b - 1] <> undefined and ltC[.b] <> undefined and ltC[.b - 1] <> undefined
                if .curve = 1
                    .va = ltA[.b - 1]
                    .vb = ltA[.b]
                else
                    .va = ltC[.b - 1] - .off
                    .vb = ltC[.b] - .off
                endif
                Draw line: log10(ltF[.b - 1]), min(.yHi, max(.yLo, .va)), log10(ltF[.b]), min(.yHi, max(.yLo, .vb))
            endif
        endfor
    endfor
    Line width: 1
    Select inner viewport: 0.6, 3.95, 6.12, 7.07
    Axes: log10(.fLo), log10(.fHi), .yLo, .yHi
    Colour: "Black"
    Draw inner box
    for .e from 1 to 5
        for .m to 3
            .fm = (if .m = 1 then 1 else if .m = 2 then 2 else 5 fi fi) * 10 ^ .e
            if .fm >= .fLo and .fm <= .fHi
                .lab$ = if .fm >= 1000 then fixed$(.fm / 1000, 0) + "k" else fixed$(.fm, 0) fi
                One mark bottom: log10(.fm), "no", "yes", "no", .lab$
            endif
        endfor
    endfor
    @niceStep: .yHi - .yLo, 4
    Marks left every: 1, niceStep, "yes", "yes", "no"
    Text left: "yes", "dB"
    Text bottom: "yes", "Frequency (Hz)"
    removeObject: .ltS, .ltO

    # envelopes on relative time 0..1 (panel 5)
    selectObject: .src
    .inS = To Intensity: 100, 0, "yes"
    .nfS = Get number of frames
    selectObject: .out
    .inO = To Intensity: 100, 0, "yes"
    .nfO = Get number of frames
    # Envelopes on a COMMON relative grid: 400 bins, mean level (energy)
    # per bin, so both sounds are compared at equal relative resolution.
    # source bins on source time; output values taken from the output
    # interval those bins were laid down at (exact frame mapping)
    selectObject: .inS
    for .q from 1 to 400
        envS[.q] = Get mean: (.q - 1) / 400 * dur, .q / 400 * dur, "energy"
    endfor
    selectObject: .inO
    for .q from 1 to 400
        @outTime: (.q - 1) / 400 * dur
        .oa = outTime
        @outTime: .q / 400 * dur
        .ob = outTime
        if .ob - .oa > 1e-4
            envO[.q] = Get mean: .oa, .ob, "energy"
        else
            envO[.q] = undefined
        endif
    endfor
    # Source envelope smoothed over ONE WINDOW (in source time): the slow
    # shape Paulstretch can carry. Its residual is the detail it cannot.
    .wb = max(1, round(window_seconds / dur * 400))
    .h = floor(.wb / 2)
    for .q from 1 to 400
        .acc = 0
        .cnt = 0
        .acc2 = 0
        .cnt2 = 0
        for .r from max(1, .q - .h) to min(400, .q + .h)
            if envS[.r] <> undefined
                .acc = .acc + envS[.r]
                .cnt = .cnt + 1
            endif
            if envO[.r] <> undefined
                .acc2 = .acc2 + envO[.r]
                .cnt2 = .cnt2 + 1
            endif
        endfor
        envSm[.q] = if .cnt > 0 then .acc / .cnt else undefined fi
        envOm[.q] = if .cnt2 > 0 then .acc2 / .cnt2 else undefined fi
    endfor
    .d2 = 0
    .nd = 0
    .sx = 0
    .sy = 0
    .sxx = 0
    .syy = 0
    .sxy = 0
    .nc = 0
    for .q from 1 to 400
        if envS[.q] <> undefined and envSm[.q] <> undefined
            .d2 = .d2 + (envS[.q] - envSm[.q]) ^ 2
            .nd = .nd + 1
        endif
        if envOm[.q] <> undefined and envSm[.q] <> undefined
            .sx = .sx + envSm[.q]
            .sy = .sy + envOm[.q]
            .sxx = .sxx + envSm[.q] ^ 2
            .syy = .syy + envOm[.q] ^ 2
            .sxy = .sxy + envSm[.q] * envOm[.q]
            .nc = .nc + 1
        endif
    endfor
    envDetail = if .nd > 0 then sqrt(.d2 / .nd) else 0 fi
    envFollow = undefined
    if .nc > 2
        .vx = .sxx - .sx ^ 2 / .nc
        .vy = .syy - .sy ^ 2 / .nc
        if .vx > 0 and .vy > 0
            envFollow = (.sxy - .sx * .sy / .nc) / sqrt(.vx * .vy)
        endif
    endif
    selectObject: .inS
    .iMax = Get maximum: 0, 0, "Parabolic"
    selectObject: .inO
    .iMaxO = Get maximum: 0, 0, "Parabolic"
    .iMax = max(.iMax, .iMaxO)
    .iLo = .iMax - 50
    .iHi = .iMax + 3
    Font size: 7
    Select inner viewport: 4.35, 7.7, 6.12, 7.07
    Axes: 0, dur, .iLo, .iHi
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, dur, .iLo, .iHi
    Colour: "Black"
    Text top: "no", "##5  What is lost##  envelope detail shorter than the window (grey = source, green = stretched)"
    for .curve to 2
        if .curve = 1
            .obj = .inS
            .nfr = .nfS
            .tEnd = dur
            Colour: "{0.50, 0.50, 0.58}"
            Line width: 1.5
        else
            .obj = .inO
            .nfr = .nfO
            .tEnd = durOut
            Colour: .colOut$
            Line width: 2
        endif
        Select inner viewport: 4.35, 7.7, 6.12, 7.07
        Axes: 0, dur, .iLo, .iHi
        selectObject: .obj
        # decimate long envelopes to <= 1500 drawn points
        .step = max(1, round(.nfr / 1500))
        .pt = undefined
        .pv = undefined
        .fr = 1
        while .fr <= .nfr
            .tt = Get time from frame number: .fr
            .vv = Get value in frame: .fr
            if .vv <> undefined
                .vv = min(.iHi, max(.iLo, .vv))
                # x = source time this frame came from
                if .curve = 1
                    .xx = .tt
                else
                    @srcTime: .tt
                    .xx = srcTime
                endif
                if .pt <> undefined and .xx >= 0 and .xx <= dur and .pt >= 0 and .pt <= dur
                    Draw line: .pt, .pv, .xx, .vv
                endif
                .pt = .xx
                .pv = .vv
            endif
            .fr = .fr + .step
        endwhile
    endfor
    Line width: 1
    Select inner viewport: 4.35, 7.7, 6.12, 7.07
    Axes: 0, dur, .iLo, .iHi
    Colour: "Black"
    Draw inner box
    @niceStep: dur, 4
    Marks bottom every: 1, niceStep, "yes", "yes", "no"
    @niceStep: .iHi - .iLo, 4
    Marks left every: 1, niceStep, "yes", "yes", "no"
    Text left: "yes", "dB"
    Text bottom: "yes", "Source time (s) - stretched envelope placed where it was taken from"
    removeObject: .inS, .inO

    # === SUMMARY STRIP ==================================================
    Font size: 6
    Select inner viewport: 0.6, 7.7, 7.72, 8.70
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "{0.25, 0.25, 0.35}"
    if random_seed = 0
        .seed$ = "random (not reproducible)"
    else
        .seed$ = string$(random_seed)
    endif
    Text: 0.01, "left", 0.80, "half", "##Process##  preset " + presetName$ + "   stretch " + fixed$(stretch, 2)
        ... + "x requested, " + fixed$(actualStretch, 4) + "x measured   window " + fixed$(window_seconds, 3)
        ... + " s (Hann, 4x overlap)   seed " + .seed$
    Text: 0.01, "left", 0.55, "half", "##Spectrum##  long-term spectrum within "
        ... + fixed$(ltDev, 1) + " dB of the source (rms over the top 40 dB, level-aligned)"
    if envFollow = undefined
        .follow$ = "n/a"
    else
        .follow$ = fixed$(envFollow, 2)
    endif
    Text: 0.01, "left", 0.30, "half", "##Envelope##  slow shape (both smoothed over one window) follows the source with r = "
        ... + .follow$ + ";  source detail faster than the window: " + fixed$(envDetail, 1)
        ... + " dB rms - replaced by random-phase texture"
    Text: 0.01, "left", 0.07, "half", "##Signal##  " + fixed$(dur, 2) + " s -> " + fixed$(durOut, 2)
        ... + " s   SR " + string$(sr) + " Hz   channels " + string$(nChannels)
        ... + "   RMS " + fixed$(rms_orig, 4) + " -> " + fixed$(rms_out, 4)
    Select inner viewport: 0.6, 7.7, 7.72, 8.70
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    removeObject: .src, .out
    Select outer viewport: 0, 8, 0, .canvasH
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc
