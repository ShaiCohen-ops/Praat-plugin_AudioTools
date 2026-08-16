# ============================================================
# Praat AudioTools - Spectral Swirl Effect.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.2 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Global nearest-bin spectral warp. For Praat bin index k=1..K,
#   the processor reads one input complex bin at
#
#       srcBin(k) = round(k + (A/df) * sin(2*pi*N*k/K))
#
#   with edge clamping. A is Maximum_shift_hz, df is FFT-bin width,
#   and N is number_of_cycles.
#   Real and imaginary parts are moved together, so each copied
#   complex bin retains its source phase. The nearest-bin remap is
#   intentionally retained as part of the effect's musical character.
#
# Changelog v0.4.3 (2026):
#   - FADE: fade-out now reaches zero before EOF and holds true digital silence
#     for End_silence_ms at the tail. This makes the fade visibly and audibly
#     complete, rather than reaching zero only on the final sample.
#   - FADE: End_silence_ms is included inside Fade_out_ms; 0 ms Fade disables
#     both ramp and silence hold.
#   - VIZ/QC: reports and marks the actual zero/silence point.
#
# Changelog v0.4.2 (2026):
#   - OUTPUT: adds a final raised-cosine fade-out after wet/dry mixing
#     and peak scaling. The default is 50 ms; 0 ms disables it.
#   - CLICK SAFETY: the last output sample reaches exactly zero when the
#     fade contains at least two samples, reducing end-of-file clicks.
#   - VIZ/QC: panel D marks the actual fade region and the footer/report
#     state the realized fade duration.
#   - DSP: spectral-swirl mapping itself is unchanged from v0.4/v0.4.1.
#
# Changelog v0.4.1 (2026):
#   - VIZ/READABILITY: separates the global title and transform law into
#     independent viewport strips so text cannot collide.
#   - VIZ/READABILITY: panel B uses one compact header line; the measured
#     source->output mapping no longer sits underneath the panel title.
#   - VIZ/AXES: logarithmic frequency ticks suppress Praat's automatic
#     numeric coordinate labels and show only 50, 100, 200, 500, 1k...
#   - VIZ/AXES: warp-law frequency ticks use readable kHz labels rather
#     than scientific notation.
#   - VIZ/QC: replaces the crowded two-line footer with one concise line.
#   - DSP: no audio-processing changes from v0.4.
#
# Changelog v0.4 (2026):
#   - VERIFY: the core effect is a global FFT frequency-axis warp,
#     not a time-varying modulation and not additive frequency shifting.
#   - PRESERVE: retains the original v0.3 phase law col/ncols exactly.
#     With nearest-bin quantization, shifting the phase origin by even
#     one bin changes audible bin assignments; the legacy law is part
#     of the effect character and is therefore not normalized away.
#   - DSP/VIZ: builds one explicit nearest-bin mapping Matrix and uses
#     that same mapping for the Spectrum formula and the visualization.
#   - SIMPLIFY: applies Formula directly to frozen Spectrum objects;
#     the Spectrum->Matrix->Spectrum round trip is no longer needed.
#   - STEREO: stereo input is processed channel-by-channel when stereo
#     output is requested; the original stereo image is no longer
#     collapsed to mono. Mono input retains the legacy 12 ms Haas
#     character, but the delay is now wet-only and user-adjustable.
#   - MIX: dry path is unprocessed and row-aware. At 0 percent wet,
#     no peak normalization is applied.
#   - VIZ: mechanism-first 2x2 layout: exact warp law, measured local
#     peak mapping, smoothed spectral-change curve, and source/final
#     waveforms on the same amplitude scale.
#   - QC: reports realized shift, edge clamping, duplicate/reverse map
#     steps, representative channel, and RMS change.
# ============================================================

form Spectral Swirl Effect v0.4.3
    optionmenu Preset: 1
        option Custom
        option Gentle Wobble
        option Liquid Metal
        option Alien Voice
        option Underwater Warble
        option Extreme Mangle
    comment === Swirl Parameters ===
    natural number_of_cycles 4
    positive Maximum_shift_hz 35
    comment === Mix / Stereo ===
    real wet_dry_percent 100
    boolean stereo_output 1
    positive Stereo_delay_ms 12
    comment === Output ===
    positive scale_peak 0.95
    real Fade_out_ms 50
    real End_silence_ms 5
    boolean draw_visualization 1
    boolean play_after_processing 1
endform

# ---------------------------
# Presets
# ---------------------------
presetName$ = "Custom"
if preset = 2
    number_of_cycles = 2
    maximum_shift_hz = 10
    presetName$ = "GentleWobble"
elsif preset = 3
    number_of_cycles = 6
    maximum_shift_hz = 25
    presetName$ = "LiquidMetal"
elsif preset = 4
    number_of_cycles = 8
    maximum_shift_hz = 50
    presetName$ = "AlienVoice"
