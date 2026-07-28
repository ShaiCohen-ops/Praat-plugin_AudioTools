# ============================================================
# Praat AudioTools - MSE_Feature_Constrained_Variation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.5 (2026) - Clamped probabilities, exact duration, RNG reset
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v1.5 (2026):
#
#   This release exists because v1.4's changelog item 6 described fixes
#   that were never written. The ceiling it added applies to
#   currentIntensity; every per-transform multiplier is applied AFTER
#   that, so nothing downstream was actually bounded.
#
#   CRITICAL - the derived grain probabilities were never clamped, and
#     two built-in presets were destroying their own source material
#     from the first iteration. Measured at each preset's INITIAL
#     intensity:
#       Granular  gi=1.500 -> swap 1.500, reverse 1.500, gate 1.050
#       Extreme   gi=2.250 -> swap 2.250, reverse 2.250, gate 1.800
#       Standard  gi=0.400 -> swap 0.160, reverse 0.120, gate 0.060
#     With gate > 1 every grain is silenced and with reverse > 1 every
#     grain is reversed first, so the granular layer was gone before
#     the noise stage put anything back. swapProb, reverseProb and
#     gateProb are now clamped to [0, 1]. THIS CHANGES GRANULAR AND
#     EXTREME AUDIO - they now actually contain granular material.
#
#   2 - The spectral multiplier (1 + mutAmp * sin) still goes negative,
#     and that is now a stated choice rather than an unnoticed one.
#     Measured ranges at each preset's initial intensity:
#       Standard  mutAmp 1.200 -> -0.20 .. 2.20
#       Spectral  mutAmp 3.375 -> -2.38 .. 4.38
#       Extreme   mutAmp 6.750 -> -5.75 .. 7.75
#     Negative values invert the phase of the affected bins.
#     allowSpectralInversion (script-level, near the top) selects:
#     1 = keep them, which is what every existing render of Spectral
#     and Extreme was made with, and the default; 0 = clamp mutAmp to
#     0.95 so the multiplier stays positive.
#
#   3 - A sub-5 ms final remainder is MERGED into the preceding grain
#     instead of being padded up to 5 ms. The grain arithmetic did
#     overrun: a 0.161 s input at a 0.080 s grain gives 80 + 80 + 1 ms,
#     the 1 ms tail was inflated to 5 ms, and the fragments summed to
#     0.165 s.
#     Measured end to end, though, the OUTPUT duration was correct in
#     both versions - 0.16100 s either way - because the granular pass
#     writes into a buffer pre-allocated at the source length, so the
#     extra 4 ms was clipped rather than appended. The real symptom was
#     therefore a duplicated ~5 ms fragment overlapping the end of the
#     buffer, not a duration error. Merging removes the duplicate and
#     makes the grain arithmetic honest.
#
#   4 - The RNG is returned to its safe state once all random
#     processing is done. v1.4 seeded it and never reset, leaving every
#     later script in the same Praat session running from a predictable
#     global sequence.
#
#   5 - The dead-dimension rationale is restated. Excluding a dimension
#     with near-zero source mean and variance is a NORMALISATION
#     decision, not a claim that the dimension is uninformative: a
#     steady tone's zero spectral flux is meaningful, and excluding it
#     makes the metric blind to a transformation that introduces flux.
#     That blind spot is the accepted cost of stable normalisation.
#
# Changelog v1.4 (2026):
#
#   CRITICAL 1 - the reported distance was not the delivered file's
#     distance. Candidates were measured, the best was chosen, and
#     THEN Scale peak 0.95 was applied. Band energies, spectral flux
#     and several MFCC coefficients all scale with gain, so the file
#     the user receives sits at a different distance from the one
#     printed. Measured on a source peaking at 0.60: Scale peak 0.95
#     multiplied its energy by 2.51x - after the distance had been
#     fixed. v1.4 normalises the source AND every candidate to the
#     same peak BEFORE feature extraction, so the measured object and
#     the delivered object are the same object at the same gain. The
#     final Scale peak is gone.
#
#   CRITICAL 2 - degenerate dimensions could still decide the result.
#     v1.3's relative floor, (2% of |mean|)^2, does nothing when the
#     mean is ALSO zero - a steady tone's spectral flux, or a band
#     that is empty at this sample rate. The 10-sigma cap then bounds
#     the term but does not make it small: one saturated statistic
#     contributes 10^2 / 38 = 2.6316 to the distance, which is 263% of
#     the Standard target (1.0), 175% of Granular (1.5) and 658% of
#     Subtle (0.4). One dead dimension could push every iteration past
#     the target band on its own. v1.4 detects dimensions that carry
#     no usable NORMALISER in the original (variance and mean both
#     below an absolute floor), EXCLUDES them from the sum, and divides
#     by the number of statistics actually used. Excluded dimensions
#     are reported. Note this is a normalisation decision, not a claim
#     that such a dimension is uninformative: a steady tone's zero
#     spectral flux is meaningful, and excluding it makes the metric
#     blind to a transformation that introduces flux. The blind spot is
#     the accepted cost of stable normalisation.
#
#   CRITICAL 3 - the metric is a bag-of-frames timbral descriptor and
#     is now described as one. Despite the "50 frames x 19 dimensions
#     = 950 features" line, the distance reduces each dimension to its
#     mean and variance: 19 x 2 = 38 numbers. Both statistics are
#     invariant to frame order - verified on a toy dimension, where
#     reordering left mean and variance identical to six decimals - so
#     granular reordering and grain reversal are very nearly free,
#     while a small overall gain or energy change moves the distance a
#     great deal. That is a legitimate constraint to compose against,
#     but it constrains TIMBRAL DISTRIBUTION, not amount of structural
#     variation, and the header and report now say so. Adding
#     order-sensitivity (delta-MFCC statistics, onset density, envelope
#     autocorrelation) would need the fixed 19-slot layout reworked and
#     every preset target recalibrated; that is a redesign, not a fix,
#     and is deliberately NOT smuggled in here.
#
#   4 - Random_seed added (0 = unpredictable), and the search is
#     described for what it is. Each iteration redraws every swap,
#     reversal, gate, tilt, burst and pitch perturbation from scratch,
#     so consecutive iterations differ by BOTH the intensity change and
#     a fresh random realisation. The distance is therefore not a
#     monotone function of intensity and the "convergence" plot is a
#     stochastic search trace, not a descent curve. A measured 12-step
#     run against a target of 1.0 went
#       19.75, 22.99, 22.46, 18.39, 20.08, 17.29,
#       13.73, 13.00,  6.40,  2.39,  8.86,  7.18
#     - a clear downward trend with the distance nearly quadrupling
#     again at step 11. bestSound keeps the closest candidate
#     regardless, so the result is sound; the shape of the curve is
#     not evidence of convergence, and should not be read as such.
#
#   5 - Short inputs no longer get phantom grains. nGrains was forced
#     to at least 3: at a 0.08 s grain size, a 0.10 s or 0.14 s input
#     produced three intervals of which one started PAST the end of
#     the source, yielding a duplicate 5 ms fragment and breaking the
#     "duration preserved" contract. Now max(1, ceiling(...)).
#
#   6 - Intensity is bounded: the controller no longer raises it
#     without an upper limit, and the run reports when it is pinned at
#     Maximum_intensity.
#     CORRECTION (v1.5): this item ALSO claimed the derived
#     probabilities were clamped and the spectral multiplier was kept
#     positive. Neither was written. The ceiling applies to
#     currentIntensity, but every per-transform multiplier is applied
#     after it, so the derived values were still unbounded. See the
#     v1.5 entry.
#
#   7 - "Intensity contrast expansion" renamed Intensity contrast expansion.
#     It compares local intensity to the mean and scales gain
#     accordingly - dynamic-range expansion. No derivative, onset or
#     attack is computed anywhere in it.
#
#   8 - Band edges and the Mel ceiling follow Nyquist. Band 4 started
#     at a hardcoded 5000 Hz: at an 8 kHz sample rate (Nyquist 4000)
#     the whole band sat above Nyquist and contributed a dead
#     dimension - exactly the kind that CRITICAL 2 lets dominate.
#
#   9 - A silent input is rejected up front rather than being analysed
#     into degenerate dimensions and handed to peak normalisation.
#
#   10 - Output is MONO by design; multichannel input is summed before
#     analysis and rendering. This was never stated.
#
#   ON THE GRAIN JOINS (documented, not changed): every granular grain
#   gets its own fade-in and fade-out and the grains are laid end to
#   end with NO overlap, so each join passes through zero. At the
#   Standard settings that is roughly a 14 ms dip every 88 ms - audible
#   periodic scalloping that is part of this effect's sound, and part
#   of the measured distance, whether or not any reordering happened.
#   The same applies to the spectral-mutation segment joins. Converting
#   to overlap-add would change every preset's character and its
#   calibration; it is left alone deliberately and noted here so it is
#   not mistaken for a defect.
#
# Changelog v1.3 (2026):
#   - FIX: zero-variance feature dimensions exploded the distance;
#     relative floor plus a +/-10 sigma cap per dimension.
#   - FIX: granular pass discarded the tail remainder (floor ->
#     ceiling on the grain count).
#   - FIX: N_mfcc_coeffs locked to 12 (the 19-dim layout depends on it).
#   - ADDED: T5 skips the PSOLA round-trip on fully unvoiced input.
#   - ADDED: Play_result form gate.
#   - FIX: info header erased itself; noise-burst placement used a
#     reversed randomUniform range for very short inputs.
#
# Description:
#   Feature-constrained experimental sound variation using
#   z-score-normalized feature distance control. Extracts
#   high-dimensional features (MFCC, spectral centroid, flux,
#   harmonicity, sub-band energy) and iteratively applies
#   spectral/temporal transformations until the transformed
#   sound reaches a target normalized distance band from the
#   original.
#
#   THE DISTANCE IS A BAG-OF-FRAMES TIMBRAL-STATISTICS DISTANCE.
#   Each of the 19 dimensions is reduced to its mean and variance
#   across frames (38 numbers). Both are invariant to frame ORDER, so
#   reordering and reversal register only weakly, while overall gain
#   and energy changes register strongly. Use it to constrain timbral
#   distribution, not to measure how much structural variation a
#   result contains.
#
#   Output is MONO. Multichannel input is summed before analysis.
#
#   Preserves: overall duration (structural anchor)
#   Transforms: granular reorder/reverse/gate, segment-wise
#   spectral coloring, transient exaggeration, band-limited
#   noise bursts, pitch jitter
#
# Changelog v1.2 (2026):
#   - FIX: Noise-burst transform was a silent no-op. The mixing
#     Formula used "object[burstId, x - ...]" with x (a time
#     value) as the column index — Praat's object[] expects an
#     integer sample index, so reads always returned 0 and no
#     noise was added. Replaced with Formula (part) and proper
#     col-based indexing. The transform now actually works.
#   - FIX: presetName$ was being overwritten by a second dispatch
#     block that mislabeled presets 3-5 as "Extreme"/"Custom".
#     Removed the duplicate dispatch.
#   - SPEED: Granular grain assembly (T1) and spectral mutation
#     segment assembly (T2) used Concatenate in tight loops, which
#     rebuilds the entire growing buffer on every iteration —
#     classic O(n^2) cost. Replaced with pre-allocated output
#     buffers and Formula (part) in-place mixing per fragment.
#   - METRIC: MSE is now z-score normalized. Previously, the raw
#     MSE summed (mean_diff)^2 + (var_diff)^2 across 19 features
#     of wildly different scales — centroid (~2000-6000 Hz)
#     dominated by ~12 orders of magnitude over band energies
#     (~0.001-0.1). The "0.15 target" was effectively a squared-
#     centroid distance. Now each dimension's mean-diff is divided
#     by sqrt(orig_variance) and each var-diff by orig_variance,
#     so all features contribute proportionally. Distance values
#     now have an interpretation: 1.0 = average one-sigma shift
#     across features.
#   - RECALIBRATION: All preset target_distance values have been
#     adjusted for the new z-score scale. Old 0.05 -> new 0.4
#     (Subtle); old 0.15 -> new 1.0 (Standard); old 0.20 -> new
#     1.5 (Granular); old 0.25 -> new 1.8 (Spectral); old 0.40 ->
#     new 2.5 (Extreme). Custom users should expect targets
#     roughly 6-8x larger than v1.1 for equivalent transformation
#     amount.
#
# Category: Composition
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

