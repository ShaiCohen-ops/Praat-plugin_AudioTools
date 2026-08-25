# ============================================================
# Praat AudioTools - Asymmetric_Soft_Clipping.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.1 (2026)
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
#   Note that bias does two separable things: it makes the curve
#   asymmetric (the even-harmonic content that is the point of the
#   effect), and it displaces the resting point, so that a silent
#   input produces a constant DC level. Bias_mode controls whether
#   that displacement is kept, compensated, or removed afterwards.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.4.1 (2026):
#   - FIXED: final summary now appends to the Info window instead of
#     erasing the earlier diagnostic report.
#   - FIXED: peak normalization skips a silent (zero-peak) result safely.
#   - RENAMED: "Conditional limiter to 0.95" ->
#     "Attenuate to 0.95 only if peak > 0.95"; the DSP is unchanged.
#   - FIXED: visualization DC references now distinguish raw y(0),
#     zero-in/zero-out compensation, and source-dependent mean removal.
#   - FIXED: transfer-function bounds follow the selected DC mode;
#     source-dependent mean removal no longer shows a static ceiling.
#   - FIXED: multichannel waveform labels use Ch 1 / Ch 2 and state
#     when additional channels are preserved but not drawn.
#
# Changelog v0.4 (2026):
#   - VISUALIZATION STANDARDIZATION ONLY; audio/DSP, analysis,
#     parameter mapping and rendering logic are unchanged.
#   - Adopted the Praat AudioTools 8-inch page convention with
#     explicit inner viewports, standard title/subtitle, suite
#     typography, neutral panel backgrounds, summary strip and
#     full-page Picture export viewport.
#   - Preserved the script-specific nonlinear/diagnostic panels;
#     the visualization remains a direct explanation of the
#     transformation rather than a generic replacement plot.
#
# Changelog v0.3:
#   - NEW Bias_mode. Bias did not only shape the curve; it turned
#     silence into constant DC. Measured zero-input output by
#     preset: Warm Tube +0.036, Hard Overdrive 0, Asymmetric Fuzz
#     +0.543, Extreme Bias +0.598, Subtle Warmer +0.0095, Manual
#     default +0.080. At +0.598 a silent passage becomes a
#     near-constant offset that eats headroom, clicks at any
#     splice, and lets peak normalization scale the DC rather than
#     the music. Subtracting f(0) restores zero-in/zero-out while
#     leaving the curve's asymmetry untouched. Raw is the default,
#     so v0.2 renders are reproducible; "Remove final mean" is
#     available as a third option. Zero-input output and the
#     input/output mean are now reported.
#   - Output_level replaces the Scale_peak boolean. Output_Gain is
#     a constant scalar applied after tanh, so normalizing the peak
#     divides it straight back out: 0.95*g*f(x) / max|g*f(x)| =
#     0.95*f(x) / max|f(x)| for every non-zero g. Verified - with
#     Scale_peak on, gains of 0.2, 0.8 and 2.0 produced identical
#     output. The parameter was displayed and reported while
#     controlling nothing. Preserve (default, = Scale_peak 0) /
#     Conditional limiter to 0.95 / Normalize to 0.95, and the
#     Normalize path now says outright that it nullifies the gain.
#   - Preserve now warns when the output peak exceeds 1.0. tanh
#     bounds the shaped signal to +/-1, so the peak is bounded by
#     |Output_Gain| - a `real` field with no upper limit.
#   - FIXED: the transfer curve was clamped to +/-1.4 in VALUE,
#     which the audio never does; a manual Output_Gain of 3 gave
#     audio reaching almost +/-3 against a flat plateau on the
#     panel. The extent is measured in a pre-pass and the Y axis
#     sized to fit; the axis label reports the range.
#   - The drawn curve now carries the DC mode and the render's
#     actual peak scaling, and the panel title states what it does
#     and does not include (mean removal cannot be drawn as a
#     function of x alone).
#   - RENAMED preset "Broken/Gated Bias" -> "Extreme Biased
#     Saturation". There is no threshold, gate, envelope detector
#     or low-level suppression anywhere in the script, and far from
#     gating quiet passages it turns silence into +0.598 DC. The
#     output object name changes from _Tube_GatedBias to
#     _Tube_ExtremeBias.
#   - The +/-1 lines are labelled as digital full scale, not
#     "output ceiling/floor" - the engine's ceiling before the
#     level stage is +/-|Output_Gain| (+/-0.9 on Warm Tube,
#     +/-0.5 on Hard Overdrive, and above 1 in Manual mode). That
#     real ceiling is now drawn as a separate pair of lines.
#   - The five shaping fields are unbounded `real`s. Zero drive,
#     zero shape, negative shape and negative gain are all still
#     allowed, but each now emits a note saying what it actually
#     does, and the asymmetry indicator no longer claims "harder
#     positive/negative" when a shape is negative.
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

