# ============================================================
# Praat AudioTools - Adaptive_Transient_Decomposition.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.7 (2026) - aligned shared-mask decomposition + mechanism-first visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   LPC-residual-guided adaptive transient decomposition.
#   An LPC inverse-filtered residual is used ONLY as the detector signal.
#   A local fast/slow energy ratio drives a soft sigmoid mask, which is
#   applied to the ORIGINAL signal as:
#       transient = original * mask
#       sustain   = original * (1 - mask)
#   The detector is offline/acausal because Praat's Hann-band filters are
#   zero-phase frequency-domain filters. This is intentional for AudioTools.
#
# v0.7 fixes / changes:
#   - FIX: v0.6 padding could reorder the concatenated objects and shift the
#     decomposition by the pad duration. Padding is now sample-indexed.
#   - Stereo/multichannel outputs preserve the original channels and use ONE
#     shared detector mask derived from the strongest-RMS input channel.
#   - Stable dB-ratio calculation with epsilon in numerator and denominator.
#   - Burst padding is documented as a soft temporal extension, not a hard
#     morphological dilation.
#   - Pre-gain transient+sustain reconstruction is explicitly measured.
#   - 2x2 AudioTools visualization: detector, mask evolution, decomposition,
#     and QC/energy split.
#
# Usage:
#   Select exactly one Sound object and run this script.
# ============================================================

# --- Input validation ---
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

origId = selected("Sound")
origName$ = selected$("Sound")

form Adaptive Transient Decomposition v0.7
    comment === Presets ===
    optionmenu Preset: 1
        option Custom
        option Percussion (sharp attacks)
        option Piano (medium attacks)
        option Strings (soft attacks)
        option Speech (consonants)
        option Gentle (preserve sustain)
        option Aggressive (isolate transients)
    comment === Analysis ===
    positive LPC_order_per_kHz 2.0
    positive Analysis_window_ms 25.0
    positive Time_step_ms 5.0
    comment === Adaptive envelope detector ===
    positive Integration_ms 5.0
    positive Floor_rate_Hz 10.0
    real Threshold_dB 6.0
    positive Sigmoid_steepness 2.0
    real Burst_padding_ms 15.0
    comment (Burst padding is a soft temporal extension; 0 disables it)
    comment === Output ===
    real Transient_output_gain_dB 0.0
    comment (Post-decomposition gain; 0 dB preserves exact reconstruction)
    boolean Draw_visualization 1
endform

# --- Apply presets ---
if preset = 2
    lPC_order_per_kHz = 2.0
    analysis_window_ms = 20.0
    time_step_ms = 3.0
    integration_ms = 3.0
    floor_rate_Hz = 8.0
    threshold_dB = 4.0
    sigmoid_steepness = 3.0
    burst_padding_ms = 10.0
    presetName$ = "Percussion"
elsif preset = 3
    lPC_order_per_kHz = 2.5
    analysis_window_ms = 25.0
    time_step_ms = 5.0
    integration_ms = 5.0
    floor_rate_Hz = 10.0
    threshold_dB = 6.0
    sigmoid_steepness = 2.0
    burst_padding_ms = 20.0
    presetName$ = "Piano"
elsif preset = 4
    lPC_order_per_kHz = 3.0
    analysis_window_ms = 30.0
    time_step_ms = 8.0
    integration_ms = 8.0
    floor_rate_Hz = 5.0
    threshold_dB = 8.0
    sigmoid_steepness = 1.5
    burst_padding_ms = 25.0
    presetName$ = "Strings"
elsif preset = 5
    lPC_order_per_kHz = 2.0
    analysis_window_ms = 25.0
    time_step_ms = 5.0
    integration_ms = 4.0
    floor_rate_Hz = 12.0
    threshold_dB = 5.0
    sigmoid_steepness = 2.5
    burst_padding_ms = 15.0
    presetName$ = "Speech"