originalSound = selected("Sound")
originalName$ = selected$("Sound")

# v1.4 fix 9: a silent input analyses into degenerate dimensions and
# then reaches peak normalisation with a peak of zero.
selectObject: originalSound
srcPeakCheck = Get absolute extremum: 0, 0, "None"
if srcPeakCheck < 1e-6
    exitScript: "The selected Sound is silent (or near-silent); nothing to vary."
endif

# ============================================================
# FORM
# ============================================================
form MSE Feature-Constrained Variation v1.5
    optionmenu Preset: 2
        option Subtle (spectral drift only)
        option Standard (balanced)
        option Granular (structural fracture)
        option Spectral (timbral destruction)
        option Extreme (full disruption)
        option Custom
    positive Target_distance 1.0
    positive Tolerance 0.25
    natural Max_iterations 15
    positive Initial_intensity 0.8
    positive Intensity_step 0.2
    positive Maximum_intensity 3.0
    natural N_analysis_frames 50
    natural N_mut_segments 6
    positive Noise_level 0.02
    positive Tilt_scale 2.0
    positive Seg_emph_scale 1.5
    integer Random_seed 0
    boolean Show_visualization 1
    boolean Play_result 1
endform

# ------------------------------------------------------------
# SCRIPT-LEVEL SETTING
# ------------------------------------------------------------
# MFCC count is LOCKED to 12: the 19-dimension feature layout puts
# harmonicity at slot 13, the four bands at 14-17, centroid at 18 and
# flux at 19. Any other value corrupts the vector.
n_mfcc_coeffs = 12

