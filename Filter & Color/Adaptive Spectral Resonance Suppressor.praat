# ============================================================
# Praat AudioTools - Adaptive Spectral Resonance Suppressor.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Adaptive Spectral Resonance Suppressor — Offline resonance suppression inspired
#   by Oeksound Soothe2. Suppresses narrowband resonances
#   (harsh spectral peaks) adaptively across time and
#   frequency via "spectral dynamic notch suppression."
#
#   This is NOT hum removal — does NOT assume harmonic series.
#   Instead, it detects peaks that protrude above the local
#   spectral envelope and attenuates them dynamically.
#
#   Pipeline:
#     1. Filter signal into N log-spaced frequency bands
#     2. Measure time-varying power per band (Intensity)
#     3. For each time frame, smooth power across bands to
#        estimate the local spectral envelope (baseline)
#     4. Detect resonances: excess above baseline > threshold
#     5. Compute gain reduction map with sharpness, LF protect,
#        HF softness, and depth limiting
#     6. Temporal smoothing via attack/release envelope follower
#     7. Apply time-varying gain envelopes per band and sum
#        (filterbank resynthesis)
#     8. Wet/dry mix and output gain
#
#   Handles mono and stereo (channels processed independently).
#
#   Soothe2 parameter mapping:
#     Depth       → maxReduction_dB (how much to cut)
#     Sharpness   → sharpness (narrow vs broad suppression)
#     Selectivity → threshold_dB (how prominent a peak must be)
#     Attack      → attack_ms (how fast suppression engages)
#     Release     → release_ms (how fast suppression releases)
#
# Changelog v1.2 (from v1.1):
#   - Default bands reduced to 24 (was 32): 25% less work
#     across filtering, intensity, and synthesis
#   - Eliminated Extract part on band Sounds: chOut bounds
#     the Formula evaluation so FFT padding is ignored
#   - Batch size increased to 8 bands per Formula call
#     (was 4): 3 calls instead of 8 for 24 bands
#   - Pre-computed combined band scale (LF × HF) per band
#   - Restored Resample: object[] in Formula is column-based
#     (same sample index), NOT time-based — low-rate envelopes
#     must be resampled to audio rate for correct alignment
#
# Changelog v1.1 (from v1.0):
#   - Single filter pass (was: filter twice for analysis
#     and synthesis separately)
#   - Intensity read via Down to Matrix + Get value in cell
#     (was: Get value at time with Cubic interpolation)
#   - selectObject removed from all inner loops
#   - Batched multiply+accumulate Formula
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline
#   Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Category: Spectral & Frequency Domain
# ============================================================

# ============================================================
# INPUT VALIDATION
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")
selectObject: originalID
originalDur = Get total duration
sampleRate = Get sampling frequency
nyquist = sampleRate / 2
nChannels = Get number of channels

if originalDur < 0.05
    exitScript: "Sound too short (minimum 0.05 s)."
endif

# ============================================================
# FORM
# ============================================================
form Spectral Soothe v1.2
    optionmenu Preset: 1
        option Custom
        option Gentle
        option Moderate
        option Aggressive
        option Vocal Clarity
        option De-Harsh
    positive Window_length_s 0.030
    positive Time_step_s 0.010
    positive Smoothing_bandwidth_Hz 400
    positive Threshold_dB 3.0
    positive Max_reduction_dB 6.0
    real Sharpness 0.5
    positive Attack_ms 10
    positive Release_ms 80
    positive Protect_Hz 150
    real Protect_amount 0.7
    positive HF_soft_Hz 10000
    integer Number_of_bands 24
    positive Min_band_Hz 60
    positive Max_frequency_Hz 16000
    real Mix 1.0
    real Output_gain_dB 0.0
    boolean Draw_visualization 1
endform

# ============================================================
# PRESETS
# ============================================================
if preset = 2
    # Gentle
    threshold_dB = 4.0
    max_reduction_dB = 4.0
    sharpness = 0.3
    attack_ms = 15
    release_ms = 120
    smoothing_bandwidth_Hz = 500
    protect_Hz = 200
    protect_amount = 0.8
elsif preset = 3
    # Moderate
    threshold_dB = 3.0
    max_reduction_dB = 6.0
    sharpness = 0.5
    attack_ms = 10
    release_ms = 80
    smoothing_bandwidth_Hz = 400
    protect_Hz = 150
    protect_amount = 0.7
