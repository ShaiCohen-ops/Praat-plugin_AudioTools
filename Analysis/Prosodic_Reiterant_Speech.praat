# ============================================================================
# ReiterantProsodySynth_KlattGrid.praat  — Reiterant / "gibberish speech"
#                                          prosody synth  •  KlattGrid edition
#
# Part of Praat AudioTools plugin
# Author: Shai Cohen, Department of Music, Bar-Ilan University
# Version: 2.5 (2026)   |   License: MIT   |   PURE PRAAT (no Python)
#
# WHAT IS NEW in v2.5
#   1. Research reproducibility: all stochastic syllable choices, F0
#      microvariation, shimmer and formant drift use a fixed internal seed;
#      Praat's global RNG is restored immediately after stimulus parameters
#      have been generated.
#   2. Pitch_strength=0 is now a STRICT monotone endpoint: the target F0 is
#      exactly the speaker median throughout voiced frames; syllabic F0
#      microvariation cannot reintroduce an intonation contour at alpha=0.
#   3. Source voiced/unvoiced decisions now gate the synthetic voicing-amplitude
#      tier. Undefined source Pitch is no longer silently converted into a
#      continuously voiced carried-forward F0 percept.
#   4. Intensity mapping preserves source dB DIFFERENCES: the source envelope is
#      shifted to a safe KlattGrid operating level instead of being stretched
#      to a fixed 28-dB range.
#   5. Numerical QC is computed for reiterant output even when the figure is
#      disabled: target-vs-output F0 correlation and semitone RMSE, voiced/
#      unvoiced agreement, speech/pause agreement, intensity-envelope
#      correlation and offset-corrected dB RMSE, plus duration error.
#   6. The /la/ onset now actually uses latOnFrac (25% of syllable duration)
#      instead of always stretching the lateral transition to the nucleus.
#   7. Internal guards sanitize duration, pause and output-peak controls without
#      changing the public form.
#
# WHAT IS NEW in v2.4
#   1. Presets now act as defaults rather than blindly overwriting every fine
#      control: a form value that differs from its form default is honoured.
#   2. Jitter_amount is now a true 0..1 depth control over a maximum ±4%
#      per-syllable F0 offset; it no longer means ±40/80% in Natural/Expressive.
#   3. Source analysis is zero-based internally, so non-zero Sound xmin works.
#   4. Peak-count correction preserves detected nuclei: excess peaks are
#      distributed across the region; missing nuclei are inserted by repeatedly
#      splitting the largest temporal gap instead of replacing real peaks.
#   5. /ma/ and /na/ now have distinct approximate place cues (F2 onset +
#      nasal antiformant), while retaining the shared /a/ vowel target.
#   6. t=0 formant/antiformant seeds now match the first consonant onset when
#      speech begins at 0, avoiding silent Add-point collisions in RealTiers.
#
# WHAT IS NEW in v2.3
#   1. Pitch_strength (intonation gradient) — interpolates the F0 contour
#      toward the median in the log/semitone domain: 1 = natural contour,
#      0 = monotone at median F0 (Parsons-style monotonization). This is the
#      human->robotic INTONATION continuum, kept separate from Naturalness
#      (which controls voice-quality micro-variation, not contour shape).
#   2. lowpass_comparison output mode — F0-individualised low-pass baseline
#      after Parsons et al. (Interspeech 2025): cutoff = 420.2*(1-e^(-0.0124*F0)),
#      transition bw = F0/4. Comparison only; reuses the original waveform.
#
# WHAT IS NEW in v2.2
#   1. Naturalness slider (0=robotic, 1=natural) — single master control that
#      scales jitter, shimmer, OQ variation, and formant micro-drift together.
#   2. Jitter & shimmer — stochastic per-syllable perturbation on the voicing
#      source: jitter applied as per-syllable F0 offset, shimmer as per-syllable
#      voicing amplitude micro-variation.
#   3. OQ (open quotient) tracking — mapped from source intensity with an
#      OQ_flat control for the human→robotic gradient.
#   4. F0 jitter_amount parameter — explicit 0–1 slider (overridden by
#      Naturalness if Naturalness < 1 and jitter_amount = 0 default).
#   5. Formant micro-drift — small random per-syllable variation on F1/F2 to
#      break the "stuck formant" percept on robotic settings.
#   6. Dangling else branch fix — the fallthrough branch in the consonant-event
#      block now emits an explicit appendInfoLine warning so unexpected values
#      are always visible in the Info window.
#
# WHAT IS NEW vs v1 (amplitude-envelope approach)
#   v1 synthesised ONE continuous pulse-train, coloured it with a single
#   formant pair, and shaped syllable boundaries with an amplitude envelope.
#   That produces one unbroken "aah" because:
#     • Consonants are spectral/temporal events, not amplitude dips.
#     • A single formant pair cannot distinguish /ma/ /la/ /na/.
#     • Contiguous identical envelopes fuse perceptually.
#
# WHAT IS NEW vs v2.0 (bandwidth-gating approach)
#   v2.0 used the voicing amplitude tier as a rhythmic gate — dropping to
#   silenceDb at every syllable boundary.  That is acoustically equivalent
#   to per-chunk synthesis: the filter stays warm but the source switches
#   on and off in step with the syllable grid, so the output still sounds
#   segmented.  v2.1 keeps the voicing amplitude CONSTANT at a high level
#   for the entire utterance.  Syllabic rhythm is carved purely through the
#   FORMANT BANDWIDTHS: they widen to ~pauseBw Hz during inter-syllable
#   pauses (which damps the resonators to near-silence without touching the
#   source), and narrow back to vowel values during the nucleus.  This is
#   how natural running speech works: the glottal source is mostly
#   continuous, and the percept of syllable boundaries arises from resonator
#   modulation, not from source switching.  Plosive closures (/ba/, /de/)
#   still receive a brief, localised amplitude dip only for the VOT interval.
#
#   v2 synthesises one CONTINUOUS KlattGrid for the entire utterance, giving:
#     • Per-syllable F0 contour (extracted from the source Pitch object).
#     • Per-syllable formant tiers (vowel body: F1/F2/F3/F4/F5 from the
#       neutral vowel target for that consonant class).
#     • Nasal antiformant (zero) at ~520 Hz during onset of /ma/ and /na/
#       — approximates the nasal murmur spectral dip.
#     • Plosive closure for /ba/ and /de/: a short silence gap
#       (≥ 30 ms) + abrupt OQ-driven onset burst, no pre-onset voicing.
#     • /la/ lateral approximant: smooth continuous onset, formant locus
#       transitions from a lateral configuration (low F1, high F2) into
#       the vowel target.
#     • Each syllable is rendered, trimmed, cross-fade concatenated.
#
# LIMITATIONS (v2)
#   • Nasal murmur modelled as a single fixed zero + low-passed onset, not
#     full velopharyngeal coupling. Sounds nasal-ish, not identical to
#     natural /m/ or /n/.
#   • Plosive burst is a sharp OQ-amplitude step, not a noise excitation
#     event. You will hear a click-like onset, not a true aspirated burst.
#     For /b/ aspiration, add frication via kg_set_frication (see notes).
#   • Formant transitions are linear ramps over the onset fraction; real
#     transitions are not perfectly linear but this is perceptually adequate
#     for reiterant speech.
#   • /la/ vs /na/ vs /ma/ are more distinct than v1 but still not
#     indistinguishable from each other; reiterant speech by design carries
#     only broad consonant-class cues.
#
# RESEARCH NOTES
#   Same cautions as v1 apply. This output is closer to Klatt (1980)-style
#   synthesis than to concatenative or articulatory models. It REQUIRES
#   perceptual intelligibility testing before use as a stimulus.
# ============================================================================

form Reiterant Prosody Synthesizer  (KlattGrid edition)
    comment === Output mode ===
    optionmenu Output_mode: 1
        option reiterant_synth
        option lowpass_comparison
    comment === Preset ===
    optionmenu Preset: 1
        option Default
        option Robotic
        option Natural Speech
        option Expressive
        option Minimal (fast)
    comment === Parameters ===
    optionmenu Syllable_pattern: 1
        option ma
        option la
        option na
        option ba
        option de_schwa
        option alternating_ma_la_na_ba
        option random_ma_la_na_ba_de
    optionmenu Speaker_profile: 3
        option male
        option female
        option auto_or_broad
    real Pitch_floor_Hz 75
    real Pitch_ceiling_Hz 600
    real Silence_threshold_dB_below_peak 25
    real Minimum_pause_duration_s 0.12
    real Minimum_syllable_duration_s 0.08
    real Maximum_syllable_duration_s 0.45
    real Output_peak 0.85
    comment --- Human/robotic continuum (0=robotic, 1=natural) ---
    real Naturalness 1.0
    comment --- Fine controls (Naturalness scales these when > 0) ---
    real Jitter_amount 0.0
    real Oq_flat 0.7
    comment --- Intonation gradient: 1=natural contour, 0=monotone at median ---
    real Pitch_strength 1.0
    boolean Draw_QC 1
    boolean Draw_spectrogram 0
    boolean Play_result 1
endform

# ---------------------------------------------------------------------------
# 0-pre. Apply Presets
#   Presets supply defaults only. If the user changed a fine-control field
#   away from its form default, that explicit value wins. This is the closest
#   caller-compatible way to support "choose preset, then tweak" without
#   changing the public form.
# ---------------------------------------------------------------------------
if preset = 1
    presetName$ = "Default"
