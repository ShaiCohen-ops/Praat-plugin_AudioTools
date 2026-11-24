# ============================================================
# Praat AudioTools - Rhythmic_Imprinting.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.4 (2026) - integrated rhythmic composition (Python engine v1.3)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   RHYTHMIC IMPRINTING
#   Gesture-driven recomposition of recorded sound.
#
#   Three workflows (v1.4):
#     A  Recorded rhythm -> recorded sound: two Sounds, as in v1.3.
#     B  Generated rhythm -> recorded sound: one Sound (= B); a rhythmic
#        composition is generated and used internally as A.
#     C  Generated rhythm only: no Sound needed, no Python; a standalone
#        monophonic rhythmic composition.
#
#   Two selected Sounds: A = Rhythm / Gesture Driver, B = Sound Material.
#   A supplies the timing, articulation pattern and broad gestural
#   organisation. B supplies the audible sonic identity. Complete
#   gestures are selected from B and recomposed on A's timeline.
#   This can impose a pulse pattern on speech, or - by reversing A/B -
#   articulate an electronic tone sequence using the rhythm of speech.
#
#   The process uses recorded B samples: no time-stretching, pitch
#   shifting, spectral resynthesis or continuous timbral morphing.
#   The result can transform musical syntax without transforming the
#   internal spectrum of every individual source gesture.
#
#   Matching is whole-gesture, NOT frame-by-frame. It uses acoustic
#   descriptor trajectories, optional joint CNN representations, and
#   duration, with phrase-aware sequencing. The CNN is optional and
#   does not by itself establish better musical correspondence.
#
# ============================================================
# HELP - RHYTHMIC IMPRINTING (v1.4)
# ============================================================
# PURPOSE
#   Imprint the RHYTHMIC / GESTURAL ORGANISATION of recording A
#   onto the SOUND MATERIAL of recording B. A determines when and
#   how the selected gestures appear; B determines what we hear.
#
# GETTING STARTED
#   1. Select two Sound objects in the Praat Objects window.
#   2. In 'Driver A is', choose which Sound supplies the rhythm.
#   3. The other Sound supplies the actual samples in the result.
#   4. Start with Preset = Pulse Lock for direct rhythmic imprinting.
#   5. Select Manual for individual controls or Hybrid Explorer for a
#      learned alternative (which may fall back to Acoustic).
#
# GENERATED RHYTHM (v1.4)
#   Rhythmic_source = Generate rhythmic composition. After OK a second
#   dialog asks for the generation parameters (duration, tempo, complexity,
#   density, duration contrast, articulation, formal development; Standards
#   restores the defaults). Random_seed is shared with the imprinting stage.
#   Imprint ... onto B on : select ONE Sound (B). Workflow B.
#   Imprint ... onto B off: no selection needed. Workflow C (no Python).
#   Models: Motivic Development (Statement, Variation, Compression, Climax,
#   Caesura, Return), Euclidean Evolution, Acceleration / Deceleration,
#   Stochastic Articulation, Additive / Subtractive Rhythm.
#   ONSET / DURATION / SILENCE: the model alone decides onsets, notated
#   values and rests. Articulation and Duration_contrast only decide which
#   fraction of each notated value sounds; they never move an onset, change
#   the event count or a section boundary, and a note never reaches the
#   next onset. The schedule is passed to the engine directly (no second
#   segmentation of the generated Sound); the report compares it with the
#   automatic segmentation.
#   Whether note duration changes the imprint is EXPERIMENTAL and not
#   established. In Following mode B gestures are cut by the inter-onset
#   slot, not by A's note length; A's durations act through the matching
#   cost, phrase detection and the lengthening of short B gestures.
#   Presets never change the generation parameters.
#
# PRESETS (v1.3)
#   Pulse Lock: following mode, short clear attack placements.
#   Syllabic Fracture: finer, tighter speech-like fragments; repeats allowed.
#   Phrase Shadow: longer source gestures, smoother transitions.
#   Contrast Cuts: juxtaposition and gestural contrast, not invented onsets.
#   Elastic Dialogue: B phrase timing may drift within A phrases.
#   Hybrid Explorer: explore learned source choices; can fall back to Acoustic.
#   Manual: all numeric/matching/mode fields in the form are used as shown.
#   IMPORTANT: when a named preset is selected, matching, mode and numeric
#   values displayed beneath it are OVERRIDDEN after OK. Driver A, training,
#   seed, playback and diagnostic export are never overridden. The Info window
#   lists the effective parameters for each run.
#
# REVERSE THE DIRECTION
#   Pulse A + speech B: the pulse pattern reorganises spoken syllables.
#   Speech A + pulse B: the syllabic timing reorganises electronic tones.
#   Reversing A and B is not an inverse signal process; it creates
#   a different composition, with a different sounding material.
#
# WHAT IT DOES / DOES NOT DO
#   Following preserves A's gesture onsets; Dialogue permits rhythmic
#   drift and dialogue with B's own temporal succession.
#   The tool cuts and recomposes gestures from B with gain and fades.
#   It does NOT time-stretch, pitch-shift or spectrally transform B.
#   A clear rhythmic imprint is not evidence of CNN added value:
#   Following explicitly preserves A's onset times even in Acoustic.
#   The learned methods may fall back to Acoustic if validation fails;
#   check the Info report and the output name ('acousticFallback').
#
# MATERIAL GUIDANCE
#   Clear attacks and sufficiently varied B gestures give the
#   segmentation and matching stages more to work with. Continuous
#   textures may produce less perceptible rhythmic transfer.
# ============================================================

# Pipeline:
#   1. Validate two Sounds and the A/B assignment. Analysis uses
#      the mean POWER spectrum of all channels of each Sound (every
#      channel's gestures count; anti-phase material cannot cancel
#      as it would in a sample sum). B keeps all channels and its
#      full precision for the final assembly.
#   2. Python engine (py/rhythmic_imprinting.py):
#      adaptive segmentation (level gate relative to each
#      recording + onset novelty from level rise, spectral flux
#      and timbre change; merging of lead-ins and repeated
#      articulations; splitting of over-long gestures), seven
#      descriptor trajectories per gesture, the Recomposer CNN
#      trained jointly on both recordings, collapse / source-bias
#      / augmentation diagnostics, DTW trajectory distance,
#      Viterbi phrase sequencing, placement plan.
#   3. Praat cuts B by sample index and adds each gesture into an
#      output buffer with one gain and raised-cosine edge fades.
#      Nothing is stretched, pitch-shifted or spectrally processed.
#      One common gain is applied only if the peak would exceed
#      -1 dBFS.
#
# Matching_method:
#   Acoustic  - 32 handcrafted summary descriptors (baseline).
#   Joint CNN - learned embedding (source-centred).
#   Hybrid    - equal blend of the two.
#   Compare all three (A/B) - renders all three with IDENTICAL
#               segmentation, costs and synthesis, so the
#               contribution of the learned representation can be
#               heard rather than asserted.
#   Joint CNN and Hybrid are used only if the REPRESENTATION
#   INTEGRITY CHECK (technical soundness) passes AND listener anchor
#   pairs, when given, do not show them WORSE than Acoustic. Passing
#   the integrity check does NOT mean the CNN matches instruments
#   better than Acoustic; that has not been demonstrated. The report
#   always states the added value: ESTABLISHED / NOT DETECTED /
#   NEGATIVE / UNDECIDED / NOT EVALUATED.
#
# Compositional_mode:
#   Following - every onset of A is kept: A's dramaturgy, exactly.
#   Dialogue  - wider candidate pool, seeded substitutions, and
#               chains of successive B gestures keep B's own timing
#               inside an A phrase (bounded drift, re-synchronised
#               at A's phrase boundaries).
#
# Continuity_vs_contrast: 0 = smoothest junctions between the
#   chosen B gestures; 1 = B's junction contrast follows the
#   contrast between A's own successive gestures.
#
# Requires: Praat 6.1.38 or newer (verified headless on 6.1.38,
#   6.4.06 and 7.0); Python 3 with numpy and
#   scikit-learn (pip install numpy scikit-learn). Nothing is
#   installed automatically, nothing is downloaded, no model file
#   is written.
#
# Listener anchor pairs (optional external test):
#   Select a Table together with the two Sounds, with columns
#   a_time and b_time (seconds, in each Sound's own time axis):
#   pairs of an A gesture and a B gesture you judge behaviourally
#   similar by ear. They are NEVER used for training. The report
#   gives, per method, where your B gesture ranks among all of B,
#   and a bootstrap interval for CNN minus Acoustic.
#
# Presets update (v1.3): six named compositional starting points; the
#   original Python engine v1.2 and its musical algorithms are unchanged.
#
# Changelog v1.4 (2026) - integrated rhythmic composition:
#   - Rhythmic_source, Rhythmic_model, Imprint_generated_rhythm_onto_B and
#     Keep_generated_rhythm_as_Sound in the form; generation parameters in
#     a second dialog shown only when generating (keeps the form short).
#   - Workflows B (generate + imprint) and C (generate only, pure Praat).
#   - Five models; event schedule with onset, notated value, sounding
#     duration, accent, section and model (RI_schedule Table on export).
#   - Engine v1.3: optional 'a_events' schedule input. Recorded drivers
#     are segmented exactly as in v1.2.
#   - Generated-form figure panel; generation section in the Info report.
#   - Model 1 uses a PROVISIONAL seven-event motif until the
#     Rhythmic_Form_POC.praat motif is integrated.
#
# Naming update (2026): "Rhythmic Imprinting" describes the audible
#   compositional operation, rather than an optional ML implementation.
#   A/B can be reversed. Engine algorithm and UI parameters are unchanged.
#
# Changelog v1.2 (2026) - second review:
#   - The v1.1 "Reliability gate" could PASS a CNN that ranked the
#     listener's pairs worse than Acoustic. Now two separate verdicts:
#     REPRESENTATION INTEGRITY CHECK (technical soundness only:
#     collapse, source bias, gain over an untrained network,
#     second-seed rank agreement >= 0.50, validation actually run)
#     and CROSS-INSTRUMENT CORRESPONDENCE EVALUATION (listener anchor
#     pairs). The CNN is used only if integrity passes AND the anchors
#     do not show it WORSE than Acoustic; CNN and Hybrid are judged
#     separately. Without anchors the report says explicitly that
#     there is no evidence the CNN adds anything beyond Acoustic.
#   - Training batches strictly balanced: k gestures from EACH
#     recording (v1.1 could train on 6 A + 58 B).
#   - Validated mode: the held-out split works from 7 gestures per
#     recording; when it cannot run, VALIDATION INSUFFICIENT fails the
#     integrity check instead of passing silently.
#   - Two caches: features + DTW are shared by all methods; switching
#     Acoustic -> Hybrid only trains the CNN.
#
# Changelog v1.1 (2026) - review repairs:
#   - Coverage: v1.0 let a short B gesture run on into B's SILENCE
#     and counted that as covered (reviewer's case: 30% reported,
#     10% sounding). Extension now stops at B's own level gate, and
#     two coverages are reported: timeline, and sounding (B material
#     that is itself above B's gate).
#   - Reliability gate: CNN / Hybrid fall back to Acoustic (named
#     "_acousticFallback") when the embedding collapses, keeps a
#     source-identity bias > 0.85, or shows no retrieval gain over
#     an untrained network, in-sample or on held-out gestures. In
#     Compare mode the CNN is still rendered, named "_UNRELIABLE".
#   - Training: 150 steps instead of 500. Measured on the synthetic
#     pair (3 seeds), the CNN trained 150 steps matched the designed
#     classes across recordings better than the SAME CNN trained 500
#     steps (0.99 vs 0.88): longer training learns each recording's
#     specifics. (A CNN-vs-CNN comparison, not CNN vs Acoustic.) Training = Validated adds a held-out
#     check (20% of gestures never trained on) and a second seed.
#   - Cache: analysis, training and DTW are reused when only the
#     compositional settings change (method, morph, contrast,
#     flexibility, crossfade, mode, repetition).
#   - Analysis on all channels (power-spectrum mean) instead of the
#     highest-RMS channel.
#   - Optional listener anchor pairs (see above).
#
# Changelog v1.0 (2026):
#   - Initial release.
#
# Citation:
#   Cohen, S. (2026). Rhythmic Imprinting: Gesture-Driven
#   Recomposition of Recorded Sound. Praat AudioTools Plugin.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Rhythmic Imprinting v1.4
    comment A = Rhythm / Gesture Driver; B = Sound Material (output audio comes from B).
    optionmenu Rhythmic_source: 1
        option Existing Sound A
        option Generate rhythmic composition
    optionmenu Rhythmic_model: 1
        option Motivic Development
        option Euclidean Evolution
        option Acceleration / Deceleration
        option Stochastic Articulation
        option Additive / Subtractive Rhythm
    boolean Imprint_generated_rhythm_onto_B 1
    boolean Keep_generated_rhythm_as_Sound 1
    comment Generate: parameters follow in a second dialog. Existing: Driver_A_is picks A.
    optionmenu Driver_A_is: 1
        option First selected Sound (higher in the list)
        option Second selected Sound (lower in the list)
    optionmenu Preset: 2
        option Manual (use controls below)
        option Pulse Lock (precise rhythm)
        option Syllabic Fracture (speech cuts)
        option Phrase Shadow (long gestures)
        option Contrast Cuts (sharp changes)
        option Elastic Dialogue (rhythmic drift)
        option Hybrid Explorer (experimental CNN)
    comment Presets override the matching method, mode and numeric controls below.
    comment Driver A, Training, Random seed, Play and Export remain independent.
    real Segmentation_sensitivity 0.5
    positive Minimum_gesture_duration_s 0.08
    positive Maximum_gesture_duration_s 2.5
    optionmenu Matching_method: 3
        option Acoustic
        option Joint CNN
        option Hybrid
        option Compare all three (A/B)
    optionmenu Training: 1
        option Validated (held-out check + second seed)
        option Quick (no validation)
    real Morphological_similarity 0.5
    real Continuity_vs_contrast 0.5
    real Duration_flexibility 0.5
    real Crossfade_ms 12
    optionmenu Compositional_mode: 1
        option Following
        option Dialogue
    boolean Avoid_repetition 1
    integer Random_seed 1
    boolean Play_result 1
    boolean Export_diagnostic_data 0
