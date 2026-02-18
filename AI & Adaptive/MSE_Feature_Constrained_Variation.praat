# ============================================================
# Praat AudioTools - MSE_Feature_Constrained_Variation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Feature-constrained experimental sound variation using MSE
#   distance control. Extracts high-dimensional features (MFCC,
#   spectral centroid, flux, harmonicity, sub-band energy) and
#   iteratively applies spectral/temporal transformations until
#   the transformed sound reaches a target MSE distance band
#   from the original.
#
#   Preserves: overall duration (structural anchor)
#   Transforms: spectral tilt, band noise, segment-wise
#   spectral coloring, amplitude modulation
#
# Category: Composition
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

originalSound = selected("Sound")
originalName$ = selected$("Sound")

# ============================================================
# FORM
# ============================================================
form MSE Feature-Constrained Variation v1.1
    comment === Preset ===
    optionmenu Preset: 2
        option Subtle (spectral drift only)
        option Standard (balanced)
        option Granular (structural fracture)
        option Spectral (timbral destruction)
        option Extreme (full disruption)
        option Custom
    comment === MSE Control (Custom only) ===
    positive Target_distance 0.15
    positive Tolerance 0.04
    natural Max_iterations 15
    comment === Intensity (Custom only) ===
    positive Initial_intensity 0.8
    positive Intensity_step 0.2
    comment === Analysis ===
    natural N_analysis_frames 50
    natural N_mfcc_coeffs 12
    comment === Transform Params (Custom only) ===
    natural N_mut_segments 6
    positive Noise_level 0.02
    positive Tilt_scale 2.0
    positive Seg_emph_scale 1.5
    comment === Output ===
    boolean Show_visualization 1
endform

# ============================================================
# APPLY PRESETS
# ============================================================

# Transform switches (all on by default)
useGranular = 1
useSpectralMutation = 1
useTransientExagg = 1
useNoiseBursts = 1
usePitchJitter = 1

# Per-transform intensity multipliers
granularMult = 1.0
spectralMult = 1.0
transientMult = 1.0
noiseMult = 1.0
pitchMult = 1.0

# Granular character
grainSizeBase = 0.08
grainSizeShrink = 0.06
grainSizeFloor = 0.015
swapScale = 0.9
reverseScale = 0.8
gateScale = 0.5

if preset = 1
    # SUBTLE: spectral-only, no structural disruption
    presetName$ = "Subtle"
    targetDistance = 0.05
    tolerance = 0.02
    maxIterations = 8
    initialIntensity = 0.4
    intensityStep = 0.1
    nAnalysisFrames = 50
    nMfccCoeffs = 12
    nMutSegs = 4
    noiseLevel = 0.005
    tiltScale = 0.8
    segEmphScale = 0.5
    # Disable structural transforms
    useGranular = 0
    useNoiseBursts = 0
    usePitchJitter = 0
    # Gentle spectral + transient
    spectralMult = 0.6
    transientMult = 0.3

elsif preset = 2
    # STANDARD: balanced mix
    presetName$ = "Standard"
    targetDistance = 0.15
    tolerance = 0.04
    maxIterations = 15
    initialIntensity = 0.8
    intensityStep = 0.2
    nAnalysisFrames = 50
    nMfccCoeffs = 12
    nMutSegs = 6
    noiseLevel = 0.02
    tiltScale = 2.0
    segEmphScale = 1.5
    # Mild granular, moderate spectral
    granularMult = 0.5
    grainSizeBase = 0.12
    grainSizeShrink = 0.04
    grainSizeFloor = 0.04
    swapScale = 0.4
    reverseScale = 0.3
    gateScale = 0.15
    pitchMult = 0.5
    noiseMult = 0.5

elsif preset = 3
    # GRANULAR: structural fracture, minimal spectral
    presetName$ = "Granular"
    targetDistance = 0.20
    tolerance = 0.06
    maxIterations = 15
    initialIntensity = 1.0
    intensityStep = 0.25
    nAnalysisFrames = 50
    nMfccCoeffs = 12
    nMutSegs = 3
    noiseLevel = 0.005
    tiltScale = 0.5
    segEmphScale = 0.3
    # Heavy granular
    granularMult = 1.5
    grainSizeBase = 0.06
    grainSizeShrink = 0.04
    grainSizeFloor = 0.012
    swapScale = 1.0
    reverseScale = 1.0
    gateScale = 0.7
    # Minimal spectral
    useSpectralMutation = 0
    useTransientExagg = 0
    pitchMult = 0.3
    noiseMult = 0.3

elsif preset = 4
    # SPECTRAL: timbral destruction, temporal flow preserved
    presetName$ = "Spectral"
    targetDistance = 0.25
    tolerance = 0.05
    maxIterations = 15
    initialIntensity = 0.9
    intensityStep = 0.2
    nAnalysisFrames = 50
    nMfccCoeffs = 12
    nMutSegs = 10
    noiseLevel = 0.04
    tiltScale = 4.0
    segEmphScale = 2.5
    # No granular reorder
    useGranular = 0
    # Heavy spectral + noise + pitch
    spectralMult = 1.5
    transientMult = 1.0
    noiseMult = 2.0
    pitchMult = 1.2

elsif preset = 5
    # EXTREME: everything maxed
    presetName$ = "Extreme"
    targetDistance = 0.40
    tolerance = 0.08
    maxIterations = 20
    initialIntensity = 1.5
    intensityStep = 0.3
    nAnalysisFrames = 50
    nMfccCoeffs = 12
    nMutSegs = 8
    noiseLevel = 0.06
    tiltScale = 5.0
    segEmphScale = 3.0
    # All transforms cranked
    granularMult = 1.5
    grainSizeBase = 0.05
    grainSizeShrink = 0.04
    grainSizeFloor = 0.010
    swapScale = 1.0
    reverseScale = 1.0
    gateScale = 0.8
    spectralMult = 1.5
    transientMult = 1.5
    noiseMult = 2.0
    pitchMult = 1.5

