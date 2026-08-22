# ============================================================
# Praat AudioTools - Neural_Granular_Texture_Morpher.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.8 (2026) - Suite-standard visualization
#
# Changelog v0.8 (2026):
#   - VISUALIZATION STANDARDIZATION ONLY; K-means analysis, event-list
#     generation, morph traversal, pitch/position/density variation,
#     true overlap-add normalization and stereo rendering are unchanged.
#   - Adopted the Praat AudioTools 8-inch page convention with explicit
#     inner viewports, suite-standard title/subtitle, typography, neutral
#     panel backgrounds, summary strip and full-page export viewport.
#   - Preserved the source/output waveforms, real-onset cluster trajectory
#     and cluster population display; the old text-only stats panel has
#     been consolidated into the summary strip.
#   - Added draw-safe source names and measured output information.
#
# Changelog v0.6 (2026):
#
#   AUDIO CHANGES throughout. The analysis grid, the placement and the
#   gain law all moved.
#
#   CRITICAL 1 - Stereo_spread was connected to nothing. The parameter
#     appeared in the form, in every preset and in the Info banner, and
#     the string "stereo_spread" occurred nowhere else in the script.
#     Stereo mode simply ran the entire engine twice, redrawing the
#     start cluster, the morph path, the grain index, the position
#     jitter, the density jitter and the pitch scatter each time - so
#     Stereo_spread = 0 gave two fully independent channels, exactly
#     like 1. v0.6 builds ONE event list (cluster, grain, source
#     position, varispeed ratio, output onset) and derives the right
#     channel from it: 0 copies it exactly, intermediate values
#     re-decide that fraction of events, 1 walks independently.
#
#   CRITICAL 2 - the analysis grid did not describe the grains played.
#     nGrains used floor((dur - grain) / hop) with no +1, dropping a
#     valid window, and centres sat at (i - 0.5) * hop instead of
#     grain/2 + (i-1) * hop. On Slow Evolution (80 ms grain, 60%
#     overlap, 32 ms hop) the first analysis point is 16 ms while the
#     first rendered grain is centred at 40 ms - a 24 ms error. Every
#     feature vector described audio next to the grain it clustered.
#
#   CRITICAL 3 - the OLA used a fixed gain guess, not the real overlap.
#     1 / (1 + overlap_ratio * 0.8) is a single global multiplier that
#     knows nothing about how many grains land on a given sample, what
#     the Hann window is worth there, or how Density_variation moved
#     the onsets. v0.6 accumulates each grain's Hann window into an
#     envelope buffer and divides by it, so the gain is correct
#     sample by sample at any overlap and under any onset jitter.
#
#   4 - The output is the requested length. The buffer was
#     output_duration_sec + grainSec and was never trimmed, so a 10 s
#     request produced a 10.06 s file with a partial grain and possibly
#     a short silent tail past the end. Now trimmed exactly, with a
#     global fade.
#
#   5 - Pitch scatter no longer pads with silence. A grain shortened by
#     varispeed was written into a buffer of zeros, so one half of the
#     scatter range added silence while the other half truncated
#     material - an asymmetry with no musical justification. The grain
#     is tiled with a short internal crossfade instead. The arbitrary
#     new_fs > 8000 lower bound is gone too: on an 8 kHz file it
#     rejected every downward shift while allowing upward ones.
#
#   6 - Morph_speed_hz renamed State_transition_rate_hz. It never meant
#     the same thing in every mode: in Cycle each cluster lasts
#     1/rate seconds, so a full cycle takes k/rate - 4 clusters at
#     1 Hz is a 0.25 Hz cycle - while Random Walk and Random Jump use
#     it as a per-step probability rate. The new name describes the
#     one thing it does consistently.
#
#   7 - "Local Random Step" renamed Local Random Step. It draws
#     randomInteger(-1, 1) and adds it to the current cluster: a lazy
#     neighbour walk. No weights based on centroid distance, cluster
#     size, transition counts or similarity exist anywhere.
#
#   8 - Empty clusters no longer occupy the morph axis. Centroids were
#     seeded with replacement, so two could start on the same grain and
#     leave a cluster permanently empty; the morph path still stepped
#     through 1..k including the dead ones, so several axis positions
#     mapped to the same active cluster and the traversal rate was
#     uneven. v0.6 seeds distinct grains, recounts from the final
#     assignment, and morphs over a dense list of ACTIVE clusters only.
#     (CORRECTION, v0.7: this entry also claimed empty clusters were
#     reseeded from a donor. No such reseeding was written. The three
#     mechanisms above are what exists, and they are sufficient - an
#     empty cluster simply never enters activeList#.)
#
#   9 - Random_seed added (0 = unpredictable), with the generator
#     returned to its safe state afterwards.
#
#   10 - Validation for overlap, cluster count, jitter amounts, spread
#     and scatter. Overlap_ratio = 1 gave a zero hop and divided by
#     zero in both nGrains and grains_needed.
#
#   11 - Silent input rejected; the final normalisation is conditional.
#
#   12 - The Spectrogram ceiling follows Nyquist. A hardcoded 8000 Hz
#     is above Nyquist on any file below 16 kHz.
#
#   13 - "Neural" is gone: there is no network, no training and no
#     learned weight here. It is a K-means cluster-based granular
#     texture morpher, and the version strings (header v0.5, form v0.4,
#     Info v0.4) now agree.
#
#   Multichannel input is downmixed to mono; the stereo output is
#   synthesised from the event list above, not from the source image.
#
# (superseded) Version: 0.5 (2026) - Empty-cluster fallback, scatter length preserved,
#                        stereo cluster trajectory, title/stats axes
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   K-means Granular Texture Morpher - K-means clustering
#   with multiple morph modes for texture evolution.
#
# Changelog v0.5 (changes the audio of some presets):
#   - Empty-cluster fallback now draws from a random non-empty
#     cluster instead of always grabbing grain #1 (removes a
#     first-grain bias when clusters are sparse)
#   - Pitch scatter preserves grain DURATION (resample keeps the
#     grid aligned) instead of silently rescaling the time axis
#   - Stereo: cluster trajectory recorded for BOTH channels and
#     both are drawn; right channel shown dashed
#   - Title and Stats panels set explicit Axes: 0,1,0,1
#
# Changelog v0.4:
#   - Fixed preset comparison (number not string)
#   - Fixed morph_mode$ undefined variable
#   - Fixed Formula object references
#   - Added preset name to output
#   - Added visualization
# ============================================================

