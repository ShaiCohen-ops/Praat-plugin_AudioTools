# ============================================================
# Praat AudioTools - Wavefolder_Foldback.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026) - Suite-standard visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Wavefolder (Foldback) - dedicated wavefolding distortion with
#   advanced controls. Signal folds back on itself when exceeding
#   threshold, creating rich harmonics. Features asymmetric
#   thresholds, multiple iterations, bipolar/unipolar modes,
#   and smoothing. Classic Buchla/Serge synthesizer effect.
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
#   - FIX: "Asymmetric Fold" preset was unipolar, so its asymmetry
#     had no effect (asymmetry only applies in bipolar mode). Made
#     the preset bipolar so it folds asymmetrically as named.
#   - FIX: the transfer-function plot now honors Bipolar_folding
#     (symmetric threshold in unipolar mode), matching the audio.
#
# Changelog v0.2:
#   - Added input check
#   - Fixed formula syntax (string interpolation)
#   - Added visualization
#   - Added info output
# ============================================================

form Wavefolder (Foldback) v0.4
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Soft Fold (Subtle)
        option Hard Fold (Aggressive)
        option Bipolar Fold
        option Asymmetric Fold
        option Multi-Fold (Harmonics)
        option Tape Saturation Style
        option Digital Crush
        option Oscillating Fold
    
    comment === Foldback Parameters ===
    real Threshold_(0-1) 0.5
    real Input_gain_dB 0.0
    real Fold_depth_(0-1) 1.0
    real Asymmetry_(-1_to_1) 0.0
    
    comment === Waveshaping ===
    natural Fold_iterations 1
    boolean Bipolar_folding 1
    real Smoothing_(0-1) 0.0
    
    comment === Output ===
    real Output_gain_dB 0.0
    boolean DC_offset_removal 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
name$ = selected$("Sound")

selectObject: original
duration = Get total duration
sr = Get sampling frequency
numChannels = Get number of channels

# === Apply Presets ===
if preset = 2
    # Soft Fold (Subtle)
    threshold = 0.7
    input_gain_dB = 3.0
    fold_depth = 0.6
    asymmetry = 0.0
    fold_iterations = 1
    bipolar_folding = 1
    smoothing = 0.3
    output_gain_dB = -3.0
    presetName$ = "SoftFold"
elsif preset = 3
    # Hard Fold (Aggressive)
    threshold = 0.3
    input_gain_dB = 12.0
    fold_depth = 1.0
    asymmetry = 0.0
    fold_iterations = 1
    bipolar_folding = 1
    smoothing = 0.0
    output_gain_dB = -6.0
    presetName$ = "HardFold"
elsif preset = 4
    # Bipolar Fold
    threshold = 0.5
    input_gain_dB = 6.0
    fold_depth = 1.0
    asymmetry = 0.0
    fold_iterations = 2
    bipolar_folding = 1
    smoothing = 0.1
    output_gain_dB = -4.0
    presetName$ = "Bipolar"
elsif preset = 5
    # Asymmetric Fold
    threshold = 0.6
    input_gain_dB = 8.0
    fold_depth = 0.85
    asymmetry = 0.6
    fold_iterations = 1
    bipolar_folding = 1
    smoothing = 0.15
    output_gain_dB = -5.0
    presetName$ = "Asymmetric"
elsif preset = 6
    # Multi-Fold (Harmonics)
    threshold = 0.4
    input_gain_dB = 10.0
    fold_depth = 1.0
    asymmetry = 0.0
    fold_iterations = 3
    bipolar_folding = 1
    smoothing = 0.0
    output_gain_dB = -8.0
    presetName$ = "MultiFold"
elsif preset = 7
    # Tape Saturation Style
    threshold = 0.65
    input_gain_dB = 4.0
    fold_depth = 0.5
    asymmetry = 0.2
    fold_iterations = 1
    bipolar_folding = 1
    smoothing = 0.5
    output_gain_dB = -2.0
    presetName$ = "TapeSat"
elsif preset = 8
    # Digital Crush
    threshold = 0.25
    input_gain_dB = 15.0
    fold_depth = 1.0
    asymmetry = 0.0
    fold_iterations = 2
    bipolar_folding = 0
    smoothing = 0.0
    output_gain_dB = -10.0
    presetName$ = "DigitalCrush"