elsif preset = 6
    lPC_order_per_kHz = 2.0
    analysis_window_ms = 30.0
    time_step_ms = 8.0
    integration_ms = 10.0
    floor_rate_Hz = 5.0
    threshold_dB = 10.0
    sigmoid_steepness = 1.0
    burst_padding_ms = 30.0
    presetName$ = "Gentle"
elsif preset = 7
    lPC_order_per_kHz = 1.5
    analysis_window_ms = 15.0
    time_step_ms = 2.0
    integration_ms = 2.0
    floor_rate_Hz = 15.0
    threshold_dB = 3.0
    sigmoid_steepness = 4.0
    burst_padding_ms = 5.0
    presetName$ = "Aggressive"
else
    presetName$ = "Custom"
endif

if burst_padding_ms < 0
    burst_padding_ms = 0
endif

# --- Constants / input properties ---
epsilon = 1e-12
minDur = 0.1
padDur = 0.1
uid$ = string$(randomInteger(10000, 99999))

selectObject: origId
nChannels = Get number of channels
totalDur = Get total duration
sr = Get sampling frequency
nSamples = Get number of samples
origStart = Get start time
origEnd = Get end time

if totalDur < minDur
    exitScript: "Sound is too short (minimum " + fixed$(minDur, 2) + " s)."
endif

if totalDur < 0.5
    padDur = totalDur * 0.25
endif

# --- Choose the strongest channel for a shared detector mask ---
analysisChannel = 1
bestRms = -1
for ch from 1 to nChannels
    selectObject: origId
    if nChannels = 1
        tmpCh = Copy: "analysis_probe"
    else
        tmpCh = Extract one channel: ch
    endif
    tmpRms = Get root-mean-square: 0, 0
    if tmpRms > bestRms
        bestRms = tmpRms
        analysisChannel = ch
    endif
    removeObject: tmpCh
endfor

selectObject: origId
if nChannels = 1
    analysisId = Copy: "analysis_channel"
else
    analysisId = Extract one channel: analysisChannel
endif
Rename: "analysis_channel_" + uid$

# --- Build adaptive detector on the representative channel ---
if bestRms <= epsilon
    # Silence: a zero mask is the only meaningful decomposition.
    selectObject: analysisId
    maskId = Copy: "mask_final_" + uid$
    Formula: "0"
    lpcOrderUsed = 0
    padSamplesUsed = round(padDur * sr)
    if draw_visualization
        selectObject: maskId
        rawMaskViz = Copy: "mask_raw_viz_" + uid$
        selectObject: maskId
        scoreViz = Copy: "score_viz_" + uid$
    else
        rawMaskViz = 0
        scoreViz = 0
    endif
else
    @buildDetector: analysisId, padDur, uid$, draw_visualization
    maskId = buildDetector.maskId
    rawMaskViz = buildDetector.rawMaskViz
    scoreViz = buildDetector.scoreViz
    lpcOrderUsed = buildDetector.lpcOrder
    padSamplesUsed = buildDetector.padSamples
endif

# Detector analysis channel is no longer needed.
removeObject: analysisId

# --- Apply ONE shared mask to every original channel ---
maskStr$ = string$(maskId)

selectObject: origId
transBase = Copy: "transient_base_" + uid$
Formula: "self * object[" + maskStr$ + ", 1, col]"

selectObject: origId
sustId = Copy: "sustain_" + uid$
Formula: "self * (1 - object[" + maskStr$ + ", 1, col])"

# --- Reconstruction proof BEFORE optional transient output gain ---
transBaseStr$ = string$(transBase)
sustStr$ = string$(sustId)
selectObject: origId
reconErrorId = Copy: "reconstruction_error_" + uid$
Formula: "self - object[" + transBaseStr$ + ", row, col] - object[" + sustStr$ + ", row, col]"
reconMax = Get absolute extremum: 0, 0, "Sinc70"
removeObject: reconErrorId

