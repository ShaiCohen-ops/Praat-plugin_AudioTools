# ============================================================
# Praat AudioTools - Adaptive Spectral Resonance Suppressor.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Adaptive Spectral Resonance Suppressor — Offline resonance suppression
#   inspired by Oeksound Soothe2. Suppresses narrowband resonances
#   (harsh spectral peaks) adaptively across time and frequency via
#   "spectral dynamic notch suppression."
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
#     Depth       -> maxReduction_dB (how much to cut)
#     Sharpness   -> sharpness (narrow vs broad suppression)
#     Selectivity -> threshold_dB (how prominent a peak must be)
#     Attack      -> attack_ms (how fast suppression engages)
#     Release     -> release_ms (how fast suppression releases)
#
# Changelog v1.3 (from v1.2):
#   - Audio pipeline UNCHANGED. Output is bit-identical to v1.2
#     for the same form parameters. Same 9-phase processing
#     (filter -> intensity -> spectral smoothing -> detection ->
#     sharpness -> reduction -> temporal smoothing -> envelope
#     build -> filterbank resynthesis). Same 5 presets with
#     same values. Same parameter clamping. Same mono/stereo
#     handling. Same wet/dry mix and output gain logic.
#   - NEW: Show_spectrum boolean form toggle (default 1, ON).
#     v1.2 always computed `To Spectrum` calls for the
#     visualization. Default ON because the spectrum IS the
#     primary diagnostic for a spectral processor; OFF skips
#     the spectrum calls and replaces Panel A with a parameter
#     report.
#   - NEW: Play_result boolean form toggle (default 1, ON).
#     v1.2 unconditionally `Play`d at the end; v1.3 makes it
#     optional for batch processing.
#   - Output filename now includes preset name: e.g.
#     `originalName_SootheLike_Moderate` (was just
#     `originalName_SootheLike`). Each preset case now assigns
#     a `presetName$` variable used both in the filename and
#     in the visualization metadata.
#   - Visualization rewritten to suite 8x8 standard (v1.2 was
#     8x7.35 with 4 audio panels + legend strip):
#       Title bar + metadata subtitle (preset, bands, depth,
#         sharpness, threshold)
#       Panel A (left, headline): spectrum comparison (original
#         blue vs processed green) OR parameter report (when
#         Show_spectrum = OFF). The spectral processor's
#         signature output.
#       Panel B (right, headline): difference signal time-series
#         (the "what was removed" diagnostic) — preserved from
#         v1.2 in red, now positioned as headline
#       Panel C: zoom overlay (first 500 ms, gray = original,
#         blue = processed) — consolidates v1.2's two separate
#         waveform panels into one
#       Panel D: full waveform comparison (gray = original,
#         blue = processed, overlaid)
#       Panel E: light-grey summary stats bar (suite standard)
#         with peak reduction, average reduction, active-frame
#         percentage, mix/gain settings, output stats. Replaces
#         v1.2's legend strip with a stats line.
#   - Cross-channel statistics tracking: v1.2 tracked
#     peakReduction/totalReduction/reductionCount per channel
#     but the variables were script-level, so only the LAST
#     channel's values persisted. v1.3 explicitly accumulates
#     across channels for the summary bar.
#
# Changelog v1.2 (from v1.1):
#   - Default bands reduced to 24 (was 32): 25% less work
#   - Eliminated Extract part on band Sounds: chOut bounds
#     the Formula evaluation so FFT padding is ignored
#   - Batch size increased to 8 bands per Formula call
#   - Pre-computed combined band scale (LF x HF) per band
#   - Restored Resample: object[] in Formula is column-based
#     (same sample index), NOT time-based — low-rate envelopes
#     must be resampled to audio rate for correct alignment
#
# Changelog v1.1 (from v1.0):
#   - Single filter pass (was: filter twice)
#   - Intensity read via Down to Matrix + Get value in cell
#   - selectObject removed from all inner loops
#   - Batched multiply+accumulate Formula
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline
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
form Spectral Soothe v1.3
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
    boolean Show_spectrum 1
    boolean Draw_visualization 1
    boolean Play_result 1
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
    presetName$ = "Gentle"
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
    presetName$ = "Moderate"
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
    presetName$ = "Aggressive"
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
    presetName$ = "VocalClarity"
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
    presetName$ = "DeHarsh"