elsif preset = 4
    # Aggressive
    threshold_dB = 1.5
    max_reduction_dB = 12.0
    sharpness = 0.6
    attack_ms = 5
    release_ms = 60
    smoothing_bandwidth_Hz = 300
    protect_Hz = 120
    protect_amount = 0.5
elsif preset = 5
    # Vocal Clarity
    threshold_dB = 2.5
    max_reduction_dB = 8.0
    sharpness = 0.7
    attack_ms = 8
    release_ms = 70
    smoothing_bandwidth_Hz = 350
    protect_Hz = 250
    protect_amount = 0.9
    hF_soft_Hz = 12000
elsif preset = 6
    # De-Harsh
    threshold_dB = 2.0
    max_reduction_dB = 10.0
    sharpness = 0.5
    attack_ms = 8
    release_ms = 90
    smoothing_bandwidth_Hz = 400
    protect_Hz = 200
    protect_amount = 0.8
    hF_soft_Hz = 8000
endif

# ============================================================
# CLAMP PARAMETERS
# ============================================================
if window_length_s < 0.010
    window_length_s = 0.010
endif
if window_length_s > 0.100
    window_length_s = 0.100
endif
if time_step_s < 0.002
    time_step_s = 0.002
endif
if time_step_s > 0.050
    time_step_s = 0.050
endif
if smoothing_bandwidth_Hz < 50
    smoothing_bandwidth_Hz = 50
endif
if smoothing_bandwidth_Hz > 2000
    smoothing_bandwidth_Hz = 2000
endif
if threshold_dB < 0.5
    threshold_dB = 0.5
endif
if threshold_dB > 12
    threshold_dB = 12
endif
if max_reduction_dB < 1
    max_reduction_dB = 1
endif
if max_reduction_dB > 24
    max_reduction_dB = 24
endif
if sharpness < 0
    sharpness = 0
endif
if sharpness > 1
    sharpness = 1
endif
if attack_ms < 1
    attack_ms = 1
endif
if release_ms < 10
    release_ms = 10
endif
if protect_amount < 0
    protect_amount = 0
endif
if protect_amount > 1
    protect_amount = 1
endif
if number_of_bands < 8
    number_of_bands = 8
endif
if number_of_bands > 64
    number_of_bands = 64
endif
if min_band_Hz < 20
    min_band_Hz = 20
endif
if max_frequency_Hz > nyquist - 100
    max_frequency_Hz = nyquist - 100
endif
if max_frequency_Hz < 2000
    max_frequency_Hz = 2000
endif
if mix < 0
    mix = 0
endif
if mix > 1
    mix = 1
endif

numBands = number_of_bands

# ============================================================
# BAND FREQUENCY COMPUTATION (log-spaced)
# ============================================================
bandRatio = (max_frequency_Hz / min_band_Hz) ^ (1 / numBands)
for b from 1 to numBands
    bandLow[b] = min_band_Hz * bandRatio ^ (b - 1)
    bandHigh[b] = min_band_Hz * bandRatio ^ b
    bandCenter[b] = sqrt(bandLow[b] * bandHigh[b])
    bandWidth[b] = bandHigh[b] - bandLow[b]
    bandSmooth[b] = bandWidth[b] * 0.4
endfor

# Pre-compute per-band scalars
for b from 1 to numBands
    localBW = bandWidth[b]
    if localBW < 1
        localBW = 1
    endif
    smoothR[b] = round(smoothing_bandwidth_Hz / localBW / 2)
    if smoothR[b] < 1
        smoothR[b] = 1
    endif
    if smoothR[b] > numBands / 2
        smoothR[b] = numBands / 2
    endif
    smoothLo[b] = b - smoothR[b]
    if smoothLo[b] < 1
        smoothLo[b] = 1
    endif
    smoothHi[b] = b + smoothR[b]
    if smoothHi[b] > numBands
        smoothHi[b] = numBands
    endif
    smoothN[b] = smoothHi[b] - smoothLo[b] + 1

    # Combined LF protect × HF softness (single multiply in hot loop)
    bandScale[b] = 1.0
    if bandCenter[b] < protect_Hz and protect_Hz > 0
        bandScale[b] = 1 - protect_amount
            ... + protect_amount * (bandCenter[b] / protect_Hz)
    endif
    if bandCenter[b] > hF_soft_Hz and hF_soft_Hz < max_frequency_Hz
        hfRange = max_frequency_Hz - hF_soft_Hz
        if hfRange > 0
            hfs = 1 - 0.5 * ((bandCenter[b] - hF_soft_Hz) / hfRange)
            if hfs < 0.3
                hfs = 0.3
            endif
            bandScale[b] = bandScale[b] * hfs
        endif
    endif
