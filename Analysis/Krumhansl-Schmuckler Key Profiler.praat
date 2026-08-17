# ============================================================
# Praat AudioTools - Krumhansl-Schmuckler Key Profiler
# Author: Shai Cohen
# Version: 0.5 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# AUDIO-ADAPTED KEY PROFILING
#   The original Krumhansl-Schmuckler (K-S) algorithm compares a
#   12-element pitch-class salience vector with 24 major/minor key
#   profiles. In symbolic applications salience is commonly based on
#   sounding duration. This script estimates that vector from audio:
#
#       audio -> windowed FFT peaks -> harmonic-aware chroma
#             -> 24 profile comparisons -> global + rolling key
#
#   Therefore the front end is an AUDIO CHROMA APPROXIMATION, not a
#   literal note-duration transcription of the K-S input.
#
# PROFILE RULES
#   - Krumhansl-Kessler profiles: Pearson correlation (K-S rule)
#   - Temperley CBMS profiles: Pearson correlation used here as a
#     profile-only adaptation; this is not the full CBMS model with
#     segmentation/change penalties.
#   - Albrecht-Shanahan profiles: Euclidean distance, matching the
#     profile family for which those corpus-derived distributions were
#     proposed. For common display/ranking, distance d is converted to
#     similarity s = 1 - d/sqrt(2); lower raw distance is better.
#
# v0.5
#   - Phase-safe multichannel analysis: channel spectra are analyzed
#     separately and pooled in magnitude/chroma space; no mono fold-down.
#   - Relative spectral threshold replaces the absolute 0.0001 peak gate.
#   - One-pass rolling FFT peak scan + parabolic frequency refinement.
#   - Soft harmonic downweighting replaces destructive hard deletion.
#   - Quiet frames are excluded relative to the loudest analysis frame.
#   - Downsampling never violates the requested analysis Nyquist range.
#   - Decision confidence is reported as best-vs-runner-up margin, not
#     the winning correlation alone.
#   - Rolling local-key track added to reveal modulation/ambiguity.
#   - Output Table stores all 24 scores and raw metrics without recompute.
#   - 2x2 mechanism-first visualization with measured evidence only.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalSound = selected("Sound")
originalName$ = selected$("Sound")

form Key Profiler v0.5
    comment === Profile / musical reference ===
    optionmenu Profile_type: 1
        option Krumhansl-Kessler / Pearson (K-S)
        option Temperley CBMS profiles / Pearson adaptation
        option Albrecht-Shanahan / Euclidean
    positive Tuning_A4_Hz 440
    optionmenu Preset: 1
        option Custom
        option Classical / Orchestral
        option Pop / Rock
        option Jazz
        option Solo Instrument
        option Voice / Choir
    comment === Audio chroma analysis ===
    positive Min_frequency_Hz 60
    positive Max_frequency_Hz 1500
    positive Window_size_seconds 0.50
    positive Time_step_seconds 0.25
    natural Max_peaks_per_frame 10
    positive Relative_peak_threshold_dB 30
    boolean Suppress_likely_harmonics 1
    positive Harmonic_tolerance_cents 50
    real Harmonic_downweight_percent 35
    positive Silence_floor_below_peak_dB 45
    comment === Local key / speed ===
    positive Local_key_window_seconds 4.0
    boolean Use_downsampling 1
    positive Target_sample_rate_Hz 8000
    comment === Output / confidence ===
    real Minimum_key_score 0.20
    real Minimum_margin 0.05
    boolean Show_visualization 1
    boolean Create_output_table 1
endform

# ---------- Presets ----------
if preset = 2
    min_frequency_Hz = 50
    max_frequency_Hz = 2200
    window_size_seconds = 1.0
    time_step_seconds = 0.5
    max_peaks_per_frame = 14
    relative_peak_threshold_dB = 32
    harmonic_tolerance_cents = 45
    harmonic_downweight_percent = 40
    local_key_window_seconds = 6.0
    presetName$ = "Classical"
elsif preset = 3
    min_frequency_Hz = 70
    max_frequency_Hz = 1600
    window_size_seconds = 0.5
    time_step_seconds = 0.25
    max_peaks_per_frame = 10
    relative_peak_threshold_dB = 28
    harmonic_tolerance_cents = 55
    harmonic_downweight_percent = 35
    local_key_window_seconds = 4.0
    presetName$ = "PopRock"
elsif preset = 4
    min_frequency_Hz = 55
    max_frequency_Hz = 2000
    window_size_seconds = 0.75
    time_step_seconds = 0.25
    max_peaks_per_frame = 12
    relative_peak_threshold_dB = 32
    harmonic_tolerance_cents = 60
    harmonic_downweight_percent = 45
    local_key_window_seconds = 5.0
    presetName$ = "Jazz"
elsif preset = 5
    min_frequency_Hz = 70
    max_frequency_Hz = 2200
    window_size_seconds = 0.30
    time_step_seconds = 0.10
    max_peaks_per_frame = 8
    relative_peak_threshold_dB = 26
    harmonic_tolerance_cents = 40
    harmonic_downweight_percent = 30
    local_key_window_seconds = 3.0
    presetName$ = "Solo"
elsif preset = 6
    min_frequency_Hz = 70
    max_frequency_Hz = 1400
    window_size_seconds = 0.50
    time_step_seconds = 0.25
    max_peaks_per_frame = 9
    relative_peak_threshold_dB = 28
    harmonic_tolerance_cents = 50
    harmonic_downweight_percent = 35
    local_key_window_seconds = 4.0
    presetName$ = "Voice"