form Asymmetric Soft Clipping v0.4.1
    comment Select a Preset (overrides sliders below)
    optionmenu Preset: 1
        option Manual (Use settings below)
        option Warm Tube Saturation
        option Hard Overdrive
        option Asymmetric Fuzz
        option Extreme Biased Saturation
        option Subtle Warmer
    
    comment Manual Parameters
    real Drive 2.0
    real Bias 0.1
    real Pos_Shape 1.0
    real Neg_Shape 3.0
    real Output_Gain 0.8
    
    comment Output
    optionmenu Bias_mode: 1
        option Raw DC-biased (v0.1/v0.2)
        option DC-compensated (zero in -> zero out)
        option Remove final mean
    optionmenu Output_level: 1
        option Preserve shaped level
        option Attenuate to 0.95 only if peak > 0.95
        option Normalize peak to 0.95
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
    # v0.3 (item 6): was "Broken/Gated Bias" / "GatedBias". There is no
    # threshold, gate, envelope detector or low-level suppression
    # anywhere in the script - and far from gating quiet passages, this
    # preset turns digital silence into +0.598 DC. It is extreme
    # one-sided saturation, so it is now named for that.
    presetName$ = "ExtremeBias"
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

writeInfoLine: "=== Asymmetric Soft Clipping v0.4.1 ==="
appendInfoLine: "Source: ", origName$, " (", fixed$(inputDur, 2), " s, ", inputCh, " ch)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""

# v0.3 (item 8): the five shaping fields are all `real` with no bounds,
# which is fine as an experimental option but stops matching the
# tube-style description the header gives. These are warnings, not
# errors - nothing here is forbidden, it just isn't tube modelling.
if drive = 0
    appendInfoLine: "  NOTE: Drive = 0 - the input is discarded and the whole file becomes a constant set by Bias."
endif
if pos_Shape = 0 or neg_Shape = 0
    appendInfoLine: "  NOTE: a Shape of 0 flattens that entire branch to a constant."
endif
if pos_Shape < 0 or neg_Shape < 0
    appendInfoLine: "  NOTE: negative Shape inverts the polarity of that branch (experimental, not tube-like)."
endif
if output_Gain < 0
    appendInfoLine: "  NOTE: negative Output_Gain inverts the whole output."
endif

# v0.3 (item 1): bias does two separable things - it makes the curve
# asymmetric (the even-harmonic content that is the point of the
# effect), and it displaces the resting point, so that silence becomes a
# constant DC level. v0.2 always did both. Measured zero-input output by
# preset: WarmTube +0.036, HardOverdrive 0, AsymmetricFuzz +0.543,
# ExtremeBias +0.598, SubtleWarmer +0.0095, Manual default +0.080. At
# +0.598 a silent passage becomes a near-constant offset that eats
# headroom, clicks at any splice, and lets Scale peak normalize the DC
# rather than the music. Subtracting f(0) keeps the curve's asymmetry
# intact while returning the resting point to zero. Raw remains the
# default so v0.2 renders are reproducible.
if bias >= 0
    zeroShape = pos_Shape
else
    zeroShape = neg_Shape
endif
zeroOffset = tanh(bias * zeroShape) * output_Gain

appendInfoLine: "Zero-input output: ", fixed$(zeroOffset, 4)

# === Process Audio ===
selectObject: original
Copy: origName$ + "_Tube_" + presetName$
result = selected("Sound")

selectObject: result
meanBefore = Get mean: 0, 0, 0

# Boolean-trick formula (preserved from v0.1 for compatibility)
in$ = "(self * " + string$(drive) + " + " + string$(bias) + ")"
shape_logic$ = "( (" + in$ + " >= 0) * " + string$(pos_Shape)
    ... + " + (" + in$ + " < 0) * " + string$(neg_Shape) + " )"
formula$ = "tanh(" + in$ + " * " + shape_logic$ + ") * " + string$(output_Gain)

if bias_mode = 2
    formula$ = formula$ + " - " + string$(zeroOffset)
    biasDesc$ = "DC-compensated"
elsif bias_mode = 3
    biasDesc$ = "final mean removed"
