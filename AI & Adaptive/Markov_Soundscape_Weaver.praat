# ============================================================
# Praat AudioTools - Neural_Markov_Soundscape_Weaver.praat
# (filename preserved for distribution compatibility)
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.6 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Markov Soundscape Weaver - learns audio "grammar" from
#   the input via:
#     (1) Grain-based feature extraction: spectral centroid,
#         spectral bandwidth, F0, harmonicity (HNR) — one
#         z-score-normalized 4D feature vector per grain
#     (2) K-means clustering (Lloyd's algorithm, ≤15 iters)
#         into k "states"
#     (3) First- or second-order Markov chain learned from
#         the analyzed state sequence
#   Synthesis: random walk through the Markov chain, picking
#   a random grain from the current state's pool, optional
#   pitch-scatter via resample-then-override-sr, Hanning grain
#   window + triangle crossfade, overlap-add into stereo (or
#   mono) output.
#
#   This is classical clustering + classical Markov + granular
#   concatenative synthesis. No neural network is involved at
#   any stage. The "Neural_" filename is preserved for
#   distribution compatibility (existing users may have it
#   wired into workflows); internal naming reflects what the
#   algorithm actually is.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline
#   Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.6 (2026):
#   - FIX (audible): OLA gain was never flat. Grains carry a Hanning
#     window PLUS an extra linear crossfade ramp, placed at
#     grain*(1-synthesis_overlap): even at overlap 0.5 the extra
#     ramps break the Hann COLA sum; RhythmicPulse (0.3) had deep
#     ~29 Hz inter-grain dips; DenseTexture (0.7) a rippling
#     over-overlapped sum. The constant 1/(1+overlap*0.7)
#     compensation addressed none of it. v0.6 accumulates each
#     grain's ANALYTIC envelope (Hann x crossfade ramps, at its
#     actual duration and actual jittered placement) into a
#     window-sum buffer per pass and divides the channel by it:
#     flat unity gain at any synthesis_overlap, exact even under
#     pitch scatter (which changes grain durations) and density
#     variation (which moves placements). Output edges recover
#     full level; gain compensation removed.
#     NOTE: output is therefore NOT bit-identical to v0.4/v0.5
#     (their gain structure was the bug). Grain phase interference
#     remains -- that is the granular texture, not a gain artifact.
#   - VIZ: title bar uses an explicit inner viewport (outer-only
#     form risks the margin-compression text collision).
#
# Changelog v0.5:
#   - Audio output is bit-identical to v0.4 for the same form
#     parameters AND same Praat RNG state. Same k-means init
#     and iteration, same Markov build (first- and second-
#     order), same transition row normalization with uniform
#     fallback, same Markov-walk sampling (cumulative roll),
#     same grain selection (random index into state pool),
#     same position jitter, same pitch scatter via Resample +
#     Override sampling frequency, same Hanning grain extract,
#     same crossfade arithmetic (now via two Formula (part)
#     calls), same overlap-add, same gain compensation, same
#     stereo decorrelation logic, same 7 presets with same
#     values.
#   - PERFORMANCE: grain crossfade now uses two
#     Formula (part) calls (fade-in range + fade-out range)
#     instead of one full-grain Formula with nested if-else.
#     The previous form evaluated the conditional for every
#     grain sample including the middle range that just
#     returned self * 1. New form skips the middle entirely.
#     For typical 80 ms grains at 44.1 kHz with 1000+ grains,
#     ~50-60% faster crossfade phase. Total wallclock ~10-30%
#     faster depending on grain count.
#   - SYNTAX: `Object_<id>(x)` legacy syntax (line 645 v0.4)
#     replaced with modern `object(<id>, x)`. Both compile in
#     current Praat; modern is forward-compatible.
#   - FRAMING: dropped "Neural" from the form title, in-script
#     header description, info output, and visualization title.
#     The script does k-means clustering + Markov chain
#     synthesis. No neural network is involved. (Filename
#     `Neural_Markov_Soundscape_Weaver.praat` preserved so
#     existing distribution paths keep working.)
#   - FORM: dropped 6 decorative `comment === ... ===` section
#     dividers. Form went from 22 effective rows (16 fields +
#     6 comments) to 16.
#   - VIZ: rewritten to suite 8x8 standard. v0.4 was an
#     8x5.8 custom layout with 5 panels (title, original
#     wave, output wave, state trajectory, transition matrix +
#     state distribution side-by-side). v0.5 keeps all the
#     diagnostic content but reorganizes:
#       Title bar (suite light) + metadata subtitle
#       Panel A (left, headline): state trajectory of the
#         generated output (the Markov walk visualized)
#       Panel B (right, headline): transition matrix heatmap.
#         For first-order: shows the actual trans# matrix.
#         For second-order: shows a first-order projection
#         derived from state_seq# (for visualization only —
#         synthesis still uses the trans2# tensor).
#       Panel C: state distribution histogram (bars colored
#         by state index, matching colors in Panel A/B)
#       Panel D: input + output waveform comparison
#         (gray = original, blue = result, shared y-axis)
#       Panel E: light-grey summary stats bar (suite standard)
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