elsif preset = 2
    presetName$ = "Robotic"
    if naturalness = 1.0
        naturalness = 0.0
    endif
    if oq_flat = 0.7
        oq_flat = 0.5
    endif
elsif preset = 3
    presetName$ = "Natural Speech"
    if jitter_amount = 0.0
        jitter_amount = 0.4
    endif
    if oq_flat = 0.7
        oq_flat = 0.75
    endif
    if silence_threshold_dB_below_peak = 25
        silence_threshold_dB_below_peak = 20
    endif
    if minimum_pause_duration_s = 0.12
        minimum_pause_duration_s = 0.10
    endif
    if minimum_syllable_duration_s = 0.08
        minimum_syllable_duration_s = 0.07
    endif
    if maximum_syllable_duration_s = 0.45
        maximum_syllable_duration_s = 0.40
    endif
elsif preset = 4
    presetName$ = "Expressive"
    if jitter_amount = 0.0
        jitter_amount = 0.8
    endif
    if oq_flat = 0.7
        oq_flat = 0.85
    endif
    if silence_threshold_dB_below_peak = 25
        silence_threshold_dB_below_peak = 18
    endif
    if minimum_pause_duration_s = 0.12
        minimum_pause_duration_s = 0.08
    endif
    if minimum_syllable_duration_s = 0.08
        minimum_syllable_duration_s = 0.06
    endif
    if maximum_syllable_duration_s = 0.45
        maximum_syllable_duration_s = 0.50
    endif
elsif preset = 5
    presetName$ = "Minimal"
    if naturalness = 1.0
        naturalness = 0.3
    endif
    if oq_flat = 0.7
        oq_flat = 0.6
    endif
    if silence_threshold_dB_below_peak = 25
        silence_threshold_dB_below_peak = 30
    endif
    if minimum_pause_duration_s = 0.12
        minimum_pause_duration_s = 0.15
    endif
    if minimum_syllable_duration_s = 0.08
        minimum_syllable_duration_s = 0.10
    endif
endif

# ---------------------------------------------------------------------------
# 0. Constants / tuning
# ---------------------------------------------------------------------------
synthSr   = 44100
gstep     = 0.01
targetSyl = 0.20

# Research reproducibility. Kept internal to preserve the public form/API.
researchSeed = 20260814

# Defensive guards for caller-supplied / Custom-like values.
if minimum_pause_duration_s < 0
    minimum_pause_duration_s = 0
endif
if minimum_syllable_duration_s <= 0
    minimum_syllable_duration_s = 0.01
endif
if maximum_syllable_duration_s < minimum_syllable_duration_s
    maximum_syllable_duration_s = minimum_syllable_duration_s
endif
if output_peak <= 0
    output_peak = 0.85
endif
if output_peak > 1
    output_peak = 1
endif
if silence_threshold_dB_below_peak < 1
    silence_threshold_dB_below_peak = 1
endif

# ---------------------------------------------------------------------------
# 0b. Naturalness continuum → derive per-feature scale factors
#     naturalness  0 = fully robotic (all stochastic variation suppressed)
#                  1 = fully natural (full jitter/shimmer/OQ swing/drift)
#
#     Explicit fine-grained sliders are honoured when Naturalness = 1;
#     at any lower value they are proportionally attenuated so the single
#     Naturalness knob remains the dominant control.
# ---------------------------------------------------------------------------
if naturalness < 0
    naturalness = 0
endif
if naturalness > 1
    naturalness = 1
endif

# Jitter_amount is a 0..1 DEPTH control over a maximum ±4% syllabic F0
# perturbation.  This is deliberately syllable-level microvariation, not
# cycle-to-cycle voice jitter.
if jitter_amount < 0
    jitter_amount = 0
endif
if jitter_amount > 1
    jitter_amount = 1
endif
jitterScale = 0.04 * jitter_amount * naturalness
# Natural Speech (0.4) => max ±1.6%; Expressive (0.8) => max ±3.2%.

# Shimmer: amplitude perturbation fraction on the voicing amplitude tier.
shimmerScale = 0.07 * naturalness
# At Naturalness=1: ±7% amplitude shimmer per syllable (natural: ~3–10%).

# OQ (open quotient) variation: swing around OQ_flat.
# OQ_flat is the baseline OQ (0=closed, 1=fully open).
# Clamped to [0.3, 0.9] to stay physically meaningful.
if oq_flat < 0.3
    oq_flat = 0.3
endif
if oq_flat > 0.9
    oq_flat = 0.9
endif
# oqSwing: how far OQ varies with intensity (natural: ~0.15 swing).
oqSwing = 0.15 * naturalness

# Formant micro-drift: per-syllable random F1/F2 offset fraction.
# At Naturalness=1: up to ±3% on F1, ±2% on F2.
fDriftF1 = 0.03 * naturalness
fDriftF2 = 0.02 * naturalness

# ---------------------------------------------------------------------------
# 1. Validate input
# ---------------------------------------------------------------------------
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object before running."
endif
source     = selected("Sound")
sourceName$ = selected$("Sound")
selectObject: source
origDur    = Get total duration
nChannels  = Get number of channels

selectObject: source
sourceStart = Get start time
if nChannels > 1
    Convert to mono
    srcMono = selected("Sound")
else
    Copy: "rps_mono"
    srcMono = selected("Sound")
endif

# All downstream prosodic analysis and the KlattGrid use a 0..duration axis.
selectObject: srcMono
if sourceStart <> 0
    Shift times by: -sourceStart
endif

# ---------------------------------------------------------------------------
# 2. Pattern label
# ---------------------------------------------------------------------------
if syllable_pattern = 1
    patternStr$ = "ma"
elsif syllable_pattern = 2
    patternStr$ = "la"
elsif syllable_pattern = 3
    patternStr$ = "na"
elsif syllable_pattern = 4
    patternStr$ = "ba"
elsif syllable_pattern = 5
    patternStr$ = "de"
elsif syllable_pattern = 6
    patternStr$ = "alt"
else
    patternStr$ = "rnd"
endif

# ---------------------------------------------------------------------------
# 3. Speaker profile → pitch range
# ---------------------------------------------------------------------------
if speaker_profile = 1
    floorHz   = 75
    ceilingHz = 300
elsif speaker_profile = 2
    floorHz   = 100
    ceilingHz = 500
else
    floorHz   = 75
    ceilingHz = 600
endif
if pitch_floor_Hz <> 75
    floorHz = pitch_floor_Hz
endif
if pitch_ceiling_Hz <> 600
    ceilingHz = pitch_ceiling_Hz
endif
if ceilingHz <= floorHz
    exitScript: "Pitch ceiling must be greater than pitch floor."
endif

writeInfoLine:  "=== Reiterant Prosody Synthesizer v2.4 (KlattGrid) ==="
appendInfoLine: "Source:      ", sourceName$
appendInfoLine: "Preset:      ", presetName$
appendInfoLine: "Pattern:     ", patternStr$
appendInfoLine: "Duration:    ", fixed$(origDur, 3), " s | Channels: ", nChannels
appendInfoLine: "Pitch:       floor ", fixed$(floorHz, 1), " / ceiling ", fixed$(ceilingHz, 1), " Hz"
appendInfoLine: "Naturalness: ", fixed$(naturalness, 2),
    ... "  |  jitterScale: ", fixed$(jitterScale, 4),
    ... "  |  shimmer: ", fixed$(shimmerScale, 4),
    ... "  |  OQ_flat: ", fixed$(oq_flat, 2), " ±", fixed$(oqSwing, 2),
    ... "  |  fDrift F1: ", fixed$(fDriftF1, 3), "  F2: ", fixed$(fDriftF2, 3)
appendInfoLine: ""

# ---------------------------------------------------------------------------
# 4. Analyse source prosody
# ---------------------------------------------------------------------------
appendInfoLine: "[1/6] Analysing pitch & intensity..."
selectObject: srcMono
pitchObj = To Pitch: 0.01, floorHz, ceilingHz
selectObject: pitchObj
medianF0 = Get quantile: 0, 0, 0.5, "Hertz"
if medianF0 = undefined or medianF0 <= 0
    medianF0 = (floorHz + ceilingHz) / 2
endif
meanF0 = Get mean: 0, 0, "Hertz"
if meanF0 = undefined or meanF0 <= 0
    meanF0 = medianF0
endif
# Clamp the intonation-gradient control (alpha): 1 = natural, 0 = monotone
if pitch_strength < 0
    pitch_strength = 0
endif
if pitch_strength > 2
    pitch_strength = 2
endif

selectObject: srcMono
intObj = To Intensity: 100, 0, "yes"
selectObject: intObj
peakDb = Get maximum: 0, 0, "Parabolic"
if peakDb = undefined
    peakDb = 70
endif
threshDb = peakDb - silence_threshold_dB_below_peak

