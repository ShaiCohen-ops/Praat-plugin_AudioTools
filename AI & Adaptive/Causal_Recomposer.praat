# ============================================================
# Praat AudioTools - Causal_Recomposer.praat
# Causal-model-guided offline grain recomposition
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# WHAT THIS DOES
#   This is a grain re-ordering processor, not a spectral filter
#   or a resynthesizer. It analyses overlapping source grains,
#   fits a compact predictive law between local intensity I and
#   spectral centroid C,
#
#       Chat(t) = f( z(I(t)) )           polynomial order 1-3
#       R(t)    = C(t) - Chat(t)
#
#   and uses one quantity derived from that model as a stable
#   sort key. The ranked grains are then laid out along a
#   compositional TRAJECTORY through the ranked pool (v1.5):
#
#       Linear sweep     one pass, start extreme -> opposite extreme
#       Out and back     start -> opposite -> start      (2N - 1 grains)
#       Oscillating      C such arcs in a row          (2C(N - 1) + 1)
#       Guided random    drifting walk over ranks, bounded jumps (N)
#
#   An optional Temporal continuity blends the causal rank with the
#   source's chronological rank before the trajectory is built.
#   The source is reduced to one protected mono grain pool and the
#   trajectory is rendered TWICE: left and right follow the same
#   trajectory plus a few channel-specific local swaps. That
#   controlled difference creates stereo from recomposition itself.
#
#   IMPORTANT INTERPRETATION
#   The polynomial is a causal-model reading, not causal
#   identification from observational audio alone. "Lawful" and
#   "anomalous" therefore mean close to / far from this chosen
#   intensity-to-centroid model, not proof of a physical cause.
#
#   The synthesis stage does not filter or synthesize new
#   spectra. A mono source grain pool is extracted with a
#   rectangular window, then only splice edges are gain-tapered
#   for overlap-add. Left and right contain the same grain pool
#   but can place nearby-ranked grains in a slightly different
#   order. Where grains overlap, samples are mixed and normalized
#   by the same window sum.
#
# METHOD NOTES
#   - Analysis and synthesis share one mono grain pool. Multichannel
#     input is averaged to mono; if that average nearly cancels
#     relative to the strongest channel, the script safely falls
#     back to that strongest channel and reports the adjustment.
#   - Stereo divergence is NOT a delay effect. Both sides share the
#     same stable causal order; only the closest adjacent key pairs
#     can be swapped in one channel, chosen by a secondary feature.
#   - The intensity predictor is standardized before polynomial
#     fitting. This keeps order-2/3 normal equations numerically
#     much better conditioned while preserving the polynomial
#     family in the original intensity variable.
#   - If a requested polynomial fit is singular, the order is
#     reduced automatically; a constant model is the final
#     fallback for an intensity-uniform source.
#   - Sorting is stable in BOTH directions: equal keys retain
#     their original chronological order.
#   - Synthesis_overlap controls temporal density/output length.
#     Crossfade_ms controls the actual raised-cosine edge taper
#     and is capped to the available overlap and half a grain.
#   - Temporal continuity is an ORDERING control only. At 100% the
#     grain order is the source chronology, but every grain is still
#     cut, tapered and overlap-added at the synthesis hop; it does not
#     promise phase continuity or a click-free splice, and the output
#     is not the source unless the synthesis geometry matches it.
#   - Stereo_divergence_percent is a local-swap AMOUNT, not the share
#     of differing L/R positions: it requests up to
#     floor(divergence/100 * nOutputGrains / 4) non-overlapping
#     adjacent swaps, so 100 changes at most about half of the
#     positions. The measured L/R difference is reported separately.
#   - Presets set only the analysis/sort/splice character (sort key,
#     direction, model order, grain, overlaps, fade). Trajectory,
#     cycles, random variation, seed, continuity, stereo divergence,
#     visualization and playback always come from the form.
#
# Changelog v1.5 (2026) - trajectory engine
#   COMPATIBILITY: Linear sweep + Temporal continuity 0 reproduces
#   v1.4 BIT-FOR-BIT (audio and L/R order; 18 cases: all presets,
#   keys, directions, overlaps, fade caps, divergence 0/20/100, mono,
#   stereo, anti-phase and constant sources), on Praat 6.1.38 and 7.0,
#   EXCEPT where v1.4 hit the intensity defect in item 5 below.
#   Disabling only that repair restores bit-identity in those cases
#   too. Note that v1.4's own 70 ms presets (Lawful/Anomalous) hit the
#   defect on ordinary material: one edge grain was undefined.
#
#   1 - Trajectory_mode: Linear sweep (v1.4), Out and back (2N - 1
#     grains), Oscillating (2C(N - 1) + 1 grains, Number_of_cycles
#     1-8), Guided random walk (N grains). Arcs are a triangle wave
#     over positions in ONE ordering, so returns read that ordering
#     backwards and turning-point grains are never duplicated.
#   2 - Guided random walk: drift +1 rank per grain, a bounded
#     nonzero jump with probability v (|jump| <= round(v * max(2,
#     ceil(0.1 (N - 1))))), a 25% pull toward the linear target, and
#     reflection at both ends. v = 0 draws no random numbers and is
#     exactly the Linear sweep. Random_seed > 0 is reproducible; the
#     generator is returned to its safe state afterwards. Measured,
#     N = 149: v 25% -> 9% backward / 12% repeated steps, max jump 5,
#     rank-order correlation 1.00; v 100% -> 44% backward, max jump 15,
#     correlation 0.97.
#   3 - Temporal_continuity_percent: stable sort of
#     (1 - w)(causal rank) + w(chronological rank), both normalized to
#     0..1. 0% = causal order exactly, 100% = source chronology
#     (verified). Measured rank correlation with chronology / with the
#     causal order: 25% 0.46 / 0.96, 50% 0.76 / 0.77, 75% 0.96 / 0.45.
#   4 - Sort_key 5: Measured spectral centroid C, distinct from the
#     predicted Chat (key 2), which the Brightness Sweep preset keeps.
#   5 - FIX: intensity. v1.4 wrote -300 dB for undefined Intensity
#     readings, and Praat reports digital silence as a DEFINED -300 dB,
#     so both planted extreme points in the regression (on a test with
#     silent gaps, R^2 0.337 -> 0.386 once removed; with 10 ms grains
#     0.286 -> 0.403). Grains are now classified from their own RMS:
#     measured / repaired (time-interpolated between measured
#     neighbours, edge-held at the ends; signal-RMS dB if no reading
#     exists at all) / silent (placed at the quietest sounding
#     intensity and excluded from the fit). Counts go to the Info
#     window; a too-small fit set caps the model order with a note.
#   6 - Stereo for any sequence: eligible swaps are adjacent output
#     positions holding DIFFERENT grains, smallest primary-key gap
#     first. This is v1.4's selection exactly on a permutation, at
#     O(L log L) instead of O(L^2). Requested amount and measured L/R
#     difference are both reported.
#   7 - Sorting: v1.4's insertion sort (O(N^2)) replaced by a stable
#     bottom-up merge sort; identical permutation.
#   8 - Rendering uses nOutputGrains throughout; output is capped at
#     600 s (cycles are reduced with a note, other modes exit with a
#     message). Formulas address temporary Sounds by object ID, not
#     by name. Measured on Praat 7.0, 30 s source with drawing:
#     Linear 1.5 s, Out and back 2.4 s, 4 cycles (239 s out) 8.6 s.
#   9 - Visualization: panel B is now TRAJECTORY. A dark line shows the
#     common path through the ranked pool (where arcs and walks read as
#     shapes), and dots show the source-time position of each L and R
#     grain, with dotted turning points. Panel A no longer draws silent
#     grains and states the fitted order and repair counts. Title and
#     summary carry the trajectory, continuity, N -> L grains, the swap
#     amount against the measured L/R difference, and the output
#     duration.
#
# ============================================================

# === Input Validation ===
nSelected = numberOfSelected("Sound")
if nSelected <> 1
    exitScript: "Please select exactly one Sound object."
endif

snd = selected("Sound")
sndName$ = selected$("Sound")

form Causal Recomposer v1.5
    optionmenu Preset: 1
        option Custom
        option Lawful to Anomalous
        option Anomalous to Lawful
        option Brightness Sweep
    optionmenu Sort_key: 1
        option Model residual magnitude  (lawful -> anomalous)
        option Predicted brightness Chat  (dark -> bright)
        option Signed model residual      (darker -> brighter than predicted)
        option Intensity                  (quiet -> loud)
        option Measured spectral centroid (dark -> bright)
    optionmenu Sort_direction: 1
        option Ascending
        option Descending
    optionmenu Trajectory_mode: 1
        option Linear sweep
        option Out and back
        option Oscillating (multi-arc)
        option Guided random walk
    natural Number_of_cycles 2
    real Random_walk_variation 25
    integer Random_seed 0
    real Temporal_continuity_percent 0
    positive Grain_size_ms 80
    real Analysis_overlap 0.5
    natural Causal_model_order 2
    real Synthesis_overlap 0.5
    real Crossfade_ms 15
    real Stereo_divergence_percent 20
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESET LOGIC
# ============================================================

if preset = 2
    sort_key = 1
    sort_direction = 1
    causal_model_order = 2
    grain_size_ms = 70
    analysis_overlap = 0.5
    synthesis_overlap = 0.4
    crossfade_ms = 20
    presetName$ = "LawfulToAnomalous"
elsif preset = 3
    sort_key = 1
    sort_direction = 2
    causal_model_order = 2
    grain_size_ms = 70
    analysis_overlap = 0.5
    synthesis_overlap = 0.4
    crossfade_ms = 20
    presetName$ = "AnomalousToLawful"