else
    presetName$ = "Custom"
endif

# ---------- Validation ----------
epsilon = 1e-12
if tuning_A4_Hz < 300 or tuning_A4_Hz > 500
    exitScript: "Tuning A4 must be between 300 and 500 Hz."
endif
if min_frequency_Hz <= 0 or max_frequency_Hz <= min_frequency_Hz
    exitScript: "Frequency range is invalid."
endif
if window_size_seconds <= 0 or time_step_seconds <= 0
    exitScript: "Window and time step must be positive."
endif
if max_peaks_per_frame < 1
    max_peaks_per_frame = 1
endif
if relative_peak_threshold_dB < 3
    relative_peak_threshold_dB = 3
elsif relative_peak_threshold_dB > 100
    relative_peak_threshold_dB = 100
endif
if harmonic_tolerance_cents < 1
    harmonic_tolerance_cents = 1
elsif harmonic_tolerance_cents > 200
    harmonic_tolerance_cents = 200
endif
if harmonic_downweight_percent < 0
    harmonic_downweight_percent = 0
elsif harmonic_downweight_percent > 100
    harmonic_downweight_percent = 100
endif
harmonicDownweight = harmonic_downweight_percent / 100
if silence_floor_below_peak_dB < 0
    silence_floor_below_peak_dB = 0
endif
if local_key_window_seconds < time_step_seconds
    local_key_window_seconds = time_step_seconds
endif
if minimum_margin < 0
    minimum_margin = 0
endif

# ---------- Profiles ----------
ksMaj# = {6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88}
ksMin# = {6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17}
tempMaj# = {5.0, 2.0, 3.5, 2.0, 4.5, 4.0, 2.0, 4.5, 2.0, 3.5, 1.5, 4.0}
tempMin# = {5.0, 2.0, 3.5, 4.5, 2.0, 4.0, 2.0, 4.5, 3.5, 2.0, 1.5, 4.0}
asMaj# = {0.238, 0.006, 0.111, 0.006, 0.137, 0.094, 0.016, 0.214, 0.009, 0.080, 0.008, 0.081}
asMin# = {0.220, 0.006, 0.104, 0.123, 0.019, 0.103, 0.012, 0.214, 0.062, 0.022, 0.061, 0.052}

if profile_type = 1
    profileMaj# = ksMaj#
    profileMin# = ksMin#
    profileName$ = "Krumhansl-Kessler"
    matchName$ = "Pearson r"
    useDistance = 0
elsif profile_type = 2
    profileMaj# = tempMaj#
    profileMin# = tempMin#
    profileName$ = "Temperley CBMS profiles"
    matchName$ = "Pearson r (profile-only adaptation)"
    useDistance = 0
else
    profileMaj# = asMaj#
    profileMin# = asMin#
    profileName$ = "Albrecht-Shanahan"
    matchName$ = "Euclidean distance"
    useDistance = 1
endif

# ---------- Source / analysis copy ----------
selectObject: originalSound
origDuration = Get total duration
origSR = Get sampling frequency
origChannels = Get number of channels
origStart = Get start time

if origDuration < window_size_seconds
    exitScript: "Analysis window is longer than the Sound."
endif
origNyquist = origSR / 2
if min_frequency_Hz >= origNyquist * 0.98
    exitScript: "Minimum analysis frequency is above the source Nyquist frequency."
endif
if max_frequency_Hz > origNyquist * 0.98
    max_frequency_Hz = origNyquist * 0.98
endif

analysisSRWanted = origSR
if use_downsampling
    # Keep comfortable room above the highest analysis frequency.
    analysisSRWanted = max(target_sample_rate_Hz, 2.4 * max_frequency_Hz)
    if analysisSRWanted > origSR
        analysisSRWanted = origSR
    endif
endif

selectObject: originalSound
if use_downsampling and analysisSRWanted < origSR - 1
    analysisBase = Resample: analysisSRWanted, 50
    resampled = 1
else
    analysisBase = Copy: "key_analysis"
    resampled = 0
endif
selectObject: analysisBase
Shift times to: "start time", 0
analysisSR = Get sampling frequency
analysisChannels = Get number of channels
analysisNyquist = analysisSR / 2
if max_frequency_Hz > analysisNyquist * 0.98
    max_frequency_Hz = analysisNyquist * 0.98
endif

# Separate channels for phase-safe magnitude evidence.
bestDisplayChannel = 1
bestChannelRms = -1
for ch from 1 to analysisChannels
    selectObject: analysisBase
    if analysisChannels = 1
        chId = Copy: "key_ch1"
    else
        chId = Extract one channel: ch
        Rename: "key_ch" + string$(ch)
    endif
    analysisChannel_'ch' = chId
    chRms = Get root-mean-square: 0, 0
    if chRms > bestChannelRms
        bestChannelRms = chRms
        bestDisplayChannel = ch
    endif
endfor

# ---------- Header ----------
clearinfo
writeInfoLine: "=== Key Profiler v0.5 ==="
appendInfoLine: "Input: ", originalName$, " | ", fixed$(origDuration, 3), " s | ", origChannels, " channel(s)"
appendInfoLine: "Profile: ", profileName$, " | matching: ", matchName$
appendInfoLine: "Preset: ", presetName$, " | A4 = ", fixed$(tuning_A4_Hz, 1), " Hz"
if resampled
    appendInfoLine: "Analysis SR: ", fixed$(analysisSR,0), " Hz (downsampled safely for max ", fixed$(max_frequency_Hz,0), " Hz)"
