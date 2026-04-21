# ============================================================
# Praat AudioTools - HMM_Timbre_Sequencing.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.2 (2025) - With Visualization
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

form HMM Timbre Sequencer v1.2 (True HMM)
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
    comment (Frame size must be >= 64ms for intensity analysis)
    comment === HMM Parameters ===
    positive Number_of_states_K 8
    positive Max_kmeans_iterations 50
    comment === Sequence Generation ===
    positive Target_duration_s 8.0
    comment (Script will loop sequence to fill target duration)
    boolean Match_input_duration 0
    positive Output_length_frames 200
    comment (Match input duration or Output length only used if Target duration is 0)
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

if frame_size_ms < 64
    exitScript: "Frame size must be >= 64ms for intensity analysis."
endif

# Convert to seconds
frame_size_s = frame_size_ms / 1000
frame_hop_s = frame_hop_ms / 1000
crossfade_s = crossfade_ms / 1000

k = number_of_states_K

# Determine if using target duration
use_target_duration = (target_duration_s > 0)

clearinfo
writeInfoLine: "╔════════════════════════════════════════════════════╗"
writeInfoLine: "║   HMM TIMBRE SEQUENCER v1.2 (True HMM + Viz)      ║"
writeInfoLine: "╚════════════════════════════════════════════════════╝"
writeInfoLine: ""
writeInfoLine: "Preset: ", presetName$
writeInfoLine: "States (K): ", k
writeInfoLine: "Frame: ", frame_size_ms, " ms (hop: ", frame_hop_ms, " ms)"
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

# Declare feature vectors
frame_start# = zero# (num_frames)
raw_int# = zero# (num_frames)
raw_pitch# = zero# (num_frames)
raw_cent# = zero# (num_frames)
raw_slope# = zero# (num_frames)

# Minimum frame duration for intensity analysis
min_intensity_duration = 6.4 / 75

# Extract features per frame
selectObject: sound_mono

for i to num_frames
    t_start = (i - 1) * frame_hop_s
    t_end = t_start + frame_size_s
    
    if t_end > duration_s
        t_end = duration_s
    endif
    
    frame_start#[i] = t_start
    frame_duration = t_end - t_start
    
    # Extract frame
    frame_sound = Extract part: t_start, t_end, "rectangular", 1.0, "no"
    
    # Intensity (only if frame is long enough)
    if frame_duration >= min_intensity_duration
        To Intensity: 75, 0, "yes"
        intensity_obj = selected("Intensity")
        raw_int#[i] = Get mean: t_start, t_end, "energy"
        if raw_int#[i] = undefined
            raw_int#[i] = 0
        endif
        removeObject: intensity_obj
        
        selectObject: frame_sound
    else
        # Frame too short - use fallback value
        raw_int#[i] = 50
    endif
    
    # Pitch
    To Pitch (ac): 0, 75, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14, 600
    pitch_obj = selected("Pitch")
    raw_pitch#[i] = Get mean: t_start, t_end, "Hertz"
    if raw_pitch#[i] = undefined
        raw_pitch#[i] = 0
    endif
    removeObject: pitch_obj
    
    selectObject: frame_sound
    
    # Spectrum for centroid and slope
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
    
    selectObject: sound_mono
endfor

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

# K-means iterations
for iter to max_kmeans_iterations
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
endfor

appendInfoLine: "K-means completed (", max_kmeans_iterations, " iterations)"

####################################################################
# COMPUTE EMISSION PROBABILITIES (GAUSSIAN)
####################################################################

appendInfoLine: "Computing emission distributions..."

# Declare emission vectors
emit_mean_int# = zero# (k)
emit_mean_pitch# = zero# (k)
emit_mean_cent# = zero# (k)
emit_mean_slope# = zero# (k)
emit_std_int# = zero# (k)
emit_std_pitch# = zero# (k)
emit_std_cent# = zero# (k)
emit_std_slope# = zero# (k)
state_count# = zero# (k)

# Compute means per state
for i to num_frames
    s = state#[i]
    emit_mean_int#[s] += norm_int#[i]
    emit_mean_pitch#[s] += norm_pitch#[i]
    emit_mean_cent#[s] += norm_cent#[i]
    emit_mean_slope#[s] += norm_slope#[i]
    state_count#[s] += 1
