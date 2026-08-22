# ============================================================
# Praat AudioTools - Genetic_Recomposer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.5 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Genetic algorithm that evolves segment-recombination parameters
#   to produce a target-length recomposition of an input sound.
#   Each genome encodes 8 parameters controlling segmentation grain,
#   bias toward short/long segments, reorder probability, crossfade,
#   and silence insertion. Fitness rewards a preset-dependent
#   combination of onset density, spectral similarity to input, and
#   envelope regularity.
#
# Changelog v1.6 (2026) -- visualization uniformity pass; no change to
# the GA, segmentation, synthesis or fitness evaluation:
#   - FIX: five caption/label collisions. Panels were stacked with
#     ~0.10 in of margin while carrying BOTH a Text top caption and a
#     Text bottom axis label, and Praat does not clip either to the
#     viewport. In v1.5: the GA Result panel's duration caption printed
#     on top of the Original panel's bottom border; "Time (s)" landed on
#     the "Evolution:" caption; "Generation" landed on the "Segment
#     pool" caption; "Output time (s)" landed on "Result spectrogram";
#     and the spectrogram's "Time (s)" was partly hidden behind the
#     summary strip. Every panel now gets 0.15 in of headroom above the
#     inner viewport when it carries a top caption and 0.30 in below it
#     when it carries a bottom label. Page height grows 8.00 -> 8.25 in.
#   - FIX: two bare percent signs. A bare % in Praat drawn text
#     italicizes the following character and prints nothing, so the
#     summary read "Reorder: 0" and "Silence: 8, 30-69 ms" instead of
#     "Reorder: 0\%" and "Silence: 8\%, 30-69 ms".
#   - FIX: the Sound name was drawn raw and Praat reads "_" as a
#     subscript marker, so "a_vox" printed as "a(sub v)ox". Escaped for
#     display only.
#   - FIX: drawing ended inside the summary strip, so Save as PNG and
#     Copy to clipboard exported that strip alone (2375 x 268 px)
#     rather than the page. Drawing now ends on the full page.
#   - Title block to the library standard: explicit inner viewport,
#     title y = 0.68 / subtitle y = 0.22, subtitle font 9 -> 7 and
#     colour {0.4, 0.4, 0.5} -> {0.35, 0.35, 0.50}.
#   - Half-width inner viewports 0.6/3.7 and 4.4/7.7 -> the standard
#     0.60/3.85 and 4.45/7.70.
#   - Fonts: the fitness and genome panels labelled their axes at 6
#     while every other panel used 7; the genome bar labels were at 5,
#     a size used nowhere else in the category. Now 7 and 6.
#   - Colours: three near-identical panel grounds ({0.97, 0.98, 0.97},
#     {0.98, 0.97, 0.97}, {0.98, 0.98, 0.96}) unified to
#     {0.97, 0.97, 0.97}; the two input-waveform greys ({0.6, 0.6, 0.6}
#     and {0.65, 0.65, 0.65}, both meaning "the input") unified to
#     {0.60, 0.60, 0.60}; reference diagonal to {0.80, 0.80, 0.80};
#     bar-label text {0.3, 0.3, 0.3} -> {0.25, 0.25, 0.35}. All tuples
#     rewritten to the 2-decimal convention. Hues otherwise unchanged,
#     pending the palette decision.
#
# Changelog v1.5 (2026) -- fourth review-driven correctness pass:
#   - FIX (spectral silence-gating was still gain-dependent): every
#     candidate is peak-normalized (Scale peak: 0.95) before its chunk
#     RMS values feed the refQuiet/candQuiet gate in
#     calculateFitnessFAST, but refMono (the source of refChunkRms#)
#     was never normalized to that same scale. A quiet-but-not-silent
#     input could then have every reference chunk classified "quiet"
#     while every (now peak-normalized) candidate chunk was classified
#     "active" -- collapsing spectralSim to 0 for the ENTIRE
#     population regardless of actual similarity. refMono is now
#     scaled to the same peak as candidates before any RMS, centroid,
#     or spread is measured from it (centroid/spread are amplitude-
#     invariant, so only the RMS-based gate is actually affected).
#   - FIX (Custom mode could hand Initialize Population a reversed
#     randomUniform range): the earlier validation only checked
#     min_seg_ms < max_seg_ms, but effect_strength scales min_seg_ms
#     DOWN and max_seg_ms UP by different factors, and every gene pair
#     in this genome needs a 10ms gap (segMax >= segMin + 10) to stay
#     repairable. A narrow Custom range could pass the raw min<max
#     check yet leave less than 10ms of room after scaling, handing
#     segMaxMs's randomUniform call a lower bound above its upper
#     bound. A new check on the EFFECTIVE (post-scaling) range now
#     catches this with a clear message before initialization runs.
#   - FIX (rare short-output path after iteration-cap padding): if the
#     hard iteration cap was hit, padding aimed exactly at
#     target_duration_s, but Concatenate with overlap then shortens
#     the whole assembly by safeXfade at the final join -- so the
#     result could still land safeXfade seconds short of target
#     AFTER concatenation, undetected by the existing "trim if too
#     long" check. The result's duration is now checked again after
#     concatenation and topped up with a plain (non-overlapping)
#     silence tail if still short, so target_duration_s is always met
#     exactly regardless of which path produced the shortfall.
#   - FIX (0.0005s exact-boundary gap): the per-segment micro-fade was
#     skipped only when .xfade < 0.0005s, while Concatenate with
#     overlap engaged only when .safeXfade > 0.0005s -- a crossfade of
#     EXACTLY 0.0005s fell into neither protection. The micro-fade
#     condition is now <= 0.0005s, so every value is covered by
#     exactly one of the two.
#
# Changelog v1.5 (2026) -- third review-driven correctness pass:
#   - FIX (mutation could re-break the min/max gene pairs crossover
#     had just repaired): each of the 8 genes mutates independently,
#     so e.g. silenceMin could mutate upward with silenceMax
#     untouched, landing back on min > max even though crossover's
#     repair step had just fixed it. A second repair now runs AFTER
#     mutation, immediately before the new generation replaces the
#     old one, and pushes the pair apart from whichever side has
#     room left within its own bound (not just the max side) so the
#     repair itself can't be pushed out of range.
#   - FIX (onset/regularity noise floor still depended on the
#     original recording's gain): using the candidate's own intensity
#     MINIMUM as a +3dB floor failed whenever the candidate itself
#     contained inserted digital silence (one of the genome's own
#     genes) -- the minimum IS near-silence, so the floor barely
#     filtered anything and onset counting could reward silence-and-
#     repeat patterns instead of real fragmentation. Both the onset
#     floor and the regularity floor are now relative to the
#     CANDIDATE's own intensity MAXIMUM (max - 55 dB / max - 60 dB),
#     computed once per candidate -- gain-invariant regardless of the
#     original recording's level, and no longer confused by the
#     candidate's own silence gene.
#   - FIX (spectral trajectory undefined on silent chunks): a chunk
#     that lands entirely in silence (either from the input's own
#     content, or a candidate's inserted silence gene) has an
#     undefined/degenerate centroid and spread, which could pollute
#     spectralSim (and the fitness comparisons built on it) with a
#     meaningless number. Each chunk pair is now RMS-gated: both
#     sides quiet -> counted as a good match (distance 0); only one
#     side quiet -> counted as a full mismatch (distance 1); both
#     active -> centroid/spread distance as before.
#   - REMOVED Fitness_stride from the form: it no longer had any
#     effect after the cheap/full split was removed in v1.4, but
#     stayed visible under "Quality / Speed" where a user would
#     reasonably expect changing it to do something. It's gone
#     entirely rather than renamed, since a misleading control is
#     worse than a slightly less compatible settings file.
#   - FIX (missing fade-in / threshold mismatch): a final fade-out
#     was added in v1.4 for the exact-duration trim point, but
#     nothing protected the very START of the output -- when
#     crossfade is active, Concatenate with overlap smooths INTERNAL
#     joins but not the leading edge of the first segment, so a
#     waveform-cycle discontinuity at t=0 could still click. A
#     matching final fade-in is now applied alongside the fade-out.
#     Separately, the per-segment micro-fade was skipped whenever
#     .xfade < 0.0005 s while overlap-concatenation required
#     .safeXfade > 0.001 s to engage -- crossfades between roughly
#     0.5-1 ms fell in neither protection. Both thresholds are now
#     the same value.
#   - FIX (iteration cap could silently return short output): if the
#     v1.4 hard iteration cap in synthesizeCandidate is ever actually
#     hit, the candidate is now padded with trailing silence up to
#     the target duration (so downstream trimming/fitness code still
#     sees the expected length), and the run prints a one-line
#     summary warning at the end if this happened for any candidate,
#     instead of staying silent about a short result.
#   - DOC: v1.4's per-generation shared seed makes within-generation
#     comparisons fair, but best-ever is still compared ACROSS
#     generations that each used a different seed, so the winning
#     genome is best described as a winning genome+seed realization
#     found during the search, not a genome verified stable across
#     random draws. No multi-seed re-evaluation is added (would
#     multiply per-candidate cost); documented here as a known,
#     intentional scope limit rather than a bug.
#
# Changelog v1.4 (2026) -- review-driven correctness pass:
#   - FIX (selection bias): "cheap" generations scored onset and
#     regularity as a constant 0.5 for the whole population, so
#     tournament selection was driven ENTIRELY by spectralSim --
#     100% spectral ranking on generations meant to optimize 70-80%
#     onset/regularity presets (Glitch, Extreme Fragmentation,
#     Rhythmic Loops). Every generation now computes full fitness.
#     every generation now computes full fitness. At default
#     population/generation sizes this is at most ~225 candidate
#     evaluations (Extreme preset) -- affordable, and the only way to
#     guarantee selection actually optimizes what each preset
#     declares.
#   - FIX (possible infinite loop): if every pool segment is shorter
#     than 2*crossfade + 2ms, Phase 2's synthesis loop could never
#     advance .currentTime and would spin forever. The pool is now
#     checked for at least one segment long enough to carry the
#     genome's crossfade; if none exists, the crossfade used for that
#     candidate is reduced to fit the pool instead of hanging. A hard
#     iteration cap is also added as a last-resort safety net.
#   - FIX (unstable random realization): every candidate synthesis
#     used a unique seed (base + running counter), so two genomes
#     were never compared under the same random draw, and the elite
#     genome carried forward to the next generation was NOT
#     re-synthesized with its own winning seed during evolution (only
#     at final render) -- fitness was effectively measuring
#     genome + a fresh lucky realization each time. All individuals
#     within one generation now share one per-generation seed, so
#     within-generation comparisons are apples-to-apples; seeds still
#     vary across generations so the search doesn't get stuck on one
#     realization.
#   - FIX (regularity ACF wasn't normalized): num/den used only the
#     lag-0 signal's energy in the denominator, so the "correlation"
#     could exceed 1 (silently clipped) and different envelopes could
#     tie at the clipped ceiling. Now a proper Pearson-style
#     normalization (sqrt of the product of BOTH sides' energy) is
#     used, so it is bounded in [-1, 1] before clipping to [0, 1].
#     Candidate lags are now derived from THIS genome's own typical
#     segment duration (as documented) instead of one fixed list that
#     ignored segMin/segMax entirely.
#   - FIX (silence floor for regularity floored relative to the
#     INPUT's own minimum, which is near -300 dB for near-silent
#     inputs, defeating the floor entirely): floor is now relative to
#     the intensity RANGE (max - 60 dB), not an offset from the
#     minimum.
#   - FIX (click at the very end of trimmed output): the exact-length
#     trim can land mid-segment/mid-waveform-cycle; a short fade-out
#     is now applied AFTER the final trim, not just at the original
#     (now possibly discarded) segment edge.
#   - FIX (onset threshold depended on input gain, not candidate
#     gain): every candidate is peak-normalized (Scale peak: 0.95),
#     but the onset noise floor came from the ORIGINAL input's
#     intensity minimum -- a quiet input made the floor essentially
#     -300 dB and filtered nothing. The floor is now computed from
#     the CANDIDATE's own intensity minimum.
#   - FIX (onset saturation same for every preset): 8 onsets/sec
#     saturated .onsetScore to 1.0 regardless of preset, so
#     Extreme Fragmentation (80% onset weight, 10-80ms segments)
#     could not discriminate among its own high-onset population.
#     The saturation point now scales with the preset's onset weight
#     (higher w_onset -> higher bar to clear 1.0).
#   - FIX (spectralSim barely discriminated within one input):
#     a single whole-file centroid/spread comparison changes very
#     little when segments of the SAME input are merely reordered.
#     spectralSim now compares short-window (chunked) centroid/spread
#     TRAJECTORIES against the input's own trajectory, which is
#     sensitive to how the material was actually recombined in time.
#   - FIX (reorderProb=0 was not sequential): the "sequential-ish"
#     branch always jumped +/-30% of the pool regardless of
#     reorderProb, so reorderProb=0 was already a fairly wide local
#     random walk, not near-original order. The local jump range is
#     now scaled BY reorderProb itself (0 -> next segment exactly,
#     approaching the old wide walk as reorderProb -> 1).
#   - ADDED uniform crossover: evolvePopulation used to clone one
#     tournament-selected parent's genome wholesale before mutation
#     (mutation-only search, no recombination of two parents). Each
#     of the 8 genes is now drawn independently from one of two
#     tournament-selected parents before mutation is applied.
#   - ADDED input/parameter validation: Effect_strength, segment
#     range ordering, Max_silence_prob range, crossfade-vs-segment-
#     range consistency, minimum usable input duration, and
#     population/generation sanity are all checked up front with a
#     clear exitScript message instead of failing deep inside the GA.
#   - FIX (double-fade at crossfaded joins): the 2ms per-segment edge
#     fade is now skipped when the genome's crossfade is actually
#     going to be used for that join (Concatenate with overlap
#     already fades both sides); it still applies when crossfade is
#     effectively off, so raw butt-joints don't click.
#   - DOC: seed and preset weights are printed to the Info window
#     regardless of whether visualization is drawn (previously only
#     shown in the visualization summary strip).
#
# Changelog v1.3 (2026):
#   - FIX: output duration. Concatenate-with-overlap shortens the
#     result by (nParts - 1) * crossfade, but .currentTime ignored
#     the overlap, so glitch presets (hundreds of parts) came out
#     SECONDS short of target. Accounting is now overlap-aware and
#     deliberately conservative (never under-builds; trim handles
#     the small overshoot).
#   - FIX: true reproducibility of the best-ever candidate. The
#     synthesis is stochastic, so re-rendering the best GENOME gave
#     a different random phenotype than the one that actually won.
#     Every synthesis is now seeded (base seed + counter); the
#     winning candidate's seed is snapshotted with its genome, and
#     the final render re-seeds with it -- the output IS the
#     best-ever candidate, sample for sample.
#   - FIX: cheap/expensive fitness scores were compared in the same
#     best-ever ledger (cheap scores pad onset/regularity with a
#     neutral 0.5). Best-ever now only updates on full-fitness
#     generations, and the LAST generation is always full-fitness.
#     Elitism guards against injecting the zero genome before the
#     first full-fitness generation.
#   - FIX: one tiny part in the pool capped safeXfade for the WHOLE
#     concatenation (clicks everywhere). Minimum part duration now
#     covers 2x the genome crossfade, for silences too.
#   - FIX: envelope-regularity ACF was dominated by -300 dB silent
#     frames (deviations of ~250 dB drown the musical envelope);
#     values are now floored at refIntMin - 10 dB before the ACF.
#   - FIX: population init could call randomUniform with a reversed
#     range when min_seg_ms > 0.4 * max_seg_ms.
#   - VIZ: stale "v1.1" title corrected; seed reported in summary.
#
# Changelog v1.2 (2026):
#   - FIX: Best-ever tracking used to store genome INDEX only, which
#     aliased to a different genome after evolution. Now snapshots
#     all 8 parameter values so the final render reproduces the true
#     best-ever candidate, not whatever sits at that slot last.
#   - FIX: Fitness function was dominated by a near-constant term
#     (sd/rms ratio is always ~1 for any audio; mean/rms is always
#     ~0 for AC-coupled audio) plus a voiced-frame term that
#     penalised exactly the aesthetics most presets aimed for
#     (glitch, fragmentation). Replaced with three measurable
#     quantities — onset density, spectral similarity to input,
#     envelope regularity — combined with preset-specific weights.
#   - FIX: Added elitism. The best-ever genome is forced into the
#     next generation, preventing loss through tournament selection.
#   - VIZ: Added segmentation panel showing input waveform with
#     segment boundaries as ticks, plus a playback-order strip
#     showing which original-time each output chunk came from.
#   - VIZ: Fitness curve now shows min/mean/max per generation,
#     not just the best, so population convergence is visible.
#   - DOC: Preset-to-fitness-weight mapping documented inline.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