else
    biasDesc$ = "raw DC-biased"
endif

selectObject: result
Formula: formula$

if bias_mode = 3
    selectObject: result
    Subtract mean
endif

selectObject: result
meanAfter = Get mean: 0, 0, 0
prePeak = Get absolute extremum: 0, 0, "None"
appendInfoLine: "Output mean: ", fixed$(meanBefore, 5), " (in) -> ", fixed$(meanAfter, 5), " (out)  [", biasDesc$, "]"
appendInfoLine: "Peak before level stage: ", fixed$(prePeak, 4)

# v0.3 (item 2): Output_Gain is a constant scalar applied AFTER tanh, so
# normalizing the peak divides it straight back out - 0.95 * g*f(x) /
# max|g*f(x)| = 0.95 * f(x) / max|f(x)| for every non-zero g. With
# Scale_peak on, gains of 0.2, 0.8 and 2.0 gave byte-identical output.
# The parameter was displayed and reported while controlling nothing.
# Conditional attenuation leaves Output_Gain meaningful until the result
# actually overshoots 0.95. Preserve is the default, matching Scale_peak = 0.
levelScale = 1
if output_level = 2
    if prePeak > 0.95
        selectObject: result
        Scale peak: 0.95
        levelScale = 0.95 / prePeak
        levelDesc$ = "attenuated to 0.95"
    else
        levelDesc$ = "unchanged"
    endif
elsif output_level = 3
    if prePeak > 0
        selectObject: result
        Scale peak: 0.95
        levelScale = 0.95 / prePeak
        levelDesc$ = "normalized to 0.95"
        appendInfoLine: "  NOTE: peak normalization divides Output_Gain back out - it no longer affects the result."
    else
        levelDesc$ = "silent; normalization skipped"
        appendInfoLine: "  NOTE: result peak is zero; normalization was skipped."
    endif
else
    levelDesc$ = "preserved"
    # v0.3 (item 5): tanh bounds the shaped signal to +/-1, so the peak
    # is bounded by |Output_Gain| - which is a `real` with no upper
    # limit. v0.2 measured the peak but never said anything about it.
    if prePeak > 1.0
        appendInfoLine: "  WARNING: output peak is ", fixed$(prePeak, 3), " - above 1.0 it will clip on playback or export."
    endif
endif
appendInfoLine: "Output level: ", levelDesc$
appendInfoLine: ""

# v0.3 (item 3): the panel used to be titled "Transfer function (input ->
# output)" while Scale peak was applied to the audio afterwards - so with
# normalization on, the same sample value could map to different final
# amplitudes in two files and no x-only curve could describe it. The
# curve now carries the render's actual peak scaling, and the title says
# what it does and does not include.
if bias_mode = 3
    curveTitle$ = "Transfer function (mean removal not shown)"
elsif levelScale <> 1
    curveTitle$ = "Transfer function (incl. this render's level scaling)"