endfor

# Frame grid
nFrames = floor(originalDur / time_step_s)
if nFrames < 2
    nFrames = 2
endif

# Intensity analysis pitch
intMinPitch = 3.2 / window_length_s
if intMinPitch < 30
    intMinPitch = 30
endif

# Attack/release coefficients
attackTime = attack_ms / 1000
releaseTime = release_ms / 1000
if attackTime < time_step_s
    attackTime = time_step_s
endif
attackCoeff = 1 - exp(-time_step_s / attackTime)
releaseCoeff = 1 - exp(-time_step_s / releaseTime)

# Sharpness exponent
sharpExp = 1 + sharpness * 4

# Envelope sample rate (= frame rate)
envRate = round(1 / time_step_s)
if envRate < 20
    envRate = 20
endif

clearinfo
writeInfoLine: "=================================================="
writeInfoLine: "  SPECTRAL SOOTHE v1.2"
writeInfoLine: "  Resonance suppression pipeline"
writeInfoLine: "=================================================="
appendInfoLine: ""
appendInfoLine: "Source:  ", originalName$, " | ",
    ... fixed$(originalDur, 2), " s | ", sampleRate, " Hz | ",
    ... nChannels, " ch"
appendInfoLine: "Bands:   ", numBands, " (",
    ... round(min_band_Hz), "–", round(max_frequency_Hz), " Hz, log)"
appendInfoLine: "Frames:  ", nFrames, " @ ", fixed$(time_step_s * 1000, 1), " ms"
appendInfoLine: ""
appendInfoLine: "Detection:  smooth ", round(smoothing_bandwidth_Hz),
    ... " Hz | thresh ", fixed$(threshold_dB, 1), " dB"
appendInfoLine: "Suppress:   depth ", fixed$(max_reduction_dB, 1),
    ... " dB | sharp ", fixed$(sharpness, 2)
appendInfoLine: "Dynamics:   atk ", round(attack_ms),
    ... " ms | rel ", round(release_ms), " ms"
appendInfoLine: "Protect:    < ", round(protect_Hz),
    ... " Hz @ ", fixed$(protect_amount, 1),
    ... " | soft > ", round(hF_soft_Hz), " Hz"
appendInfoLine: ""

# ============================================================
# MAIN PROCESSING LOOP (per channel)
# ============================================================

