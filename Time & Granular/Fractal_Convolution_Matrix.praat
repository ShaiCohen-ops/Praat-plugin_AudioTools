# ============================================================
# Praat AudioTools - Fractal_Convolution_Matrix.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Fractal Convolution Matrix - creates self-similar textures
#   by convolving sound with delayed versions of itself at
#   multiple time scales. Each depth level adds echoes at
#   geometrically decreasing intervals (2^depth), creating
#   fractal-like temporal patterns.
#
# Changelog v0.3:
#   - FIX (audio): the per-depth amplitude scaling was linear
#     (1 - depth*reduction), which crosses zero and goes NEGATIVE for
#     deep levels (e.g. Extreme at depth >= 5; depth 10 -> -1.2, an
#     invert-and-amplify). Replaced with a geometric law
#     (1 - reduction)^depth, so deeper levels genuinely get quieter and
#     stay in (0,1). Changes the deep-level character of every preset.
#   - FIX (audio): the convolution taps used in-place self[col+shift],
#     which reads already-modified samples (backward taps) and lets each
#     tap feed the next -- an IIR feedback, not a convolution. Each depth
#     now snapshots its input and all taps read that fixed source
#     (object[snapshot,...]), making it a true feedback-free FIR.
#   - VISUALIZATION: rebuilt to the AudioTools suite 8x8 standard
#     (waveform pair + original/result spectrograms + summary).
#   - Added presetName$ (presets did not set it); preset name now
#     appears in the output filename.
#
# Changelog v0.2:
#   - Modern syntax
#   - Added visualization
#   - Fixed Formula interpolation
# ============================================================

form Fractal Convolution
    comment Select a Sound object first
    optionmenu Preset: 1
        option Custom
        option Subtle Fractal
        option Medium Fractal
        option Heavy Fractal
        option Extreme Fractal
    
    positive Tail_duration_s 2.0
    natural Fractal_depth 5
    natural Convolution_width 3
    positive Kernel_divisor 10
    positive Amplitude_reduction 0.15
    positive Scale_peak 0.90
    positive Fadeout_duration_s 1.0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Subtle Fractal
    tail_duration_s = 1.5
    fractal_depth = 3
    convolution_width = 2
    kernel_divisor = 12
    amplitude_reduction = 0.12
    scale_peak = 0.92
    fadeout_duration_s = 0.8
    presetName$ = "Subtle"
elsif preset = 3
    # Medium Fractal
    tail_duration_s = 2.0
    fractal_depth = 5
    convolution_width = 3
    kernel_divisor = 10
    amplitude_reduction = 0.15
    scale_peak = 0.90
    fadeout_duration_s = 1.0
    presetName$ = "Medium"
elsif preset = 4
    # Heavy Fractal
    tail_duration_s = 2.8
    fractal_depth = 7
    convolution_width = 4
    kernel_divisor = 8
    amplitude_reduction = 0.18
    scale_peak = 0.88
    fadeout_duration_s = 1.4
    presetName$ = "Heavy"
elsif preset = 5
    # Extreme Fractal
    tail_duration_s = 4.0
    fractal_depth = 10
    convolution_width = 5
    kernel_divisor = 6
    amplitude_reduction = 0.22
    scale_peak = 0.86
    fadeout_duration_s = 1.8
    presetName$ = "Extreme"
else
    presetName$ = "Custom"
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
sampling_rate = Get sampling frequency
channels = Get number of channels
originalDuration = Get total duration

# === Info ===
writeInfoLine: "=== Fractal Convolution Matrix v0.3 ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(originalDuration, 2), " s)"
appendInfoLine: ""
appendInfoLine: "Fractal depth: ", fractal_depth
appendInfoLine: "Convolution width: ", convolution_width
appendInfoLine: "Kernel divisor: ", kernel_divisor
appendInfoLine: ""

# === Create Silent Tail ===
if channels = 2
    Create Sound from formula: "silent_tail", 2, 0, tail_duration_s, sampling_rate, "0"
else
    Create Sound from formula: "silent_tail", 1, 0, tail_duration_s, sampling_rate, "0"
endif
silentTail = selected("Sound")

# === Concatenate ===
selectObject: original, silentTail
Concatenate
extended = selected("Sound")
Rename: "extended"

removeObject: silentTail

# === Copy for Processing ===
selectObject: extended
Copy: "fractal_work"
result = selected("Sound")

totalSamples = Get number of samples

# === Main Fractal Processing Loop ===
appendInfoLine: "Processing fractal depths..."
appendInfoLine: ""
appendInfoLine: "Depth | Scale | Kernel Size | Delays"
appendInfoLine: "------|-------|-------------|-------"

