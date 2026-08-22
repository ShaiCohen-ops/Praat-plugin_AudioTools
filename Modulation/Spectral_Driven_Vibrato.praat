# ============================================================
# Praat AudioTools - Spectral_Driven_Vibrato.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Global spectral-driven vibrato. A mono analysis copy is windowed
#   and measured over the requested frequency range. Spectral flatness
#   controls vibrato depth; normalized spectral spread controls rate.
#
#   The spectral descriptors are global file-level measurements, not
#   time-varying trackers. Processing preserves all source channels,
#   sample rate, sample count, duration, and start time.
#
#   Vibrato is implemented as a causal fractional-delay modulation.
#   The requested depth is mapped to an approximately symmetric pitch
#   excursion in semitones; the positive peak is exact by construction.
#
# Changelog v0.4:
#   - VISUALIZATION STANDARDIZATION ONLY; audio/DSP, analysis,
#     parameter mapping and rendering logic are unchanged.
#   - Standardized title/version, Picture-page restoration,
#     typography and summary/export behavior for AudioTools.
#
# v0.3 changes:
#   - Replaces amplitude-dependent raw-bin "roughness" with normalized
#     spectral spread for the rate mapping.
#   - Uses exact-length FFT, a Hann analysis window, and only the bins
#     inside the requested range.
#   - Uses direct Spectrum cell access instead of repeated query
#     commands for substantially faster analysis.
#   - Replaces future-reading integer delay with causal fractional
#     interpolation and local-time LFO modulation.
#   - Makes 0% wet (and zero modulation) an exact bypass.
#   - Removes forced peak normalization; Safety_peak only attenuates.
#   - Adds cancellation-safe mono analysis for multichannel sources.
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
sampleCount = Get number of samples
originalStart = Get start time
originalEnd = Get end time
numChannels = Get number of channels
nyquist = sampling / 2

form Spectral-Driven Vibrato v0.4
    optionmenu Preset: 1
        option Custom (use settings below)
        option Subtle Natural
        option Moderate Expressive
        option Strong Character
        option Fast Flutter
        option Slow Sweep

    comment --- Global spectral analysis ---
    positive Min_frequency_Hz: 80
    positive Max_frequency_Hz: 5000
    positive Spread_response: 1.0

    comment --- Depth mapping (semitones) ---
    real Base_depth: 0.05
    real Max_depth_add: 0.15

    comment --- Rate mapping (Hz) ---
    real Base_rate_Hz: 4.0
    real Max_rate_add_Hz: 3.0

    comment --- Delay line / output ---
    real Base_delay_ms: 5.0
    real Dry_wet_percent: 100
    real Safety_peak: 0.99
    boolean Draw_visualization: 1
    boolean Play_result: 1
endform

# ============================================================
# PRESETS
# ============================================================
if preset = 2
    base_depth = 0.03
    max_depth_add = 0.10
    base_rate_Hz = 5.0
    max_rate_add_Hz = 2.0
    spread_response = 1.0
    presetName$ = "Subtle"
elsif preset = 3
    base_depth = 0.05
    max_depth_add = 0.15
    base_rate_Hz = 4.5
    max_rate_add_Hz = 3.0
    spread_response = 1.0
    presetName$ = "Moderate"
elsif preset = 4
    base_depth = 0.08
    max_depth_add = 0.25
    base_rate_Hz = 4.0
    max_rate_add_Hz = 4.0
    spread_response = 1.0
    presetName$ = "Strong"
elsif preset = 5
    base_depth = 0.04
    max_depth_add = 0.10
    base_rate_Hz = 6.0
    max_rate_add_Hz = 4.0
    spread_response = 1.25
    presetName$ = "Flutter"
elsif preset = 6
    base_depth = 0.10
    max_depth_add = 0.20
    base_rate_Hz = 2.5
    max_rate_add_Hz = 2.0
    spread_response = 0.85
    presetName$ = "Slow"
else
    presetName$ = "Custom"
endif

# ============================================================
# VALIDATION
# ============================================================
if duration <= 0 or sampleCount < 2
    exitScript: "Error: Sound is too short."
endif

min_frequency_Hz = max(0, min_frequency_Hz)
max_frequency_Hz = min(0.98 * nyquist, max_frequency_Hz)
if max_frequency_Hz <= min_frequency_Hz
    exitScript: "Error: Analysis range must contain frequencies below Nyquist."
endif

spread_response = min(4, max(0, spread_response))
base_depth = min(2, max(0, base_depth))
max_depth_add = min(2, max(0, max_depth_add))
base_rate_Hz = min(50, max(0, base_rate_Hz))
max_rate_add_Hz = min(50, max(0, max_rate_add_Hz))
base_delay_ms = max(0, base_delay_ms)
dry_wet_percent = min(100, max(0, dry_wet_percent))
safety_peak = min(1, max(0, safety_peak))

