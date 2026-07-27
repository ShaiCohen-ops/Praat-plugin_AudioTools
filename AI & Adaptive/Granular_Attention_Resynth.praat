# ============================================================
# Praat AudioTools - Granular_Attention_Resynth.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 2.0 (2026) - True Hann OLA, gated softmax, live time jitter
# License: MIT License
#
# Changelog v2.0:
#
#   NOTE: audio is NOT comparable to v1.1. The synthesis architecture,
#   the selection distribution and the transient score all changed.
#
#   CRITICAL 1 - the ReLU gate did almost nothing.
#     Rejected grains were set to 0 and then fed to softmax anyway, and
#     exp(0) is not 0. Worked example, verified numerically: one active
#     grain at score 1, ninety-nine rejected at 0, meanScore 0.5,
#     alpha 1 -> active weight 1.000, each rejected 0.135, rejected
#     total 13.398. The suppressed grains carried 93.05% of the
#     probability mass. v2.0 computes softmax over ACTIVE grains only;
#     rejected grains get exactly zero probability. If nothing passes
#     the floor, only the single highest-scoring grain is activated
#     (v1.1 re-opened the gate completely, so Floor_dB = +6 could turn
#     into no floor at all).
#
#   CRITICAL 2 - the synthesis was not the Hann OLA this header claimed.
#     Each grain was extracted with a full Hann window baked into its
#     samples (verified: centre 0.500, edge 0.00049), and then
#     Concatenate with overlap applied its own Hann crossfade over the
#     same region. Measured on two 0.2 s Hann grains at 0.1 s overlap:
#     the source level was 0.5, the grain peak read 0.500, and the join
#     centre read 0.250 - a 6 dB dip at every single join, repeating at
#     the hop rate. There was no envelope accumulation and no division
#     by it anywhere in v1.1, despite the pipeline note above.
#     v2.0 implements the documented architecture: rectangular grain ->
#     one Hann window -> add into an output buffer at its true time ->
#     accumulate the same Hann into an envelope buffer -> divide by the
#     accumulated envelope. Overlaps beyond 2 grains now sum correctly,
#     which the pairwise crossfade could never do.
#
#   CRITICAL 3 - Time_jitter_ms was a dead parameter.
#     timeJitter was computed and then never read again. Self-Remix
#     (8 ms), Slabs (15 ms) and Cloud (30 ms) all sounded exactly as
#     they would at 0 ms. Buffer OLA makes it implementable, so it is
#     now real output-position jitter around the nominal hop.
#
#   4 - Sources shorter than the grain broke the candidate math.
#     With srcDur 50 ms, grainDur 150 ms, candHop 100 ms:
#     floor((0.05 - 0.15) / 0.1) + 1 = 0, forced to 2, and candidate 2
#     got tStart 0.100 with tEnd 0.050 - a start later than its end.
#     overlapDur was still 75 ms against a real grain of at most 50 ms.
#     v2.0 clamps the grain to the source length first and allows a
#     single candidate.
#
#   5 - Transient mode scored decays as loudly as attacks. It used the
#     absolute energy difference, so note endings competed with note
#     beginnings while the form promised "attacks/onsets repeat".
#     Score_type now distinguishes Onsets (positive slope only) from
#     Energy edges (absolute slope, the old behaviour, honestly named).
#
#   6 - Scores are now measured on the windowed grain that is actually
#     rendered. v1.1 scored a rectangular extraction but played a Hann
#     one, so an event near a grain edge could win the competition and
#     then be almost entirely windowed away.
#
#   7 - Dry is now the unmodified source level. v1.1 took the dry copy
#     from the peak-normalized mono working sound, so Wet_percent = 0
#     did not return the input. NOTE: output is MONO by design; a
#     stereo input is summed. This was never stated before.
#
#   8 - Random_seed added (0 = unpredictable), and the generator is
#     returned to its safe state once synthesis is done.
#
#   9 - Temperature renamed Attention_sharpness_alpha. The formula is
#     exp(score * T), so a higher value SHARPENED the distribution,
#     which is the inverse of the usual softmax(z / T) convention.
#     The name now matches the behaviour and the alpha in these notes.
#
#   10 - Pitch jitter is varispeed and is now labelled as such. It is
#     applied BEFORE windowing, so the Hann envelope is no longer
#     truncated when a downward shift lengthens the grain. Grains no
#     longer need identical lengths, because OLA places each one at its
#     own position instead of relying on a uniform concatenation hop.
#
#   11 - A short fade is applied to the wet path after the trim to
#     source length, since the cut can land mid-grain at a non-zero
#     amplitude.
#
#   12 - Hop count is capped with a warning. v1.1 allowed a 1 ms hop
#     over a ten-minute source, which meant roughly 600,000 Sound
#     objects alive before concatenation. Buffer OLA keeps only one
#     grain object alive at a time, but the cap still guards run time.
#
#   13 - Removed the unused cdf# array (drawGrain always rebuilt its own
#     penalized distribution) and fixed two visualization panels that
#     still read "v1.0".
#
# Description:
#   Granular Attention Re-synthesis - grains compete for
#   being chosen (selection), not for gain.
#
#   CONCEPT:
#   ReLU + Softmax applied to GRAIN SELECTION, not filtering.
#   The source re-synthesizes itself from its own most
#   energetic (or most transient) moments. At high alpha
#   this becomes motif extraction / crystallized stutter.
#   At low alpha it becomes a textural self-remix.
#
#   PIPELINE:
#   1. Extract N candidate grains (sliding window, candHop),
#      Hann-window each one, and score it by RMS power,
#      onset slope, energy-edge slope, or a mix
#   2. ReLU gate: grains below (meanScore + floor_dB) are removed
#      from the competition entirely
#   3. Softmax over the SURVIVING grains only:
#        w[i]    = exp((gated[i] - maxGated) / meanScore * alpha)
#        prob[i] = w[i] / sum(w)   (rejected grains: prob = 0)
#   4. Synthesis: for each output hop position:
#        - draw a grain by inverse-transform sampling
#        - recency penalty: last 3 grains less likely to repeat
#        - optional varispeed pitch jitter (resample +/- semitones)
#        - apply one Hann window
#        - place at hop position +/- time jitter:
#            outBuf += grain          (Formula (part), region-limited)
#            envBuf += the same Hann window
#   5. Divide outBuf by the accumulated envelope (true OLA)
#   6. Trim to source length, fade, wet/dry blend
#
#   SCORE TYPES:
#   RMS          - energy competition: loudest grains repeat
#   Onsets       - positive slope only: attacks repeat
#   Energy edges - absolute slope: attacks AND decays repeat
#   Mixed        - weighted blend: control transient_weight
#
#   OUTPUT IS MONO. Stereo and multichannel input is summed to mono.
#
#   MUSICAL EFFECTS BY alpha:
#   alpha 1-3:  gentle self-remix, all grains roughly equally chosen
#   alpha 5-10: energetic moments dominate, texture crystallizes
#   alpha 15+:  winner-take-most: a few grains repeat obsessively
#               -> motif extraction, stutter loops, self-quotation
#
# Category: Granular / Composition / Experimental
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