inputSound = selected("Sound")
soundName$ = selected$("Sound")

form GA Segment Recombination v1.6
    comment === Presets ===
    optionmenu Preset: 1
        option Custom
        option Subtle Texture
        option Granular Shimmer
        option Glitch / Stutter
        option Extreme Fragmentation
        option Rhythmic Loops
    comment === Output ===
    positive Target_duration_s 8.0
    comment === Effect Strength (1-10) ===
    positive Effect_strength 6
    comment === Quality / Speed ===
    positive Pop_size 10
    positive Generations 10
    comment === Segmentation (ms) ===
    positive Min_seg_ms 20
    positive Max_seg_ms 180
    comment === Texture ===
    positive Max_crossfade_ms 6
    real Max_silence_prob 0.25
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

###############################################################################
# APPLY PRESET
#
# Each preset also specifies how the GA's fitness should weight the three
# measurable quantities:
#   w_onset    — reward outputs with high onset density (sharp intensity
#                jumps per second). Good for glitch/fragmentation aesthetics.
#   w_spectral — reward outputs whose spectrum resembles the input's. Good
#                for subtle/coherent aesthetics.
#   w_regular  — reward outputs with high envelope autocorrelation (i.e.,
#                repeating rhythmic patterns). Good for loop aesthetics.
# The weights sum to 1 and drive what the GA actually selects for.
###############################################################################

if preset = 2
    # SubtleTexture: gentle, keep the input's spectral character.
    effect_strength = 3
    pop_size = 8
    generations = 8
    max_crossfade_ms = 8
    max_silence_prob = 0.15
    presetName$ = "SubtleTexture"
    w_onset = 0.10
    w_spectral = 0.70
    w_regular = 0.20
elsif preset = 3
    # GranularShimmer: spectral activity + some onset structure.
    effect_strength = 5
    pop_size = 12
    generations = 12
    max_crossfade_ms = 12
    max_silence_prob = 0.20
    presetName$ = "GranularShimmer"
    w_onset = 0.35
    w_spectral = 0.40
    w_regular = 0.25
elsif preset = 4
    # GlitchStutter: maximum onset density, minimal coherence constraint.
    effect_strength = 8
    pop_size = 10
    generations = 10
    max_crossfade_ms = 3
    max_silence_prob = 0.45
    presetName$ = "GlitchStutter"
    w_onset = 0.70
    w_spectral = 0.10
    w_regular = 0.20
elsif preset = 5
    # ExtremeFrag: all-in on fragmentation.
    effect_strength = 10
    min_seg_ms = 10
    max_seg_ms = 80
    pop_size = 15
    generations = 15
    max_crossfade_ms = 2
    max_silence_prob = 0.50
    presetName$ = "ExtremeFrag"
    w_onset = 0.80
    w_spectral = 0.05
    w_regular = 0.15
elsif preset = 6
    # RhythmicLoops: strong repetition, moderate onsets.
    effect_strength = 6
    min_seg_ms = 50
    max_seg_ms = 250
    pop_size = 12
    generations = 12
    max_crossfade_ms = 8
    max_silence_prob = 0.10
    presetName$ = "RhythmicLoops"
    w_onset = 0.25
    w_spectral = 0.25
    w_regular = 0.50