for depth from 1 to fractal_depth
    scaleFactor = 2 ^ depth
    kernelSize = round(totalSamples / (kernel_divisor * scaleFactor))
    
    # Info
    delayMs = kernelSize / sampling_rate * 1000
    appendInfoLine: "  ", depth, "   |  ", scaleFactor, "   |    ", kernelSize, "     | ", fixed$(delayMs, 1), " ms"
    
    # Snapshot this depth's input so every tap reads a FIXED source
    # (feedback-free FIR) instead of the accumulating in-place result.
    selectObject: result
    Copy: "fractal_snapshot"
    snapshot = selected("Sound")
    
    # Fractal convolution kernel (taps read the snapshot)
    selectObject: result
    for kernel from -convolution_width to convolution_width
        kernelWeight = 1 / (1 + abs(kernel))
        kernelShift = kernel * kernelSize
        depthFactor = depth + 2
        
        Formula: "self + if col + kernelShift >= 1 and col + kernelShift <= ncol then object['snapshot', row, col + kernelShift] * kernelWeight / depthFactor else 0 fi"
    endfor
    
    removeObject: snapshot
    
    # Fractal amplitude scaling (geometric: deep levels truly decrease,
    # stays in (0,1) instead of the old linear law going negative)
    selectObject: result
    ampScale = (1 - amplitude_reduction) ^ depth
    Formula: "self * ampScale"
endfor

# === Scale Peak ===
selectObject: result
Scale peak: scale_peak

# === Apply Fadeout ===
totalDuration = Get total duration
fadeStart = totalDuration - fadeout_duration_s

Formula: "if x > fadeStart then self * (0.5 + 0.5 * cos(pi * (x - fadeStart) / fadeout_duration_s)) else self fi"

Rename: original_name$ + "_fractal_" + presetName$

# === Cleanup ===
removeObject: extended

# === Visualization ===
if draw_visualization
    selectObject: result
    vizDur = Get total duration

    Erase all
    Select outer viewport: 0, 8, 0, 8
    Black
    Plain line

    # ---- TITLE BAR ----
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##FRACTAL CONVOLUTION MATRIX##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... original_name$
        ... + "  |  " + presetName$
        ... + "  |  depth " + string$(fractal_depth)
        ... + "  |  width " + string$(convolution_width)
        ... + "  |  " + fixed$(originalDuration, 2) + " s -> " + fixed$(vizDur, 2) + " s"

    # ---- ORIGINAL WAVEFORM (left) ----
    Select outer viewport: 0, 4.2, 0.75, 2.10
    Select inner viewport: 0.55, 4.00, 0.95, 1.98
    selectObject: original
    Colour: "{0.55, 0.55, 0.60}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Original"
    Font size: 6
    Text left: "yes", "Amp"

    # ---- RESULT WAVEFORM (right) ----
    Select outer viewport: 4.2, 8, 0.75, 2.10
    Select inner viewport: 4.55, 7.75, 0.95, 1.98
    selectObject: result
    Colour: "{0.20, 0.50, 0.70}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Fractal"
    Font size: 6
    Text left: "yes", "Amp"

    # ---- ORIGINAL SPECTROGRAM (left) ----
    Select outer viewport: 0, 4.2, 2.20, 4.40
    Select inner viewport: 0.55, 4.00, 2.40, 4.28
    selectObject: original
    if channels > 1
        origMono = Convert to mono
    else
        origMono = Copy: "fcm_orig_mono"
    endif
    selectObject: origMono
    To Spectrogram: 0.03, 5000, 0.01, 20, "Gaussian"
    origSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: origSpec, origMono
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Original spectrogram"
    Font size: 6
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"

    # ---- RESULT SPECTROGRAM (right, signature: fractal echo buildup) ----
    Select outer viewport: 4.2, 8, 2.20, 4.40
    Select inner viewport: 4.55, 7.75, 2.40, 4.28
    selectObject: result
    if channels > 1
        resMono = Convert to mono
    else
        resMono = Copy: "fcm_res_mono"
    endif
    selectObject: resMono
    To Spectrogram: 0.03, 5000, 0.01, 20, "Gaussian"
    resSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: resSpec, resMono
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Fractal spectrogram"
    Font size: 6
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"

    # ---- SUMMARY BAR ----
    Select outer viewport: 0, 8, 4.50, 5.20
    Select inner viewport: 0.55, 7.75, 4.57, 5.14
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + original_name$
        ... + "  |  depth " + string$(fractal_depth)
        ... + "  |  width " + string$(convolution_width)
        ... + "  |  divisor " + string$(kernel_divisor)
        ... + "  |  amp reduction " + fixed$(amplitude_reduction, 2)
    Text: 0.02, "left", 0.28, "half",
        ... "Tail " + fixed$(tail_duration_s, 1) + " s"
        ... + "  |  scale peak " + fixed$(scale_peak, 2)
        ... + "  |  fadeout " + fixed$(fadeout_duration_s, 1) + " s"
        ... + "  |  " + fixed$(originalDuration, 2) + " s -> " + fixed$(vizDur, 2) + " s"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# === Final Info ===
selectObject: result
finalDuration = Get total duration

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Original: ", fixed$(originalDuration, 2), " s"
appendInfoLine: "Result: ", fixed$(finalDuration, 2), " s"
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result