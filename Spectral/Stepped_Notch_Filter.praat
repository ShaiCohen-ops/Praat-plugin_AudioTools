# ============================================================
# Praat AudioTools - Stepped_Notch_Filter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.4 (2026)
# License: MIT License
#
# Description:
#   Whole-file FFT stepped spectral attenuator. One or two rectangular
#   frequency regions are multiplied by fixed gains, with a separate
#   gain outside the regions. Useful for static presence reduction,
#   static de-essing, telephone-band coloration, and spectral sculpting.
#
#   IMPORTANT: this is a global FFT-domain stepped filter, not a dynamic
#   de-esser and not a time-local IIR/FIR notch. Hard spectral edges are
#   intentionally preserved and can contribute ringing/character.
#
# Changelog v0.4:
#   - Preserves stereo input by processing L/R independently
#   - True dry path; wet=0 is an unscaled dry bypass (channel-format choice still applies)
#   - Mono->stereo mode delays only the wet right channel (legacy 12 ms)
#   - Gains may be exactly 0; band limits are clamped to Nyquist
#   - Telephone preset now attenuates from 3.4 kHz all the way to Nyquist
#   - Overlapping custom bands use the stronger attenuation (minimum gain)
#   - Preset wording corrected: static spectral attenuation, not dynamics
#   - Visualization rebuilt around the actual transfer law and measurement
#   - Source/wet spectra share one scale; waveforms share one amplitude scale
#   - Added transfer-function QC (target vs measured gain)
#
# Usage:
#   Select exactly one mono or stereo Sound object and run this script.
# ============================================================

form Stepped Notch Filter
    optionmenu Preset: 1
        option Custom
        option Vocal Presence Dip (2-4 kHz)
        option Static De-Esser (5-8 kHz)
        option Hollow Middle (400-2000 Hz)
        option Telephone Band (300-3400 Hz)
    comment === Band 1 ===
    real band1_low 2000
    real band1_high 2200
    real band1_gain 0.1
    comment === Band 2 ===
    real band2_low 5500
    real band2_high 5800
    real band2_gain 0.2
    comment === Outside Bands ===
    real outside_gain 1.0
    comment === Mix / channels ===
    real wet_dry_percent 100
    comment (0 = dry only with no peak scaling, 100 = full wet)
    boolean stereo_output 1
    comment (stereo input is preserved; mono uses 12 ms wet-only stereo offset)
    comment === Output ===
    positive scale_peak 0.90
    boolean draw_visualization 1
    boolean play_after_processing 1
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
    exitScript: "Stepped Notch Filter v0.4 supports mono or stereo Sound input."
endif

# ---------------------------
# Presets
# ---------------------------
presetName$ = "Custom"
if preset = 2
    band1_low = 2000
    band1_high = 4000
    band1_gain = 0.3
    band2_low = 0
    band2_high = 0
    band2_gain = 1.0
    outside_gain = 1.0
    presetName$ = "VocalPresenceDip"
elsif preset = 3
    band1_low = 5000
    band1_high = 8000
    band1_gain = 0.4
    band2_low = 0
    band2_high = 0
    band2_gain = 1.0
    outside_gain = 1.0
    presetName$ = "StaticDeEsser"
elsif preset = 4
    band1_low = 400
    band1_high = 2000
    band1_gain = 0.2
    band2_low = 0
    band2_high = 0
    band2_gain = 1.0
    outside_gain = 1.0
    presetName$ = "HollowMiddle"
elsif preset = 5
    band1_low = 0
    band1_high = 300
    band1_gain = 0.1
    band2_low = 3400
    band2_high = nyq
    band2_gain = 0.1
    outside_gain = 1.0
    presetName$ = "TelephoneBand"
endif

# ---------------------------
# Validation / effective law
# ---------------------------
if band1_low < 0 or band1_high < 0 or band2_low < 0 or band2_high < 0
    exitScript: "Band frequencies must be 0 Hz or greater."
endif
if band1_gain < 0 or band2_gain < 0 or outside_gain < 0
    exitScript: "Band and outside gains must be 0 or greater."
endif

# Normalize reversed custom band limits.
if band1_high < band1_low
    temp = band1_low
    band1_low = band1_high
    band1_high = temp
endif
if band2_high < band2_low
    temp = band2_low
    band2_low = band2_high
    band2_high = temp
