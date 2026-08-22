# ============================================================
# Praat AudioTools - MCMC_Musical_Variation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3.1 (2026)
# v1.3 (2026): SPATIAL VISUALIZATION STANDARDIZATION ONLY - label rails, compact summary, typography; DSP unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Metropolis-Hastings-style chain for musical variation.
#   State = pitch contour + time map + dynamic map per phrase.
#   Proposals operate at phrase/note level (not granular).
#   Energy enforces scale conformity, voice leading, rhythmic
#   stability, range, dynamics, phrase integrity, contour variety.
#   Each accepted + thinned step renders a full-length variation
#   via Tape Speed (pitch) + Lengthen (time) + Formula (dynamics).
#
#   PIPELINE PER PHRASE SEGMENT:
#   1. Extract source segment
#   2. Override SR * pitchRatio  (tape speed pitch shift)
#   3. Resample back to srcSr   (bake shift into samples)
#   4. Lengthen (overlap-add)   (independent time stretch)
#   5. Formula amplitude        (dynamics)
#   6. Concatenate with overlap (assembly)
#
# Methodological note (v1.1):
#   This is best understood as ANNEALED EXPLORATION with an
#   MH-style acceptance rule, not strict posterior sampling.
#   Some proposals satisfy detailed balance (PitchNudge,
#   PhraseTranspose, TemporalSwap, GlobalTranspose are symmetric
#   in the proposal density), while others do not — DynamicSwell,
#   TempoWarp, and DynamicArch use clipping that breaks
#   reversibility at boundaries; MicroRubato compensates an
#   adjacent phrase, breaking symmetry. The chain explores the
#   state space and biases toward lower-energy regions, which is
#   the operationally useful property here. The "samples from a
#   stationary posterior" interpretation does not strictly apply.
#
# Changelog v1.3 (2026):
#   - REPRODUCIBILITY: Added a Seed field. Seed=0 keeps behaviour
#     unpredictable (as before); any other value fixes Praat's RNG
#     via random_initializeWithSeedUnsafelyButPredictably, so a
#     chain that produced a good result can be rerun exactly.
#   - CORRECTNESS: Guaranteed that at least one Variation is always
#     rendered. Previously a Variation was only produced when a
#     step was BOTH accepted AND on the thinning interval, and the
#     one fallback path also required the last step to be accepted
#     - so varCount could legitimately end at 0 and crash the
#     multichannel-combine step. The chain's final state is now
#     rendered directly whenever nothing else was rendered.
#   - BEHAVIOUR: Removed the separate Play_first (variation-1
#     preview) option. There is now a single Play checkbox
#     (default on) that governs playback of the combined output,
#     so it's explicit and user-controlled rather than always-on
#     regardless of what was requested. A note is still printed
#     when >2 channels are combined, since most playback hardware
#     is stereo and won't expose every channel.
#   - CORRECTNESS: "Combine to stereo" requires 2+ selected mono
#     sounds and could fail whenever exactly one variation was
#     produced (the varCount=0 fallback, Max_variations=1, or only
#     one thinning point ever accepted). That case now copies the
#     single variation through directly (named "..._mcmc_output")
#     instead of calling Combine to stereo on one sound.
#   - CORRECTNESS: PitchNudge's proposal is now actually symmetric.
#     A rounded-Gaussian delta of 0 used to always become +1, which
#     gave +1 extra probability mass -1 never got. It now resolves
#     to +1/-1 with a fair coin, matching the symmetric-proposal
#     claim in the methodological note above.
#   - CORRECTNESS: The duration-preservation term (E4) now compares
#     processed phrase length against the sum of the ORIGINAL
#     (silence-stripped) phrase durations, not the full source
#     duration. Comparing against srcDur penalised even the
#     untouched state (tm=1 for every phrase) whenever the source
#     contained silence.
#   - VISUALIZATION: Render markers in the energy-trace plot now
#     use the step actually recorded at render time (renderStep_v),
#     not an assumed v * thinning_interval position, which could be
#     wrong whenever earlier candidate steps were rejected.
#   - WORDING: "lower = more musical" replaced with "lower = better
#     fit to the selected energy criteria" - the model measures
#     conformance to defined weights, not musicality in general.
#   - ROBUSTNESS: Added validation for Mcmc_steps > 0,
#     Thinning_interval > 0, Max_variations > 0, and
#     Pitch_floor_Hz < Pitch_ceiling_Hz. Added a printed warning
#     when phrase detection finds more than 20 phrases and later
#     ones are dropped (previously silent).
#
# Changelog v1.1 (2026):
#   - SPEED: Per-phrase resample precision is now tied to a
#     Speed_mode parameter (Full/Balanced/Fast -> 50/20/10).
#     Resampling per phrase per variation was the dominant cost.
#   - ROBUSTNESS: Pitch_floor_Hz and Pitch_ceiling_Hz form fields
#     control the PSOLA pitch range used by Lengthen (overlap-add).
#     Defaults widened from 75-600 to 60-700 Hz to handle
#     instrumental music and low voices more reliably.
#   - NAMING: Final multichannel output renamed from
#     "<src>_mcmc_stereo" to "<src>_mcmc_multichannel" since the
#     output has varCount channels (often >2), not stereo.
#   - DOC: Detailed-balance note added to header (above).
#
# Category: Composition / MCMC
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

srcSound = selected("Sound")
srcName$ = selected$("Sound")
selectObject: srcSound
srcDur = Get total duration
srcSr  = Get sampling frequency
srcCh  = Get number of channels

if srcDur < 1.0
    exitScript: "Sound too short (minimum 1 s)."
endif

# ============================================================
# FORM
# ============================================================

