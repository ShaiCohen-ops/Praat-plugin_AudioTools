# ============================================================
# Praat AudioTools - Spectral_Driven_Intensity_Modulation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Time-varying spectral-driven tremolo. Short analysis windows measure
#   scale-invariant spectral flatness and normalized spectral spread.
#   Flat/noisy windows receive deeper attenuation; spectrally broad windows
#   receive faster modulation. Tonal/spectrally compact windows can be
#   protected with reduced depth and rate.
#
#   Depth is a relative attenuation range: 0 dB to -Depth_dB. The effect
#   never boosts as part of the tremolo itself. The same gain trajectory is
#   applied to every input channel. Sample rate, start time, duration, and
#   channel count are preserved.
#
# v0.3 changes:
#   - Replaces level-dependent raw-power roughness with normalized spectral
#     spread; flatness uses a power-relative floor and is level invariant.
#   - Uses direct Spectrum cell access and exact-length FFTs for faster analysis.
#   - Defines depth as attenuation-only dB modulation (0 to -Depth_dB).
#   - Uses Multiply "no" with a relative-dB IntensityTier; removes normalization.
#   - Adds Dry_wet_percent and attenuation-only Safety_peak.
#   - Preserves arbitrary channels and non-zero Sound start times.
#   - Adds anti-phase fold-down fallback for spectral analysis.
#   - Uses adaptive control resolution for fast modulation.
#   - Updates visualization to the AudioTools house layout.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Error: Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
duration = Get total duration
sampling = Get sampling frequency
soundStart = Get start time
soundEnd = Get end time
numChannels = Get number of channels
nyquist = sampling / 2

form Spectral-Driven Intensity Modulation
    optionmenu Preset: 1
        option Custom (use settings below)
        option Subtle Texture
        option Moderate Dynamics
        option Strong Spectral Response
        option Voice Protection Mode
        option Maximum Effect

    comment --- Analysis ---
    natural Num_analysis_points: 8
    positive Window_size_seconds: 0.2
    positive Min_frequency_Hz: 80
    positive Max_frequency_Hz: 5000

    comment --- Modulation mapping ---
    positive Base_depth_dB: 20
    positive Max_depth_dB: 50
    positive Base_mod_speed_Hz: 1.0
    positive Max_mod_speed_Hz: 5.0

    comment --- Tonal / compact-spectrum protection ---
    positive Tonal_flatness_threshold: 0.3
    positive Smooth_spread_threshold: 0.12
    real Tonal_depth_reduction: 0.3
    real Tonal_speed_reduction: 0.7

    comment --- Output ---
    positive Time_step: 0.01
    real Dry_wet_percent: 100
    real Safety_peak: 0.99
    boolean Draw_visualization: 1
    boolean Play_result: 1
endform

# ============================================================
# PRESETS
# ============================================================
if preset = 2
    base_depth_dB = 12
    max_depth_dB = 30
    base_mod_speed_Hz = 0.8
    max_mod_speed_Hz = 3.0
    presetName$ = "Subtle"
elsif preset = 3
    base_depth_dB = 18
    max_depth_dB = 42
    base_mod_speed_Hz = 1.0
    max_mod_speed_Hz = 4.0
    presetName$ = "Moderate"
elsif preset = 4
    base_depth_dB = 22
    max_depth_dB = 52
    base_mod_speed_Hz = 1.5
    max_mod_speed_Hz = 6.0
    presetName$ = "Strong"
elsif preset = 5
    base_depth_dB = 16
    max_depth_dB = 36
    tonal_flatness_threshold = 0.40
    smooth_spread_threshold = 0.18
    tonal_depth_reduction = 0.20
    tonal_speed_reduction = 0.50
    presetName$ = "VoicePro"
elsif preset = 6
    base_depth_dB = 26
    max_depth_dB = 60
    base_mod_speed_Hz = 2.0
    max_mod_speed_Hz = 8.0
    tonal_depth_reduction = 0.60
    presetName$ = "Maximum"
else
    presetName$ = "Custom"
endif

# ============================================================
# VALIDATION
# ============================================================
if duration <= 0
    exitScript: "Error: Sound duration must be positive."
endif

