# ============================================================
# Praat AudioTools - Voice_Quality_Sonification.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Sonifies local voice-quality instability by mapping measured
#   jitter and shimmer trajectories to two time-varying spectral
#   band-pass regions. This is creative data-to-sound mapping, not
#   formant estimation or formant synthesis.
#
# Method:
#   1. Measure local jitter and shimmer in rectangular analysis windows.
#   2. Normalize valid measurements across the file (0..1).
#   3. Map the normalized controls to multiplicative shifts of a low
#      and high band-pass region.
#   4. Filter the full source at each control point and linearly
#      crossfade adjacent filter states for click-free time variation.
#
# Changelog v1.1:
#   - FIX: analysis no longer uses a Hamming taper, which artificially
#     inflated shimmer and jitter.
#   - FIX: direct Get jitter/shimmer commands replace Voice report parsing.
#   - FIX: invalid/unvoiced windows are excluded from normalization and
#     inherit the nearest valid control value; fully undefined metrics are neutral.
#   - FIX: Reverse/Swap semantics made explicit with Mapping_mode.
#   - FIX: hard segment joins replaced by continuous crossfades.
#   - FIX: no per-segment or final peak normalization; Safety_peak only attenuates.
#   - FIX: arbitrary channel count and non-zero start time are preserved.
#   - NEW: Dry_wet_mix and filter-transition control.
#   - NEW: AudioTools house-style visualization.
# ============================================================

form Voice Quality Sonification v1.1
    optionmenu Preset: 1
        option Custom
        option Subtle Variation
        option Moderate Effect
        option Extreme Mapping
        option Swap Jitter/Shimmer
        option Invert Direction
    comment === Analysis ===
    integer Num_windows 8
    positive Window_size_s 0.2
    optionmenu Mapping_mode: 1
        option Jitter -> low, Shimmer -> high
        option Shimmer -> low, Jitter -> high
        option Jitter/Shimmer inverted direction
        option Swapped + inverted direction
    comment === Mapping Depth ===
    real Jitter_mapping_depth 0.15
    real Shimmer_mapping_depth 0.12
    comment (0.15 = +/-15% band-frequency shift across normalized range)
    comment === Base Band Ranges ===
    positive Low_band_low_Hz 280
    positive Low_band_high_Hz 900
    positive High_band_low_Hz 900
    positive High_band_high_Hz 2500
    positive Filter_transition_Hz 100
    comment === Output ===
    real Dry_wet_mix 1.0
    real Safety_peak 0.99
    boolean Draw_analysis 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================
if preset = 2
    num_windows = 6
    window_size_s = 0.25
    mapping_mode = 1
    jitter_mapping_depth = 0.08
    shimmer_mapping_depth = 0.06
    presetName$ = "Subtle"
elsif preset = 3
    num_windows = 8
    window_size_s = 0.20
    mapping_mode = 1
    jitter_mapping_depth = 0.15
    shimmer_mapping_depth = 0.12
    presetName$ = "Moderate"
elsif preset = 4
    num_windows = 12
    window_size_s = 0.15
    mapping_mode = 1
    jitter_mapping_depth = 0.30
    shimmer_mapping_depth = 0.25
    presetName$ = "Extreme"
elsif preset = 5
    num_windows = 8
    window_size_s = 0.20
    mapping_mode = 2
    jitter_mapping_depth = 0.15
    shimmer_mapping_depth = 0.12
    presetName$ = "Swap"
elsif preset = 6
    num_windows = 8
    window_size_s = 0.20
    mapping_mode = 3
    jitter_mapping_depth = 0.15
    shimmer_mapping_depth = 0.12
    presetName$ = "Invert"
else
    presetName$ = "Custom"
endif

# ============================================================
# INPUT + PARAMETER VALIDATION
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")
selectObject: originalID
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels
originalStart = Get start time
nyquist = sampleRate / 2
originalPeak = Get absolute extremum: 0, 0, "None"

if num_windows < 2
    num_windows = 2
endif
if num_windows > 64
    num_windows = 64
endif
if window_size_s < 0.05
    window_size_s = 0.05
endif
if duration < window_size_s
    exitScript: "Sound is too short for the requested analysis window (" + fixed$(window_size_s, 3) + " s)."
