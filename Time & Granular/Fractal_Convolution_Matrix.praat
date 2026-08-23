# ============================================================
# Praat AudioTools - Fractal_Convolution_Matrix.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.3 (2026) - Readable fractal delay matrix
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
#
# Changelog v0.4.3:
#   Visualization only.
#   - Reserved a dedicated annotation band above depth 1 so legend/base-delay
#     text cannot collide with the widest tap row in Extreme presets.
#
# Changelog v0.4.2:
#   Visualization only.
#   - Fractal delay matrix now uses log10(1 + delay_ms) on the horizontal axis.
#     The delays halve at every depth, so a linear axis collapsed the deep taps
#     near zero in Extreme presets. The log view gives each 2:1 scale change
#     comparable visual space and makes the self-similar structure legible.
#   - Added neutral guide lines and explicit 1/10/100/1000 ms scale labels.
#     Marker radii remain physical millimetres and gain-coded.
#
# Changelog v0.4.1:
#   Visualization only. DSP, convolution kernels and audio output are unchanged.
#   - Rebuilt Picture output to the current AudioTools suite structure:
#     Source -> Fractal delay matrix -> Output -> Summary.
#   - Replaced generic before/after spectrograms with a direct map of the
#     causal FIR kernel at every fractal depth. X = physical tap delay (ms),
#     row = depth, orange circles = delayed taps, gray = dry path, and circle
#     radius = tap gain. Marker sizes are specified in physical millimetres so
#     they remain legible in the Praat Picture window.
#   - Added shared Source/Output waveform scale, underscore-safe display names,
#     aligned panel geometry and a compact summary.
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