endform

# ============================================================
# MUSICAL PRESETS (v1.3)
# ============================================================
# Each preset sets a complete, reproducible cluster of musical controls.
# The values displayed in the form are the MANUAL defaults; because Praat
# form controls cannot be refreshed by another optionmenu, a non-Manual
# preset deliberately overrides them AFTER the user presses OK.
# Driver_A_is, Training, Random_seed, Play_result and Export_diagnostic_data
# are independent and are NEVER overwritten.
# The Python analysis/matching/renderer is unchanged from engine v1.2.
# These are starting points, not audio-invariant guarantees.
presetName$ = "Manual"
if preset = 2
    presetName$ = "Pulse Lock"
    matching_method = 1
    compositional_mode = 1
    segmentation_sensitivity = 0.70
    minimum_gesture_duration_s = 0.045
    maximum_gesture_duration_s = 0.70
    morphological_similarity = 0.70
    continuity_vs_contrast = 0.45
    duration_flexibility = 0.20
    crossfade_ms = 6
    avoid_repetition = 1
elsif preset = 3
    presetName$ = "Syllabic Fracture"
    matching_method = 1
    compositional_mode = 1
    segmentation_sensitivity = 0.88
    minimum_gesture_duration_s = 0.035
    maximum_gesture_duration_s = 0.35
    morphological_similarity = 0.80
    continuity_vs_contrast = 0.80
    duration_flexibility = 0.18
    crossfade_ms = 5
    avoid_repetition = 0
elsif preset = 4
    presetName$ = "Phrase Shadow"
    matching_method = 1
    compositional_mode = 1
    segmentation_sensitivity = 0.38
    minimum_gesture_duration_s = 0.15
    maximum_gesture_duration_s = 2.70
    morphological_similarity = 0.70
    continuity_vs_contrast = 0.20
    duration_flexibility = 0.72
    crossfade_ms = 30
    avoid_repetition = 1
elsif preset = 5
    presetName$ = "Contrast Cuts"
    matching_method = 1
    compositional_mode = 1
    segmentation_sensitivity = 0.80
    minimum_gesture_duration_s = 0.05
    maximum_gesture_duration_s = 0.70
    morphological_similarity = 0.25
    continuity_vs_contrast = 1.00
    duration_flexibility = 0.28
    crossfade_ms = 8
    avoid_repetition = 1
elsif preset = 6
    presetName$ = "Elastic Dialogue"
    matching_method = 1
    compositional_mode = 2
    segmentation_sensitivity = 0.55
    minimum_gesture_duration_s = 0.09
    maximum_gesture_duration_s = 1.40
    morphological_similarity = 0.50
    continuity_vs_contrast = 0.65
    duration_flexibility = 0.70
    crossfade_ms = 16
    avoid_repetition = 1
elsif preset = 7
    presetName$ = "Hybrid Explorer"
    matching_method = 3
    compositional_mode = 1
    segmentation_sensitivity = 0.60
    minimum_gesture_duration_s = 0.07
    maximum_gesture_duration_s = 1.40
    morphological_similarity = 0.25
    continuity_vs_contrast = 0.60
    duration_flexibility = 0.50
    crossfade_ms = 12
    avoid_repetition = 1
endif

# ============================================================
# WORKFLOW (v1.4)
# ============================================================
if rhythmic_model = 1
    modelName$ = "Motivic Development"
    modelShort$ = "Motivic"
elsif rhythmic_model = 2
    modelName$ = "Euclidean Evolution"
    modelShort$ = "Euclidean"
elsif rhythmic_model = 3
    modelName$ = "Acceleration / Deceleration"
    modelShort$ = "AccelDecel"
elsif rhythmic_model = 4
    modelName$ = "Stochastic Articulation"
    modelShort$ = "Stochastic"
else
    modelName$ = "Additive / Subtractive Rhythm"
    modelShort$ = "AddSub"
endif
if rhythmic_source = 1
    if imprint_generated_rhythm_onto_B = 0
        exitScript: "Rhythmic_source is 'Existing Sound A' and Imprint_generated_rhythm_onto_B is off." + newline$
            ... + "There is nothing to generate, and the only possible output would duplicate Sound A." + newline$
            ... + "Either choose 'Generate rhythmic composition' (rhythm only, no Sound needed)," + newline$
            ... + "or switch imprinting on to imprint Sound A onto Sound B as before."
    endif
    workflow$ = "A"
elsif imprint_generated_rhythm_onto_B
    workflow$ = "B"
else
    workflow$ = "C"
endif
# The selection is read BEFORE anything is created.
nSelSound = numberOfSelected("Sound")
nSelTable = numberOfSelected("Table")
selSnd1 = 0
selSnd2 = 0
if nSelSound >= 1
    selSnd1 = selected("Sound", 1)
endif
if nSelSound >= 2
    selSnd2 = selected("Sound", 2)
endif
selTab = 0
if nSelTable = 1
    selTab = selected("Table")
endif
if workflow$ = "A"
    if numberOfSelected("Sound") <> 2
        exitScript: "Please select exactly two Sound objects: the Gesture / Driver (A) and the Material / Source (B)."
    endif
    snd1 = selected("Sound", 1)
    snd2 = selected("Sound", 2)
    anchorTab = 0
    if numberOfSelected("Table") = 1
        anchorTab = selected("Table")
    elsif numberOfSelected("Table") > 1
        exitScript: "Select at most one Table (listener anchor pairs with columns a_time and b_time)."
    endif
    if driver_A_is = 1
        soundA = snd1
        soundB = snd2
    else
        soundA = snd2
        soundB = snd1
    endif
elsif workflow$ = "B"
    if nSelSound <> 1
        exitScript: "Generate + imprint: select exactly ONE Sound - the material B." + newline$
            ... + "The generated rhythm replaces Sound A (" + string$(nSelSound) + " Sounds are selected)."
    endif
    if nSelTable > 1
        exitScript: "Select at most one Table (listener anchor pairs with columns a_time and b_time)."
    endif
    anchorTab = selTab
    soundB = selSnd1
endif

# ---------- generation parameters (second dialog, generated mode only) ----------
procedure riGenDefaults
    composition_duration_s = 40
    base_tempo_BPM = 92
    rhythmic_complexity = 0.5
    event_density = 0.45
    duration_contrast = 0.75
    articulation = 0.78
    formal_development = 0.7
endproc
if workflow$ <> "A"
    @riGenDefaults
    # Headless/batch use: RI_GENERATION = "duration tempo complexity density
    # contrast articulation development" (seven numbers) replaces the dialog.
    genEnv$ = environment$("RI_GENERATION")
    if genEnv$ <> ""
        genEnv$ = replace_regex$(genEnv$, "^ +| +$", "", 0) + " "
        for k to 7
            sp = index(genEnv$, " ")
            genVal[k] = number(left$(genEnv$, sp - 1))
            genEnv$ = replace_regex$(mid$(genEnv$, sp + 1, length(genEnv$)), "^ +", "", 0)
        endfor
        composition_duration_s = genVal[1]
        base_tempo_BPM = genVal[2]
        rhythmic_complexity = genVal[3]
        event_density = genVal[4]
        duration_contrast = genVal[5]
        articulation = genVal[6]
        formal_development = genVal[7]
    else
        repeat
            beginPause: "Rhythmic Imprinting - generate: " + modelName$
                comment: "Onsets, durations and rests are separate. Articulation and Duration_contrast never move onsets."
                positive: "Composition_duration_s", composition_duration_s
                positive: "Base_tempo_BPM", base_tempo_BPM
                real: "Rhythmic_complexity", rhythmic_complexity
                real: "Event_density", event_density
                real: "Duration_contrast", duration_contrast
                real: "Articulation", articulation
                real: "Formal_development", formal_development
                comment: "Complexity and density are independent. Presets do not change these values."
            clicked = endPause: "Standards", "Cancel", "OK", 3, 2
            if clicked = 1
                @riGenDefaults
            endif
        until clicked = 3
    endif
    genWarn$ = ""
    if composition_duration_s < 5 or composition_duration_s > 600
        composition_duration_s = max(5, min(600, composition_duration_s))
        genWarn$ = genWarn$ + "  ! Composition_duration_s limited to 5..600 s" + newline$
    endif
    if base_tempo_BPM < 30 or base_tempo_BPM > 240
        base_tempo_BPM = max(30, min(240, base_tempo_BPM))
        genWarn$ = genWarn$ + "  ! Base_tempo_BPM limited to 30..240" + newline$
    endif
    rhythmic_complexity = max(0, min(1, rhythmic_complexity))
    event_density = max(0, min(1, event_density))
    duration_contrast = max(0, min(1, duration_contrast))
    formal_development = max(0, min(1, formal_development))
    if articulation < 0.2 or articulation > 0.98
        articulation = max(0.2, min(0.98, articulation))
        genWarn$ = genWarn$ + "  ! Articulation limited to 0.20..0.98 -> " + fixed$(articulation, 2) + newline$
    endif
    @riGenerate
    genName$ = "RI_Rhythm_" + modelShort$ + "_Seed" + string$(random_seed)
    @riSynth: genName$
    genSound = riSynth.snd
    selectObject: genSound
    genPeak = Get absolute extremum: 0, 0, "None"
    genSched = 0
    if export_diagnostic_data
        @riScheduleTable: "RI_schedule_" + modelShort$ + "_Seed" + string$(random_seed)
        genSched = riScheduleTable.tab
    endif
endif

# ---------- Workflow C: generated rhythm only (no Python, no files) ----------
if workflow$ = "C"
    clearinfo
    writeInfoLine: "=== Rhythmic Imprinting v1.4 - generated rhythm only ==="
    appendInfoLine: "Imprinting: OFF (no Sound B used, no Python, no CNN, no files written)"
    if nSelSound > 0
        appendInfoLine: "Note: the ", nSelSound, " selected Sound(s) were not used in this workflow."
    endif
    @riGenReport
    appendInfoLine: "Peak ", fixed$(20 * log10(max(1e-12, genPeak)), 1), " dBFS (no clipping; fixed gain, nothing normalised)"
    if genWarn$ <> ""
        appendInfo: genWarn$
    endif
    appendInfoLine: "Output: ", genName$, if genSched then " + schedule Table" else "" fi
    Erase all
    Line width: 1
    Solid line
    @riFormFigure: 0, 1, genSound
    Select outer viewport: 0, 8, 0, riFormFigure.bottom
    Font size: 10
    selectObject: genSound
    if play_result
        Play
    endif
    exitScript ()
endif

if workflow$ = "B"
    soundA = genSound
endif
selectObject: soundA
nameA$ = selected$("Sound")
durA = Get total duration
xminA = Get start time
srA = Get sampling frequency
nChA = Get number of channels
peakA = Get absolute extremum: 0, 0, "None"
rmsA = Get root-mean-square: 0, 0
selectObject: soundB
nameB$ = selected$("Sound")
durB = Get total duration
xminB = Get start time
srB = Get sampling frequency
nChB = Get number of channels
nSampB = Get number of samples
peakB = Get absolute extremum: 0, 0, "None"
rmsB = Get root-mean-square: 0, 0