elsif preset = 5
    number_of_cycles = 3
    maximum_shift_hz = 20
    presetName$ = "UnderwaterWarble"
elsif preset = 6
    number_of_cycles = 12
    maximum_shift_hz = 100
    presetName$ = "ExtremeMangle"
endif

# ---------------------------
# Input / validation
# ---------------------------
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

originalID = selected("Sound")
sound$ = selected$("Sound")
selectObject: originalID
original_sr = Get sampling frequency
duration = Get total duration
n_channels = Get number of channels

if n_channels > 2
    exitScript: "Spectral Swirl v0.4.3 supports mono or stereo Sound input."
endif

wet_dry_percent = max(0, min(100, wet_dry_percent))
wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level
stereo_delay_ms = max(0, stereo_delay_ms)
fade_out_ms = max(0, fade_out_ms)
end_silence_ms = max(0, end_silence_ms)

timingDummy = stopwatch

writeInfoLine: "SPECTRAL SWIRL v0.4.3"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Duration: ", fixed$(duration, 3), " s"
appendInfoLine: "Original SR: ", original_sr, " Hz"
appendInfoLine: "Channels: ", n_channels
appendInfoLine: "Cycles parameter (legacy index law): ", number_of_cycles
appendInfoLine: "Requested max shift: ", fixed$(maximum_shift_hz, 2), " Hz"
appendInfoLine: "Wet/Dry: ", fixed$(wet_dry_percent, 0), "%"
appendInfoLine: "Fade out: ", fixed$(fade_out_ms, 1), " ms requested"
appendInfoLine: "End silence: ", fixed$(end_silence_ms, 1), " ms requested (inside fade region)"

# ---------------------------
# Prepare source channels and dry path
# ---------------------------
# ch1Source / ch2Source are the actual channels used by the spectral DSP.
selectObject: originalID
if n_channels = 1
    Copy: "swirl_src_1"
    ch1Source = selected("Sound")
    ch2Source = 0
    repChannel = 1
else
    if stereo_output
        Extract one channel: 1
        ch1Source = selected("Sound")
        selectObject: originalID
        Extract one channel: 2
        ch2Source = selected("Sound")

        selectObject: ch1Source
        rms1 = Get root-mean-square: 0, 0
        selectObject: ch2Source
        rms2 = Get root-mean-square: 0, 0
        if rms2 > rms1
            repChannel = 2
        else
            repChannel = 1
        endif
    else
        Convert to mono
        ch1Source = selected("Sound")
        ch2Source = 0
        repChannel = 1
    endif
endif

# Dry output has the channel layout requested by stereo_output.
if stereo_output
    if n_channels = 2
        selectObject: originalID
        Copy: "swirl_dry_stereo"
        dryID = selected("Sound")
    else
        selectObject: originalID
        Copy: "swirl_dry_L"
        dryL = selected("Sound")
        selectObject: originalID
        Copy: "swirl_dry_R"
        dryR = selected("Sound")
        selectObject: dryL
        plusObject: dryR
        Combine to stereo
        dryID = selected("Sound")
        removeObject: dryL, dryR
    endif
else
    if n_channels = 1
        selectObject: originalID
        Copy: "swirl_dry_mono"
        dryID = selected("Sound")
    else
        selectObject: originalID
        Convert to mono
        dryID = selected("Sound")
        Rename: "swirl_dry_mono"
    endif
endif

# ---------------------------
# Build reference Spectrum and exact mapping ledger
# ---------------------------
appendInfoLine: ""
appendInfoLine: "[1/4] Building spectral warp law..."
selectObject: ch1Source
To Spectrum: "yes"
srcSpec1 = selected("Spectrum")
binWidth = Get bin width
ncols = object[srcSpec1].nx
nyq = original_sr / 2
shiftBins = maximum_shift_hz / binWidth

if ncols < 2
    exitScript: "Input is too short for spectral warping."
endif

# The mapping stores the source bin read by every output bin.
Create simple Matrix: "swirl_map", 1, ncols,
    ... "round(max(1, min(ncols, col + shiftBins * sin(2*pi*number_of_cycles*col/ncols))))"
mapID = selected("Matrix")

# Mapping QC from the exact ledger used by the DSP.
realized_max_shift = 0
edge_clamped = 0
duplicate_steps = 0
reverse_steps = 0
prevSrcCol = object[mapID, 1, 1]
for c from 1 to ncols
    srcCol = object[mapID, 1, c]
    dHz = (srcCol - c) * binWidth
    if abs(dHz) > realized_max_shift
        realized_max_shift = abs(dHz)
    endif
    phase01 = c / ncols
    idealCol = c + shiftBins * sin(2*pi*number_of_cycles*phase01)
    if idealCol < 1 or idealCol > ncols
        edge_clamped += 1
    endif
    if c > 1
        if srcCol = prevSrcCol
            duplicate_steps += 1
        elsif srcCol < prevSrcCol
            reverse_steps += 1
        endif
    endif
    prevSrcCol = srcCol