# --- Component metrics before output gain ---
selectObject: origId
rmsOrig = Get root-mean-square: 0, 0
selectObject: transBase
rmsTransBase = Get root-mean-square: 0, 0
selectObject: sustId
rmsSust = Get root-mean-square: 0, 0
selectObject: maskId
maskMean = Get mean: 0, 0, 0

# --- Optional post-decomposition gain on transient output ---
transId = transBase
if transient_output_gain_dB <> 0
    selectObject: transId
    gainLinear = 10 ^ (transient_output_gain_dB / 20)
    gainStr$ = string$(gainLinear)
    Formula: "self * " + gainStr$
endif

selectObject: transId
rmsTransOut = Get root-mean-square: 0, 0
Rename: origName$ + "_transients"
selectObject: sustId
Rename: origName$ + "_sustain"

# --- Info ---
writeInfoLine: "=== Adaptive Transient Decomposition v0.7 ==="
appendInfoLine: "Input: ", origName$
appendInfoLine: "Channels preserved: ", nChannels
appendInfoLine: "Shared detector from strongest RMS channel: ", analysisChannel
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "LPC order used: ", lpcOrderUsed
appendInfoLine: "Threshold: ", fixed$(threshold_dB, 1), " dB"
appendInfoLine: "Soft burst extension: ", fixed$(burst_padding_ms, 1), " ms"
appendInfoLine: "Mean mask value: ", fixed$(maskMean, 4)
appendInfoLine: "Pre-gain reconstruction max error: ", string$(reconMax)
if transient_output_gain_dB <> 0
    appendInfoLine: "Transient output gain: ", fixed$(transient_output_gain_dB, 1), " dB (post decomposition)"
endif
appendInfoLine: "Detector note: envelope filters are zero-phase/acausal (offline analysis)."

# --- Visualization ---
if draw_visualization
    # Representative channel for source and both outputs.
    selectObject: origId
    if nChannels = 1
        vizOrig = Copy: "viz_original_" + uid$
    else
        vizOrig = Extract one channel: analysisChannel
    endif

    selectObject: transId
    if nChannels = 1
        vizTrans = Copy: "viz_transient_" + uid$
    else
        vizTrans = Extract one channel: analysisChannel
    endif

    selectObject: sustId
    if nChannels = 1
        vizSust = Copy: "viz_sustain_" + uid$
    else
        vizSust = Extract one channel: analysisChannel
    endif

    @drawVisualization: vizOrig, vizTrans, vizSust, scoreViz, rawMaskViz, maskId, origName$, presetName$, analysisChannel, lpcOrderUsed, reconMax, rmsOrig, rmsTransOut, rmsSust, maskMean

    removeObject: vizOrig, vizTrans, vizSust, scoreViz, rawMaskViz
endif

# Detector mask is internal after the visualization.
removeObject: maskId

# --- Final selection ---
selectObject: origId
plusObject: transId
plusObject: sustId

appendInfoLine: "Created: ", origName$, "_transients"
appendInfoLine: "Created: ", origName$, "_sustain"
appendInfoLine: "=== Done ==="