appendInfoLine: "=== Spectral-Driven Vibrato v0.4 ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(duration, 3), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Channels: ", numChannels, " | Sample rate: ", fixed$(sampling, 0), " Hz"
appendInfoLine: "Analysis: global file-level spectrum"
appendInfoLine: ""

# ============================================================
# MONO ANALYSIS COPY WITH CANCELLATION FALLBACK
# ============================================================
if numChannels = 1
    selectObject: original
    analysisSound = Copy: originalName$ + "_sv_analysis"
    analysisSource$ = "mono input"
else
    selectObject: original
    analysisSound = Convert to mono
    Rename: originalName$ + "_sv_fold"
    monoPeak = Get absolute extremum: 0, 0, "None"

    bestChannel = 1
    bestPeak = -1
    for ch from 1 to numChannels
        selectObject: original
        Extract one channel: ch
        tmpCh = selected("Sound")
        chPeak = Get absolute extremum: 0, 0, "None"
        if chPeak > bestPeak
            bestPeak = chPeak
            bestChannel = ch
        endif
        removeObject: tmpCh
    endfor

    if bestPeak > 0 and monoPeak < 0.10 * bestPeak
        removeObject: analysisSound
        selectObject: original
        Extract one channel: bestChannel
        analysisSound = selected("Sound")
        Rename: originalName$ + "_sv_analysis_ch" + string$(bestChannel)
        analysisSource$ = "channel " + string$(bestChannel) + " (fold-down cancellation fallback)"
    else
        analysisSource$ = "mono fold-down"
    endif
endif

selectObject: analysisSound
analysisPeak = Get absolute extremum: 0, 0, "None"

# Visualization storage
maxVizBins = 300
vizFreqs# = zero#(maxVizBins)
vizPower# = zero#(maxVizBins)
vizCount = 0

# ============================================================
# GLOBAL SPECTRAL FEATURES
# ============================================================
if analysisPeak <= 1e-15
    flatness = 0
    centroid = 0
    spread = 0
    spreadNorm = 0
    validBins = 0
else
    # Hann-window only the disposable analysis copy.
    selectObject: analysisSound
    Formula: ~ self * (0.5 - 0.5 * cos(2*pi*(col-1)/(ncol-1)))

    To Spectrum: "no"
    spectrum = selected("Spectrum")
    nBins = Get number of bins
    binWidth = Get bin width

    firstBin = max(1, ceiling(min_frequency_Hz / binWidth) + 1)
    lastBin = min(nBins, floor(max_frequency_Hz / binWidth) + 1)
    validBins = lastBin - firstBin + 1
    if validBins < 2
        removeObject: spectrum, analysisSound
        exitScript: "Error: Analysis range contains too few FFT bins."
    endif

    vizStride = max(1, ceiling(validBins / maxVizBins))

    lnSum = 0
    linearSum = 0
    freqPowerSum = 0
    freq2PowerSum = 0

    for bin from firstBin to lastBin
        freq = (bin - 1) * binWidth
        re = object [spectrum, 1, bin]
        im = object [spectrum, 2, bin]
        power = re*re + im*im
        if power < 1e-300
            power = 1e-300
        endif

        lnSum = lnSum + ln(power)
        linearSum = linearSum + power
        freqPowerSum = freqPowerSum + freq * power
        freq2PowerSum = freq2PowerSum + freq * freq * power

        if ((bin - firstBin) mod vizStride = 0) and vizCount < maxVizBins
            vizCount = vizCount + 1
            vizFreqs#[vizCount] = freq
            vizPower#[vizCount] = 10 * log10(power)
        endif
    endfor

    meanPower = linearSum / validBins
    flatness = exp(lnSum / validBins) / meanPower
    flatness = min(1, max(0, flatness))

    centroid = freqPowerSum / linearSum
    spreadSquared = max(0, freq2PowerSum / linearSum - centroid*centroid)
    spread = sqrt(spreadSquared)

    analysisWidth = max_frequency_Hz - min_frequency_Hz
    spreadNorm = min(1, sqrt(12) * spread / analysisWidth)

    removeObject: spectrum
endif

removeObject: analysisSound

# ============================================================
# MAP FEATURES TO VIBRATO
# ============================================================
spreadDrive = min(1, max(0, spreadNorm * spread_response))
depth = min(2, max(0, base_depth + flatness * max_depth_add))
rate_hz = min(50, max(0, base_rate_Hz + spreadDrive * max_rate_add_Hz))

