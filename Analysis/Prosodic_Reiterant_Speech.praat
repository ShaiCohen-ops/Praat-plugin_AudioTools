# ============================================================================
# Prosodic_Reiterant_Speech.praat  — Reiterant / "gibberish speech"
#                                    prosody synth  •  KlattGrid edition
#
# Part of Praat AudioTools plugin
# Author: Shai Cohen, Department of Music, Bar-Ilan University
# Version: 2.6.2 (2026)   |   License: MIT   |   PURE PRAAT (no Python)
#
# WHAT IS NEW in v2.6.2
#   VISUALIZATION-ONLY redesign. DSP and numerical QC are unchanged.
#   1. Panel A shows the measured timing scaffold: speech regions, syllable
#      boundaries, nuclei, and (when sparse enough) the actual reiterant labels.
#   2. Panel B now visualizes the F0 mechanism itself: source, manipulated target,
#      and synthesized output in semitones relative to the speaker median. This is
#      the same log domain in which Pitch_strength is defined.
#   3. Panel C compares intensity SHAPE after independently mean-centering source
#      and output over the exact QC-eligible frames; the y-axis is symmetric.
#   4. Default Panel D is a process diagram explaining the experimental mapping.
#      The optional spectrogram remains available when Draw_spectrogram is enabled.
#   5. All panel titles live in independent text strips; data viewports are
#      reselected before drawing, preventing inherited-axis/text overflow bugs.
#   6. The bottom QC area is now a three-column research dashboard rather than
#      three long text lines.
#
# WHAT IS NEW in v2.6
#   1. BLOCKER FIX: source Pitch dropouts no longer mute the synthetic signal
#      frame-by-frame. V/UV gating is now opt-in and applies only to sustained
#      unvoiced runs longer than a user-defined minimum (default 50 ms).
#   2. Plosive closures are precomputed before the intensity envelope is built;
#      generic envelope points are skipped through closure+VOT, so /ba/ and /de/
#      now contain a real local silence interval. Release level follows local dB.
#   3. Nasal pole+zero are explicitly controlled. /m/ and /n/ use separated
#      onset zeros plus a ~270-Hz nasal pole; both pole and zero are parked at
#      identical idle values before/after the onset to keep the vowel transparent.
#   4. Presets now have an explicit contract. Presets set their synthesis defaults;
#      a new Custom option honours the form controls literally. Default regains
#      modest F0 microvariation instead of silently producing zero jitter.
#   5. Research_seed is a form parameter; 0 requests an unpredictable run. Fixed
#      non-zero seeds remain reproducible and Praat's RNG is restored afterwards.
#   6. QC now separates source-vs-output F0 preservation from target-vs-output
#      synthesis accuracy. Intensity QC reports correlation, regression slope,
#      and offset-removed shape RMSE; the figure shows the offset-aligned contour.
#   7. The t=0 open-phase seed no longer collides with a real intensity-derived
#      OQ point when speech begins at time zero. Header/UI cleanup included.
#
# WHAT IS NEW in v2.5
#   1. Research reproducibility: all stochastic syllable choices, F0
#      microvariation, shimmer and formant drift use a fixed internal seed;
#      Praat's global RNG is restored immediately after stimulus parameters
#      have been generated.
#   2. Pitch_strength=0 is now a STRICT monotone endpoint: the target F0 is
#      exactly the speaker median throughout voiced frames; syllabic F0
#      microvariation cannot reintroduce an intonation contour at alpha=0.
#   3. (Superseded in v2.6) Source V/UV decisions were used as a frame-wise
#      voicing gate. Runtime testing showed tracker dropouts could punch holes
#      into speech, so v2.6 makes sustained-run gating opt-in.
#   4. Intensity mapping translates the source dB contour into the KlattGrid
#      operating range without the old 28-dB range stretch. v2.6 QC explicitly
#      measures contour correlation/slope because the synthesizer can reshape it.
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
#   receive a brief, localised closure plus VOT ramp, written explicitly.
#
#   v2 synthesises one CONTINUOUS KlattGrid for the entire utterance, giving:
#     • Per-syllable F0 contour (extracted from the source Pitch object).
#     • Per-syllable formant tiers (vowel body: F1/F2/F3/F4/F5 from the
#       neutral vowel target for that consonant class).
#     • Nasal pole + place-dependent antiformant during onset of /ma/ and /na/
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
        option Custom (use controls below literally)
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
    comment --- Fine controls (literal in Custom; presets set their own defaults) ---
    real Jitter_amount 0.0
    real Oq_flat 0.7
    comment --- Intonation gradient: 1=natural contour, 0=monotone at median ---
    real Pitch_strength 1.0
    comment --- Research reproducibility / optional source V-UV gating ---
    integer Research_seed 20260814
    boolean Gate_long_unvoiced_runs 0
    positive Minimum_unvoiced_gate_s 0.05
    boolean Draw_QC 1
    boolean Draw_spectrogram 0
    boolean Play_result 1
endform

# ---------------------------------------------------------------------------
# 0-pre. Apply Presets
#   v2.6 contract: Presets are complete synthesis defaults. Choose Custom to
#   honour Naturalness/Jitter/OQ and segmentation controls literally.
#   Pitch_strength remains independent because it is the experimental alpha.
# ---------------------------------------------------------------------------
if preset = 1
    presetName$ = "Default"
    naturalness = 1.0
    jitter_amount = 0.4
    oq_flat = 0.70
    silence_threshold_dB_below_peak = 25
    minimum_pause_duration_s = 0.12
    minimum_syllable_duration_s = 0.08
    maximum_syllable_duration_s = 0.45
elsif preset = 2
    presetName$ = "Robotic"
    naturalness = 0.0
    jitter_amount = 0.0
    oq_flat = 0.50
    silence_threshold_dB_below_peak = 25
    minimum_pause_duration_s = 0.12
    minimum_syllable_duration_s = 0.08
    maximum_syllable_duration_s = 0.45
elsif preset = 3
    presetName$ = "Natural Speech"
    naturalness = 1.0
    jitter_amount = 0.4
    oq_flat = 0.75
    silence_threshold_dB_below_peak = 20
    minimum_pause_duration_s = 0.10
    minimum_syllable_duration_s = 0.07
    maximum_syllable_duration_s = 0.40