elsif preset = 4
    sort_key = 2
    sort_direction = 1
    causal_model_order = 1
    grain_size_ms = 90
    analysis_overlap = 0.5
    synthesis_overlap = 0.5
    crossfade_ms = 25
    presetName$ = "BrightnessSweep"
else
    presetName$ = "Custom"
endif

if causal_model_order > 3
    causal_model_order = 3
endif
if causal_model_order < 1
    causal_model_order = 1
endif

sortKeyName$ = "Model residual magnitude"
if sort_key = 2
    sortKeyName$ = "Predicted brightness (Chat)"
elsif sort_key = 3
    sortKeyName$ = "Signed model residual"
elsif sort_key = 4
    sortKeyName$ = "Intensity"
elsif sort_key = 5
    sortKeyName$ = "Measured centroid C"
endif

sortDirName$ = "Ascending"
if sort_direction = 2
    sortDirName$ = "Descending"
endif

trajName$ = "Linear sweep"
if trajectory_mode = 2
    trajName$ = "Out and back"
elsif trajectory_mode = 3
    trajName$ = "Oscillating"
elsif trajectory_mode = 4
    trajName$ = "Guided random walk"
endif

# ============================================================
# VALIDATION AND SETUP
# ============================================================
warnLines$ = ""

if analysis_overlap < 0
    analysis_overlap = 0
    warnLines$ = warnLines$ + "  ! Analysis overlap < 0 -> 0" + newline$
endif
if analysis_overlap > 0.9
    analysis_overlap = 0.9
    warnLines$ = warnLines$ + "  ! Analysis overlap > 0.9 -> 0.9" + newline$
endif
if synthesis_overlap < 0
    synthesis_overlap = 0
    warnLines$ = warnLines$ + "  ! Synthesis overlap < 0 -> 0" + newline$
endif
if synthesis_overlap > 0.9
    synthesis_overlap = 0.9
    warnLines$ = warnLines$ + "  ! Synthesis overlap > 0.9 -> 0.9" + newline$
endif
if crossfade_ms < 0
    crossfade_ms = 0
    warnLines$ = warnLines$ + "  ! Crossfade < 0 ms -> 0 ms" + newline$
endif
if stereo_divergence_percent < 0
    stereo_divergence_percent = 0
    warnLines$ = warnLines$ + "  ! Stereo divergence < 0 -> 0" + newline$
endif
if stereo_divergence_percent > 100
    stereo_divergence_percent = 100
    warnLines$ = warnLines$ + "  ! Stereo divergence > 100 -> 100" + newline$
endif
if number_of_cycles > 8
    number_of_cycles = 8
    warnLines$ = warnLines$ + "  ! Number of cycles > 8 -> 8" + newline$
endif
if random_walk_variation < 0
    random_walk_variation = 0
    warnLines$ = warnLines$ + "  ! Random walk variation < 0 -> 0" + newline$
endif
if random_walk_variation > 100
    random_walk_variation = 100
    warnLines$ = warnLines$ + "  ! Random walk variation > 100 -> 100" + newline$
endif
if temporal_continuity_percent < 0
    temporal_continuity_percent = 0
    warnLines$ = warnLines$ + "  ! Temporal continuity < 0 -> 0" + newline$
endif
if temporal_continuity_percent > 100
    temporal_continuity_percent = 100
    warnLines$ = warnLines$ + "  ! Temporal continuity > 100 -> 100" + newline$
endif
if random_seed < 0
    random_seed = 0
    warnLines$ = warnLines$ + "  ! Random seed < 0 -> 0 (unpredictable)" + newline$
endif

# Resource guard (v1.5): trajectories can be up to 16x longer than the
# grain pool. The render holds the stereo buffer, a window buffer and,
# with visualization, four more mono copies of the output, all at double
# precision, so the output is capped rather than allowed to grow without
# limit.
maxOutputSec = 600

selectObject: snd
dur = Get total duration
fs = Get sampling frequency
nChannels = Get number of channels

# Quantize all temporal synthesis geometry to the source sample grid.
# This keeps shifted grain samples aligned with output samples.
grainSamples = round((grain_size_ms / 1000) * fs)
if grainSamples < 2
    grainSamples = 2
endif
grainSec = grainSamples / fs
effectiveGrainMs = 1000 * grainSec

analysisStepSamples = round(grainSamples * (1 - analysis_overlap))
if analysisStepSamples < 1
    analysisStepSamples = 1
endif
analysisStepSec = analysisStepSamples / fs

synthStepSamples = round(grainSamples * (1 - synthesis_overlap))
if synthStepSamples < 1
    synthStepSamples = 1
endif
synthStepSec = synthStepSamples / fs
overlapSamples = grainSamples - synthStepSamples
overlapSec = overlapSamples / fs

requestedFadeSamples = round((crossfade_ms / 1000) * fs)
effectiveFadeSamples = requestedFadeSamples
if effectiveFadeSamples > overlapSamples
    effectiveFadeSamples = overlapSamples
    warnLines$ = warnLines$ + "  ! Crossfade exceeds synthesis overlap -> capped to overlap" + newline$
endif
if effectiveFadeSamples > floor(grainSamples / 2)
    effectiveFadeSamples = floor(grainSamples / 2)
    warnLines$ = warnLines$ + "  ! Crossfade exceeds half a grain -> capped to half-grain" + newline$
endif
if synthesis_overlap = 0 and crossfade_ms > 0
    effectiveFadeSamples = 0
    warnLines$ = warnLines$ + "  ! Synthesis overlap is 0 -> crossfade taper disabled" + newline$
endif
if effectiveFadeSamples < 0
    effectiveFadeSamples = 0
endif
effectiveFadeSec = effectiveFadeSamples / fs
effectiveFadeMs = 1000 * effectiveFadeSec

if dur < grainSec * 4
    exitScript: "Sound too short for the requested grain size."
endif

# Build the mono grain pool used by BOTH analysis and synthesis.
# Average channels first, but protect against severe anti-phase collapse.
strongestCh = 1
strongestRms = -1
for ch from 1 to nChannels
    selectObject: snd
    tmpCh = Extract one channel: ch
    tmpRms = Get root-mean-square: 0, 0
    if tmpRms > strongestRms
        strongestRms = tmpRms
        strongestCh = ch
    endif
    removeObject: tmpCh
endfor

selectObject: snd
workSnd = Convert to mono
Rename: "CausalMono"
monoMethod$ = "channel average"
selectObject: workSnd
monoRms = Get root-mean-square: 0, 0

if nChannels > 1 and strongestRms > 0 and monoRms < 0.1 * strongestRms
    removeObject: workSnd
    selectObject: snd
    workSnd = Extract one channel: strongestCh
    Rename: "CausalMono"
    selectObject: workSnd
    monoRms = Get root-mean-square: 0, 0
    monoMethod$ = "strongest channel fallback"
    warnLines$ = warnLines$ + "  ! Channel average nearly cancelled -> mono pool uses strongest channel " + string$(strongestCh) + newline$
endif

clearinfo
writeInfoLine: "=== Causal Recomposer v1.5 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Sound: ", sndName$, "  (", fixed$(dur, 2), " s, ", nChannels, " ch)"
appendInfoLine: "Mono grain pool: ", monoMethod$, " | RMS ", fixed$(monoRms,4)
appendInfoLine: "Grain: ", fixed$(effectiveGrainMs, 3), " ms effective | Analysis overlap: ", fixed$(analysis_overlap * 100, 0), "%"
appendInfoLine: "Requested model order: ", causal_model_order
appendInfoLine: "Sort key: ", sortKeyName$, " | Direction: ", sortDirName$
trajDetail$ = ""
if trajectory_mode = 3
    trajDetail$ = " | cycles " + string$(number_of_cycles)
elsif trajectory_mode = 4
    trajDetail$ = " | variation " + fixed$(random_walk_variation, 0) + "% | seed "
    if random_seed > 0
        trajDetail$ = trajDetail$ + string$(random_seed)
    else
        trajDetail$ = trajDetail$ + "unpredictable"
    endif
endif
appendInfoLine: "Trajectory: ", trajName$, trajDetail$, " | Temporal continuity: ", fixed$(temporal_continuity_percent, 0), "%"
appendInfoLine: "Synthesis overlap: ", fixed$(synthesis_overlap * 100, 0), "% | Crossfade: ", fixed$(effectiveFadeMs, 1), " ms effective"
appendInfoLine: "Stereo divergence (local-swap amount): ", fixed$(stereo_divergence_percent,1), "% requested"
appendInfoLine: "Interpretation: model-guided residual, not causal identification from a single recording."
if warnLines$ <> ""
    appendInfoLine: ""
    appendInfoLine: "Adjustments:"
    appendInfo: warnLines$
endif
appendInfoLine: ""

# ------------------------------------------------------------
# PHASE 1: LOCAL INTENSITY AND SPECTRAL CENTROID
# ------------------------------------------------------------
appendInfoLine: "Phase 1: analyzing local intensity and spectral centroid..."

selectObject: workSnd
intensityObj = To Intensity: 75, 0, "yes"

nGrains = floor((dur - grainSec) / analysisStepSec) + 1
if nGrains < causal_model_order + 3
    removeObject: workSnd, intensityObj
    exitScript: "Not enough grains to fit a stable model at this grain size."
endif

grain_time# = zero#(nGrains)
feat_I# = zero#(nGrains)
feat_C# = zero#(nGrains)