else
    presetName$ = "Custom"
    w_onset = 0.34
    w_spectral = 0.33
    w_regular = 0.33
endif

###############################################################################
# v1.4: VALIDATION -- catch bad parameter combinations here, with a clear
# message, instead of failing deep inside the GA loop or the synthesis loop.
###############################################################################

if effect_strength < 1 or effect_strength > 10
    exitScript: "Effect_strength must be between 1 and 10 (got ", effect_strength, ")."
endif
if min_seg_ms >= max_seg_ms
    exitScript: "Min_seg_ms (", min_seg_ms, ") must be less than Max_seg_ms (", max_seg_ms, ")."
endif
if max_silence_prob < 0 or max_silence_prob > 1
    exitScript: "Max_silence_prob must be between 0 and 1 (got ", max_silence_prob, ")."
endif
if pop_size < 2
    exitScript: "Pop_size must be at least 2 (got ", pop_size, ")."
endif
if generations < 1
    exitScript: "Generations must be at least 1 (got ", generations, ")."
endif
if target_duration_s < 0.2
    exitScript: "Target_duration_s is too short to be usable (got ", target_duration_s, " s)."
endif

###############################################################################
# SETUP
###############################################################################

clearinfo
writeInfoLine: "=== GA Segment Recomposer v1.6 ==="
appendInfoLine: "Input: ", soundName$
appendInfoLine: "Target duration: ", target_duration_s, " s"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Effect strength: ", effect_strength, "/10"
appendInfoLine: "Fitness weights: onset=", fixed$(w_onset, 2),
    ... " spectral=", fixed$(w_spectral, 2),
    ... " regular=", fixed$(w_regular, 2)
appendInfoLine: ""

selectObject: inputSound
inputDuration = Get total duration
inputSampleRate = Get sampling frequency
inputChannels = Get number of channels

# v1.4: an input too short to hold even one minimal segment, or one
# that is entirely (near-)silent, would produce an unusable segment
# pool and/or undefined spectral reference features -- catch both
# before any GA work starts.
if inputDuration < 0.05
    exitScript: "Input sound is too short to segment (", fixed$(inputDuration, 3), " s)."
endif
inputRms = Get root-mean-square: 0, 0
if inputRms < 1e-6
    exitScript: "Input sound appears to be silent (RMS ~ 0); there is no material to recompose."
endif

appendInfoLine: "Original duration: ", fixed$(inputDuration, 2), " s"
appendInfoLine: "Sample rate: ", inputSampleRate, " Hz"
appendInfoLine: ""

###############################################################################
# COMPUTE REFERENCE FEATURES OF INPUT (once, reused for fitness)
#
# spectralSim fitness component compares a candidate's spectral centroid
# and spread to the INPUT's. We compute the input's reference values
# here, once, rather than per-fitness-call.
###############################################################################

selectObject: inputSound
inputForRefFeats = Copy: "input_feats_tmp"
# Convert to mono for feature consistency
if inputChannels > 1
    refMono = Convert to mono
    removeObject: inputForRefFeats
else
    refMono = inputForRefFeats
endif

# v1.5: every candidate is peak-normalized (Scale peak: 0.95) before
# its chunk RMS values are computed in calculateFitnessFAST, but
# refMono previously was NOT -- so chunkSilenceRms (an absolute
# threshold) compared the reference and the candidate on two
# different gain scales. A quiet-but-not-silent input could then have
# every refChunk classified "quiet" while every (now-normalized)
# candidate chunk was classified "active", collapsing spectralSim to
# 0 for the whole population regardless of actual similarity.
# Normalizing refMono here, before any RMS/centroid/spread is
# measured from it, puts both sides on the same scale. Centroid and
# spread are amplitude-invariant so this doesn't affect them; it only
# fixes the RMS-based quiet/active gate.
selectObject: refMono
Scale peak: 0.95

selectObject: refMono
refSpec = To Spectrum: "yes"
refCentroid = Get centre of gravity: 2
refSpread = Get standard deviation: 2
removeObject: refSpec

# Reference intensity envelope for onset-density scaling
selectObject: refMono
refIntensity = To Intensity: 100, 0, "yes"
refIntMean = Get mean: 0, 0, "dB"
refIntMin = Get minimum: 0, 0, "Parabolic"
refIntMax = Get maximum: 0, 0, "Parabolic"
removeObject: refIntensity

# v1.4: a single whole-file centroid/spread barely moves when segments
# of the SAME input are merely reordered, so spectralSim could not
# discriminate much between candidates. We additionally record a
# short-window centroid/spread TRAJECTORY across the input (nChunks
# equal windows) so the fitness function can compare how the
# recombination changed the spectral shape over time, not just its
# whole-file average.
#
# v1.5: a chunk that is itself (near-)silent has an undefined or
# meaningless centroid/spread, so its RMS is also recorded here --
# the fitness function gates on it before trusting the spectral
# numbers for that chunk (see calculateFitnessFAST).
chunkSilenceRms = 0.001
nSpecChunks = 6
refChunkCentroid# = zero#(nSpecChunks)
refChunkSpread# = zero#(nSpecChunks)
refChunkRms# = zero#(nSpecChunks)
chunkDur = inputDuration / nSpecChunks
for .c to nSpecChunks
    .t1 = (.c - 1) * chunkDur
    .t2 = .t1 + chunkDur
    selectObject: refMono
    Extract part: .t1, .t2, "rectangular", 1, "no"
    .chunkSnd = selected("Sound")
    refChunkRms#[.c] = Get root-mean-square: 0, 0
    .chunkSpec = To Spectrum: "yes"
    refChunkCentroid#[.c] = Get centre of gravity: 2
    refChunkSpread#[.c] = Get standard deviation: 2
    removeObject: .chunkSnd, .chunkSpec
endfor

removeObject: refMono

appendInfoLine: "Input reference features:"
appendInfoLine: "  Spectral centroid: ", fixed$(refCentroid, 1), " Hz"
appendInfoLine: "  Spectral spread: ", fixed$(refSpread, 1), " Hz"
appendInfoLine: "  Intensity: mean=", fixed$(refIntMean, 1),
    ... " min=", fixed$(refIntMin, 1), " max=", fixed$(refIntMax, 1), " dB"
appendInfoLine: ""

###############################################################################
# EFFECT STRENGTH SCALING
###############################################################################

strength_factor = effect_strength / 10.0

eff_min_seg_ms = min_seg_ms * (1 - strength_factor * 0.3)
eff_max_seg_ms = max_seg_ms * (1 + strength_factor * 0.3)
eff_max_crossfade_ms = max_crossfade_ms * (1 + strength_factor * 0.5)
eff_silence_prob = max_silence_prob * strength_factor

min_silence_ms = 5
max_silence_ms = 80

# v1.4: onset saturation used to be a flat 8 onsets/sec for every
# preset, so a preset that leans HEAVILY on onset density (Extreme
# Fragmentation, w_onset=0.80) had its whole population clip to 1.0
# and lose all discrimination among its own high-onset candidates.
# The saturation bar now rises with how much the preset actually
# weights onset density.
onsetSatRate = 8 + 32 * w_onset

# v1.5: min_seg_ms < max_seg_ms (checked earlier) is not sufficient --
# the GA requires a genome-level gap of at least 10ms between the
# segMin/segMax genes (see the repair steps in evolvePopulation), but
# effect_strength scales min_seg_ms DOWN and max_seg_ms UP by
# DIFFERENT factors, so a narrow Custom range that passed the earlier
# check (e.g. min=97, max=104 after scaling) can still be too narrow
# for that gap. Without this check, Initialize Population's
# randomUniform calls for segMaxMs could receive a lower bound
# greater than its upper bound.
if eff_max_seg_ms - eff_min_seg_ms < 10
    exitScript: "Min_seg_ms/Max_seg_ms are too close together for the current ",
        ... "Effect_strength: after scaling they become ",
        ... fixed$(eff_min_seg_ms, 1), " - ", fixed$(eff_max_seg_ms, 1),
        ... " ms, which leaves less than the required 10 ms gap between ",
        ... "them. Widen Min_seg_ms/Max_seg_ms or lower Effect_strength."
endif

appendInfoLine: "Effective parameters:"
appendInfoLine: "  Segment range: ", fixed$(eff_min_seg_ms, 1), " - ", fixed$(eff_max_seg_ms, 1), " ms"
appendInfoLine: "  Crossfade: 0 - ", fixed$(eff_max_crossfade_ms, 1), " ms"
appendInfoLine: "  Silence prob: 0 - ", fixed$(eff_silence_prob, 3)
appendInfoLine: ""

# v1.4: if the max crossfade can't fit inside even the shortest
# effective segment (crossfade needs roughly half the segment on
# each side), warn rather than let every candidate silently discard
# nearly its whole pool in synthesizeCandidate's minSegDur check.
if eff_max_crossfade_ms * 2 > eff_min_seg_ms
    appendInfoLine: "  NOTE: Max_crossfade_ms is large relative to the segment range;"
    appendInfoLine: "        synthesizeCandidate will shrink crossfade per-candidate as needed"
    appendInfoLine: "        (see v1.4 fix) rather than stall."
    appendInfoLine: ""
endif

###############################################################################
# INITIALIZE POPULATION
###############################################################################

appendInfoLine: "Initializing population (", pop_size, " individuals)..."

# v1.3: guard against a reversed randomUniform range when
# eff_min_seg_ms > 0.4 * eff_max_seg_ms (e.g. min 100, max 200).
initSegUpper = max(eff_min_seg_ms + 5, eff_max_seg_ms * 0.4)

for ind to pop_size
    segMinMs_'ind' = randomUniform(eff_min_seg_ms, initSegUpper)
    segMaxMs_'ind' = randomUniform(max(segMinMs_'ind' + 10, eff_max_seg_ms * 0.6), eff_max_seg_ms)
    segBias_'ind' = randomUniform(-0.8, 0.8)
    reorderProb_'ind' = randomUniform(0, 1)
    crossfadeMs_'ind' = randomUniform(0, eff_max_crossfade_ms)
    silenceProb_'ind' = randomUniform(0, eff_silence_prob)
    silenceMin_'ind' = randomUniform(min_silence_ms, max_silence_ms * 0.5)
    silenceMax_'ind' = randomUniform(max(silenceMin_'ind' + 5, max_silence_ms * 0.5), max_silence_ms)
