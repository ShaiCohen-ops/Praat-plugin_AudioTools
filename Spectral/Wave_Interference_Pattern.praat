# ============================================================
# Praat AudioTools - Wave_Interference_Pattern.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.5 (2026)
# License: MIT License
#
# Description:
#   Creates a static spectral interference / moire pattern by multiplying
#   FFT bins by the non-negative gain law
#
#       G[k] = |sin(k / Ds) + W cos(k / Dc)| * B[k]
#
#   below a cutoff, where B[k] is a linear brightness ramp. The same gain
#   multiplies the real and imaginary parts of every complex bin, so the
#   operation changes spectral magnitude while preserving bin phase.
#
#   IMPORTANT: this is a whole-file FFT-domain spectral pattern, not a
#   time-varying phaser or temporal beating effect. Ds and Dc are measured
#   in FFT bins, so the pattern spacing in Hz depends on input duration.
#   That duration dependence is an intentional part of this processor.
#
# Changelog v0.5:
#   - Corrected the promise: static spectral interference / moire, not LFO phasing
#   - Preserves stereo input by processing L/R independently
#   - True dry path; wet=0 is an unscaled dry bypass
#   - Mono->stereo keeps the library 12 ms character on the wet signal only
#   - Exact gain ledger is built once and used by both DSP and visualization
#   - Cutoff is clamped to the realizable FFT range
#   - Visualization rebuilt in the AudioTools 2x2 house layout
#   - Added target-vs-measured transfer proof and shared spectral/time scales
#
# Usage:
#   Select exactly one mono or stereo Sound object and run this script.
# ============================================================

form Wave Interference Pattern v0.5
    optionmenu Preset: 1
        option Custom
        option Strong Spectral Interference
        option Subtle Spectral Interference
        option Alien Radio
        option Slow Spectral Moire
        option Metallic Ring
        option Underwater Transmission
    comment === Interference law ===
    comment (divisors are FFT-bin units; Hz spacing therefore depends on input duration)
    positive Frequency_cutoff_hz 11000
    positive Sine_divisor 800
    positive Cosine_divisor 1200
    real Cosine_weight 0.5
    comment === Tone ===
    positive Brightness_compensation 1.2
    comment (1 = neutral ramp; >1 progressively boosts higher patterned bins)
    comment === Mix / channels ===
    real Wet_dry_percent 100
    comment (0 = dry only with no peak scaling, 100 = full wet)
    boolean Stereo_output 1
    real Stereo_delay_ms 12
    comment (stereo input is preserved; mono uses wet-only stereo delay)
    comment === Output ===
    positive Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_after_processing 1
endform

# ---------------------------
# Selection / input facts
# ---------------------------
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")
selectObject: originalID
original_sr = Get sampling frequency
duration = Get total duration
n_channels = Get number of channels
nyq = original_sr / 2

if n_channels > 2
    exitScript: "Wave Interference Pattern v0.5 supports mono or stereo Sound input."
endif

# ---------------------------
# Presets
# ---------------------------
presetName$ = "Custom"
if preset = 2
    sine_divisor = 400
    cosine_divisor = 600
    cosine_weight = 0.8
    brightness_compensation = 1.5
    presetName$ = "StrongInterference"
elsif preset = 3
    sine_divisor = 1200
    cosine_divisor = 2000
    cosine_weight = 0.2
    brightness_compensation = 1.1
    presetName$ = "SubtleInterference"
elsif preset = 4
    sine_divisor = 150
    cosine_divisor = 160
    cosine_weight = 0.9
    brightness_compensation = 2.0
    presetName$ = "AlienRadio"
elsif preset = 5
    # Close bin-domain periods create a slow moire envelope across frequency.
    sine_divisor = 2000
    cosine_divisor = 2005
    cosine_weight = 1.0
    brightness_compensation = 1.0
    presetName$ = "SlowSpectralMoire"
elsif preset = 6
    sine_divisor = 300
    cosine_divisor = 450
    cosine_weight = 0.7
    brightness_compensation = 1.8
    presetName$ = "MetallicRing"
elsif preset = 7
    sine_divisor = 500
    cosine_divisor = 700
    cosine_weight = 0.6
    brightness_compensation = 0.8
    frequency_cutoff_hz = 6000
    presetName$ = "UnderwaterTransmission"
endif

