# ============================================================
# Praat AudioTools - Neural_Markov_Soundscape_Weaver.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2025) - Fixed syntax
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Neural Markov Soundscape Weaver - Learns audio grammar via
#   k-means clustering and Markov chains for generative synthesis.
#
# Changelog v0.4:
#   - Fixed preset comparison (number not string)
#   - Fixed Formula object references
#   - Added preset name to output
#   - Added markov order name
#   - Added visualization
# ============================================================

# === Input Validation ===
nSelected = numberOfSelected("Sound")
if nSelected <> 1
    exitScript: "Please select exactly one Sound object."
endif

snd = selected("Sound")
sndName$ = selected$("Sound")

form Neural Markov Soundscape Weaver v0.4
    comment === Preset ===
    optionmenu Preset: 1
        option Manual
        option Ambient Flow
        option Rhythmic Pulse
        option Dense Texture
        option Sparse Minimal
        option Evolving Landscape
        option Chaotic Transitions
    comment === Analysis ===
    positive Grain_size_ms 80
    positive Analysis_overlap 0.5
    integer Number_of_states 5
    comment === Markov Chain ===
    optionmenu Markov_order: 1
        option First Order
        option Second Order
    real Randomness 0.0
    comment === Synthesis ===
    positive Output_duration_sec 15.0
    positive Synthesis_overlap 0.5
    positive Crossfade_ms 10
    comment === Grain Variation ===
    real Pitch_scatter_semitones 0.0
    real Position_jitter 0.1
    real Density_variation 0.0
    comment === Output ===
    boolean Stereo_output 1
    real Stereo_decorrelation 0.3
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================
# PRESET LOGIC
# ============================================

if preset = 2
    # Ambient Flow
    grain_size_ms = 100
    analysis_overlap = 0.6
    number_of_states = 4
    markov_order = 1
    randomness = 0.1
    output_duration_sec = 20.0
    synthesis_overlap = 0.6
    crossfade_ms = 15
    pitch_scatter_semitones = 0.0
    position_jitter = 0.1
    density_variation = 0.05
    stereo_decorrelation = 0.4
    presetName$ = "AmbientFlow"
elsif preset = 3
    # Rhythmic Pulse
    grain_size_ms = 50
    analysis_overlap = 0.3
    number_of_states = 6
    markov_order = 1
    randomness = 0.05
    output_duration_sec = 12.0
    synthesis_overlap = 0.3
    crossfade_ms = 5
    pitch_scatter_semitones = 0.0
    position_jitter = 0.0
    density_variation = 0.0
    stereo_decorrelation = 0.2
    presetName$ = "RhythmicPulse"
elsif preset = 4
    # Dense Texture
    grain_size_ms = 40
    analysis_overlap = 0.7
    number_of_states = 8
    markov_order = 2
    randomness = 0.15
    output_duration_sec = 15.0
    synthesis_overlap = 0.7
    crossfade_ms = 8
    pitch_scatter_semitones = 0.3
    position_jitter = 0.2
    density_variation = 0.1
    stereo_decorrelation = 0.5
    presetName$ = "DenseTexture"
elsif preset = 5
    # Sparse Minimal
    grain_size_ms = 150
    analysis_overlap = 0.4
    number_of_states = 3
    markov_order = 1
    randomness = 0.2
    output_duration_sec = 25.0
    synthesis_overlap = 0.4
    crossfade_ms = 25
    pitch_scatter_semitones = 0.0
    position_jitter = 0.15
    density_variation = 0.1
    stereo_decorrelation = 0.3
    presetName$ = "SparseMinimal"
elsif preset = 6
    # Evolving Landscape
    grain_size_ms = 120
    analysis_overlap = 0.5
    number_of_states = 5
    markov_order = 2
    randomness = 0.1
    output_duration_sec = 30.0
    synthesis_overlap = 0.6
    crossfade_ms = 20
    pitch_scatter_semitones = 0.2
    position_jitter = 0.1
    density_variation = 0.08
    stereo_decorrelation = 0.6
    presetName$ = "EvolvingLandscape"
elsif preset = 7
    # Chaotic Transitions
    grain_size_ms = 60
    analysis_overlap = 0.5
    number_of_states = 10
    markov_order = 1
    randomness = 0.5
    output_duration_sec = 12.0
    synthesis_overlap = 0.5
    crossfade_ms = 10
    pitch_scatter_semitones = 0.8
    position_jitter = 0.3
    density_variation = 0.15
    stereo_decorrelation = 0.7
    presetName$ = "ChaoticTransitions"
