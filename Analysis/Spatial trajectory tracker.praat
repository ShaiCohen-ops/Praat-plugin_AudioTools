# ============================================================
# Praat AudioTools - Spatial_trajectory_tracker.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.1 (2026) - Correlation-aware stereo trajectory analysis
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Tracks the lateral balance and stereo state of a two-channel Sound.
#   The analysis separates three distinct properties:
#     1) lateral energy balance (-1 left ... 0 centre ... +1 right),
#     2) inter-channel correlation (-1 anti-phase ... +1 coherent),
#     3) diffuse spread (0 compact/coherent ... 1 decorrelated spread).
#
#   Silence is not propagated as a fictitious last-known position.
#   The output Table retains a valid flag so downstream analysis can
#   distinguish measured frames from gated regions.
#
# Changelog v0.4:
#   - Replaced the old "width" proxy (which was only L/R energy balance)
#     with correlation-aware diffuse spread.
#   - Added zero-lag inter-channel correlation and phase-risk measures.
#   - Renamed the conceptual pan measurement to lateral balance while
#     retaining pan_raw/pan_smooth columns for backward compatibility.
#   - Removed last-pan propagation through silence; smoothing is confined
#     to contiguous valid regions.
#   - Corrected frame count (+1), non-zero Sound start times, and stereo
#     gate normalization.
#   - Added adaptive hop protection for long files.
#   - Replaced the arbitrary energy-radius polar display with a measured
#     Stereo State Map (balance x spread).
#   - Updated visualization to the AudioTools 8x8 research layout.
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Stereo Sound object."
endif

soundID = selected("Sound")
originalName$ = selected$("Sound")
numChans = Get number of channels

if numChans <> 2
    exitScript: "Input sound must be Stereo (2 channels)."
endif

form Spatial Trajectory Tracker v0.4.1
    comment === Preset ===
    optionmenu Preset: 1
        option Manual
        option Fast Overview
        option Detailed Analysis
        option Ultra Smooth
        option Transient Sensitive
    comment === Analysis Parameters ===
    positive Frame_length_s 0.02
    positive Hop_size_s 0.01
    real Silence_gate_dB -60.0
    natural Smoothing_frames 10
    comment === Visualization ===
    boolean Draw_visualization 1
    boolean Show_waveform 1
    boolean Show_stereo_state 1
endform

# ============================================================
# Presets
# ============================================================
if preset = 2
    frame_length_s = 0.05
    hop_size_s = 0.025
    smoothing_frames = 5
    silence_gate_dB = -50
    presetName$ = "FastOverview"
elsif preset = 3
    frame_length_s = 0.01
    hop_size_s = 0.005
    smoothing_frames = 15
    silence_gate_dB = -65
    presetName$ = "Detailed"
elsif preset = 4
    frame_length_s = 0.03
    hop_size_s = 0.015
    smoothing_frames = 30
    silence_gate_dB = -55
    presetName$ = "UltraSmooth"
elsif preset = 5
    frame_length_s = 0.005
    hop_size_s = 0.002
    smoothing_frames = 3
    silence_gate_dB = -70
    presetName$ = "Transient"
else
    presetName$ = "Manual"
endif

# ==============================================================================
# 1. SETUP
# ==============================================================================
clearinfo
writeInfoLine: "=== Spatial Trajectory Tracker v0.4.1 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Input: ", originalName$

selectObject: soundID
tmin = Get start time
tmax = Get end time
dur = Get total duration
sr = Get sampling frequency

if dur < frame_length_s
    exitScript: "Sound is shorter than the requested analysis frame."
endif

# Limit the expensive per-frame analysis on long files without exposing
# another technical control in the main form.
maxAnalysisFrames = 12000
effectiveHop = hop_size_s
usableSpan = dur - frame_length_s
requestedFrames = floor(usableSpan / effectiveHop) + 1
if requestedFrames > maxAnalysisFrames and usableSpan > 0
    effectiveHop = usableSpan / (maxAnalysisFrames - 1)
endif
numFrames = floor(usableSpan / effectiveHop) + 1
if numFrames < 1
    numFrames = 1
endif