form Fractal Convolution v0.4.3
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
    Select outer viewport: 0, 8, 0, 7.10
    Black
    Plain line

    displayName$ = replace$(original_name$, "_", " ", 0)

    # Zero-based mono display copies. Visualization only.
    selectObject: original
    if channels > 1
        vizOrig = Convert to mono
    else
        vizOrig = Copy: "fcm_viz_source"
    endif
    selectObject: vizOrig
    vizOrigStart = Get start time
    Shift times by: -vizOrigStart

    selectObject: result
    if channels > 1
        vizOut = Convert to mono
    else
        vizOut = Copy: "fcm_viz_output"
    endif
    selectObject: vizOut
    vizOutStart = Get start time
    Shift times by: -vizOutStart

    # Shared source/output amplitude scale.
    selectObject: vizOrig
    origPeakViz = Get absolute extremum: 0, 0, "None"
    selectObject: vizOut
    outPeakViz = Get absolute extremum: 0, 0, "None"
    sharedPeak = max(origPeakViz, outPeakViz)
    if sharedPeak < 0.001
        sharedPeak = 0.001
    endif
    sharedAmp = 1.15 * sharedPeak

    # Reconstruct the exact active causal tap geometry used by the DSP.
    # Delays are sample-rounded exactly as in the processing loop.
    maxTapDelayMsViz = 0
    maxTapGainViz = 0
    lastBaseDelayMsViz = 0
    activeViz = 0
    for depth from 1 to fractal_depth
        scaleFactorViz = 2 ^ depth
        kernelSizeViz = round(originalSamples / (kernel_divisor * scaleFactorViz))
        if kernelSizeViz >= 1
            activeViz = activeViz + 1
            depthGainViz = (1 - amplitude_reduction) ^ depth
            baseDelayMsViz = kernelSizeViz / sampling_rate * 1000
            lastBaseDelayMsViz = baseDelayMsViz
            maxDelayThisViz = convolution_width * baseDelayMsViz
            if maxDelayThisViz > maxTapDelayMsViz
                maxTapDelayMsViz = maxDelayThisViz
            endif
            for kernel from 1 to convolution_width
                kernelWeightViz = 1 / (1 + kernel)
                tapGainViz = depthGainViz * kernelWeightViz / kernelWeightSum
                if tapGainViz > maxTapGainViz
                    maxTapGainViz = tapGainViz
                endif
            endfor
        endif
    endfor
    if maxTapDelayMsViz < 0.001
        maxTapDelayMsViz = 1
    endif
    if maxTapGainViz < 0.000001
        maxTapGainViz = 1
    endif

    mapXmax = log10(1 + 1.08 * maxTapDelayMsViz)
    mapYmin = 0.25
    mapYmax = activeViz + 1.65
    mapYspan = mapYmax - mapYmin

    # ----------------------------------------------------------
    # TITLE / SUBTITLE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Fractal Convolution Matrix##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -1.30, "half", displayName$ + "  |  " + presetName$ + "  |  depth " + string$(activeDepths) + "/" + string$(fractal_depth) + "  |  width " + string$(convolution_width)

    # ----------------------------------------------------------
    # SOURCE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.65, 1.90
    Select inner viewport: 0.55, 7.75, 0.82, 1.78
    Axes: 0, originalDuration, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, originalDuration, -sharedAmp, sharedAmp
    selectObject: vizOrig
    Colour: "{0.58, 0.58, 0.62}"
    Draw: 0, originalDuration, -sharedAmp, sharedAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "##Source##"
    Font size: 6
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"
    Axes: 0, originalDuration, -sharedAmp, sharedAmp
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.01 * originalDuration, "left", 0.82 * sharedAmp, "half", "delay scales derived from source length  |  divisor " + string$(kernel_divisor)

    # ----------------------------------------------------------
    # FRACTAL DELAY MATRIX
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 2.05, 4.55
    Select inner viewport: 0.55, 7.75, 2.22, 4.40
    Axes: 0, mapXmax, mapYmin, mapYmax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, mapXmax, mapYmin, mapYmax

    # Structural row guides, neutral by design.
    Colour: "{0.86, 0.86, 0.88}"
    for depth from 1 to fractal_depth
        scaleFactorViz = 2 ^ depth
        kernelSizeViz = round(originalSamples / (kernel_divisor * scaleFactorViz))
        if kernelSizeViz >= 1
            rowIndexViz = 0
            for d2 from 1 to depth
                kernelSizeD2 = round(originalSamples / (kernel_divisor * (2 ^ d2)))
                if kernelSizeD2 >= 1
                    rowIndexViz = rowIndexViz + 1
                endif
            endfor
            rowY = activeViz - rowIndexViz + 1
            Draw line: 0, rowY, mapXmax, rowY
        endif
    endfor

    # Causal FIR taps. Colour has one meaning only: orange = delayed echo tap.
    # Radius is physical (mm) and gain-coded, but never allowed to become tiny.
    activeRow = 0
    for depth from 1 to fractal_depth
        scaleFactorViz = 2 ^ depth
        kernelSizeViz = round(originalSamples / (kernel_divisor * scaleFactorViz))
        if kernelSizeViz >= 1
            activeRow = activeRow + 1
            rowY = activeViz - activeRow + 1
            depthGainViz = (1 - amplitude_reduction) ^ depth
            baseDelayMsViz = kernelSizeViz / sampling_rate * 1000
            maxDelayThisViz = convolution_width * baseDelayMsViz

            # Dry path, present once at every stage.
            Paint circle (mm): "{0.58, 0.58, 0.62}", 0, rowY, 1.00

            # Stage line makes the causal direction readable at a glance.
            Colour: "{0.70, 0.70, 0.73}"
            Line width: 1.1
            Draw line: 0, rowY, log10(1 + maxDelayThisViz), rowY
            Line width: 1

            for kernel from 1 to convolution_width
                kernelWeightViz = 1 / (1 + kernel)
                tapGainViz = depthGainViz * kernelWeightViz / kernelWeightSum
                gainNormViz = tapGainViz / maxTapGainViz
                markerRadiusViz = 0.95 + 0.85 * sqrt(max(0, gainNormViz))
                if markerRadiusViz < 0.95
                    markerRadiusViz = 0.95
                endif
                if markerRadiusViz > 1.80
                    markerRadiusViz = 1.80
                endif
                tapDelayMsViz = kernel * baseDelayMsViz
                tapX = log10(1 + tapDelayMsViz)
                Paint circle (mm): "{0.88, 0.48, 0.20}", tapX, rowY, markerRadiusViz
            endfor
        endif
    endfor

    # Log-delay scale guides. The transform is log10(1 + delay_ms);
    # labels report physical milliseconds.
    Colour: "{0.80, 0.80, 0.82}"
    Dotted line
    for tickIndex from 1 to 4
        if tickIndex = 1
            tickMs = 1
        elsif tickIndex = 2
            tickMs = 10
        elsif tickIndex = 3
            tickMs = 100
        else
            tickMs = 1000
        endif
        tickX = log10(1 + tickMs)
        if tickX < mapXmax
            Draw line: tickX, mapYmin, tickX, activeViz + 0.20
        endif
    endfor
    Solid line

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "##Fractal delay matrix##"
    Font size: 6
    Text left: "yes", "Depth  (1 at top)"
    Text bottom: "yes", "Causal tap delay (ms, logarithmic spacing)"
    Axes: 0, mapXmax, mapYmin, mapYmax
    Colour: "{0.30, 0.30, 0.30}"
    annotationY = activeViz + 1.18
    Text: 0.01 * mapXmax, "left", annotationY, "half", "orange = delayed tap  |  gray = dry path  |  radius = tap gain  |  log delay exposes the 2:1 fractal scale"

    # A compact scale cue at top right: first and deepest active base delay.
    if activeViz > 0
        firstKernelViz = round(originalSamples / (kernel_divisor * 2))
        firstBaseDelayMsViz = firstKernelViz / sampling_rate * 1000
        Text: 0.99 * mapXmax, "right", annotationY, "half", "base delay " + fixed$(firstBaseDelayMsViz, 2) + " -> " + fixed$(lastBaseDelayMsViz, 2) + " ms"
    endif

    Colour: "{0.42, 0.42, 0.44}"
    Font size: 5
    for tickIndex from 1 to 4
        if tickIndex = 1
            tickMs = 1
        elsif tickIndex = 2
            tickMs = 10
        elsif tickIndex = 3
            tickMs = 100
        else
            tickMs = 1000
        endif
        tickX = log10(1 + tickMs)
        if tickX < mapXmax
            Text: tickX, "centre", mapYmin + 0.035 * mapYspan, "half", string$(tickMs)
        endif
    endfor
    Font size: 6

    # ----------------------------------------------------------
    # OUTPUT
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.70, 5.95
    Select inner viewport: 0.55, 7.75, 4.87, 5.83
    Axes: 0, vizDur, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, vizDur, -sharedAmp, sharedAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, vizDur, 0
    selectObject: vizOut
    Colour: "{0.25, 0.50, 0.82}"
    Draw: 0, vizDur, -sharedAmp, sharedAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "yes", "##Output##"
    Font size: 6
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"
    Axes: 0, vizDur, -sharedAmp, sharedAmp
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.01 * vizDur, "left", 0.82 * sharedAmp, "half", "causal self-convolution cascade  |  tail " + fixed$(tail_duration_s, 1) + " s  |  fadeout " + fixed$(effectiveFadeout, 1) + " s"

    # ----------------------------------------------------------
    # SUMMARY
    # ----------------------------------------------------------
    if tail_duration_s + 1 / sampling_rate < fractalSpan
        tailState$ = "tail truncates theoretical span"
    else
        tailState$ = "tail contains theoretical span"
    endif

    Select outer viewport: 0, 8, 6.10, 7.05
    Select inner viewport: 0.30, 7.80, 6.17, 6.98
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "{0.48, 0.48, 0.48}"
    Draw rectangle: 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.80, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.49, "half", presetName$ + "  |  depth " + string$(activeDepths) + "/" + string$(fractal_depth) + "  |  width " + string$(convolution_width) + "  |  divisor " + string$(kernel_divisor) + "  |  layer reduction " + fixed$(amplitude_reduction, 2) + "  |  scale peak " + fixed$(scale_peak, 2)
    Text: 0.02, "left", 0.18, "half", "fractal span " + fixed$(fractalSpan, 3) + " s  |  " + tailState$ + "  |  source " + fixed$(originalDuration, 2) + " s  ->  output " + fixed$(vizDur, 2) + " s"

    Font size: 10
    Colour: "Black"
    Line width: 1

    removeObject: vizOrig, vizOut
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