srcID    = selected("Sound")
srcName$ = selected$("Sound")
selectObject: srcID
srcDur = Get total duration
srcSr  = Get sampling frequency
srcCh  = Get number of channels

if srcDur < 0.05
    exitScript: "Sound must be at least 50 ms."
endif

# ============================================================
# FORM
# ============================================================

form Granular Attention Re-synthesis v2.0
    optionmenu Preset: 1
        option Custom
        option Self-Remix      (gentle, textural, most grains used)
        option Crystallize     (high alpha, dense repeats, few grains)
        option Motif Extract   (very high alpha, stutter of strongest)
        option Onset Harvest   (onset score, attacks repeat)
        option Shimmer         (small grains, light jitter, low alpha)
        option Slabs           (large grains 300ms, slow mosaic)
        option Cloud           (very large grains 600ms, drifting layers)
    positive Grain_size_ms 150.0
    positive Synthesis_hop_ms 50.0
    positive Candidate_hop_ms 20.0
    positive Attention_sharpness_alpha 1.0
    real Floor_dB 0.0
    optionmenu Score_type: 1
        option RMS            (energy: loudest grains repeat)
        option Onsets         (positive slope: attacks repeat)
        option Energy edges   (absolute slope: attacks and decays)
        option Mixed          (blend of RMS and slope)
    real Transient_weight 0.5
    positive Time_jitter_ms 5.0
    real Pitch_jitter_semitones 0.0
    real Recency_penalty 0.5
    real Wet_percent 100.0
    integer Random_seed 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform



# ============================================================
# PRESETS
# ============================================================

presetName$ = "Custom"

if preset = 2
    grain_size_ms           = 60.0
    synthesis_hop_ms        = 30.0
    candidate_hop_ms        = 20.0
    attention_sharpness_alpha = 3.0
    floor_dB                = -3.0
    score_type              = 1
    transient_weight        = 0.3
    time_jitter_ms          = 8.0
    pitch_jitter_semitones  = 0.0
    recency_penalty         = 0.3
    wet_percent             = 100.0
    presetName$             = "SelfRemix"
elsif preset = 3
    grain_size_ms           = 40.0
    synthesis_hop_ms        = 20.0
    candidate_hop_ms        = 15.0
    attention_sharpness_alpha = 12.0
    floor_dB                = 3.0
    score_type              = 1
    transient_weight        = 0.2
    time_jitter_ms          = 3.0
    pitch_jitter_semitones  = 0.0
    recency_penalty         = 0.4
    wet_percent             = 100.0
    presetName$             = "Crystallize"
elsif preset = 4
    grain_size_ms           = 30.0
    synthesis_hop_ms        = 15.0
    candidate_hop_ms        = 10.0
    attention_sharpness_alpha = 25.0
    floor_dB                = 6.0
    score_type              = 1
    transient_weight        = 0.0
    time_jitter_ms          = 1.0
    pitch_jitter_semitones  = 0.0
    recency_penalty         = 0.6
    wet_percent             = 100.0
    presetName$             = "MotifExtract"
elsif preset = 5
    grain_size_ms           = 50.0
    synthesis_hop_ms        = 25.0
    candidate_hop_ms        = 15.0
    attention_sharpness_alpha = 8.0
    floor_dB                = 2.0
    score_type              = 2
    transient_weight        = 1.0
    time_jitter_ms          = 5.0
    pitch_jitter_semitones  = 0.0
    recency_penalty         = 0.4
    wet_percent             = 100.0
    presetName$             = "OnsetHarvest"
elsif preset = 6
    grain_size_ms           = 20.0
    synthesis_hop_ms        = 10.0
    candidate_hop_ms        = 10.0
    attention_sharpness_alpha = 2.0
    floor_dB                = -6.0
    score_type              = 1
    transient_weight        = 0.2
    time_jitter_ms          = 4.0
    pitch_jitter_semitones  = 0.3
    recency_penalty         = 0.2
    wet_percent             = 85.0
    presetName$             = "Shimmer"
elsif preset = 7
    grain_size_ms           = 300.0
    synthesis_hop_ms        = 150.0
    candidate_hop_ms        = 50.0
    attention_sharpness_alpha = 10.0
    floor_dB                = 2.0
    score_type              = 1
    transient_weight        = 0.0
    time_jitter_ms          = 15.0
    pitch_jitter_semitones  = 0.0
    recency_penalty         = 0.5
    wet_percent             = 100.0
    presetName$             = "Slabs"