# Preserve the requested smoothing duration if adaptive hop is engaged.
requestedSmoothDuration = smoothing_frames * hop_size_s
effectiveSmoothFrames = round(requestedSmoothDuration / effectiveHop)
if effectiveSmoothFrames < 1
    effectiveSmoothFrames = 1
endif

appendInfoLine: "Time domain: ", fixed$(tmin, 3), " to ", fixed$(tmax, 3), " s"
appendInfoLine: "Duration: ", fixed$(dur, 3), " s"
appendInfoLine: "Frame: ", fixed$(frame_length_s * 1000, 2), " ms"
appendInfoLine: "Requested hop: ", fixed$(hop_size_s * 1000, 2), " ms"
appendInfoLine: "Effective hop: ", fixed$(effectiveHop * 1000, 2), " ms"
appendInfoLine: "Frames: ", numFrames
appendInfoLine: ""

# ==============================================================================
# 2. ANALYZE STEREO FIELD
# ==============================================================================
appendInfoLine: "Analyzing stereo trajectory..."

selectObject: soundID
Extract one channel: 1
ch1ID = selected("Sound")

selectObject: soundID
Extract one channel: 2
ch2ID = selected("Sound")

# Mid and side are created once. Their frame RMS values let us recover the
# zero-lag cross term efficiently:
#   M=(L+R)/sqrt(2), S=(L-R)/sqrt(2)
#   E_M - E_S = 2 * mean(L*R)
selectObject: ch1ID
midID = Copy: "SpatialMid_tmp"
midFormula$ = "(object[" + string$(ch1ID) + ", row, col] + object[" + string$(ch2ID) + ", row, col]) / sqrt(2)"
Formula: midFormula$

selectObject: ch1ID
sideID = Copy: "SpatialSide_tmp"
sideFormula$ = "(object[" + string$(ch1ID) + ", row, col] - object[" + string$(ch2ID) + ", row, col]) / sqrt(2)"
Formula: sideFormula$

# Backward-compatible pan_raw/pan_smooth names are retained, but in v0.4
# they explicitly mean lateral energy balance, not a geometric source angle.
Create Table with column names: "spatial_data", numFrames, "time pan_raw pan_smooth energy_L energy_R width width_smooth correlation phase_risk valid"
tableID = selected("Table")

gateThreshold = 10 ^ (silence_gate_dB / 20)
epsilon = 0.000000000001

sumBalance = 0
sumBalanceSq = 0
sumSpread = 0
sumCorr = 0
validFrames = 0
corrFrames = 0
negativeCorrFrames = 0
minBalance = 1
maxBalance = -1

for i from 1 to numFrames
    tStart = tmin + (i - 1) * effectiveHop
    tEnd = tStart + frame_length_s
    if tEnd > tmax
        tEnd = tmax
    endif
    tMid = (tStart + tEnd) / 2

    selectObject: ch1ID
    rmsL = Get root-mean-square: tStart, tEnd
    selectObject: ch2ID
    rmsR = Get root-mean-square: tStart, tEnd
    selectObject: midID
    rmsM = Get root-mean-square: tStart, tEnd
    selectObject: sideID
    rmsS = Get root-mean-square: tStart, tEnd

    energyL = rmsL * rmsL
    energyR = rmsR * rmsR
    stereoRMS = sqrt((energyL + energyR) / 2)

    frameValid = 0
    balance = undefined
    corr = undefined
    spread = undefined
    phaseRisk = undefined

    if stereoRMS > gateThreshold
        frameValid = 1

        # Lateral energy balance. This is robust for arbitrary stereo mixes
        # and does not pretend to recover a unique geometric source angle.
        balance = (energyR - energyL) / (energyR + energyL + epsilon)
        if balance > 1
            balance = 1
        elsif balance < -1
            balance = -1
        endif

        # Correlation from the M/S energy identity.
        corrDen = 2 * rmsL * rmsR
        if corrDen > epsilon
            energyM = rmsM * rmsM
            energyS = rmsS * rmsS
            corr = (energyM - energyS) / corrDen
            if corr > 1
                corr = 1
            elsif corr < -1
                corr = -1
            endif

            # Diffuse spread requires BOTH channels to be present and
            # rewards decorrelation, not anti-phase. A hard-panned mono
            # source and a coherent centre both therefore have low spread.
            overlap = 2 * min(rmsL, rmsR) / (rmsL + rmsR + epsilon)
            spread = overlap * (1 - abs(corr))
            if spread < 0
                spread = 0
            elsif spread > 1
                spread = 1
            endif

            phaseRisk = max(0, -corr)

            sumCorr = sumCorr + corr
            corrFrames = corrFrames + 1
            if corr < 0
                negativeCorrFrames = negativeCorrFrames + 1
            endif
        else
            # One channel is effectively absent: lateral, but not diffuse.
            spread = 0
            phaseRisk = 0
        endif

        sumBalance = sumBalance + balance
        sumBalanceSq = sumBalanceSq + balance * balance
        sumSpread = sumSpread + spread
        validFrames = validFrames + 1

        if balance < minBalance
            minBalance = balance
        endif
        if balance > maxBalance
            maxBalance = balance
        endif
    endif

    selectObject: tableID
    Set numeric value: i, "time", tMid
    Set numeric value: i, "pan_raw", balance
    Set numeric value: i, "pan_smooth", balance
    Set numeric value: i, "energy_L", energyL
    Set numeric value: i, "energy_R", energyR
    Set numeric value: i, "width", spread
    Set numeric value: i, "width_smooth", spread
    Set numeric value: i, "correlation", corr
    Set numeric value: i, "phase_risk", phaseRisk
    Set numeric value: i, "valid", frameValid