# v1.5 intensity repair. v1.4 wrote -300 dB for every undefined
# Intensity reading, and Praat itself reports digital silence as a
# DEFINED -300 dB, so both cases planted artificial extremes in the
# regression. Each grain is now classified from its own audio:
#   1 measured  - Intensity defined and above intensityFloorDb
#   2 repaired  - the grain has signal, but the Intensity reading is
#                 undefined or at the floor (file edges, interpolation
#                 across a silence boundary): interpolated in time
#                 between the nearest measured grains, or held at the
#                 nearest one at the edges
#   3 silent    - the grain's own RMS is below silenceRms: placed at
#                 the quietest measured intensity and EXCLUDED from
#                 the model fit (its centroid is not measurable)
# Units: dB re 2e-5, the reference of Praat's Intensity object.
intensityFloorDb = -100
silenceRms = 2e-5 * 10 ^ (intensityFloorDb / 20)
intClass# = zero#(nGrains)
grainRms# = zero#(nGrains)

for i from 1 to nGrains
    t = grainSec / 2 + (i - 1) * analysisStepSec
    if t > dur - grainSec / 2
        t = dur - grainSec / 2
    endif
    grain_time#[i] = t

    selectObject: workSnd
    gr = Get root-mean-square: max(0, t - grainSec / 2), min(dur, t + grainSec / 2)
    if gr = undefined
        gr = 0
    endif
    grainRms#[i] = gr

    selectObject: intensityObj
    ii = Get value at time: t, "Cubic"
    if gr < silenceRms
        intClass#[i] = 3
    elsif ii = undefined
        intClass#[i] = 2
    elsif ii <= intensityFloorDb
        intClass#[i] = 2
    else
        intClass#[i] = 1
        feat_I#[i] = ii
    endif

    selectObject: workSnd
    g1 = Extract part: max(0, t - grainSec / 2), min(dur, t + grainSec / 2), "Hanning", 1, "no"
    sp1 = To Spectrum: "yes"
    cc = Get centre of gravity: 2
    if cc = undefined
        cc = 0
    endif
    feat_C#[i] = cc
    removeObject: g1, sp1
endfor

appendInfoLine: "  ", nGrains, " grains analyzed"

# --- Repair pass: nearest measured grain on each side (O(N)) ---
prevValid# = zero#(nGrains)
nextValid# = zero#(nGrains)
lastValid = 0
for i from 1 to nGrains
    if intClass#[i] = 1
        lastValid = i
    endif
    prevValid#[i] = lastValid
endfor
lastValid = 0
for back from 1 to nGrains
    i = nGrains - back + 1
    if intClass#[i] = 1
        lastValid = i
    endif
    nextValid#[i] = lastValid
endfor

nMeasuredI = 0
nRepairedI = 0
nSignalI = 0
nSilentI = 0
for i from 1 to nGrains
    if intClass#[i] = 1
        nMeasuredI += 1
    elsif intClass#[i] = 3
        nSilentI += 1
    endif
endfor

for i from 1 to nGrains
    if intClass#[i] = 2
        p = prevValid#[i]
        n = nextValid#[i]
        if p > 0 and n > 0
            tp = grain_time#[p]
            tn = grain_time#[n]
            if tn > tp
                feat_I#[i] = feat_I#[p] + (feat_I#[n] - feat_I#[p]) * (grain_time#[i] - tp) / (tn - tp)
            else
                feat_I#[i] = feat_I#[p]
            endif
            nRepairedI += 1
        elsif p > 0
            feat_I#[i] = feat_I#[p]
            nRepairedI += 1
        elsif n > 0
            feat_I#[i] = feat_I#[n]
            nRepairedI += 1
        else
            # No measured Intensity anywhere: fall back to the grain's
            # own RMS, in the same dB re 2e-5 units.
            feat_I#[i] = 20 * log10(grainRms#[i] / 2e-5)
            nSignalI += 1
        endif
    endif
endfor

# Silent grains sit at the quietest NON-silent intensity, so they never
# extend the regression's domain.
nSoundingI = nGrains - nSilentI
if nSilentI > 0
    if nSoundingI > 0
        quietI = 1e300
        for i from 1 to nGrains
            if intClass#[i] <> 3 and feat_I#[i] < quietI
                quietI = feat_I#[i]
            endif
        endfor
    else
        quietI = 0
        warnLines$ = warnLines$ + "  ! Source is digital silence -> constant model, chronological ties" + newline$
    endif
    for i from 1 to nGrains
        if intClass#[i] = 3
            feat_I#[i] = quietI
        endif
    endfor
endif

fitMask# = zero#(nGrains)
for i from 1 to nGrains
    if intClass#[i] <> 3
        fitMask#[i] = 1
    endif
endfor
nFit = nSoundingI

appendInfoLine: "  intensity: ", nMeasuredI, " measured | ", nRepairedI, " repaired (time-interpolated/edge-held) | ",
    ... nSignalI, " signal-RMS fallback | ", nSilentI, " silent (excluded from fit)"

# ------------------------------------------------------------
# PHASE 2: STANDARDIZED POLYNOMIAL MODEL
#   z(I) = (I - meanI) / sdI
#   Chat = a0 + a1*z + ... + ak*z^k
# ------------------------------------------------------------
appendInfoLine: "Phase 2: fitting standardized intensity -> centroid model..."

meanI = 0
meanC = 0
minI = feat_I#[1]
maxI = feat_I#[1]
minC = feat_C#[1]
maxC = feat_C#[1]
for i from 1 to nGrains
    if fitMask#[i] = 1
        meanI += feat_I#[i]
        meanC += feat_C#[i]
    endif
    if feat_I#[i] < minI
        minI = feat_I#[i]
    endif
    if feat_I#[i] > maxI
        maxI = feat_I#[i]
    endif
    if feat_C#[i] < minC
        minC = feat_C#[i]
    endif
    if feat_C#[i] > maxC
        maxC = feat_C#[i]
    endif
endfor
# v1.5: the fit uses sounding grains only (fitMask#). With no silent
# grains nFit = nGrains and every sum below is the v1.4 sum, in the
# same order.
if nFit > 0
    meanI = meanI / nFit
    meanC = meanC / nFit
else
    meanI = 0
    meanC = 0
    for i from 1 to nGrains
        meanI += feat_I#[i]
        meanC += feat_C#[i]
    endfor
    meanI = meanI / nGrains
    meanC = meanC / nGrains
endif

