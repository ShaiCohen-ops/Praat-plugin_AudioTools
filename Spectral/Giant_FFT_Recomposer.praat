# ============================================================
# Praat AudioTools - GiantFFTRecomposer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3.0 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Giant FFT Recomposer treats the complete duration of a selected
#   Sound as one global complex Spectrum rather than an STFT sequence.
#   It recomposes the relationship between magnitude, phase and
#   frequency through artistic presets such as phase dissolution,
#   spectral sparsification, drift, reflection, folding and magnitude
#   mutation. Processing is implemented entirely in native Praat.
#
# Changelog v0.3.0 (2026):
#   - PERFORMANCE. Magnitude and phase are precomputed once per channel into
#     1 x nBins Matrices, and each mode builds its new phase (and new
#     magnitude where it changes) as another Matrix. The Spectrum formula then
#     reads two cells and calls one cos or sin. Previously the same
#     arctan2 (im, re) was recomputed up to twelve times inside one formula
#     that ran once per row per bin: Phase Crystal and Phase Gravity 12
#     arctan2 per bin, Giant Collapse 12 arctan2 + 6 sqrt, Phase Mist 8. On
#     6.5 s of stereo at 44.1 kHz with the fast FFT that is 262145 bins x 2
#     rows x 2 channels, so Phase Crystal alone reached roughly 25 million
#     transcendental calls. Now 1 arctan2 per bin, evaluated once rather than
#     twice. The transformation maths is unchanged.
#   - VISUALIZATION CORRECTNESS. The global spectrum panel decimated by
#     point-sampling one bin in every stepBins - with nBins = 262145 that is
#     one bin in every 404. On a sparse spectrum, which is exactly what
#     Spectral Skeleton, Constellation and Giant Collapse produce, the panel
#     showed almost nothing: on a test spectrum with 3000 retained peaks it
#     sampled 8 of them (0.3%) and drew a flat line on the -80 dB floor while
#     the real spectrum was full of peaks at 0 dB. Even on a dense spectrum
#     the point-sampled median ran 15 dB low. Each plotted point is now the
#     MAXIMUM over its block of bins.
#   - New option Decorrelate_channels (default off, i.e. previous behaviour).
#     The shared random-phase field pushes both stereo channels toward the
#     same phase, so at full depth they differ only in magnitude and the image
#     NARROWS. Measured on decorrelated stereo material at depth 1.0:
#         source              L/R corr 0.710   side/mid  -7.7 dB
#         shared phase field  L/R corr 0.888   side/mid -12.3 dB
#         per-channel fields  L/R corr 0.003   side/mid   0.0 dB
#   - Version string is now a single variable. The header said 0.2.4 while the
#     Info window and the plot title both still said 0.2.3.
#
# Changelog v0.2.4 (2026):
#   - Renamed the FFT-bin count variable from nx to nBins because nx is
#     also an intrinsic Matrix attribute inside Praat Formula contexts.
#   - Hardened neighbour-based formulas at the first and last spectral
#     bins to avoid out-of-range Matrix access.
#
# Changelog v0.2.3 (2026):
#   - Added an appended spectral tail before the global FFT, allowing
#     transformed spectral energy to extend beyond the source duration.
#   - Added a tail-only half-cosine fade-out.
#   - Preserved RMS over the original body rather than the added tail.
#   - Revised the Praat AudioTools visualization with distinct semantic
#     colours for source, transformed body, tail, spectra and profile.
#
# Changelog v0.2.2 (2026):
#   - Standardized the visualization geometry and Picture styling to
#     Praat AudioTools conventions.
#
# Changelog v0.2.1 (2026):
#   - Corrected the Fast_FFT form-variable name for Praat scripting.
#
# Notes:
#   - Native Praat only: no Python, Parselmouth, plug-ins or external files.
#   - The original selected Sound is never modified.
# ============================================================

versionStr$ = "0.3.0"

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object before running Giant FFT Recomposer."
endif

sourceID = selected("Sound")
sourceName$ = selected$("Sound")
selectObject: sourceID
numChannels = Get number of channels
sourceFs = Get sampling frequency
numSamples = Get number of samples
sourceDuration = Get total duration

if numChannels > 2
    exitScript: "Giant FFT Recomposer v" + versionStr$ + " supports mono and stereo Sounds. Please split multichannel material first."
endif

form Giant FFT Recomposer
    optionmenu Preset: 2
        option Original Structure
        option Phase Mist
        option Deep Dissolution
        option Phase Crystal
        option Phase Gravity
        option Spectral Skeleton
        option Constellation
        option Spectrum Drift
        option Spectral Mirror
        option Spectral Fold
        option Magnitude Mutation
        option Global Freeze
        option Giant Collapse
        option Radical Recomposition
        option Custom
    real Transformation_depth 0.60
    real Phase_disorder 0.50
    optionmenu Phase_mode: 1
        option Random mist
        option Quantize (crystal)
        option Gravity
        option Time morph (scale)
    integer Phase_states 8
    real Phase_scale 1.50
    real Bin_density 0.30
    real Magnitude_amount 0.00
    real Pivot_frequency 1000
    real Frequency_drift 200
    real Fold_depth 0.50
    real Dry_wet_mix 1.00
    comment === Spectral Tail ===
    real Tail_duration_s 1.50
    real Fadeout_duration_s 1.00
    boolean Decorrelate_channels 0
    boolean Preserve_RMS 1
    boolean Fast_FFT 1
    boolean Create_visualization 1
    boolean Keep_Spectrum_objects 0
    boolean Play 1
    integer Random_seed 0
endform

# ------------------------------------------------------------------------------
# VALIDATION
# ------------------------------------------------------------------------------
if transformation_depth < 0 or transformation_depth > 1
    exitScript: "Transformation depth must be between 0 and 1."