endfor

###############################################################################
# EVOLUTION
###############################################################################

appendInfoLine: "Evolving over ", generations, " generations..."
appendInfoLine: ""

fitnessHistMax# = zero#(generations)
fitnessHistMean# = zero#(generations)
fitnessHistMin# = zero#(generations)
bestFitness = -100000

# v1.4: seeded synthesis for true reproducibility, as in v1.3, but
# now one seed is shared by every individual IN A GENERATION rather
# than a fresh seed per synthesis call. v1.3 gave every candidate a
# unique seed, so fitness measured "genome + a fresh lucky random
# realization" rather than the genome alone -- two genomes were never
# actually compared under the same random draw, and even the elite
# genome got re-synthesized with a NEW seed every generation (only
# the final render used its snapshotted winning seed). Sharing one
# seed per generation makes within-generation tournament comparisons
# apples-to-apples; seeds still change across generations so the
# search isn't stuck on one realization forever.
gaBaseSeed = randomInteger(1, 1000000000)
bestGenomeSeed = 0
bestEverSet = 0
# v1.5: counts how many candidates ever hit synthesizeCandidate's
# hard iteration cap and had to be padded with trailing silence.
# Reported once at the end of the run (see "Complete" section) rather
# than per-candidate, to avoid spamming the Info window.
iterCapHitCount = 0

# Snapshot of the best genome's parameter VALUES (not index), so the
# final render reproduces the true best-ever candidate. Previous
# versions stored only the index, which aliased to a different genome
# after evolution.
bestGenomeSegMin = 0
bestGenomeSegMax = 0
bestGenomeBias = 0
bestGenomeReorder = 0
bestGenomeXfade = 0
bestGenomeSilProb = 0
bestGenomeSilMin = 0
bestGenomeSilMax = 0

for gen to generations
    appendInfoLine: "Generation ", gen, "/", generations, "..."

    selectObject: inputSound

    # v1.4: cheap/full fitness split removed entirely -- every
    # generation now computes full fitness (see changelog). This is
    # the only way selection reliably optimizes what a preset's
    # weights actually declare, rather than defaulting to pure
    # spectral-similarity ranking whenever a "cheap" generation hit.
    genSeed = gaBaseSeed + gen

    for ind to pop_size
        candSeed_'ind' = genSeed
        random_initializeWithSeedUnsafelyButPredictably: candSeed_'ind'

        @synthesizeCandidate: ind
        candidateSound = synthesizeCandidate.result

        typicalSegDurS = (segMinMs_'ind' + segMaxMs_'ind') / 2 / 1000
        @calculateFitnessFAST: candidateSound, 1, typicalSegDurS
        fitness_'ind' = calculateFitnessFAST.score

        selectObject: candidateSound
        nocheck Remove
    endfor

    # Per-generation min/mean/max + update best-ever with genome snapshot.
    genBestFitness = -100000
    genMinFitness = 100000
    genSumFitness = 0
    for ind to pop_size
        .f = fitness_'ind'
        genSumFitness = genSumFitness + .f
        if .f > genBestFitness
            genBestFitness = .f
        endif
        if .f < genMinFitness
            genMinFitness = .f
        endif
        if .f > bestFitness
            bestFitness = .f
            # Snapshot the winning genome's 8 parameter values. This
            # is the key fix over v1.1: subsequent evolution cannot
            # overwrite these.
            bestGenomeSegMin   = segMinMs_'ind'
            bestGenomeSegMax   = segMaxMs_'ind'
            bestGenomeBias     = segBias_'ind'
            bestGenomeReorder  = reorderProb_'ind'
            bestGenomeXfade    = crossfadeMs_'ind'
            bestGenomeSilProb  = silenceProb_'ind'
            bestGenomeSilMin   = silenceMin_'ind'
            bestGenomeSilMax   = silenceMax_'ind'
            # genome + seed together determine the phenotype exactly.
            bestGenomeSeed     = candSeed_'ind'
            bestEverSet = 1
        endif
    endfor

    fitnessHistMax#[gen]  = genBestFitness
    fitnessHistMean#[gen] = genSumFitness / pop_size
    fitnessHistMin#[gen]  = genMinFitness

    appendInfoLine: "  Max: ", fixed$(genBestFitness, 3),
        ... "  Mean: ", fixed$(genSumFitness / pop_size, 3),
        ... "  Min: ", fixed$(genMinFitness, 3)

    if gen < generations
        @evolvePopulation
        # Elitism: force the best-ever genome into slot 1 of the new
        # population. This prevents the best genome from being lost
        # through tournament selection + mutation.
        # v1.3: guarded -- before generation 1 finishes there is no
        # best-ever snapshot yet (the fields would be 0, and
        # segMin = segMax = 0 hangs Phase 1 forever).
        if bestEverSet = 1
            segMinMs_1   = bestGenomeSegMin
            segMaxMs_1   = bestGenomeSegMax
            segBias_1    = bestGenomeBias
            reorderProb_1 = bestGenomeReorder
            crossfadeMs_1 = bestGenomeXfade
            silenceProb_1 = bestGenomeSilProb
            silenceMin_1 = bestGenomeSilMin
            silenceMax_1 = bestGenomeSilMax
        endif
    endif
endfor

###############################################################################
# FINAL OUTPUT
#
# v1.2 FIX: synthesise using the snapshotted best-ever genome, not
# whatever currently sits at index `bestInd` (which may have been
# overwritten by later evolution). We force the best values into
# slot 1 and synthesise from there.
# v1.3: re-seed the RNG with the winning candidate's seed first.
# Genome + seed determine the phenotype exactly, so the rendered
# output is sample-identical to the candidate that actually won --
# not just a fresh random draw from the same genome.
###############################################################################

appendInfoLine: ""
appendInfoLine: "Generating final output..."

segMinMs_1   = bestGenomeSegMin
segMaxMs_1   = bestGenomeSegMax
segBias_1    = bestGenomeBias
reorderProb_1 = bestGenomeReorder
crossfadeMs_1 = bestGenomeXfade
silenceProb_1 = bestGenomeSilProb
silenceMin_1 = bestGenomeSilMin
silenceMax_1 = bestGenomeSilMax

random_initializeWithSeedUnsafelyButPredictably: bestGenomeSeed
@synthesizeCandidate: 1
random_initializeSafelyAndUnpredictably()
finalSound = synthesizeCandidate.result
finalNumSegs = synthesizeCandidate.numSegs
finalOutputParts = synthesizeCandidate.outputParts
selectObject: finalSound
Rename: "GA_Recombine_" + presetName$

bestSegMin  = bestGenomeSegMin
bestSegMax  = bestGenomeSegMax
bestBias    = bestGenomeBias
bestReorder = bestGenomeReorder
bestXfade   = bestGenomeXfade
bestSilProb = bestGenomeSilProb
bestSilMin  = bestGenomeSilMin
bestSilMax  = bestGenomeSilMax

selectObject: finalSound
finalDuration = Get total duration
appendInfoLine: "Final duration: ", fixed$(finalDuration, 2), " s (target was ", target_duration_s, " s)"
# v1.4: previously only shown in the visualization summary strip, so
# it was lost entirely when Draw_visualization was off.
appendInfoLine: "Best fitness: ", fixed$(bestFitness, 3), "   Seed: ", bestGenomeSeed
appendInfoLine: "Best genome: Seg ", fixed$(bestGenomeSegMin, 1), "-", fixed$(bestGenomeSegMax, 1),
    ... " ms | Bias ", fixed$(bestGenomeBias, 2),
    ... " | Reorder ", fixed$(bestGenomeReorder * 100, 0), "%",
    ... " | Xfade ", fixed$(bestGenomeXfade, 1), " ms",
    ... " | Silence ", fixed$(bestGenomeSilProb * 100, 0), "%, ",
    ... fixed$(bestGenomeSilMin, 0), "-", fixed$(bestGenomeSilMax, 0), " ms"

if iterCapHitCount > 0
    appendInfoLine: ""
    appendInfoLine: "WARNING: ", iterCapHitCount, " candidate(s) during the search hit the",
        ... " synthesis iteration cap and were padded with trailing silence."
    appendInfoLine: "         This means Min_seg_ms/Max_seg_ms/Max_crossfade_ms left too few",
        ... " usable segments to reach Target_duration_s naturally for those genomes;"
    appendInfoLine: "         consider a shorter crossfade or a wider segment range if this",
        ... " persists across runs."
endif

###############################################################################
# VISUALIZATION
###############################################################################