else
    # CUSTOM: use form values directly
    presetName$ = "Custom"
    targetDistance = target_distance
    tolerance = tolerance
    maxIterations = max_iterations
    initialIntensity = initial_intensity
    intensityStep = intensity_step
    nAnalysisFrames = n_analysis_frames
    nMfccCoeffs = n_mfcc_coeffs
    nMutSegs = n_mut_segments
    noiseLevel = noise_level
    tiltScale = tilt_scale
    segEmphScale = seg_emph_scale
endif

# Fixed parameters
analysisWindowDur = 0.05
amDepthMax = 0.25
amFreqMin = 3
amFreqMax = 15

# Features per frame:
#   1-12: MFCC coefficients
#   13: harmonicity
#   14-17: sub-band energy (4 bands)
#   18: spectral centroid
#   19: spectral flux
nFeatPerFrame = 19
totalFeatures = nAnalysisFrames * nFeatPerFrame

# Preset label for reporting
if preset = 1
    presetName$ = "Subtle"
elsif preset = 2
    presetName$ = "Standard"
elsif preset = 3
    presetName$ = "Extreme"
else
    presetName$ = "Custom"
endif

# === Setup ===
selectObject: originalSound
totalDur = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels
nyquist = sampleRate / 2

# Sub-band boundaries
band1lo = 0
band1hi = 500
band2lo = 500
band2hi = 2000
band3lo = 2000
band3hi = 5000
band4lo = 5000
band4hi = nyquist - 10
if band4hi < band4lo + 100
    band4hi = band4lo + 100
endif

clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  MSE Feature-Constrained Variation v1.1"
writeInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Input: ", originalName$,
    ... " (", fixed$(totalDur, 2), " s, ", sampleRate, " Hz, ", numChannels, " ch)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Target MSE: ", fixed$(targetDistance, 3),
    ... " +/- ", fixed$(tolerance, 3)
appendInfoLine: "Max iterations: ", maxIterations
appendInfoLine: "Initial intensity: ", fixed$(initialIntensity, 3)
appendInfoLine: "Features: ", totalFeatures,
    ... " (", nAnalysisFrames, " frames x ", nFeatPerFrame, " dims)"
appendInfoLine: ""

# === Create mono base ===
selectObject: originalSound
if numChannels > 1
    monoBase = Convert to mono
else
    monoBase = Copy: "mono_base"
endif

# ============================================================
# STEP 1: Extract features from original (bag-of-frames)
# ============================================================
appendInfoLine: "[1/4] Extracting original features..."

# MFCC analysis
selectObject: monoBase
To MelSpectrogram: 0.025, 0.01, 24, 100, 5000
origMelSpec = selected("MelSpectrogram")
To MFCC: nMfccCoeffs
origMfcc = selected("MFCC")

selectObject: origMfcc
nMfccFramesOrig = Get number of frames

# Harmonicity analysis
selectObject: monoBase
To Harmonicity (cc): 0.01, 75, 0.1, 1.0
origHarm = selected("Harmonicity")

# Collect raw frame features into per-dimension accumulators
for d from 1 to nFeatPerFrame
    origDimSum_'d' = 0
    origDimSqSum_'d' = 0
endfor

prevTotalEnergy = 0

for af from 1 to nAnalysisFrames
    frameTime = totalDur * af / (nAnalysisFrames + 1)

    # MFCC
    mfccFrame = round(af / nAnalysisFrames * nMfccFramesOrig)
    if mfccFrame < 1
        mfccFrame = 1
    endif
    if mfccFrame > nMfccFramesOrig
        mfccFrame = nMfccFramesOrig
    endif

    for c from 1 to nMfccCoeffs
        selectObject: origMfcc
        val = Get value in frame: mfccFrame, c
        if val = undefined
            val = 0
        endif
        origDimSum_'c' = origDimSum_'c' + val
        origDimSqSum_'c' = origDimSqSum_'c' + val * val
    endfor

    # Harmonicity
    selectObject: origHarm
    hval = Get value at time: frameTime, "Cubic"
    if hval = undefined
        hval = 0
    endif
    origDimSum_13 = origDimSum_13 + hval
    origDimSqSum_13 = origDimSqSum_13 + hval * hval

    # Spectrum slice for sub-bands + centroid + flux
    segStart = frameTime - analysisWindowDur / 2
    segEnd = frameTime + analysisWindowDur / 2
    if segStart < 0
        segStart = 0
    endif
    if segEnd > totalDur
        segEnd = totalDur
    endif
    if segEnd - segStart < 0.01
        segEnd = segStart + 0.01
    endif

    selectObject: monoBase
    Extract part: segStart, segEnd, "Hanning", 1, "no"
    tempSeg = selected("Sound")
    To Spectrum: "yes"
    tempSpec = selected("Spectrum")

    e1 = Get band energy: band1lo, band1hi
    e2 = Get band energy: band2lo, band2hi
    e3 = Get band energy: band3lo, band3hi
    e4 = Get band energy: band4lo, band4hi

    origDimSum_14 = origDimSum_14 + e1
    origDimSqSum_14 = origDimSqSum_14 + e1 * e1
    origDimSum_15 = origDimSum_15 + e2
    origDimSqSum_15 = origDimSqSum_15 + e2 * e2
    origDimSum_16 = origDimSum_16 + e3
    origDimSqSum_16 = origDimSqSum_16 + e3 * e3
    origDimSum_17 = origDimSum_17 + e4
    origDimSqSum_17 = origDimSqSum_17 + e4 * e4

    totalE = e1 + e2 + e3 + e4 + 1e-10
    band4center = (band4lo + band4hi) / 2
    centroid = (250 * e1 + 1250 * e2 + 3500 * e3 + band4center * e4) / totalE
    origDimSum_18 = origDimSum_18 + centroid
    origDimSqSum_18 = origDimSqSum_18 + centroid * centroid

    if af > 1
        flux = totalE - prevTotalEnergy
        if flux < 0
            flux = -flux
        endif
    else
        flux = 0
    endif
    origDimSum_19 = origDimSum_19 + flux
    origDimSqSum_19 = origDimSqSum_19 + flux * flux
    prevTotalEnergy = totalE

    removeObject: tempSeg, tempSpec