elsif preset = 8
    grain_size_ms           = 600.0
    synthesis_hop_ms        = 300.0
    candidate_hop_ms        = 80.0
    attention_sharpness_alpha = 4.0
    floor_dB                = -3.0
    score_type              = 4
    transient_weight        = 0.4
    time_jitter_ms          = 30.0
    pitch_jitter_semitones  = 0.0
    recency_penalty         = 0.3
    wet_percent             = 90.0
    presetName$             = "Cloud"
endif

# ============================================================
# CLAMPS + DERIVED PARAMETERS
# ============================================================

if grain_size_ms < 5.0
    grain_size_ms = 5.0
endif
if grain_size_ms > 1000.0
    grain_size_ms = 1000.0
endif
if synthesis_hop_ms < 1.0
    synthesis_hop_ms = 1.0
endif
# Enforce overlap: hop should be <= grain/2 for stable Hann OLA
if synthesis_hop_ms > grain_size_ms / 2
    synthesis_hop_ms = grain_size_ms / 2
endif
if candidate_hop_ms < 1.0
    candidate_hop_ms = 1.0
endif
# alpha is the sharpness of the attention distribution: higher = more
# concentrated on the winners. v1.1 called this Temperature, which reads
# backwards for a softmax (softmax(z/T) flattens as T rises). Resolved
# here, AFTER the presets have had their say.
temperature = attention_sharpness_alpha
if temperature < 0.01
    temperature = 0.01
endif
if transient_weight < 0.0
    transient_weight = 0.0
endif
if transient_weight > 1.0
    transient_weight = 1.0
endif
if time_jitter_ms < 0.0
    time_jitter_ms = 0.0
endif
if pitch_jitter_semitones < 0.0
    pitch_jitter_semitones = 0.0
endif
if pitch_jitter_semitones > 4.0
    pitch_jitter_semitones = 4.0
endif
if recency_penalty < 0.0
    recency_penalty = 0.0
endif
if recency_penalty > 1.0
    recency_penalty = 1.0
endif
if wet_percent < 0.0
    wet_percent = 0.0
endif
if wet_percent > 100.0
    wet_percent = 100.0
endif

grainDur    = grain_size_ms    / 1000.0
synthHop    = synthesis_hop_ms / 1000.0
candHop     = candidate_hop_ms / 1000.0
timeJitter  = time_jitter_ms   / 1000.0
wetLevel    = wet_percent / 100.0
dryLevel    = 1.0 - wetLevel

warnLines$ = ""

# v2.0 fix 4: a grain cannot be longer than the source. v1.1 left
# grainDur alone here, so with srcDur 50 ms / grainDur 150 ms /
# candHop 100 ms the candidate count came out as
# floor((0.05 - 0.15) / 0.1) + 1 = 0, was forced up to 2, and the
# second candidate got tStart 0.100 against tEnd 0.050 - a start later
# than its own end. overlapDur stayed at 75 ms for a grain that could
# never exceed 50 ms.
if grainDur > srcDur
    warnLines$ = warnLines$ + "  ! Grain (" + fixed$(grainDur * 1000, 1) +
        ... " ms) longer than source -> clamped to " +
        ... fixed$(srcDur * 1000, 1) + " ms" + newline$
    grainDur = srcDur
endif

# Re-apply the overlap rule against the clamped grain.
if synthHop > grainDur / 2
    synthHop = grainDur / 2
endif
if synthHop < 0.001
    synthHop = 0.001
endif
if candHop > grainDur
    candHop = grainDur
endif

# Time jitter must not be able to push a grain a whole hop out of place.
if timeJitter > synthHop
    timeJitter = synthHop
    warnLines$ = warnLines$ + "  ! Time_jitter capped to one hop (" +
        ... fixed$(timeJitter * 1000, 1) + " ms)" + newline$
endif

# v2.0 fix 12: guard run time. v1.1 permitted a 1 ms hop across a
# ten-minute source, i.e. roughly 600,000 Sound objects held alive
# before its single concatenation. Buffer OLA keeps one grain object
# alive at a time, but the loop cost still needs a ceiling.
maxHops = 20000
projectedHops = floor(srcDur / synthHop) + 1
if projectedHops > maxHops
    synthHop = srcDur / (maxHops - 1)
    warnLines$ = warnLines$ + "  ! " + string$(projectedHops) +
        ... " hops requested; hop raised to " + fixed$(synthHop * 1000, 2) +
        ... " ms to stay under " + string$(maxHops) + newline$
endif

# v2.0 fix 8: reproducibility. v1.1 had no seed at all.
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedLabel$ = string$(random_seed)
else
    random_initializeSafelyAndUnpredictably ()
    seedLabel$ = "unpredictable"
endif

# ============================================================
# PREPARE MONO
# ============================================================

clearinfo
writeInfoLine:  "=================================================="
writeInfoLine:  "  Granular Attention Re-synthesis v2.0"
writeInfoLine:  "=================================================="
appendInfoLine: ""
appendInfoLine: "Source   : ", srcName$, "  (", fixed$(srcDur, 3), " s)"
appendInfoLine: "Preset   : ", presetName$
appendInfoLine: "Grain    : ", fixed$(grain_size_ms, 1), " ms  hop: ", fixed$(synthesis_hop_ms, 1), " ms"
appendInfoLine: "Alpha    : ", fixed$(temperature, 2), " (attention sharpness)"
appendInfoLine: "Floor    : mean + ", fixed$(floor_dB, 1), " dB"
if score_type = 1
    scoreLabel$ = "RMS energy"
elsif score_type = 2
    scoreLabel$ = "Onsets (positive slope)"
elsif score_type = 3
    scoreLabel$ = "Energy edges (absolute slope)"