form MCMC Musical Variation v1.3
    comment === Aesthetic Mode ===
    optionmenu Aesthetic_mode: 2
        option Custom
        option Conservative  (faithful, T=0.8 fixed)
        option Expressive    (reinterpretive, T 3.0 -> 1.0)
        option Exploratory   (creative, T 8.0 -> 2.0)
    comment === Speed (resample precision per phrase) ===
    optionmenu Speed_mode: 2
        option Full Quality (precision 50)
        option Balanced (precision 20)
        option Fast (precision 10)
    comment === Reproducibility ===
    integer Seed 0
    comment (0 = unpredictable/random each run; any other integer = reproducible chain)
    comment === Chain ===
    integer Mcmc_steps 60
    integer Thinning_interval 6
    comment === Temperature ===
    positive Start_temp 2.0
    positive End_temp 0.5
    boolean Anneal 1
    comment === Phrase Detection ===
    real Silence_thresh_dB -35.0
    positive Min_phrase_s 0.5
    comment === Pitch Range for PSOLA Lengthen ===
    positive Pitch_floor_Hz 60
    positive Pitch_ceiling_Hz 700
    comment === Tonal Center (0=C 2=D 4=E 5=F 7=G 9=A 11=B) ===
    integer Tonal_center_st 0
    comment === Output ===
    integer Max_variations 8
    boolean Keep_individual_variations 0
    boolean Draw_visualization 1
    boolean Play 1
endform

# ============================================================
# ALIASES
# ============================================================

aestheticMode  = aesthetic_mode
nSteps         = mcmc_steps
thin           = thinning_interval
tStart        = start_temp
tEnd          = end_temp
doAnneal       = anneal
silThresh      = silence_thresh_dB
minPhraseDur   = min_phrase_s
tonalCenter    = tonal_center_st
maxVar         = max_variations
pitchFloorHz   = pitch_floor_Hz
pitchCeilingHz = pitch_ceiling_Hz

# ============================================================
# PARAMETER VALIDATION (v1.3)
# ============================================================

if nSteps <= 0
    exitScript: "Mcmc_steps must be greater than 0."
endif
if thin <= 0
    exitScript: "Thinning_interval must be greater than 0."
endif
if maxVar <= 0
    exitScript: "Max_variations must be greater than 0."
endif
if pitchFloorHz >= pitchCeilingHz
    exitScript: "Pitch_floor_Hz must be lower than Pitch_ceiling_Hz."
endif

# ============================================================
# RANDOM SEED (v1.3)
# A fixed, non-zero Seed makes the whole chain (proposals AND
# acceptance draws) reproducible, so a chain that produced a
# good result can be re-run exactly. Seed = 0 keeps behaviour
# unpredictable, as before.
# ============================================================

if seed <> 0
    random_initializeWithSeedUnsafelyButPredictably (seed)
    seedStr$ = string$(seed) + " (fixed / reproducible)"
else
    random_initializeSafelyAndUnpredictably ()
    seedStr$ = "0 (unpredictable)"
endif

# v1.1: Resample precision tied to speed_mode.
# Per-phrase resampling is the dominant cost. Lower precision
# (down to ~10) is acceptable when the source is being
# reassembled with crossfades and dynamic shaping anyway —
# small aliasing artifacts are masked.
if speed_mode = 1
    resamplePrecision = 50
    speedStr$ = "Full Quality"
elsif speed_mode = 2
    resamplePrecision = 20
    speedStr$ = "Balanced"
else
    resamplePrecision = 10
    speedStr$ = "Fast"
endif

# ============================================================
# MODE PRESETS
# Energy weights: w1=scale w2=voiceLead w3=range w4=rhythm
#                 w5=dynamics w6=phraseInteg w7=contour
# Proposal weights: pw1=pitchNudge pw2=dynSwell pw3=rubato
#   pw4=phraseTranspose pw5=temporalSwap pw6=globalTranspose
#   pw7=tempoWarp pw8=dynArch   (must sum to 1.0)
# ============================================================

if aestheticMode = 2
    presetName$ = "Conservative"
    tStart = 0.8
    tEnd   = 0.8
    doAnneal = 0
    w1 = 2.5
    w2 = 2.0
    w3 = 1.5
    w4 = 2.0
    w5 = 1.0
    w6 = 1.2
    w7 = 0.5
    pw1 = 0.35
    pw2 = 0.15
    pw3 = 0.25
    pw4 = 0.05
    pw5 = 0.08
    pw6 = 0.03
    pw7 = 0.06
    pw8 = 0.03
elsif aestheticMode = 3
    presetName$ = "Expressive"
    tStart = 3.0
    tEnd   = 1.0
    doAnneal = 1
    w1 = 2.0
    w2 = 1.5
    w3 = 1.0
    w4 = 1.5
    w5 = 0.8
    w6 = 1.2
    w7 = 0.7
    pw1 = 0.25
    pw2 = 0.12
    pw3 = 0.20
    pw4 = 0.15
    pw5 = 0.10
    pw6 = 0.08
    pw7 = 0.07
    pw8 = 0.03
elsif aestheticMode = 4
    presetName$ = "Exploratory"
    tStart = 8.0
    tEnd   = 2.0
    doAnneal = 1
    w1 = 1.5
    w2 = 1.0
    w3 = 0.7
    w4 = 1.0
    w5 = 0.6
    w6 = 0.8
    w7 = 1.2
    pw1 = 0.18
    pw2 = 0.10
    pw3 = 0.15
    pw4 = 0.18
    pw5 = 0.12
    pw6 = 0.12
    pw7 = 0.10
    pw8 = 0.05
else
    presetName$ = "Custom"
    w1 = 2.0
    w2 = 1.5
    w3 = 1.0
    w4 = 1.5
    w5 = 0.8
    w6 = 1.2
    w7 = 0.7
    pw1 = 0.25
    pw2 = 0.12
    pw3 = 0.20
    pw4 = 0.15
    pw5 = 0.10
    pw6 = 0.08
    pw7 = 0.07
    pw8 = 0.03
endif

# ============================================================
# SCALE DEFINITION (major scale degrees)
# ============================================================

nScaleDeg = 7
sDeg_1 = 0
sDeg_2 = 2
sDeg_3 = 4
sDeg_4 = 5
sDeg_5 = 7
sDeg_6 = 9
sDeg_7 = 11

# ============================================================
# MONO CONVERSION
# ============================================================

selectObject: srcSound
if srcCh > 1
    monoSrc = Convert to mono
else
    monoSrc = Copy: "mcmc_src"
endif

# ============================================================
# PHRASE DETECTION
# ============================================================

selectObject: monoSrc
tgSil = To TextGrid (silences): 100, 0, silThresh, 0.15, 0.05, "silent", "sounding"
selectObject: tgSil
nIntervals = Get number of intervals: 1