# ---------------------------------------------------------------------------
# 4b. LOW-PASS COMPARISON MODE  (Parsons et al., Interspeech 2025)
#     Baseline/comparison only. UNLIKE the synth, this REUSES the original
#     waveform (filtered), so it may retain residual speech cues.
#     F0-individualised cutoff = 420.2 * (1 - e^(-0.0124 * meanF0)),
#     transition bandwidth = meanF0 / 4.  (standard human-prosody low-pass is
#     ~225-400 Hz; individualising by F0 equalises obfuscation across voices.)
# ---------------------------------------------------------------------------
if output_mode = 2
    lpCut = 420.2 * (1 - exp(-0.0124 * meanF0))
    lpBw  = meanF0 / 4
    if lpBw < 10
        lpBw = 10
    endif
    appendInfoLine: "[2/2] Low-pass comparison: F-bar0 ", fixed$(meanF0, 1), " Hz -> cutoff ", fixed$(lpCut, 1), " Hz (bw ", fixed$(lpBw, 1), ")"
    selectObject: srcMono
    lpSound = Filter (pass Hann band): 0, lpCut, lpBw
    Rename: "lowpass_" + sourceName$
    resultFinal = selected("Sound")
    Scale peak: output_peak
    outDur = Get total duration

    appendInfoLine: ""
    appendInfoLine: "===================== QC SUMMARY ====================="
    appendInfoLine: "Output mode:                lowpass_comparison (Parsons 2025)"
    appendInfoLine: "Source duration:            ", fixed$(origDur, 3), " s"
    appendInfoLine: "Output duration:            ", fixed$(outDur, 3), " s"
    appendInfoLine: "Mean F0 (F-bar0):           ", fixed$(meanF0, 1), " Hz"
    appendInfoLine: "Low-pass cutoff:            ", fixed$(lpCut, 1), " Hz"
    appendInfoLine: "Transition bandwidth:       ", fixed$(lpBw, 1), " Hz"
    appendInfoLine: "NOTE: reuses the ORIGINAL waveform (filtered) — may retain"
    appendInfoLine: "      residual speech cues. Comparison/baseline only."
    appendInfoLine: "======================================================"

    if draw_QC = 1
        Erase all
        Select outer viewport: 0, 8, 0, 0.6
        Axes: 0, 1, 0, 1
        Font size: 12
        Black
        Text: 0.5, "centre", 0.5, "half", "##Low-pass comparison## (Parsons 2025) — " + sourceName$
        Select outer viewport: 0, 8, 0.8, 2.6
        selectObject: srcMono
        Colour: "{0.45, 0.45, 0.55}"
        Draw: 0, origDur, 0, 0, "no", "Curve"
        Black
        Draw inner box
        Axes: 0, 1, 0, 1
        Font size: 9
        Text: 0.02, "left", 0.92, "half", "Original (mono)"
        Select outer viewport: 0, 8, 2.9, 4.7
        selectObject: resultFinal
        Colour: "{0.20, 0.40, 0.80}"
        Draw: 0, origDur, 0, 0, "no", "Curve"
        Black
        Draw inner box
        Axes: 0, 1, 0, 1
        Font size: 9
        Text: 0.02, "left", 0.92, "half", "Low-pass " + fixed$(lpCut, 0) + " Hz (bw " + fixed$(lpBw, 0) + ")"
    endif

    if play_result = 1
        selectObject: resultFinal
        Play
    endif

    removeObject: pitchObj, intObj, srcMono
    selectObject: resultFinal
    goto FINISHED
endif

# ---------------------------------------------------------------------------
# 5. Speech / silence region detection (with short-pause merge)
# ---------------------------------------------------------------------------
appendInfoLine: "[2/6] Detecting speech regions & syllables..."
nSteps = floor(origDur / gstep)

rawN    = 0
inSpeech = 0
for i from 0 to nSteps
    t = i * gstep
    if t > origDur
        t = origDur
    endif
    selectObject: intObj
    iv = Get value at time: t, "Cubic"
    if iv = undefined
        iv = -1000
    endif
    isSp = 0
    if iv >= threshDb
        isSp = 1
    endif
    if isSp = 1 and inSpeech = 0
        rawN = rawN + 1
        rawStart[rawN] = t
        inSpeech = 1
    endif
    if isSp = 0 and inSpeech = 1
        rawEnd[rawN] = t
        inSpeech = 0
    endif
endfor
if inSpeech = 1
    rawEnd[rawN] = origDur
endif

# Merge short inter-region gaps
nReg = 0
ri   = 1
while ri <= rawN
    cs = rawStart[ri]
    ce = rawEnd[ri]
    merging = 1
    while merging = 1
        merging = 0
        if ri < rawN
            gap = rawStart[ri + 1] - ce
            if gap < minimum_pause_duration_s
                ce = rawEnd[ri + 1]
                ri = ri + 1
                merging = 1
            endif
        endif
    endwhile
    nReg = nReg + 1
    regStart[nReg] = cs
    regEnd[nReg]   = ce
    ri = ri + 1
endwhile

# ---------------------------------------------------------------------------
# 6. Syllable segmentation — peak-based timing
#    Strategy:
#      1. Detect local intensity maxima within each speech region.
#         These are the syllable nuclei (peak times stored in pkT[]).
#      2. Syllable boundaries = midpoints between consecutive peaks.
#         First boundary = region start; last boundary = region end.
#      3. sylNucT[k] = the actual detected peak time (NOT nucleusAt fraction).
#    Falls back to equal division only if no peaks are found.
# ---------------------------------------------------------------------------
nSyl = 0
for r from 1 to nReg
    rs   = regStart[r]
    re   = regEnd[r]
    rdur = re - rs

    # --- Pass 1: collect local maxima that meet timing & level constraints ---
    nPk   = 0
    lastPk = rs - minimum_syllable_duration_s
    steps  = floor(rdur / gstep)
    for j from 1 to steps - 1
        ta = rs + (j - 1) * gstep
        tb = rs +  j      * gstep
        tc = rs + (j + 1) * gstep
        if tc > re
            tc = re
        endif
        selectObject: intObj
        va = Get value at time: ta, "Cubic"
        vb = Get value at time: tb, "Cubic"
        vc = Get value at time: tc, "Cubic"
        if va = undefined
            va = -1000
        endif
        if vb = undefined
            vb = -1000
        endif
        if vc = undefined
            vc = -1000
        endif
        if vb >= va and vb > vc and vb > threshDb and (tb - lastPk) >= minimum_syllable_duration_s
            nPk       = nPk + 1
            pkT[nPk]  = tb
            pkIv[nPk] = vb
            lastPk    = tb
        endif
    endfor

    # --- Fallback: if no peaks found, place one nucleus at region centre -----
    if nPk < 1
        fallN = round(rdur / targetSyl)
        if fallN < 1
            fallN = 1
        endif
        maxN = floor(rdur / minimum_syllable_duration_s)
        minN = ceiling(rdur / maximum_syllable_duration_s)
        if maxN < 1
            maxN = 1
        endif
        if minN < 1
            minN = 1
        endif
        if fallN > maxN
            fallN = maxN
        endif
        if fallN < minN
            fallN = minN
        endif
        sdur = rdur / fallN
        for k from 1 to fallN
            nPk       = nPk + 1
            pkT[nPk]  = rs + (k - 0.5) * sdur
            pkIv[nPk] = threshDb
        endfor
    endif

    # --- Clamp peak count to min/max syllable-duration constraints -----------
    maxN = floor(rdur / minimum_syllable_duration_s)
    minN = ceiling(rdur / maximum_syllable_duration_s)
    if maxN < 1
        maxN = 1
    endif
    if minN < 1
        minN = 1
    endif
    if nPk > maxN
        # Keep ACTUAL detected peaks but distribute the retained set across the
        # entire region instead of simply discarding all late peaks.
        oldNPk = nPk
        for kk from 1 to oldNPk
            pkTmpT[kk] = pkT[kk]
            pkTmpIv[kk] = pkIv[kk]
        endfor
        if maxN = 1
            # With only one allowed nucleus, keep the strongest real peak.
            bestK = 1
            bestIv = pkTmpIv[1]
            for kk from 2 to oldNPk
                if pkTmpIv[kk] > bestIv
                    bestK = kk
                    bestIv = pkTmpIv[kk]
                endif
            endfor
            pkT[1] = pkTmpT[bestK]
            pkIv[1] = pkTmpIv[bestK]
        else
            for kk from 1 to maxN
                srcK = round(1 + (kk - 1) * (oldNPk - 1) / (maxN - 1))
                pkT[kk] = pkTmpT[srcK]
                pkIv[kk] = pkTmpIv[srcK]
            endfor
        endif
        nPk = maxN
    endif
    while nPk < minN
        # Preserve every detected nucleus. Add one synthetic nucleus at a time
        # by splitting the largest temporal gap (region edge or inter-peak).
        bestGap = -1
        insertPos = 1
        insertTime = (rs + re) / 2
        leftT = rs
        for kk from 1 to nPk
            thisGap = pkT[kk] - leftT
            if thisGap > bestGap
                bestGap = thisGap
                insertPos = kk
                insertTime = (leftT + pkT[kk]) / 2
            endif
            leftT = pkT[kk]
        endfor
        thisGap = re - leftT
        if thisGap > bestGap
            insertPos = nPk + 1
            insertTime = (leftT + re) / 2
        endif

        oldNPk = nPk
        for kk from 1 to oldNPk
            pkTmpT[kk] = pkT[kk]
            pkTmpIv[kk] = pkIv[kk]
        endfor
        srcK = 1
        for kk from 1 to oldNPk + 1
            if kk = insertPos
                pkT[kk] = insertTime
                pkIv[kk] = threshDb
            else
                pkT[kk] = pkTmpT[srcK]
                pkIv[kk] = pkTmpIv[srcK]
                srcK = srcK + 1
            endif
        endfor
        nPk = oldNPk + 1
    endwhile

    # --- Build syllable boundaries from peak midpoints -----------------------
    for k from 1 to nPk
        nSyl = nSyl + 1
        # Boundary before this peak
        if k = 1
            sylStart[nSyl] = rs
        else
            sylStart[nSyl] = (pkT[k - 1] + pkT[k]) / 2
        endif
        # Boundary after this peak
        if k = nPk
            sylEnd[nSyl] = re
        else
            sylEnd[nSyl] = (pkT[k] + pkT[k + 1]) / 2
        endif
        # Nucleus = actual detected peak (not fraction)
        sylNucT[nSyl]    = pkT[k]
        sylNucIv[nSyl]   = pkIv[k]
        sylRegion[nSyl]  = r
    endfor
