# ============================================================
# Praat AudioTools Plugin
# Script:      Draw_Intensity_Envelope.praat
# Author:      Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version:     1.0 (2026)
# License:     MIT License
# Repository:  https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Draw a gain envelope (dB) by hand in the Demo window, pure Praat,
#   no Python. The waveform is shown above the drawing panel on the
#   same time axis; the points are joined by a line as you draw.
#
#   Click          add a point (clicking at the time of an existing
#                  point moves that point instead of adding a new one)
#   U              undo the last add/move
#   Enter          apply the envelope, then play the result
#   Escape         cancel (nothing is created)
#
#   Outside the first and last point the gain is held constant
#   (IntensityTier behaviour) - shown as a dotted extension.
#
# Processing:
#   Sound & IntensityTier: Multiply with scaling OFF, so the drawn dB
#   values are applied as true relative gain (0 dB = unchanged).
#   Optional peak guard rescales to 0.99 only if the result would clip.
#
# Usage:
#   Select one Sound object, run the script, click in the Demo window
#   once so it has keyboard focus.
# ============================================================

form: "Draw Intensity Envelope"
    comment: "Click to add points, U = undo, Enter = apply and play, Esc = cancel"
    positive: "Range_dB", "30"
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

# ---- Layout (Demo window units 0..100; sx/sy scale for Picture tests) ----
sx = 1
sy = 1
vpL = 7.5 * sx
vpR = 96.25 * sx
ttlB = 91 * sy
ttlT = 99 * sy
wavB = 66 * sy
wavT = 86 * sy
crvB = 18 * sy
crvT = 60 * sy
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

# ---- Point storage (kept sorted by time) ----
nPts  = 0
nHist = 0
moveTol = duration * 0.004
status$ = "Click in the lower panel to add points."
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

procedure drawTitle
    demo Font size: 12
    demo Select inner viewport: vpL, vpR, ttlB, ttlT
    demo Axes: 0, 1, 0, 1
    demo Colour: "Black"
    demo Text: 0.5, "centre", 0.72, "half", "##Draw Intensity Envelope##"
    demo Font size: 7
    demo Select inner viewport: vpL, vpR, ttlB, ttlT
    demo Axes: 0, 1, 0, 1
    demo Colour: cSubTx$
    demo Text: 0.5, "centre", 0.12, "half", soundName$ + "   |   "
        ... + fixed$ (duration, 3) + " s   |   "
        ... + string$ (nChIn) + " ch   |   range ±" + string$ (range_dB) + " dB"
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
    demo Colour: cInput$
    selectObject: sound
    demo Draw: 0, 0, -.range, .range, "no", "Curve"
    if appliedView = 1
        demo Select inner viewport: vpL, vpR, wavB, wavT
        demo Colour: cPrim$
        selectObject: result
        demo Draw: 0, 0, -.range, .range, "no", "Curve"
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

procedure drawCurve
    demo Font size: 7
    demo Select inner viewport: vpL, vpR, crvB, crvT
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

    if nPts > 0
        # held-constant extensions before the first / after the last point
        demo Colour: cPrim$
        demo Line width: 2
        demo Dotted line
        if ptT[1] > 0
            demo Draw line: 0, ptV[1], ptT[1], ptV[1]
        endif
        if ptT[nPts] < duration
            demo Draw line: ptT[nPts], ptV[nPts], duration, ptV[nPts]
        endif
        demo Solid line
        # the drawn envelope, in time order
        for .i to nPts - 1
            .j = .i + 1
            demo Draw line: ptT[.i], ptV[.i], ptT[.j], ptV[.j]
        endfor
        demo Line width: 1
        for .i to nPts
            demo Paint circle (mm): cSecond$, ptT[.i], ptV[.i], 1.6
        endfor
    endif

    demo Select inner viewport: vpL, vpR, crvB, crvT
    demo Axes: 0, duration, -range_dB, range_dB
    demo Colour: "Black"
    demo Draw inner box
    demo Marks left every: 1, dbStep, "yes", "yes", "no"
    demo Marks bottom every: 1, tStep, "yes", "yes", "no"
    demo Text left: "yes", "Gain (dB)"
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
    demo Text: 0.01, "left", 0.28, "half", "##Points:## " + string$ (nPts) + "     " + status$
    demo Select inner viewport: vpL, vpR, sumB, sumT
    demo Axes: 0, 1, 0, 1
    demo Colour: "Black"
    demo Draw inner box
endproc