else
    appendInfoLine: "Analysis SR: ", fixed$(analysisSR,0), " Hz"
endif
appendInfoLine: "Multichannel evidence: spectra pooled in magnitude/chroma space; display channel ", bestDisplayChannel, " is strongest RMS"
appendInfoLine: "Audio front end: Hanning FFT peaks -> relative threshold -> soft harmonic suppression -> frame chroma"
appendInfoLine: "Window ", fixed$(window_size_seconds,3), " s | step ", fixed$(time_step_seconds,3), " s | local key window ", fixed$(local_key_window_seconds,2), " s"
appendInfoLine: ""

# ---------- Frame analysis ----------
nFrames = floor((origDuration - window_size_seconds) / time_step_seconds) + 1
if nFrames < 1
    nFrames = 1
endif
frameTime# = zero#(nFrames)
frameRms# = zero#(nFrames)
frameHasEvidence# = zero#(nFrames)
frameValid# = zero#(nFrames)
frameChroma# = zero#(nFrames * 12)

cachedDx = 0
cachedNBins = 0
cachedMinBin = 0
cachedMaxBin = 0
maxFrameRms = 0

appendInfoLine: "Analyzing ", nFrames, " frames..."

for f from 1 to nFrames
    frameStart = (f - 1) * time_step_seconds
    frameEnd = frameStart + window_size_seconds
    frameMid = 0.5 * (frameStart + frameEnd)
    frameTime#[f] = frameMid

    selectObject: analysisBase
    fr = Get root-mean-square: frameStart, frameEnd
    if fr = undefined
        fr = 0
    endif
    frameRms#[f] = fr
    if fr > maxFrameRms
        maxFrameRms = fr
    endif

    pooled# = zero#(12)
    channelRms# = zero#(analysisChannels)
    channelTotals# = zero#(analysisChannels)
    channelLedger# = zero#(analysisChannels * 12)
    sumChannelRms = 0

    for ch from 1 to analysisChannels
        selectObject: analysisChannel_'ch'
        extract = Extract part: frameStart, frameEnd, "Hanning", 1.0, "no"
        channelFrameRms = Get root-mean-square: 0, 0
        if channelFrameRms = undefined
            channelFrameRms = 0
        endif
        channelRms#[ch] = channelFrameRms
        sumChannelRms += channelFrameRms
        spectrum = To Spectrum: "yes"

        if cachedDx = 0
            cachedNBins = Get number of bins
            cachedDx = Get bin width
            cachedMinBin = ceiling(min_frequency_Hz / cachedDx) + 1
            cachedMaxBin = floor(max_frequency_Hz / cachedDx) + 1
            if cachedMinBin < 2
                cachedMinBin = 2
            endif
            if cachedMaxBin > cachedNBins - 1
                cachedMaxBin = cachedNBins - 1
            endif
        endif

        rawPeakCount = 0
        channelMaxDb = -999
        if cachedMaxBin >= cachedMinBin
            leftBin = cachedMinBin - 1
            rePrev = Get real value in bin: leftBin
            imPrev = Get imaginary value in bin: leftBin
            mPrev = sqrt(rePrev * rePrev + imPrev * imPrev)

            reCur = Get real value in bin: cachedMinBin
            imCur = Get imaginary value in bin: cachedMinBin
            mCur = sqrt(reCur * reCur + imCur * imCur)

            for ib from cachedMinBin to cachedMaxBin
                nextBin = ib + 1
                reNext = Get real value in bin: nextBin
                imNext = Get imaginary value in bin: nextBin
                mNext = sqrt(reNext * reNext + imNext * imNext)

                if mCur > epsilon
                    dbCur = 20 * log10(mCur)
                else
                    dbCur = -999
                endif
                if dbCur > channelMaxDb
                    channelMaxDb = dbCur
                endif

                if mCur > mPrev and mCur >= mNext
                    y1 = ln(mPrev + epsilon)
                    y2 = ln(mCur + epsilon)
                    y3 = ln(mNext + epsilon)
                    denom = y1 - 2 * y2 + y3
                    delta = 0
                    if abs(denom) > 1e-12
                        delta = 0.5 * (y1 - y3) / denom
                        if delta < -0.5
                            delta = -0.5
                        elsif delta > 0.5
                            delta = 0.5
                        endif
                    endif
                    rawPeakCount += 1
                    rawPeakFreq_'rawPeakCount' = (ib - 1 + delta) * cachedDx
                    rawPeakDb_'rawPeakCount' = dbCur
                endif
                mPrev = mCur
                mCur = mNext
            endfor
        endif

        nPeaks = 0
        if channelMaxDb > -900
            effectiveThreshold = channelMaxDb - relative_peak_threshold_dB
            for rp from 1 to rawPeakCount
                if rawPeakDb_'rp' >= effectiveThreshold
                    nPeaks += 1
                    peakFreq_'nPeaks' = rawPeakFreq_'rp'
                    peakDb_'nPeaks' = rawPeakDb_'rp'
                endif
            endfor

            keepN = nPeaks
            if keepN > max_peaks_per_frame
                keepN = max_peaks_per_frame
            endif
            # Partial selection sort: strongest keepN only.
            for i from 1 to keepN
                bestJ = i
                bestDb = peakDb_'i'
                for j from i + 1 to nPeaks
                    if peakDb_'j' > bestDb
                        bestDb = peakDb_'j'
                        bestJ = j
                    endif
                endfor
                if bestJ <> i
                    tf = peakFreq_'i'
                    td = peakDb_'i'
                    peakFreq_'i' = peakFreq_'bestJ'
                    peakDb_'i' = peakDb_'bestJ'
                    peakFreq_'bestJ' = tf
                    peakDb_'bestJ' = td
                endif
            endfor
            nPeaks = keepN

            channelTotal = 0
            for i from 1 to nPeaks
                pf = peakFreq_'i'
                pdb = peakDb_'i'
                factor = 1
                if suppress_likely_harmonics
                    for j from 1 to nPeaks
                        lowerF = peakFreq_'j'
                        lowerDb = peakDb_'j'
                        if lowerF < pf and lowerDb >= pdb - 24
                            ratio = pf / lowerF
                            hGuess = round(ratio)
                            if hGuess >= 2 and hGuess <= 8
                                centsDiff = 1200 * abs(ln(ratio / hGuess) / ln(2))
                                if centsDiff <= harmonic_tolerance_cents
                                    if harmonicDownweight < factor
                                        factor = harmonicDownweight
                                    endif
                                endif
                            endif
                        endif
                    endfor
                endif

                relMag = 10 ^ ((pdb - channelMaxDb) / 20)
                evidence = relMag * factor
                midi = 69 + 12 * (ln(pf / tuning_A4_Hz) / ln(2))
                midiRounded = round(midi)
                pc = midiRounded mod 12
                if pc < 0
                    pc += 12
                endif
                ledIdx = (ch - 1) * 12 + pc + 1
                channelLedger#[ledIdx] = channelLedger#[ledIdx] + evidence
                channelTotal += evidence
            endfor
            channelTotals#[ch] = channelTotal
        endif

        removeObject: spectrum, extract
    endfor

    # Phase-safe pooling: normalize within each channel, then weight by
    # that channel's RMS contribution to the frame.
    if sumChannelRms > epsilon
        for ch from 1 to analysisChannels
            if channelTotals#[ch] > epsilon
                chWeight = channelRms#[ch] / sumChannelRms
                for pc from 0 to 11
                    ledIdx = (ch - 1) * 12 + pc + 1
                    pooled#[pc + 1] = pooled#[pc + 1] + chWeight * channelLedger#[ledIdx] / channelTotals#[ch]
                endfor
            endif
        endfor
    endif

    poolSum = 0
    for pc from 1 to 12
        poolSum += pooled#[pc]
    endfor
    if poolSum > epsilon
        frameHasEvidence#[f] = 1
        for pc from 0 to 11
            idx = (f - 1) * 12 + pc + 1
            frameChroma#[idx] = pooled#[pc + 1] / poolSum
        endfor
    endif
