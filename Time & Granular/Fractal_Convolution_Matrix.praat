# ============================================================
# Praat AudioTools - Fractal_Convolution_Matrix.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
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
# Changelog v0.4:
#   DSP / correctness pass:
#   - CRITICAL: kernel is now causal. v0.3 used taps from -width..+width,
#     so half of the matrix read future samples (pre-echo/advance) although
#     the effect is documented as delayed self-copies. v0.4 uses delayed
#     taps only: x[n-kD].
#   - Kernel delay scales are derived from the ORIGINAL Sound length, not
#     the original+tail canvas. Tail_duration therefore changes only the
#     available decay space and no longer retunes every delay.
#   - Amplitude_reduction now controls only each NEW echo layer. In v0.3
#     it multiplied the entire result at every depth and was then largely
#     cancelled by final peak normalization.
#   - Removed the duplicated zero-shift kernel tap. Each depth is now an
#     explicit dry path plus a normalized bank of delayed taps.
#   - Snapshot access uses object ID instead of the temporary object name.
#   - Depths whose rounded delay is < 1 sample are skipped and reported.
#   - Added validation for amplitude reduction, scale peak, tail/fade time,
#     and a safe normalization path for silent input.
#   - Fadeout is clamped to the actual result duration; 0 disables it.
#   - Visualization spectrogram ceiling is min(5 kHz, Nyquist).
#   - Reports the theoretical cumulative fractal delay span and whether the
#     requested tail truncates that span.
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

form Fractal Convolution v0.4
    comment Select a Sound object first
    optionmenu Preset: 1
        option Custom
        option Subtle Fractal
        option Medium Fractal
        option Heavy Fractal
        option Extreme Fractal
    
    real Tail_duration_s 2.0
    natural Fractal_depth 5
    natural Convolution_width 3
    positive Kernel_divisor 10
    real Amplitude_reduction 0.15
    real Scale_peak 0.90
    real Fadeout_duration_s 1.0
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
originalSamples = Get number of samples
nyquist = sampling_rate / 2
vizMaxHz = min(5000, nyquist)

# === Validate ===
if tail_duration_s < 0
    exitScript: "Tail duration must be >= 0 s"
endif
if fractal_depth < 1
    exitScript: "Fractal depth must be at least 1"
endif
if convolution_width < 1
    exitScript: "Convolution width must be at least 1"
endif
if kernel_divisor <= 0
    exitScript: "Kernel divisor must be > 0"
endif
if fractal_depth > 30
    exitScript: "Fractal depth must not exceed 30"
endif
if convolution_width > 64
    exitScript: "Convolution width must not exceed 64"
endif
firstKernelSize = round(originalSamples / (kernel_divisor * 2))
if firstKernelSize < 1
    exitScript: "Kernel divisor is too large for this Sound: depth 1 would be shorter than one sample"
endif
if amplitude_reduction < 0 or amplitude_reduction >= 1
    exitScript: "Amplitude reduction must be in the range 0 <= value < 1"
endif
if scale_peak <= 0 or scale_peak > 1
    exitScript: "Scale peak must be > 0 and <= 1"
endif
if fadeout_duration_s < 0
    exitScript: "Fadeout duration must be >= 0 s"
endif

# === Info ===
writeInfoLine: "=== Fractal Convolution Matrix v0.4 ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(originalDuration, 2), " s)"
appendInfoLine: ""
appendInfoLine: "Fractal depth: ", fractal_depth
appendInfoLine: "Convolution width: ", convolution_width
appendInfoLine: "Kernel divisor: ", kernel_divisor
appendInfoLine: ""

# === Create Processing Canvas ===
# Tail duration supplies room for causal delayed copies. It must NOT be part
# of the delay-scale calculation (which is based on originalSamples only).
if tail_duration_s > 0
    Create Sound from formula: "silent_tail", channels, 0, tail_duration_s, sampling_rate, "0"
    silentTail = selected("Sound")

    # original is older in the Object list than silentTail, so Praat's
    # Object-list concatenation order is original -> tail.
    selectObject: original, silentTail
    Concatenate
    extended = selected("Sound")
    Rename: "extended"
    removeObject: silentTail
else
    selectObject: original
    extended = Copy: "extended"
endif

# === Copy for Processing ===
selectObject: extended
Copy: "fractal_work"
result = selected("Sound")

totalSamples = Get number of samples