else
    presetName$ = "Custom"
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
writeInfoLine: "  SPECTRAL SOOTHE v1.3"
writeInfoLine: "  Resonance suppression pipeline"
writeInfoLine: "=================================================="
appendInfoLine: ""
appendInfoLine: "Source:  ", originalName$, " | ",
    ... fixed$(originalDur, 2), " s | ", sampleRate, " Hz | ",
    ... nChannels, " ch"
appendInfoLine: "Preset:  ", presetName$
appendInfoLine: "Bands:   ", numBands, " (",
    ... round(min_band_Hz), "-", round(max_frequency_Hz), " Hz, log)"
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
# Cross-channel statistics accumulators (v1.3)
# v1.2 tracked these per channel but only the last channel's
# values survived to the summary. v1.3 aggregates across channels.
# ============================================================
xc_peakReduction = 0
xc_totalReductionSum = 0
xc_totalReductionCount = 0

# ============================================================
# MAIN PROCESSING LOOP (per channel)
# ============================================================

for ch from 1 to nChannels
    appendInfoLine: "-- Channel ", ch, " --"

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
    # PHASE B: Measure power per band via Intensity -> Matrix
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

    # Aggregate to cross-channel totals
    if peakReduction > xc_peakReduction
        xc_peakReduction = peakReduction
    endif
    xc_totalReductionSum = xc_totalReductionSum + totalReduction
    xc_totalReductionCount = xc_totalReductionCount + reductionCount
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
Rename: originalName$ + "_SootheLike_" + presetName$

# Capture final stats for visualization
selectObject: processed
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"

if xc_totalReductionCount > 0
    xc_avgRed = xc_totalReductionSum / xc_totalReductionCount
else
    xc_avgRed = 0