# ==============================================================================
# Procedure: buildDetector
# ==============================================================================
procedure buildDetector: .inputId, .pad, .id$, .keepViz
    selectObject: .inputId
    .sr = Get sampling frequency
    .dur = Get total duration
    .nSamples = Get number of samples
    .origStart = Get start time
    .origEnd = Get end time

    .analysisWindow = analysis_window_ms / 1000
    .timeStep = time_step_ms / 1000

    # Exact sample-indexed padding. This avoids Concatenate ordering errors.
    .padSamples = round(.pad * .sr)
    if .padSamples < 1
        .padSamples = 1
    endif
    .workSamples = .nSamples + 2 * .padSamples
    .workDur = .workSamples / .sr

    .inputStr$ = string$(.inputId)
    .padStr$ = string$(.padSamples)
    .nStr$ = string$(.nSamples)

    Create Sound from formula: "work_" + .id$, 1, 0, .workDur, .sr,
        ... "if col > " + .padStr$ + " and col <= " + .padStr$ + " + " + .nStr$ + " then object[" + .inputStr$ + ", 1, col - " + .padStr$ + "] else 0 fi"
    .workSnd = selected("Sound")

    # LPC inverse filtering: detector residual, not an output component.
    .nyquistKHz = (.sr / 2) / 1000
    .lpcOrder = round(.nyquistKHz * lPC_order_per_kHz + 2)
    if .lpcOrder < 2
        .lpcOrder = 2
    endif

    selectObject: .workSnd
    To LPC (autocorrelation): .lpcOrder, .analysisWindow, .timeStep, 50
    .lpcObj = selected("LPC")

    selectObject: .workSnd
    plusObject: .lpcObj
    Filter (inverse)
    .residual = selected("Sound")
    Rename: "residual_" + .id$
    removeObject: .lpcObj

    # Fast squared-residual envelope.
    selectObject: .residual
    .residSq = Copy: "resid_sq_" + .id$
    Formula: "self * self"

    .nyquist = .sr / 2
    .bwFast = 1000 / integration_ms
    if .bwFast > .nyquist - 1
        .bwFast = .nyquist - 1
    endif
    if .bwFast < 1
        .bwFast = 1
    endif
    .smoothFast = min(100, max(1, .bwFast / 2))
    Filter (pass Hann band): 0, .bwFast, .smoothFast
    .envFast = selected("Sound")
    Rename: "env_fast_" + .id$
    Formula: "sqrt(abs(self))"
    removeObject: .residSq

    # Slow local floor envelope.
    selectObject: .residual
    .residSqSlow = Copy: "resid_sq_slow_" + .id$
    Formula: "self * self"

    .floorCut = floor_rate_Hz
    if .floorCut > .nyquist - 1
        .floorCut = .nyquist - 1
    endif
    if .floorCut < 1
        .floorCut = 1
    endif
    .smoothSlow = min(20, max(1, .floorCut / 2))
    Filter (pass Hann band): 0, .floorCut, .smoothSlow
    .envSlow = selected("Sound")
    Rename: "env_slow_" + .id$
    Formula: "sqrt(abs(self))"
    removeObject: .residSqSlow

    # Adaptive detector score in dB: fast residual energy relative to local floor.
    .envSlowStr$ = string$(.envSlow)
    .epsStr$ = string$(epsilon)
    selectObject: .envFast
    .score = Copy: "score_db_" + .id$
    Formula: "20 * log10((self + " + .epsStr$ + ") / (object[" + .envSlowStr$ + ", 1, col] + " + .epsStr$ + "))"

    # Raw sigmoid mask. Clamp the argument only in the saturated tails.
    .steepStr$ = string$(sigmoid_steepness)
    .threshStr$ = string$(threshold_dB)
    selectObject: .score
    .rawMask = Copy: "raw_mask_" + .id$
    Formula: "1 / (1 + exp(-" + .steepStr$ + " * max(-20, min(20, self - " + .threshStr$ + "))))"

    # Soft temporal extension (legacy musical behavior, now named accurately).
    if burst_padding_ms > 0
        .bwPad = 1000 / burst_padding_ms
        if .bwPad > .nyquist - 1
            .bwPad = .nyquist - 1
        endif
        if .bwPad < 1
            .bwPad = 1
        endif
        .smoothPad = min(100, max(1, .bwPad / 2))
        selectObject: .rawMask
        Filter (pass Hann band): 0, .bwPad, .smoothPad
        .finalMaskPadded = selected("Sound")
        Rename: "mask_soft_" + .id$
        # Normalized legacy sigmoid: preserves the soft expansion but maps
        # exact zero to zero instead of imposing the old 0.269 mask floor.
        .padSig0 = 1 / (1 + exp(1))
        .padSig1 = 1 / (1 + exp(-9))
        .padSig0Str$ = string$(.padSig0)
        .padSigRangeStr$ = string$(.padSig1 - .padSig0)
        Formula: "max(0, min(1, ((1 / (1 + exp(-10 * max(-10, min(10, self - 0.1))))) - " + .padSig0Str$ + ") / " + .padSigRangeStr$ + "))"
    else
        selectObject: .rawMask
        .finalMaskPadded = Copy: "mask_soft_" + .id$
    endif

    # Crop the detector products by SAMPLE INDEX, never by concatenation order.
    .finalStr$ = string$(.finalMaskPadded)
    .rawStr$ = string$(.rawMask)
    .scoreStr$ = string$(.score)
    .outDur = .nSamples / .sr

    Create Sound from formula: "mask_final_" + .id$, 1, 0, .outDur, .sr,
        ... "object[" + .finalStr$ + ", 1, col + " + .padStr$ + "]"
    .maskId = selected("Sound")
    Shift times to: "start time", .origStart

    if .keepViz
        Create Sound from formula: "mask_raw_viz_" + .id$, 1, 0, .outDur, .sr,
            ... "object[" + .rawStr$ + ", 1, col + " + .padStr$ + "]"
        .rawMaskViz = selected("Sound")
        Shift times to: "start time", .origStart

        Create Sound from formula: "score_viz_" + .id$, 1, 0, .outDur, .sr,
            ... "max(-40, min(40, object[" + .scoreStr$ + ", 1, col + " + .padStr$ + "]))"
        .scoreViz = selected("Sound")
        Shift times to: "start time", .origStart
    else
        .rawMaskViz = 0
        .scoreViz = 0
    endif

    removeObject: .envFast, .envSlow, .score, .rawMask, .finalMaskPadded, .residual, .workSnd