nPhrases = 0
for ii from 1 to nIntervals
    selectObject: tgSil
    lbl$ = Get label of interval: 1, ii
    if lbl$ = "sounding"
        iStart = Get start time of interval: 1, ii
        iEnd   = Get end time of interval: 1, ii
        iDur   = iEnd - iStart
        if iDur >= minPhraseDur
            nPhrases = nPhrases + 1
            phraseStart_'nPhrases' = iStart
            phraseEnd_'nPhrases'   = iEnd
            phraseDur_'nPhrases'   = iDur
        endif
    endif
endfor
removeObject: tgSil

# Fallback: divide into equal segments
if nPhrases < 2
    nPhrases = 4
    segLen = srcDur / 4
    for pp from 1 to 4
        phraseStart_'pp' = (pp - 1) * segLen
        phraseEnd_'pp'   = pp * segLen
        phraseDur_'pp'   = segLen
    endfor
endif

phrasesTruncated = 0
nPhrasesDetected = nPhrases
if nPhrases > 20
    phrasesTruncated = 1
    nPhrases = 20
endif

# v1.3: Reference duration for the E4 duration-preservation term.
# Phrase detection strips silence, so the sum of *processed*
# phrase durations should never be compared against srcDur (which
# includes the stripped silence) — even tm=1 for every phrase
# would then look "too short" and be penalised. Compare instead
# against the sum of the *original* (silence-stripped) phrase
# durations, which is what tm=1 for every phrase actually equals.
srcPhraseDurSum = 0
for pp from 1 to nPhrases
    srcPhraseDurSum = srcPhraseDurSum + phraseDur_'pp'
endfor
if srcPhraseDurSum <= 0
    srcPhraseDurSum = srcDur
endif

# ============================================================
# STATE INITIALIZATION
# pc_N  = pitch contour offset in semitones (integer)
# tm_N  = time map ratio (>0, 1.0=no change)
# dm_N  = dynamic map (amplitude scale, 1.0=no change)
# transpo = global semitone shift
# ============================================================

transpo = 0
for pp from 1 to nPhrases
    pc_'pp' = 0
    tm_'pp' = 1.0
    dm_'pp' = 1.0
endfor

# ============================================================
# PROCEDURE: computeEnergy
# Reads global state pc_N, tm_N, dm_N, transpo, nPhrases,
# phraseDur_N, w1-w7, tonalCenter, nScaleDeg, sDeg_N
# Writes: energyResult
# ============================================================

procedure computeEnergy

    # --- E1: Scale conformity ---
    e1sum = 0
    for pp from 1 to nPhrases
        totalPitch = pc_'pp' + transpo
        # Pitch class relative to tonal center, forced into [0,12)
        rawPc = totalPitch - tonalCenter
        pitchClass = rawPc - floor(rawPc / 12) * 12
        # Min distance to any scale degree (circular)
        minD = 12
        for sd from 1 to nScaleDeg
            sdv = sDeg_'sd'
            dd = abs(pitchClass - sdv)
            if dd > 6
                dd = 12 - dd
            endif
            if dd < minD
                minD = dd
            endif
        endfor
        e1sum = e1sum + minD
    endfor
    e1 = e1sum / nPhrases

    # --- E2: Voice-leading smoothness ---
    e2sum = 0
    if nPhrases > 1
        for pp from 1 to nPhrases - 1
            ppN = pp + 1
            leap = abs(pc_'ppN' - pc_'pp')
            if leap > 12
                leap = leap + (leap - 12) * 2
            endif
            e2sum = e2sum + leap
        endfor
        e2 = e2sum / (nPhrases - 1)
    else
        e2 = 0
    endif

    # --- E3: Range constraint ---
    e3sum = 0
    for pp from 1 to nPhrases
        totalShift = abs(pc_'pp' + transpo)
        if totalShift > 12
            e3sum = e3sum + (totalShift - 12)^2
        endif
    endfor
    e3 = e3sum / nPhrases

    # --- E4: Rhythmic stability + duration preservation ---
    tmSum = 0
    for pp from 1 to nPhrases
        tmSum = tmSum + tm_'pp'
    endfor
    tmMean = tmSum / nPhrases
    tmVar = 0
    for pp from 1 to nPhrases
        tmVar = tmVar + (tm_'pp' - tmMean)^2
    endfor
    tmVar = tmVar / nPhrases
    newDurSum = 0
    for pp from 1 to nPhrases
        newDurSum = newDurSum + phraseDur_'pp' * tm_'pp'
    endfor
    durRatio = newDurSum / srcPhraseDurSum
    durPen = (durRatio - 1.0)^2 * 8
    e4 = tmVar + durPen

    # --- E5: Dynamic coherence ---
    dmSum = 0
    for pp from 1 to nPhrases
        dmSum = dmSum + dm_'pp'
    endfor
    dmMean = dmSum / nPhrases
    dmVar = 0
    clipPen = 0
    for pp from 1 to nPhrases
        dmVar = dmVar + (dm_'pp' - dmMean)^2
        if dm_'pp' > 1.6
            clipPen = clipPen + (dm_'pp' - 1.6)^2 * 3
        endif
        if dm_'pp' < 0.08
            clipPen = clipPen + (0.08 - dm_'pp')^2 * 5
        endif
    endfor
    dmVar = dmVar / nPhrases
    e5 = dmVar + clipPen

    # --- E6: Phrase integrity (no phrase becomes too short) ---
    e6sum = 0
    for pp from 1 to nPhrases
        newPhrDur = phraseDur_'pp' * tm_'pp'
        if newPhrDur < 0.25
            e6sum = e6sum + (0.25 - newPhrDur)^2 * 8
        endif
    endfor
    e6 = e6sum / nPhrases

    # --- E7: Contour naturalness (penalize monotone contour) ---
    e7 = 0
    if nPhrases > 2
        upCount   = 0
        downCount = 0
        for pp from 1 to nPhrases - 1
            ppN = pp + 1
            cDiff = pc_'ppN' - pc_'pp'
            if cDiff > 0
                upCount = upCount + 1
            elsif cDiff < 0
                downCount = downCount + 1
            endif
        endfor
        totalMoves = nPhrases - 1
        if totalMoves > 0
            topCount = upCount
            if downCount > topCount
                topCount = downCount
            endif
            monFrac = topCount / totalMoves
            if monFrac > 0.75
                e7 = (monFrac - 0.75)^2 * 4
            endif
        endif
    endif

    energyResult = w1*e1 + w2*e2 + w3*e3 + w4*e4 + w5*e5 + w6*e6 + w7*e7