# ---------------------------
# Validation / user controls
# ---------------------------
if sine_divisor <= 0 or cosine_divisor <= 0
    exitScript: "Sine and cosine divisors must be greater than zero."
endif
if cosine_weight < 0
    exitScript: "Cosine weight must be zero or greater."
endif
if brightness_compensation <= 0
    exitScript: "Brightness compensation must be greater than zero."
endif
if stereo_delay_ms < 0
    stereo_delay_ms = 0
endif
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif
wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

writeInfoLine: "=== Wave Interference Pattern v0.5 ==="
appendInfoLine: "Algorithm: whole-file FFT -> static bin-domain interference gain -> IFFT"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Input: ", n_channels, " ch | ", fixed$(original_sr,0), " Hz | ", fixed$(duration,3), " s"
appendInfoLine: "Divisors: sin ", sine_divisor, " bins | cos ", cosine_divisor, " bins"
appendInfoLine: "Cosine weight: ", fixed$(cosine_weight,3), " | brightness: ", fixed$(brightness_compensation,3)
appendInfoLine: "Wet: ", fixed$(wet_dry_percent,0), "%"

# ---------------------------
# Prepare source and dry path
# ---------------------------
# stereo_output=0 intentionally produces mono output from a stereo source.
if n_channels = 2 and not stereo_output
    selectObject: originalID
    processMono = Convert to mono
    selectObject: processMono
    dryID = Copy: "interference_dry_mono"
    process_channels = 1
elsif n_channels = 1
    selectObject: originalID
    processMono = Copy: "interference_process_mono"
    if stereo_output
        selectObject: originalID
        dryID = Convert to stereo
        Rename: "interference_dry_stereo"
    else
        selectObject: originalID
        dryID = Copy: "interference_dry_mono"
    endif
    process_channels = 1
else
    selectObject: originalID
    dryID = Copy: "interference_dry_stereo"
    process_channels = 2
endif

# Object ledgers used by cleanup / visualization.
monoSourceSpec = 0
monoWetSpec = 0
monoWet = 0
leftWork = 0
rightWork = 0
leftSourceSpec = 0
leftWetSpec = 0
rightSourceSpec = 0
rightWetSpec = 0
leftWet = 0
rightWet = 0
wetLeft = 0
wetRight = 0
repChannel = 1

# ---------------------------
# Build first spectrum and exact gain ledger
# ---------------------------
if process_channels = 1
    selectObject: processMono
    monoSourceSpec = To Spectrum: "yes"
    Rename: "interference_source_spectrum"
    refSpec = monoSourceSpec
else
    selectObject: originalID
    leftWork = Extract one channel: 1
    Rename: "interference_left_work"
    rmsL = Get root-mean-square: 0, 0
    selectObject: originalID
    rightWork = Extract one channel: 2
    Rename: "interference_right_work"
    rmsR = Get root-mean-square: 0, 0
    if rmsR > rmsL
        repChannel = 2
    endif

    selectObject: leftWork
    leftSourceSpec = To Spectrum: "yes"
    Rename: "interference_source_spectrum_L"
    refSpec = leftSourceSpec
endif

selectObject: refSpec
binWidth = Get bin width
nBins = Get number of bins
if nBins < 2
    exitScript: "Input is too short for FFT interference processing."
endif

# Preserve the legacy col-based law exactly, while clamping its cutoff to the FFT.
cutoff_bin_requested = round(frequency_cutoff_hz / binWidth)
cutoff_bin = min(nBins + 1, max(1, cutoff_bin_requested))
actual_cutoff_hz = min(nyq, frequency_cutoff_hz)
last_pattern_col = cutoff_bin - 1
if last_pattern_col >= 1
    last_pattern_hz = max(0, (last_pattern_col - 1) * binWidth)
else
    last_pattern_hz = 0
endif

sDiv$ = fixed$(sine_divisor, 2)
cDiv$ = fixed$(cosine_divisor, 2)
cWeight$ = fixed$(cosine_weight, 4)
bright$ = fixed$(brightness_compensation, 4)
cutBin$ = string$(cutoff_bin)
nBins$ = string$(nBins)

# This Matrix is the exact scalar gain applied to BOTH Spectrum rows.
Create simple Matrix: "interference_gain_map", 1, nBins,
    ... "if col < " + cutBin$ + " then abs(sin(col / " + sDiv$ + ") + " + cWeight$ + " * cos(col / " + cDiv$ + ")) * (1 + (col / " + nBins$ + ") * (" + bright$ + " - 1)) else 1 fi"