endproc

# ==============================================================================
# Procedure: drawVisualization
# ==============================================================================
procedure drawVisualization: .origId, .transId, .sustId, .scoreId, .rawMaskId, .maskId, .name$, .preset$, .analysisCh, .lpcOrder, .reconMax, .rmsOrig, .rmsTrans, .rmsSust, .maskMean
    selectObject: .origId
    .tMin = Get start time
    .tMax = Get end time
    .origMax = Get maximum: 0, 0, "Sinc70"
    .origMin = Get minimum: 0, 0, "Sinc70"
    .ampMax = max(abs(.origMax), abs(.origMin))
    if .ampMax <= 0
        .ampMax = 1
    else
        .ampMax = .ampMax * 1.05
    endif

    # RMS ratios for the compact QC panel.
    .transRatio = .rmsTrans / (.rmsOrig + epsilon)
    .sustRatio = .rmsSust / (.rmsOrig + epsilon)
    .barMax = max(1, max(.transRatio, .sustRatio)) * 1.1

    # Score plotting range around the threshold, clipped to the stored +/-40 dB.
    .scoreLow = max(-40, threshold_dB - 18)
    .scoreHigh = min(40, threshold_dB + 18)
    if .scoreHigh <= .scoreLow
        .scoreLow = -20
        .scoreHigh = 20
    endif

    Erase all
    Colour: "Black"
    Line width: 1

    # --- Main title ---
    Select outer viewport: 0, 8, 0.00, 0.34
    Axes: 0, 1, 0, 1
    Font size: 14
    Text: 0.5, "centre", 0.5, "half", "Adaptive Transient Decomposition"

    # --- Process strip ---
    Select outer viewport: 0.35, 7.65, 0.35, 0.67
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.35, 0.35, 0.35}"
    .process$ = "strongest ch " + string$(.analysisCh) + " -> LPC residual -> fast/slow dB -> sigmoid -> soft pad -> shared mask -> x*m , x*(1-m)"
    Text: 0.5, "centre", 0.5, "half", .process$

    # Panel coordinates.
    .xL1 = 0.45
    .xL2 = 3.85
    .xR1 = 4.15
    .xR2 = 7.55
    .titleY1 = 0.78
    .titleY2 = 1.05
    .dataY1 = 1.08
    .dataY2 = 2.48
    .titleY3 = 2.72
    .titleY4 = 2.99
    .dataY3 = 3.02
    .dataY4 = 4.52

    # ==================== A: ADAPTIVE DETECTOR ====================
    Select outer viewport: .xL1, .xL2, .titleY1, .titleY2
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.5, "half", "A  ADAPTIVE DETECTOR"

    Select inner viewport: .xL1 + 0.32, .xL2 - 0.08, .dataY1 + 0.08, .dataY2 - 0.20
    Axes: .tMin, .tMax, .scoreLow, .scoreHigh
    Colour: "{0.92, 0.92, 0.92}"
    Draw line: .tMin, 0, .tMax, 0
    Colour: "{0.55, 0.55, 0.55}"
    Dotted line
    Draw line: .tMin, threshold_dB, .tMax, threshold_dB
    Solid line
    Colour: "{0.85, 0.35, 0.15}"
    Line width: 1.5
    selectObject: .scoreId
    Draw: .tMin, .tMax, .scoreLow, .scoreHigh, "no", "Curve"
    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 10, "yes", "yes", "no"
    Text left: "yes", "Fast/slow (dB)"
    Marks bottom: 3, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    Select inner viewport: .xL1 + 0.32, .xL2 - 0.08, .dataY1 + 0.08, .dataY2 - 0.20
    Axes: .tMin, .tMax, .scoreLow, .scoreHigh
    Font size: 6
    Text: .tMin + 0.02 * (.tMax-.tMin), "left", threshold_dB + 0.04*(.scoreHigh-.scoreLow), "half", "threshold"

    # ==================== B: MASK EVOLUTION ====================
    Select outer viewport: .xR1, .xR2, .titleY1, .titleY2
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.5, "half", "B  MASK EVOLUTION"

    Select inner viewport: .xR1 + 0.32, .xR2 - 0.08, .dataY1 + 0.08, .dataY2 - 0.20
    Axes: .tMin, .tMax, -0.05, 1.05
    Colour: "{0.72, 0.72, 0.72}"
    Line width: 1
    selectObject: .rawMaskId
    Draw: .tMin, .tMax, -0.05, 1.05, "no", "Curve"
    Colour: "{0.45, 0.20, 0.65}"
    Line width: 1.5
    selectObject: .maskId
    Draw: .tMin, .tMax, -0.05, 1.05, "no", "Curve"
    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks left: 3, "yes", "yes", "no"
    Text left: "yes", "Mask"
    Marks bottom: 3, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    Select inner viewport: .xR1 + 0.32, .xR2 - 0.08, .dataY1 + 0.08, .dataY2 - 0.20
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.45, 0.45, 0.45}"
    Text: 0.04, "left", 0.92, "half", "raw sigmoid"
    Colour: "{0.45, 0.20, 0.65}"
    Text: 0.30, "left", 0.92, "half", "final shared mask"

    # ==================== C: DECOMPOSITION ====================
    Select outer viewport: .xL1, .xL2, .titleY3, .titleY4
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.5, "half", "C  DECOMPOSITION"

    # Three lanes, same amplitude range and time axis.
    .laneX1 = .xL1 + 0.36
    .laneX2 = .xL2 - 0.08
    .laneH = 0.36
    .laneGap = 0.08
    .lane1Y1 = .dataY3 + 0.08
    .lane1Y2 = .lane1Y1 + .laneH
    .lane2Y1 = .lane1Y2 + .laneGap
    .lane2Y2 = .lane2Y1 + .laneH
    .lane3Y1 = .lane2Y2 + .laneGap
    .lane3Y2 = .lane3Y1 + .laneH

    Select inner viewport: .laneX1, .laneX2, .lane1Y1, .lane1Y2
    Axes: .tMin, .tMax, -.ampMax, .ampMax
    Colour: "{0.25, 0.25, 0.25}"
    selectObject: .origId
    Draw: .tMin, .tMax, -.ampMax, .ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box

    Select inner viewport: .laneX1, .laneX2, .lane2Y1, .lane2Y2
    Axes: .tMin, .tMax, -.ampMax, .ampMax
    Colour: "{0.75, 0.25, 0.20}"
    selectObject: .transId
    Draw: .tMin, .tMax, -.ampMax, .ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box

    Select inner viewport: .laneX1, .laneX2, .lane3Y1, .lane3Y2
    Axes: .tMin, .tMax, -.ampMax, .ampMax
    Colour: "{0.20, 0.45, 0.70}"
    selectObject: .sustId
    Draw: .tMin, .tMax, -.ampMax, .ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Marks bottom: 3, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"

    # Lane labels in a dedicated strip, not on top of the data.
    Select outer viewport: .xL1, .laneX1 - 0.04, .dataY3, .dataY4
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.25, 0.25, 0.25}"
    Text: 0.98, "right", 0.82, "half", "source"
    Colour: "{0.75, 0.25, 0.20}"
    Text: 0.98, "right", 0.50, "half", "transient"
    Colour: "{0.20, 0.45, 0.70}"
    Text: 0.98, "right", 0.18, "half", "sustain"

    # ==================== D: QC / ENERGY SPLIT ====================
    Select outer viewport: .xR1, .xR2, .titleY3, .titleY4
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.5, "half", "D  OUTPUT LEVEL / QC"

    Select inner viewport: .xR1 + 0.48, .xR2 - 0.10, .dataY3 + 0.12, .dataY4 - 0.28
    Axes: 0, .barMax, 0, 3
    Colour: "{0.92, 0.92, 0.92}"
    Paint rectangle: "{0.92, 0.92, 0.92}", 0, .barMax, 0, 3

    Colour: "{0.75, 0.25, 0.20}"
    Paint rectangle: "{0.75, 0.25, 0.20}", 0, .transRatio, 2.05, 2.55
    Colour: "{0.20, 0.45, 0.70}"
    Paint rectangle: "{0.20, 0.45, 0.70}", 0, .sustRatio, 1.20, 1.70
    Colour: "{0.45, 0.20, 0.65}"
    Paint rectangle: "{0.45, 0.20, 0.65}", 0, .maskMean, 0.35, 0.85

    Colour: "Black"
    Draw inner box
    Marks bottom: 3, "yes", "yes", "no"
    Text bottom: "yes", "Ratio to source RMS / mean mask"
    Select inner viewport: .xR1 + 0.48, .xR2 - 0.10, .dataY3 + 0.12, .dataY4 - 0.28
    Axes: 0, .barMax, 0, 3
    Font size: 6
    Text: 0.02 * .barMax, "left", 2.30, "half", "transient RMS"
    Text: 0.02 * .barMax, "left", 1.45, "half", "sustain RMS"
    Text: 0.02 * .barMax, "left", 0.60, "half", "mean mask"

    # Reconstruction proof in a separate line above the bars.
    Select outer viewport: .xR1 + 0.20, .xR2 - 0.08, .dataY4 - 0.28, .dataY4
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.25, 0.25, 0.25}"
    .proof$ = "pre-gain max |source - (transient+sustain)| = " + string$(.reconMax)
    Text: 0.5, "centre", 0.5, "half", .proof$

    # --- Summary bar ---
    Select outer viewport: 0.55, 7.45, 4.82, 5.18
    Axes: 0, 1, 0, 1
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0.12, 0.88
    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    .summary$ = .preset$ + " | ch " + string$(.analysisCh) + " | LPC " + string$(.lpcOrder) + " | threshold " + fixed$(threshold_dB, 1) + " dB | soft pad " + fixed$(burst_padding_ms, 1) + " ms | trans gain " + fixed$(transient_output_gain_dB, 1) + " dB | mask mean " + fixed$(.maskMean, 3)
    Text: 0.5, "centre", 0.5, "half", .summary$

    Font size: 10
    Colour: "Black"
    Line width: 1
endproc