procedure drawAll
    demo Erase all
    @drawTitle
    @drawWave
    @drawCurve
    @drawSummary
    # Leave the drawing frame on the curve panel so demoX/demoY
    # (and click hit-testing) use its world coordinates.
    demo Font size: 7
    demo Select inner viewport: vpL, vpR, crvB, crvT
    demo Axes: 0, duration, -range_dB, range_dB
endproc

procedure handleClick: .x, .y
    if .x >= 0 and .x <= duration and .y >= -range_dB and .y <= range_dB
        # near an existing point in time? -> move it
        .hit = 0
        for .i to nPts
            if .hit = 0 and abs (ptT[.i] - .x) <= moveTol
                .hit = .i
            endif
        endfor
        nHist += 1
        if .hit > 0
            histKind[nHist] = 2
            histT[nHist]    = ptT[.hit]
            histV[nHist]    = ptV[.hit]
            ptV[.hit] = .y
            status$ = "Moved point at " + fixed$ (ptT[.hit], 3) + " s to "
                ... + fixed$ (.y, 1) + " dB."
        else
            # sorted insert
            .pos = nPts + 1
            for .i to nPts
                if .pos = nPts + 1 and ptT[.i] > .x
                    .pos = .i
                endif
            endfor
            for .k to nPts - .pos + 1
                .j  = nPts - .k + 1
                .jn = .j + 1
                ptT[.jn] = ptT[.j]
                ptV[.jn] = ptV[.j]
            endfor
            ptT[.pos] = .x
            ptV[.pos] = .y
            nPts += 1
            histKind[nHist] = 1
            histT[nHist]    = .x
            histV[nHist]    = .y
            status$ = "Added " + fixed$ (.x, 3) + " s, " + fixed$ (.y, 1) + " dB."
        endif
    else
        status$ = "Click inside the lower panel."
    endif
endproc

procedure undoLast
    if nHist = 0
        status$ = "Nothing to undo."
    else
        .idx = 0
        for .i to nPts
            if ptT[.i] = histT[nHist]
                .idx = .i
            endif
        endfor
        if histKind[nHist] = 2 and .idx > 0
            ptV[.idx] = histV[nHist]
            status$ = "Undid move."
        elsif .idx > 0
            for .i from .idx to nPts - 1
                .j = .i + 1
                ptT[.i] = ptT[.j]
                ptV[.i] = ptV[.j]
            endfor
            nPts -= 1
            status$ = "Undid add."
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
            if nPts = 0
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
# APPLY  (Sound & IntensityTier: Multiply, scaling OFF)
# ============================================================
# Editor times are relative (0..duration); the tier lives on the Sound's
# own time domain, so shift by tStart.
tier = Create IntensityTier: "drawn", tStart, tEnd
for i to nPts
    Add point: tStart + ptT[i], ptV[i]
endfor

selectObject: sound, tier
result = Multiply: "no"
Rename: soundName$ + "_drawnIntensity"
removeObject: tier

selectObject: result
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

# ---- Final view: input vs output waveform ----
appliedView = 1
if scaled
    status$ = "Applied. Peak " + fixed$ (peakRaw, 3) + " rescaled to 0.99. Playing..."
else
    status$ = "Applied. Peak " + fixed$ (peakOut, 3) + ". Playing..."
endif
@drawAll

# ---- Info ----
writeInfoLine: "=== Draw Intensity Envelope 1.0 ==="
appendInfoLine: "Input:    ", soundName$, "  (", fixed$ (duration, 3), " s, ", nChIn, " ch)"
appendInfoLine: "Points:   ", nPts, "   range ±", range_dB, " dB"
for i to nPts
    appendInfoLine: "  ", fixed$ (ptT[i], 3), " s   ", fixed$ (ptV[i], 2), " dB"
endfor
appendInfoLine: "Peak in:  ", fixed$ (peakIn, 4), "   out: ", fixed$ (peakOut, 4)
if scaled
    appendInfoLine: "          (raw peak ", fixed$ (peakRaw, 4), " rescaled to 0.99 - absolute level not preserved)"
elsif peakRaw > 1
    appendInfoLine: "WARNING: output peak > 1 will clip on playback/save (Prevent_clipping is off)."
endif
if rmsIn > 0 and rmsOut > 0
    appendInfoLine: "RMS change: ", fixed$ (20 * log10 (rmsOut / rmsIn), 2), " dB"
endif
appendInfoLine: "Output:   ", soundName$, "_drawnIntensity"

selectObject: result
Play