endproc

# ============================================================
# PROCEDURE: saveState / restoreState
# ============================================================

procedure saveState
    saved_transpo = transpo
    for pp from 1 to nPhrases
        saved_pc_'pp' = pc_'pp'
        saved_tm_'pp' = tm_'pp'
        saved_dm_'pp' = dm_'pp'
    endfor
endproc

procedure restoreState
    transpo = saved_transpo
    for pp from 1 to nPhrases
        pc_'pp' = saved_pc_'pp'
        tm_'pp' = saved_tm_'pp'
        dm_'pp' = saved_dm_'pp'
    endfor
endproc

# ============================================================
# PROPOSAL PROCEDURES
# ============================================================

procedure proposePitchNudge
    pp = randomInteger(1, nPhrases)
    delta = round(randomGauss(0, 1.5))
    # v1.3: a rounded Gaussian can land on 0, which is not a move.
    # Previously this was always bumped to +1, which added extra
    # probability mass to +1 that -1 never got, breaking the
    # symmetric-proposal-density claim in the header. Resolve the
    # zero case with a fair coin instead, so +1 and -1 remain
    # equally likely.
    if delta = 0
        signR = randomInteger(0, 1)
        if signR = 0
            delta = -1
        else
            delta = 1
        endif
    endif
    pc_'pp' = pc_'pp' + delta
endproc

procedure proposeDynamicSwell
    pp = randomInteger(1, nPhrases)
    delta = randomGauss(0, 0.12)
    newDm = dm_'pp' + delta
    if newDm < 0.08
        newDm = 0.08
    endif
    if newDm > 1.8
        newDm = 1.8
    endif
    dm_'pp' = newDm
endproc

procedure proposeMicroRubato
    pp = randomInteger(1, nPhrases)
    delta = randomGauss(0, 0.10)
    newTm = tm_'pp' + delta
    if newTm < 0.3
        newTm = 0.3
    endif
    if newTm > 2.5
        newTm = 2.5
    endif
    # Compensate adjacent phrase to preserve approximate total duration
    if nPhrases > 1
        ppAdj = pp - 1
        if ppAdj < 1
            ppAdj = 2
        endif
        if ppAdj >= 1 and ppAdj <= nPhrases and ppAdj <> pp
            oldTotal = tm_'pp' * phraseDur_'pp' + tm_'ppAdj' * phraseDur_'ppAdj'
            tm_'pp' = newTm
            adjNeeded = (oldTotal - newTm * phraseDur_'pp') / phraseDur_'ppAdj'
            if adjNeeded < 0.3
                adjNeeded = 0.3
            endif
            if adjNeeded > 2.5
                adjNeeded = 2.5
            endif
            tm_'ppAdj' = adjNeeded
        else
            tm_'pp' = newTm
        endif
    else
        tm_'pp' = newTm
    endif
endproc

procedure proposePhraseTranspose
    pp = randomInteger(1, nPhrases)
    delta = randomInteger(1, 5)
    signR = randomInteger(0, 1)
    if signR = 0
        delta = -delta
    endif
    pc_'pp' = pc_'pp' + delta
endproc

procedure proposeTemporalSwap
    if nPhrases > 1
        pp1 = randomInteger(1, nPhrases - 1)
        pp2 = pp1 + 1
        tmpTm = tm_'pp1'
        tm_'pp1' = tm_'pp2'
        tm_'pp2' = tmpTm
    endif
endproc

procedure proposeGlobalTranspose
    delta = randomInteger(1, 3)
    signR = randomInteger(0, 1)
    if signR = 0
        delta = -delta
    endif
    transpo = transpo + delta
endproc

procedure proposeTempoWarp
    factor = randomGauss(1.0, 0.06)
    if factor < 0.75
        factor = 0.75
    endif
    if factor > 1.25
        factor = 1.25
    endif
    for pp from 1 to nPhrases
        newTm = tm_'pp' * factor
        if newTm < 0.3
            newTm = 0.3
        endif
        if newTm > 2.5
            newTm = 2.5
        endif
        tm_'pp' = newTm
    endfor
endproc

procedure proposeDynamicArch
    archType = randomInteger(1, 3)
    for pp from 1 to nPhrases
        if nPhrases > 1
            phi = (pp - 1) / (nPhrases - 1)
        else
            phi = 0.5
        endif
        if archType = 1
            archVal = 0.6 + phi * 0.7
        elsif archType = 2
            archVal = 1.3 - phi * 0.7
        else
            archVal = 0.65 + sin(phi * pi) * 0.7
        endif
        newDm = dm_'pp' * archVal
        if newDm < 0.08
            newDm = 0.08
        endif
        if newDm > 1.8
            newDm = 1.8
        endif
        dm_'pp' = newDm
    endfor
endproc

# ============================================================
# PROCEDURE: renderVariation
# Reads: global state, monoSrc, srcSr, srcName$, nPhrases,
#        phraseStart_N, phraseEnd_N, phraseDur_N
# Input: .vNum = variation index
# Writes: lastVariation (Sound ID)
# ============================================================

