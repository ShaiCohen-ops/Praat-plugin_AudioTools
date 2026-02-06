# ============================================================
# Praat AudioTools - Gestural_Accumulator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.1 (2025) - Debugged & Patched
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Gestural Accumulator - algorithmic composition engine that
#   transforms a single sound into an evolving perceptual canon
#   by rigorously budgeting dissimilarity across timbral color
#   and gestural motion. Creates variants with pitch/formant/
#   duration shifts, then selects a path through timbral space
#   following a dissimilarity budget schedule.
#
# Changelog v0.4.1:
#   - FIXED: Variable substitution syntax error in visualization
#   - FIXED: Array index out of bounds when 'Skip First' is active
#   - FIXED: Praat crash caused by overlapping short sounds > 100%
#
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

form Compositional Canon
    comment === Preset / Style ===
    optionmenu Preset 1
        option Custom
        option Smooth Drift (Hide Ruptures)
        option Violent Rupture (Expose Ruptures)
        option Nervous Energy (High Motion / Glitch)
    
    comment === Structural Form ===
    optionmenu Pacing_curve 1
        option Linear (Steady accumulation)
        option Accelerate (Slow start -> Rush to finish)
        option Decelerate (Explosive start -> Stabilize)
    
    comment === Overlap Rhetoric ===
    optionmenu Overlap_mode 1
        option Hide Ruptures (Big Diff = Long Fade)
        option Expose Ruptures (Big Diff = Hard Cut)
    
    comment === Parameters ===
    positive N_variants 30
    positive K_steps 8
    positive Target_budget 60.0
    
    comment === Timbre & Motion ===
    boolean Track_motion_variance 1
    
    positive Pitch_range_st 2.0
    positive Time_stretch 0.15
    real Formant_shift_range 0.15
    positive Random_seed 1987
    boolean Skip_first 1
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ==============================================================================
# 1. PRESETS
# ==============================================================================
if preset = 2
    # Smooth Drift
    pacing_curve = 1
    overlap_mode = 1
    track_motion_variance = 0
    pitch_range_st = 0.5
    target_budget = 40.0
elsif preset = 3
    # Violent Rupture
    pacing_curve = 2
    overlap_mode = 2
    track_motion_variance = 1
    pitch_range_st = 12.0
    target_budget = 120.0
elsif preset = 4
    # Nervous Energy
    pacing_curve = 3
    overlap_mode = 2
    track_motion_variance = 1
    pitch_range_st = 3.0
    time_stretch = 0.5
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

# Store original duration for viz
selectObject: user_original_id
original_duration = Get total duration

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

writeInfoLine: "=== Gestural Accumulator: ", preset$, " ==="
appendInfoLine: "Original: ", user_name$
appendInfoLine: "Channels: ", n_channels_orig
appendInfoLine: "Base pitch: ", fixed$(base_pitch, 1), " Hz"
appendInfoLine: ""
appendInfoLine: "Generating ", n_variants, " variants..."

# ==============================================================================
# 3. GENERATE VARIANTS (With Physics Safety)
# ==============================================================================
for i from 1 to n_variants
    # 1. Calculate Target Parameters
    st_shift = randomUniform(-pitch_range_st, pitch_range_st)
    target_pitch = base_pitch * (2 ^ (st_shift / 12))
    f_shift = randomUniform(1.0 - formant_shift_range, 1.0 + formant_shift_range)

    # Store transform params for viz
    variant_pitch_shift[i] = st_shift
    variant_formant_shift[i] = f_shift

    # 2. DURATION PHYSICS (The Crash Fix)
    selectObject: work_id
    current_dur = Get total duration
    
    min_stretch = 1.0 - time_stretch
    if min_stretch < 0.1
        min_stretch = 0.1
    endif
    dur_factor = randomUniform(min_stretch, 1.0 + time_stretch)
    
    # SAFETY: Ensure resulting duration is at least 0.064s (Praat Limit)
    projected_dur = current_dur * dur_factor
    if projected_dur < 0.064
         dur_factor = 0.07 / current_dur
    endif
    
    variant_duration_factor[i] = dur_factor
    
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

appendInfoLine: "  Variants created"

# ==============================================================================
# 4. FEATURE EXTRACTION (Safety Wrapped)
# ==============================================================================
appendInfoLine: "Analyzing timbral features..."
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
    
    if dur_check > 0.025
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
                    for d from 1 to base_dim
                        idx = base_dim + d
                        f'i'_'idx' = 0
                    endfor
                endif
            endif
            removeObject: mfcc_id, mat_id
        else
            for d from 1 to total_dim
                f'i'_'d' = 0
            endfor
        endif
    else
        for d from 1 to total_dim
            f'i'_'d' = 0
        endfor
    endif
    
    removeObject: analyze_obj
endfor

appendInfoLine: "  Feature extraction complete"

# Distance Matrix & Median
appendInfoLine: "Calculating pairwise distances..."
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

appendInfoLine: "  Median pairwise distance: ", fixed$(global_median_dist, 2)

