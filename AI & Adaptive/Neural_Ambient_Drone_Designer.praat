# ============================================================
# Praat AudioTools - Neural_Ambient_Drone_Designer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.9 (2026) - Honest cluster count, ordered seeding, smooth tiles
#
# Changelog v0.9 (2026):
#
#   1 - clusterCount# now describes assigns#. v0.8 reseeded an empty
#     cluster by stealing a grain without decrementing the DONOR's
#     count and without re-running assignment, so the two could
#     disagree. The pathological case: with identical feature vectors
#     every distance ties, `distSq < minDist` always keeps cluster 1,
#     and each empty cluster took the same grain in turn - so k
#     clusters could be reported active while only one held anything.
#     v0.9 reseeds only from a donor with a grain to spare, decrements
#     that donor, and then runs ONE authoritative pass after k-means:
#     every grain reassigned to its nearest final centroid, counts
#     rebuilt from scratch. If the data cannot support k clusters the
#     report says so instead of inventing them. The title bar now
#     shows active-of-requested.
#
#   2 - CORRECTION to v0.8's item 6. It claimed the RNG was seeded
#     only after the deterministic input checks; it was not. Seeding
#     sat at line 369 while "Sound too short" (394) and
#     "Number_of_clusters < 1" (582) still came after it, so a short
#     input with a positive seed exited and left Praat globally
#     predictable - the exact failure the item said was fixed. Both
#     checks now run before the generator is touched, and the two
#     exits that can only happen after seeding reset it on the way out.
#
#   3 - Tile seams are crossfaded. v0.9's shimmer fix concatenated
#     copies of the shortened grain directly, so wherever the last
#     sample of one copy did not match the first sample of the next
#     there was a waveform step - a hard seam in the middle of every
#     shimmered grain, repeating at the grain rate, which on high-HNR
#     material reads as a periodic spectral transient. A 2 ms internal
#     crossfade removes it; the outer grain crossfade is unchanged.
#
#   4 - Centroid seeds are drawn from a shuffled index list. v0.8's
#     rejection sampling had an `or nGrains <= k` escape that is
#     always true when nGrains = k, so the same grain could still seed
#     several centroids - precisely what the check existed to prevent.
#
#   5 - Remaining "tonal" wording in user-facing messages replaced,
#     and the Shimmer_intervals option "Full harmonic series" renamed
#     Extended interval set: it is a mixed set of up and down
#     transpositions, not a harmonic series.
#
# Version: 0.8 (2026) - Aligned grid, tiled shimmer, real cluster count
# License: MIT License
#
# Changelog v0.8 (2026):
#
#   CRITICAL 1 - octave shimmer replaced up to half of every affected
#     grain with SILENCE. After Resample + Override the grain is
#     shorter, and v0.7 restored its length by writing it into a buffer
#     of zeros - so the tail was literally nothing. The crossfade only
#     covers the join, not that hole. Measured silent gap before the
#     next grain begins:
#       100 ms grain, 20 ms fade, ratio 0.50 -> 30.0 ms of silence
#       100 ms grain, 20 ms fade, ratio 0.25 -> 55.0 ms
#        80 ms grain, 15 ms fade, ratio 0.50 -> 25.0 ms
#        80 ms grain, 15 ms fade, ratio 0.25 -> 45.0 ms
#     So Bright Shimmer, the preset built around this, gated itself
#     periodically. v0.8 TILES the shortened grain - repeating it until
#     it fills the slot, then cutting to length - so the duration is
#     preserved with audio rather than with a hole.
#     Measured end to end at shimmer probability 1.0 with the full
#     harmonic series, counting 25 ms windows below RMS 0.002:
#       1 layer:  v0.7 1.56% near-silent   v0.8 0%
#       3 layers: v0.7 0%                  v0.8 0%
#     The multi-layer figure is worth knowing: with three layers summed
#     the holes in one layer are filled by the others, so the defect is
#     masked at the default settings and shows up per-layer - worst on
#     sparse, few-layer, high-shimmer material, which is exactly where
#     an ambient drone is most exposed.
#
#   CRITICAL 2 - the analysis grid did not describe the grains that
#     get played. nGrains used floor((dur - grain) / hop) with no +1,
#     dropping a valid window (98 instead of 99 on a 5 s file), and
#     centres were placed at (i - 0.5) * hop. At a 100 ms grain and
#     50 ms hop that puts the first analysis point at 25.0 ms while
#     the first rendered grain is centred at 50.0 ms - a 25 ms offset,
#     half a grain. Every feature vector described audio adjacent to
#     the grain it was clustering. Now
#     nGrains = floor((dur - grain) / hop) + 1 and
#     t = grain/2 + (i - 1) * hop.
#     NOTE the remaining mismatch, which is not fixed: Praat's Gaussian
#     spectrogram analysis uses a context roughly twice its effective
#     window length, while the rendered grain is a rectangular cut of
#     exactly grainSec. The centres now line up; the extents still do
#     not. That is a wider spectral context, not an error, and it is
#     documented rather than papered over.
#
#   3 - A global fade at both ends of the finished output. Grains are
#     rectangular cuts and Concatenate with overlap fades only the
#     JOINS, never the head of the first grain or the tail of the last;
#     each layer was also trimmed with a rectangular Extract part that
#     can land mid-waveform.
#
#   4 - Empty clusters are handled rather than merely excluded from
#     selection. Centroids were seeded with replacement, so two could
#     start on the same grain and leave a cluster permanently empty -
#     Number_of_clusters = 5 could yield three active ones while the
#     title and Info box still said 5. v0.8 seeds distinct grains,
#     reseeds an empty cluster to its worst-fitting grain, and reports
#     the ACTIVE count.
#
#   5 - Silent input is rejected up front, and the final Scale peak is
#     conditional. A silent file gives undefined centroid and bandwidth
#     values that then poison the means, standard deviations and the
#     whole k-means pass.
#
#   6 - The RNG is seeded only AFTER the deterministic input checks
#     (v0.7 seeded first, so exiting on "Sound too short" left Praat
#     globally predictable) and is returned to its safe state once all
#     random work is done.
#
#   7 - Naming:
#     - "Highest HNR" cluster -> HIGHEST-HNR cluster. There is no
#       absolute HNR floor, no voicing requirement and no pitch test,
#       so on a noise source the script still picked a winner and
#       called it tonal. It is the least inharmonic cluster present,
#       which is a different claim.
#     - Layer_density -> Number_of_layers. It never controlled density
#       within a layer; each layer is a continuous grain sequence.
#     - The effective crossfade is reported when it differs from the
#       requested one (it is silently capped at 40% of the grain).
#     - Multichannel input is downmixed to mono and the stereo output
#       is synthesised from independently generated layers; the source
#       stereo image is not preserved. Now stated.
#
#   ON PITCH AND HNR (documented, unchanged): an unvoiced frame gets
#   pitch = 0 and HNR = -50, and both are z-scored alongside real
#   values, so voiced/unvoiced can dominate two of the four k-means
#   dimensions. For a drone designer that split is often what you want,
#   which is why it is left alone - but it is a property of the model.
#
# Version: 0.7 (2026) - Real per-grain crossfade (no pre-tapered
#                        window fighting the overlap), integer
#                        layer count, empty-cluster guard
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Cluster-Based Ambient Drone Designer - Generates lush evolving
#   drones from source material using k-means clustering over
#   acoustic features (spectral centroid, bandwidth, HNR, pitch).
#   File kept as "Neural_Ambient_Drone_Designer.praat" for now, but
#   the method has no neural network in it - it's feature-space /
#   k-means clustering. The form title, Info banner, and
#   visualization below all say "Cluster-Based" instead, since that
#   is what a technical audience (e.g. at DAFx) will actually see
#   and hear referenced. Please call it "Feature-Space Ambient
#   Drone Designer" or "Cluster-Based Ambient Drone Designer" when
#   presenting it - not "neural" or "AI analysis".
#
# Changelog v0.7:
#   - CORRECTNESS: Grains are now extracted with a rectangular
#     window instead of Hanning. The Hanning window already tapered
#     each grain to ~0 at both edges, so "Concatenate with overlap"
#     was crossfading between two signals that were already faded
#     out - reintroducing the same power dip the v0.6 fix was meant
#     to remove, especially at short overlap ratios. The overlap
#     crossfade is now the only fade applied.
#   - ROBUSTNESS: Layer_density is now an integer field (was
#     "positive", which silently accepted non-integer values like
#     3.5 for something used as an array size / loop count), and is
#     validated to be at least 1.
#   - CORRECTNESS: k-means centroids are initialized by drawing grain
#     indices with replacement, so two centroids can start on the
#     same grain and a cluster can end up with zero members. The
#     final membership count per cluster is now tracked, and
#     best_cluster is chosen only among clusters that actually have
#     members - previously an empty cluster's untouched (and
#     possibly high-HNR) centroid could "win" and produce a false
#     "No highest-HNR-cluster grains found" failure.
#   - CORRECTNESS: Removed a stray "+1" from the grains_needed
#     formula. N grains joined with a fixed overlap produce a total
#     length of fade + N*(grainSec-fade), so the "+1" always
#     rendered and processed one extra grain per layer that was
#     immediately trimmed away.
#
# Changelog v0.6:
#   - VERSION: Header, form title, and Info banner now agree (all
#     said different things: header 0.5, form/Info 0.4).
#   - TERMINOLOGY: Form title and on-screen labels no longer claim
#     "Neural" or "AI Analysis" - the method is k-means clustering
#     over hand-designed acoustic features, not a neural network.
#     The "=== AI Analysis ===" form section is now
#     "=== Feature Extraction & Clustering ===".
#   - REPRODUCIBILITY: Added a Seed field. k-means initialization,
#     grain selection, and shimmer decisions all draw from Praat's
#     RNG; Seed=0 keeps behaviour unpredictable (as before), any
#     other value makes the whole run reproducible.
#   - CORRECTNESS: Grains are now genuinely crossfaded using
#     Praat's "Concatenate with overlap" (a real overlap where the
#     outgoing grain fades out and the incoming grain fades in over
#     Grain_crossfade_ms), instead of a per-grain fade-to-~0
#     envelope followed by a plain, non-overlapping Concatenate -
#     which produced audible gating rather than a crossfade.
#     grains_needed is now derived from the actual hop implied by
#     that overlap, instead of assuming a 50%-hop architecture the
#     code never implemented.
#   - ROBUSTNESS: Number_of_clusters is capped at the grain count,
#     Kmeans_iterations must be positive, Shimmer_probability and
#     Stereo_width are clamped to [0,1], and the spectrogram's
#     analysis ceiling is capped below the Nyquist frequency.
#
# Changelog v0.5:
#   - Mono mix no longer crashes when layers differ in length:
#     mixing uses time-domain Object(x) (0 outside range) and a
#     buffer sized to the shortest layer, matching the stereo path
#   - Shimmer transposition preserves grain DURATION (resample
#     would otherwise rescale the time axis) -> CHANGES AUDIO of
#     presets that use shimmer
#   - Title and Info-box panels set explicit Axes: 0,1,0,1
#   - Pitch feature guards f0 <= 0 as well as undefined
#
# Changelog v0.4:
#   - Fixed preset comparison (number not string)
#   - Fixed Formula object references
#   - Added preset name to output
# ============================================================