procedure renderVariation: .vNum
    hasAssembly = 0
    currentAssembly = 0

    for pp from 1 to nPhrases
        selectObject: monoSrc
        segStart = phraseStart_'pp'
        segEnd   = phraseEnd_'pp'
        segDur   = phraseDur_'pp'

        Extract part: segStart, segEnd, "rectangular", 1, "no"
        rawSeg = selected("Sound")

        semitones = pc_'pp' + transpo
        pitchRatio = 2^(semitones / 12)
        timeRat    = tm_'pp'
        dynScale   = dm_'pp'

        # Tape speed pitch shift (if meaningful)
        if abs(semitones) > 0.05
            selectObject: rawSeg
            Copy: "seg_work"
            workedSeg = selected("Sound")
            Override sampling frequency: srcSr * pitchRatio
            Resample: srcSr, resamplePrecision
            pitchedSeg = selected("Sound")
            removeObject: workedSeg, rawSeg
        else
            selectObject: rawSeg
            Copy: "seg_work"
            pitchedSeg = selected("Sound")
            removeObject: rawSeg
        endif

        # Lengthen for time stretch
        # After tape speed: duration = segDur / pitchRatio
        # Target duration  = segDur * timeRat
        # Lengthen factor  = timeRat * pitchRatio
        lenFactor = timeRat * pitchRatio
        if lenFactor < 0.1
            lenFactor = 0.1
        endif
        if lenFactor > 8.0
            lenFactor = 8.0
        endif
        if abs(lenFactor - 1.0) > 0.02
            selectObject: pitchedSeg
            Lengthen (overlap-add): pitchFloorHz, pitchCeilingHz, lenFactor
            stretchedSeg = selected("Sound")
            removeObject: pitchedSeg
        else
            stretchedSeg = pitchedSeg
        endif

        # Dynamic scaling
        selectObject: stretchedSeg
        Formula: "self * " + string$(dynScale)

        # 5ms click-prevention fades
        selectObject: stretchedSeg
        segFadeDur = Get total duration
        fadeSec = 0.005
        if fadeSec > segFadeDur * 0.1
            fadeSec = segFadeDur * 0.1
        endif
        if fadeSec > 0.001
            fsStr$ = fixed$(fadeSec, 8)
            Formula: "if x - xmin < " + fsStr$ + " then self * ((x - xmin) / " + fsStr$ + ") else self fi"
            Formula: "if xmax - x < " + fsStr$ + " then self * ((xmax - x) / " + fsStr$ + ") else self fi"
        endif

        # Append to assembly
        if hasAssembly = 0
            selectObject: stretchedSeg
            Copy: "var_asm"
            currentAssembly = selected("Sound")
            removeObject: stretchedSeg
            hasAssembly = 1
        else
            selectObject: currentAssembly
            plusObject: stretchedSeg
            newAsm = Concatenate with overlap: 0.02
            removeObject: currentAssembly, stretchedSeg
            currentAssembly = newAsm
        endif

    endfor

    selectObject: currentAssembly
    peakVal = Get absolute extremum: 0, 0, "None"
    if peakVal > 0
        Scale peak: 0.95
    endif
    Rename: srcName$ + "_mcmc_v" + string$(.vNum)
    lastVariation = currentAssembly
endproc

# ============================================================
# SETUP INFO
# ============================================================

clearinfo
writeInfoLine:  "=================================================="
writeInfoLine:  "  MCMC Musical Variation v1.3"
writeInfoLine:  "=================================================="
appendInfoLine: ""
appendInfoLine: "Source    : ", srcName$, " (", fixed$(srcDur, 2), " s)"
appendInfoLine: "Seed      : ", seedStr$
appendInfoLine: "Mode      : ", presetName$
appendInfoLine: "Speed     : ", speedStr$, "  (resample precision=",
    ... resamplePrecision, ")"
appendInfoLine: "PSOLA F0  : ", fixed$(pitchFloorHz, 0), " - ",
    ... fixed$(pitchCeilingHz, 0), " Hz"
appendInfoLine: "Phrases   : ", nPhrases
if phrasesTruncated = 1
    appendInfoLine: "WARNING: ", nPhrasesDetected,
        ... " phrases detected; only the first 20 are used ",
        ... "(later phrases are ignored)."
endif
for pp from 1 to nPhrases
    appendInfoLine: "  P", pp, ": ", fixed$(phraseStart_'pp', 2),
        ... " -> ", fixed$(phraseEnd_'pp', 2), " s  (",
        ... fixed$(phraseDur_'pp', 2), " s)"
endfor
appendInfoLine: ""
appendInfoLine: "Chain     : ", nSteps, " steps  |  thinning=", thin,
    ... "  |  T: ", fixed$(tStart, 2), " -> ", fixed$(tEnd, 2),
    ... "  anneal=", doAnneal
appendInfoLine: "MaxVar    : ", maxVar
appendInfoLine: "Weights   : E1=", fixed$(w1,1), " E2=", fixed$(w2,1),
    ... " E3=", fixed$(w3,1), " E4=", fixed$(w4,1),
    ... " E5=", fixed$(w5,1), " E6=", fixed$(w6,1), " E7=", fixed$(w7,1)
appendInfoLine: ""

# ============================================================
# COMPUTE INITIAL ENERGY
# ============================================================

@computeEnergy
currentEnergy = energyResult
appendInfoLine: "Initial energy: ", fixed$(currentEnergy, 4)
appendInfoLine: ""
appendInfoLine: "Running MCMC chain..."
appendInfoLine: ""

# ============================================================
# MCMC CHAIN
# ============================================================

nAccepted = 0
varCount  = 0

# Storage for trace and visualization
for s from 1 to nSteps
    eTrace_'s'  = currentEnergy
    accTrace_'s' = 0
endfor

# Store initial pitch contour for visualization
for pp from 1 to nPhrases
    initPc_'pp' = pc_'pp'
endfor

# Cumulative proposal weights
cum1 = pw1
cum2 = cum1 + pw2
cum3 = cum2 + pw3
cum4 = cum3 + pw4
cum5 = cum4 + pw5
cum6 = cum5 + pw6
cum7 = cum6 + pw7