elsif preset = 4
    presetName$ = "Expressive"
    naturalness = 1.0
    jitter_amount = 0.8
    oq_flat = 0.85
    silence_threshold_dB_below_peak = 18
    minimum_pause_duration_s = 0.08
    minimum_syllable_duration_s = 0.06
    maximum_syllable_duration_s = 0.50
elsif preset = 5
    presetName$ = "Minimal"
    naturalness = 0.3
    jitter_amount = 0.15
    oq_flat = 0.60
    silence_threshold_dB_below_peak = 30
    minimum_pause_duration_s = 0.15
    minimum_syllable_duration_s = 0.10
    maximum_syllable_duration_s = 0.45
else
    presetName$ = "Custom"
endif

# ---------------------------------------------------------------------------
# 0. Constants / tuning
# ---------------------------------------------------------------------------
gstep     = 0.01
targetSyl = 0.20

# Research reproducibility: 0 = unpredictable run, non-zero = fixed seed.
researchSeed = research_seed
if researchSeed < 0
    researchSeed = -researchSeed
endif
if minimum_unvoiced_gate_s < 0.02
    minimum_unvoiced_gate_s = 0.02
endif

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
#     In Custom, Jitter_amount is literal and Naturalness scales the resulting
#     stochastic variation. Presets set Jitter_amount explicitly, avoiding the
#     old ambiguity where 0 could mean either "auto" or "zero".
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

writeInfoLine:  "=== Reiterant Prosody Synthesizer v2.6 (KlattGrid) ==="
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
#      • A nasal flag    nas  (1 = add nasal pole + place-dependent zero)
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

# Reproducible when seed is non-zero; unpredictable when seed = 0. Restore
# Praat's global RNG after the last stochastic draw in either case.
if researchSeed = 0
    random_initializeSafelyAndUnpredictably ()
else
    random_initializeWithSeedUnsafelyButPredictably (researchSeed)
endif

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
        qcSourceF0[nQcF0] = sourceF0g
        qcTargetF0[nQcF0] = f0g
    else
        qcSourceF0[nQcF0] = 0
        qcTargetF0[nQcF0] = 0
    endif

    selectObject: kg
    Add pitch point: tg, f0g
endfor

# ---- 8a-iib. Optional sustained source V/UV gate ----------------------------
# Frame-wise Pitch dropouts are NOT used as an amplitude gate. If explicitly
# enabled, only contiguous source-unvoiced runs >= minimum_unvoiced_gate_s are
# allowed to mute the generic synthetic voicing envelope.
nUvGate = 0
gatedDuration = 0
if gate_long_unvoiced_runs = 1
    uvActive = 0
    uvStart = 0
    for qi from 1 to nQcF0
        if qcSourceVoiced[qi] = 0 and uvActive = 0
            uvActive = 1
            uvStart = qcF0Time[qi]
        elsif qcSourceVoiced[qi] = 1 and uvActive = 1
            uvEnd = qcF0Time[qi]
            if uvEnd - uvStart >= minimum_unvoiced_gate_s
                nUvGate = nUvGate + 1
                uvGateStart[nUvGate] = uvStart
                uvGateEnd[nUvGate] = uvEnd
                gatedDuration = gatedDuration + (uvEnd - uvStart)
            endif
            uvActive = 0
        endif
    endfor
    if uvActive = 1
        uvEnd = origDur
        if uvEnd - uvStart >= minimum_unvoiced_gate_s
            nUvGate = nUvGate + 1
            uvGateStart[nUvGate] = uvStart
            uvGateEnd[nUvGate] = uvEnd
            gatedDuration = gatedDuration + (uvEnd - uvStart)
        endif
    endif
endif

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
# If speech starts at t=0, the first loop point is the real intensity-derived
# OQ value. Do not occupy t=0 with a default that would silently win.
if nReg < 1 or regStart[1] > 0.0000001
    Add open phase point: 0, oq_flat
endif

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

# Intensity -> voicing amplitude mapping
# Translate the source dB contour with one global offset (source peak -> 78 dB).
# Klatt filtering and source-parameter interaction can still reshape the output;
# v2.6 therefore measures the realised contour correlation, slope and RMSE.
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

# Approximate nasal pole + place-specific antiformants. The idle pole and zero
# are parked at the SAME F/B so the nasal branch is effectively transparent.
nasPoleF = 270
nasPoleB = 90
nasAF_m  = 900
nasAFB_m = 120
nasAF_n  = 1650
nasAFB_n = 150
nasIdleF = 4000
nasIdleB = 2000

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

    # Precompute plosive closure + VOT control interval BEFORE the generic
    # amplitude envelope is written. Generic points inside this interval will
    # be skipped, so they cannot fill the closure back in.
    sylPlosive[k] = 0
    sylPlosStart[k] = -1
    sylPlosClosureEnd[k] = -1
    sylPlosRelease[k] = -1
    if cs$ = "ba" or cs$ = "de"
        sd_pl = sylEnd[k] - sylStart[k]
        closeDur_pl = plosClosed
        if closeDur_pl > 0.25 * sd_pl
            closeDur_pl = 0.25 * sd_pl
        endif
        sylPlosive[k] = 1
        sylPlosStart[k] = sylStart[k]
        sylPlosClosureEnd[k] = sylStart[k] + closeDur_pl
        sylPlosRelease[k] = sylPlosClosureEnd[k] + plosVOT
        if sylPlosRelease[k] > sylNucT[k]
            sylPlosRelease[k] = sylNucT[k]
        endif
    endif

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
#         Source Pitch dropouts are NOT an unconditional gate. Plosive control
#         intervals are skipped here and written explicitly in 8b-iii.
# ---------------------------------------------------------------------------
ampSampleStep = 0.015
selectObject: kg
Add voicing amplitude point: 0, silenceDb