endfor

# M/S are no longer needed after the frame statistics.
removeObject: midID, sideID

# ==============================================================================
# 3. CONTIGUOUS-REGION SMOOTHING
# ==============================================================================
if effectiveSmoothFrames > 1
    selectObject: tableID
    halfWin = floor(effectiveSmoothFrames / 2)

    for i from 1 to numFrames
        frameValid = Get value: i, "valid"
        if frameValid = 1
            centreBalance = Get value: i, "pan_raw"
            centreSpread = Get value: i, "width"
            smoothBalanceSum = centreBalance
            smoothSpreadSum = centreSpread
            smoothCount = 1

            leftOpen = 1
            rightOpen = 1
            for k from 1 to halfWin
                if leftOpen = 1
                    leftIndex = i - k
                    if leftIndex >= 1
                        leftValid = Get value: leftIndex, "valid"
                        if leftValid = 1
                            leftBalance = Get value: leftIndex, "pan_raw"
                            leftSpread = Get value: leftIndex, "width"
                            smoothBalanceSum = smoothBalanceSum + leftBalance
                            smoothSpreadSum = smoothSpreadSum + leftSpread
                            smoothCount = smoothCount + 1
                        else
                            leftOpen = 0
                        endif
                    else
                        leftOpen = 0
                    endif
                endif

                if rightOpen = 1
                    rightIndex = i + k
                    if rightIndex <= numFrames
                        rightValid = Get value: rightIndex, "valid"
                        if rightValid = 1
                            rightBalance = Get value: rightIndex, "pan_raw"
                            rightSpread = Get value: rightIndex, "width"
                            smoothBalanceSum = smoothBalanceSum + rightBalance
                            smoothSpreadSum = smoothSpreadSum + rightSpread
                            smoothCount = smoothCount + 1
                        else
                            rightOpen = 0
                        endif
                    else
                        rightOpen = 0
                    endif
                endif
            endfor

            Set numeric value: i, "pan_smooth", smoothBalanceSum / smoothCount
            Set numeric value: i, "width_smooth", smoothSpreadSum / smoothCount
        endif
    endfor
endif

# ==============================================================================
# 4. STATISTICS
# ==============================================================================
if validFrames > 0
    meanBalance = sumBalance / validFrames
    varianceBalance = (sumBalanceSq / validFrames) - meanBalance * meanBalance
    if varianceBalance < 0
        varianceBalance = 0
    endif
    stdBalance = sqrt(varianceBalance)
    balanceRange = maxBalance - minBalance
    meanSpread = sumSpread / validFrames
else
    meanBalance = 0
    stdBalance = 0
    balanceRange = 0
    meanSpread = 0
    minBalance = 0
    maxBalance = 0
endif

if corrFrames > 0
    meanCorr = sumCorr / corrFrames
    negativeCorrPercent = 100 * negativeCorrFrames / corrFrames