if draw_visualization
    appendInfoLine: "Creating visualization..."
    
    Erase all
    Select outer viewport: 0, 8, 0, 8.25

    # v1.6: Praat reads "_" in drawn text as a subscript marker, so a
    # Sound named "a_vox" printed as "a(sub v)ox". Escape for display
    # only; the object name itself is untouched.
    vizSoundName$ = replace$(soundName$, "_", "\_ ", 0)

    Select outer viewport: 0, 8, 0, 0.50
    Select inner viewport: 0.60, 7.70, 0.02, 0.48
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##GA Segment Recomposer v1.6##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half",
        ... vizSoundName$ + " | " + presetName$
        ... + " | Strength: " + string$(effect_strength)
    
    Select outer viewport: 0, 8, 0.60, 1.42
    Select inner viewport: 0.60, 7.70, 0.75, 1.37
    selectObject: inputSound
    Colour: "{0.60, 0.60, 0.60}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Text top: "no", fixed$(inputDuration, 2) + " s"
    
    Select outer viewport: 0, 8, 1.52, 2.52
    Select inner viewport: 0.60, 7.70, 1.67, 2.22
    selectObject: finalSound
    Colour: "{0.30, 0.60, 0.50}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "GA Result"
    Text bottom: "yes", "Time (s)"
    Text top: "no", fixed$(finalDuration, 2) + " s (target: " + fixed$(target_duration_s, 1) + "s)"
    
    Select outer viewport: 0, 4, 2.62, 4.02
    Select inner viewport: 0.60, 3.85, 2.77, 3.72

    # Find overall fitness extent across min and max histories.
    minFit = fitnessHistMin#[1]
    maxFit = fitnessHistMax#[1]
    for g from 2 to generations
        if fitnessHistMin#[g] < minFit
            minFit = fitnessHistMin#[g]
        endif
        if fitnessHistMax#[g] > maxFit
            maxFit = fitnessHistMax#[g]
        endif
    endfor

    fitRange = maxFit - minFit
    if fitRange < 0.1
        fitRange = 0.1
    endif
    minFit = minFit - fitRange * 0.08
    maxFit = maxFit + fitRange * 0.08

    Axes: 0, generations + 1, minFit, maxFit
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, generations + 1, minFit, maxFit

    # Shaded band between min and max (population spread).
    # Drawn as a series of thin vertical rectangles at each generation
    # tick since Praat has no native shaded-band primitive.
    for g from 1 to generations
        Paint rectangle: "{0.85, 0.92, 0.85}",
            ... g - 0.4, g + 0.4,
            ... fitnessHistMin#[g], fitnessHistMax#[g]
    endfor

    # Min line
    Colour: "{0.60, 0.50, 0.40}"
    Line width: 1
    for g from 2 to generations
        Draw line: g - 1, fitnessHistMin#[g - 1], g, fitnessHistMin#[g]
    endfor

    # Mean line
    Colour: "{0.40, 0.55, 0.40}"
    Line width: 1.5
    for g from 2 to generations
        Draw line: g - 1, fitnessHistMean#[g - 1], g, fitnessHistMean#[g]
    endfor

    # Max line (best per generation) — drawn last so it sits on top
    Colour: "{0.20, 0.60, 0.25}"
    Line width: 2
    for g from 2 to generations
        Draw line: g - 1, fitnessHistMax#[g - 1], g, fitnessHistMax#[g]
    endfor
    for g from 1 to generations
        Paint circle: "{0.20, 0.60, 0.25}", g, fitnessHistMax#[g], 0.12
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Fitness"
    Text bottom: "yes", "Generation"
    Text top: "no", "Evolution: green=max, olive=mean, brown=min, shaded=spread"
    
    Select outer viewport: 4, 8, 2.62, 4.02
    Select inner viewport: 4.45, 7.70, 2.77, 3.72
    
    Axes: 0, 8, 0, 1.1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 8, 0, 1.1
    
    param1 = (bestSegMin - eff_min_seg_ms) / (eff_max_seg_ms - eff_min_seg_ms + 0.001)
    param2 = (bestSegMax - eff_min_seg_ms) / (eff_max_seg_ms - eff_min_seg_ms + 0.001)
    param3 = (bestBias + 1) / 2
    param4 = bestReorder
    param5 = bestXfade / (eff_max_crossfade_ms + 0.001)
    param6 = bestSilProb / (eff_silence_prob + 0.001)
    param7 = (bestSilMin - min_silence_ms) / (max_silence_ms - min_silence_ms + 0.001)
    param8 = (bestSilMax - min_silence_ms) / (max_silence_ms - min_silence_ms + 0.001)
    
    param1 = max(0, min(1, param1))
    param2 = max(0, min(1, param2))
    param3 = max(0, min(1, param3))
    param4 = max(0, min(1, param4))
    param5 = max(0, min(1, param5))
    param6 = max(0, min(1, param6))
    param7 = max(0, min(1, param7))
    param8 = max(0, min(1, param8))
    
    barW = 0.7
    
    Paint rectangle: "{0.50, 0.70, 0.50}", 0.5 - barW/2, 0.5 + barW/2, 0, param1
    Paint rectangle: "{0.50, 0.70, 0.50}", 1.5 - barW/2, 1.5 + barW/2, 0, param2
    Paint rectangle: "{0.60, 0.60, 0.70}", 2.5 - barW/2, 2.5 + barW/2, 0, param3
    Paint rectangle: "{0.70, 0.50, 0.50}", 3.5 - barW/2, 3.5 + barW/2, 0, param4
    Paint rectangle: "{0.60, 0.70, 0.60}", 4.5 - barW/2, 4.5 + barW/2, 0, param5
    Paint rectangle: "{0.70, 0.60, 0.50}", 5.5 - barW/2, 5.5 + barW/2, 0, param6
    Paint rectangle: "{0.50, 0.60, 0.70}", 6.5 - barW/2, 6.5 + barW/2, 0, param7
    Paint rectangle: "{0.50, 0.60, 0.70}", 7.5 - barW/2, 7.5 + barW/2, 0, param8
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.5, "centre", -0.08, "half", "SegMin"
    Text: 1.5, "centre", -0.08, "half", "SegMax"
    Text: 2.5, "centre", -0.08, "half", "Bias"
    Text: 3.5, "centre", -0.08, "half", "Reorder"
    Text: 4.5, "centre", -0.08, "half", "Xfade"
    Text: 5.5, "centre", -0.08, "half", "SilProb"
    Text: 6.5, "centre", -0.08, "half", "SilMin"
    Text: 7.5, "centre", -0.08, "half", "SilMax"
    
    Font size: 7
    Text left: "yes", "Normalized"
    Text top: "no", "Best Genome Parameters"
    
    # ========================================================
    # Segmentation panel: input waveform with segment boundaries
    # marked. Reused segments (those that appear in the output) are
    # highlighted in green; unused segments stay grey.
    # ========================================================
    Select outer viewport: 0, 8, 4.12, 5.10
    Select inner viewport: 0.60, 7.70, 4.27, 5.05

    selectObject: inputSound
    Colour: "{0.60, 0.60, 0.60}"
    Draw: 0, 0, 0, 0, "no", "Curve"

    # Determine which segment indices were used in the output.
    # Up to finalNumSegs distinct indices possible; we mark a
    # usage count per segment by scanning the outputPart kinds.
    # We scan segIdx from 1..finalNumSegs for cleanliness.
    segUsed# = zero#(finalNumSegs)
    for .p from 1 to finalOutputParts
        if partKind_'.p' = 1
            .si = partSegIdx_'.p'
            if .si >= 1 and .si <= finalNumSegs
                segUsed#[.si] = segUsed#[.si] + 1
            endif
        endif
    endfor

    Axes: 0, inputDuration, -1, 1

    # Shade each segment by its usage count. Grey for 0, green
    # (darker for higher count) for 1+.
    for .s from 1 to finalNumSegs
        .st = segStart_'.s'
        .en = segEnd_'.s'
        .count = segUsed#[.s]
        if .count = 0
            # Skip — waveform shows grey behind anyway.
        else
            # Green with intensity scaling on usage (cap at 4).
            .cap = .count
            if .cap > 4
                .cap = 4
            endif
            .alpha = 0.25 + 0.15 * .cap
            if .alpha > 0.85
                .alpha = 0.85
            endif
            .rC = 0.55 - 0.35 * (.alpha - 0.25) / 0.6
            .gC = 0.85 - 0.15 * (.alpha - 0.25) / 0.6
            .bC = 0.55 - 0.30 * (.alpha - 0.25) / 0.6
            Paint rectangle: "{" + fixed$(.rC, 2) + "," + fixed$(.gC, 2)
                ... + "," + fixed$(.bC, 2) + "}",
                ... .st, .en, -1.0, -0.85
            Paint rectangle: "{" + fixed$(.rC, 2) + "," + fixed$(.gC, 2)
                ... + "," + fixed$(.bC, 2) + "}",
                ... .st, .en, 0.85, 1.0
        endif
    endfor

    # Thin vertical ticks at each segment boundary
    Colour: "{0.45, 0.45, 0.50}"
    Line width: 0.6
    for .s from 1 to finalNumSegs
        .bT = segStart_'.s'
        Draw line: .bT, -0.95, .bT, 0.95
    endfor
    Line width: 1

    # Redraw waveform on top so it's visible against the shading
    selectObject: inputSound
    Colour: "{0.25, 0.35, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"
    Text top: "no", "Segment pool ("
        ... + string$(finalNumSegs) + " segments; green = reused in output)"

    # ========================================================
    # Playback-order strip: output time on x, input time on y.
    # Each segment in the output is drawn as a thick line from
    # (outputTime, sourceStart) to (outputTime + duration,
    # sourceStart + duration). Silences are flat lines at y = -1
    # for visibility.
    # ========================================================
    Select outer viewport: 0, 8, 5.20, 6.30
    Select inner viewport: 0.60, 7.70, 5.35, 6.00

    Axes: 0, target_duration_s, -0.1, inputDuration
    Paint rectangle: "{0.97, 0.97, 0.97}",
        ... 0, target_duration_s, -0.1, inputDuration

    # Diagonal reference line (what a pure copy would look like)
    Colour: "{0.80, 0.80, 0.80}"
    Dotted line
    Draw line: 0, 0, target_duration_s,
        ... min(target_duration_s, inputDuration)
    Solid line

    for .p from 1 to finalOutputParts
        .ot = partOutputStart_'.p'
        .od = partDuration_'.p'
        if partKind_'.p' = 1
            .ss = partSourceStart_'.p'
            Colour: "{0.20, 0.55, 0.30}"
            Line width: 1.8
            Draw line: .ot, .ss, .ot + .od, .ss + .od
        else
            # Silence marker
            Colour: "{0.80, 0.55, 0.25}"
            Line width: 1.0
            Draw line: .ot, -0.05, .ot + .od, -0.05
        endif
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Source time"
    Text bottom: "yes", "Output time (s)"
    Text top: "no", "Playback map: green = where each output chunk came from; orange = silence"

    # ========================================================
    # Output spectrogram (kept; useful reference)
    # ========================================================
    Select outer viewport: 0, 8, 6.40, 7.55
    Select inner viewport: 0.60, 7.70, 6.55, 7.25

    selectObject: finalSound
    if inputChannels > 1
        Extract one channel: 1
        tmpFinal = selected("Sound")
    else
        Copy: "tmpFinal"
        tmpFinal = selected("Sound")
    endif

    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    finalSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Result spectrogram"

    removeObject: finalSpec, tmpFinal
    
    Select outer viewport: 0, 8, 7.65, 8.25
    Select inner viewport: 0.60, 7.70, 7.70, 8.20

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.02, "left", 0.75, "half",
        ... "##Best genome##   Seg: " + fixed$(bestSegMin, 1)
        ... + "-" + fixed$(bestSegMax, 1) + " ms"
        ... + "   |   Bias: " + fixed$(bestBias, 2)
        ... + "   |   Reorder: " + fixed$(bestReorder * 100, 0) + "\%  "
        ... + "   |   Xfade: " + fixed$(bestXfade, 1) + " ms"
        ... + "   |   Silence: " + fixed$(bestSilProb * 100, 0)
        ... + "\% , " + fixed$(bestSilMin, 0) + "-" + fixed$(bestSilMax, 0) + " ms"
    Text: 0.02, "left", 0.30, "half",
        ... "##Evolution##   Pop: " + string$(pop_size)
        ... + "   Gens: " + string$(generations)
        ... + "   Best fitness: " + fixed$(bestFitness, 3)
        ... + "   Seed: " + string$(bestGenomeSeed)
        ... + "   Weights: onset=" + fixed$(w_onset, 2)
        ... + " spec=" + fixed$(w_spectral, 2)
        ... + " reg=" + fixed$(w_regular, 2)
        ... + "   Target/Actual: " + fixed$(target_duration_s, 1)
        ... + "/" + fixed$(finalDuration, 2) + " s"

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # Restore the full page as the last drawing action, so Save as PNG /
    # Copy to clipboard capture the whole figure rather than cropping to
    # the summary strip.
    Select outer viewport: 0, 8, 0, 8.25
    Font size: 10
    Colour: "Black"
    Line width: 1