nQcAmp = 0
for r from 1 to nReg
    rs = regStart[r]
    re = regEnd[r]
    selectObject: kg
    Add voicing amplitude point: rs, silenceDb

    # Region opening ramp: skip if it falls inside a precomputed plosive
    # closure/VOT control interval.
    rampT = rs + ampRamp
    if rampT > re
        rampT = re
    endif
    plosControlled = 0
    for kp from 1 to nSyl
        if sylPlosive[kp] = 1 and rampT >= sylPlosStart[kp] and rampT <= sylPlosRelease[kp]
            plosControlled = 1
        endif
    endfor
    if plosControlled = 0
        selectObject: intObj
        rampIv = Get value at time: rampT, "Cubic"
        if rampIv = undefined
            rampIv = threshDb
        endif
        rampAmp = rampIv + ampOffsetDb
        for ks from 1 to nSyl
            if rampT >= sylStart[ks] and rampT <= sylEnd[ks]
                rampAmp = rampAmp + sylShimmerDb[ks]
            endif
        endfor
        gateThis = 0
        if gate_long_unvoiced_runs = 1
            for gi from 1 to nUvGate
                if rampT >= uvGateStart[gi] and rampT <= uvGateEnd[gi]
                    gateThis = 1
                endif
            endfor
        endif
        if gateThis = 1
            rampAmp = silenceDb
        endif
        if rampAmp < silenceDb + 1 and rampAmp <> silenceDb
            rampAmp = silenceDb + 1
        endif
        if rampAmp > ampHi + 3
            rampAmp = ampHi + 3
        endif
        selectObject: kg
        Add voicing amplitude point: rampT, rampAmp
    endif

    nAmpSteps = floor((re - rs - 2 * ampRamp) / ampSampleStep)
    for ai from 1 to nAmpSteps
        ta = rs + ampRamp + (ai - 1) * ampSampleStep
        if ta < re - ampRamp
            # Do not write generic envelope points through closure or VOT.
            plosControlled = 0
            for kp from 1 to nSyl
                if sylPlosive[kp] = 1 and ta >= sylPlosStart[kp] and ta <= sylPlosRelease[kp]
                    plosControlled = 1
                endif
            endfor

            if plosControlled = 0
                selectObject: intObj
                iv_a = Get value at time: ta, "Cubic"
                if iv_a = undefined
                    iv_a = threshDb
                endif

                vAmp = iv_a + ampOffsetDb
                shimDb = 0
                for ks from 1 to nSyl
                    if ta >= sylStart[ks] and ta <= sylEnd[ks]
                        shimDb = sylShimmerDb[ks]
                    endif
                endfor
                vAmp = vAmp + shimDb

                # Optional sustained V/UV gating only. Short tracker dropouts are
                # deliberately ignored because they are not reliable segment cues.
                gateThis = 0
                if gate_long_unvoiced_runs = 1
                    for gi from 1 to nUvGate
                        if ta >= uvGateStart[gi] and ta <= uvGateEnd[gi]
                            gateThis = 1
                        endif
                    endfor
                endif
                if gateThis = 1
                    vAmp = silenceDb
                else
                    # QC uses only points whose intensity contour is intended to
                    # be preserved (not closures and not an optional V/UV mute).
                    nQcAmp = nQcAmp + 1
                    qcAmpTime[nQcAmp] = ta
                    qcSourceIntensity[nQcAmp] = iv_a
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
        endif
    endfor

    # Region closing ramp, with the same plosive/gating safeguards.
    rampT = re - ampRamp
    if rampT < rs
        rampT = rs
    endif
    plosControlled = 0
    for kp from 1 to nSyl
        if sylPlosive[kp] = 1 and rampT >= sylPlosStart[kp] and rampT <= sylPlosRelease[kp]
            plosControlled = 1
        endif
    endfor
    if plosControlled = 0
        selectObject: intObj
        rampIv = Get value at time: rampT, "Cubic"
        if rampIv = undefined
            rampIv = threshDb
        endif
        rampAmp = rampIv + ampOffsetDb
        for ks from 1 to nSyl
            if rampT >= sylStart[ks] and rampT <= sylEnd[ks]
                rampAmp = rampAmp + sylShimmerDb[ks]
            endif
        endfor
        gateThis = 0
        if gate_long_unvoiced_runs = 1
            for gi from 1 to nUvGate
                if rampT >= uvGateStart[gi] and rampT <= uvGateEnd[gi]
                    gateThis = 1
                endif
            endfor
        endif
        if gateThis = 1
            rampAmp = silenceDb
        endif
        if rampAmp < silenceDb + 1 and rampAmp <> silenceDb
            rampAmp = silenceDb + 1
        endif
        if rampAmp > ampHi + 3
            rampAmp = ampHi + 3
        endif
        selectObject: kg
        Add voicing amplitude point: rampT, rampAmp
    endif

    selectObject: kg
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
seedAF = nasIdleF
seedAFB = nasIdleB
seedNF = nasIdleF
seedNFB = nasIdleB
if sylStart[1] <= 0.0000001
    seedCons$ = sylCons$[1]
    if seedCons$ = "ma"
        seedF1 = 300
        seedF2 = 1000
        seedAF = nasAF_m
        seedAFB = nasAFB_m
        seedNF = nasPoleF
        seedNFB = nasPoleB
    elsif seedCons$ = "na"
        seedF1 = 300
        seedF2 = 1750
        seedAF = nasAF_n
        seedAFB = nasAFB_n
        seedNF = nasPoleF
        seedNFB = nasPoleB
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
Add nasal formant frequency point: 1, 0, seedNF
Add nasal formant bandwidth point: 1, 0, seedNFB
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
        # Park both pole and zero just before onset so interpolation across the
        # preceding vowel remains neutral; then activate the nasal branch.
        preNasPark = ts - 0.005
        if preNasPark > 0
            Add nasal formant frequency point: 1, preNasPark, nasIdleF
            Add nasal formant bandwidth point: 1, preNasPark, nasIdleB
            Add nasal antiformant frequency point: 1, preNasPark, nasIdleF
            Add nasal antiformant bandwidth point: 1, preNasPark, nasIdleB
        endif
        Add nasal formant frequency point: 1, ts, nasPoleF
        Add nasal formant bandwidth point: 1, ts, nasPoleB
        Add nasal antiformant frequency point: 1, ts, thisNasAF
        Add nasal antiformant bandwidth point: 1, ts, thisNasAFB
        Add nasal formant frequency point: 1, nasEnd, nasPoleF
        Add nasal formant bandwidth point: 1, nasEnd, nasPoleB
        Add nasal antiformant frequency point: 1, nasEnd, thisNasAF
        Add nasal antiformant bandwidth point: 1, nasEnd, thisNasAFB
        postNasPark = nasEnd + 0.005
        if postNasPark > te
            postNasPark = te
        endif
        Add nasal formant frequency point: 1, postNasPark, nasIdleF
        Add nasal formant bandwidth point: 1, postNasPark, nasIdleB
        Add nasal antiformant frequency point: 1, postNasPark, nasIdleF
        Add nasal antiformant bandwidth point: 1, postNasPark, nasIdleB
        Add oral formant frequency point: 1, ts, 300
        Add oral formant frequency point: 1, tn, sylTgtF1[k]
        Add oral formant frequency point: 2, ts, nasalF2Locus
        Add oral formant frequency point: 2, tn, sylTgtF2[k]

    elsif cs$ = "ba" or cs$ = "de"
        # Plosive onset: use the precomputed closure/VOT interval that was
        # excluded from the generic envelope in 8b-ii.
        closEnd = sylPlosClosureEnd[k]
        votEnd = sylPlosRelease[k]
        Add voicing amplitude point: ts, silenceDb
        Add voicing amplitude point: closEnd, silenceDb

        # Return to the LOCAL source-derived level, not a hard-coded 78 dB.
        selectObject: intObj
        releaseIv = Get value at time: votEnd, "Cubic"
        if releaseIv = undefined
            releaseIv = threshDb
        endif
        releaseAmp = releaseIv + ampOffsetDb + sylShimmerDb[k]
        if releaseAmp < silenceDb + 1
            releaseAmp = silenceDb + 1
        endif
        if releaseAmp > ampHi + 3
            releaseAmp = ampHi + 3
        endif
        selectObject: kg
        Add voicing amplitude point: votEnd, releaseAmp

        # F1 closure locus -> vowel at tn
        Add oral formant frequency point: 1, ts,      200
        Add oral formant frequency point: 1, closEnd, 200
        Add oral formant frequency point: 1, tn,      sylTgtF1[k]
        # F2 locus: /ba/ -> 800 Hz; /de/ -> 1800 Hz
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
        preNasPark = ts - 0.005
        if preNasPark > 0
            Add nasal formant frequency point: 1, preNasPark, nasIdleF
            Add nasal formant bandwidth point: 1, preNasPark, nasIdleB
            Add nasal antiformant frequency point: 1, preNasPark, nasIdleF
            Add nasal antiformant bandwidth point: 1, preNasPark, nasIdleB
        endif
        Add nasal formant frequency point: 1, ts, nasPoleF
        Add nasal formant bandwidth point: 1, ts, nasPoleB
        Add nasal antiformant frequency point: 1, ts, nasAF_m
        Add nasal antiformant bandwidth point: 1, ts, nasAFB_m
        Add nasal formant frequency point: 1, nasEnd, nasPoleF
        Add nasal formant bandwidth point: 1, nasEnd, nasPoleB
        Add nasal antiformant frequency point: 1, nasEnd, nasAF_m
        Add nasal antiformant bandwidth point: 1, nasEnd, nasAFB_m
        postNasPark = nasEnd + 0.005
        if postNasPark > te
            postNasPark = te
        endif
        Add nasal formant frequency point: 1, postNasPark, nasIdleF
        Add nasal formant bandwidth point: 1, postNasPark, nasIdleB
        Add nasal antiformant frequency point: 1, postNasPark, nasIdleF
        Add nasal antiformant bandwidth point: 1, postNasPark, nasIdleB
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
Add nasal formant frequency point: 1, origDur, nasIdleF
Add nasal formant bandwidth point: 1, origDur, nasIdleB
Add nasal antiformant frequency point: 1, origDur, nasIdleF
Add nasal antiformant bandwidth point: 1, origDur, nasIdleB