num_analysis_points = min(64, max(2, num_analysis_points))
window_size_seconds = min(duration, max(0.005, window_size_seconds))

min_frequency_Hz = max(0, min(min_frequency_Hz, 0.49 * sampling))
max_frequency_Hz = max(0, min(max_frequency_Hz, 0.49 * sampling))
if max_frequency_Hz <= min_frequency_Hz
    exitScript: "Error: Max_frequency_Hz must be greater than Min_frequency_Hz after Nyquist clamping."
endif

base_depth_dB = min(80, max(0, base_depth_dB))
max_depth_dB = min(80, max(base_depth_dB, max_depth_dB))
base_mod_speed_Hz = min(50, max(0, base_mod_speed_Hz))
max_mod_speed_Hz = min(50, max(base_mod_speed_Hz, max_mod_speed_Hz))
tonal_flatness_threshold = min(1, max(0, tonal_flatness_threshold))
smooth_spread_threshold = min(1, max(0, smooth_spread_threshold))
tonal_depth_reduction = min(1, max(0, tonal_depth_reduction))
tonal_speed_reduction = min(1, max(0, tonal_speed_reduction))
time_step = min(0.05, max(0.0005, time_step))
dry_wet_percent = min(100, max(0, dry_wet_percent))
safety_peak = min(1, max(0, safety_peak))

# Keep at least 32 control points per fastest requested modulation cycle.
if max_mod_speed_Hz > 0
    controlStep = min(time_step, 1 / (32 * max_mod_speed_Hz))
else
    controlStep = time_step
endif

appendInfoLine: "=== Spectral-Driven Intensity Modulation v0.3 ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(duration, 3), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Channels: ", numChannels, " | Sample rate: ", fixed$(sampling, 0), " Hz"
appendInfoLine: "Analysis: ", num_analysis_points, " windows x ", fixed$(window_size_seconds * 1000, 1), " ms"
appendInfoLine: "Range: ", fixed$(min_frequency_Hz, 0), " - ", fixed$(max_frequency_Hz, 0), " Hz"
appendInfoLine: "Depth: ", fixed$(base_depth_dB, 1), " - ", fixed$(max_depth_dB, 1), " dB attenuation"
appendInfoLine: "Rate: ", fixed$(base_mod_speed_Hz, 2), " - ", fixed$(max_mod_speed_Hz, 2), " Hz"
appendInfoLine: "Dry/Wet: ", fixed$(dry_wet_percent, 1), "%"
appendInfoLine: ""

# ============================================================
# ANALYSIS SOURCE
# ============================================================
if numChannels = 1
    selectObject: original
    analysisSound = Copy: originalName$ + "_analysis"
    analysisSource$ = "mono input"
else
    selectObject: original
    Convert to mono
    analysisSound = selected("Sound")
    Rename: originalName$ + "_analysis_fold"
    monoPeak = Get absolute extremum: 0, 0, "None"

    bestChannel = 1
    bestPeak = -1
    for ch from 1 to numChannels
        selectObject: original
        Extract one channel: ch
        chTmp = selected("Sound")
        chPeak = Get absolute extremum: 0, 0, "None"
        if chPeak > bestPeak
            bestPeak = chPeak
            bestChannel = ch
        endif
        removeObject: chTmp
    endfor

    if bestPeak > 0 and monoPeak < 0.10 * bestPeak
        removeObject: analysisSound
        selectObject: original
        Extract one channel: bestChannel
        analysisSound = selected("Sound")
        Rename: originalName$ + "_analysis_ch" + string$(bestChannel)
        analysisSource$ = "channel " + string$(bestChannel) + " (fold-down cancellation fallback)"
    else
        analysisSource$ = "mono fold-down"
    endif
endif

selectObject: analysisSound
if soundStart <> 0
    Shift times by: -soundStart
endif
analysisPeak = Get absolute extremum: 0, 0, "None"

appendInfoLine: "Analysis source: ", analysisSource$

# ============================================================
# WINDOWED SPECTRAL FEATURES
# ============================================================
analysisTimes# = zero#(num_analysis_points)
flatness# = zero#(num_analysis_points)
spreadNorm# = zero#(num_analysis_points)
centroid# = zero#(num_analysis_points)