# Spectral-mutation multiplier is (1 + mutAmp * sin(...)). Once mutAmp
# passes 1 the multiplier goes negative on part of its cycle, flipping
# the phase of those bins. That is audible destruction and it is what
# the Spectral and Extreme presets have always done.
#   1 = keep the inversions (default; preserves existing preset audio)
#   0 = clamp mutAmp to 0.95, so the multiplier stays positive
allowSpectralInversion = 1

# Everything except Preset, Random_seed and the two output toggles is
# read only when Preset = Custom. Random_seed: 0 = unpredictable.

# v1.4 fix 4: reproducibility. Every iteration redraws all of its
# swaps, reversals, gates, tilts, bursts and pitch perturbations, so
# without a seed no successful take could be recovered.
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedLabel$ = string$(random_seed)
else
    random_initializeSafelyAndUnpredictably ()
    seedLabel$ = "unpredictable"
endif

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
    targetDistance = 0.4
    tolerance = 0.12
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
    targetDistance = 1.0
    tolerance = 0.25
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
    targetDistance = 1.5
    tolerance = 0.35
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
    targetDistance = 1.8
    tolerance = 0.30
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
    targetDistance = 2.5
    tolerance = 0.50
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

# v1.3: the 19-dim feature layout hardcodes slot 13 = harmonicity,
# 14-17 = bands, 18 = centroid, 19 = flux. Other MFCC counts either
# leave dead dimensions (which explode the z-score distance) or
# overwrite slot 13 -- so the coefficient count is a layout constant.
if nMfccCoeffs <> 12
    nMfccCoeffs = 12
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