form Markov Soundscape Weaver v0.6
    optionmenu Preset: 1
        option Manual
        option Ambient Flow
        option Rhythmic Pulse
        option Dense Texture
        option Sparse Minimal
        option Evolving Landscape
        option Chaotic Transitions
    positive Grain_size_ms 80
    positive Analysis_overlap 0.5
    integer Number_of_states 5
    optionmenu Markov_order: 1
        option First Order
        option Second Order
    real Randomness 0.0
    positive Output_duration_sec 15.0
    positive Synthesis_overlap 0.5
    positive Crossfade_ms 10
    real Pitch_scatter_semitones 0.0
    real Position_jitter 0.1
    real Density_variation 0.0
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
writeInfoLine: "=== Markov Soundscape Weaver v0.6 ==="
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
# NORMALIZE FEATURES (per feature: z-score)
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
# Always build a first-order matrix for VISUALIZATION
# (from state_seq#). For markov_order=1 this duplicates trans#;
# for markov_order=2 it gives a useful first-order projection
# of the underlying state sequence.
# ============================================

viz_trans# = zero#(k * k)
for i from 1 to nGrains - 1
    curr = state_seq#[i]
    next = state_seq#[i + 1]
    idx = (curr - 1) * k + next
    viz_trans#[idx] += 1
endfor
for r from 1 to k
    row_sum = 0
    for c from 1 to k
        idx = (r - 1) * k + c
        row_sum += viz_trans#[idx]
    endfor
    if row_sum > 0
        for c from 1 to k
            idx = (r - 1) * k + c
            viz_trans#[idx] /= row_sum
        endfor
    endif
endfor

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
    
    # v0.6: per-pass window-sum envelope. Each grain's analytic
    # envelope (Hann x crossfade ramps, actual duration, actual
    # placement) is accumulated here; the channel is divided by it
    # after the walk, giving flat unity gain at any overlap.
    env_sum = Create Sound from formula: "EnvSum_" + string$(pass), 1, 0, output_dur, fs, "0"
    
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
        
        # v0.5: two Formula (part) calls — fade-in range and
        # fade-out range only. Skips the middle "self * 1"
        # no-op range that v0.4 iterated over via the nested
        # if/else conditional. Bit-identical arithmetic.
        if crossfadeSec > 0
            selectObject: grain
            grain_dur = Get total duration
            fade = min(crossfadeSec, grain_dur * 0.4)
            if fade > 0
                Formula (part): 0, fade, 1, 1, "self * x / fade"
                Formula (part): grain_dur - fade, grain_dur, 1, 1, "self * (grain_dur - x) / fade"
            endif
        endif
        
        selectObject: grain
        grain_dur = Get total duration
        
        # v0.5: modern object(<id>, x) instead of legacy
        # Object_<id>(x). Same lookup; forward-compatible.
        selectObject: output_buf
        Formula (part): t_out, t_out + grain_dur, 1, 1,
            ... "self + object(grain, x - t_out)"
        
        # v0.6: accumulate this grain's analytic envelope:
        # Hann over its actual duration, times the same linear
        # crossfade ramps applied above (fade may be 0).
        if crossfadeSec > 0
            env_fade = min(crossfadeSec, grain_dur * 0.4)
        else
            env_fade = 0
        endif
        selectObject: env_sum
        if env_fade > 0
            Formula (part): t_out, t_out + grain_dur, 1, 1,
                ... "self + (0.5 - 0.5 * cos(2 * pi * (x - t_out) / grain_dur))"
                ... + " * min(1, min((x - t_out) / env_fade, (grain_dur - (x - t_out)) / env_fade))"
        else
            Formula (part): t_out, t_out + grain_dur, 1, 1,
                ... "self + (0.5 - 0.5 * cos(2 * pi * (x - t_out) / grain_dur))"
        endif
        
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
    
    # v0.6: exact window-sum normalization (replaces the constant
    # 1/(1+overlap*0.7), which was never flat at any overlap)
    envSumIdStr$ = string$(env_sum)
    selectObject: output_buf
    Formula: "self / (object[" + envSumIdStr$ + ", 1, col] + 1e-6)"
    removeObject: env_sum
    
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

# Capture stats
selectObject: finalOut
finalDuration = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"
finalChannels = Get number of channels