endif
if phase_disorder < 0 or phase_disorder > 1
    exitScript: "Phase disorder must be between 0 and 1."
endif
if phase_states < 2
    exitScript: "Phase states must be at least 2."
endif
if bin_density <= 0 or bin_density > 1
    exitScript: "Bin density must be greater than 0 and at most 1."
endif
if magnitude_amount < 0 or magnitude_amount > 1
    exitScript: "Magnitude amount must be between 0 and 1."
endif
if pivot_frequency <= 0 or pivot_frequency >= sourceFs/2
    exitScript: "Pivot frequency must be above 0 Hz and below Nyquist (" + fixed$(sourceFs/2, 1) + " Hz)."
endif
if fold_depth < 0 or fold_depth > 1
    exitScript: "Fold depth must be between 0 and 1."
endif
if dry_wet_mix < 0 or dry_wet_mix > 1
    exitScript: "Dry/wet mix must be between 0 and 1."
endif
if tail_duration_s < 0
    exitScript: "Tail duration cannot be negative."
endif
if fadeout_duration_s < 0
    exitScript: "Fadeout duration cannot be negative."
endif

effectiveFadeoutDuration = min (fadeout_duration_s, tail_duration_s)
processingDuration = sourceDuration + tail_duration_s

presetCode = preset
presetLabel$ = preset$

# ------------------------------------------------------------------------------
# PRESET RESOLUTION
# ------------------------------------------------------------------------------
depth = transformation_depth
amtPhase = phase_disorder
phaseStatesN = phase_states
phaseScaleFactor = phase_scale
densityAmt = bin_density
magAmount = magnitude_amount
pivotHz = pivot_frequency
driftHz = frequency_drift
foldDepthAmt = fold_depth

gravityAmt = 0.70
reflectionAmt = 0.80
constellationContrast = 1.40

if presetCode = 1
    depth = 0
    amtPhase = 0
elif presetCode = 2
    depth = 0.55
    amtPhase = 0.55
elif presetCode = 3
    depth = 1.00
    amtPhase = 1.00
elif presetCode = 4
    depth = 0.75
    amtPhase = 0.90
    phaseStatesN = 8
elif presetCode = 5
    depth = 0.80
    gravityAmt = 0.90
elif presetCode = 6
    depth = 0.90
    densityAmt = 0.18
elif presetCode = 7
    depth = 0.90
    densityAmt = 0.10
    constellationContrast = 1.80
elif presetCode = 8
    depth = 0.80
    driftHz = 300
elif presetCode = 9
    depth = 0.90
    reflectionAmt = 0.95
elif presetCode = 10
    depth = 0.90
    foldDepthAmt = 0.95
elif presetCode = 11
    depth = 0.85
    magAmount = 0.90
elif presetCode = 12
    depth = 0.90
    amtPhase = 0.90
elif presetCode = 13
    depth = 0.95
    gravityAmt = 0.95
    densityAmt = 0.15
elif presetCode = 14
    depth = 0.90
    phaseScaleFactor = 2.20
    driftHz = 280
    densityAmt = 0.20
endif

# ------------------------------------------------------------------------------
# EXTENDED PROCESSING SOURCE
# ------------------------------------------------------------------------------
# The global FFT is taken over the source plus an appended silent tail. Phase and
# magnitude reorganization can therefore move energy into this extra time region
# instead of being hard-truncated at the original end. Only the appended tail is
# faded, so the source body is never attenuated by the fade-out.
if tail_duration_s > 0
    Create Sound from formula: "GiantFFT_silentTail", numChannels, 0, tail_duration_s, sourceFs, "0"
    silentTailID = selected("Sound")
    selectObject: sourceID, silentTailID
    Concatenate
    processingSourceID = selected("Sound")
    removeObject: silentTailID
else
    selectObject: sourceID
    processingSourceID = Copy: "GiantFFT_processingSource"
endif
selectObject: processingSourceID
processingSamples = Get number of samples
processingDuration = Get total duration

# Random-phase field. By default ONE field is shared by both stereo channels,
# which keeps the transformation spatially coherent - but coherent here means
# both channels are pushed toward the SAME phase, so at full depth they differ
# only in magnitude and the stereo image narrows. Measured on decorrelated
# stereo material at depth 1.0:
#     source              L/R corr 0.710   side/mid  -7.7 dB
#     shared phase field  L/R corr 0.888   side/mid -12.3 dB
#     per-channel fields  L/R corr 0.003   side/mid   0.0 dB
# Decorrelate_channels gives each channel its own field, which widens instead
# of narrowing. Neither is right in general; the default preserves the old
# behaviour and the switch makes the choice explicit rather than implied.
randomPhaseID = 0
randomPhaseNx = 0
randomPhaseChannel = 0
currentChannel = 1

# Timing diagnostic
stopwatch

# ==============================================================================
# HELPERS
# ==============================================================================

procedure ensureRandomPhase
    if decorrelate_channels = 1 and randomPhaseID <> 0 and randomPhaseChannel <> currentChannel
        removeObject: randomPhaseID
        randomPhaseID = 0
    endif
    if randomPhaseID = 0
        if random_seed > 0
            # Offset by channel so decorrelated runs stay reproducible.
            random_initializeWithSeedUnsafelyButPredictably (random_seed + currentChannel - 1)
        endif
        randomPhaseID = Create simple Matrix: "GiantFFT_randomPhase", 1, nBins, ~ randomUniform (-pi, pi)
        randomPhaseNx = nBins
        randomPhaseChannel = currentChannel
        if random_seed > 0
            random_initializeSafelyAndUnpredictably ()
        endif
    elsif randomPhaseNx <> nBins
        exitScript: "Internal error: stereo channels produced different FFT sizes."
    endif
endproc

procedure createMagnitudeMatrix: .specID
    .matrixID = Create simple Matrix: "GiantFFT_magnitude", 1, nBins, ~ sqrt (object [.specID, 1, col]^2 + object [.specID, 2, col]^2)
