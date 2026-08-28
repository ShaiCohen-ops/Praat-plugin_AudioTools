# ============================================================
# Praat AudioTools - Acoustic_Grammar_Reducer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.7 (2026) - pGTTM Acoustic-Grammar Loop, all three stages
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Complete Praat + Python pGTTM Acoustic-Grammar Loop. Extracts
#   time-aligned pitch, formant and intensity features from the selected
#   Sound, hands the audio to pgttm_engine.py for spectral-flux onset
#   detection and probabilistic GTTM grouping/reduction, then splices the
#   retained structural spans back into a new Sound object.
#
#   The deliverable is a Sound in the object list:
#       [name]_pGTTM_Skeleton_Montage
#   The CSV / TextGrid / EDL are scratch by default and are deleted once
#   the montage exists (set Keep_intermediate_files to keep them).
#
#   Pipeline (single script, no chaining):
#     [Sound] -> Stage 1  features + analysis WAV   (Praat)
#             -> Stage 2  onsets + pGTTM grammar    (pgttm_engine.py)
#             -> Stage 3  splice retained spans     (Praat)
#             -> Stage 4  analysis figure           (Praat Picture)
#             -> [name]_pGTTM_Skeleton_Montage
#
# v1.7 reviewed (external code review; three contract/edge fixes plus two
# of my own):
#   - Merge_weakest_fraction is no longer silently overwritten by the
#     material preset. The form said "Input material (sets onset detection)"
#     while the presets also set the merge depth, and the header comment
#     claimed presets set "detection parameters ONLY (... , boundary
#     threshold)" — a sentence that contradicts itself. The field now
#     defaults to -1, meaning "follow the preset"; any value in 0..1 is the
#     user's and is honoured. The Info window states which source won.
#   - Target_retention documented as a TARGET, not a hard cap. One head
#     always survives, so a file whose best segment already exceeds the
#     budget overshoots it: measured, a 1 s file with a 0.8 s best segment
#     keeps 80% against a 45% request. The engine now says so when it
#     happens instead of leaving the exception in a code comment.
#   - An onset accepted on the FINAL frame produced a segment ending at
#     duration + time_step, because the old code extended zero-length spans
#     instead of clamping them. That put a TextGrid interval past the
#     object's own xmax — an invalid TextGrid. The audio was never affected,
#     since Stage 3 clamps before cutting, which is exactly why it went
#     unnoticed. Spans are now clamped, degenerate ones dropped, and the
#     TextGrid writer re-checks the invariant at the point of writing.
#   - Zero-crossing snapping now uses the ANALYSIS channel instead of
#     channel 1. On a stereo file whose strongest channel is 2, the cuts came
#     from channel 2 but were snapped to channel 1's crossings.
#   - The FFT window was ~46 ms at 44.1 kHz but 85.3 ms at 48, 96 and
#     192 kHz, because rounding UP to a power of two crosses a boundary just
#     above 0.046*sr at those rates. Nearest power of two instead: every
#     supported rate now lands in 42.7-46.4 ms, so the same recording gives
#     the same onsets at 44.1 and 48 kHz.
#   - Pitch variability moved from Hz to CENTS. In Hz the same musical wobble
#     scored as more variance the higher the register.
#
# v1.6 reviewed (naming and figure; no change to the signal path or grammar):
#   - RENAMED from extract_features.praat. That name described Stage 1 of
#     five and implied the deliverable was a feature table; the deliverable
#     is spliced audio. Anyone reading the plugin directory would have
#     mis-sorted this script next to the analysis utilities.
#   - The Sound and TextGrid the script creates keep their pGTTM names.
#     They describe the artifact, not the script, and pGTTM IS the acoustic
#     grammar the new title refers to; the TextGrid tier names
#     (Grouping_Macro, TimeSpan_Heads) already use that vocabulary.
#
#   - Figure moved onto the suite's shared palette, the one used by
#     Perceptual_Graph and CWT_Granular_Resampler: structural greys
#     {0.25,0.25,0.35} / {0.35,0.35,0.50} / {0.55,0.55,0.62} / {0.80,0.80,0.80},
#     plate fills {0.97,0.97,0.97} and {0.94,0.94,0.94}, and the categorical
#     set {0.85,0.35,0.35} / {0.35,0.55,0.85} / {0.35,0.75,0.45} for the
#     reduction levels. Figures from different scripts in the suite now sit
#     together on a page.
#   - Nothing in the figure is drawn in black any more. Black read as
#     "default" rather than as a choice, and in a figure where colour carries
#     the reduction level it also competed with the darkest category: the L0
#     anchors were near-black, so the ranking looked like a greyscale ramp
#     with two colours attached rather than three ranked categories.
#   - L3 takes the LIGHT variant of the library's eighth category rather than
#     a fourth strong colour, so discarded material recedes.
#   - Panels I-IV gained the light plate fill the other scripts use.
#
# v1.5 reviewed — the montage was coming out equal to the input:
#   Two absolute thresholds were being applied to quantities whose scale
#   depends on the material, the same mistake as the pre-v1.4 onset
#   threshold. Measured on a 10.7 s flute phrase and 17.9 s of Hebrew
#   speech, every preset returned 51-97% of the original and one returned
#   97.5%, which plays back as the input.
#
#   - Boundary_threshold -> Merge_weakest_fraction, and it is now a
#     QUANTILE. GPR strength is a weighted mean of four min-max normalized
#     cues that peak at DIFFERENT boundaries, so the mean is crushed toward
#     zero: measured median 0.15 (flute) and 0.20 (speech) against a
#     maximum of 0.66-0.71. Any absolute level near 0.5 therefore deleted
#     over 90% of boundaries — 25 onsets collapsed to 2 groups — and a
#     reduction with two groups to choose between cannot reduce. Asking for
#     "merge the weakest half" instead is well defined whatever the
#     distribution looks like: 25 onsets now yield 12-15 groups.
#   - Target_retention: a cap on the fraction of the original DURATION the
#     montage may keep. Capping the segment COUNT never bounded this,
#     because w1 rewards duration and the head DP therefore selects the
#     LONGEST groups; keeping 2 of 3 groups kept 97.5% of the flute phrase.
#     Heads are now dropped lowest-score-first until the retained span fits
#     the budget, with at least one head always surviving.
#   - The script and the engine both warn when retention exceeds 90%. This
#     failure is otherwise silent: a montage that is 97% of the input plays
#     as the input and nothing in the pipeline notices.
#   - The figure reads the resolved merge cut back out of the data rather
#     than drawing the form value as a strength level, and panel II colours
#     each stem by the decision actually recorded for it.
#
#   Measured after the fix, target retention 45%:
#     flute  10.69 s: 25 onsets -> 12-15 groups -> 3-5 spans -> 39-44% kept
#     speech 17.87 s: 42-57 onsets -> 22-30 groups -> 7-13 spans -> 40-45% kept
#
# v1.4 reviewed:
#   - INPUT MATERIAL PRESETS. Onset detection is not one problem but two.
#     A plucked or struck attack is an energy discontinuity one frame wide,
#     so the intensity derivative is informative and smoothing destroys the
#     cue. A bowed, sung or blown legato note change has no energy
#     discontinuity at all: amplitude runs straight through the note
#     boundary and the only evidence is a broad spectral ramp, which needs a
#     low threshold, a wide smoothing window and a long refractory period so
#     vibrato is not read as a series of onsets. One default cannot serve
#     both, and the previous single default was tuned for the struck case.
#     Presets set the detection parameters (threshold margin, minimum IOI,
#     flux weight, smoothing width, median window) plus a default merge
#     depth, which Merge_weakest_fraction overrides whenever it is set to a
#     real value. Grouping_style,
#     Structural_style and Reduction_density stay independent because they
#     express musical intent, not a property of the recording; pitch range
#     stays independent because it follows the instrument's register, not
#     its articulation.
#   - ANALYSIS FIGURE in the suite's standard layout: onset function with
#     the detection threshold, GPR boundary strengths against the merge
#     threshold, the pTSR head-score field, the reduction map, and the
#     montage's own spectrogram with its splice points. Panels I-IV are the
#     control domain; panel V is measured. Figure data comes from two small
#     tables written by the engine (a decimated trace and one row per raw
#     segment) rather than from the 18,000-row frame CSV, because Praat
#     Table queries cost one call per cell.
#
# v1.3: Stage 3 became internal. v1.0-v1.2 ended by calling
#   build_montage.praat through runScript, so if that script wasn't
#   installed next to this one the run stopped at splicing_edl.csv and
#   produced no audio at all.
#
# v1.2: moved all spectral work to the Python backend (house pattern:
#   Praat = orchestration, Python = DSP). The former in-Praat flux loop
#   queried a Spectrogram once per band per frame (~288,000 calls for a
#   3-minute file) and buffered ~410,000 indexed variables, which is why
#   Stage 1 could appear to hang.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Requires: Praat 6.0+ (Concatenate with overlap), Python 3 with
#           numpy + pandas.
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound      = selected("Sound")
soundName$ = selected$("Sound")