# ============================================================
# RHYTHMIC COMPOSITION GENERATOR (v1.4) - pure Praat, no Python
# ============================================================
# Event schedule (one entry per note):
#   evOn  onset (s)              - set ONLY by the model (values + rests)
#   evVal notated value (s)      - room the note owns before the next event
#   evLc  length class 0..1      - the model's short/long marking
#   evAcc accent 0..1
#   evSec section index          - secName$[], secT[]
#   evDur sounding duration (s)  - computed AFTERWARDS from Articulation and
#                                  Duration_contrast as a fraction of evVal.
# Onsets never depend on Articulation / Duration_contrast, and a sounding
# duration can never reach the next onset (no clipping, no overlap).
# Randomness: own Park-Miller generator seeded by Random_seed + model, so the
# result is identical on every Praat version.

procedure riRnd
    rngState = (16807 * rngState) mod 2147483647
    .x = rngState / 2147483647
endproc

procedure riGauss
    @riRnd
    .u1 = max(1e-12, riRnd.x)
    @riRnd
    .u2 = riRnd.x
    .x = sqrt(-2 * ln(.u1)) * cos(2 * pi * .u2)
endproc

procedure riSec: .name$
    nSec += 1
    secName$[nSec] = .name$
    secT[nSec] = genT
endproc

procedure riEv: .val, .lc, .acc
    nEv += 1
    evOn[nEv] = genT
    evVal[nEv] = .val
    evLc[nEv] = max(0, min(1, .lc))
    evAcc[nEv] = max(0, min(1, .acc))
    evSec[nEv] = nSec
    genT += .val
endproc

procedure riRest: .t
    if .t > 0
        genT += .t
    endif
endproc

# ---------- working cell (values in ticks) ----------
procedure riPlayCell: .scale, .accAdd
    for .i to wN
        @riEv: wV[.i] * tick * .scale, wL[.i], wA[.i] + .accAdd
    endfor
endproc

procedure riCellLen
    .t = 0
    for .i to wN
        .t += wV[.i]
    endfor
endproc

procedure riInsert: .pos, .v, .l, .a
    .j = wN
    while .j >= .pos
        wV[.j + 1] = wV[.j]
        wL[.j + 1] = wL[.j]
        wA[.j + 1] = wA[.j]
        .j -= 1
    endwhile
    wN += 1
    wV[.pos] = .v
    wL[.pos] = .l
    wA[.pos] = .a
endproc

procedure riDelete: .pos
    for .j from .pos to wN - 1
        wV[.j] = wV[.j + 1]
        wL[.j] = wL[.j + 1]
        wA[.j] = wA[.j + 1]
    endfor
    wN -= 1
endproc

# ---------- Model 1: Motivic Development ----------
# PROVISIONAL MOTIF: Rhythmic_Form_POC.praat was not available when v1.4 was
# written. This seven-event motif (values in sixteenths 3 1 2 2 1 1 2 + rest,
# long-short-short-medium-short-short-long) is a stand-in with the POC's
# five-part form; replace it with the POC motif when supplied.
procedure riMotif
    wN = 7
    wV[1] = 3
    wV[2] = 1
    wV[3] = 2
    wV[4] = 2
    wV[5] = 1
    wV[6] = 1
    wV[7] = 2
    wL[1] = 1
    wL[2] = 0
    wL[3] = 0.5
    wL[4] = 0.5
    wL[5] = 0
    wL[6] = 0
    wL[7] = 1
    wA[1] = 1
    wA[2] = 0.35
    wA[3] = 0.6
    wA[4] = 0.75
    wA[5] = 0.4
    wA[6] = 0.45
    wA[7] = 0.85
endproc

procedure riVaryCell
    @riRnd
    .r = riRnd.x
    @riRnd
    .j = min(wN, 2 + floor(riRnd.x * (wN - 1)))
    @riRnd
    .r2 = riRnd.x
    if .r < 0.22
        # augmentation of one value
        wV[.j] = wV[.j] * 2
        wL[.j] = min(1, wL[.j] + 0.5)
    elsif .r < 0.40 and .j < wN
        # exchange two neighbouring values (the head stays)
        .v = wV[.j]
        .l = wL[.j]
        wV[.j] = wV[.j + 1]
        wL[.j] = wL[.j + 1]
        wV[.j + 1] = .v
        wL[.j + 1] = .l
    elsif .r < 0.55 and wN >= 6
        # fragmentation: drop the last two events, the new last one is long
        wN -= 2
        wV[wN] = wV[wN] + 2
        wL[wN] = 1
        wA[wN] = max(wA[wN], 0.8)
    elsif .r2 < rhythmic_complexity
        if wV[.j - 1] >= 2
            # syncopation: event j starts one sixteenth earlier
            wV[.j - 1] -= 1
            wV[.j] += 1
            wA[.j] = min(1, wA[.j] + 0.3)
        elsif rhythmic_complexity > 0.6 and wV[.j] = 2
            # triplet: one eighth becomes three equal values
            wV[.j] = 2 / 3
            @riInsert: .j + 1, 2 / 3, 0, 0.4
            @riInsert: .j + 1, 2 / 3, 0, 0.4
        elsif wV[.j] >= 2
            wV[.j] -= 1
            @riInsert: .j + 1, 1, 0, 0.4
        endif
    else
        if wV[.j] >= 2
            wV[.j] -= 1
            @riInsert: .j + 1, 1, 0, 0.35
        else
            wV[.j] += 1
            wL[.j] = min(1, wL[.j] + 0.3)
        endif
    endif
endproc

procedure riModelMotivic
    .motifLen = 12
    .restBase = 4 + round((1 - event_density) * 8)
    @riSec: "Statement"
    .end = genT + compDur * 0.18
    .c = 0
    while .c < 2 or genT + (.motifLen + .restBase) * tick <= .end
        @riMotif
        @riPlayCell: 1, 0
        @riRest: .restBase * tick
        .c += 1
    endwhile
    @riSec: "Variation"
    .end = genT + compDur * 0.24
    .c = 0
    while .c < 1 or genT + (.motifLen + .restBase) * tick <= .end
        @riMotif
        .nOps = 1 + round(formal_development * 2)
        for .op to .nOps
            @riVaryCell
        endfor
        @riPlayCell: 1, 0
        .r = .restBase
        @riRnd
        if riRnd.x < rhythmic_complexity
            @riRnd
            .r = max(1, .restBase + (if riRnd.x < 0.5 then -2 else 3 fi))
        endif
        @riRest: .r * tick
        .c += 1
    endwhile
    @riSec: "Compression"
    .start = genT
    .len = compDur * 0.22
    .end = .start + .len
    .c = 0
    while .c < 2 or genT < .end - 0.5 * .motifLen * tick
        .p = min(1, (genT - .start) / .len)
        .scale = 1 - 0.5 * formal_development * .p
        @riMotif
        if .p > 0.5 and formal_development > 0.3
            # head of the motif and a long ending
            wN = 5
            wV[5] = 2
            wL[5] = 1
        endif
        @riPlayCell: .scale, 0.2 * .p * formal_development
        @riRest: round(.restBase * (1 - .p * (0.3 + 0.7 * formal_development))) * tick * .scale
        .c += 1
    endwhile
    @riSec: "Climax"
    .end = genT + compDur * 0.12
    .scale = 1 - 0.5 * formal_development
    .g = 0
    while .g < 2 or genT + 6 * tick * .scale <= .end
        .shift = rhythmic_complexity > 0.4 and .g mod 3 = 2
        @riEv: 3 * tick * .scale, 0.7, if .shift then 0.6 else 1 fi
        @riEv: 1 * tick * .scale, 0, if .shift then 1 else 0.5 fi
        @riEv: 2 * tick * .scale, 0.4, 0.65
        .g += 1
    endwhile
    @riEv: 6 * tick, 1, 1
    @riSec: "Caesura"
    @riRest: (8 + 16 * formal_development) * tick
    @riSec: "Return"
    for .c to 2
        @riMotif
        @riPlayCell: 1, 0
        @riRest: .restBase * tick
    endfor
    @riEv: 8 * tick, 1, 0.8
endproc

# ---------- Model 2: Euclidean Evolution ----------
procedure riEuclidCycle: .k, .n, .rot, .accK
    .nP = 0
    for .i from 0 to .n - 1
        .j = (.i + .rot) mod .n
        if floor(.j * .k / .n) <> floor((.j - 1) * .k / .n)
            .nP += 1
            .pos[.nP] = .i
        endif
    endfor
    if .pos[1] > 0
        @riRest: .pos[1] * tick
    endif
    for .q to .nP
        .nxt = if .q < .nP then .pos[.q + 1] else .n fi
        .gap = .nxt - .pos[.q]
        .v = min(.gap, 3)
        .isAcc = floor((.q - 1) * .accK / .nP) <> floor((.q - 2) * .accK / .nP)
        @riEv: .v * tick, (.v - 1) / 2, 0.45 + 0.4 * .isAcc + (if .q = 1 then 0.1 else 0 fi)
        @riRest: (.gap - .v) * tick
    endfor
endproc

procedure riModelEuclid
    .n0 = if rhythmic_complexity < 0.5 then 16 else 12 fi
    .k0 = max(3, min(.n0 - 1, round(.n0 * (0.2 + 0.45 * event_density))))
    .acc0 = max(1, round(.k0 / 3))
    .n1 = .n0 - 2 * round(formal_development * 3)
    if rhythmic_complexity > 0.7
        .n1 -= 1
    endif
    .n1 = max(.k0 + 1, .n1)
    @riSec: "Pattern"
    .end = genT + compDur * 0.20
    .c = 0
    while .c < 2 or genT + .n0 * tick <= .end
        @riEuclidCycle: .k0, .n0, 0, .acc0
        .c += 1
    endwhile
    @riSec: "Rotation"
    .end = genT + compDur * 0.20
    .rot = 0
    .step = if formal_development < 0.15 then 0 else 1 + (rhythmic_complexity > 0.5) fi
    .c = 0
    while .c < 2 or genT + .n0 * tick <= .end
        if .c mod 2 = 0
            .rot = (.rot + .step) mod .n0
        endif
        @riEuclidCycle: .k0, .n0, .rot, .acc0
        .c += 1
    endwhile
    @riSec: "Regrouping"
    .start = genT
    .len = compDur * 0.25
    .c = 0
    while .c < 2 or genT < .start + .len - .n0 * tick * 0.5
        .p = min(1, (genT - .start) / .len)
        .n = round(.n0 + (.n1 - .n0) * min(1, 2 * .p))
        .k = .k0
        if rhythmic_complexity > 0.3 and .c mod 2 = 1
            .k = .k0 + 1
        endif
        .k = max(2, min(.k, .n - 1))
        @riEuclidCycle: .k, .n, 0, max(1, round(.k / 2))
        .c += 1
    endwhile
    @riSec: "Redistribution"
    .start = genT
    .len = compDur * 0.20
    .c = 0
    while .c < 2 or genT < .start + .len - .n0 * tick * 0.5
        .p = min(1, (genT - .start) / .len)
        .n = round(.n1 + (.n0 - .n1) * .p)
        .k = round(.k0 + formal_development * .n0 * 0.25 * sin(pi * .p))
        .k = max(2, min(.k, .n - 1))
        @riEuclidCycle: .k, .n, round(.p * 3), max(1, round(.k * (0.25 + 0.5 * .p)))
        .c += 1
    endwhile
    @riRest: (.n0 / 2) * tick
    @riSec: "Recurrence"
    .end = genT + compDur * 0.15
    .c = 0
    while .c < 2 or genT + .n0 * tick <= .end
        @riEuclidCycle: .k0, .n0, 0, .acc0
        .c += 1
    endwhile
    @riEv: 6 * tick, 1, 0.9
endproc

# ---------- Model 3: Acceleration / Deceleration ----------
procedure riRun: .len, .ioi1, .ioi2, .lc1, .lc2, .acc1, .acc2
    .start = genT
    .end = genT + .len
    .cnt = 0
    .grp = 4
    while genT < .end
        .p = min(1, (genT - .start) / .len)
        .ioi = .ioi1 * (.ioi2 / .ioi1) ^ .p
        .acc = .acc1 + (.acc2 - .acc1) * .p
        @riEv: .ioi, .lc1 + (.lc2 - .lc1) * .p, if .cnt = 0 then .acc + 0.35 else .acc fi
        .cnt += 1
        if .cnt >= .grp
            .cnt = 0
            .grp = 4
            if rhythmic_complexity > 0
                @riRnd
                if riRnd.x < rhythmic_complexity
                    @riRnd
                    .grp = 3 + 2 * floor(riRnd.x * 3)
                endif
                @riRnd
                if riRnd.x < 0.5 * rhythmic_complexity
                    @riRnd
                    @riRest: .ioi * (1 + riRnd.x)
                endif
            endif
        endif
    endwhile
endproc