endif

appendInfoLine: ""
appendInfoLine: "=== Complete ==="

selectObject: finalSound
if play_result
    appendInfoLine: "Playing..."
    Play
endif

###############################################################################
# PROCEDURES
###############################################################################

procedure synthesizeCandidate: .ind
    .segMin = segMinMs_'.ind' / 1000
    .segMax = segMaxMs_'.ind' / 1000
    .bias = segBias_'.ind'
    .reorder = reorderProb_'.ind'
    .xfade = crossfadeMs_'.ind' / 1000
    .silProb = silenceProb_'.ind'
    .silMin = silenceMin_'.ind' / 1000
    .silMax = silenceMax_'.ind' / 1000
    
    # === PHASE 1: Create segment pool from input ===
    .time = 0
    .numSegs = 0
    while .time < inputDuration
        .rand = randomUniform(0, 1)
        if .bias < 0
            .rand = .rand ^ (1 - .bias)
        elsif .bias > 0
            .rand = 1 - (1 - .rand) ^ (1 + .bias)
        endif
        .segDur = .segMin + .rand * (.segMax - .segMin)
        .numSegs += 1
        segStart_'.numSegs' = .time
        segEnd_'.numSegs' = min(.time + .segDur, inputDuration)
        .time = segEnd_'.numSegs'
    endwhile
    
    # === PHASE 2: Build output by drawing from segment pool ===
    .currentTime = 0
    .outputParts = 0
    # v1.3: every part must be able to carry the genome's crossfade
    # on both sides -- previously one tiny part capped safeXfade for
    # the WHOLE concatenation, silently disabling all crossfades.
    .minSegDur = max(0.005, 2 / inputSampleRate)
    if 2 * .xfade + 0.002 > .minSegDur
        .minSegDur = 2 * .xfade + 0.002
    endif

    # v1.4: if NO segment in the pool is long enough to carry this
    # candidate's crossfade, Phase 2 below could never advance
    # .currentTime and would loop forever (this genome's Min_seg_ms/
    # Max_seg_ms/crossfade combination is simply infeasible). Rather
    # than hang, shrink the crossfade actually used for THIS
    # candidate to fit the pool's longest segment -- the fitness
    # function will naturally select against genomes that need this.
    .maxPoolSegDur = 0
    for .s to .numSegs
        .d = segEnd_'.s' - segStart_'.s'
        if .d > .maxPoolSegDur
            .maxPoolSegDur = .d
        endif
    endfor
    if .maxPoolSegDur < .minSegDur
        .xfade = max(0, .maxPoolSegDur / 2 - 0.002)
        .minSegDur = max(0.005, 2 / inputSampleRate)
        if 2 * .xfade + 0.002 > .minSegDur
            .minSegDur = 2 * .xfade + 0.002
        endif
    endif

    .lastUsedIdx = randomInteger(1, .numSegs)

    # v1.4: hard iteration cap as a last-resort safety net -- no
    # legitimate parameter combination should need more advances than
    # this many times the theoretical minimum-segment count, but a
    # cap guarantees the loop always terminates even if some future
    # edit reintroduces a stuck case.
    .maxIter = 4 * ceiling(target_duration_s / .minSegDur) + 2000
    .iter = 0

    # Keep looping until we hit target duration
    while .currentTime < target_duration_s and .iter < .maxIter
        .iter += 1
        # Pick a segment from the pool
        if randomUniform(0, 1) < .reorder
            # Random selection
            .idx = randomInteger(1, .numSegs)
        else
            # v1.4: the local jump range now SCALES with .reorder
            # itself. reorderProb=0 used to still jump +/-30% of the
            # whole pool regardless -- not remotely "sequential". Now
            # reorderProb=0 advances to exactly the next segment
            # (with wraparound), and the jitter grows toward the old
            # wide walk as reorderProb approaches 1.
            .range = round(.reorder * .numSegs * 0.3)
            if .range < 1
                .offset = 0
            else
                .offset = randomInteger(-.range, .range)
            endif
            .idx = .lastUsedIdx + 1 + .offset
            # wrap around the pool instead of clamping, so running off
            # either end loops back rather than sticking to an edge
            .idx = ((.idx - 1 + .numSegs * 100) mod .numSegs) + 1
        endif
        
        .lastUsedIdx = .idx
        
        .segStart = segStart_'.idx'
        .segEnd = segEnd_'.idx'
        .segDur = .segEnd - .segStart
        
        if .segDur >= .minSegDur
            selectObject: inputSound
            Extract part: .segStart, .segEnd, "rectangular", 1, "no"
            .segment = selected("Sound")
            
            .dur = Get total duration
            # v1.4: this micro-fade and Concatenate with overlap's own
            # crossfade both taper the same edge when .xfade is
            # actually going to be used at the join, compounding into
            # a slightly deeper dip than either fade alone intends.
            # Only apply it when crossfade is effectively off, so a
            # true butt-join still doesn't click.
            # v1.5: was "< 0.0005" here vs "> 0.0005" at the overlap
            # threshold below -- at exactly .xfade = 0.0005 s, NEITHER
            # branch engaged. Using "<=" here closes that gap: at the
            # boundary, the micro-fade now applies (and overlap
            # concatenation still doesn't, since that side is
            # unchanged), so every crossfade value is covered by
            # exactly one of the two protections.
            if .dur > 0.005 and .xfade <= 0.0005
                Formula: "if x < 0.002 then self * x / 0.002 else if x > xmax - 0.002 then self * (xmax - x) / 0.002 else self fi fi"
            endif
            
            .outputParts += 1
            outputPart_'.outputParts' = .segment
            partDuration_'.outputParts' = .dur
            # v1.2: record the SOURCE time and the OUTPUT time of this
            # part. Used by the visualization to draw the playback-
            # order strip and highlight which input segments were
            # reused. partKind: 1 = segment, 0 = silence.
            partSourceStart_'.outputParts' = .segStart
            partOutputStart_'.outputParts' = .currentTime
            partKind_'.outputParts' = 1
            partSegIdx_'.outputParts' = .idx
            # v1.3: overlap-aware advance. Concatenate-with-overlap
            # shortens the result by xfade per JOIN, which the old
            # accounting ignored -- outputs came out (nParts-1)*xfade
            # short of target (seconds, for glitch presets). Using
            # the genome xfade (>= the safeXfade actually applied)
            # under-counts, so the build can only OVERSHOOT, and the
            # trim step brings it back to the exact target.
            if .outputParts = 1
                .advance = .dur
            else
                .advance = .dur - .xfade
                if .advance < .dur * 0.5
                    .advance = .dur * 0.5
                endif
            endif
            .currentTime += .advance
        endif
        
        # Add silence with probability
        if .currentTime < target_duration_s and randomUniform(0, 1) < .silProb
            .silDur = randomUniform(.silMin, .silMax)
            
            # Don't overshoot target
            if .currentTime + .silDur > target_duration_s
                .silDur = target_duration_s - .currentTime
            endif
            
            # v1.3: silences must also carry the crossfade
            if .silDur > .minSegDur
                Create Sound from formula: "silence", inputChannels, 0, .silDur, inputSampleRate, "0"
                .silence = selected("Sound")
                
                .outputParts += 1
                outputPart_'.outputParts' = .silence
                partDuration_'.outputParts' = .silDur
                partSourceStart_'.outputParts' = -1
                partOutputStart_'.outputParts' = .currentTime
                partKind_'.outputParts' = 0
                partSegIdx_'.outputParts' = 0
                # v1.3: overlap-aware advance (see segment branch)
                if .outputParts = 1
                    .advance = .silDur
                else
                    .advance = .silDur - .xfade
                    if .advance < .silDur * 0.5
                        .advance = .silDur * 0.5
                    endif
                endif
                .currentTime += .advance
            endif
        endif
    endwhile

    # v1.5: if the hard iteration cap above was actually hit before
    # reaching target_duration_s, this candidate would otherwise come
    # out short -- pad with trailing silence so downstream trimming/
    # fitness code still sees the expected length, and flag it so the
    # run can report it once at the end instead of staying silent.
    if .currentTime < target_duration_s
        iterCapHitCount += 1
        .padDur = target_duration_s - .currentTime
        Create Sound from formula: "capPad", inputChannels, 0, .padDur, inputSampleRate, "0"
        .padSilence = selected("Sound")
        .outputParts += 1
        outputPart_'.outputParts' = .padSilence
        partDuration_'.outputParts' = .padDur
        partSourceStart_'.outputParts' = -1
        partOutputStart_'.outputParts' = .currentTime
        partKind_'.outputParts' = 0
        partSegIdx_'.outputParts' = 0
        .currentTime += .padDur
    endif

    # === PHASE 3: Concatenate all parts ===
    if .outputParts > 0
        if .outputParts = 1
            .result = outputPart_1
        else
            .minPartDur = partDuration_1
            for .p from 2 to .outputParts
                if partDuration_'.p' < .minPartDur
                    .minPartDur = partDuration_'.p'
                endif
            endfor
            
            .safeXfade = .xfade
            if .safeXfade > (.minPartDur / 2 - 0.0005)
                .safeXfade = .minPartDur / 2 - 0.0005
            endif
            if .safeXfade < 0
                .safeXfade = 0
            endif
            
            selectObject: outputPart_1
            for .p from 2 to .outputParts
                plusObject: outputPart_'.p'
            endfor
            
            # v1.5: this threshold now matches the micro-fade skip
            # threshold above (.xfade < 0.0005) exactly. They used to
            # differ (0.001 here vs 0.0005 there), so a crossfade of
            # roughly 0.5-1 ms fell into neither protection: too small
            # to trigger Concatenate with overlap, but also too large
            # to still get the per-segment micro-fade.
            if .safeXfade > 0.0005
                Concatenate with overlap: .safeXfade
            else
                Concatenate
            endif
            .result = selected("Sound")
            
            for .p to .outputParts
                nocheck removeObject: outputPart_'.p'
            endfor
        endif
        
        # Trim to exact target duration if exceeded
        selectObject: .result
        .actualDur = Get total duration
        if .actualDur > target_duration_s
            Extract part: 0, target_duration_s, "rectangular", 1, "no"
            .trimmed = selected("Sound")
            removeObject: .result
            .result = .trimmed
        elsif .actualDur < target_duration_s
            # v1.5: this is a rare-path top-up, not the normal case.
            # It only fires when the iteration cap above was hit AND
            # Concatenate with overlap then shortened the result by
            # safeXfade at the final join, landing .actualDur just
            # under target even though the padding loop aimed exactly
            # at target_duration_s. Top up with a plain, non-
            # overlapping silence tail (not run through Concatenate
            # with overlap again, so it can't shave off yet more time)
            # so the result always reaches target_duration_s exactly.
            .shortfall = target_duration_s - .actualDur
            Create Sound from formula: "shortfallPad", inputChannels, 0, .shortfall, inputSampleRate, "0"
            .shortfallSnd = selected("Sound")
            selectObject: .result
            plusObject: .shortfallSnd
            Concatenate
            .padded = selected("Sound")
            removeObject: .result, .shortfallSnd
            .result = .padded
        endif

        # v1.4: the exact-duration trim above can land mid-segment or
        # mid-waveform-cycle, and the original 2ms edge fade (applied
        # before this cut, to a part that may no longer even be the
        # last one) doesn't help at the NEW end point. Apply a short
        # fade-out here, after the cut, so the actual final sample
        # always tapers to zero instead of jumping.
        #
        # v1.5: also apply a matching fade-IN. Concatenate with
        # overlap smooths INTERNAL joins between parts, but nothing
        # protects the very first sample of the very first part --
        # if it starts mid-waveform-cycle, the output could still
        # click at t=0 even with crossfade fully engaged elsewhere.
        selectObject: .result
        .finalDur = Get total duration
        .outFade = min(0.004, .finalDur * 0.2)
        if .outFade > 0.0002
            Formula: "if x < '.outFade' then self * x / '.outFade' else if x > xmax - '.outFade' then self * (xmax - x) / '.outFade' else self fi fi"
        endif

        selectObject: .result
        Scale peak: 0.95
    else
        Create Sound from formula: "empty", inputChannels, 0, target_duration_s, inputSampleRate, "0"
        .result = selected("Sound")
    endif
    
    synthesizeCandidate.result = .result
    # v1.2: publish pool size and output-part count to the caller so
    # the visualization can iterate over the segments and playback
    # order. The segStart_N / segEnd_N / partSourceStart_N / etc.
    # families are already global by construction.
    synthesizeCandidate.numSegs = .numSegs
    synthesizeCandidate.outputParts = .outputParts