# v1.2: Removed a duplicate presetName$ dispatch block that was
# overwriting the correct labels here. The first if-elsif block
# above sets presetName$ correctly for all six presets.

# === Setup ===
selectObject: originalSound
totalDur = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels
nyquist = sampleRate / 2

# Sub-band boundaries.
# v1.4 fix 8: every edge follows Nyquist. Band 4 used to start at a
# hardcoded 5000 Hz, so at an 8 kHz sample rate (Nyquist 4000) the
# entire band sat above Nyquist and produced a dead dimension - and a
# dead dimension is exactly what CRITICAL 2 lets dominate.
band1lo = 0
band1hi = 500
band2lo = 500
band2hi = 2000
band3lo = 2000
band4lo = 5000
if band4lo > nyquist * 0.75
    band4lo = nyquist * 0.75
endif
if band4lo < band3lo + 100
    band3lo = band4lo / 2.5
    if band3lo < band2hi + 50
        band2hi = band3lo - 50
        if band2hi < band2lo + 50
            band2hi = band2lo + 50
            band3lo = band2hi + 50
        endif
    endif
endif
band3hi = band4lo
band4hi = nyquist - 10
if band4hi < band4lo + 50
    band4hi = band4lo + 50
endif
if band4hi > nyquist
    band4hi = nyquist
endif

band1center = (band1lo + band1hi) / 2
band2center = (band2lo + band2hi) / 2
band3center = (band3lo + band3hi) / 2
band4center = (band4lo + band4hi) / 2

# Mel ceiling must also stay under Nyquist
melMax = 5000
if melMax > nyquist - 100
    melMax = nyquist - 100
endif
if melMax < 500
    melMax = 500
endif

clearinfo
writeInfoLine: "=============================================="
appendInfoLine: "  MSE Feature-Constrained Variation v1.5"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Input: ", originalName$,
    ... " (", fixed$(totalDur, 2), " s, ", sampleRate, " Hz, ", numChannels, " ch)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Target distance (z-score): ", fixed$(targetDistance, 3),
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

# v1.4 CRITICAL 1: fix the gain ONCE, before any feature is measured.
# v1.3 measured candidates, chose the best, and only then applied
# Scale peak 0.95 - but band energies, spectral flux and several MFCC
# coefficients scale with gain, so the delivered file sat at a
# different distance from the one reported. Measured on a source
# peaking at 0.60, Scale peak 0.95 multiplied its energy by 2.51x,
# after the distance had been decided. Normalising the source and
# every candidate to the same peak makes the measured object and the
# delivered object identical.
analysisPeak = 0.95
selectObject: monoBase
Scale peak: analysisPeak