for step from 1 to nSteps

    # Temperature schedule
    if doAnneal = 1 and nSteps > 1
        tCur = tStart + (tEnd - tStart) * (step - 1) / (nSteps - 1)
    else
        tCur = tStart
    endif

    # Save current state
    @saveState

    # Select and apply proposal
    u = randomUniform(0, 1)
    if u < cum1
        @proposePitchNudge
        propName$ = "PitchNudge"
    elsif u < cum2
        @proposeDynamicSwell
        propName$ = "DynSwell"
    elsif u < cum3
        @proposeMicroRubato
        propName$ = "Rubato"
    elsif u < cum4
        @proposePhraseTranspose
        propName$ = "PhrTrans"
    elsif u < cum5
        @proposeTemporalSwap
        propName$ = "TmSwap"
    elsif u < cum6
        @proposeGlobalTranspose
        propName$ = "GlobTrans"
    elsif u < cum7
        @proposeTempoWarp
        propName$ = "TempoWarp"
    else
        @proposeDynamicArch
        propName$ = "DynArch"
    endif

    # Compute proposed energy
    @computeEnergy
    proposedEnergy = energyResult

    # Metropolis-Hastings acceptance
    deltaE = proposedEnergy - currentEnergy
    if deltaE <= 0
        acceptProb = 1.0
    else
        if tCur > 0.001
            acceptProb = exp(-deltaE / tCur)
        else
            acceptProb = 0
        endif
    endif

    accepted = 0
    if randomUniform(0, 1) < acceptProb
        currentEnergy = proposedEnergy
        accepted = 1
        nAccepted = nAccepted + 1
    else
        @restoreState
    endif

    eTrace_'step'   = currentEnergy
    accTrace_'step' = accepted

    # Render variation at thinning interval if accepted
    if accepted = 1 and varCount < maxVar
        stepMod = step - floor(step / thin) * thin
        doRender = 0
        if stepMod = 0
            doRender = 1
        endif
        if doRender = 1
            varCount = varCount + 1
            appendInfoLine: "  [step ", step, "/", nSteps,
                ... "]  RENDER var ", varCount,
                ... "  E=", fixed$(currentEnergy, 3),
                ... "  T=", fixed$(tCur, 3),
                ... "  prop=", propName$
            # Store pitch contour snapshot for viz
            for pp from 1 to nPhrases
                varPc_'varCount'_'pp' = pc_'pp'
            endfor
            varTranspo_'varCount' = transpo
            varEnergy_'varCount'  = currentEnergy
            renderStep_'varCount' = step
            @renderVariation: varCount
            variation_'varCount' = lastVariation
        else
            appendInfoLine: "  [step ", step, "]  acc  E=",
                ... fixed$(currentEnergy, 4), "  T=", fixed$(tCur, 3),
                ... "  prop=", propName$
        endif
    else
        accStr$ = "rej"
        if accepted = 1
            accStr$ = "acc"
        endif
        appendInfoLine: "  [step ", step, "]  ", accStr$,
            ... "  E=", fixed$(currentEnergy, 4),
            ... "  T=", fixed$(tCur, 3),
            ... "  prop=", propName$
    endif

endfor

# v1.3: The loop above only renders on an accepted step that also
# lands on the thinning interval, so it is possible to reach the
# end of the chain with varCount = 0 (nothing rendered), which
# used to crash the multichannel-combine step below. Guarantee at
# least one rendered variation by rendering the chain's final
# state directly, independent of accept/thinning timing.
if varCount = 0
    varCount = 1
    appendInfoLine: "  [fallback]  no step was both accepted and on ",
        ... "the thinning interval -> rendering final chain state",
        ... "  E=", fixed$(currentEnergy, 3)
    for pp from 1 to nPhrases
        varPc_1_'pp' = pc_'pp'
    endfor
    varTranspo_1 = transpo
    varEnergy_1  = currentEnergy
    renderStep_1 = nSteps
    @renderVariation: 1
    variation_1 = lastVariation
endif

acceptRate = nAccepted / nSteps

appendInfoLine: ""
appendInfoLine: "Chain complete."
appendInfoLine: "  Accepted   : ", nAccepted, " / ", nSteps,
    ... "  (", fixed$(acceptRate * 100, 1), "%)"