endfor

appendInfoLine: "  Speech regions: ", nReg, " | syllable units: ", nSyl

if nSyl < 1
    removeObject: pitchObj, intObj, srcMono
    exitScript: "No speech detected. Try lowering Silence_threshold_dB_below_peak."
endif

# ---------------------------------------------------------------------------
# 7. Vowel + consonant-class formant tables
#    Each consonant class has:
#      • A vowel target  (F1..F5, bandwidths B1..B5)
#      • An onset locus  (F1o..F2o) that transitions to the target
#      • An onset fraction fo  (0..1 of syllable duration)
#      • A plosive flag  plos (1 = silence gap + abrupt onset)
#      • A nasal flag    nas  (1 = add antiformant zero at ~520 Hz)
# ---------------------------------------------------------------------------
#  Formant targets (Hz)     F1    F2    F3    F4    F5
#  Bandwidths (Hz)          B1    B2    B3    B4    B5
#  "a" (open, back):
vowF1_a = 750
vowF2_a = 1150
vowF3_a = 2550
vowF4_a = 3550
vowF5_a = 4200
vowB1_a = 90
vowB2_a = 110
vowB3_a = 170
vowB4_a = 250
vowB5_a = 350
#  schwa (de):
vowF1_e = 500
vowF2_e = 1500
vowF3_e = 2500
vowF4_e = 3500
vowF5_e = 4200
vowB1_e = 80
vowB2_e = 120
vowB3_e = 160
vowB4_e = 250
vowB5_e = 350

# ---------------------------------------------------------------------------
# 8. Build ONE continuous KlattGrid spanning the entire utterance.
#
#    Why: synthesising one chunk per syllable and concatenating causes
#    audible "windowing" — the KlattGrid filter rings up from silence at
#    every chunk boundary, producing a periodic amplitude flutter at the
#    syllable rate.  Writing all per-syllable variation as time-points on
#    a single KlattGrid lets the glottal pulse train and formant filters
#    run uninterrupted.  Pauses are encoded as voicing-amplitude dips to
#    near-silence rather than true zero.
# ---------------------------------------------------------------------------
appendInfoLine: "[3/6] Building continuous KlattGrid..."

# One KlattGrid for the whole utterance
# args: name, tmin, tmax, nOralFormants, nNasalFormants, nNasalAntiFormants,
#       nTrachealFormants, nTrachealAntiFormants, nDeltaFormants, nFrication
kg = Create KlattGrid: "rps_kg", 0, origDur, 6, 1, 1, 6, 1, 1, 1

# Deterministic stimulus generation. Restore the global RNG after the last
# random syllable/formant/shimmer draw so callers are not left with a seeded RNG.
random_initializeWithSeedUnsafelyButPredictably (researchSeed)

# ---- 8a. F0 tier: sample source Pitch across entire duration ---------------
#          The Pitch tier stays continuous for KlattGrid synthesis, while a
#          separate sourceVoicedQC[] mask records the source V/UV decisions.
#          At Pitch_strength=0 the target is STRICTLY medianF0 on voiced frames.
lastF0_g = medianF0
nPtGlobal = ceiling(origDur / 0.01)

# Pre-compute per-syllable F0 microvariation (stored as multipliers).
for k from 1 to nSyl
    if jitterScale > 0
        sylJitter[k] = 1.0 + jitterScale * (randomUniform(-1, 1) + randomUniform(-1, 1)) * 0.5
    else
        sylJitter[k] = 1.0
    endif
endfor

nQcF0 = 0
for i from 0 to nPtGlobal
    tg = i * 0.01
    if tg > origDur
        tg = origDur
    endif

    selectObject: pitchObj
    sourceF0g = Get value at time: tg, "Hertz", "Linear"
    sourceVoiced = 1
    if sourceF0g = undefined or sourceF0g <= 0
        sourceVoiced = 0
        f0g = lastF0_g
    else
        f0g = sourceF0g
        lastF0_g = sourceF0g
    endif

    # Intonation gradient in the log/semitone domain.
    if pitch_strength = 0
        f0g = medianF0
    elsif pitch_strength <> 1 and medianF0 > 0 and f0g > 0
        f0g = medianF0 * (f0g / medianF0) ^ pitch_strength
    endif

    # Syllabic microvariation is voice-quality detail, but MUST NOT destroy
    # the experimentally defined strict-monotone alpha=0 endpoint.
    appliedJitter = 1.0
    if pitch_strength <> 0
        for k from 1 to nSyl
            if tg >= sylStart[k] and tg <= sylEnd[k]
                appliedJitter = sylJitter[k]
            endif
        endfor
    endif
    f0g = f0g * appliedJitter

    if f0g < floorHz
        f0g = floorHz
    endif
    if f0g > ceilingHz
        f0g = ceilingHz
    endif

    nQcF0 = nQcF0 + 1
    qcF0Time[nQcF0] = tg
    qcSourceVoiced[nQcF0] = sourceVoiced
    if sourceVoiced = 1
        qcTargetF0[nQcF0] = f0g
    else
        qcTargetF0[nQcF0] = 0
    endif

    selectObject: kg
    Add pitch point: tg, f0g
endfor

# ---- 8a-ii. OQ (open quotient) tier ----------------------------------------
#   OQ is mapped from local intensity: higher intensity → lower OQ (more closed,
#   pressed voice) scaled by naturalness.  OQ_flat sets the robotic baseline.
#   KlattGrid's "open phase" parameter is a fraction in (0, 1] — pass OQ directly.
#   We write one OQ point per 15 ms sample step (same grid as amplitude).
#   ampRange is needed here and again in 8b — define it once now.
ampRange = peakDb - threshDb
if ampRange < 1
    ampRange = 1
endif
selectObject: kg
Add open phase point: 0, oq_flat

oqSampleStep = 0.015
for r from 1 to nReg
    rs_oq = regStart[r]
    re_oq = regEnd[r]
    nOqSteps = floor((re_oq - rs_oq) / oqSampleStep)
    for oi from 0 to nOqSteps
        toq = rs_oq + oi * oqSampleStep
        if toq > re_oq
            toq = re_oq
        endif
        selectObject: intObj
        iv_oq = Get value at time: toq, "Cubic"
        if iv_oq = undefined
            iv_oq = threshDb
        endif
        normOq = (iv_oq - threshDb) / ampRange
        if normOq < 0
            normOq = 0
        endif
        if normOq > 1
            normOq = 1
        endif
        # Higher intensity → voice more pressed → lower OQ
        thisOQ = oq_flat - oqSwing * normOq + oqSwing * 0.5
        if thisOQ < 0.20
            thisOQ = 0.20
        endif
        if thisOQ > 0.95
            thisOQ = 0.95
        endif
        selectObject: kg
        Add open phase point: toq, thisOQ
    endfor
endfor
selectObject: kg
Add open phase point: origDur, oq_flat

# ---- 8b. Amplitude + formant tiers: intensity-driven stress,
#          peak-timed nuclei, real consonant-class onset events.        v3.0
# ---------------------------------------------------------------------------

pauseBw   = 1000   ; bandwidth in silence / at region edges
silenceDb = -80    ; voicing level outside speech regions
ampRamp   = 0.010  ; 10 ms ramp at region edges

# Intensity → voicing amplitude mapping
# Preserve source dB DIFFERENCES exactly (until safety clamps) by applying a
# single global offset: source peak -> 78 dB KlattGrid voicing amplitude.
ampHi = 78
ampOffsetDb = ampHi - peakDb
ampLo = threshDb + ampOffsetDb
if ampLo < silenceDb + 1
    ampLo = silenceDb + 1
endif
# ampRange remains useful for normalized OQ/formant-drift controls.

# Consonant-class timing
nasOnFrac  = 0.20   ; nasal murmur: first 20% of syllable duration
latOnFrac  = 0.25   ; lateral locus transition: first 25%
plosClosed = 0.035  ; plosive closure gap (s); clamped to 25% of syl dur
plosVOT    = 0.020  ; post-burst VOT ramp (s)

# Approximate place-specific nasal antiformants (zeros). The values are
# intentionally broad synthesis targets, not speaker-independent measurements.
nasAF_m  = 650
nasAFB_m = 100
nasAF_n  = 1250
nasAFB_n = 120

