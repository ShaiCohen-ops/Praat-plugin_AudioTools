# ============================================================
# Praat AudioTools - Zero_Crossing_Rate.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Zero Crossing Rate (ZCR) - frame-by-frame analysis of the
#   rate at which the signal crosses zero. High ZCR indicates
#   noisy/unvoiced content; low ZCR indicates voiced/tonal content.
#   Uses Praat's built-in PointProcess zero-crossing detection
#   (C-level, no per-sample script loop) for efficiency.
#   Outputs a ZCR time-series curve and global statistics.
#
# Changelog v1.1:
#   - Stereo/multichannel analysis uses the strongest-RMS channel instead of mono fold-down.
#   - Frame times respect the Sound time origin; exported ZCR Sound is aligned to frame centres.
#   - ZCR units are reported as crossings/s, not spectral Hz.
#   - Low/high ZCR is presented as a descriptive heuristic rather than a V/U classifier.
#   - Visualization uses the representative channel, explicit symmetric waveform scale,
#     actual Sound time coordinates, and separated title/metadata strips.
#
# Features:
#   - Frame-by-frame ZCR analysis (crossings/sec)
#   - Fast: uses To PointProcess (zeroes) + Count points
#   - 5 analysis presets (Fine → Coarse)
#   - Low/high ZCR interpretation threshold (heuristic)
#   - Full visualization: waveform, ZCR curve, histogram
#   - Exports ZCR curve as a Sound object for further use
#
# Usage:
#   Select a Sound object in Praat and run this script.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
sound_tmin = Get start time
sound_tmax = Get end time
duration = sound_tmax - sound_tmin
sampleRate = Get sampling frequency
numChannels = Get number of channels

form Zero Crossing Rate (ZCR)
    comment === Analysis Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Fine (10ms window, 2.5ms hop)
        option Standard (20ms window, 5ms hop)
        option Speech (30ms window, 10ms hop)
        option Coarse (50ms window, 20ms hop)
        option Ultra-Fine (5ms window, 1ms hop)

    comment === Analysis Parameters ===
    positive Window_duration_ms 20
    positive Hop_duration_ms 5

    comment === Interpretation Threshold ===
    positive Threshold_crossings_per_s 3000
    comment (High ZCR often noisy/unvoiced; heuristic only)

    comment === Output ===
    boolean Export_ZCR_curve 1
    boolean Draw_visualization 1
    boolean Play_result 0
endform

# === Apply Presets ===
if preset = 2
    window_duration_ms = 10
    hop_duration_ms = 2.5
    presetName$ = "Fine"
elsif preset = 3
    window_duration_ms = 20
    hop_duration_ms = 5
    presetName$ = "Standard"
elsif preset = 4
    window_duration_ms = 30
    hop_duration_ms = 10
    presetName$ = "Speech"
elsif preset = 5
    window_duration_ms = 50
    hop_duration_ms = 20
    presetName$ = "Coarse"
elsif preset = 6
    window_duration_ms = 5
    hop_duration_ms = 1
    presetName$ = "UltraFine"
else
    presetName$ = "Custom"
endif

windowSec = window_duration_ms / 1000
hopSec = hop_duration_ms / 1000

# Validate
if windowSec > duration
    windowSec = duration
endif
if hopSec > windowSec
    hopSec = windowSec / 4
endif

# === Representative analysis channel ===
# Avoid stereo fold-down: anti-phase or decorrelated channels can cancel and
# create an artificial zero-crossing pattern. Analyse the strongest RMS channel.
analysis_channel = 1
if numChannels > 1
    best_rms = -1
    for ch from 1 to numChannels
        selectObject: original
        tmp_channel = Extract one channel: ch
        channel_rms = Get root-mean-square: sound_tmin, sound_tmax
        if channel_rms > best_rms
            best_rms = channel_rms
            analysis_channel = ch
        endif
        removeObject: tmp_channel
    endfor
    selectObject: original
    workSound = Extract one channel: analysis_channel
else
    selectObject: original
    workSound = Copy: "work_zcr"
endif

# ============================================================
# ZCR ANALYSIS
# ============================================================

clearinfo
writeInfoLine: "=== Zero Crossing Rate (ZCR) ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(duration, 2), " s, ", sampleRate, " Hz)"
if numChannels > 1
    appendInfoLine: "Analysis channel: ", analysis_channel, " of ", numChannels, " (strongest RMS)"