# ---- OS-SPECIFIC PYTHON DISCOVERY ----
if macintosh
    if fileReadable("/opt/homebrew/bin/python3")
        pythonCmd$ = "/opt/homebrew/bin/python3"
    elsif fileReadable("/Library/Frameworks/Python.framework/Versions/3.14/bin/python3")
        pythonCmd$ = "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3"
    elsif fileReadable("/usr/local/bin/python3")
        pythonCmd$ = "/usr/local/bin/python3"
    else
        pythonCmd$ = "python3"
    endif
elsif windows
    pythonCmd$ = "python"
else
    pythonCmd$ = "python3"
endif

# ---- PATHS ----
pluginDirRaw$ = preferencesDirectory$ + "/plugin_AudioTools/"
pluginDir$ = replace_regex$(pluginDirRaw$, "\\", "/", 0)

pythonScript$ = pluginDir$ + "py/pgttm_engine.py"
if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/pgttm_engine.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: pgttm_engine.py" + newline$ + "Expected at: " + pluginDir$ + "py/ or next to this script."
endif

# ---- FORM ----
# Style knobs are collapsed into optionmenu presets (same convention as
# PhaseSpaceComposer's Attractor_type / Weight_preset) so the form fits on
# one screen. Fine-grained numeric control is still available — edit the
# preset tables below the form instead of exposing 20 raw fields.
form Acoustic Grammar Reducer v1.7
    comment === Input material (sets onset detection) ===
    optionmenu Input_material: 3
        option Custom (use Onset settings below)
        option Staccato / plucked
        option Legato / sustained
        option Percussive / transient-dense
        option Speech / vocal
        option Continuous texture (drone, noise)
        option Mixed ensemble
    comment === Analysis ===
    real Time_step 0.01
    real Pitch_floor 75
    real Pitch_ceiling 600
    comment === Onset detection (overridden unless material is Custom) ===
    real Onset_threshold 0.35
    real Min_ioi_ms 80
    comment === Grouping (GPR 2/3) style — -1 follows the material preset ===
    optionmenu Grouping_style: 1
        option Balanced
        option Rubato-tolerant (IOI-lenient)
        option Strict-tempo (IOI-strict)
        option Timbre-focus
    real Merge_weakest_fraction -1
    comment === Structural (pTSR) style ===
    optionmenu Structural_style: 1
        option Balanced
        option Duration-favoring
        option Stability-favoring
        option Dynamics-favoring
    comment === Reduction density ===
    real Target_retention 0.45
    optionmenu Reduction_density: 2
        option Sparse (fewer, longer heads)
        option Balanced
        option Dense (more, shorter heads)
    comment === Splice ===
    real Crossfade_ms 10
    boolean Snap_to_zero_crossings 1
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
    boolean Import_analysis_TextGrid 1
    boolean Keep_intermediate_files 0
    boolean Debug 0
endform

# ---------------------------------------------------------------------------
# INPUT MATERIAL PRESETS
# ---------------------------------------------------------------------------
# Detection parameters only. Each preset answers one question: what does an
# event boundary physically look like in this kind of recording?
#
#   onset_flux_weight    how much of the decision is spectral change versus
#                        energy rise. Legato and drone material has no energy
#                        rise at note boundaries, so it must be near 1.
#   onset_smooth_frames  width of the moving average before peak-picking. A
#                        struck attack is one frame wide and is blunted by
#                        smoothing; a bowed transition is a broad ramp whose
#                        peak is unstable until smoothed.
#   min_ioi_ms           refractory period. Long for legato and drone, where
#                        vibrato and slow modulation otherwise register as a
#                        train of onsets; short for percussion.
#   onset_threshold      MARGIN a peak must clear above the LOCAL median of
#                        the onset function, not an absolute level. Struck
#                        material has a near-zero background so the two are
#                        nearly the same thing; sustained material has no
#                        quiet background at all — measured on a slurred
#                        49-note fixture the onset function's median sat at
#                        0.50 against 0.08 for a struck one — and only the
#                        local comparison separates a note change from the
#                        vibrato around it.
#   onset_median_window_s  width of that local median. Short follows the
#                        dynamics closely (percussion); long is needed for
#                        drone, where the "background" changes over seconds.
#   merge_weakest_fraction  what FRACTION of the weakest onset boundaries is
#                        merged away. A quantile, not a level — see the note
#                        on the form field below.
onset_smooth_frames = 3
onset_median_window_s = 1.0
materialMerge = 0.50
materialName$ = "Custom"

if input_material = 2
    materialName$ = "Staccato / plucked"
    onset_threshold = 0.40
    min_ioi_ms = 60
    onset_flux_weight = 0.55
    onset_smooth_frames = 1
    onset_median_window_s = 0.5
    materialMerge = 0.55

elsif input_material = 3
    materialName$ = "Legato / sustained"
    onset_threshold = 0.20
    min_ioi_ms = 180
    onset_flux_weight = 0.90
    onset_smooth_frames = 5
    onset_median_window_s = 1.0
    materialMerge = 0.42

elsif input_material = 4
    materialName$ = "Percussive / transient-dense"
    onset_threshold = 0.45
    min_ioi_ms = 40
    onset_flux_weight = 0.50
    onset_smooth_frames = 1
    onset_median_window_s = 0.5
    materialMerge = 0.60

elsif input_material = 5
    materialName$ = "Speech / vocal"
    onset_threshold = 0.28
    min_ioi_ms = 90
    onset_flux_weight = 0.60
    onset_smooth_frames = 3
    onset_median_window_s = 0.7
    materialMerge = 0.45

elsif input_material = 6
    materialName$ = "Continuous texture"
    onset_threshold = 0.30
    min_ioi_ms = 300
    onset_flux_weight = 0.95
    onset_smooth_frames = 7
    onset_median_window_s = 2.0
    materialMerge = 0.35

elsif input_material = 7
    materialName$ = "Mixed ensemble"
    onset_threshold = 0.32
    min_ioi_ms = 100
    onset_flux_weight = 0.65
    onset_smooth_frames = 3
    onset_median_window_s = 1.0
    materialMerge = 0.50

else
    # Custom: the form's own Onset_threshold / Min_ioi_ms stand, with the
    # house defaults for the parameters the form does not expose.
    onset_flux_weight = 0.60
    onset_smooth_frames = 3
    onset_median_window_s = 1.0
    materialMerge = 0.50
endif

# The material preset carries a merge depth because how many boundaries a
# recording naturally presents IS a property of the material. But a number
# typed into the form must never be silently discarded: through v1.6 the
# presets overwrote Merge_weakest_fraction outright, so a user who set 0.50
# and then chose Legato got 0.42 with no indication. -1 means "follow the
# preset"; anything in 0..1 is the user's and wins.
if merge_weakest_fraction < 0
    merge_weakest_fraction = materialMerge
    mergeSourceStr$ = "from the " + materialName$ + " preset"
else
    mergeSourceStr$ = "set on the form"
endif

# ---- FIXED ANALYSIS CONSTANTS ----
formant_max_number  = 4
formant_ceiling     = 5500
spectral_bins       = 16
spectral_max_freq   = 5000
zero_crossing_window_ms = 5
trace_points        = 1200

