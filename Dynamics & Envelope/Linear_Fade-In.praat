# ============================================================
# Praat AudioTools - Linear_Fade-In.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Fade-In with multiple curve shapes and optional attenuation.
#   All processing in-place on a copy. Visualization shows the
#   envelope curve overlaid on the original and processed waveforms.
#
#   CURVE SHAPES:
#   - Linear       : phi  (constant rate)
#   - Exponential  : (base^phi - 1) / (base - 1)  (slow then fast)
#   - Logarithmic  : log(1 + phi*(base-1)) / log(base)  (fast then slow)
#   - S-Curve      : cosine-based, smooth start and end
#   - Quarter-sine : sin(phi * pi/2)  (perceptually smooth)
#
#   PARTIAL FADE:
#   Fade can cover only the first N seconds rather than the full sound.
#   After the fade region, amplitude = 1.0 (no further change).
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
form Fade-In v1.1
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Gentle Entry     (log, full, no attenuation)
        option Dramatic Rise    (exponential, full)
        option Smooth Open      (S-curve, full)
        option Quick Attack     (quarter-sine, first 20%)
        option Soft Intro       (linear, first 2 s, attenuated)
        option Cinematic Swell  (S-curve, full, attenuated -6dB)
    comment === Fade Curve ===
    optionmenu Curve_shape: 4
        option Linear
        option Exponential  (slow start, fast end)
        option Logarithmic  (fast start, slow end)
        option S-Curve  (smooth start and end)
        option Quarter-sine
    positive Curve_base 10.0
    comment (used by Exponential and Logarithmic only)
    comment === Fade Range ===
    boolean Full_duration 1
    positive Fade_seconds 2.0
    comment (ignored when Full_duration = on)
    comment === Attenuation ===
    boolean Apply_attenuation 0
    real Attenuation_dB -6.0
    comment (negative = quieter, e.g. -6 dB = half amplitude)
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
doAtten     = apply_attenuation
attenDb     = attenuation_dB

# ============================================================
# PRESETS
# ============================================================

presetName$ = "Custom"

if preset = 2
    presetName$ = "Gentle Entry"
    curveShape = 3
    fullDur    = 1
    doAtten    = 0
elsif preset = 3
    presetName$ = "Dramatic Rise"
    curveShape = 2
    curveBase  = 20.0
    fullDur    = 1
    doAtten    = 0
elsif preset = 4
    presetName$ = "Smooth Open"
    curveShape = 4
    fullDur    = 1
    doAtten    = 0
elsif preset = 5
    presetName$ = "Quick Attack"
    curveShape = 5
    fullDur    = 0
    fadeSecs   = srcDur * 0.20
    doAtten    = 0
elsif preset = 6
    presetName$ = "Soft Intro"
    curveShape = 1
    fullDur    = 0
    fadeSecs   = 2.0
    doAtten    = 1
    attenDb    = -12.0
elsif preset = 7
    presetName$ = "Cinematic Swell"
    curveShape = 4
    fullDur    = 1
    doAtten    = 1
    attenDb    = -6.0
endif

# Curve name for display
if curveShape = 1
    curveName$ = "Linear"
elsif curveShape = 2
    curveName$ = "Exponential (base " + string$(curveBase) + ")"
elsif curveShape = 3
    curveName$ = "Logarithmic (base " + string$(curveBase) + ")"
elsif curveShape = 4
    curveName$ = "S-Curve"
else
    curveName$ = "Quarter-sine"
endif

# Fade region end time
if fullDur = 1
    fadeEnd = srcDur
else
    fadeEnd = fadeSecs
    if fadeEnd > srcDur
        fadeEnd = srcDur
    endif
    if fadeEnd < 0.001
        fadeEnd = 0.001
    endif
endif

# Attenuation linear factor
attenFactor = 10 ^ (attenDb / 20)

# ============================================================
# PROCESS
# ============================================================

selectObject: srcSound
workSound = Copy: srcName$ + "_fadeIn"

# Apply attenuation first (before fade)
if doAtten = 1
    selectObject: workSound
    Formula: "self * " + string$(attenFactor)
endif

# Apply fade-in curve over [0, fadeEnd]
# phi = position within fade region [0,1]
# For samples beyond fadeEnd: envelope = 1.0 (no change)

selectObject: workSound

if curveShape = 1
    # Linear: phi
    Formula: "if x <= " + string$(fadeEnd) +
        ... " then self * ((x - xmin) / " + string$(fadeEnd) + ")" +
        ... " else self endif"

elsif curveShape = 2
    # Exponential: (base^phi - 1) / (base - 1)
    bStr$ = string$(curveBase)
    fStr$ = string$(fadeEnd)
    Formula: "if x <= " + fStr$ +
        ... " then self * ((" + bStr$ + "^((x-xmin)/" + fStr$ + ") - 1) / (" + bStr$ + " - 1))" +
        ... " else self endif"

elsif curveShape = 3
    # Logarithmic: log(1 + phi*(base-1)) / log(base)
    bStr$ = string$(curveBase)
    fStr$ = string$(fadeEnd)
    Formula: "if x <= " + fStr$ +
        ... " then self * (ln(1 + ((x-xmin)/" + fStr$ + ")*(" + bStr$ + "-1)) / ln(" + bStr$ + "))" +
        ... " else self endif"

elsif curveShape = 4
    # S-Curve: (1 - cos(phi*pi)) / 2
    fStr$ = string$(fadeEnd)
    Formula: "if x <= " + fStr$ +
        ... " then self * ((1 - cos(((x-xmin)/" + fStr$ + ") * pi)) / 2)" +
        ... " else self endif"