# === Input Validation ===
nSelected = numberOfSelected("Sound")
if nSelected <> 1
    exitScript: "Please select exactly one Sound object."
endif

snd = selected("Sound")
sndName$ = selected$("Sound")

form K-means Granular Texture Morpher v0.8
    optionmenu Preset: 1
        option Manual
        option Slow Evolution
        option Rapid Texture
        option Random Walk
        option Rhythmic Cycle
        option Ambient Drift
        option Chaotic Morph
    positive Grain_size_ms 60
    positive Overlap_ratio 0.5
    integer Number_of_clusters 4
    positive Output_duration_sec 10.0
    positive State_transition_rate_hz 0.5
    optionmenu Morph_mode: 1
        option Cycle (linear)
        option Pendulum (back-forth)
        option Random Walk
        option Random Jump
        option Local Random Step
    real Pitch_scatter_semitones 0.0
    real Position_randomness 0.2
    real Density_variation 0.1
    real Stereo_spread 0.5
    integer Random_seed 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Stereo_spread: 0 = identical channels, 1 = an independent walk per
# channel, in between = that fraction of events re-decided. Negative
# gives mono output.
# State_transition_rate_hz is a transition RATE, not a cycle frequency:
# in Cycle each cluster lasts 1/rate seconds, so a full pass over k
# clusters takes k/rate seconds.
# Multichannel input is downmixed to mono.
morph_speed_hz = state_transition_rate_hz
if stereo_spread < 0
    stereo_output = 0
    stereo_spread = 0
else
    stereo_output = 1
endif

# ============================================
# PRESET LOGIC
# ============================================

if preset = 2
    # Slow Evolution
    grain_size_ms = 80
    overlap_ratio = 0.6
    number_of_clusters = 4
    output_duration_sec = 15.0
    morph_speed_hz = 0.15
    state_transition_rate_hz = 0.15
    morph_mode = 1
    pitch_scatter_semitones = 0.0
    position_randomness = 0.1
    density_variation = 0.05
    stereo_spread = 0.4
    presetName$ = "SlowEvolution"
elsif preset = 3
    # Rapid Texture
    grain_size_ms = 30
    overlap_ratio = 0.4
    number_of_clusters = 6
    output_duration_sec = 8.0
    morph_speed_hz = 2.0
    state_transition_rate_hz = 2.0
    morph_mode = 1
    pitch_scatter_semitones = 0.5
    position_randomness = 0.3
    density_variation = 0.15
    stereo_spread = 0.6
    presetName$ = "RapidTexture"
elsif preset = 4
    # Random Walk
    grain_size_ms = 50
    overlap_ratio = 0.5
    number_of_clusters = 5
    output_duration_sec = 12.0
    morph_speed_hz = 0.8
    state_transition_rate_hz = 0.8
    morph_mode = 3
    pitch_scatter_semitones = 0.3
    position_randomness = 0.25
    density_variation = 0.1
    stereo_spread = 0.5
    presetName$ = "RandomWalk"
elsif preset = 5
    # Rhythmic Cycle
    grain_size_ms = 40
    overlap_ratio = 0.3
    number_of_clusters = 4
    output_duration_sec = 10.0
    morph_speed_hz = 1.0
    state_transition_rate_hz = 1.0
    morph_mode = 2
    pitch_scatter_semitones = 0.0
    position_randomness = 0.05
    density_variation = 0.0
    stereo_spread = 0.3
    presetName$ = "RhythmicCycle"
elsif preset = 6
    # Ambient Drift
    grain_size_ms = 100
    overlap_ratio = 0.7
    number_of_clusters = 3
    output_duration_sec = 20.0
    morph_speed_hz = 0.1
    state_transition_rate_hz = 0.1
    morph_mode = 3
    pitch_scatter_semitones = 0.2
    position_randomness = 0.15
    density_variation = 0.08
    stereo_spread = 0.7
    presetName$ = "AmbientDrift"
elsif preset = 7
    # Chaotic Morph
    grain_size_ms = 45
    overlap_ratio = 0.5
    number_of_clusters = 8
    output_duration_sec = 10.0
    morph_speed_hz = 1.5
    state_transition_rate_hz = 1.5
    morph_mode = 4
    pitch_scatter_semitones = 1.0
    position_randomness = 0.4
    density_variation = 0.2
    stereo_spread = 0.8
    presetName$ = "ChaoticMorph"
else
    presetName$ = "Manual"
endif

# Get morph mode name
if morph_mode = 1
    morphModeName$ = "Cycle"
elsif morph_mode = 2
    morphModeName$ = "Pendulum"
elsif morph_mode = 3
    morphModeName$ = "RandomWalk"
elsif morph_mode = 4
    morphModeName$ = "RandomJump"
else
    morphModeName$ = "LocalRandomStep"
endif

# ============================================
# SETUP
# ============================================

selectObject: snd
dur = Get total duration
fs = Get sampling frequency

clearinfo
writeInfoLine: "=== K-means Granular Texture Morpher v0.8 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Grain: ", grain_size_ms, " ms | Overlap: ", fixed$(overlap_ratio * 100, 0), "%"
appendInfoLine: "Clusters: ", number_of_clusters, " | Morph: ", morph_speed_hz, " Hz"
appendInfoLine: "Mode: ", morphModeName$
if stereo_output
    appendInfoLine: "Output: Stereo (spread ", fixed$(stereo_spread * 100, 0), "%)"
else
    appendInfoLine: "Output: Mono"
endif
appendInfoLine: ""

selectObject: snd
workSnd = Convert to mono

