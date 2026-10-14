# ============================================================
# Praat AudioTools Plugin
# Script:      Draw_Intensity_Envelope.praat
# Author:      Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version:     1.1 (2026)
# License:     MIT License
# Repository:  https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Draw a gain envelope (dB) and a pan envelope by hand in the Demo
#   window, pure Praat, no Python. The waveform is shown above the two
#   drawing panels on the same time axis; points are joined by a line.
#
#   Click          add a point in the Gain or Pan panel (clicking at
#                  the time of an existing point in that panel moves it)
#   U              undo the last add/move (either panel)
#   Enter          apply the envelopes, then play the result
#   Escape         cancel (nothing is created)
#
#   Outside the first and last point each curve is held constant
#   (shown as a dotted extension). Pan clicks within 4% of centre
#   snap to C.
#
# Processing:
#   Gain: Sound & IntensityTier: Multiply with scaling OFF, so the drawn
#   dB values are applied as true relative gain (0 dB = unchanged).
#   Pan (only if pan points were drawn; mono or stereo input):
#     mono input   -> converted to stereo and panned
#                     (equal power: -3 dB per channel at C;
#                      linear: -6 dB per channel at C)
#     stereo input -> balance: the far channel is attenuated, the near
#                     channel never exceeds unity
#   The pan curve is interpolated linearly at sample rate.
#   Optional peak guard rescales to 0.99 only if the result would clip.
#
# Usage:
#   Select one Sound object, run the script, click in the Demo window
#   once so it has keyboard focus.
# ============================================================

form: "Draw Intensity & Pan Envelope"
    comment: "Click Gain or Pan panel, U = undo, Enter = apply, Esc = cancel"
    positive: "Range_dB", "30"
    optionmenu: "Pan_law", 1
        option: "Equal power (-3 dB centre)"
        option: "Linear (-6 dB centre)"
    boolean: "Prevent_clipping", 1
endform

