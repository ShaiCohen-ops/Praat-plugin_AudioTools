# ============================================================
# Praat AudioTools - Rhythmic_Imprinting.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3 (2026) - musical presets (Python engine v1.2)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   RHYTHMIC IMPRINTING
#   Gesture-driven recomposition of recorded sound.
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
# HELP - RHYTHMIC IMPRINTING (v1.3)
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

form Rhythmic Imprinting v1.3
    comment A = Rhythm / Gesture Driver; B = Sound Material (output audio comes from B).
    comment For the reverse imprint, choose the other Sound as A in Driver_A_is.
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
# SELECTION AND ASSIGNMENT
# ============================================================
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
writeInfoLine: "=== Rhythmic Imprinting v1.3 ==="
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
planPrefix$ = tmpPrefix$ + "plan_"
probePy$ = tmpPrefix$ + "probe.py"
anchorF$ = tmpPrefix$ + "anchors.tsv"
cacheDir$ = replace_regex$(preferencesDirectory$ + "/ri_cache", "\\", "/", 0)
probeOk$ = tmpPrefix$ + "probe.ok"

procedure riCleanUp
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

selectObject: outSound[1]
for iOut from 2 to nOut
    plusObject: outSound[iOut]
endfor
if play_result
    Play
endif