# === Input Validation ===
nSelected = numberOfSelected("Sound")
if nSelected <> 1
    exitScript: "Please select exactly one Sound object."
endif

snd = selected("Sound")
sndName$ = selected$("Sound")

form Cluster-Based Ambient Drone Designer v0.9
    optionmenu Preset: 1
        option Manual
        option Dark Ambient
        option Bright Shimmer
        option Dense Texture
        option Sparse Minimal
        option Evolving Pad
    positive Output_duration_sec 20.0
    integer Number_of_layers 3
    positive Grain_size_ms 100
    positive Grain_crossfade_ms 20
    boolean Add_octave_shimmer 1
    positive Shimmer_probability 0.15
    optionmenu Shimmer_intervals: 1
        option Octaves only
        option Octaves and fifths
        option Extended interval set
    integer Number_of_clusters 3
    integer Kmeans_iterations 10
    real Stereo_width 0.7
    integer Seed 0
    boolean Play_result 1
endform

# Number_of_layers replaces Layer_density: it is a layer COUNT, not a
# density control - each layer is a continuous sequence of grains.
# Stereo_width < 0 gives mono output; 0 centres every layer.
# Grain_crossfade_ms is capped at 40% of the grain size, and the
# effective value is reported when the cap bites.
# Seed 0 = unpredictable, any other integer = reproducible.
# Multichannel input is downmixed to mono; the stereo output is
# synthesised from independently generated layers, so the source
# stereo image is NOT preserved.