gainMap = selected("Matrix")
gainMap$ = string$(gainMap)
gainFormula$ = "self * object[" + gainMap$ + ", 1, col]"

appendInfoLine: "FFT bin width: ", fixed$(binWidth,6), " Hz"
appendInfoLine: "Requested cutoff: ", fixed$(frequency_cutoff_hz,1), " Hz | realizable: ", fixed$(actual_cutoff_hz,1), " Hz"
appendInfoLine: "Last patterned bin centre: ", fixed$(last_pattern_hz,2), " Hz"

# ---------------------------
# FFT processing
# ---------------------------
if process_channels = 1
    selectObject: monoSourceSpec
    monoWetSpec = Copy: "interference_wet_spectrum"
    Formula: gainFormula$
    selectObject: monoWetSpec
    monoWet = To Sound
    wetDur = Get total duration
    if wetDur > duration
        trimmedWet = Extract part: 0, duration, "rectangular", 1, "no"
        removeObject: monoWet
        monoWet = trimmedWet
    endif

    if stereo_output and n_channels = 1
        # Library character: mono input may become stereo, but only the WET is delayed.
        delay_samples = round((stereo_delay_ms / 1000) * original_sr)
        monoWet$ = string$(monoWet)
        Create Sound from formula: "interference_wet_left", 1, 0, duration, original_sr,
            ... "object[" + monoWet$ + ", 1, col]"
        wetLeft = selected("Sound")
        Create Sound from formula: "interference_wet_right", 1, 0, duration, original_sr,
            ... "if col > " + string$(delay_samples) + " then object[" + monoWet$ + ", 1, col - " + string$(delay_samples) + "] else 0 fi"
        wetRight = selected("Sound")
        selectObject: wetLeft
        plusObject: wetRight
        wetID = Combine to stereo
    else
        wetID = monoWet
    endif
else
    # Process left spectrum with the exact shared gain ledger.
    selectObject: leftSourceSpec
    leftWetSpec = Copy: "interference_wet_spectrum_L"
    Formula: gainFormula$
    selectObject: leftWetSpec
    leftWet = To Sound
    wetDurL = Get total duration
    if wetDurL > duration
        trimmedL = Extract part: 0, duration, "rectangular", 1, "no"
        removeObject: leftWet
        leftWet = trimmedL
    endif

    # Right channel uses the same law but retains its own complex spectrum.
    selectObject: rightWork
    rightSourceSpec = To Spectrum: "yes"
    Rename: "interference_source_spectrum_R"
    selectObject: rightSourceSpec
    rightWetSpec = Copy: "interference_wet_spectrum_R"
    Formula: gainFormula$
    selectObject: rightWetSpec
    rightWet = To Sound
    wetDurR = Get total duration
    if wetDurR > duration
        trimmedR = Extract part: 0, duration, "rectangular", 1, "no"
        removeObject: rightWet
        rightWet = trimmedR
    endif

    selectObject: leftWet
    plusObject: rightWet
    wetID = Combine to stereo
endif

# ---------------------------
# Wet/dry and output
# ---------------------------
if wet_level = 0
    selectObject: dryID
    resultID = Copy: originalName$ + "_" + presetName$
else
    selectObject: wetID
    resultID = Copy: "interference_mix"
    Formula: "self * " + string$(wet_level) + " + object[" + string$(dryID) + ", row, col] * " + string$(dry_level)
    Rename: originalName$ + "_" + presetName$

    # Keep the legacy target-peak behaviour when wet processing is present.
    currentPeak = Get absolute extremum: 0, 0, "None"
    if currentPeak > 0
        Scale peak: scale_peak
    endif
endif