# CSV rows are accumulated in a string and flushed every csvFlushEvery rows.
# Per-row appendFileLine would mean one open/append/close cycle per frame
# (18,000+ on a 3-minute file); an unbounded buffer would make Praat's string
# concatenation quadratic. A few hundred rows per flush sits in the flat part
# of both curves.
csvFlushEvery = 250

# ---- ARTIFACT PATHS ----
# Scratch by default: the deliverable is the Sound object, not a pile of files
# next to the script. Keep_intermediate_files puts them in the working
# directory instead and leaves them there.
if keep_intermediate_files
    outDir$ = defaultDirectory$ + "/"
else
    outDir$ = temporaryDirectory$ + "/"
endif

featuresCsv$  = outDir$ + "acoustic_features.csv"
gttmTextGrid$ = outDir$ + "gttm_output.TextGrid"
splicingEdl$  = outDir$ + "splicing_edl.csv"
traceCsv$     = outDir$ + "pgttm_trace.csv"
segmentsCsv$  = outDir$ + "pgttm_segments.csv"
analysisWav$  = temporaryDirectory$ + "/temp_pgttm_analysis.wav"
probeMarker$  = temporaryDirectory$ + "/temp_pgttm_probe.ok"

# Enforce forward slashes for all paths passed to python
pythonScriptJ$ = replace_regex$(pythonScript$, "\\", "/", 0)
featuresCsvJ$  = replace_regex$(featuresCsv$, "\\", "/", 0)
gttmTgJ$       = replace_regex$(gttmTextGrid$, "\\", "/", 0)
splicingEdlJ$  = replace_regex$(splicingEdl$, "\\", "/", 0)
traceCsvJ$     = replace_regex$(traceCsv$, "\\", "/", 0)
segmentsCsvJ$  = replace_regex$(segmentsCsv$, "\\", "/", 0)
analysisWavJ$  = replace_regex$(analysisWav$, "\\", "/", 0)
probeMarkerJ$  = replace_regex$(probeMarker$, "\\", "/", 0)

# ---- CLEANUP PROCEDURES ----
# Scratch that never survives a run, whatever happens.
procedure cleanUpScratch
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
    if fileReadable(analysisWav$)
        deleteFile: analysisWav$
    endif
endproc

# Pipeline artifacts — removed once the montage and figure exist, unless the
# user asked to keep them. Called only on success; a failed run leaves them in
# place so the failure can be diagnosed.
procedure cleanUpArtifacts
    if not keep_intermediate_files
        if fileReadable(featuresCsv$)
            deleteFile: featuresCsv$
        endif
        if fileReadable(gttmTextGrid$)
            deleteFile: gttmTextGrid$
        endif
        if fileReadable(splicingEdl$)
            deleteFile: splicingEdl$
        endif
        if fileReadable(traceCsv$)
            deleteFile: traceCsv$
        endif
        if fileReadable(segmentsCsv$)
            deleteFile: segmentsCsv$
        endif
    endif
endproc

@cleanUpScratch

# ---- MAP Grouping_style -> GPR weights ----
if grouping_style = 1
    gpr_ioi_weight = 1.0
    gpr_pitch_weight = 1.0
    gpr_dynamic_weight = 1.0
    gpr_timbre_weight = 1.0
    groupingStyleStr$ = "Balanced"
elsif grouping_style = 2
    gpr_ioi_weight = 0.4
    gpr_pitch_weight = 1.2
    gpr_dynamic_weight = 1.2
    gpr_timbre_weight = 1.2
    groupingStyleStr$ = "Rubato-tolerant"
elsif grouping_style = 3
    gpr_ioi_weight = 2.0
    gpr_pitch_weight = 0.8
    gpr_dynamic_weight = 0.8
    gpr_timbre_weight = 0.8
    groupingStyleStr$ = "Strict-tempo"
else
    gpr_ioi_weight = 0.6
    gpr_pitch_weight = 0.8
    gpr_dynamic_weight = 0.8
    gpr_timbre_weight = 2.0
    groupingStyleStr$ = "Timbre-focus"
endif

# ---- MAP Structural_style -> pTSR weights (w1=duration, w2=pitch ----
# ---- stability, w3=intensity peak, w4=pitch-variance penalty) ----
if structural_style = 1
    w1_duration = 1.0
    w2_pitch_stability = 1.0
    w3_intensity_peak = 1.0
    w4_pitch_variance = 0.5
    structuralStyleStr$ = "Balanced"
elsif structural_style = 2
    w1_duration = 2.0
    w2_pitch_stability = 0.7
    w3_intensity_peak = 0.7
    w4_pitch_variance = 0.3
    structuralStyleStr$ = "Duration-favoring"
elsif structural_style = 3
    w1_duration = 0.6
    w2_pitch_stability = 2.0
    w3_intensity_peak = 0.8
    w4_pitch_variance = 1.0
    structuralStyleStr$ = "Stability-favoring"
else
    w1_duration = 0.6
    w2_pitch_stability = 0.7
    w3_intensity_peak = 2.0
    w4_pitch_variance = 0.3
    structuralStyleStr$ = "Dynamics-favoring"
endif

# ---- MAP Reduction_density -> level fractions + DP min-gap spacing ----
if reduction_density = 1
    level0_fraction = 0.08
    level1_fraction = 0.22
    level2_fraction = 0.30
    min_anchor_gap_s = 0.80
    min_head_gap_s = 0.35
    reductionDensityStr$ = "Sparse"
elsif reduction_density = 2
    level0_fraction = 0.15
    level1_fraction = 0.35
    level2_fraction = 0.30
    min_anchor_gap_s = 0.40
    min_head_gap_s = 0.15
    reductionDensityStr$ = "Balanced"
else
    level0_fraction = 0.25
    level1_fraction = 0.45
    level2_fraction = 0.30
    min_anchor_gap_s = 0.20
    min_head_gap_s = 0.08
    reductionDensityStr$ = "Dense"
endif

# ---- CLAMP PARAMETERS ----
if time_step < 0.002
    time_step = 0.002
endif
if time_step > 0.05
    time_step = 0.05
endif
if pitch_floor < 25
    pitch_floor = 25
endif
if pitch_ceiling <= pitch_floor
    pitch_ceiling = pitch_floor + 50
endif
if onset_threshold < 0
    onset_threshold = 0
endif
if onset_threshold > 1
    onset_threshold = 1
endif
if min_ioi_ms < 10
    min_ioi_ms = 10
endif
if onset_smooth_frames < 1
    onset_smooth_frames = 1
endif
if onset_median_window_s < 0
    onset_median_window_s = 0
endif
if onset_median_window_s > 10
    onset_median_window_s = 10
endif
if merge_weakest_fraction > 1
    merge_weakest_fraction = 1
endif
if target_retention < 0.02
    target_retention = 0.02
endif
if target_retention > 1
    target_retention = 1
endif
if crossfade_ms < 0
    crossfade_ms = 0
endif
if crossfade_ms > 200
    crossfade_ms = 200
endif

# Level fractions must sum to <= 1 (the remainder is implicitly Level 3).
# Renormalize rather than fail outright — a bad fraction split shouldn't abort
# a long extraction; the engine reports the fractions actually achieved so a
# mismatch is easy to spot.
fracSum = level0_fraction + level1_fraction + level2_fraction
if fracSum > 1.0
    level0_fraction = level0_fraction / fracSum
    level1_fraction = level1_fraction / fracSum
    level2_fraction = level2_fraction / fracSum
    fracWarning$ = " (renormalized — requested fractions summed above 1.0)"
else
    fracWarning$ = ""
endif

# ---- INFO HEADER ----
clearinfo
writeInfoLine:  "=== Acoustic Grammar Reducer v1.7 ==="
appendInfoLine: "Input: ", soundName$
appendInfoLine: "Material preset: ", materialName$
appendInfoLine: "Time step: ", time_step, " s | Pitch: ", pitch_floor, "-", pitch_ceiling, " Hz"
appendInfoLine: "Onset: margin=", fixed$(onset_threshold, 2), " over a ",
... fixed$(onset_median_window_s, 1), " s local median | min_IOI=", min_ioi_ms,
... " ms | flux_w=", fixed$(onset_flux_weight, 2), " | smooth=", onset_smooth_frames, " frames"
appendInfoLine: "Grouping: ", groupingStyleStr$, " (merging the weakest ",
... fixed$(100 * merge_weakest_fraction, 0), "% of boundaries, ", mergeSourceStr$,
... ") | Structural: ", structuralStyleStr$,
... " | Density: ", reductionDensityStr$, " | Retention cap: ", fixed$(100 * target_retention, 0), "%"
appendInfoLine: "Level targets: L0=", fixed$(level0_fraction, 2), " L1=", fixed$(level1_fraction, 2),
... " L2=", fixed$(level2_fraction, 2), fracWarning$
appendInfoLine: ""

