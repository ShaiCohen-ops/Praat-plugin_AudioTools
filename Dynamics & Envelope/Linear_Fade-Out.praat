# ============================================================
# Praat AudioTools - Linear_Fade-Out.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Fade-Out with multiple curve shapes, optional soft compression,
#   and optional partial fade (last N seconds only).
#
#   CURVE SHAPES (phi = position in fade region, 0=start, 1=end):
#   - Linear         : 1 - phi
#   - Exponential    : (base^(1-phi) - 1) / (base - 1)  (holds, then drops)
#   - Logarithmic    : 1 - log(1 + phi*(base-1)) / log(base)  (drops fast)
#   - S-Curve        : (1 + cos(phi*pi)) / 2  (smooth start and end)
#   - Quarter-cosine : cos(phi * pi/2)  (perceptually smooth)
#
#   SOFT COMPRESSION (waveshaping, optional):
#   Applied before fade. Shape: x / (1 + x^2/C)
#   Rounds peaks without hard clipping. Higher C = less effect.
#
#   PARTIAL FADE:
#   Fade covers only the last N seconds. Before the fade region
#   the amplitude remains unchanged (envelope = 1.0).
#
# Category: Dynamics
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

srcSound = selected("Sound")
srcName$ = selected$("Sound")

selectObject: srcSound
srcDur = Get total duration
srcSr  = Get sampling frequency

# ============================================================
# FORM
# ============================================================

# Changelog v1.1 (2026):
#   - VISUALIZATION / UI STANDARDIZATION ONLY. Audio analysis,
#     DSP, scheduling and rendering are unchanged from the
#     previous version.
#   - Adopted the Praat AudioTools 8-inch visualization header,
#     suite typography, neutral panel backgrounds, summary-style
#     reporting and full-page Picture export restoration.
#   - Preserved the script-specific diagnostic / transformation
#     views rather than replacing them with generic plots.
#
form Fade-Out v1.1
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Natural Decay    (quarter-cosine, full, no compression)
        option Hard Cut         (exponential, last 10%, fast drop)
        option Cinematic Close  (S-curve, full, soft compression)
        option Slow Dissolve    (logarithmic, full)
        option Tail Trim        (linear, last 3 s)
        option Compressed Exit  (S-curve, full, heavy compression)
    comment === Fade Curve ===
    optionmenu Curve_shape: 5
        option Linear
        option Exponential  (holds, then drops fast)
        option Logarithmic  (drops fast, then holds)
        option S-Curve  (smooth start and end)
        option Quarter-cosine
    positive Curve_base 10.0
    comment (used by Exponential and Logarithmic only)
    comment === Fade Range ===
    boolean Full_duration 1
    positive Fade_seconds 3.0
    comment (fade covers last N seconds; ignored when Full_duration = on)
    comment === Soft Compression (optional) ===
    boolean Apply_compression 0
    positive Compression_denominator 4.0
    comment (higher = less effect  |  try 2-8)
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# ALIASES
# ============================================================

curveShape  = curve_shape
curveBase   = curve_base
fullDur     = full_duration
fadeSecs    = fade_seconds
doComp      = apply_compression
compDenom   = compression_denominator

# ============================================================
# PRESETS
# ============================================================

presetName$ = "Custom"

if preset = 2
    presetName$ = "Natural Decay"
    curveShape = 5
    fullDur    = 1
    doComp     = 0
elsif preset = 3
    presetName$ = "Hard Cut"
    curveShape = 2
    curveBase  = 30.0
    fullDur    = 0
    fadeSecs   = srcDur * 0.10
    doComp     = 0
elsif preset = 4
    presetName$ = "Cinematic Close"
    curveShape = 4
    fullDur    = 1
    doComp     = 1
    compDenom  = 6.0
elsif preset = 5
    presetName$ = "Slow Dissolve"
    curveShape = 3
    curveBase  = 8.0
    fullDur    = 1
    doComp     = 0
elsif preset = 6
    presetName$ = "Tail Trim"
    curveShape = 1
    fullDur    = 0
    fadeSecs   = 3.0
    doComp     = 0
elsif preset = 7
    presetName$ = "Compressed Exit"
    curveShape = 4
    fullDur    = 1
    doComp     = 1
    compDenom  = 2.0
endif

# Curve name
if curveShape = 1
    curveName$ = "Linear"
elsif curveShape = 2
    curveName$ = "Exponential (base " + string$(curveBase) + ")"
elsif curveShape = 3
    curveName$ = "Logarithmic (base " + string$(curveBase) + ")"
elsif curveShape = 4
    curveName$ = "S-Curve"
else
    curveName$ = "Quarter-cosine"
endif

