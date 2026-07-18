# ============================================================
# Praat AudioTools - Neural_Ambient_Drone_Designer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
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
#     "No tonal segments found" failure.
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

form Cluster-Based Ambient Drone Designer v0.7
    comment === Preset ===
    optionmenu Preset: 1
        option Manual
        option Dark Ambient
        option Bright Shimmer
        option Dense Texture
        option Sparse Minimal
        option Evolving Pad
    comment === Reproducibility ===
    integer Seed 0
    comment (0 = unpredictable/random each run; any other integer = reproducible run)
    comment === Synthesis ===
    positive Output_duration_sec 20.0
    integer Layer_density 3
    positive Grain_crossfade_ms 20
    comment === Shimmer Control ===
    boolean Add_octave_shimmer 1
    positive Shimmer_probability 0.15
    optionmenu Shimmer_intervals: 1
        option Octaves only
        option Octaves and fifths
        option Full harmonic series
    comment === Feature Extraction & Clustering ===
    positive Grain_size_ms 100
    integer Number_of_clusters 3
    integer Kmeans_iterations 10
    comment === Output ===
    boolean Stereo_output 1
    real Stereo_width 0.7
    boolean Play_result 1
endform

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
    exitScript: "Layer_density must be at least 1."
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

if seed <> 0
    random_initializeWithSeedUnsafelyButPredictably (seed)
    seedStr$ = string$(seed) + " (fixed / reproducible)"
else
    random_initializeSafelyAndUnpredictably ()
    seedStr$ = "0 (unpredictable)"
endif

# ============================================
# SETUP
# ============================================

selectObject: snd
dur = Get total duration
fs = Get sampling frequency
nch = Get number of channels

selectObject: snd
workSnd = Convert to mono
Rename: "Analysis_Work"

grainSec = grain_size_ms / 1000
stepSec = grainSec * 0.5
crossfadeSec = grain_crossfade_ms / 1000

# v0.6: the true per-join crossfade time, shared by the grain
# assembly (Concatenate with overlap) and the grains_needed
# calculation below, so the two stay consistent with each other.
fade = min(crossfadeSec, grainSec * 0.4)

if dur < grainSec * 2
    removeObject: workSnd
    exitScript: "Sound too short. Need at least " + fixed$(grainSec * 2, 2) + " s."
endif

clearinfo
writeInfoLine: "=== Cluster-Based Ambient Drone Designer v0.7 ==="
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

nGrains = floor((dur - grainSec) / stepSec)
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
    t = (i - 0.5) * stepSec
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

if number_of_clusters < 1
    exitScript: "Number_of_clusters must be at least 1."
endif
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

for c from 1 to k
    randRow = randomInteger(1, nGrains)
    cent_c#[c] = norm_cent#[randRow]
    cent_b#[c] = norm_band#[randRow]
    cent_h#[c] = norm_hnr#[randRow]
    cent_p#[c] = norm_pitch#[randRow]
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
    
    if changes = 0
        appendInfoLine: "  Converged at iteration ", iter
        iter = kmeans_iterations + 1
    endif
endfor

# ============================================
# IDENTIFY BEST CLUSTER (Highest HNR)
# ============================================

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
    exitScript: "k-means produced no non-empty clusters. Try a different Seed or fewer clusters."
endif

appendInfoLine: "  Selected Cluster ", best_cluster, " (Most Tonal, ",
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
    exitScript: "No tonal segments found. Try more clusters."
endif

appendInfoLine: "  Found ", tonal_count, " tonal grains"

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
                    gid_new = Create Sound from formula: "g", 1, 0, gid_dur0, sr_orig, "0"
                    selectObject: gid_new
                    shiftedStr$ = string$(gid_shifted)
                    Formula (part): 0, shifted_dur, 1, 1,
                        ... "Object_" + shiftedStr$ + "(x)"
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
Scale peak: 0.99

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

Text: 0.5, "centre", 0.5, "half", "Grain: " + string$(grain_size_ms) + "ms | Clusters: " + string$(number_of_clusters) + " | Tonal grains: " + string$(tonal_count) + "/" + string$(nGrains) + shimmerText$

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