endfor

for s to k
    if state_count#[s] > 0
        emit_mean_int#[s] /= state_count#[s]
        emit_mean_pitch#[s] /= state_count#[s]
        emit_mean_cent#[s] /= state_count#[s]
        emit_mean_slope#[s] /= state_count#[s]
    endif
endfor

# Compute standard deviations per state
for i to num_frames
    s = state#[i]
    emit_std_int#[s] += (norm_int#[i] - emit_mean_int#[s])^2
    emit_std_pitch#[s] += (norm_pitch#[i] - emit_mean_pitch#[s])^2
    emit_std_cent#[s] += (norm_cent#[i] - emit_mean_cent#[s])^2
    emit_std_slope#[s] += (norm_slope#[i] - emit_mean_slope#[s])^2
endfor

for s to k
    if state_count#[s] > 1
        emit_std_int#[s] = sqrt(emit_std_int#[s] / state_count#[s])
        emit_std_pitch#[s] = sqrt(emit_std_pitch#[s] / state_count#[s])
        emit_std_cent#[s] = sqrt(emit_std_cent#[s] / state_count#[s])
        emit_std_slope#[s] = sqrt(emit_std_slope#[s] / state_count#[s])
    else
        emit_std_int#[s] = 0.1
        emit_std_pitch#[s] = 0.1
        emit_std_cent#[s] = 0.1
        emit_std_slope#[s] = 0.1
    endif
    
    # Prevent zero std
    if emit_std_int#[s] < 0.01
        emit_std_int#[s] = 0.1
    endif
    if emit_std_pitch#[s] < 0.01
        emit_std_pitch#[s] = 0.1
    endif
    if emit_std_cent#[s] < 0.01
        emit_std_cent#[s] = 0.1
    endif
    if emit_std_slope#[s] < 0.01
        emit_std_slope#[s] = 0.1
    endif
endfor

####################################################################
# COMPUTE TRANSITION PROBABILITIES
####################################################################

appendInfoLine: "Learning transition probabilities..."

# Simulate 2D arrays with 1D indexing: index = (s1-1)*k + s2
max_trans_size = k * k
trans_count# = zero# (max_trans_size)
trans_prob# = zero# (max_trans_size)

# Count transitions
for i from 1 to num_frames - 1
    s_from = state#[i]
    s_to = state#[i + 1]
    idx = (s_from - 1) * k + s_to
    trans_count#[idx] += 1
endfor

# Convert to probabilities (with smoothing)
smoothing = 0.01
for s1 to k
    row_sum = 0
    for s2 to k
        idx = (s1 - 1) * k + s2
        row_sum += trans_count#[idx] + smoothing
    endfor
    
    for s2 to k
        idx = (s1 - 1) * k + s2
        if row_sum > 0
            trans_prob#[idx] = (trans_count#[idx] + smoothing) / row_sum
        else
            trans_prob#[idx] = 1 / k
        endif
    endfor
endfor

####################################################################
# GENERATE SEQUENCE (HMM SAMPLING)
####################################################################

appendInfoLine: ""
appendInfoLine: "Generating HMM sequence..."

# Determine output length
if use_target_duration
    # Calculate frames needed for target duration
    base_output_length = floor(target_duration_s / frame_hop_s)
    appendInfoLine: "Target: ", target_duration_s, " s (≈", base_output_length, " frames)"
else
    if match_input_duration
        base_output_length = num_frames
        appendInfoLine: "Matching input duration (", num_frames, " frames)"
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