endproc

procedure getPeakMagnitude: .specID
    @createMagnitudeMatrix: .specID
    .matrixID = createMagnitudeMatrix.matrixID
    selectObject: .matrixID
    .peakMagnitude = Get maximum
    removeObject: .matrixID
endproc

# Threshold mapping used by Skeleton / Collapse. Bin_density is deliberately
# interpreted as an artistic retention control rather than an expensive exact
# percentile. 1.0 reaches about -66 dB from the strongest bin; sparse settings
# keep only the strongest global components.
procedure computeRetentionThreshold: .specID, .density
    @getPeakMagnitude: .specID
    .peakMagnitude = getPeakMagnitude.peakMagnitude
    .thresholdDb = -6 - 60 * .density
    .threshold = .peakMagnitude * 10^(.thresholdDb/20)
endproc

procedure makeDriftMap
    spanBins = nBins - 2
    if spanBins < 1
        spanBins = 1
    endif
    driftBins = round (driftHz / df * depth)
    .mapID = Create simple Matrix: "GiantFFT_driftMap", 1, nBins, ~ if col = 1 or col = nBins then col else 2 + ((col - 2 - driftBins) - spanBins * floor ((col - 2 - driftBins) / spanBins)) fi
endproc

procedure makeFoldMap
    foldBin = round (pivotHz / df) + 1
    if foldBin < 3
        foldBin = 3
    endif
    if foldBin > nBins - 1
        foldBin = nBins - 1
    endif
    foldHalf = foldBin - 1
    foldPeriod = 2 * foldHalf
    .mapID = Create simple Matrix: "GiantFFT_foldMap", 1, nBins, ~ if col = 1 or col = nBins then col else 1 + if ((col - 1) mod foldPeriod) > foldHalf then foldPeriod - ((col - 1) mod foldPeriod) else ((col - 1) mod foldPeriod) fi fi
endproc

# ==============================================================================
# VECTORIZED TRANSFORMATIONS
# Each procedure writes directly into workSpecID with Spectrum: Formula.
# origSpecID remains immutable.
#
# v0.3.0 - POLAR PRECOMPUTATION.
#   Magnitude and phase are now computed ONCE per channel into magID and phID
#   (1 x nBins Matrices), and every mode builds its new phase - and, where it
#   changes, its new magnitude - as another 1 x nBins Matrix. The Spectrum
#   Formula then reads two cells and calls one cos or sin.
#
#   Before this, the same arctan2 (im, re) was recomputed up to twelve times
#   inside a single formula, and that formula ran once per row per bin. Counted
#   per bin on the old code: Phase Crystal and Phase Gravity 12 arctan2, Giant
#   Collapse 12 arctan2 + 6 sqrt, Phase Mist 8 arctan2. On 6.5 s of stereo at
#   44.1 kHz with the fast FFT that is 262145 bins x 2 rows x 2 channels, so
#   Phase Crystal alone reached roughly 25 million transcendental calls in
#   Praat's tree-walking formula interpreter.
#
#   The mode maths below is unchanged - only the number of times each
#   sub-expression is evaluated.
# ==============================================================================

procedure buildPolarMatrices
    magID = Create simple Matrix: "GiantFFT_mag", 1, nBins,
        ... ~ sqrt (object [origSpecID,1,col]^2 + object [origSpecID,2,col]^2)
    phID = Create simple Matrix: "GiantFFT_phase", 1, nBins,
        ... ~ arctan2 (object [origSpecID,2,col], object [origSpecID,1,col])
endproc

# Rebuild the Spectrum from a magnitude Matrix and a phase Matrix. DC and a
# real Nyquist bin are copied through untouched, exactly as before.
procedure writeFromPolar
    selectObject: workSpecID
    Formula: ~ if col = 1 or (nyquistIsReal = 1 and col = ncol) then object [origSpecID,row,col] else if row = 1 then object [polarMagID,1,col] * cos (object [polarPhID,1,col]) else object [polarMagID,1,col] * sin (object [polarPhID,1,col]) fi fi
endproc

procedure modeOriginal
    selectObject: workSpecID
    Formula: ~ object [origSpecID, row, col]
endproc

procedure modePhaseMist
    @ensureRandomPhase
    amt = min (1, depth * amtPhase)
    newPhID = Create simple Matrix: "GiantFFT_newPhase", 1, nBins,
        ... ~ object [phID,1,col] + amt * arctan2 (sin (object [randomPhaseID,1,col] - object [phID,1,col]), cos (object [randomPhaseID,1,col] - object [phID,1,col]))
    polarMagID = magID
    polarPhID = newPhID
    @writeFromPolar
    removeObject: newPhID
endproc

procedure modePhaseCrystal
    amt = min (1, depth * amtPhase)
    phaseStep = 2*pi / phaseStatesN
    newPhID = Create simple Matrix: "GiantFFT_newPhase", 1, nBins,
        ... ~ object [phID,1,col] + amt * arctan2 (sin (round (object [phID,1,col] / phaseStep) * phaseStep - object [phID,1,col]), cos (round (object [phID,1,col] / phaseStep) * phaseStep - object [phID,1,col]))
    polarMagID = magID
    polarPhID = newPhID
    @writeFromPolar
    removeObject: newPhID
endproc

procedure modePhaseGravity
    amt = min (1, depth * gravityAmt)
    gravityStep = pi/2
    newPhID = Create simple Matrix: "GiantFFT_newPhase", 1, nBins,
        ... ~ object [phID,1,col] + amt * arctan2 (sin (round (object [phID,1,col] / gravityStep) * gravityStep - object [phID,1,col]), cos (round (object [phID,1,col] / gravityStep) * gravityStep - object [phID,1,col]))
    polarMagID = magID
    polarPhID = newPhID
    @writeFromPolar
    removeObject: newPhID