endfor

removeObject: origMelSpec, origMfcc, origHarm

# Compute per-dimension mean and variance for original
for d from 1 to nFeatPerFrame
    origMean_'d' = origDimSum_'d' / nAnalysisFrames
    origVar_'d' = origDimSqSum_'d' / nAnalysisFrames - origMean_'d' * origMean_'d'
    if origVar_'d' < 0
        origVar_'d' = 0
    endif
endfor

totalStats = nFeatPerFrame * 2

appendInfoLine: "  Bag-of-frames statistics: ", totalStats, " values"
appendInfoLine: "  (", nFeatPerFrame, " dims x {mean, var} over ", nAnalysisFrames, " frames)"
appendInfoLine: ""

# ============================================================
# STEP 2: Iterative transformation loop
# ============================================================
appendInfoLine: "[2/4] Iterative transformation..."

currentIntensity = initialIntensity
bestMse = -1
bestSound = 0
converged = 0
nIterationsRun = 0

for iter from 1 to maxIterations
    if converged = 0
        nIterationsRun = iter
        appendInfoLine: "  --- Iteration ", iter, " (intensity: ", fixed$(currentIntensity, 3), ") ---"

        # =============================================
        # T1: Micro-segmentation with reorder + reverse
        # =============================================
        if useGranular
            gi_intensity = currentIntensity * granularMult
            
            grainBase = grainSizeBase - gi_intensity * grainSizeShrink
            if grainBase < grainSizeFloor
                grainBase = grainSizeFloor
            endif
            grainDur = grainBase
            fadeDur = grainDur * 0.08
            if fadeDur < 0.002
                fadeDur = 0.002
            endif
            
            selectObject: monoBase
            nGrains = floor(totalDur / grainDur)
            if nGrains < 3
                nGrains = 3
            endif
            
            for gi from 1 to nGrains
                grainStart_'gi' = (gi - 1) * grainDur
                grainEnd_'gi' = gi * grainDur
                if grainEnd_'gi' > totalDur
                    grainEnd_'gi' = totalDur
                endif
            endfor
            
            swapProb = gi_intensity * swapScale
            reverseProb = gi_intensity * reverseScale
            gateProb = gi_intensity * gateScale
            
            for gi from 1 to nGrains
                grainOrder_'gi' = gi
                grainReverse_'gi' = 0
                grainGate_'gi' = 0
            endfor
            
            nSwaps = floor(nGrains * swapProb)
            for sw from 1 to nSwaps
                idxA = randomInteger(1, nGrains)
                idxB = randomInteger(1, nGrains)
                tempOrd = grainOrder_'idxA'
                grainOrder_'idxA' = grainOrder_'idxB'
                grainOrder_'idxB' = tempOrd
            endfor
            
            nReversed = 0
            nGated = 0
            for gi from 1 to nGrains
                r = randomUniform(0, 1)
                if r < reverseProb
                    grainReverse_'gi' = 1
                    nReversed = nReversed + 1
                endif
                r2 = randomUniform(0, 1)
                if r2 < gateProb
                    grainGate_'gi' = 1
                    nGated = nGated + 1
                endif
            endfor
            
            assembledSound = 0
            
            for gi from 1 to nGrains
                srcIdx = grainOrder_'gi'
                gStart = grainStart_'srcIdx'
                gEnd = grainEnd_'srcIdx'
                gDur = gEnd - gStart
                
                if gDur < 0.005
                    gDur = 0.005
                    gEnd = gStart + gDur
                    if gEnd > totalDur
                        gEnd = totalDur
                        gStart = totalDur - gDur
                        if gStart < 0
                            gStart = 0
                        endif
                    endif
                endif
                
                selectObject: monoBase
                Extract part: gStart, gEnd, "rectangular", 1, "no"
                grainSnd = selected("Sound")
                
                if grainReverse_'gi' = 1
                    selectObject: grainSnd
                    Reverse
                endif
                
                if grainGate_'gi' = 1
                    selectObject: grainSnd
                    Formula: "self * 0"
                endif
                
                selectObject: grainSnd
                gSndDur = Get total duration
                localFade = fadeDur
                if localFade > gSndDur / 3
                    localFade = gSndDur / 3
                endif
                fadeStr$ = fixed$(localFade, 8)
                Formula: "if x - xmin < " + fadeStr$
                    ... + " then self * ((x - xmin) / " + fadeStr$
                    ... + ") else self fi"
                Formula: "if xmax - x < " + fadeStr$
                    ... + " then self * ((xmax - x) / " + fadeStr$
                    ... + ") else self fi"
                
                if gi = 1
                    assembledSound = grainSnd
                else
                    selectObject: assembledSound, grainSnd
                    Concatenate
                    newAssembled = selected("Sound")
                    removeObject: assembledSound, grainSnd
                    assembledSound = newAssembled
                endif
            endfor
            
            workingSound = assembledSound
            
            appendInfoLine: "    T1 Granular: ", nGrains, " grains (",
                ... fixed$(grainDur * 1000, 0), "ms) | swaps: ", nSwaps,
                ... " | rev: ", nReversed, " | gate: ", nGated
        else
            # No granular — start from monoBase copy
            selectObject: monoBase
            workingSound = Copy: "working"
            appendInfoLine: "    T1 Granular: OFF"
        endif
        
        # =============================================
        # T2: Per-segment spectral mutation
        # =============================================
        if useSpectralMutation
            sm_intensity = currentIntensity * spectralMult
            
            selectObject: workingSound
            workDur = Get total duration
            mutSegDur = workDur / nMutSegs
            mutFade = 0.003
            
            mutAssembled = 0
            
            for ms from 1 to nMutSegs
                msStart = (ms - 1) * mutSegDur
                msEnd = ms * mutSegDur
                if ms = nMutSegs
                    msEnd = workDur
                endif
                
                selectObject: workingSound
                Extract part: msStart, msEnd, "rectangular", 1, "no"
                msSnd = selected("Sound")
                
                To Spectrum: "yes"
                msSpec = selected("Spectrum")
                
                mutTilt = sm_intensity * tiltScale * randomUniform(-1, 1)
                mutTiltStr$ = fixed$(mutTilt, 8)
                
                mutPhase = randomUniform(0, 6.2832)
                mutFreq = randomUniform(2, 12)
                mutAmp = sm_intensity * segEmphScale
                mutPhStr$ = fixed$(mutPhase, 8)
                mutFrStr$ = fixed$(mutFreq, 8)
                mutAmpStr$ = fixed$(mutAmp, 8)
                
                selectObject: msSpec
                Formula: "self * exp(" + mutTiltStr$
                    ... + " * (col / ncol - 0.5))"
                    ... + " * (1 + " + mutAmpStr$
                    ... + " * sin(" + mutFrStr$
                    ... + " * 3.14159 * col / ncol + " + mutPhStr$ + "))"
                
                To Sound
                msResult = selected("Sound")
                Override sampling frequency: sampleRate
                removeObject: msSnd, msSpec
                
                selectObject: msResult
                msResDur = Get total duration
                localMutFade = mutFade
                if localMutFade > msResDur / 3
                    localMutFade = msResDur / 3
                endif
                mutFadeStr$ = fixed$(localMutFade, 8)
                Formula: "if x - xmin < " + mutFadeStr$
                    ... + " then self * ((x - xmin) / " + mutFadeStr$
                    ... + ") else self fi"
                Formula: "if xmax - x < " + mutFadeStr$
                    ... + " then self * ((xmax - x) / " + mutFadeStr$
                    ... + ") else self fi"
                
                if ms = 1
                    mutAssembled = msResult
                else
                    selectObject: mutAssembled, msResult
                    Concatenate
                    newMut = selected("Sound")
                    removeObject: mutAssembled, msResult
                    mutAssembled = newMut
                endif
            endfor
            
            removeObject: workingSound
            workingSound = mutAssembled
            
            appendInfoLine: "    T2 Spectral mutation: ", nMutSegs,
                ... " segs (x", fixed$(spectralMult, 1), ")"
        else
            appendInfoLine: "    T2 Spectral mutation: OFF"
        endif
        
        # =============================================
        # T3: Transient exaggeration / suppression
        # =============================================
        if useTransientExagg
            te_intensity = currentIntensity * transientMult
            
            selectObject: workingSound
            workCopy = Copy: "env_work"
            
            selectObject: workCopy
            To Intensity: 100, 0.005, "yes"
            workIntensity = selected("Intensity")
            
            selectObject: workIntensity
            meanInt = Get mean: 0, 0, "energy"
            
            exaggeration = te_intensity * 0.5
            
            selectObject: workingSound
            workDur2 = Get total duration
            
            intId = workIntensity
            nIntFrames = floor(workDur2 / 0.01)
            if nIntFrames < 1
                nIntFrames = 1
            endif
            
            for ef from 1 to nIntFrames
                efTime = ef * 0.01
                efStart = efTime - 0.005
                efEnd = efTime + 0.005
                if efStart < 0
                    efStart = 0
                endif
                if efEnd > workDur2
                    efEnd = workDur2
                endif
                
                selectObject: workIntensity
                localInt = Get value at time: efTime, "Cubic"
                if localInt = undefined
                    localInt = meanInt
                endif
                
                factor = 1 + exaggeration * (localInt - meanInt) / 40
                if factor < 0.1
                    factor = 0.1
                endif
                if factor > 3
                    factor = 3
                endif
                
                factorStr$ = fixed$(factor, 8)
                selectObject: workingSound
                Formula (part): efStart, efEnd, 1, 1,
                    ... "self * " + factorStr$
            endfor
            
            removeObject: workCopy, workIntensity
            
            appendInfoLine: "    T3 Transient exagg: ", fixed$(exaggeration, 3),
                ... " (x", fixed$(transientMult, 1), ")"
        else
            appendInfoLine: "    T3 Transient exagg: OFF"
        endif
        
        # =============================================
        # T4: Band-limited noise bursts
        # =============================================
        if useNoiseBursts
            nb_intensity = currentIntensity * noiseMult
            noiseAmt = nb_intensity * noiseLevel * 3
            nBursts = floor(nb_intensity * 8) + 2
            burstDur = 0.04
            
            selectObject: workingSound
            workDur3 = Get total duration
            
            for nb from 1 to nBursts
                burstTime = randomUniform(0, workDur3 - burstDur)
                burstFreq = randomUniform(200, 6000)
                burstBW = randomUniform(200, 2000)
                burstLo = burstFreq - burstBW / 2
                burstHi = burstFreq + burstBW / 2
                if burstLo < 50
                    burstLo = 50
                endif
                if burstHi > nyquist - 100
                    burstHi = nyquist - 100
                endif
                if burstLo >= burstHi
                    burstLo = 50
                    burstHi = 4000
                endif
                
                noiseAmtStr$ = fixed$(noiseAmt, 8)
                Create Sound from formula: "burst", 1, 0, burstDur, sampleRate,
                    ... "randomGauss(0, " + noiseAmtStr$ + ")"
                burstSnd = selected("Sound")
                Filter (pass Hann band): burstLo, burstHi, 100
                filtBurst = selected("Sound")
                removeObject: burstSnd
                
                selectObject: filtBurst
                burstFade = 0.005
                burstFadeStr$ = fixed$(burstFade, 8)
                Formula: "if x - xmin < " + burstFadeStr$
                    ... + " then self * ((x - xmin) / " + burstFadeStr$
                    ... + ") else self fi"
                Formula: "if xmax - x < " + burstFadeStr$
                    ... + " then self * ((xmax - x) / " + burstFadeStr$
                    ... + ") else self fi"
                
                burstId = filtBurst
                burstTimeStr$ = fixed$(burstTime, 8)
                burstEndStr$ = fixed$(burstTime + burstDur, 8)
                
                selectObject: workingSound
                Formula: "if x >= " + burstTimeStr$
                    ... + " and x < " + burstEndStr$
                    ... + " then self + object[burstId, x - " + burstTimeStr$ + " + object[burstId].xmin]"
                    ... + " else self fi"
                
                removeObject: filtBurst
            endfor
            
            appendInfoLine: "    T4 Noise bursts: ", nBursts,
                ... " x ", fixed$(burstDur * 1000, 0), "ms",
                ... " (x", fixed$(noiseMult, 1), ")"
        else
            appendInfoLine: "    T4 Noise bursts: OFF"
        endif
        
        # =============================================
        # T5: Pitch perturbation (backward iteration)
        # =============================================
        if usePitchJitter
            selectObject: workingSound
            To Manipulation: 0.01, 75, 600
            workManip = selected("Manipulation")
            
            Extract pitch tier
            workPitchTier = selected("PitchTier")
            
            selectObject: workPitchTier
            nPitchPoints = Get number of points
            
            pitchJitter = currentIntensity * 0.35 * pitchMult
            
            pp = nPitchPoints
            while pp >= 1
                selectObject: workPitchTier
                ppTime = Get time from index: pp
                ppVal = Get value at index: pp
                if ppVal > 0
                    ppShift = ppVal * pitchJitter * randomUniform(-1, 1)
                    newVal = ppVal + ppShift
                    if newVal < 50
                        newVal = 50
                    endif
                    if newVal > 800
                        newVal = 800
                    endif
                    Remove point: pp
                    Add point: ppTime, newVal
                endif
                pp = pp - 1
            endwhile
            
            selectObject: workManip
            plusObject: workPitchTier
            Replace pitch tier
            
            selectObject: workManip
            Get resynthesis (overlap-add)
            pitchResult = selected("Sound")
            
            removeObject: workManip, workPitchTier, workingSound
            workingSound = pitchResult
            
            appendInfoLine: "    T5 Pitch jitter: ", fixed$(pitchJitter * 100, 1),
                ... "% (x", fixed$(pitchMult, 1), ")"
        else
            appendInfoLine: "    T5 Pitch jitter: OFF"
        endif

        # =============================================
        # FEATURE EXTRACTION from transformed
        # =============================================
        selectObject: workingSound
        To MelSpectrogram: 0.025, 0.01, 24, 100, 5000
        transMelSpec = selected("MelSpectrogram")
        To MFCC: nMfccCoeffs
        transMfcc = selected("MFCC")

        selectObject: transMfcc
        transNframes = Get number of frames

        selectObject: workingSound
        To Harmonicity (cc): 0.01, 75, 0.1, 1.0
        transHarm = selected("Harmonicity")

        selectObject: workingSound
        transDur = Get total duration

        for d from 1 to nFeatPerFrame
            transDimSum_'d' = 0
            transDimSqSum_'d' = 0
        endfor

        prevTransEnergy = 0

        for af from 1 to nAnalysisFrames
            frameTime = transDur * af / (nAnalysisFrames + 1)

            mfccFrame = round(af / nAnalysisFrames * transNframes)
            if mfccFrame < 1
                mfccFrame = 1
            endif
            if mfccFrame > transNframes
                mfccFrame = transNframes
            endif

            for c from 1 to nMfccCoeffs
                selectObject: transMfcc
                val = Get value in frame: mfccFrame, c
                if val = undefined
                    val = 0
                endif
                transDimSum_'c' = transDimSum_'c' + val
                transDimSqSum_'c' = transDimSqSum_'c' + val * val
            endfor

            selectObject: transHarm
            hval = Get value at time: frameTime, "Cubic"
            if hval = undefined
                hval = 0
            endif
            transDimSum_13 = transDimSum_13 + hval
            transDimSqSum_13 = transDimSqSum_13 + hval * hval

            segStart = frameTime - analysisWindowDur / 2
            segEnd = frameTime + analysisWindowDur / 2
            if segStart < 0
                segStart = 0
            endif
            if segEnd > transDur
                segEnd = transDur
            endif
            if segEnd - segStart < 0.01
                segEnd = segStart + 0.01
            endif

            selectObject: workingSound
            Extract part: segStart, segEnd, "Hanning", 1, "no"
            tempSeg = selected("Sound")
            To Spectrum: "yes"
            tempSpec = selected("Spectrum")

            e1 = Get band energy: band1lo, band1hi
            e2 = Get band energy: band2lo, band2hi
            e3 = Get band energy: band3lo, band3hi
            e4 = Get band energy: band4lo, band4hi

            transDimSum_14 = transDimSum_14 + e1
            transDimSqSum_14 = transDimSqSum_14 + e1 * e1
            transDimSum_15 = transDimSum_15 + e2
            transDimSqSum_15 = transDimSqSum_15 + e2 * e2
            transDimSum_16 = transDimSum_16 + e3
            transDimSqSum_16 = transDimSqSum_16 + e3 * e3
            transDimSum_17 = transDimSum_17 + e4
            transDimSqSum_17 = transDimSqSum_17 + e4 * e4

            totalE = e1 + e2 + e3 + e4 + 1e-10
            band4center = (band4lo + band4hi) / 2
            centroid = (250 * e1 + 1250 * e2 + 3500 * e3 + band4center * e4) / totalE
            transDimSum_18 = transDimSum_18 + centroid
            transDimSqSum_18 = transDimSqSum_18 + centroid * centroid

            if af > 1
                flux = totalE - prevTransEnergy
                if flux < 0
                    flux = -flux
                endif
            else
                flux = 0
            endif
            transDimSum_19 = transDimSum_19 + flux
            transDimSqSum_19 = transDimSqSum_19 + flux * flux
            prevTransEnergy = totalE

            removeObject: tempSeg, tempSpec
        endfor

        removeObject: transMelSpec, transMfcc, transHarm

        # =============================================
        # COMPUTE MSE
        # =============================================
        mseSum = 0
        for d from 1 to nFeatPerFrame
            transMean = transDimSum_'d' / nAnalysisFrames
            transVar = transDimSqSum_'d' / nAnalysisFrames - transMean * transMean
            if transVar < 0
                transVar = 0
            endif

            diffMean = origMean_'d' - transMean
            mseSum = mseSum + diffMean * diffMean

            diffVar = origVar_'d' - transVar
            mseSum = mseSum + diffVar * diffVar
        endfor
        mse = mseSum / totalStats
        mseHistory_'iter' = mse

        appendInfoLine: "    MSE: ", fixed$(mse, 4),
            ... " (target: ", fixed$(targetDistance - tolerance, 3),
            ... " - ", fixed$(targetDistance + tolerance, 3), ")"

        # =============================================
        # CONVERGENCE CHECK
        # =============================================
        loBound = targetDistance - tolerance
        hiBound = targetDistance + tolerance

        if mse >= loBound and mse <= hiBound
            converged = 1
            if bestSound > 0
                removeObject: bestSound
            endif
            bestSound = workingSound
            bestMse = mse
            appendInfoLine: "    ** Converged! **"
        else
            dist = mse - targetDistance
            if dist < 0
                dist = -dist
            endif

            if bestSound = 0
                bestSound = workingSound
                bestMse = mse
            else
                bestDist = bestMse - targetDistance
                if bestDist < 0
                    bestDist = -bestDist
                endif
                if dist < bestDist
                    removeObject: bestSound
                    bestSound = workingSound
                    bestMse = mse
                else
                    removeObject: workingSound
                endif
            endif

            if mse < loBound
                currentIntensity = currentIntensity + intensityStep
                appendInfoLine: "    -> Too similar, intensity +",
                    ... fixed$(intensityStep, 2)
            else
                halfStep = intensityStep * 0.5
                currentIntensity = currentIntensity - halfStep
                if currentIntensity < 0.05
                    currentIntensity = 0.05
                endif
                appendInfoLine: "    -> Too different, intensity -",
                    ... fixed$(halfStep, 2)
            endif
        endif
    endif