else
    meanCorr = undefined
    negativeCorrPercent = 0
endif

if meanBalance < -0.1
    biasDesc$ = "left-biased"
elsif meanBalance > 0.1
    biasDesc$ = "right-biased"
else
    biasDesc$ = "centered"
endif

if stdBalance < 0.1
    moveDesc$ = "static"
elsif stdBalance < 0.3
    moveDesc$ = "moderate movement"
else
    moveDesc$ = "dynamic"
endif

if meanSpread < 0.15
    spreadDesc$ = "compact/coherent"
elsif meanSpread < 0.45
    spreadDesc$ = "moderate spread"
else
    spreadDesc$ = "diffuse/wide"
endif

appendInfoLine: ""
appendInfoLine: "=== Statistics ==="
appendInfoLine: "Mean balance: ", fixed$(meanBalance, 3), " (", biasDesc$, ")"
appendInfoLine: "Balance std: ", fixed$(stdBalance, 3), " (", moveDesc$, ")"
appendInfoLine: "Balance range: ", fixed$(minBalance, 2), " to ", fixed$(maxBalance, 2)
appendInfoLine: "Mean diffuse spread: ", fixed$(meanSpread, 3), " (", spreadDesc$, ")"
if meanCorr <> undefined
    appendInfoLine: "Mean L/R correlation: ", fixed$(meanCorr, 3)
    appendInfoLine: "Negative-correlation frames: ", fixed$(negativeCorrPercent, 1), "%"
else
    appendInfoLine: "Mean L/R correlation: undefined (one channel absent in valid frames)"
endif
appendInfoLine: "Valid frames: ", validFrames, " / ", numFrames