endif
if sampleRate < 8000
    exitScript: "Sample rate is too low for the default voice-quality bands (minimum supported: 8 kHz)."
endif

jitter_mapping_depth = max(0, min(0.90, abs(jitter_mapping_depth)))
shimmer_mapping_depth = max(0, min(0.90, abs(shimmer_mapping_depth)))
dry_wet_mix = max(0, min(1, dry_wet_mix))
safety_peak = max(0, min(1, safety_peak))
filter_transition_Hz = max(1, filter_transition_Hz)

low_band_low_Hz = max(20, min(nyquist - 80, low_band_low_Hz))
low_band_high_Hz = max(low_band_low_Hz + 20, min(nyquist - 40, low_band_high_Hz))
high_band_low_Hz = max(20, min(nyquist - 80, high_band_low_Hz))
high_band_high_Hz = max(high_band_low_Hz + 20, min(nyquist - 40, high_band_high_Hz))

# Work internally on a zero-based copy; restore the original time domain later.
selectObject: originalID
workSource = Copy: originalName$ + "_vqs_work"
if originalStart <> 0
    Shift times by: -originalStart
endif

# Analysis source: channel average, unless cancellation makes it nearly silent.
selectObject: workSource
if numChannels > 1
    analysisSource = Convert to mono
    Rename: "vqs_analysis"
    selectObject: analysisSource
    analysisPeak = Get absolute extremum: 0, 0, "None"
    if originalPeak > 0 and analysisPeak < 0.05 * originalPeak
        removeObject: analysisSource
        selectObject: workSource
        analysisSource = Extract one channel: 1
        Rename: "vqs_analysis"
        analysisSourceLabel$ = "channel 1 fallback"
    else
        analysisSourceLabel$ = "channel average"
    endif
else
    selectObject: workSource
    analysisSource = Copy: "vqs_analysis"
    analysisSourceLabel$ = "mono"
endif

# ============================================================
# REPORT HEADER
# ============================================================
clearinfo
writeInfoLine: "=== Voice Quality Sonification v1.1 ==="
appendInfoLine: "Input: ", originalName$, "   ", fixed$(duration, 3), " s   ", numChannels, " ch   ", fixed$(sampleRate, 0), " Hz"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Analysis source: ", analysisSourceLabel$
appendInfoLine: "Windows: ", num_windows, " x ", fixed$(window_size_s * 1000, 1), " ms"
appendInfoLine: "Dry/Wet: ", fixed$(dry_wet_mix, 2)
appendInfoLine: ""

# ============================================================
# JITTER / SHIMMER ANALYSIS
# ============================================================
periodFloor = 1 / 600
periodCeiling = 1 / 75
maxPeriodFactor = 1.3
maxAmplitudeFactor = 1.6
validJitterCount = 0
validShimmerCount = 0

for w to num_windows
    analysisTime[w] = 0
    jitterVal[w] = undefined
    shimmerVal[w] = undefined
    jitterValid[w] = 0
    shimmerValid[w] = 0
    jitterNorm[w] = 0.5
    shimmerNorm[w] = 0.5
    lowCenter[w] = 0
    highCenter[w] = 0
endfor

appendInfoLine: "Analyzing local jitter/shimmer..."