endproc

procedure calculateFitnessFAST: .sound, .doExpensive, .typicalSegDur
    # Three measurable components:
    #   .onsetScore    — count of sharp intensity jumps per second,
    #                    normalised. High on glitchy/fragmented outputs.
    #   .spectralSim   — 1 - distance(candidate spectral (centroid,
    #                    spread) TRAJECTORY from input's own trajectory,
    #                    both measured in nSpecChunks short windows).
    #                    Higher = more input-like spectral shape over
    #                    time, not just on whole-file average.
    #   .regularScore  — intensity-envelope autocorrelation at lags
    #                    derived from THIS genome's typical segment
    #                    length. High = repeating rhythmic pattern.
    # The final score is the preset-specified weighted sum. All three
    # components are in [0, 1] (clipped), so the fitness is in [0, 1].
    #
    # v1.4: .doExpensive is kept as a parameter for call-site
    # compatibility but is always 1 now -- the cheap/neutral-0.5
    # fallback path was removed because it made selection track
    # spectralSim alone regardless of preset (see changelog).

    selectObject: .sound
    .dur = Get total duration
    .rms = Get root-mean-square: 0, 0

    .onsetScore = 0.5
    .spectralSim = 0.5
    .regularScore = 0.5
    .usable = 1

    # Degenerate outputs (silent / near-silent) fail all components.
    if .rms < 1e-6 or .dur < 0.1
        .usable = 0
        .onsetScore = 0
        .spectralSim = 0
        .regularScore = 0
    endif

    if .usable = 1
        # -- Component 1: spectral similarity to input ----------
        selectObject: .sound
        if inputChannels > 1
            .cMono = Convert to mono
        else
            .cMono = Copy: "cand_mono_tmp"
        endif

        # v1.4: whole-file centroid/spread barely moves when segments
        # of the SAME input are just reordered, so this used to
        # discriminate very little (esp. for Subtle Texture, where it
        # carries 70% of the weight). Compare short-window trajectories
        # against the input's own (computed once, in refChunkCentroid#/
        # refChunkSpread#) instead of one number for the whole file.
        .chunkDist = 0
        .cChunkDur = .dur / nSpecChunks
        for .c to nSpecChunks
            .t1 = (.c - 1) * .cChunkDur
            .t2 = .t1 + .cChunkDur
            selectObject: .cMono
            Extract part: .t1, .t2, "rectangular", 1, "no"
            .chunkSnd = selected("Sound")
            .cChunkRms = Get root-mean-square: 0, 0

            # v1.5: a chunk that's itself (near-)silent -- from the
            # input's own content, OR from a candidate's inserted
            # silence gene -- has an undefined/degenerate centroid
            # and spread. Gate on RMS before trusting those numbers:
            # both sides quiet is a genuine match (distance 0); only
            # one side quiet is a genuine mismatch (distance 1);
            # only when both are active do we measure centroid/spread.
            .refQuiet = refChunkRms#[.c] < chunkSilenceRms
            .candQuiet = .cChunkRms < chunkSilenceRms
            if .refQuiet and .candQuiet
                .d = 0
                removeObject: .chunkSnd
            elsif .refQuiet or .candQuiet
                .d = 1
                removeObject: .chunkSnd
            else
                .chunkSpec = To Spectrum: "yes"
                .cc = Get centre of gravity: 2
                .cs = Get standard deviation: 2
                removeObject: .chunkSnd, .chunkSpec

                .dCent = 0
                if refChunkCentroid#[.c] > 1
                    .dCent = abs(.cc - refChunkCentroid#[.c]) / refChunkCentroid#[.c]
                endif
                .dSpread = 0
                if refChunkSpread#[.c] > 1
                    .dSpread = abs(.cs - refChunkSpread#[.c]) / refChunkSpread#[.c]
                endif
                .d = (.dCent + .dSpread) / 2
                if .d > 1
                    .d = 1
                endif
            endif
            .chunkDist = .chunkDist + .d
        endfor
        .chunkDist = .chunkDist / nSpecChunks
        .spectralSim = 1 - .chunkDist

        # -- Components 2 and 3: onset density + regularity -----
        if .doExpensive = 1
            selectObject: .cMono
            .cInt = To Intensity: 100, 0, "yes"
            .nFr = Get number of frames
            .dt = Get time step

            if .nFr > 4
                # v1.5: the candidate's own intensity MINIMUM failed
                # as a floor reference whenever the candidate itself
                # contains inserted digital silence (one of the
                # genome's own genes) -- the minimum IS near-silence
                # in that case, so "min + 3" barely filters anything
                # and onset counting could reward silence-and-repeat
                # patterns instead of real fragmentation. Use the
                # candidate's own intensity MAXIMUM instead (computed
                # once, reused for the regularity floor below too):
                # gain-invariant regardless of the original
                # recording's level, and not confused by the
                # candidate's own silence gene.
                .candIntMax = Get maximum: 0, 0, "Parabolic"
                .noiseFloor = .candIntMax - 55
                .onsetThresh = 3.5
                .prevVal = Get value in frame: 1
                .onsetCount = 0
                for .f from 2 to .nFr
                    .v = Get value in frame: .f
                    if .v > .noiseFloor and (.v - .prevVal) >= .onsetThresh
                        .onsetCount = .onsetCount + 1
                    endif
                    .prevVal = .v
                endfor
                .onsetRate = .onsetCount / .dur

                # v1.4: saturation point now scales with the preset's
                # own onset weight (onsetSatRate, set once in EFFECT
                # STRENGTH SCALING) instead of a flat 8/sec that let
                # high-onset presets' whole populations clip to 1.0.
                .onsetScore = .onsetRate / onsetSatRate
                if .onsetScore > 1
                    .onsetScore = 1
                endif

                # Regularity: autocorrelation at lags derived from
                # THIS genome's own typical segment duration, kept the
                # best. Read values into a vector once.
                # v1.5: floor is now relative to the CANDIDATE's own
                # intensity maximum (reusing .candIntMax above), not
                # the input's -- the candidate is always peak-
                # normalized (Scale peak: 0.95) before fitness runs,
                # so flooring against the un-normalized input's range
                # was not actually gain-invariant: changing only the
                # input's recording level left every candidate at the
                # same normalized level, but shifted this floor.
                .envFloor = .candIntMax - 60
                envVals# = zero#(.nFr)
                for .f from 1 to .nFr
                    .ev = Get value in frame: .f
                    if .ev < .envFloor
                        .ev = .envFloor
                    endif
                    envVals#[.f] = .ev
                endfor
                .envMean = 0
                for .f from 1 to .nFr
                    .envMean = .envMean + envVals#[.f]
                endfor
                .envMean = .envMean / .nFr

                .bestACF = 0
                # v1.4: lags are now multiples of this genome's own
                # typical segment duration (documented behavior that
                # the fixed {0.15, 0.25, 0.4, 0.6, 0.9, 1.3} list
                # never actually implemented), clipped to a sane
                # audible-rhythm range.
                .lagsToTry# = zero#(4)
                for .l to 4
                    .lagCand = .l * .typicalSegDur
                    if .lagCand < 0.08
                        .lagCand = 0.08
                    elsif .lagCand > 2.0
                        .lagCand = 2.0
                    endif
                    .lagsToTry#[.l] = .lagCand
                endfor
                for .l from 1 to size(.lagsToTry#)
                    .lagS = .lagsToTry#[.l]
                    .lagF = round(.lagS / .dt)
                    if .lagF >= 2 and .lagF < .nFr - 2
                        .num = 0
                        .denA = 0
                        .denB = 0
                        for .f from 1 to .nFr - .lagF
                            .a = envVals#[.f] - .envMean
                            .b = envVals#[.f + .lagF] - .envMean
                            .num = .num + .a * .b
                            .denA = .denA + .a * .a
                            .denB = .denB + .b * .b
                        endfor
                        # v1.4: proper Pearson-style normalization
                        # (sqrt of the product of BOTH sides' energy).
                        # The old num/den (energy of the LAG-0 side
                        # only) could exceed 1 and got silently
                        # clipped, letting unrelated envelopes tie at
                        # the ceiling.
                        if .denA > 1e-9 and .denB > 1e-9
                            .acf = .num / sqrt(.denA * .denB)
                            if .acf > .bestACF
                                .bestACF = .acf
                            endif
                        endif
                    endif
                endfor
                .regularScore = .bestACF
                if .regularScore < 0
                    .regularScore = 0
                endif
                if .regularScore > 1
                    .regularScore = 1
                endif
            endif

            removeObject: .cInt
        endif

        removeObject: .cMono
    endif

    .score = w_onset * .onsetScore
        ... + w_spectral * .spectralSim
        ... + w_regular * .regularScore

    calculateFitnessFAST.score = .score
    calculateFitnessFAST.onsetScore = .onsetScore
    calculateFitnessFAST.spectralSim = .spectralSim
    calculateFitnessFAST.regularScore = .regularScore
endproc

procedure evolvePopulation
    # v1.4: uniform crossover. v1.3 ran one tournament and cloned the
    # WHOLE winning genome (mutation-only search, no recombination of
    # two parents' genes). Two tournaments now pick parentA/parentB,
    # and each of the 8 genes is drawn independently from one of them
    # before mutation is applied -- a proper Genetic Algorithm
    # crossover step, not just tournament + mutation.
    for .i to pop_size
        parent1 = randomInteger(1, pop_size)
        parent2 = randomInteger(1, pop_size)
        if fitness_'parent1' > fitness_'parent2'
            .parentA = parent1
        else
            .parentA = parent2
        endif

        parent3 = randomInteger(1, pop_size)
        parent4 = randomInteger(1, pop_size)
        if fitness_'parent3' > fitness_'parent4'
            .parentB = parent3
        else
            .parentB = parent4
        endif

        if randomUniform(0, 1) < 0.5
            newSegMinMs_'.i' = segMinMs_'.parentA'
        else
            newSegMinMs_'.i' = segMinMs_'.parentB'
        endif
        if randomUniform(0, 1) < 0.5
            newSegMaxMs_'.i' = segMaxMs_'.parentA'
        else
            newSegMaxMs_'.i' = segMaxMs_'.parentB'
        endif
        if randomUniform(0, 1) < 0.5
            newSegBias_'.i' = segBias_'.parentA'
        else
            newSegBias_'.i' = segBias_'.parentB'
        endif
        if randomUniform(0, 1) < 0.5
            newReorderProb_'.i' = reorderProb_'.parentA'
        else
            newReorderProb_'.i' = reorderProb_'.parentB'
        endif
        if randomUniform(0, 1) < 0.5
            newCrossfadeMs_'.i' = crossfadeMs_'.parentA'
        else
            newCrossfadeMs_'.i' = crossfadeMs_'.parentB'
        endif
        if randomUniform(0, 1) < 0.5
            newSilenceProb_'.i' = silenceProb_'.parentA'
        else
            newSilenceProb_'.i' = silenceProb_'.parentB'
        endif
        if randomUniform(0, 1) < 0.5
            newSilenceMin_'.i' = silenceMin_'.parentA'
        else
            newSilenceMin_'.i' = silenceMin_'.parentB'
        endif
        if randomUniform(0, 1) < 0.5
            newSilenceMax_'.i' = silenceMax_'.parentA'
        else
            newSilenceMax_'.i' = silenceMax_'.parentB'
        endif

        # v1.4: segMin/segMax and silenceMin/silenceMax are an
        # ordered PAIR of genes -- independent crossover can pull
        # e.g. segMin from parentA and segMax from parentB and land
        # on an inconsistent pair (max < min). Repair unconditionally,
        # regardless of whether mutation touches them below.
        if newSegMaxMs_'.i' < newSegMinMs_'.i' + 10
            newSegMaxMs_'.i' = newSegMinMs_'.i' + 10
        endif
        if newSilenceMax_'.i' < newSilenceMin_'.i' + 5
            newSilenceMax_'.i' = newSilenceMin_'.i' + 5
        endif
    endfor
    
    .mutRate = 0.15
    
    for .i to pop_size
        if randomUniform(0, 1) < .mutRate
            newSegMinMs_'.i' = max(eff_min_seg_ms, min(initSegUpper, newSegMinMs_'.i' + randomGauss(0, 10)))
        endif
        if randomUniform(0, 1) < .mutRate
            newSegMaxMs_'.i' = max(newSegMinMs_'.i' + 10, min(eff_max_seg_ms, newSegMaxMs_'.i' + randomGauss(0, 15)))
        endif
        if randomUniform(0, 1) < .mutRate
            newSegBias_'.i' = max(-0.8, min(0.8, newSegBias_'.i' + randomGauss(0, 0.2)))
        endif
        if randomUniform(0, 1) < .mutRate
            newReorderProb_'.i' = max(0, min(1, newReorderProb_'.i' + randomGauss(0, 0.15)))
        endif
        if randomUniform(0, 1) < .mutRate
            newCrossfadeMs_'.i' = max(0, min(eff_max_crossfade_ms, newCrossfadeMs_'.i' + randomGauss(0, 2)))
        endif
        if randomUniform(0, 1) < .mutRate
            newSilenceProb_'.i' = max(0, min(eff_silence_prob, newSilenceProb_'.i' + randomGauss(0, 0.05)))
        endif
        if randomUniform(0, 1) < .mutRate
            newSilenceMin_'.i' = max(min_silence_ms, min(max_silence_ms * 0.5, newSilenceMin_'.i' + randomGauss(0, 8)))
        endif
        if randomUniform(0, 1) < .mutRate
            newSilenceMax_'.i' = max(newSilenceMin_'.i' + 5, min(max_silence_ms, newSilenceMax_'.i' + randomGauss(0, 10)))
        endif
    endfor

    # v1.5: mutation can re-break the min/max gene pairs even though
    # crossover's repair (above) already fixed them -- each gene
    # mutates independently, so e.g. silenceMin can mutate upward on
    # its own with silenceMax untouched, landing back on min > max.
    # Repair again here, right before the new generation replaces the
    # old one. Prefer giving ground on the max side (raise it to
    # min+gap) when that still fits under its own ceiling; only when
    # the min is already too close to the ceiling do we instead pull
    # the min down, so the repair itself can never be pushed out of
    # the genome's allowed range.
    for .i to pop_size
        if newSegMaxMs_'.i' < newSegMinMs_'.i' + 10
            if newSegMinMs_'.i' + 10 <= eff_max_seg_ms
                newSegMaxMs_'.i' = newSegMinMs_'.i' + 10
            else
                newSegMaxMs_'.i' = eff_max_seg_ms
                newSegMinMs_'.i' = max(eff_min_seg_ms, newSegMaxMs_'.i' - 10)
            endif
        endif
        if newSilenceMax_'.i' < newSilenceMin_'.i' + 5
            if newSilenceMin_'.i' + 5 <= max_silence_ms
                newSilenceMax_'.i' = newSilenceMin_'.i' + 5
            else
                newSilenceMax_'.i' = max_silence_ms
                newSilenceMin_'.i' = max(min_silence_ms, newSilenceMax_'.i' - 5)
            endif
        endif
    endfor
    
    for .i to pop_size
        segMinMs_'.i' = newSegMinMs_'.i'
        segMaxMs_'.i' = newSegMaxMs_'.i'
        segBias_'.i' = newSegBias_'.i'
        reorderProb_'.i' = newReorderProb_'.i'
        crossfadeMs_'.i' = newCrossfadeMs_'.i'
        silenceProb_'.i' = newSilenceProb_'.i'
        silenceMin_'.i' = newSilenceMin_'.i'
        silenceMax_'.i' = newSilenceMax_'.i'
    endfor
endproc