else
    curveTitle$ = "Static transfer function (input -> output)"
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
    pageHeight = 8.0
    Line width: 1
    Colour: "Black"
    Solid line
    vizName$ = replace$(origName$, "_", "\_ ", 0)
    Erase all
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Asymmetric Soft Clipping v0.4.1##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.22, "half",
        ... vizName$
        ... + "  |  " + presetName$
        ... + "  |  Drive: " + fixed$(drive, 2)
        ... + "  |  Bias: " + fixed$(bias, 2)
        ... + "  |  Shape +/-: " + fixed$(pos_Shape, 2) + " / " + fixed$(neg_Shape, 2)
        ... + "  |  Out gain: " + fixed$(output_Gain, 2)
    
    # ----------------------------------------------------------
    # PANEL A: TRANSFER FUNCTION  (left, headline)
    # The defining diagnostic for any clipper.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4, 0.75, 4.60
    Select inner viewport: 0.60, 3.85, 0.95, 4.40
    
    # v0.3 (item 4): the curve used to be clamped to +/-1.4 in VALUE,
    # which the audio does not do. Output_Gain is a `real` with no upper
    # bound, so a manual gain of 3 gives audio reaching almost +/-3 while
    # the panel drew a flat plateau at +/-1.4. The extent is measured
    # first and the Y axis sized to fit.
    # (item 3): the curve now also carries levelScale, the actual peak
    # scaling applied to THIS render, so the panel describes the finished
    # output rather than the pre-normalization function. levelScale is a
    # pure scalar and therefore exactly representable; mean removal is
    # not, and is called out in the title when it is active.
    nPoints = 200
    yLim = 1.5
    for i from 0 to nPoints
        xs = -1.5 + (i / nPoints) * 3.0
        vs = xs * drive + bias
        if vs >= 0
            shs = pos_Shape
        else
            shs = neg_Shape
        endif
        ys = tanh(vs * shs) * output_Gain
        if bias_mode = 2
            ys = ys - zeroOffset
        endif
        ys = ys * levelScale
        if abs(ys) * 1.1 > yLim
            yLim = abs(ys) * 1.1
        endif
    endfor
    
    Axes: -1.5, 1.5, -yLim, yLim
    Paint rectangle: "{0.97, 0.97, 0.97}", -1.5, 1.5, -yLim, yLim
    
    # Grid: zero axes
    Colour: "{0.85, 0.85, 0.88}"
    Line width: 1
    Draw line: -1.5, 0, 1.5, 0
    Draw line: 0, -yLim, 0, yLim
    
    # y=x reference (no shaping)
    Dotted line
    Colour: "{0.65, 0.65, 0.70}"
    Draw line: -1.5, -1.5, 1.5, 1.5
    Solid line
    Font size: 6
    Text: -1.45, "left", -yLim * 0.93, "half", "y = x"
    
    # v0.3 (item 7): these were labelled "output ceiling/floor", but the
    # engine's ceiling before the level stage is +/-|Output_Gain| (tanh
    # saturates at 1), which is +/-0.9 on Warm Tube and +/-0.5 on Hard
    # Overdrive - and in Manual mode can sit above +/-1. These lines are
    # digital full scale, nothing more; the real ceiling is drawn
    # separately below.
    Colour: "{0.78, 0.65, 0.78}"
    Dotted line
    Draw line: -1.5, 1, 1.5, 1
    Draw line: -1.5, -1, 1.5, -1
    Solid line
    Font size: 6
    Colour: "{0.55, 0.30, 0.55}"
    Text: -1.45, "left", 1, "bottom", " +1 full scale"
    Text: -1.45, "left", -1, "top", " -1 full scale"
    
    # Static tanh output bounds. Raw mode is symmetric around zero.
    # DC compensation subtracts the raw zero-input offset, so the two
    # bounds move by the same amount. Final-mean removal is source-dependent
    # and therefore has no x-only static bound to draw here.
    if bias_mode = 1
        upperBound = abs(output_Gain) * levelScale
        lowerBound = -abs(output_Gain) * levelScale
        boundLabel$ = "tanh bounds"
    elsif bias_mode = 2
        upperBound = (abs(output_Gain) - zeroOffset) * levelScale
        lowerBound = (-abs(output_Gain) - zeroOffset) * levelScale
        boundLabel$ = "DC-comp. bounds"
    endif
    if bias_mode <> 3
        Colour: "{0.85, 0.72, 0.45}"
        Dotted line
        if upperBound > -yLim and upperBound < yLim
            Draw line: -1.5, upperBound, 1.5, upperBound
        endif
        if lowerBound > -yLim and lowerBound < yLim
            Draw line: -1.5, lowerBound, 1.5, lowerBound
        endif
        Solid line
        Font size: 6
        Colour: "{0.60, 0.45, 0.20}"
        if upperBound > -yLim and upperBound < yLim
            Text: 1.45, "right", upperBound, "bottom", boundLabel$
        endif
    endif
    
    # Bias offset reference (vertical line at the input level
    # where tanh argument is zero)
    if drive <> 0
        zeroIn = -bias / drive
        if zeroIn >= -1.5 and zeroIn <= 1.5
            Colour: "{0.55, 0.78, 0.55}"
            Dotted line
            Draw line: zeroIn, -yLim, zeroIn, yLim
            Solid line
            Font size: 6
            Colour: "{0.30, 0.55, 0.30}"
            Text: zeroIn, "left", -yLim * 0.93, "half", " sign flip"
        endif
    endif
    
    # Draw transfer function
    Colour: "{0.30, 0.45, 0.78}"
    Line width: 2
    
    # First point
    prev_x = -1.5
    val_prev = prev_x * drive + bias
    if val_prev >= 0
        shape_p = pos_Shape
    else
        shape_p = neg_Shape
    endif
    prev_y = tanh(val_prev * shape_p) * output_Gain
    if bias_mode = 2
        prev_y = prev_y - zeroOffset
    endif
    prev_y = prev_y * levelScale
    
    for i from 1 to nPoints
        curr_x = -1.5 + (i / nPoints) * 3.0
        val = curr_x * drive + bias
        if val >= 0
            shape = pos_Shape
        else
            shape = neg_Shape
        endif
        curr_y = tanh(val * shape) * output_Gain
        if bias_mode = 2
            curr_y = curr_y - zeroOffset
        endif
        curr_y = curr_y * levelScale
        Draw line: prev_x, prev_y, curr_x, curr_y
        prev_x = curr_x
        prev_y = curr_y
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Output (+/-" + fixed$(yLim, 2) + ")"
    Text bottom: "yes", "Input"
    
    # ----------------------------------------------------------
    # PANEL B: PARAMETER REPORT  (right, headline-height)
    # ----------------------------------------------------------
    Select outer viewport: 4, 8, 0.75, 4.60
    Select inner viewport: 4.45, 7.70, 0.95, 4.40
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
    
    # Section: Transfer
    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.93, "half", "Transfer parameters:"
    
    Font size: 7
    Colour: "{0.30, 0.45, 0.78}"
    Text: 0.10, "left", 0.84, "half", "Drive:    " + fixed$(drive, 2)
    Text: 0.10, "left", 0.76, "half", "Bias:     " + fixed$(bias, 3)
    
    # Section: Asymmetry
    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.65, "half", "Asymmetric shapes:"
    
    Font size: 7
    Colour: "{0.80, 0.40, 0.40}"
    Text: 0.10, "left", 0.56, "half", "Pos:      " + fixed$(pos_Shape, 2)
    Colour: "{0.40, 0.55, 0.78}"
    Text: 0.10, "left", 0.48, "half", "Neg:      " + fixed$(neg_Shape, 2)
    
    # Asymmetry indicator
    # v0.3 (item 8): "harder positive/negative" compares two numbers and
    # says nothing useful once one of them is negative - a negative shape
    # inverts that branch rather than softening it.
    if pos_Shape < 0 or neg_Shape < 0
        asymStr$ = "inverted branch (experimental)"
    elsif pos_Shape > neg_Shape
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
    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.28, "half", "Output:"
    
    Font size: 7
    Colour: "{0.40, 0.65, 0.40}"
    Text: 0.10, "left", 0.19, "half", "Gain:     " + fixed$(output_Gain, 2)
    
    Font size: 7
    Colour: "{0.55, 0.55, 0.55}"
    Text: 0.10, "left", 0.13, "half", "Level: " + levelDesc$
    if bias_mode = 1
        dcViz$ = "Raw y(0): " + fixed$(zeroOffset, 3)
    elsif bias_mode = 2
        dcViz$ = "Raw y(0): " + fixed$(zeroOffset, 3) + " -> effective 0"
    else
        dcViz$ = "Raw y(0): " + fixed$(zeroOffset, 3) + " | final source-dependent"
    endif
    Text: 0.10, "left", 0.06, "half", dcViz$
    
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
    Text: 2.10, "centre", 7.30, "half", curveTitle$
    Text: 6.10, "centre", 7.30, "half", "Parameter report"
    
    # ----------------------------------------------------------
    # PANEL C: OUTPUT WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.75
    Select inner viewport: 0.60, 7.70, 4.75, 5.68
    
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
    if nResultCh = 2
        Text top: "no", "Output  (blue=Ch 1  orange=Ch 2)"
    elsif nResultCh > 2
        Text top: "no", "Output  (Ch 1/2 shown; " + string$(nResultCh) + " channels preserved)"
    else
        Text top: "no", "Output (mono)"
    endif
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: SUMMARY BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.82, 6.58
    Select inner viewport: 0.60, 7.70, 5.88, 6.52
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + vizName$
        ... + "  |  Drive: " + fixed$(drive, 2)
        ... + "  |  Bias: " + fixed$(bias, 3)
        ... + "  |  Pos: " + fixed$(pos_Shape, 2)
        ... + "  |  Neg: " + fixed$(neg_Shape, 2)
    
    Text: 0.02, "left", 0.28, "half",
        ... "Output gain: " + fixed$(output_Gain, 2)
        ... + "  |  Asymmetry: " + asymStr$
        ... + "  |  Level: " + levelDesc$
        ... + "  |  DC: " + biasDesc$
        ... + "  |  Output: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 7
    Colour: "Black"
    Line width: 1

    # Restore complete page for Picture export / clipboard.
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# === Final ===
selectObject: result

appendInfoLine: "--- Final result ---"
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