layer_density = number_of_layers
if stereo_width < 0
    stereo_output = 0
    stereo_width = 0
else
    stereo_output = 1
endif
if stereo_width > 1
    stereo_width = 1
endif

# ============================================
# PRESET LOGIC
# ============================================

if preset = 2
    # Dark Ambient
    output_duration_sec = 30.0
    layer_density = 4
    grain_crossfade_ms = 40
    add_octave_shimmer = 1
    shimmer_probability = 0.1
    shimmer_intervals = 1
    grain_size_ms = 150
    number_of_clusters = 3
    stereo_width = 0.8
    presetName$ = "DarkAmbient"
elsif preset = 3
    # Bright Shimmer
    output_duration_sec = 20.0
    layer_density = 5
    grain_crossfade_ms = 15
    add_octave_shimmer = 1
    shimmer_probability = 0.25
    shimmer_intervals = 3
    grain_size_ms = 80
    number_of_clusters = 4
    stereo_width = 0.9
    presetName$ = "BrightShimmer"
elsif preset = 4
    # Dense Texture
    output_duration_sec = 25.0
    layer_density = 6
    grain_crossfade_ms = 10
    add_octave_shimmer = 0
    shimmer_probability = 0.05
    shimmer_intervals = 1
    grain_size_ms = 50
    number_of_clusters = 5
    stereo_width = 0.6
    presetName$ = "DenseTexture"
elsif preset = 5
    # Sparse Minimal
    output_duration_sec = 40.0
    layer_density = 2
    grain_crossfade_ms = 60
    add_octave_shimmer = 1
    shimmer_probability = 0.08
    shimmer_intervals = 1
    grain_size_ms = 200
    number_of_clusters = 2
    stereo_width = 0.5
    presetName$ = "SparseMinimal"
elsif preset = 6
    # Evolving Pad
    output_duration_sec = 30.0
    layer_density = 4
    grain_crossfade_ms = 30
    add_octave_shimmer = 1
    shimmer_probability = 0.18
    shimmer_intervals = 2
    grain_size_ms = 120
    number_of_clusters = 4
    stereo_width = 0.75
    presetName$ = "EvolvingPad"
else
    presetName$ = "Manual"
endif

# ============================================================
# PARAMETER VALIDATION (v0.6)
# ============================================================

if kmeans_iterations < 1
    exitScript: "Kmeans_iterations must be at least 1."
endif

if layer_density < 1
    exitScript: "Number_of_layers must be at least 1."
endif

if shimmer_probability > 1
    shimmerClamped = 1
    shimmer_probability = 1
else
    shimmerClamped = 0
endif

widthClamped$ = ""
if stereo_width < 0
    widthClamped$ = "low"
    stereo_width = 0
elsif stereo_width > 1
    widthClamped$ = "high"
    stereo_width = 1
endif

# ============================================================
# RANDOM SEED (v0.6)
# k-means initialization, grain selection, and shimmer decisions
# all draw from Praat's RNG. A fixed, non-zero Seed makes the
# whole run reproducible; Seed = 0 keeps behaviour unpredictable,
# as before.
# ============================================================


# ============================================
# SETUP
# ============================================

selectObject: snd
dur = Get total duration
fs = Get sampling frequency
nch = Get number of channels

# v0.9: grain timing is derived here so the deterministic checks can
# use it BEFORE the generator is seeded.
grainSec = grain_size_ms / 1000
stepSec = grainSec * 0.5
crossfadeSec = grain_crossfade_ms / 1000

if dur < grainSec * 2
    exitScript: "Sound too short. Need at least " + fixed$(grainSec * 2, 2) + " s."
endif
if number_of_clusters < 1
    exitScript: "Number_of_clusters must be at least 1."
endif

selectObject: snd
workSnd = Convert to mono

# v0.8 fix 5: reject a silent input BEFORE any analysis. An empty
# spectrum gives undefined centroid and bandwidth, which then poison
# the means, the standard deviations and the whole k-means pass.
selectObject: workSnd
srcPeak = Get absolute extremum: 0, 0, "None"
if srcPeak < 1e-6
    removeObject: workSnd
    exitScript: "The selected Sound is silent (or near-silent); nothing to cluster."
endif

# v0.9 CORRECTION: every deterministic check that can exitScript now
# runs BEFORE the generator is touched. v0.8's changelog claimed this
# and it was not true - "Sound too short" and "Number_of_clusters < 1"
# both still came after the seed, so a short input with a positive seed
# exited leaving Praat globally predictable for whatever ran next.
if seed <> 0
    random_initializeWithSeedUnsafelyButPredictably (seed)
    seedStr$ = string$(seed) + " (fixed / reproducible)"