appendInfoLine: "  Variations : ", varCount
appendInfoLine: "  Final E    : ", fixed$(currentEnergy, 4)

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization = 1 and varCount > 0

    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    # Get amplitude range from original
    selectObject: monoSrc
    origPeak = Get absolute extremum: 0, 0, "None"
    if origPeak < 0.001
        origPeak = 0.001
    endif
    ampMax = origPeak * 1.15

    # Get first variation duration
    selectObject: variation_1
    var1Dur = Get total duration

    Erase all

    # === TITLE ===
    Select outer viewport: 0, 8, 0, 0.28
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##MCMC Musical Variation v1.3.2##"
    Select outer viewport: 0, 8, 0.28, 0.50
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.5, "half",
        ... "[" + presetName$ + "]  " + srcName$
        ... + "  |  " + string$(nPhrases) + " phrases"
        ... + "  |  " + string$(nSteps) + " steps"
        ... + "  |  " + string$(varCount) + " variations"
        ... + "  |  acc " + fixed$(acceptRate*100, 0) + "%"

    # === PANEL 1: Original waveform ===
    Select outer viewport: 0, 4, 0.52, 1.42
    Select inner viewport: 0.55, 3.8, 0.57, 1.37
    Axes: 0, srcDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, srcDur, -ampMax, ampMax
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, srcDur, 0
    # Phrase boundaries
    for pp from 1 to nPhrases
        pBound = phraseStart_'pp'
        if pBound > 0.001
            Colour: "{0.70, 0.75, 0.85}"
            Dotted line
            Draw line: pBound, -ampMax, pBound, ampMax
            Solid line
        endif
    endfor
    selectObject: monoSrc
    Colour: "{0.45, 0.50, 0.60}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.08, 0.52, 0.52, 1.42
    Select inner viewport: 0.08, 0.52, 0.54, 1.4
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Source"
    Select outer viewport: 0, 4, 0.52, 1.42
    Select inner viewport: 0.55, 3.8, 0.57, 1.37
    Axes: 0, srcDur, -ampMax, ampMax
    Text top: "no", "Input  (dotted = phrase boundaries)"

    # === PANEL 2: Variation 1 waveform ===
    Select outer viewport: 4, 8, 0.52, 1.42
    Select inner viewport: 4.2, 7.8, 0.57, 1.37
    Axes: 0, var1Dur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, var1Dur, -ampMax, ampMax
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, var1Dur, 0
    selectObject: variation_1
    Colour: "{0.22, 0.48, 0.75}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 4.02, 4.4, 0.52, 1.42
    Select inner viewport: 4.02, 4.4, 0.54, 1.4
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Var 1"
    Select outer viewport: 4, 8, 0.52, 1.42
    Select inner viewport: 4.2, 7.8, 0.57, 1.37
    Axes: 0, var1Dur, -ampMax, ampMax
    Text top: "no", "Variation 1  (E=" + fixed$(varEnergy_1, 3) + ")"

    # === PANEL 3: Energy trace ===
    Select outer viewport: 0, 8, 1.50, 2.30
    Select inner viewport: 0.55, 7.75, 1.55, 2.12

    # Find min/max energy
    eMin = eTrace_1
    eMax = eTrace_1
    for s from 1 to nSteps
        if eTrace_'s' < eMin
            eMin = eTrace_'s'
        endif
        if eTrace_'s' > eMax
            eMax = eTrace_'s'
        endif
    endfor
    eRange = eMax - eMin
    if eRange < 0.01
        eRange = 0.01
    endif
    ePlotMin = eMin - eRange * 0.1
    ePlotMax = eMax + eRange * 0.15

    Axes: 1, nSteps, ePlotMin, ePlotMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 1, nSteps, ePlotMin, ePlotMax

    # Shade accepted steps
    for s from 1 to nSteps
        if accTrace_'s' = 1
            Paint rectangle: "{0.88, 0.94, 0.88}", s - 0.5, s + 0.5, ePlotMin, ePlotMax
        endif
    endfor

    # Mark render points
    for v from 1 to varCount
        # Exact step where this variation was rendered, recorded
        # at render time (v1.3) — not guessed from v * thin, since
        # a variation is only rendered on an accepted step that
        # also lands on the thinning interval.
        rStep = renderStep_'v'
        if rStep > nSteps
            rStep = nSteps
        endif
        Colour: "{0.80, 0.80, 0.95}"
        Paint rectangle: "{0.80, 0.80, 0.95}", rStep - 0.6, rStep + 0.6, ePlotMin, ePlotMax
    endfor

    # Draw energy line
    Colour: "{0.75, 0.25, 0.15}"
    Line width: 1.5
    for s from 1 to nSteps - 1
        sN = s + 1
        Draw line: s, eTrace_'s', sN, eTrace_'sN'
    endfor
    Line width: 1

    # Temperature overlay (normalized to energy axis)
    Colour: "{0.25, 0.50, 0.80}"
    Line width: 1
    Dotted line
    for s from 1 to nSteps - 1
        sN = s + 1
        if doAnneal = 1 and nSteps > 1
            tNorm1 = tStart + (tEnd - tStart) * (s - 1) / (nSteps - 1)
            tNorm2 = tStart + (tEnd - tStart) * (sN - 1) / (nSteps - 1)
        else
            tNorm1 = tStart
            tNorm2 = tStart
        endif
        # Scale T to energy plot range
        tPlot1 = ePlotMin + (tNorm1 / (tStart + 0.001)) * eRange * 0.3
        tPlot2 = ePlotMin + (tNorm2 / (tStart + 0.001)) * eRange * 0.3
        Draw line: s, tPlot1, sN, tPlot2
    endfor
    Solid line
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.08, 0.52, 1.50, 2.30
    Select inner viewport: 0.08, 0.52, 1.52, 2.28
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Energy"
    Select outer viewport: 0, 8, 1.50, 2.30
    Select inner viewport: 0.55, 7.75, 1.55, 2.12
    Axes: 1, nSteps, ePlotMin, ePlotMax
    Text bottom: "yes", "MCMC step"
    Text top: "no",
        ... "Energy trace  (green=accepted  blue=render  red=energy  dotted=T)"

    # === PANEL 4: Pitch contour heatmap (variation x phrase) ===
    Select outer viewport: 0, 4, 2.55, 3.65
    Select inner viewport: 0.55, 3.8, 2.60, 3.43

    if varCount > 1 and nPhrases > 1
        Axes: 0, nPhrases, 0, varCount
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, nPhrases, 0, varCount

        # Find pitch range across all variations
        pcMin = 0
        pcMax = 0
        for v from 1 to varCount
            vt = varTranspo_'v'
            for pp from 1 to nPhrases
                pcVal = varPc_'v'_'pp' + vt
                if pcVal < pcMin
                    pcMin = pcVal
                endif
                if pcVal > pcMax
                    pcMax = pcVal
                endif
            endfor
        endfor
        pcRange = pcMax - pcMin
        if pcRange < 1
            pcRange = 1
        endif

        for v from 1 to varCount
            vt = varTranspo_'v'
            for pp from 1 to nPhrases
                pcVal = varPc_'v'_'pp' + vt
                norm = (pcVal - pcMin) / pcRange
                # Blue (low) to Red (high)
                cR = 0.15 + norm * 0.70
                cG = 0.30 + norm * 0.10
                cB = 0.75 - norm * 0.55
                cRs$ = fixed$(cR, 2)
                cGs$ = fixed$(cG, 2)
                cBs$ = fixed$(cB, 2)
                Paint rectangle: "{" + cRs$ + "," + cGs$ + "," + cBs$ + "}",
                    ... pp - 1, pp, v - 1, v
            endfor
        endfor

        Colour: "Black"
        Draw inner box
        Font size: 7
        Select outer viewport: 0.08, 0.52, 2.55, 3.65
        Select inner viewport: 0.08, 0.52, 2.57, 3.63
        Axes: 0, 1, 0, 1
        Font size: 7
        Colour: "Black"
        Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Variation"
        Select outer viewport: 0, 4, 2.55, 3.65
        Select inner viewport: 0.55, 3.8, 2.60, 3.43
        Axes: 0, nPhrases, 0, varCount
        Text bottom: "yes", "Phrase"
        Text top: "no", "Pitch contour  (blue=low  red=high)"
    else
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1
        Font size: 7
        Colour: "{0.5, 0.5, 0.5}"
        Text: 0.5, "centre", 0.5, "half", "Need >1 var + >1 phrase for heatmap"
        Colour: "Black"
        Draw inner box
    endif

    # === PANEL 5: Per-variation energy bar chart ===
    Select outer viewport: 4, 8, 2.55, 3.65
    Select inner viewport: 4.2, 7.8, 2.60, 3.43

    vEmin = varEnergy_1
    vEmax = varEnergy_1
    for v from 1 to varCount
        if varEnergy_'v' < vEmin
            vEmin = varEnergy_'v'
        endif
        if varEnergy_'v' > vEmax
            vEmax = varEnergy_'v'
        endif
    endfor
    vErange = vEmax - vEmin
    if vErange < 0.01
        vErange = 0.01
    endif
    vEplotMax = vEmax + vErange * 0.15

    Axes: 0, varCount + 1, 0, vEplotMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, varCount + 1, 0, vEplotMax

    for v from 1 to varCount
        norm = (varEnergy_'v' - vEmin) / vErange
        cR = 0.25 + norm * 0.55
        cG = 0.60 - norm * 0.25
        cB = 0.35
        cRs$ = fixed$(cR, 2)
        cGs$ = fixed$(cG, 2)
        cBs$ = fixed$(cB, 2)
        Paint rectangle: "{" + cRs$ + "," + cGs$ + "," + cBs$ + "}",
            ... v - 0.35, v + 0.35, 0, varEnergy_'v'
        # Label
        Font size: 6
        Colour: "White"
        Text: v, "centre", varEnergy_'v' * 0.5, "half", "V" + string$(v)
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 4.02, 4.4, 2.55, 3.65
    Select inner viewport: 4.02, 4.4, 2.57, 3.63
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Energy"
    Select outer viewport: 4, 8, 2.55, 3.65
    Select inner viewport: 4.2, 7.8, 2.60, 3.43
    Axes: 0, varCount + 1, 0, vEplotMax
    Text bottom: "yes", "Variation"
    Text top: "no", "Energy per rendered variation  (lower = better fit to the selected energy criteria)"

    # === PANEL 6: SUMMARY ===
    Select outer viewport: 0, 8, 3.95, 4.95
    Select inner viewport: 0.60, 7.70, 4.02, 4.88
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.88, "half", "##MCMC Musical Variation v1.3.2##"
    Font size: 6
    Colour: "{0.35, 0.35, 0.40}"
    Text: 0.02, "left", 0.68, "half",
        ... "Source: " + srcName$ + "  (" + fixed$(srcDur,2) + " s)"
        ... + "  |  Mode: " + presetName$
        ... + "  |  Phrases: " + string$(nPhrases)
        ... + "  |  T: " + fixed$(tStart,2) + " -> " + fixed$(tEnd,2)
    Text: 0.02, "left", 0.48, "half",
        ... "Steps: " + string$(nSteps)
        ... + "  |  Accepted: " + string$(nAccepted)
        ... + "  (" + fixed$(acceptRate*100,1) + "%)"
        ... + "  |  Rendered: " + string$(varCount)
        ... + "  |  Thinning: " + string$(thin)
    Text: 0.02, "left", 0.28, "half",
        ... "E weights: scale=" + fixed$(w1,1)
        ... + " voice=" + fixed$(w2,1)
        ... + " range=" + fixed$(w3,1)
        ... + " rhythm=" + fixed$(w4,1)
        ... + " dyn=" + fixed$(w5,1)
        ... + " phrase=" + fixed$(w6,1)
        ... + " contour=" + fixed$(w7,1)
    Text: 0.02, "left", 0.10, "half",
        ... "Initial E=" + fixed$(eTrace_1,3)
        ... + "  Final E=" + fixed$(currentEnergy,3)
        ... + "  Delta=" + fixed$(currentEnergy - eTrace_1, 3)
        ... + "  Tonal center: " + string$(tonalCenter) + " st"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Select outer viewport: 0, 8, 0, 5.05
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
    Font size: 10
    Colour: "Black"
    Line width: 1

    appendInfoLine: "  Visualization complete."