for w from 1 to num_windows
    if num_windows > 1
        analysisTime[w] = window_size_s / 2 + (w - 1) * (duration - window_size_s) / (num_windows - 1)
    else
        analysisTime[w] = duration / 2
    endif
    windowStart = analysisTime[w] - window_size_s / 2
    windowEnd = analysisTime[w] + window_size_s / 2
    windowStart = max(0, windowStart)
    windowEnd = min(duration, windowEnd)

    # Rectangular extraction is essential: tapering would create artificial shimmer.
    selectObject: analysisSource
    windowSound = Extract part: windowStart, windowEnd, "rectangular", 1, "no"
    selectObject: windowSound
    pitchObj = To Pitch (cc): 0, 75, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14, 600
    selectObject: windowSound
    plusObject: pitchObj
    pointProc = To PointProcess (cc)

    selectObject: pointProc
    numPulses = Get number of points
    if numPulses >= 4
        jitterNow = Get jitter (local): 0, 0, periodFloor, periodCeiling, maxPeriodFactor
        if jitterNow <> undefined and jitterNow >= 0
            jitterVal[w] = 100 * jitterNow
            jitterValid[w] = 1
            validJitterCount += 1
        endif

        selectObject: windowSound
        plusObject: pointProc
        shimmerNow = Get shimmer (local): 0, 0, periodFloor, periodCeiling, maxPeriodFactor, maxAmplitudeFactor
        if shimmerNow <> undefined and shimmerNow >= 0
            shimmerVal[w] = 100 * shimmerNow
            shimmerValid[w] = 1
            validShimmerCount += 1
        endif
    endif

    if jitterValid[w] and shimmerValid[w]
        appendInfoLine: "  Window ", w, " @ ", fixed$(analysisTime[w], 3), " s: jitter ", fixed$(jitterVal[w], 4), "%, shimmer ", fixed$(shimmerVal[w], 4), "%"
    elsif jitterValid[w]
        appendInfoLine: "  Window ", w, " @ ", fixed$(analysisTime[w], 3), " s: jitter ", fixed$(jitterVal[w], 4), "%, shimmer undefined"
    elsif shimmerValid[w]
        appendInfoLine: "  Window ", w, " @ ", fixed$(analysisTime[w], 3), " s: jitter undefined, shimmer ", fixed$(shimmerVal[w], 4), "%"
    else
        appendInfoLine: "  Window ", w, " @ ", fixed$(analysisTime[w], 3), " s: unvoiced/insufficient pulses"
    endif

    removeObject: windowSound, pitchObj, pointProc
endfor

# ============================================================
# NORMALIZE VALID MEASUREMENTS ONLY
# ============================================================
if validJitterCount > 0
    minJitter = undefined
    maxJitter = undefined
    for w to num_windows
        if jitterValid[w]
            if minJitter = undefined or jitterVal[w] < minJitter
                minJitter = jitterVal[w]
            endif
            if maxJitter = undefined or jitterVal[w] > maxJitter
                maxJitter = jitterVal[w]
            endif
        endif
    endfor
    for w to num_windows
        if jitterValid[w]
            if maxJitter > minJitter
                jitterNorm[w] = (jitterVal[w] - minJitter) / (maxJitter - minJitter)
            else
                jitterNorm[w] = 0.5
            endif
        endif
    endfor
    # Invalid windows inherit the nearest valid jitter control.
    for w to num_windows
        if not jitterValid[w]
            bestDist = num_windows + 1
            bestVal = 0.5
            for j to num_windows
                if jitterValid[j]
                    dIndex = abs(j - w)
                    if dIndex < bestDist
                        bestDist = dIndex
                        bestVal = jitterNorm[j]
                    endif
                endif
            endfor
            jitterNorm[w] = bestVal
        endif
    endfor
else
    minJitter = undefined
    maxJitter = undefined
endif

if validShimmerCount > 0
    minShimmer = undefined
    maxShimmer = undefined
    for w to num_windows
        if shimmerValid[w]
            if minShimmer = undefined or shimmerVal[w] < minShimmer
                minShimmer = shimmerVal[w]
            endif
            if maxShimmer = undefined or shimmerVal[w] > maxShimmer
                maxShimmer = shimmerVal[w]
            endif
        endif
    endfor
    for w to num_windows
        if shimmerValid[w]
            if maxShimmer > minShimmer
                shimmerNorm[w] = (shimmerVal[w] - minShimmer) / (maxShimmer - minShimmer)
            else
                shimmerNorm[w] = 0.5
            endif
        endif
    endfor
    # Invalid windows inherit the nearest valid shimmer control.
    for w to num_windows
        if not shimmerValid[w]
            bestDist = num_windows + 1
            bestVal = 0.5
            for j to num_windows
                if shimmerValid[j]
                    dIndex = abs(j - w)
                    if dIndex < bestDist
                        bestDist = dIndex
                        bestVal = shimmerNorm[j]
                    endif
                endif
            endfor
            shimmerNorm[w] = bestVal
        endif
    endfor
else
    minShimmer = undefined
    maxShimmer = undefined
endif