appendInfoLine: "  v2.6: peak-timed nuclei + closure-safe envelope + optional sustained V/UV gate + nasal pole/zero"
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

# ---- F0 preservation vs source + synthesis accuracy vs target ---------------
# Source/output answers the preservation question. Target/output answers whether
# the synthesizer actually hit the manipulated F0 target (important when alpha != 1).
nF0SourcePair = 0
sumSFX = 0
sumSFY = 0
sumSFXX = 0
sumSFYY = 0
sumSFXY = 0
sumSourceSemitoneErr2 = 0

nF0TargetPair = 0
sumTFX = 0
sumTFY = 0
sumTFXX = 0
sumTFYY = 0
sumTFXY = 0
sumTargetSemitoneErr2 = 0

nVu = 0
nVuAgree = 0

for qi from 1 to nQcF0
    tq = qcF0Time[qi]
    sourceVoicedQ = qcSourceVoiced[qi]

    selectObject: outPitchQC
    outF0q = Get value at time: tq, "Hertz", "Linear"
    outVoiced = 1
    if outF0q = undefined or outF0q <= 0
        outVoiced = 0
    endif

    nVu = nVu + 1
    if outVoiced = sourceVoicedQ
        nVuAgree = nVuAgree + 1
    endif

    sourceF0q = qcSourceF0[qi]
    targetF0q = qcTargetF0[qi]

    if sourceVoicedQ = 1 and outVoiced = 1 and sourceF0q > 0
        sfx = log2(sourceF0q)
        sfy = log2(outF0q)
        nF0SourcePair = nF0SourcePair + 1
        sumSFX = sumSFX + sfx
        sumSFY = sumSFY + sfy
        sumSFXX = sumSFXX + sfx * sfx
        sumSFYY = sumSFYY + sfy * sfy
        sumSFXY = sumSFXY + sfx * sfy
        sourceSemitoneErr = 12 * log2(outF0q / sourceF0q)
        sumSourceSemitoneErr2 = sumSourceSemitoneErr2 + sourceSemitoneErr * sourceSemitoneErr
    endif

    if sourceVoicedQ = 1 and outVoiced = 1 and targetF0q > 0
        tfx = log2(targetF0q)
        tfy = log2(outF0q)
        nF0TargetPair = nF0TargetPair + 1
        sumTFX = sumTFX + tfx
        sumTFY = sumTFY + tfy
        sumTFXX = sumTFXX + tfx * tfx
        sumTFYY = sumTFYY + tfy * tfy
        sumTFXY = sumTFXY + tfx * tfy
        targetSemitoneErr = 12 * log2(outF0q / targetF0q)
        sumTargetSemitoneErr2 = sumTargetSemitoneErr2 + targetSemitoneErr * targetSemitoneErr
    endif
endfor

f0SourceCorr = undefined
f0SourceRmseSt = undefined
if nF0SourcePair > 1
    sfden1 = nF0SourcePair * sumSFXX - sumSFX * sumSFX
    sfden2 = nF0SourcePair * sumSFYY - sumSFY * sumSFY
    if sfden1 > 0 and sfden2 > 0
        f0SourceCorr = (nF0SourcePair * sumSFXY - sumSFX * sumSFY) / sqrt(sfden1 * sfden2)
    endif
    f0SourceRmseSt = sqrt(sumSourceSemitoneErr2 / nF0SourcePair)