appendInfoLine: "Analysis source: ", analysisSource$
appendInfoLine: "Range: ", fixed$(min_frequency_Hz, 0), " - ", fixed$(max_frequency_Hz, 0), " Hz"
appendInfoLine: "Spectral flatness: ", fixed$(flatness, 5)
appendInfoLine: "Spectral centroid: ", fixed$(centroid, 1), " Hz"
appendInfoLine: "Spectral spread: ", fixed$(spread, 1), " Hz | normalized ", fixed$(spreadNorm, 4)
appendInfoLine: "Derived depth: ", fixed$(depth, 4), " st"
appendInfoLine: "Derived rate: ", fixed$(rate_hz, 3), " Hz"
appendInfoLine: ""

# ============================================================
# CAUSAL FRACTIONAL-DELAY VIBRATO
# ============================================================
bypass = 0
if dry_wet_percent <= 0 or depth <= 0 or rate_hz <= 0
    bypass = 1
endif

if bypass
    selectObject: original
    result = Copy: originalName$ + "_spectralVib_" + presetName$
    effectiveBaseDelay = 0
    delayExcursion = 0
    pitchRatioExcursion = 0
    maxDelay = 0
else
    # A sinusoidal delay D(t) has pitch ratio approximately 1-D'(t).
    # Choose D excursion so the positive pitch peak equals +depth semitones.
    pitchRatioExcursion = 2^(depth/12) - 1
    delayExcursion = pitchRatioExcursion / (2*pi*rate_hz)

    # Keep the delay trajectory causal and feasible for the source duration.
    maxDelayAllowed = max(4/sampling, 0.45 * duration)
    maxExcursion = max(0, 0.5 * (maxDelayAllowed - 2/sampling))
    if delayExcursion > maxExcursion
        delayExcursion = maxExcursion
        pitchRatioExcursion = 2*pi*rate_hz*delayExcursion
        depth = 12 * log2(1 + pitchRatioExcursion)
        appendInfoLine: "Depth clamped for causal delay: ", fixed$(depth, 4), " st"
    endif

    minBaseDelay = delayExcursion + 2/sampling
    effectiveBaseDelay = max(base_delay_ms/1000, minBaseDelay)
    if effectiveBaseDelay + delayExcursion > maxDelayAllowed
        effectiveBaseDelay = max(minBaseDelay, maxDelayAllowed - delayExcursion)
        appendInfoLine: "Base delay clamped to fit source duration."
    endif
    maxDelay = effectiveBaseDelay + delayExcursion

    globalOriginal = original
    globalStart = originalStart
    globalRate = rate_hz
    globalBaseDelay = effectiveBaseDelay
    globalDelayExcursion = delayExcursion
    globalMaxDelay = maxDelay
    globalWet = dry_wet_percent / 100

    selectObject: original
    result = Copy: originalName$ + "_spectralVib_" + presetName$
    selectObject: result

    # Causal fractional interpolation via object(id, time, channel).
    # Fade from dry to the filled delay line during the initial maxDelay.
    Formula: ~ object(globalOriginal, x, row) * (1 - globalWet * min(1, max(0, (x-globalStart)/globalMaxDelay))) + globalWet * min(1, max(0, (x-globalStart)/globalMaxDelay)) * object(globalOriginal, x - (globalBaseDelay - globalDelayExcursion*cos(2*pi*globalRate*(x-globalStart))), row)
endif

selectObject: result
Rename: originalName$ + "_spectralVib_" + presetName$

# Attenuation-only safety; exact bypass remains exact.
peakBeforeSafety = Get absolute extremum: 0, 0, "None"
if bypass = 0 and safety_peak > 0 and peakBeforeSafety > safety_peak
    Scale peak: safety_peak
endif
outputPeak = Get absolute extremum: 0, 0, "None"

appendInfoLine: "Effective base delay: ", fixed$(effectiveBaseDelay*1000, 3), " ms"
appendInfoLine: "Delay excursion: +/-", fixed$(delayExcursion*1000, 4), " ms"
appendInfoLine: "Dry/Wet: ", fixed$(dry_wet_percent, 1), "%"
appendInfoLine: "Peak before safety: ", fixed$(peakBeforeSafety, 6)
appendInfoLine: "Output peak: ", fixed$(outputPeak, 6)