# ============================================
# VALIDATION  (v0.6 fix 10)
# ============================================
warnLines$ = ""
if overlap_ratio < 0
    overlap_ratio = 0
    warnLines$ = warnLines$ + "  ! Overlap_ratio < 0 leaves gaps -> 0" + newline$
endif
if overlap_ratio > 0.95
    overlap_ratio = 0.95
    warnLines$ = warnLines$ + "  ! Overlap_ratio >= 1 gives a zero hop (division by zero)" +
        ... " -> 0.95" + newline$
endif
if number_of_clusters < 1
    number_of_clusters = 1
    warnLines$ = warnLines$ + "  ! Number_of_clusters < 1 -> 1" + newline$
endif
if position_randomness < 0
    position_randomness = 0
    warnLines$ = warnLines$ + "  ! Position_randomness < 0 -> 0" + newline$
endif
if position_randomness > 1
    position_randomness = 1
    warnLines$ = warnLines$ + "  ! Position_randomness > 1 -> 1" + newline$
endif
if density_variation < 0
    density_variation = 0
    warnLines$ = warnLines$ + "  ! Density_variation < 0 -> 0" + newline$
endif
if density_variation > 1
    density_variation = 1
    warnLines$ = warnLines$ + "  ! Density_variation > 1 -> 1" + newline$
endif
if stereo_spread > 1
    stereo_spread = 1
    warnLines$ = warnLines$ + "  ! Stereo_spread > 1 -> 1" + newline$
endif
if pitch_scatter_semitones < 0
    pitch_scatter_semitones = 0
    warnLines$ = warnLines$ + "  ! Pitch_scatter_semitones < 0 -> 0" + newline$
endif

# v0.6 fix 11: a silent input gives undefined centroid and bandwidth,
# fallback pitch and HNR, and then an invalid k-means pass.
selectObject: workSnd
srcPeak = Get absolute extremum: 0, 0, "None"
if srcPeak < 1e-6
    removeObject: workSnd
    exitScript: "The selected Sound is silent (or near-silent); nothing to cluster."
endif

Rename: "Analysis_Work"

grainSec = grain_size_ms / 1000
stepSec = grainSec * (1 - overlap_ratio)

if dur < grainSec * 2
    removeObject: workSnd
    exitScript: "Sound too short for granular analysis."
endif

k = number_of_clusters

# ============================================
# FEATURE EXTRACTION
# ============================================

appendInfoLine: "Analyzing grains..."

# v0.6 CRITICAL 2: the missing +1. floor((D-G)/H) drops the last
# valid window.
nGrains = floor((dur - grainSec) / stepSec) + 1
if nGrains < k
    removeObject: workSnd
    exitScript: "Not enough grains. Reduce grain size or clusters."
endif

# v0.7: seed AFTER every deterministic exit. v0.6 seeded before the
# "Sound too short" and "Not enough grains" checks, so a positive seed
# left Praat's generator globally predictable when either fired.
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedLabel$ = string$(random_seed)
else
    random_initializeSafelyAndUnpredictably ()
    seedLabel$ = "unpredictable"
endif

feat_centroid# = zero#(nGrains)
feat_bandwidth# = zero#(nGrains)
feat_pitch# = zero#(nGrains)
feat_hnr# = zero#(nGrains)
feat_intensity# = zero#(nGrains)
grain_time# = zero#(nGrains)

selectObject: workSnd
# v0.6 fix 12: a hardcoded 8000 Hz ceiling is above Nyquist on any
# file below 16 kHz.
specMax = 8000
if specMax > fs / 2 * 0.9
    specMax = fs / 2 * 0.9
endif
spec = To Spectrogram: grainSec, specMax, stepSec, 20, "Gaussian"

selectObject: workSnd
pit = To Pitch: stepSec, 75, 600

selectObject: workSnd
hnr_obj = To Harmonicity (cc): stepSec, 75, 0.1, 1.0

selectObject: workSnd
inten = To Intensity: 75, stepSec, "yes"

for i from 1 to nGrains
    # v0.6 CRITICAL 2: the first window's CENTRE is grain/2, not
    # hop/2. On Slow Evolution (80 ms grain, 32 ms hop) the old
    # formula analysed 16 ms while the first rendered grain is
    # centred at 40 ms - a 24 ms error on every frame.
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
    
    selectObject: pit
    f0 = Get value at time: t, "Hertz", "Linear"
    if f0 = undefined or f0 <= 0
        feat_pitch#[i] = 0
    else
        feat_pitch#[i] = f0
    endif
    
    selectObject: hnr_obj
    h = Get value at time: t, "cubic"
    if h = undefined
        feat_hnr#[i] = -50
    else
        feat_hnr#[i] = h
    endif
    
    selectObject: inten
    iv = Get value at time: t, "cubic"
    if iv = undefined
        feat_intensity#[i] = 50
    else
        feat_intensity#[i] = iv
    endif
endfor

removeObject: spec, pit, hnr_obj, inten

appendInfoLine: "  ", nGrains, " grains analyzed"

# ============================================
# NORMALIZE FEATURES
# ============================================

# Centroid
sum = 0
for i to nGrains
    sum += feat_centroid#[i]