# ==============================================================================
# 5. BUDGET-AS-SCHEDULE SELECTION
# ==============================================================================
appendInfoLine: ""
appendInfoLine: "Selecting path through variant space..."
appendInfoLine: "  Pacing: ", pacing_curve$
appendInfoLine: "  Target budget: ", target_budget

for s from 1 to k_steps
    progress = s / k_steps
    if pacing_curve = 1
        # Linear
        sched_accum_'s' = target_budget * progress
    elsif pacing_curve = 2
        # Accelerate
        sched_accum_'s' = target_budget * (progress^2)
    elsif pacing_curve = 3
        # Decelerate
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

appendInfoLine: "  Selected ", sel_count, " variants"
appendInfoLine: "  Actual cumulative distance: ", fixed$(current_accum, 2)

# ==============================================================================
# 6. ASSEMBLY (Stereo-Ready)
# ==============================================================================
appendInfoLine: ""
appendInfoLine: "Assembling canon..."

start_pos = 1
if skip_first and sel_count > 1
    start_pos = 2
endif

id = sel_idx_'start_pos'
selectObject: v_id'id'
Copy: "Result"
result_id = selected("Sound")

# Track overlaps for visualization
for i from start_pos+1 to sel_count
    next_idx = sel_idx_'i'
    selectObject: v_id'next_idx'
    next_dur = Get total duration
    
    step_dist = sel_dist_'i'
    rel_dist = step_dist / global_median_dist
    
    # Rhetoric Logic
    if overlap_mode = 1
        # Hide: Big distance = long fade
        factor = rel_dist * 0.4 
        if factor > 0.9
            factor = 0.9
        endif
        if factor < 0.1
            factor = 0.1
        endif
    elsif overlap_mode = 2
        # Expose: Big distance = hard cut
        factor = 0.6 / rel_dist
        if factor > 0.9
            factor = 0.9
        endif
        if factor < 0.05
            factor = 0.05
        endif
    endif
    
    overlap_sec = next_dur * factor
    
    # === CRASH FIX: Protect against impossible overlap ===
    selectObject: result_id
    current_canon_dur = Get total duration
    
    # Cap overlap to 95% of the shortest involved sound segment
    limit_dur = min(current_canon_dur, next_dur)
    
    if overlap_sec > limit_dur * 0.95
        overlap_sec = limit_dur * 0.95
    endif
    # ===================================================

    overlap_duration[i] = overlap_sec
    overlap_factor[i] = factor
    
    selectObject: result_id
    plusObject: v_id'next_idx'
    Concatenate with overlap: overlap_sec
    temp = selected("Sound")
    removeObject: result_id
    result_id = temp
endfor

selectObject: result_id
Rename: user_name$ + "_canon"
final_name$ = selected$("Sound")

# Get final duration
final_duration = Get total duration