# ============================================================
# VISUALIZATION - AudioTools house layout
# ============================================================
if draw_visualization
    pageHeight = 7.0
    if safety_peak > 0
        safeStr$ = fixed$(safety_peak, 2)
    else
        safeStr$ = "off"
    endif

    Erase all
    Select outer viewport: 0, 8, 0, pageHeight
    Colour: "Black"
    Font size: 10
    Line width: 1

    # ---- TITLE ----
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Spectral-Driven Vibrato v0.4##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.22, "half", originalName$ + "  |  " + presetName$ + "  |  global spectral mapping"

    # ---- INPUT ----
    Select outer viewport: 0, 4.2, 0.65, 2.15
    Select inner viewport: 0.55, 4.00, 0.83, 2.03
    selectObject: original
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Input"
    Font size: 6
    Text left: "yes", "Amp"

    # ---- OUTPUT ----
    Select outer viewport: 4.2, 8, 0.65, 2.15
    Select inner viewport: 4.55, 7.75, 0.83, 2.03
    selectObject: result
    Colour: "{0.22, 0.46, 0.82}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Output"
    Font size: 6
    Text left: "yes", "Amp"

    # ---- GLOBAL SPECTRUM ----
    Select outer viewport: 0, 8, 2.25, 4.15
    Select inner viewport: 0.55, 7.75, 2.45, 4.02

    if vizCount > 0
        minPow = vizPower#[1]
        maxPow = vizPower#[1]
        for v from 2 to vizCount
            minPow = min(minPow, vizPower#[v])
            maxPow = max(maxPow, vizPower#[v])
        endfor
        if maxPow - minPow < 20
            minPow = maxPow - 20
        endif
    else
        minPow = -120
        maxPow = 0
    endif

    Axes: min_frequency_Hz, max_frequency_Hz, minPow, maxPow
    Paint rectangle: "{0.97, 0.97, 0.97}", min_frequency_Hz, max_frequency_Hz, minPow, maxPow
    if vizCount > 1
        Colour: "{0.48, 0.35, 0.74}"
        Line width: 1.2
        for v from 2 to vizCount
            Draw line: vizFreqs#[v-1], vizPower#[v-1], vizFreqs#[v], vizPower#[v]
        endfor
    endif
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Analysis spectrum"
    Font size: 6
    Text left: "yes", "dB"
    Text bottom: "yes", "Frequency (Hz)"

    # ---- ACTUAL PITCH TRAJECTORY ----
    Select outer viewport: 0, 8, 4.25, 5.75
    Select inner viewport: 0.55, 7.75, 4.43, 5.62
    pitchDisplayDur = min(1, duration)

    if bypass
        centsMin = -0.1
        centsMax = 0.1
    else
        lowRatio = max(1e-6, 1 - pitchRatioExcursion)
        centsMin = 12*log2(lowRatio)
        centsMax = 12*log2(1 + pitchRatioExcursion)
        if centsMax - centsMin < 0.1
            centsMin = -0.05
            centsMax = 0.05
        endif
    endif

    Axes: 0, pitchDisplayDur, centsMin*1.15, centsMax*1.15
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, pitchDisplayDur, centsMin*1.15, centsMax*1.15
    Colour: "{0.75, 0.75, 0.75}"
    Dotted line
    Draw line: 0, 0, pitchDisplayDur, 0
    Solid line

    if bypass = 0
        Colour: "{0.48, 0.35, 0.74}"
        Line width: 1.4
        nPitchPts = 300
        for p from 2 to nPitchPts
            t1 = (p-2)/(nPitchPts-1)*pitchDisplayDur
            t2 = (p-1)/(nPitchPts-1)*pitchDisplayDur
            r1 = max(1e-6, 1 - pitchRatioExcursion*sin(2*pi*rate_hz*t1))
            r2 = max(1e-6, 1 - pitchRatioExcursion*sin(2*pi*rate_hz*t2))
            c1 = 12*log2(r1)
            c2 = 12*log2(r2)
            Draw line: t1, c1, t2, c2
        endfor
    endif

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Pitch modulation"
    Font size: 6
    Text left: "yes", "Semitones"
    Text bottom: "yes", "Local time (s)"

    # ---- SUMMARY ----
    Select outer viewport: 0, 8, 5.88, 6.78
    Select inner viewport: 0.55, 7.75, 5.96, 6.70
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.80, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.50, "half", "Flatness " + fixed$(flatness, 4) + " -> depth " + fixed$(depth, 3) + " st  |  Spread " + fixed$(spreadNorm, 3) + " -> rate " + fixed$(rate_hz, 2) + " Hz"
    Text: 0.02, "left", 0.18, "half", "Range " + fixed$(min_frequency_Hz, 0) + "-" + fixed$(max_frequency_Hz, 0) + " Hz  |  wet " + fixed$(dry_wet_percent, 0) + "%  |  safety " + safeStr$ + "  |  " + fixed$(duration, 2) + " s / " + string$(numChannels) + " ch"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
    # Restore full Picture page for export
    Select outer viewport: 0, 8, 0, pageHeight
    Axes: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

selectObject: result
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

if play_result
    Play
endif

selectObject: result