endfor

appendInfoLine: "      FFT bin width: ", fixed$(binWidth, 5), " Hz"
appendInfoLine: "      Requested depth: ", fixed$(shiftBins, 2), " bins"
appendInfoLine: "      Realized max shift: ", fixed$(realized_max_shift, 2), " Hz"
appendInfoLine: "      Edge-clamped bins: ", edge_clamped
appendInfoLine: "      Duplicate map steps: ", duplicate_steps
appendInfoLine: "      Reverse map steps: ", reverse_steps
if reverse_steps > 0
    appendInfoLine: "      NOTE: non-monotonic spectral folds are active at this SR/depth/cycle setting."
endif

# ---------------------------
# Process channel 1
# ---------------------------
appendInfoLine: "[2/4] Warping complex spectrum..."
selectObject: srcSpec1
Copy: "swirl_spec_1"
wetSpec1 = selected("Spectrum")
Formula: "object[" + string$(srcSpec1) + ", row, object[" + string$(mapID) + ", 1, col]]"

selectObject: wetSpec1
To Sound
wet1 = selected("Sound")
Override sampling frequency: original_sr
wet1Dur = Get total duration
if wet1Dur > duration
    Extract part: 0, duration, "rectangular", 1, "no"
    wet1Trim = selected("Sound")
    removeObject: wet1
    wet1 = wet1Trim
endif
Rename: "swirl_wet_1"

# ---------------------------
# Process stereo channel 2 when preserving stereo
# ---------------------------
srcSpec2 = 0
wetSpec2 = 0
wet2 = 0
if n_channels = 2 and stereo_output
    selectObject: ch2Source
    To Spectrum: "yes"
    srcSpec2 = selected("Spectrum")
    if object[srcSpec2].nx <> ncols
        exitScript: "Stereo channels produced incompatible FFT sizes."
    endif
    selectObject: srcSpec2
    Copy: "swirl_spec_2"
    wetSpec2 = selected("Spectrum")
    Formula: "object[" + string$(srcSpec2) + ", row, object[" + string$(mapID) + ", 1, col]]"

    selectObject: wetSpec2
    To Sound
    wet2 = selected("Sound")
    Override sampling frequency: original_sr
    wet2Dur = Get total duration
    if wet2Dur > duration
        Extract part: 0, duration, "rectangular", 1, "no"
        wet2Trim = selected("Sound")
        removeObject: wet2
        wet2 = wet2Trim
    endif
    Rename: "swirl_wet_2"
endif

# Representative source/wet branch for measurement and visualization.
if repChannel = 2 and wet2 <> 0
    vizSrcRef = ch2Source
    vizWetRef = wet2
    vizSrcSpecRef = srcSpec2
    vizWetSpecRef = wetSpec2
else
    vizSrcRef = ch1Source
    vizWetRef = wet1
    vizSrcSpecRef = srcSpec1
    vizWetSpecRef = wetSpec1
endif

# ---------------------------
# Construct wet output channel layout
# ---------------------------
appendInfoLine: "[3/4] Building output channels..."
if stereo_output
    if n_channels = 2
        selectObject: wet1
        plusObject: wet2
        Combine to stereo
        wetID = selected("Sound")
        Rename: "swirl_wet_stereo"
    else
        # Preserve the historical mono-input Haas character, but on WET only.
        delay_samples = round(stereo_delay_ms * 0.001 * original_sr)
        wet1Str$ = string$(wet1)
        delayStr$ = string$(delay_samples)
        Create Sound from formula: "swirl_wet_L", 1, 0, duration, original_sr,
            ... "object[" + wet1Str$ + ", 1, col]"
        wetL = selected("Sound")
        Create Sound from formula: "swirl_wet_R", 1, 0, duration, original_sr,
            ... "if col > " + delayStr$ + " then object[" + wet1Str$ + ", 1, col - " + delayStr$ + "] else 0 fi"
        wetR = selected("Sound")
        selectObject: wetL
        plusObject: wetR
        Combine to stereo
        wetID = selected("Sound")
        Rename: "swirl_wet_stereo"
        removeObject: wetL, wetR
    endif
else
    wetID = wet1
endif

# ---------------------------
# Wet/dry and final level
# ---------------------------
appendInfoLine: "[4/4] Mixing wet/dry..."
if wet_level = 0
    selectObject: dryID
    Copy: "swirl_result"
    resultID = selected("Sound")
elsif dry_level = 0
    selectObject: wetID
    Copy: "swirl_result"
    resultID = selected("Sound")
    Scale peak: scale_peak