else
    scoreLabel$ = "Mixed (slope weight=" + fixed$(transient_weight, 2) + ")"
endif
appendInfoLine: "Score    : ", scoreLabel$
appendInfoLine: "Seed     : ", seedLabel$
appendInfoLine: "Output   : MONO"
if warnLines$ <> ""
    appendInfoLine: ""
    appendInfoLine: "Adjustments:"
    appendInfo: warnLines$
endif
appendInfoLine: "Jitter   : ±", fixed$(time_jitter_ms, 1), " ms  pitch: ±", fixed$(pitch_jitter_semitones, 2), " st"
appendInfoLine: ""

selectObject: srcID
if srcCh > 1
    monoSrc = Convert to mono
else
    monoSrc = Copy: "gar_mono"
endif

# v2.0 fix 7: the dry path is the source at ITS OWN level. v1.1 copied
# the dry signal from the peak-normalized working sound below, so
# Wet_percent = 0 did not return the input.
selectObject: monoSrc
dryRef = Copy: "gar_dry_ref"

selectObject: monoSrc
Scale peak: 0.99

# ============================================================
# PHASE 1: EXTRACT + SCORE ALL CANDIDATE GRAINS
# ============================================================

appendInfoLine: "[1/4] Extracting and scoring candidate grains..."

# v2.0 fix 4: allow a SINGLE candidate. v1.1 forced the count to 2,
# which manufactured an invalid second grain on short sources.
nCandGrains = floor((srcDur - grainDur) / candHop) + 1
if nCandGrains < 1
    nCandGrains = 1
endif

appendInfoLine: "  Candidates: ", nCandGrains, "  (", fixed$(candHop * 1000, 1), " ms hop)"

rmsScore#       = zero#(nCandGrains)
grainStartTime# = zero#(nCandGrains)

# v2.0 fix 6: score the WINDOWED grain, i.e. the audio that actually
# reaches the output. v1.1 scored a rectangular extraction but rendered
# a Hann-windowed one, so an event sitting near a grain edge could win
# the competition and then be almost entirely windowed away.
for ii from 1 to nCandGrains
    tStart = (ii - 1) * candHop
    if tStart > srcDur - grainDur
        tStart = srcDur - grainDur
    endif
    if tStart < 0
        tStart = 0
    endif
    tEnd = tStart + grainDur
    if tEnd > srcDur
        tEnd = srcDur
    endif
    grainStartTime#[ii] = tStart

    selectObject: monoSrc
    gSnd = Extract part: tStart, tEnd, "rectangular", 1, "no"
    selectObject: gSnd
    Formula: "self * (0.5 - 0.5 * cos(2 * pi * (x - xmin) / (xmax - xmin)))"
    selectObject: gSnd
    rms = Get root-mean-square: 0, 0
    removeObject: gSnd

    if rms < 1e-9
        rms = 1e-9
    endif
    rmsScore#[ii] = rms * rms
endfor

# Slope score. v2.0 fix 5: v1.1 took the ABSOLUTE energy difference, so
# a note ending scored as highly as a note beginning while the form
# promised "attacks/onsets repeat". Onsets now means positive slope
# only; the old behaviour is still available as Energy edges.
transScore# = zero#(nCandGrains)
transScore#[1] = 0
for ii from 2 to nCandGrains
    diff = rmsScore#[ii] - rmsScore#[ii - 1]
    if score_type = 3
        # Energy edges: attacks AND decays
        if diff < 0
            diff = -diff
        endif
    else
        # Onsets / Mixed: rising energy only
        if diff < 0
            diff = 0
        endif
    endif
    transScore#[ii] = diff
endfor

# Normalize slope scores to the same range as RMS for mixing
maxTrans = transScore#[1]
for ii from 2 to nCandGrains
    if transScore#[ii] > maxTrans
        maxTrans = transScore#[ii]
    endif
endfor
maxRMS = rmsScore#[1]
for ii from 2 to nCandGrains
    if rmsScore#[ii] > maxRMS
        maxRMS = rmsScore#[ii]
    endif
endfor
if maxTrans < 1e-30
    maxTrans = 1e-30
endif
if maxRMS < 1e-30
    maxRMS = 1e-30
endif

# Build combined score
rawScore# = zero#(nCandGrains)
for ii from 1 to nCandGrains
    rmsN   = rmsScore#[ii]   / maxRMS
    transN = transScore#[ii] / maxTrans
    if score_type = 1
        rawScore#[ii] = rmsN
    elsif score_type = 2 or score_type = 3
        rawScore#[ii] = transN
    else
        rawScore#[ii] = rmsN * (1 - transient_weight) + transN * transient_weight
    endif
endfor

# ============================================================
# PHASE 2: RELU + SOFTMAX COMPETITION
# ============================================================

appendInfoLine: "[2/4] Computing grain selection probabilities..."

# Mean of raw scores in linear space
sumS = 0
for ii from 1 to nCandGrains
    sumS = sumS + rawScore#[ii]
endfor
meanScore = sumS / nCandGrains
if meanScore < 1e-30
    meanScore = 1e-30
endif

# Floor in same (normalized linear) units
# floor_dB offset → multiplicative threshold = 10^(floor_dB/10)
floorFactor = 10 ^ (floor_dB / 10)
floorValue  = meanScore * floorFactor

# ReLU gate. v2.0 CRITICAL 1: v1.1 set rejected grains to 0 and then
# ran softmax over ALL of them, and exp(0) is not 0. Verified example:
# 1 active grain at score 1 and 99 rejected at 0, meanScore 0.5,
# alpha 1 -> active weight 1.000, each rejected exp(-2) = 0.135,
# rejected total 13.398. The suppressed grains held 93.05% of the
# probability mass, so at low alpha the floor barely mattered.
# An explicit active mask now keeps them out of the sum entirely.
gated#  = zero#(nCandGrains)
active# = zero#(nCandGrains)
nActive = 0
for ii from 1 to nCandGrains
    if rawScore#[ii] >= floorValue
        gated#[ii]  = rawScore#[ii]
        active#[ii] = 1
        nActive     = nActive + 1
    endif