else
    presetName$ = "Manual"
endif

# Get markov order name
if markov_order = 1
    markovOrderName$ = "First-Order"
else
    markovOrderName$ = "Second-Order"
endif

# ============================================
# SETUP
# ============================================

selectObject: snd
dur = Get total duration
fs = Get sampling frequency

clearinfo
writeInfoLine: "=== Neural Markov Soundscape Weaver v0.4 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Grain: ", grain_size_ms, " ms | States: ", number_of_states
appendInfoLine: "Markov: ", markovOrderName$
appendInfoLine: "Randomness: ", fixed$(randomness * 100, 0), "%"
if stereo_output
    appendInfoLine: "Output: Stereo (decorrelation ", fixed$(stereo_decorrelation * 100, 0), "%)"
else
    appendInfoLine: "Output: Mono"
endif
appendInfoLine: ""

selectObject: snd
workSnd = Convert to mono
Rename: "Analysis_Work"

grainSec = grain_size_ms / 1000
stepSec = grainSec * (1 - analysis_overlap)
crossfadeSec = crossfade_ms / 1000

if dur < grainSec * 4
    removeObject: workSnd
    exitScript: "Sound too short for analysis."
endif

k = number_of_states

# ============================================
# FEATURE EXTRACTION
# ============================================

appendInfoLine: "Analyzing audio structure..."

nGrains = floor((dur - grainSec) / stepSec)
if nGrains < k * 2
    removeObject: workSnd
    exitScript: "Not enough grains for ", k, " states."
endif

feat_centroid# = zero#(nGrains)
feat_bandwidth# = zero#(nGrains)
feat_pitch# = zero#(nGrains)
feat_hnr# = zero#(nGrains)
grain_time# = zero#(nGrains)

selectObject: workSnd
spec = To Spectrogram: grainSec, 8000, stepSec, 20, "Gaussian"

selectObject: workSnd
pit = To Pitch: stepSec, 75, 600

selectObject: workSnd
hnr_obj = To Harmonicity (cc): stepSec, 75, 0.1, 1.0

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
endfor

removeObject: spec, pit, hnr_obj

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

# ============================================
# K-MEANS CLUSTERING
# ============================================

appendInfoLine: "Learning states..."

cent_1# = zero#(k)
cent_2# = zero#(k)
cent_3# = zero#(k)
cent_4# = zero#(k)

for c from 1 to k
    r = randomInteger(1, nGrains)
    cent_1#[c] = norm_centroid#[r]
    cent_2#[c] = norm_bandwidth#[r]
    cent_3#[c] = norm_pitch#[r]
    cent_4#[c] = norm_hnr#[r]
endfor