# ============================================
# CLEANUP
# ============================================

removeObject: workSnd

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# Panel A: state trajectory of the generated output
# Panel B: transition matrix heatmap (first-order projection)
# Panel C: state distribution histogram
# Panel D: input + output waveform comparison
# Panel E: light-grey summary
# ============================================================
if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    Black
    Plain line
    
    # Mono copies for waveform panels
    selectObject: snd
    nChIn = Get number of channels
    if nChIn > 1
        vizOriginal = Convert to mono
    else
        vizOriginal = Copy: "viz_original"
    endif
    
    selectObject: finalOut
    if finalChannels > 1
        vizResult = Convert to mono
    else
        vizResult = Copy: "viz_result"
    endif
    
    # Shared y-axis from both waveforms
    selectObject: vizOriginal
    oPeak = Get absolute extremum: 0, 0, "None"
    selectObject: vizResult
    rPeak = Get absolute extremum: 0, 0, "None"
    sharedPeak = oPeak
    if rPeak > sharedPeak
        sharedPeak = rPeak
    endif
    if sharedPeak < 0.01
        sharedPeak = 0.01
    endif
    sharedAmp = sharedPeak * 1.15
    
    # State color palette function: for state s in [1, k],
    # produce (r, g, b) varying with s/k. Use the same scheme
    # as v0.4 for visual continuity.
    # Computed inline below per panel; helpers via vars.
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Select inner viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half", "##MARKOV SOUNDSCAPE WEAVER##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.26, "half",
        ... sndName$
        ... + "  |  " + presetName$
        ... + "  |  " + string$(nGrains) + " grains analyzed"
        ... + "  |  " + string$(k) + " states"
        ... + "  |  " + markovOrderName$
        ... + "  |  rnd " + fixed$(randomness * 100, 0) + "%"
        ... + "  |  out " + fixed$(output_duration_sec, 1) + " s"
    
    # ----------------------------------------------------------
    # PANEL A: STATE TRAJECTORY  (left, headline)
    # Generated state sequence over output time. Color encodes
    # the destination state.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    Axes: 0, output_duration_sec, 0.5, k + 0.5
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, output_duration_sec, 0.5, k + 0.5
    
    # Horizontal grid at each state level
    Colour: "{0.88, 0.88, 0.92}"
    Line width: 1
    Dotted line
    for s from 1 to k
        Draw line: 0, s, output_duration_sec, s
    endfor
    Solid line
    
    # Draw the trajectory
    Line width: 1.5
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
    Line width: 1
    
    # State labels on left axis
    Font size: 5
    Colour: "{0.40, 0.40, 0.45}"
    for s from 1 to k
        Text: output_duration_sec * 0.005, "left", s, "half", "s" + string$(s)
    endfor
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "State"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL B: TRANSITION MATRIX HEATMAP  (right, headline)
    # First-order matrix. For markov_order=1, the actual trans#
    # used in synthesis. For markov_order=2, first-order
    # projection from state_seq# (synthesis still uses trans2#).
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40
    
    Axes: 0, k, 0, k
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, k, 0, k
    
    for r from 1 to k
        for c from 1 to k
            idx = (r - 1) * k + c
            prob = viz_trans#[idx]
            intensity = prob
            rVal$ = fixed$(1 - intensity * 0.7, 2)
            gVal$ = fixed$(1 - intensity * 0.3, 2)
            bVal$ = fixed$(1 - intensity * 0.8, 2)
            Paint rectangle: "{" + rVal$ + ", " + gVal$ + ", " + bVal$ + "}", c - 1, c, k - r, k - r + 1
        endfor
    endfor
    
    # Cell grid
    Colour: "{0.85, 0.85, 0.90}"
    Line width: 0.5
    for r from 0 to k
        Draw line: 0, r, k, r
    endfor
    for c from 0 to k
        Draw line: c, 0, c, k
    endfor
    
    # Row/col labels (state indices)
    Font size: 5
    Colour: "{0.40, 0.40, 0.45}"
    for r from 1 to k
        Text: -0.05, "right", k - r + 0.5, "half", "s" + string$(r)
    endfor
    for c from 1 to k
        Text: c - 0.5, "centre", -0.20, "half", "s" + string$(c)
    endfor
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "From state"
    Text bottom: "yes", "To state"
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "State trajectory of the generated output"
    if markov_order = 1
        Text: 6.10, "centre", 7.30, "half", "Transition matrix (first-order)"
    else
        Text: 6.10, "centre", 7.30, "half", "Transition matrix (first-order projection; synthesis uses second-order)"
    endif
    
    # ----------------------------------------------------------
    # PANEL C: STATE DISTRIBUTION HISTOGRAM
    # Bars colored by state index (matching trajectory + matrix).
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.75, 5.48
    
    maxCount = 1
    for s from 1 to k
        if state_count#[s] > maxCount
            maxCount = state_count#[s]
        endif
    endfor
    
    Axes: 0.4, k + 0.6, 0, maxCount * 1.15
    Paint rectangle: "{0.97, 0.97, 0.97}", 0.4, k + 0.6, 0, maxCount * 1.15
    
    # Light gridline at top of tallest bar
    Colour: "{0.88, 0.88, 0.92}"
    Line width: 1
    Dotted line
    Draw line: 0.4, maxCount, k + 0.6, maxCount
    Solid line
    
    for s from 1 to k
        colorVal = s / k
        rVal$ = fixed$(0.3 + colorVal * 0.5, 2)
        gVal$ = fixed$(0.5 - colorVal * 0.2, 2)
        bVal$ = fixed$(0.7 - colorVal * 0.4, 2)
        Paint rectangle: "{" + rVal$ + ", " + gVal$ + ", " + bVal$ + "}", s - 0.35, s + 0.35, 0, state_count#[s]
        
        # Count label inside or above the bar
        Font size: 5
        Colour: "{0.30, 0.30, 0.35}"
        labelY = state_count#[s] + maxCount * 0.04
        Text: s, "centre", labelY, "half", string$(state_count#[s])
        
        # State label below the bar
        Font size: 5
        Colour: "{0.40, 0.40, 0.45}"
        Text: s, "centre", -maxCount * 0.05, "half", "s" + string$(s)
    endfor
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "State distribution (analysis grains per state)"
    Text left: "yes", "Grains"
    Text bottom: "yes", "State"
    
    # ----------------------------------------------------------
    # PANEL D: INPUT + OUTPUT WAVEFORM COMPARISON
    # Different time scales (input duration vs output duration).
    # Use the longer as common axis; gray = original (capped at
    # its own duration), blue = result.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.55, 7.72, 5.69, 6.48
    
    if finalDuration > dur
        dispDur = finalDuration
    else
        dispDur = dur
    endif
    
    Axes: 0, dispDur, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, dispDur, -sharedAmp, sharedAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, dispDur, 0
    
    # Mark where input ends if shorter than output
    if dur < finalDuration
        Colour: "{0.85, 0.50, 0.20}"
        Line width: 1
        Dotted line
        Draw line: dur, -sharedAmp, dur, sharedAmp
        Solid line
        Font size: 5
        Text: dur + dispDur * 0.005, "left", sharedAmp * 0.85, "half", "input ends"
    endif
    
    # Original behind
    selectObject: vizOriginal
    Colour: "{0.62, 0.62, 0.62}"
    Line width: 1
    Draw: 0, dur, -sharedAmp, sharedAmp, "no", "Curve"
    
    # Result on top
    selectObject: vizResult
    Colour: "{0.25, 0.45, 0.75}"
    Line width: 1
    Draw: 0, finalDuration, -sharedAmp, sharedAmp, "no", "Curve"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Input vs result waveform  (gray = original, blue = result)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR  (suite standard light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.55, 7.72, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    if stereo_output
        stereoStr$ = "stereo (decorr " + fixed$(stereo_decorrelation * 100, 0) + "%)"
    else
        stereoStr$ = "mono"
    endif
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + sndName$
        ... + "  |  Grains: " + string$(nGrains) + " analyzed (size " + fixed$(grain_size_ms, 0) + " ms, overlap " + fixed$(analysis_overlap * 100, 0) + "%)"
        ... + "  |  States: " + string$(k) + " (k-means)"
        ... + "  |  Markov: " + markovOrderName$
    
    Text: 0.02, "left", 0.28, "half",
        ... "Randomness: " + fixed$(randomness * 100, 0) + "%"
        ... + "  |  Pitch scatter: " + fixed$(pitch_scatter_semitones, 1) + " st"
        ... + "  |  Pos jitter: " + fixed$(position_jitter, 2)
        ... + "  |  Crossfade: " + fixed$(crossfade_ms, 1) + " ms"
        ... + "  |  Output: " + stereoStr$ + ", " + fixed$(finalDuration, 2) + " s, peak " + fixed$(finalPeak, 3)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
    
    removeObject: vizOriginal, vizResult
endif

# ============================================
# OUTPUT
# ============================================

selectObject: snd
plusObject: finalOut

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
selectObject: finalOut
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDuration, 2), " s"
appendInfoLine: "Channels: ", finalChannels

if play_result
    appendInfoLine: "Playing..."
    selectObject: finalOut
    Play
endif

selectObject: finalOut