endif

# Clamp wet/dry.
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif
wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

# Clamp bands to the realizable spectrum.
b1l = min(nyq, max(0, band1_low))
b1h = min(nyq, max(0, band1_high))
b2l = min(nyq, max(0, band2_low))
b2h = min(nyq, max(0, band2_high))
b1active = b1h > b1l
b2active = b2h > b2l

# In an overlap, use the stronger attenuation (lower gain).
overlap_gain = min(band1_gain, band2_gain)

# Build the exact gain formula used for every processed channel.
b1l$ = fixed$(b1l, 12)
b1h$ = fixed$(b1h, 12)
b1g$ = fixed$(band1_gain, 12)
b2l$ = fixed$(b2l, 12)
b2h$ = fixed$(b2h, 12)
b2g$ = fixed$(band2_gain, 12)
outG$ = fixed$(outside_gain, 12)
overlapG$ = fixed$(overlap_gain, 12)

if b1active and b2active
    gainFormula$ = "if x >= " + b1l$ + " and x <= " + b1h$ + " and x >= " + b2l$ + " and x <= " + b2h$ + " then self * " + overlapG$ + " else if x >= " + b1l$ + " and x <= " + b1h$ + " then self * " + b1g$ + " else if x >= " + b2l$ + " and x <= " + b2h$ + " then self * " + b2g$ + " else self * " + outG$ + " fi fi fi"
elsif b1active
    gainFormula$ = "if x >= " + b1l$ + " and x <= " + b1h$ + " then self * " + b1g$ + " else self * " + outG$ + " fi"
elsif b2active
    gainFormula$ = "if x >= " + b2l$ + " and x <= " + b2h$ + " then self * " + b2g$ + " else self * " + outG$ + " fi"
else
    gainFormula$ = "self * " + outG$
endif

writeInfoLine: "=== Stepped Notch Filter v0.4 ==="
appendInfoLine: "Algorithm: whole-file FFT -> stepped complex-bin gain -> IFFT"
appendInfoLine: "Preset: ", presetName$
if b1active
    appendInfoLine: "Band 1: ", fixed$(b1l,1), "-", fixed$(b1h,1), " Hz | gain ", fixed$(band1_gain,3)
else
    appendInfoLine: "Band 1: inactive"
endif
if b2active
    appendInfoLine: "Band 2: ", fixed$(b2l,1), "-", fixed$(b2h,1), " Hz | gain ", fixed$(band2_gain,3)
else
    appendInfoLine: "Band 2: inactive"
endif
appendInfoLine: "Outside gain: ", fixed$(outside_gain,3)
appendInfoLine: "Wet: ", fixed$(wet_dry_percent,0), "%"

# ---------------------------
# Representative source channel for visualization
# ---------------------------
repChannel = 1
if n_channels = 2 and stereo_output
    selectObject: originalID
    tempL = Extract one channel: 1
    rmsL = Get root-mean-square: 0, 0
    selectObject: originalID
    tempR = Extract one channel: 2
    rmsR = Get root-mean-square: 0, 0
    if rmsR > rmsL
        repChannel = 2
    endif
    removeObject: tempL, tempR
endif

# ---------------------------
# Prepare processing source and dry path
# ---------------------------
# stereo_output=0 intentionally produces mono output from a stereo source.
if n_channels = 2 and not stereo_output
    selectObject: originalID
    processMono = Convert to mono
    selectObject: processMono
    dryID = Copy: "dry_mono"
    process_channels = 1
elsif n_channels = 1
    selectObject: originalID
    processMono = Copy: "process_mono"
    if stereo_output
        selectObject: originalID
        dryID = Convert to stereo
    else
        selectObject: originalID
        dryID = Copy: "dry_mono"
    endif
    process_channels = 1
else
    # stereo input + stereo output: preserve original channel structure.
    selectObject: originalID
    dryID = Copy: "dry_stereo"
    process_channels = 2
endif

# ---------------------------
# FFT processing
# ---------------------------
# Keep the original/processed spectra until after visualization.
leftSourceSpec = 0
leftWetSpec = 0
rightSourceSpec = 0
rightWetSpec = 0
monoSourceSpec = 0
monoWetSpec = 0