endif

# ============================================================
# CLEANUP
# ============================================================

removeObject: monoSrc

# ============================================================
# OUTPUT
# ============================================================

appendInfoLine: ""
appendInfoLine: "=================================================="
appendInfoLine: "  COMPLETE  -  ", varCount, " variations"
appendInfoLine: "=================================================="
appendInfoLine: ""
for v from 1 to varCount
    selectObject: variation_'v'
    vName$ = selected$("Sound")
    vDurOut = Get total duration
    appendInfoLine: "  Var ", v, ": ", vName$,
        ... "  (", fixed$(vDurOut, 2), " s)",
        ... "  E=", fixed$(varEnergy_'v', 3),
        ... "  transpo=", varTranspo_'v', " st"
endfor

# Combine all variations into a multichannel sound and play.
# Each variation goes to a separate channel (up to maxVar).
# Variations are zero-padded to the longest duration before combining.
# Note: despite Praat calling this action "Combine to stereo", the
# result has N channels equal to the number of selected mono sounds.
# When varCount > 2, this is a multichannel file, not stereo.

appendInfoLine: ""
appendInfoLine: "Combining variations into multichannel mix..."

# Find longest variation duration
maxVarDur = 0
for v from 1 to varCount
    selectObject: variation_'v'
    vd = Get total duration
    if vd > maxVarDur
        maxVarDur = vd
    endif
endfor

# Pad each variation to maxVarDur
for v from 1 to varCount
    selectObject: variation_'v'
    vd = Get total duration
    if maxVarDur - vd > 0.005
        padDur = maxVarDur - vd
        Create Sound from formula: "pad", 1, 0, padDur, srcSr, "0"
        padSnd = selected("Sound")
        selectObject: variation_'v'
        plusObject: padSnd
        paddedVar = Concatenate
        removeObject: variation_'v', padSnd
        variation_'v' = paddedVar
        Rename: srcName$ + "_mcmc_v" + string$(v)
    endif
endfor

# Select all and combine to multichannel.
# "Combine to stereo" requires 2+ selected mono sounds; with a
# single variation (fallback case, Max_variations=1, or only one
# thinning point ever accepted) there is nothing to combine, so
# that case is copied through directly instead.
if varCount = 1
    selectObject: variation_1
    mcmcMulti = Copy: srcName$ + "_mcmc_output"
    outName$ = srcName$ + "_mcmc_output"
else
    selectObject: variation_1
    for v from 2 to varCount
        plusObject: variation_'v'
    endfor
    Combine to stereo
    mcmcMulti = selected("Sound")
    Rename: srcName$ + "_mcmc_multichannel"
    outName$ = srcName$ + "_mcmc_multichannel"
endif

if varCount = 1
    chanWord$ = "channel"
else
    chanWord$ = "channels"
endif
appendInfoLine: "  Combined: ", outName$, "  (",
    ... string$(varCount), " ", chanWord$, ")"

selectObject: mcmcMulti
Scale peak: 0.95

if varCount > 2
    appendInfoLine: "  Note: ", varCount, " channels - most audio ",
        ... "interfaces are stereo, so playback will only expose ",
        ... "2 of them meaningfully. Use Keep_individual_variations ",
        ... "to inspect the others individually."
endif

if play = 1
    appendInfoLine: ""
    appendInfoLine: "Playing..."
    Play
else
    appendInfoLine: ""
    appendInfoLine: "  (Play = off, not auto-playing. The combined ",
        ... "sound is available in the Objects list.)"
endif

# Remove individual variations unless user asked to keep them
if keep_individual_variations = 0
    for v from 1 to varCount
        removeObject: variation_'v'
    endfor
    appendInfoLine: "  Individual variations removed (keep_individual_variations = off)"
else
    appendInfoLine: "  Individual variations kept in Objects list"
    selectObject: mcmcMulti
endif