endif

f0TargetCorr = undefined
f0TargetRmseSt = undefined
if nF0TargetPair > 1
    tfden1 = nF0TargetPair * sumTFXX - sumTFX * sumTFX
    tfden2 = nF0TargetPair * sumTFYY - sumTFY * sumTFY
    if tfden1 > 0 and tfden2 > 0
        f0TargetCorr = (nF0TargetPair * sumTFXY - sumTFX * sumTFY) / sqrt(tfden1 * tfden2)
    endif
    f0TargetRmseSt = sqrt(sumTargetSemitoneErr2 / nF0TargetPair)
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
ampSlope = undefined
ampRmseOffsetDb = undefined
meanADiff = 0
if nAmpPair > 1
    aden1 = nAmpPair * sumAXX - sumAX * sumAX
    aden2 = nAmpPair * sumAYY - sumAY * sumAY
    if aden1 > 0
        ampSlope = (nAmpPair * sumAXY - sumAX * sumAY) / aden1
    endif
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
nSpExcluded = 0
nSpSteps = ceiling(origDur / gstep)
for qi from 0 to nSpSteps
    tq = qi * gstep
    if tq > origDur
        tq = origDur
    endif

    # Exclude deliberately synthetic mute intervals (plosive closure/VOT and
    # optional sustained V/UV gates) from PROSODIC speech/pause preservation QC.
    spEligible = 1
    for kp from 1 to nSyl
        if sylPlosive[kp] = 1 and tq >= sylPlosStart[kp] and tq <= sylPlosRelease[kp]
            spEligible = 0
        endif
    endfor
    if gate_long_unvoiced_runs = 1
        for gi from 1 to nUvGate
            if tq >= uvGateStart[gi] and tq <= uvGateEnd[gi]
                spEligible = 0
            endif
        endfor
    endif

    if spEligible = 1
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
    else
        nSpExcluded = nSpExcluded + 1
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
appendInfoLine: "Synthesis engine:           KlattGrid v2.6 (corrective research pass)"
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
if researchSeed = 0
    appendInfoLine: "Research seed:              unseeded / unpredictable"
else
    appendInfoLine: "Research seed:              ", researchSeed
endif
if gate_long_unvoiced_runs = 1
    appendInfoLine: "Sustained V/UV gating:      ON, min run ", fixed$(minimum_unvoiced_gate_s * 1000, 0), " ms; intervals ", nUvGate, "; total ", fixed$(gatedDuration * 1000, 1), " ms"
else
    appendInfoLine: "Sustained V/UV gating:      OFF (recommended for prosody-only stimuli)"
endif
appendInfoLine: "Duration error:             ", fixed$(durationErrorMs, 3), " ms"
if f0SourceCorr <> undefined
    appendInfoLine: "Source/output F0 corr:      ", fixed$(f0SourceCorr, 4), " (log2-Hz preservation)"
else
    appendInfoLine: "Source/output F0 corr:      undefined (insufficient paired voiced frames)"
endif
if f0SourceRmseSt <> undefined
    appendInfoLine: "Source/output F0 RMSE:      ", fixed$(f0SourceRmseSt, 4), " semitones"
endif
if f0TargetCorr <> undefined
    appendInfoLine: "Target/output F0 corr:      ", fixed$(f0TargetCorr, 4), " (synthesis accuracy)"
else
    appendInfoLine: "Target/output F0 corr:      undefined"
endif
if f0TargetRmseSt <> undefined
    appendInfoLine: "Target/output F0 RMSE:      ", fixed$(f0TargetRmseSt, 4), " semitones"
endif
appendInfoLine: "Pitch V/UV agreement:       ", fixed$(vuAgreementPct, 2), "% (diagnostic only)"
if ampCorr <> undefined
    appendInfoLine: "Intensity-contour corr:     ", fixed$(ampCorr, 4), " (preservation samples)"
else
    appendInfoLine: "Intensity-contour corr:     undefined"
endif
if ampSlope <> undefined
    appendInfoLine: "Intensity dB slope:         ", fixed$(ampSlope, 4), " (1.0 = difference-preserving)"
endif
if ampRmseOffsetDb <> undefined
    appendInfoLine: "Intensity shape RMSE:       ", fixed$(ampRmseOffsetDb, 3), " dB (global level removed)"
else
    appendInfoLine: "Intensity shape RMSE:       undefined"
endif
appendInfoLine: "Speech/pause agreement:     ", fixed$(speechPauseAgreementPct, 2), "% (designed mute frames excluded: ", nSpExcluded, ")"
appendInfoLine: "NOTE: final Scale peak fixes global output level; absolute source/output dB offset is not a preservation metric."
appendInfoLine: "Original waveform not used as audible reiterant output."
appendInfoLine: "EXPERIMENTAL — requires perceptual intelligibility testing."
appendInfoLine: "Compare against stricter hum / low-pass / vocoding controls."
appendInfoLine: "======================================================"
appendInfoLine: "[6/6] Done."

# Compact QC strings for the picture summary.
if f0SourceCorr <> undefined
    qcF0Source$ = fixed$(f0SourceCorr, 3)
else
    qcF0Source$ = "n/a"
endif
if f0TargetCorr <> undefined
    qcF0Target$ = fixed$(f0TargetCorr, 3)
else
    qcF0Target$ = "n/a"
endif
if f0TargetRmseSt <> undefined
    qcF0TargetRmse$ = fixed$(f0TargetRmseSt, 2)
else
    qcF0TargetRmse$ = "n/a"
endif
if ampCorr <> undefined
    qcAmpCorr$ = fixed$(ampCorr, 3)
else
    qcAmpCorr$ = "n/a"
endif
if ampSlope <> undefined
    qcAmpSlope$ = fixed$(ampSlope, 2)
else
    qcAmpSlope$ = "n/a"
endif
if ampRmseOffsetDb <> undefined
    qcAmpRmse$ = fixed$(ampRmseOffsetDb, 2)
else
    qcAmpRmse$ = "n/a"
endif
if researchSeed = 0
    qcSeed$ = "unseeded"
else
    qcSeed$ = string$(researchSeed)