if process_channels = 1
    if n_channels = 2 and not stereo_output
        monoWork = processMono
    else
        monoWork = processMono
    endif

    selectObject: monoWork
    monoSourceSpec = To Spectrum: "yes"
    Rename: "source_spectrum"
    selectObject: monoSourceSpec
    monoWetSpec = Copy: "wet_spectrum"
    Formula: gainFormula$
    selectObject: monoWetSpec
    monoWet = To Sound
    monoWetDur = Get total duration
    if monoWetDur > duration
        trimmed = Extract part: 0, duration, "rectangular", 1, "no"
        removeObject: monoWet
        monoWet = trimmed
    endif

    if stereo_output and n_channels = 1
        # Legacy library character: create stereo only from the wet signal.
        delay_samples = round(0.012 * original_sr)
        monoWet$ = string$(monoWet)
        Create Sound from formula: "wet_left", 1, 0, duration, original_sr, "object[" + monoWet$ + ", 1, col]"
        wetLeft = selected("Sound")
        Create Sound from formula: "wet_right", 1, 0, duration, original_sr,
            ... "if col > " + string$(delay_samples) + " then object[" + monoWet$ + ", 1, col - " + string$(delay_samples) + "] else 0 fi"
        wetRight = selected("Sound")
        selectObject: wetLeft
        plusObject: wetRight
        wetID = Combine to stereo
        removeObject: monoWet, wetLeft, wetRight
    else
        wetID = monoWet
    endif
else
    # Left channel
    selectObject: originalID
    leftWork = Extract one channel: 1
    selectObject: leftWork
    leftSourceSpec = To Spectrum: "yes"
    Rename: "source_spectrum_L"
    selectObject: leftSourceSpec
    leftWetSpec = Copy: "wet_spectrum_L"
    Formula: gainFormula$
    selectObject: leftWetSpec
    leftWet = To Sound
    leftWetDur = Get total duration
    if leftWetDur > duration
        trimmedL = Extract part: 0, duration, "rectangular", 1, "no"
        removeObject: leftWet
        leftWet = trimmedL
    endif

    # Right channel
    selectObject: originalID
    rightWork = Extract one channel: 2
    selectObject: rightWork
    rightSourceSpec = To Spectrum: "yes"
    Rename: "source_spectrum_R"
    selectObject: rightSourceSpec
    rightWetSpec = Copy: "wet_spectrum_R"
    Formula: gainFormula$
    selectObject: rightWetSpec
    rightWet = To Sound
    rightWetDur = Get total duration
    if rightWetDur > duration
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
    resultID = Copy: "mixed_result"
    Formula: "self * " + string$(wet_level) + " + object[" + string$(dryID) + ", row, col] * " + string$(dry_level)
    Rename: originalName$ + "_" + presetName$
    Scale peak: scale_peak
endif