# Fade region: [fadeStart, srcDur]
if fullDur = 1
    fadeStart = 0
else
    fadeStart = srcDur - fadeSecs
    if fadeStart < 0
        fadeStart = 0
    endif
endif

# ============================================================
# PROCESS
# ============================================================

selectObject: srcSound
workSound = Copy: srcName$ + "_fadeOut"

# Optional soft compression first
if doComp = 1
    selectObject: workSound
    cdStr$ = string$(compDenom)
    Formula: "self / (1 + (self^2) / " + cdStr$ + ")"
endif

# Fade-out envelope over [fadeStart, srcDur]
# phi = (x - fadeStart) / (srcDur - fadeStart)  within fade region
# env = 1.0 before fadeStart

selectObject: workSound
fadeLen = srcDur - fadeStart

if fadeLen > 0.001

    fsStr$ = string$(fadeStart)
    flStr$ = string$(fadeLen)

    if curveShape = 1
        # Linear: 1 - phi
        Formula: "if x >= " + fsStr$ +
            ... " then self * (1 - (x - " + fsStr$ + ") / " + flStr$ + ")" +
            ... " else self endif"

    elsif curveShape = 2
        # Exponential: holds long then drops fast
        # env = (base^(1-phi) - 1) / (base - 1)
        bStr$ = string$(curveBase)
        Formula: "if x >= " + fsStr$ +
            ... " then self * ((" + bStr$ + "^(1-(x-" + fsStr$ + ")/" + flStr$ + ") - 1) / (" + bStr$ + " - 1))" +
            ... " else self endif"

    elsif curveShape = 3
        # Logarithmic: drops fast then holds
        # env = 1 - ln(1 + phi*(base-1)) / ln(base)
        bStr$ = string$(curveBase)
        Formula: "if x >= " + fsStr$ +
            ... " then self * (1 - ln(1 + ((x-" + fsStr$ + ")/" + flStr$ + ")*(" + bStr$ + "-1)) / ln(" + bStr$ + "))" +
            ... " else self endif"

    elsif curveShape = 4
        # S-Curve: (1 + cos(phi*pi)) / 2
        Formula: "if x >= " + fsStr$ +
            ... " then self * ((1 + cos(((x-" + fsStr$ + ")/" + flStr$ + ") * pi)) / 2)" +
            ... " else self endif"

    else
        # Quarter-cosine: cos(phi * pi/2)
        Formula: "if x >= " + fsStr$ +
            ... " then self * cos(((x-" + fsStr$ + ")/" + flStr$ + ") * (pi/2))" +
            ... " else self endif"
    endif

endif

selectObject: workSound
outPeak = Get absolute extremum: 0, 0, "None"
if outPeak > 0
    Scale peak: 0.99
endif

# ============================================================
# INFO
# ============================================================

clearinfo
writeInfoLine:  "=================================================="
writeInfoLine:  "  Fade-Out v1.1"
writeInfoLine:  "=================================================="
appendInfoLine: ""
appendInfoLine: "Preset       : ", presetName$
appendInfoLine: "Source       : ", srcName$, " (", fixed$(srcDur, 3), " s)"
appendInfoLine: "Curve        : ", curveName$
appendInfoLine: "Fade region  : ", fixed$(fadeStart, 3), " s -> ", fixed$(srcDur, 3), " s",
    ... "  (", fixed$(srcDur - fadeStart, 3), " s)"
if doComp = 1
    compLabel$ = "on  (denom=" + string$(compDenom) + ")"
else
    compLabel$ = "off"