endproc

procedure modePhaseMorph
    factor = 1 + (phaseScaleFactor - 1) * depth
    newPhID = Create simple Matrix: "GiantFFT_newPhase", 1, nBins,
        ... ~ object [phID,1,col] * factor
    polarMagID = magID
    polarPhID = newPhID
    @writeFromPolar
    removeObject: newPhID
endproc

procedure modeSkeleton
    @computeRetentionThreshold: origSpecID, densityAmt
    retentionThreshold = computeRetentionThreshold.threshold
    selectObject: workSpecID
    Formula: ~ if col = 1 or (nyquistIsReal = 1 and col = ncol) then object [origSpecID,row,col] else if object [magID,1,col] >= retentionThreshold then object [origSpecID,row,col] else object [origSpecID,row,col] * (1-depth) fi fi
endproc

procedure modeConstellation
    @getPeakMagnitude: origSpecID
    maxMag = getPeakMagnitude.peakMagnitude
    constellationThreshold = maxMag * 10^((-10 - 35*densityAmt)/20)
    selectObject: workSpecID
    Formula: ~ if col = 1 or col = ncol then object [origSpecID,row,col] else if object [magID,1,col] >= object [magID,1,col-1] and object [magID,1,col] >= object [magID,1,col+1] and object [magID,1,col] >= constellationThreshold then object [origSpecID,row,col] * (1 + constellationContrast*depth) else object [origSpecID,row,col] * (1-depth) fi fi
endproc

procedure modeDrift
    @makeDriftMap
    driftMapID = makeDriftMap.mapID
    selectObject: workSpecID
    Formula: ~ if col = 1 or (nyquistIsReal = 1 and col = ncol) then object [origSpecID,row,col] else object [origSpecID,row,object [driftMapID,1,col]] fi
    removeObject: driftMapID
endproc

procedure modeMirror
    pivotBin = round (pivotHz/df) + 1
    amt = min (1, reflectionAmt * depth)
    selectObject: workSpecID
    Formula: ~ if col = 1 or (nyquistIsReal = 1 and col = ncol) then object [origSpecID,row,col] else if 2*pivotBin-col >= 2 and 2*pivotBin-col <= ncol-1 then object [origSpecID,row,col]*(1-amt) + object [origSpecID,row,2*pivotBin-col]*amt else object [origSpecID,row,col] fi fi
endproc

procedure modeFold
    @makeFoldMap
    foldMapID = makeFoldMap.mapID
    amt = min (1, foldDepthAmt * depth)
    selectObject: workSpecID
    Formula: ~ if col = 1 or (nyquistIsReal = 1 and col = ncol) then object [origSpecID,row,col] else object [origSpecID,row,col]*(1-amt) + object [origSpecID,row,object [foldMapID,1,col]]*amt fi
    removeObject: foldMapID
endproc

procedure modeMagnitudeMutation
    amt = min (1, magAmount * depth)
    newMagID = Create simple Matrix: "GiantFFT_newMag", 1, nBins,
        ... ~ (1-amt)*object [magID,1,col] + amt*object [magID,1,ncol-col+1]
    polarMagID = newMagID
    polarPhID = phID
    @writeFromPolar
    removeObject: newMagID
endproc

procedure modeFreeze
    @ensureRandomPhase
    smoothMagID = Create simple Matrix: "GiantFFT_smoothMagnitude", 1, nBins,
        ... ~ if col = 1 or col = ncol then object [magID,1,col] else (object [magID,1,col-1] + 2*object [magID,1,col] + object [magID,1,col+1])/4 fi
    phaseAmt = min (1, 0.45 + 0.55*depth)
    newMagID = Create simple Matrix: "GiantFFT_newMag", 1, nBins,
        ... ~ (1-depth)*object [magID,1,col] + depth*object [smoothMagID,1,col]
    newPhID = Create simple Matrix: "GiantFFT_newPhase", 1, nBins,
        ... ~ object [phID,1,col] + phaseAmt * arctan2 (sin (object [randomPhaseID,1,col] - object [phID,1,col]), cos (object [randomPhaseID,1,col] - object [phID,1,col]))
    polarMagID = newMagID
    polarPhID = newPhID
    @writeFromPolar
    removeObject: smoothMagID, newMagID, newPhID
endproc

procedure modeCollapse
    @computeRetentionThreshold: origSpecID, densityAmt
    retentionThreshold = computeRetentionThreshold.threshold
    amt = min (1, gravityAmt*depth)
    gravityStep = pi/2
    newMagID = Create simple Matrix: "GiantFFT_newMag", 1, nBins,
        ... ~ if object [magID,1,col] >= retentionThreshold then object [magID,1,col] else object [magID,1,col]*(1-depth) fi
    newPhID = Create simple Matrix: "GiantFFT_newPhase", 1, nBins,
        ... ~ object [phID,1,col] + amt * arctan2 (sin (round (object [phID,1,col]/gravityStep)*gravityStep - object [phID,1,col]), cos (round (object [phID,1,col]/gravityStep)*gravityStep - object [phID,1,col]))
    polarMagID = newMagID
    polarPhID = newPhID
    @writeFromPolar
    removeObject: newMagID, newPhID
endproc

procedure modeRadical
    @makeDriftMap
    radicalMapID = makeDriftMap.mapID
    @computeRetentionThreshold: origSpecID, densityAmt
    retentionThreshold = computeRetentionThreshold.threshold
    factor = 1 + (phaseScaleFactor - 1) * depth
    newMagID = Create simple Matrix: "GiantFFT_newMag", 1, nBins,
        ... ~ if object [magID,1,object [radicalMapID,1,col]] >= retentionThreshold then object [magID,1,object [radicalMapID,1,col]] else object [magID,1,object [radicalMapID,1,col]]*(1-depth) fi
    newPhID = Create simple Matrix: "GiantFFT_newPhase", 1, nBins,
        ... ~ object [phID,1,object [radicalMapID,1,col]] * factor
    polarMagID = newMagID
    polarPhID = newPhID
    @writeFromPolar
    removeObject: radicalMapID, newMagID, newPhID