# ---------------------------
# Visualization references / QC
# ---------------------------
if draw_visualization
    # Source/wet spectrum pair corresponding to the actual processing path.
    if process_channels = 2
        if repChannel = 2
            vizSrcSpecRef = rightSourceSpec
            vizWetSpecRef = rightWetSpec
        else
            vizSrcSpecRef = leftSourceSpec
            vizWetSpecRef = leftWetSpec
        endif
        selectObject: originalID
        vizSrc = Extract one channel: repChannel
        selectObject: resultID
        vizFinal = Extract one channel: repChannel
    else
        vizSrcSpecRef = monoSourceSpec
        vizWetSpecRef = monoWetSpec
        if n_channels = 2 and not stereo_output
            selectObject: processMono
            vizSrc = Copy: "viz_source"
        else
            selectObject: originalID
            vizSrc = Copy: "viz_source"
        endif
        selectObject: resultID
        resultChannels = Get number of channels
        if resultChannels = 2
            vizFinal = Extract one channel: 1
        else
            vizFinal = Copy: "viz_final"
        endif
    endif

    # Common time-domain amplitude range.
    selectObject: vizSrc
    srcPeak = Get absolute extremum: 0, 0, "None"
    selectObject: vizFinal
    finalPeak = Get absolute extremum: 0, 0, "None"
    waveAbs = 1.05 * max(srcPeak, finalPeak, 1e-6)

    # Spectrum geometry.
    selectObject: vizSrcSpecRef
    nBins = Get number of bins
    maxFreq = Get highest frequency
    fMinPlot = max(30, maxFreq / (nBins - 1))
    fMaxPlot = maxFreq
    if fMaxPlot <= fMinPlot
        fMinPlot = 1
    endif

    # Shared spectral reference from local band-averaged power.
    # This keeps the measured spectrum readable while preserving the hard law in A/C.
    specPoints = 140
    binWidth = maxFreq / (nBins - 1)
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
    specRef = sqrt(specRefPower)

    # Target/measured transfer QC over the same log-frequency grid.
    proofSSE = 0
    proofN = 0
    for i from 1 to specPoints
        frac = (i - 1) / (specPoints - 1)
        fHz = 10^(log10(fMinPlot) + frac * (log10(fMaxPlot) - log10(fMinPlot)))

        targetGain = outside_gain
        inB1 = b1active and fHz >= b1l and fHz <= b1h
        inB2 = b2active and fHz >= b2l and fHz <= b2h
        if inB1 and inB2
            targetGain = overlap_gain
        elsif inB1
            targetGain = band1_gain
        elsif inB2
            targetGain = band2_gain
        endif
        if targetGain > 0
            targetDb = 20 * log10(targetGain)
        else
            targetDb = -80
        endif

        selectObject: vizSrcSpecRef
        cReal = Get bin number from frequency: fHz
        c = round(cReal)
        c = min(nBins, max(1, c))
        sr = Get real value in bin: c
        si = Get imaginary value in bin: c
        srcMag = sqrt(sr*sr + si*si)
        selectObject: vizWetSpecRef
        wr = Get real value in bin: c
        wi = Get imaginary value in bin: c
        wetMag = sqrt(wr*wr + wi*wi)
        if srcMag > specRef * 1e-10
            if wetMag > 0
                measuredDb = 20 * log10(wetMag / srcMag)
            else
                measuredDb = -80
            endif
            # Treat values below the display floor as equivalent for QC.
            targetQc = max(-80, targetDb)
            measuredQc = max(-80, measuredDb)
            proofSSE += (measuredQc - targetQc)^2
            proofN += 1
        endif
    endfor
    if proofN > 0
        proofRmse = sqrt(proofSSE / proofN)
    else
        proofRmse = undefined
    endif

    # Gain display range in dB.
    minGain = outside_gain
    maxGain = outside_gain
    if b1active
        minGain = min(minGain, band1_gain)
        maxGain = max(maxGain, band1_gain)
    endif
    if b2active
        minGain = min(minGain, band2_gain)
        maxGain = max(maxGain, band2_gain)
    endif
    if minGain > 0
        minGainDb = 20*log10(minGain)
    else
        minGainDb = -60
    endif
    if maxGain > 0
        maxGainDb = 20*log10(maxGain)
    else
        maxGainDb = 0
    endif
    lawYmin = min(-12, floor(minGainDb/6)*6 - 3)
    lawYmin = max(-66, lawYmin)
    lawYmax = max(3, ceiling(maxGainDb/6)*6 + 3)

    Erase all

    # Overall title and law strips are isolated from the panel viewports.
    Select outer viewport: 0.4, 7.8, 0.04, 0.25
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.50, "half", "Stepped Notch Filter v0.4 — " + presetName$

    Select outer viewport: 0.4, 7.8, 0.28, 0.46
    Axes: 0, 1, 0, 1
    Font size: 6.5
    Colour: "{0.35,0.35,0.35}"
    Text: 0.5, "centre", 0.50, "half", "Sound -> per-channel FFT -> stepped G(f) -> IFFT -> wet/dry   |   hard frequency edges preserved"

    # =======================
    # A: EXACT FILTER LAW
    # =======================
    Select outer viewport: 0.3, 3.95, 0.60, 2.60
    Select inner viewport: 0.72, 3.72, 1.02, 2.36
    Axes: log10(fMinPlot), log10(fMaxPlot), lawYmin, lawYmax
    Paint rectangle: "{0.97,0.97,0.97}", log10(fMinPlot), log10(fMaxPlot), lawYmin, lawYmax
    Colour: "{0.78,0.78,0.78}"
    Draw line: log10(fMinPlot), 0, log10(fMaxPlot), 0

    # Shade active receiving regions.
    if b1active and b1h >= fMinPlot and b1l <= fMaxPlot
        shadeLo = log10(max(fMinPlot, max(b1l, 1e-9)))
        shadeHi = log10(min(fMaxPlot, b1h))
        Paint rectangle: "{0.94,0.91,0.91}", shadeLo, shadeHi, lawYmin, lawYmax
    endif
    if b2active and b2h >= fMinPlot and b2l <= fMaxPlot
        shadeLo = log10(max(fMinPlot, max(b2l, 1e-9)))
        shadeHi = log10(min(fMaxPlot, b2h))
        Paint rectangle: "{0.94,0.91,0.91}", shadeLo, shadeHi, lawYmin, lawYmax
    endif

    Colour: "{0.15,0.42,0.68}"
    Line width: 1.5
    lawPoints = 300
    for i from 1 to lawPoints
        frac = (i - 1) / (lawPoints - 1)
        fHz = 10^(log10(fMinPlot) + frac * (log10(fMaxPlot) - log10(fMinPlot)))
        g = outside_gain
        inB1 = b1active and fHz >= b1l and fHz <= b1h
        inB2 = b2active and fHz >= b2l and fHz <= b2h
        if inB1 and inB2
            g = overlap_gain
        elsif inB1
            g = band1_gain
        elsif inB2
            g = band2_gain
        endif
        if g > 0
            gDb = 20*log10(g)
        else
            gDb = lawYmin
        endif
        gDb = max(lawYmin, min(lawYmax, gDb))
        xlog = log10(fHz)
        if i > 1
            Draw line: prevLawX, prevLawDb, xlog, gDb
        endif
        prevLawX = xlog
        prevLawDb = gDb
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 12, "yes", "yes", "no"
    Text left: "yes", "Gain (dB)"
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

    Select outer viewport: 0.3, 3.95, 0.60, 0.88
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.5, "centre", 0.55, "half", "A  FILTER LAW"

    # =======================
    # B: SOURCE vs PURE WET
    # =======================
    Select outer viewport: 4.05, 7.75, 0.60, 2.60
    Select inner viewport: 4.46, 7.53, 1.02, 2.36
    Axes: log10(fMinPlot), log10(fMaxPlot), -72, 3
    Paint rectangle: "{0.97,0.97,0.97}", log10(fMinPlot), log10(fMaxPlot), -72, 3

    if b1active and b1h >= fMinPlot and b1l <= fMaxPlot
        shadeLo = log10(max(fMinPlot, max(b1l, 1e-9)))
        shadeHi = log10(min(fMaxPlot, b1h))
        Paint rectangle: "{0.94,0.91,0.91}", shadeLo, shadeHi, -72, 3
    endif
    if b2active and b2h >= fMinPlot and b2l <= fMaxPlot
        shadeLo = log10(max(fMinPlot, max(b2l, 1e-9)))
        shadeHi = log10(min(fMaxPlot, b2h))
        Paint rectangle: "{0.94,0.91,0.91}", shadeLo, shadeHi, -72, 3
    endif

    # Source and wet traces use the same local band averaging and shared scale.
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

    # Compact in-panel legend.
    legendX = log10(fMinPlot) + 0.04*(log10(fMaxPlot)-log10(fMinPlot))
    legendLen = 0.12*(log10(fMaxPlot)-log10(fMinPlot))
    Colour: "{0.55,0.55,0.55}"
    Draw line: legendX, -7, legendX + legendLen, -7
    Colour: "Black"
    Font size: 6
    Text: legendX + 1.15*legendLen, "left", -7, "half", "source"
    Colour: "{0.15,0.42,0.68}"
    Line width: 1.5
    Draw line: legendX, -15, legendX + legendLen, -15
    Line width: 1
    Colour: "Black"
    Text: legendX + 1.15*legendLen, "left", -15, "half", "pure wet"

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

    Select outer viewport: 4.05, 7.75, 0.60, 0.88
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.5, "centre", 0.55, "half", "B  SOURCE / PURE WET"

    # =======================
    # C: TRANSFER PROOF
    # =======================
    Select outer viewport: 0.3, 3.95, 2.82, 4.82
    Select inner viewport: 0.72, 3.72, 3.22, 4.56
    Axes: log10(fMinPlot), log10(fMaxPlot), lawYmin, lawYmax
    Paint rectangle: "{0.97,0.97,0.97}", log10(fMinPlot), log10(fMaxPlot), lawYmin, lawYmax
    Colour: "{0.78,0.78,0.78}"
    Draw line: log10(fMinPlot), 0, log10(fMaxPlot), 0

    # Target law (gray).
    Colour: "{0.55,0.55,0.55}"
    Line width: 1
    for i from 1 to specPoints
        frac = (i - 1) / (specPoints - 1)
        fHz = 10^(log10(fMinPlot) + frac * (log10(fMaxPlot) - log10(fMinPlot)))
        g = outside_gain
        inB1 = b1active and fHz >= b1l and fHz <= b1h
        inB2 = b2active and fHz >= b2l and fHz <= b2h
        if inB1 and inB2
            g = overlap_gain
        elsif inB1
            g = band1_gain
        elsif inB2
            g = band2_gain
        endif
        if g > 0
            targetDb = 20*log10(g)
        else
            targetDb = lawYmin
        endif
        targetDb = max(lawYmin, min(lawYmax, targetDb))
        xlog = log10(fHz)
        if i > 1
            Draw line: prevTargetX, prevTargetDb, xlog, targetDb
        endif
        prevTargetX = xlog
        prevTargetDb = targetDb
    endfor

    # Measured complex-magnitude ratio at source bins with measurable energy.
    Colour: "{0.15,0.42,0.68}"
    Line width: 1.5
    havePrev = 0
    for i from 1 to specPoints
        frac = (i - 1) / (specPoints - 1)
        fHz = 10^(log10(fMinPlot) + frac * (log10(fMaxPlot) - log10(fMinPlot)))
        selectObject: vizSrcSpecRef
        cReal = Get bin number from frequency: fHz
        c = round(cReal)
        c = min(nBins, max(1, c))
        sr = Get real value in bin: c
        si = Get imaginary value in bin: c
        srcMag = sqrt(sr*sr + si*si)
        selectObject: vizWetSpecRef
        wr = Get real value in bin: c
        wi = Get imaginary value in bin: c
        wetMag = sqrt(wr*wr + wi*wi)
        if srcMag > specRef * 1e-10
            if wetMag > 0
                measuredDb = 20*log10(wetMag/srcMag)
            else
                measuredDb = lawYmin
            endif
            measuredDb = max(lawYmin, min(lawYmax, measuredDb))
            xlog = log10(fHz)
            if havePrev
                Draw line: prevProofX, prevProofDb, xlog, measuredDb
            endif
            prevProofX = xlog
            prevProofDb = measuredDb
            havePrev = 1
        else
            havePrev = 0
        endif
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 12, "yes", "yes", "no"
    Text left: "yes", "Measured gain (dB)"
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
    Text: 0.5, "centre", 0.55, "half", "C  TRANSFER PROOF"

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
    # Three readable time marks; source/final share exactly the same time axis.
    One mark bottom: 0, "no", "yes", "no", "0"
    One mark bottom: duration/2, "no", "yes", "no", fixed$(duration/2, 1)
    One mark bottom: duration, "no", "yes", "no", fixed$(duration, 1)
    Text bottom: "yes", "Time (s)"

    Select outer viewport: 4.05, 7.75, 2.82, 3.10
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.5, "centre", 0.55, "half", "D  TIME-DOMAIN CONSEQUENCE"

    # Bottom summary strip: one line, no wrapping.
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
    Font size: 6.3
    summary$ = "wet " + fixed$(wet_dry_percent,0) + " pct | ch " + string$(resultChannels) + " | Nyq " + fixed$(nyq/1000,1) + " kHz | proof "
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
if process_channels = 1
    removeObject: monoSourceSpec, monoWetSpec, processMono
else
    removeObject: leftWork, rightWork, leftSourceSpec, leftWetSpec, rightSourceSpec, rightWetSpec, leftWet, rightWet
endif
removeObject: wetID, dryID

appendInfoLine: ""
appendInfoLine: "Complete."
selectObject: resultID
outputChannels = Get number of channels
appendInfoLine: "Output channels: ", outputChannels
if b1active and band1_high > nyq
    appendInfoLine: "Band 1 high edge was clamped to Nyquist."
endif
if b2active and band2_high > nyq
    appendInfoLine: "Band 2 high edge was clamped to Nyquist."
endif
if b1active and b2active and max(b1l,b2l) <= min(b1h,b2h)
    appendInfoLine: "Band overlap used the lower gain (stronger attenuation)."
endif

selectObject: resultID
if play_after_processing
    Play
endif