endfor

# ---------- Silence gating / global chroma ----------
if maxFrameRms > epsilon
    silenceRms = maxFrameRms * 10 ^ (-silence_floor_below_peak_dB / 20)
else
    silenceRms = 1e300
endif

globalChroma# = zero#(12)
validFrames = 0
for f from 1 to nFrames
    if frameHasEvidence#[f] = 1 and frameRms#[f] >= silenceRms
        frameValid#[f] = 1
        validFrames += 1
        for pc from 0 to 11
            idx = (f - 1) * 12 + pc + 1
            globalChroma#[pc + 1] = globalChroma#[pc + 1] + frameChroma#[idx]
        endfor
    endif
endfor

if validFrames = 0
    # Cleanup before exiting.
    for ch from 1 to analysisChannels
        removeObject: analysisChannel_'ch'
    endfor
    removeObject: analysisBase
    exitScript: "No usable tonal frames were found. Lower the silence/peak thresholds or check the frequency range."
endif

globalSum = 0
for pc from 1 to 12
    globalSum += globalChroma#[pc]
endfor
for pc from 1 to 12
    globalChroma#[pc] = globalChroma#[pc] / globalSum
endfor
validPct = 100 * validFrames / nFrames

# ---------- Global 24-key comparison ----------
allScore# = zero#(24)
allRaw# = zero#(24)
for root from 0 to 11
    @scoreKey: globalChroma#, root, 1
    allScore#[root + 1] = scoreKey.score
    allRaw#[root + 1] = scoreKey.raw
    @scoreKey: globalChroma#, root, 2
    allScore#[root + 13] = scoreKey.score
    allRaw#[root + 13] = scoreKey.raw
endfor

bestIdx = 1
bestScore = allScore#[1]
secondIdx = 1
secondScore = -1e300
for i from 1 to 24
    if allScore#[i] > bestScore
        secondScore = bestScore
        secondIdx = bestIdx
        bestScore = allScore#[i]
        bestIdx = i
    elsif i <> bestIdx and allScore#[i] > secondScore
        secondScore = allScore#[i]
        secondIdx = i
    endif
endfor
# If index 1 stayed best, secondScore was filled by later entries.
if secondScore < -1e200
    secondScore = allScore#[2]
    secondIdx = 2
endif
bestMargin = bestScore - secondScore

@keyIndexToName: bestIdx
bestKey$ = keyIndexToName.result$
bestRoot = keyIndexToName.root
bestMode = keyIndexToName.mode
@keyIndexToName: secondIdx
secondKey$ = keyIndexToName.result$

if bestScore < minimum_key_score or bestMargin < minimum_margin
    decisionLabel$ = "AMBIGUOUS"