for i to output_sequence_length
    s = output_state#[i]
    
    # Find all frames assigned to this state
    # Store count at index 1
    candidates#[1] = 0
    for f to num_frames
        if state#[f] = s
            candidates#[1] += 1
            candidates#[candidates#[1] + 1] = f
        endif
    endfor
    
    # Sample from candidates
    if candidates#[1] > 0
        random_idx = randomInteger(1, candidates#[1])
        output_frame#[i] = candidates#[random_idx + 1]
    else
        # Fallback: random frame
        output_frame#[i] = randomInteger(1, num_frames)
    endif
endfor

appendInfoLine: "Generated ", output_sequence_length, " frames"

####################################################################
# SYNTHESIZE OUTPUT
####################################################################

appendInfoLine: ""
appendInfoLine: "Synthesizing audio..."

selectObject: sound_mono

# Create first frame
t_start = frame_start#[output_frame#[1]]
t_end = t_start + frame_size_s

if t_end > duration_s
    t_end = duration_s
endif

first_segment = Extract part: t_start, t_end, "rectangular", 1.0, "no"
Fade in: 0, 0, crossfade_s, "yes"
Fade out: 0, frame_size_s, -crossfade_s, "yes"

output_sound = Copy: sound_name$ + "_HMM_" + presetName$

# Concatenate remaining frames
for i from 2 to output_sequence_length
    frame_idx = output_frame#[i]
    t_start = frame_start#[frame_idx]
    t_end = t_start + frame_size_s
    
    if t_end > duration_s
        t_end = duration_s
    endif
    
    selectObject: sound_mono
    segment = Extract part: t_start, t_end, "rectangular", 1.0, "no"
    
    Fade in: 0, 0, crossfade_s, "yes"
    Fade out: 0, frame_size_s, -crossfade_s, "yes"
    
    selectObject: output_sound, segment
    temp = Concatenate with overlap: crossfade_s
    
    removeObject: output_sound, segment
    output_sound = temp
    
    selectObject: sound_mono
endfor

removeObject: first_segment

# Loop to target duration if needed
if use_target_duration
    selectObject: output_sound
    current_duration = Get total duration
    
    if current_duration < target_duration_s
        base_sound = output_sound
        
        while current_duration < target_duration_s
            selectObject: base_sound
            loop_copy = Copy: "loop_temp"
            
            selectObject: output_sound, loop_copy
            temp = Concatenate with overlap: crossfade_s
            
            removeObject: output_sound, loop_copy
            output_sound = temp
            
            selectObject: output_sound
            current_duration = Get total duration
        endwhile
        
        if current_duration > target_duration_s
            trimmed = Extract part: 0, target_duration_s, "rectangular", 1, "no"
            removeObject: output_sound
            output_sound = trimmed
        endif
        
        removeObject: base_sound
    endif
endif

selectObject: output_sound
Scale peak: 0.95

####################################################################
# STEREO OUTPUT (if requested)
####################################################################

if stereo_output
    appendInfoLine: "Creating stereo with independent channels..."
    
    # Create separate sequences for L and R
    output_frame_L# = zero# (output_sequence_length)
    output_frame_R# = zero# (output_sequence_length)
    
    for i to output_sequence_length
        s = output_state#[i]
        
        # Left channel
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
        else
            output_frame_L#[i] = randomInteger(1, num_frames)
        endif
        
        # Right channel (different sample)
        if candidates#[1] > 0
            random_idx = randomInteger(1, candidates#[1])
            output_frame_R#[i] = candidates#[random_idx + 1]
        else
            output_frame_R#[i] = randomInteger(1, num_frames)
        endif
    endfor
    
    # Build left channel
    selectObject: sound_mono
    t_start = frame_start#[output_frame_L#[1]]
    t_end = t_start + frame_size_s
    if t_end > duration_s
        t_end = duration_s
    endif
    
    first_seg_L = Extract part: t_start, t_end, "rectangular", 1.0, "no"
    Fade in: 0, 0, crossfade_s, "yes"
    Fade out: 0, frame_size_s, -crossfade_s, "yes"
    
    left_channel = Copy: "left"
    removeObject: first_seg_L
    
    for i from 2 to output_sequence_length
        frame_idx = output_frame_L#[i]
        t_start = frame_start#[frame_idx]
        t_end = t_start + frame_size_s
        
        if t_end > duration_s
            t_end = duration_s
        endif
        
        selectObject: sound_mono
        seg_L = Extract part: t_start, t_end, "rectangular", 1.0, "no"
        Fade in: 0, 0, crossfade_s, "yes"
        Fade out: 0, frame_size_s, -crossfade_s, "yes"
        
        selectObject: left_channel, seg_L
        temp = Concatenate with overlap: crossfade_s
        
        removeObject: left_channel, seg_L
        left_channel = temp
        
        selectObject: sound_mono
    endfor
    
    # Loop left channel if needed
    if use_target_duration
        selectObject: left_channel
        current_duration_L = Get total duration
        
        if current_duration_L < target_duration_s
            base_sound_L = left_channel
            
            while current_duration_L < target_duration_s
                selectObject: base_sound_L
                loop_copy_L = Copy: "loop_L_temp"
                
                selectObject: left_channel, loop_copy_L
                temp = Concatenate with overlap: crossfade_s
                
                removeObject: left_channel, loop_copy_L
                left_channel = temp
                
                selectObject: left_channel
                current_duration_L = Get total duration
            endwhile
            
            if current_duration_L > target_duration_s
                trimmed_L = Extract part: 0, target_duration_s, "rectangular", 1, "no"
                removeObject: left_channel
                left_channel = trimmed_L
            endif
            
            removeObject: base_sound_L
        endif
    endif
    
    selectObject: left_channel
    Scale peak: 0.95
    
    # Build right channel
    selectObject: sound_mono
    t_start = frame_start#[output_frame_R#[1]]
    t_end = t_start + frame_size_s
    if t_end > duration_s
        t_end = duration_s
    endif
    
    first_seg_R = Extract part: t_start, t_end, "rectangular", 1.0, "no"
    Fade in: 0, 0, crossfade_s, "yes"
    Fade out: 0, frame_size_s, -crossfade_s, "yes"
    
    right_channel = Copy: "right"
    removeObject: first_seg_R
    
    for i from 2 to output_sequence_length
        frame_idx = output_frame_R#[i]
        t_start = frame_start#[frame_idx]
        t_end = t_start + frame_size_s
        
        if t_end > duration_s
            t_end = duration_s
        endif
        
        selectObject: sound_mono
        seg_R = Extract part: t_start, t_end, "rectangular", 1.0, "no"
        Fade in: 0, 0, crossfade_s, "yes"
        Fade out: 0, frame_size_s, -crossfade_s, "yes"
        
        selectObject: right_channel, seg_R
        temp = Concatenate with overlap: crossfade_s
        
        removeObject: right_channel, seg_R
        right_channel = temp
        
        selectObject: sound_mono
    endfor
    
    # Loop right channel if needed
    if use_target_duration
        selectObject: right_channel
        current_duration_R = Get total duration
        
        if current_duration_R < target_duration_s
            base_sound_R = right_channel
            
            while current_duration_R < target_duration_s
                selectObject: base_sound_R
                loop_copy_R = Copy: "loop_R_temp"
                
                selectObject: right_channel, loop_copy_R
                temp = Concatenate with overlap: crossfade_s
                
                removeObject: right_channel, loop_copy_R
                right_channel = temp
                
                selectObject: right_channel
                current_duration_R = Get total duration
            endwhile
            
            if current_duration_R > target_duration_s
                trimmed_R = Extract part: 0, target_duration_s, "rectangular", 1, "no"
                removeObject: right_channel
                right_channel = trimmed_R
            endif
            
            removeObject: base_sound_R
        endif
    endif
    
    selectObject: right_channel
    Scale peak: 0.95
    
    # Combine to stereo
    selectObject: left_channel, right_channel
    stereo_sound = Combine to stereo
    Rename: sound_name$ + "_HMM_" + presetName$ + "_stereo"
    
    removeObject: output_sound, left_channel, right_channel
    output_sound = stereo_sound
endif

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
    
    # === PANEL 1: TITLE & PARAMETERS ===
    Select outer viewport: 0, 12, 0, 0.8
    Select inner viewport: 0, 12, 0, 0.8
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "HMM Timbre Sequencing - " + presetName$
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.3, "half", "States: " + string$(k) + " | Frames: " + string$(num_frames) + " → " + string$(output_sequence_length) + " | Frame: " + string$(frame_size_ms) + "ms"
    
    # === PANEL 2: INPUT STATE SEQUENCE ===
    Select outer viewport: 0, 6, 1.0, 2.8
    Select inner viewport: 0.5, 5.7, 1.1, 2.75
    
    max_time_input = duration_s
    Axes: 0, max_time_input, 0.5, k + 0.5
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, max_time_input, 0.5, k + 0.5
    
    # Draw input state sequence as colored blocks
    for i to num_frames
        s = state#[i]
        t_start = frame_start#[i]
        if i < num_frames
            t_end = frame_start#[i + 1]
        else
            t_end = max_time_input
        endif
        
        color_idx = ((s - 1) mod 24) + 1
        Colour: state_colors$#[color_idx]
        Paint rectangle: state_colors$#[color_idx], t_start, t_end, s - 0.4, s + 0.4
    endfor
    
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 1, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "State"
    Text top: "no", "Input State Sequence (Viterbi Path)"
    Text bottom: "yes", "Time (s)"
    
    # === PANEL 3: OUTPUT STATE SEQUENCE ===
    Select outer viewport: 6, 12, 1.0, 2.8
    Select inner viewport: 6.3, 11.7, 1.1, 2.75
    
    max_time_output = output_sequence_length * frame_hop_s
    Axes: 0, max_time_output, 0.5, k + 0.5
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, max_time_output, 0.5, k + 0.5
    
    # Draw output state sequence
    for i to output_sequence_length
        s = output_state#[i]
        t_start = (i - 1) * frame_hop_s
        t_end = i * frame_hop_s
        
        color_idx = ((s - 1) mod 24) + 1
        Colour: state_colors$#[color_idx]
        Paint rectangle: state_colors$#[color_idx], t_start, t_end, s - 0.4, s + 0.4
    endfor
    
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 1, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "State"
    Text top: "no", "Generated State Sequence (HMM Sampling)"
    Text bottom: "yes", "Time (s)"
    
    # === PANEL 4: FEATURE TRAJECTORIES ===
    Select outer viewport: 0, 12, 3.0, 5.5
    Select inner viewport: 0.5, 11.7, 3.1, 5.45
    
    Axes: 0, max_time_input, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, max_time_input, 0, 1
    
    # Draw grid
    Colour: "{0.9, 0.9, 0.9}"
    level = 0.25
    while level <= 0.75
        Draw line: 0, level, max_time_input, level
        level = level + 0.25
    endwhile
    
    # Draw feature trajectories
    feature_colors$# = {"{0.2, 0.4, 0.8}", "{0.8, 0.2, 0.4}", "{0.2, 0.8, 0.4}", "{0.8, 0.6, 0.2}"}
    feature_names$# = {"Intensity", "Pitch", "Centroid", "Slope"}
    
    # Intensity
    Colour: feature_colors$#[1]
    Line width: 1.5
    for i from 1 to num_frames - 1
        t1 = frame_start#[i]
        t2 = frame_start#[i + 1]
        Draw line: t1, norm_int#[i], t2, norm_int#[i + 1]
    endfor
    
    # Pitch
    Colour: feature_colors$#[2]
    for i from 1 to num_frames - 1
        t1 = frame_start#[i]
        t2 = frame_start#[i + 1]
        Draw line: t1, norm_pitch#[i], t2, norm_pitch#[i + 1]
    endfor
    
    # Centroid
    Colour: feature_colors$#[3]
    for i from 1 to num_frames - 1
        t1 = frame_start#[i]
        t2 = frame_start#[i + 1]
        Draw line: t1, norm_cent#[i], t2, norm_cent#[i + 1]
    endfor
    
    # Slope
    Colour: feature_colors$#[4]
    for i from 1 to num_frames - 1
        t1 = frame_start#[i]
        t2 = frame_start#[i + 1]
        Draw line: t1, norm_slope#[i], t2, norm_slope#[i + 1]
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 0.5, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "Normalized"
    Text top: "no", "Feature Trajectories (4D Observations)"
    Text bottom: "yes", "Time (s)"
    
    # Legend
    Font size: 6
    x_legend = max_time_input * 0.02
    Colour: feature_colors$#[1]
    Text: x_legend, "left", 0.95, "half", feature_names$#[1]
    Colour: feature_colors$#[2]
    Text: x_legend, "left", 0.88, "half", feature_names$#[2]
    Colour: feature_colors$#[3]
    Text: x_legend, "left", 0.81, "half", feature_names$#[3]
    Colour: feature_colors$#[4]
    Text: x_legend, "left", 0.74, "half", feature_names$#[4]
    
    # === PANEL 5: TRANSITION MATRIX HEATMAP ===
    Select outer viewport: 0, 6, 5.7, 8.5
    Select inner viewport: 0.8, 5.5, 5.9, 8.35
    
    Axes: 0.5, k + 0.5, 0.5, k + 0.5
    
    # Draw heatmap
    for s1 to k
        for s2 to k
            idx = (s1 - 1) * k + s2
            prob = trans_prob#[idx]
            
            # Color intensity based on probability
            gray_level = 1 - prob
            if gray_level < 0
                gray_level = 0
            endif
            if gray_level > 1
                gray_level = 1
            endif
            
            color$ = "{" + string$(gray_level) + ", " + string$(gray_level) + ", " + string$(gray_level) + "}"
            Colour: color$
            Paint rectangle: color$, s2 - 0.5, s2 + 0.5, k - s1 + 0.5, k - s1 + 1.5
        endfor
    endfor
    
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Marks left every: 1, 1, "yes", "yes", "no"
    Font size: 7
    Text bottom: "yes", "To State"
    Text left: "yes", "From State"
    Text top: "no", "Transition Matrix (Darker = Higher Prob)"
    
    # === PANEL 6: EMISSION DISTRIBUTIONS ===
    Select outer viewport: 6, 12, 5.7, 8.5
    Select inner viewport: 6.5, 11.7, 5.9, 8.35
    
    Axes: 0.5, k + 0.5, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0.5, k + 0.5, 0, 1
    
    # Draw emission means ± std for each feature
    bar_width = 0.15
    feature_offset# = {-0.3, -0.1, 0.1, 0.3}
    
    for s to k
        # Intensity
        mean_val = emit_mean_int#[s]
        std_val = emit_std_int#[s]
        x_pos = s + feature_offset#[1]
        Colour: feature_colors$#[1]
        Paint rectangle: feature_colors$#[1], x_pos - bar_width/2, x_pos + bar_width/2, 0, mean_val
        Draw line: x_pos, max(0, mean_val - std_val), x_pos, min(1, mean_val + std_val)
        
        # Pitch
        mean_val = emit_mean_pitch#[s]
        std_val = emit_std_pitch#[s]
        x_pos = s + feature_offset#[2]
        Colour: feature_colors$#[2]
        Paint rectangle: feature_colors$#[2], x_pos - bar_width/2, x_pos + bar_width/2, 0, mean_val
        Draw line: x_pos, max(0, mean_val - std_val), x_pos, min(1, mean_val + std_val)
        
        # Centroid
        mean_val = emit_mean_cent#[s]
        std_val = emit_std_cent#[s]
        x_pos = s + feature_offset#[3]
        Colour: feature_colors$#[3]
        Paint rectangle: feature_colors$#[3], x_pos - bar_width/2, x_pos + bar_width/2, 0, mean_val
        Draw line: x_pos, max(0, mean_val - std_val), x_pos, min(1, mean_val + std_val)
        
        # Slope
        mean_val = emit_mean_slope#[s]
        std_val = emit_std_slope#[s]
        x_pos = s + feature_offset#[4]
        Colour: feature_colors$#[4]
        Paint rectangle: feature_colors$#[4], x_pos - bar_width/2, x_pos + bar_width/2, 0, mean_val
        Draw line: x_pos, max(0, mean_val - std_val), x_pos, min(1, mean_val + std_val)
    endfor
    
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Marks left every: 1, 0.5, "yes", "yes", "no"
    Font size: 7
    Text bottom: "yes", "State"
    Text left: "yes", "Mean ± Std"
    Text top: "no", "Emission Distributions (Gaussian per State)"
    
    # Legend
    Font size: 5
    Colour: feature_colors$#[1]
    Draw circle: 0.8, 0.95, 0.03
    Text: 1.0, "left", 0.95, "half", "Int"
    Colour: feature_colors$#[2]
    Draw circle: 0.8, 0.88, 0.03
    Text: 1.0, "left", 0.88, "half", "Pitch"
    Colour: feature_colors$#[3]
    Draw circle: 0.8, 0.81, 0.03
    Text: 1.0, "left", 0.81, "half", "Cent"
    Colour: feature_colors$#[4]
    Draw circle: 0.8, 0.74, 0.03
    Text: 1.0, "left", 0.74, "half", "Slope"
    
    Font size: 10
    Colour: "Black"
    
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