halfWindow = window_size_seconds / 2
analysisSpan = max(0, duration - window_size_seconds)

for point from 1 to num_analysis_points
    if analysisSpan > 0
        analysisTimes#[point] = halfWindow + (point - 1) * analysisSpan / (num_analysis_points - 1)
        beginTime = analysisTimes#[point] - halfWindow
        endTime = analysisTimes#[point] + halfWindow
    else
        # Very short sound: reuse the whole sound at all analysis points but
        # distribute the control timestamps over the valid output domain.
        analysisTimes#[point] = (point - 1) * duration / (num_analysis_points - 1)
        beginTime = 0
        endTime = duration
    endif

    if analysisPeak <= 1e-15
        flatness#[point] = 0
        spreadNorm#[point] = 0
        centroid#[point] = 0
    else
        selectObject: analysisSound
        windowSound = Extract part: beginTime, endTime, "Hamming", 1, "no"
        selectObject: windowSound
        spectrum = To Spectrum: "no"

        selectObject: spectrum
        nBins = Get number of bins
        binWidth = Get bin width
        firstBin = max(1, ceiling(min_frequency_Hz / binWidth) + 1)
        lastBin = min(nBins, floor(max_frequency_Hz / binWidth) + 1)
        validBins = lastBin - firstBin + 1

        if validBins < 2
            removeObject: spectrum, windowSound, analysisSound
            exitScript: "Error: Analysis range contains too few FFT bins."
        endif

        linearSum = 0
        freqPowerSum = 0
        freq2PowerSum = 0

        for bin from firstBin to lastBin
            freq = (bin - 1) * binWidth
            re = object [spectrum, 1, bin]
            im = object [spectrum, 2, bin]
            power = re*re + im*im
            linearSum = linearSum + power
            freqPowerSum = freqPowerSum + freq * power
            freq2PowerSum = freq2PowerSum + freq * freq * power
        endfor

        if linearSum <= 1e-300
            flatness#[point] = 0
            spreadNorm#[point] = 0
            centroid#[point] = 0
        else
            meanPower = linearSum / validBins
            relativeFloor = max(1e-300, meanPower * 1e-12)
            lnSum = 0

            for bin from firstBin to lastBin
                re = object [spectrum, 1, bin]
                im = object [spectrum, 2, bin]
                power = max(relativeFloor, re*re + im*im)
                lnSum = lnSum + ln(power)
            endfor

            flatness#[point] = exp(lnSum / validBins) / meanPower
            flatness#[point] = min(1, max(0, flatness#[point]))

            centroid#[point] = freqPowerSum / linearSum
            spreadSquared = max(0, freq2PowerSum / linearSum - centroid#[point]^2)
            spread = sqrt(spreadSquared)
            analysisWidth = max_frequency_Hz - min_frequency_Hz
            spreadNorm#[point] = min(1, sqrt(12) * spread / analysisWidth)
        endif

        removeObject: spectrum, windowSound
    endif

    appendInfoLine: "  Window ", point, " @ ", fixed$(analysisTimes#[point], 3), " s: flatness=",
        ... fixed$(flatness#[point], 4), " spread=", fixed$(spreadNorm#[point], 4)
endfor

removeObject: analysisSound

# ============================================================
# BUILD RELATIVE-dB GAIN TRAJECTORY
# ============================================================
numGridPoints = ceiling(duration / controlStep) + 1
gainTier = Create IntensityTier: "spectral_gain", soundStart, soundEnd

maxVizPoints = min(numGridPoints, 500)
vizTimes# = zero#(maxVizPoints)
vizGainDb# = zero#(maxVizPoints)
vizFlatness# = zero#(maxVizPoints)
vizSpread# = zero#(maxVizPoints)
vizSpeed# = zero#(maxVizPoints)

currentPhase = 0
previousLocalTime = 0
segment = 1

avgFlat = 0
avgSpread = 0
avgDepth = 0
avgSpeed = 0

for i from 1 to numGridPoints
    localTime = min(duration, (i - 1) * controlStep)
    absTime = soundStart + localTime

    while segment < num_analysis_points - 1 and localTime > analysisTimes#[segment + 1]
        segment = segment + 1
    endwhile

    if localTime <= analysisTimes#[1]
        currentFlatness = flatness#[1]
        currentSpread = spreadNorm#[1]
    elsif localTime >= analysisTimes#[num_analysis_points]
        currentFlatness = flatness#[num_analysis_points]
        currentSpread = spreadNorm#[num_analysis_points]
    else
        segmentStart = analysisTimes#[segment]
        segmentEnd = analysisTimes#[segment + 1]
        if segmentEnd <= segmentStart
            progress = 0
        else
            progress = (localTime - segmentStart) / (segmentEnd - segmentStart)
        endif
        currentFlatness = flatness#[segment] + progress * (flatness#[segment + 1] - flatness#[segment])
        currentSpread = spreadNorm#[segment] + progress * (spreadNorm#[segment + 1] - spreadNorm#[segment])
    endif

    depthDb = base_depth_dB + currentFlatness * (max_depth_dB - base_depth_dB)
    modulationSpeed = base_mod_speed_Hz + currentSpread * (max_mod_speed_Hz - base_mod_speed_Hz)

    if currentFlatness < tonal_flatness_threshold and currentSpread < smooth_spread_threshold
        depthDb = depthDb * tonal_depth_reduction
        modulationSpeed = modulationSpeed * tonal_speed_reduction
    endif

    if i > 1
        dt = localTime - previousLocalTime
        currentPhase = currentPhase + 2*pi*modulationSpeed*dt
    endif

    # Attenuation-only tremolo. At phase zero gain is 0 dB, so the processed
    # signal begins without an artificial level step.
    gainDb = -0.5 * depthDb * (1 - cos(currentPhase))

    selectObject: gainTier
    Add point: absTime, gainDb

    avgFlat = avgFlat + currentFlatness
    avgSpread = avgSpread + currentSpread
    avgDepth = avgDepth + depthDb
    avgSpeed = avgSpeed + modulationSpeed
    previousLocalTime = localTime

    vizIdx = floor((i - 1) / numGridPoints * maxVizPoints) + 1
    if vizIdx >= 1 and vizIdx <= maxVizPoints
        vizTimes#[vizIdx] = localTime
        vizGainDb#[vizIdx] = gainDb
        vizFlatness#[vizIdx] = currentFlatness
        vizSpread#[vizIdx] = currentSpread
        vizSpeed#[vizIdx] = modulationSpeed
    endif
endfor

avgFlat = avgFlat / numGridPoints
avgSpread = avgSpread / numGridPoints
avgDepth = avgDepth / numGridPoints
avgSpeed = avgSpeed / numGridPoints

# ============================================================
# APPLY / MIX / SAFETY
# ============================================================
if dry_wet_percent <= 0 or max_depth_dB <= 0
    selectObject: original
    result = Copy: originalName$ + "_spectralIntensity_" + presetName$
else
    selectObject: original, gainTier
    wetSound = Multiply: "no"
    Rename: originalName$ + "_spectralIntensityWet"

    if dry_wet_percent >= 100
        result = wetSound
        selectObject: result
        Rename: originalName$ + "_spectralIntensity_" + presetName$
    else
        globalWet = dry_wet_percent / 100
        globalDry = 1 - globalWet
        globalOriginal = original

        selectObject: wetSound
        result = Copy: originalName$ + "_spectralIntensity_" + presetName$
        Formula: "'globalWet' * self + 'globalDry' * object ['globalOriginal', row, col]"
        removeObject: wetSound
    endif
endif

removeObject: gainTier

selectObject: result
peakBeforeSafety = Get absolute extremum: 0, 0, "None"
if dry_wet_percent > 0 and safety_peak > 0 and peakBeforeSafety > safety_peak
    Scale peak: safety_peak
endif
outputPeak = Get absolute extremum: 0, 0, "None"

appendInfoLine: ""
appendInfoLine: "Average flatness: ", fixed$(avgFlat, 4)
appendInfoLine: "Average normalized spread: ", fixed$(avgSpread, 4)
appendInfoLine: "Average derived depth: ", fixed$(avgDepth, 2), " dB"
appendInfoLine: "Average derived rate: ", fixed$(avgSpeed, 3), " Hz"
appendInfoLine: "Control step: ", fixed$(controlStep * 1000, 3), " ms"
appendInfoLine: "Peak before safety: ", fixed$(peakBeforeSafety, 6)
appendInfoLine: "Output peak: ", fixed$(outputPeak, 6)

# ============================================================
# VISUALIZATION - AudioTools house layout
# ============================================================
if draw_visualization
    Erase all
    Select outer viewport: 0, 8, 0, 8
    Colour: "Black"
    Font size: 10
    Line width: 1

    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Spectral-Driven Intensity Modulation##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... originalName$ + "  |  " + presetName$ + "  |  time-varying spectral analysis"

    # Input
    Select outer viewport: 0, 4.2, 0.75, 2.20
    Select inner viewport: 0.55, 4.00, 0.95, 2.08
    selectObject: original
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Input"
    Font size: 6
    Text left: "yes", "Amp"

    # Output
    Select outer viewport: 4.2, 8, 0.75, 2.20
    Select inner viewport: 4.55, 7.75, 0.95, 2.08
    selectObject: result
    Colour: "{0.22, 0.46, 0.82}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Output"
    Font size: 6
    Text left: "yes", "Amp"

    # Spectral drives
    Select outer viewport: 0, 4.2, 2.30, 4.20
    Select inner viewport: 0.55, 4.00, 2.52, 4.08
    Axes: 0, duration, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, 0, 1
    Colour: "{0.55, 0.55, 0.55}"
    Dotted line
    Draw line: 0, tonal_flatness_threshold, duration, tonal_flatness_threshold
    Colour: "{0.48, 0.35, 0.74}"
    Solid line
    Line width: 1.4
    for v from 2 to maxVizPoints
        if vizTimes#[v] > 0 and vizTimes#[v - 1] >= 0
            Draw line: vizTimes#[v - 1], vizFlatness#[v - 1], vizTimes#[v], vizFlatness#[v]
        endif
    endfor
    Colour: "{0.22, 0.46, 0.82}"
    Line width: 1
    for v from 2 to maxVizPoints
        if vizTimes#[v] > 0 and vizTimes#[v - 1] >= 0
            Draw line: vizTimes#[v - 1], vizSpread#[v - 1], vizTimes#[v], vizSpread#[v]
        endif
    endfor
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Spectral drives"
    Font size: 6
    Text left: "yes", "0..1"
    Text bottom: "yes", "Time (s)"

    # Gain trajectory
    Select outer viewport: 4.2, 8, 2.30, 4.20
    Select inner viewport: 4.55, 7.75, 2.52, 4.08
    Axes: 0, duration, -max(1, max_depth_dB), 0
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, -max(1, max_depth_dB), 0
    Colour: "{0.48, 0.35, 0.74}"
    Line width: 1.4
    for v from 2 to maxVizPoints
        if vizTimes#[v] > 0 and vizTimes#[v - 1] >= 0
            Draw line: vizTimes#[v - 1], vizGainDb#[v - 1], vizTimes#[v], vizGainDb#[v]
        endif
    endfor
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Gain modulation"
    Font size: 6
    Text left: "yes", "dB"
    Text bottom: "yes", "Time (s)"

    # Summary
    Select outer viewport: 0, 8, 4.35, 5.25
    Select inner viewport: 0.55, 7.75, 4.43, 5.18
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 7
    Text: 0.02, "left", 0.80, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.50, "half",
        ... "Flatness " + fixed$(avgFlat, 3) + "  |  spread " + fixed$(avgSpread, 3)
        ... + "  |  depth " + fixed$(avgDepth, 1) + " dB  |  rate " + fixed$(avgSpeed, 2) + " Hz"
    Text: 0.02, "left", 0.18, "half",
        ... "Wet " + fixed$(dry_wet_percent, 0) + "%  |  safety " + fixed$(safety_peak, 2)
        ... + "  |  " + fixed$(duration, 2) + " s / " + fixed$(sampling, 0) + " Hz / " + string$(numChannels) + " ch"

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

selectObject: result
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

if play_result
    Play
endif

selectObject: result