# ---- CAPTURE ORIGINAL STATS ----
selectObject: sound
dur       = Get total duration
sr        = Get sampling frequency
nChannels = Get number of channels

appendInfoLine: "Duration: ", fixed$(dur, 2), " s | SR: ", sr, " Hz | Ch: ", nChannels

# Representative-channel policy: never average stereo/multichannel channels for
# analysis, because anti-phase material can cancel and create a fictitious
# "silent" analysis signal. Choose the whole-file strongest-RMS real channel,
# same house convention used across the suite. This affects ANALYSIS only — the
# montage is spliced from the original Sound, so it keeps every channel.
analysisChannel = 1
if nChannels > 1
    bestChannelRms = -1
    for ch from 1 to nChannels
        selectObject: sound
        Extract one channel: ch
        probeCh = selected("Sound")
        chRms = Get root-mean-square: 0, 0
        if chRms > bestChannelRms
            bestChannelRms = chRms
            analysisChannel = ch
        endif
        removeObject: probeCh
    endfor
    selectObject: sound
    Extract one channel: analysisChannel
    analysisMono = selected("Sound")
else
    selectObject: sound
    Copy: "gttm_analysisMono"
    analysisMono = selected("Sound")
endif
appendInfoLine: "Analysis channel: ", analysisChannel, " (strongest RMS real channel)"
appendInfoLine: ""

# ===========================================================================
# Stage 0 — Detect Python Dependencies
# ===========================================================================
# Checked up front, before any analysis work, and with a targeted install hint
# — a missing pandas/numpy otherwise fails silently deep inside
# pgttm_engine.py later, and "check terminal" is no help if Praat was launched
# by double-click with no terminal open.
appendInfoLine: "Checking Python dependencies (numpy, pandas)..."

probeCmd$ = pythonCmd$ + " -c ""import numpy, pandas; open('""" + probeMarkerJ$ + """', 'w').write('ok')"""
runSystem_nocheck: probeCmd$

if not fileReadable(probeMarker$)
    removeObject: analysisMono
    @cleanUpScratch
    exitScript: "Python not found, or numpy/pandas missing." + newline$ + "Please install: pip install numpy pandas"
endif
deleteFile: probeMarker$
appendInfoLine: "  Python found: ", pythonCmd$
appendInfoLine: ""

# ===========================================================================
# Stage 1a — Run analyses on the representative channel
# ===========================================================================
# No Spectrogram is built here. Everything spectral is Stage 2's job, from the
# exported WAV, in numpy.
appendInfoLine: "[1/5] Running Pitch / Formant / Intensity analyses..."

selectObject: analysisMono
To Pitch: time_step, pitch_floor, pitch_ceiling
pitchObj = selected("Pitch")

selectObject: analysisMono
To Formant (burg): time_step, formant_max_number, formant_ceiling, 0.025, 50
formantObj = selected("Formant")

selectObject: analysisMono
To Intensity: pitch_floor, time_step, "yes"
intensityObj = selected("Intensity")

# ===========================================================================
# Stage 1b — Export the analysis channel for the Python DSP backend
# ===========================================================================
# Peak-scaled on a throwaway copy: Praat writes 16-bit PCM, so a source with
# peaks above full scale would clip on export. Flux is normalized in Stage 2
# anyway, and intensity_db below comes from the *unscaled* Intensity object, so
# this changes nothing measured — it only protects the waveform Python sees.
appendInfoLine: "[2/5] Exporting analysis channel for the Python DSP stage..."

selectObject: analysisMono
Copy: "gttm_exportCopy"
exportCopy = selected("Sound")
Scale peak: 0.99
Save as WAV file: analysisWav$
removeObject: exportCopy

if not fileReadable(analysisWav$)
    removeObject: analysisMono, pitchObj, formantObj, intensityObj
    @cleanUpScratch
    exitScript: "Could not write the temporary analysis WAV to:" + newline$ + analysisWav$
endif

# ===========================================================================
# Stage 1c — Single streaming pass: sample frames, write CSV
# ===========================================================================
# One pass, no indexed arrays. v1.0/v1.1 buffered ~23 indexed variables per
# frame (frameBand alone was nFrames x 16) and then made a second pass to write
# them out; indexed variables are hash-table entries keyed by a formatted name,
# so that buffering cost more than the querying did. Rows are built and flushed
# directly instead.
appendInfoLine: "[3/5] Sampling frames at ", time_step, " s..."

nFrames = floor(dur / time_step) + 1
referenceHz = 100.0

writeFileLine: featuresCsv$, "frame,time_s,f0_hz,voiced,f0_cents,f1_hz,f1_bw,f2_hz,f2_bw,f3_hz,f3_bw,f4_hz,f4_bw,intensity_db"

csvBuffer$ = ""
bufferedRows = 0

for i from 1 to nFrames
    t = (i - 1) * time_step
    if t > dur
        t = dur
    endif

    # ---- Pitch ----
    selectObject: pitchObj
    f0 = Get value at time: t, "Hertz", "Linear"
    if f0 = undefined
        voicedFlag = 0
        f0Hz  = 0
        cents = 0
    else
        voicedFlag = 1
        f0Hz  = f0
        cents = 1200 * log2(f0 / referenceHz)
    endif

    # ---- Formants (frequency + bandwidth, F1-F4) ----
    selectObject: formantObj
    f1Hz = Get value at time: 1, t, "Hertz", "Linear"
    f1Bw = Get bandwidth at time: 1, t, "Hertz", "Linear"
    f2Hz = Get value at time: 2, t, "Hertz", "Linear"
    f2Bw = Get bandwidth at time: 2, t, "Hertz", "Linear"
    f3Hz = Get value at time: 3, t, "Hertz", "Linear"
    f3Bw = Get bandwidth at time: 3, t, "Hertz", "Linear"
    f4Hz = Get value at time: 4, t, "Hertz", "Linear"
    f4Bw = Get bandwidth at time: 4, t, "Hertz", "Linear"
    if f1Hz = undefined
        f1Hz = 0
    endif
    if f1Bw = undefined
        f1Bw = 0
    endif
    if f2Hz = undefined
        f2Hz = 0
    endif
    if f2Bw = undefined
        f2Bw = 0
    endif
    if f3Hz = undefined
        f3Hz = 0
    endif
    if f3Bw = undefined
        f3Bw = 0
    endif
    if f4Hz = undefined
        f4Hz = 0
    endif
    if f4Bw = undefined
        f4Bw = 0
    endif

    # ---- Intensity ----
    selectObject: intensityObj
    dB = Get value at time: t, "Cubic"
    if dB = undefined
        dB = 0
    endif

    row$ = string$(i) + "," + fixed$(t, 6) + ","
    ...+ fixed$(f0Hz, 4) + "," + string$(voicedFlag) + "," + fixed$(cents, 4) + ","
    ...+ fixed$(f1Hz, 2) + "," + fixed$(f1Bw, 2) + ","
    ...+ fixed$(f2Hz, 2) + "," + fixed$(f2Bw, 2) + ","
    ...+ fixed$(f3Hz, 2) + "," + fixed$(f3Bw, 2) + ","
    ...+ fixed$(f4Hz, 2) + "," + fixed$(f4Bw, 2) + ","
    ...+ fixed$(dB, 4)

    csvBuffer$ = csvBuffer$ + row$ + newline$
    bufferedRows += 1

    if bufferedRows >= csvFlushEvery
        appendFile: featuresCsv$, csvBuffer$
        csvBuffer$ = ""
        bufferedRows = 0
    endif

    if i mod 2000 = 0
        appendInfoLine: "  ...", i, " / ", nFrames, " frames"
    endif
endfor