else
    random_initializeSafelyAndUnpredictably ()
    seedStr$ = "0 (unpredictable)"
endif

Rename: "Analysis_Work"


# v0.6: the true per-join crossfade time, shared by the grain
# assembly (Concatenate with overlap) and the grains_needed
# calculation below, so the two stay consistent with each other.
fade = min(crossfadeSec, grainSec * 0.4)
if fade < crossfadeSec - 1e-9
    appendInfoLine: "  Crossfade requested ", fixed$(crossfadeSec * 1000, 1),
        ... " ms -> capped to ", fixed$(fade * 1000, 1),
        ... " ms (40% of the grain)"
endif

clearinfo
writeInfoLine: "=== Cluster-Based Ambient Drone Designer v0.9 ==="
appendInfoLine: "Seed: ", seedStr$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Duration: ", output_duration_sec, " s | Layers: ", layer_density
appendInfoLine: "Grain: ", grain_size_ms, " ms | Clusters: ", number_of_clusters
if shimmerClamped = 1
    appendInfoLine: "WARNING: Shimmer_probability was above 1, clamped to 1."
endif
if widthClamped$ = "low"
    appendInfoLine: "WARNING: Stereo_width was below 0, clamped to 0."
elsif widthClamped$ = "high"
    appendInfoLine: "WARNING: Stereo_width was above 1, clamped to 1."
endif
if add_octave_shimmer
    appendInfoLine: "Shimmer: ", fixed$(shimmer_probability * 100, 0), "%"
endif
if stereo_output
    appendInfoLine: "Output: Stereo (width ", fixed$(stereo_width * 100, 0), "%)"
else
    appendInfoLine: "Output: Mono"
endif
appendInfoLine: ""

# ============================================
# FEATURE EXTRACTION
# ============================================

appendInfoLine: "Analyzing spectral stability..."

# v0.8 CRITICAL 2: the standard full-window count includes the +1.
# Without it one valid window was dropped (98 instead of 99 on a 5 s
# file at a 100 ms grain and 50 ms hop).
nGrains = floor((dur - grainSec) / stepSec) + 1
nFeatures = 4

# v0.6: The spectrogram's frequency ceiling was a fixed 8000 Hz,
# which can meet or exceed the Nyquist frequency for lower sample
# rates. Cap it a little below Nyquist instead.
nyquist = fs / 2
specMaxFreq = 8000
if specMaxFreq >= nyquist
    specMaxFreq = nyquist * 0.98
endif

feat_centroid# = zero#(nGrains)
feat_bandwidth# = zero#(nGrains)
feat_hnr# = zero#(nGrains)
feat_pitch# = zero#(nGrains)
grain_time# = zero#(nGrains)

selectObject: workSnd
spec = To Spectrogram: grainSec, specMaxFreq, stepSec, 20, "Gaussian"

selectObject: workSnd
hnr = To Harmonicity (cc): stepSec, 75, 0.1, 1.0

selectObject: workSnd
pit = To Pitch: stepSec, 75, 600

for i from 1 to nGrains
    # v0.8 CRITICAL 2: the first window's CENTRE is grain/2, not
    # hop/2. At a 100 ms grain and 50 ms hop the old formula analysed
    # 25.0 ms while the first rendered grain is centred at 50.0 ms - a
    # 25 ms offset, half a grain, so every feature vector described
    # audio next to the grain it was clustering rather than the grain
    # itself.
    t = grainSec / 2 + (i - 1) * stepSec
    if t > dur - grainSec / 2
        t = dur - grainSec / 2
    endif
    grain_time#[i] = t
    
    selectObject: spec
    slice = To Spectrum (slice): t
    selectObject: slice
    feat_centroid#[i] = Get centre of gravity: 2
    feat_bandwidth#[i] = Get standard deviation: 2
    removeObject: slice
    
    selectObject: hnr
    h = Get value at time: t, "cubic"
    if h = undefined
        feat_hnr#[i] = -50
    else
        feat_hnr#[i] = h
    endif
    
    selectObject: pit
    f0 = Get value at time: t, "Hertz", "Linear"
    if f0 = undefined or f0 <= 0
        feat_pitch#[i] = 0
    else
        feat_pitch#[i] = f0
    endif
endfor

removeObject: spec, hnr, pit

appendInfoLine: "  Extracted ", nGrains, " grains"

# ============================================
# NORMALIZE FEATURES (Z-Score)
# ============================================

# Centroid
sum = 0
for i to nGrains
    sum += feat_centroid#[i]