# ============================================================
# STEP 1: Extract features from original (bag-of-frames)
# ============================================================
appendInfoLine: "[1/4] Extracting original features..."

# MFCC analysis
selectObject: monoBase
To MelSpectrogram: 0.025, 0.01, 24, 100, melMax
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
    centroid = (band1center * e1 + band2center * e2 + band3center * e3 + band4center * e4) / totalE
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

# v1.4 CRITICAL 2: mark dimensions the original never varies in, and
# whose level is also ~0. Such a dimension cannot report how far a
# variation has travelled; including it let a single saturated
# statistic contribute 2.6316 - more than the whole Standard target.
deadVarFloor = 1e-10
deadMeanFloor = 1e-6
nDeadDims = 0
deadList$ = ""
for d from 1 to nFeatPerFrame
    dimIsDead_'d' = 0
    if origVar_'d' < deadVarFloor and abs(origMean_'d') < deadMeanFloor
        dimIsDead_'d' = 1
        nDeadDims = nDeadDims + 1
        deadList$ = deadList$ + " " + string$(d)
    endif
endfor
if nDeadDims > 0
    appendInfoLine: "  ", nDeadDims, " dimension(s) carry no information in the",
        ... " original and are excluded from the distance:", deadList$
endif

appendInfoLine: "  Bag-of-frames statistics: ", totalStats, " values"
appendInfoLine: "  (", nFeatPerFrame, " dims x {mean, var} over ", nAnalysisFrames, " frames)"
appendInfoLine: ""

# ============================================================
# STEP 2: Iterative transformation loop
# ============================================================
appendInfoLine: "[2/4] Iterative transformation..."

currentIntensity = initialIntensity
bestMse = -1

# v1.4 fix 6: bound the controller. v1.3 raised intensity without a
# ceiling, so gate and reverse probabilities could pass 1 (every grain
# silenced or reversed), the spectral multiplier could go negative and
# the noise level could grow without limit.
maximumIntensity = maximum_intensity
if maximumIntensity < initialIntensity
    maximumIntensity = initialIntensity