else
    wetStr$ = string$(wet_level)
    dryStr$ = string$(dry_level)
    dryIDStr$ = string$(dryID)
    selectObject: wetID
    Copy: "swirl_result"
    resultID = selected("Sound")
    Formula: "self * " + wetStr$ + " + object[" + dryIDStr$ + ", row, col] * " + dryStr$
    Scale peak: scale_peak
endif

# Final fade-to-silence. The requested Fade_out_ms is the total tail region:
# a raised-cosine ramp reaches exactly zero, then the last End_silence_ms are
# held at true digital silence. This is intentionally the final amplitude step.
selectObject: resultID
result_n_samples = object[resultID].nx
fade_samples = round(fade_out_ms * 0.001 * original_sr)
fade_samples = min(result_n_samples, max(0, fade_samples))
if fade_samples = 1
    fade_samples = min(2, result_n_samples)
endif
if fade_samples >= 2
    # Keep the silence hold inside the requested fade region. Leave at least
    # two samples for a proper cosine ramp whenever possible.
    silence_samples = round(end_silence_ms * 0.001 * original_sr)
    silence_samples = max(1, silence_samples)
    silence_samples = min(silence_samples, max(1, fade_samples - 2))
    ramp_samples = fade_samples - silence_samples
    if ramp_samples < 2
        ramp_samples = 2
        silence_samples = max(0, fade_samples - ramp_samples)
    endif

    fade_start_col = result_n_samples - fade_samples + 1
    zero_start_col = fade_start_col + ramp_samples - 1
    fade_denom = ramp_samples - 1
    fadeStartStr$ = string$(fade_start_col)
    zeroStartStr$ = string$(zero_start_col)
    fadeDenomStr$ = string$(fade_denom)

    Formula: "if col >= " + zeroStartStr$ + " then 0 else if col >= " + fadeStartStr$ + " then self * 0.5 * (1 + cos(pi * (col - " + fadeStartStr$ + ") / " + fadeDenomStr$ + ")) else self fi fi"

    realized_fade_ms = 1000 * (fade_samples - 1) / original_sr
    realized_silence_ms = 1000 * (result_n_samples - zero_start_col + 1) / original_sr
    fade_start_time = max(0, duration - realized_fade_ms / 1000)
    zero_start_time = max(0, duration - realized_silence_ms / 1000)
else
    silence_samples = 0
    ramp_samples = 0
    realized_fade_ms = 0
    realized_silence_ms = 0
    fade_start_time = duration
    zero_start_time = duration
endif

selectObject: resultID
Rename: sound$ + "_swirl_" + presetName$
processingTime = stopwatch

# ---------------------------
# Measurement values used by visualization / QC
# ---------------------------
selectObject: vizSrcRef
srcRms = Get root-mean-square: 0, 0
srcPeak = Get absolute extremum: 0, 0, "None"
selectObject: vizWetRef
wetRms = Get root-mean-square: 0, 0
selectObject: resultID
finalRms = Get root-mean-square: 0, 0
finalPeak = Get absolute extremum: 0, 0, "None"
if srcRms > 0
    wetRmsDb = 20 * log10(max(wetRms, 1e-30) / srcRms)
    finalRmsDb = 20 * log10(max(finalRms, 1e-30) / srcRms)
else
    wetRmsDb = 0
    finalRmsDb = 0
endif

# Find the strongest non-DC source component in the representative channel.
peakStartHz = min(40, 0.1 * nyq)
startCol = max(2, round(peakStartHz / binWidth) + 1)
srcPeakSpecCol = startCol
srcPeakMag2 = 0
for c from startCol to ncols
    re = object[vizSrcSpecRef, 1, c]
    im = object[vizSrcSpecRef, 2, c]
    mag2 = re*re + im*im
    if mag2 > srcPeakMag2
        srcPeakMag2 = mag2
        srcPeakSpecCol = c
    endif
endfor
srcPeakHz = (srcPeakSpecCol - 1) * binWidth

# Find the output bin whose actual ledger reads nearest to that source bin.
bestOutCol = 1
bestMapError = 1e30
for c from 1 to ncols
    srcReadCol = object[mapID, 1, c]
    mapError = abs(srcReadCol - srcPeakSpecCol)
    if mapError < bestMapError
        bestMapError = mapError
        bestOutCol = c
    endif
endfor
mappedReadCol = object[mapID, 1, bestOutCol]
mappedReadHz = (mappedReadCol - 1) * binWidth
mappedOutHz = (bestOutCol - 1) * binWidth