varI = 0
for i from 1 to nGrains
    if fitMask#[i] = 1
        varI += (feat_I#[i] - meanI)^2
    endif
endfor
if nFit > 1
    varI = varI / (nFit - 1)
endif
sdI = sqrt(max(0, varI))

# Too few sounding grains for the requested order: cap it (the
# singular-fit fallback below still applies on top of this).
if nFit < causal_model_order + 3
    cappedOrder = max(0, nFit - 3)
    if cappedOrder < causal_model_order
        warnLines$ = warnLines$ + "  ! Only " + string$(nFit) + " sounding grains -> model order capped to "
            ... + string$(cappedOrder) + newline$
        causal_model_order = cappedOrder
    endif
endif

zI# = zero#(nGrains)
if sdI > 1e-9
    for i from 1 to nGrains
        zI#[i] = (feat_I#[i] - meanI) / sdI
    endfor
endif

requestedOrder = causal_model_order
effectiveOrder = requestedOrder
fitSolved = 0

if sdI <= 1e-9 or requestedOrder < 1
    effectiveOrder = 0
else
    while effectiveOrder >= 1 and fitSolved = 0
        nCoef = effectiveOrder + 1
        aug## = zero##(nCoef, nCoef + 1)

        for row from 1 to nCoef
            for col from 1 to nCoef
                p = (row - 1) + (col - 1)
                s = 0
                for i from 1 to nGrains
                    if fitMask#[i] = 1
                        s += zI#[i] ^ p
                    endif
                endfor
                aug##[row, col] = s
            endfor
            s = 0
            for i from 1 to nGrains
                if fitMask#[i] = 1
                    s += zI#[i] ^ (row - 1) * feat_C#[i]
                endif
            endfor
            aug##[row, nCoef + 1] = s
        endfor

        fitOK = 1
        for col from 1 to nCoef
            if fitOK = 1
                pivotRow = col
                pivotVal = abs(aug##[col, col])
                for r from col + 1 to nCoef
                    if abs(aug##[r, col]) > pivotVal
                        pivotVal = abs(aug##[r, col])
                        pivotRow = r
                    endif
                endfor

                if pivotVal < 1e-10
                    fitOK = 0
                else
                    if pivotRow <> col
                        for c from 1 to nCoef + 1
                            tmp = aug##[col, c]
                            aug##[col, c] = aug##[pivotRow, c]
                            aug##[pivotRow, c] = tmp
                        endfor
                    endif

                    pivot = aug##[col, col]
                    for c from 1 to nCoef + 1
                        aug##[col, c] = aug##[col, c] / pivot
                    endfor

                    for r from 1 to nCoef
                        if r <> col
                            factor = aug##[r, col]
                            for c from 1 to nCoef + 1
                                aug##[r, c] = aug##[r, c] - factor * aug##[col, c]
                            endfor
                        endif
                    endfor
                endif
            endif
        endfor

        if fitOK = 1
            fitSolved = 1
        else
            effectiveOrder -= 1
        endif
    endwhile
endif

if effectiveOrder = 0
    nCoef = 1
    coef# = zero#(1)
    coef#[1] = meanC
    if requestedOrder > 0
        warnLines$ = warnLines$ + "  ! Intensity variation/model rank insufficient -> constant centroid model" + newline$
    endif
else
    nCoef = effectiveOrder + 1
    coef# = zero#(nCoef)
    for row from 1 to nCoef
        coef#[row] = aug##[row, nCoef + 1]
    endfor
    if effectiveOrder < requestedOrder
        warnLines$ = warnLines$ + "  ! Singular requested polynomial -> reduced model order to " + string$(effectiveOrder) + newline$
    endif
endif

feat_Chat# = zero#(nGrains)
feat_R# = zero#(nGrains)
sumSqTot = 0
sumSqRes = 0

for i from 1 to nGrains
    if effectiveOrder = 0
        val = meanC
    else
        val = 0
        zPower = 1
        for c from 1 to nCoef
            val += coef#[c] * zPower
            zPower *= zI#[i]
        endfor
    endif
    feat_Chat#[i] = val
    feat_R#[i] = feat_C#[i] - val
    if fitMask#[i] = 1
        sumSqRes += feat_R#[i]^2
        sumSqTot += (feat_C#[i] - meanC)^2
    endif
endfor

if sumSqTot > 0
    rSquared = 1 - sumSqRes / sumSqTot
else
    rSquared = 0
endif
residualRms = sqrt(sumSqRes / max(1, nFit))

appendInfoLine: "  effective model order = ", effectiveOrder
appendInfoLine: "  fit R^2 = ", fixed$(rSquared, 3), " | residual RMS = ", fixed$(residualRms, 1), " Hz"

# ------------------------------------------------------------
# PHASE 3: CAUSAL ORDER -> CONTINUITY -> TRAJECTORY -> STEREO VARIANTS
# 3a  one stable causal ranking of the grain pool
# 3b  optional blend with chronological rank (Temporal continuity)
# 3c  trajectory through that ordering (linear, arcs or guided walk)
# 3d  both channels get EXACTLY that trajectory; stereo divergence then
#     swaps only adjacent grains with the smallest primary-key gaps, so
#     the global shape is kept while near-equivalent grains differ L/R
# 3e  measured statistics
# ------------------------------------------------------------
appendInfoLine: "Phase 3: causal order -> continuity -> trajectory -> stereo variants..."

sortKey# = zero#(nGrains)
for i from 1 to nGrains
    if sort_key = 1
        sortKey#[i] = abs(feat_R#[i])
    elsif sort_key = 2
        sortKey#[i] = feat_Chat#[i]
    elsif sort_key = 3
        sortKey#[i] = feat_R#[i]
    elsif sort_key = 5
        sortKey#[i] = feat_C#[i]
    else
        sortKey#[i] = feat_I#[i]
    endif
endfor

# Secondary measured cue decides WHICH channel gets each local swap.
# It does not change which pairs are eligible: eligibility comes only
# from closeness in the primary causal sort key.
secondary# = zero#(nGrains)
secondaryName$ = "signed residual"
if sort_key = 3
    secondaryName$ = "standardized intensity"
    for i from 1 to nGrains
        secondary#[i] = zI#[i]
    endfor
else
    for i from 1 to nGrains
        secondary#[i] = feat_R#[i]
    endfor
endif

secMaxAbs = 0
for i from 1 to nGrains
    if abs(secondary#[i]) > secMaxAbs
        secMaxAbs = abs(secondary#[i])
    endif
endfor
if secMaxAbs < 1e-12 and sort_key <> 3
    secondaryName$ = "standardized intensity fallback"
    for i from 1 to nGrains
        secondary#[i] = zI#[i]
    endfor
    secMaxAbs = 0
    for i from 1 to nGrains
        if abs(secondary#[i]) > secMaxAbs
            secMaxAbs = abs(secondary#[i])
        endif
    endfor
endif

# ---- 3a. Stable base causal sort ----
# v1.5: bottom-up merge sort (O(N log N)) instead of v1.4's insertion
# sort (O(N^2)). Both are stable, so equal keys keep chronological
# order and the permutation is identical. Descending sorts the negated
# key, which is the same stable descending order.
sortVal# = zero#(nGrains)
sortIdx# = zero#(nGrains)
for i from 1 to nGrains
    if sort_direction = 1
        sortVal#[i] = sortKey#[i]
    else
        sortVal#[i] = -sortKey#[i]
    endif
    sortIdx#[i] = i
endfor
@stableArgsort: nGrains
permBase# = sortIdx#

baseRank# = zero#(nGrains)
for g from 1 to nGrains
    baseRank#[permBase#[g]] = g
endfor

# ---- 3b. Temporal continuity ----
# Blend of two NORMALIZED ranks, both in 0..1, then a stable sort:
#   blend = (1 - w) * (causalRank - 1)/(N - 1) + w * (sourceIndex - 1)/(N - 1)
# Raw intensity, residual, centroid and time are never mixed.
# w = 0 keeps the causal order exactly; w = 1 gives the chronology.
contW = temporal_continuity_percent / 100
if contW <= 0
    ordered# = permBase#
else
    for i from 1 to nGrains
        sortVal#[i] = (1 - contW) * (baseRank#[i] - 1) / (nGrains - 1)
            ... + contW * (i - 1) / (nGrains - 1)
        sortIdx#[i] = i
    endfor
    @stableArgsort: nGrains
    ordered# = sortIdx#
endif

# ---- 3c. Trajectory through the ordered pool ----
# The trajectory is a sequence of POSITIONS in ordered#[1..N]; the
# grains are ordered#[trajPos#[k]]. Return paths read the same
# ordering backwards, never a re-sort.
nCyclesUsed = 0
if trajectory_mode = 2
    nCyclesUsed = 1
elsif trajectory_mode = 3
    nCyclesUsed = number_of_cycles
endif

if nCyclesUsed > 0
    # Cap the cycle count so the render stays under maxOutputSec.
    maxCycles = floor((maxOutputSec - grainSec) / (2 * (nGrains - 1) * synthStepSec))
    if maxCycles < 1
        removeObject: workSnd, intensityObj
        exitScript: "Out-and-back output would exceed " + string$(maxOutputSec)
            ... + " s. Use a shorter sound, a larger grain or a lower synthesis overlap."
    endif
    if nCyclesUsed > maxCycles
        warnLines$ = warnLines$ + "  ! " + string$(nCyclesUsed) + " cycles exceed the "
            ... + string$(maxOutputSec) + " s output cap -> " + string$(maxCycles) + " cycles" + newline$
        nCyclesUsed = maxCycles
    endif
    nOutputGrains = 2 * nCyclesUsed * (nGrains - 1) + 1
else
    nOutputGrains = nGrains
endif

outDur = (nOutputGrains - 1) * synthStepSec + grainSec
if outDur > maxOutputSec
    removeObject: workSnd, intensityObj
    exitScript: "Output would be " + fixed$(outDur, 1) + " s, above the " + string$(maxOutputSec)
        ... + " s cap. Use a shorter sound, a larger grain or a lower synthesis overlap."
endif

trajPos# = zero#(nOutputGrains)
walkJump = 0
if trajectory_mode = 1
    for k from 1 to nOutputGrains
        trajPos#[k] = k
    endfor
elsif trajectory_mode = 2 or trajectory_mode = 3
    # Triangle wave over positions 1..N..1..N..1, period 2(N - 1):
    # turning points appear once, never duplicated.
    period = 2 * (nGrains - 1)
    for k from 1 to nOutputGrains
        m = (k - 1) mod period
        if m <= nGrains - 1
            trajPos#[k] = m + 1
        else
            trajPos#[k] = period - m + 1
        endif
    endfor
else
    # Guided random walk on rank positions.
    #   drift   +1 position per output grain (one full pass in N grains)
    #   jumps   with probability v, an extra nonzero step in
    #           [-J, +J], J = round(v * max(2, ceil(0.1 (N - 1))))
    #   guide   the candidate is pulled 25% of the way toward the linear
    #           target 1 + (N - 1)(k - 1)/(L - 1), which keeps the large-
    #           scale direction and stops the walk parking at an edge
    #   bounds  reflection at 1 and N, then clamped
    # v = 0 draws no random numbers and gives exactly the linear sweep.
    walkV = random_walk_variation / 100
    walkJump = max(1, round(walkV * max(2, ceiling(0.1 * (nGrains - 1)))))
    walkPull = 0.25
    if walkV > 0 and random_seed > 0
        random_initializeWithSeedUnsafelyButPredictably (random_seed)
    endif
    pos = 1
    trajPos#[1] = 1
    for k from 2 to nOutputGrains
        target = 1 + (nGrains - 1) * (k - 1) / (nOutputGrains - 1)
        stepW = 1
        if walkV > 0
            if randomUniform (0, 1) < walkV
                d = randomInteger (-walkJump, walkJump - 1)
                if d >= 0
                    d += 1
                endif
                stepW += d
            endif
        endif
        cand = pos + stepW
        cand = round(cand + walkPull * (target - cand))
        if cand < 1
            cand = 2 - cand
        endif
        if cand > nGrains
            cand = 2 * nGrains - cand
        endif
        cand = max(1, min(nGrains, cand))
        pos = cand
        trajPos#[k] = pos
    endfor
    if walkV > 0 and random_seed > 0
        random_initializeSafelyAndUnpredictably ()
    endif
endif

traj# = zero#(nOutputGrains)
for k from 1 to nOutputGrains
    traj#[k] = ordered#[trajPos#[k]]
endfor

# Turning points of the common trajectory (direction reversals).
nTurns = 0
nBackSteps = 0
nRepeatSteps = 0
for k from 2 to nOutputGrains
    if trajPos#[k] < trajPos#[k - 1]
        nBackSteps += 1
    elsif trajPos#[k] = trajPos#[k - 1]
        nRepeatSteps += 1
    endif
endfor
turnAt# = zero#(max(1, nOutputGrains))
for k from 2 to nOutputGrains - 1
    if (trajPos#[k] - trajPos#[k - 1]) * (trajPos#[k + 1] - trajPos#[k]) < 0
        nTurns += 1
        turnAt#[nTurns] = k
    endif
endfor
distinctUsed# = zero#(nGrains)
nDistinct = 0
for k from 1 to nOutputGrains
    if distinctUsed#[traj#[k]] = 0
        distinctUsed#[traj#[k]] = 1
        nDistinct += 1
    endif
endfor

# ---- 3d. Channel variants by controlled local swaps ----
# Both channels start from the SAME trajectory. Eligible swaps are
# adjacent output positions holding two DIFFERENT grains (a repeated
# grain swapped with itself changes nothing), ranked by the gap in the
# primary causal key, smallest first, ties by earliest position. They
# are taken greedily without overlap. On a permutation this is exactly
# v1.4's repeated minimum scan, but O(L log L) instead of O(L^2).
seqL# = traj#
seqR# = traj#

nCand = 0
for g from 1 to nOutputGrains - 1
    if traj#[g] <> traj#[g + 1]
        nCand += 1
    endif
endfor

# Maximum design: at divergence=100, swap up to one quarter of the
# output grains as pairs (so at most about half the positions differ).
targetPairs = floor((stereo_divergence_percent / 100) * nOutputGrains / 4)
maxPairs = floor(nOutputGrains / 2)
if targetPairs > maxPairs
    targetPairs = maxPairs
endif
if targetPairs < 0
    targetPairs = 0
endif

actualPairs = 0
if nCand > 0 and targetPairs > 0
    sortVal# = zero#(nOutputGrains - 1)
    sortIdx# = zero#(nCand)
    c = 0
    for g from 1 to nOutputGrains - 1
        sortVal#[g] = abs(sortKey#[traj#[g]] - sortKey#[traj#[g + 1]])
        if traj#[g] <> traj#[g + 1]
            c += 1
            sortIdx#[c] = g
        endif
    endfor
    @stableArgsort: nCand

    usedPos# = zero#(nOutputGrains)
    for c from 1 to nCand
        if actualPairs < targetPairs
            bestPos = sortIdx#[c]
            if usedPos#[bestPos] = 0 and usedPos#[bestPos + 1] = 0
                actualPairs += 1
                swapNo = actualPairs
                a = traj#[bestPos]
                b = traj#[bestPos + 1]

                # Deterministic channel choice from the secondary feature.
                # Ties alternate by swap number to keep the field balanced.
                swapLeft = 0
                if secondary#[a] < secondary#[b]
                    swapLeft = 1
                elsif secondary#[a] = secondary#[b]
                    if swapNo mod 2 = 1
                        swapLeft = 1
                    endif
                endif

                if swapLeft = 1
                    seqL#[bestPos] = b
                    seqL#[bestPos + 1] = a
                else
                    seqR#[bestPos] = b
                    seqR#[bestPos + 1] = a
                endif

                usedPos#[bestPos] = 1
                usedPos#[bestPos + 1] = 1
            endif
        endif
    endfor
endif

# ---- 3e. Measured sequence statistics ----
# Generalized from v1.4 for sequences of any length with repeats:
# source positions and output positions are both normalized to 0..1,
# so for a Linear permutation every figure equals v1.4's.
dispSum = 0
adjBreaksL = 0
adjBreaksR = 0
stereoDifferent = 0
stereoRankSepSum = 0
for g from 1 to nOutputGrains
    if nGrains > 1 and nOutputGrains > 1
        outFrac = (g - 1) / (nOutputGrains - 1)
        dispSum += 0.5 * (abs((seqL#[g] - 1) / (nGrains - 1) - outFrac)
            ... + abs((seqR#[g] - 1) / (nGrains - 1) - outFrac))
    endif
    if nGrains > 1
        stereoRankSepSum += abs(baseRank#[seqL#[g]] - baseRank#[seqR#[g]]) / (nGrains - 1)
    endif
    if seqL#[g] <> seqR#[g]
        stereoDifferent += 1
    endif
    if g > 1
        if abs(seqL#[g] - seqL#[g - 1]) <> 1
            adjBreaksL += 1
        endif
        if abs(seqR#[g] - seqR#[g - 1]) <> 1
            adjBreaksR += 1
        endif
    endif
endfor
meanDisplacementPct = 100 * dispSum / nOutputGrains
stereoDifferentPct = 100 * stereoDifferent / nOutputGrains
stereoOrderSeparationPct = 100 * stereoRankSepSum / nOutputGrains
if nOutputGrains > 1
    adjacencyBreakPct = 50 * (adjBreaksL + adjBreaksR) / (nOutputGrains - 1)
else
    adjacencyBreakPct = 0
endif

appendInfoLine: "  trajectory = ", trajName$, " | ", nGrains, " source -> ", nOutputGrains, " output grains | ",
    ... nDistinct, " distinct | ", nTurns, " turning points"
if trajectory_mode = 4
    appendInfoLine: "  walk: jump bound +/-", walkJump, " | backward steps ", nBackSteps, " | repeats ", nRepeatSteps
endif
appendInfoLine: "  stereo cue = ", secondaryName$, " | local swap pairs = ", actualPairs, " of ", targetPairs, " requested"
appendInfoLine: "  L/R differing positions = ", fixed$(stereoDifferentPct,1), "% | mean causal-rank separation = ", fixed$(stereoOrderSeparationPct,3), "%"

# ------------------------------------------------------------
# PHASE 4: DUAL MONO-POOL RECOMPOSITION -> GENERATED STEREO
# Both channels use the same source pool and splice law. Only the
# model-guided grain order differs slightly between L and R.
# ------------------------------------------------------------
appendInfoLine: "Phase 4: recomposing mono source pool into generated stereo..."

# outDur was set in Phase 3 from the generated length:
#   outDur = (nOutputGrains - 1) * synthStepSec + grainSec
# v1.5: formulas address the temporary Sounds by object ID rather than
# by name ("Sound cr_grainL"), so a same-named object already in the
# list can never be picked up. Interpolation is unchanged.
outBuf = Create Sound from formula: "cr_out", 2, 0, outDur, fs, "0"
outWin = Create Sound from formula: "cr_win", 1, 0, outDur, fs, "0"

for g from 1 to nOutputGrains
    outStart = (g - 1) * synthStepSec
    outEnd = outStart + grainSec

    # LEFT process
    srcIdx = seqL#[g]
    srcT = grain_time#[srcIdx]
    t1src = max(0, srcT - grainSec / 2)
    t2src = min(dur, srcT + grainSec / 2)
    selectObject: workSnd
    grainL = Extract part: t1src, t2src, "rectangular", 1, "no"
    Rename: "cr_grainL"
    if effectiveFadeSec > 0
        selectObject: grainL
        Formula: "if x < 'effectiveFadeSec' then self * (0.5 - 0.5*cos(pi*x/'effectiveFadeSec')) else if x > xmax - 'effectiveFadeSec' then self * (0.5 - 0.5*cos(pi*(xmax-x)/'effectiveFadeSec')) else self fi fi"
    endif
    selectObject: grainL
    Shift times to: "start time", outStart
    selectObject: outBuf
    Formula (part): max(0, outStart), min(outDur, outEnd), 1, 1,
        ... "self + object (" + string$(grainL) + ", x, 1)"

    # RIGHT process
    srcIdx = seqR#[g]
    srcT = grain_time#[srcIdx]
    t1src = max(0, srcT - grainSec / 2)
    t2src = min(dur, srcT + grainSec / 2)
    selectObject: workSnd
    grainR = Extract part: t1src, t2src, "rectangular", 1, "no"
    Rename: "cr_grainR"
    if effectiveFadeSec > 0
        selectObject: grainR
        Formula: "if x < 'effectiveFadeSec' then self * (0.5 - 0.5*cos(pi*x/'effectiveFadeSec')) else if x > xmax - 'effectiveFadeSec' then self * (0.5 - 0.5*cos(pi*(xmax-x)/'effectiveFadeSec')) else self fi fi"
    endif
    selectObject: grainR
    Shift times to: "start time", outStart
    selectObject: outBuf
    Formula (part): max(0, outStart), min(outDur, outEnd), 2, 2,
        ... "self + object (" + string$(grainR) + ", x, 1)"

    # The overlap geometry is identical on both sides, so one
    # measured denominator normalizes both channels.
    selectObject: outWin
    if effectiveFadeSec > 0
        Formula (part): max(0, outStart), min(outDur, outEnd), 1, 1,
            ... "self + if x-'outStart' < 'effectiveFadeSec' then 0.5 - 0.5*cos(pi*(x-'outStart')/'effectiveFadeSec') else if x-'outStart' > 'grainSec'-'effectiveFadeSec' then 0.5 - 0.5*cos(pi*('grainSec'-(x-'outStart'))/'effectiveFadeSec') else 1 fi fi"
    else
        Formula (part): max(0, outStart), min(outDur, outEnd), 1, 1, "self + 1"
    endif

    removeObject: grainL, grainR
endfor

selectObject: outBuf
winId$ = string$(outWin)
Formula: "if object (" + winId$ + ", x, 0) > 1e-6 then self / object (" + winId$ + ", x, 0) else 0 fi"
Rename: sndName$ + "_causal_recomposed_stereo"
removeObject: outWin

selectObject: outBuf
outChannels = Get number of channels
outPeak = Get absolute extremum: 0, 0, "None"
outRms = Get root-mean-square: 0, 0

# ============================================================
# VISUALIZATION
# v1.3: simplified mechanism-first 2x2 layout with generated stereo.
# Each panel answers one question and uses measured data only.
#
# v1.4 (2026) - visualization uniformity pass; no change to analysis,
# sorting, splicing or synthesis. The 2x2 mechanism-first layout, the
# lettered A-D sections and every plotted quantity are unchanged.
#   1. FIX (real defect, not cosmetic): four occurrences of the percent
#      escape were malformed. In Praat text, \% prints a percent sign
#      and then CONSUMES the following character. At the end of a
#      string it had nothing to consume and printed a stray backslash
#      ("rank separation 0.164\"), and in "output position (\%)" it
#      swallowed the closing bracket, so both scatter axes were labelled
#      "output position (" and "source position (". Every \% is now
#      followed by a spare space.
#   2. FIX: the figure ended inside the summary strip, so Save as PNG
#      and Copy to clipboard exported that strip alone (2502 x 293 px)
#      rather than the whole page. drawing now ends by re-selecting the
#      full page.
#   3. Title block rebuilt to the library standard: bold ##...## title
#      at font 12 with a font 7 subtitle beneath it. The preset name
#      moves out of the title into the subtitle, which now also carries
#      sort key, direction, grain count, grain and fade length and
#      output duration. The "mono grain pool -> ..." chain description
#      moves to the summary strip, where the other scripts keep it.
#   4. Column geometry regularized. Outer splits 0.18/3.92 and
#      4.08/7.82 become 0/4 and 4/8; plot inner viewports become
#      0.60, 3.85 (left) and 4.45, 7.70 (right), a 0.60 in gutter that
#      leaves the right column the same y-label room as the left.
#      Section headers keep their 0.18 in outdent from the column edge.
#   5. Fonts: tick marks 5 -> 6 (5 was unique to this script in the
#      whole category), axis labels 6 -> 7, summary 7/6 -> 6 with
#      ##bold## run-in labels. Section headers stay at 9.
#   6. Colours normalized to the 2-decimal, spaced convention:
#      panel ground {0.975,0.975,0.978} -> {0.97, 0.97, 0.97},
#      summary ground {0.965,0.965,0.970} -> {0.94, 0.94, 0.94},
#      secondary text {0.34,0.34,0.40} and {0.35,0.35,0.40} ->
#      {0.35, 0.35, 0.50}, summary text -> {0.25, 0.25, 0.35}.
#      The two near-identical blues ({0.26,0.46,0.76} for the scatter
#      dots, {0.26,0.48,0.78} for the lines) collapse to one.
#      Reference band {0.94,0.94,0.95} -> {0.92, 0.92, 0.92} so it
#      stays distinct from the summary ground now that both are grey.
#      Hues are otherwise unchanged, pending the palette decision.
# ============================================================
if draw_visualization
    appendInfoLine: "Drawing simplified process visualization..."

    # Measured mono source and generated stereo MID/SIDE.
    vizSrc = workSnd
    selectObject: vizSrc
    srcPeak = Get absolute extremum: 0, 0, "None"
    srcRms = Get root-mean-square: 0, 0

    selectObject: outBuf
    vizL = Extract one channel: 1
    Rename: "cr_viz_left"
    selectObject: outBuf
    vizR = Extract one channel: 2
    Rename: "cr_viz_right"

    vizLid$ = string$(vizL)
    vizRid$ = string$(vizR)
    vizMid = Create Sound from formula: "cr_viz_mid", 1, 0, outDur, fs,
        ... "(object (" + vizLid$ + ", x, 1) + object (" + vizRid$ + ", x, 1)) / 2"
    vizSide = Create Sound from formula: "cr_viz_side", 1, 0, outDur, fs,
        ... "(object (" + vizLid$ + ", x, 1) - object (" + vizRid$ + ", x, 1)) / 2"

    selectObject: vizMid
    vizOutPeak = Get absolute extremum: 0, 0, "None"
    vizOutRms = Get root-mean-square: 0, 0
    midRms = vizOutRms
    selectObject: vizSide
    sideRms = Get root-mean-square: 0, 0
    if midRms > 1e-12 and sideRms > 1e-12
        sideMidDb = 20 * log10(sideRms / midRms)
    elsif sideRms <= 1e-12
        sideMidDb = -300
    else
        sideMidDb = 60
    endif
    if sideMidDb < -100
        sideMidLabel$ = "mono"
    else
        sideMidLabel$ = fixed$(sideMidDb,1) + " dB"
    endif

    # Spectral-shape QC compares the mono grain pool to stereo MID.
    # Each LTAS is mean-removed, so D measures shape change rather
    # than overall level.
    selectObject: vizSrc
    srcSpec = To Spectrum: "yes"
    srcGlobalCentroid = Get centre of gravity: 2
    To Ltas (1-to-1)
    srcLtas = selected("Ltas")

    selectObject: vizMid
    outSpec = To Spectrum: "yes"
    outGlobalCentroid = Get centre of gravity: 2
    To Ltas (1-to-1)
    outLtas = selected("Ltas")

    specFmin = 50
    specFmax = min(16000, 0.45 * fs)
    if specFmax <= specFmin * 1.2
        specFmin = max(1, specFmax / 5)
    endif
    logFmin = log10(specFmin)
    logFmax = log10(specFmax)
    nSpecPoints = 72
    specFreq# = zero#(nSpecPoints)
    srcShape# = zero#(nSpecPoints)
    outShape# = zero#(nSpecPoints)
    specDelta# = zero#(nSpecPoints)
    meanSrcShape = 0
    meanOutShape = 0

    for q from 1 to nSpecPoints
        frac = (q - 1) / (nSpecPoints - 1)
        freq = specFmin * (specFmax / specFmin)^frac
        specFreq#[q] = freq
        bandLo = max(specFmin, freq / 1.04)
        bandHi = min(specFmax, freq * 1.04)
        if bandHi <= bandLo
            bandHi = min(specFmax, bandLo + 1)
        endif
        selectObject: srcLtas
        sdb = Get mean: bandLo, bandHi, "dB"
        selectObject: outLtas
        odb = Get mean: bandLo, bandHi, "dB"
        if sdb = undefined
            sdb = -300
        endif
        if odb = undefined
            odb = -300
        endif
        srcShape#[q] = sdb
        outShape#[q] = odb
        meanSrcShape += sdb
        meanOutShape += odb
    endfor
    meanSrcShape = meanSrcShape / nSpecPoints
    meanOutShape = meanOutShape / nSpecPoints

    specDiffMax = 0
    shapeSq = 0
    for q from 1 to nSpecPoints
        srcShape#[q] = srcShape#[q] - meanSrcShape
        outShape#[q] = outShape#[q] - meanOutShape
        specDelta#[q] = outShape#[q] - srcShape#[q]
        if abs(specDelta#[q]) > specDiffMax
            specDiffMax = abs(specDelta#[q])
        endif
        shapeSq += specDelta#[q]^2
    endfor
    shapeRmseDb = sqrt(shapeSq / nSpecPoints)
    specDiffRange = 5 * ceiling((specDiffMax + 1) / 5)
    if specDiffRange < 10
        specDiffRange = 10
    endif

    centroidDelta = outGlobalCentroid - srcGlobalCentroid
    durationRatio = outDur / dur

    # Round linear tick spacing.
    procedure crVizStep: .range, .target
        .raw = .range / .target
        .mag = 10 ^ floor(log10(max(1e-12, .raw)))
        .n = .raw / .mag
        if .n < 1.5
            .step = 1 * .mag
        elsif .n < 3.5
            .step = 2 * .mag
        elsif .n < 7.5
            .step = 5 * .mag
        else
            .step = 10 * .mag
        endif
    endproc

    Erase all

    # ---------------- Title ----------------
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Causal Recomposer v1.5##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half",
        ... "[" + presetName$ + "]  " + sortKeyName$ + " / " + sortDirName$
        ... + "  |  " + trajName$
        ... + "  |  " + string$(nGrains) + " -> " + string$(nOutputGrains) + " grains"
        ... + "  |  grain " + fixed$(grain_size_ms, 0) + " ms"
        ... + "  |  fade " + fixed$(effectiveFadeMs, 1) + " ms"
        ... + "  |  " + fixed$(outDur, 2) + " s"

    # ========================================================
    # A  MODEL
    # ========================================================
    Select outer viewport: 0, 4, 0.64, 0.90
    Select inner viewport: 0.18, 3.85, 0.64, 0.90
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.01, "left", 0.72, "half", "A  MODEL - measured intensity -> centroid law"
    Font size: 6
    Colour: "{0.35, 0.35, 0.50}"
    modelSub$ = "order " + string$(effectiveOrder) + " | R2 " + fixed$(rSquared,3) + " | residual RMS " + fixed$(residualRms,0) + " Hz"
    if nSilentI > 0
        modelSub$ = modelSub$ + " | " + string$(nSilentI) + " silent grains not fitted or drawn"
    endif
    if nRepairedI + nSignalI > 0
        modelSub$ = modelSub$ + " | " + string$(nRepairedI + nSignalI) + " intensity repaired"
    endif
    Text: 0.01, "left", 0.18, "half", modelSub$

    iPad = max(1, 0.04 * (maxI - minI))
    cPad = max(50, 0.08 * (maxC - minC))
    plotIMin = minI - iPad
    plotIMax = maxI + iPad
    plotCMin = max(0, minC - cPad)
    plotCMax = maxC + cPad
    for i from 1 to nGrains
        if feat_Chat#[i] < plotCMin
            plotCMin = max(0, feat_Chat#[i] - cPad)
        endif
        if feat_Chat#[i] > plotCMax
            plotCMax = feat_Chat#[i] + cPad
        endif
    endfor
    if plotIMax <= plotIMin
        plotIMax = plotIMin + 1
    endif
    if plotCMax <= plotCMin
        plotCMax = plotCMin + 100
    endif

    Select outer viewport: 0, 4, 0.90, 3.03
    Select inner viewport: 0.60, 3.85, 1.01, 2.86
    Axes: plotIMin, plotIMax, plotCMin, plotCMax
    Paint rectangle: "{0.97, 0.97, 0.97}", plotIMin, plotIMax, plotCMin, plotCMax

    # Fit curve first.
    Colour: "{0.78, 0.28, 0.22}"
    Line width: 2
    nCurve = 120
    for q from 1 to nCurve
        i0 = minI + (maxI - minI) * (q - 1) / nCurve
        i1 = minI + (maxI - minI) * q / nCurve
        if effectiveOrder = 0
            c0 = meanC
            c1 = meanC
        else
            z0 = (i0 - meanI) / sdI
            z1 = (i1 - meanI) / sdI
            c0 = 0
            c1 = 0
            zPow0 = 1
            zPow1 = 1
            for c from 1 to nCoef
                c0 += coef#[c] * zPow0
                c1 += coef#[c] * zPow1
                zPow0 *= z0
                zPow1 *= z1
            endfor
        endif
        Draw line: i0, c0, i1, c1
    endfor
    Line width: 1

    # Measured grains. No residual stems: one visual claim only.
    pointStride = ceiling(nGrains / 120)
    if pointStride < 1
        pointStride = 1
    endif
    for i from 1 to nGrains
        # silent grains are not part of the fit and have no measurable
        # centroid, so they are not drawn (v1.5)
        if (i - 1) mod pointStride = 0 and fitMask#[i] = 1
            Paint circle (mm): "{0.26, 0.48, 0.78}", feat_I#[i], feat_C#[i], 0.48
        endif
    endfor
    Select inner viewport: 0.60, 3.85, 1.01, 2.86
    Axes: plotIMin, plotIMax, plotCMin, plotCMax
    Colour: "Black"
    Draw inner box
    Font size: 6
    @crVizStep: plotIMax - plotIMin, 5
    Marks bottom every: 1, crVizStep.step, "yes", "yes", "no"
    @crVizStep: plotCMax - plotCMin, 5
    Marks left every: 1, crVizStep.step, "yes", "yes", "no"
    Font size: 7
    Text bottom: "yes", "intensity (dB)"
    Text left: "yes", "centroid (Hz)"

    # ========================================================
    # B  TRAJECTORY
    # v1.5: output position -> position, for sequences of ANY length
    # (repeats and arcs included). Grey = the common trajectory through
    # the ranked pool (rank space, where arcs and walks read as shapes);
    # blue/red = the source-time position of the grain actually placed
    # in each channel. Dotted verticals mark turning points.
    # ========================================================
    Select outer viewport: 4, 8, 0.64, 0.90
    Select inner viewport: 4.18, 7.70, 0.64, 0.90
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.01, "left", 0.72, "half", "B  TRAJECTORY - " + trajName$ + " | " + string$(nGrains) + " -> " + string$(nOutputGrains) + " grains"
    Font size: 6
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.01, "left", 0.18, "half", "dark line = rank path | dots = source time (blue L, red R) | L/R differ "
        ... + fixed$(stereoDifferentPct,1) + "\%  | " + string$(actualPairs) + " swaps | " + string$(nTurns) + if nTurns = 1 then " turn" else " turns" fi

    Font size: 6
    Select outer viewport: 4, 8, 0.90, 3.03
    Select inner viewport: 4.45, 7.70, 1.01, 2.86
    Axes: 0, 100, 0, 100
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 100, 0, 100

    if nOutputGrains > 1
        xScale = 100 / (nOutputGrains - 1)
    else
        xScale = 100
    endif

    # Turning points (arc modes only; a random walk has too many).
    if trajectory_mode = 2 or trajectory_mode = 3
        Colour: "{0.70, 0.70, 0.72}"
        Dotted line
        for q from 1 to nTurns
            xt = xScale * (turnAt#[q] - 1)
            Draw line: xt, 0, xt, 100
        endfor
        Solid line
    endif

    # Source-time position of the grain actually placed in each channel,
    # as dots: a causal order is scrambled in time, and joined lines
    # would bury the trajectory shape. Blue L underneath, smaller red R
    # on top, so a position where L and R differ shows both colours.
    for g from 1 to nOutputGrains
        Paint circle (mm): "{0.26, 0.48, 0.78}", xScale * (g - 1), 100 * (seqL#[g] - 1) / (nGrains - 1), 0.32
    endfor
    for g from 1 to nOutputGrains
        Paint circle (mm): "{0.78, 0.28, 0.22}", xScale * (g - 1), 100 * (seqR#[g] - 1) / (nGrains - 1), 0.20
    endfor

    # Common trajectory in rank space, drawn last so its shape (sweep,
    # arcs, walk) is always readable.
    Select inner viewport: 4.45, 7.70, 1.01, 2.86
    Axes: 0, 100, 0, 100
    Colour: "{0.25, 0.25, 0.30}"
    Line width: 2
    for g from 2 to nOutputGrains
        Draw line: xScale * (g - 2), 100 * (trajPos#[g - 1] - 1) / (nGrains - 1),
            ... xScale * (g - 1), 100 * (trajPos#[g] - 1) / (nGrains - 1)
    endfor
    Line width: 1

    Select inner viewport: 4.45, 7.70, 1.01, 2.86
    Axes: 0, 100, 0, 100
    Colour: "Black"
    Draw inner box
    Font size: 6
    Marks bottom every: 1, 20, "yes", "yes", "no"
    Marks left every: 1, 20, "yes", "yes", "no"
    Font size: 7
    Text bottom: "yes", "output position (\% )"
    Text left: "yes", "rank / source position (\% )"

    # ========================================================
    # C  SPLICE
    # ========================================================
    Select outer viewport: 0, 4, 3.13, 3.39
    Select inner viewport: 0.18, 3.85, 3.13, 3.39
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.01, "left", 0.72, "half", "C  SPLICE - actual edge taper + OLA denominator"
    Font size: 6
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.01, "left", 0.18, "half", "blue = one source-grain gain | red = normalization weight | fade " + fixed$(effectiveFadeMs,1) + " ms | hop " + fixed$(1000*synthStepSec,1) + " ms"

    geomXmax = grainSec + 2 * synthStepSec
    geomMax = 1
    for q from 0 to 220
        tq = geomXmax * q / 220
        wsum = 0
        for kk from 0 to 12
            ws = kk * synthStepSec
            localT = tq - ws
            if localT >= 0 and localT <= grainSec
                if effectiveFadeSec > 0
                    if localT < effectiveFadeSec
                        w = 0.5 - 0.5*cos(pi*localT/effectiveFadeSec)
                    elsif localT > grainSec - effectiveFadeSec
                        w = 0.5 - 0.5*cos(pi*(grainSec-localT)/effectiveFadeSec)
                    else
                        w = 1
                    endif
                else
                    w = 1
                endif
                wsum += w
            endif
        endfor
        if wsum > geomMax
            geomMax = wsum
        endif
    endfor
    geomYmax = max(1.15, 1.10 * geomMax)

    Select outer viewport: 0, 4, 3.39, 5.52
    Select inner viewport: 0.60, 3.85, 3.50, 5.35
    Axes: 0, 1000*geomXmax, 0, geomYmax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1000*geomXmax, 0, geomYmax

    # One actual local grain gain window.
    Colour: "{0.26, 0.48, 0.78}"
    Line width: 2
    nDraw = 160
    for q from 1 to nDraw
        t0 = grainSec * (q - 1) / nDraw
        t1 = grainSec * q / nDraw
        if effectiveFadeSec > 0
            if t0 < effectiveFadeSec
                w0 = 0.5 - 0.5*cos(pi*t0/effectiveFadeSec)
            elsif t0 > grainSec - effectiveFadeSec
                w0 = 0.5 - 0.5*cos(pi*(grainSec-t0)/effectiveFadeSec)
            else
                w0 = 1
            endif
            if t1 < effectiveFadeSec
                w1 = 0.5 - 0.5*cos(pi*t1/effectiveFadeSec)
            elsif t1 > grainSec - effectiveFadeSec
                w1 = 0.5 - 0.5*cos(pi*(grainSec-t1)/effectiveFadeSec)
            else
                w1 = 1
            endif
        else
            w0 = 1
            w1 = 1
        endif
        Draw line: 1000*t0, w0, 1000*t1, w1
    endfor

    # Red = actual normalization denominator from the overlap pattern.
    Colour: "{0.78, 0.28, 0.22}"
    Line width: 1.5
    for q from 1 to 220
        t0 = geomXmax * (q - 1) / 220
        t1 = geomXmax * q / 220
        sum0 = 0
        sum1 = 0
        for kk from 0 to 12
            ws = kk * synthStepSec
            u0 = t0 - ws
            u1 = t1 - ws
            if u0 >= 0 and u0 <= grainSec
                if effectiveFadeSec > 0
                    if u0 < effectiveFadeSec
                        w0 = 0.5 - 0.5*cos(pi*u0/effectiveFadeSec)
                    elsif u0 > grainSec - effectiveFadeSec
                        w0 = 0.5 - 0.5*cos(pi*(grainSec-u0)/effectiveFadeSec)
                    else
                        w0 = 1
                    endif
                else
                    w0 = 1
                endif
                sum0 += w0
            endif
            if u1 >= 0 and u1 <= grainSec
                if effectiveFadeSec > 0
                    if u1 < effectiveFadeSec
                        w1 = 0.5 - 0.5*cos(pi*u1/effectiveFadeSec)
                    elsif u1 > grainSec - effectiveFadeSec
                        w1 = 0.5 - 0.5*cos(pi*(grainSec-u1)/effectiveFadeSec)
                    else
                        w1 = 1
                    endif
                else
                    w1 = 1
                endif
                sum1 += w1
            endif
        endfor
        Draw line: 1000*t0, sum0, 1000*t1, sum1
    endfor
    Line width: 1

    Select inner viewport: 0.60, 3.85, 3.50, 5.35
    Axes: 0, 1000*geomXmax, 0, geomYmax
    Colour: "Black"
    Draw inner box
    Font size: 6
    @crVizStep: 1000*geomXmax, 5
    Marks bottom every: 1, crVizStep.step, "yes", "yes", "no"
    @crVizStep: geomYmax, 4
    Marks left every: 1, crVizStep.step, "yes", "yes", "no"
    Font size: 7
    Text bottom: "yes", "time (ms)"
    Text left: "yes", "gain / weight"

    # ========================================================
    # D  CHECK
    # ========================================================
    Select outer viewport: 4, 8, 3.13, 3.39
    Select inner viewport: 4.18, 7.70, 3.13, 3.39
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.01, "left", 0.72, "half", "D  CHECK - stereo MID spectral-shape difference"
    Font size: 6
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.01, "left", 0.18, "half", "MID - mono source | shape RMSE " + fixed$(shapeRmseDb,2) + " dB | SIDE/MID " + sideMidLabel$

    Select outer viewport: 4, 8, 3.39, 5.52
    Select inner viewport: 4.45, 7.70, 3.50, 5.35
    Axes: logFmin, logFmax, -specDiffRange, specDiffRange
    Paint rectangle: "{0.97, 0.97, 0.97}", logFmin, logFmax, -specDiffRange, specDiffRange
    # Quiet reference band around zero.
    bandRef = min(3, specDiffRange)
    Paint rectangle: "{0.92, 0.92, 0.92}", logFmin, logFmax, -bandRef, bandRef
    Colour: "{0.60, 0.60, 0.64}"
    Draw line: logFmin, 0, logFmax, 0

    Colour: "{0.26, 0.48, 0.78}"
    Line width: 1.8
    for q from 2 to nSpecPoints
        Draw line: log10(specFreq#[q-1]), specDelta#[q-1], log10(specFreq#[q]), specDelta#[q]
    endfor
    Line width: 1

    Select inner viewport: 4.45, 7.70, 3.50, 5.35
    Axes: logFmin, logFmax, -specDiffRange, specDiffRange
    Colour: "Black"
    Draw inner box
    Font size: 6
    Marks left every: 1, max(5, specDiffRange/2), "yes", "yes", "no"
    freqTicks# = {50,100,200,500,1000,2000,5000,10000,16000}
    for k from 1 to size(freqTicks#)
        ft = freqTicks#[k]
        if ft >= specFmin and ft <= specFmax
            if ft >= 1000
                flab$ = fixed$(ft/1000,1) + "k"
            else
                flab$ = fixed$(ft,0)
            endif
            One mark bottom: log10(ft), "no", "yes", "no", flab$
        endif
    endfor
    Font size: 7
    Text bottom: "yes", "frequency (Hz, log)"
    Text left: "yes", "MID - mono source (dB)"

    # ---------------- Summary strip ----------------
    Select outer viewport: 0, 8, 5.62, 6.19
    Select inner viewport: 0.60, 7.70, 5.67, 6.14
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    if trajectory_mode = 3
        trajSum$ = trajName$ + " x" + string$(nCyclesUsed)
    elsif trajectory_mode = 4
        trajSum$ = trajName$ + " " + fixed$(random_walk_variation, 0) + "\%  seed "
        if random_seed > 0
            trajSum$ = trajSum$ + string$(random_seed)
        else
            trajSum$ = trajSum$ + "free"
        endif
    else
        trajSum$ = trajName$
    endif
    Text: 0.02, "left", 0.80, "half",
        ... "##Sort##  " + sortKeyName$ + " / " + sortDirName$
        ... + "   ##Trajectory##  " + trajSum$
        ... + "   ##Continuity##  " + fixed$(temporal_continuity_percent, 0) + "\%  "
        ... + "   ##Grains##  " + string$(nGrains) + " -> " + string$(nOutputGrains)
        ... + "   ##Out##  " + fixed$(outDur, 2) + " s"
    Text: 0.02, "left", 0.50, "half",
        ... "##Stereo##  " + fixed$(stereo_divergence_percent, 0) + "\%  swap amount -> L/R differ "
        ... + fixed$(stereoDifferentPct, 1) + "\%  (" + string$(actualPairs) + " pairs)"
        ... + "   rank sep " + fixed$(stereoOrderSeparationPct, 3) + "\%  "
        ... + "   SIDE/MID " + sideMidLabel$
        ... + "   ##Model##  order " + string$(effectiveOrder) + "   R^2 " + fixed$(rSquared, 3)
        ... + "   fade " + fixed$(effectiveFadeMs, 1) + " ms"
    Text: 0.02, "left", 0.20, "half",
        ... "##Chain##  mono grain pool (" + monoMethod$ + ") -> causal rank -> continuity blend"
        ... + " -> trajectory -> local L/R swaps -> stereo overlap-add"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # Restore the full page as the last drawing action, so Save as PNG /
    # Copy to clipboard capture the whole figure rather than cropping to
    # the summary strip.
    Select outer viewport: 0, 8, 0, 6.19
    Font size: 10
    Colour: "Black"
    Line width: 1

    removeObject: vizL, vizR, vizMid, vizSide, srcSpec, outSpec, srcLtas, outLtas
endif

# ============================================================
# OUTPUT
# ============================================================
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Effective model order: ", effectiveOrder, " (requested ", requestedOrder, ")"
appendInfoLine: "Fit R^2: ", fixed$(rSquared, 3), " | residual RMS: ", fixed$(residualRms, 1), " Hz"
appendInfoLine: "Trajectory: ", trajName$, trajDetail$, " | continuity ", fixed$(temporal_continuity_percent, 0), "%"
if trajectory_mode = 3 and nCyclesUsed <> number_of_cycles
    appendInfoLine: "  cycles used: ", nCyclesUsed, " (requested ", number_of_cycles, ")"
endif
appendInfoLine: "Grains: ", nGrains, " source -> ", nOutputGrains, " output (", nDistinct, " distinct, ",
    ... nTurns, " turning points)"
appendInfoLine: "Intensity readings: ", nMeasuredI, " measured, ", nRepairedI, " repaired, ",
    ... nSignalI, " signal-RMS fallback, ", nSilentI, " silent (excluded from fit, ", nFit, " grains fitted)"
appendInfoLine: "Mean displacement from source chronology (L/R average): ", fixed$(meanDisplacementPct, 1), "%"
appendInfoLine: "Stereo divergence: ", fixed$(stereo_divergence_percent, 1), "% requested swap amount -> ",
    ... actualPairs, " swap pairs (", targetPairs, " requested)"
appendInfoLine: "L/R differing output positions (measured): ", fixed$(stereoDifferentPct,1), "% | mean causal-rank separation: ", fixed$(stereoOrderSeparationPct,3), "%"
appendInfoLine: "Broken source adjacencies: ", fixed$(adjacencyBreakPct, 1), "%"
appendInfoLine: "Effective crossfade: ", fixed$(effectiveFadeMs, 1), " ms"
appendInfoLine: "Output channels: ", outChannels, " generated from mono grain pool (source had ", nChannels, " ch)"
appendInfoLine: "Output duration: ", fixed$(outDur, 2), " s  (source ", fixed$(dur, 2), " s)"
appendInfoLine: "Output peak: ", fixed$(outPeak, 4), " | RMS: ", fixed$(outRms, 4)
if warnLines$ <> ""
    appendInfoLine: ""
    appendInfoLine: "Adjustments made during processing:"
    appendInfo: warnLines$
endif

removeObject: workSnd, intensityObj
selectObject: outBuf

if play_result
    appendInfoLine: "Playing..."
    Play
endif

# ============================================================
# PROCEDURES
# ============================================================

# Stable argsort (v1.5). Sorts the item ids in sortIdx#[1..n]
# ascending by sortVal#[id]; items with equal values keep their input
# order. Bottom-up merge sort, O(n log n). sortVal# is indexed by item
# id, so it may be longer than n (a subset of items can be sorted).
procedure stableArgsort: .n
    .width = 1
    while .width < .n
        .tmp# = zero#(.n)
        .lo = 1
        while .lo <= .n
            .mid = min(.lo + .width - 1, .n)
            .hi = min(.lo + 2 * .width - 1, .n)
            .a = .lo
            .b = .mid + 1
            for .k from .lo to .hi
                .takeA = 0
                if .a <= .mid
                    if .b > .hi
                        .takeA = 1
                    elsif sortVal#[sortIdx#[.a]] <= sortVal#[sortIdx#[.b]]
                        .takeA = 1
                    endif
                endif
                if .takeA = 1
                    .tmp#[.k] = sortIdx#[.a]
                    .a += 1
                else
                    .tmp#[.k] = sortIdx#[.b]
                    .b += 1
                endif
            endfor
            .lo = .lo + 2 * .width
        endwhile
        sortIdx# = .tmp#
        .width = .width * 2
    endwhile
endproc