if validJitterCount = 0 and validShimmerCount = 0
    removeObject: workSource, analysisSource
    selectObject: originalID
    exitScript: "No valid jitter or shimmer measurements were found. Use a voiced/periodic source or adjust the analysis window."
endif

if validJitterCount = 0
    appendInfoLine: "NOTE: jitter was undefined throughout; jitter control held neutral."
endif
if validShimmerCount = 0
    appendInfoLine: "NOTE: shimmer was undefined throughout; shimmer control held neutral."
endif

# ============================================================
# MAP CONTROLS TO FILTER STATES
# ============================================================
swapMetrics = (mapping_mode = 2 or mapping_mode = 4)
invertDirection = (mapping_mode = 3 or mapping_mode = 4)

if swapMetrics
    mappingName$ = "Shimmer -> low / Jitter -> high"
else
    mappingName$ = "Jitter -> low / Shimmer -> high"
endif
if invertDirection
    mappingName$ = mappingName$ + " (inverted)"
endif
appendInfoLine: "Mapping: ", mappingName$
appendInfoLine: ""

for w to num_windows
    if swapMetrics
        lowControl = shimmerNorm[w]
        highControl = jitterNorm[w]
        lowDepth = shimmer_mapping_depth
        highDepth = jitter_mapping_depth
    else
        lowControl = jitterNorm[w]
        highControl = shimmerNorm[w]
        lowDepth = jitter_mapping_depth
        highDepth = shimmer_mapping_depth
    endif

    if invertDirection
        lowSigned = -(lowControl - 0.5)
        highSigned = -(highControl - 0.5)
    else
        lowSigned = lowControl - 0.5
        highSigned = highControl - 0.5
    endif

    lowShift[w] = 1 + 2 * lowSigned * lowDepth
    highShift[w] = 1 + 2 * highSigned * highDepth

    lowLo[w] = max(20, min(nyquist - 80, low_band_low_Hz * lowShift[w]))
    lowHi[w] = max(lowLo[w] + 20, min(nyquist - 40, low_band_high_Hz * lowShift[w]))
    highLo[w] = max(20, min(nyquist - 80, high_band_low_Hz * highShift[w]))
    highHi[w] = max(highLo[w] + 20, min(nyquist - 40, high_band_high_Hz * highShift[w]))
    lowCenter[w] = sqrt(lowLo[w] * lowHi[w])
    highCenter[w] = sqrt(highLo[w] * highHi[w])
endfor

# ============================================================
# TIME-VARYING DUAL-BAND FILTERING
#   Each control point creates one full-file filter state. Adjacent
#   states are linearly crossfaded, so weights sum to unity at all times.
# ============================================================
appendInfoLine: "Rendering time-varying dual-band filter..."

selectObject: workSource
outputSound = Copy: originalName$ + "_jitshim"
Formula: "0"

if dry_wet_mix > 0
    for w to num_windows
        selectObject: workSource
        fLow = Filter (pass Hann band): lowLo[w], lowHi[w], filter_transition_Hz
        selectObject: workSource
        fHigh = Filter (pass Hann band): highLo[w], highHi[w], filter_transition_Hz

        # Sum the two spectral regions without per-state normalization.
        selectObject: fLow
        stateSound = Copy: "vqs_state"
        Formula: "self + object['fHigh:0', row, col]"

        if w = 1
            tCurr = analysisTime[w]
            tNext = analysisTime[w + 1]
            weight$ = "if x <= 'tCurr:12' then 1 else if x < 'tNext:12' then ('tNext:12' - x) / ('tNext:12' - 'tCurr:12') else 0 fi fi"
        elsif w = num_windows
            tPrev = analysisTime[w - 1]
            tCurr = analysisTime[w]
            weight$ = "if x >= 'tCurr:12' then 1 else if x > 'tPrev:12' then (x - 'tPrev:12') / ('tCurr:12' - 'tPrev:12') else 0 fi fi"
        else
            tPrev = analysisTime[w - 1]
            tCurr = analysisTime[w]
            tNext = analysisTime[w + 1]
            weight$ = "if x <= 'tPrev:12' or x >= 'tNext:12' then 0 else if x <= 'tCurr:12' then (x - 'tPrev:12') / ('tCurr:12' - 'tPrev:12') else ('tNext:12' - x) / ('tNext:12' - 'tCurr:12') fi fi"
        endif

        selectObject: outputSound
        Formula: "self + (" + weight$ + ") * object['stateSound:0', row, col]"
        removeObject: fLow, fHigh, stateSound
    endfor

    if dry_wet_mix < 1
        selectObject: outputSound
        Formula: "'dry_wet_mix:12' * self + (1 - 'dry_wet_mix:12') * object['workSource:0', row, col]"
    endif
