# ============================================================
# Praat AudioTools - MCMC_Musical_Variation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.4 (2026)
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

form MCMC Musical Variation v1.3.1
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
# Cancellation-safe: preserve the ordinary channel average unless
# it nearly cancels relative to the strongest source channel.
# ============================================================

selectObject: srcSound
if srcCh > 1
    strongestChannel = 1
    strongestRms = -1
    for ch from 1 to srcCh
        selectObject: srcSound
        tmpChannel = Extract one channel: ch
        channelRms = Get root-mean-square: 0, 0
        if channelRms > strongestRms
            strongestRms = channelRms
            strongestChannel = ch
        endif
        removeObject: tmpChannel
    endfor

    selectObject: srcSound
    avgSrc = Convert to mono
    selectObject: avgSrc
    averageRms = Get root-mean-square: 0, 0

    if strongestRms > 1e-12 and averageRms < 0.10 * strongestRms
        removeObject: avgSrc
        selectObject: srcSound
        monoSrc = Extract one channel: strongestChannel
        Rename: "mcmc_src"
        appendInfoLine: "Mono source: channel average nearly cancelled; using strongest channel " + string$(strongestChannel) + "."
    else
        monoSrc = avgSrc
        selectObject: monoSrc
        Rename: "mcmc_src"
    endif
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
writeInfoLine:  "  MCMC Musical Variation v1.3.1"
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
initialEnergy = currentEnergy

# Component values of the CURRENT (accepted) state.  computeEnergy leaves
# e1..e7 holding whatever it last evaluated, which after a REJECTED step is
# the proposal, not the state — so these are only refreshed on acceptance.
curE1 = e1
curE2 = e2
curE3 = e3
curE4 = e4
curE5 = e5
curE6 = e6
curE7 = e7

# Per-proposal-type diagnostics
moveName$ [1] = "PitchNudge"
moveName$ [2] = "DynSwell"
moveName$ [3] = "Rubato"
moveName$ [4] = "PhrTrans"
moveName$ [5] = "TmSwap"
moveName$ [6] = "GlobTrans"
moveName$ [7] = "TempoWarp"
moveName$ [8] = "DynArch"
for k from 1 to 8
    propTried [k] = 0
    propOk    [k] = 0
    propDsum  [k] = 0
endfor
appendInfoLine: "Initial energy: ", fixed$(initialEnergy, 4)
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
        propIdx = 1
    elsif u < cum2
        @proposeDynamicSwell
        propName$ = "DynSwell"
        propIdx = 2
    elsif u < cum3
        @proposeMicroRubato
        propName$ = "Rubato"
        propIdx = 3
    elsif u < cum4
        @proposePhraseTranspose
        propName$ = "PhrTrans"
        propIdx = 4
    elsif u < cum5
        @proposeTemporalSwap
        propName$ = "TmSwap"
        propIdx = 5
    elsif u < cum6
        @proposeGlobalTranspose
        propName$ = "GlobTrans"
        propIdx = 6
    elsif u < cum7
        @proposeTempoWarp
        propName$ = "TempoWarp"
        propIdx = 7
    else
        @proposeDynamicArch
        propName$ = "DynArch"
        propIdx = 8
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

    # --- chain diagnostics (v1.4) -----------------------------------
    if accepted = 1
        curE1 = e1
        curE2 = e2
        curE3 = e3
        curE4 = e4
        curE5 = e5
        curE6 = e6
        curE7 = e7
    endif
    ecTrace_1_'step' = w1 * curE1
    ecTrace_2_'step' = w2 * curE2
    ecTrace_3_'step' = w3 * curE3
    ecTrace_4_'step' = w4 * curE4
    ecTrace_5_'step' = w5 * curE5
    ecTrace_6_'step' = w6 * curE6
    ecTrace_7_'step' = w7 * curE7
    tTrace_'step'  = tCur
    dTrace_'step'  = deltaE
    piTrace_'step' = propIdx
    propTried [propIdx] = propTried [propIdx] + 1
    propDsum  [propIdx] = propDsum  [propIdx] + deltaE
    if accepted = 1
        propOk [propIdx] = propOk [propIdx] + 1
    endif

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