elsif bestMargin < 2 * minimum_margin
    decisionLabel$ = "MODERATE"
else
    decisionLabel$ = "CLEAR"
endif

# ---------- Prefix sums for rolling local key ----------
prefix# = zero#((nFrames + 1) * 12)
prefixCount# = zero#(nFrames + 1)
for f from 1 to nFrames
    prefixCount#[f + 1] = prefixCount#[f] + frameValid#[f]
    for pc from 0 to 11
        prevIdx = (f - 1) * 12 + pc + 1
        currIdx = f * 12 + pc + 1
        srcIdx = (f - 1) * 12 + pc + 1
        prefix#[currIdx] = prefix#[prevIdx]
        if frameValid#[f]
            prefix#[currIdx] = prefix#[currIdx] + frameChroma#[srcIdx]
        endif
    endfor
endfor

localHalfFrames = round(0.5 * local_key_window_seconds / time_step_seconds)
if localHalfFrames < 0
    localHalfFrames = 0
endif
localBest# = zero#(nFrames)
localScore# = zero#(nFrames)
localMargin# = zero#(nFrames)
localValid# = zero#(nFrames)

for f from 1 to nFrames
    a = f - localHalfFrames
    b = f + localHalfFrames
    if a < 1
        a = 1
    endif
    if b > nFrames
        b = nFrames
    endif
    countLocal = prefixCount#[b + 1] - prefixCount#[a]
    if countLocal > 0
        localChroma# = zero#(12)
        localSum = 0
        for pc from 0 to 11
            hiIdx = b * 12 + pc + 1
            loIdx = (a - 1) * 12 + pc + 1
            v = prefix#[hiIdx] - prefix#[loIdx]
            localChroma#[pc + 1] = v
            localSum += v
        endfor
        if localSum > epsilon
            for pc from 1 to 12
                localChroma#[pc] = localChroma#[pc] / localSum
            endfor
            lb = 1
            ls = -1e300
            l2 = -1e300
            for root from 0 to 11
                @scoreKey: localChroma#, root, 1
                sc = scoreKey.score
                if sc > ls
                    l2 = ls
                    ls = sc
                    lb = root + 1
                elsif sc > l2
                    l2 = sc
                endif
                @scoreKey: localChroma#, root, 2
                sc = scoreKey.score
                if sc > ls
                    l2 = ls
                    ls = sc
                    lb = root + 13
                elsif sc > l2
                    l2 = sc
                endif
            endfor
            localBest#[f] = lb
            localScore#[f] = ls
            localMargin#[f] = ls - l2
            localValid#[f] = 1
        endif
    endif
endfor

# Light confirmation for the rolling key track. The raw profile score is
# still shown in the margin panel; this only prevents one-frame key flicker
# in the categorical timeline.
localConfirmFrames = round(0.50 / time_step_seconds)
if localConfirmFrames < 1
    localConfirmFrames = 1
endif
stableLocalKey = 0
pendingLocalKey = 0
pendingLocalCount = 0
for f from 1 to nFrames
    if localValid#[f]
        rawKey = localBest#[f]
        if stableLocalKey = 0
            stableLocalKey = rawKey
            pendingLocalKey = 0
            pendingLocalCount = 0
        elsif rawKey = stableLocalKey
            pendingLocalKey = 0
            pendingLocalCount = 0
        else
            if rawKey = pendingLocalKey
                pendingLocalCount += 1
            else
                pendingLocalKey = rawKey
                pendingLocalCount = 1
            endif
            if pendingLocalCount >= localConfirmFrames
                stableLocalKey = pendingLocalKey
                pendingLocalKey = 0
                pendingLocalCount = 0
            endif
        endif
        localBest#[f] = stableLocalKey
    else
        pendingLocalKey = 0
        pendingLocalCount = 0
    endif
endfor

# Merge confirmed local key frames into visual timeline segments.
maxLocalSegs = nFrames
localSegStart# = zero#(maxLocalSegs)
localSegEnd# = zero#(maxLocalSegs)
localSegKey# = zero#(maxLocalSegs)
nLocalSegs = 0
inLocal = 0
for f from 1 to nFrames
    if localValid#[f]
        thisKey = localBest#[f]
        if inLocal = 0
            nLocalSegs += 1
            localSegStart#[nLocalSegs] = max(0, frameTime#[f] - 0.5 * time_step_seconds)
            localSegKey#[nLocalSegs] = thisKey
            inLocal = 1
        elsif thisKey <> localSegKey#[nLocalSegs]
            localSegEnd#[nLocalSegs] = max(localSegStart#[nLocalSegs], frameTime#[f] - 0.5 * time_step_seconds)
            nLocalSegs += 1
            localSegStart#[nLocalSegs] = localSegEnd#[nLocalSegs - 1]
            localSegKey#[nLocalSegs] = thisKey
        endif
        localSegEnd#[nLocalSegs] = min(origDuration, frameTime#[f] + 0.5 * time_step_seconds)
    else
        if inLocal
            localSegEnd#[nLocalSegs] = max(localSegStart#[nLocalSegs], frameTime#[f] - 0.5 * time_step_seconds)
            inLocal = 0
        endif
    endif
endfor