# ---------------------------
# Visualization
# ---------------------------
if draw_visualization
    # Representative final channel: strongest original channel when stereo,
    # left channel for generated stereo from mono.
    selectObject: resultID
    finalChannels = Get number of channels
    if finalChannels > 1
        finalVizChannel = repChannel
        if n_channels = 1
            finalVizChannel = 1
        endif
        Extract one channel: finalVizChannel
        vizFinal = selected("Sound")
    else
        Copy: "swirl_viz_final"
        vizFinal = selected("Sound")
    endif

    # Common waveform range.
    selectObject: vizSrcRef
    srcAbs = Get absolute extremum: 0, 0, "None"
    selectObject: vizFinal
    finalAbs = Get absolute extremum: 0, 0, "None"
    waveAbs = max(srcAbs, finalAbs)
    if waveAbs <= 0
        waveAbs = 1
    endif
    waveAbs = 1.08 * waveAbs

    # Smoothed spectral-change range, measured from actual source and pure wet spectra.
    specPoints = 90
    fMinPlot = max(40, 4 * binWidth)
    fMaxPlot = nyq * 0.98
    if fMaxPlot <= fMinPlot
        fMinPlot = binWidth
        fMaxPlot = nyq
    endif
    maxSpecDelta = 0
    for i from 1 to specPoints
        frac = (i - 1) / (specPoints - 1)
        fHz = 10^(log10(fMinPlot) + frac * (log10(fMaxPlot) - log10(fMinPlot)))
        centreCol = round(fHz / binWidth) + 1
        halfHz = max(4 * binWidth, 0.025 * fHz)
        halfBins = max(2, round(halfHz / binWidth))
        lo = max(2, centreCol - halfBins)
        hi = min(ncols, centreCol + halfBins)
        pSrc = 0
        pWet = 0
        countBins = hi - lo + 1
        for b from lo to hi
            sr = object[vizSrcSpecRef, 1, b]
            si = object[vizSrcSpecRef, 2, b]
            wr = object[vizWetSpecRef, 1, b]
            wi = object[vizWetSpecRef, 2, b]
            pSrc += sr*sr + si*si
            pWet += wr*wr + wi*wi
        endfor
        pSrc /= countBins
        pWet /= countBins
        deltaDb = 10 * log10((pWet + 1e-30) / (pSrc + 1e-30))
        if abs(deltaDb) > maxSpecDelta
            maxSpecDelta = abs(deltaDb)
        endif
    endfor
    specY = max(3, min(30, 1.1 * maxSpecDelta))

    Erase all

    # Overall title and transform law use independent strips.
    # Keeping these viewports separate prevents font-size-dependent collisions.
    Select outer viewport: 0.4, 7.8, 0.04, 0.25
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.50, "half", "Spectral Swirl v0.4.1 — " + presetName$

    Select outer viewport: 0.4, 7.8, 0.28, 0.46
    Axes: 0, 1, 0, 1
    Font size: 6.5
    Colour: "{0.35,0.35,0.35}"
    Text: 0.5, "centre", 0.50, "half", "k <- round(k + A/df * sin(2*pi*N*k/K))   |   nearest-bin complex remap"

    # =======================
    # A: ACTUAL WARP LAW
    # =======================
    Select outer viewport: 0.3, 3.95, 0.60, 2.60
    Select inner viewport: 0.72, 3.72, 1.02, 2.36
    shiftY = max(1, 1.15 * max(maximum_shift_hz, realized_max_shift))
    Axes: 0, nyq, -shiftY, shiftY
    Paint rectangle: "{0.97,0.97,0.97}", 0, nyq, -shiftY, shiftY
    Colour: "{0.78,0.78,0.78}"
    Draw line: 0, 0, nyq, 0

    # Requested continuous law (thin gray)
    Colour: "{0.55,0.55,0.55}"
    Line width: 1
    lawPoints = 300
    for i from 1 to lawPoints
        frac = (i - 1) / (lawPoints - 1)
        fHz = frac * nyq
        phaseLegacy = (1 + fHz / binWidth) / ncols
        dIdeal = maximum_shift_hz * sin(2*pi*number_of_cycles*phaseLegacy)
        if i > 1
            Draw line: prevLawF, prevLawD, fHz, dIdeal
        endif
        prevLawF = fHz
        prevLawD = dIdeal
    endfor

    # Exact discrete ledger used by DSP (blue)
    Colour: "{0.15,0.42,0.68}"
    Line width: 1.5
    mapPoints = min(600, ncols)
    for i from 1 to mapPoints
        c = round(1 + (i - 1) * (ncols - 1) / (mapPoints - 1))
        fHz = (c - 1) * binWidth
        dActual = (object[mapID, 1, c] - c) * binWidth
        if i > 1
            Draw line: prevMapF, prevMapD, fHz, dActual
        endif
        prevMapF = fHz
        prevMapD = dActual
    endfor
    Line width: 1
    # Compact in-panel legend
    legendX = 0.03 * nyq
    legendLen = 0.08 * nyq
    legendY1 = 0.88 * shiftY
    legendY2 = 0.68 * shiftY
    Colour: "{0.55,0.55,0.55}"
    Draw line: legendX, legendY1, legendX + legendLen, legendY1
    Colour: "Black"
    Font size: 6
    Text: legendX + 1.15*legendLen, "left", legendY1, "half", "requested law"
    Colour: "{0.15,0.42,0.68}"
    Line width: 1.5
    Draw line: legendX, legendY2, legendX + legendLen, legendY2
    Line width: 1
    Colour: "Black"
    Text: legendX + 1.15*legendLen, "left", legendY2, "half", "realized bins"
    Draw inner box
    # Readable quarter-Nyquist labels; suppress raw/scientific coordinate text.
    aTick0 = 0
    aTick1 = nyq/4
    aTick2 = nyq/2
    aTick3 = 3*nyq/4
    aTick4 = nyq
    aTick0$ = "0"
    if aTick1 >= 1000
        aTick1$ = fixed$(aTick1/1000, 1) + "k"
        aTick2$ = fixed$(aTick2/1000, 1) + "k"
        aTick3$ = fixed$(aTick3/1000, 1) + "k"
        aTick4$ = fixed$(aTick4/1000, 1) + "k"
    else
        aTick1$ = fixed$(aTick1, 0)
        aTick2$ = fixed$(aTick2, 0)
        aTick3$ = fixed$(aTick3, 0)
        aTick4$ = fixed$(aTick4, 0)
    endif
    One mark bottom: aTick0, "no", "yes", "no", aTick0$
    One mark bottom: aTick1, "no", "yes", "no", aTick1$
    One mark bottom: aTick2, "no", "yes", "no", aTick2$
    One mark bottom: aTick3, "no", "yes", "no", aTick3$
    One mark bottom: aTick4, "no", "yes", "no", aTick4$
    Marks left every: 1, max(1, maximum_shift_hz/2), "yes", "yes", "no"
    Text bottom: "yes", "Output frequency (Hz)"
    Text left: "yes", "Source read offset (Hz)"

    Select outer viewport: 0.3, 3.95, 0.60, 0.88
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.5, "centre", 0.55, "half", "A  WARP LAW"

    # =======================
    # B: LOCAL MEASURED MAPPING
    # =======================
    Select outer viewport: 4.05, 7.75, 0.60, 2.60
    Select inner viewport: 4.46, 7.53, 1.02, 2.36
    localHalf = max(180, 4 * maximum_shift_hz)
    localMin = max(0, srcPeakHz - localHalf)
    localMax = min(nyq, srcPeakHz + localHalf)
    if localMax <= localMin
        localMin = 0
        localMax = nyq
    endif

    # Find a common local magnitude reference.
    loCol = max(1, round(localMin / binWidth) + 1)
    hiCol = min(ncols, round(localMax / binWidth) + 1)
    localMaxMag = 1e-30
    for c from loCol to hiCol
        sr = object[vizSrcSpecRef, 1, c]
        si = object[vizSrcSpecRef, 2, c]
        wr = object[vizWetSpecRef, 1, c]
        wi = object[vizWetSpecRef, 2, c]
        localMaxMag = max(localMaxMag, sqrt(sr*sr + si*si), sqrt(wr*wr + wi*wi))
    endfor
    Axes: localMin, localMax, -50, 3
    Paint rectangle: "{0.97,0.97,0.97}", localMin, localMax, -50, 3

    # Source spectrum local trace
    Colour: "{0.55,0.55,0.55}"
    Line width: 1
    localPoints = min(500, hiCol - loCol + 1)
    for i from 1 to localPoints
        c = round(loCol + (i - 1) * (hiCol - loCol) / max(1, localPoints - 1))
        fHz = (c - 1) * binWidth
        sr = object[vizSrcSpecRef, 1, c]
        si = object[vizSrcSpecRef, 2, c]
        valDb = 20*log10((sqrt(sr*sr + si*si) + 1e-30) / localMaxMag)
        valDb = max(-50, valDb)
        if i > 1
            Draw line: prevLocalF, prevLocalSrc, fHz, valDb
        endif
        prevLocalF = fHz
        prevLocalSrc = valDb
    endfor

    # Pure wet local trace
    Colour: "{0.15,0.42,0.68}"
    Line width: 1.5
    for i from 1 to localPoints
        c = round(loCol + (i - 1) * (hiCol - loCol) / max(1, localPoints - 1))
        fHz = (c - 1) * binWidth
        wr = object[vizWetSpecRef, 1, c]
        wi = object[vizWetSpecRef, 2, c]
        valDb = 20*log10((sqrt(wr*wr + wi*wi) + 1e-30) / localMaxMag)
        valDb = max(-50, valDb)
        if i > 1
            Draw line: prevLocalWetF, prevLocalWet, fHz, valDb
        endif
        prevLocalWetF = fHz
        prevLocalWet = valDb
    endfor
    Line width: 1
    # Compact trace legend
    legendLX = localMin + 0.04*(localMax-localMin)
    legendLL = 0.12*(localMax-localMin)
    Colour: "{0.55,0.55,0.55}"
    Draw line: legendLX, -5, legendLX + legendLL, -5
    Colour: "Black"
    Font size: 6
    Text: legendLX + 1.15*legendLL, "left", -5, "half", "source"
    Colour: "{0.15,0.42,0.68}"
    Line width: 1.5
    Draw line: legendLX, -12, legendLX + legendLL, -12
    Line width: 1
    Colour: "Black"
    Text: legendLX + 1.15*legendLL, "left", -12, "half", "pure wet"

    # Measured/predicted landing markers from actual map ledger.
    Colour: "{0.45,0.45,0.45}"
    Draw line: srcPeakHz, -50, srcPeakHz, 3
    Colour: "{0.75,0.20,0.18}"
    Draw line: mappedOutHz, -50, mappedOutHz, 3
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, max(50, localHalf/2), "yes", "yes", "no"
    Marks left every: 1, 10, "yes", "yes", "no"
    Text bottom: "yes", "Frequency (Hz)"
    Text left: "yes", "Relative magnitude (dB)"

    Select outer viewport: 4.05, 7.75, 0.60, 0.88
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Font size: 9
    Text: 0.00, "left", 0.50, "half", "B  LOCAL PROOF"
    Font size: 6.5
    Colour: "{0.35,0.35,0.35}"
    mappingText$ = fixed$(srcPeakHz, 1) + " Hz -> " + fixed$(mappedOutHz, 1) + " Hz"
    Text: 1.00, "right", 0.50, "half", mappingText$

    # =======================
    # C: GLOBAL SPECTRAL CHANGE
    # =======================
    Select outer viewport: 0.3, 3.95, 2.82, 4.82
    Select inner viewport: 0.72, 3.72, 3.22, 4.56
    Axes: log10(fMinPlot), log10(fMaxPlot), -specY, specY
    Paint rectangle: "{0.97,0.97,0.97}", log10(fMinPlot), log10(fMaxPlot), -specY, specY
    Colour: "{0.78,0.78,0.78}"
    Draw line: log10(fMinPlot), 0, log10(fMaxPlot), 0
    Colour: "{0.15,0.42,0.68}"
    Line width: 1.5
    for i from 1 to specPoints
        frac = (i - 1) / (specPoints - 1)
        fHz = 10^(log10(fMinPlot) + frac * (log10(fMaxPlot) - log10(fMinPlot)))
        centreCol = round(fHz / binWidth) + 1
        halfHz = max(4 * binWidth, 0.025 * fHz)
        halfBins = max(2, round(halfHz / binWidth))
        lo = max(2, centreCol - halfBins)
        hi = min(ncols, centreCol + halfBins)
        pSrc = 0
        pWet = 0
        countBins = hi - lo + 1
        for b from lo to hi
            sr = object[vizSrcSpecRef, 1, b]
            si = object[vizSrcSpecRef, 2, b]
            wr = object[vizWetSpecRef, 1, b]
            wi = object[vizWetSpecRef, 2, b]
            pSrc += sr*sr + si*si
            pWet += wr*wr + wi*wi
        endfor
        pSrc /= countBins
        pWet /= countBins
        deltaDb = 10 * log10((pWet + 1e-30) / (pSrc + 1e-30))
        xlog = log10(fHz)
        if i > 1
            Draw line: prevSpecX, prevSpecD, xlog, deltaDb
        endif
        prevSpecX = xlog
        prevSpecD = deltaDb
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks left every: 1, max(1, specY/3), "yes", "yes", "no"
    Text left: "yes", "Wet - source (dB)"
    # Manual logarithmic frequency marks (axis coordinates are log10 Hz).
    if fMinPlot <= 50 and 50 <= fMaxPlot
        One mark bottom: log10(50), "no", "yes", "no", "50"
    endif
    if fMinPlot <= 100 and 100 <= fMaxPlot
        One mark bottom: log10(100), "no", "yes", "no", "100"
    endif
    if fMinPlot <= 200 and 200 <= fMaxPlot
        One mark bottom: log10(200), "no", "yes", "no", "200"
    endif
    if fMinPlot <= 500 and 500 <= fMaxPlot
        One mark bottom: log10(500), "no", "yes", "no", "500"
    endif
    if fMinPlot <= 1000 and 1000 <= fMaxPlot
        One mark bottom: log10(1000), "no", "yes", "no", "1k"
    endif
    if fMinPlot <= 2000 and 2000 <= fMaxPlot
        One mark bottom: log10(2000), "no", "yes", "no", "2k"
    endif
    if fMinPlot <= 5000 and 5000 <= fMaxPlot
        One mark bottom: log10(5000), "no", "yes", "no", "5k"
    endif
    if fMinPlot <= 10000 and 10000 <= fMaxPlot
        One mark bottom: log10(10000), "no", "yes", "no", "10k"
    endif
    if fMinPlot <= 20000 and 20000 <= fMaxPlot
        One mark bottom: log10(20000), "no", "yes", "no", "20k"
    endif
    Text bottom: "yes", "Frequency (Hz, log)"

    Select outer viewport: 0.3, 3.95, 2.82, 3.10
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.5, "centre", 0.55, "half", "C  MEASURED SPECTRAL CHANGE"

    # =======================
    # D: TIME-DOMAIN CONSEQUENCE
    # =======================
    Select outer viewport: 4.05, 7.75, 2.82, 4.82
    Select inner viewport: 4.46, 7.53, 3.22, 3.78
    selectObject: vizSrcRef
    Colour: "{0.50,0.50,0.50}"
    Draw: 0, duration, -waveAbs, waveAbs, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6.5
    Text left: "yes", "Source"

    Select outer viewport: 4.05, 7.75, 2.82, 4.82
    Select inner viewport: 4.46, 7.53, 4.00, 4.56
    selectObject: vizFinal
    Colour: "{0.15,0.42,0.68}"
    Draw: 0, duration, -waveAbs, waveAbs, "no", "Curve"
    if realized_fade_ms > 0
        Select outer viewport: 4.05, 7.75, 2.82, 4.82
        Select inner viewport: 4.46, 7.53, 4.00, 4.56
        Axes: 0, duration, -waveAbs, waveAbs
        Colour: "{0.68,0.68,0.68}"
        Draw line: fade_start_time, -waveAbs, fade_start_time, waveAbs
        Colour: "{0.35,0.35,0.35}"
        Font size: 5.8
        Text: fade_start_time, "left", 0.78*waveAbs, "half", " fade"
        if realized_silence_ms > 0
            Colour: "{0.72,0.72,0.72}"
            Draw line: zero_start_time, -waveAbs, zero_start_time, waveAbs
            Colour: "{0.35,0.35,0.35}"
            Text: zero_start_time, "right", -0.78*waveAbs, "half", "zero "
        endif
    endif
    Select outer viewport: 4.05, 7.75, 2.82, 4.82
    Select inner viewport: 4.46, 7.53, 4.00, 4.56
    Axes: 0, duration, -waveAbs, waveAbs
    Colour: "Black"
    Draw inner box
    Font size: 6.5
    Text left: "yes", "Final"
    Text bottom: "yes", "Time (s)"

    Select outer viewport: 4.05, 7.75, 2.82, 3.10
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.5, "centre", 0.55, "half", "D  TIME-DOMAIN CONSEQUENCE"

    # Bottom summary strip: one line only.
    Select outer viewport: 0.4, 7.7, 4.96, 5.22
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95,0.95,0.95}", 0, 1, 0, 1
    Colour: "Black"
    Font size: 6.5
    summary$ = "A=" + fixed$(maximum_shift_hz, 1) + " Hz | cycles=" + string$(number_of_cycles) + " | realized=" + fixed$(realized_max_shift, 1) + " Hz | reverse=" + string$(reverse_steps) + " | wet=" + fixed$(wet_dry_percent, 0) + " pct | fade=" + fixed$(realized_fade_ms, 0) + " ms | final RMS/source=" + fixed$(finalRmsDb, 1) + " dB | peak=" + fixed$(finalPeak, 3)
    Text: 0.5, "centre", 0.50, "half", summary$

    removeObject: vizFinal
    Font size: 10
    Colour: "Black"