# ---------------------------
# Visualization / measurement
# ---------------------------
if draw_visualization
    # Representative channel and matching source/wet spectra.
    if process_channels = 2
        if repChannel = 2
            vizSrcSpecRef = rightSourceSpec
            vizWetSpecRef = rightWetSpec
            selectObject: rightWork
            vizSrc = Copy: "interference_viz_source"
        else
            vizSrcSpecRef = leftSourceSpec
            vizWetSpecRef = leftWetSpec
            selectObject: leftWork
            vizSrc = Copy: "interference_viz_source"
        endif
        selectObject: resultID
        vizFinal = Extract one channel: repChannel
    else
        vizSrcSpecRef = monoSourceSpec
        vizWetSpecRef = monoWetSpec
        selectObject: processMono
        vizSrc = Copy: "interference_viz_source"
        selectObject: resultID
        outChannels = Get number of channels
        if outChannels = 2
            vizFinal = Extract one channel: 1
        else
            vizFinal = Copy: "interference_viz_final"
        endif
    endif

    # Shared waveform scale.
    selectObject: vizSrc
    srcPeak = Get absolute extremum: 0, 0, "None"
    selectObject: vizFinal
    finalPeak = Get absolute extremum: 0, 0, "None"
    waveAbs = 1.05 * max(srcPeak, finalPeak, 1e-6)

    # Exact gain-law range for panels A/B.
    if actual_cutoff_hz < nyq
        lawMaxFreq = min(nyq, max(1000, actual_cutoff_hz * 1.12))
    else
        lawMaxFreq = nyq
    endif
    if lawMaxFreq <= 0
        lawMaxFreq = nyq
    endif
    lawMaxCol = min(nBins, max(2, round(lawMaxFreq / binWidth) + 1))
    lawMaxGain = 1
    lawPoints = 500
    for i from 1 to lawPoints
        c = round(1 + (i - 1) / (lawPoints - 1) * (lawMaxCol - 1))
        g = object[gainMap, 1, c]
        lawMaxGain = max(lawMaxGain, g)
    endfor
    lawYmax = max(1.2, 1.08 * lawMaxGain)

    # Reference magnitude and target-vs-measured transfer QC.
    specRefMag = 1e-30
    qcPoints = 360
    for i from 1 to qcPoints
        c = round(1 + (i - 1) / (qcPoints - 1) * (nBins - 1))
        sr = object[vizSrcSpecRef, 1, c]
        si = object[vizSrcSpecRef, 2, c]
        srcMag = sqrt(sr*sr + si*si)
        specRefMag = max(specRefMag, srcMag)
    endfor

    proofSSE = 0
    proofN = 0
    measuredMaxDb = 0
    for i from 1 to qcPoints
        c = round(1 + (i - 1) / (qcPoints - 1) * (lawMaxCol - 1))
        g = object[gainMap, 1, c]
        targetDb = 20 * log10(max(g, 0.0001))
        sr = object[vizSrcSpecRef, 1, c]
        si = object[vizSrcSpecRef, 2, c]
        wr = object[vizWetSpecRef, 1, c]
        wi = object[vizWetSpecRef, 2, c]
        srcMag = sqrt(sr*sr + si*si)
        wetMag = sqrt(wr*wr + wi*wi)
        if srcMag > specRefMag * 1e-9
            measuredDb = 20 * log10(max(wetMag / srcMag, 0.0001))
            targetQc = max(-80, targetDb)
            measuredQc = max(-80, measuredDb)
            proofSSE += (measuredQc - targetQc)^2
            proofN += 1
            measuredMaxDb = max(measuredMaxDb, measuredDb)
        endif
    endfor
    if proofN > 0
        proofRmse = sqrt(proofSSE / proofN)
    else
        proofRmse = undefined
    endif
    proofYmin = -48
    proofYmax = max(6, ceiling(max(measuredMaxDb, 20*log10(max(lawMaxGain,1))) / 6) * 6 + 3)

    # Smoothed source/pure-wet spectral reference for panel C.
    fMinPlot = max(30, binWidth)
    fMaxPlot = nyq
    if fMaxPlot <= fMinPlot
        fMinPlot = max(binWidth, 1)
    endif
    specPoints = 130
    specRefPower = 1e-30
    for i from 1 to specPoints
        frac = (i - 1) / (specPoints - 1)
        fHz = 10^(log10(fMinPlot) + frac * (log10(fMaxPlot) - log10(fMinPlot)))
        c = round(fHz / binWidth) + 1
        c = min(nBins, max(1, c))
        halfHz = max(4*binWidth, 0.02*fHz)
        halfBins = max(2, round(halfHz/binWidth))
        lo = max(2, c-halfBins)
        hi = min(nBins, c+halfBins)
        pSrc = 0
        pWet = 0
        countBins = hi-lo+1
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
        specRefPower = max(specRefPower, pSrc, pWet)
    endfor

    Erase all

    # Title and process strips.
    Select outer viewport: 0.4, 7.8, 0.04, 0.25
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.50, "half", "Wave Interference Pattern v0.5 - " + presetName$

    Select outer viewport: 0.4, 7.8, 0.28, 0.46
    Axes: 0, 1, 0, 1
    Font size: 6.3
    Colour: "{0.35,0.35,0.35}"
    Text: 0.5, "centre", 0.50, "half", "FFT -> G[k] = abs(sin(k/Ds) + W cos(k/Dc)) x brightness -> IFFT   |   static spectral moire; bin phase preserved"

    # =======================
    # A: EXACT GAIN LAW
    # =======================
    Select outer viewport: 0.3, 3.95, 0.60, 2.60
    Select inner viewport: 0.72, 3.72, 1.02, 2.36
    Axes: 0, lawMaxFreq, 0, lawYmax
    Paint rectangle: "{0.97,0.97,0.97}", 0, lawMaxFreq, 0, lawYmax
    Colour: "{0.80,0.80,0.80}"
    Draw line: 0, 1, lawMaxFreq, 1

    # Requested/effective cutoff marker.
    if actual_cutoff_hz > 0 and actual_cutoff_hz < lawMaxFreq
        Colour: "{0.75,0.35,0.30}"
        Draw line: actual_cutoff_hz, 0, actual_cutoff_hz, lawYmax
    endif

    # Exact ledger used by the DSP, sampled only for drawing.
    Colour: "{0.15,0.42,0.68}"
    Line width: 1.5
    for i from 1 to lawPoints
        c = round(1 + (i - 1) / (lawPoints - 1) * (lawMaxCol - 1))
        fHz = (c - 1) * binWidth
        g = object[gainMap, 1, c]
        if i > 1
            Draw line: prevLawF, prevLawG, fHz, g
        endif
        prevLawF = fHz
        prevLawG = g
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 0.5, "yes", "yes", "no"
    Text left: "yes", "Gain"
    One mark bottom: 0, "no", "yes", "no", "0"
    One mark bottom: lawMaxFreq/4, "no", "yes", "no", fixed$(lawMaxFreq/4000,1) + "k"
    One mark bottom: lawMaxFreq/2, "no", "yes", "no", fixed$(lawMaxFreq/2000,1) + "k"
    One mark bottom: 3*lawMaxFreq/4, "no", "yes", "no", fixed$(3*lawMaxFreq/4000,1) + "k"
    One mark bottom: lawMaxFreq, "no", "yes", "no", fixed$(lawMaxFreq/1000,1) + "k"
    Text bottom: "yes", "Frequency (Hz)"

    Select outer viewport: 0.3, 3.95, 0.60, 0.88
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.5, "centre", 0.55, "half", "A  EXACT GAIN LAW"

    # =======================
    # B: TRANSFER PROOF
    # =======================
    Select outer viewport: 4.05, 7.75, 0.60, 2.60
    Select inner viewport: 4.46, 7.53, 1.02, 2.36
    Axes: 0, lawMaxFreq, proofYmin, proofYmax
    Paint rectangle: "{0.97,0.97,0.97}", 0, lawMaxFreq, proofYmin, proofYmax
    Colour: "{0.80,0.80,0.80}"
    Draw line: 0, 0, lawMaxFreq, 0

    # Target law in gray.
    Colour: "{0.55,0.55,0.55}"
    Line width: 1
    for i from 1 to qcPoints
        c = round(1 + (i - 1) / (qcPoints - 1) * (lawMaxCol - 1))
        fHz = (c - 1) * binWidth
        g = object[gainMap, 1, c]
        targetDb = max(proofYmin, min(proofYmax, 20*log10(max(g,0.0001))))
        if i > 1
            Draw line: prevTargetF, prevTargetDb, fHz, targetDb
        endif
        prevTargetF = fHz
        prevTargetDb = targetDb
    endfor

    # Measured magnitude ratio in blue, only where source energy is measurable.
    Colour: "{0.15,0.42,0.68}"
    Line width: 1.5
    havePrev = 0
    for i from 1 to qcPoints
        c = round(1 + (i - 1) / (qcPoints - 1) * (lawMaxCol - 1))
        fHz = (c - 1) * binWidth
        sr = object[vizSrcSpecRef, 1, c]
        si = object[vizSrcSpecRef, 2, c]
        wr = object[vizWetSpecRef, 1, c]
        wi = object[vizWetSpecRef, 2, c]
        srcMag = sqrt(sr*sr + si*si)
        wetMag = sqrt(wr*wr + wi*wi)
        if srcMag > specRefMag * 1e-9
            measuredDb = max(proofYmin, min(proofYmax, 20*log10(max(wetMag/srcMag,0.0001))))
            if havePrev
                Draw line: prevProofF, prevProofDb, fHz, measuredDb
            endif
            prevProofF = fHz
            prevProofDb = measuredDb
            havePrev = 1
        else
            havePrev = 0
        endif
    endfor
    Line width: 1

    # Compact legend.
    legendF = 0.06 * lawMaxFreq
    legendLen = 0.12 * lawMaxFreq
    Colour: "{0.55,0.55,0.55}"
    Draw line: legendF, proofYmax-6, legendF+legendLen, proofYmax-6
    Colour: "Black"
    Font size: 6
    Text: legendF+1.15*legendLen, "left", proofYmax-6, "half", "target"
    Colour: "{0.15,0.42,0.68}"
    Line width: 1.5
    Draw line: legendF, proofYmax-13, legendF+legendLen, proofYmax-13
    Line width: 1
    Colour: "Black"
    Text: legendF+1.15*legendLen, "left", proofYmax-13, "half", "measured"

    Draw inner box
    Marks left every: 1, 12, "yes", "yes", "no"
    Text left: "yes", "Gain (dB)"
    One mark bottom: 0, "no", "yes", "no", "0"
    One mark bottom: lawMaxFreq/2, "no", "yes", "no", fixed$(lawMaxFreq/2000,1) + "k"
    One mark bottom: lawMaxFreq, "no", "yes", "no", fixed$(lawMaxFreq/1000,1) + "k"
    Text bottom: "yes", "Frequency (Hz)"

    Select outer viewport: 4.05, 7.75, 0.60, 0.88
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.5, "centre", 0.55, "half", "B  TRANSFER PROOF"

    # =======================
    # C: SOURCE / PURE WET
    # =======================
    Select outer viewport: 0.3, 3.95, 2.82, 4.82
    Select inner viewport: 0.72, 3.72, 3.22, 4.56
    Axes: log10(fMinPlot), log10(fMaxPlot), -72, 3
    Paint rectangle: "{0.97,0.97,0.97}", log10(fMinPlot), log10(fMaxPlot), -72, 3

    Colour: "{0.55,0.55,0.55}"
    Line width: 1
    for i from 1 to specPoints
        frac = (i - 1) / (specPoints - 1)
        fHz = 10^(log10(fMinPlot) + frac * (log10(fMaxPlot) - log10(fMinPlot)))
        c = round(fHz / binWidth) + 1
        c = min(nBins, max(1, c))
        halfHz = max(4*binWidth, 0.02*fHz)
        halfBins = max(2, round(halfHz/binWidth))
        lo = max(2, c-halfBins)
        hi = min(nBins, c+halfBins)
        pSrc = 0
        countBins = hi-lo+1
        for b from lo to hi
            sr = object[vizSrcSpecRef, 1, b]
            si = object[vizSrcSpecRef, 2, b]
            pSrc += sr*sr + si*si
        endfor
        pSrc /= countBins
        valDb = 10*log10((pSrc + 1e-30)/specRefPower)
        valDb = max(-72, valDb)
        xlog = log10(fHz)
        if i > 1
            Draw line: prevSrcX, prevSrcDb, xlog, valDb
        endif
        prevSrcX = xlog
        prevSrcDb = valDb
    endfor

    Colour: "{0.15,0.42,0.68}"
    Line width: 1.5
    for i from 1 to specPoints
        frac = (i - 1) / (specPoints - 1)
        fHz = 10^(log10(fMinPlot) + frac * (log10(fMaxPlot) - log10(fMinPlot)))
        c = round(fHz / binWidth) + 1
        c = min(nBins, max(1, c))
        halfHz = max(4*binWidth, 0.02*fHz)
        halfBins = max(2, round(halfHz/binWidth))
        lo = max(2, c-halfBins)
        hi = min(nBins, c+halfBins)
        pWet = 0
        countBins = hi-lo+1
        for b from lo to hi
            wr = object[vizWetSpecRef, 1, b]
            wi = object[vizWetSpecRef, 2, b]
            pWet += wr*wr + wi*wi
        endfor
        pWet /= countBins
        valDb = 10*log10((pWet + 1e-30)/specRefPower)
        valDb = max(-72, valDb)
        xlog = log10(fHz)
        if i > 1
            Draw line: prevWetX, prevWetDb, xlog, valDb
        endif
        prevWetX = xlog
        prevWetDb = valDb
    endfor
    Line width: 1

    # In-panel legend.
    legendX = log10(fMinPlot) + 0.04*(log10(fMaxPlot)-log10(fMinPlot))
    legendLen = 0.12*(log10(fMaxPlot)-log10(fMinPlot))
    Colour: "{0.55,0.55,0.55}"
    Draw line: legendX, -7, legendX+legendLen, -7
    Colour: "Black"
    Font size: 6
    Text: legendX+1.15*legendLen, "left", -7, "half", "source"
    Colour: "{0.15,0.42,0.68}"
    Line width: 1.5
    Draw line: legendX, -15, legendX+legendLen, -15
    Line width: 1
    Colour: "Black"
    Text: legendX+1.15*legendLen, "left", -15, "half", "pure wet"

    Draw inner box
    Marks left every: 1, 12, "yes", "yes", "no"
    Text left: "yes", "Relative magnitude (dB)"
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
    Text: 0.5, "centre", 0.55, "half", "C  SOURCE / PURE WET"

    # =======================
    # D: TIME-DOMAIN CONSEQUENCE
    # =======================
    Select outer viewport: 4.05, 7.75, 2.82, 4.82
    Select inner viewport: 4.46, 7.53, 3.22, 3.78
    selectObject: vizSrc
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
    Colour: "Black"
    Draw inner box
    Font size: 6.5
    Text left: "yes", "Final"
    One mark bottom: 0, "no", "yes", "no", "0"
    One mark bottom: duration/2, "no", "yes", "no", fixed$(duration/2,1)
    One mark bottom: duration, "no", "yes", "no", fixed$(duration,1)
    Text bottom: "yes", "Time (s)"

    Select outer viewport: 4.05, 7.75, 2.82, 3.10
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.5, "centre", 0.55, "half", "D  TIME-DOMAIN CONSEQUENCE"

    # Bottom summary strip.
    selectObject: resultID
    resultChannels = Get number of channels
    selectObject: vizFinal
    finalRms = Get root-mean-square: 0, 0
    selectObject: vizSrc
    sourceRms = Get root-mean-square: 0, 0
    if sourceRms > 0 and finalRms > 0
        rmsDb = 20*log10(finalRms/sourceRms)
    else
        rmsDb = undefined
    endif

    Select outer viewport: 0.4, 7.7, 4.96, 5.22
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95,0.95,0.95}", 0, 1, 0, 1
    Colour: "Black"
    Font size: 6.1
    summary$ = "bin " + fixed$(binWidth,3) + " Hz | cutoff " + fixed$(actual_cutoff_hz/1000,1) + " kHz | wet " + fixed$(wet_dry_percent,0) + " pct | ch " + string$(resultChannels) + " | proof "
    if proofN > 0
        if proofRmse < 0.001
            summary$ = summary$ + "<0.001 dB"
        else
            summary$ = summary$ + fixed$(proofRmse,3) + " dB"
        endif
    else
        summary$ = summary$ + "n/a"
    endif
    if sourceRms > 0 and finalRms > 0
        summary$ = summary$ + " | final RMS/source " + fixed$(rmsDb,1) + " dB"
    endif
    Text: 0.5, "centre", 0.50, "half", summary$

    removeObject: vizSrc, vizFinal
    Font size: 10
    Colour: "Black"
endif

# ---------------------------
# Cleanup
# ---------------------------
removeObject: gainMap, dryID
if process_channels = 1
    if stereo_output and n_channels = 1
        removeObject: wetID, wetLeft, wetRight, monoWet, monoSourceSpec, monoWetSpec, processMono
    else
        removeObject: wetID, monoSourceSpec, monoWetSpec, processMono
    endif
else
    removeObject: wetID, leftWork, rightWork, leftSourceSpec, leftWetSpec, rightSourceSpec, rightWetSpec, leftWet, rightWet
endif

appendInfoLine: ""
appendInfoLine: "Complete."
selectObject: resultID
outputChannels = Get number of channels
appendInfoLine: "Output channels: ", outputChannels
if frequency_cutoff_hz > nyq
    appendInfoLine: "Cutoff was clamped to Nyquist."
endif
appendInfoLine: "Note: the interference pattern is static in the FFT domain; it is not a time-varying phaser."

if play_after_processing
    Play
endif
