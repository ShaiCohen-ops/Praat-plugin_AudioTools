# ============================================================
# Praat AudioTools - HMM_Timbre_Sequencing.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.3 (2026) - True Viterbi + repaired features
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   True Hidden Markov Model (HMM) for timbre-based sequence generation.
#   
#   HMM Components:
#   - Hidden States: Discovered timbre classes (via k-means initialization)
#   - Observations: 4D feature vectors (intensity, pitch, centroid, slope)
#   - Emission Model: Gaussian distributions per state
#   - Transition Model: Learned state-to-state probabilities
#   - Decoding: Viterbi algorithm to find most likely state path
#   - Generation: Sample states → sample observations → synthesize
#
#   BUGFIX v1.3:
#   - FIXED (critical): intensity and pitch features were dead.
#     They were computed on EXTRACTED frames (domain starts at 0)
#     but queried over the ORIGINAL time range -- out of domain,
#     undefined, constant fallback for every frame after the first.
#     Additionally the per-frame To Intensity minimum at a 75 Hz
#     floor is 85.3 ms, above the 80 ms default frame, so intensity
#     never ran at default settings ("must be >= 64 ms" enforced
#     the wrong threshold). Both are now computed ONCE globally
#     and queried per frame in real time coordinates -- correct,
#     and far faster than per-frame To Pitch.
#   - ADDED: the advertised Viterbi decoder now exists. Log-space
#     Viterbi over the learned Gaussian emissions + transitions,
#     followed by one hard-EM re-estimation (emissions and
#     transitions recomputed from the decoded path). Panel 2's
#     "Viterbi Path" label is now true.
#   - FIXED (critical): output duration was ~2x target. The frame
#     count came from the HOP, but frames concatenate at
#     (frame_size - crossfade) spacing; and the trim was nested
#     inside the wrong branch, so overshoot was never trimmed.
#   - FIXED: the loop-to-target branch crashed whenever it ran
#     (base_sound aliased an object the loop removed). It never
#     ran only because the duration bug always overshot.
#   - PERF: synthesis is one multi-object Concatenate-with-overlap
#     instead of O(n^2) incremental concatenation; stereo no
#     longer builds and discards a full mono sequence first.
#   - FIXED: info header erased itself (repeated writeInfoLine).
#   - ADDED: k-means early exit on convergence; num_frames >= K
#     validation; crossfade clamped below half the frame size.
#
#   BUGFIX v1.2:
#   - Fixed vector indexing (Praat is 1-indexed, no index 0)
#   - Removed 'break' statement (not supported)
#   - Fixed 2D array handling with 1D indexing
#   - Added minimum frame size validation (64ms)
#   - Added target duration with looping
#   - ADDED: Complete 6-panel visualization
# ============================================================

####################################################################
# INPUT VALIDATION
####################################################################

numberOfSelectedSounds = numberOfSelected("Sound")
if numberOfSelectedSounds <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound_original = selected("Sound")
sound_name$ = selected$("Sound")

####################################################################
# FORM
####################################################################

form HMM Timbre Sequencer v1.3 (True HMM)
    comment === Preset Selection ===
    optionmenu Preset 1
        option Custom
        option Fine Grain (subtle, 12 states)
        option Coarse Grain (bold, 5 states)
        option Textural (dense, 16 states)
        option Rhythmic (pulse, 8 states)
        option Experimental (glitchy, 24 states)
    comment === Feature Extraction ===
    positive Frame_size_ms 80
    positive Frame_hop_ms 40
    comment (Intensity/pitch are analyzed globally; any frame size >= 10 ms)
    comment === HMM Parameters ===
    positive Number_of_states_K 8
    positive Max_kmeans_iterations 50
    comment === Sequence Generation ===
    real Target_duration_s 8.0
    comment (Script will loop sequence to fill target duration)
    boolean Match_input_duration 0
    positive Output_length_frames 200
    comment (Set Target duration to 0 to use the two options above)
    comment === Output ===
    positive Crossfade_ms 5
    boolean Stereo_output 1
    boolean Draw_visualization 1
    boolean Show_info 1
    boolean Play_result 1
endform

####################################################################
# APPLY PRESETS
####################################################################

if preset = 2
    # Fine Grain
    frame_size_ms = 80
    frame_hop_ms = 40
    number_of_states_K = 12
    output_length_frames = 400
    crossfade_ms = 3
    presetName$ = "FineGrain"
elsif preset = 3
    # Coarse Grain
    frame_size_ms = 100
    frame_hop_ms = 50
    number_of_states_K = 5
    output_length_frames = 80
    crossfade_ms = 10
    presetName$ = "CoarseGrain"
elsif preset = 4
    # Textural
    frame_size_ms = 80
    frame_hop_ms = 40
    number_of_states_K = 16
    output_length_frames = 600
    crossfade_ms = 4
    presetName$ = "Textural"
elsif preset = 5
    # Rhythmic
    frame_size_ms = 100
    frame_hop_ms = 50
    number_of_states_K = 8
    output_length_frames = 200
    crossfade_ms = 8
    presetName$ = "Rhythmic"
elsif preset = 6
    # Experimental
    frame_size_ms = 64
    frame_hop_ms = 32
    number_of_states_K = 24
    output_length_frames = 1000
    crossfade_ms = 2
    presetName$ = "Experimental"