# ==============================================================================
# 7. VISUALIZATION
# ==============================================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 1, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Gestural Accumulator: " + preset$
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.6, 0.7, 1.3
    selectObject: user_original_id
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Select outer viewport: 0.1, 8, 0.5, 1.4
    Text left: "yes", "Original"
    
    # Result waveform (Canon)
    Select outer viewport: 0, 8, 1.5, 2.3
    Select inner viewport: 0.6, 7.6, 1.6, 2.2
    selectObject: result_id
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Canon Result"
    Text bottom: "yes", "Time (s)"
    
    # Dissimilarity Trajectory
    Select outer viewport: 0, 4, 2.5, 4.0
    Select inner viewport: 0.6, 3.6, 2.6, 3.9
    
    # Calculate max for scaling
    max_accum = current_accum * 1.1
    
    Axes: 0, sel_count, 0, max_accum
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, sel_count, 0, max_accum
    
    # Draw target schedule
    Colour: "{0.8, 0.8, 0.8}"
    Dotted line
    prev_sched = 0
    for s from 1 to k_steps
        if s <= sel_count
            Draw line: s - 1, prev_sched, s, sched_accum_'s'
            prev_sched = sched_accum_'s'
        endif
    endfor
    Solid line
    
    # Draw actual trajectory
    Colour: "{0.9, 0.3, 0.3}"
    Line width: 2
    accum = 0
    Draw line: 0, 0, 1, 0
    for s from 2 to sel_count
        prev_accum = accum
        accum = accum + sel_dist_'s'
        Draw line: s - 1, prev_accum, s, accum
    endfor
    Line width: 1
    
    # Mark points
    accum = 0
    for s from 1 to sel_count
        if s > 1
            accum = accum + sel_dist_'s'
        endif
        Paint circle (mm): "{0.2, 0.5, 0.8}", s, accum, 1.0
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Cumulative Distance"
    Text bottom: "yes", "Selection Step"
    
    Select outer viewport: 0, 4, 2.4, 2.5
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 2.0, "centre", 0.5, "half", "Gray = Target | Red = Actual Path"
    
    # Variant Transform Space (Pitch vs Formant)
    Select outer viewport: 4, 8, 2.5, 4.0
    Select inner viewport: 4.6, 7.6, 2.6, 3.9
    
    Axes: -pitch_range_st, pitch_range_st, 1.0 - formant_shift_range, 1.0 + formant_shift_range
    Paint rectangle: "{0.97, 0.97, 0.97}", -pitch_range_st, pitch_range_st, 1.0 - formant_shift_range, 1.0 + formant_shift_range
    
    # Draw all variants in gray
    for i to n_variants
        Paint circle (mm): "{0.8, 0.8, 0.8}", variant_pitch_shift[i], variant_formant_shift[i], 0.6
    endfor
    
    # Draw selected path in color
    for s from 1 to sel_count
        idx = sel_idx_'s'
        # Color by position in sequence
        hue = (s - 1) / max(sel_count - 1, 1)
        red = 0.2 + hue * 0.7
        green = 0.5
        blue = 0.9 - hue * 0.7
        
        dotColor$ = "{" + fixed$(red, 2) + ", " + fixed$(green, 2) + ", " + fixed$(blue, 2) + "}"
        Paint circle (mm): dotColor$, variant_pitch_shift[idx], variant_formant_shift[idx], 1.2
        
        # Draw connection lines
        if s > 1
            # === FIXED: Variable substitution syntax ===
            prev_s = s - 1
            prev_idx = sel_idx_'prev_s'
            
            Colour: "{0.6, 0.6, 0.6}"
            Dotted line
            Draw line: variant_pitch_shift[prev_idx], variant_formant_shift[prev_idx], variant_pitch_shift[idx], variant_formant_shift[idx]
            Solid line
        endif
    endfor
    
    # Reference lines
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: -pitch_range_st, 1.0, pitch_range_st, 1.0
    Draw line: 0, 1.0 - formant_shift_range, 0, 1.0 + formant_shift_range
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Formant Shift"
    Text bottom: "yes", "Pitch Shift (st)"
    
    Select outer viewport: 4, 8, 2.4, 2.5
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 6.0, "centre", 0.5, "half", "Gray = All variants | Colored = Selected path"
    
    # Overlap Analysis
    Select outer viewport: 0, 8, 4.1, 5.0
    Select inner viewport: 0.6, 7.6, 4.2, 4.9
    
    if sel_count > 1
        max_overlap = 0
        # === FIXED: Use 'start_pos + 1' instead of hardcoded 2 ===
        for i from start_pos + 1 to sel_count
            if overlap_duration[i] > max_overlap
                max_overlap = overlap_duration[i]
            endif
        endfor
        
        Axes: 1, sel_count, 0, max_overlap * 1.1
        Paint rectangle: "{0.97, 0.97, 0.97}", 1, sel_count, 0, max_overlap * 1.1
        
        # Draw overlap bars
        # === FIXED: Use 'start_pos + 1' instead of hardcoded 2 ===
        for i from start_pos + 1 to sel_count
            # Color by overlap amount
            norm = overlap_duration[i] / max(max_overlap, 0.001)
            
            if overlap_mode = 1
                # Hide mode: long = smooth (blue)
                barColor$ = "{" + fixed$(0.3 * (1 - norm), 2) + ", " + fixed$(0.5, 2) + ", " + fixed$(0.9 - 0.3 * (1 - norm), 2) + "}"
            else
                # Expose mode: short = harsh (red)
                barColor$ = "{" + fixed$(0.9 - 0.6 * norm, 2) + ", " + fixed$(0.3 + 0.3 * norm, 2) + ", " + fixed$(0.3 * norm, 2) + "}"
            endif
            
            Paint rectangle: barColor$, i - 0.4, i + 0.4, 0, overlap_duration[i]
        endfor
        
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Overlap (s)"
        Text bottom: "yes", "Transition #"
    endif
    
    # Legend and Statistics
    Select outer viewport: 0, 8, 5.1, 5.5
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 1.0, "left", 0.3, "half", "Variants: " + string$(n_variants) + " → Selected: " + string$(sel_count) + " | Budget: " + fixed$(current_accum, 1) + "/" + fixed$(target_budget, 1)
    Text: 1.0, "left", -2.7, "half", "Pacing: " + pacing_curve$ + " | Overlap: " + overlap_mode$ + " | Motion track: " + string$(track_motion_variance)
    
    Font size: 10
    Colour: "Black"
endif

# ==============================================================================
# 8. CLEANUP AND FINALIZE
# ==============================================================================

# Cleanup
for i from 1 to n_variants
    removeObject: v_id'i'
endfor
removeObject: work_id

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", final_name$
appendInfoLine: "Duration: ", fixed$(final_duration, 2), " s (original: ", fixed$(original_duration, 2), " s)"
appendInfoLine: "Expansion factor: ", fixed$(final_duration / original_duration, 2), "x"

# === Play ===
if play_result
    appendInfoLine: ""
    appendInfoLine: "Playing result..."
    selectObject: result_id
    Play
endif

selectObject: result_id