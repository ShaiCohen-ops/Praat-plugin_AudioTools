# ============================================================
# Praat AudioTools - Linear_Fade-Out.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 (2026)
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
srcStart = Get start time
srcEnd = Get end time

# ============================================================
# FORM
# ============================================================

# Changelog v1.2 (2026):
#   - FIX: All fade boundaries, formulas, reporting, and visualization now use
#     the Sound's actual start/end time instead of assuming xmin = 0.
#   - FIX: Curve_base = 1 is handled as the exact linear limiting case for
#     Exponential/Logarithmic curves, avoiding division by zero; 0 < base < 1
#     remains supported and is drawn with the same formula used for DSP.
#   - FIX: Info reporting now uses appendInfoLine after the first writeInfoLine.
#   - FIX: Visualization uses gain = 1.0 outside the fade region (not 1.1).
#   - CHANGE: Removed forced peak normalization. Normalize_output is now an
#     explicit option, off by default; when enabled, non-silent output is
#     scaled to 0.99 peak.
#
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
form Fade-Out v1.2
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
    boolean Normalize_output 0
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
normalizeOut = normalize_output

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

# Preserve the documented curve character: bases below 1 reverse the named
# Exponential/Logarithmic curvature. Base = 1 is allowed as the linear limit.
if (curveShape = 2 or curveShape = 3) and curveBase < 1
    exitScript: "Curve_base must be >= 1.0 for Exponential/Logarithmic curves (1.0 gives the linear limiting case)."
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

# Fade region in the Sound's actual time domain: [fadeStart, srcEnd]
if fullDur = 1
    fadeLen = srcDur
else
    fadeLen = fadeSecs
    if fadeLen > srcDur
        fadeLen = srcDur
    endif
    if fadeLen < 0.001
        fadeLen = min(0.001, srcDur)
    endif
endif
fadeStart = srcEnd - fadeLen
fadeEnd = srcEnd

# Exponential/Logarithmic base = 1 is the exact linear limiting case.
baseIsLinearLimit = abs(curveBase - 1) < 1e-9

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

# Fade-out envelope over [fadeStart, fadeEnd]
# phi = (x - fadeStart) / fadeLen within the fade region
# env = 1.0 before fadeStart.

selectObject: workSound

if fadeLen > 0

    fsStr$ = string$(fadeStart)
    flStr$ = string$(fadeLen)

    if curveShape = 1
        # Linear: 1 - phi
        Formula: "if x >= " + fsStr$ +
            ... " then self * (1 - (x - " + fsStr$ + ") / " + flStr$ + ")" +
            ... " else self endif"

    elsif curveShape = 2
        # Exponential: (base^(1-phi) - 1)/(base-1); base -> 1 gives linear.
        if baseIsLinearLimit
            Formula: "if x >= " + fsStr$ +
                ... " then self * (1 - (x - " + fsStr$ + ") / " + flStr$ + ")" +
                ... " else self endif"
        else
            bStr$ = string$(curveBase)
            Formula: "if x >= " + fsStr$ +
                ... " then self * ((" + bStr$ + "^(1-(x-" + fsStr$ + ")/" + flStr$ + ") - 1) / (" + bStr$ + " - 1))" +
                ... " else self endif"
        endif

    elsif curveShape = 3
        # Logarithmic: 1 - ln(1 + phi*(base-1))/ln(base); base -> 1 linear.
        if baseIsLinearLimit
            Formula: "if x >= " + fsStr$ +
                ... " then self * (1 - (x - " + fsStr$ + ") / " + flStr$ + ")" +
                ... " else self endif"
        else
            bStr$ = string$(curveBase)
            Formula: "if x >= " + fsStr$ +
                ... " then self * (1 - ln(1 + ((x-" + fsStr$ + ")/" + flStr$ + ")*(" + bStr$ + "-1)) / ln(" + bStr$ + "))" +
                ... " else self endif"
        endif

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

# Optional, explicit normalization. Off by default so the fade/compression
# retain their natural gain effect.
normalizationApplied = 0
selectObject: workSound
preNormalizePeak = Get absolute extremum: 0, 0, "None"
if normalizeOut = 1
    if preNormalizePeak > 0
        Scale peak: 0.99
        normalizationApplied = 1
    endif
endif

# ============================================================
# INFO
# ============================================================

clearinfo
writeInfoLine:  "=================================================="
appendInfoLine: "  Fade-Out v1.2"
appendInfoLine: "=================================================="
appendInfoLine: ""
appendInfoLine: "Preset       : ", presetName$
appendInfoLine: "Source       : ", srcName$, " (", fixed$(srcDur, 3), " s; time ", fixed$(srcStart, 3), " -> ", fixed$(srcEnd, 3), " s)"
appendInfoLine: "Curve        : ", curveName$
appendInfoLine: "Fade region  : ", fixed$(fadeStart, 3), " s -> ", fixed$(fadeEnd, 3), " s",
    ... "  (", fixed$(fadeLen, 3), " s)"