else
    presetName$ = "Custom"
endif

####################################################################
# PARAMETER VALIDATION
####################################################################

if frame_size_ms < 10
    exitScript: "Frame size must be >= 10 ms."
endif

# Convert to seconds
frame_size_s = frame_size_ms / 1000
frame_hop_s = frame_hop_ms / 1000
crossfade_s = crossfade_ms / 1000

# v1.3: the crossfade must fit inside a frame twice (fade-in +
# fade-out + Concatenate overlap)
if crossfade_s > frame_size_s * 0.4
    crossfade_s = frame_size_s * 0.4
endif

k = number_of_states_K

# Determine if using target duration
use_target_duration = (target_duration_s > 0)

clearinfo
writeInfoLine: "╔════════════════════════════════════════════════════╗"
appendInfoLine: "║   HMM TIMBRE SEQUENCER v1.3 (True HMM + Viz)      ║"
appendInfoLine: "╚════════════════════════════════════════════════════╝"
appendInfoLine: ""
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "States (K): ", k
appendInfoLine: "Frame: ", frame_size_ms, " ms (hop: ", frame_hop_ms, " ms)"
appendInfoLine: ""

####################################################################
# PREPARE AUDIO
####################################################################

selectObject: sound_original
sound_mono = Convert to mono
Rename: sound_name$ + "_mono"

selectObject: sound_mono
duration_s = Get total duration
sampleRate = Get sampling frequency

appendInfoLine: "Audio: ", fixed$(duration_s, 2), " s @ ", sampleRate, " Hz"

####################################################################
# EXTRACT FEATURES
####################################################################

appendInfoLine: ""
appendInfoLine: "Extracting features..."

# Calculate number of frames
num_frames = floor((duration_s - frame_size_s) / frame_hop_s) + 1
appendInfoLine: "  Frames: ", num_frames

# v1.3: validation
if duration_s < 0.1
    removeObject: sound_mono
    exitScript: "Input too short: need at least 0.1 s of audio."
endif
if num_frames < 4
    removeObject: sound_mono
    exitScript: "Input too short for this frame size/hop: only "
        ... + string$(num_frames) + " frames."
endif
if num_frames < k
    removeObject: sound_mono
    exitScript: "Fewer frames (" + string$(num_frames) + ") than states (K="
        ... + string$(k) + "). Use a shorter frame/hop or fewer states."
endif

# Declare feature vectors
frame_start# = zero# (num_frames)
raw_int# = zero# (num_frames)
raw_pitch# = zero# (num_frames)
raw_cent# = zero# (num_frames)
raw_slope# = zero# (num_frames)

for i to num_frames
    frame_start#[i] = (i - 1) * frame_hop_s
endfor

# v1.3: intensity and pitch are computed ONCE on the whole file and
# queried per frame in real time coordinates. v1.2 computed them on
# extracted frames (whose domain starts at 0) and then queried the
# ORIGINAL time range -- out of domain, undefined, constant fallback:
# both features were dead for every frame after the first. The
# per-frame To Intensity also needed >= 85.3 ms at a 75 Hz floor,
# above the 80 ms default frame, so intensity never even ran.
selectObject: sound_mono
globalIntensity = To Intensity: 75, 0, "yes"
selectObject: sound_mono
globalPitch = To Pitch (ac): 0, 75, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14, 600

for i to num_frames
    t_start = frame_start#[i]
    t_end = t_start + frame_size_s
    
    if t_end > duration_s
        t_end = duration_s
    endif
    
    # Intensity (global object, real time range)
    selectObject: globalIntensity
    val = Get mean: t_start, t_end, "energy"
    if val = undefined
        val = 50
    endif
    raw_int#[i] = val
    
    # Pitch (global object, real time range)
    selectObject: globalPitch
    val = Get mean: t_start, t_end, "Hertz"
    if val = undefined
        val = 0
    endif
    raw_pitch#[i] = val
    
    # Spectrum for centroid and slope (per frame)
    selectObject: sound_mono
    frame_sound = Extract part: t_start, t_end, "rectangular", 1.0, "no"
    To Spectrum: "yes"
    spectrum_obj = selected("Spectrum")
    
    # Spectral centroid
    raw_cent#[i] = Get centre of gravity: 2
    if raw_cent#[i] = undefined
        raw_cent#[i] = 1000
    endif
    
    # Spectral slope (approximation via band energy ratio)
    low_energy = Get band energy: 0, 1000
    high_energy = Get band energy: 1000, 5000
    if low_energy > 0
        raw_slope#[i] = high_energy / low_energy
    else
        raw_slope#[i] = 1
    endif
    
    removeObject: spectrum_obj, frame_sound
endfor

removeObject: globalIntensity, globalPitch

appendInfoLine: "  Features extracted"

appendInfoLine: "  Features extracted"

####################################################################
# NORMALIZE FEATURES
####################################################################

appendInfoLine: "Normalizing features..."

# Find min/max
min_int = raw_int#[1]
max_int = raw_int#[1]
min_pitch = raw_pitch#[1]
max_pitch = raw_pitch#[1]
min_cent = raw_cent#[1]
max_cent = raw_cent#[1]
min_slope = raw_slope#[1]
max_slope = raw_slope#[1]