endif
xc_activePct = xc_totalReductionCount / (numBands * nFrames * nChannels) * 100

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================
if draw_visualization

    # Prepare mono copies of original and processed for display
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
    oMax = Get absolute extremum: 0, 0, "None"
    if oMax < 0.001
        oMax = 0.001
    endif
    ampMax = oMax * 1.15

    # Compute difference signal once
    selectObject: vizOrig
    vizDiff = Copy: "viz_diff"
    selectObject: vizDiff
    Formula: "self - object [" + string$(vizProc) + "]"

    selectObject: vizDiff
    dMax = Get absolute extremum: 0, 0, "None"
    diffMax = dMax * 1.15
    if diffMax < 0.0001
        diffMax = ampMax * 0.3
    endif

    # Spectra (only if user opted in)
    if show_spectrum
        selectObject: vizOrig
        specOrig = To Spectrum: "yes"
        selectObject: vizProc
        specProc = To Spectrum: "yes"
    endif

    Erase all
    Black
    Plain line

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##ADAPTIVE SPECTRAL RESONANCE SUPPRESSOR##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... originalName$
        ... + "  |  " + presetName$
        ... + "  |  " + string$(numBands) + " bands"
        ... + "  |  depth " + fixed$(max_reduction_dB, 1) + " dB"
        ... + "  |  sharp " + fixed$(sharpness, 2)
        ... + "  |  thresh " + fixed$(threshold_dB, 1) + " dB"

    # ----------------------------------------------------------
    # PANEL A: SPECTRUM COMPARISON  (left, headline)
    # Original (blue) vs Processed (green) — the spectral
    # processor's signature output. When Show_spectrum = OFF,
    # show a parameter report instead.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40

    if show_spectrum
        specMaxF = max_frequency_Hz
        if specMaxF > nyquist - 500
            specMaxF = nyquist - 500
        endif
        Axes: 0, specMaxF, -60, 10

        Paint rectangle: "{0.97, 0.97, 0.99}", 0, specMaxF, -60, 10

        # Reference grid
        Colour: "{0.88, 0.88, 0.92}"
        Line width: 1
        Dotted line
        gdb = -50
        while gdb <= 0
            Draw line: 0, gdb, specMaxF, gdb
            gdb += 10
        endwhile
        Solid line
        Line width: 1

        # Original spectrum (blue)
        selectObject: specOrig
        Colour: "{0.30, 0.45, 0.78}"
        Line width: 1.5
        Draw: 0, specMaxF, -60, 10, "no"

        # Processed spectrum (green)
        selectObject: specProc
        Colour: "{0.20, 0.65, 0.30}"
        Line width: 1.5
        Draw: 0, specMaxF, -60, 10, "no"
        Line width: 1

        # Inline legend
        Font size: 5
        Colour: "{0.30, 0.45, 0.78}"
        Text: specMaxF * 0.02, "left", 6, "half", "original"
        Colour: "{0.20, 0.65, 0.30}"
        Text: specMaxF * 0.14, "left", 6, "half", "processed"

        Colour: "Black"
        Line width: 1
        Draw inner box
        Font size: 6
        Text left: "yes", "dB"
        Text bottom: "yes", "Frequency (Hz)"
    else
        # Parameter report panel when spectrum is disabled
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1

        Font size: 9
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.05, "left", 0.93, "half", "Detection:"

        Font size: 10
        Colour: "{0.20, 0.50, 0.80}"
        Text: 0.10, "left", 0.85, "half", "Threshold:    " + fixed$(threshold_dB, 1) + " dB"
        Text: 0.10, "left", 0.78, "half", "Smoothing BW: " + fixed$(smoothing_bandwidth_Hz, 0) + " Hz"
        Text: 0.10, "left", 0.71, "half", "Bands:        " + string$(numBands) + " (" + fixed$(min_band_Hz, 0) + "-" + fixed$(max_frequency_Hz, 0) + " Hz log)"

        Font size: 9
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.05, "left", 0.62, "half", "Suppression:"

        Font size: 10
        Colour: "{0.85, 0.30, 0.30}"
        Text: 0.10, "left", 0.54, "half", "Max depth:    " + fixed$(max_reduction_dB, 1) + " dB"
        Text: 0.10, "left", 0.47, "half", "Sharpness:    " + fixed$(sharpness, 2)
        Text: 0.10, "left", 0.40, "half", "Attack:       " + fixed$(attack_ms, 0) + " ms"
        Text: 0.10, "left", 0.33, "half", "Release:      " + fixed$(release_ms, 0) + " ms"

        Font size: 9
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.05, "left", 0.24, "half", "Protection:"

        Font size: 10
        Colour: "{0.30, 0.62, 0.30}"
        Text: 0.10, "left", 0.16, "half", "LF protect:   < " + fixed$(protect_Hz, 0) + " Hz @ " + fixed$(protect_amount, 2)
        Text: 0.10, "left", 0.09, "half", "HF soft:      > " + fixed$(hF_soft_Hz, 0) + " Hz"
        Text: 0.10, "left", 0.02, "half", "Mix:          " + fixed$(mix * 100, 0) + "% wet"

        Colour: "Black"
        Draw inner box
    endif

    # ----------------------------------------------------------
    # PANEL B: DIFFERENCE SIGNAL  (right, headline)
    # The "resonance energy removed" — preserved from v1.2
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40

    Axes: 0, originalDur, -diffMax, diffMax
    Paint rectangle: "{1.00, 0.96, 0.94}", 0, originalDur, -diffMax, diffMax
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, originalDur, 0

    selectObject: vizDiff
    Colour: "{0.85, 0.28, 0.22}"
    Line width: 1
    Draw: 0, originalDur, -diffMax, diffMax, "no", "Curve"

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8

    Font size: 7
    Colour: "Black"
    if show_spectrum
        Text: 2.10, "centre", 7.30, "half", "Spectrum: original (blue) vs processed (green)"
    else
        Text: 2.10, "centre", 7.30, "half", "Parameter report (spectrum disabled)"
    endif
    Text: 6.10, "centre", 7.30, "half", "Difference signal (resonance energy removed)"

    # ----------------------------------------------------------
    # PANEL C: ZOOM OVERLAY  (first 500 ms)
    # Gray = original, blue = processed.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.75, 5.48

    zoomDur = 0.5
    if zoomDur > originalDur
        zoomDur = originalDur
    endif
    if zoomDur > finalDur
        zoomDur = finalDur
    endif

    selectObject: vizOrig
    z_peak1 = Get absolute extremum: 0, zoomDur, "None"
    selectObject: vizProc
    z_peak2 = Get absolute extremum: 0, zoomDur, "None"
    z_max = z_peak1
    if z_peak2 > z_max
        z_max = z_peak2
    endif
    if z_max < 0.001
        z_max = 0.001
    endif
    z_amp = z_max * 1.15

    Axes: 0, zoomDur, -z_amp, z_amp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, zoomDur, -z_amp, z_amp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, zoomDur, 0

    # Original behind
    selectObject: vizOrig
    Colour: "{0.65, 0.65, 0.65}"
    Line width: 1
    Draw: 0, zoomDur, -z_amp, z_amp, "no", "Curve"

    # Processed on top
    selectObject: vizProc
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, zoomDur, -z_amp, z_amp, "no", "Curve"

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Zoom: first " + fixed$(zoomDur * 1000, 0) + " ms  (gray = original, blue = processed)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL D: FULL WAVEFORM COMPARISON  (overlaid)
    # Gray = original, blue = processed.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.55, 7.72, 5.69, 6.48

    Axes: 0, originalDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, originalDur, -ampMax, ampMax
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, originalDur, 0

    selectObject: vizOrig
    Colour: "{0.65, 0.65, 0.65}"
    Line width: 1
    Draw: 0, originalDur, -ampMax, ampMax, "no", "Curve"

    selectObject: vizProc
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, originalDur, -ampMax, ampMax, "no", "Curve"

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Full waveform  (gray = original, blue = processed)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR  (suite standard — light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.55, 7.72, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    if show_spectrum
        specStr$ = "shown"
    else
        specStr$ = "off"
    endif

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + originalName$
        ... + "  |  Bands: " + string$(numBands)
        ... + "  |  Depth: " + fixed$(max_reduction_dB, 1) + " dB max"
        ... + "  |  Sharp: " + fixed$(sharpness, 2)
        ... + "  |  Thresh: " + fixed$(threshold_dB, 1) + " dB"
        ... + "  |  Atk/Rel: " + fixed$(attack_ms, 0) + "/" + fixed$(release_ms, 0) + " ms"

    Text: 0.02, "left", 0.28, "half",
        ... "Peak reduction: " + fixed$(xc_peakReduction, 1) + " dB"
        ... + "  |  Avg (active): " + fixed$(xc_avgRed, 1) + " dB"
        ... + "  |  Active: " + fixed$(xc_activePct, 1) + "%"
        ... + "  |  Mix: " + fixed$(mix * 100, 0) + "% wet"
        ... + "  |  Gain: " + fixed$(output_gain_dB, 1) + " dB"
        ... + "  |  Out: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
        ... + "  |  Spec: " + specStr$

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1

    # Cleanup viz objects
    removeObject: vizOrig, vizProc, vizDiff
    if show_spectrum
        removeObject: specOrig, specProc
    endif
endif

# ============================================================
# FINAL REPORT
# ============================================================
appendInfoLine: "-- Output --"
appendInfoLine: "  Peak reduction (all channels): ", fixed$(xc_peakReduction, 1), " dB"
appendInfoLine: "  Avg (active):                  ", fixed$(xc_avgRed, 1), " dB"
appendInfoLine: "  Active frame ratio:            ", fixed$(xc_activePct, 1), "%"
appendInfoLine: "  Mix:    ", fixed$(mix * 100, 0), "% wet"
appendInfoLine: "  Gain:   ", fixed$(output_gain_dB, 1), " dB"
appendInfoLine: "  Result: ", originalName$ + "_SootheLike_" + presetName$
appendInfoLine: ""
appendInfoLine: "=================================================="

selectObject: processed
if play_result
    Play
endif