procedure riModelAccel
    .ioi0 = beat * (1.25 - 0.85 * event_density)
    .ioiMin = .ioi0 * (1 - 0.78 * formal_development)
    .ioiMax = .ioi0 * (1 + 1.3 * formal_development)
    @riSec: "Pulse"
    @riRun: compDur * 0.18, .ioi0, .ioi0, 0.5, 0.5, 0.45, 0.45
    @riSec: "Acceleration"
    @riRun: compDur * 0.27, .ioi0, .ioiMin, 0.45, 0.1, 0.45, 0.55
    @riSec: "Interruption"
    .start = genT
    @riRest: 2 * .ioi0
    @riEv: 0.3 * .ioi0, 0, 1
    @riRest: 1.2 * .ioi0
    @riEv: 0.3 * .ioi0, 0, 0.9
    @riRest: 0.4 * .ioi0
    @riEv: 0.6 * .ioi0, 0.3, 1
    @riRest: max(1.5 * .ioi0, .start + compDur * 0.10 - genT)
    @riSec: "Deceleration"
    @riRun: compDur * 0.27, .ioiMin, .ioiMax, 0.1, 1, 0.55, 0.4
    @riSec: "Return"
    @riRun: compDur * 0.18, .ioi0, .ioi0, 0.5, 0.5, 0.45, 0.45
    @riEv: 2.5 * .ioi0, 1, 0.8
endproc

# ---------- Model 4: Stochastic Articulation ----------
procedure riStoch: .len, .ioiMul, .sig, .restP, .restMul, .lcM, .lcS, .accM, .accS, .burstP, .bimP
    .end = genT + .len
    .burst = 0
    .after = 0
    while genT < .end
        if .burst > 0
            .ioi = stochM * 0.22
            .burst -= 1
            .after = .burst = 0
        else
            @riRnd
            if riRnd.x < .burstP
                @riRnd
                .burst = 2 + floor(riRnd.x * 5)
                .ioi = stochM * 0.22
            else
                @riGauss
                .ioi = stochM * .ioiMul * exp(.sig * riGauss.x)
                @riRnd
                if riRnd.x < .bimP
                    @riRnd
                    .ioi = stochM * (if riRnd.x < 0.5 then 0.28 else 1.9 fi) * exp(0.3 * .sig * riGauss.x)
                endif
            endif
        endif
        if rhythmic_complexity < 0.5
            .ioi = tick * max(1, round(.ioi / tick))
        endif
        .ioi = max(0.06, min(4 * beat, .ioi))
        @riRnd
        .lc = .lcM + .lcS * (2 * riRnd.x - 1)
        @riRnd
        .acc = .accM + .accS * (2 * riRnd.x - 1)
        @riEv: .ioi, .lc, .acc
        @riRnd
        if riRnd.x < .restP
            @riRnd
            @riRest: stochM * .restMul * (0.5 + riRnd.x)
        endif
        if .after
            @riRest: stochM * 2.6
            .after = 0
        endif
    endwhile
endproc

procedure riModelStoch
    stochM = beat * (1.3 - 0.9 * event_density)
    .s0 = 0.2 + 0.5 * rhythmic_complexity
    .f = formal_development
    @riSec: "Sparse"
    @riStoch: compDur * 0.2, 1, .s0, 0.12, 1.5, 0.5, 0.25, 0.55, 0.15, 0, 0
    @riSec: "Clusters"
    @riStoch: compDur * 0.2, 1, .s0, 0.12 + .f * (0.05 - 0.12), 1.5 + .f * (1 - 1.5), 0.5 + .f * (0.15 - 0.5), 0.25 + .f * (0.1 - 0.25), 0.55 + .f * (0.65 - 0.55), 0.15 + .f * (0.2 - 0.15), 0.6 * .f, 0
    @riSec: "Drift"
    @riStoch: compDur * 0.2, 1 + .f * (0.55 - 1), .s0 * (1 - 0.8 * .f), 0.12 + .f * (0.02 - 0.12), 1.5 + .f * (1 - 1.5), 0.5 + .f * (0.9 - 0.5), 0.25 + .f * (0.08 - 0.25), 0.55 + .f * (0.45 - 0.55), 0.15 + .f * (0.08 - 0.15), 0, 0
    @riSec: "Fracture"
    @riStoch: compDur * 0.2, 1, .s0, 0.12 + .f * (0.3 - 0.12), 1.5 + .f * (2.5 - 1.5), 0.5 + .f * (0.4 - 0.5), 0.25 + .f * (0.45 - 0.25), 0.55 + .f * (0.7 - 0.55), 0.15 + .f * (0.3 - 0.15), 0, 0.6 * .f
    @riSec: "Return"
    @riStoch: compDur * 0.2, 1, .s0, 0.12, 1.5, 0.5, 0.25, 0.55, 0.15, 0, 0
    @riEv: 2 * stochM, 1, 0.8
endproc

# ---------- Model 5: Additive / Subtractive Rhythm ----------
procedure riCell0
    wN = 3
    wV[1] = 2
    wV[2] = 1
    wV[3] = 1
    wL[1] = 1
    wL[2] = 0
    wL[3] = 0
    wA[1] = 1
    wA[2] = 0.5
    wA[3] = 0.6
endproc

procedure riModelAdditive
    .rest = round(1 + (1 - event_density) * 5)
    .nSteps = 2 + round(formal_development * 7)
    @riSec: "Cell"
    .end = genT + compDur * 0.15
    @riCell0
    .c = 0
    while .c < 3 or genT + (4 + .rest) * tick <= .end
        @riPlayCell: 1, 0
        @riRest: .rest * tick
        .c += 1
    endwhile
    @riSec: "Addition"
    .budget = compDur * 0.40
    .start = genT
    for .s to .nSteps
        @riRnd
        if riRnd.x < 0.5 + 0.3 * rhythmic_complexity
            # add an event (one sixteenth)
            if rhythmic_complexity < 0.5
                .pos = wN + 1
            else
                @riRnd
                .pos = 2 + floor(riRnd.x * wN)
            endif
            @riInsert: .pos, 1, 0, 0.45
        else
            # add a duration unit to an existing event
            if rhythmic_complexity < 0.5
                .pos = 1 + ((.s - 1) mod wN)
            else
                @riRnd
                .pos = 1 + floor(riRnd.x * wN)
            endif
            wV[.pos] += 1
            wL[.pos] = min(1, (wV[.pos] - 1) / 3)
        endif
        @riCellLen
        .left = .budget - (genT - .start)
        .reps = max(1, floor(.left / ((.nSteps - .s + 1) * (riCellLen.t + .rest) * tick)))
        for .r to .reps
            @riPlayCell: 1, 0
            @riRest: .rest * tick
        endfor
    endfor
    @riSec: "Subtraction"
    .budget = compDur * 0.30
    .start = genT
    @riCellLen
    while wN <> 3 or riCellLen.t <> 4
        if wN > 3
            # remove the weakest event after the head
            .best = 2
            for .i from 3 to wN
                if wA[.i] < wA[.best] or (wA[.i] = wA[.best] and wV[.i] <= wV[.best])
                    .best = .i
                endif
            endfor
            @riDelete: .best
        elsif riCellLen.t > 4
            .best = 1
            for .i from 2 to wN
                if wV[.i] >= wV[.best]
                    .best = .i
                endif
            endfor
            wV[.best] -= 1
            wL[.best] = min(1, (wV[.best] - 1) / 3)
        else
            wV[1] += 4 - riCellLen.t
        endif
        @riCellLen
        .stepsLeft = max(1, (wN - 3) + abs(riCellLen.t - 4))
        .left = .budget - (genT - .start)
        .reps = max(1, floor(.left / (.stepsLeft * (riCellLen.t + .rest) * tick)))
        for .r to .reps
            @riPlayCell: 1, 0
            @riRest: .rest * tick
        endfor
    endwhile
    @riSec: "Return"
    @riCell0
    for .c to 3
        @riPlayCell: 1, 0
        @riRest: .rest * tick
    endfor
    @riEv: 6 * tick, 1, 0.85
endproc

# ---------- durations: Articulation x Duration_contrast, onsets untouched ----------
procedure riDurations
    .gap = 0.004
    genClamped = 0
    for .i to nEv
        .d = evLc[.i] - 0.5
        .f = articulation + 2 * duration_contrast * .d * (if .d > 0 then 0.98 - articulation else articulation - 0.12 fi)
        if .f < 0.12 or .f > 0.98
            genClamped += 1
        endif
        .f = max(0.12, min(0.98, .f))
        .dur = evVal[.i] * .f
        .dur = max(.dur, min(0.02, evVal[.i] - .gap))
        evDur[.i] = min(.dur, evVal[.i] - .gap)
    endfor
endproc

# ---------- synthesis: 330 Hz + second harmonic, click-safe envelope ----------
procedure riSynth: .name$
    .total = genT + 0.5
    .snd = Create Sound from formula: .name$, 1, 0, .total, 44100, "0"
    for .i to nEv
        .on$ = fixed$(evOn[.i], 6)
        .end$ = fixed$(evOn[.i] + evDur[.i], 6)
        .att$ = fixed$(min(0.005, evDur[.i] / 4), 6)
        .rel$ = fixed$(min(0.03, evDur[.i] * 0.35), 6)
        .amp$ = fixed$(0.70 * (0.35 + 0.65 * evAcc[.i]), 5)
        Formula (part): evOn[.i], evOn[.i] + evDur[.i], 1, 1,
            ... "self + " + .amp$ + " * (if x - " + .on$ + " < " + .att$ + " then 0.5 - 0.5 * cos(pi * (x - " + .on$ + ") / " + .att$ + ") else 1 fi)"
            ... + " * (if " + .end$ + " - x < " + .rel$ + " then 0.5 - 0.5 * cos(pi * max(0, " + .end$ + " - x) / " + .rel$ + ") else 1 fi)"
            ... + " * exp(-(x - " + .on$ + ") / 2.5) * (sin(2 * pi * 330 * (x - " + .on$ + ")) + 0.22 * sin(2 * pi * 660 * (x - " + .on$ + ")))"
    endfor
    selectObject: .snd
endproc

procedure riMedian: .which$
    .tab = Create Table with column names: "ri_median", 1, "x"
    .n = 0
    for .i to nEv
        if .which$ = "ioi"
            if .i < nEv
                .n += 1
                if .n > 1
                    Append row
                endif
                Set numeric value: .n, "x", evOn[.i + 1] - evOn[.i]
            endif
        else
            .n += 1
            if .n > 1
                Append row
            endif
            Set numeric value: .n, "x", evDur[.i]
        endif
    endfor
    .mean = Get mean: "x"
    Sort rows: "x"
    if .n mod 2 = 1
        .med = Get value: (.n + 1) / 2, "x"
    else
        .m1 = Get value: .n / 2, "x"
        .m2 = Get value: .n / 2 + 1, "x"
        .med = (.m1 + .m2) / 2
    endif
    removeObject: .tab
endproc

procedure riGenerate
    tick = 60 / base_tempo_BPM / 4
    beat = 60 / base_tempo_BPM
    compDur = composition_duration_s
    rngState = ((random_seed * 7919 + rhythmic_model * 104729) mod 2147483646 + 2147483646) mod 2147483646 + 1
    nEv = 0
    nSec = 0
    genT = 0.15
    if rhythmic_model = 1
        @riModelMotivic
    elsif rhythmic_model = 2
        @riModelEuclid
    elsif rhythmic_model = 3
        @riModelAccel
    elsif rhythmic_model = 4
        @riModelStoch
    else
        @riModelAdditive
    endif
    @riDurations
    # statistics
    genOverlaps = 0
    genLongestRest = 0
    genLongestRestAt = 0
    genSounding = 0
    for .i to nEv
        genSounding += evDur[.i]
        if .i < nEv
            if evOn[.i] + evDur[.i] > evOn[.i + 1] + 1e-9
                genOverlaps += 1
            endif
            .r = evOn[.i + 1] - evOn[.i] - evDur[.i]
            if .r > genLongestRest
                genLongestRest = .r
                genLongestRestAt = evOn[.i] + evDur[.i]
            endif
        endif
    endfor
    genSpan = evOn[nEv] + evDur[nEv] - evOn[1]
    genRatio = genSounding / genSpan
endproc

procedure riScheduleTable: .name$
    .tab = Create Table with column names: .name$, nEv, "event onset_s dur_s value_s ioi_s accent length_class section section_name model"
    for .i to nEv
        Set numeric value: .i, "event", .i
        Set numeric value: .i, "onset_s", evOn[.i]
        Set numeric value: .i, "dur_s", evDur[.i]
        Set numeric value: .i, "value_s", evVal[.i]
        Set numeric value: .i, "ioi_s", if .i < nEv then evOn[.i + 1] - evOn[.i] else evVal[.i] fi
        Set numeric value: .i, "accent", evAcc[.i]
        Set numeric value: .i, "length_class", evLc[.i]
        Set numeric value: .i, "section", evSec[.i]
        Set string value: .i, "section_name", secName$[evSec[.i]]
        Set string value: .i, "model", modelShort$
    endfor