# ---------------------------------------------------------------------------
# 8b-i. Per-syllable vowel targets and consonant-class assignment
# ---------------------------------------------------------------------------
for k from 1 to nSyl
    sylTgtF1[k] = vowF1_a
    sylTgtF2[k] = vowF2_a
    sylTgtF3[k] = vowF3_a
    sylTgtF4[k] = vowF4_a
    sylTgtF5[k] = vowF5_a
    sylTgtB1[k] = vowB1_a
    sylTgtB2[k] = vowB2_a
    sylTgtB3[k] = vowB3_a
    sylTgtB4[k] = vowB4_a
    sylTgtB5[k] = vowB5_a

    if syllable_pattern = 6
        kk = (k - 1) mod 4
        if kk = 0
            cs$ = "ma"
        elsif kk = 1
            cs$ = "la"
        elsif kk = 2
            cs$ = "na"
        else
            cs$ = "ba"
        endif
    elsif syllable_pattern = 7
        rsel = randomInteger(1, 5)
        if rsel = 1
            cs$ = "ma"
        elsif rsel = 2
            cs$ = "la"
        elsif rsel = 3
            cs$ = "na"
        elsif rsel = 4
            cs$ = "ba"
        else
            cs$ = "de"
        endif
    else
        cs$ = patternStr$
    endif
    sylCons$[k] = cs$

    if cs$ = "de"
        sylTgtF1[k] = vowF1_e
        sylTgtF2[k] = vowF2_e
        sylTgtF3[k] = vowF3_e
        sylTgtF4[k] = vowF4_e
        sylTgtF5[k] = vowF5_e
        sylTgtB1[k] = vowB1_e
        sylTgtB2[k] = vowB2_e
        sylTgtB3[k] = vowB3_e
        sylTgtB4[k] = vowB4_e
        sylTgtB5[k] = vowB5_e
    endif

    # Coarticulation drift from nucleus intensity (already stored in sylNucIv)
    drift = (sylNucIv[k] - threshDb) / ampRange
    if drift < 0
        drift = 0
    endif
    if drift > 1
        drift = 1
    endif
    sylTgtF1[k] = sylTgtF1[k] * (0.92 + 0.16 * drift)
    sylTgtF2[k] = sylTgtF2[k] * (1.04 - 0.08 * drift)

    # ---- Formant micro-drift (v2.2) -----------------------------------------
    #   Small stochastic F1/F2 perturbation per syllable to break the
    #   "stuck formant" percept on robotic or repeated-syllable synthesis.
    #   Two uniform draws summed give a roughly triangular distribution.
    if fDriftF1 > 0
        f1rand = (randomUniform(-1, 1) + randomUniform(-1, 1)) * 0.5
        sylTgtF1[k] = sylTgtF1[k] * (1.0 + fDriftF1 * f1rand)
        if sylTgtF1[k] < 150
            sylTgtF1[k] = 150
        endif
        if sylTgtF1[k] > 1100
            sylTgtF1[k] = 1100
        endif
    endif
    if fDriftF2 > 0
        f2rand = (randomUniform(-1, 1) + randomUniform(-1, 1)) * 0.5
        sylTgtF2[k] = sylTgtF2[k] * (1.0 + fDriftF2 * f2rand)
        if sylTgtF2[k] < 700
            sylTgtF2[k] = 700
        endif
        if sylTgtF2[k] > 2800
            sylTgtF2[k] = 2800
        endif
    endif

    # ---- Shimmer: per-syllable amplitude perturbation (v2.2) -----------------
    #   Stored as a dB offset applied when writing voicing amplitude points
    #   for this syllable's nucleus region.
    if shimmerScale > 0
        sylShimmer[k] = shimmerScale * (randomUniform(-1, 1) + randomUniform(-1, 1)) * 0.5
        # Convert fraction to dB: ±7% ≈ ±0.6 dB at Naturalness=1
        sylShimmerDb[k] = 20 * log10(1.0 + sylShimmer[k])
        if sylShimmerDb[k] < -3
            sylShimmerDb[k] = -3
        endif
        if sylShimmerDb[k] > 3
            sylShimmerDb[k] = 3
        endif
    else
        sylShimmerDb[k] = 0
    endif
endfor

# Do not leak the deterministic research seed into caller scripts.
random_initializeSafelyAndUnpredictably ()

# ---------------------------------------------------------------------------
# 8b-ii. Intensity-driven voicing amplitude tier (sampled every 15 ms)
#         Source V/UV decisions gate the SYNTHETIC voicing source; no original
#         waveform is copied. Voiced-frame dB differences are preserved.
# ---------------------------------------------------------------------------
ampSampleStep = 0.015
selectObject: kg
Add voicing amplitude point: 0, silenceDb

nQcAmp = 0
for r from 1 to nReg
    rs = regStart[r]
    re = regEnd[r]
    Add voicing amplitude point: rs, silenceDb

    startAmp = ampLo
    selectObject: pitchObj
    startF0 = Get value at time: rs + ampRamp, "Hertz", "Linear"
    if startF0 = undefined or startF0 <= 0
        startAmp = silenceDb
    endif
    selectObject: kg
    Add voicing amplitude point: rs + ampRamp, startAmp

    nAmpSteps = floor((re - rs - 2 * ampRamp) / ampSampleStep)
    for ai from 1 to nAmpSteps
        ta = rs + ampRamp + (ai - 1) * ampSampleStep
        if ta < re - ampRamp
            selectObject: intObj
            iv_a = Get value at time: ta, "Cubic"
            if iv_a = undefined
                iv_a = threshDb
            endif

            # Store the SOURCE intensity target for offset-invariant QC.
            nQcAmp = nQcAmp + 1
            qcAmpTime[nQcAmp] = ta
            qcSourceIntensity[nQcAmp] = iv_a

            # Preserve the source envelope by dB translation, not range stretch.
            vAmp = iv_a + ampOffsetDb

            # Apply syllabic shimmer as a small dB perturbation.
            shimDb = 0
            for ks from 1 to nSyl
                if ta >= sylStart[ks] and ta <= sylEnd[ks]
                    shimDb = sylShimmerDb[ks]
                endif
            endfor
            vAmp = vAmp + shimDb

            # Preserve source V/UV decisions by muting the synthetic glottal
            # source when source Pitch marks this frame unvoiced.
            selectObject: pitchObj
            voicedF0_a = Get value at time: ta, "Hertz", "Linear"
            if voicedF0_a = undefined or voicedF0_a <= 0
                vAmp = silenceDb
            endif

            if vAmp < silenceDb + 1 and vAmp <> silenceDb
                vAmp = silenceDb + 1
            endif
            if vAmp > ampHi + 3
                vAmp = ampHi + 3
            endif

            selectObject: kg
            Add voicing amplitude point: ta, vAmp
        endif
    endfor

    endAmp = ampLo
    selectObject: pitchObj
    endF0 = Get value at time: re - ampRamp, "Hertz", "Linear"
    if endF0 = undefined or endF0 <= 0
        endAmp = silenceDb
    endif
    selectObject: kg
    Add voicing amplitude point: re - ampRamp, endAmp
    Add voicing amplitude point: re, silenceDb
endfor
selectObject: kg
Add voicing amplitude point: origDur, silenceDb

# ---------------------------------------------------------------------------
# 8b-iii. Formant tiers: per-consonant-class onset + vowel nucleus anchors
# ---------------------------------------------------------------------------
selectObject: kg

# Seed tier at t=0. RealTier-style Add-point commands ignore a second point
# at an already occupied time, so if speech starts at 0 the seed itself must
# already contain the intended consonant onset values.
seedF1 = sylTgtF1[1]
seedF2 = sylTgtF2[1]
seedF3 = sylTgtF3[1]
seedAF = 4000
seedAFB = 2000
if sylStart[1] <= 0.0000001
    seedCons$ = sylCons$[1]
    if seedCons$ = "ma"
        seedF1 = 300
        seedF2 = 1000
        seedAF = nasAF_m
        seedAFB = nasAFB_m
    elsif seedCons$ = "na"
        seedF1 = 300
        seedF2 = 1750
        seedAF = nasAF_n
        seedAFB = nasAFB_n
    elsif seedCons$ = "la"
        seedF1 = 250
        seedF2 = 1100
        seedF3 = 2800
    elsif seedCons$ = "ba"
        seedF1 = 200
        seedF2 = 800
    elsif seedCons$ = "de"
        seedF1 = 200
        seedF2 = 1800
    endif
endif

Add oral formant frequency point: 1, 0, seedF1
Add oral formant frequency point: 2, 0, seedF2
Add oral formant frequency point: 3, 0, seedF3
Add oral formant frequency point: 4, 0, sylTgtF4[1]
Add oral formant frequency point: 5, 0, sylTgtF5[1]
Add oral formant bandwidth point: 1, 0, pauseBw
Add oral formant bandwidth point: 2, 0, pauseBw
Add oral formant bandwidth point: 3, 0, pauseBw
Add oral formant bandwidth point: 4, 0, pauseBw
Add oral formant bandwidth point: 5, 0, pauseBw
Add nasal antiformant frequency point: 1, 0, seedAF
Add nasal antiformant bandwidth point: 1, 0, seedAFB

