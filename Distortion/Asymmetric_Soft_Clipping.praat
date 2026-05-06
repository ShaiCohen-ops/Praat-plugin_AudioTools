# ============================================================
# Praat AudioTools - Asymmetric_Soft_Clipping.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Asymmetric Soft Clipping (Tube Distortion). Models tube-style
#   bias distortion with independent positive/negative shape
#   parameters. The transfer function is:
#       y = tanh((x * drive + bias) * shape) * output_gain
#   where shape switches between pos_Shape and neg_Shape based on
#   the sign of (x * drive + bias). Bias offsets the signal into
#   the tube's nonlinear region asymmetrically.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.2:
#   - Audio pipeline UNCHANGED. Output is bit-identical to v0.1
#     for the same form parameters. Speed matches v0.1 exactly.
#   - Form syntax modernized: optionmenu uses colon.
#   - NEW (optional): Scale_peak toggle. Default OFF (matches
#     v0.1 — output level depends on input * drive * tanh-shape
#     * output_gain). When ON, scales final result to 0.95 peak
#     for consistent output level across sources.
#   - Visualization rewritten to suite 8x8 standard with title
#     bar + metadata subtitle, transfer function as headline,
#     parameter report panel, output waveform with L/R channels
#     distinguished, summary stats bar.
#   - Removed dead code (unused Get start time / Get end time).
# Changelog v0.1:
#   - Initial release. Boolean-trick formula for compatibility
#     across older Praat versions. 5 presets.
# ============================================================

form Asymmetric Soft Clipping v0.2
    comment Select a Preset (overrides sliders below)
    optionmenu Preset: 1
        option Manual (Use settings below)
        option Warm Tube Saturation
        option Hard Overdrive
        option Asymmetric Fuzz
        option Broken/Gated Bias
        option Subtle Warmer
    
    comment Manual Parameters
    real Drive 2.0
    real Bias 0.1
    real Pos_Shape 1.0
    real Neg_Shape 3.0
    real Output_Gain 0.8
    
    comment Output
    boolean Scale_peak 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

# === Handle Presets ===
presetName$ = "Manual"

if preset = 2
    presetName$ = "WarmTube"
    drive = 1.5
    bias = 0.05
    pos_Shape = 0.8
    neg_Shape = 1.2
    output_Gain = 0.9
elsif preset = 3
    presetName$ = "HardOverdrive"
    drive = 5.0
    bias = 0.0
    pos_Shape = 2.0
    neg_Shape = 2.0
    output_Gain = 0.5
elsif preset = 4
    presetName$ = "AsymmetricFuzz"
    drive = 3.5
    bias = 0.3
    pos_Shape = 5.0
    neg_Shape = 0.5
    output_Gain = 0.6
elsif preset = 5
    presetName$ = "GatedBias"
    drive = 4.0
    bias = 0.8
    pos_Shape = 4.0
    neg_Shape = 0.5
    output_Gain = 0.6
elsif preset = 6
    presetName$ = "SubtleWarmer"
    drive = 1.1
    bias = 0.02
    pos_Shape = 0.5
    neg_Shape = 0.6
    output_Gain = 0.95
endif

# === Get original details ===
original = selected("Sound")
origName$ = selected$("Sound")

selectObject: original
inputDur = Get total duration
inputCh = Get number of channels

# === Process Audio  (identical to v0.1) ===
selectObject: original
Copy: origName$ + "_Tube_" + presetName$
result = selected("Sound")

# Boolean-trick formula (preserved from v0.1 for compatibility)
in$ = "(self * " + string$(drive) + " + " + string$(bias) + ")"
shape_logic$ = "( (" + in$ + " >= 0) * " + string$(pos_Shape)
    ... + " + (" + in$ + " < 0) * " + string$(neg_Shape) + " )"
formula$ = "tanh(" + in$ + " * " + shape_logic$ + ") * " + string$(output_Gain)

selectObject: result
Formula: formula$

if scale_peak
    selectObject: result
    Scale peak: 0.95
endif