endif
appendInfoLine: "Compression  : ", compLabel$
appendInfoLine: "Output       : ", srcName$, "_fadeOut"

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization = 1

    selectObject: srcSound
    origPeak = Get absolute extremum: 0, 0, "None"
    selectObject: workSound
    outPeakViz = Get absolute extremum: 0, 0, "None"
    ampMax = origPeak
    if outPeakViz > ampMax
        ampMax = outPeakViz
    endif
    if ampMax < 0.001
        ampMax = 0.001
    endif
    ampMax = ampMax * 1.15

    Erase all
    vizName$ = replace$(srcName$, "_", "\_ ", 0)
    pageWidth = 8
    # === Header ===
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Fade-Out v1.1##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", vizName$ + " | " + presetName$ + " | " + curveName$ + " | fade " + fixed$(fadeStart, 2) + " -> " + fixed$(srcDur, 2) + " s"

    # --- PANEL 1: Original waveform ---
    Select outer viewport: 0, 8, 0.55, 1.55
    Select inner viewport: 0.75, 7.6, 0.60, 1.50
    Axes: 0, srcDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, srcDur, -ampMax, ampMax
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, srcDur, 0
    selectObject: srcSound
    Colour: "{0.55, 0.55, 0.60}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Text top: "no", "Input waveform"

    # --- PANEL 2: Envelope curve ---
    Select outer viewport: 0, 8, 1.60, 2.40
    Select inner viewport: 0.75, 7.6, 1.65, 2.35
    Axes: 0, srcDur, -0.05, 1.15
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, srcDur, -0.05, 1.15
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, srcDur, 0
    Draw line: 0, 1, srcDur, 1

    # Fade region background
    Paint rectangle: "{0.99, 0.93, 0.88}", fadeStart, srcDur, -0.05, 1.15

    # Draw envelope with 300 points
    nPts = 300
    Colour: "{0.85, 0.35, 0.15}"
    Line width: 2
    for p from 1 to nPts - 1
        t1 = (p - 1) / nPts * srcDur
        t2 = p / nPts * srcDur

        if t1 >= fadeStart and fadeLen > 0.001
            pp1 = (t1 - fadeStart) / fadeLen
            if curveShape = 1
                e1 = 1 - pp1
            elsif curveShape = 2
                if curveBase > 1
                    e1 = (curveBase^(1-pp1) - 1) / (curveBase - 1)
                else
                    e1 = 1 - pp1
                endif
            elsif curveShape = 3
                if curveBase > 1
                    e1 = 1 - ln(1 + pp1*(curveBase-1)) / ln(curveBase)
                else
                    e1 = 1 - pp1
                endif
            elsif curveShape = 4
                e1 = (1 + cos(pp1 * pi)) / 2
            else
                e1 = cos(pp1 * (pi/2))
            endif
        else
            e1 = 1.1
        endif

        if t2 >= fadeStart and fadeLen > 0.001
            pp2 = (t2 - fadeStart) / fadeLen
            if curveShape = 1
                e2 = 1 - pp2
            elsif curveShape = 2
                if curveBase > 1
                    e2 = (curveBase^(1-pp2) - 1) / (curveBase - 1)
                else
                    e2 = 1 - pp2
                endif
            elsif curveShape = 3
                if curveBase > 1
                    e2 = 1 - ln(1 + pp2*(curveBase-1)) / ln(curveBase)
                else
                    e2 = 1 - pp2
                endif
            elsif curveShape = 4
                e2 = (1 + cos(pp2 * pi)) / 2
            else
                e2 = cos(pp2 * (pi/2))
            endif
        else
            e2 = 1.1
        endif

        Draw line: t1, e1, t2, e2
    endfor
    Line width: 1

    # Fade-start marker for partial fade
    if fullDur = 0
        Colour: "{0.20, 0.50, 0.85}"
        Dotted line
        Draw line: fadeStart, -0.05, fadeStart, 1.15
        Solid line
    endif

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Gain"
    Text top: "no", "Fade-out envelope  (orange shading = fade region)"

    # --- PANEL 3: Processed waveform ---
    Select outer viewport: 0, 8, 2.45, 3.45
    Select inner viewport: 0.75, 7.6, 2.50, 3.40
    Axes: 0, srcDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, srcDur, -ampMax, ampMax
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, srcDur, 0
    selectObject: workSound
    Colour: "{0.85, 0.35, 0.15}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text top: "no", "Processed waveform"
    Text bottom: "yes", "Time (s)"

    # --- Summary strip ---
    Select outer viewport: 0, 8, 3.55, 4.25
    Select inner viewport: 0.5, 7.8, 3.60, 4.20
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.85, "half", "##Summary##  Fade-Out v1.1##"
    Font size: 6
    Colour: "{0.35, 0.35, 0.40}"
    Text: 0.02, "left", 0.62, "half",
        ... "Source: " + srcName$ + "  (" + fixed$(srcDur, 3) + " s  |  " + string$(srcSr) + " Hz)"
    Text: 0.02, "left", 0.40, "half",
        ... "Curve: " + curveName$
        ... + "  |  Fade: " + fixed$(fadeStart, 3) + " -> " + fixed$(srcDur, 3) + " s"
        ... + "  (" + fixed$(srcDur - fadeStart, 3) + " s)"
    compLine$ = "Compression: off"
    if doComp = 1
        compLine$ = "Compression: on  (denom=" + string$(compDenom) + ")"
    endif
    Text: 0.02, "left", 0.18, "half",
        ... compLine$ + "  |  Output peak: " + fixed$(outPeakViz, 4) + "  |  Preset: " + presetName$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Line width: 1
    Colour: "Black"
    # Restore complete page for Picture export / clipboard.
    pageHeight = 6.20
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line

endif

# ============================================================
# OUTPUT
# ============================================================

selectObject: workSound

if play_result = 1
    Play
endif