endif

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
    # v2.6.2 visualization-only redesign.
    # The figure explains the experimental mechanism as well as validating it.
    # Every comparison uses the same axes, measured DSP/QC data, and explicit
    # viewport resets so Picture-window state cannot leak between panels.

    # ---- restrained AudioTools palette ----
    srcCol$    = "{0.20, 0.20, 0.24}"
    targetCol$ = "{0.72, 0.42, 0.34}"
    outCol$    = "{0.15, 0.42, 0.80}"
    wavS$      = "{0.50, 0.50, 0.55}"
    bg$        = "{0.975, 0.975, 0.978}"
    speechBg$  = "{0.945, 0.960, 0.975}"
    refCol$    = "{0.62, 0.62, 0.62}"
    sylCol$    = "{0.80, 0.45, 0.45}"
    qcBg$      = "{0.945, 0.945, 0.948}"

    # ---- shared time ticks ----
    if origDur <= 2
        tTick = 0.2
    elsif origDur <= 5
        tTick = 0.5
    elsif origDur <= 12
        tTick = 1
    else
        tTick = 2
    endif

    outPitch = outPitchQC
    outInt = outIntQC

    # Stable page geometry. Title strips are independent from data viewports.
    lpL = 0.95
    lpR = 7.70

    Erase all
    Select outer viewport: 0, 8, 0, 8
    Black
    Plain line
    Line width: 1

    # ==========================================================
    # HEADER
    # ==========================================================
    Select inner viewport: 0.60, 7.70, 0.05, 0.30
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.52, "half", "##Reiterant prosody synthesis | acoustic validation##"

    Select inner viewport: 0.60, 7.70, 0.32, 0.55
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.35, 0.35, 0.45}"
    Text: 0.5, "centre", 0.52, "half",
        ... "preset " + presetName$
        ... + "   |   pattern /" + patternStr$ + "/"
        ... + "   |   alpha " + fixed$(pitch_strength, 2)
        ... + "   |   Nat " + fixed$(naturalness, 2)
        ... + "   |   " + string$(nSyl) + " syllables / " + string$(nReg) + " speech regions"

    # ==========================================================
    # PANEL A TITLE — measured timing scaffold
    # ==========================================================
    Select inner viewport: lpL, lpR, 0.62, 0.79
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.00, "left", 0.50, "half", "##A  Timing scaffold##"
    Font size: 5.5
    Colour: "{0.40, 0.40, 0.44}"
    Text: 0.24, "left", 0.50, "half", "speech regions | syllable bounds | detected nuclei"

    # ==========================================================
    # PANEL A DATA
    # ==========================================================
    Select inner viewport: lpL, lpR, 0.82, 1.95
    selectObject: srcMono
    sPk = Get absolute extremum: 0, 0, "None"
    if sPk = undefined or sPk <= 0
        sPk = 1
    endif
    sRange = 1.08 * sPk

    Axes: 0, 1, 0, 1
    Paint rectangle: bg$, 0, 1, 0, 1
    Axes: 0, origDur, -sRange, sRange

    # Speech regions are the large-scale timing structure.
    for r from 1 to nReg
        Paint rectangle: speechBg$, regStart[r], regEnd[r], -sRange, sRange
    endfor

    Marks bottom every: 1, tTick, "no", "yes", "yes"
    Colour: refCol$
    Draw line: 0, 0, origDur, 0

    selectObject: srcMono
    Colour: wavS$
    Draw: 0, origDur, -sRange, sRange, "no", "Curve"

    # Syllable boundaries and measured nuclei.
    Select inner viewport: lpL, lpR, 0.82, 1.95
    Axes: 0, origDur, -sRange, sRange
    Colour: sylCol$
    Dotted line
    for k from 1 to nSyl
        Draw line: sylStart[k], -0.92 * sRange, sylStart[k], 0.92 * sRange
    endfor
    Plain line
    Colour: "Black"
    for k from 1 to nSyl
        Draw line: sylNucT[k], 0.72 * sRange, sylNucT[k], 0.92 * sRange
    endfor

    # Labels are useful only while they remain readable.
    if nSyl <= 14
        Font size: 5
        Colour: "{0.35, 0.35, 0.35}"
        for k from 1 to nSyl
            Text: sylNucT[k], "centre", 0.58 * sRange, "half", sylCons$[k]
        endfor
    endif

    Colour: "Black"
    Draw inner box
    Text left: "yes", "amplitude"

    # ==========================================================
    # PANEL B TITLE — actual F0 transformation mechanism
    # ==========================================================
    Select inner viewport: lpL, lpR, 2.10, 2.28
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.00, "left", 0.50, "half", "##B  F0 transformation | semitones re median##"
    Font size: 5.5
    Colour: srcCol$
    Text: 0.69, "left", 0.50, "half", "source"
    Colour: targetCol$
    Text: 0.79, "left", 0.50, "half", "target"
    Colour: outCol$
    Text: 0.89, "left", 0.50, "half", "output"

    # Find a symmetric semitone range from the ACTUAL source, target and output.
    stAbsMax = 2
    for qi from 1 to nQcF0
        if qcSourceVoiced[qi] = 1 and qcSourceF0[qi] > 0 and qcTargetF0[qi] > 0
            srcStRange = 12 * log2(qcSourceF0[qi] / medianF0)
            tgtStRange = 12 * log2(qcTargetF0[qi] / medianF0)
            stAbsMax = max(stAbsMax, abs(srcStRange))
            stAbsMax = max(stAbsMax, abs(tgtStRange))

            selectObject: outPitch
            outF0Range = Get value at time: qcF0Time[qi], "Hertz", "Linear"
            if outF0Range <> undefined and outF0Range > 0
                outStRange = 12 * log2(outF0Range / medianF0)
                stAbsMax = max(stAbsMax, abs(outStRange))
            endif
        endif
    endfor
    stRange = ceiling(stAbsMax + 1)
    if stRange < 3
        stRange = 3
    endif
    if stRange <= 6
        stTick = 2
    elsif stRange <= 12
        stTick = 4
    else
        stTick = 6
    endif

    # ==========================================================
    # PANEL B DATA
    # ==========================================================
    Select inner viewport: lpL, lpR, 2.32, 3.50
    Axes: 0, 1, 0, 1
    Paint rectangle: bg$, 0, 1, 0, 1
    Axes: 0, origDur, -stRange, stRange
    Marks left every: 1, stTick, "yes", "yes", "yes"
    Marks bottom every: 1, tTick, "no", "yes", "yes"

    # Median reference = 0 semitones.
    Colour: refCol$
    Dotted line
    Draw line: 0, 0, origDur, 0
    Plain line

    prevSrcValid = 0
    prevTgtValid = 0
    prevOutValid = 0
    prevSrcT = 0
    prevTgtT = 0
    prevOutT = 0
    prevSrcSt = 0
    prevTgtSt = 0
    prevOutSt = 0

    for qi from 1 to nQcF0
        tq = qcF0Time[qi]
        srcValid = 0
        tgtValid = 0
        outValid = 0

        if qcSourceVoiced[qi] = 1 and qcSourceF0[qi] > 0
            srcSt = 12 * log2(qcSourceF0[qi] / medianF0)
            srcValid = 1
        endif
        if qcSourceVoiced[qi] = 1 and qcTargetF0[qi] > 0
            tgtSt = 12 * log2(qcTargetF0[qi] / medianF0)
            tgtValid = 1
        endif

        selectObject: outPitch
        outF0Draw = Get value at time: tq, "Hertz", "Linear"
        if qcSourceVoiced[qi] = 1 and outF0Draw <> undefined and outF0Draw > 0
            outSt = 12 * log2(outF0Draw / medianF0)
            outValid = 1
        endif

        Select inner viewport: lpL, lpR, 2.32, 3.50
        Axes: 0, origDur, -stRange, stRange

        if srcValid = 1
            if prevSrcValid = 1 and tq - prevSrcT <= 0.015
                Colour: srcCol$
                Draw line: prevSrcT, prevSrcSt, tq, srcSt
            endif
            prevSrcT = tq
            prevSrcSt = srcSt
        endif

        if tgtValid = 1
            if prevTgtValid = 1 and tq - prevTgtT <= 0.015
                Colour: targetCol$
                Draw line: prevTgtT, prevTgtSt, tq, tgtSt
            endif
            prevTgtT = tq
            prevTgtSt = tgtSt
        endif

        if outValid = 1
            if prevOutValid = 1 and tq - prevOutT <= 0.015
                Colour: outCol$
                Draw line: prevOutT, prevOutSt, tq, outSt
            endif
            prevOutT = tq
            prevOutSt = outSt
        endif

        prevSrcValid = srcValid
        prevTgtValid = tgtValid
        prevOutValid = outValid
    endfor

    Colour: "Black"
    Draw inner box
    Text left: "yes", "semitones"

    # ==========================================================
    # PANEL C TITLE — intensity shape, not absolute level
    # ==========================================================
    Select inner viewport: lpL, lpR, 3.64, 3.82
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.00, "left", 0.50, "half", "##C  Intensity-shape preservation | mean removed##"
    Font size: 5.5
    Colour: srcCol$
    Text: 0.79, "left", 0.50, "half", "source"
    Colour: outCol$
    Text: 0.89, "left", 0.50, "half", "output"

    # Means are computed over exactly the same QC-eligible paired frames used
    # for the numerical intensity metrics.
    if nAmpPair > 1
        meanSrcAmp = sumAX / nAmpPair
        meanOutAmp = sumAY / nAmpPair
    else
        meanSrcAmp = 0
        meanOutAmp = 0
    endif

    dbAbsMax = 5
    if nAmpPair > 1
        for qi from 1 to nQcAmp
            tq = qcAmpTime[qi]
            srcIq = qcSourceIntensity[qi]
            selectObject: outInt
            outIq = Get value at time: tq, "Cubic"
            if outIq <> undefined and srcIq >= threshDb
                srcRelRange = srcIq - meanSrcAmp
                outRelRange = outIq - meanOutAmp
                dbAbsMax = max(dbAbsMax, abs(srcRelRange))
                dbAbsMax = max(dbAbsMax, abs(outRelRange))
            endif
        endfor
    endif
    dbRange = ceiling(dbAbsMax + 1)
    if dbRange < 6
        dbRange = 6
    endif
    if dbRange <= 10
        dbShapeTick = 2
    elsif dbRange <= 25
        dbShapeTick = 5
    else
        dbShapeTick = 10
    endif

    # ==========================================================
    # PANEL C DATA
    # ==========================================================
    Select inner viewport: lpL, lpR, 3.86, 5.04
    Axes: 0, 1, 0, 1
    Paint rectangle: bg$, 0, 1, 0, 1
    Axes: 0, origDur, -dbRange, dbRange
    Marks left every: 1, dbShapeTick, "yes", "yes", "yes"
    Marks bottom every: 1, tTick, "no", "yes", "yes"

    Colour: refCol$
    Dotted line
    Draw line: 0, 0, origDur, 0
    Plain line

    if nAmpPair > 1
        prevAmpValid = 0
        prevAmpT = 0
        prevSrcRel = 0
        prevOutRel = 0

        for qi from 1 to nQcAmp
            tq = qcAmpTime[qi]
            srcIq = qcSourceIntensity[qi]
            selectObject: outInt
            outIq = Get value at time: tq, "Cubic"
            ampValid = 0
            if outIq <> undefined and srcIq >= threshDb
                ampValid = 1
                srcRel = srcIq - meanSrcAmp
                outRel = outIq - meanOutAmp
            endif

            Select inner viewport: lpL, lpR, 3.86, 5.04
            Axes: 0, origDur, -dbRange, dbRange

            if ampValid = 1
                # Do not bridge designed closures, pauses, or omitted QC frames.
                if prevAmpValid = 1 and tq - prevAmpT <= 0.025
                    Colour: srcCol$
                    Draw line: prevAmpT, prevSrcRel, tq, srcRel
                    Colour: outCol$
                    Draw line: prevAmpT, prevOutRel, tq, outRel
                endif
                prevAmpT = tq
                prevSrcRel = srcRel
                prevOutRel = outRel
            endif
            prevAmpValid = ampValid
        endfor
    else
        Select inner viewport: lpL, lpR, 3.86, 5.04
        Axes: 0, 1, 0, 1
        Font size: 6
        Colour: "{0.45, 0.45, 0.45}"
        Text: 0.5, "centre", 0.5, "half", "insufficient paired intensity frames"
    endif

    Select inner viewport: lpL, lpR, 3.86, 5.04
    Axes: 0, origDur, -dbRange, dbRange
    Colour: "Black"
    Draw inner box
    Text left: "yes", "relative dB"

    # ==========================================================
    # PANEL D TITLE
    # ==========================================================
    Select inner viewport: lpL, lpR, 5.18, 5.36
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    if draw_spectrogram = 1
        Text: 0.00, "left", 0.50, "half", "##D  Output spectral check##"
    else
        Text: 0.00, "left", 0.50, "half", "##D  Experimental mechanism | what is preserved and what is replaced##"
    endif

    # ==========================================================
    # PANEL D DATA — optional spectrogram or explanatory process diagram
    # ==========================================================
    Select inner viewport: lpL, lpR, 5.40, 6.84

    if draw_spectrogram = 1
        selectObject: resultFinal
        outSrVis = Get sampling frequency
        specMax = min(5000, 0.48 * outSrVis)
        spec = To Spectrogram: 0.005, specMax, 0.002, 20, "Gaussian"
        selectObject: spec
        Paint: 0, origDur, 0, specMax, 100, "yes", 50, 6, 0, "no"
        removeObject: spec

        Select inner viewport: lpL, lpR, 5.40, 6.84
        Axes: 0, origDur, 0, specMax
        selectObject: outPitch
        Colour: outCol$
        Draw: 0, origDur, 0, specMax, "no"

        Select inner viewport: lpL, lpR, 5.40, 6.84
        Axes: 0, origDur, 0, specMax
        Colour: "Black"
        Marks left every: 1, 1000, "yes", "yes", "no"
        Marks bottom every: 1, tTick, "yes", "yes", "no"
        Draw inner box
        Text left: "yes", "frequency (Hz)"
        Text bottom: "yes", "Time (s)"
    else
        Axes: 0, 1, 0, 1
        Paint rectangle: bg$, 0, 1, 0, 1

        # Process boxes.
        Paint rectangle: "{0.92, 0.92, 0.93}", 0.03, 0.20, 0.43, 0.82
        Paint rectangle: "{0.90, 0.94, 0.98}", 0.28, 0.46, 0.43, 0.82
        Paint rectangle: "{0.98, 0.93, 0.91}", 0.54, 0.72, 0.43, 0.82
        Paint rectangle: "{0.91, 0.95, 0.99}", 0.80, 0.97, 0.43, 0.82

        Colour: "{0.35, 0.35, 0.38}"
        Draw rectangle: 0.03, 0.20, 0.43, 0.82
        Draw rectangle: 0.28, 0.46, 0.43, 0.82
        Draw rectangle: 0.54, 0.72, 0.43, 0.82
        Draw rectangle: 0.80, 0.97, 0.43, 0.82

        Font size: 6
        Colour: "Black"
        Text: 0.115, "centre", 0.69, "half", "##SOURCE##"
        Font size: 5
        Text: 0.115, "centre", 0.55, "half", "timing | F0 | dB"

        Font size: 6
        Text: 0.37, "centre", 0.69, "half", "##PROSODY MAP##"
        Font size: 5
        Text: 0.37, "centre", 0.55, "half", "regions | nuclei | alpha"

        Font size: 6
        Text: 0.63, "centre", 0.69, "half", "##REITERANT KLATT##"
        Font size: 5
        Text: 0.63, "centre", 0.55, "half", "/" + patternStr$ + "/ scaffold"

        Font size: 6
        Text: 0.885, "centre", 0.69, "half", "##OUTPUT##"
        Font size: 5
        Text: 0.885, "centre", 0.55, "half", "prosody without words"

        # Arrows and action labels.
        Colour: "{0.35, 0.35, 0.38}"
        Arrow size: 1.0
        Draw arrow: 0.205, 0.625, 0.275, 0.625
        Draw arrow: 0.465, 0.625, 0.535, 0.625
        Draw arrow: 0.725, 0.625, 0.795, 0.625
        Font size: 4.5
        Colour: "{0.45, 0.45, 0.48}"
        Text: 0.24, "centre", 0.74, "half", "measure"
        Text: 0.50, "centre", 0.74, "half", "map"
        Text: 0.76, "centre", 0.74, "half", "synth"

        # Governing F0 formula in the same domain used by the DSP.
        Font size: 6
        Colour: "{0.28, 0.28, 0.32}"
        Text: 0.5, "centre", 0.25, "half",
            ... "log2(F0target/F0med) = alpha * log2(F0source/F0med)"
        Font size: 5
        Colour: "{0.45, 0.45, 0.48}"
        Text: 0.5, "centre", 0.11, "half",
            ... "segment identity is synthetic; timing, F0 target and intensity shape come from the source"

        Colour: "Black"
        Draw inner box
    endif

    # ==========================================================
    # THREE-COLUMN RESEARCH QC DASHBOARD
    # ==========================================================
    Select inner viewport: lpL, lpR, 7.02, 7.78
    Axes: 0, 1, 0, 1
    Paint rectangle: qcBg$, 0, 1, 0, 1
    Colour: "{0.72, 0.72, 0.74}"
    Draw line: 0.335, 0.08, 0.335, 0.92
    Draw line: 0.67, 0.08, 0.67, 0.92

    # Column 1: preservation.
    Font size: 5.5
    Colour: "{0.28, 0.28, 0.32}"
    Text: 0.02, "left", 0.78, "half", "##PRESERVATION##"
    Font size: 5.2
    Text: 0.02, "left", 0.49, "half", "F0 source-output r  " + qcF0Source$
    Text: 0.02, "left", 0.22, "half", "Intensity contour r  " + qcAmpCorr$

    # Column 2: shape and timing.
    Font size: 5.5
    Text: 0.355, "left", 0.78, "half", "##SHAPE + TIMING##"
    Font size: 5.2
    Text: 0.355, "left", 0.49, "half", "dB slope " + qcAmpSlope$ + " | RMSE " + qcAmpRmse$ + " dB"
    Text: 0.355, "left", 0.22, "half",
        ... "speech/pause " + fixed$(speechPauseAgreementPct, 1) + " pct | dur err " + fixed$(durationErrorMs, 1) + " ms"

    # Column 3: synthesis accuracy.
    Font size: 5.5
    Text: 0.69, "left", 0.78, "half", "##SYNTHESIS CHECK##"
    Font size: 5.2
    Text: 0.69, "left", 0.49, "half", "Target-output F0 r  " + qcF0Target$
    Text: 0.69, "left", 0.22, "half", "RMSE " + qcF0TargetRmse$ + " st | seed " + qcSeed$

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # Reset global Picture defaults for subsequent script drawings.
    Font size: 10
    Colour: "Black"
    Plain line
    Line width: 1
endproc