endproc

procedure riGenReport
    appendInfoLine: "--- generated rhythmic composition ---"
    appendInfoLine: "Model: ", modelName$, if rhythmic_model = 1 then " (PROVISIONAL motif - Rhythmic_Form_POC.praat not yet integrated)" else "" fi
    appendInfoLine: "Seed ", random_seed, " | duration target ", fixed$(composition_duration_s, 1), " s | tempo ", fixed$(base_tempo_BPM, 1), " BPM | complexity ", fixed$(rhythmic_complexity, 2),
        ... " | density ", fixed$(event_density, 2), " | duration contrast ", fixed$(duration_contrast, 2), " | articulation ", fixed$(articulation, 2), " | formal development ", fixed$(formal_development, 2)
    appendInfoLine: "Scheduled events: ", nEv, " | Sound ", fixed$(genT + 0.5, 2), " s, 44100 Hz mono, 330 Hz + 2nd harmonic"
    .s$ = ""
    for .k to nSec
        .s$ = .s$ + secName$[.k] + " " + fixed$(secT[.k], 2) + (if .k < nSec then " | " else "" fi)
    endfor
    appendInfoLine: "Sections (start s): ", .s$, " | end ", fixed$(genT, 2)
    @riMedian: "ioi"
    appendInfoLine: "Inter-onset interval: mean ", fixed$(riMedian.mean, 3), " s, median ", fixed$(riMedian.med, 3), " s"
    @riMedian: "dur"
    appendInfoLine: "Sounding duration: mean ", fixed$(riMedian.mean, 3), " s, median ", fixed$(riMedian.med, 3), " s"
    appendInfoLine: "Articulation ", fixed$(articulation, 2), " -> sounding-time ratio ", fixed$(genRatio, 3), " | longest silence ", fixed$(genLongestRest, 2), " s (at ", fixed$(genLongestRestAt, 2), " s)"
    appendInfoLine: "Duration checks: overlaps ", genOverlaps, " | notes at the 0.12/0.98 fraction limit ", genClamped, " (durations are fractions of each notated value, never clipped by the next onset)"
endproc

# ============================================================
# PARAMETER CHECKS
# ============================================================
warnLines$ = ""
if durA < 0.3 or durB < 0.3
    exitScript: "Both Sounds must be at least 0.3 s long (A " + fixed$(durA, 3) + " s, B " + fixed$(durB, 3) + " s)."
endif
if srA < 8000 or srB < 8000
    exitScript: "Both Sounds need a sampling frequency of at least 8000 Hz."
endif
if peakA < 1e-5 or peakB < 1e-5
    exitScript: "Sound " + (if peakA < 1e-5 then "A (" + nameA$ + ")" else "B (" + nameB$ + ")" fi) + " is silent."
endif
if abs(durA - durB) < 1e-9 and srA = srB and abs(rmsA - rmsB) < 1e-12
    warnLines$ = warnLines$ + "  ! A and B look identical (same duration, rate and RMS): the result will be B re-ordered by itself." + newline$
endif
if srA <> srB
    warnLines$ = warnLines$ + "  - Sampling rates differ (A " + string$(srA) + " Hz, B " + string$(srB) + " Hz): fine, A is only analysed; the output uses B's rate." + newline$
endif
if segmentation_sensitivity < 0 or segmentation_sensitivity > 1
    segmentation_sensitivity = max(0, min(1, segmentation_sensitivity))
    warnLines$ = warnLines$ + "  ! Segmentation_sensitivity limited to 0..1 -> " + fixed$(segmentation_sensitivity, 2) + newline$
endif
if minimum_gesture_duration_s < 0.03
    minimum_gesture_duration_s = 0.03
    warnLines$ = warnLines$ + "  ! Minimum_gesture_duration_s raised to 0.03 s" + newline$
endif
if maximum_gesture_duration_s < 2 * minimum_gesture_duration_s
    maximum_gesture_duration_s = 2 * minimum_gesture_duration_s
    warnLines$ = warnLines$ + "  ! Maximum_gesture_duration_s raised to twice the minimum: " + fixed$(maximum_gesture_duration_s, 2) + " s" + newline$
endif
if morphological_similarity < 0 or morphological_similarity > 1
    morphological_similarity = max(0, min(1, morphological_similarity))
    warnLines$ = warnLines$ + "  ! Morphological_similarity limited to 0..1 -> " + fixed$(morphological_similarity, 2) + newline$
endif
if continuity_vs_contrast < 0 or continuity_vs_contrast > 1
    continuity_vs_contrast = max(0, min(1, continuity_vs_contrast))
    warnLines$ = warnLines$ + "  ! Continuity_vs_contrast limited to 0..1 -> " + fixed$(continuity_vs_contrast, 2) + newline$
endif
if duration_flexibility < 0 or duration_flexibility > 1
    duration_flexibility = max(0, min(1, duration_flexibility))
    warnLines$ = warnLines$ + "  ! Duration_flexibility limited to 0..1 -> " + fixed$(duration_flexibility, 2) + newline$
endif
if crossfade_ms < 0 or crossfade_ms > 200
    crossfade_ms = max(0, min(200, crossfade_ms))
    warnLines$ = warnLines$ + "  ! Crossfade_ms limited to 0..200 -> " + fixed$(crossfade_ms, 1) + newline$
endif
if crossfade_ms < 2
    warnLines$ = warnLines$ + "  ! Crossfade below 2 ms: cuts inside sounding material may click." + newline$
endif
if matching_method = 1
    method$ = "acoustic"
elsif matching_method = 2
    method$ = "cnn"
elsif matching_method = 3
    method$ = "hybrid"
else
    method$ = "compare"
endif
mode$ = if compositional_mode = 1 then "following" else "dialogue" fi

clearinfo
writeInfoLine: "=== Rhythmic Imprinting v1.4 ==="
if workflow$ = "B"
    appendInfoLine: "Workflow B: generated rhythm -> recorded sound (Driver_A_is is not used)"
    @riGenReport
    if genWarn$ <> ""
        appendInfo: genWarn$
    endif
    appendInfoLine: ""
endif
appendInfoLine: "A  Gesture / Driver : ", nameA$, "  (", fixed$(durA, 2), " s, ", srA, " Hz, ", nChA, " ch)"
appendInfoLine: "B  Material / Source: ", nameB$, "  (", fixed$(durB, 2), " s, ", srB, " Hz, ", nChB, " ch)"
appendInfoLine: "Rhythmic Imprinting: A's onset/gesture pattern reorganises B's recorded sound."
appendInfoLine: "Swap Driver A to reverse the direction (and the resulting sonic material)."
appendInfoLine: "Preset: ", presetName$, if preset = 1 then " (manual controls applied)" else " (overrides matching/mode/numeric fields)" fi
appendInfoLine: "Method ", method$, " | mode ", mode$, " | seed ", random_seed
appendInfoLine: "Effective settings: sensitivity ", fixed$(segmentation_sensitivity, 2), " | gesture ", fixed$(minimum_gesture_duration_s, 3), "-", fixed$(maximum_gesture_duration_s, 2), " s"
appendInfoLine: "Morph ", fixed$(morphological_similarity, 2), " | contrast ", fixed$(continuity_vs_contrast, 2), " | flexibility ", fixed$(duration_flexibility, 2), " | fade ", fixed$(crossfade_ms, 1), " ms | avoid repeats ", avoid_repetition

# ============================================================
# PRAAT 7 TRUST (this script writes, runs and deletes files)
# ============================================================
if praatVersion >= 7000
    trustGranted = askForTrust()
    if trustGranted = 0
        exitScript: "Rhythmic Imprinting needs permission to write temporary files and run Python."
    endif
endif

# ============================================================
# PATHS
# ============================================================
pluginDir$ = replace_regex$(preferencesDirectory$ + "/plugin_AudioTools/", "\\", "/", 0)
pythonScript$ = pluginDir$ + "py/rhythmic_imprinting.py"
if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/rhythmic_imprinting.py"
endif
if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/../py/rhythmic_imprinting.py"
endif
# Backward-compatible lookup for an installation with the old engine name.
if not fileReadable(pythonScript$)
    pythonScript$ = pluginDir$ + "py/joint_gestural_representation_learning.py"
endif
if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/joint_gestural_representation_learning.py"
endif
if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/../py/joint_gestural_representation_learning.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find the Python engine rhythmic_imprinting.py" + newline$
        ... + "Place rhythmic_imprinting.py in: " + pluginDir$ + "py/ (or next to the Praat script)."
endif
pythonScriptJ$ = replace_regex$(pythonScript$, "\\", "/", 0)

# Per-run unique names in Praat's temporary folder; every file is removed at the end.
token$ = string$(randomInteger(100000, 999999))
tmpPrefix$ = replace_regex$(temporaryDirectory$ + "/ri_" + token$ + "_", "\\", "/", 0)
wavA$ = tmpPrefix$ + "a.wav"
wavB$ = tmpPrefix$ + "b.wav"
cfg$ = tmpPrefix$ + "config.json"
logF$ = tmpPrefix$ + "log.txt"
errF$ = tmpPrefix$ + "stderr.txt"
statusF$ = tmpPrefix$ + "status.txt"
reportF$ = tmpPrefix$ + "report.txt"
statsF$ = tmpPrefix$ + "stats.txt"
evAF$ = tmpPrefix$ + "events_a.tsv"
evBF$ = tmpPrefix$ + "events_b.tsv"
schedF$ = tmpPrefix$ + "schedule_a.tsv"
planPrefix$ = tmpPrefix$ + "plan_"
probePy$ = tmpPrefix$ + "probe.py"
anchorF$ = tmpPrefix$ + "anchors.tsv"
cacheDir$ = replace_regex$(preferencesDirectory$ + "/ri_cache", "\\", "/", 0)
probeOk$ = tmpPrefix$ + "probe.ok"

procedure riCleanUp
    if fileReadable(schedF$)
        deleteFile: schedF$
    endif
    for .k to 15
        if .k = 1
            .f$ = wavA$
        elsif .k = 2
            .f$ = wavB$
        elsif .k = 3
            .f$ = cfg$
        elsif .k = 4
            .f$ = logF$
        elsif .k = 5
            .f$ = errF$
        elsif .k = 6
            .f$ = statusF$
        elsif .k = 7
            .f$ = reportF$
        elsif .k = 8
            .f$ = statsF$
        elsif .k = 9
            .f$ = evAF$
        elsif .k = 10
            .f$ = evBF$
        elsif .k = 11
            .f$ = planPrefix$ + "acoustic.tsv"
        elsif .k = 12
            .f$ = planPrefix$ + "cnn.tsv"
        elsif .k = 13
            .f$ = planPrefix$ + "hybrid.tsv"
        elsif .k = 14
            .f$ = anchorF$
        else
            .f$ = probePy$
        endif
        if fileReadable(.f$)
            deleteFile: .f$
        endif
    endfor
    if fileReadable(probeOk$)
        deleteFile: probeOk$
    endif
endproc

# ============================================================
# PYTHON DETECTION (no automatic installation)
# ============================================================
writeFileLine: probePy$, "import sys"
appendFileLine: probePy$, "if sys.version_info[0] < 3: sys.exit(1)"
appendFileLine: probePy$, "try:"
appendFileLine: probePy$, "    import numpy, sklearn"
appendFileLine: probePy$, "    open(r'" + probeOk$ + "', 'w').write('ok')"
appendFileLine: probePy$, "except Exception:"
appendFileLine: probePy$, "    sys.exit(1)"
nCand = 0
if macintosh
    if fileReadable("/opt/homebrew/bin/python3")
        nCand += 1
        cand$[nCand] = """/opt/homebrew/bin/python3"""
    endif
    if fileReadable("/usr/local/bin/python3")
        nCand += 1
        cand$[nCand] = """/usr/local/bin/python3"""
    endif
    nCand += 1
    cand$[nCand] = "python3"
    nCand += 1
    cand$[nCand] = "python"
elsif windows
    nCand += 1
    cand$[nCand] = "python"
    nCand += 1
    cand$[nCand] = "py -3"
    nCand += 1
    cand$[nCand] = "py"
    nCand += 1
    cand$[nCand] = "python3"
else
    nCand += 1
    cand$[nCand] = "python3"
    nCand += 1
    cand$[nCand] = "python"