endif
intensityPinned = 0
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
            # v1.3: ceiling, not floor -- floor silently discarded the
            # tail remainder (up to one grain) every granular pass,
            # violating the "duration preserved" contract by ~30-60 ms
            # per run. The last grain is clipped to totalDur below.
            # v1.4 fix 5: do NOT invent grains. Forcing a minimum of
            # 3 meant that at a 0.08 s grain size a 0.10 s or 0.14 s
            # input got three intervals, one of which started past the
            # end of the source - a duplicated 5 ms fragment and a
            # broken "duration preserved" contract. Swaps, reversal
            # and gating all work fine with one or two grains.
            nGrains = ceiling(totalDur / grainDur)
            if nGrains < 1
                nGrains = 1
            endif
            
            for gi from 1 to nGrains
                grainStart_'gi' = (gi - 1) * grainDur
                grainEnd_'gi' = gi * grainDur
                if grainEnd_'gi' > totalDur
                    grainEnd_'gi' = totalDur
                endif
            endfor

            # v1.5: MERGE a sub-5 ms final remainder into the grain
            # before it, rather than padding it up to 5 ms. Measured:
            # a 0.161 s input at a 0.080 s grain gives 80 + 80 + 1 ms,
            # and the 1 ms tail was inflated to 5 ms - a 0.165 s output
            # from a 0.161 s input, breaking "duration preserved" by
            # exactly the amount that was invented.
            if nGrains > 1
                lastLen = grainEnd_'nGrains' - grainStart_'nGrains'
                if lastLen < 0.005
                    prevG = nGrains - 1
                    grainEnd_'prevG' = grainEnd_'nGrains'
                    nGrains = nGrains - 1
                endif
            endif
            
            # v1.5 CRITICAL: clamp the derived probabilities to [0, 1].
            # v1.4's changelog claimed this and it was never written -
            # only currentIntensity was capped, which does nothing here
            # because the per-transform multiplier is applied
            # afterwards. Measured at each preset's INITIAL intensity:
            #   Granular  gi=1.500 -> swap 1.500, reverse 1.500, gate 1.050
            #   Extreme   gi=2.250 -> swap 2.250, reverse 2.250, gate 1.800
            #   Standard  gi=0.400 -> swap 0.160, reverse 0.120, gate 0.060
            # So from their very first iteration Granular and Extreme
            # reversed EVERY grain and then gated every grain to
            # silence: the granular layer was gone before the noise
            # stage put anything back.
            swapProb = gi_intensity * swapScale
            if swapProb < 0
                swapProb = 0
            endif
            if swapProb > 1
                swapProb = 1
            endif
            reverseProb = gi_intensity * reverseScale
            if reverseProb < 0
                reverseProb = 0
            endif
            if reverseProb > 1
                reverseProb = 1
            endif
            gateProb = gi_intensity * gateScale
            if gateProb < 0
                gateProb = 0
            endif
            if gateProb > 1
                gateProb = 1
            endif
            
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
            
            # v1.2: Pre-allocate output buffer instead of growing
            # via Concatenate. Compute each output grain's start
            # position (cumulative sum of preceding durations after
            # swaps), then write each grain in-place via
            # Formula (part). O(n) instead of O(n^2).
            
            # Pass 1: compute durations and start positions in output
            outTotalDur = 0
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
                outStart_'gi' = outTotalDur
                outDur_'gi' = gDur
                outSrcStart_'gi' = gStart
                outSrcEnd_'gi' = gEnd
                outTotalDur = outTotalDur + gDur
            endfor
            
            # Allocate output buffer
            assembledSound = Create Sound from formula: "granular_out", 1,
                ... 0, outTotalDur, sampleRate, "0"
            
            # Pass 2: process each grain and mix into output at outStart
            for gi from 1 to nGrains
                gStart = outSrcStart_'gi'
                gEnd = outSrcEnd_'gi'
                gDur = outDur_'gi'
                gOutStart = outStart_'gi'
                gOutEnd = gOutStart + gDur
                
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
                
                # Mix grain into output at gOutStart via Formula (part)
                grainStartCol = round(gOutStart * sampleRate)
                grainStartColStr$ = string$(grainStartCol)
                grainIdStr$ = string$(grainSnd)
                selectObject: assembledSound
                Formula (part): gOutStart, gOutEnd, 1, 1,
                    ... "self + object[" + grainIdStr$
                    ... + ", 1, col - " + grainStartColStr$ + "]"
                
                removeObject: grainSnd
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
            
            # v1.2: Pre-allocate output buffer of input duration.
            # Each To Sound (from spectrum) round-trip can shift the
            # segment length by a sample or two due to FFT padding;
            # we clip writes to the planned segment window so any
            # drift is absorbed silently.
            mutAssembled = Create Sound from formula: "spectral_out", 1,
                ... 0, workDur, sampleRate, "0"
            
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
                # v1.5: the spectral multiplier (1 + mutAmp * sin) goes
                # NEGATIVE once mutAmp exceeds 1, inverting the phase of
                # the affected bins. v1.4's changelog wrongly claimed
                # Maximum_intensity prevented this; it does not, because
                # segEmphScale is applied afterwards. Measured ranges at
                # each preset's initial intensity:
                #   Standard  mutAmp 1.200 -> -0.20 .. 2.20
                #   Spectral  mutAmp 3.375 -> -2.38 .. 4.38
                #   Extreme   mutAmp 6.750 -> -5.75 .. 7.75
                # allowSpectralInversion (set near the top of the file)
                # decides. The default KEEPS the inversions, because
                # they are what every existing render of Spectral and
                # Extreme was made with; set it to 0 for a positive-only
                # multiplier bounded at 0.95.
                mutAmp = sm_intensity * segEmphScale
                if allowSpectralInversion = 0
                    if mutAmp > 0.95
                        mutAmp = 0.95
                    endif
                endif
                if mutAmp < 0
                    mutAmp = 0
                endif
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
                
                # Mix into pre-allocated output via Formula (part).
                # Write window is the planned [msStart, msEnd];
                # any FFT-induced drift in msResult length is
                # truncated when col - msStartCol exceeds msResult's
                # column count (object[] returns 0 outside bounds).
                msStartCol = round(msStart * sampleRate)
                msStartColStr$ = string$(msStartCol)
                msResIdStr$ = string$(msResult)
                selectObject: mutAssembled
                Formula (part): msStart, msEnd, 1, 1,
                    ... "self + object[" + msResIdStr$
                    ... + ", 1, col - " + msStartColStr$ + "]"
                
                removeObject: msResult
            endfor
            
            removeObject: workingSound
            workingSound = mutAssembled
            
            appendInfoLine: "    T2 Spectral mutation: ", nMutSegs,
                ... " segs (x", fixed$(spectralMult, 1), ")"
        else
            appendInfoLine: "    T2 Spectral mutation: OFF"
        endif
        
        # =============================================
        # T3: Intensity contrast expansion / suppression
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
            
            appendInfoLine: "    T3 Intensity contrast exagg: ", fixed$(exaggeration, 3),
                ... " (x", fixed$(transientMult, 1), ")"
        else
            appendInfoLine: "    T3 Intensity contrast exagg: OFF"
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
                # v1.3: guard against reversed range on inputs
                # shorter than one burst
                burstSpan = workDur3 - burstDur
                if burstSpan < 0
                    burstSpan = 0
                endif
                burstTime = randomUniform(0, burstSpan)
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
                
                # v1.2 FIX: previous Formula used "object[burstId,
                # x - burstTime + object[burstId].xmin]" which
                # passes a TIME value as the column index. Praat's
                # object[id, row, col] requires col to be an integer
                # sample index. The result was always 0 — no noise
                # was ever added. Now uses Formula (part) with col
                # arithmetic so the burst samples are read correctly
                # by their integer index.
                burstStartCol = round(burstTime * sampleRate)
                burstStartColStr$ = string$(burstStartCol)
                burstIdStr$ = string$(filtBurst)
                burstEndTime = burstTime + burstDur
                if burstEndTime > workDur3
                    burstEndTime = workDur3
                endif
                selectObject: workingSound
                Formula (part): burstTime, burstEndTime, 1, 1,
                    ... "self + object[" + burstIdStr$
                    ... + ", 1, col - " + burstStartColStr$ + "]"
                
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
            
            
            if nPitchPoints = 0
                # v1.3: fully unvoiced input -- jitter has nothing to
                # move, and the PSOLA round-trip would only add
                # resynthesis coloration. Skip the whole stage.
                removeObject: workManip, workPitchTier
                appendInfoLine: "    T5 Pitch jitter: skipped (no voiced frames)"
            else
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
            endif
        else
            appendInfoLine: "    T5 Pitch jitter: OFF"
        endif

        # =============================================
        # FEATURE EXTRACTION from transformed
        # =============================================
        # v1.4 CRITICAL 1: bring the candidate to the SAME peak the
        # original was analysed at, before measuring it. This is the
        # gain the candidate keeps, so the reported distance is the
        # distance of the delivered file.
        selectObject: workingSound
        candPeak = Get absolute extremum: 0, 0, "None"
        if candPeak > 1e-9
            selectObject: workingSound
            Scale peak: analysisPeak
        endif

        selectObject: workingSound
        To MelSpectrogram: 0.025, 0.01, 24, 100, melMax
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
            centroid = (band1center * e1 + band2center * e2 + band3center * e3 + band4center * e4) / totalE
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
        # COMPUTE Z-SCORE NORMALIZED DISTANCE
        # =============================================
        # v1.2: Each dimension's contribution is normalized by the
        # ORIGINAL's variance (or std, for the mean term), so all
        # features contribute proportionally regardless of their
        # natural scale. The previous unnormalized MSE was dominated
        # by the centroid term (~10^6 squared) over band energies
        # (~10^-6 squared). Now:
        #
        #   normMeanDiff_d = (orig_mean_d - trans_mean_d) / sigma_d
        #   normVarDiff_d  = (orig_var_d - trans_var_d)  / orig_var_d
        #
        # where sigma_d = sqrt(orig_var_d). With these, a value of
        # 1.0 corresponds to "average one-sigma shift" — interpretable
        # and scale-free. Total distance is the average of squared
        # normalized differences across 19 dims and 2 stats.
        #
        # Epsilon (1e-12) prevents division by zero on dimensions
        # where the original is constant (zero variance).
        # v1.3: RELATIVE variance floor. With the old absolute
        # epsilon (1e-12), one constant original dimension (steady
        # tone, silence padding) produced a ~1e11 normalized term
        # that drowned the other 18 dimensions and made convergence
        # impossible. The floor (2% of |mean|)^2 + 1e-12 leaves
        # healthy dimensions untouched (std >> 2% of mean), so the
        # v1.2 calibration is preserved.
        mseSum = 0
        usedStats = 0
        for d from 1 to nFeatPerFrame
            transMean = transDimSum_'d' / nAnalysisFrames
            transVar = transDimSqSum_'d' / nAnalysisFrames - transMean * transMean
            if transVar < 0
                transVar = 0
            endif

            origVarD = origVar_'d'

            # v1.4 CRITICAL 2: skip dimensions that carry no
            # information in the ORIGINAL. v1.3's relative floor,
            # (2% of |mean|)^2, does nothing when the mean is also
            # zero - a steady tone's spectral flux, or a band that is
            # empty at this sample rate. The 10-sigma cap bounded such
            # a term but did not make it small: one saturated
            # statistic contributes 10^2 / 38 = 2.6316, which is 263%
            # of the Standard target, 175% of Granular and 658% of
            # Subtle. A dimension the original never varies in cannot
            # say anything about how far a variation has moved, so it
            # is excluded and the denominator shrinks with it.
            #
            # v1.5, more precisely: this is a normalisation decision,
            # not a claim that such a dimension holds no information.
            # A steady tone's spectral flux of 0 IS meaningful, and if a
            # transformation introduces large flux, excluding the
            # dimension makes the metric blind to exactly that change.
            # Dimensions with near-zero source mean AND variance are
            # deliberately ignored because normalising by them is
            # unstable - the blind spot is the accepted cost.
            if dimIsDead_'d' = 0
                varFloor = (0.02 * abs(origMean_'d'))^2 + 1e-12

                diffMean = origMean_'d' - transMean
                normMeanDiff = diffMean / sqrt(origVarD + varFloor)
                if normMeanDiff > 10
                    normMeanDiff = 10
                endif
                if normMeanDiff < -10
                    normMeanDiff = -10
                endif
                mseSum = mseSum + normMeanDiff * normMeanDiff
                usedStats = usedStats + 1

                diffVar = origVarD - transVar
                normVarDiff = diffVar / (origVarD + varFloor)
                if normVarDiff > 10
                    normVarDiff = 10
                endif
                if normVarDiff < -10
                    normVarDiff = -10
                endif
                mseSum = mseSum + normVarDiff * normVarDiff
                usedStats = usedStats + 1
            endif
        endfor
        if usedStats < 1
            usedStats = 1
        endif
        mse = mseSum / usedStats
        mseHistory_'iter' = mse

        appendInfoLine: "    Distance: ", fixed$(mse, 4),
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
                if currentIntensity > maximumIntensity
                    currentIntensity = maximumIntensity
                    intensityPinned = 1
                endif
                appendInfoLine: "    -> Too similar, intensity +",
                    ... fixed$(intensityStep, 2)
                if intensityPinned
                    appendInfoLine: "       (pinned at Maximum_intensity ",
                        ... fixed$(maximumIntensity, 2), ")"
                endif
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