# ---------- Report ----------
appendInfoLine: "Accepted tonal frames: ", validFrames, "/", nFrames, " (", fixed$(validPct,1), "%)"
appendInfoLine: ""
appendInfoLine: "GLOBAL KEY: ", bestKey$
appendInfoLine: "  score: ", fixed$(bestScore,4), " | runner-up: ", secondKey$, " (", fixed$(secondScore,4), ")"
appendInfoLine: "  decision margin: ", fixed$(bestMargin,4), " -> ", decisionLabel$
if useDistance
    appendInfoLine: "  raw Albrecht-Shanahan distance: ", fixed$(allRaw#[bestIdx],4), " (lower is better)"
else
    appendInfoLine: "  Pearson correlation: ", fixed$(allRaw#[bestIdx],4)
endif
appendInfoLine: ""
appendInfoLine: "Top 5 candidates:"
rankWork# = allScore#
for rank from 1 to 5
    ri = 1
    rv = rankWork#[1]
    for i from 2 to 24
        if rankWork#[i] > rv
            rv = rankWork#[i]
            ri = i
        endif
    endfor
    @keyIndexToName: ri
    appendInfoLine: "  ", rank, ". ", keyIndexToName.result$, "  score ", fixed$(rv,4)
    rankWork#[ri] = -1e300
endfor

# ---------- Output Table ----------
table = 0
if create_output_table
    safeTableName$ = replace$(originalName$, " ", "_", 0)
    table = Create Table with column names: "KeyProfile_" + safeTableName$, 24, "key mode score raw_metric metric rank"
    for i from 1 to 24
        @keyIndexToName: i
        selectObject: table
        Set string value: i, "key", keyIndexToName.result$
        if i <= 12
            Set string value: i, "mode", "Major"
        else
            Set string value: i, "mode", "Minor"
        endif
        Set numeric value: i, "score", allScore#[i]
        Set numeric value: i, "raw_metric", allRaw#[i]
        Set string value: i, "metric", matchName$
        rr = 1
        for j from 1 to 24
            if allScore#[j] > allScore#[i]
                rr += 1
            endif
        endfor
        Set numeric value: i, "rank", rr
    endfor
    appendInfoLine: "Created Table: KeyProfile_", safeTableName$
endif

# ---------- Visualization ----------
if show_visualization
    Erase all

    # Shared helpers for plots.
    chromaMax = 0
    for pc from 1 to 12
        if globalChroma#[pc] > chromaMax
            chromaMax = globalChroma#[pc]
        endif
    endfor
    if chromaMax < epsilon
        chromaMax = 1
    endif

    if bestMode = 1
        winProfile# = profileMaj#
    else
        winProfile# = profileMin#
    endif
    profileMax = winProfile#[1]
    for i from 2 to 12
        if winProfile#[i] > profileMax
            profileMax = winProfile#[i]
        endif
    endfor

    # ----- Title -----
    Select outer viewport: 0.4, 7.8, 0.04, 0.25
    Select inner viewport: 0.4, 7.8, 0.04, 0.25
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.52, "half", "Key Profiler v0.5 - " + bestKey$

    Select outer viewport: 0.4, 7.8, 0.28, 0.46
    Select inner viewport: 0.4, 7.8, 0.28, 0.46
    Axes: 0, 1, 0, 1
    Font size: 6.5
    Colour: "{0.35,0.35,0.40}"
    Text: 0.5, "centre", 0.52, "half", "windowed FFT peaks -> harmonic-aware audio chroma -> 24 profile comparisons -> rolling local key"

    # ----- Panel A title -----
    Select outer viewport: 0.30, 3.95, 0.60, 0.82
    Select inner viewport: 0.30, 3.95, 0.60, 0.82
    Axes: 0, 1, 0, 1
    Font size: 8.5
    Colour: "Black"
    Text: 0.02, "left", 0.62, "half", "A  AUDIO CHROMA / WINNING PROFILE"
    Font size: 5.5
    Colour: "{0.35,0.35,0.40}"
    Text: 0.02, "left", 0.15, "half", "shape-normalized; bars = measured chroma, line = " + bestKey$ + " profile"

    Select outer viewport: 0.30, 3.95, 0.84, 2.60
    Select inner viewport: 0.62, 3.80, 0.95, 2.42
    Axes: -0.5, 11.5, 0, 1.10
    Paint rectangle: "{0.975,0.975,0.978}", -0.5, 11.5, 0, 1.10
    for pc from 0 to 11
        y = globalChroma#[pc + 1] / chromaMax
        if pc = bestRoot
            c$ = "{0.25,0.62,0.38}"
        else
            c$ = "{0.30,0.50,0.78}"
        endif
        Paint rectangle: c$, pc - 0.31, pc + 0.31, 0, y
    endfor
    # Winning profile in absolute pitch-class coordinates.
    Colour: "{0.42,0.42,0.46}"
    Line width: 1.5
    prevSet = 0
    for pc from 0 to 11
        degree = (pc - bestRoot + 12) mod 12
        py = winProfile#[degree + 1] / profileMax
        if prevSet
            Draw line: pc - 1, prevY, pc, py
        endif
        # Cross marker, not Paint circle (world-size ambiguity across Praat versions).
        Draw line: pc - 0.10, py, pc + 0.10, py
        Draw line: pc, py - 0.025, pc, py + 0.025
        prevY = py
        prevSet = 1
    endfor
    Colour: "Black"
    Draw inner box
    Font size: 5
    for pc from 0 to 11
        @numToNote: pc
        Text: pc, "centre", -0.045, "top", numToNote.result$
    endfor
    Text left: "yes", "relative shape"

    # ----- Panel B title -----
    Select outer viewport: 4.05, 7.75, 0.60, 0.82
    Select inner viewport: 4.05, 7.75, 0.60, 0.82
    Axes: 0, 1, 0, 1
    Font size: 8.5
    Colour: "Black"
    Text: 0.02, "left", 0.62, "half", "B  ALL 24 KEY SCORES"
    Font size: 5.5
    Colour: "{0.35,0.35,0.40}"
    Text: 0.02, "left", 0.15, "half", matchName$ + " | green = winner, orange = runner-up"

    if useDistance
        scoreMin = 0
        scoreMax = 1
    else
        scoreMin = -1
        scoreMax = 1
    endif
    Select outer viewport: 4.05, 7.75, 0.84, 2.60
    Select inner viewport: 4.42, 7.62, 0.95, 2.42
    Axes: 0.5, 24.5, scoreMin, scoreMax
    Paint rectangle: "{0.975,0.975,0.978}", 0.5, 24.5, scoreMin, scoreMax
    if scoreMin < 0
        Colour: "{0.82,0.82,0.85}"
        Draw line: 0.5, 0, 24.5, 0
    endif
    for i from 1 to 24
        if i = bestIdx
            c$ = "{0.25,0.62,0.38}"
        elsif i = secondIdx
            c$ = "{0.86,0.52,0.22}"
        else
            c$ = "{0.60,0.60,0.64}"
        endif
        Colour: c$
        Draw line: i, max(0, scoreMin), i, allScore#[i]
    endfor
    Colour: "Black"
    Draw inner box
    Font size: 5
    # Root labels every other pitch class in both mode halves.
    for root from 0 to 11
        if root mod 2 = 0
            @numToNote: root
            Text: root + 1, "centre", scoreMin - 0.04 * (scoreMax - scoreMin), "top", numToNote.result$
            Text: root + 13, "centre", scoreMin - 0.04 * (scoreMax - scoreMin), "top", numToNote.result$
        endif
    endfor
    Font size: 5.5
    Text: 6.5, "centre", scoreMin + 0.05 * (scoreMax - scoreMin), "bottom", "MAJOR"
    Text: 18.5, "centre", scoreMin + 0.05 * (scoreMax - scoreMin), "bottom", "MINOR"
    Text left: "yes", "score"

    # ----- Panel C title -----
    Select outer viewport: 0.30, 3.95, 2.82, 3.04
    Select inner viewport: 0.30, 3.95, 2.82, 3.04
    Axes: 0, 1, 0, 1
    Font size: 8.5
    Colour: "Black"
    Text: 0.02, "left", 0.62, "half", "C  LOCAL KEY TRACK"
    Font size: 5.5
    Colour: "{0.35,0.35,0.40}"
    Text: 0.02, "left", 0.15, "half", "rolling " + fixed$(local_key_window_seconds,1) + " s estimate + 0.5 s change confirmation; not ground truth"

    Select outer viewport: 0.30, 3.95, 3.06, 4.82
    Select inner viewport: 0.62, 3.80, 3.17, 4.64
    Axes: 0, origDuration, 0, 1
    Paint rectangle: "{0.975,0.975,0.978}", 0, origDuration, 0, 1
    for s from 1 to nLocalSegs
        kidx = localSegKey#[s]
        if kidx <= 12
            c$ = "{0.68,0.80,0.93}"
        else
            c$ = "{0.86,0.75,0.90}"
        endif
        Paint rectangle: c$, localSegStart#[s], localSegEnd#[s], 0.18, 0.82
        segWidth = localSegEnd#[s] - localSegStart#[s]
        if segWidth >= max(0.35, origDuration / 14)
            @keyIndexToName: kidx
            Font size: 5.5
            Colour: "{0.18,0.18,0.22}"
            Text: 0.5 * (localSegStart#[s] + localSegEnd#[s]), "centre", 0.50, "half", keyIndexToName.short$
        endif
    endfor
    Colour: "Black"
    Draw inner box
    Font size: 5
    @niceStep: origDuration, 5
    Marks bottom every: 1, niceStep.step, "yes", "yes", "no"
    Font size: 6
    Text bottom: "yes", "time (s)"
    Text left: "yes", "local key"

    # ----- Panel D title -----
    Select outer viewport: 4.05, 7.75, 2.82, 3.04
    Select inner viewport: 4.05, 7.75, 2.82, 3.04
    Axes: 0, 1, 0, 1
    Font size: 8.5
    Colour: "Black"
    Text: 0.02, "left", 0.62, "half", "D  DECISION MARGIN"
    Font size: 5.5
    Colour: "{0.35,0.35,0.40}"
    Text: 0.02, "left", 0.15, "half", "best local score - runner-up; dashed = requested minimum"

    marginMax = minimum_margin * 1.5
    if marginMax < bestMargin * 1.2
        marginMax = bestMargin * 1.2
    endif
    for f from 1 to nFrames
        if localValid#[f] and localMargin#[f] > marginMax
            marginMax = localMargin#[f] * 1.1
        endif
    endfor
    if marginMax < 0.05
        marginMax = 0.05
    endif

    Select outer viewport: 4.05, 7.75, 3.06, 4.82
    Select inner viewport: 4.42, 7.62, 3.17, 4.64
    Axes: 0, origDuration, 0, marginMax
    Paint rectangle: "{0.975,0.975,0.978}", 0, origDuration, 0, marginMax
    Colour: "{0.80,0.28,0.26}"
    Dashed line
    Draw line: 0, minimum_margin, origDuration, minimum_margin
    Solid line
    Colour: "{0.28,0.50,0.78}"
    Line width: 1.5
    havePrev = 0
    for f from 1 to nFrames
        if localValid#[f]
            if havePrev
                if f = prevF + 1
                    Draw line: frameTime#[prevF], localMargin#[prevF], frameTime#[f], localMargin#[f]
                endif
            endif
            prevF = f
            havePrev = 1
        else
            havePrev = 0
        endif
    endfor
    Colour: "{0.25,0.62,0.38}"
    Draw line: 0, bestMargin, origDuration, bestMargin
    Colour: "Black"
    Draw inner box
    Font size: 5
    @niceStep: origDuration, 5
    Marks bottom every: 1, niceStep.step, "yes", "yes", "no"
    @niceStep: marginMax, 4
    Marks left every: 1, niceStep.step, "yes", "yes", "no"
    Font size: 6
    Text bottom: "yes", "time (s)"
    Text left: "yes", "score margin"

    # ----- Summary -----
    Select outer viewport: 0.4, 7.7, 4.93, 5.28
    Select inner viewport: 0.4, 7.7, 4.93, 5.28
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96,0.96,0.965}", 0, 1, 0, 1
    Font size: 7
    Colour: "{0.25,0.25,0.28}"
    Text: 0.02, "left", 0.66, "half", "GLOBAL  " + bestKey$ + "   score " + fixed$(bestScore,3) + "   runner-up " + secondKey$ + "   margin " + fixed$(bestMargin,3) + "   " + decisionLabel$
    Font size: 6.2
    Colour: "{0.38,0.38,0.42}"
    Text: 0.02, "left", 0.22, "half", "profile " + profileName$ + " | valid frames " + fixed$(validPct,1) + "% | " + string$(analysisChannels) + " channel(s), phase-safe magnitude pooling | A4 " + fixed$(tuning_A4_Hz,1) + " Hz"
endif

# ---------- Cleanup / selection ----------
for ch from 1 to analysisChannels
    removeObject: analysisChannel_'ch'
endfor
removeObject: analysisBase

selectObject: originalSound
if create_output_table and table <> 0
    plusObject: table
endif

appendInfoLine: ""
appendInfoLine: "Done."

# ============================================================
# Procedures
# ============================================================
procedure scoreKey: .v#, .root, .mode
    if .mode = 1
        .p# = profileMaj#
    else
        .p# = profileMin#
    endif

    if useDistance
        # A-S profiles are distributions; normalize small published
        # rounding discrepancy before Euclidean comparison.
        .psum = 0
        for .i from 1 to 12
            .psum += .p#[.i]
        endfor
        .d2 = 0
        for .i from 0 to 11
            .idx = (.root + .i) mod 12
            .a = .v#[.idx + 1]
            .b = .p#[.i + 1] / .psum
            .d2 += (.a - .b) ^ 2
        endfor
        .d = sqrt(.d2)
        .sim = 1 - .d / sqrt(2)
        if .sim < 0
            .sim = 0
        elsif .sim > 1
            .sim = 1
        endif
        .raw = .d
        .score = .sim
    else
        .sx = 0
        .sy = 0
        .sxy = 0
        .sx2 = 0
        .sy2 = 0
        for .i from 0 to 11
            .idx = (.root + .i) mod 12
            .x = .v#[.idx + 1]
            .y = .p#[.i + 1]
            .sx += .x
            .sy += .y
            .sxy += .x * .y
            .sx2 += .x * .x
            .sy2 += .y * .y
        endfor
        .dx = 12 * .sx2 - .sx * .sx
        .dy = 12 * .sy2 - .sy * .sy
        if .dx > 0 and .dy > 0
            .r = (12 * .sxy - .sx * .sy) / (sqrt(.dx) * sqrt(.dy))
        else
            .r = -1
        endif
        .raw = .r
        .score = .r
    endif
endproc

procedure numToNote: .pc
    if .pc = 0
        .result$ = "C"
    elsif .pc = 1
        .result$ = "Db"
    elsif .pc = 2
        .result$ = "D"
    elsif .pc = 3
        .result$ = "Eb"
    elsif .pc = 4
        .result$ = "E"
    elsif .pc = 5
        .result$ = "F"
    elsif .pc = 6
        .result$ = "Gb"
    elsif .pc = 7
        .result$ = "G"
    elsif .pc = 8
        .result$ = "Ab"
    elsif .pc = 9
        .result$ = "A"
    elsif .pc = 10
        .result$ = "Bb"
    else
        .result$ = "B"
    endif
endproc

procedure keyIndexToName: .idx
    if .idx <= 12
        .root = .idx - 1
        .mode = 1
        .modeName$ = "Major"
        .shortMode$ = "M"
    else
        .root = .idx - 13
        .mode = 2
        .modeName$ = "Minor"
        .shortMode$ = "m"
    endif
    @numToNote: .root
    .result$ = numToNote.result$ + " " + .modeName$
    .short$ = numToNote.result$ + .shortMode$
endproc

procedure niceStep: .range, .target
    .raw = .range / .target
    .mag = 10 ^ floor(log10(max(1e-12, .raw)))
    .n = .raw / .mag
    if .n < 1.5
        .step = 1 * .mag
    elsif .n < 3.5
        .step = 2 * .mag
    elsif .n < 7.5
        .step = 5 * .mag
    else
        .step = 10 * .mag
    endif
endproc