else
    selectObject: outputSound
    Formula: "object['workSource:0', row, col]"
endif

# Safety attenuation only: never boost quiet output.
selectObject: outputSound
peakBeforeSafety = Get absolute extremum: 0, 0, "None"
if safety_peak > 0 and peakBeforeSafety > safety_peak
    Scale peak: safety_peak
    appendInfoLine: "Safety attenuation: peak ", fixed$(peakBeforeSafety, 4), " -> ", fixed$(safety_peak, 4)
endif

if originalStart <> 0
    Shift times by: originalStart
endif
Rename: originalName$ + "_jitshim"
outputPeak = Get absolute extremum: 0, 0, "None"

# ============================================================
# VISUALIZATION - AudioTools house style
# ============================================================
if draw_analysis
    Erase all
    Helvetica
    Line width: 1

    colInput$ = "{0.55,0.55,0.55}"
    colOutput$ = "{0.25,0.50,0.82}"
    colAccent$ = "{0.55,0.38,0.72}"
    colLight$ = "{0.92,0.92,0.92}"
    colLabel$ = "{0.35,0.35,0.52}"

    # Title
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half", "##Voice Quality Sonification##"
    Font size: 7
    Colour: colLabel$
    Text: 0.5, "centre", -1.22, "half", originalName$ + " | " + presetName$ + " | " + mappingName$

    # Normalized metrics
    Select outer viewport: 0, 8, 0.72, 2.00
    Select inner viewport: 0.65, 7.7, 0.84, 1.92
    Axes: 0, duration, 0, 1
    Paint rectangle: "{0.97,0.97,0.97}", 0, duration, 0, 1
    Colour: colLight$
    Draw line: 0, 0.5, duration, 0.5
    Colour: colOutput$
    Line width: 1.5
    for w from 1 to num_windows - 1
        Draw line: analysisTime[w], jitterNorm[w], analysisTime[w+1], jitterNorm[w+1]
    endfor
    Colour: colAccent$
    for w from 1 to num_windows - 1
        Draw line: analysisTime[w], shimmerNorm[w], analysisTime[w+1], shimmerNorm[w+1]
    endfor
    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left every: 1, 0.5, "yes", "yes", "no"
    Marks bottom every: 1, max(0.1, duration / 4), "yes", "yes", "no"
    Font size: 7
    Text top: "no", "Normalized voice-quality controls"
    Text bottom: "yes", "Time (s)"
    Font size: 6
    Colour: colOutput$
    Text: duration * 0.02, "left", 0.92, "half", "jitter"
    Colour: colAccent$
    Text: duration * 0.02, "left", 0.82, "half", "shimmer"

    # Filter-center trajectories
    minBand = min(lowCenter[1], highCenter[1])
    maxBand = max(lowCenter[1], highCenter[1])
    for w from 2 to num_windows
        minBand = min(minBand, lowCenter[w], highCenter[w])
        maxBand = max(maxBand, lowCenter[w], highCenter[w])
    endfor
    minBand = max(20, minBand * 0.85)
    maxBand = min(nyquist, maxBand * 1.15)

    Select outer viewport: 0, 8, 2.08, 3.30
    Select inner viewport: 0.65, 7.7, 2.18, 3.22
    Axes: 0, duration, minBand, maxBand
    Paint rectangle: "{0.97,0.97,0.97}", 0, duration, minBand, maxBand
    Colour: colOutput$
    Line width: 1.5
    for w from 1 to num_windows - 1
        Draw line: analysisTime[w], lowCenter[w], analysisTime[w+1], lowCenter[w+1]
    endfor
    Colour: colAccent$
    for w from 1 to num_windows - 1
        Draw line: analysisTime[w], highCenter[w], analysisTime[w+1], highCenter[w+1]
    endfor
    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left: 4, "yes", "yes", "no"
    Marks bottom every: 1, max(0.1, duration / 4), "yes", "yes", "no"
    Font size: 7
    Text top: "no", "Mapped band-center trajectories"
    Text bottom: "yes", "Time (s)"
    Font size: 6
    Colour: colOutput$
    Text: duration * 0.02, "left", maxBand - 0.07 * (maxBand - minBand), "half", "low band"
    Colour: colAccent$
    Text: duration * 0.02, "left", maxBand - 0.16 * (maxBand - minBand), "half", "high band"

    # Input/output waveforms
    selectObject: workSource
    if numChannels > 1
        vizIn = Convert to mono
    else
        vizIn = Copy: "vqs_vizin"
    endif
    selectObject: outputSound
    if numChannels > 1
        vizOut = Convert to mono
    else
        vizOut = Copy: "vqs_vizout"
    endif
    if originalStart <> 0
        selectObject: vizOut
        Shift times by: -originalStart
    endif

    selectObject: vizIn
    pIn = Get absolute extremum: 0, 0, "None"
    selectObject: vizOut
    pOut = Get absolute extremum: 0, 0, "None"
    waveMax = max(0.001, pIn, pOut) * 1.05

    Select outer viewport: 0, 4, 3.38, 4.55
    Select inner viewport: 0.55, 3.85, 3.48, 4.48
    Axes: 0, duration, -waveMax, waveMax
    Colour: colInput$
    selectObject: vizIn
    Draw: 0, duration, -waveMax, waveMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Input"

    Select outer viewport: 4, 8, 3.38, 4.55
    Select inner viewport: 4.25, 7.7, 3.48, 4.48
    Axes: 0, duration, -waveMax, waveMax
    Colour: colOutput$
    selectObject: vizOut
    Draw: 0, duration, -waveMax, waveMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Output"

    removeObject: vizIn, vizOut

    # Summary
    Select outer viewport: 0, 8, 4.68, 5.58
    Select inner viewport: 0.55, 7.7, 4.74, 5.52
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94,0.94,0.94}", 0, 1, 0, 1
    Colour: "{0.25,0.25,0.35}"
    Font size: 6
    Text: 0.02, "left", 0.77, "half", "##Analysis##  valid jitter " + string$(validJitterCount) + "/" + string$(num_windows) + " | valid shimmer " + string$(validShimmerCount) + "/" + string$(num_windows)
    Text: 0.02, "left", 0.48, "half", "##Bands##  low " + fixed$(low_band_low_Hz,0) + "-" + fixed$(low_band_high_Hz,0) + " Hz | high " + fixed$(high_band_low_Hz,0) + "-" + fixed$(high_band_high_Hz,0) + " Hz | transition " + fixed$(filter_transition_Hz,0) + " Hz"
    Text: 0.02, "left", 0.19, "half", "##Output##  " + string$(numChannels) + " ch | wet " + fixed$(dry_wet_mix,2) + " | peak " + fixed$(originalPeak,4) + " -> " + fixed$(outputPeak,4)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================
# FINAL INFO + CLEANUP
# ============================================================
appendInfoLine: ""
appendInfoLine: "=== Complete ==="
appendInfoLine: "Output: ", originalName$, "_jitshim"
appendInfoLine: "Channels: ", numChannels, "   start: ", fixed$(originalStart, 3), " s"
appendInfoLine: "Valid jitter windows: ", validJitterCount, "/", num_windows
appendInfoLine: "Valid shimmer windows: ", validShimmerCount, "/", num_windows
if validJitterCount > 0
    appendInfoLine: "Jitter range: ", fixed$(minJitter, 5), " - ", fixed$(maxJitter, 5), "%"
endif
if validShimmerCount > 0
    appendInfoLine: "Shimmer range: ", fixed$(minShimmer, 5), " - ", fixed$(maxShimmer, 5), "%"
endif
appendInfoLine: "Output peak: ", fixed$(outputPeak, 4)

removeObject: workSource, analysisSource
selectObject: outputSound
if play_result
    Play
endif