for i from 2 to num_frames
    if raw_int#[i] < min_int
        min_int = raw_int#[i]
    endif
    if raw_int#[i] > max_int
        max_int = raw_int#[i]
    endif
    
    if raw_pitch#[i] < min_pitch
        min_pitch = raw_pitch#[i]
    endif
    if raw_pitch#[i] > max_pitch
        max_pitch = raw_pitch#[i]
    endif
    
    if raw_cent#[i] < min_cent
        min_cent = raw_cent#[i]
    endif
    if raw_cent#[i] > max_cent
        max_cent = raw_cent#[i]
    endif
    
    if raw_slope#[i] < min_slope
        min_slope = raw_slope#[i]
    endif
    if raw_slope#[i] > max_slope
        max_slope = raw_slope#[i]
    endif
endfor

# Normalize to [0, 1]
norm_int# = zero# (num_frames)
norm_pitch# = zero# (num_frames)
norm_cent# = zero# (num_frames)
norm_slope# = zero# (num_frames)

range_int = max_int - min_int
range_pitch = max_pitch - min_pitch
range_cent = max_cent - min_cent
range_slope = max_slope - min_slope

if range_int < 0.001
    range_int = 1
endif
if range_pitch < 0.001
    range_pitch = 1
endif
if range_cent < 0.001
    range_cent = 1
endif
if range_slope < 0.001
    range_slope = 1
endif

for i to num_frames
    norm_int#[i] = (raw_int#[i] - min_int) / range_int
    norm_pitch#[i] = (raw_pitch#[i] - min_pitch) / range_pitch
    norm_cent#[i] = (raw_cent#[i] - min_cent) / range_cent
    norm_slope#[i] = (raw_slope#[i] - min_slope) / range_slope
endfor

####################################################################
# K-MEANS CLUSTERING (INITIALIZE STATES)
####################################################################

appendInfoLine: ""
appendInfoLine: "Running k-means clustering (K=", k, ")..."

# Initialize centroids
centroid_int# = zero# (k)
centroid_pitch# = zero# (k)
centroid_cent# = zero# (k)
centroid_slope# = zero# (k)

for s to k
    random_idx = randomInteger(1, num_frames)
    centroid_int#[s] = norm_int#[random_idx]
    centroid_pitch#[s] = norm_pitch#[random_idx]
    centroid_cent#[s] = norm_cent#[random_idx]
    centroid_slope#[s] = norm_slope#[random_idx]
endfor

# State assignments
state# = zero# (num_frames)

