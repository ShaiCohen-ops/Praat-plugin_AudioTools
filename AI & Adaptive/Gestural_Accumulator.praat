# ============================================================
# Praat AudioTools - Gestural Accumulator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025) - Fast multi-track overlap
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   algorithmic composition engine that transforms a single sound into an evolving perceptual canon
#   by rigorously budgeting dissimilarity across timbral color and gestural motion.
#
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

form Compositional Canon
    comment Preset / Style:
    optionmenu Preset 1
        option Custom
        option Smooth Drift (Hide Ruptures)
        option Violent Rupture (Expose Ruptures)
        option Nervous Energy (High Motion / Glitch)
    
    comment Structural Form:
    optionmenu Pacing_curve 1
        option Linear (Steady accumulation)
        option Accelerate (Slow start -> Rush to finish)
        option Decelerate (Explosive start -> Stabilize)
    
    comment Overlap Rhetoric:
    optionmenu Overlap_mode 1
        option Hide Ruptures (Big Diff = Long Fade)
        option Expose Ruptures (Big Diff = Hard Cut)
    
    comment Parameters:
    positive N_variants 30
    positive K_steps 8
    positive Target_budget 60.0
    
    comment Timbre & Motion:
    boolean Track_motion_variance 1
    
    positive Pitch_range_st 2.0
    positive Time_stretch 0.15
    real Formant_shift_range 0.15
    positive Random_seed 1987
    boolean Skip_first 1
endform

# ==============================================================================
# 1. PRESETS
# ==============================================================================
if preset = 2 ; Smooth Drift
    pacing_curve = 1
    overlap_mode = 1 ; Hide
    track_motion_variance = 0
    pitch_range_st = 0.5
    target_budget = 40.0
elsif preset = 3 ; Violent Rupture
    pacing_curve = 2 ; Accelerate
    overlap_mode = 2 ; Expose
    track_motion_variance = 1
    pitch_range_st = 12.0
    target_budget = 120.0
elsif preset = 4 ; Nervous Energy
    pacing_curve = 3 ; Decelerate
    overlap_mode = 2 ; Expose
    track_motion_variance = 1
    pitch_range_st = 3.0
    time_stretch = 0.5 ; This causes short sounds, handled below
    target_budget = 80.0
endif

# ==============================================================================
# 2. SETUP (Stereo-Aware)
# ==============================================================================
randomseed = random_seed
user_original_id = selected("Sound")
user_name$ = selected$("Sound")
n_channels_orig = Get number of channels

# Create WORK COPY (Stereo if original is stereo)
selectObject: user_original_id
Copy: "Work_Copy_Base"
work_id = selected("Sound")

# Create a MONO version strictly for Pitch Analysis
if n_channels_orig > 1
    Convert to mono
    analysis_id = selected("Sound")
else
    Copy: "Analysis_Temp"
    analysis_id = selected("Sound")
endif

selectObject: analysis_id
noprogress To Pitch: 0.0, 75, 600
base_pitch = Get quantile: 0.0, 0.0, 0.5, "Hertz"
removeObject: selected("Pitch")
removeObject: analysis_id

if base_pitch = undefined or base_pitch < 50
    base_pitch = 150
endif

writeInfoLine: "=== Composition (v10): ", preset$, " ==="
appendInfoLine: "Channels: ", n_channels_orig
appendInfoLine: "Generating variants..."

# ==============================================================================
# 3. GENERATE VARIANTS (With Physics Safety)
# ==============================================================================
for i from 1 to n_variants
    # 1. Calculate Target Parameters
    st_shift = randomUniform(-pitch_range_st, pitch_range_st)
    target_pitch = base_pitch * (2 ^ (st_shift / 12))
    f_shift = randomUniform(1.0 - formant_shift_range, 1.0 + formant_shift_range)

    # 2. DURATION PHYSICS (The Crash Fix)
    # Check current duration
    selectObject: work_id
    current_dur = Get total duration
    
    # Calculate proposed factor
    min_stretch = 1.0 - time_stretch
    if min_stretch < 0.1
        min_stretch = 0.1
    endif
    dur_factor = randomUniform(min_stretch, 1.0 + time_stretch)
    
    # SAFETY: Ensure resulting duration is at least 0.064s (Praat Limit)
    projected_dur = current_dur * dur_factor
    if projected_dur < 0.064
        # Force factor to keep it above limit
        dur_factor = 0.07 / current_dur
    endif
    
    # 3. Process
    selectObject: work_id
    if n_channels_orig > 1
        # STEREO PATH
        Extract all channels
        ch1_id = selected("Sound", 1)
        ch2_id = selected("Sound", 2)
        
        selectObject: ch1_id
        nowarn noprogress Change gender: 75, 600, f_shift, target_pitch, 1.0, dur_factor
        var_L = selected("Sound")
        
        selectObject: ch2_id
        nowarn noprogress Change gender: 75, 600, f_shift, target_pitch, 1.0, dur_factor
        var_R = selected("Sound")
        
        selectObject: var_L
        plusObject: var_R
        Combine to stereo
        v_id'i' = selected("Sound")
        
        removeObject: ch1_id, ch2_id, var_L, var_R
    else
        # MONO PATH
        nowarn noprogress Change gender: 75, 600, f_shift, target_pitch, 1.0, dur_factor
        v_id'i' = selected("Sound")
    endif
    
    Scale peak: 0.9
endfor

# ==============================================================================
# 4. FEATURE EXTRACTION (Safety Wrapped)
# ==============================================================================
appendInfoLine: "Analyzing..."
base_dim = 13
if track_motion_variance
    total_dim = 26
else
    total_dim = 13
endif