endif
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Window: ", fixed$(window_duration_ms, 1), " ms  |  Hop: ", fixed$(hop_duration_ms, 1), " ms"
appendInfoLine: ""

# Find all zero crossings using Praat's C-level detection
selectObject: workSound
ppZeros = To PointProcess (zeroes): 1, "yes", "yes"

selectObject: ppZeros
totalZeroCrossings = Get number of points

appendInfoLine: "Total zero crossings: ", totalZeroCrossings
globalZCR = totalZeroCrossings / duration
appendInfoLine: "Global ZCR: ", fixed$(globalZCR, 1), " crossings/s"
appendInfoLine: ""

# Frame-by-frame ZCR
nFrames = floor((duration - windowSec) / hopSec) + 1
if nFrames < 1
    nFrames = 1
endif

appendInfoLine: "Analysing ", nFrames, " frames..."

# Store ZCR values
for f from 1 to nFrames
    tStart = sound_tmin + (f - 1) * hopSec
    tEnd = tStart + windowSec
    if tEnd > sound_tmax
        tEnd = sound_tmax
    endif
    tMid = (tStart + tEnd) / 2

    selectObject: ppZeros
    # Get first point at or after tStart, last point at or before tEnd
    hiIdx = Get high index: tStart
    loIdx = Get low index: tEnd
    if hiIdx > 0 and loIdx > 0 and loIdx >= hiIdx
        nCrossings = loIdx - hiIdx + 1
    else
        nCrossings = 0
    endif
    frameDur = tEnd - tStart
    if frameDur > 0
        zcrVal[f] = nCrossings / frameDur
    else
        zcrVal[f] = 0
    endif
    zcrTime[f] = tMid
endfor

# Compute statistics
zcrMin = zcrVal[1]
zcrMax = zcrVal[1]
zcrSum = 0
lowZcrFrames = 0
highZcrFrames = 0

for f from 1 to nFrames
    zcrSum = zcrSum + zcrVal[f]
    if zcrVal[f] < zcrMin
        zcrMin = zcrVal[f]
    endif
    if zcrVal[f] > zcrMax
        zcrMax = zcrVal[f]
    endif
    if zcrVal[f] < threshold_crossings_per_s
        lowZcrFrames = lowZcrFrames + 1
    else
        highZcrFrames = highZcrFrames + 1
    endif
endfor

zcrMean = zcrSum / nFrames

# Standard deviation
zcrVarSum = 0
for f from 1 to nFrames
    zcrVarSum = zcrVarSum + (zcrVal[f] - zcrMean)^2
endfor
zcrStdDev = sqrt(zcrVarSum / nFrames)

lowZcrPct = lowZcrFrames / nFrames * 100
highZcrPct = highZcrFrames / nFrames * 100

appendInfoLine: ""
appendInfoLine: "=== Statistics ==="
appendInfoLine: "  Mean ZCR:  ", fixed$(zcrMean, 1), " crossings/s"
appendInfoLine: "  Std Dev:   ", fixed$(zcrStdDev, 1)
appendInfoLine: "  Min ZCR:   ", fixed$(zcrMin, 1)
appendInfoLine: "  Max ZCR:   ", fixed$(zcrMax, 1)
appendInfoLine: ""
appendInfoLine: "  Interpretation threshold: ", fixed$(threshold_crossings_per_s, 0), " crossings/s"
appendInfoLine: "  Low-ZCR frames:  ", lowZcrFrames, " (", fixed$(lowZcrPct, 1), "%)"
appendInfoLine: "  High-ZCR frames: ", highZcrFrames, " (", fixed$(highZcrPct, 1), "%)"
appendInfoLine: "  Note: low/high ZCR is descriptive; it is not a stand-alone voiced/unvoiced classifier."
appendInfoLine: ""

# ============================================================
# EXPORT ZCR CURVE AS SOUND OBJECT
# ============================================================

if export_ZCR_curve
    # Store ZCR values as a Sound object (1 sample per frame)
    # so it can be queried, drawn, or exported
    zcrSR = 1 / hopSec
    # Sound sample centres must coincide with the actual ZCR frame centres.
    zcr_xmin = zcrTime[1] - hopSec / 2
    zcr_xmax = zcr_xmin + nFrames * hopSec
    Create Sound from formula: "ZCR_" + originalName$, 1, zcr_xmin, zcr_xmax, zcrSR, "0"
    zcrSound = selected("Sound")
    zcrNs = Get number of samples

    for f from 1 to min(nFrames, zcrNs)
        Set value at sample number: 1, f, zcrVal[f]
    endfor