# === Main Fractal Processing Loop ===
appendInfoLine: "Processing fractal depths..."
appendInfoLine: ""
appendInfoLine: "Depth | Layer gain | Base delay | Max tap delay"
appendInfoLine: "------|------------|------------|--------------"

# Normalize the delayed-tap bank so Convolution_width changes texture/density
# without automatically multiplying the total wet gain.
kernelWeightSum = 0
for kernel from 1 to convolution_width
    kernelWeightSum = kernelWeightSum + 1 / (1 + kernel)
endfor

activeDepths = 0
fractalSpanSamples = 0

for depth from 1 to fractal_depth
    scaleFactor = 2 ^ depth
    # IMPORTANT: delay scale is tied to the original source, not the tail.
    kernelSize = round(originalSamples / (kernel_divisor * scaleFactor))

    if kernelSize >= 1
        activeDepths = activeDepths + 1
        depthGain = (1 - amplitude_reduction) ^ depth
        baseDelayMs = kernelSize / sampling_rate * 1000
        maxTapDelaySamples = convolution_width * kernelSize
        maxTapDelayMs = maxTapDelaySamples / sampling_rate * 1000
        fractalSpanSamples = fractalSpanSamples + maxTapDelaySamples

        appendInfoLine: "  ", depth, "   |   ", fixed$(depthGain, 4), "   |  ", fixed$(baseDelayMs, 2), " ms |  ", fixed$(maxTapDelayMs, 2), " ms"

        # Snapshot the complete previous depth. This makes each stage a true
        # FIR convolution layer and also creates the self-similar cascade:
        # later depths convolve the echoes produced by earlier depths.
        selectObject: result
        snapshot = Copy: "fractal_snapshot"
        snapshotStr$ = string$(snapshot)

        # Start from the dry snapshot exactly once. The old zero-shift tap
        # duplicated it. Then add ONLY causal delayed taps from the snapshot.
        selectObject: result
        Formula: "object[" + snapshotStr$ + ", row, col]"

        for kernel from 1 to convolution_width
            kernelWeight = 1 / (1 + kernel)
            tapGain = depthGain * kernelWeight / kernelWeightSum
            kernelShift = kernel * kernelSize

            selectObject: result
            Formula: "self + if col - " + string$(kernelShift) + " >= 1 then object[" + snapshotStr$ + ", row, col - " + string$(kernelShift) + "] * " + fixed$(tapGain, 12) + " else 0 fi"
        endfor

        removeObject: snapshot
    else
        appendInfoLine: "  ", depth, "   |  skipped (delay < 1 sample)"
    endif
endfor

fractalSpan = fractalSpanSamples / sampling_rate
appendInfoLine: ""
appendInfoLine: "Active depth levels: ", activeDepths, "/", fractal_depth
appendInfoLine: "Theoretical cumulative delay span: ", fixed$(fractalSpan, 3), " s"
if tail_duration_s + 1 / sampling_rate < fractalSpan
    appendInfoLine: "Note: tail is shorter than the full theoretical delay span; late fractal echoes are intentionally truncated."
endif

# === Scale Peak ===
selectObject: result
resultPeak = Get absolute extremum: 0, 0, "Sinc70"
if resultPeak > 0
    Scale peak: scale_peak
endif

# === Apply Fadeout ===
totalDuration = Get total duration
effectiveFadeout = min(fadeout_duration_s, totalDuration)
if effectiveFadeout > 0
    fadeStart = totalDuration - effectiveFadeout
    Formula: "if x > fadeStart then self * (0.5 + 0.5 * cos(pi * (x - fadeStart) / effectiveFadeout)) else self fi"
endif

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
    To Spectrogram: 0.03, vizMaxHz, 0.01, 20, "Gaussian"
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
    To Spectrogram: 0.03, vizMaxHz, 0.01, 20, "Gaussian"
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
        ... + "  |  depth " + string$(activeDepths) + "/" + string$(fractal_depth)
        ... + "  |  width " + string$(convolution_width)
        ... + "  |  divisor " + string$(kernel_divisor)
        ... + "  |  layer reduction " + fixed$(amplitude_reduction, 2)
    Text: 0.02, "left", 0.28, "half",
        ... "Tail " + fixed$(tail_duration_s, 1) + " s"
        ... + "  |  fractal span " + fixed$(fractalSpan, 2) + " s"
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