for i from 1 to n_variants
    selectObject: v_id'i'
    
    # Temp mono for analysis
    if n_channels_orig > 1
        Convert to mono
        analyze_obj = selected("Sound")
    else
        Copy: "Temp_Analyze"
        analyze_obj = selected("Sound")
    endif
    
    # CRASH PROTECTION: Check duration before MFCC
    dur_check = Get total duration
    
    # 0.02s is minimum for default MFCC window
    if dur_check > 0.025
        # Attempt MFCC
        nocheck nowarn noprogress To MFCC: base_dim, 0.015, 0.005, 100.0, 100.0, 8000
        
        if numberOfSelected("MFCC") = 1
            mfcc_id = selected("MFCC")
            To Matrix
            mat_id = selected("Matrix")
            n_cols = Get number of columns
            
            # 1. Means
            for d from 1 to base_dim
                val = Get mean: d, d, 1, n_cols
                f'i'_'d' = val
            endfor
            
            # 2. Variance (With Safety Check)
            if track_motion_variance
                if n_cols > 1
                    for d from 1 to base_dim
                        val = Get standard deviation: d, d, 1, n_cols
                        idx = base_dim + d
                        f'i'_'idx' = val
                    endfor
                else
                    # Fallback for short sounds
                    for d from 1 to base_dim
                        idx = base_dim + d
                        f'i'_'idx' = 0
                    endfor
                endif
            endif
            removeObject: mfcc_id, mat_id
        else
            # MFCC Failed (Silent/Too short) -> Fill Zeros
            for d from 1 to total_dim
                f'i'_'d' = 0
            endfor
        endif
    else
        # Duration too short -> Fill Zeros
        for d from 1 to total_dim
            f'i'_'d' = 0
        endfor
    endif
    
    removeObject: analyze_obj
endfor

# Distance Matrix & Median
appendInfoLine: "Calculating Distances..."
count = 0
for i from 1 to n_variants
    for j from i to n_variants
        if i = j
            d'i'_'j' = 0
        else
            s = 0
            for d from 1 to total_dim
                diff = f'i'_'d' - f'j'_'d'
                s += diff * diff
            endfor
            dist = sqrt(s)
            d'i'_'j' = dist
            d'j'_'i' = dist
            count += 1
            dist_list_'count' = dist
        endif
    endfor
endfor

# Bubble sort for Median
for i from 1 to count-1
    for j from i+1 to count
        if dist_list_'j' < dist_list_'i'
            temp = dist_list_'i'
            dist_list_'i' = dist_list_'j'
            dist_list_'j' = temp
        endif
    endfor
endfor
if count > 0
    mid_idx = round(count / 2)
    global_median_dist = dist_list_'mid_idx'
else
    global_median_dist = 1.0
endif

# ==============================================================================
# 5. BUDGET-AS-SCHEDULE SELECTION
# ==============================================================================
appendInfoLine: "Selecting..."
for s from 1 to k_steps
    progress = s / k_steps
    if pacing_curve = 1 ; Linear
        sched_accum_'s' = target_budget * progress
    elsif pacing_curve = 2 ; Accelerate
        sched_accum_'s' = target_budget * (progress^2)
    elsif pacing_curve = 3 ; Decelerate
        sched_accum_'s' = target_budget * sqrt(progress)
    endif
endfor

curr = 1
used'curr' = 1
sel_idx_1 = 1
sel_count = 1
current_accum = 0

for step from 2 to k_steps
    ideal_total = sched_accum_'step'
    needed_step = ideal_total - current_accum
    
    if needed_step < 0.1
        needed_step = 0.1
    endif
    
    best_cand = 0
    best_score = 1000000
    
    for cand from 1 to n_variants
        is_used = 0
        if variableExists("used"+string$(cand))
            is_used = used'cand'
        endif
        
        if is_used = 0
            dist = d'curr'_'cand'
            score = abs(dist - needed_step)
            if score < best_score
                best_score = score
                best_cand = cand
            endif
        endif
    endfor
    
    if best_cand = 0
        goto FINISH
    endif
    
    sel_count += 1
    sel_idx_'sel_count' = best_cand
    used'best_cand' = 1
    
    actual_dist = d'curr'_'best_cand'
    sel_dist_'sel_count' = actual_dist
    current_accum += actual_dist
    curr = best_cand
endfor
label FINISH

# ==============================================================================
# 6. ASSEMBLY (Stereo-Ready)
# ==============================================================================
appendInfoLine: "Assembling..."

start_pos = 1
if skip_first and sel_count > 1
    start_pos = 2
endif

id = sel_idx_'start_pos'
selectObject: v_id'id'
Copy: "Result"
result_id = selected("Sound")

for i from start_pos+1 to sel_count
    next_idx = sel_idx_'i'
    selectObject: v_id'next_idx'
    next_dur = Get total duration
    
    step_dist = sel_dist_'i'
    rel_dist = step_dist / global_median_dist
    
    # Rhetoric Logic
    if overlap_mode = 1 ; Hide
        factor = rel_dist * 0.4 
        if factor > 0.9
            factor = 0.9
        endif
        if factor < 0.1
            factor = 0.1
        endif
    elsif overlap_mode = 2 ; Expose
        factor = 0.6 / rel_dist
        if factor > 0.9
            factor = 0.9
        endif
        if factor < 0.05
            factor = 0.05
        endif
    endif
    
    overlap_sec = next_dur * factor
    
    selectObject: result_id
    plusObject: v_id'next_idx'
    Concatenate with overlap: overlap_sec
    temp = selected("Sound")
    removeObject: result_id
    result_id = temp
endfor

selectObject: result_id
Rename: user_name$ + "_v10_" + preset$

# Cleanup
for i from 1 to n_variants
    removeObject: v_id'i'
endfor
removeObject: work_id

appendInfoLine: "Done."
Play