endproc

procedure modeCustom
    # Phase stage: fully vectorized and referenced to the immutable original.
    if phase_mode = 1
        @modePhaseMist
    elsif phase_mode = 2
        @modePhaseCrystal
    elsif phase_mode = 3
        @modePhaseGravity
    else
        @modePhaseMorph
    endif

    # Spectral retention can safely multiply the current complex Spectrum in place.
    if densityAmt < 0.999999
        @computeRetentionThreshold: origSpecID, densityAmt
        retentionThreshold = computeRetentionThreshold.threshold
        selectObject: workSpecID
        Formula: ~ if col = 1 or (nyquistIsReal = 1 and col = ncol) or object [magID,1,col] >= retentionThreshold then self else self*(1-depth) fi
    endif

    # Optional magnitude mutation. The magnitudes here are those of the CURRENT
    # work spectrum, not the original, because the retention stage above may
    # already have scaled them - so a fresh magnitude Matrix is built rather
    # than reusing magID. Phase is untouched by both stages, so phID still
    # holds it only if no retention scaling occurred; to stay exact, phase is
    # taken from the stage copy.
    if magAmount > 0.000001
        selectObject: workSpecID
        customStageID = Copy: "GiantFFT_customStage"
        amt = min (1, magAmount*depth)
        stageMagID = Create simple Matrix: "GiantFFT_stageMag", 1, nBins,
            ... ~ sqrt (object [customStageID,1,col]^2 + object [customStageID,2,col]^2)
        stagePhID = Create simple Matrix: "GiantFFT_stagePhase", 1, nBins,
            ... ~ arctan2 (object [customStageID,2,col], object [customStageID,1,col])
        newMagID = Create simple Matrix: "GiantFFT_newMag", 1, nBins,
            ... ~ (1-amt)*object [stageMagID,1,col] + amt*object [stageMagID,1,ncol-col+1]
        selectObject: workSpecID
        Formula: ~ if col = 1 or (nyquistIsReal = 1 and col = ncol) then object [customStageID,row,col] else if row = 1 then object [newMagID,1,col] * cos (object [stagePhID,1,col]) else object [newMagID,1,col] * sin (object [stagePhID,1,col]) fi fi
        removeObject: customStageID, stageMagID, stagePhID, newMagID
    endif

    # Optional drift uses one temporary Spectrum for safe pull mapping.
    if abs (driftHz) > 0.000001
        selectObject: workSpecID
        customStageID = Copy: "GiantFFT_customStage"
        @makeDriftMap
        customDriftMapID = makeDriftMap.mapID
        selectObject: workSpecID
        Formula: ~ if col = 1 or (nyquistIsReal = 1 and col = ncol) then object [customStageID,row,col] else object [customStageID,row,object [customDriftMapID,1,col]] fi
        removeObject: customStageID, customDriftMapID
    endif
endproc

procedure applyPreset
    if presetCode = 1
        @modeOriginal
    elsif presetCode = 2 or presetCode = 3
        @modePhaseMist
    elsif presetCode = 4
        @modePhaseCrystal
    elsif presetCode = 5
        @modePhaseGravity
    elsif presetCode = 6
        @modeSkeleton
    elsif presetCode = 7
        @modeConstellation
    elsif presetCode = 8
        @modeDrift
    elsif presetCode = 9
        @modeMirror
    elsif presetCode = 10
        @modeFold
    elsif presetCode = 11
        @modeMagnitudeMutation
    elsif presetCode = 12
        @modeFreeze
    elsif presetCode = 13
        @modeCollapse
    elsif presetCode = 14
        @modeRadical
    else
        @modeCustom
    endif
endproc

# ==============================================================================
# CHANNEL PROCESSING
# ==============================================================================
procedure processChannel: .srcID, .channelNumber
    selectObject: .srcID
    fs = Get sampling frequency
    if fast_FFT = 1
        To Spectrum: "yes"
    else
        To Spectrum: "no"
    endif
    origSpecID = selected("Spectrum")
    nBins = object[origSpecID].nx
    df = object[origSpecID].dx
    freqLast = (nBins-1)*df
    nyquistIsReal = 0
    if abs (freqLast - fs/2) <= max (1e-12, df/4)
        nyquistIsReal = 1
    endif

    currentChannel = .channelNumber

    selectObject: origSpecID
    workSpecID = Copy: "GiantFFT_workSpectrum"

    # Magnitude and phase, once per channel. Every mode reads these instead of
    # recomputing sqrt and arctan2 inside the per-bin Spectrum formula.
    @buildPolarMatrices

    @applyPreset

    removeObject: magID, phID

    selectObject: workSpecID
    To Sound
    paddedSoundID = selected("Sound")

    # Fast FFT may zero-pad to a power-of-two length. Trim the inverse FFT back
    # to the exact extended processing duration before mixing or returning the result.
    selectObject: paddedSoundID
    outSamples = Get number of samples
    if outSamples <> processingSamples
        Extract part: 0, processingDuration, "rectangular", 1.0, "no"
        .outID = selected("Sound")
        removeObject: paddedSoundID
    else
        .outID = paddedSoundID
    endif

    .origSpecID = origSpecID
    .workSpecID = workSpecID

    if keep_Spectrum_objects = 1
        selectObject: origSpecID
        Rename: sourceName$ + "_GiantFFT_SourceSpectrum_ch" + string$(.channelNumber)
        selectObject: workSpecID
        Rename: sourceName$ + "_GiantFFT_WetSpectrum_ch" + string$(.channelNumber)
    endif
endproc