for k from 1 to nSyl
    tn  = sylNucT[k]   ; actual detected peak time
    ts  = sylStart[k]  ; midpoint-based boundary before this syllable
    te  = sylEnd[k]    ; midpoint-based boundary after this syllable
    sd  = te - ts
    cs$ = sylCons$[k]
    thisReg = sylRegion[k]
    rs  = regStart[thisReg]
    re  = regEnd[thisReg]

    # ---- Region-open bandwidth ramp (first syllable of each region) --------
    if k = 1 or sylRegion[k-1] <> thisReg
        Add oral formant bandwidth point: 1, rs,           pauseBw
        Add oral formant bandwidth point: 1, rs + ampRamp, sylTgtB1[k]
        Add oral formant bandwidth point: 2, rs,           pauseBw
        Add oral formant bandwidth point: 2, rs + ampRamp, sylTgtB2[k]
        Add oral formant bandwidth point: 3, rs,           pauseBw
        Add oral formant bandwidth point: 3, rs + ampRamp, sylTgtB3[k]
        Add oral formant bandwidth point: 4, rs,           pauseBw
        Add oral formant bandwidth point: 4, rs + ampRamp, sylTgtB4[k]
        Add oral formant bandwidth point: 5, rs,           pauseBw
        Add oral formant bandwidth point: 5, rs + ampRamp, sylTgtB5[k]
    endif

    # ---- Consonant-class onset events -------------------------------------

    if cs$ = "ma" or cs$ = "na"
        # Nasal onset. /m/ and /n/ share the vowel body but differ in broad
        # place cues: bilabial /m/ has a lower F2 locus/zero, alveolar /n/ higher.
        if cs$ = "ma"
            thisNasAF = nasAF_m
            thisNasAFB = nasAFB_m
            nasalF2Locus = 1000
        else
            thisNasAF = nasAF_n
            thisNasAFB = nasAFB_n
            nasalF2Locus = 1750
        endif
        nasEnd = ts + nasOnFrac * sd
        if nasEnd > tn
            nasEnd = tn - 0.005
        endif
        if nasEnd < ts
            nasEnd = ts
        endif
        Add nasal antiformant frequency point: 1, ts,            thisNasAF
        Add nasal antiformant bandwidth point: 1, ts,            thisNasAFB
        Add nasal antiformant frequency point: 1, nasEnd,         thisNasAF
        Add nasal antiformant bandwidth point: 1, nasEnd,         thisNasAFB
        Add nasal antiformant frequency point: 1, nasEnd + 0.005, 4000
        Add nasal antiformant bandwidth point: 1, nasEnd + 0.005, 2000
        Add oral formant frequency point: 1, ts, 300
        Add oral formant frequency point: 1, tn, sylTgtF1[k]
        Add oral formant frequency point: 2, ts, nasalF2Locus
        Add oral formant frequency point: 2, tn, sylTgtF2[k]

    elsif cs$ = "ba" or cs$ = "de"
        # Plosive onset: closure silence gap then abrupt release
        closeDur = plosClosed
        if closeDur > 0.25 * sd
            closeDur = 0.25 * sd
        endif
        closEnd = ts + closeDur
        votEnd  = closEnd + plosVOT
        if votEnd > tn
            votEnd = tn
        endif
        # Local amplitude dip for closure (overrides intensity-envelope points)
        Add voicing amplitude point: ts,      silenceDb
        Add voicing amplitude point: closEnd, silenceDb
        releaseAmp = ampHi
        selectObject: pitchObj
        releaseF0 = Get value at time: votEnd, "Hertz", "Linear"
        if releaseF0 = undefined or releaseF0 <= 0
            releaseAmp = silenceDb
        endif
        selectObject: kg
        Add voicing amplitude point: votEnd, releaseAmp
        # F1 closure locus → vowel at tn
        Add oral formant frequency point: 1, ts,      200
        Add oral formant frequency point: 1, closEnd, 200
        Add oral formant frequency point: 1, tn,      sylTgtF1[k]
        # F2 locus: /ba/ → 800 Hz; /de/ → 1800 Hz
        if cs$ = "ba"
            f2locus = 800
        else
            f2locus = 1800
        endif
        Add oral formant frequency point: 2, ts,      f2locus
        Add oral formant frequency point: 2, closEnd, f2locus
        Add oral formant frequency point: 2, tn,      sylTgtF2[k]

    elsif cs$ = "la"
        # Lateral onset: transition reaches the vowel target within latOnFrac
        # of the syllable, then remains at the vowel target through the nucleus.
        latEnd = ts + latOnFrac * sd
        if latEnd > tn
            latEnd = tn
        endif
        if latEnd < ts
            latEnd = ts
        endif
        Add oral formant frequency point: 1, ts, 250
        Add oral formant frequency point: 1, latEnd, sylTgtF1[k]
        Add oral formant frequency point: 1, tn, sylTgtF1[k]
        Add oral formant frequency point: 2, ts, 1100
        Add oral formant frequency point: 2, latEnd, sylTgtF2[k]
        Add oral formant frequency point: 2, tn, sylTgtF2[k]
        # Raised F3 during lateral onset
        Add oral formant frequency point: 3, ts, 2800
        Add oral formant frequency point: 3, latEnd, sylTgtF3[k]
        Add oral formant frequency point: 3, tn, sylTgtF3[k]

    else
        # --------------------------------------------------------------------
        # FALLTHROUGH BRANCH — unexpected consonant label in sylCons$[k].
        # This fires when a single-pattern run uses a label that is not one
        # of the four handled classes.  The original v2.1 code silently fell
        # through and duplicated the /ma/ nasal block, which masked bugs.
        # v2.2: emit a visible warning and apply nasal defaults explicitly.
        # --------------------------------------------------------------------
        appendInfoLine: "  [WARN] syllable ", k, ": unrecognised consonant label '",
            ... cs$, "' — defaulting to nasal (/ma/) onset."
        nasEnd = ts + nasOnFrac * sd
        if nasEnd > tn
            nasEnd = tn - 0.005
        endif
        Add nasal antiformant frequency point: 1, ts,            nasAF_m
        Add nasal antiformant bandwidth point: 1, ts,            nasAFB_m
        Add nasal antiformant frequency point: 1, nasEnd,         nasAF_m
        Add nasal antiformant bandwidth point: 1, nasEnd,         nasAFB_m
        Add nasal antiformant frequency point: 1, nasEnd + 0.005, 4000
        Add nasal antiformant bandwidth point: 1, nasEnd + 0.005, 2000
        Add oral formant frequency point: 1, ts, 300
        Add oral formant frequency point: 1, tn, sylTgtF1[k]
        Add oral formant frequency point: 2, ts, 1000
        Add oral formant frequency point: 2, tn, sylTgtF2[k]
    endif

    # ---- Vowel nucleus anchors (F3/F4/F5 at tn; F1/F2 already written) ----
    Add oral formant frequency point: 3, tn, sylTgtF3[k]
    Add oral formant frequency point: 4, tn, sylTgtF4[k]
    Add oral formant frequency point: 5, tn, sylTgtF5[k]

    # ---- Region-close bandwidth ramp (last syllable of each region) --------
    if k = nSyl or sylRegion[k+1] <> thisReg
        Add oral formant bandwidth point: 1, re - ampRamp, sylTgtB1[k]
        Add oral formant bandwidth point: 1, re,           pauseBw
        Add oral formant bandwidth point: 2, re - ampRamp, sylTgtB2[k]
        Add oral formant bandwidth point: 2, re,           pauseBw
        Add oral formant bandwidth point: 3, re - ampRamp, sylTgtB3[k]
        Add oral formant bandwidth point: 3, re,           pauseBw
        Add oral formant bandwidth point: 4, re - ampRamp, sylTgtB4[k]
        Add oral formant bandwidth point: 4, re,           pauseBw
        Add oral formant bandwidth point: 5, re - ampRamp, sylTgtB5[k]
        Add oral formant bandwidth point: 5, re,           pauseBw
        Add oral formant frequency point: 1, re, sylTgtF1[k]
        Add oral formant frequency point: 2, re, sylTgtF2[k]
    endif
endfor

# Tail points to close all tiers
Add oral formant frequency point: 1, origDur, sylTgtF1[nSyl]
Add oral formant frequency point: 2, origDur, sylTgtF2[nSyl]
Add oral formant frequency point: 3, origDur, sylTgtF3[nSyl]
Add oral formant frequency point: 4, origDur, sylTgtF4[nSyl]
Add oral formant frequency point: 5, origDur, sylTgtF5[nSyl]
Add oral formant bandwidth point: 1, origDur, pauseBw
Add oral formant bandwidth point: 2, origDur, pauseBw
Add oral formant bandwidth point: 3, origDur, pauseBw
Add oral formant bandwidth point: 4, origDur, pauseBw
Add oral formant bandwidth point: 5, origDur, pauseBw
Add nasal antiformant frequency point: 1, origDur, 4000
Add nasal antiformant bandwidth point: 1, origDur, 2000

appendInfoLine: "  v2.5: peak-timed nuclei + dB-faithful envelope + source V/UV gating + consonant onsets"
appendInfoLine: "        + jitter/shimmer/OQ/formant-drift (Naturalness=", fixed$(naturalness, 2), ")."

# ---------------------------------------------------------------------------
# 9. Synthesise the single continuous KlattGrid
# ---------------------------------------------------------------------------
appendInfoLine: "[4/6] Synthesising continuous KlattGrid..."
selectObject: kg
fullRaw = To Sound
removeObject: kg

# ---------------------------------------------------------------------------
# 10. Rename and normalise
# ---------------------------------------------------------------------------
selectObject: fullRaw
Rename: "reiterant_" + patternStr$ + "_" + sourceName$
resultFinal = selected("Sound")
outDur = Get total duration
Scale peak: output_peak

appendInfoLine: "[5/6] Computing numerical preservation QC..."

# Analyse output once; drawQC reuses these objects.
selectObject: resultFinal
outPitchQC = To Pitch: 0.01, floorHz, ceilingHz
selectObject: resultFinal
outIntQC = To Intensity: 100, 0, "yes"