for ch from 1 to nChannels
    appendInfoLine: "── Channel ", ch, " ──"

    if nChannels = 1
        selectObject: originalID
        chSnd = Copy: "ch_proc"
    else
        selectObject: originalID
        chSnd = Extract one channel: ch
    endif

    # ========================================================
    # PHASE A: Filter all bands ONCE
    # ========================================================
    # No Extract part — chOut limits Formula evaluation,
    # so FFT padding beyond originalDur is ignored.

    appendInfoLine: "  Filtering ", numBands, " bands..."

    for b from 1 to numBands
        selectObject: chSnd
        bandSnd[b] = Filter (pass Hann band): bandLow[b], bandHigh[b], bandSmooth[b]
    endfor

    # ========================================================
    # PHASE B: Measure power per band via Intensity → Matrix
    # ========================================================

    appendInfoLine: "  Measuring band power..."

    for b from 1 to numBands
        selectObject: bandSnd[b]
        bInt = To Intensity: intMinPitch, time_step_s, "yes"
        selectObject: bInt
        bMat = Down to Matrix
        removeObject: bInt

        selectObject: bMat
        nIntCols = Get number of columns
        useFrames = nIntCols
        if nFrames < useFrames
            useFrames = nFrames
        endif

        for f from 1 to useFrames
            val = Get value in cell: 1, f
            if val = undefined
                val = -80
            endif
            if val < -80
                val = -80
            endif
            pw[(b - 1) * nFrames + f] = val
        endfor
        for f from useFrames + 1 to nFrames
            pw[(b - 1) * nFrames + f] = -80
        endfor

        removeObject: bMat
    endfor

    # ========================================================
    # PHASE C: Resonance detection & gain map
    # ========================================================

    appendInfoLine: "  Computing resonance map..."

    peakReduction = 0
    totalReduction = 0
    reductionCount = 0

    for f from 1 to nFrames
        # Spectral smoothing: baseline
        for b from 1 to numBands
            sumVal = 0
            for nb from smoothLo[b] to smoothHi[b]
                sumVal += pw[(nb - 1) * nFrames + f]
            endfor
            bl[(b - 1) * nFrames + f] = sumVal / smoothN[b]
        endfor

        # Excess and resonance score
        maxR = 0
        for b from 1 to numBands
            idx = (b - 1) * nFrames + f
            excess = pw[idx] - bl[idx]
            if excess < 0
                excess = 0
            endif
            rScore = excess - threshold_dB
            if rScore < 0
                rScore = 0
            endif
            rs[idx] = rScore
            if rScore > maxR
                maxR = rScore
            endif
        endfor

        # Sharpness concentration
        if maxR > 0 and sharpness > 0.01
            for b from 1 to numBands
                idx = (b - 1) * nFrames + f
                if rs[idx] > 0
                    rNorm = rs[idx] / maxR
                    rs[idx] = rNorm ^ sharpExp * maxR
                endif
            endfor
        endif

        # Reduction with combined band scale
        for b from 1 to numBands
            idx = (b - 1) * nFrames + f
            redDB = rs[idx]
            if redDB > max_reduction_dB
                redDB = max_reduction_dB
            endif
            redDB = redDB * bandScale[b]
            rd[idx] = redDB

            if redDB > peakReduction
                peakReduction = redDB
            endif
            if redDB > 0.01
                totalReduction += redDB
                reductionCount += 1
            endif
        endfor
    endfor

    # ========================================================
    # PHASE D: Temporal smoothing
    # ========================================================

    for b from 1 to numBands
        idx1 = (b - 1) * nFrames + 1
        sm[idx1] = rd[idx1]
        for f from 2 to nFrames
            idx = (b - 1) * nFrames + f
            idxPrev = idx - 1
            target = rd[idx]
            prev = sm[idxPrev]
            if target > prev
                sm[idx] = prev + attackCoeff * (target - prev)
            else
                sm[idx] = prev + releaseCoeff * (target - prev)
            endif
        endfor
    endfor

    # Convert to linear gain
    for b from 1 to numBands
        for f from 1 to nFrames
            idx = (b - 1) * nFrames + f
            redDB = sm[idx]
            if redDB < 0.001
                gn[idx] = 1.0
            else
                gn[idx] = 10 ^ (-redDB / 20)
            endif
        endfor
    endfor

    # ========================================================
    # PHASE E: Build gain envelopes, resample to audio rate
    # ========================================================
    # object [id] in Formula is COLUMN-based (same sample index),
    # NOT time-based. A 100 Hz envelope referenced from a 44100 Hz
    # Formula would only cover the first 533/44100 = 0.012 s.
    # Resample to audio rate so columns align 1:1.

    appendInfoLine: "  Building envelopes..."

    for b from 1 to numBands
        envSnd = Create Sound from formula: "env", 1, 0,
            ... originalDur, envRate, "1"
        nSamp = Get number of samples
        for f from 1 to nFrames
            samp = f
            if samp > nSamp
                samp = nSamp
            endif
            Set value at sample number: 1, samp, gn[(b - 1) * nFrames + f]
        endfor
        envHR[b] = Resample: sampleRate, 50
        removeObject: envSnd
    endfor

    # ========================================================
    # PHASE F: Batched multiply+accumulate (8 bands per call)
    # ========================================================
    # Formula: "self + band1*env1 + band2*env2 + ... + band8*env8"
    # 3 calls for 24 bands.

    appendInfoLine: "  Applying filterbank..."

    selectObject: chSnd
    chOut = Copy: "ch_out"
    selectObject: chOut
    Formula: "0"

    batchSize = 8
    b = 1
    while b <= numBands
        bEnd = b + batchSize - 1
        if bEnd > numBands
            bEnd = numBands
        endif
        fStr$ = "self"
        for bb from b to bEnd
            fStr$ = fStr$ + " + object ["
                ... + string$(bandSnd[bb])
                ... + "] * object ["
                ... + string$(envHR[bb]) + "]"
        endfor
        selectObject: chOut
        Formula: fStr$
        b += batchSize
    endwhile

    # Cleanup bands and envelopes
    for b from 1 to numBands
        removeObject: bandSnd[b], envHR[b]
    endfor

    processedCh[ch] = chOut
    removeObject: chSnd

    # Report
    if reductionCount > 0
        avgRed = totalReduction / reductionCount
    else
        avgRed = 0
    endif
    appendInfoLine: "  Peak reduction: ", fixed$(peakReduction, 1), " dB"
    appendInfoLine: "  Avg reduction (active): ", fixed$(avgRed, 1), " dB"
    appendInfoLine: "  Active frames: ",
        ... fixed$(reductionCount / (numBands * nFrames) * 100, 1), "%"
    appendInfoLine: ""