# All stochastic proposal and acceptance draws are complete. Return
# Praat's global RNG to safe/unpredictable mode so a fixed Seed here
# cannot make a subsequently-run script deterministic.
random_initializeSafelyAndUnpredictably ()

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
#
# Canvas: 8.0 x 8.95 in.
#
#   Source waveform | Variation 1 waveform     (half-width pair)
#   Energy trace + temperature                 (full width)
#   Energy component breakdown                 (full width)
#   Proposal diagnostics                       (full width)
#   Pitch contour heatmap | per-variation E    (half-width pair)
#   Summary
#
# Every panel is numbered on both axes.  v1.3 had axis LABELS but no ticks
# and no numbers anywhere, so no value could be read off any panel.
# ============================================================

if draw_visualization = 1 and varCount > 0

    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    canvasH = 8.95

    # Absolute page x for the rotated rail labels: one for the left/full
    # panels, one for the right-hand half panels, so every rail lines up
    # regardless of how wide its panel is.
    railLeft  = 0.30
    railRight = 3.98

    selectObject: monoSrc
    origPeak = Get absolute extremum: 0, 0, "None"
    if origPeak < 0.001
        origPeak = 0.001
    endif
    ampMax = origPeak * 1.15

    selectObject: variation_1
    var1Dur = Get total duration

    Erase all
    Select outer viewport: 0, 8, 0, canvasH

    # === TITLE =======================================================
    # Text strips must use Select INNER viewport: Axes maps to the inner
    # viewport, so an outer-viewport strip is silently inset by the standard
    # margins and the two lines collapse onto each other.
    Font size: 12
    Select inner viewport: 0.6, 7.7, 0.04, 0.38
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.80, "half", "##MCMC Musical Variation##"
    Font size: 7
    Select inner viewport: 0.6, 7.7, 0.04, 0.38
    Axes: 0, 1, 0, 1
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.18, "half",
        ... "[" + presetName$ + "]  " + srcName$
        ... + "  |  " + string$(nPhrases) + " phrases"
        ... + "  |  " + string$(nSteps) + " steps"
        ... + "  |  " + string$(varCount) + " variations"
        ... + "  |  acc " + fixed$(acceptRate*100, 0) + "\%  "

    @niceTick: srcDur
    tickSrc = niceTick.t
    @niceTick: var1Dur
    tickVar = niceTick.t

    # === PANEL 1: Source waveform ====================================
    Font size: 7
    Select outer viewport: 0, 4, 0.44, 1.16
    Select inner viewport: 0.60, 3.75, 0.54, 1.06
    Axes: 0, srcDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, srcDur, -ampMax, ampMax
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, srcDur, 0
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
    Select inner viewport: 0.60, 3.75, 0.54, 1.06
    Axes: 0, srcDur, -ampMax, ampMax
    Marks bottom every: 1, tickSrc, "yes", "yes", "no"
    Text bottom: "yes", "Source time (s)"
    Text top: "no", "Input  (dotted = phrase boundaries)"
    @railLabelAt: 0.60, 3.75, 0.54, 1.06, 7, railLeft, "Source"

    # === PANEL 2: Variation 1 waveform ===============================
    Font size: 7
    Select outer viewport: 4, 8, 0.44, 1.16
    Select inner viewport: 4.25, 7.70, 0.54, 1.06
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
    Select inner viewport: 4.25, 7.70, 0.54, 1.06
    Axes: 0, var1Dur, -ampMax, ampMax
    Marks bottom every: 1, tickVar, "yes", "yes", "no"
    Text bottom: "yes", "Variation time (s)"
    Text top: "no", "Variation 1  (E=" + fixed$(varEnergy_1, 3) + ")"
    @railLabelAt: 4.25, 7.70, 0.54, 1.06, 7, railRight, "Var 1"

    # =================================================================
    # === PANEL 3: Energy trace + temperature =========================
    #
    # v1.3 shaded every accepted step with a green column.  At a 90%+
    # acceptance rate that washes the whole panel and carries no signal,
    # so acceptance is now a row of tick marks along the top instead.
    # Temperature had been squeezed onto the energy axis at an arbitrary
    # 30% of the energy range, giving a line whose height meant nothing;
    # it now has its own right-hand axis, numbered.
    # =================================================================
    etX1 = 0.60
    etX2 = 7.70
    etY1 = 1.66
    etY2 = 2.62

    Select outer viewport: 0, 8, 1.54, 2.72

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
    if initialEnergy < eMin
        eMin = initialEnergy
    endif
    if initialEnergy > eMax
        eMax = initialEnergy
    endif
    eRange = eMax - eMin
    if eRange < 0.01
        eRange = 0.01
    endif
    ePlotMin = eMin - eRange * 0.10
    ePlotMax = eMax + eRange * 0.22

    tHi = tStart
    if tEnd > tHi
        tHi = tEnd
    endif
    tHi = tHi * 1.15
    if tHi < 0.01
        tHi = 0.01
    endif

    @niceTick: nSteps
    tickStep = niceTick.t
    @niceTick: ePlotMax - ePlotMin
    tickE = niceTick.t
    @niceTick: tHi
    tickT = niceTick.t

    Font size: 6
    Select inner viewport: etX1, etX2, etY1, etY2
    Axes: 1, nSteps, ePlotMin, ePlotMax
    Paint rectangle: "{0.975, 0.977, 0.985}", 1, nSteps, ePlotMin, ePlotMax

    Colour: "{0.88, 0.89, 0.93}"
    Line width: 1
    gV = tickStep
    while gV < nSteps
        Draw line: gV, ePlotMin, gV, ePlotMax
        gV += tickStep
    endwhile

    # Render points: full-height columns
    for v from 1 to varCount
        rStep = renderStep_'v'
        if rStep > nSteps
            rStep = nSteps
        endif
        Paint rectangle: "{0.86, 0.86, 0.96}", rStep - 0.45, rStep + 0.45, ePlotMin, ePlotMax
    endfor

    # Acceptance as a tick row along the top of the panel
    accY1 = ePlotMax - (ePlotMax - ePlotMin) * 0.055
    accY2 = ePlotMax
    for s from 1 to nSteps
        if accTrace_'s' = 1
            Paint rectangle: "{0.25, 0.60, 0.30}", s - 0.42, s + 0.42, accY1, accY2
        else
            Paint rectangle: "{0.82, 0.30, 0.25}", s - 0.42, s + 0.42, accY1, accY2
        endif
    endfor
    Colour: "{0.55, 0.55, 0.58}"
    Line width: 1
    Draw line: 1, accY1, nSteps, accY1

    # Starting energy reference
    Colour: "{0.60, 0.60, 0.65}"
    Dashed line
    Draw line: 1, initialEnergy, nSteps, initialEnergy
    Solid line

    # Best energy reached so far
    bestSoFar = eTrace_1
    Colour: "{0.35, 0.55, 0.35}"
    Line width: 1
    for s from 1 to nSteps - 1
        sN = s + 1
        b1 = bestSoFar
        if eTrace_'sN' < bestSoFar
            bestSoFar = eTrace_'sN'
        endif
        Draw line: s, b1, sN, bestSoFar
    endfor

    # Energy trace
    Colour: "{0.75, 0.25, 0.15}"
    Line width: 1.5
    for s from 1 to nSteps - 1
        sN = s + 1
        Draw line: s, eTrace_'s', sN, eTrace_'sN'
    endfor
    Line width: 1

    # Temperature on its own right-hand scale
    Font size: 6
    Select inner viewport: etX1, etX2, etY1, etY2
    Axes: 1, nSteps, 0, tHi
    Colour: "{0.25, 0.50, 0.80}"
    Line width: 1.2
    Dotted line
    for s from 1 to nSteps - 1
        sN = s + 1
        Draw line: s, tTrace_'s', sN, tTrace_'sN'
    endfor
    Solid line
    Line width: 1
    Marks right every: 1, tickT, "yes", "yes", "no"

    Font size: 6
    Select inner viewport: etX1, etX2, etY1, etY2
    Axes: 1, nSteps, ePlotMin, ePlotMax
    Colour: "Black"
    Line width: 1
    Draw inner box

    Font size: 6
    Select inner viewport: etX1, etX2, etY1, etY2
    Axes: 1, nSteps, ePlotMin, ePlotMax
    Marks bottom every: 1, tickStep, "yes", "yes", "no"
    Marks left every: 1, tickE, "yes", "yes", "no"

    Font size: 7
    Select inner viewport: etX1, etX2, etY1, etY2
    Axes: 1, nSteps, ePlotMin, ePlotMax
    Text bottom: "yes", "MCMC step"
    Text top: "no", "##Energy trace##  —  red = total E, green line = best so far, dashed = start, ticks (top): green = accepted, red = rejected, lilac = render, dotted blue = temperature, numbered on the RIGHT axis"
    @railLabelAt: etX1, etX2, etY1, etY2, 7, railLeft, "Energy"

    # =================================================================
    # === PANEL 4: Energy component breakdown =========================
    #
    # Each term is plotted WEIGHTED (wN * eN), which is what actually
    # competes inside the total, so a term with a small raw value but a
    # large weight is not made to look harmless.
    # =================================================================
    ecX1 = 0.60
    ecX2 = 7.70
    ecY1 = 3.22
    ecY2 = 4.12

    Select outer viewport: 0, 8, 3.10, 4.22

    ecMax = 0
    for k from 1 to 7
        for s from 1 to nSteps
            if ecTrace_'k'_'s' > ecMax
                ecMax = ecTrace_'k'_'s'
            endif
        endfor
    endfor
    if ecMax < 0.01
        ecMax = 0.01
    endif
    ecPlotMax = ecMax * 1.30
    @niceTick: ecPlotMax
    tickEc = niceTick.t

    Font size: 6
    Select inner viewport: ecX1, ecX2, ecY1, ecY2
    Axes: 1, nSteps, 0, ecPlotMax
    Paint rectangle: "{0.975, 0.977, 0.985}", 1, nSteps, 0, ecPlotMax

    Colour: "{0.88, 0.89, 0.93}"
    gV = tickStep
    while gV < nSteps
        Draw line: gV, 0, gV, ecPlotMax
        gV += tickStep
    endwhile

    ecCol$ [1] = "{0.85, 0.20, 0.20}"
    ecCol$ [2] = "{0.95, 0.55, 0.10}"
    ecCol$ [3] = "{0.80, 0.72, 0.10}"
    ecCol$ [4] = "{0.20, 0.65, 0.30}"
    ecCol$ [5] = "{0.15, 0.55, 0.80}"
    ecCol$ [6] = "{0.45, 0.25, 0.75}"
    ecCol$ [7] = "{0.75, 0.30, 0.60}"
    ecName$ [1] = "scale"
    ecName$ [2] = "voice"
    ecName$ [3] = "range"
    ecName$ [4] = "rhythm"
    ecName$ [5] = "dyn"
    ecName$ [6] = "phrase"
    ecName$ [7] = "contour"

    Line width: 1.3
    for k from 1 to 7
        Colour: ecCol$ [k]
        for s from 1 to nSteps - 1
            sN = s + 1
            Draw line: s, ecTrace_'k'_'s', sN, ecTrace_'k'_'sN'
        endfor
    endfor
    Line width: 1

    # Legend strip along the top of the panel
    Font size: 5
    Select inner viewport: ecX1, ecX2, ecY1, ecY2
    Axes: 0, 1, 0, 1
    Paint rectangle: "White", 0.008, 0.700, 0.905, 0.988
    Colour: "{0.70, 0.70, 0.75}"
    Draw rectangle: 0.008, 0.700, 0.905, 0.988
    for k from 1 to 7
        lgx = 0.020 + (k - 1) * 0.0965
        Colour: ecCol$ [k]
        Line width: 2
        Draw line: lgx, 0.946, lgx + 0.020, 0.946
        Line width: 1
        Colour: "{0.20, 0.20, 0.24}"
        Text: lgx + 0.026, "left", 0.946, "half", ecName$ [k]
    endfor

    Font size: 6
    Select inner viewport: ecX1, ecX2, ecY1, ecY2
    Axes: 1, nSteps, 0, ecPlotMax
    Colour: "Black"
    Line width: 1
    Draw inner box

    Font size: 6
    Select inner viewport: ecX1, ecX2, ecY1, ecY2
    Axes: 1, nSteps, 0, ecPlotMax
    Marks bottom every: 1, tickStep, "yes", "yes", "no"
    Marks left every: 1, tickEc, "yes", "yes", "no"

    Font size: 7
    Select inner viewport: ecX1, ecX2, ecY1, ecY2
    Axes: 1, nSteps, 0, ecPlotMax
    Text bottom: "yes", "MCMC step"
    Text top: "no", "##Energy components##  —  weighted contribution of each criterion to the total above"
    @railLabelAt: ecX1, ecX2, ecY1, ecY2, 7, railLeft, "Weighted E"

    # =================================================================
    # === PANEL 5: Proposal diagnostics ===============================
    #
    # Per move type: how often it was tried, how often it was accepted,
    # and its mean deltaE.  This is the panel to read when tuning the
    # proposal weights — a move with a high accept rate and a mean deltaE
    # near zero is doing nothing but burning steps.
    # =================================================================
    pdX1 = 0.60
    pdX2 = 7.70
    pdY1 = 4.72
    pdY2 = 5.62

    Select outer viewport: 0, 8, 4.60, 5.72

    pdTriedMax = 1
    for k from 1 to 8
        if propTried [k] > pdTriedMax
            pdTriedMax = propTried [k]
        endif
    endfor
    pdPlotMax = pdTriedMax * 1.35

    Font size: 6
    Select inner viewport: pdX1, pdX2, pdY1, pdY2
    Axes: 0.4, 8.6, 0, pdPlotMax
    Paint rectangle: "{0.975, 0.977, 0.985}", 0.4, 8.6, 0, pdPlotMax

    for k from 1 to 8
        # tried (pale) with accepted (solid) drawn inside it
        Paint rectangle: "{0.80, 0.83, 0.90}", k - 0.34, k + 0.34, 0, propTried [k]
        Paint rectangle: "{0.20, 0.45, 0.72}", k - 0.34, k + 0.34, 0, propOk [k]
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box

    # Labels: name, n, accept rate and mean deltaE per move
    Font size: 5
    Select inner viewport: pdX1, pdX2, pdY1, pdY2
    Axes: 0.4, 8.6, 0, pdPlotMax
    for k from 1 to 8
        if propTried [k] > 0
            pdRate = propOk [k] / propTried [k]
            pdMeanD = propDsum [k] / propTried [k]
            pdLab$ = string$(propOk [k]) + "/" + string$(propTried [k])
            pdLab2$ = fixed$(pdRate * 100, 0) + "\%  dE " + fixed$(pdMeanD, 2)
        else
            pdLab$ = "0/0"
            pdLab2$ = "not tried"
        endif
        Colour: "{0.20, 0.20, 0.24}"
        Text: k, "centre", propTried [k] + pdPlotMax * 0.135, "half", pdLab$
        Colour: "{0.45, 0.45, 0.50}"
        Text: k, "centre", propTried [k] + pdPlotMax * 0.055, "half", pdLab2$
    endfor

    Font size: 6
    Select inner viewport: pdX1, pdX2, pdY1, pdY2
    Axes: 0.4, 8.6, 0, pdPlotMax
    @niceTick: pdPlotMax
    tickPd = niceTick.t
    Marks left every: 1, tickPd, "yes", "yes", "no"
    for k from 1 to 8
        One mark bottom: k, "no", "yes", "no", moveName$ [k]
    endfor

    Font size: 7
    Select inner viewport: pdX1, pdX2, pdY1, pdY2
    Axes: 0.4, 8.6, 0, pdPlotMax
    Text bottom: "yes", "Proposal type"
    Text top: "no", "##Proposal diagnostics##  —  pale = proposed, solid = accepted; labels give accepted/tried, accept rate and mean dE (proposed minus current)"
    @railLabelAt: pdX1, pdX2, pdY1, pdY2, 7, railLeft, "Steps"

    # =================================================================
    # === PANEL 6: Pitch contour heatmap ==============================
    #
    # Row 0 is the UNCHANGED starting contour (initPc), which v1.3 stored
    # but never drew — without it there is nothing to read the variations
    # against.  Cells now carry their semitone value.
    # =================================================================
    hmX1 = 0.60
    hmX2 = 3.75
    hmY1 = 6.22
    hmY2 = 7.22

    Select outer viewport: 0, 4, 6.10, 7.32

    if nPhrases > 0
        pcMin = initPc_1
        pcMax = initPc_1
        for pp from 1 to nPhrases
            if initPc_'pp' < pcMin
                pcMin = initPc_'pp'
            endif
            if initPc_'pp' > pcMax
                pcMax = initPc_'pp'
            endif
        endfor
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

        Font size: 6
        Select inner viewport: hmX1, hmX2, hmY1, hmY2
        Axes: 0, nPhrases, -1, varCount
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, nPhrases, -1, varCount

        showCellText = 0
        if nPhrases <= 10 and varCount <= 10
            showCellText = 1
        endif

        for v from 0 to varCount
            for pp from 1 to nPhrases
                if v = 0
                    pcVal = initPc_'pp'
                else
                    pcVal = varPc_'v'_'pp' + varTranspo_'v'
                endif
                norm = (pcVal - pcMin) / pcRange
                cR = 0.15 + norm * 0.70
                cG = 0.30 + norm * 0.10
                cB = 0.75 - norm * 0.55
                cRs$ = fixed$(cR, 2)
                cGs$ = fixed$(cG, 2)
                cBs$ = fixed$(cB, 2)
                yLo = v - 1
                yHi = v
                Paint rectangle: "{" + cRs$ + "," + cGs$ + "," + cBs$ + "}",
                    ... pp - 1, pp, yLo, yHi
                if showCellText = 1
                    Font size: 5
                    Colour: "White"
                    Text: pp - 0.5, "centre", yLo + 0.5, "half", fixed$(pcVal, 0)
                endif
            endfor
        endfor

        # Separate the reference row from the variations
        Font size: 6
        Select inner viewport: hmX1, hmX2, hmY1, hmY2
        Axes: 0, nPhrases, -1, varCount
        Colour: "White"
        Line width: 2
        Draw line: 0, 0, nPhrases, 0
        Line width: 1
        Colour: "Black"
        Draw inner box

        Font size: 6
        Select inner viewport: hmX1, hmX2, hmY1, hmY2
        Axes: 0, nPhrases, -1, varCount
        @niceTick: nPhrases
        tickPh = niceTick.t
        if tickPh < 1
            tickPh = 1
        endif
        Marks bottom every: 1, tickPh, "yes", "yes", "no"
        One mark left: -0.5, "no", "yes", "no", "##src##"
        hmEvery = 1
        if varCount > 12
            hmEvery = 2
        endif
        if varCount > 24
            hmEvery = 5
        endif
        for v from 1 to varCount
            vMod = v - floor(v / hmEvery) * hmEvery
            if vMod = 0 or hmEvery = 1
                One mark left: v - 0.5, "no", "yes", "no", "V" + string$(v)
            endif
        endfor

        Font size: 7
        Select inner viewport: hmX1, hmX2, hmY1, hmY2
        Axes: 0, nPhrases, -1, varCount
        Text bottom: "yes", "Phrase"
        Text top: "no", "Pitch contour, semitones  (blue " + fixed$(pcMin, 0) + " to red " + fixed$(pcMax, 0) + "; row ##src## = unchanged source)"
        @railLabelAt: hmX1, hmX2, hmY1, hmY2, 7, railLeft, "Variation"
    else
        Font size: 7
        Select inner viewport: hmX1, hmX2, hmY1, hmY2
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1
        Colour: "{0.5, 0.5, 0.5}"
        Text: 0.5, "centre", 0.5, "half", "No phrases detected"
        Colour: "Black"
        Select inner viewport: hmX1, hmX2, hmY1, hmY2
        Axes: 0, 1, 0, 1
        Draw rectangle: 0, 1, 0, 1
    endif

    # === PANEL 7: Per-variation energy bar chart =====================
    beX1 = 4.25
    beX2 = 7.70
    beY1 = 6.22
    beY2 = 7.22

    Select outer viewport: 4, 8, 6.10, 7.32

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
    # A single variation gives vErange = 0, so the headroom for the value
    # labels has to come from the bar height, not from the spread.
    if vErange < vEmax * 0.05
        vErange = vEmax * 0.05
    endif
    if vErange < 0.01
        vErange = 0.01
    endif
    vEplotMax = vEmax + vErange * 0.28
    if vEplotMax < vEmax * 1.10
        vEplotMax = vEmax * 1.10
    endif
    @niceTick: vEplotMax
    tickVe = niceTick.t

    # Centre a small number of bars instead of letting one bar fill the panel
    beHalf = varCount / 2 + 0.1
    if beHalf < 2.1
        beHalf = 2.1
    endif
    beCtr = (varCount + 1) / 2
    beLo = beCtr - beHalf
    beHi = beCtr + beHalf

    Font size: 6
    Select inner viewport: beX1, beX2, beY1, beY2
    Axes: beLo, beHi, 0, vEplotMax
    Paint rectangle: "{0.975, 0.977, 0.985}", beLo, beHi, 0, vEplotMax

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
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box

    Font size: 5
    Select inner viewport: beX1, beX2, beY1, beY2
    Axes: beLo, beHi, 0, vEplotMax
    for v from 1 to varCount
        # Inside the bar where it fits, above it only for very short bars —
        # a value printed above a full-height bar lands on the caption.
        if varEnergy_'v' > vEplotMax * 0.16
            Colour: "White"
            Text: v, "centre", varEnergy_'v' - vEplotMax * 0.055, "half", fixed$(varEnergy_'v', 2)
        else
            Colour: "{0.20, 0.20, 0.24}"
            Text: v, "centre", varEnergy_'v' + vEplotMax * 0.055, "half", fixed$(varEnergy_'v', 2)
        endif
    endfor

    Font size: 6
    Select inner viewport: beX1, beX2, beY1, beY2
    Axes: beLo, beHi, 0, vEplotMax
    Marks left every: 1, tickVe, "yes", "yes", "no"
    for v from 1 to varCount
        One mark bottom: v, "no", "yes", "no", "V" + string$(v)
    endfor

    Font size: 7
    Select inner viewport: beX1, beX2, beY1, beY2
    Axes: beLo, beHi, 0, vEplotMax
    Text bottom: "yes", "Variation  (rendered at steps shown in the energy trace)"
    Text top: "no", "Energy per rendered variation  (lower = better fit to the selected criteria)"
    @railLabelAt: beX1, beX2, beY1, beY2, 7, railRight, "Energy"

    # === PANEL 8: SUMMARY ============================================
    Font size: 7
    Select outer viewport: 0, 8, 7.74, 8.88
    Select inner viewport: 0.60, 7.70, 7.80, 8.84
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Text: 0.02, "left", 0.88, "half", "##Summary##"

    Font size: 6
    Select inner viewport: 0.60, 7.70, 7.80, 8.84
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.40}"
    Text: 0.02, "left", 0.68, "half",
        ... "Source: " + srcName$ + "  (" + fixed$(srcDur,2) + " s)"
        ... + "  |  Mode: " + presetName$
        ... + "  |  Phrases: " + string$(nPhrases)
        ... + "  |  T: " + fixed$(tStart,2) + " -> " + fixed$(tEnd,2)
        ... + "  |  Seed: " + string$(seed)
    Text: 0.02, "left", 0.50, "half",
        ... "Steps: " + string$(nSteps)
        ... + "  |  Accepted: " + string$(nAccepted)
        ... + "  (" + fixed$(acceptRate*100,1) + "\% )"
        ... + "  |  Rendered: " + string$(varCount)
        ... + "  |  Thinning: " + string$(thin)
        ... + "  |  Initial E=" + fixed$(initialEnergy,3)
        ... + "  Final E=" + fixed$(currentEnergy,3)
        ... + "  Delta=" + fixed$(currentEnergy - initialEnergy, 3)
    Text: 0.02, "left", 0.32, "half",
        ... "E weights: scale=" + fixed$(w1,1)
        ... + " voice=" + fixed$(w2,1)
        ... + " range=" + fixed$(w3,1)
        ... + " rhythm=" + fixed$(w4,1)
        ... + " dyn=" + fixed$(w5,1)
        ... + " phrase=" + fixed$(w6,1)
        ... + " contour=" + fixed$(w7,1)
        ... + "  |  Tonal center: " + string$(tonalCenter) + " st"

    # An acceptance rate this high means the temperature is large relative
    # to the energy scale: nearly every proposal passes, so the chain is a
    # random walk rather than annealed exploration.  Worth saying out loud
    # on the figure rather than leaving it to be inferred from "acc 92%".
    if acceptRate > 0.85
        chainNote$ = "Note: acceptance " + fixed$(acceptRate*100,0) + "\%   — T is high relative to the energy scale, so the chain is exploring nearly freely rather than descending. Lower Start\_ temp for more selective behaviour."
    elsif acceptRate < 0.15
        chainNote$ = "Note: acceptance " + fixed$(acceptRate*100,0) + "\%   — T is low relative to the energy scale, so the chain is nearly frozen. Raise Start\_ temp or lower the weights for more movement."
    else
        chainNote$ = "Acceptance " + fixed$(acceptRate*100,0) + "\%   is in a workable range for annealed exploration."
    endif
    Colour: "{0.45, 0.35, 0.30}"
    Text: 0.02, "left", 0.13, "half", chainNote$

    Font size: 6
    Select inner viewport: 0.60, 7.70, 7.80, 8.84
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # Save as / Copy from the Picture window exports the CURRENT viewport
    # selection, so the script must end on the whole canvas or the export
    # comes out cropped to the last panel drawn.
    Colour: "Black"
    Line width: 1
    Solid line
    Font size: 10
    Select outer viewport: 0, 8, 0, canvasH

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