# ---- Verify selection ----
if numberOfSelected ("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound      = selected ("Sound")
soundName$ = selected$ ("Sound")
duration   = Get total duration
tStart     = Get start time
tEnd       = Get end time
nChIn      = Get number of channels
peakIn     = Get absolute extremum: 0, 0, "None"
if peakIn <= 0
    peakIn = 1
endif
nChOut = nChIn
panOK  = nChIn <= 2

# ---- Layout (Demo window units 0..100; sx/sy scale for Picture tests) ----
sx = 1
sy = 1
vpL  = 7.5 * sx
vpR  = 96.25 * sx
ttlB = 91 * sy
ttlT = 99 * sy
wavB = 72 * sy
wavT = 86 * sy
gaiB = 48 * sy
gaiT = 66 * sy
panB = 22 * sy
panT = 40 * sy
sumB = 2 * sy
sumT = 10 * sy

# ---- Palette (AudioTools standard) ----
cPanel$  = "{0.97, 0.97, 0.97}"
cSum$    = "{0.94, 0.94, 0.94}"
cSumTx$  = "{0.25, 0.25, 0.35}"
cSubTx$  = "{0.35, 0.35, 0.50}"
cGrid$   = "{0.80, 0.80, 0.80}"
cInput$  = "{0.55, 0.55, 0.60}"
cPrim$   = "{0.20, 0.48, 0.75}"
cSecond$ = "{0.85, 0.38, 0.18}"

# ---- Tick steps (1-2-5 series) ----
@niceStep: duration, 8
tStep = niceStep.result
@niceStep: 2 * range_dB, 6
dbStep = niceStep.result

# ---- Point storage ----
# Two curves share ptT[] / ptV[], kept sorted by time per curve:
#   curve 1 (gain, dB)  at indices      1 .. nP[1]
#   curve 2 (pan, -1..1) at indices 100001 .. 100000 + nP[2]
nP[1] = 0
nP[2] = 0
curveName$[1] = "gain"
curveName$[2] = "pan"
nHist = 0
moveTol = duration * 0.004
status$ = "Click in the Gain or Pan panel to add points."
appliedView = 0
result = 0

# ============================================================
# PROCEDURES
# ============================================================
procedure niceStep: .span, .target
    .raw = .span / .target
    .mag = 10 ^ floor (log10 (.raw))
    .result = 10 * .mag
    if 5 * .mag >= .raw
        .result = 5 * .mag
    endif
    if 2 * .mag >= .raw
        .result = 2 * .mag
    endif
    if .mag >= .raw
        .result = .mag
    endif
endproc

procedure valueText: .c, .v
    if .c = 1
        .s$ = fixed$ (.v, 1) + " dB"
    elsif .v = 0
        .s$ = "C"
    elsif .v < 0
        .s$ = "L " + fixed$ (-100 * .v, 0) + "%"
    else
        .s$ = "R " + fixed$ (100 * .v, 0) + "%"
    endif
endproc

procedure drawTitle
    if not panOK
        .pan$ = "pan n/a (" + string$ (nChIn) + " ch)"
    elsif pan_law = 1
        .pan$ = "pan: equal power"
    else
        .pan$ = "pan: linear"
    endif
    demo Font size: 12
    demo Select inner viewport: vpL, vpR, ttlB, ttlT
    demo Axes: 0, 1, 0, 1
    demo Colour: "Black"
    demo Text: 0.5, "centre", 0.72, "half", "##Draw Intensity & Pan Envelope##"
    demo Font size: 7
    demo Select inner viewport: vpL, vpR, ttlB, ttlT
    demo Axes: 0, 1, 0, 1
    demo Colour: cSubTx$
    demo Text: 0.5, "centre", 0.12, "half", soundName$ + "   |   "
        ... + fixed$ (duration, 3) + " s   |   "
        ... + string$ (nChIn) + " ch   |   gain ±" + string$ (range_dB) + " dB   |   " + .pan$
endproc

procedure drawWave
    demo Font size: 7
    demo Select inner viewport: vpL, vpR, wavB, wavT
    demo Axes: tStart, tEnd, -1, 1
    demo Paint rectangle: cPanel$, tStart, tEnd, -1, 1
    if appliedView = 0
        .range = peakIn
    else
        .range = max (peakIn, peakOut)
    endif

    if appliedView = 1 and nChOut = 2
        # split view: L in the upper half, R in the lower half
        .mid = (wavB + wavT) / 2
        for .ch to 2
            if .ch = 1
                .b = .mid
                .t = wavT
                .inId = iL
                .outId = oL
            else
                .b = wavB
                .t = .mid
                .inId = iR
                .outId = oR
            endif
            demo Select inner viewport: vpL, vpR, .b, .t
            demo Colour: cInput$
            selectObject: .inId
            demo Draw: 0, 0, -.range, .range, "no", "Curve"
            demo Select inner viewport: vpL, vpR, .b, .t
            demo Colour: cPrim$
            selectObject: .outId
            demo Draw: 0, 0, -.range, .range, "no", "Curve"
        endfor
        demo Select inner viewport: vpL, vpR, wavB, wavT
        demo Axes: tStart, tEnd, -1, 1
        demo Colour: cGrid$
        demo Draw line: tStart, 0, tEnd, 0
        demo Axes: 0, 1, 0, 1
        demo Colour: cSubTx$
        demo Text: 1.005, "left", 0.75, "half", "##L##"
        demo Text: 1.005, "left", 0.25, "half", "##R##"
    else
        demo Colour: cInput$
        selectObject: sound
        demo Draw: 0, 0, -.range, .range, "no", "Curve"
        if appliedView = 1
            demo Select inner viewport: vpL, vpR, wavB, wavT
            demo Colour: cPrim$
            selectObject: result
            demo Draw: 0, 0, -.range, .range, "no", "Curve"
        endif
    endif

    demo Select inner viewport: vpL, vpR, wavB, wavT
    demo Axes: tStart, tEnd, -1, 1
    demo Colour: "Black"
    demo Draw inner box
    demo Marks bottom every: 1, tStep, "no", "yes", "no"
    demo Select inner viewport: vpL, vpR, wavB, wavT
    demo Axes: 0, 1, 0, 1
    if appliedView = 0
        demo Colour: cInput$
        demo Text: 0.005, "left", 1.06, "bottom", "##Input waveform##"
    else
        demo Colour: cInput$
        demo Text: 0.005, "left", 1.06, "bottom", "##Input##"
        demo Colour: cPrim$
        demo Text: 0.08, "left", 1.06, "bottom", "##Output##"
    endif
endproc

# Draws curve .c into the current viewport/axes.
procedure drawPoints: .c
    .base = (.c - 1) * 100000
    .n = nP[.c]
    if .n > 0
        .t1 = ptT[.base + 1]
        .v1 = ptV[.base + 1]
        .tn = ptT[.base + .n]
        .vn = ptV[.base + .n]
        # held-constant extensions before the first / after the last point
        demo Colour: cPrim$
        demo Line width: 2
        demo Dotted line
        if .t1 > 0
            demo Draw line: 0, .v1, .t1, .v1
        endif
        if .tn < duration
            demo Draw line: .tn, .vn, duration, .vn
        endif
        demo Solid line
        for .i to .n - 1
            .a = .base + .i
            demo Draw line: ptT[.a], ptV[.a], ptT[.a + 1], ptV[.a + 1]
        endfor
        demo Line width: 1
        for .i to .n
            .a = .base + .i
            demo Paint circle (mm): cSecond$, ptT[.a], ptV[.a], 1.6
        endfor
    endif
endproc

procedure drawGainPanel
    demo Font size: 7
    demo Select inner viewport: vpL, vpR, gaiB, gaiT
    demo Axes: 0, duration, -range_dB, range_dB
    demo Paint rectangle: cPanel$, 0, duration, -range_dB, range_dB

    # grid: dotted dB lines, solid 0 dB reference
    demo Colour: cGrid$
    demo Dotted line
    .k1 = floor (range_dB / dbStep)
    for .k to .k1
        .g = .k * dbStep
        if .g < range_dB
            demo Draw line: 0, .g, duration, .g
            demo Draw line: 0, -.g, duration, -.g
        endif
    endfor
    demo Solid line
    demo Draw line: 0, 0, duration, 0

    @drawPoints: 1

    demo Select inner viewport: vpL, vpR, gaiB, gaiT
    demo Axes: 0, duration, -range_dB, range_dB
    demo Colour: "Black"
    demo Draw inner box
    demo Marks left every: 1, dbStep, "yes", "yes", "no"
    demo Marks bottom every: 1, tStep, "yes", "yes", "no"
    demo Text left: "yes", "Gain (dB)"
endproc

procedure drawPanPanel
    demo Font size: 7
    demo Select inner viewport: vpL, vpR, panB, panT
    demo Axes: 0, duration, -1, 1
    demo Paint rectangle: cPanel$, 0, duration, -1, 1

    if panOK
        demo Colour: cGrid$
        demo Dotted line
        demo Draw line: 0, 0.5, duration, 0.5
        demo Draw line: 0, -0.5, duration, -0.5
        demo Solid line
        demo Draw line: 0, 0, duration, 0
        @drawPoints: 2
    else
        demo Colour: cSubTx$
        demo Text: duration / 2, "centre", 0, "half",
            ... "Pan needs a mono or stereo input (" + string$ (nChIn) + " ch)"
    endif

    demo Select inner viewport: vpL, vpR, panB, panT
    demo Axes: 0, duration, -1, 1
    demo Colour: "Black"
    demo Draw inner box
    demo One mark left: 1, "no", "yes", "no", "R"
    demo One mark left: 0, "no", "yes", "no", "C"
    demo One mark left: -1, "no", "yes", "no", "L"
    demo Marks bottom every: 1, tStep, "yes", "yes", "no"
    demo Text left: "yes", "Pan"
    demo Text bottom: "yes", "Time (s)"
endproc

procedure drawSummary
    demo Font size: 7
    demo Select inner viewport: vpL, vpR, sumB, sumT
    demo Axes: 0, 1, 0, 1
    demo Paint rectangle: cSum$, 0, 1, 0, 1
    demo Colour: cSumTx$
    demo Text: 0.01, "left", 0.70, "half", "##Click## add / move point     ##U## undo     "
        ... + "##Enter## apply and play     ##Esc## cancel"
    demo Text: 0.01, "left", 0.28, "half", "##Points:## gain " + string$ (nP[1])
        ... + ", pan " + string$ (nP[2]) + "     " + status$
    demo Select inner viewport: vpL, vpR, sumB, sumT
    demo Axes: 0, 1, 0, 1
    demo Colour: "Black"
    demo Draw inner box
endproc

procedure drawAll
    demo Erase all
    @drawTitle
    @drawWave
    @drawGainPanel
    @drawPanPanel
    @drawSummary
    # Leave the frame in raw Demo units (0..100) so demoX/demoY can be
    # hit-tested against both drawing panels.
    demo Font size: 7
    demo Select inner viewport: 0, 100, 0, 100
    demo Axes: 0, 100, 0, 100
endproc

procedure addOrMove: .c, .x, .y
    .base = (.c - 1) * 100000
    .n = nP[.c]
    @valueText: .c, .y
    .val$ = valueText.s$
    # near an existing point of this curve in time? -> move it
    .hit = 0
    for .i to .n
        if .hit = 0 and abs (ptT[.base + .i] - .x) <= moveTol
            .hit = .i
        endif
    endfor
    nHist += 1
    histC[nHist] = .c
    if .hit > 0
        .k = .base + .hit
        histKind[nHist] = 2
        histT[nHist]    = ptT[.k]
        histV[nHist]    = ptV[.k]
        ptV[.k] = .y
        status$ = "Moved " + curveName$[.c] + " point at " + fixed$ (ptT[.k], 3)
            ... + " s to " + .val$ + "."
    else
        # sorted insert
        .pos = .n + 1
        for .i to .n
            if .pos = .n + 1 and ptT[.base + .i] > .x
                .pos = .i
            endif
        endfor
        for .k to .n - .pos + 1
            .j = .base + .n - .k + 1
            ptT[.j + 1] = ptT[.j]
            ptV[.j + 1] = ptV[.j]
        endfor
        ptT[.base + .pos] = .x
        ptV[.base + .pos] = .y
        nP[.c] = .n + 1
        histKind[nHist] = 1
        histT[nHist]    = .x
        histV[nHist]    = .y
        status$ = "Added " + curveName$[.c] + " " + fixed$ (.x, 3) + " s, " + .val$ + "."
    endif
endproc

procedure handleClick: .x, .y
    .c = 0
    if .x >= vpL and .x <= vpR
        .t = (.x - vpL) / (vpR - vpL) * duration
        if .y >= gaiB and .y <= gaiT
            .c = 1
            .v = -range_dB + (.y - gaiB) / (gaiT - gaiB) * 2 * range_dB
        elsif .y >= panB and .y <= panT
            if panOK
                .c = 2
                .v = -1 + (.y - panB) / (panT - panB) * 2
                if abs (.v) < 0.04
                    .v = 0
                endif
            else
                .c = -1
                status$ = "Pan needs a mono or stereo input."
            endif
        endif
    endif
    if .c = 0
        status$ = "Click inside the Gain or Pan panel."
    elsif .c > 0
        @addOrMove: .c, .t, .v
    endif
endproc

procedure undoLast
    if nHist = 0
        status$ = "Nothing to undo."
    else
        .c = histC[nHist]
        .base = (.c - 1) * 100000
        .n = nP[.c]
        .idx = 0
        for .i to .n
            if ptT[.base + .i] = histT[nHist]
                .idx = .i
            endif
        endfor
        if .idx > 0
            if histKind[nHist] = 2
                ptV[.base + .idx] = histV[nHist]
                status$ = "Undid " + curveName$[.c] + " move."
            else
                for .i from .idx to .n - 1
                    .j = .base + .i
                    ptT[.j] = ptT[.j + 1]
                    ptV[.j] = ptV[.j + 1]
                endfor
                nP[.c] = .n - 1
                status$ = "Undid " + curveName$[.c] + " add."
            endif
        endif
        nHist -= 1
    endif
endproc

# ============================================================
# INTERACTIVE DRAWING
# ============================================================
@drawAll

# >>> INPUT LOOP
action$ = ""
while action$ = ""
    demoWaitForInput ()
    if demoClicked ()
        @handleClick: demoX (), demoY ()
        @drawAll
    elsif demoKeyPressed ()
        key$ = demoKey$ ()
        if key$ = newline$ or key$ = unicode$ (13)
            if nP[1] + nP[2] = 0
                status$ = "Add at least one point before pressing Enter."
                @drawAll
            else
                action$ = "apply"
            endif
        elsif key$ = unicode$ (27)
            action$ = "cancel"
        elsif key$ = "u" or key$ = "U"
            @undoLast
            @drawAll
        endif
    endif
endwhile
# <<< INPUT LOOP

if action$ = "cancel"
    status$ = "Cancelled - nothing was created."
    @drawAll
    exitScript: "Draw Intensity Envelope cancelled."
endif

# ============================================================
# APPLY GAIN  (Sound & IntensityTier: Multiply, scaling OFF)
# ============================================================
# Drawn times are relative (0..duration); the tier lives on the Sound's
# own time domain, so shift by tStart.
if nP[1] > 0
    tier = Create IntensityTier: "drawn", tStart, tEnd
    for i to nP[1]
        Add point: tStart + ptT[i], ptV[i]
    endfor
    selectObject: sound, tier
    result = Multiply: "no"
    removeObject: tier
else
    selectObject: sound
    result = Copy: "work"
endif

# ============================================================
# APPLY PAN  (sample-rate control signal, linear interpolation)
# ============================================================
if nP[2] > 0
    if nChIn = 1
        selectObject: result
        stereo = Convert to stereo
        removeObject: result
        result = stereo
    endif

    # control signal on exactly the same sampling grid as the audio
    selectObject: result
    ctl = Extract one channel: 1
    Formula: string$ (ptV[100001])
    for i to nP[2] - 1
        a  = 100000 + i
        t1 = tStart + ptT[a]
        t2 = tStart + ptT[a + 1]
        v1 = ptV[a]
        v2 = ptV[a + 1]
        Formula (part): t1, t2, 1, 1, string$ (v1) + " + (" + string$ (v2 - v1)
            ... + ") * (x - " + string$ (t1) + ") / " + string$ (t2 - t1)
    endfor
    a = 100000 + nP[2]
    Formula (part): tStart + ptT[a], tEnd, 1, 1, string$ (ptV[a])

    p$  = "object[" + string$ (ctl) + ", 1, col]"
    th$ = "(" + p$ + " + 1) * pi / 4"
    if pan_law = 1
        if nChIn = 1
            gL$ = "cos (" + th$ + ")"
            gR$ = "sin (" + th$ + ")"
        else
            gL$ = "min (1, sqrt (2) * cos (" + th$ + "))"
            gR$ = "min (1, sqrt (2) * sin (" + th$ + "))"
        endif
    else
        if nChIn = 1
            gL$ = "(1 - " + p$ + ") / 2"
            gR$ = "(1 + " + p$ + ") / 2"
        else
            gL$ = "min (1, 1 - " + p$ + ")"
            gR$ = "min (1, 1 + " + p$ + ")"
        endif
    endif
    selectObject: result
    Formula: "self * (if row = 1 then " + gL$ + " else " + gR$ + " fi)"
    removeObject: ctl
endif

if nP[2] > 0 and nP[1] > 0
    suffix$ = "_drawnIntensityPan"
elsif nP[2] > 0
    suffix$ = "_drawnPan"
else
    suffix$ = "_drawnIntensity"
endif
selectObject: result
Rename: soundName$ + suffix$
nChOut = Get number of channels

peakRaw = Get absolute extremum: 0, 0, "None"
scaled = 0
if prevent_clipping and peakRaw > 0.99
    Scale peak: 0.99
    scaled = 1
endif
peakOut = Get absolute extremum: 0, 0, "None"
rmsOut  = Get root-mean-square: 0, 0
selectObject: sound
rmsIn   = Get root-mean-square: 0, 0

# ---- per-channel display objects for the stereo split view ----
extractedIn = 0
if nChOut = 2
    selectObject: result
    oL = Extract one channel: 1
    selectObject: result
    oR = Extract one channel: 2
    if nChIn = 2
        selectObject: sound
        iL = Extract one channel: 1
        selectObject: sound
        iR = Extract one channel: 2
        extractedIn = 1
    else
        iL = sound
        iR = sound
    endif
endif

# ---- Final view: input vs output waveform ----
appliedView = 1
if scaled
    status$ = "Applied. Peak " + fixed$ (peakRaw, 3) + " rescaled to 0.99. Playing..."
else
    status$ = "Applied. Peak " + fixed$ (peakOut, 3) + ". Playing..."
endif
@drawAll

if nChOut = 2
    removeObject: oL, oR
    if extractedIn
        removeObject: iL, iR
    endif
endif

# ---- Info ----
writeInfoLine: "=== Draw Intensity & Pan Envelope 1.1 ==="
appendInfoLine: "Input:    ", soundName$, "  (", fixed$ (duration, 3), " s, ", nChIn, " ch)"
appendInfoLine: "Gain points: ", nP[1], "   range ±", range_dB, " dB"
for i to nP[1]
    appendInfoLine: "  ", fixed$ (ptT[i], 3), " s   ", fixed$ (ptV[i], 2), " dB"
endfor
if nP[2] > 0
    if nChIn = 1
        mode$ = "mono -> stereo pan"
    else
        mode$ = "stereo balance"
    endif
    appendInfoLine: "Pan points:  ", nP[2], "   ", pan_law$, ", ", mode$
    for i to nP[2]
        @valueText: 2, ptV[100000 + i]
        appendInfoLine: "  ", fixed$ (ptT[100000 + i], 3), " s   ", valueText.s$
    endfor
else
    appendInfoLine: "Pan points:  0 (channel count unchanged)"
endif
appendInfoLine: "Peak in:  ", fixed$ (peakIn, 4), "   out: ", fixed$ (peakOut, 4)
if scaled
    appendInfoLine: "          (raw peak ", fixed$ (peakRaw, 4), " rescaled to 0.99 - absolute level not preserved)"
elsif peakRaw > 1
    appendInfoLine: "WARNING: output peak > 1 will clip on playback/save (Prevent_clipping is off)."
endif
if rmsIn > 0 and rmsOut > 0
    appendInfoLine: "RMS change: ", fixed$ (20 * log10 (rmsOut / rmsIn), 2), " dB"
endif
appendInfoLine: "Output:   ", soundName$, suffix$, "  (", nChOut, " ch)"

selectObject: result
Play