if bufferedRows > 0
    appendFile: featuresCsv$, csvBuffer$
    csvBuffer$ = ""
    bufferedRows = 0
endif

removeObject: analysisMono, pitchObj, formantObj, intensityObj

appendInfoLine: "  ", nFrames, " frames analysed"
appendInfoLine: ""

# ===========================================================================
# Stage 2 — pGTTM Engine (Python): onsets + grouping + reduction
# ===========================================================================
appendInfoLine: "[4/5] Running pgttm_engine.py (onset detection + pGTTM grammar)..."

debugFlag$ = ""
if debug
    debugFlag$ = " --debug"
endif

# Figure tables are requested only when the figure will be drawn: they are
# cheap, but there is no reason to write files nothing reads.
figureArgs$ = ""
if draw_visualization
    figureArgs$ = " --out_trace """ + traceCsvJ$ + """"
    ... + " --out_segments """ + segmentsCsvJ$ + """"
    ... + " --trace_points " + string$(trace_points)
endif

pythonCall$ = pythonCmd$ + " """ + pythonScriptJ$ + """"
    ... + " --features """     + featuresCsvJ$ + """"
    ... + " --audio """        + analysisWavJ$ + """"
    ... + " --sound_name """   + soundName$     + """"
    ... + " --duration "       + fixed$(dur, 6)
    ... + " --time_step "      + fixed$(time_step, 6)
    ... + " --out_textgrid """ + gttmTgJ$      + """"
    ... + " --out_edl """      + splicingEdlJ$ + """"
    ... + " --onset_threshold "     + fixed$(onset_threshold, 4)
    ... + " --min_ioi_ms "          + fixed$(min_ioi_ms, 4)
    ... + " --onset_flux_weight "   + fixed$(onset_flux_weight, 4)
    ... + " --onset_smooth_frames " + string$(onset_smooth_frames)
    ... + " --onset_median_window_s " + fixed$(onset_median_window_s, 4)
    ... + " --spectral_bins "       + string$(spectral_bins)
    ... + " --spectral_max_freq "   + fixed$(spectral_max_freq, 2)
    ... + " --gpr_ioi_weight "     + fixed$(gpr_ioi_weight, 4)
    ... + " --gpr_pitch_weight "   + fixed$(gpr_pitch_weight, 4)
    ... + " --gpr_dynamic_weight " + fixed$(gpr_dynamic_weight, 4)
    ... + " --gpr_timbre_weight "  + fixed$(gpr_timbre_weight, 4)
    ... + " --merge_weakest_fraction " + fixed$(merge_weakest_fraction, 4)
    ... + " --target_retention " + fixed$(target_retention, 4)
    ... + " --w1 " + fixed$(w1_duration, 4)
    ... + " --w2 " + fixed$(w2_pitch_stability, 4)
    ... + " --w3 " + fixed$(w3_intensity_peak, 4)
    ... + " --w4 " + fixed$(w4_pitch_variance, 4)
    ... + " --level0_frac " + fixed$(level0_fraction, 4)
    ... + " --level1_frac " + fixed$(level1_fraction, 4)
    ... + " --level2_frac " + fixed$(level2_fraction, 4)
    ... + " --min_anchor_gap_s " + fixed$(min_anchor_gap_s, 4)
    ... + " --min_head_gap_s "   + fixed$(min_head_gap_s, 4)
    ... + figureArgs$
    ... + debugFlag$

# Remove any stale outputs from a PREVIOUS run before calling Python. The
# output paths are fixed, so without this, a crashed run would leave the old
# TextGrid/EDL in place and the fileReadable() check below would pass on stale
# data — silently splicing a previous analysis of a different file instead of
# failing clearly.
if fileReadable(gttmTextGrid$)
    deleteFile: gttmTextGrid$
endif
if fileReadable(splicingEdl$)
    deleteFile: splicingEdl$
endif
if fileReadable(traceCsv$)
    deleteFile: traceCsv$
endif
if fileReadable(segmentsCsv$)
    deleteFile: segmentsCsv$
endif

runSystem_nocheck: pythonCall$

if not fileReadable(gttmTextGrid$) or not fileReadable(splicingEdl$)
    @cleanUpScratch
    exitScript: "pgttm_engine.py failed — no TextGrid / EDL written." + newline$
    ...+ "Intermediate files left in: " + outDir$ + newline$
    ...+ "Run again with Debug on and check the terminal for details."
endif

# The scratch WAV has done its job.
if debug
    appendInfoLine: "  Debug on — keeping analysis WAV: ", analysisWav$
else
    @cleanUpScratch
endif

# ===========================================================================
# Stage 3 — Splice the retained structural spans into a new Sound
# ===========================================================================
# This is the deliverable. Spans come from splicing_edl.csv (Level 0 Anchors +
# Level 1 Heads, already in time order and non-overlapping) and are cut from
# the ORIGINAL Sound, so the montage keeps the source's channel count and
# sample rate.
appendInfoLine: "[5/5] Splicing retained spans into a montage..."

Read Table from comma-separated file: splicingEdl$
edlTable = selected("Table")
nSpans = Get number of rows

if nSpans = 0
    removeObject: edlTable
    exitScript: "The EDL is empty — nothing survived the reduction, so there is "
    ...+ "no audio to build." + newline$
    ...+ "Lower Onset_threshold or Boundary_threshold, or choose the Dense "
    ...+ "Reduction_density preset."
endif

zeroWin = zero_crossing_window_ms / 1000

nKept = 0
minChunkDur = 1e30
totalKeptDur = 0

for r from 1 to nSpans
    selectObject: edlTable
    tStart = Get value: r, "start_s"
    tEnd   = Get value: r, "end_s"

    # Snap cut points to the nearest zero crossing within a small window.
    # Cutting mid-cycle is what produces a click at every join; the window
    # keeps the snap from dragging a boundary somewhere musically different
    # when the region is quiet and crossings are sparse.
    if snap_to_zero_crossings
        selectObject: sound
        # Snap on the ANALYSIS channel, not channel 1. The EDL boundaries were
        # derived from the strongest-RMS channel, so on a stereo file where
        # channel 2 won, snapping to channel 1 moved the cut to a crossing of
        # a channel the analysis never saw — which is a click generator, not a
        # click remover. A cut can only be zero-aligned in one channel of a
        # multichannel file anyway; the analysis channel is the defensible one.
        zStart = Get nearest zero crossing: analysisChannel, tStart
        zEnd   = Get nearest zero crossing: analysisChannel, tEnd
        if zStart <> undefined
            if abs(zStart - tStart) <= zeroWin
                tStart = zStart
            endif
        endif
        if zEnd <> undefined
            if abs(zEnd - tEnd) <= zeroWin
                tEnd = zEnd
            endif
        endif
    endif

    # Clamp into the file and drop anything that collapsed to nothing.
    if tStart < 0
        tStart = 0
    endif
    if tEnd > dur
        tEnd = dur
    endif

    if tEnd - tStart > 0.001
        selectObject: sound
        Extract part: tStart, tEnd, "rectangular", 1, "no"
        nKept += 1
        chunk[nKept] = selected("Sound")
        chunkDur = Get total duration
        chunkLen[nKept] = chunkDur
        totalKeptDur = totalKeptDur + chunkDur
        if chunkDur < minChunkDur
            minChunkDur = chunkDur
        endif
    endif
endfor

removeObject: edlTable

if nKept = 0
    exitScript: "Every EDL span collapsed to zero length after clamping — "
    ...+ "nothing to splice."
endif

# The crossfade must be shorter than the shortest chunk, or the overlap
# swallows a whole segment. Clamped to 45% of the shortest span rather than
# failing, and the clamp is reported so a silently-shortened crossfade isn't
# mistaken for the requested one.
overlap = crossfade_ms / 1000
maxOverlap = minChunkDur * 0.45
crossfadeNote$ = ""
if overlap > maxOverlap
    overlap = maxOverlap
    crossfadeNote$ = " (clamped from " + fixed$(crossfade_ms, 1) + " ms — shortest span is "
    ...+ fixed$(minChunkDur * 1000, 1) + " ms)"
endif

selectObject: chunk[1]
for r from 2 to nKept
    plusObject: chunk[r]
endfor

if nKept = 1
    # A single span is already the montage; concatenating one object would
    # only cost an extra copy.
    montage = chunk[1]
elsif overlap > 0.0005
    Concatenate with overlap: overlap
    montage = selected("Sound")
    for r from 1 to nKept
        removeObject: chunk[r]
    endfor
else
    Concatenate
    montage = selected("Sound")
    for r from 1 to nKept
        removeObject: chunk[r]
    endfor
endif

selectObject: montage
Rename: soundName$ + "_pGTTM_Skeleton_Montage"
montageDur = Get total duration
montagePeak = Get absolute extremum: 0, 0, "None"
montageRms = Get root-mean-square: 0, 0

# Splice positions ON THE MONTAGE TIMELINE, for the figure. After k chunks the
# montage runs to sum(dur[1..k]) - (k-1)*overlap, and the crossfade into chunk
# k+1 occupies the last `overlap` of that, so its centre is half an overlap
# earlier.
spliceCount = 0
runningLen = 0
for r from 1 to nKept
    runningLen = runningLen + chunkLen[r]
    if r < nKept
        spliceCount += 1
        spliceAt[spliceCount] = runningLen - (r - 1) * overlap - overlap / 2
    endif
endfor

# ---- Optionally bring the analysis TextGrid into the object list ----
# Its times refer to the ORIGINAL sound, not the montage — select it together
# with the source Sound to inspect the grammar, not with the montage.
if import_analysis_TextGrid
    Read from file: gttmTextGrid$
    tgObj = selected("TextGrid")
    Rename: soundName$ + "_pGTTM_analysis"
endif

# ===========================================================================
# Stage 4 — Analysis figure
# ===========================================================================
if draw_visualization
    if fileReadable(traceCsv$) and fileReadable(segmentsCsv$)
        @drawPgttmFigure
    else
        appendInfoLine: "  Figure skipped — the engine did not write "
        ...+ "pgttm_trace.csv / pgttm_segments.csv."
    endif
endif

# ---- Artifacts have served their purpose; the objects are the result ----
@cleanUpArtifacts

# ---- REPORT ----
appendInfoLine: "  Spans spliced: ", nKept, " of ", nSpans, " EDL rows"
appendInfoLine: "  Crossfade: ", fixed$(overlap * 1000, 1), " ms", crossfadeNote$
appendInfoLine: "  Montage duration: ", fixed$(montageDur, 2), " s of ", fixed$(dur, 2),
...  " s original (", fixed$(100 * montageDur / dur, 1), "% retained, cap ",
...  fixed$(100 * target_retention, 0), "%)"
if montageDur > 0.90 * dur
    appendInfoLine: ""
    appendInfoLine: "  WARNING: the montage keeps ", fixed$(100 * montageDur / dur, 1),
    ...  "% of the original — it will sound close to the input."
    appendInfoLine: "  Lower Target_retention, or lower Merge_weakest_fraction so more"
    appendInfoLine: "  boundaries survive and the reduction has more groups to choose between."
endif
appendInfoLine: ""
appendInfoLine: "Created Sound: ", soundName$, "_pGTTM_Skeleton_Montage"
if import_analysis_TextGrid
    appendInfoLine: "Created TextGrid: ", soundName$, "_pGTTM_analysis (times refer to the original Sound)"
endif
if keep_intermediate_files
    appendInfoLine: "Intermediate files kept in: ", outDir$
endif
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="

selectObject: montage
if play_result
    Play
endif

# ===========================================================================
# FIGURE
# ===========================================================================
# Standard suite layout: 0.60-7.70 text column, panel bodies indented to 0.90
# where they carry a left axis, ##bold## section headers at font 8 with a faint
# right-aligned caption, grey summary strip at the foot, note strip below it.
#
# Domain discipline, stated in the figure: panels I-III show the CONTROL field
# — the evidence the grammar acted on. Panel IV is the reduction itself. Panel
# V is MEASURED, the spectrogram of the audio actually produced, so the formal
# layer stays anchored to the sound.
#
# Drawing-order discipline: `Text:` and `Draw inner box` leave the drawing
# frame on the OUTER viewport and a later `Axes:` does not restore it, so every
# panel re-selects its inner viewport between drawing groups.
# ---------------------------------------------------------------------------
procedure drawPgttmFigure
    # -----------------------------------------------------------------------
    # LIBRARY PALETTE. Same tones as Perceptual_Graph and
    # CWT_Granular_Resampler so figures from different scripts in the suite
    # sit together on a page. Nothing in the figure is drawn in black: black
    # reads as "default", and in a figure where colour carries the reduction
    # level it also competes with the darkest category.
    #
    # Structural greys:
    #   ink   titles and section headers
    #   label axis labels and data ink
    #   faint captions, notes, panel boxes
    #   grid  ticks and rules
    #   panel plot-area fill
    #   sumBg summary strip
    .ink$    = "{0.25, 0.25, 0.35}"
    .label$  = "{0.35, 0.35, 0.50}"
    .faint$  = "{0.55, 0.55, 0.62}"
    .grid$   = "{0.80, 0.80, 0.80}"
    .panel$  = "{0.97, 0.97, 0.97}"
    .sumBg$  = "{0.94, 0.94, 0.94}"
    #
    # Categorical set, in the library's order. The reduction levels take the
    # first three so the ranking reads as red > blue > green, and the
    # discarded level takes the light variant of the last, which recedes
    # instead of asserting a fourth category.
    .cat1$   = "{0.85, 0.35, 0.35}"
    .cat2$   = "{0.35, 0.55, 0.85}"
    .cat3$   = "{0.35, 0.75, 0.45}"
    .cat2L$  = "{0.75, 0.85, 0.95}"
    .l0col$  = .cat1$
    .l1col$  = .cat2$
    .l2col$  = .cat3$
    .l3col$  = "{0.82, 0.88, 0.78}"
    # accent carries thresholds, merge cuts and splice marks
    .accent$ = .cat1$
    .left = 0.90
    .right = 7.70

    if dur <= 10
        .tTick = 1
    elsif dur <= 30
        .tTick = 5
    elsif dur <= 120
        .tTick = 20
    else
        .tTick = 60
    endif

    # -----------------------------------------------------------------------
    # Load the two figure tables. These exist precisely so this procedure
    # never touches the 18,000-row frame CSV: Praat Table access is one call
    # per cell, so a full-resolution redraw would cost more than the analysis.
    # -----------------------------------------------------------------------
    Read Table from comma-separated file: traceCsv$
    .trace = selected("Table")
    .nTrace = Get number of rows

    selectObject: .trace
    for .k to .nTrace
        trT[.k] = Get value: .k, "time_s"
        trV[.k] = Get value: .k, "onset_fn"
        trThr[.k] = Get value: .k, "thr_curve"
    endfor

    Read Table from comma-separated file: segmentsCsv$
    .segs = selected("Table")
    .nSeg = Get number of rows
    selectObject: .segs

    .nGroups = 0
    .minGroupDur = 1e30
    .maxGroupDur = 0
    .nL0 = 0
    .nL1 = 0
    .nL2 = 0
    .nL3 = 0
    .nSurvived = 0
    .cutLine = 1e30

    for .i to .nSeg
        segStart[.i] = Get value: .i, "start_s"
        segGpr[.i]   = Get value: .i, "gpr_strength"
        segKept[.i]  = Get value: .i, "boundary_kept"
        segLev[.i]   = Get value: .i, "level_id"
        segScore[.i] = Get value: .i, "score"
        segGs[.i]    = Get value: .i, "group_start_s"
        segGe[.i]    = Get value: .i, "group_end_s"

        # The merge cut is a quantile resolved inside the engine, so the
        # figure must read it back out of the data rather than assume the
        # form value is a strength level. boundary_kept already records the
        # decision; the lowest strength among kept boundaries IS the cut.
        if .i > 1 and segKept[.i] = 1
            .nSurvived += 1
            if segGpr[.i] < .cutLine
                .cutLine = segGpr[.i]
            endif
        endif

        if segKept[.i] = 1
            .nGroups += 1
            .gd = segGe[.i] - segGs[.i]
            if .gd < .minGroupDur
                .minGroupDur = .gd
            endif
            if .gd > .maxGroupDur
                .maxGroupDur = .gd
            endif
            if segLev[.i] = 0
                .nL0 += 1
            elsif segLev[.i] = 1
                .nL1 += 1
            elsif segLev[.i] = 2
                .nL2 += 1
            else
                .nL3 += 1
            endif
        endif
    endfor

    if .cutLine > 1e29
        .cutLine = 0
    endif
    if .minGroupDur >= .maxGroupDur or .minGroupDur <= 0
        .minGroupDur = 0.05
        .maxGroupDur = max(0.10, .maxGroupDur)
    endif
    .logLo = ln(.minGroupDur) - 0.15
    .logHi = ln(.maxGroupDur) + 0.15

    Erase all
    Solid line
    Line width: 1

    # =======================================================================
    # TITLE
    # =======================================================================
    Select inner viewport: 0.60, 7.70, 0.12, 0.52
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: .ink$
    Text: 0.5, "centre", 0.76, "half", "##pGTTM SKELETON MONTAGE — " + soundName$ + "##"
    Font size: 6
    Colour: .faint$
    Text: 0.5, "centre", 0.28, "half",
        ... materialName$ + "  |  " + groupingStyleStr$ + "  |  " + structuralStyleStr$
        ... + "  |  " + reductionDensityStr$ + " density  |  " + fixed$(dur, 1) + " s in, "
        ... + fixed$(montageDur, 1) + " s out"
    Text: 0.5, "centre", 0.04, "half",
        ... "probabilistic grouping and time-span reduction over the measured onset field; "
        ... + "panels I-III control domain, IV the reduction, V the audio produced"

    # =======================================================================
    # I. ONSET DETECTION FUNCTION
    # =======================================================================
    Select inner viewport: 0.60, 7.70, 0.86, 1.04
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: .ink$
    Text: 0.0, "left", 0.5, "half", "##I  ONSET DETECTION FUNCTION##"
    Font size: 5
    Colour: .faint$
    Text: 1.0, "right", 0.5, "half",
        ... "control field  —  flux/dB mix at " + fixed$(onset_flux_weight, 2)
        ... + ", smoothed over " + string$(onset_smooth_frames)
        ... + " frames; red = adaptive threshold; ticks below = accepted onsets"

    Select inner viewport: .left, .right, 1.10, 1.96
    Axes: 0, dur, 0, 1.05
    Paint rectangle: .panel$, 0, dur, 0, 1.05
    Colour: .label$
    Line width: 0.5
    for .k from 2 to .nTrace
        Draw line: trT[.k - 1], trV[.k - 1], trT[.k], trV[.k]
    endfor

    # The threshold is a curve, not a level: a peak must clear the local
    # median of the onset function by Onset_threshold. Drawing it flat would
    # misrepresent every decision the detector made on sustained material.
    Select inner viewport: .left, .right, 1.10, 1.96
    Axes: 0, dur, 0, 1.05
    Colour: .accent$
    Line width: 1
    for .k from 2 to .nTrace
        Draw line: trT[.k - 1], trThr[.k - 1], trT[.k], trThr[.k]
    endfor
    Font size: 5
    Text: dur, "right", trThr[.nTrace] + 0.07, "half",
        ... "median + " + fixed$(onset_threshold, 2)

    # Accepted onsets. Every raw segment starts at one, so the segment table
    # doubles as the onset list.
    Select inner viewport: .left, .right, 1.10, 1.96
    Axes: 0, dur, 0, 1.05
    Colour: .l1col$
    Line width: 0.5
    for .i to .nSeg
        Draw line: segStart[.i], 0, segStart[.i], 0.07
    endfor

    Select inner viewport: .left, .right, 1.10, 1.96
    Axes: 0, dur, 0, 1.05
    Colour: .faint$
    Line width: 1
    Draw inner box
    Font size: 5
    Marks left: 3, "yes", "yes", "no"
    Marks bottom every: 1, .tTick, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "onset function"
    Text bottom: "yes", "Time (s)"

    # =======================================================================
    # II. GPR BOUNDARY STRENGTH        III. pTSR HEAD-SCORE FIELD
    # =======================================================================
    Select inner viewport: 0.60, 3.85, 2.26, 2.44
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: .ink$
    Text: 0.0, "left", 0.5, "half", "##II  GPR BOUNDARY STRENGTH##"

    Select inner viewport: 4.20, 7.70, 2.26, 2.44
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: .ink$
    Text: 0.0, "left", 0.5, "half", "##III  pTSR HEAD-SCORE FIELD##"

    # --- II: one stem per raw boundary, dark above the merge threshold ---
    Select inner viewport: 1.10, 3.85, 2.78, 4.00
    Axes: 0, dur, 0, 1.05
    Paint rectangle: .panel$, 0, dur, 0, 1.05
    Line width: 0.5
    for .i from 2 to .nSeg
        if segGpr[.i] >= 0
            if segKept[.i] = 1
                Colour: .cat2$
            else
                Colour: .cat2L$
            endif
            Draw line: segStart[.i], 0, segStart[.i], segGpr[.i]
        endif
    endfor

    Select inner viewport: 1.10, 3.85, 2.78, 4.00
    Axes: 0, dur, 0, 1.05
    Colour: .accent$
    Dashed line
    Line width: 1
    Draw line: 0, .cutLine, dur, .cutLine
    Solid line
    Font size: 5
    Text: dur, "right", .cutLine + 0.06, "half", "cut " + fixed$(.cutLine, 3)

    Select inner viewport: 1.10, 3.85, 2.78, 4.00
    Axes: 0, dur, 0, 1.05
    Colour: .faint$
    Line width: 1
    Draw inner box
    Font size: 5
    Marks left: 3, "yes", "yes", "no"
    Marks bottom every: 1, .tTick, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "boundary strength"
    Text bottom: "yes", "Time (s)"
    Font size: 5
    Colour: .faint$
    Text: 0.5 * dur, "centre", 1.16, "half",
        ... "weakest " + fixed$(100 * merge_weakest_fraction, 0) + "% merged  —  "
        ... + string$(.nSurvived) + " of " + string$(.nSeg - 1) + " boundaries kept"

    # --- III: duration vs head score, one dot per merged group ---
    Select inner viewport: 4.70, 7.55, 2.78, 4.00
    Axes: .logLo, .logHi, -0.05, 1.05
    Paint rectangle: .panel$, .logLo, .logHi, -0.05, 1.05
    for .i to .nSeg
        if segKept[.i] = 1
            .gd = segGe[.i] - segGs[.i]
            if .gd > 0
                if segLev[.i] = 0
                    .c$ = .l0col$
                    .r = 1.5
                elsif segLev[.i] = 1
                    .c$ = .l1col$
                    .r = 1.2
                elsif segLev[.i] = 2
                    .c$ = .l2col$
                    .r = 0.9
                else
                    .c$ = .l3col$
                    .r = 0.7
                endif
                Paint circle (mm): .c$, ln(.gd), segScore[.i], .r
            endif
        endif
    endfor

    Select inner viewport: 4.70, 7.55, 2.78, 4.00
    Axes: .logLo, .logHi, -0.05, 1.05
    Colour: .faint$
    Line width: 1
    Draw inner box
    Font size: 5
    Marks left: 3, "yes", "yes", "no"
    # Log-spaced duration ticks, labelled only where they fall inside the
    # observed range — a fixed decade grid would otherwise print ticks for
    # durations no segment has.
    .decade = 0.01
    while .decade <= 1000
        if ln(.decade) >= .logLo and ln(.decade) <= .logHi
            if .decade < 1
                .dlab$ = fixed$(.decade, 2)
            else
                .dlab$ = fixed$(.decade, 0)
            endif
            One mark bottom: ln(.decade), "yes", "yes", "no", .dlab$
        endif
        .decade = .decade * 10
    endwhile
    Font size: 6
    Text left: "yes", "head score"
    Text bottom: "yes", "Group duration (s, log)"

    Select inner viewport: 4.70, 7.55, 2.78, 4.00
    Axes: 0, 1, 0, 1
    Font size: 5
    Colour: .faint$
    Text: 0.5, "centre", 1.10, "half",
        ... "L0 " + string$(.nL0) + "   L1 " + string$(.nL1)
        ... + "   L2 " + string$(.nL2) + "   L3 " + string$(.nL3)
        ... + "   of " + string$(.nGroups) + " groups"

    # =======================================================================
    # IV. REDUCTION MAP
    # =======================================================================
    Select inner viewport: 0.60, 7.70, 4.42, 4.60
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: .ink$
    Text: 0.0, "left", 0.5, "half", "##IV  REDUCTION MAP##"
    Font size: 5
    Colour: .faint$
    Text: 1.0, "right", 0.5, "half",
        ... "control field  —  upper band: every Grouping_Macro segment by level; "
        ... + "lower band: what the montage keeps; time axis as panel I"

    Select inner viewport: .left, .right, 4.66, 5.34
    Axes: 0, dur, 0, 1
    Paint rectangle: .panel$, 0, dur, 0, 1
    for .i to .nSeg
        if segKept[.i] = 1
            if segLev[.i] = 0
                .c$ = .l0col$
            elsif segLev[.i] = 1
                .c$ = .l1col$
            elsif segLev[.i] = 2
                .c$ = .l2col$
            else
                .c$ = .l3col$
            endif
            Paint rectangle: .c$, segGs[.i], segGe[.i], 0.42, 0.94
            # Lower band: only L0/L1 reach the EDL and therefore the audio.
            if segLev[.i] <= 1
                Paint rectangle: .label$, segGs[.i], segGe[.i], 0.08, 0.30
            endif
        endif
    endfor

    Select inner viewport: .left, .right, 4.66, 5.34
    Axes: 0, dur, 0, 1
    Colour: .faint$
    Line width: 1
    Draw inner box
    Font size: 5
    Marks bottom every: 1, .tTick, "yes", "yes", "no"

    # Legend, drawn as swatches so the colour mapping is stated once and the
    # panel itself needs no per-band labels.
    Select inner viewport: .left, .right, 5.46, 5.62
    Axes: 0, 1, 0, 1
    Font size: 5
    Paint rectangle: .l0col$, 0.00, 0.022, 0.30, 0.80
    Colour: .faint$
    Text: 0.030, "left", 0.55, "half", "L0 Primary Anchor"
    Paint rectangle: .l1col$, 0.16, 0.182, 0.30, 0.80
    Colour: .faint$
    Text: 0.190, "left", 0.55, "half", "L1 Phrase Head"
    Paint rectangle: .l2col$, 0.32, 0.342, 0.30, 0.80
    Colour: .faint$
    Text: 0.350, "left", 0.55, "half", "L2 Ornament"
    Paint rectangle: .l3col$, 0.48, 0.502, 0.30, 0.80
    Colour: .faint$
    Text: 0.510, "left", 0.55, "half", "L3 Artifact / Noise"
    Colour: .label$
    Text: 0.66, "left", 0.55, "half", "lower band = spliced into the montage"

    # =======================================================================
    # V. THE MONTAGE ITSELF
    # =======================================================================
    Select inner viewport: 0.60, 7.70, 5.74, 5.92
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: .ink$
    Text: 0.0, "left", 0.5, "half", "##V  THE MONTAGE ITSELF##"
    Font size: 5
    Colour: .faint$
    Text: 1.0, "right", 0.5, "half",
        ... "measured  —  spectrogram of the produced Sound; vertical marks = splice points"

    .specStep = max(0.005, montageDur / 1400)
    selectObject: montage
    .spec = To Spectrogram: 0.03, spectral_max_freq, .specStep, 20, "Gaussian"

    Select inner viewport: .left, .right, 5.98, 6.76
    selectObject: .spec
    Paint: 0, 0, 0, spectral_max_freq, 100, 1, 50, 6, 0, 0
    removeObject: .spec

    # Splice marks. Above ~200 joins the marks would be a solid wash and would
    # say nothing, so they are thinned and the count is reported instead.
    Select inner viewport: .left, .right, 5.98, 6.76
    Axes: 0, montageDur, 0, spectral_max_freq
    .spliceStep = 1
    if spliceCount > 200
        .spliceStep = ceiling(spliceCount / 200)
    endif
    Colour: .accent$
    Line width: 0.5
    for .k from 1 to spliceCount
        if (.k mod .spliceStep) = 0 or .spliceStep = 1
            Draw line: spliceAt[.k], 0, spliceAt[.k], spectral_max_freq * 0.06
        endif
    endfor

    Select inner viewport: .left, .right, 5.98, 6.76
    Axes: 0, montageDur, 0, spectral_max_freq
    Colour: .faint$
    Line width: 1
    Draw inner box
    Font size: 5
    Marks left: 5, "yes", "yes", "no"
    if montageDur <= 10
        .mTick = 1
    elsif montageDur <= 30
        .mTick = 5
    elsif montageDur <= 120
        .mTick = 20
    else
        .mTick = 60
    endif
    Marks bottom every: 1, .mTick, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "Frequency (Hz)"
    Text bottom: "yes", "Montage time (s)"

    # =======================================================================
    # SUMMARY / QC
    # =======================================================================
    Select inner viewport: 0.60, 7.70, 7.16, 7.70
    Axes: 0, 1, 0, 1
    Paint rectangle: .sumBg$, 0, 1, 0, 1

    Select inner viewport: 0.60, 7.70, 7.16, 7.70
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: .ink$
    Text: 0.02, "left", 0.80, "half",
        ... "detection: " + materialName$ + "  |  margin " + fixed$(onset_threshold, 2)
        ... + " over a " + fixed$(onset_median_window_s, 1) + " s local median"
        ... + "  |  min IOI " + fixed$(min_ioi_ms, 0) + " ms  |  flux weight "
        ... + fixed$(onset_flux_weight, 2) + "  |  smoothing " + string$(onset_smooth_frames)
        ... + " frames  |  " + string$(.nSeg) + " onsets"
    Text: 0.02, "left", 0.50, "half",
        ... "grammar: merged weakest " + fixed$(100 * merge_weakest_fraction, 0)
        ... + "% of boundaries (cut " + fixed$(.cutLine, 3) + ")  |  "
        ... + string$(.nGroups) + " groups from " + string$(.nSeg) + " raw segments  |  L0 "
        ... + string$(.nL0) + " / L1 " + string$(.nL1) + " / L2 " + string$(.nL2)
        ... + " / L3 " + string$(.nL3) + "  |  targets L0 " + fixed$(level0_fraction, 2)
        ... + " L1 " + fixed$(level1_fraction, 2)
    Text: 0.02, "left", 0.20, "half",
        ... "output: " + string$(nKept) + " spans  |  " + fixed$(montageDur, 2) + " s of "
        ... + fixed$(dur, 2) + " s (" + fixed$(100 * montageDur / dur, 1) + "% retained, cap "
        ... + fixed$(100 * target_retention, 0) + "%)  |  crossfade "
        ... + fixed$(overlap * 1000, 1) + " ms" + crossfadeNote$ + "  |  peak "
        ... + fixed$(montagePeak, 3) + "  |  RMS " + fixed$(montageRms, 4)

    Select inner viewport: 0.60, 7.70, 7.16, 7.70
    Axes: 0, 1, 0, 1
    Colour: .faint$
    Line width: 1
    Draw rectangle: 0, 1, 0, 1

    # -----------------------------------------------------------------------
    # HONEST LIMITS, stated in the figure rather than only in the header.
    # -----------------------------------------------------------------------
    Select inner viewport: 0.60, 7.70, 7.76, 7.92
    Axes: 0, 1, 0, 1
    Font size: 5
    Colour: .faint$
    Text: 0.0, "left", 0.5, "half",
        ... "Limits: boundary strengths and head scores are normalized within this "
        ... + "file, so the thresholds are relative to this material, not absolute. "
        ... + "Level assignment is a minimum-spacing dynamic program over segment "
        ... + "scores, not a full pGTTM parse: no rule hierarchy is inferred and no "
        ... + "alternative parse is scored against this one."

    removeObject: .trace, .segs

    # State reset only — restores Praat's drawing defaults for whatever the
    # user draws next. Nothing in the figure above is drawn in black.
    Colour: "Black"
    Line width: 1
    Font size: 10
endproc