# K-means iterations (v1.3: early exit when assignments stop changing)
kmeansConverged = 0
iterationsUsed = 0
for iter to max_kmeans_iterations
    if kmeansConverged = 0
        nChanged = 0
        # Assignment step
        for i to num_frames
            min_dist = 999999
            best_state = 1
            
            for s to k
                dist = (norm_int#[i] - centroid_int#[s])^2 +
                ... (norm_pitch#[i] - centroid_pitch#[s])^2 +
                ... (norm_cent#[i] - centroid_cent#[s])^2 +
                ... (norm_slope#[i] - centroid_slope#[s])^2
                
                if dist < min_dist
                    min_dist = dist
                    best_state = s
                endif
            endfor
            
            if state#[i] <> best_state
                nChanged += 1
            endif
            state#[i] = best_state
        endfor
        
        # Update step
        for s to k
            sum_int = 0
            sum_pitch = 0
            sum_cent = 0
            sum_slope = 0
            count = 0
            
            for i to num_frames
                if state#[i] = s
                    sum_int = sum_int + norm_int#[i]
                    sum_pitch = sum_pitch + norm_pitch#[i]
                    sum_cent = sum_cent + norm_cent#[i]
                    sum_slope = sum_slope + norm_slope#[i]
                    count = count + 1
                endif
            endfor
            
            if count > 0
                centroid_int#[s] = sum_int / count
                centroid_pitch#[s] = sum_pitch / count
                centroid_cent#[s] = sum_cent / count
                centroid_slope#[s] = sum_slope / count
            endif
        endfor
        
        iterationsUsed = iter
        if nChanged = 0
            kmeansConverged = 1
        endif
    endif
endfor

appendInfoLine: "K-means completed (", iterationsUsed, " iterations)"

####################################################################
# COMPUTE EMISSION PROBABILITIES (GAUSSIAN)
####################################################################

appendInfoLine: "Computing emission distributions..."

# Declare emission vectors (filled by estimateEmissions; the
# procedure preserves previous means for states that lose all
# members, so declare-once here)
emit_mean_int# = zero# (k)
emit_mean_pitch# = zero# (k)
emit_mean_cent# = zero# (k)
emit_mean_slope# = zero# (k)
emit_std_int# = zero# (k)
emit_std_pitch# = zero# (k)
emit_std_cent# = zero# (k)
emit_std_slope# = zero# (k)
state_count# = zero# (k)

@estimateEmissions

####################################################################
# COMPUTE TRANSITION PROBABILITIES
####################################################################

appendInfoLine: "Learning transition probabilities..."

# Simulate 2D arrays with 1D indexing: index = (s1-1)*k + s2
max_trans_size = k * k
trans_count# = zero# (max_trans_size)
trans_prob# = zero# (max_trans_size)

@estimateTransitions

####################################################################
# VITERBI DECODE + ONE HARD-EM RE-ESTIMATION (v1.3)
#
# Decode the most likely hidden-state path under the learned
# Gaussian emissions and transition matrix (log-space Viterbi),
# then re-estimate emissions and transitions from the decoded
# path (one hard-EM iteration). The k-means labels serve as the
# initialization; the decoded path is what generation and the
# visualization use -- panel 2's "Viterbi Path" label is now true.
####################################################################

appendInfoLine: "Viterbi decoding..."

# Pre-compute log emissions (constant terms dropped -- identical
# across states per feature count) and log transitions
emitLog# = zero# (num_frames * k)
for i to num_frames
    for s to k
        z1 = (norm_int#[i] - emit_mean_int#[s]) / emit_std_int#[s]
        z2 = (norm_pitch#[i] - emit_mean_pitch#[s]) / emit_std_pitch#[s]
        z3 = (norm_cent#[i] - emit_mean_cent#[s]) / emit_std_cent#[s]
        z4 = (norm_slope#[i] - emit_mean_slope#[s]) / emit_std_slope#[s]
        emitLog#[(i - 1) * k + s] = -0.5 * (z1*z1 + z2*z2 + z3*z3 + z4*z4)
            ... - ln(emit_std_int#[s]) - ln(emit_std_pitch#[s])
            ... - ln(emit_std_cent#[s]) - ln(emit_std_slope#[s])
    endfor
endfor

lnTrans# = zero# (k * k)
for idx to k * k
    lnTrans#[idx] = ln(trans_prob#[idx])
endfor

prevDelta# = zero# (k)
curDelta# = zero# (k)
psi# = zero# (num_frames * k)

# Initial probabilities from state occupancy (smoothed)
for s to k
    piS = (state_count#[s] + 0.5) / (num_frames + 0.5 * k)
    prevDelta#[s] = ln(piS) + emitLog#[s]
endfor

# Forward pass
for i from 2 to num_frames
    for s to k
        best = -1e30
        bestPrev = 1
        for s1 to k
            v = prevDelta#[s1] + lnTrans#[(s1 - 1) * k + s]
            if v > best
                best = v
                bestPrev = s1
            endif
        endfor
        curDelta#[s] = best + emitLog#[(i - 1) * k + s]
        psi#[(i - 1) * k + s] = bestPrev
    endfor
    prevDelta# = curDelta#
endfor

# Backtrack (ascending loop form -- descending "for" is a silent
# no-op in Praat)
viterbi_state# = zero# (num_frames)
best = prevDelta#[1]
bestS = 1
for s from 2 to k
    if prevDelta#[s] > best
        best = prevDelta#[s]
        bestS = s
    endif
endfor
viterbi_state#[num_frames] = bestS

for back to num_frames - 1
    i = num_frames - back
    viterbi_state#[i] = psi#[i * k + viterbi_state#[i + 1]]
endfor

nChangedV = 0
for i to num_frames
    if viterbi_state#[i] <> state#[i]
        nChangedV += 1
    endif
endfor
state# = viterbi_state#
appendInfoLine: "  Viterbi changed ", nChangedV, "/", num_frames,
    ... " frame assignments vs k-means"

# Re-estimate the model on the decoded path (hard EM, one step)
@estimateEmissions
@estimateTransitions

####################################################################
# GENERATE SEQUENCE (HMM SAMPLING)
####################################################################

appendInfoLine: ""
appendInfoLine: "Generating HMM sequence..."

# Determine output length
# v1.3: frames concatenate at (frame_size - crossfade) spacing, NOT
# at the analysis hop. v1.2 divided the target by the hop, which
# with the 80/40 ms defaults produced ~2x the requested duration
# (and the trim was nested inside the under-build branch, so the
# overshoot was never trimmed).
advance_s = frame_size_s - crossfade_s
if advance_s < 0.001
    advance_s = 0.001
endif

if use_target_duration
    base_output_length = ceiling((target_duration_s - crossfade_s) / advance_s)
    if base_output_length < 2
        base_output_length = 2
    endif
    appendInfoLine: "Target: ", target_duration_s, " s (", base_output_length,
        ... " frames at ", fixed$(advance_s * 1000, 0), " ms advance)"
else
    if match_input_duration
        base_output_length = ceiling((duration_s - crossfade_s) / advance_s)
        if base_output_length < 2
            base_output_length = 2
        endif
        appendInfoLine: "Matching input duration (", base_output_length, " frames)"
    else
        base_output_length = output_length_frames
        appendInfoLine: "Fixed output length: ", output_length_frames, " frames"
    endif
endif

# Generate initial sequence
output_sequence_length = base_output_length

# Declare output vectors with extra space
max_output_frames = output_sequence_length * 3
output_state# = zero# (max_output_frames)
output_frame# = zero# (max_output_frames)

# Initialize with random state
current_state = randomInteger(1, k)
output_state#[1] = current_state

# Generate state sequence using transition probabilities
for i from 2 to output_sequence_length
    # Sample next state based on current state's transition probabilities
    rand = randomUniform(0, 1)
    cumulative = 0
    next_state = 1
    found = 0
    
    for s to k
        if found = 0
            idx = (current_state - 1) * k + s
            cumulative += trans_prob#[idx]
            if rand <= cumulative
                next_state = s
                found = 1
            endif
        endif
    endfor
    
    output_state#[i] = next_state
    current_state = next_state
endfor

# For each output frame, sample a matching input frame
appendInfoLine: "Sampling frames from emission distributions..."

# Declare candidates vector - use index 1 for count, 2+ for actual candidates
candidates# = zero# (num_frames + 2)

####################################################################
# SYNTHESIZE OUTPUT
#
# v1.3: all segments are extracted and faded first, then joined in
# a SINGLE multi-object Concatenate-with-overlap (the old one-at-a-
# time loop copied the growing output every iteration: O(n^2), and
# painful at the Experimental preset's 1000 frames). Stereo builds
# L and R directly instead of building and discarding a full mono
# sequence first. Loop-to-target and trim live in buildSequence,
# with a real copy as the loop base (v1.2 aliased base_sound to an
# object the loop removed, crashing whenever the branch ran).
####################################################################

appendInfoLine: ""
appendInfoLine: "Synthesizing audio..."

if stereo_output
    appendInfoLine: "Creating stereo with independent channels..."
    
    output_frame_L# = zero# (output_sequence_length)
    output_frame_R# = zero# (output_sequence_length)
    
    for i to output_sequence_length
        s = output_state#[i]
        
        candidates#[1] = 0
        for f to num_frames
            if state#[f] = s
                candidates#[1] += 1
                candidates#[candidates#[1] + 1] = f
            endif
        endfor
        
        if candidates#[1] > 0
            random_idx = randomInteger(1, candidates#[1])
            output_frame_L#[i] = candidates#[random_idx + 1]
            random_idx = randomInteger(1, candidates#[1])
            output_frame_R#[i] = candidates#[random_idx + 1]
        else
            output_frame_L#[i] = randomInteger(1, num_frames)
            output_frame_R#[i] = randomInteger(1, num_frames)
        endif
    endfor
    
    buildFrames# = output_frame_L#
    @buildSequence: output_sequence_length
    left_channel = buildSequence.result
    
    buildFrames# = output_frame_R#
    @buildSequence: output_sequence_length
    right_channel = buildSequence.result
    
    selectObject: left_channel, right_channel
    output_sound = Combine to stereo
    Rename: sound_name$ + "_HMM_" + presetName$ + "_stereo"
    removeObject: left_channel, right_channel
else
    for i to output_sequence_length
        s = output_state#[i]
        
        candidates#[1] = 0
        for f to num_frames
            if state#[f] = s
                candidates#[1] += 1
                candidates#[candidates#[1] + 1] = f
            endif
        endfor
        
        if candidates#[1] > 0
            random_idx = randomInteger(1, candidates#[1])
            output_frame#[i] = candidates#[random_idx + 1]
        else
            output_frame#[i] = randomInteger(1, num_frames)
        endif
    endfor
    
    buildFrames# = zero# (output_sequence_length)
    for i to output_sequence_length
        buildFrames#[i] = output_frame#[i]
    endfor
    @buildSequence: output_sequence_length
    output_sound = buildSequence.result
    selectObject: output_sound
    Rename: sound_name$ + "_HMM_" + presetName$
endif

appendInfoLine: "Generated ", output_sequence_length, " frames"

####################################################################
# VISUALIZATION
####################################################################

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # Color palette for states (up to 24 states)
    state_colors$# = {
    ... "{0.2, 0.4, 0.8}", "{0.8, 0.2, 0.4}", "{0.2, 0.8, 0.4}", "{0.8, 0.6, 0.2}",
    ... "{0.6, 0.2, 0.8}", "{0.2, 0.8, 0.8}", "{0.8, 0.8, 0.2}", "{0.8, 0.4, 0.6}",
    ... "{0.4, 0.8, 0.6}", "{0.6, 0.4, 0.8}", "{0.3, 0.6, 0.3}", "{0.6, 0.3, 0.6}",
    ... "{0.5, 0.5, 0.2}", "{0.2, 0.5, 0.5}", "{0.5, 0.2, 0.5}", "{0.7, 0.5, 0.3}",
    ... "{0.3, 0.7, 0.5}", "{0.5, 0.3, 0.7}", "{0.4, 0.4, 0.4}", "{0.6, 0.6, 0.6}",
    ... "{0.3, 0.3, 0.8}", "{0.8, 0.3, 0.3}", "{0.3, 0.8, 0.3}", "{0.7, 0.7, 0.3}"
    ... }
    
    # v1.3: layout converted to the library-standard 8-wide canvas
    # (outer+inner viewports, 0.6/7.7 margins, ##Bold## title,
    # font 6-7 labels, summary strip at the bottom).

    # State-axis mark step (avoid clutter at high K)
    markStep = ceiling(k / 12)
    if markStep < 1
        markStep = 1
    endif

    # === TITLE ===
    Select outer viewport: 0, 8, 0, 0.45
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", -1.7, "half",
        ... "##HMM Timbre Sequencer v1.3##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.20, "half",
        ... sound_name$ + " | " + presetName$
        ... + " | K=" + string$(k)
        ... + " | " + string$(num_frames) + " -> " + string$(output_sequence_length) + " frames"
        ... + " | frame " + string$(frame_size_ms) + " ms"

    # === PANEL: INPUT STATE SEQUENCE (VITERBI PATH) ===
    Select outer viewport: 0, 4, 0.50, 2.00
    Select inner viewport: 0.6, 3.85, 0.60, 1.95

    max_time_input = duration_s
    Axes: 0, max_time_input, 0.5, k + 0.5
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, max_time_input, 0.5, k + 0.5

    for i to num_frames
        s = state#[i]
        t_start = frame_start#[i]
        if i < num_frames
            t_end = frame_start#[i + 1]
        else
            t_end = max_time_input
        endif
        color_idx = ((s - 1) mod 24) + 1
        Paint rectangle: state_colors$#[color_idx], t_start, t_end, s - 0.4, s + 0.4
    endfor

    Colour: "Black"
    Draw inner box
    Marks left every: 1, markStep, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "State"
    Text top: "no", "Input states (Viterbi path)"
    Text bottom: "yes", "Time (s)"

    # === PANEL: OUTPUT STATE SEQUENCE ===
    Select outer viewport: 4, 8, 0.50, 2.00
    Select inner viewport: 4.2, 7.7, 0.60, 1.95

    # Output frames advance by (frame_size - crossfade)
    max_time_output = output_sequence_length * advance_s + crossfade_s
    Axes: 0, max_time_output, 0.5, k + 0.5
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, max_time_output, 0.5, k + 0.5

    for i to output_sequence_length
        s = output_state#[i]
        t_start = (i - 1) * advance_s
        t_end = i * advance_s
        color_idx = ((s - 1) mod 24) + 1
        Paint rectangle: state_colors$#[color_idx], t_start, t_end, s - 0.4, s + 0.4
    endfor

    Colour: "Black"
    Draw inner box
    Marks left every: 1, markStep, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "State"
    Text top: "no", "Generated states (HMM sampling)"
    Text bottom: "yes", "Time (s)"

    # === PANEL: FEATURE TRAJECTORIES ===
    Select outer viewport: 0, 8, 2.05, 3.85
    Select inner viewport: 0.6, 7.7, 2.15, 3.80

    Axes: 0, max_time_input, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, max_time_input, 0, 1

    Colour: "{0.9, 0.9, 0.9}"
    level = 0.25
    while level <= 0.75
        Draw line: 0, level, max_time_input, level
        level = level + 0.25
    endwhile

    feature_colors$# = {"{0.2, 0.4, 0.8}", "{0.8, 0.2, 0.4}", "{0.2, 0.8, 0.4}", "{0.8, 0.6, 0.2}"}
    feature_names$# = {"Intensity", "Pitch", "Centroid", "Slope"}

    Colour: feature_colors$#[1]
    Line width: 1.5
    for i from 1 to num_frames - 1
        Draw line: frame_start#[i], norm_int#[i], frame_start#[i + 1], norm_int#[i + 1]
    endfor

    Colour: feature_colors$#[2]
    for i from 1 to num_frames - 1
        Draw line: frame_start#[i], norm_pitch#[i], frame_start#[i + 1], norm_pitch#[i + 1]
    endfor

    Colour: feature_colors$#[3]
    for i from 1 to num_frames - 1
        Draw line: frame_start#[i], norm_cent#[i], frame_start#[i + 1], norm_cent#[i + 1]
    endfor

    Colour: feature_colors$#[4]
    for i from 1 to num_frames - 1
        Draw line: frame_start#[i], norm_slope#[i], frame_start#[i + 1], norm_slope#[i + 1]
    endfor

    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 0.5, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "Normalized"
    Text top: "no", "Feature trajectories (4D observations)"
    Text bottom: "yes", "Time (s)"

    Font size: 6
    x_legend = max_time_input * 0.02
    Colour: feature_colors$#[1]
    Text: x_legend, "left", 0.95, "half", feature_names$#[1]
    Colour: feature_colors$#[2]
    Text: x_legend, "left", 0.86, "half", feature_names$#[2]
    Colour: feature_colors$#[3]
    Text: x_legend, "left", 0.77, "half", feature_names$#[3]
    Colour: feature_colors$#[4]
    Text: x_legend, "left", 0.68, "half", feature_names$#[4]

    # === PANEL: TRANSITION MATRIX HEATMAP ===
    Select outer viewport: 0, 4, 3.90, 6.10
    Select inner viewport: 0.8, 3.7, 4.00, 6.00

    Axes: 0.5, k + 0.5, 0.5, k + 0.5

    for s1 to k
        for s2 to k
            idx = (s1 - 1) * k + s2
            prob = trans_prob#[idx]
            gray_level = 1 - prob
            if gray_level < 0
                gray_level = 0
            endif
            if gray_level > 1
                gray_level = 1
            endif
            color$ = "{" + string$(gray_level) + ", " + string$(gray_level) + ", " + string$(gray_level) + "}"
            Paint rectangle: color$, s2 - 0.5, s2 + 0.5, k - s1 + 0.5, k - s1 + 1.5
        endfor
    endfor

    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, markStep, "yes", "yes", "no"
    Marks left every: 1, markStep, "yes", "yes", "no"
    Font size: 7
    Text bottom: "yes", "To state"
    Text left: "yes", "From state"
    Text top: "no", "Transitions (darker = higher p)"

    # === PANEL: EMISSION DISTRIBUTIONS ===
    Select outer viewport: 4, 8, 3.90, 6.10
    Select inner viewport: 4.35, 7.7, 4.00, 6.00

    Axes: 0.5, k + 0.5, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0.5, k + 0.5, 0, 1

    bar_width = 0.15
    feature_offset# = {-0.3, -0.1, 0.1, 0.3}

    for s to k
        mean_val = emit_mean_int#[s]
        std_val = emit_std_int#[s]
        x_pos = s + feature_offset#[1]
        Colour: feature_colors$#[1]
        Paint rectangle: feature_colors$#[1], x_pos - bar_width/2, x_pos + bar_width/2, 0, mean_val
        Draw line: x_pos, max(0, mean_val - std_val), x_pos, min(1, mean_val + std_val)

        mean_val = emit_mean_pitch#[s]
        std_val = emit_std_pitch#[s]
        x_pos = s + feature_offset#[2]
        Colour: feature_colors$#[2]
        Paint rectangle: feature_colors$#[2], x_pos - bar_width/2, x_pos + bar_width/2, 0, mean_val
        Draw line: x_pos, max(0, mean_val - std_val), x_pos, min(1, mean_val + std_val)

        mean_val = emit_mean_cent#[s]
        std_val = emit_std_cent#[s]
        x_pos = s + feature_offset#[3]
        Colour: feature_colors$#[3]
        Paint rectangle: feature_colors$#[3], x_pos - bar_width/2, x_pos + bar_width/2, 0, mean_val
        Draw line: x_pos, max(0, mean_val - std_val), x_pos, min(1, mean_val + std_val)

        mean_val = emit_mean_slope#[s]
        std_val = emit_std_slope#[s]
        x_pos = s + feature_offset#[4]
        Colour: feature_colors$#[4]
        Paint rectangle: feature_colors$#[4], x_pos - bar_width/2, x_pos + bar_width/2, 0, mean_val
        Draw line: x_pos, max(0, mean_val - std_val), x_pos, min(1, mean_val + std_val)
    endfor

    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, markStep, "yes", "yes", "no"
    Marks left every: 1, 0.5, "yes", "yes", "no"
    Font size: 7
    Text bottom: "yes", "State"
    Text left: "yes", "Mean +- std"
    Text top: "no", "Emissions (Gaussian per state)"

    # === SUMMARY STRIP ===
    Select outer viewport: 0, 8, 6.20, 6.90
    Select inner viewport: 0.6, 7.7, 6.25, 6.85
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    selectObject: output_sound
    vizOutDur = Get total duration
    vizOutCh = Get number of channels

    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.02, "left", 0.78, "half",
        ... "##Model##  K=" + string$(k)
        ... + "  frames " + string$(num_frames) + " -> " + string$(output_sequence_length)
        ... + "  k-means " + string$(iterationsUsed) + " iter"
        ... + "  Viterbi changed " + string$(nChangedV) + "/" + string$(num_frames)
    Text: 0.02, "left", 0.48, "half",
        ... "##Frames##  size=" + string$(frame_size_ms) + " ms"
        ... + "  hop=" + string$(frame_hop_ms) + " ms"
        ... + "  advance=" + fixed$(advance_s * 1000, 0) + " ms"
        ... + "  crossfade=" + fixed$(crossfade_s * 1000, 1) + " ms"
    Text: 0.02, "left", 0.18, "half",
        ... "##Output##  " + fixed$(vizOutDur, 2) + " s"
        ... + "  " + string$(vizOutCh) + " ch"
        ... + "  preset=" + presetName$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1

    appendInfoLine: "  Visualization complete!"
endif

####################################################################
# CLEANUP
####################################################################

removeObject: sound_mono

selectObject: output_sound

if show_info
    selectObject: output_sound
    dur = Get total duration
    n_ch = Get number of channels
    appendInfoLine: ""
    appendInfoLine: "=== Complete ==="
    appendInfoLine: "Output: ", selected$("Sound")
    appendInfoLine: "Duration: ", fixed$(dur, 3), " s"
    appendInfoLine: "Channels: ", n_ch
    appendInfoLine: ""
    appendInfoLine: "HMM Model:"
    appendInfoLine: "  States: ", k, " hidden timbre classes"
    appendInfoLine: "  Observations: 4D feature vectors"
    appendInfoLine: "  Emissions: Gaussian (mean + std per feature)"
    appendInfoLine: "  Transitions: Learned from data"
endif

if play_result
    Play
endif
####################################################################
# PROCEDURES (v1.3)
####################################################################

# Estimate Gaussian emissions and state occupancy from the current
# global state# assignment. States with no members keep their
# previous means (generation falls back to a random frame for them
# anyway); stds get the standard floors.
procedure estimateEmissions
    .sInt# = zero# (k)
    .sPit# = zero# (k)
    .sCen# = zero# (k)
    .sSlo# = zero# (k)
    state_count# = zero# (k)
    
    for .i to num_frames
        .s = state#[.i]
        .sInt#[.s] += norm_int#[.i]
        .sPit#[.s] += norm_pitch#[.i]
        .sCen#[.s] += norm_cent#[.i]
        .sSlo#[.s] += norm_slope#[.i]
        state_count#[.s] += 1
    endfor
    
    for .s to k
        if state_count#[.s] > 0
            emit_mean_int#[.s] = .sInt#[.s] / state_count#[.s]
            emit_mean_pitch#[.s] = .sPit#[.s] / state_count#[.s]
            emit_mean_cent#[.s] = .sCen#[.s] / state_count#[.s]
            emit_mean_slope#[.s] = .sSlo#[.s] / state_count#[.s]
        endif
    endfor
    
    .vInt# = zero# (k)
    .vPit# = zero# (k)
    .vCen# = zero# (k)
    .vSlo# = zero# (k)
    
    for .i to num_frames
        .s = state#[.i]
        .vInt#[.s] += (norm_int#[.i] - emit_mean_int#[.s])^2
        .vPit#[.s] += (norm_pitch#[.i] - emit_mean_pitch#[.s])^2
        .vCen#[.s] += (norm_cent#[.i] - emit_mean_cent#[.s])^2
        .vSlo#[.s] += (norm_slope#[.i] - emit_mean_slope#[.s])^2
    endfor
    
    for .s to k
        if state_count#[.s] > 1
            emit_std_int#[.s] = sqrt(.vInt#[.s] / state_count#[.s])
            emit_std_pitch#[.s] = sqrt(.vPit#[.s] / state_count#[.s])
            emit_std_cent#[.s] = sqrt(.vCen#[.s] / state_count#[.s])
            emit_std_slope#[.s] = sqrt(.vSlo#[.s] / state_count#[.s])
        else
            emit_std_int#[.s] = 0.1
            emit_std_pitch#[.s] = 0.1
            emit_std_cent#[.s] = 0.1
            emit_std_slope#[.s] = 0.1
        endif
        
        if emit_std_int#[.s] < 0.01
            emit_std_int#[.s] = 0.1
        endif
        if emit_std_pitch#[.s] < 0.01
            emit_std_pitch#[.s] = 0.1
        endif
        if emit_std_cent#[.s] < 0.01
            emit_std_cent#[.s] = 0.1
        endif
        if emit_std_slope#[.s] < 0.01
            emit_std_slope#[.s] = 0.1
        endif
    endfor
endproc

# Count transitions in the current global state# assignment and
# convert to row-normalized probabilities with add-constant
# smoothing.
procedure estimateTransitions
    trans_count# = zero# (max_trans_size)
    
    for .i from 1 to num_frames - 1
        .idx = (state#[.i] - 1) * k + state#[.i + 1]
        trans_count#[.idx] += 1
    endfor
    
    .smoothing = 0.01
    for .s1 to k
        .rowSum = 0
        for .s2 to k
            .idx = (.s1 - 1) * k + .s2
            .rowSum += trans_count#[.idx] + .smoothing
        endfor
        
        for .s2 to k
            .idx = (.s1 - 1) * k + .s2
            if .rowSum > 0
                trans_prob#[.idx] = (trans_count#[.idx] + .smoothing) / .rowSum
            else
                trans_prob#[.idx] = 1 / k
            endif
        endfor
    endfor
endproc

# Build one audio sequence from buildFrames#[1..n]: extract and
# fade all segments, join them in a single Concatenate-with-overlap,
# then loop and/or trim to the target duration if one is set.
procedure buildSequence: .n
    for .i to .n
        .fi = buildFrames#[.i]
        .t1 = frame_start#[.fi]
        .t2 = .t1 + frame_size_s
        if .t2 > duration_s
            .t2 = duration_s
        endif
        selectObject: sound_mono
        bseg_'.i' = Extract part: .t1, .t2, "rectangular", 1.0, "no"
        .segDur = Get total duration
        Fade in: 0, 0, crossfade_s, "yes"
        Fade out: 0, .segDur, -crossfade_s, "yes"
    endfor
    
    selectObject: bseg_1
    for .i from 2 to .n
        plusObject: bseg_'.i'
    endfor
    if .n >= 2
        .cat = Concatenate with overlap: crossfade_s
    else
        .cat = Copy: "sequence"
    endif
    for .i to .n
        removeObject: bseg_'.i'
    endfor
    
    if use_target_duration
        selectObject: .cat
        .d = Get total duration
        
        if .d < target_duration_s
            # v1.3: the loop base is a REAL copy. v1.2 aliased it to
            # the object the loop removes, crashing on iteration 2
            # (or at cleanup after iteration 1).
            selectObject: .cat
            .base = Copy: "loop_base"
            while .d < target_duration_s
                selectObject: .base
                .lc = Copy: "loop_tmp"
                selectObject: .cat, .lc
                .tmp = Concatenate with overlap: crossfade_s
                removeObject: .cat, .lc
                .cat = .tmp
                selectObject: .cat
                .d = Get total duration
            endwhile
            removeObject: .base
        endif
        
        # v1.3: trim is unconditional on overshoot (it was nested
        # inside the under-build branch, so it never ran)
        selectObject: .cat
        .d = Get total duration
        if .d > target_duration_s
            .tr = Extract part: 0, target_duration_s, "rectangular", 1, "no"
            removeObject: .cat
            .cat = .tr
        endif
    endif
    
    selectObject: .cat
    Scale peak: 0.95
    buildSequence.result = .cat
endproc