endfor

# ============================================================
# RECOMBINE STEREO
# ============================================================
if nChannels = 1
    processed = processedCh[1]
else
    selectObject: processedCh[1]
    plusObject: processedCh[2]
    Combine to stereo
    processed = selected("Sound")
    removeObject: processedCh[1], processedCh[2]
endif

# ============================================================
# WET/DRY MIX
# ============================================================
if mix < 0.999
    mixStr$ = fixed$(mix, 6)
    dryStr$ = fixed$(1 - mix, 6)
    selectObject: processed
    Formula: "self * " + mixStr$ + " + object [" + string$(originalID)
        ... + "] * " + dryStr$
endif

# ============================================================
# OUTPUT GAIN
# ============================================================
if output_gain_dB <> 0
    outGainLin = 10 ^ (output_gain_dB / 20)
    outGainStr$ = fixed$(outGainLin, 6)
    selectObject: processed
    Formula: "self * " + outGainStr$
endif

# Prevent clipping
selectObject: processed
peakVal = Get maximum: 0, 0, "Sinc70"
peakNeg = Get minimum: 0, 0, "Sinc70"
if peakNeg < 0
    peakNeg = -peakNeg
endif
if peakNeg > peakVal
    peakVal = peakNeg
endif
if peakVal > 1.0
    Scale peak: 0.95
endif

selectObject: processed
Rename: originalName$ + "_SootheLike"