# ============================================================
# VISUALIZATION HELPERS
# ============================================================

# Text left: / Text right: position a rotated panel label against whatever
# drawing frame is current, so panels of different widths get their names at
# different x.  Placing them at an ABSOLUTE page position instead keeps the
# rails straight across half-width and full-width panels alike.
# Vertical alignment must be "bottom", not "half": "half" anchors the glyph
# bounding box, so a descender shifts that one label off the rail.
procedure railLabelAt: .x1, .x2, .y1, .y2, .size, .targetIn, .label$
    .xn = (.targetIn - .x1) / (.x2 - .x1)
    Font size: .size
    Select inner viewport: .x1, .x2, .y1, .y2
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text special: .xn, "centre", 0.5, "bottom", "Helvetica", .size, "90", .label$
endproc

# Axis tick spacing: the largest 1/2/5 x 10^k step that still gives roughly
# eight divisions across the span.
procedure niceTick: .span
    if .span <= 0
        .t = 1
    else
        .raw  = .span / 8
        .expo = floor(log10(.raw))
        .base = .raw / 10 ^ .expo
        if .base < 1.5
            .m = 1
        elsif .base < 3.5
            .m = 2
        elsif .base < 7.5
            .m = 5
        else
            .m = 10
        endif
        .t = .m * 10 ^ .expo
    endif
endproc