if doComp = 1
    compLabel$ = "on  (denom=" + string$(compDenom) + ")"
else
    compLabel$ = "off"
endif
appendInfoLine: "Compression  : ", compLabel$
if normalizeOut = 1
    if normalizationApplied
        normLabel$ = "on (peak 0.99)"
    else
        normLabel$ = "requested; skipped (silent output)"
    endif
else
    normLabel$ = "off"
endif
appendInfoLine: "Normalize    : ", normLabel$
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
    Text: 0.5, "centre", 0.68, "half", "##Fade-Out v1.2##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", vizName$ + " | " + presetName$ + " | " + curveName$ + " | fade " + fixed$(fadeStart, 2) + " -> " + fixed$(fadeEnd, 2) + " s"

    # --- PANEL 1: Original waveform ---
    Select outer viewport: 0, 8, 0.55, 1.55
    Select inner viewport: 0.75, 7.6, 0.60, 1.50
    Axes: srcStart, srcEnd, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", srcStart, srcEnd, -ampMax, ampMax
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: srcStart, 0, srcEnd, 0
    selectObject: srcSound
    Colour: "{0.55, 0.55, 0.60}"
    Draw: srcStart, srcEnd, -ampMax, ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Text top: "no", "Input waveform"

    # --- PANEL 2: Envelope curve ---
    Select outer viewport: 0, 8, 1.60, 2.40
    Select inner viewport: 0.75, 7.6, 1.65, 2.35
    Axes: srcStart, srcEnd, -0.05, 1.15
    Paint rectangle: "{0.97, 0.97, 0.97}", srcStart, srcEnd, -0.05, 1.15
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: srcStart, 0, srcEnd, 0
    Draw line: srcStart, 1, srcEnd, 1

    # Fade region background
    Paint rectangle: "{0.99, 0.93, 0.88}", fadeStart, fadeEnd, -0.05, 1.15

    # Draw envelope with 300 points
    nPts = 300
    Colour: "{0.85, 0.35, 0.15}"
    Line width: 2
    for p from 1 to nPts - 1
        t1 = srcStart + (p - 1) / nPts * srcDur
        t2 = srcStart + p / nPts * srcDur

        if t1 >= fadeStart and fadeLen > 0.001
            pp1 = (t1 - fadeStart) / fadeLen
            if curveShape = 1
                e1 = 1 - pp1
            elsif curveShape = 2
                if not baseIsLinearLimit
                    e1 = (curveBase^(1-pp1) - 1) / (curveBase - 1)
                else
                    e1 = 1 - pp1
                endif
            elsif curveShape = 3
                if not baseIsLinearLimit
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
            e1 = 1.0
        endif

        if t2 >= fadeStart and fadeLen > 0.001
            pp2 = (t2 - fadeStart) / fadeLen
            if curveShape = 1
                e2 = 1 - pp2
            elsif curveShape = 2
                if not baseIsLinearLimit
                    e2 = (curveBase^(1-pp2) - 1) / (curveBase - 1)
                else
                    e2 = 1 - pp2
                endif
            elsif curveShape = 3
                if not baseIsLinearLimit
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
            e2 = 1.0
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
    Axes: srcStart, srcEnd, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", srcStart, srcEnd, -ampMax, ampMax
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: srcStart, 0, srcEnd, 0
    selectObject: workSound
    Colour: "{0.85, 0.35, 0.15}"
    Draw: srcStart, srcEnd, -ampMax, ampMax, "no", "Curve"
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
    Text: 0.02, "left", 0.85, "half", "##Summary##  Fade-Out v1.2##"
    Font size: 6
    Colour: "{0.35, 0.35, 0.40}"
    Text: 0.02, "left", 0.62, "half",
        ... "Source: " + srcName$ + "  (" + fixed$(srcDur, 3) + " s  |  " + string$(srcSr) + " Hz)"
    Text: 0.02, "left", 0.40, "half",
        ... "Curve: " + curveName$
        ... + "  |  Fade: " + fixed$(fadeStart, 3) + " -> " + fixed$(fadeEnd, 3) + " s"
        ... + "  (" + fixed$(fadeLen, 3) + " s)"
    compLine$ = "Compression: off"
    if doComp = 1
        compLine$ = "Compression: on  (denom=" + string$(compDenom) + ")"
    endif
    normLine$ = "Normalize: off"
    if normalizeOut = 1
        if normalizationApplied
            normLine$ = "Normalize: peak 0.99"
        else
            normLine$ = "Normalize: skipped (silent)"
        endif
    endif
    Text: 0.02, "left", 0.18, "half",
        ... compLine$ + "  |  " + normLine$ + "  |  Output peak: " + fixed$(outPeakViz, 4) + "  |  Preset: " + presetName$
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