endfor

if converged = 0
    appendInfoLine: ""
    appendInfoLine: "  Did not converge in ", maxIterations,
        ... " iterations. Using best result."
endif

appendInfoLine: ""

# ============================================================
# STEP 3: Finalize
# ============================================================
appendInfoLine: "[3/4] Finalizing..."

selectObject: bestSound
Scale peak: 0.95
Rename: originalName$ + "_experimental"
finalOutput = selected("Sound")
finalDur = Get total duration

removeObject: monoBase

appendInfoLine: "  Output: ", originalName$, "_experimental"
appendInfoLine: "  Duration: ", fixed$(finalDur, 2), " s"
appendInfoLine: "  Final MSE: ", fixed$(bestMse, 4)
appendInfoLine: ""

# ============================================================
# STEP 4: Visualization
# ============================================================
appendInfoLine: "[4/4] Visualization..."

if show_visualization = 1

    # Re-extract transformed stats from final output for comparison
    selectObject: finalOutput
    finalCh = Get number of channels
    if finalCh > 1
        finalVizMono = Convert to mono
    else
        finalVizMono = Copy: "final_viz"
    endif
    
    selectObject: finalVizMono
    To MelSpectrogram: 0.025, 0.01, 24, 100, 5000
    vizMelSpec = selected("MelSpectrogram")
    To MFCC: nMfccCoeffs
    vizMfcc = selected("MFCC")
    selectObject: vizMfcc
    vizNframes = Get number of frames
    
    selectObject: finalVizMono
    To Harmonicity (cc): 0.01, 75, 0.1, 1.0
    vizHarm = selected("Harmonicity")
    
    selectObject: finalVizMono
    vizDur = Get total duration
    
    for d from 1 to nFeatPerFrame
        vizDimSum_'d' = 0
    endfor
    
    vizPrevEnergy = 0
    
    for af from 1 to nAnalysisFrames
        frameTime = vizDur * af / (nAnalysisFrames + 1)
        
        mfccFrame = round(af / nAnalysisFrames * vizNframes)
        if mfccFrame < 1
            mfccFrame = 1
        endif
        if mfccFrame > vizNframes
            mfccFrame = vizNframes
        endif
        
        for c from 1 to nMfccCoeffs
            selectObject: vizMfcc
            val = Get value in frame: mfccFrame, c
            if val = undefined
                val = 0
            endif
            vizDimSum_'c' = vizDimSum_'c' + val
        endfor
        
        selectObject: vizHarm
        hval = Get value at time: frameTime, "Cubic"
        if hval = undefined
            hval = 0
        endif
        vizDimSum_13 = vizDimSum_13 + hval
        
        segStart = frameTime - analysisWindowDur / 2
        segEnd = frameTime + analysisWindowDur / 2
        if segStart < 0
            segStart = 0
        endif
        if segEnd > vizDur
            segEnd = vizDur
        endif
        if segEnd - segStart < 0.01
            segEnd = segStart + 0.01
        endif
        
        selectObject: finalVizMono
        Extract part: segStart, segEnd, "Hanning", 1, "no"
        vizSeg = selected("Sound")
        To Spectrum: "yes"
        vizSpec = selected("Spectrum")
        
        e1 = Get band energy: band1lo, band1hi
        e2 = Get band energy: band2lo, band2hi
        e3 = Get band energy: band3lo, band3hi
        e4 = Get band energy: band4lo, band4hi
        
        vizDimSum_14 = vizDimSum_14 + e1
        vizDimSum_15 = vizDimSum_15 + e2
        vizDimSum_16 = vizDimSum_16 + e3
        vizDimSum_17 = vizDimSum_17 + e4
        
        totalE = e1 + e2 + e3 + e4 + 1e-10
        band4center = (band4lo + band4hi) / 2
        centroid = (250 * e1 + 1250 * e2 + 3500 * e3 + band4center * e4) / totalE
        vizDimSum_18 = vizDimSum_18 + centroid
        
        if af > 1
            flux = totalE - vizPrevEnergy
            if flux < 0
                flux = -flux
            endif
        else
            flux = 0
        endif
        vizDimSum_19 = vizDimSum_19 + flux
        vizPrevEnergy = totalE
        
        removeObject: vizSeg, vizSpec
    endfor
    
    for d from 1 to nFeatPerFrame
        vizMean_'d' = vizDimSum_'d' / nAnalysisFrames
    endfor
    
    removeObject: vizMelSpec, vizMfcc, vizHarm, finalVizMono
    
    # =============================================
    # DRAW
    # =============================================
    Erase all
    
    # === TITLE ===
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half",
        ... "##MSE Feature-Constrained Variation v1.1##"
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -0.6, "half",
        ... originalName$ + " | " + presetName$
        ... + " | Target: " + fixed$(targetDistance, 3)
        ... + " | Final MSE: " + fixed$(bestMse, 4)
    
    # === ORIGINAL WAVEFORM ===
    Select outer viewport: 0, 4, 0.6, 1.5
    Select inner viewport: 0.6, 3.7, 0.7, 1.4
    selectObject: originalSound
    Colour: "{0.3, 0.5, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Amp"
    Text top: "no", "Original: " + originalName$
    
    # === OUTPUT WAVEFORM ===
    Select outer viewport: 4, 8, 0.6, 1.5
    Select inner viewport: 4.4, 7.7, 0.7, 1.4
    selectObject: finalOutput
    Colour: "{0.4, 0.6, 0.4}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Amp"
    Text top: "no", "Experimental"
    
    # === ORIGINAL SPECTROGRAM ===
    Select outer viewport: 0, 4, 1.6, 2.9
    Select inner viewport: 0.6, 3.7, 1.7, 2.8
    selectObject: originalSound
    if numChannels > 1
        origViz = Convert to mono
    else
        origViz = Copy: "orig_viz"
    endif
    selectObject: origViz
    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    specOrig = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text top: "no", "Original Spectrogram"
    removeObject: specOrig, origViz
    
    # === OUTPUT SPECTROGRAM ===
    Select outer viewport: 4, 8, 1.6, 2.9
    Select inner viewport: 4.4, 7.7, 1.7, 2.8
    selectObject: finalOutput
    if finalCh > 1
        outViz = Convert to mono
    else
        outViz = Copy: "out_viz"
    endif
    selectObject: outViz
    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    specOut = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text top: "no", "Experimental Spectrogram"
    removeObject: specOut, outViz
    
    # === MSE CONVERGENCE CURVE ===
    Select outer viewport: 0, 4, 3.0, 4.5
    Select inner viewport: 0.6, 3.7, 3.1, 4.4
    
    if nIterationsRun > 0
        minMse = 9999
        maxMse = 0
        for ci from 1 to nIterationsRun
            val = mseHistory_'ci'
            if val < minMse
                minMse = val
            endif
            if val > maxMse
                maxMse = val
            endif
        endfor
        
        if loBound < minMse
            minMse = loBound
        endif
        if hiBound > maxMse
            maxMse = hiBound
        endif
        
        mseRange = maxMse - minMse
        if mseRange < 0.01
            mseRange = 0.01
        endif
        plotLo = minMse - mseRange * 0.15
        plotHi = maxMse + mseRange * 0.15
        
        Axes: 0.5, nIterationsRun + 0.5, plotLo, plotHi
        Paint rectangle: "{0.97, 0.97, 0.97}",
            ... 0.5, nIterationsRun + 0.5, plotLo, plotHi
        
        # Target band
        Paint rectangle: "{0.85, 0.95, 0.85}",
            ... 0.5, nIterationsRun + 0.5, loBound, hiBound
        
        # Target + bounds
        Colour: "{0.6, 0.8, 0.6}"
        Dotted line
        Draw line: 0.5, targetDistance, nIterationsRun + 0.5, targetDistance
        Solid line
        
        # MSE curve
        Colour: "{0.8, 0.3, 0.3}"
        Line width: 2
        for ci from 1 to nIterationsRun
            val = mseHistory_'ci'
            if ci > 1
                ciPrev = ci - 1
                prev = mseHistory_'ciPrev'
                Draw line: ciPrev, prev, ci, val
            endif
            Paint circle (mm): "{0.8, 0.3, 0.3}", ci, val, 1.2
        endfor
        Line width: 1
    else
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
    endif
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "MSE"
    Text bottom: "yes", "Iteration"
    Text top: "no", "MSE Convergence"
    
    # === PER-DIMENSION COMPARISON (orig vs transformed means) ===
    Select outer viewport: 4, 8, 3.0, 4.5
    Select inner viewport: 4.4, 7.7, 3.1, 4.4
    
    # Compute per-dim absolute difference for bar height
    maxDimDiff = 0
    for d from 1 to nFeatPerFrame
        dimDiff_'d' = origMean_'d' - vizMean_'d'
        if dimDiff_'d' < 0
            dimDiff_'d' = -dimDiff_'d'
        endif
        if dimDiff_'d' > maxDimDiff
            maxDimDiff = dimDiff_'d'
        endif
    endfor
    if maxDimDiff < 0.01
        maxDimDiff = 0.01
    endif
    
    Axes: 0.5, nFeatPerFrame + 0.5, 0, maxDimDiff * 1.15
    Paint rectangle: "{0.97, 0.97, 0.97}",
        ... 0.5, nFeatPerFrame + 0.5, 0, maxDimDiff * 1.15
    
    for d from 1 to nFeatPerFrame
        # Colour by feature type
        if d <= 12
            barColor$ = "{0.3, 0.5, 0.8}"
        elsif d = 13
            barColor$ = "{0.6, 0.3, 0.7}"
        elsif d <= 17
            barColor$ = "{0.9, 0.6, 0.2}"
        elsif d = 18
            barColor$ = "{0.2, 0.7, 0.6}"
        else
            barColor$ = "{0.8, 0.3, 0.3}"
        endif
        Paint rectangle: barColor$, d - 0.4, d + 0.4, 0, dimDiff_'d'
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "|Diff|"
    Text bottom: "yes", "1-12:MFCC  13:Harm  14-17:Band  18:Cent  19:Flux"
    Text top: "no", "Per-Dimension Mean Difference"
    
    # === STATS PANEL ===
    Select outer viewport: 0, 8, 4.6, 5.5
    Select inner viewport: 0.6, 7.7, 4.7, 5.45
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.88, "half", "##Variation Summary##"
    Font size: 6
    Colour: "{0.3, 0.3, 0.35}"
    
    if converged
        convergeTxt$ = "YES (iter " + string$(nIterationsRun) + ")"
    else
        convergeTxt$ = "NO (best of " + string$(nIterationsRun) + ")"
    endif
    
    Text: 0.02, "left", 0.68, "half",
        ... "Input: " + originalName$ + " | "
        ... + fixed$(totalDur, 2) + "s | "
        ... + string$(sampleRate) + " Hz | Preset: " + presetName$
    Text: 0.02, "left", 0.48, "half",
        ... "MSE: " + fixed$(bestMse, 4)
        ... + " | Target: " + fixed$(targetDistance, 3)
        ... + " +/- " + fixed$(tolerance, 3)
        ... + " | Converged: " + convergeTxt$
    Text: 0.02, "left", 0.28, "half",
        ... "Tilt: " + fixed$(tiltScale, 1)
        ... + " | SegEmph: " + fixed$(segEmphScale, 1)
        ... + " | Noise: " + fixed$(noiseLevel, 3)
        ... + " | AM: " + fixed$(amDepthMax, 2)
        ... + " | Intensity: " + fixed$(currentIntensity, 3)
    Text: 0.02, "left", 0.08, "half",
        ... "Centroid: " + fixed$(origMean_18, 0)
        ... + " -> " + fixed$(vizMean_18, 0) + " Hz"
        ... + " | Harm: " + fixed$(origMean_13, 1)
        ... + " -> " + fixed$(vizMean_13, 1) + " dB"
        ... + " | Flux: " + fixed$(origMean_19, 3)
        ... + " -> " + fixed$(vizMean_19, 3)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    # === LEGEND ===
    Select outer viewport: 0, 8, 5.55, 5.85
    Axes: 0, 1, 0, 1
    Font size: 6
    
    Colour: "{0.3, 0.5, 0.8}"
    Draw line: 0.02, 0.5, 0.06, 0.5
    Colour: "Black"
    Text: 0.07, "left", 0.5, "half", "Original/MFCC"
    
    Colour: "{0.4, 0.6, 0.4}"
    Draw line: 0.20, 0.5, 0.24, 0.5
    Colour: "Black"
    Text: 0.25, "left", 0.5, "half", "Experimental"
    
    Colour: "{0.8, 0.3, 0.3}"
    Line width: 2
    Draw line: 0.38, 0.5, 0.42, 0.5
    Line width: 1
    Colour: "Black"
    Text: 0.43, "left", 0.5, "half", "MSE/Flux"
    
    Colour: "{0.6, 0.3, 0.7}"
    Draw line: 0.54, 0.5, 0.58, 0.5
    Colour: "Black"
    Text: 0.59, "left", 0.5, "half", "Harm"
    
    Colour: "{0.9, 0.6, 0.2}"
    Draw line: 0.67, 0.5, 0.71, 0.5
    Colour: "Black"
    Text: 0.72, "left", 0.5, "half", "Bands"
    
    Colour: "{0.2, 0.7, 0.6}"
    Draw line: 0.80, 0.5, 0.84, 0.5
    Colour: "Black"
    Text: 0.85, "left", 0.5, "half", "Centroid"
    
    Paint rectangle: "{0.85, 0.95, 0.85}", 0.93, 0.96, 0.3, 0.7
    Text: 0.97, "left", 0.5, "half", "Target"
    
    Font size: 10
    Colour: "Black"

else
    appendInfoLine: "  (Visualization skipped)"
endif
# ============================================================
# Final
# ============================================================
selectObject: finalOutput
Play

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Final MSE: ", fixed$(bestMse, 4)
appendInfoLine: "Converged: ", converged, " (in ", nIterationsRun, " iterations)"
appendInfoLine: "Output: ", originalName$, "_experimental"