else
    # Quarter-sine: sin(phi * pi/2)
    fStr$ = string$(fadeEnd)
    Formula: "if x <= " + fStr$ +
        ... " then self * sin(((x-xmin)/" + fStr$ + ") * (pi/2))" +
        ... " else self endif"
endif

selectObject: workSound
Scale peak: 0.99

# ============================================================
# INFO
# ============================================================

clearinfo
writeInfoLine:  "=================================================="
writeInfoLine:  "  Fade-In v1.1"
writeInfoLine:  "=================================================="
appendInfoLine: ""
appendInfoLine: "Preset   : ", presetName$
appendInfoLine: "Source   : ", srcName$, " (", fixed$(srcDur, 3), " s)"
appendInfoLine: "Curve    : ", curveName$
if fullDur = 1
    fadeEndLabel$ = "  (full duration)"
else
    fadeEndLabel$ = "  (partial)"
endif
appendInfoLine: "Fade end : ", fixed$(fadeEnd, 3), " s", fadeEndLabel$
if doAtten = 1
    attenLabel$ = string$(attenDb) + " dB  (x" + fixed$(attenFactor, 4) + ")"
else
    attenLabel$ = "off"
endif
appendInfoLine: "Atten    : ", attenLabel$
appendInfoLine: "Output   : ", srcName$, "_fadeIn"

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization = 1

    selectObject: srcSound
    origPeak = Get absolute extremum: 0, 0, "None"
    selectObject: workSound
    outPeak = Get absolute extremum: 0, 0, "None"
    ampMax = origPeak
    if outPeak > ampMax
        ampMax = outPeak
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
    Text: 0.5, "centre", 0.68, "half", "##Fade-In v1.1##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", vizName$ + " | " + presetName$ + " | " + curveName$ + " | fade 0 -> " + fixed$(fadeEnd, 2) + " s"

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
    Colour: "{0.88, 0.88, 0.88}"
    Draw line: 0, 0, srcDur, 0
    Draw line: 0, 1, srcDur, 1

    # Fade region background
    Paint rectangle: "{0.90, 0.94, 0.99}", 0, fadeEnd, -0.05, 1.15

    # Draw envelope curve with 300 points
    nPts = 300
    Colour: "{0.20, 0.50, 0.85}"
    Line width: 2
    for p from 1 to nPts - 1
        phi1 = (p - 1) / nPts
        phi2 = p / nPts
        t1 = phi1 * srcDur
        t2 = phi2 * srcDur

        # Compute envelope value at phi1
        if t1 <= fadeEnd
            pp1 = (t1) / fadeEnd
            if curveShape = 1
                e1 = pp1
            elsif curveShape = 2
                if curveBase > 1
                    e1 = (curveBase^pp1 - 1) / (curveBase - 1)
                else
                    e1 = pp1
                endif
            elsif curveShape = 3
                if curveBase > 1
                    e1 = ln(1 + pp1*(curveBase-1)) / ln(curveBase)
                else
                    e1 = pp1
                endif
            elsif curveShape = 4
                e1 = (1 - cos(pp1 * pi)) / 2
            else
                e1 = sin(pp1 * (pi/2))
            endif
        else
            e1 = 1.1
        endif

        if t2 <= fadeEnd
            pp2 = (t2) / fadeEnd
            if curveShape = 1
                e2 = pp2
            elsif curveShape = 2
                if curveBase > 1
                    e2 = (curveBase^pp2 - 1) / (curveBase - 1)
                else
                    e2 = pp2
                endif
            elsif curveShape = 3
                if curveBase > 1
                    e2 = ln(1 + pp2*(curveBase-1)) / ln(curveBase)
                else
                    e2 = pp2
                endif
            elsif curveShape = 4
                e2 = (1 - cos(pp2 * pi)) / 2
            else
                e2 = sin(pp2 * (pi/2))
            endif
        else
            e2 = 1.1
        endif

        Draw line: t1, e1, t2, e2
    endfor
    Line width: 1

    # Fade-end marker
    if fullDur = 0
        Colour: "{0.85, 0.35, 0.20}"
        Dotted line
        Draw line: fadeEnd, -0.05, fadeEnd, 1.15
        Solid line
    endif

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Gain"
    Text top: "no", "Fade-in envelope  (blue shading = fade region)"

    # --- PANEL 3: Processed waveform ---
    Select outer viewport: 0, 8, 2.45, 3.45
    Select inner viewport: 0.75, 7.6, 2.50, 3.40
    Axes: 0, srcDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, srcDur, -ampMax, ampMax
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, srcDur, 0
    selectObject: workSound
    Colour: "{0.20, 0.50, 0.85}"
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
    Text: 0.02, "left", 0.85, "half", "##Summary##  Fade-In v1.1##"
    Font size: 6
    Colour: "{0.35, 0.35, 0.40}"
    Text: 0.02, "left", 0.62, "half",
        ... "Source: " + srcName$ + "  (" + fixed$(srcDur, 3) + " s  |  " + string$(srcSr) + " Hz)"
    Text: 0.02, "left", 0.40, "half",
        ... "Curve: " + curveName$
        ... + "  |  Fade region: 0 -> " + fixed$(fadeEnd, 3) + " s"
    attenLine$ = "Attenuation: off"
    if doAtten = 1
        attenLine$ = "Attenuation: " + string$(attenDb) + " dB  (x" + fixed$(attenFactor, 4) + ")"
    endif
    Text: 0.02, "left", 0.18, "half",
        ... attenLine$ + "  |  Output peak: " + fixed$(outPeak, 4) + "  |  Preset: " + presetName$
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