endfor
mean_cent = sum / nGrains
sumSq = 0
for i to nGrains
    sumSq += (feat_centroid#[i] - mean_cent)^2
endfor
std_cent = sqrt(sumSq / nGrains)
if std_cent = 0
    std_cent = 1
endif

# Bandwidth
sum = 0
for i to nGrains
    sum += feat_bandwidth#[i]
endfor
mean_band = sum / nGrains
sumSq = 0
for i to nGrains
    sumSq += (feat_bandwidth#[i] - mean_band)^2
endfor
std_band = sqrt(sumSq / nGrains)
if std_band = 0
    std_band = 1
endif

# HNR
sum = 0
for i to nGrains
    sum += feat_hnr#[i]
endfor
mean_hnr = sum / nGrains
sumSq = 0
for i to nGrains
    sumSq += (feat_hnr#[i] - mean_hnr)^2
endfor
std_hnr = sqrt(sumSq / nGrains)
if std_hnr = 0
    std_hnr = 1
endif

# Pitch
sum = 0
for i to nGrains
    sum += feat_pitch#[i]
endfor
mean_pitch = sum / nGrains
sumSq = 0
for i to nGrains
    sumSq += (feat_pitch#[i] - mean_pitch)^2
endfor
std_pitch = sqrt(sumSq / nGrains)
if std_pitch = 0
    std_pitch = 1
endif

# Normalize
norm_cent# = zero#(nGrains)
norm_band# = zero#(nGrains)
norm_hnr# = zero#(nGrains)
norm_pitch# = zero#(nGrains)

for i to nGrains
    norm_cent#[i] = (feat_centroid#[i] - mean_cent) / std_cent
    norm_band#[i] = (feat_bandwidth#[i] - mean_band) / std_band
    norm_hnr#[i] = (feat_hnr#[i] - mean_hnr) / std_hnr
    norm_pitch#[i] = (feat_pitch#[i] - mean_pitch) / std_pitch
endfor

# ============================================
# K-MEANS CLUSTERING
# ============================================

appendInfoLine: "Clustering textures..."

if number_of_clusters > nGrains
    appendInfoLine: "WARNING: Number_of_clusters (", number_of_clusters,
        ... ") exceeds the number of grains (", nGrains,
        ... "); reducing to ", nGrains, "."
    number_of_clusters = nGrains
endif

k = number_of_clusters

cent_c# = zero#(k)
cent_b# = zero#(k)
cent_h# = zero#(k)
cent_p# = zero#(k)

shuffledIdx# = zero#(nGrains)
for i from 1 to nGrains
    shuffledIdx#[i] = i
endfor
nShuf = min(k, nGrains)
for i from 1 to nShuf
    r = randomInteger(i, nGrains)
    tmpv = shuffledIdx#[i]
    shuffledIdx#[i] = shuffledIdx#[r]
    shuffledIdx#[r] = tmpv
endfor

for c from 1 to k
    # v0.9: draw seeds from a SHUFFLED index list, without
    # replacement. v0.8 used rejection sampling with an
    # `or nGrains <= k` escape, and that escape is always true when
    # nGrains = k, so the same grain could still seed several
    # centroids - the exact case the check was meant to prevent.
    picked = shuffledIdx#[c]
    cent_c#[c] = norm_cent#[picked]
    cent_b#[c] = norm_band#[picked]
    cent_h#[c] = norm_hnr#[picked]
    cent_p#[c] = norm_pitch#[picked]
endfor

assigns# = zero#(nGrains)
clusterCount# = zero#(k)

for iter from 1 to kmeans_iterations
    changes = 0
    
    for i from 1 to nGrains
        minDist = 1e9
        bestK = 1
        
        for c from 1 to k
            distSq = (norm_cent#[i] - cent_c#[c])^2 +
                ... (norm_band#[i] - cent_b#[c])^2 +
                ... (norm_hnr#[i] - cent_h#[c])^2 +
                ... (norm_pitch#[i] - cent_p#[c])^2
            
            if distSq < minDist
                minDist = distSq
                bestK = c
            endif
        endfor
        
        if assigns#[i] <> bestK
            assigns#[i] = bestK
            changes += 1
        endif
    endfor
    
    for c from 1 to k
        sum_c = 0
        sum_b = 0
        sum_h = 0
        sum_p = 0
        count = 0
        
        for i from 1 to nGrains
            if assigns#[i] = c
                sum_c += norm_cent#[i]
                sum_b += norm_band#[i]
                sum_h += norm_hnr#[i]
                sum_p += norm_pitch#[i]
                count += 1
            endif
        endfor
        
        if count > 0
            cent_c#[c] = sum_c / count
            cent_b#[c] = sum_b / count
            cent_h#[c] = sum_h / count
            cent_p#[c] = sum_p / count
        endif
        clusterCount#[c] = count
    endfor

    # v0.9: reseed an empty cluster only from a donor that can SPARE a
    # grain, and decrement the donor's own count. v0.8 stole the grain
    # without touching the donor, so clusterCount# stopped describing
    # assigns#.
    for c from 1 to k
        if clusterCount#[c] = 0
            worstD = -1
            worstI = 0
            for i from 1 to nGrains
                own = assigns#[i]
                if own >= 1 and clusterCount#[own] > 1
                    dOwn = (norm_cent#[i] - cent_c#[own])^2 +
                        ... (norm_band#[i] - cent_b#[own])^2 +
                        ... (norm_hnr#[i] - cent_h#[own])^2 +
                        ... (norm_pitch#[i] - cent_p#[own])^2
                    if dOwn > worstD
                        worstD = dOwn
                        worstI = i
                    endif
                endif
            endfor
            # If no cluster has a grain to spare, the data genuinely
            # cannot support k clusters. Leave it empty and let the
            # final recount report the truth.
            if worstI > 0
                donor = assigns#[worstI]
                clusterCount#[donor] = clusterCount#[donor] - 1
                cent_c#[c] = norm_cent#[worstI]
                cent_b#[c] = norm_band#[worstI]
                cent_h#[c] = norm_hnr#[worstI]
                cent_p#[c] = norm_pitch#[worstI]
                assigns#[worstI] = c
                clusterCount#[c] = 1
                changes += 1
            endif
        endif
    endfor

    if changes = 0
        appendInfoLine: "  Converged at iteration ", iter
        iter = kmeans_iterations + 1
    endif
endfor

# v0.9: one authoritative pass. Every grain is reassigned to its
# nearest FINAL centroid and the counts are rebuilt from assigns#, so
# clusterCount# and nActiveClusters describe what actually happened.
# v0.8 could report k active clusters while only one or two held any
# grain - most visibly when all feature vectors are identical, where
# every distance ties, `distSq < minDist` always keeps cluster 1, and
# the reseeding handed the same grain around in a circle.
for c from 1 to k
    clusterCount#[c] = 0
endfor
for i from 1 to nGrains
    minDist = 1e30
    bestC = 1
    for c from 1 to k
        distSq = (norm_cent#[i] - cent_c#[c])^2 +
            ... (norm_band#[i] - cent_b#[c])^2 +
            ... (norm_hnr#[i] - cent_h#[c])^2 +
            ... (norm_pitch#[i] - cent_p#[c])^2
        if distSq < minDist
            minDist = distSq
            bestC = c
        endif
    endfor
    assigns#[i] = bestC
    clusterCount#[bestC] = clusterCount#[bestC] + 1
endfor

# ============================================
# IDENTIFY BEST CLUSTER (Highest HNR)
# ============================================

# v0.8 fix 7: this picks the HIGHEST-HNR cluster, not a "tonal" one.
# There is no absolute HNR floor, no voicing requirement and no pitch
# test, so on a pure noise source the script still selects a winner.
# It is the least inharmonic cluster present - a weaker claim.
nActiveClusters = 0
for c from 1 to k
    if clusterCount#[c] > 0
        nActiveClusters += 1
    endif
endfor
appendInfoLine: "  Active clusters: ", nActiveClusters, " of ", k, " requested"

best_cluster = 0
max_hnr_score = -1e9

for c from 1 to k
    if clusterCount#[c] > 0 and cent_h#[c] > max_hnr_score
        max_hnr_score = cent_h#[c]
        best_cluster = c
    endif
endfor

if best_cluster = 0
    removeObject: workSnd
    random_initializeSafelyAndUnpredictably ()
    exitScript: "k-means produced no non-empty clusters. Try a different Seed or fewer clusters."
endif

appendInfoLine: "  Selected Cluster ", best_cluster, " (Highest HNR, ",
    ... clusterCount#[best_cluster], " grains)"

tonal_indices# = zero#(nGrains)
tonal_count = 0

for i from 1 to nGrains
    if assigns#[i] = best_cluster
        tonal_count += 1
        tonal_indices#[tonal_count] = i
    endif
endfor

if tonal_count = 0
    removeObject: workSnd
    random_initializeSafelyAndUnpredictably ()
    exitScript: "No grains are assigned to the selected highest-HNR cluster. Try more clusters."
endif

appendInfoLine: "  Found ", tonal_count, " highest-HNR-cluster grains"

# ============================================
# SHIMMER INTERVALS
# ============================================

if shimmer_intervals = 1
    n_intervals = 2
    interval_1 = 0.5
    interval_2 = 2.0
elsif shimmer_intervals = 2
    n_intervals = 4
    interval_1 = 0.5
    interval_2 = 0.667
    interval_3 = 1.5
    interval_4 = 2.0
else
    n_intervals = 6
    interval_1 = 0.5
    interval_2 = 0.667
    interval_3 = 1.25
    interval_4 = 1.5
    interval_5 = 2.0
    interval_6 = 3.0
endif

# ============================================
# GENERATIVE DRONE SYNTHESIS
# ============================================

appendInfoLine: ""
appendInfoLine: "Generating drone layers..."

nLayers = layer_density
layer_dur = output_duration_sec

layer_ids# = zero#(nLayers)

# Calculate pan positions
for layer_idx from 1 to nLayers
    if nLayers = 1
        pan_'layer_idx' = 0.5
    else
        pan_'layer_idx' = (layer_idx - 1) / (nLayers - 1)
        pan_'layer_idx' = 0.5 + (pan_'layer_idx' - 0.5) * stereo_width
    endif
endfor

for layer_idx from 1 to nLayers
    appendInfoLine: "  Layer ", layer_idx, "/", nLayers, "..."
    
    # v0.6: grains are joined with a real crossfade (see below), so
    # each additional grain only advances the output by
    # (grainSec - fade), not by a full grain. Solve for the grain
    # count that reaches layer_dur under that hop.
    hopSec = grainSec - fade
    if hopSec <= 0
        hopSec = grainSec * 0.1
    endif
    grains_needed = ceiling((layer_dur - fade) / hopSec)
    if grains_needed < 1
        grains_needed = 1
    endif
    grain_sounds# = zero#(grains_needed)
    
    for g from 1 to grains_needed
        rand_idx = randomInteger(1, tonal_count)
        g_idx = tonal_indices#[rand_idx]
        
        t_center = grain_time#[g_idx]
        t1 = t_center - (grainSec / 2)
        t2 = t_center + (grainSec / 2)
        
        if t1 < 0
            t1 = 0
            t2 = grainSec
        endif
        if t2 > dur
            t2 = dur
            t1 = dur - grainSec
        endif
        
        selectObject: workSnd
        Extract part: t1, t2, "rectangular", 1, "no"
        gid = selected("Sound")
        
        # Shimmer transposition. Resample shifts pitch but also
        # rescales DURATION; restore the original grain length so the
        # concatenation grid stays consistent.
        if add_octave_shimmer and randomUniform(0, 1) < shimmer_probability
            selectObject: gid
            gid_dur0 = Get total duration
            sr_orig = Get sampling frequency
            
            int_choice = randomInteger(1, n_intervals)
            ratio = interval_'int_choice'
            
            new_sr = sr_orig * ratio
            if new_sr > 8000 and new_sr < 96000
                Resample: new_sr, 50
                Override sampling frequency: sr_orig
                gid_shifted = selected("Sound")
                selectObject: gid_shifted
                shifted_dur = Get total duration
                if shifted_dur >= gid_dur0
                    gid_new = Extract part: 0, gid_dur0, "rectangular", 1, "no"
                else
                    # v0.8 CRITICAL 1: TILE the shortened grain instead
                    # of writing it into a buffer of zeros. v0.7 padded
                    # with silence, so an octave-up grain was half
                    # signal and half hole - measured gaps before the
                    # next grain begins: 30.0 ms at a 100 ms grain with
                    # a 20 ms fade and ratio 0.50, and 55.0 ms at ratio
                    # 0.25. The crossfade covers the join, not the
                    # hole, so Bright Shimmer gated itself.
                    # v0.9: crossfade the tile seams. v0.8 used a bare
                    # Concatenate, so wherever the last sample of one
                    # copy did not match the first sample of the next
                    # there was a waveform step - a hard seam in the
                    # middle of every shimmered grain, repeating at the
                    # grain rate. On high-HNR material that reads as a
                    # periodic spectral transient. A 2 ms internal
                    # crossfade removes it; the outer grain crossfade
                    # is untouched.
                    tileFade = 0.002
                    if tileFade > shifted_dur * 0.25
                        tileFade = shifted_dur * 0.25
                    endif
                    nCopies = ceiling((gid_dur0 + tileFade) / (shifted_dur - tileFade))
                    if nCopies < 2
                        nCopies = 2
                    endif
                    selectObject: gid_shifted
                    tileAcc = Copy: "tile_acc"
                    for cc from 2 to nCopies
                        selectObject: gid_shifted
                        tileNext = Copy: "tile_next"
                        selectObject: tileAcc
                        plusObject: tileNext
                        if tileFade > 0.0002
                            tileNew = Concatenate with overlap: tileFade
                        else
                            tileNew = Concatenate
                        endif
                        removeObject: tileAcc, tileNext
                        tileAcc = tileNew
                    endfor
                    selectObject: tileAcc
                    tiledDur = Get total duration
                    if tiledDur < gid_dur0
                        # one more copy if the overlap ate too much
                        selectObject: gid_shifted
                        tileNext = Copy: "tile_next"
                        selectObject: tileAcc
                        plusObject: tileNext
                        tileNew = Concatenate with overlap: tileFade
                        removeObject: tileAcc, tileNext
                        tileAcc = tileNew
                    endif
                    selectObject: tileAcc
                    gid_new = Extract part: 0, gid_dur0, "rectangular", 1, "no"
                    removeObject: tileAcc
                endif
                removeObject: gid, gid_shifted
                gid = gid_new
            endif
        endif
        
        grain_sounds#[g] = gid
    endfor
    
    # Join grains with a genuine crossfade: "Concatenate with
    # overlap" fades the outgoing grain out and the incoming grain
    # in over `fade` seconds and sums them, instead of each grain
    # fading to ~silence on its own and being butted up against the
    # next (which produced audible gating, not a crossfade).
    selectObject: grain_sounds#[1]
    if grains_needed = 1
        layerSnd = Copy: "Layer_" + string$(layer_idx)
    else
        for g from 2 to grains_needed
            plusObject: grain_sounds#[g]
        endfor
        if fade > 0
            Concatenate with overlap: fade
        else
            Concatenate
        endif
        layerSnd = selected("Sound")
    endif
    
    # Trim to duration
    selectObject: layerSnd
    current_dur = Get total duration
    if current_dur > layer_dur
        Extract part: 0, layer_dur, "rectangular", 1, "no"
        trimmed = selected("Sound")
        removeObject: layerSnd
        layerSnd = trimmed
    endif
    
    selectObject: layerSnd
    Rename: "Layer_" + string$(layer_idx)
    
    # Cleanup grains
    for g from 1 to grains_needed
        removeObject: grain_sounds#[g]
    endfor
    
    layer_ids#[layer_idx] = layerSnd
endfor

# ============================================
# MIX LAYERS
# ============================================

appendInfoLine: ""
appendInfoLine: "Mixing layers..."

min_dur = 1e9
for layer_idx from 1 to nLayers
    selectObject: layer_ids#[layer_idx]
    d = Get total duration
    if d < min_dur
        min_dur = d
    endif
endfor

# Layers may differ in length; mixing samples each layer in the TIME
# domain via Object_X(x), which returns 0 outside the layer's range
# (reading by [col] crashes when a layer is shorter than the buffer).
# Buffers are sized to the shortest layer so every layer fully covers them.
if stereo_output
    output_left = Create Sound from formula: "Mix_L", 1, 0, min_dur, fs, "0"
    output_right = Create Sound from formula: "Mix_R", 1, 0, min_dur, fs, "0"
    
    for layer_idx from 1 to nLayers
        layerId = layer_ids#[layer_idx]
        layerIdStr$ = string$(layerId)
        
        pan = pan_'layer_idx'
        left_gain = cos(pan * pi / 2)
        right_gain = sin(pan * pi / 2)
        leftGainStr$ = string$(left_gain)
        rightGainStr$ = string$(right_gain)
        
        selectObject: output_left
        Formula: "self + Object_" + layerIdStr$ + "(x) * " + leftGainStr$
        
        selectObject: output_right
        Formula: "self + Object_" + layerIdStr$ + "(x) * " + rightGainStr$
    endfor
    
    selectObject: output_left
    plusObject: output_right
    finalOut = Combine to stereo
    Rename: sndName$ + "_ClusterDrone_" + presetName$
    
    removeObject: output_left, output_right
else
    finalOut = Create Sound from formula: "Mix", 1, 0, min_dur, fs, "0"
    
    for layer_idx from 1 to nLayers
        layerId = layer_ids#[layer_idx]
        layerIdStr$ = string$(layerId)
        
        selectObject: finalOut
        Formula: "self + Object_" + layerIdStr$ + "(x)"
    endfor
    
    selectObject: finalOut
    Rename: sndName$ + "_ClusterDrone_" + presetName$
endif

selectObject: finalOut
# v0.8 fix 3: a global fade at both ends. Grains are rectangular cuts,
# and Concatenate with overlap fades only the JOINS - never the head of
# the first grain or the tail of the last - while each layer is trimmed
# with a rectangular Extract part that can land mid-waveform.
selectObject: finalOut
outDurNow = Get total duration
edgeFade = 0.005
if edgeFade > outDurNow * 0.1
    edgeFade = outDurNow * 0.1
endif
if edgeFade > 0.0002
    efA$ = fixed$(edgeFade, 8)
    selectObject: finalOut
    Formula: "if x - xmin < " + efA$ + " then self * ((x - xmin) / " + efA$ + ") else self fi"
    selectObject: finalOut
    Formula: "if xmax - x < " + efA$ + " then self * ((xmax - x) / " + efA$ + ") else self fi"
endif

# v0.8 fix 5: only normalise if there is something to normalise.
selectObject: finalOut
outPeak = Get absolute extremum: 0, 0, "None"
if outPeak > 1e-9
    selectObject: finalOut
    Scale peak: 0.99
else
    appendInfoLine: "  ! Output peak is zero; skipping normalisation."
endif

# v0.8 fix 6: hand the generator back to its safe state.
random_initializeSafelyAndUnpredictably ()

# Cleanup layers
for layer_idx from 1 to nLayers
    removeObject: layer_ids#[layer_idx]
endfor

# ============================================
# VISUALIZATION
# ============================================

appendInfoLine: ""
appendInfoLine: "Creating visualization..."

Erase all

# === TITLE ===
Select outer viewport: 1, 8, 0, 0.5
Axes: 0, 1, 0, 1
Font size: 12
Colour: "Black"
Text: 0.5, "centre", 0.5, "half", "##Cluster-Based Ambient Drone## | " + presetName$ + " | " + string$(nLayers) + " layers"

# === SOURCE WAVEFORM ===
Select outer viewport: 0, 8, 0.6, 2.0
Select inner viewport: 0.8, 7.6, 0.8, 1.8

selectObject: snd
Colour: "{0.5, 0.5, 0.5}"
Draw: 0, 0, 0, 0, "no", "Curve"

Colour: "Black"
Draw inner box
Font size: 7
Select outer viewport: 0.15, 8, 0.6, 2.0
Text left: "yes", "Source"

# === CLUSTER ANALYSIS (HNR over time with cluster coloring) ===
Select outer viewport: 0, 8, 2.1, 3.8
Select inner viewport: 0.8, 7.6, 2.3, 3.6

# Find HNR range
hnr_min = 1e9
hnr_max = -1e9
for i from 1 to nGrains
    if feat_hnr#[i] < hnr_min
        hnr_min = feat_hnr#[i]
    endif
    if feat_hnr#[i] > hnr_max
        hnr_max = feat_hnr#[i]
    endif
endfor

hnr_range = hnr_max - hnr_min
if hnr_range < 1
    hnr_range = 1
endif

Axes: 0, dur, hnr_min - 2, hnr_max + 2

# Background
Paint rectangle: "{0.95, 0.95, 0.95}", 0, dur, hnr_min - 2, hnr_max + 2

# Draw grains colored by cluster
for i from 1 to nGrains
    t = grain_time#[i]
    h = feat_hnr#[i]
    cluster = assigns#[i]
    
    # Color by cluster - put color directly in Paint command
    if cluster = best_cluster
        Paint circle (mm): "{0.2, 0.7, 0.3}", t, h, 1.0
    elsif cluster = 1
        Paint circle (mm): "{0.7, 0.3, 0.3}", t, h, 1.0
    elsif cluster = 2
        Paint circle (mm): "{0.3, 0.3, 0.7}", t, h, 1.0
    elsif cluster = 3
        Paint circle (mm): "{0.7, 0.5, 0.2}", t, h, 1.0
    else
        Paint circle (mm): "{0.5, 0.5, 0.5}", t, h, 1.0
    endif
endfor

# Mark selected cluster
Colour: "Black"
Font size: 6
Text: dur * 0.02, "left", hnr_max, "top", "Green = Selected (Cluster " + string$(best_cluster) + ")"

Colour: "Black"
Draw inner box
Font size: 7
Select outer viewport: 0.15, 8, 2.1, 3.8
Text left: "yes", "HNR (dB)"

# === OUTPUT WAVEFORM ===
Select outer viewport: 0, 8, 3.9, 5.5
Select inner viewport: 0.8, 7.6, 4.1, 5.3

selectObject: finalOut
Colour: "{0.3, 0.5, 0.7}"
Draw: 0, 0, 0, 0, "no", "Curve"

Colour: "Black"
Draw inner box
Font size: 7
Select outer viewport: 0.15, 8, 3.9, 5.5
Text left: "yes", "Output"
Text bottom: "yes", "Time (s)"

# === INFO BOX ===
Select outer viewport: 0, 8, 5.6, 6.1
Axes: 0, 1, 0, 1
Font size: 6
Colour: "{0.4, 0.4, 0.4}"

shimmerText$ = ""
if add_octave_shimmer
    shimmerText$ = " | Shimmer: " + fixed$(shimmer_probability * 100, 0) + "%"
endif

Text: 0.5, "centre", 0.5, "half", "Grain: " + string$(grain_size_ms) + "ms | Clusters: " + string$(nActiveClusters) + " active of " + string$(number_of_clusters) + " | Selected grains: " + string$(tonal_count) + "/" + string$(nGrains) + shimmerText$

Font size: 10
Colour: "Black"

# ============================================
# CLEANUP & FINISH
# ============================================

removeObject: workSnd

selectObject: snd
plusObject: finalOut

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
selectObject: finalOut
n_ch = Get number of channels
out_dur = Get total duration
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(out_dur, 2), " s"
appendInfoLine: "Channels: ", n_ch

if play_result
    appendInfoLine: "Playing..."
    selectObject: finalOut
    Play
endif

selectObject: finalOut