# ---- F0 target vs output, and voiced/unvoiced agreement --------------------
nF0Pair = 0
sumFX = 0
sumFY = 0
sumFXX = 0
sumFYY = 0
sumFXY = 0
sumSemitoneErr2 = 0
nVu = 0
nVuAgree = 0

for qi from 1 to nQcF0
    tq = qcF0Time[qi]
    targetVoiced = qcSourceVoiced[qi]

    selectObject: outPitchQC
    outF0q = Get value at time: tq, "Hertz", "Linear"
    outVoiced = 1
    if outF0q = undefined or outF0q <= 0
        outVoiced = 0
    endif

    nVu = nVu + 1
    if outVoiced = targetVoiced
        nVuAgree = nVuAgree + 1
    endif

    targetF0q = qcTargetF0[qi]
    if targetVoiced = 1 and outVoiced = 1 and targetF0q > 0
        fx = log2(targetF0q)
        fy = log2(outF0q)
        nF0Pair = nF0Pair + 1
        sumFX = sumFX + fx
        sumFY = sumFY + fy
        sumFXX = sumFXX + fx * fx
        sumFYY = sumFYY + fy * fy
        sumFXY = sumFXY + fx * fy
        semitoneErr = 12 * log2(outF0q / targetF0q)
        sumSemitoneErr2 = sumSemitoneErr2 + semitoneErr * semitoneErr
    endif
endfor

f0Corr = undefined
f0RmseSt = undefined
if nF0Pair > 1
    fden1 = nF0Pair * sumFXX - sumFX * sumFX
    fden2 = nF0Pair * sumFYY - sumFY * sumFY
    if fden1 > 0 and fden2 > 0
        f0Corr = (nF0Pair * sumFXY - sumFX * sumFY) / sqrt(fden1 * fden2)
    endif
    f0RmseSt = sqrt(sumSemitoneErr2 / nF0Pair)
endif

vuAgreementPct = 0
if nVu > 0
    vuAgreementPct = 100 * nVuAgree / nVu
endif

# ---- Intensity envelope preservation (speech samples; offset invariant) -----
nAmpPair = 0
sumAX = 0
sumAY = 0
sumAXX = 0
sumAYY = 0
sumAXY = 0
sumADiff = 0
sumADiff2 = 0

for qi from 1 to nQcAmp
    tq = qcAmpTime[qi]
    srcIq = qcSourceIntensity[qi]
    selectObject: outIntQC
    outIq = Get value at time: tq, "Cubic"
    if outIq <> undefined and srcIq >= threshDb
        nAmpPair = nAmpPair + 1
        sumAX = sumAX + srcIq
        sumAY = sumAY + outIq
        sumAXX = sumAXX + srcIq * srcIq
        sumAYY = sumAYY + outIq * outIq
        sumAXY = sumAXY + srcIq * outIq
        ad = outIq - srcIq
        sumADiff = sumADiff + ad
        sumADiff2 = sumADiff2 + ad * ad
    endif
endfor

ampCorr = undefined
ampRmseOffsetDb = undefined
if nAmpPair > 1
    aden1 = nAmpPair * sumAXX - sumAX * sumAX
    aden2 = nAmpPair * sumAYY - sumAY * sumAY
    if aden1 > 0 and aden2 > 0
        ampCorr = (nAmpPair * sumAXY - sumAX * sumAY) / sqrt(aden1 * aden2)
    endif
    meanADiff = sumADiff / nAmpPair
    ampVarDiff = sumADiff2 / nAmpPair - meanADiff * meanADiff
    if ampVarDiff < 0
        ampVarDiff = 0
    endif
    ampRmseOffsetDb = sqrt(ampVarDiff)
endif

# ---- Speech/pause agreement using relative intensity thresholds -------------
selectObject: outIntQC
outPeakDb = Get maximum: 0, 0, "Parabolic"
if outPeakDb = undefined
    outPeakDb = 70
endif
outSpeechThreshDb = outPeakDb - silence_threshold_dB_below_peak
nSp = 0
nSpAgree = 0
nSpSteps = ceiling(origDur / gstep)
for qi from 0 to nSpSteps
    tq = qi * gstep
    if tq > origDur
        tq = origDur
    endif
    selectObject: intObj
    srcSpDb = Get value at time: tq, "Cubic"
    srcSp = 0
    if srcSpDb <> undefined and srcSpDb >= threshDb
        srcSp = 1
    endif

    selectObject: outIntQC
    outSpDb = Get value at time: tq, "Cubic"
    outSp = 0
    if outSpDb <> undefined and outSpDb >= outSpeechThreshDb
        outSp = 1
    endif

    nSp = nSp + 1
    if srcSp = outSp
        nSpAgree = nSpAgree + 1
    endif
endfor

speechPauseAgreementPct = 0
if nSp > 0
    speechPauseAgreementPct = 100 * nSpAgree / nSp
endif

durationErrorMs = 1000 * (outDur - origDur)

# ---------------------------------------------------------------------------
# 13. QC summary
# ---------------------------------------------------------------------------
appendInfoLine: ""
appendInfoLine: "===================== QC SUMMARY ====================="
appendInfoLine: "Preset:                     ", presetName$
appendInfoLine: "Pattern:                    ", patternStr$
appendInfoLine: "Synthesis engine:           KlattGrid v2.5 (research-preservation pass)"
appendInfoLine: "Source duration:            ", fixed$(origDur, 3), " s"
appendInfoLine: "Output duration:            ", fixed$(outDur, 3), " s"
appendInfoLine: "Speech regions:             ", nReg
appendInfoLine: "Syllable-like intervals:    ", nSyl
appendInfoLine: "Pitch floor / ceiling:      ", fixed$(floorHz, 1), " / ", fixed$(ceilingHz, 1), " Hz"
appendInfoLine: "Naturalness:                ", fixed$(naturalness, 2), "  (0=robotic, 1=natural)"
appendInfoLine: "Intonation strength:        ", fixed$(pitch_strength, 2), "  (1=natural contour, 0=monotone)"
appendInfoLine: "Jitter scale:               ", fixed$(jitterScale, 4), "  (syllabic F0 fraction)"
appendInfoLine: "Shimmer scale:              ", fixed$(shimmerScale, 4), "  (per-syl amp fraction)"
appendInfoLine: "OQ flat / swing:            ", fixed$(oq_flat, 2), " / ", fixed$(oqSwing, 2)
appendInfoLine: "Formant drift F1/F2:        ", fixed$(fDriftF1, 3), " / ", fixed$(fDriftF2, 3)
appendInfoLine: "Research seed:              ", researchSeed
appendInfoLine: "Duration error:             ", fixed$(durationErrorMs, 3), " ms"
if f0Corr <> undefined
    appendInfoLine: "Target/output F0 corr:      ", fixed$(f0Corr, 4), " (log2-Hz)"
else
    appendInfoLine: "Target/output F0 corr:      undefined (insufficient paired voiced frames)"
endif
if f0RmseSt <> undefined
    appendInfoLine: "Target/output F0 RMSE:      ", fixed$(f0RmseSt, 4), " semitones"
else
    appendInfoLine: "Target/output F0 RMSE:      undefined"
endif
appendInfoLine: "Voiced/unvoiced agreement:  ", fixed$(vuAgreementPct, 2), "%"
if ampCorr <> undefined
    appendInfoLine: "Intensity-envelope corr:    ", fixed$(ampCorr, 4), " (speech samples)"
else
    appendInfoLine: "Intensity-envelope corr:    undefined"
endif
if ampRmseOffsetDb <> undefined
    appendInfoLine: "Intensity shape RMSE:       ", fixed$(ampRmseOffsetDb, 3), " dB (global level removed)"
else
    appendInfoLine: "Intensity shape RMSE:       undefined"
endif
appendInfoLine: "Speech/pause agreement:     ", fixed$(speechPauseAgreementPct, 2), "%"
appendInfoLine: "Original waveform not used as audible output."
appendInfoLine: "EXPERIMENTAL — requires perceptual intelligibility testing."
appendInfoLine: "Compare against stricter hum / low-pass / vocoding controls."
appendInfoLine: "======================================================"
appendInfoLine: "[6/6] Done."

if draw_QC = 1
    @drawQC
endif

if play_result = 1
    selectObject: resultFinal
    Play
endif

removeObject: pitchObj, intObj, srcMono, outPitchQC, outIntQC
selectObject: resultFinal

label FINISHED


# ===========================================================================
# PROCEDURES
# ===========================================================================