endif
pythonCmd$ = ""
iCand = 1
while iCand <= nCand and pythonCmd$ = ""
    if fileReadable(probeOk$)
        deleteFile: probeOk$
    endif
    runSystem_nocheck: cand$[iCand] + " """ + probePy$ + """"
    if fileReadable(probeOk$)
        pythonCmd$ = cand$[iCand]
    endif
    iCand += 1
endwhile
if pythonCmd$ = ""
    @riCleanUp
    exitScript: "No Python 3 with numpy and scikit-learn was found (tried python3 / python / py)." + newline$
        ... + "Install them yourself, e.g.:  pip install numpy scikit-learn"
endif
appendInfoLine: "Python: ", pythonCmd$

# ============================================================
# ANALYSIS EXPORT: every channel of each Sound, peak 0.99
# (analysis only - the output is cut from the untouched Sound B)
# ============================================================
procedure riExportAnalysis: .snd, .path$
    selectObject: .snd
    .copy = Copy: "ri_analysis"
    Scale peak: 0.99
    Save as WAV file: .path$
    removeObject: .copy
endproc
@riExportAnalysis: soundA, wavA$
@riExportAnalysis: soundB, wavB$
appendInfoLine: "Analysis: all channels (A ", nChA, ", B ", nChB, ") via their mean power spectrum; all ", nChB, " B channel(s) are kept in the output"

# ============================================================
# LISTENER ANCHOR PAIRS (optional selected Table)
# ============================================================
nAnchors = 0
if anchorTab > 0
    selectObject: anchorTab
    colA = Get column index: "a_time"
    colB = Get column index: "b_time"
    if colA = 0 or colB = 0
        @riCleanUp
        exitScript: "The selected Table needs columns a_time and b_time (seconds)."
    endif
    nAnchorRows = Get number of rows
    writeFileLine: anchorF$, "a_time" + tab$ + "b_time"
    for i to nAnchorRows
        selectObject: anchorTab
        ta = Get value: i, "a_time"
        tb = Get value: i, "b_time"
        if ta <> undefined and tb <> undefined
            appendFileLine: anchorF$, fixed$(ta - xminA, 4) + tab$ + fixed$(tb - xminB, 4)
            nAnchors += 1
        endif
    endfor
    appendInfoLine: "Listener anchor pairs: ", nAnchors, " (evaluation only, never used for training)"
endif

# ============================================================
# CONFIGURATION AND ENGINE CALL
# ============================================================
c$ = "{" + newline$
c$ = c$ + "  ""a_wav"": """ + wavA$ + """," + newline$
c$ = c$ + "  ""b_wav"": """ + wavB$ + """," + newline$
c$ = c$ + "  ""plan_prefix"": """ + planPrefix$ + """," + newline$
c$ = c$ + "  ""events_a"": """ + evAF$ + """," + newline$
c$ = c$ + "  ""events_b"": """ + evBF$ + """," + newline$
c$ = c$ + "  ""report"": """ + reportF$ + """," + newline$
c$ = c$ + "  ""stats"": """ + statsF$ + """," + newline$
c$ = c$ + "  ""log"": """ + logF$ + """," + newline$
c$ = c$ + "  ""status"": """ + statusF$ + """," + newline$
c$ = c$ + "  ""method"": """ + method$ + """," + newline$
c$ = c$ + "  ""mode"": """ + mode$ + """," + newline$
c$ = c$ + "  ""sensitivity"": " + fixed$(segmentation_sensitivity, 4) + "," + newline$
c$ = c$ + "  ""min_dur"": " + fixed$(minimum_gesture_duration_s, 4) + "," + newline$
c$ = c$ + "  ""max_dur"": " + fixed$(maximum_gesture_duration_s, 4) + "," + newline$
c$ = c$ + "  ""morph"": " + fixed$(morphological_similarity, 4) + "," + newline$
c$ = c$ + "  ""contrast"": " + fixed$(continuity_vs_contrast, 4) + "," + newline$
c$ = c$ + "  ""flex"": " + fixed$(duration_flexibility, 4) + "," + newline$
c$ = c$ + "  ""xfade_ms"": " + fixed$(crossfade_ms, 3) + "," + newline$
c$ = c$ + "  ""avoid_rep"": " + string$(avoid_repetition) + "," + newline$
c$ = c$ + "  ""training"": """ + (if training = 1 then "validated" else "quick" fi) + """," + newline$
c$ = c$ + "  ""cache_dir"": """ + cacheDir$ + """," + newline$
if nAnchors > 0
    c$ = c$ + "  ""anchors"": """ + anchorF$ + """," + newline$
endif
if workflow$ = "B"
    # v1.4: authoritative driver schedule (onset and sounding duration of
    # every generated note) instead of a second segmentation pass.
    writeFileLine: schedF$, "onset_s" + tab$ + "dur_s"
    for i to nEv
        appendFileLine: schedF$, fixed$(evOn[i], 6) + tab$ + fixed$(evDur[i], 6)
    endfor
    c$ = c$ + "  ""a_events"": """ + schedF$ + """," + newline$
endif
c$ = c$ + "  ""seed"": " + string$(random_seed) + newline$
c$ = c$ + "}" + newline$
writeFile: cfg$, c$

appendInfoLine: "Running the engine (segmentation, joint training, matching)..."
runSystem_nocheck: pythonCmd$ + " """ + pythonScriptJ$ + """ """ + cfg$ + """ 2> """ + errF$ + """"

status$ = ""
if fileReadable(statusF$)
    status$ = readFile$(statusF$)
endif
if left$(status$, 2) <> "ok"
    msg$ = "Python engine failed."
    if status$ <> ""
        msg$ = msg$ + newline$ + status$
    endif
    if fileReadable(logF$)
        appendInfoLine: ""
        appendInfoLine: "--- engine log ---"
        appendInfo: readFile$(logF$)
    endif
    if fileReadable(errF$)
        appendInfoLine: "--- stderr ---"
        appendInfo: readFile$(errF$)
    endif
    @riCleanUp
    exitScript: msg$
endif

procedure riStat: .key$
    .text$ = readFile$(statsF$)
    .result$ = "?"
    .pos = index(.text$, newline$ + .key$ + "=")
    if .pos > 0
        .pos = .pos + 1
    elsif left$(.text$, length(.key$) + 1) = .key$ + "="
        .pos = 1
    endif
    if .pos > 0
        .start = .pos + length(.key$) + 1
        .rest$ = mid$(.text$, .start, length(.text$) - .start + 1)
        .nl = index(.rest$, newline$)
        if .nl > 0
            .result$ = left$(.rest$, .nl - 1)
        else
            .result$ = .rest$
        endif
    endif
endproc
@riStat: "total_n"
totalN = number(riStat.result$)
@riStat: "sr_b"
srEngine = number(riStat.result$)
@riStat: "cnn_ok"
cnnOk = number(riStat.result$)
@riStat: "n_a"
nEvA = number(riStat.result$)
@riStat: "n_b"
nEvB = number(riStat.result$)
@riStat: "coverage"
statCoverage$ = riStat.result$
@riStat: "sounding_coverage"
statSounding$ = riStat.result$
@riStat: "integrity"
statIntegrity$ = riStat.result$
@riStat: "added_value"
statAdded$ = riStat.result$
@riStat: "state_cnn"
stateCnn$ = riStat.result$
@riStat: "state_hybrid"
stateHybrid$ = riStat.result$
@riStat: "unique_b"
statUnique$ = riStat.result$
@riStat: "max_reuse"
statReuse$ = riStat.result$
@riStat: "env_corr"
statEnv$ = riStat.result$
@riStat: "agree_acoustic"
statAgree$ = riStat.result$
@riStat: "bias_centred"
statBias$ = riStat.result$
@riStat: "eff_rank"
statRank$ = riStat.result$
@riStat: "cnn_status"
statCnn$ = riStat.result$
@riStat: "seconds"
statSec$ = riStat.result$
@riStat: "warnings"
statWarn$ = riStat.result$
if workflow$ = "B"
    @riStat: "sched_used"
    statSchedUsed$ = riStat.result$
    @riStat: "auto_n"
    statAutoN$ = riStat.result$
    @riStat: "auto_hit"
    statAutoHit$ = riStat.result$
endif
if totalN = undefined or srEngine <> srB
    @riCleanUp
    exitScript: "The engine returned an inconsistent plan (sampling rate " + string$(srEngine) + " vs " + string$(srB) + " Hz)."
endif

appendInfoLine: ""
appendInfoLine: "--- engine report ---"
appendInfo: readFile$(reportF$)

# ============================================================
# ASSEMBLY: whole gestures of B, sample-exact, all channels
# ============================================================
procedure riRender: .plan, .name$
    selectObject: .plan
    .nRows = Get number of rows
    .out = Create Sound from formula: .name$, nChB, 0, totalN / srB, srB, "0"
    for .r to .nRows
        selectObject: .plan
        .o = Get value: .r, "out_s0"
        .s = Get value: .r, "src_s0"
        .len = Get value: .r, "n"
        .g = Get value: .r, "gain"
        .fin = Get value: .r, "fin_n"
        .fout = Get value: .r, "fout_n"
        .sh = .s - .o
        .k$ = "(col - " + string$(.o + 1) + ")"
        .eIn$ = "1"
        if .fin > 0
            .eIn$ = "(if " + .k$ + " < " + string$(.fin) + " then 0.5 - 0.5 * cos(pi * (" + .k$ + " + 0.5) / " + string$(.fin) + ") else 1 fi)"
        endif
        .eOut$ = "1"
        if .fout > 0
            .eOut$ = "(if " + .k$ + " >= " + string$(.len - .fout) + " then 0.5 - 0.5 * cos(pi * (" + string$(.len) + " - " + .k$ + " - 0.5) / " + string$(.fout) + ") else 1 fi)"
        endif
        if .s >= 0 and .s + .len <= nSampB and .len > 0
            selectObject: .out
            Formula (part): (.o + 0.25) / srB, (.o + .len - 0.25) / srB, 1, nChB,
                ... "self + " + fixed$(.g, 8) + " * " + .eIn$ + " * " + .eOut$ + " * object[" + string$(soundB) + ", row, col + " + string$(.sh) + "]"
        endif
    endfor
    selectObject: .out
    .peak = Get absolute extremum: 0, 0, "None"
    .ceilGain = 1
    if .peak > 10 ^ (-1 / 20)
        .ceilGain = 10 ^ (-1 / 20) / .peak
        Formula: "self * " + fixed$(.ceilGain, 10)
    endif
    .peakOut = Get absolute extremum: 0, 0, "None"
    .rms = Get root-mean-square: 0, 0
endproc

baseName$ = replace_regex$(nameB$ + "_by_" + nameA$, "[^A-Za-z0-9_\-]", "_", 0)
if method$ = "compare"
    nOut = 3
    outMethod$[1] = "acoustic"
    outMethod$[2] = "cnn"
    outMethod$[3] = "hybrid"
else
    nOut = 1
    outMethod$[1] = method$
endif
appendInfoLine: ""
appendInfoLine: "--- assembly ---"
for iOut to nOut
    m$ = outMethod$[iOut]
    planTab[iOut] = Read Table from tab-separated file: planPrefix$ + m$ + ".tsv"
    suffix$ = m$
    mState$ = "used"
    if m$ = "cnn"
        mState$ = stateCnn$
    elsif m$ = "hybrid"
        mState$ = stateHybrid$
    endif
    if mState$ = "fallback"
        suffix$ = m$ + "_acousticFallback"
    elsif mState$ = "unreliable"
        suffix$ = m$ + "_UNRELIABLE"
    endif
    @riRender: planTab[iOut], baseName$ + "_RI_" + suffix$ + "_" + mode$
    outSound[iOut] = riRender.out
    selectObject: planTab[iOut]
    nRows[iOut] = Get number of rows
    selectObject: outSound[iOut]
    outDur[iOut] = Get total duration
    appendInfoLine: "  ", selected$("Sound"), ": ", nRows[iOut], " placed gestures | ", fixed$(outDur[iOut], 2), " s | ",
        ... nChB, " ch | peak ", fixed$(20 * log10(max(1e-12, riRender.peakOut)), 1), " dBFS",
        ... if riRender.ceilGain < 1 then " (common ceiling gain " + fixed$(20 * log10(riRender.ceilGain), 1) + " dB)" else "" fi
endfor
mainIdx = if method$ = "compare" then 3 else 1 fi

# ============================================================
# DIAGNOSTIC OBJECTS (optional)
# ============================================================
evTabA = Read Table from tab-separated file: evAF$
evTabB = Read Table from tab-separated file: evBF$

procedure riEventGrid: .tab, .xmin, .xmax, .prefix$, .extraCol$, .name$
    .tg = Create TextGrid: .xmin, .xmax, "gestures", ""
    Rename: .name$
    selectObject: .tab
    .n = Get number of rows
    .last = .xmin
    for .i to .n
        selectObject: .tab
        .t1 = Get value: .i, "start_s"
        .t2 = Get value: .i, "end_s"
        .x = Get value: .i, .extraCol$
        .t1 = .t1 + .xmin
        .t2 = min(.t2 + .xmin, .xmax)
        selectObject: .tg
        if .t1 > .last + 1e-6 and .t1 < .xmax - 1e-6
            Insert boundary: 1, .t1
        endif
        if .t2 > .t1 + 1e-6 and .t2 < .xmax - 1e-6
            Insert boundary: 1, .t2
        endif
        .last = .t2
        .iv = Get interval at time: 1, (.t1 + .t2) / 2
        if .prefix$ = "A"
            Set interval text: 1, .iv, "A" + string$(.i) + ">B" + string$(.x)
        else
            Set interval text: 1, .iv, "B" + string$(.i) + (if .x > 0 then " x" + string$(.x) else "" fi)
        endif
    endfor
endproc

procedure riMapGrid: .plan, .dur, .name$
    .tg = Create TextGrid: 0, .dur, "A_gesture B_gesture", ""
    Rename: .name$
    selectObject: .plan
    .n = Get number of rows
    .last = 0
    for .i to .n
        selectObject: .plan
        .t = Get value: .i, "out_start_s"
        selectObject: .tg
        if .t > .last + 0.001 and .t < .dur - 0.001
            Insert boundary: 1, .t
            Insert boundary: 2, .t
            .last = .t
        endif
    endfor
    for .i to .n
        selectObject: .plan
        .t = Get value: .i, "out_start_s"
        .a = Get value: .i, "a_event"
        .b = Get value: .i, "b_event"
        .bt = Get value: .i, "b_start_s"
        selectObject: .tg
        .iv = Get interval at time: 1, min(.dur - 0.0005, .t + 0.0005)
        .old$ = Get label of interval: 1, .iv
        .new$ = "A" + string$(.a)
        if .old$ <> ""
            .new$ = .old$ + "+" + .new$
        endif
        Set interval text: 1, .iv, .new$
        .old$ = Get label of interval: 2, .iv
        .new$ = "B" + string$(.b) + " @" + fixed$(.bt, 2) + "s"
        if .old$ <> ""
            .new$ = .old$ + " + " + .new$
        endif
        Set interval text: 2, .iv, .new$
    endfor
endproc

if export_diagnostic_data
    @riEventGrid: evTabA, xminA, xminA + durA, "A", "matched_b", "RI_gestures_A_" + replace_regex$(nameA$, "[^A-Za-z0-9_\-]", "_", 0)
    @riEventGrid: evTabB, xminB, xminB + durB, "B", "used", "RI_gestures_B_" + replace_regex$(nameB$, "[^A-Za-z0-9_\-]", "_", 0)
    for iOut to nOut
        @riMapGrid: planTab[iOut], outDur[iOut], "RI_map_" + outMethod$[iOut]
        selectObject: planTab[iOut]
        Rename: "RI_mapping_" + outMethod$[iOut]
    endfor
    selectObject: evTabA
    Rename: "RI_events_A"
    selectObject: evTabB
    Rename: "RI_events_B"
    appendInfoLine: "Diagnostic objects: gesture TextGrids for A and B, a mapping TextGrid and a mapping Table per result"
    appendInfoLine: "  (Table > Save as comma-separated file gives the CSV)."
endif

# ============================================================
# VISUALIZATION
# ============================================================
procedure riSafe: .s$
    .out$ = replace$(.s$, "\", "/", 0)
    .out$ = replace$(.out$, "_", "\_ ", 0)
    .out$ = replace$(.out$, "%", "\% ", 0)
    .out$ = replace$(.out$, "#", "\# ", 0)
    .out$ = replace$(.out$, "^", "\^ ", 0)
endproc

procedure riPanelName: .top, .bottom, .name$
    Font size: 7
    Select inner viewport: 0.6, 7.7, .top, .bottom
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text special: -0.035, "centre", 0.5, "bottom", "Helvetica", 7, "90", .name$
endproc

procedure riStep: .range, .target
    .raw = .range / .target
    .mag = 10 ^ floor(log10(max(1e-12, .raw)))
    .nn = .raw / .mag
    if .nn < 1.5
        .step = .mag
    elsif .nn < 3.5
        .step = 2 * .mag
    elsif .nn < 7.5
        .step = 5 * .mag
    else
        .step = 10 * .mag
    endif
endproc


# ---------- generated-form figure (v1.4) ----------
# Notated value (pale bar), sounding note (bar height = accent), rests (empty),
# section boundaries, and inter-onset interval vs. sounding duration over time.
procedure riFormFigure: .y0, .standalone, .snd
    .tEnd = genT + 0.5
    if .standalone
        Font size: 13
        Select inner viewport: 0, 8, .y0 + 0.05, .y0 + 0.55
        Axes: 0, 1, 0, 1
        Colour: "Black"
        Text: 0.5, "centre", 0.72, "half", "##Rhythmic Imprinting - generated rhythmic form##"
        Font size: 7
        Select inner viewport: 0, 8, .y0 + 0.05, .y0 + 0.55
        Axes: 0, 1, 0, 1
        Colour: "{0.35, 0.35, 0.50}"
        Text: 0.5, "centre", 0.20, "half", modelName$ + "   |   seed " + string$(random_seed) + "   |   " + string$(nEv) + " events   |   " + fixed$(.tEnd, 1) + " s   |   no imprinting (standalone Sound)"
        .eTop = .y0 + 0.78
    else
        Font size: 9
        Select inner viewport: 0, 8, .y0, .y0 + 0.3
        Axes: 0, 1, 0, 1
        Colour: "Black"
        Text: 0.5, "centre", 0.5, "half", "##Generated driver A: " + modelName$ + ", seed " + string$(random_seed) + "##"
        .eTop = .y0 + 0.4
    endif
    .eBot = .eTop + 1.3
    # ----- events -----
    Font size: 6
    Select inner viewport: 0.6, 7.7, .eTop, .eBot
    Axes: 0, .tEnd, 0, 1.18
    Paint rectangle: "{0.985, 0.985, 0.99}", 0, .tEnd, 0, 1.18
    for .k to nSec
        .s1 = secT[.k]
        .s2 = if .k < nSec then secT[.k + 1] else genT fi
        Paint rectangle: if .k mod 2 = 1 then "{0.93, 0.95, 0.99}" else "{0.97, 0.97, 0.97}" fi, .s1, .s2, 0, 1.18
    endfor
    for .i to nEv
        Paint rectangle: "{0.80, 0.80, 0.80}", evOn[.i], evOn[.i] + evVal[.i], 0.02, 0.08
        Paint rectangle: "{0.20, 0.40, 0.80}", evOn[.i], evOn[.i] + evDur[.i], 0.12, 0.12 + 0.88 * evAcc[.i]
    endfor
    Colour: "{0.10, 0.15, 0.35}"
    for .i to nEv
        Draw line: evOn[.i], 0.12, evOn[.i], 0.12 + 0.88 * evAcc[.i]
    endfor
    Colour: "{0.55, 0.20, 0.20}"
    Dotted line
    for .k from 2 to nSec
        Draw line: secT[.k], 0, secT[.k], 1.18
    endfor
    Solid line
    Colour: "{0.25, 0.25, 0.35}"
    for .k to nSec
        Text: secT[.k] + 0.004 * .tEnd, "left", 1.10, "half", secName$[.k]
    endfor
    Colour: "Black"
    Select inner viewport: 0.6, 7.7, .eTop, .eBot
    Axes: 0, .tEnd, 0, 1.18
    Draw inner box
    @riPanelName: .eTop, .eBot, "Events"
    # ----- IOI vs duration -----
    .iTop = .eBot + 0.2
    .iBot = .iTop + 0.85
    .yMax = 0
    for .i to nEv
        .ioi = if .i < nEv then evOn[.i + 1] - evOn[.i] else evVal[.i] fi
        .yMax = max(.yMax, .ioi)
    endfor
    .yMax = .yMax * 1.1
    Font size: 6
    Select inner viewport: 0.6, 7.7, .iTop, .iBot
    Axes: 0, .tEnd, 0, .yMax
    Paint rectangle: "{0.985, 0.985, 0.99}", 0, .tEnd, 0, .yMax
    for .i to nEv - 1
        Paint circle (mm): "{0.20, 0.40, 0.80}", evOn[.i], evOn[.i + 1] - evOn[.i], 0.45
        Paint circle (mm): "{0.85, 0.45, 0.10}", evOn[.i], evDur[.i], 0.35
    endfor
    Colour: "{0.55, 0.20, 0.20}"
    Dotted line
    for .k from 2 to nSec
        Draw line: secT[.k], 0, secT[.k], .yMax
    endfor
    Solid line
    Colour: "Black"
    Select inner viewport: 0.6, 7.7, .iTop, .iBot
    Axes: 0, .tEnd, 0, .yMax
    Draw inner box
    @riStep: .yMax, 3
    Marks left every: 1, riStep.step, "yes", "yes", "no"
    Font size: 6
    Select inner viewport: 0.6, 7.7, .iTop, .iBot
    Axes: 0, 1, 0, 1
    Colour: "{0.20, 0.40, 0.80}"
    Text: 0.008, "left", 0.90, "half", "inter-onset interval"
    Colour: "{0.85, 0.45, 0.10}"
    Text: 0.12, "left", 0.90, "half", "sounding duration"
    Colour: "Black"
    @riPanelName: .iTop, .iBot, "Seconds"
    .last = .iBot
    # ----- waveform (standalone only) -----
    if .standalone
        .wTop = .iBot + 0.2
        .wBot = .wTop + 0.8
        selectObject: .snd
        .pk = Get absolute extremum: 0, 0, "None"
        Font size: 6
        Select inner viewport: 0.6, 7.7, .wTop, .wBot
        Colour: "{0.20, 0.40, 0.80}"
        Draw: 0, 0, -.pk, .pk, "no", "Curve"
        Colour: "Black"
        Select inner viewport: 0.6, 7.7, .wTop, .wBot
        Axes: 0, .tEnd, -.pk, .pk
        Draw inner box
        @riPanelName: .wTop, .wBot, "Sound"
        .last = .wBot
    endif
    Font size: 6
    Select inner viewport: 0.6, 7.7, .last - 0.1, .last
    Axes: 0, .tEnd, 0, 1
    @riStep: .tEnd, 10
    Marks bottom every: 1, riStep.step, "yes", "yes", "no"
    Select inner viewport: 0.6, 7.7, .last - 0.1, .last
    Axes: 0, 1, 0, 1
    Text bottom: "yes", "Time (s) - pale bar = notated value, blue = sounding note (height = accent), gap = rest"
    # ----- summary -----
    .sTop = .last + 0.42
    .sBot = .sTop + 0.5
    Font size: 7
    Select inner viewport: 0.6, 7.7, .sTop, .sBot
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Select inner viewport: 0.6, 7.7, .sTop, .sBot
    Axes: 0, 1, 0, 1
    Draw inner box
    Select inner viewport: 0.6, 7.7, .sTop, .sBot
    Axes: 0, 1, 0, 1
    Colour: "Black"
    @riMedian: "ioi"
    .ioiTxt$ = fixed$(riMedian.med, 3)
    @riMedian: "dur"
    .durTxt$ = fixed$(riMedian.med, 3)
    Text: 0.015, "left", 0.70, "half", string$(nEv) + " events   |   median IOI " + .ioiTxt$ + " s   |   median duration " + .durTxt$ + " s   |   sounding ratio " + fixed$(genRatio, 2) + "   |   longest silence " + fixed$(genLongestRest, 2) + " s   |   overlaps " + string$(genOverlaps)
    Text: 0.015, "left", 0.28, "half", "tempo " + fixed$(base_tempo_BPM, 0) + " BPM  |  complexity " + fixed$(rhythmic_complexity, 2) + "  |  density " + fixed$(event_density, 2) + "  |  duration contrast " + fixed$(duration_contrast, 2) + "  |  articulation " + fixed$(articulation, 2) + "  |  formal development " + fixed$(formal_development, 2)
    .bottom = .sBot + 0.1
endproc

mainPlan = planTab[mainIdx]
mainOut = outSound[mainIdx]
tShow = outDur[mainIdx]
canvasH = 7.25

Erase all
Line width: 1
Solid line

# ---------- title ----------
@riSafe: nameA$
safeA$ = riSafe.out$
@riSafe: nameB$
safeB$ = riSafe.out$
Font size: 13
Select inner viewport: 0, 8, 0.05, 0.55
Axes: 0, 1, 0, 1
Colour: "Black"
Text: 0.5, "centre", 0.72, "half", "##Rhythmic Imprinting##"
Font size: 7
Select inner viewport: 0, 8, 0.05, 0.55
Axes: 0, 1, 0, 1
Colour: "{0.35, 0.35, 0.50}"
Text: 0.5, "centre", 0.20, "half", "A " + safeA$ + " drives B " + safeB$ + "   |   " + (if method$ = "compare" then "compare (figure: hybrid)" else method$ fi) + "   |   " + mode$
Colour: "Black"

# ---------- I. driver A with its gestures ----------
iTop = 0.78
iBot = 1.62
xA2 = 0.6 + 7.1 * min(1, durA / tShow)
Font size: 6
Select inner viewport: 0.6, 7.7, iTop, iBot
Axes: 0, tShow, 0, 1
Paint rectangle: "{0.985, 0.985, 0.99}", 0, tShow, 0, 1
selectObject: evTabA
for i to nEvA
    selectObject: evTabA
    t1 = Get value: i, "start_s"
    t2 = Get value: i, "end_s"
    Paint rectangle: if i mod 2 = 1 then "{0.86, 0.90, 0.97}" else "{0.93, 0.95, 0.99}" fi, t1, t2, 0, 1
endfor
Select inner viewport: 0.6, xA2, iTop, iBot
selectObject: soundA
Colour: "{0.25, 0.30, 0.45}"
Draw: 0, 0, -peakA, peakA, "no", "Curve"
Colour: "Black"
Select inner viewport: 0.6, 7.7, iTop, iBot
Axes: 0, 1, 0, 1
Draw inner box
Font size: 6
Select inner viewport: 0.6, 7.7, iTop, iBot
Axes: 0, 1, 0, 1
Text: 0.008, "left", 0.90, "half", string$(nEvA) + " gestures (shaded)"
@riPanelName: iTop, iBot, "A  driver"

# ---------- II. gesture map: output time -> position in B ----------
mTop = 1.82
mBot = 3.62
Font size: 6
Select inner viewport: 0.6, 7.7, mTop, mBot
Axes: 0, tShow, 0, durB
Paint rectangle: "{0.985, 0.985, 0.99}", 0, tShow, 0, durB
# B gestures as faint horizontal bands; used ones darker
for i to nEvB
    selectObject: evTabB
    t1 = Get value: i, "start_s"
    t2 = Get value: i, "end_s"
    u = Get value: i, "used"
    if u > 0
        bandCol$ = if i mod 2 = 1 then "{0.90, 0.87, 0.78}" else "{0.94, 0.92, 0.86}" fi
    else
        bandCol$ = if i mod 2 = 1 then "{0.93, 0.93, 0.93}" else "{0.97, 0.97, 0.97}" fi
    endif
    Paint rectangle: bandCol$, 0, tShow, t1, t2
endfor
Select inner viewport: 0.6, 7.7, mTop, mBot
Axes: 0, tShow, 0, durB
selectObject: mainPlan
nMain = Get number of rows
for i to nMain
    selectObject: mainPlan
    o1 = Get value: i, "out_start_s"
    o2 = Get value: i, "out_end_s"
    b1 = Get value: i, "src_start_s"
    b2 = Get value: i, "src_end_s"
    sc = Get value: i, "successor"
    ex = Get value: i, "extended"
    if sc = 1
        Colour: "{0.45, 0.20, 0.60}"
    elsif ex = 1
        Colour: "{0.85, 0.45, 0.10}"
    else
        Colour: "{0.15, 0.45, 0.55}"
    endif
    Line width: 2.5
    Draw line: o1, b1, o2, b2
    Paint circle (mm): "{0.80, 0.20, 0.25}", o1, b1, 0.35
endfor
Line width: 1
Colour: "Black"
Select inner viewport: 0.6, 7.7, mTop, mBot
Axes: 0, tShow, 0, durB
Draw inner box
@riStep: durB, 5
Marks left every: 1, riStep.step, "yes", "yes", "no"
Font size: 6
Select inner viewport: 0.6, 7.7, mTop, mBot
Axes: 0, 1, 0, 1
Colour: "{0.15, 0.45, 0.55}"
Text: 0.008, "left", 0.955, "half", "placed B gesture"
Colour: "{0.45, 0.20, 0.60}"
Text: 0.135, "left", 0.955, "half", "B successor (phrase)"
Colour: "{0.85, 0.45, 0.10}"
Text: 0.290, "left", 0.955, "half", "extended into B's continuation"
Colour: "{0.45, 0.45, 0.50}"
Text: 0.992, "right", 0.955, "half", "bands = B gestures (darker = used)"
Colour: "Black"
@riPanelName: mTop, mBot, "B position (s)"

# ---------- III. result ----------
rTop = 3.82
rBot = 4.72
selectObject: mainOut
rPeak = Get absolute extremum: 0, 0, "None"
if rPeak <= 0
    rPeak = 1
endif
Font size: 6
Select inner viewport: 0.6, 7.7, rTop, rBot
Colour: "{0.20, 0.40, 0.80}"
Draw: 0, 0, -rPeak, rPeak, "no", "Curve"
Colour: "Black"
Select inner viewport: 0.6, 7.7, rTop, rBot
Axes: 0, tShow, -rPeak, rPeak
Draw inner box
@riStep: tShow, 10
Marks bottom every: 1, riStep.step, "yes", "yes", "no"
Font size: 6
Select inner viewport: 0.6, 7.7, rTop, rBot
Axes: 0, 1, 0, 1
Text bottom: "yes", "Time (s) - output aligned to A"
@riPanelName: rTop, rBot, "Result"

# ---------- IV. matching cost, or three-way choice map ----------
cTop = 5.17
cBot = 6.12
Font size: 6
if method$ = "compare"
    Select inner viewport: 0.6, 7.7, cTop, cBot
    Axes: 0, tShow, 0, durB
    Paint rectangle: "{0.985, 0.985, 0.99}", 0, tShow, 0, durB
    for iOut to 3
        if iOut = 1
            col$ = "{0.55, 0.55, 0.55}"
            rad = 1.00
        elsif iOut = 2
            col$ = "{0.20, 0.40, 0.80}"
            rad = 0.70
        else
            col$ = "{0.85, 0.45, 0.10}"
            rad = 0.40
        endif
        selectObject: planTab[iOut]
        nr = Get number of rows
        for i to nr
            selectObject: planTab[iOut]
            ta = Get value: i, "a_start_s"
            tb = Get value: i, "b_start_s"
            Select inner viewport: 0.6, 7.7, cTop, cBot
            Axes: 0, tShow, 0, durB
            Paint circle (mm): col$, ta, tb, rad
        endfor
    endfor
    Select inner viewport: 0.6, 7.7, cTop, cBot
    Axes: 0, tShow, 0, durB
    Draw inner box
    @riStep: durB, 4
    Marks left every: 1, riStep.step, "yes", "yes", "no"
    Font size: 6
    Select inner viewport: 0.6, 7.7, cTop, cBot
    Axes: 0, 1, 0, 1
    Colour: "{0.55, 0.55, 0.55}"
    Text: 0.008, "left", 0.94, "half", "Acoustic"
    Colour: "{0.20, 0.40, 0.80}"
    Text: 0.075, "left", 0.94, "half", "Joint CNN"
    Colour: "{0.85, 0.45, 0.10}"
    Text: 0.150, "left", 0.94, "half", "Hybrid"
    Colour: "{0.45, 0.45, 0.50}"
    Text: 0.992, "right", 0.94, "half", "B gesture chosen for each A gesture (concentric = agreement)"
    Colour: "Black"
    @riPanelName: cTop, cBot, "Choice (B s)"
else
    selectObject: mainPlan
    cMax = Get maximum: "cost"
    if cMax <= 0
        cMax = 1
    endif
    cMax = cMax * 1.1
    Select inner viewport: 0.6, 7.7, cTop, cBot
    Axes: 0, tShow, 0, cMax
    Paint rectangle: "{0.985, 0.985, 0.99}", 0, tShow, 0, cMax
    for i to nMain
        selectObject: mainPlan
        ta1 = Get value: i, "a_start_s"
        ta2 = Get value: i, "a_end_s"
        cc = Get value: i, "cost"
        ct = Get value: i, "d_traj"
        sb = Get value: i, "substitution"
        Paint rectangle: if sb = 1 then "{0.95, 0.75, 0.55}" else "{0.65, 0.78, 0.90}" fi, ta1, ta2, 0, cc
    endfor
    Select inner viewport: 0.6, 7.7, cTop, cBot
    Axes: 0, tShow, 0, cMax
    Draw inner box
    @riStep: cMax, 3
    Marks left every: 1, riStep.step, "yes", "yes", "no"
    Font size: 6
    Select inner viewport: 0.6, 7.7, cTop, cBot
    Axes: 0, 1, 0, 1
    Colour: "{0.30, 0.50, 0.70}"
    Text: 0.008, "left", 0.92, "half", "best-cost choice"
    Colour: "{0.80, 0.50, 0.20}"
    Text: 0.115, "left", 0.92, "half", "phrase / repetition choice (not the single best cost)"
    Colour: "{0.45, 0.45, 0.50}"
    Text: 0.992, "right", 0.92, "half", "matching cost per A gesture (lower = closer)"
    Colour: "Black"
    @riPanelName: cTop, cBot, "Cost"
endif

# ---------- summary ----------
Font size: 7
Select inner viewport: 0.6, 7.7, 6.42, 7.15
Axes: 0, 1, 0, 1
Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
Select inner viewport: 0.6, 7.7, 6.42, 7.15
Axes: 0, 1, 0, 1
Draw inner box
Select inner viewport: 0.6, 7.7, 6.42, 7.15
Axes: 0, 1, 0, 1
Colour: "Black"
procedure riNum: .s$, .d
    .v = number(.s$)
    .out$ = if .v = undefined then "n/a" else fixed$(.v, .d) fi
endproc
@riNum: statCoverage$, 2
covTxt$ = riNum.out$
@riNum: statSounding$, 2
sndTxt$ = riNum.out$
@riNum: statEnv$, 2
envTxt$ = riNum.out$
@riNum: statRank$, 1
rankTxt$ = riNum.out$
@riNum: statBias$, 2
biasTxt$ = riNum.out$
@riNum: statAgree$, 2
agreeTxt$ = riNum.out$
@riNum: statSec$, 1
secTxt$ = riNum.out$
Text: 0.015, "left", 0.80, "half", "Gestures A " + string$(nEvA) + " | B " + string$(nEvB) + "   |   B gestures used " + statUnique$ + " (max reuse " + statReuse$ + ")   |   A's sounding time covered: timeline " + covTxt$ + ", sounding " + sndTxt$ + "   |   envelope r " + envTxt$ + "   |   engine " + secTxt$ + " s"
@riSafe: statCnn$
Text: 0.015, "left", 0.50, "half", "Joint CNN " + riSafe.out$ + "   |   integrity check " + statIntegrity$ + "   |   added value over Acoustic: " + replace$(statAdded$, "_", " ", 0) + "   |   use: CNN " + stateCnn$ + ", Hybrid " + stateHybrid$
Text: 0.015, "left", 0.20, "half", "Agreement with Acoustic " + agreeTxt$ + "  |  morph " + fixed$(morphological_similarity, 2) + "  |  continuity-contrast " + fixed$(continuity_vs_contrast, 2) + "  |  duration flex " + fixed$(duration_flexibility, 2) + "  |  crossfade " + fixed$(crossfade_ms, 1) + " ms  |  sensitivity " + fixed$(segmentation_sensitivity, 2) + "  |  seed " + string$(random_seed) + (if statWarn$ <> "0" then "  |  warnings " + statWarn$ + " (see Info)" else "" fi)
if workflow$ = "B"
    @riFormFigure: 7.35, 0, genSound
    canvasH = riFormFigure.bottom
endif
Select outer viewport: 0, 8, 0, canvasH
Font size: 10

# ============================================================
# REPORT AND CLEANUP
# ============================================================
if warnLines$ <> ""
    appendInfoLine: ""
    appendInfoLine: "Adjustments / notes:"
    appendInfo: warnLines$
endif
appendInfoLine: ""
appendInfoLine: "Listening comparison: with Compare all three, the Sounds play Acoustic, Joint CNN, Hybrid in that order."
appendInfoLine: "Everything was rendered with the same segmentation, costs, crossfades and gains."

if not export_diagnostic_data
    for iOut to nOut
        removeObject: planTab[iOut]
    endfor
    removeObject: evTabA, evTabB
endif
@riCleanUp
if workflow$ = "B"
    appendInfoLine: ""
    appendInfoLine: "Generated driver: scheduled events ", nEv, " | used by the engine ", statSchedUsed$,
        ... " | automatic segmentation (check only) ", statAutoN$, " gestures, ", statAutoHit$, " of ", nEv, " onsets within 30 ms"
    appendInfoLine: "Following preserves the scheduled onsets by design; this is not evidence about the CNN."
    if keep_generated_rhythm_as_Sound
        appendInfoLine: "Generated rhythm kept as: ", genName$
    else
        removeObject: genSound
    endif
endif

selectObject: outSound[1]
for iOut from 2 to nOut
    plusObject: outSound[iOut]
endfor
if play_result
    Play
endif