# ============================================================
# VISUALIZATION
# ============================================================
if draw_visualization

    selectObject: originalID
    if nChannels > 1
        vizOrig = Convert to mono
    else
        vizOrig = Copy: "viz_orig"
    endif

    selectObject: processed
    if nChannels > 1
        vizProc = Convert to mono
    else
        vizProc = Copy: "viz_proc"
    endif

    selectObject: vizOrig
    oMax = Get maximum: 0, 0, "Sinc70"
    oMin = Get minimum: 0, 0, "Sinc70"
    if oMax < 0
        oMax = -oMax
    endif
    if oMin < 0
        oMin = -oMin
    endif
    if oMin > oMax
        oMax = oMin
    endif
    ampMax = oMax * 1.15
    if ampMax < 0.001
        ampMax = 0.001
    endif

    Erase all

    # === TITLE ===
    Select outer viewport: 0, 8, 0, 0.45
    Axes: 0, 1, 0, 1
    Font size: 11
    Colour: "Black"
    Text: 0.5, "centre", 0.7, "half", "##Spectral Soothe v1.2##"
    Font size: 7
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.0, "half",
        ... originalName$ + " | " + fixed$(originalDur, 2) + " s | "
        ... + "depth " + fixed$(max_reduction_dB, 0) + " dB | "
        ... + "sharp " + fixed$(sharpness, 1) + " | "
        ... + "thresh " + fixed$(threshold_dB, 1) + " dB"

    # === PANEL 1: Original waveform ===
    Select outer viewport: 0, 8, 0.5, 2.0
    Select inner viewport: 0.7, 7.6, 0.6, 1.9
    Axes: 0, originalDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, originalDur, -ampMax, ampMax
    Colour: "{0.6, 0.6, 0.6}"
    Draw line: 0, 0, originalDur, 0
    selectObject: vizOrig
    Colour: "{0.3, 0.3, 0.5}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Original"
    Text left: "yes", "Amp"

    # === PANEL 2: Processed waveform ===
    Select outer viewport: 0, 8, 2.05, 3.55
    Select inner viewport: 0.7, 7.6, 2.15, 3.45
    Axes: 0, originalDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, originalDur, -ampMax, ampMax
    Colour: "{0.6, 0.6, 0.6}"
    Draw line: 0, 0, originalDur, 0
    selectObject: vizProc
    Colour: "{0.2, 0.5, 0.3}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Processed (SootheLike)"
    Text left: "yes", "Amp"

    # === PANEL 3: Difference ===
    selectObject: vizOrig
    vizDiff = Copy: "viz_diff"
    selectObject: vizDiff
    Formula: "self - object [" + string$(vizProc) + "]"

    selectObject: vizDiff
    dMax = Get maximum: 0, 0, "Sinc70"
    dMin = Get minimum: 0, 0, "Sinc70"
    if dMax < 0
        dMax = -dMax
    endif
    if dMin < 0
        dMin = -dMin
    endif
    if dMin > dMax
        dMax = dMin
    endif
    diffMax = dMax * 1.15
    if diffMax < 0.0001
        diffMax = ampMax * 0.3
    endif

    Select outer viewport: 0, 8, 3.6, 5.1
    Select inner viewport: 0.7, 7.6, 3.7, 5.0
    Axes: 0, originalDur, -diffMax, diffMax
    Paint rectangle: "{1.0, 0.96, 0.94}", 0, originalDur, -diffMax, diffMax
    Colour: "{0.8, 0.8, 0.8}"
    Draw line: 0, 0, originalDur, 0
    selectObject: vizDiff
    Colour: "{0.8, 0.25, 0.2}"
    Draw: 0, 0, -diffMax, diffMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Difference (resonance energy removed)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"

    # === PANEL 4: Spectral comparison ===
    selectObject: vizOrig
    specOrig = To Spectrum: "yes"
    selectObject: vizProc
    specProc = To Spectrum: "yes"

    Select outer viewport: 0, 8, 5.2, 7.0
    Select inner viewport: 0.7, 7.6, 5.3, 6.9

    specMaxF = max_frequency_Hz
    if specMaxF > nyquist - 500
        specMaxF = nyquist - 500
    endif
    Axes: 0, specMaxF, -60, 10

    Paint rectangle: "{0.97, 0.97, 0.97}", 0, specMaxF, -60, 10

    Colour: "{0.88, 0.88, 0.88}"
    gdb = -50
    while gdb <= 0
        Draw line: 0, gdb, specMaxF, gdb
        gdb += 10
    endwhile

    selectObject: specOrig
    Colour: "{0.4, 0.4, 0.65}"
    Draw: 0, specMaxF, -60, 10, "no"
    selectObject: specProc
    Colour: "{0.2, 0.65, 0.3}"
    Draw: 0, specMaxF, -60, 10, "no"

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Spectrum: original (blue) vs processed (green)"
    Text left: "yes", "dB"
    Text bottom: "yes", "Frequency (Hz)"

    if specMaxF > 12000
        Marks bottom every: 1, 4000, "yes", "yes", "no"
    else
        Marks bottom every: 1, 2000, "yes", "yes", "no"
    endif
    Marks left every: 1, 10, "yes", "yes", "no"

    # === LEGEND ===
    Select outer viewport: 0, 8, 7.05, 7.35
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.4, 0.4, 0.65}"
    Draw line: 0.05, 0.5, 0.12, 0.5
    Colour: "Black"
    Text: 0.13, "left", 0.5, "half", "Original"
    Colour: "{0.2, 0.65, 0.3}"
    Draw line: 0.28, 0.5, 0.35, 0.5
    Colour: "Black"
    Text: 0.36, "left", 0.5, "half", "Processed"
    Colour: "{0.8, 0.25, 0.2}"
    Draw line: 0.54, 0.5, 0.61, 0.5
    Colour: "Black"
    Text: 0.62, "left", 0.5, "half", "Removed"

    Font size: 10
    Line width: 1

    removeObject: vizOrig, vizProc, vizDiff, specOrig, specProc
endif

# ============================================================
# FINAL REPORT
# ============================================================
appendInfoLine: "── Output ──"
appendInfoLine: "  Mix:    ", fixed$(mix * 100, 0), "% wet"
appendInfoLine: "  Gain:   ", fixed$(output_gain_dB, 1), " dB"
appendInfoLine: "  Result: ", originalName$ + "_SootheLike"
appendInfoLine: ""
appendInfoLine: "=================================================="

selectObject: processed
Play