# ---------------------------------------------------------------------------
# @drawQC
# ---------------------------------------------------------------------------
procedure drawQC
    # Scientific multi-panel acoustic figure.
    # Shared, aligned time axis across panels; numbered/gridded axes with units;
    # source-vs-output overlays on F0 and intensity demonstrate prosody
    # preservation (the validation argument).  Opt-in spectrogram via the form.

    # ---- palette ----
    srcCol$  = "{0.20, 0.20, 0.24}"
    outCol$  = "{0.15, 0.42, 0.80}"
    wavS$    = "{0.50, 0.50, 0.55}"
    wavO$    = "{0.15, 0.42, 0.80}"
    bg$      = "{0.975, 0.975, 0.978}"
    refCol$  = "{0.62, 0.62, 0.62}"
    sylCol$  = "{0.80, 0.45, 0.45}"

    # ---- shared time tick step (nice round value) ----
    if origDur <= 2
        tTick = 0.2
    elsif origDur <= 5
        tTick = 0.5
    elsif origDur <= 12
        tTick = 1
    else
        tTick = 2
    endif
    # F0 tick step
    if (ceilingHz - floorHz) <= 350
        f0Tick = 50
    else
        f0Tick = 100
    endif
    dbTick = 10

    # ---- reuse OUTPUT analyses already computed for numerical QC ----
    outPitch = outPitchQC
    outInt = outIntQC

    # layout: left/right margins leave room for numbered y axes
    lpL = 0.95
    lpR = 7.70

    Erase all
    Select outer viewport: 0, 8, 0, 8
    Black
    Plain line
    Line width: 1

    # ==========================================================
    # TITLE
    # ==========================================================
    Select outer viewport: 0, 8, 0, 0.55
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.62, "half", "##Reiterant prosody synthesis — acoustic QC##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.35, "half",
        ... sourceName$
        ... + "   |   preset " + presetName$
        ... + "   |   /" + patternStr$ + "/"
        ... + "   |   Nat " + fixed$(naturalness, 2)
        ... + "   |   Intonation " + fixed$(pitch_strength, 2)
        ... + "   |   " + string$(nSyl) + " syllables / " + string$(nReg) + " regions"

    # ==========================================================
    # PANEL A — source waveform + syllable structure
    # ==========================================================
    Select inner viewport: lpL, lpR, 0.80, 2.05
    selectObject: srcMono
    sPk = Get absolute extremum: 0, 0, "None"
    if sPk = undefined or sPk <= 0
        sPk = 1
    endif
    Axes: 0, 1, 0, 1
    Paint rectangle: bg$, 0, 1, 0, 1
    Axes: 0, origDur, -sPk, sPk
    Marks bottom every: 1, tTick, "no", "yes", "yes"
    # zero line
    Colour: refCol$
    Draw line: 0, 0, origDur, 0
    # waveform
    selectObject: srcMono
    Colour: wavS$
    Draw: 0, origDur, -sPk, sPk, "no", "Curve"
    # syllable boundaries (dotted) + nucleus ticks
    Axes: 0, origDur, -sPk, sPk
    Colour: sylCol$
    Dotted line
    for k from 1 to nSyl
        Draw line: sylStart[k], -0.92 * sPk, sylStart[k], 0.92 * sPk
    endfor
    Plain line
    Colour: "Black"
    for k from 1 to nSyl
        Draw line: sylNucT[k], 0.78 * sPk, sylNucT[k], sPk
    endfor
    Colour: "Black"
    Draw inner box
    Axes: 0, 1, 0, 1
    Font size: 8
    Text: 0.012, "left", 0.88, "half", "##A##"
    Font size: 6
    Text: 0.11, "left", 0.88, "half", "source waveform — dotted = syllable bounds, ticks = nuclei"
    Text left: "yes", "amplitude"

    # ==========================================================
    # PANEL B — F0 (Hz): source vs output overlay
    # ==========================================================
    Select inner viewport: lpL, lpR, 2.45, 3.70
    Axes: 0, 1, 0, 1
    Paint rectangle: bg$, 0, 1, 0, 1
    Axes: 0, origDur, floorHz, ceilingHz
    Marks left every: 1, f0Tick, "yes", "yes", "yes"
    Marks bottom every: 1, tTick, "no", "yes", "yes"
    # median reference
    Colour: refCol$
    Dotted line
    Draw line: 0, medianF0, origDur, medianF0
    Plain line
    # source then output
    selectObject: pitchObj
    Colour: srcCol$
    Draw: 0, origDur, floorHz, ceilingHz, "no"
    selectObject: outPitch
    Colour: outCol$
    Draw: 0, origDur, floorHz, ceilingHz, "no"
    Colour: "Black"
    Draw inner box
    Axes: 0, 1, 0, 1
    Font size: 8
    Text: 0.012, "left", 0.88, "half", "##B##"
    Font size: 6
    Text: 0.11, "left", 0.88, "half", "F0 (Hz) — dotted = median " + fixed$(medianF0, 0) + " Hz"
    Colour: srcCol$
    Text: 0.84, "left", 0.90, "half", "source"
    Colour: outCol$
    Text: 0.84, "left", 0.74, "half", "output"
    Black
    Text left: "yes", "F0 (Hz)"

    # ==========================================================
    # PANEL C — intensity (dB): source vs output overlay
    # ==========================================================
    Select inner viewport: lpL, lpR, 4.10, 5.35
    intFloor = threshDb - 5
    intCeil  = peakDb + 3
    Axes: 0, 1, 0, 1
    Paint rectangle: bg$, 0, 1, 0, 1
    Axes: 0, origDur, intFloor, intCeil
    Marks left every: 1, dbTick, "yes", "yes", "yes"
    Marks bottom every: 1, tTick, "no", "yes", "yes"
    # speech threshold reference
    Colour: refCol$
    Dotted line
    Draw line: 0, threshDb, origDur, threshDb
    Plain line
    # source then output
    selectObject: intObj
    Colour: srcCol$
    Draw: 0, origDur, intFloor, intCeil, "no"
    selectObject: outInt
    Colour: outCol$
    Draw: 0, origDur, intFloor, intCeil, "no"
    Colour: "Black"
    Draw inner box
    Axes: 0, 1, 0, 1
    Font size: 8
    Text: 0.012, "left", 0.88, "half", "##C##"
    Font size: 6
    Text: 0.11, "left", 0.88, "half", "intensity (dB) — dotted = speech threshold " + fixed$(threshDb, 0) + " dB"
    Colour: srcCol$
    Text: 0.84, "left", 0.90, "half", "source"
    Colour: outCol$
    Text: 0.84, "left", 0.74, "half", "output"
    Black
    Text left: "yes", "intensity (dB)"

    # ==========================================================
    # PANEL D — output: spectrogram (opt-in) or waveform
    # ==========================================================
    Select inner viewport: lpL, lpR, 5.75, 7.00
    if draw_spectrogram = 1
        specMax = 5000
        selectObject: resultFinal
        spec = To Spectrogram: 0.005, specMax, 0.002, 20, "Gaussian"
        selectObject: spec
        Paint: 0, origDur, 0, specMax, 100, "yes", 50, 6, 0, "no"
        removeObject: spec
        # overlay output F0 on the spectrogram
        Axes: 0, origDur, 0, specMax
        selectObject: outPitch
        Colour: outCol$
        Draw: 0, origDur, 0, specMax, "no"
        Black
        Axes: 0, origDur, 0, specMax
        Marks left every: 1, 1000, "yes", "yes", "no"
        Marks bottom every: 1, tTick, "yes", "yes", "no"
        Draw inner box
        Axes: 0, 1, 0, 1
        Font size: 8
        Text: 0.012, "left", 0.88, "half", "##D##"
        Font size: 6
        Text: 0.11, "left", 0.88, "half", "output spectrogram (F0 overlaid)"
        Text left: "yes", "freq (Hz)"
    else
        selectObject: resultFinal
        oPk = Get absolute extremum: 0, 0, "None"
        if oPk = undefined or oPk <= 0
            oPk = 1
        endif
        Axes: 0, 1, 0, 1
        Paint rectangle: bg$, 0, 1, 0, 1
        Axes: 0, origDur, -oPk, oPk
        Marks bottom every: 1, tTick, "yes", "yes", "yes"
        Colour: refCol$
        Draw line: 0, 0, origDur, 0
        selectObject: resultFinal
        Colour: wavO$
        Draw: 0, origDur, -oPk, oPk, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Axes: 0, 1, 0, 1
        Font size: 8
        Text: 0.012, "left", 0.88, "half", "##D##"
        Font size: 6
        Text: 0.11, "left", 0.88, "half", "synthesised output waveform"
        Text left: "yes", "amplitude"
    endif
    Font size: 7
    Text bottom: "yes", "Time (s)"

    # ==========================================================
    # SUMMARY STRIP
    # ==========================================================
    Select inner viewport: lpL, lpR, 7.20, 7.80
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.80, "half",
        ... "##Engine##  KlattGrid v2.5"
        ... + "   |   ##Pitch##  " + fixed$(floorHz, 0) + "–" + fixed$(ceilingHz, 0) + " Hz"
        ... + "   |   ##Median F0##  " + fixed$(medianF0, 0) + " Hz"
        ... + "   |   ##Intonation alpha##  " + fixed$(pitch_strength, 2)
        ... + "   |   ##Naturalness##  " + fixed$(naturalness, 2)
    Text: 0.02, "left", 0.46, "half",
        ... "##Jitter##  " + fixed$(jitterScale, 3)
        ... + "   |   ##Shimmer##  " + fixed$(shimmerScale, 3)
        ... + "   |   ##OQ##  " + fixed$(oq_flat, 2) + " ±" + fixed$(oqSwing, 2)
        ... + "   |   ##fDrift F1/F2##  " + fixed$(fDriftF1, 3) + "/" + fixed$(fDriftF2, 3)
        ... + "   |   ##Dur##  " + fixed$(origDur, 2) + " s -> " + fixed$(outDur, 2) + " s"
    Text: 0.02, "left", 0.13, "half",
        ... "EXPERIMENTAL — original waveform not used as audio — overlays show source vs output prosody — requires perceptual validation"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # Output Pitch/Intensity objects are cleaned up by the caller after drawing.

    Font size: 10
    Colour: "Black"
    Line width: 1
endproc