state_seq# = zero#(nGrains)

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
                ... (norm_hnr#[i] - cent_4#[c])^2
            
            if distSq < minDist
                minDist = distSq
                bestK = c
            endif
        endfor
        
        if state_seq#[i] <> bestK
            state_seq#[i] = bestK
            changes += 1
        endif
    endfor
    
    for c from 1 to k
        sum_1 = 0
        sum_2 = 0
        sum_3 = 0
        sum_4 = 0
        count = 0
        
        for i from 1 to nGrains
            if state_seq#[i] = c
                sum_1 += norm_centroid#[i]
                sum_2 += norm_bandwidth#[i]
                sum_3 += norm_pitch#[i]
                sum_4 += norm_hnr#[i]
                count += 1
            endif
        endfor
        
        if count > 0
            cent_1#[c] = sum_1 / count
            cent_2#[c] = sum_2 / count
            cent_3#[c] = sum_3 / count
            cent_4#[c] = sum_4 / count
        endif
    endfor
    
    if changes = 0
        appendInfoLine: "  Converged at iteration ", iter
        iter = max_iter + 1
    endif
endfor

# ============================================
# BUILD STATE INDEX
# ============================================

appendInfoLine: "  Building state index..."

state_count# = zero#(k)
for i from 1 to nGrains
    s = state_seq#[i]
    state_count#[s] += 1
endfor

state_offset# = zero#(k + 1)
state_offset#[1] = 0
for s from 2 to k + 1
    state_offset#[s] = state_offset#[s-1] + state_count#[s-1]
endfor

state_index# = zero#(nGrains)
state_fill# = zero#(k)

for i from 1 to nGrains
    s = state_seq#[i]
    pos = state_offset#[s] + state_fill#[s] + 1
    state_index#[pos] = i
    state_fill#[s] += 1
endfor

# ============================================
# BUILD MARKOV TRANSITION MATRIX
# ============================================

appendInfoLine: "Learning grammar..."

if markov_order = 1
    trans# = zero#(k * k)
    
    for i from 1 to nGrains - 1
        curr = state_seq#[i]
        next = state_seq#[i + 1]
        idx = (curr - 1) * k + next
        trans#[idx] += 1
    endfor
    
    for r from 1 to k
        row_sum = 0
        for c from 1 to k
            idx = (r - 1) * k + c
            row_sum += trans#[idx]
        endfor
        
        if row_sum > 0
            for c from 1 to k
                idx = (r - 1) * k + c
                trans#[idx] /= row_sum
            endfor
        else
            for c from 1 to k
                idx = (r - 1) * k + c
                trans#[idx] = 1 / k
            endfor
        endif
    endfor
    
    appendInfoLine: "  First-order matrix built"
else
    n_pairs = k * k
    trans2# = zero#(n_pairs * k)
    
    for i from 1 to nGrains - 2
        prev = state_seq#[i]
        curr = state_seq#[i + 1]
        next = state_seq#[i + 2]
        pair_idx = (prev - 1) * k + curr
        idx = (pair_idx - 1) * k + next
        trans2#[idx] += 1
    endfor
    
    for pair from 1 to n_pairs
        row_sum = 0
        for c from 1 to k
            idx = (pair - 1) * k + c
            row_sum += trans2#[idx]
        endfor
        
        if row_sum > 0
            for c from 1 to k
                idx = (pair - 1) * k + c
                trans2#[idx] /= row_sum
            endfor
        else
            for c from 1 to k
                idx = (pair - 1) * k + c
                trans2#[idx] = 1 / k
            endfor
        endif
    endfor
    
    appendInfoLine: "  Second-order matrix built"
endif

# ============================================
# GENERATIVE SYNTHESIS
# ============================================

appendInfoLine: ""
appendInfoLine: "Weaving soundscape..."

synth_step = grainSec * (1 - synthesis_overlap)
grains_needed = ceiling(output_duration_sec / synth_step)
output_dur = output_duration_sec + grainSec

if stereo_output
    n_passes = 2
else
    n_passes = 1
endif

# Track state history for visualization
state_history# = zero#(grains_needed)

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
    
    current_state = randomInteger(1, k)
    prev_state = randomInteger(1, k)
    
    if pass = 2 and stereo_decorrelation > 0
        current_state = ((current_state + floor(k * stereo_decorrelation)) mod k) + 1
    endif
    
    for g from 1 to grains_needed
        t_out = (g - 1) * synth_step
        
        if density_variation > 0
            t_out = t_out + randomUniform(-1, 1) * density_variation * synth_step
            if t_out < 0
                t_out = 0
            endif
        endif
        
        # Store state for visualization (first pass only)
        if pass = 1
            state_history#[g] = current_state
        endif
        
        if state_count#[current_state] > 0
            r_idx = randomInteger(1, state_count#[current_state])
            idx_pos = state_offset#[current_state] + r_idx
            grain_idx = state_index#[idx_pos]
        else
            grain_idx = randomInteger(1, nGrains)
        endif
        
        t_grain = grain_time#[grain_idx]
        if position_jitter > 0
            t_grain = t_grain + randomUniform(-1, 1) * position_jitter * grainSec
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
        
        if crossfadeSec > 0
            selectObject: grain
            grain_dur = Get total duration
            fade = min(crossfadeSec, grain_dur * 0.4)
            fadeStr$ = string$(fade)
            durMinusFade$ = string$(grain_dur - fade)
            durStr$ = string$(grain_dur)
            Formula: "self * (if x < " + fadeStr$ + " then x/" + fadeStr$ +
                ... " else if x > " + durMinusFade$ + " then (" + durStr$ + "-x)/" + fadeStr$ +
                ... " else 1 fi fi)"
        endif
        
        selectObject: grain
        grain_dur = Get total duration
        grainIdStr$ = string$(grain)
        tOutStr$ = string$(t_out)
        
        selectObject: output_buf
        Formula (part): t_out, t_out + grain_dur, 1, 1,
            ... "self + Object_" + grainIdStr$ + "(x - " + tOutStr$ + ")"
        
        removeObject: grain
        
        # Markov transition
        if randomUniform(0, 1) < randomness
            next_state = randomInteger(1, k)
        else
            roll = randomUniform(0, 1)
            cumSum = 0
            next_state = 1
            
            if markov_order = 1
                for c from 1 to k
                    idx = (current_state - 1) * k + c
                    cumSum += trans#[idx]
                    if roll <= cumSum
                        next_state = c
                        c = k + 1
                    endif
                endfor
            else
                pair_idx = (prev_state - 1) * k + current_state
                for c from 1 to k
                    idx = (pair_idx - 1) * k + c
                    cumSum += trans2#[idx]
                    if roll <= cumSum
                        next_state = c
                        c = k + 1
                    endif
                endfor
            endif
        endif
        
        if pass = 2 and stereo_decorrelation > 0
            if randomUniform(0, 1) < stereo_decorrelation * 0.3
                next_state = randomInteger(1, k)
            endif
        endif
        
        prev_state = current_state
        current_state = next_state
    endfor
    
    selectObject: output_buf
    if synthesis_overlap > 0.3
        gain_comp = 1 / (1 + synthesis_overlap * 0.7)
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
    Rename: sndName$ + "_MarkovWeave_" + presetName$
    
    removeObject: channel_left, channel_right
else
    finalOut = channel_left
    Rename: sndName$ + "_MarkovWeave_" + presetName$
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
    Text: 0.5, "centre", 0.5, "half", "Neural Markov Soundscape Weaver: " + sndName$ + " [" + presetName$ + "]"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.6, 0.7, 1.4
    selectObject: snd
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Output waveform
    Select outer viewport: 0, 8, 1.6, 2.5
    Select inner viewport: 0.6, 7.6, 1.7, 2.4
    selectObject: finalOut
    Colour: "{0.3, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    
    # State trajectory
    Select outer viewport: 0, 8, 2.7, 3.9
    Select inner viewport: 0.6, 7.6, 2.9, 3.8
    
    Axes: 0, output_duration_sec, 0, k + 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, output_duration_sec, 0, k + 1
    
    for g from 2 to grains_needed
        t1 = (g - 2) * synth_step
        t2 = (g - 1) * synth_step
        s1 = state_history#[g-1]
        s2 = state_history#[g]
        
        colorVal = s2 / k
        rVal$ = fixed$(0.3 + colorVal * 0.5, 2)
        gVal$ = fixed$(0.5 - colorVal * 0.2, 2)
        bVal$ = fixed$(0.7 - colorVal * 0.4, 2)
        Colour: "{" + rVal$ + ", " + gVal$ + ", " + bVal$ + "}"
        Draw line: t1, s1, t2, s2
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "State"
    Text bottom: "yes", "Time (s)"
    
    # Transition matrix heatmap (first-order only)
    if markov_order = 1
        Select outer viewport: 0, 4, 4.1, 5.8
        Select inner viewport: 0.6, 3.6, 4.3, 5.6
        
        Axes: 0, k, 0, k
        
        for r from 1 to k
            for c from 1 to k
                idx = (r - 1) * k + c
                prob = trans#[idx]
                intensity = prob
                rVal$ = fixed$(1 - intensity * 0.7, 2)
                gVal$ = fixed$(1 - intensity * 0.3, 2)
                bVal$ = fixed$(1 - intensity * 0.8, 2)
                Paint rectangle: "{" + rVal$ + ", " + gVal$ + ", " + bVal$ + "}", c - 1, c, k - r, k - r + 1
            endfor
        endfor
        
        Colour: "Black"
        Draw inner box
        Font size: 8
        Text left: "yes", "From"
        Text bottom: "yes", "To State"
    endif
    
    # State distribution
    Select outer viewport: 4, 8, 4.1, 5.8
    Select inner viewport: 4.4, 7.6, 4.3, 5.6
    
    maxCount = 1
    for s from 1 to k
        if state_count#[s] > maxCount
            maxCount = state_count#[s]
        endif
    endfor
    
    Axes: 0, k + 1, 0, maxCount * 1.1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, k + 1, 0, maxCount * 1.1
    
    for s from 1 to k
        colorVal = s / k
        rVal$ = fixed$(0.3 + colorVal * 0.5, 2)
        gVal$ = fixed$(0.5 - colorVal * 0.2, 2)
        bVal$ = fixed$(0.7 - colorVal * 0.4, 2)
        Paint rectangle: "{" + rVal$ + ", " + gVal$ + ", " + bVal$ + "}", s - 0.4, s + 0.4, 0, state_count#[s]
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Grains"
    Text bottom: "yes", "State"
    
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