endfor
mean_c = sum / nGrains
sumSq = 0
for i to nGrains
    sumSq += (feat_centroid#[i] - mean_c)^2
endfor
std_c = sqrt(sumSq / nGrains)
if std_c < 0.001
    std_c = 1
endif
norm_centroid# = zero#(nGrains)
for i to nGrains
    norm_centroid#[i] = (feat_centroid#[i] - mean_c) / std_c
endfor

# Bandwidth
sum = 0
for i to nGrains
    sum += feat_bandwidth#[i]
endfor
mean_b = sum / nGrains
sumSq = 0
for i to nGrains
    sumSq += (feat_bandwidth#[i] - mean_b)^2
endfor
std_b = sqrt(sumSq / nGrains)
if std_b < 0.001
    std_b = 1
endif
norm_bandwidth# = zero#(nGrains)
for i to nGrains
    norm_bandwidth#[i] = (feat_bandwidth#[i] - mean_b) / std_b
endfor

# Pitch
sum = 0
for i to nGrains
    sum += feat_pitch#[i]
endfor
mean_p = sum / nGrains
sumSq = 0
for i to nGrains
    sumSq += (feat_pitch#[i] - mean_p)^2
endfor
std_p = sqrt(sumSq / nGrains)
if std_p < 0.001
    std_p = 1
endif
norm_pitch# = zero#(nGrains)
for i to nGrains
    norm_pitch#[i] = (feat_pitch#[i] - mean_p) / std_p
endfor

# HNR
sum = 0
for i to nGrains
    sum += feat_hnr#[i]
endfor
mean_h = sum / nGrains
sumSq = 0
for i to nGrains
    sumSq += (feat_hnr#[i] - mean_h)^2
endfor
std_h = sqrt(sumSq / nGrains)
if std_h < 0.001
    std_h = 1
endif
norm_hnr# = zero#(nGrains)
for i to nGrains
    norm_hnr#[i] = (feat_hnr#[i] - mean_h) / std_h
endfor

# Intensity
sum = 0
for i to nGrains
    sum += feat_intensity#[i]
endfor
mean_i = sum / nGrains
sumSq = 0
for i to nGrains
    sumSq += (feat_intensity#[i] - mean_i)^2
endfor
std_i = sqrt(sumSq / nGrains)
if std_i < 0.001
    std_i = 1
endif
norm_intensity# = zero#(nGrains)
for i to nGrains
    norm_intensity#[i] = (feat_intensity#[i] - mean_i) / std_i
endfor

# ============================================
# K-MEANS CLUSTERING
# ============================================

appendInfoLine: "Clustering textures..."

cent_1# = zero#(k)
cent_2# = zero#(k)
cent_3# = zero#(k)
cent_4# = zero#(k)
cent_5# = zero#(k)

shufIdx# = zero#(nGrains)
for si from 1 to nGrains
    shufIdx#[si] = si
endfor
nShuf = min(k, nGrains)
for si from 1 to nShuf
    rr = randomInteger(si, nGrains)
    tmpv = shufIdx#[si]
    shufIdx#[si] = shufIdx#[rr]
    shufIdx#[rr] = tmpv
endfor

for c from 1 to k
    # v0.6 fix 8: DISTINCT seeds from a shuffled index list. Drawing
    # with replacement let two centroids start on the same grain and
    # leave a cluster permanently empty.
    r = shufIdx#[c]
    cent_1#[c] = norm_centroid#[r]
    cent_2#[c] = norm_bandwidth#[r]
    cent_3#[c] = norm_pitch#[r]
    cent_4#[c] = norm_hnr#[r]
    cent_5#[c] = norm_intensity#[r]
endfor

assigns# = zero#(nGrains)

max_iter = 15
for iter from 1 to max_iter
    changes = 0
    
    for i from 1 to nGrains
        minDist = 1e9
        bestK = 1
        
        for c from 1 to k
            distSq = (norm_centroid#[i] - cent_1#[c])^2 +
                ... (norm_bandwidth#[i] - cent_2#[c])^2 +
                ... (norm_pitch#[i] - cent_3#[c])^2 +
                ... (norm_hnr#[i] - cent_4#[c])^2 +
                ... (norm_intensity#[i] - cent_5#[c])^2
            
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
        sum_1 = 0
        sum_2 = 0
        sum_3 = 0
        sum_4 = 0
        sum_5 = 0
        count = 0
        
        for i from 1 to nGrains
            if assigns#[i] = c
                sum_1 += norm_centroid#[i]
                sum_2 += norm_bandwidth#[i]
                sum_3 += norm_pitch#[i]
                sum_4 += norm_hnr#[i]
                sum_5 += norm_intensity#[i]
                count += 1
            endif
        endfor
        
        if count > 0
            cent_1#[c] = sum_1 / count
            cent_2#[c] = sum_2 / count
            cent_3#[c] = sum_3 / count
            cent_4#[c] = sum_4 / count
            cent_5#[c] = sum_5 / count
        endif
    endfor
    
    if changes = 0
        appendInfoLine: "  Converged at iteration ", iter
        iter = max_iter + 1
    endif
endfor

# ============================================
# BUILD CLUSTER INDEX
# ============================================

appendInfoLine: "  Building cluster index..."

cluster_count# = zero#(k)
for i from 1 to nGrains
    c = assigns#[i]
    cluster_count#[c] += 1
endfor

# v0.6 fix 8: one authoritative pass. Every grain is reassigned to its
# nearest FINAL centroid and the counts rebuilt, so cluster_count#
# describes assigns#. Then a DENSE list of active clusters is built:
# v0.5 morphed over 1..k including empty ones, so several axis
# positions mapped to the same active cluster and the traversal rate
# was uneven.
for c from 1 to k
    cluster_count#[c] = 0
endfor
for i from 1 to nGrains
    minD = 1e30
    bestC = 1
    for c from 1 to k
        dd = (norm_centroid#[i] - cent_1#[c])^2 +
            ... (norm_bandwidth#[i] - cent_2#[c])^2 +
            ... (norm_pitch#[i] - cent_3#[c])^2 +
            ... (norm_hnr#[i] - cent_4#[c])^2 +
            ... (norm_intensity#[i] - cent_5#[c])^2
        if dd < minD
            minD = dd
            bestC = c
        endif
    endfor
    assigns#[i] = bestC
    cluster_count#[bestC] = cluster_count#[bestC] + 1
endfor

# v0.7: order the active clusters by centroid PROXIMITY, not by label.
# K-means labels are arbitrary - they come from the order of the random
# centroid seeds - so "cluster 2 is next to cluster 3" meant nothing.
# Cycle was not a linear traversal of timbre, Pendulum swung along an
# arbitrary path, and a different seed reordered the morph even when
# the partition of the material was nearly identical.
# A greedy nearest-neighbour path over the centroids gives the axis a
# real timbral meaning: adjacent positions are now adjacent textures.
rawActive# = zero#(k)
nActive = 0
for c from 1 to k
    if cluster_count#[c] > 0
        nActive = nActive + 1
        rawActive#[nActive] = c
    endif
endfor

activeList# = zero#(k)
usedC# = zero#(k)
if nActive > 0
    # start from the cluster with the lowest centroid brightness, so
    # the axis has a stable orientation rather than a seed-dependent one
    startI = 1
    bestVal = 1e30
    for a from 1 to nActive
        cc = rawActive#[a]
        if cent_1#[cc] < bestVal
            bestVal = cent_1#[cc]
            startI = a
        endif
    endfor
    activeList#[1] = rawActive#[startI]
    usedC#[startI] = 1
    for pos from 2 to nActive
        prevC = activeList#[pos - 1]
        bestD = 1e30
        bestA = 0
        for a from 1 to nActive
            if usedC#[a] = 0
                cc = rawActive#[a]
                dd = (cent_1#[cc] - cent_1#[prevC])^2 +
                    ... (cent_2#[cc] - cent_2#[prevC])^2 +
                    ... (cent_3#[cc] - cent_3#[prevC])^2 +
                    ... (cent_4#[cc] - cent_4#[prevC])^2 +
                    ... (cent_5#[cc] - cent_5#[prevC])^2
                if dd < bestD
                    bestD = dd
                    bestA = a
                endif
            endif
        endfor
        if bestA > 0
            activeList#[pos] = rawActive#[bestA]
            usedC#[bestA] = 1
        endif
    endfor
    ordStr$ = ""
    for pos from 1 to nActive
        ordStr$ = ordStr$ + " " + string$(activeList#[pos])
    endfor
    appendInfoLine: "  Morph axis (ordered by centroid proximity):", ordStr$
endif
appendInfoLine: "  Active clusters: ", nActive, " of ", k, " requested"
if nActive < 1
    random_initializeSafelyAndUnpredictably ()
    exitScript: "k-means produced no non-empty cluster."
endif

cluster_offset# = zero#(k + 1)
cluster_offset#[1] = 0
for c from 2 to k + 1
    cluster_offset#[c] = cluster_offset#[c-1] + cluster_count#[c-1]
endfor

cluster_index# = zero#(nGrains)
cluster_fill# = zero#(k)

for i from 1 to nGrains
    c = assigns#[i]
    pos = cluster_offset#[c] + cluster_fill#[c] + 1
    cluster_index#[pos] = i
    cluster_fill#[c] += 1
endfor

valid_clusters = 0
for c from 1 to k
    if cluster_count#[c] > 0
        valid_clusters += 1
    endif
endfor

# v0.7: this exit happens AFTER seeding, so restore the generator.
if valid_clusters < 2
    random_initializeSafelyAndUnpredictably ()
    removeObject: workSnd
    exitScript: "Not enough distinct textures. Try fewer clusters."
endif

appendInfoLine: "  ", valid_clusters, " valid clusters"

# ============================================
# GENERATIVE SYNTHESIS
# ============================================

appendInfoLine: ""
appendInfoLine: "Synthesizing texture..."

grains_needed = ceiling(output_duration_sec / stepSec)
output_dur = output_duration_sec + grainSec

if stereo_output
    n_passes = 2
else
    n_passes = 1
endif

current_cluster = 1
walk_momentum = 0

# Track cluster usage for visualization (per channel)
cluster_history# = zero#(grains_needed)
cluster_history_R# = zero#(grains_needed)

# ============================================================
# EVENT LIST  (v0.6 CRITICAL 1)
# ============================================================
# v0.5 ran the whole engine twice and redrew every decision each time,
# so Stereo_spread = 0 gave two unrelated channels - identical in
# behaviour to Stereo_spread = 1. The parameter was declared, set by
# every preset, printed in the Info banner, and read by nothing.
# One event list is built for the left channel; the right is DERIVED
# from it, with Stereo_spread deciding how much diverges.

ev_cluster# = zero#(grains_needed)
ev_grain# = zero#(grains_needed)
ev_tout# = zero#(grains_needed)
ev_ratio# = zero#(grains_needed)
ev_tgrain# = zero#(grains_needed)
# v0.7: the active-list POSITION of each left event. v0.6 restored the
# right chain with curPosR = curPos, but curPos is the state after the
# ENTIRE left list was built, not the state at event g - so a copied
# event sounded correct while the chain it continued from was wrong.
ev_pos# = zero#(grains_needed)

evR_cluster# = zero#(grains_needed)
evR_grain# = zero#(grains_needed)
evR_tout# = zero#(grains_needed)
evR_ratio# = zero#(grains_needed)
evR_tgrain# = zero#(grains_needed)

# --- pick a grain from a cluster, with its position and scatter ---
procedure drawEvent: .cluster
    .cnt = cluster_count#[.cluster]
    if .cnt < 1
        exitScript: "Internal error: cluster " + string$(.cluster) + " is empty."
    endif
    .r = randomInteger(1, .cnt)
    drawEvent.grain = cluster_index#[cluster_offset#[.cluster] + .r]

    .tg = grain_time#[drawEvent.grain]
    if position_randomness > 0
        .tg = .tg + randomUniform(-1, 1) * position_randomness * grainSec
        .tg = max(grainSec/2, min(dur - grainSec/2, .tg))
    endif
    drawEvent.tgrain = .tg

    if pitch_scatter_semitones > 0
        .sc = randomUniform(-pitch_scatter_semitones, pitch_scatter_semitones)
        drawEvent.ratio = 2 ^ (.sc / 12)
    else
        drawEvent.ratio = 1
    endif
endproc

# --- morph over the DENSE active list, not 1..k ---
procedure nextCluster: .curPos, .tOut
    if morph_mode = 1
        .cyc = .tOut * morph_speed_hz
        nextCluster.out = floor(.cyc mod nActive) + 1
    elsif morph_mode = 2
        .cyc = .tOut * morph_speed_hz
        .period = 2 * nActive - 2
        if .period < 1
            .period = 1
        endif
        .ph = .cyc mod .period
        if .ph < nActive
            nextCluster.out = floor(.ph) + 1
        else
            nextCluster.out = nActive - floor(.ph - nActive) - 1
        endif
        if nextCluster.out < 1
            nextCluster.out = 1
        endif
        if nextCluster.out > nActive
            nextCluster.out = nActive
        endif
    elsif morph_mode = 3
        if randomUniform(0, 1) < morph_speed_hz * stepSec
            .off = randomInteger(-1, 1)
            .np = .curPos + .off
            if .np < 1
                .np = 1
            endif
            if .np > nActive
                .np = nActive
            endif
            nextCluster.out = .np
        else
            nextCluster.out = .curPos
        endif
    elsif morph_mode = 4
        if randomUniform(0, 1) < morph_speed_hz * stepSec
            nextCluster.out = randomInteger(1, nActive)
        else
            nextCluster.out = .curPos
        endif
    else
        # Local Random Step (v0.5 called this "Weighted Random"; no
        # weight of any kind is computed - it is a neighbour walk).
        # v0.7: gated by the transition rate like the other stochastic
        # modes. v0.6 stepped on EVERY grain regardless, so at a 60 ms
        # grain and 50% overlap it attempted ~33 transitions per second
        # even with State_transition_rate_hz set to 0.01 - which
        # contradicted the parameter's own name. Measured before the
        # fix: 68 of 133 grains changed cluster at BOTH rate 0.01
        # (p = 0.0003) and rate 20 (p = 0.6) - identical, because the
        # rate was never consulted.
        # It differs from Random Walk in that Random Walk can also hold
        # position on a zero offset, making it stickier; this mode
        # always moves when the gate opens.
        if randomUniform(0, 1) < min(1, morph_speed_hz * stepSec)
            .off = randomInteger(-1, 1)
            if .off = 0
                if randomUniform(0, 1) < 0.5
                    .off = -1
                else
                    .off = 1
                endif
            endif
            .np = .curPos + .off
            if .np < 1
                .np = 1
            endif
            if .np > nActive
                .np = nActive
            endif
            nextCluster.out = .np
        else
            nextCluster.out = .curPos
        endif
    endif
endproc

appendInfoLine: "  Building event list..."

curPos = 1
for g from 1 to grains_needed
    t_out = (g - 1) * stepSec
    if density_variation > 0
        t_out = t_out + randomUniform(-1, 1) * density_variation * stepSec
        if t_out < 0
            t_out = 0
        endif
    endif

    @nextCluster: curPos, t_out
    curPos = nextCluster.out
    cl = activeList#[curPos]

    ev_cluster#[g] = cl
    ev_tout#[g] = t_out
    @drawEvent: cl
    ev_grain#[g] = drawEvent.grain
    ev_tgrain#[g] = drawEvent.tgrain
    ev_ratio#[g] = drawEvent.ratio
    ev_pos#[g] = curPos
    cluster_history#[g] = cl
endfor

# --- derive the right channel ---
if stereo_output
    if stereo_spread <= 0
        for g from 1 to grains_needed
            evR_cluster#[g] = ev_cluster#[g]
            evR_grain#[g] = ev_grain#[g]
            evR_tout#[g] = ev_tout#[g]
            evR_tgrain#[g] = ev_tgrain#[g]
            evR_ratio#[g] = ev_ratio#[g]
            cluster_history_R#[g] = ev_cluster#[g]
        endfor
    else
        curPosR = 1
        for g from 1 to grains_needed
            if randomUniform(0, 1) < stereo_spread
                tR = (g - 1) * stepSec
                if density_variation > 0
                    tR = tR + randomUniform(-1, 1) * density_variation * stepSec
                    if tR < 0
                        tR = 0
                    endif
                endif
                @nextCluster: curPosR, tR
                curPosR = nextCluster.out
                clR = activeList#[curPosR]
                evR_cluster#[g] = clR
                evR_tout#[g] = tR
                @drawEvent: clR
                evR_grain#[g] = drawEvent.grain
                evR_tgrain#[g] = drawEvent.tgrain
                evR_ratio#[g] = drawEvent.ratio
            else
                evR_cluster#[g] = ev_cluster#[g]
                evR_grain#[g] = ev_grain#[g]
                evR_tout#[g] = ev_tout#[g]
                evR_tgrain#[g] = ev_tgrain#[g]
                evR_ratio#[g] = ev_ratio#[g]
                # v0.7: continue from the position of THIS left event,
                # not from the final state of the whole left list.
                curPosR = ev_pos#[g]
            endif
            cluster_history_R#[g] = evR_cluster#[g]
        endfor
    endif
endif

# ============================================================
# RENDER  (v0.6 CRITICAL 3: true OLA with envelope normalisation)
# ============================================================
# v0.5 applied one global multiplier, 1 / (1 + overlap * 0.8), which
# knows nothing about how many grains land on a sample, what the Hann
# window is worth there, or how Density_variation moved the onsets.

for pass from 1 to n_passes
    if stereo_output
        if pass = 1
            appendInfoLine: "  LEFT channel..."
        else
            appendInfoLine: "  RIGHT channel..."
        endif
    else
        appendInfoLine: "  Generating..."
    endif

    output_buf = Create Sound from formula: "Output_" + string$(pass), 1, 0, output_dur, fs, "0"
    env_buf = Create Sound from formula: "Env_" + string$(pass), 1, 0, output_dur, fs, "0"

    for g from 1 to grains_needed
        if pass = 1
            t_out = ev_tout#[g]
            t_grain = ev_tgrain#[g]
            ratio = ev_ratio#[g]
        else
            t_out = evR_tout#[g]
            t_grain = evR_tgrain#[g]
            ratio = evR_ratio#[g]
        endif

        t_start = t_grain - grainSec/2
        t_end = t_grain + grainSec/2
        if t_start < 0
            t_start = 0
            t_end = grainSec
        endif
        if t_end > dur
            t_end = dur
            t_start = dur - grainSec
            if t_start < 0
                t_start = 0
            endif
        endif

        # rectangular here; the Hann is applied once below so the same
        # shape can be accumulated into the envelope
        selectObject: workSnd
        grain = Extract part: t_start, t_end, "rectangular", 1, "no"

        if ratio <> 1
            selectObject: grain
            grain_dur0 = Get total duration
            orig_fs = Get sampling frequency
            new_fs = orig_fs * ratio
            # v0.6 fix 5: no arbitrary 8 kHz lower bound - on an 8 kHz
            # file it rejected every downward shift while allowing the
            # upward ones.
            if new_fs > 1000 and new_fs < 200000
                Resample: new_fs, 50
                Override sampling frequency: orig_fs
                grain_shifted = selected("Sound")
                removeObject: grain
                selectObject: grain_shifted
                shifted_dur = Get total duration
                if shifted_dur >= grain_dur0
                    grain = Extract part: 0, grain_dur0, "rectangular", 1, "no"
                    removeObject: grain_shifted
                else
                    # v0.6 fix 5: TILE, do not pad with zeros. v0.5
                    # wrote the shortened grain into a buffer of
                    # silence, so one half of the scatter range added
                    # holes while the other truncated material.
                    tileFade = 0.002
                    if tileFade > shifted_dur * 0.25
                        tileFade = shifted_dur * 0.25
                    endif
                    nCopies = ceiling((grain_dur0 + tileFade) / (shifted_dur - tileFade))
                    if nCopies < 2
                        nCopies = 2
                    endif
                    selectObject: grain_shifted
                    tAcc = Copy: "tile_acc"
                    for cc from 2 to nCopies
                        selectObject: grain_shifted
                        tNext = Copy: "tile_next"
                        selectObject: tAcc
                        plusObject: tNext
                        if tileFade > 0.0002
                            tNew = Concatenate with overlap: tileFade
                        else
                            tNew = Concatenate
                        endif
                        removeObject: tAcc, tNext
                        tAcc = tNew
                    endfor
                    selectObject: tAcc
                    tiledDur = Get total duration
                    if tiledDur < grain_dur0
                        selectObject: grain_shifted
                        tNext = Copy: "tile_next"
                        selectObject: tAcc
                        plusObject: tNext
                        tNew = Concatenate with overlap: tileFade
                        removeObject: tAcc, tNext
                        tAcc = tNew
                    endif
                    selectObject: tAcc
                    grain = Extract part: 0, grain_dur0, "rectangular", 1, "no"
                    removeObject: tAcc, grain_shifted
                endif
            endif
        endif

        selectObject: grain
        grain_dur = Get total duration
        if grain_dur > 0.0005
            selectObject: grain
            Formula: "self * (0.5 - 0.5 * cos(2 * pi * (x - xmin) / (xmax - xmin)))"
        endif

        if t_out + grain_dur > output_dur
            grain_dur = output_dur - t_out
        endif

        if grain_dur > 0.0005
            selectObject: grain
            Shift times to: "start time", t_out
            gStr$ = string$(grain)
            oStr$ = fixed$(t_out, 9)
            gdStr$ = fixed$(grain_dur, 9)

            selectObject: output_buf
            Formula (part): t_out, t_out + grain_dur, 1, 1,
                ... "self + object(" + gStr$ + ", x)"

            selectObject: env_buf
            Formula (part): t_out, t_out + grain_dur, 1, 1,
                ... "self + (0.5 - 0.5 * cos(2 * pi * (x - " + oStr$ + ") / " + gdStr$ + "))"
        endif

        removeObject: grain
    endfor

    # divide by the accumulated envelope
    selectObject: env_buf
    envPeak = Get absolute extremum: 0, 0, "None"
    if envPeak < 1e-9
        envPeak = 1e-9
    endif
    efStr$ = fixed$(envPeak * 0.02, 9)
    envStr$ = string$(env_buf)
    selectObject: output_buf
    Formula: "self / max(object[" + envStr$ + ", col], " + efStr$ + ")"
    removeObject: env_buf

    # v0.6 fix 4: deliver the requested length exactly. v0.5 built the
    # buffer at output_duration_sec + grainSec and never trimmed, so a
    # 10 s request produced a 10.06 s file.
    selectObject: output_buf
    bufNow = Get total duration
    if bufNow > output_duration_sec
        selectObject: output_buf
        trimBuf = Extract part: 0, output_duration_sec, "rectangular", 1, "no"
        removeObject: output_buf
        output_buf = trimBuf
    endif

    selectObject: output_buf
    chDur = Get total duration
    eF = 0.005
    if eF > chDur * 0.1
        eF = chDur * 0.1
    endif
    if eF > 0.0002
        eFs$ = fixed$(eF, 8)
        selectObject: output_buf
        Formula: "if x - xmin < " + eFs$ + " then self * ((x - xmin) / " + eFs$ + ") else self fi"
        selectObject: output_buf
        Formula: "if xmax - x < " + eFs$ + " then self * ((xmax - x) / " + eFs$ + ") else self fi"
    endif

    if pass = 1
        channel_left = output_buf
    else
        channel_right = output_buf
    endif
endfor

# ============================================
# COMBINE OUTPUT
# ============================================

if stereo_output
    appendInfoLine: "Combining to stereo..."
    
    selectObject: channel_left
    dur_L = Get total duration
    selectObject: channel_right
    dur_R = Get total duration
    
    min_dur = min(dur_L, dur_R)
    
    if dur_L > min_dur
        selectObject: channel_left
        tmp = Extract part: 0, min_dur, "rectangular", 1, "no"
        removeObject: channel_left
        channel_left = tmp
    endif
    if dur_R > min_dur
        selectObject: channel_right
        tmp = Extract part: 0, min_dur, "rectangular", 1, "no"
        removeObject: channel_right
        channel_right = tmp
    endif
    
    selectObject: channel_left
    plusObject: channel_right
    finalOut = Combine to stereo
    Rename: sndName$ + "_TextureMorph_" + presetName$
    
    removeObject: channel_left, channel_right
else
    finalOut = channel_left
    Rename: sndName$ + "_TextureMorph_" + presetName$
endif

selectObject: finalOut
# v0.6 fix 11: conditional, so a quiet result is not lifted along with
# its noise floor.
finalPeakChk = Get absolute extremum: 0, 0, "None"
if finalPeakChk > 0.99
    Scale peak: 0.99
endif

# v0.6 fix 9: all random draws are done.
random_initializeSafelyAndUnpredictably ()

# ============================================
# CLEANUP
# ============================================

removeObject: workSnd

# ============================================
# VISUALIZATION
# ============================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."

    selectObject: finalOut
    outDurDisplay = Get total duration
    outPeakDisplay = Get absolute extremum: 0, 0, "None"
    outChannelsDisplay = Get number of channels

    pageHeight = 6.95
    Erase all
    Select outer viewport: 0, 8, 0, pageHeight

    vizSndName$ = replace$(sndName$, "_", "\_ ", 0)

    if stereo_output
        stereoDesc$ = "stereo spread " + fixed$(stereo_spread, 2)
    else
        stereoDesc$ = "mono output"
    endif

    # === Header ===
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##K-means Granular Texture Morpher v0.8##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", vizSndName$ + " | " + presetName$ + " | " + morphModeName$ + " | " + string$(nActive) + "/" + string$(k) + " active clusters"

    # === Original waveform ===
    Select outer viewport: 0, 8, 0.66, 1.48
    Select inner viewport: 0.60, 7.70, 0.78, 1.32
    selectObject: snd
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Text top: "no", "Source Sound"

    # === Output waveform ===
    Select outer viewport: 0, 8, 1.62, 2.44
    Select inner viewport: 0.60, 7.70, 1.74, 2.28
    selectObject: finalOut
    Colour: "{0.25, 0.45, 0.75}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "no", "Time (s)"
    Text top: "no", "Granular Morph Output | " + fixed$(outDurDisplay, 2) + " s | " + string$(outChannelsDisplay) + " ch | peak " + fixed$(outPeakDisplay, 3)

    # === Cluster trajectory ===
    Select outer viewport: 0, 8, 2.64, 4.26
    Select inner viewport: 0.60, 7.70, 2.84, 4.04

    traj_tmax = (grains_needed - 1) * stepSec
    if traj_tmax <= 0
        traj_tmax = output_duration_sec
    endif
    Axes: 0, traj_tmax, 0, k + 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, traj_tmax, 0, k + 1

    # Left trajectory: actual jittered event onsets.
    Line width: 1
    for g from 2 to grains_needed
        t1 = ev_tout#[g-1]
        t2 = ev_tout#[g]
        c1 = cluster_history#[g-1]
        c2 = cluster_history#[g]
        if k > 1
            colorVal = (c2 - 1) / (k - 1)
        else
            colorVal = 0
        endif
        rVal$ = fixed$(0.25 + colorVal * 0.50, 3)
        gVal$ = fixed$(0.55 - colorVal * 0.25, 3)
        bVal$ = fixed$(0.75 - colorVal * 0.35, 3)
        Colour: "{" + rVal$ + ", " + gVal$ + ", " + bVal$ + "}"
        Draw line: t1, c1, t2, c2
    endfor

    # Right trajectory: dashed neutral overlay when stereo.
    if stereo_output
        Colour: "{0.55, 0.55, 0.55}"
        Dashed line
        for g from 2 to grains_needed
            if cluster_history_R#[g-1] > 0 and cluster_history_R#[g] > 0
                t1 = evR_tout#[g-1]
                t2 = evR_tout#[g]
                Draw line: t1, cluster_history_R#[g-1], t2, cluster_history_R#[g]
            endif
        endfor
        Solid line
    endif

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Cluster"
    Text bottom: "no", "Time (s)"
    if stereo_output
        Text top: "no", "Cluster Trajectory | actual jittered onsets | solid L, dashed R"
    else
        Text top: "no", "Cluster Trajectory | actual jittered event onsets"
    endif

    # === Cluster population ===
    Select outer viewport: 0, 8, 4.46, 5.66
    Select inner viewport: 0.60, 7.70, 4.66, 5.44

    maxCount = 1
    for c from 1 to k
        if cluster_count#[c] > maxCount
            maxCount = cluster_count#[c]
        endif
    endfor

    Axes: 0, k + 1, 0, maxCount * 1.12
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, k + 1, 0, maxCount * 1.12

    for c from 1 to k
        if k > 1
            colorVal = (c - 1) / (k - 1)
        else
            colorVal = 0
        endif
        rVal$ = fixed$(0.25 + colorVal * 0.50, 3)
        gVal$ = fixed$(0.55 - colorVal * 0.25, 3)
        bVal$ = fixed$(0.75 - colorVal * 0.35, 3)
        Paint rectangle: "{" + rVal$ + ", " + gVal$ + ", " + bVal$ + "}", c - 0.38, c + 0.38, 0, cluster_count#[c]
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Analysis grains"
    Text bottom: "no", "Cluster"
    Text top: "no", "Cluster Population | " + string$(nActive) + " active of " + string$(k) + " requested"

    # === Summary strip ===
    Select outer viewport: 0, 8, 5.88, 6.90
    Select inner viewport: 0.60, 7.70, 5.96, 6.82
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    summary1$ = "##Analysis##  grain " + fixed$(grain_size_ms, 1) + " ms | overlap " + fixed$(100 * overlap_ratio, 0) + "\% | " + string$(nGrains) + " source grains | " + string$(nActive) + "/" + string$(k) + " active clusters"
    summary2$ = "##Morph##  " + morphModeName$ + " | transition rate " + fixed$(state_transition_rate_hz, 2) + " Hz | position randomness " + fixed$(position_randomness, 2) + " | density variation " + fixed$(density_variation, 2)
    summary3$ = "##Output##  " + string$(grains_needed) + " events | pitch scatter +/-" + fixed$(pitch_scatter_semitones, 2) + " st | " + stereoDesc$ + " | " + fixed$(outDurDisplay, 2) + " s | true OLA normalization"
    Text: 0.02, "left", 0.78, "half", summary1$
    Text: 0.02, "left", 0.50, "half", summary2$
    Text: 0.02, "left", 0.22, "half", summary3$

    Colour: "Black"
    Draw inner box

    # Restore complete page for Picture export / clipboard.
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
endif

# ============================================
# OUTPUT
# ============================================

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