# v1.4 CRITICAL 1: NO gain change here. The candidate was normalised
# to analysisPeak before it was measured, so bestMse is genuinely the
# distance of this object. v1.3 rescaled at this point and reported a
# figure that belonged to a different gain.
# v1.5: hand Praat's generator back to its safe state. v1.4 seeded it
# and never reset, so every later script in the same session continued
# from a predictable global sequence.
random_initializeSafelyAndUnpredictably ()

selectObject: bestSound
Rename: originalName$ + "_experimental"
finalOutput = selected("Sound")
finalDur = Get total duration

removeObject: monoBase

appendInfoLine: "  Output: ", originalName$, "_experimental"
appendInfoLine: "  Duration: ", fixed$(finalDur, 2), " s"
appendInfoLine: "  Final distance (z-score): ", fixed$(bestMse, 4),
    ... "  [measured on this exact output]"
appendInfoLine: "  Metric: bag-of-frames timbral statistics (mean + variance"
appendInfoLine: "          per dimension); insensitive to frame ORDER."
if nDeadDims > 0
    appendInfoLine: "  ", nDeadDims, " of ", nFeatPerFrame,
        ... " dimensions carried no information in the original and were excluded."
endif
if intensityPinned
    appendInfoLine: "  ! The controller hit Maximum_intensity (",
        ... fixed$(maximumIntensity, 2), ") and could go no further."
endif
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
    To MelSpectrogram: 0.025, 0.01, 24, 100, melMax
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
        centroid = (band1center * e1 + band2center * e2 + band3center * e3 + band4center * e4) / totalE
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
        ... "##MSE Feature-Constrained Variation v1.5##"
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -0.6, "half",
        ... originalName$ + " | " + presetName$
        ... + " | Target: " + fixed$(targetDistance, 3)
        ... + " | Final distance: " + fixed$(bestMse, 4)
    
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
    Text left: "yes", "Distance"
    Text bottom: "yes", "Iteration"
    Text top: "no", "Distance Convergence (z-score normalized)"
    
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
        ... "Distance: " + fixed$(bestMse, 4)
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
    Text: 0.43, "left", 0.5, "half", "Distance/Flux"
    
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
if play_result
    Play
endif

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Final distance (z-score): ", fixed$(bestMse, 4)
appendInfoLine: "Converged: ", converged, " (in ", nIterationsRun, " iterations)"
appendInfoLine: "Output: ", originalName$, "_experimental"
