# ============================================================
# Praat AudioTools - Neural_Granular_Texture_Morpher.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2025) - Fixed syntax
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Neural Granular Texture Morpher - K-means clustering
#   with multiple morph modes for texture evolution.
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

form Neural Texture Morpher v0.4
    comment === Preset ===
    optionmenu Preset: 1
        option Manual
        option Slow Evolution
        option Rapid Texture
        option Random Walk
        option Rhythmic Cycle
        option Ambient Drift
        option Chaotic Morph
    comment === Analysis ===
    positive Grain_size_ms 60
    positive Overlap_ratio 0.5
    integer Number_of_clusters 4
    comment === Synthesis ===
    positive Output_duration_sec 10.0
    positive Morph_speed_hz 0.5
    optionmenu Morph_mode: 1
        option Cycle (linear)
        option Pendulum (back-forth)
        option Random Walk
        option Random Jump
        option Weighted Random
    comment === Grain Variation ===
    real Pitch_scatter_semitones 0.0
    real Position_randomness 0.2
    real Density_variation 0.1
    comment === Output ===
    boolean Stereo_output 1
    real Stereo_spread 0.5
    boolean Draw_visualization 1
    boolean Play_result 1
endform

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
    morphModeName$ = "WeightedRandom"
endif

# ============================================
# SETUP
# ============================================

selectObject: snd
dur = Get total duration
fs = Get sampling frequency

clearinfo
writeInfoLine: "=== Neural Granular Texture Morpher v0.4 ==="
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

nGrains = floor((dur - grainSec) / stepSec)
if nGrains < k
    removeObject: workSnd
    exitScript: "Not enough grains. Reduce grain size or clusters."
endif

feat_centroid# = zero#(nGrains)
feat_bandwidth# = zero#(nGrains)
feat_pitch# = zero#(nGrains)
feat_hnr# = zero#(nGrains)
feat_intensity# = zero#(nGrains)
grain_time# = zero#(nGrains)

selectObject: workSnd
spec = To Spectrogram: grainSec, 8000, stepSec, 20, "Gaussian"

selectObject: workSnd
pit = To Pitch: stepSec, 75, 600

selectObject: workSnd
hnr_obj = To Harmonicity (cc): stepSec, 75, 0.1, 1.0

selectObject: workSnd
inten = To Intensity: 75, stepSec, "yes"

for i from 1 to nGrains
    t = (i - 0.5) * stepSec
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

for c from 1 to k
    r = randomInteger(1, nGrains)
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

if valid_clusters < 2
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

# Track cluster usage for visualization
cluster_history# = zero#(grains_needed)

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
    
    if pass = 2
        current_cluster = randomInteger(1, k)
    else
        current_cluster = 1
    endif
    
    for g from 1 to grains_needed
        t_out = (g - 1) * stepSec
        
        if density_variation > 0
            t_out = t_out + randomUniform(-1, 1) * density_variation * stepSec
            if t_out < 0
                t_out = 0
            endif
        endif
        
        # Determine target cluster
        if morph_mode = 1
            cycle_pos = t_out * morph_speed_hz
            target_c = floor(cycle_pos mod k) + 1
        elsif morph_mode = 2
            cycle_pos = t_out * morph_speed_hz
            ping_pong = cycle_pos mod (2 * (k - 1))
            if ping_pong < k - 1
                target_c = floor(ping_pong) + 1
            else
                target_c = k - floor(ping_pong - (k - 1)) - 1
            endif
            target_c = max(1, min(k, target_c))
        elsif morph_mode = 3
            if randomUniform(0, 1) < morph_speed_hz * stepSec
                walk_momentum += randomUniform(-1, 1)
                walk_momentum = walk_momentum * 0.8
                current_cluster += round(walk_momentum)
                if current_cluster < 1
                    current_cluster = 1
                    walk_momentum = abs(walk_momentum)
                elsif current_cluster > k
                    current_cluster = k
                    walk_momentum = -abs(walk_momentum)
                endif
            endif
            target_c = current_cluster
        elsif morph_mode = 4
            if randomUniform(0, 1) < morph_speed_hz * stepSec
                target_c = randomInteger(1, k)
                current_cluster = target_c
            else
                target_c = current_cluster
            endif
        else
            if randomUniform(0, 1) < morph_speed_hz * stepSec * 0.5
                offset = randomInteger(-1, 1)
                target_c = current_cluster + offset
                target_c = max(1, min(k, target_c))
                current_cluster = target_c
            else
                target_c = current_cluster
            endif
        endif
        
        if target_c < 1
            target_c = 1
        elsif target_c > k
            target_c = k
        endif
        
        # Handle empty cluster
        if cluster_count#[target_c] = 0
            for offset from 1 to k
                if target_c + offset <= k and cluster_count#[target_c + offset] > 0
                    target_c = target_c + offset
                    offset = k + 1
                elsif target_c - offset >= 1 and cluster_count#[target_c - offset] > 0
                    target_c = target_c - offset
                    offset = k + 1
                endif
            endfor
        endif
        
        # Store for visualization (first pass only)
        if pass = 1
            cluster_history#[g] = target_c
        endif
        
        # Select grain
        n_in_cluster = cluster_count#[target_c]
        if n_in_cluster > 0
            r_idx = randomInteger(1, n_in_cluster)
            idx_pos = cluster_offset#[target_c] + r_idx
            grain_idx = cluster_index#[idx_pos]
        else
            grain_idx = 1
        endif
        
        t_grain = grain_time#[grain_idx]
        if position_randomness > 0
            t_grain = t_grain + randomUniform(-1, 1) * position_randomness * grainSec
            t_grain = max(grainSec/2, min(dur - grainSec/2, t_grain))
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
        
        selectObject: workSnd
        grain = Extract part: t_start, t_end, "Hanning", 1, "no"
        
        # Pitch scatter
        if pitch_scatter_semitones > 0
            selectObject: grain
            scatter = randomUniform(-pitch_scatter_semitones, pitch_scatter_semitones)
            ratio = 2 ^ (scatter / 12)
            orig_fs = Get sampling frequency
            new_fs = orig_fs * ratio
            if new_fs > 8000 and new_fs < 96000
                Resample: new_fs, 50
                Override sampling frequency: orig_fs
                grain_new = selected("Sound")
                removeObject: grain
                grain = grain_new
            endif
        endif
        
        # Add to output (overlap-add)
        selectObject: grain
        grain_dur = Get total duration
        grainIdStr$ = string$(grain)
        tOutStr$ = string$(t_out)
        
        selectObject: output_buf
        Formula (part): t_out, t_out + grain_dur, 1, 1,
            ... "self + Object_" + grainIdStr$ + "(x - " + tOutStr$ + ")"
        
        removeObject: grain
    endfor
    
    # OLA gain compensation
    selectObject: output_buf
    if overlap_ratio > 0.3
        gain_comp = 1 / (1 + overlap_ratio * 0.8)
        gainStr$ = string$(gain_comp)
        Formula: "self * " + gainStr$
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
Scale peak: 0.99