# ==============================================================================
# 5. VISUALIZATION - AudioTools 8x8 layout
# ==============================================================================
if draw_visualization
    Erase all
    timeTick = dur / 5
    if timeTick <= 0
        timeTick = 1
    endif

    # ---------- Title strip ----------
    Select outer viewport: 0.35, 7.65, 0.12, 0.62
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", -1.5, "half", "Spatial Trajectory Tracker"

    # ---------- Metadata strip ----------
    Select outer viewport: 0.35, 7.65, 0.63, 1.05
    Axes: 0, 1, 0, 1
    Font size: 8
    meta$ = originalName$ + " | " + presetName$ + " | " + string$(numFrames) + " frames | hop " + fixed$(effectiveHop * 1000, 1) + " ms"
    Text: 0.5, "centre", 0.68, "half", meta$
    metric$ = "mean balance " + fixed$(meanBalance, 2) + " | spread " + fixed$(meanSpread, 2)
    if meanCorr <> undefined
        metric$ = metric$ + " | corr " + fixed$(meanCorr, 2) + " | negative corr " + fixed$(negativeCorrPercent, 1) + "%"
    endif
    Text: 0.5, "centre", -1.20, "half", metric$

    # ---------- Panel A: lateral balance ----------
    Select outer viewport: 0.35, 7.75, 1.15, 3.18
    Select inner viewport: 0.95, 7.55, 1.45, 2.88
    Axes: tmin, tmax, -1.05, 1.05

    Paint rectangle: "{0.97, 0.97, 0.97}", tmin, tmax, -1.05, 1.05
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: tmin, 0, tmax, 0
    Dotted line
    Draw line: tmin, 0.5, tmax, 0.5
    Draw line: tmin, -0.5, tmax, -0.5
    Solid line

    selectObject: tableID
    if numFrames > 1
        Colour: "{0.70, 0.70, 0.76}"
        Line width: 1
        for i from 1 to numFrames - 1
            v1 = Get value: i, "valid"
            v2 = Get value: i + 1, "valid"
            if v1 = 1 and v2 = 1
                tt1 = Get value: i, "time"
                pp1 = Get value: i, "pan_raw"
                tt2 = Get value: i + 1, "time"
                pp2 = Get value: i + 1, "pan_raw"
                Draw line: tt1, pp1, tt2, pp2
            endif
        endfor

        Colour: "{0.10, 0.28, 0.55}"
        Line width: 1.5
        for i from 1 to numFrames - 1
            v1 = Get value: i, "valid"
            v2 = Get value: i + 1, "valid"
            if v1 = 1 and v2 = 1
                tt1 = Get value: i, "time"
                pp1 = Get value: i, "pan_smooth"
                tt2 = Get value: i + 1, "time"
                pp2 = Get value: i + 1, "pan_smooth"
                Draw line: tt1, pp1, tt2, pp2
            endif
        endfor
    endif

    Colour: "{0.55, 0.18, 0.18}"
    Line width: 1
    Dotted line
    Draw line: tmin, meanBalance, tmax, meanBalance
    Solid line

    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left every: 1, 0.5, "yes", "yes", "no"
    Marks bottom every: 1, timeTick, "yes", "yes", "no"
    Text left: "yes", "Lateral balance"
    Font size: 9
    Text top: "no", "A  Lateral energy balance  (-1 L, 0 C, +1 R)"

    # ---------- Panel B: correlation and diffuse spread ----------
    Select outer viewport: 0.35, 7.75, 3.28, 5.30
    Select inner viewport: 0.95, 7.55, 3.58, 5.00
    Axes: tmin, tmax, -1.05, 1.05

    Paint rectangle: "{0.97, 0.97, 0.97}", tmin, tmax, -1.05, 1.05
    Paint rectangle: "{0.96, 0.93, 0.93}", tmin, tmax, -1.05, 0
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: tmin, 0, tmax, 0

    selectObject: tableID
    if numFrames > 1
        # Correlation
        Colour: "{0.12, 0.38, 0.45}"
        Line width: 1.5
        for i from 1 to numFrames - 1
            v1 = Get value: i, "valid"
            v2 = Get value: i + 1, "valid"
            c1 = Get value: i, "correlation"
            c2 = Get value: i + 1, "correlation"
            if v1 = 1 and v2 = 1 and c1 <> undefined and c2 <> undefined
                tt1 = Get value: i, "time"
                tt2 = Get value: i + 1, "time"
                Draw line: tt1, c1, tt2, c2
            endif
        endfor

        # Smoothed diffuse spread, shown in the same -1..1 axes but
        # physically confined to the upper half [0..1].
        Colour: "{0.55, 0.32, 0.12}"
        Line width: 1.5
        for i from 1 to numFrames - 1
            v1 = Get value: i, "valid"
            v2 = Get value: i + 1, "valid"
            if v1 = 1 and v2 = 1
                tt1 = Get value: i, "time"
                w1 = Get value: i, "width_smooth"
                tt2 = Get value: i + 1, "time"
                w2 = Get value: i + 1, "width_smooth"
                Draw line: tt1, w1, tt2, w2
            endif
        endfor
    endif

    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left every: 1, 0.5, "yes", "yes", "no"
    Marks bottom every: 1, timeTick, "yes", "yes", "no"
    Text left: "yes", "Corr / spread"
    Text bottom: "yes", "Time (s)"
    Font size: 9
    Text top: "no", "B  Stereo coherence and diffuse spread"
    Colour: "{0.12, 0.38, 0.45}"
    Text: tmin + 0.02 * dur, "left", 0.90, "half", "correlation"
    Colour: "{0.55, 0.32, 0.12}"
    Text: tmin + 0.02 * dur, "left", 0.72, "half", "diffuse spread"
    Colour: "{0.55, 0.18, 0.18}"
    Text: tmin + 0.02 * dur, "left", -0.88, "half", "negative corr = phase risk"

    # ---------- Bottom-left: measured stereo state ----------
    if show_stereo_state
        Select outer viewport: 0.35, 4.05, 5.42, 7.78
        Select inner viewport: 0.82, 3.82, 5.75, 7.42
        Axes: -1.05, 1.05, -0.05, 1.05
        Paint rectangle: "{0.97, 0.97, 0.97}", -1.05, 1.05, -0.05, 1.05

        Colour: "{0.82, 0.82, 0.82}"
        Draw line: 0, 0, 0, 1
        Dotted line
        Draw line: -0.5, 0, -0.5, 1
        Draw line: 0.5, 0, 0.5, 1
        Solid line

        selectObject: tableID
        plotStep = ceiling(numFrames / 1200)
        if plotStep < 1
            plotStep = 1
        endif
        previousStateValid = 0
        previousX = 0
        previousY = 0

        for i from 1 to numFrames
            if (i - 1) mod plotStep = 0
                frameValid = Get value: i, "valid"
                if frameValid = 1
                    stateX = Get value: i, "pan_smooth"
                    stateY = Get value: i, "width_smooth"

                    if previousStateValid = 1
                        Colour: "{0.72, 0.72, 0.72}"
                        Line width: 1
                        Draw line: previousX, previousY, stateX, stateY
                    endif

                    progress = (i - 1) / max(1, numFrames - 1)
                    rVal$ = fixed$(progress, 2)
                    bVal$ = fixed$(1 - progress, 2)
                    pointSize = 0.018
                    Paint rectangle: "{" + rVal$ + ", 0.25, " + bVal$ + "}", stateX - pointSize, stateX + pointSize, stateY - pointSize, stateY + pointSize

                    previousX = stateX
                    previousY = stateY
                    previousStateValid = 1
                else
                    previousStateValid = 0
                endif
            endif
        endfor

        Colour: "Black"
        Line width: 1
        Draw inner box
        Marks left every: 1, 0.5, "yes", "yes", "no"
        Marks bottom every: 1, 0.5, "yes", "yes", "no"
        Text left: "yes", "Diffuse spread"
        Text bottom: "yes", "Lateral balance"
        Font size: 9
        Text top: "no", "C  Stereo state map  (blue=start, red=end)"
    endif

    # ---------- Bottom-right: waveform or statistics ----------
    if show_waveform
        if show_stereo_state
            bottomLeft = 4.18
        else
            bottomLeft = 0.35
        endif

        Select outer viewport: bottomLeft, 7.75, 5.42, 7.78
        Select inner viewport: bottomLeft + 0.48, 7.52, 5.75, 7.42

        selectObject: ch1ID
        minL = Get minimum: tmin, tmax, "None"
        maxL = Get maximum: tmin, tmax, "None"
        selectObject: ch2ID
        minR = Get minimum: tmin, tmax, "None"
        maxR = Get maximum: tmin, tmax, "None"
        wavePeak = max(max(abs(minL), abs(maxL)), max(abs(minR), abs(maxR)))
        if wavePeak <= 0
            wavePeak = 1
        endif
        wavePeak = wavePeak * 1.05

        selectObject: ch1ID
        Colour: "{0.18, 0.34, 0.58}"
        Draw: tmin, tmax, -wavePeak, wavePeak, "no", "Curve"

        selectObject: ch2ID
        Colour: "{0.58, 0.28, 0.18}"
        Draw: tmin, tmax, -wavePeak, wavePeak, "no", "Curve"

        Colour: "Black"
        Draw inner box
        Text bottom: "yes", "Time (s)"
        Font size: 9
        Text top: "no", "D  Stereo waveform  (L blue, R brown)"
    elsif show_stereo_state
        Select outer viewport: 4.18, 7.75, 5.42, 7.78
        Select inner viewport: 4.50, 7.52, 5.78, 7.42
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
        Colour: "{0.25, 0.25, 0.25}"
        Font size: 9
        Text: 0.05, "left", 0.88, "half", "Mean balance: " + fixed$(meanBalance, 3)
        Text: 0.05, "left", 0.72, "half", "Balance std: " + fixed$(stdBalance, 3)
        Text: 0.05, "left", 0.56, "half", "Mean spread: " + fixed$(meanSpread, 3)
        if meanCorr <> undefined
            Text: 0.05, "left", 0.40, "half", "Mean correlation: " + fixed$(meanCorr, 3)
            Text: 0.05, "left", 0.24, "half", "Negative corr: " + fixed$(negativeCorrPercent, 1) + "%"
        endif
        Colour: "Black"
        Draw inner box
        Text top: "no", "D  Summary"
    endif
endif

# ==============================================================================
# 6. CLEANUP AND OUTPUT
# ==============================================================================
removeObject: ch1ID, ch2ID

selectObject: tableID
Rename: "SpatialAnalysis_" + originalName$ + "_" + presetName$

selectObject: soundID
plusObject: tableID

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Analysis table: SpatialAnalysis_", originalName$, "_", presetName$