elsif preset = 9
    # Oscillating Fold
    threshold = 0.55
    input_gain_dB = 7.0
    fold_depth = 0.9
    asymmetry = -0.3
    fold_iterations = 2
    bipolar_folding = 1
    smoothing = 0.2
    output_gain_dB = -5.0
    presetName$ = "Oscillating"
else
    presetName$ = "Custom"
endif

# Convert gains to linear
input_gain_linear = 10^(input_gain_dB/20)
output_gain_linear = 10^(output_gain_dB/20)

# Calculate asymmetric thresholds
if asymmetry >= 0
    threshold_pos = threshold * (1 - asymmetry)
    threshold_neg = threshold
else
    threshold_pos = threshold
    threshold_neg = threshold * (1 + asymmetry)
endif

# === Info ===
writeInfoLine: "=== Wavefolder (Foldback) v0.4 ==="
appendInfoLine: "Source: ", name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Threshold: ", threshold, " (pos: ", fixed$(threshold_pos, 2), ", neg: ", fixed$(threshold_neg, 2), ")"
appendInfoLine: "Input gain: ", input_gain_dB, " dB"
appendInfoLine: "Fold depth: ", fold_depth
appendInfoLine: "Asymmetry: ", asymmetry
appendInfoLine: "Iterations: ", fold_iterations
appendInfoLine: "Bipolar: ", if bipolar_folding then "yes" else "no" fi
appendInfoLine: "Smoothing: ", smoothing
appendInfoLine: "Output gain: ", output_gain_dB, " dB"
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Processing..."

selectObject: original
Copy: name$ + "_fold_" + presetName$
result = selected("Sound")

# Build formula strings
inGain_str$ = string$(input_gain_linear)
outGain_str$ = string$(output_gain_linear)
threshPos_str$ = string$(threshold_pos)
threshNeg_str$ = string$(threshold_neg)
thresh_str$ = string$(threshold)
depth_str$ = string$(fold_depth)

# Apply input gain
appendInfoLine: "  Applying input gain (", fixed$(input_gain_dB, 1), " dB)..."
Formula: "self * " + inGain_str$

# Apply foldback iterations
for iteration from 1 to fold_iterations
    appendInfoLine: "  Fold iteration ", iteration, "/", fold_iterations, "..."
    selectObject: result
    
    if bipolar_folding
        # Bipolar folding: fold positive and negative independently
        # Positive folding
        Formula: "if self > " + threshPos_str$ + " then " + threshPos_str$ + " - (self - " + threshPos_str$ + ") * " + depth_str$ + " else self fi"
        # Negative folding
        Formula: "if self < -" + threshNeg_str$ + " then -" + threshNeg_str$ + " + (abs(self) - " + threshNeg_str$ + ") * " + depth_str$ + " else self fi"
    else
        # Unipolar folding
        Formula: "if abs(self) > " + thresh_str$ + " then (if self > 0 then " + thresh_str$ + " - (self - " + thresh_str$ + ") * " + depth_str$ + " else -" + thresh_str$ + " + (abs(self) - " + thresh_str$ + ") * " + depth_str$ + " fi) else self fi"
    endif
endfor

# Apply smoothing (soft clipping)
if smoothing > 0
    appendInfoLine: "  Applying smoothing..."
    smooth_amount = smoothing * 2
    smooth_str$ = string$(smooth_amount)
    selectObject: result
    Formula: "if abs(self) > (1 - " + smooth_str$ + ") then self / (1 + abs(self) * " + smooth_str$ + ") else self fi"
endif

# Apply output gain
appendInfoLine: "  Applying output gain (", fixed$(output_gain_dB, 1), " dB)..."
selectObject: result
Formula: "self * " + outGain_str$

# DC offset removal
if dC_offset_removal
    appendInfoLine: "  Removing DC offset..."
    Subtract mean
endif

# Final normalization check
selectObject: result
max_amp = Get maximum: 0, 0, "Sinc70"
min_amp = Get minimum: 0, 0, "Sinc70"
peak = max(abs(max_amp), abs(min_amp))