# ==============================================================================
# MAIN FLOW
# ==============================================================================
visualOrigSpecID = 0
visualWetSpecID = 0
rightOrigSpecID = 0
rightWetSpecID = 0

if numChannels = 2
    selectObject: processingSourceID
    Extract one channel: 1
    leftID = selected("Sound")
    selectObject: processingSourceID
    Extract one channel: 2
    rightID = selected("Sound")

    @processChannel: leftID, 1
    wetLeftID = processChannel.outID
    visualOrigSpecID = processChannel.origSpecID
    visualWetSpecID = processChannel.workSpecID

    @processChannel: rightID, 2
    wetRightID = processChannel.outID
    rightOrigSpecID = processChannel.origSpecID
    rightWetSpecID = processChannel.workSpecID

    selectObject: wetLeftID, wetRightID
    Combine to stereo
    wetID = selected("Sound")

    removeObject: leftID, rightID, wetLeftID, wetRightID

    if keep_Spectrum_objects = 0
        removeObject: rightOrigSpecID, rightWetSpecID
    endif
else
    @processChannel: processingSourceID, 1
    wetID = processChannel.outID
    visualOrigSpecID = processChannel.origSpecID
    visualWetSpecID = processChannel.workSpecID
endif

resultID = wetID

# True dry/wet mix by sample index. The fast-FFT output has already been trimmed
# to the extended processing sample count, so no temporary dry Sound is required.
if dry_wet_mix < 0.999999
    selectObject: resultID
    Formula: ~ self*dry_wet_mix + object [processingSourceID,row,col]*(1-dry_wet_mix)
endif

# Tail-only half-cosine fade. The fade is constrained to the appended region.
if tail_duration_s > 0 and effectiveFadeoutDuration > 0
    fadeStart = processingDuration - effectiveFadeoutDuration
    selectObject: resultID
    Formula: ~ if x > fadeStart then self * (0.5 + 0.5*cos(pi*(x-fadeStart)/effectiveFadeoutDuration)) else self fi
else
    fadeStart = processingDuration
endif

# Preserve the level of the ORIGINAL-DURATION body, not the appended tail.
# This prevents a long quiet tail from causing an unintended global gain boost.
if preserve_RMS = 1
    selectObject: sourceID
    origRMS = Get root-mean-square: 0, 0
    selectObject: resultID
    bodyRMS = Get root-mean-square: 0, sourceDuration
    if bodyRMS > 0
        rmsGain = origRMS / bodyRMS
        Formula: ~ self*rmsGain
    endif
endif

selectObject: resultID
peakVal = Get absolute extremum: 0, 0, "none"
if peakVal > 0.999
    safetyGain = 0.999 / peakVal
    Formula: ~ self*safetyGain
endif

presetTag$ = replace$ (presetLabel$, " ", "", 0)
finalName$ = sourceName$ + "_GiantFFT_" + presetTag$
selectObject: resultID
Rename: finalName$

# ==============================================================================
# DIAGNOSTICS (reuse retained spectra; no extra FFTs)
# For stereo, spectrum diagnostics/plots use channel 1 while waveforms show the
# complete stereo Sounds.
# ==============================================================================
selectObject: visualOrigSpecID
origCentroid = Get centre of gravity: 2
selectObject: visualWetSpecID
wetCentroid = Get centre of gravity: 2

selectObject: sourceID
origRMSInfo = Get root-mean-square: 0, 0
sourcePeak = Get absolute extremum: 0, 0, "none"
selectObject: resultID
resultRMSInfo = Get root-mean-square: 0, 0
resultPeak = Get absolute extremum: 0, 0, "none"
resultDuration = Get total duration

elapsedSeconds = stopwatch

writeInfoLine: "Giant FFT Recomposer v", versionStr$
appendInfoLine: "Preset: ", presetLabel$
appendInfoLine: "Transformation depth: ", fixed$(depth, 3)
appendInfoLine: "FFT mode: ", if fast_FFT = 1 then "fast (zero-padded internally, trimmed after IFFT)" else "exact-length" fi
appendInfoLine: "Spectrum diagnostic channel: ", if numChannels = 2 then "1 (left)" else "mono" fi
appendInfoLine: "Original spectral centroid (Hz): ", fixed$(origCentroid, 1)
appendInfoLine: "Wet spectral centroid (Hz): ", fixed$(wetCentroid, 1)
appendInfoLine: "Original RMS: ", fixed$(origRMSInfo, 5)
appendInfoLine: "Final RMS: ", fixed$(resultRMSInfo, 5)
appendInfoLine: "Tail: ", fixed$(tail_duration_s, 3), " s | fade-out: ", fixed$(effectiveFadeoutDuration, 3), " s"
appendInfoLine: "Final duration: ", fixed$(resultDuration, 3), " s"
appendInfoLine: "Processing time (s): ", fixed$(elapsedSeconds, 3)
appendInfoLine: "Result object: ", finalName$

# ============================================================================== 
# PRAAT AUDIOTOOLS VISUALIZATION STANDARD
# Follows the current library convention used by LZ-Inspired Audio Variations:
#   - 8-inch page convention with explicit outer + inner viewports
#   - light neutral panel backgrounds
#   - each displayed data role has its own stable house colour
#   - neutral grey = dry/source waveform; mauve = transformed body; rust = tail
#   - blue = source spectrum; amber = transformed spectrum; plum = profile
#   - curves drawn without Praat's automatic garnish, then boxed/labeled manually
#   - shared waveform amplitude scale
#   - diagnostics in a dedicated summary strip, outside the data panels
#   - no automatic Marks... commands: panel geometry and labels remain stable
# ============================================================================== 
# Draw one magnitude envelope, taking the MAXIMUM over each block of bins
# rather than sampling a single bin per plotted point.
procedure drawSpectrumEnvelope
    selectObject: envDrawID
    Line width: 1
    havePrev = 0
    i = 1
    while i <= nBins
        blockEnd = i + stepBins - 1
        if blockEnd > nBins
            blockEnd = nBins
        endif
        m = Get maximum: i - 1, blockEnd, "None"
        db = 20 * log10 (max (m / displayPeakMag, 1e-12))
        if db < spectrumFloor
            db = spectrumFloor
        endif
        f = (i - 1) * df
        if havePrev = 1
            Draw line: prevF, prevDb, f, db
        endif
        prevF = f
        prevDb = db
        havePrev = 1
        i = i + stepBins
    endwhile