endfor

# If nothing clears the floor, activate ONLY the strongest grain.
# v1.1 re-opened the gate for everything, so Floor_dB = +6 could end up
# behaving as no floor at all whenever the threshold exceeded the max.
if nActive = 0
    bestIdx = 1
    bestVal = rawScore#[1]
    for ii from 2 to nCandGrains
        if rawScore#[ii] > bestVal
            bestVal = rawScore#[ii]
            bestIdx = ii
        endif
    endfor
    gated#[bestIdx]  = rawScore#[bestIdx]
    active#[bestIdx] = 1
    nActive = 1
    warnLines$ = warnLines$ +
        ... "  ! No grain cleared the floor; using the single strongest grain" +
        ... newline$
endif

# Softmax over ACTIVE grains only (max subtracted for stability)
maxGated = -1e30
for ii from 1 to nCandGrains
    if active#[ii] = 1 and gated#[ii] > maxGated
        maxGated = gated#[ii]
    endif
endfor

softNum# = zero#(nCandGrains)
softSum  = 0
for ii from 1 to nCandGrains
    if active#[ii] = 1
        arg = (gated#[ii] - maxGated) / meanScore * temperature
        if arg < -500
            arg = -500
        endif
        sw = exp(arg)
    else
        sw = 0
    endif
    softNum#[ii] = sw
    softSum      = softSum + sw
endfor
if softSum < 1e-30
    softSum = 1e-30
endif

prob# = zero#(nCandGrains)
for ii from 1 to nCandGrains
    prob#[ii] = softNum#[ii] / softSum
endfor

# v2.0 fix 13: the cdf# array built here in v1.1 was never read -
# drawGrain always rebuilds its own distribution after the recency
# penalty. Removed.

appendInfoLine: "  Active grains: ", nActive, "/", nCandGrains
appendInfoLine: "  Mean score: ", fixed$(meanScore, 6),
    ... "  Floor: ", fixed$(floorValue, 6)

# ============================================================
# HELPER: DRAW GRAIN FROM CDF WITH RECENCY PENALTY
# Returns: selectedGrainIdx (1-based)
# Uses globals: prob#, nCandGrains, recency_penalty
# Recency state: lastGrain1, lastGrain2, lastGrain3
# ============================================================

procedure drawGrain
    # Build penalized CDF
    penSum = 0
    for .ii from 1 to nCandGrains
        penP = prob#[.ii]
        if .ii = lastGrain1
            penP = penP * (1 - recency_penalty)
        endif
        if .ii = lastGrain2
            penP = penP * (1 - recency_penalty * 0.6)
        endif
        if .ii = lastGrain3
            penP = penP * (1 - recency_penalty * 0.3)
        endif
        if penP < 0
            penP = 0
        endif
        penProb_'.ii' = penP
        penSum = penSum + penP
    endfor
    if penSum < 1e-30
        penSum = 1e-30
    endif

    # Walk CDF until cumulative sum exceeds uniform random draw
    r = randomUniform(0, 1)
    cumP = 0
    selected = nCandGrains
    for .ii from 1 to nCandGrains
        cumP = cumP + penProb_'.ii' / penSum
        if cumP >= r and selected = nCandGrains
            selected = .ii
        endif
    endfor

    drawGrain.index = selected

    # Update recency ring
    lastGrain3 = lastGrain2
    lastGrain2 = lastGrain1
    lastGrain1 = selected
endproc

# ============================================================
# PHASE 3: SYNTHESIS - TRUE HANN OVERLAP-ADD
# ============================================================
# v2.0 CRITICAL 2. v1.1 extracted every grain with a Hann window baked
# into its samples and then handed the whole set to
# Concatenate with overlap, which applies its OWN Hann crossfade on top.
# Measured on two 0.2 s Hann grains at 0.1 s overlap over a flat 0.5
# source: grain peak 0.500, join centre 0.250 - a 6 dB dip at every
# join, repeating at the hop rate, with no envelope normalization
# anywhere despite the header claiming it. Pairwise crossfading also
# cannot represent three or more grains overlapping at once, which is
# exactly what happens when hop < grain/2.
#
# This is the architecture the header always described:
#   rectangular grain -> varispeed -> one Hann window
#   -> outBuf += grain at its true time
#   -> envBuf += the same Hann window
#   -> outBuf / envBuf
# Formula (part) keeps each add region-limited, so cost scales with
# total grain samples rather than hops x buffer length.
# ============================================================

appendInfoLine: "[3/4] Synthesizing output (Hann OLA)..."

nOutputHops = floor(srcDur / synthHop) + 1

# Buffer runs past the source so late grains and jitter are not clipped
bufDur = srcDur + grainDur + timeJitter + 0.05

Create Sound from formula: "gar_outbuf", 1, 0, bufDur, srcSr, "0"
outBuf = selected("Sound")
Create Sound from formula: "gar_envbuf", 1, 0, bufDur, srcSr, "0"
envBuf = selected("Sound")

# Recency state
lastGrain1 = 0
lastGrain2 = 0
lastGrain3 = 0

# Per-hop logs for visualization
chosenGrain# = zero#(nOutputHops)

appendInfoLine: "  Hops: ", nOutputHops,
    ... "  grain: ", fixed$(grainDur * 1000, 1), " ms",
    ... "  jitter: +/-", fixed$(timeJitter * 1000, 1), " ms"

for hop from 1 to nOutputHops
    @drawGrain
    chosen = drawGrain.index
    chosenGrain#[hop] = chosen

    # --- rectangular extraction (window comes later, after varispeed) ---
    origStart = grainStartTime#[chosen]
    tGEnd = origStart + grainDur
    if tGEnd > srcDur
        tGEnd = srcDur
    endif
    selectObject: monoSrc
    grainCopy = Extract part: origStart, tGEnd, "rectangular", 1, "no"

    # --- varispeed pitch jitter (v2.0 fix 10) ---
    # This is varispeed, not duration-preserving pitch shifting: pitch,
    # internal speed and event durations all move together. It runs
    # BEFORE the window, so a downward shift can no longer leave the
    # Hann envelope truncated the way it did in v1.1. Grains need not
    # share a length any more, because OLA places each at its own time.
    if pitch_jitter_semitones > 0.001
        pitchShift = randomUniform(-pitch_jitter_semitones, pitch_jitter_semitones)
        shiftFactor = 2 ^ (pitchShift / 12)
        interpSr = round(srcSr / shiftFactor)
        if interpSr < 1000
            interpSr = 1000
        endif
        if interpSr > 200000
            interpSr = 200000
        endif
        selectObject: grainCopy
        pitched = Resample: interpSr, 10
        removeObject: grainCopy
        selectObject: pitched
        Override sampling frequency: srcSr
        grainCopy = pitched
    endif

    # --- one Hann window, applied exactly once ---
    selectObject: grainCopy
    gLen = Get total duration
    if gLen > 0.0005
        selectObject: grainCopy
        Formula: "self * (0.5 - 0.5 * cos(2 * pi * (x - xmin) / (xmax - xmin)))"
    endif

    # --- output position, with real time jitter (v2.0 CRITICAL 3) ---
    pos = (hop - 1) * synthHop
    if timeJitter > 0
        pos = pos + randomUniform(-timeJitter, timeJitter)
    endif
    if pos < 0
        pos = 0
    endif
    if pos + gLen > bufDur
        pos = bufDur - gLen
    endif
    if pos < 0
        pos = 0
    endif

    # --- overlap-add into the buffers ---
    selectObject: grainCopy
    Shift times to: "start time", pos
    gid$ = string$(grainCopy)
    p0$ = fixed$(pos, 9)
    p1$ = fixed$(pos + gLen, 9)
    gl$ = fixed$(gLen, 9)

    selectObject: outBuf
    Formula (part): pos, pos + gLen, 1, 1, "self + object(" + gid$ + ", x)"

    selectObject: envBuf
    Formula (part): pos, pos + gLen, 1, 1,
        ... "self + (0.5 - 0.5 * cos(2 * pi * (x - " + p0$ + ") / " + gl$ + "))"

    removeObject: grainCopy

    if hop mod 200 = 0
        appendInfoLine: "  Grain ", hop, "/", nOutputHops,
            ... "  (", fixed$(100 * hop / nOutputHops, 0), "%)"
    endif
endfor

appendInfoLine: "  Grain ", nOutputHops, "/", nOutputHops, " (100%)"

# --- divide by the accumulated Hann envelope (the OLA step) ---
appendInfoLine: "  Normalizing by accumulated envelope..."
selectObject: envBuf
envPeak = Get absolute extremum: 0, 0, "None"
if envPeak < 1e-9
    envPeak = 1e-9
endif
# Floor the divisor rather than dividing by near-zero: at the very head
# and tail only one grain's rising edge is present, and an unfloored
# division would boost that edge instead of letting it fade.
envFloor = envPeak * 0.15
ef$ = fixed$(envFloor, 9)
envID$ = string$(envBuf)
selectObject: outBuf
Formula: "self / max(object[" + envID$ + ", col], " + ef$ + ")"

removeObject: envBuf
concatResult = outBuf

# Trim to source length
selectObject: concatResult
concatDur = Get total duration
if concatDur > srcDur
    trimmed = Extract part: 0, srcDur, "rectangular", 1, "no"
    removeObject: concatResult
    concatResult = trimmed
endif

# v2.0 fix 11: the trim can land mid-grain at a non-zero amplitude.
selectObject: concatResult
edgeFade = 0.005
selectObject: concatResult
resDur = Get total duration
if edgeFade > resDur * 0.1
    edgeFade = resDur * 0.1
endif
if edgeFade > 0.0002
    fs$ = fixed$(edgeFade, 8)
    selectObject: concatResult
    Formula: "if x - xmin < " + fs$ + " then self * ((x - xmin) / " + fs$ + ") else self fi"
    selectObject: concatResult
    Formula: "if xmax - x < " + fs$ + " then self * ((xmax - x) / " + fs$ + ") else self fi"
endif

# v2.0 fix 8: all random draws are done.
random_initializeSafelyAndUnpredictably ()

# ============================================================
# WET / DRY MIX
# ============================================================

if dryLevel > 0.001
    # v2.0 fix 7: dry comes from the UNNORMALIZED source copy.
    selectObject: dryRef
    dryCopy  = Copy: "gar_dry"

    # Pad dry to match concatResult duration if needed
    selectObject: concatResult
    wetDur = Get total duration
    selectObject: dryCopy
    dryDur = Get total duration
    if abs(wetDur - dryDur) > 0.005
        if dryDur < wetDur
            Create Sound from formula: "dry_pad", 1, 0, wetDur - dryDur, srcSr, "0"
            padSnd = selected("Sound")
            selectObject: dryCopy
            plusObject: padSnd
            paddedDry = Concatenate
            removeObject: dryCopy, padSnd
            dryCopy = paddedDry
        else
            selectObject: dryCopy
            trimDry = Extract part: 0, wetDur, "rectangular", 1, "no"
            removeObject: dryCopy
            dryCopy = trimDry
        endif
    endif

    wetStr$ = fixed$(wetLevel, 6)
    dryStr$ = fixed$(dryLevel, 6)
    dryID$  = string$(dryCopy)
    selectObject: concatResult
    Formula: "self * " + wetStr$ + " + object[" + dryID$ + ", col] * " + dryStr$
    removeObject: dryCopy
endif

# ============================================================
# FINALIZE
# ============================================================

selectObject: concatResult
peakVal = Get absolute extremum: 0, 0, "None"
if peakVal > 0.001
    Scale peak: 0.99
endif
outputName$ = srcName$ + "_GAR_" + presetName$
Rename: outputName$
resultID  = selected("Sound")
resultDur = Get total duration

removeObject: monoSrc
removeObject: dryRef

appendInfoLine: ""
appendInfoLine: "Output: ", outputName$
appendInfoLine: "Duration: ", fixed$(resultDur, 3), " s"

# ============================================================
# GRAIN USAGE STATISTICS
# ============================================================

for ii from 1 to nCandGrains
    usageCount_'ii' = 0
endfor
for hop from 1 to nOutputHops
    idx = chosenGrain#[hop]
    if idx >= 1 and idx <= nCandGrains
        usageCount_'idx' = usageCount_'idx' + 1
    endif
endfor

maxUsage    = 0
usedGrains  = 0
for ii from 1 to nCandGrains
    c = usageCount_'ii'
    if c > 0
        usedGrains = usedGrains + 1
    endif
    if c > maxUsage
        maxUsage    = c
        maxUsageIdx = ii
    endif
endfor

appendInfoLine: ""
appendInfoLine: "Unique grains used : ", usedGrains, "/", nCandGrains
appendInfoLine: "Most-used grain    : #", maxUsageIdx,
    ... " at t=", fixed$(grainStartTime#[maxUsageIdx], 3), " s  (used ", maxUsage, " times)"

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization = 1

    selectObject: srcID
    srcPeak = Get absolute extremum: 0, 0, "None"
    if srcPeak < 0.001
        srcPeak = 0.001
    endif
    ampMax = srcPeak * 1.15

    Erase all

    # === TITLE ===
    Select outer viewport: 0, 8, 0, 0.46
    Axes: 0, 1, 0, 1
    Font size: 11
    Colour: "Black"
    Text: 0.5, "centre", 0.73, "half", "##Granular Attention Re-synthesis v2.0##"
    Font size: 7.5
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -0.08, "half",
        ... "[" + presetName$ + "]  " + srcName$
        ... + "  |  α=" + fixed$(temperature, 1)
        ... + "  floor=mean+" + fixed$(floor_dB, 0) + "dB"
        ... + "  grain=" + fixed$(grain_size_ms, 0) + "ms"
        ... + "  hop=" + fixed$(synthesis_hop_ms, 0) + "ms"
        ... + "  unique=" + string$(usedGrains) + "/" + string$(nCandGrains)

    # === Panel 1: Input waveform ===
    Select outer viewport: 0, 8, 0.50, 1.33
    Select inner viewport: 0.58, 7.65, 0.55, 1.28
    Axes: 0, srcDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, srcDur, -ampMax, ampMax
    Colour: "{0.80, 0.80, 0.80}"
    Draw line: 0, 0, srcDur, 0
    selectObject: srcID
    Colour: "{0.45, 0.50, 0.58}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"
    Text top: "no", "Original waveform"

    # === Panel 2: Output waveform ===
    Select outer viewport: 0, 8, 1.36, 2.18
    Select inner viewport: 0.58, 7.65, 1.41, 2.13
    Axes: 0, resultDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, resultDur, -ampMax, ampMax
    Colour: "{0.80, 0.80, 0.80}"
    Draw line: 0, 0, resultDur, 0
    selectObject: resultID
    Colour: "{0.22, 0.50, 0.68}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text top: "no", outputName$
    Text bottom: "yes", "Time (s)"

    # === Panel 3: Grain score landscape + probability ===
    Select outer viewport: 0, 8, 2.25, 3.22
    Select inner viewport: 0.58, 7.65, 2.30, 3.17

    # Normalise scores for display
    maxRawScore = rawScore#[1]
    minRawScore = rawScore#[1]
    for ii from 2 to nCandGrains
        if rawScore#[ii] > maxRawScore
            maxRawScore = rawScore#[ii]
        endif
        if rawScore#[ii] < minRawScore
            minRawScore = rawScore#[ii]
        endif
    endfor
    rawRange = maxRawScore - minRawScore
    if rawRange < 1e-10
        rawRange = 1e-10
    endif

    maxProb = prob#[1]
    for ii from 2 to nCandGrains
        if prob#[ii] > maxProb
            maxProb = prob#[ii]
        endif
    endfor
    if maxProb < 1e-10
        maxProb = 1e-10
    endif

    Axes: 0, srcDur, -0.08, 1.30
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, srcDur, -0.08, 1.30

    # Floor line
    floorNorm = (floorValue - minRawScore) / rawRange
    if floorNorm < 0
        floorNorm = 0
    endif
    if floorNorm > 1
        floorNorm = 1
    endif
    Colour: "{0.88, 0.55, 0.18}"
    Dotted line
    Draw line: 0, floorNorm, srcDur, floorNorm
    Solid line
    Font size: 5
    Text: srcDur * 0.01, "left", floorNorm + 0.04, "half",
        ... "ReLU floor"

    # Score bars (grey)
    for ii from 1 to nCandGrains
        x = grainStartTime#[ii]
        h = (rawScore#[ii] - minRawScore) / rawRange
        Colour: "{0.78, 0.78, 0.84}"
        Draw line: x, 0, x, h
    endfor

    # Probability overlay (blue, scaled to same axis)
    Colour: "{0.20, 0.48, 0.75}"
    Line width: 1.5
    for ii from 2 to nCandGrains
        x1 = grainStartTime#[ii - 1]
        x2 = grainStartTime#[ii]
        y1 = prob#[ii - 1] / maxProb
        y2 = prob#[ii]     / maxProb
        Draw line: x1, y1, x2, y2
    endfor
    Line width: 1

    # Usage count: size of circle = how often this grain was chosen
    if maxUsage > 0
        for ii from 1 to nCandGrains
            c = usageCount_'ii'
            if c > 0
                x = grainStartTime#[ii]
                r = c / maxUsage * 1.4 + 0.3
                Colour: "{0.85, 0.38, 0.18}"
                Paint circle (mm): "{0.85, 0.38, 0.18}", x, prob#[ii] / maxProb, r
            endif
        endfor
    endif

    Font size: 5
    Colour: "{0.78, 0.78, 0.84}"
    Text: srcDur * 0.79, "left", 1.22, "half", "score"
    Colour: "{0.20, 0.48, 0.75}"
    Text: srcDur * 0.79, "left", 1.10, "half", "probability"
    Colour: "{0.85, 0.38, 0.18}"
    Text: srcDur * 0.79, "left", 0.98, "half", "usage (size)"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Score"
    Text top: "no", "Grain score / probability / usage   (orange dot = chosen, size = frequency)"

    # === Panel 4: Grain selection sequence ===
    Select outer viewport: 0, 8, 3.28, 4.22
    Select inner viewport: 0.58, 7.65, 3.33, 4.17

    dispHops = nOutputHops
    if dispHops > 200
        dispHops = 200
    endif

    Axes: 0, dispHops + 1, 0, nCandGrains + 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, dispHops + 1, 0, nCandGrains + 1

    # Color by score value
    for hop from 1 to dispHops
        idx = chosenGrain#[hop]
        if idx >= 1 and idx <= nCandGrains
            scoreFrac = (rawScore#[idx] - minRawScore) / rawRange
            cR = 0.15 + scoreFrac * 0.65
            cG = 0.45 + scoreFrac * 0.15
            cB = 0.80 - scoreFrac * 0.58
            Paint rectangle: "{" + fixed$(cR, 2) + "," + fixed$(cG, 2) + "," + fixed$(cB, 2) + "}",
                ... hop - 0.48, hop + 0.48, idx - 0.48, idx + 0.48
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Grain #"
    Text bottom: "yes", "Output hop"
    Text top: "no", "Grain selection sequence  (blue=low score  orange=high score)"

    # === Panel 5: Usage histogram ===
    Select outer viewport: 0, 4, 4.28, 5.10
    Select inner viewport: 0.55, 3.75, 4.33, 5.05
    Axes: 0, nCandGrains + 1, 0, maxUsage * 1.15
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, nCandGrains + 1, 0, maxUsage * 1.15

    meanUsage = nOutputHops / nCandGrains
    Colour: "{0.85, 0.85, 0.85}"
    Dotted line
    Draw line: 0, meanUsage, nCandGrains + 1, meanUsage
    Solid line

    for ii from 1 to nCandGrains
        c = usageCount_'ii'
        if c > 0
            scoreFrac = (rawScore#[ii] - minRawScore) / rawRange
            cR = 0.15 + scoreFrac * 0.65
            cG = 0.45 + scoreFrac * 0.15
            cB = 0.80 - scoreFrac * 0.58
            Paint rectangle: "{" + fixed$(cR, 2) + "," + fixed$(cG, 2) + "," + fixed$(cB, 2) + "}",
                ... ii - 0.45, ii + 0.45, 0, c
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Count"
    Text bottom: "yes", "Grain #"
    Text top: "no", "Usage histogram  (dashed = uniform mean)"

    # === Panel 6: Stats ===
    Select outer viewport: 4, 8, 4.28, 5.10
    Select inner viewport: 4.18, 7.65, 4.33, 5.05
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.04, "left", 0.90, "half", "##Granular Attention Re-synthesis v2.0##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.38}"
    Text: 0.04, "left", 0.71, "half",
        ... "Preset: " + presetName$
        ... + "  |  α=" + fixed$(temperature, 1)
        ... + "  floor=mean+" + fixed$(floor_dB, 0) + "dB"
    Text: 0.04, "left", 0.53, "half",
        ... "Grain=" + fixed$(grain_size_ms, 0) + "ms"
        ... + "  hop=" + fixed$(synthesis_hop_ms, 0) + "ms"
        ... + "  cand=" + string$(nCandGrains)
        ... + "  active=" + string$(nActive)
    Text: 0.04, "left", 0.35, "half",
        ... "Unique used: " + string$(usedGrains) + "/" + string$(nCandGrains)
        ... + "  (" + fixed$(100 * usedGrains / nCandGrains, 0) + "%)"
    Text: 0.04, "left", 0.17, "half",
        ... "Top grain: #" + string$(maxUsageIdx)
        ... + "  t=" + fixed$(grainStartTime#[maxUsageIdx], 2) + "s"
        ... + "  used " + string$(maxUsage) + "×"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================
# OUTPUT
# ============================================================

selectObject: resultID

appendInfoLine: ""
appendInfoLine: "=================================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=================================================="
appendInfoLine: "Output  : ", outputName$
appendInfoLine: "Duration: ", fixed$(resultDur, 3), " s"
appendInfoLine: "Preset  : ", presetName$
appendInfoLine: "alpha / floor: ", fixed$(temperature, 2), " / mean+", fixed$(floor_dB, 1), " dB"
appendInfoLine: "Hops    : ", nOutputHops
appendInfoLine: "Unique grains used: ", usedGrains, "/", nCandGrains

if play_result = 1
    Play
endif