# ============================================
# CLEANUP
# ============================================

removeObject: workSnd

# ============================================
# VISUALIZATION
# ============================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Neural Granular Texture Morpher: " + sndName$ + " [" + presetName$ + "]"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.6
    Select inner viewport: 0.6, 7.6, 0.7, 1.5
    selectObject: snd
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Output waveform
    Select outer viewport: 0, 8, 1.7, 2.7
    Select inner viewport: 0.6, 7.6, 1.8, 2.6
    selectObject: finalOut
    Colour: "{0.2, 0.6, 0.4}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    
    # Cluster trajectory
    Select outer viewport: 0, 8, 2.9, 4.2
    Select inner viewport: 0.6, 7.6, 3.1, 4.1
    
    Axes: 0, output_duration_sec, 0, k + 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, output_duration_sec, 0, k + 1
    
    # Draw cluster history
    for g from 2 to grains_needed
        t1 = (g - 2) * stepSec
        t2 = (g - 1) * stepSec
        c1 = cluster_history#[g-1]
        c2 = cluster_history#[g]
        
        # Color by cluster
        colorVal = c2 / k
        rVal$ = fixed$(0.2 + colorVal * 0.6, 2)
        gVal$ = fixed$(0.5 - colorVal * 0.3, 2)
        bVal$ = fixed$(0.8 - colorVal * 0.5, 2)
        Colour: "{" + rVal$ + ", " + gVal$ + ", " + bVal$ + "}"
        Draw line: t1, c1, t2, c2
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Cluster"
    Text bottom: "yes", "Time (s)"
    
    # Cluster distribution
    Select outer viewport: 0, 4, 4.4, 5.6
    Select inner viewport: 0.6, 3.8, 4.6, 5.5
    
    maxCount = 1
    for c from 1 to k
        if cluster_count#[c] > maxCount
            maxCount = cluster_count#[c]
        endif
    endfor
    
    Axes: 0, k + 1, 0, maxCount * 1.1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, k + 1, 0, maxCount * 1.1
    
    for c from 1 to k
        colorVal = c / k
        rVal$ = fixed$(0.2 + colorVal * 0.6, 2)
        gVal$ = fixed$(0.5 - colorVal * 0.3, 2)
        bVal$ = fixed$(0.8 - colorVal * 0.5, 2)
        Paint rectangle: "{" + rVal$ + ", " + gVal$ + ", " + bVal$ + "}", c - 0.4, c + 0.4, 0, cluster_count#[c]
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Grains"
    Text bottom: "yes", "Cluster"
    
    # Stats
    Select outer viewport: 4, 8, 4.4, 5.6
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.5, "centre", 0.85, "half", "Mode: " + morphModeName$
    Text: 0.5, "centre", 0.65, "half", "Morph: " + fixed$(morph_speed_hz, 2) + " Hz"
    Text: 0.5, "centre", 0.45, "half", "Grains: " + string$(nGrains) + " | Clusters: " + string$(k)
    Text: 0.5, "centre", 0.25, "half", "Grain: " + string$(grain_size_ms) + " ms"
    
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