endproc

if create_visualization = 1
    wavePeak = max (sourcePeak, resultPeak)
    if wavePeak <= 0
        wavePeak = 1
    endif
    wavePeak = wavePeak * 1.10

    # Magnitude envelopes as Sounds (1 Hz, one sample per bin) so that a block
    # MAXIMUM can be taken per plotted point with Get maximum. The v0.2.4 panel
    # point-sampled one bin in every stepBins instead, which for nBins = 262145
    # meant showing one bin in every 404. On a sparse spectrum - exactly what
    # Spectral Skeleton, Constellation and Giant Collapse produce - that draws
    # almost nothing: on a test spectrum with 3000 retained peaks the panel
    # sampled 8 of them, 0.3%, and the curve sat on the -80 dB floor while the
    # real spectrum was full of peaks at 0 dB. Even on a dense spectrum the
    # point-sampled median ran 15 dB low.
    origEnvID = Create Sound from formula: "GiantFFT_origEnv", 1, 0, nBins, 1,
        ... ~ sqrt (object [visualOrigSpecID,1,col]^2 + object [visualOrigSpecID,2,col]^2)
    wetEnvID = Create Sound from formula: "GiantFFT_wetEnv", 1, 0, nBins, 1,
        ... ~ sqrt (object [visualWetSpecID,1,col]^2 + object [visualWetSpecID,2,col]^2)
    selectObject: origEnvID
    origPeakMag = Get maximum: 0, 0, "None"
    selectObject: wetEnvID
    wetPeakMag = Get maximum: 0, 0, "None"
    displayPeakMag = max (origPeakMag, wetPeakMag)
    if displayPeakMag <= 0
        displayPeakMag = 1
    endif

    maxFreq = sourceFs / 2
    spectrumFloor = -80
    spectrumCeiling = 3

    plotPoints = 650
    stepBins = ceiling (nBins / plotPoints)
    if stepBins < 1
        stepBins = 1
    endif

    phaseProfile = 0
    if presetCode = 2 or presetCode = 3 or presetCode = 4 or presetCode = 5 or presetCode = 12 or presetCode = 13 or presetCode = 14 or presetCode = 15
        phaseProfile = 1
    endif

    vizName$ = replace$ (sourceName$, "_", "\_ ", 0)
    fftMode$ = "exact-length FFT"
    if fast_FFT = 1
        fftMode$ = "fast FFT"
    endif

    pageHeight = 8.55
    Erase all
    Line width: 1
    Colour: "Black"
    Solid line
    Select outer viewport: 0, 8, 0, pageHeight

    # === Header ===
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Giant FFT Recomposer v" + versionStr$ + "##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", vizName$ + " | " + presetLabel$ + " | depth " + fixed$ (depth, 2) + " | one global FFT"

    # === A: source waveform ===
    Select outer viewport: 0, 8, 0.72, 2.05
    Select inner viewport: 0.60, 7.70, 0.94, 1.76
    Axes: 0, sourceDuration, -wavePeak, wavePeak
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, sourceDuration, -wavePeak, wavePeak

    selectObject: sourceID
    Colour: "{0.60, 0.60, 0.60}"
    Draw: 0, 0, -wavePeak, wavePeak, "no", "Curve"

    Select inner viewport: 0.60, 7.70, 0.94, 1.76
    Axes: 0, sourceDuration, -wavePeak, wavePeak
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, sourceDuration, 0
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "no", "Amp"
    Text bottom: "no", "Time (s)"
    Text top: "no", "Source | shared amplitude scale"

    # === B: transformed output waveform ===
    Select outer viewport: 0, 8, 2.05, 3.38
    Select inner viewport: 0.60, 7.70, 2.27, 3.09
    Axes: 0, resultDuration, -wavePeak, wavePeak
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, resultDuration, -wavePeak, wavePeak
    if tail_duration_s > 0
        # The tail has its own quiet field so its extension beyond the source is explicit.
        Paint rectangle: "{0.965, 0.945, 0.925}", sourceDuration, resultDuration, -wavePeak, wavePeak
    endif

    selectObject: resultID
    # House palette: transformed body = mauve, appended spectral tail = rust.
    Colour: "{0.60, 0.50, 0.60}"
    Draw: 0, sourceDuration, -wavePeak, wavePeak, "no", "Curve"
    if tail_duration_s > 0
        Colour: "{0.80, 0.35, 0.20}"
        Draw: sourceDuration, resultDuration, -wavePeak, wavePeak, "no", "Curve"
    endif

    Select inner viewport: 0.60, 7.70, 2.27, 3.09
    Axes: 0, resultDuration, -wavePeak, wavePeak
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, resultDuration, 0
    if tail_duration_s > 0
        Dashed line
        Colour: "{0.68, 0.60, 0.56}"
        Draw line: sourceDuration, -wavePeak, sourceDuration, wavePeak
        if effectiveFadeoutDuration > 0 and fadeStart > sourceDuration
            Dotted line
            Colour: "{0.76, 0.58, 0.46}"
            Draw line: fadeStart, -wavePeak, fadeStart, wavePeak
        endif
        Solid line
    endif
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "no", "Amp"
    Text bottom: "no", "Time (s)"
    if tail_duration_s > 0
        Text top: "no", "Transformed Output | mauve = body, rust = spectral tail | fade begins at " + fixed$ (fadeStart, 2) + " s"
    else
        Text top: "no", "Transformed Output | mauve = transformed body"
    endif

    # === C: global magnitude spectrum, source + wet on one scale ===
    Select outer viewport: 0, 8, 3.38, 5.20
    Select inner viewport: 0.60, 7.70, 3.66, 4.91
    Axes: 0, maxFreq, spectrumFloor, spectrumCeiling
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, maxFreq, spectrumFloor, spectrumCeiling

    # Quiet reference guides behind the curves.
    Colour: "{0.86, 0.86, 0.86}"
    Dotted line
    guideDb = -20
    while guideDb >= -60
        Draw line: 0, guideDb, maxFreq, guideDb
        guideDb = guideDb - 20
    endwhile
    Solid line

    # Original spectrum first, neutral.
    Colour: "{0.30, 0.48, 0.74}"
    envDrawID = origEnvID
    @drawSpectrumEnvelope

    # Core transformed spectrum on top, using the library amber accent.
    Colour: "{0.88, 0.52, 0.12}"
    envDrawID = wetEnvID
    @drawSpectrumEnvelope

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "no", "Relative magnitude (dB)"
    Text bottom: "no", "Frequency (Hz)"
    Text top: "no", "Global Spectrum | blue = source, amber = transformed core"

    # === D: transformation profile ===
    Select outer viewport: 0, 8, 5.20, 6.78
    Select inner viewport: 0.60, 7.70, 5.48, 6.49

    if phaseProfile = 1
        Axes: 0, maxFreq, -1, 1
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, maxFreq, -1, 1
        Colour: "{0.84, 0.84, 0.84}"
        Draw line: 0, 0, maxFreq, 0

        Colour: "{0.60, 0.40, 0.50}"
        havePrev = 0
        i = 2
        while i <= nBins - 1
            f = (i - 1) * df
            p0 = arctan2 (object [visualOrigSpecID,2,i], object [visualOrigSpecID,1,i])
            p1 = arctan2 (object [visualWetSpecID,2,i], object [visualWetSpecID,1,i])
            delta = arctan2 (sin (p1 - p0), cos (p1 - p0)) / pi
            if havePrev = 1
                Draw line: prevF, prevValue, f, delta
            endif
            prevF = f
            prevValue = delta
            havePrev = 1
            i = i + stepBins
        endwhile

        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "no", "Phase change / pi"
        Text bottom: "no", "Frequency (Hz)"
        Text top: "no", "Transformation Profile | wrapped phase displacement"
    else
        Axes: 0, maxFreq, -40, 40
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, maxFreq, -40, 40
        Colour: "{0.84, 0.84, 0.84}"
        Draw line: 0, 0, maxFreq, 0

        Colour: "{0.60, 0.40, 0.50}"
        havePrev = 0
        i = 2
        while i <= nBins - 1
            f = (i - 1) * df
            m0 = sqrt (object [visualOrigSpecID,1,i]^2 + object [visualOrigSpecID,2,i]^2)
            m1 = sqrt (object [visualWetSpecID,1,i]^2 + object [visualWetSpecID,2,i]^2)
            changeDb = 20 * log10 (max (m1, 1e-15) / max (m0, 1e-15))
            if changeDb < -40
                changeDb = -40
            elsif changeDb > 40
                changeDb = 40
            endif
            if havePrev = 1
                Draw line: prevF, prevValue, f, changeDb
            endif
            prevF = f
            prevValue = changeDb
            havePrev = 1
            i = i + stepBins
        endwhile

        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "no", "Magnitude change (dB)"
        Text bottom: "no", "Frequency (Hz)"
        Text top: "no", "Transformation Profile | wet minus source magnitude"
    endif

    # === Summary strip ===
    Select outer viewport: 0, 8, 6.82, 8.40
    Select inner viewport: 0.60, 7.70, 6.94, 8.28
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    summary1$ = "##Transform##  " + presetLabel$ + " | depth " + fixed$ (depth, 2) + " | " + fftMode$ + " | dry/wet " + fixed$ (dry_wet_mix, 2) + " | tail " + fixed$ (tail_duration_s, 2) + " s / fade " + fixed$ (effectiveFadeoutDuration, 2) + " s"
    if phaseProfile = 1
        profileLabel$ = "wrapped phase displacement"
    else
        profileLabel$ = "magnitude change"
    endif
    summary2$ = "##Spectrum##  blue source / amber transformed | centroid " + fixed$ (origCentroid, 1) + " -> " + fixed$ (wetCentroid, 1) + " Hz | floor " + fixed$ (spectrumFloor, 0) + " dB | plum profile = " + profileLabel$
    summary3$ = "##Output##  RMS " + fixed$ (origRMSInfo, 4) + " -> " + fixed$ (resultRMSInfo, 4) + " | peak " + fixed$ (resultPeak, 3) + " | duration " + fixed$ (resultDuration, 2) + " s | processing " + fixed$ (elapsedSeconds, 2) + " s"
    Text: 0.02, "left", 0.78, "half", summary1$
    Text: 0.02, "left", 0.50, "half", summary2$
    Text: 0.02, "left", 0.22, "half", summary3$

    Colour: "Black"
    Draw inner box

    # Restore complete page for Picture export / clipboard.
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line

    removeObject: origEnvID, wetEnvID
endif

# Clean internal random-control object.
if randomPhaseID <> 0
    removeObject: randomPhaseID
endif

# The extended source is private working material; keep the caller's original only.
removeObject: processingSourceID

# Remove retained analysis spectra only after diagnostics and visualization.
if keep_Spectrum_objects = 0
    removeObject: visualOrigSpecID, visualWetSpecID
endif

selectObject: resultID
if play = 1
    Play
endif

selectObject: resultID