# === Final stats ===
selectObject: result
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"
nResultCh = Get number of channels

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_visualization
    Erase all
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##ASYMMETRIC SOFT CLIPPING (TUBE)##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... origName$
        ... + "  |  " + presetName$
        ... + "  |  Drive: " + fixed$(drive, 2)
        ... + "  |  Bias: " + fixed$(bias, 2)
        ... + "  |  Shape +/-: " + fixed$(pos_Shape, 2) + " / " + fixed$(neg_Shape, 2)
        ... + "  |  Out gain: " + fixed$(output_Gain, 2)
    
    # ----------------------------------------------------------
    # PANEL A: TRANSFER FUNCTION  (left, headline)
    # The defining diagnostic for any clipper.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    Axes: -1.5, 1.5, -1.5, 1.5
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.5, 1.5, -1.5, 1.5
    
    # Grid: zero axes
    Colour: "{0.85, 0.85, 0.88}"
    Line width: 1
    Draw line: -1.5, 0, 1.5, 0
    Draw line: 0, -1.5, 0, 1.5
    
    # y=x reference (no shaping)
    Dotted line
    Colour: "{0.65, 0.65, 0.70}"
    Draw line: -1.5, -1.5, 1.5, 1.5
    Solid line
    Font size: 5
    Text: -1.45, "left", -1.40, "half", "y = x"
    
    # ±1 reference lines (output ceiling/floor)
    Colour: "{0.78, 0.65, 0.78}"
    Dotted line
    Draw line: -1.5, 1, 1.5, 1
    Draw line: -1.5, -1, 1.5, -1
    Solid line
    Font size: 5
    Colour: "{0.55, 0.30, 0.55}"
    Text: -1.45, "left", 1, "bottom", " +1"
    Text: -1.45, "left", -1, "top", " -1"
    
    # Bias offset reference (vertical line at the input level
    # where tanh argument is zero)
    if drive <> 0
        zeroIn = -bias / drive
        if zeroIn >= -1.5 and zeroIn <= 1.5
            Colour: "{0.55, 0.78, 0.55}"
            Dotted line
            Draw line: zeroIn, -1.5, zeroIn, 1.5
            Solid line
            Font size: 5
            Colour: "{0.30, 0.55, 0.30}"
            Text: zeroIn, "left", -1.40, "half", " sign flip"
        endif
    endif
    
    # Draw transfer function
    Colour: "{0.30, 0.45, 0.78}"
    Line width: 2
    nPoints = 200
    
    # First point
    prev_x = -1.5
    val_prev = prev_x * drive + bias
    if val_prev >= 0
        shape_p = pos_Shape
    else
        shape_p = neg_Shape
    endif
    prev_y = tanh(val_prev * shape_p) * output_Gain
    if prev_y > 1.4
        prev_y = 1.4
    endif
    if prev_y < -1.4
        prev_y = -1.4
    endif
    
    for i from 1 to nPoints
        curr_x = -1.5 + (i / nPoints) * 3.0
        val = curr_x * drive + bias
        if val >= 0
            shape = pos_Shape
        else
            shape = neg_Shape
        endif
        curr_y = tanh(val * shape) * output_Gain
        if curr_y > 1.4
            curr_y = 1.4
        endif
        if curr_y < -1.4
            curr_y = -1.4
        endif
        Draw line: prev_x, prev_y, curr_x, curr_y
        prev_x = curr_x
        prev_y = curr_y
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Output"
    Text bottom: "yes", "Input"
    
    # ----------------------------------------------------------
    # PANEL B: PARAMETER REPORT  (right, headline-height)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1
    
    # Section: Transfer
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.93, "half", "Transfer parameters:"
    
    Font size: 11
    Colour: "{0.30, 0.45, 0.78}"
    Text: 0.10, "left", 0.84, "half", "Drive:    " + fixed$(drive, 2)
    Text: 0.10, "left", 0.76, "half", "Bias:     " + fixed$(bias, 3)
    
    # Section: Asymmetry
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.65, "half", "Asymmetric shapes:"
    
    Font size: 11
    Colour: "{0.80, 0.40, 0.40}"
    Text: 0.10, "left", 0.56, "half", "Pos:      " + fixed$(pos_Shape, 2)
    Colour: "{0.40, 0.55, 0.78}"
    Text: 0.10, "left", 0.48, "half", "Neg:      " + fixed$(neg_Shape, 2)
    
    # Asymmetry indicator
    if pos_Shape > neg_Shape
        asymStr$ = "harder positive"
    elsif neg_Shape > pos_Shape
        asymStr$ = "harder negative"
    else
        asymStr$ = "symmetric"
    endif
    Font size: 7
    Colour: "{0.55, 0.55, 0.55}"
    Text: 0.10, "left", 0.40, "half", "(" + asymStr$ + ")"
    
    # Section: Output
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.28, "half", "Output:"
    
    Font size: 11
    Colour: "{0.40, 0.65, 0.40}"
    Text: 0.10, "left", 0.19, "half", "Gain:     " + fixed$(output_Gain, 2)
    
    Font size: 7
    Colour: "{0.55, 0.55, 0.55}"
    if scale_peak
        Text: 0.10, "left", 0.11, "half", "Peak normalized to 0.95"
    else
        Text: 0.10, "left", 0.11, "half", "No peak normalization"
    endif
    
    Colour: "Black"
    Draw inner box
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Transfer function (input -> output)"
    Text: 6.10, "centre", 7.30, "half", "Parameter report"
    
    # ----------------------------------------------------------
    # PANEL C: OUTPUT WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.75
    Select inner viewport: 0.55, 7.72, 4.75, 5.68
    
    selectObject: result
    outPeakViz = Get absolute extremum: 0, 0, "None"
    if outPeakViz < 0.001
        outPeakViz = 0.001
    endif
    ampViz = outPeakViz * 1.15
    
    Axes: 0, finalDur, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDur, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, finalDur, 0
    
    selectObject: result
    if nResultCh = 1
        Colour: "{0.20, 0.55, 0.55}"
        Line width: 1
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    else
        Extract one channel: 1
        vCh1 = selected("Sound")
        Colour: "{0.25, 0.50, 0.82}"
        Line width: 1
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
        removeObject: vCh1
        
        if nResultCh >= 2
            selectObject: result
            Extract one channel: 2
            vCh2 = selected("Sound")
            Colour: "{0.82, 0.45, 0.25}"
            Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
            removeObject: vCh2
        endif
    endif
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    if nResultCh > 1
        Text top: "no", "Output  (blue=L  orange=R)"
    else
        Text top: "no", "Output (mono)"
    endif
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: SUMMARY BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.82, 6.58
    Select inner viewport: 0.55, 7.72, 5.88, 6.52
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    # Pre-compute the scale-peak status string (Praat's inline if/then/else
    # in expressions is reliable inside Formula but less reliable in script
    # string concatenation contexts — using a plain variable is safer).
    if scale_peak
        scaleStr$ = "yes"
    else
        scaleStr$ = "no"
    endif
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + origName$
        ... + "  |  Drive: " + fixed$(drive, 2)
        ... + "  |  Bias: " + fixed$(bias, 3)
        ... + "  |  Pos: " + fixed$(pos_Shape, 2)
        ... + "  |  Neg: " + fixed$(neg_Shape, 2)
    
    Text: 0.02, "left", 0.28, "half",
        ... "Output gain: " + fixed$(output_Gain, 2)
        ... + "  |  Asymmetry: " + asymStr$
        ... + "  |  Scale peak: " + scaleStr$
        ... + "  |  Output: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# === Final ===
selectObject: result

writeInfoLine: "=== Asymmetric Soft Clipping v0.2 ==="
appendInfoLine: "Source: ", origName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Drive: ", fixed$(drive, 2), " | Bias: ", fixed$(bias, 3)
appendInfoLine: "Shape +/-: ", fixed$(pos_Shape, 2), " / ", fixed$(neg_Shape, 2)
appendInfoLine: "Output gain: ", fixed$(output_Gain, 2)
appendInfoLine: "Output: ", selected$("Sound"), " (", fixed$(finalDur, 2), " s, peak ", fixed$(finalPeak, 3), ")"

if play_result
    selectObject: result
    Play
endif

selectObject: result