if peak > 0.99
    appendInfoLine: "  Normalizing (peak was ", fixed$(peak, 2), ")..."
    peak_str$ = string$(peak)
    Formula: "self * 0.99 / " + peak_str$
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    pageHeight = 6.75
    Line width: 1
    Colour: "Black"
    Solid line
    vizName$ = replace$(name$, "_", "\_ ", 0)
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Wavefolder (Foldback) v0.4##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", vizName$ + " | " + presetName$ + " | threshold " + fixed$(threshold, 2) + " | " + string$(fold_iterations) + " folds | input gain " + fixed$(input_gain_dB, 1) + " dB"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.60, 7.70, 0.7, 1.4
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.6, 2.5
    Select inner viewport: 0.60, 7.70, 1.7, 2.4
    selectObject: result
    Colour: "{0.7, 0.5, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Folded"
    Text bottom: "yes", "Time (s)"
    
    # Zoomed comparison
    zoomDur = min(0.02, duration)
    
    Select outer viewport: 0, 4, 2.7, 3.8
    Select inner viewport: 0.60, 3.85, 2.8, 3.7
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, zoomDur, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Orig (zoom)"
    
    Select outer viewport: 4, 8, 2.7, 3.8
    Select inner viewport: 4.45, 7.70, 2.8, 3.7
    selectObject: result
    Colour: "{0.7, 0.5, 0.6}"
    Draw: 0, zoomDur, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Folded (zoom)"
    Text bottom: "yes", "Time (s)"
    
    # Transfer function (folding curve)
    Select outer viewport: 0, 4, 4.0, 5.5
    Select inner viewport: 0.60, 3.85, 4.1, 5.4

    # Measure the actual static shaping range before drawing it. The audio
    # does not clamp the folded value to +/-1.4, so the visualization must
    # not invent a plateau when a high-drive fold overshoots that range.
    nPoints = 300
    transferYLim = 1.5
    for p from 1 to nPoints
        tx = -1.2 + (p - 1) / (nPoints - 1) * 2.4
        ty = tx * input_gain_linear
        for iter from 1 to fold_iterations
            if bipolar_folding
                if ty > threshold_pos
                    ty = threshold_pos - (ty - threshold_pos) * fold_depth
                endif
                if ty < -threshold_neg
                    ty = -threshold_neg + (abs(ty) - threshold_neg) * fold_depth
                endif
            else
                if abs(ty) > threshold
                    if ty > 0
                        ty = threshold - (ty - threshold) * fold_depth
                    else
                        ty = -threshold + (abs(ty) - threshold) * fold_depth
                    endif
                endif
            endif
        endfor
        if smoothing > 0
            smooth_amount_viz = smoothing * 2
            if abs(ty) > (1 - smooth_amount_viz)
                ty = ty / (1 + abs(ty) * smooth_amount_viz)
            endif
        endif
        ty = ty * output_gain_linear
        if abs(ty) * 1.10 > transferYLim
            transferYLim = abs(ty) * 1.10
        endif
    endfor

    Axes: -1.5, 1.5, -transferYLim, transferYLim
    Paint rectangle: "{0.97, 0.97, 0.97}", -1.5, 1.5, -transferYLim, transferYLim

    # Grid
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: -1.5, 0, 1.5, 0
    Draw line: 0, -transferYLim, 0, transferYLim
    Dotted line
    Draw line: -1.2, -1.2, 1.2, 1.2
    Solid line

    # Threshold lines
    Colour: "{0.8, 0.7, 0.7}"
    Dotted line
    if bipolar_folding
        Draw line: threshold_pos, -transferYLim, threshold_pos, transferYLim
        Draw line: -threshold_neg, -transferYLim, -threshold_neg, transferYLim
    else
        Draw line: threshold, -transferYLim, threshold, transferYLim
        Draw line: -threshold, -transferYLim, -threshold, transferYLim
    endif
    Solid line

    # Draw the same static chain used by the audio before DC removal and
    # the final peak limiter: input gain -> folds -> smoothing -> output gain.
    Colour: "{0.65, 0.35, 0.60}"
    Line width: 2

    for p from 2 to nPoints
        x1 = -1.2 + (p - 2) / nPoints * 2.4
        x2 = -1.2 + (p - 1) / nPoints * 2.4
        
        # Apply input gain
        in1 = x1 * input_gain_linear
        in2 = x2 * input_gain_linear
        
        # Apply folding (simulate iterations)
        y1 = in1
        y2 = in2
        
        for iter from 1 to fold_iterations
            if bipolar_folding
                # Bipolar: independent pos/neg thresholds (asymmetric)
                if y1 > threshold_pos
                    y1 = threshold_pos - (y1 - threshold_pos) * fold_depth
                endif
                if y1 < -threshold_neg
                    y1 = -threshold_neg + (abs(y1) - threshold_neg) * fold_depth
                endif
                if y2 > threshold_pos
                    y2 = threshold_pos - (y2 - threshold_pos) * fold_depth
                endif
                if y2 < -threshold_neg
                    y2 = -threshold_neg + (abs(y2) - threshold_neg) * fold_depth
                endif
            else
                # Unipolar: symmetric threshold (matches audio)
                if abs(y1) > threshold
                    if y1 > 0
                        y1 = threshold - (y1 - threshold) * fold_depth
                    else
                        y1 = -threshold + (abs(y1) - threshold) * fold_depth
                    endif
                endif
                if abs(y2) > threshold
                    if y2 > 0
                        y2 = threshold - (y2 - threshold) * fold_depth
                    else
                        y2 = -threshold + (abs(y2) - threshold) * fold_depth
                    endif
                endif
            endif
        endfor
        
        # Apply smoothing exactly as in the audio path.
        if smoothing > 0
            smooth_amount_viz = smoothing * 2
            if abs(y1) > (1 - smooth_amount_viz)
                y1 = y1 / (1 + abs(y1) * smooth_amount_viz)
            endif
            if abs(y2) > (1 - smooth_amount_viz)
                y2 = y2 / (1 + abs(y2) * smooth_amount_viz)
            endif
        endif

        # Apply output gain. DC removal and the final peak limiter are
        # file-dependent stages and therefore are not part of this x-only curve.
        y1 = y1 * output_gain_linear
        y2 = y2 * output_gain_linear

        Draw line: x1, y1, x2, y2
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Output (+/-" + fixed$(transferYLim, 2) + ")"
    Text bottom: "yes", "Input"
    Text top: "no", "Static fold chain | before DC removal / final peak limiting"
    
    # Parameters
    Select outer viewport: 4, 8, 4.0, 5.5
    Select inner viewport: 4.45, 7.70, 4.1, 5.4
    
    Axes: 0, 4, 0, 8
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 4, 0, 8
    
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    
    Text: 0.2, "left", 7.5, "half", "Threshold: " + fixed$(threshold, 2)
    Text: 0.2, "left", 6.7, "half", "  Pos: " + fixed$(threshold_pos, 2) + " / Neg: " + fixed$(threshold_neg, 2)
    Text: 0.2, "left", 5.9, "half", "Input gain: " + fixed$(input_gain_dB, 1) + " dB"
    Text: 0.2, "left", 5.1, "half", "Fold depth: " + fixed$(fold_depth, 2)
    Text: 0.2, "left", 4.3, "half", "Asymmetry: " + fixed$(asymmetry, 2)
    Text: 0.2, "left", 3.5, "half", "Iterations: " + string$(fold_iterations)
    Text: 0.2, "left", 2.7, "half", "Bipolar: " + if bipolar_folding then "yes" else "no" fi
    Text: 0.2, "left", 1.9, "half", "Smoothing: " + fixed$(smoothing, 2)
    Text: 0.2, "left", 1.1, "half", "Output gain: " + fixed$(output_gain_dB, 1) + " dB"
    
    Colour: "Black"
    Draw inner box
    
    Font size: 7
    Colour: "Black"

    # === Summary strip ===
    Select outer viewport: 0, 8, 5.65, 6.70
    Select inner viewport: 0.60, 7.70, 5.73, 6.62
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    summary1$ = "##Input##  " + vizName$ + " | " + fixed$(duration, 2) + " s | " + string$(numChannels) + " ch | preset " + presetName$
    summary2$ = "##Folding##  threshold " + fixed$(threshold, 2) + " | pos/neg " + fixed$(threshold_pos, 2) + "/" + fixed$(threshold_neg, 2) + " | depth " + fixed$(fold_depth, 2) + " | asymmetry " + fixed$(asymmetry, 2) + " | iterations " + string$(fold_iterations)
    summary3$ = "##Output##  input gain " + fixed$(input_gain_dB, 1) + " dB | output gain " + fixed$(output_gain_dB, 1) + " dB | smoothing " + fixed$(smoothing, 2) + " | measured pre-limit peak " + fixed$(peak, 3)
    Text: 0.02, "left", 0.78, "half", summary1$
    Text: 0.02, "left", 0.50, "half", summary2$
    Text: 0.02, "left", 0.22, "half", summary3$
    Colour: "Black"
    Draw inner box

    # Restore complete page for Picture export / clipboard.
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