endif

# PointProcess is no longer needed; keep workSound for the visualization.
removeObject: ppZeros

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    Select outer viewport: 0, 8, 0, 8

    # ----------------------------------------------------------
    # Title + metadata in independent strips (prevents collisions)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.00, 0.34
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.50, "half", "##Zero Crossing Rate (ZCR)##"

    Select outer viewport: 0, 8, 0.34, 0.62
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.52, "half",
        ... originalName$ + "  |  " + presetName$
        ... + "  |  win=" + fixed$(window_duration_ms, 0) + "ms"
        ... + "  hop=" + fixed$(hop_duration_ms, 1) + "ms"
        ... + "  |  " + string$(nFrames) + " frames"

    # ----------------------------------------------------------
    # Input waveform
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.66, 1.66
    Select inner viewport: 0.55, 7.65, 0.71, 1.61
    selectObject: workSound
    wavePeak = Get absolute extremum: sound_tmin, sound_tmax, "Sinc70"
    if wavePeak = undefined or wavePeak <= 0
        wavePeak = 1
    endif
    wavePeak = wavePeak * 1.03
    Colour: "{0.55, 0.55, 0.55}"
    Draw: sound_tmin, sound_tmax, -wavePeak, wavePeak, "no", "Curve"
    Select inner viewport: 0.55, 7.65, 0.71, 1.61
    Axes: sound_tmin, sound_tmax, -wavePeak, wavePeak
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Amp"
    Text top: "no", "Analysis-channel waveform"

    # ----------------------------------------------------------
    # ZCR curve over time
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 1.74, 3.54
    Select inner viewport: 0.55, 7.65, 1.84, 3.44

    zcrDisplayMax = zcrMax * 1.15
    if zcrDisplayMax < 100
        zcrDisplayMax = 100
    endif

    Axes: sound_tmin, sound_tmax, 0, zcrDisplayMax
    Paint rectangle: "{0.96, 0.96, 0.96}", sound_tmin, sound_tmax, 0, zcrDisplayMax

    # V/U threshold line
    if threshold_crossings_per_s < zcrDisplayMax
        Colour: "{0.82, 0.55, 0.55}"
        Dotted line
        Line width: 1
        Draw line: sound_tmin, threshold_crossings_per_s, sound_tmax, threshold_crossings_per_s
        Solid line
        Font size: 5
        Text: sound_tmin + duration * 0.99, "right", threshold_crossings_per_s + zcrDisplayMax * 0.03, "half",
            ... "threshold " + fixed$(threshold_crossings_per_s, 0)
    endif

    # Mean line
    Colour: "{0.55, 0.72, 0.55}"
    Dotted line
    Draw line: sound_tmin, zcrMean, sound_tmax, zcrMean
    Solid line
    Font size: 5
    Text: sound_tmin + duration * 0.01, "left", zcrMean + zcrDisplayMax * 0.03, "half",
        ... "mean=" + fixed$(zcrMean, 0)

    # ZCR curve — fill voiced (below threshold) in blue, unvoiced in red
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1.5
    for f from 2 to nFrames
        if zcrVal[f] < threshold_crossings_per_s
            Colour: "{0.25, 0.50, 0.82}"
        else
            Colour: "{0.82, 0.40, 0.30}"
        endif
        Draw line: zcrTime[f-1], zcrVal[f-1], zcrTime[f], zcrVal[f]
    endfor

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Crossings/s"
    Text bottom: "yes", "Time (s)"
    Text top: "no",
        ... "ZCR curve  (blue = low ZCR,  red = high ZCR)"

    # ----------------------------------------------------------
    # ZCR histogram (left half)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.1, 3.62, 5.02
    Select inner viewport: 0.55, 3.85, 3.72, 4.92

    # Build histogram (20 bins)
    nHistBins = 20
    histBinWidth = zcrDisplayMax / nHistBins
    for hb from 1 to nHistBins
        histCount[hb] = 0
    endfor
    for f from 1 to nFrames
        hb = floor(zcrVal[f] / histBinWidth) + 1
        if hb > nHistBins
            hb = nHistBins
        endif
        if hb < 1
            hb = 1
        endif
        histCount[hb] = histCount[hb] + 1
    endfor
    histMax = 0
    for hb from 1 to nHistBins
        if histCount[hb] > histMax
            histMax = histCount[hb]
        endif
    endfor
    if histMax < 1
        histMax = 1
    endif

    Axes: 0, zcrDisplayMax, 0, histMax * 1.15
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, zcrDisplayMax, 0, histMax * 1.15

    # Low/high ZCR threshold line on histogram
    if threshold_crossings_per_s < zcrDisplayMax
        Colour: "{0.82, 0.55, 0.55}"
        Dotted line
        Draw line: threshold_crossings_per_s, 0, threshold_crossings_per_s, histMax * 1.15
        Solid line
    endif

    for hb from 1 to nHistBins
        binLeft = (hb - 1) * histBinWidth
        binRight = hb * histBinWidth
        binMid = (binLeft + binRight) / 2
        if binMid < threshold_crossings_per_s
            barCol$ = "{0.25, 0.50, 0.82}"
        else
            barCol$ = "{0.82, 0.40, 0.30}"
        endif
        Paint rectangle: barCol$, binLeft, binRight, 0, histCount[hb]
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Count"
    Text bottom: "yes", "Crossings/s"
    Text top: "no", "ZCR distribution"

    # ----------------------------------------------------------
    # Statistics panel (right half)
    # ----------------------------------------------------------
    Select outer viewport: 4.1, 8, 3.62, 5.02
    Select inner viewport: 4.40, 7.65, 3.72, 4.92

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.50, "centre", 0.92, "half", "##Statistics##"

    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.08, "left", 0.76, "half", "Mean ZCR:  " + fixed$(zcrMean, 1) + " crossings/s"
    Text: 0.08, "left", 0.62, "half", "Std Dev:     " + fixed$(zcrStdDev, 1)
    Text: 0.08, "left", 0.48, "half", "Min:            " + fixed$(zcrMin, 1)
    Text: 0.08, "left", 0.34, "half", "Max:           " + fixed$(zcrMax, 1)

    # Low/high ZCR ratio bar
    Colour: "{0.25, 0.50, 0.82}"
    Paint rectangle: "{0.25, 0.50, 0.82}", 0.08, 0.08 + 0.84 * lowZcrPct / 100, 0.12, 0.22
    Colour: "{0.82, 0.40, 0.30}"
    Paint rectangle: "{0.82, 0.40, 0.30}", 0.08 + 0.84 * lowZcrPct / 100, 0.92, 0.12, 0.22

    Font size: 5
    Colour: "{0.15, 0.35, 0.65}"
    Text: 0.08, "left", 0.06, "half", "Low ZCR: " + fixed$(lowZcrPct, 0) + "%"
    Colour: "{0.65, 0.28, 0.20}"
    Text: 0.60, "left", 0.06, "half", "High ZCR: " + fixed$(highZcrPct, 0) + "%"

    Colour: "Black"
    Draw inner box

    # ----------------------------------------------------------
    # Summary panel
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.10, 5.84
    Select inner viewport: 0.55, 7.65, 5.16, 5.78
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.78, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.48, "half",
        ... "Source: " + originalName$
        ... + "  |  Preset: " + presetName$
        ... + "  |  Window: " + fixed$(window_duration_ms, 0) + " ms"
        ... + "  |  Hop: " + fixed$(hop_duration_ms, 1) + " ms"
        ... + "  |  Frames: " + string$(nFrames)
    Text: 0.02, "left", 0.18, "half",
        ... "Mean=" + fixed$(zcrMean, 0) + " crossings/s"
        ... + "  |  σ=" + fixed$(zcrStdDev, 0)
        ... + "  |  Range: " + fixed$(zcrMin, 0) + "–" + fixed$(zcrMax, 0) + " crossings/s"
        ... + "  |  Low/High: " + fixed$(lowZcrPct, 0) + "/" + fixed$(highZcrPct, 0) + "%"
        ... + "  |  Threshold: " + fixed$(threshold_crossings_per_s, 0) + " crossings/s"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# Representative analysis Sound is no longer needed.
removeObject: workSound

# ============================================================
# FINAL
# ============================================================

appendInfoLine: "=== Done ==="

if export_ZCR_curve
    appendInfoLine: "Exported: ZCR_", originalName$, " (", nFrames, " samples at ", fixed$(zcrSR, 1), " Hz)"
    appendInfoLine: "  Query with: Get value at time... <seconds> Nearest"
    selectObject: zcrSound
    if play_result
        Play
    endif
else
    selectObject: original
endif