endif

# ---------------------------
# Report / cleanup
# ---------------------------
appendInfoLine: ""
appendInfoLine: "COMPLETE"
appendInfoLine: "Representative channel: ", repChannel
appendInfoLine: "Strongest source component: ", fixed$(srcPeakHz, 2), " Hz"
appendInfoLine: "Nearest mapped output: ", fixed$(mappedOutHz, 2), " Hz (reads ", fixed$(mappedReadHz, 2), " Hz)"
appendInfoLine: "Wet RMS / source: ", fixed$(wetRmsDb, 2), " dB"
appendInfoLine: "Final RMS / source: ", fixed$(finalRmsDb, 2), " dB"
appendInfoLine: "Realized fade region: ", fixed$(realized_fade_ms, 2), " ms"
appendInfoLine: "Final digital silence: ", fixed$(realized_silence_ms, 2), " ms"
appendInfoLine: "Processing time: ", fixed$(processingTime, 3), " s"

# Keep only final output and the user's original Sound.
if srcSpec2 <> 0
    removeObject: srcSpec2, wetSpec2
endif
if ch2Source <> 0
    removeObject: ch2Source
endif
if wet2 <> 0
    removeObject: wet2
endif
if wetID <> wet1
    removeObject: wetID
endif
removeObject: ch1Source, srcSpec1, wetSpec1, mapID, wet1, dryID

selectObject: resultID
if play_after_processing
    Play
endif
selectObject: resultID
