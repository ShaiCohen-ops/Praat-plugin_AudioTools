# ============================================================
# Praat AudioTools - Gestural_Accumulator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.2 (2026)
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
# Changelog v0.4.2:
#
#   TIER 1 (polish, audio bit-identical):
#     - Dropped 6 decorative `comment === ... ===` form rows
#       (Preset / Style / Structural Form / Overlap Rhetoric /
#       Parameters / Timbre & Motion / Output). Form: 20 rows
#       -> 14 rows.
#     - Added missing colons to all 3 optionmenus (Preset:,
#       Pacing_curve:, Overlap_mode:). Suite convention.
#     - Added presetName$ (short form, no special chars) for
#       output filename: `<input>_canon` -> `<input>_canon_<preset>`
#       so different presets produce distinct Praat object names.
#     - Visualization rewritten from custom 8x5.5 layout to suite
#       8x8:
#         Title bar (suite light) + metadata subtitle
#         Original / Canon waveform (side-by-side, headline)
#         Dissimilarity trajectory / Variant transform scatter
#           (side-by-side, signature)
#         Overlap analysis  (full width, bar chart)
#         Light-grey 3-line summary  (suite standard)
#
#   TIER 2 (real bugs, audio bit-identical):
#     - FIXED: pacing_curve$ and overlap_mode$ strings desynced
#       from numeric values after preset override. v0.4.1 had
#       presets that reassigned the NUMERIC pacing_curve and
#       overlap_mode but never updated the matching $ strings
#       (which are set by the form to the user's original choice).
#       Result: the info log and viz could display "Pacing: Linear"
#       while running with numeric pacing_curve = 2 (Accelerate)
#       under a preset. Cosmetic-only bug (audio was correct;
#       display was wrong). v0.4.2 rebuilds pacing_curve$ and
#       overlap_mode$ as SHORT strings from the final numeric
#       values immediately after the preset block.
#     - FIXED: legend panel text was drawn at unpredictable outer
#       y positions. v0.4.1 lines 651-657 set the legend's outer
#       viewport but never set Axes, so it inherited
#       `Axes: 1, sel_count, 0, max_overlap * 1.1` from the
#       overlap-analysis panel above. The Text() calls used x=1.0
#       and y=0.3 / y=-2.7 in those inherited axes, sending the
#       second text far below the legend strip (typically outer
#       y > 5.5, off the panel). v0.4.2 sets explicit
#       `Axes: 0, 1, 0, 1` before any Text() in the summary panel.
#     - FIXED: Skip-First viz edge case. v0.4.1 gated the overlap
#       analysis viz on `if sel_count > 1`, but when skip_first=1
#       and sel_count=2, start_pos=2 so the inner loop
#       `for i from start_pos+1 to sel_count` = `for 3 to 2`
#       doesn't execute (silent no-op per Praat for-loop rules),
#       leaving max_overlap at 0 and producing
#       `Axes: 1, 2, 0, 0` (degenerate y-range). v0.4.2 gates on
#       `if sel_count > start_pos` so the panel only renders
#       when there's at least one transition to display.
#
#   Audio output is bit-identical to v0.4.1 for the same seed.
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

form Compositional Canon v0.4.2
    optionmenu Preset: 1
        option Custom
        option Smooth Drift (Hide Ruptures)
        option Violent Rupture (Expose Ruptures)
        option Nervous Energy (High Motion / Glitch)
    optionmenu Pacing_curve: 1
        option Linear (Steady accumulation)
        option Accelerate (Slow start -> Rush to finish)
        option Decelerate (Explosive start -> Stabilize)
    optionmenu Overlap_mode: 1
        option Hide Ruptures (Big Diff = Long Fade)
        option Expose Ruptures (Big Diff = Hard Cut)
    positive N_variants 30
    positive K_steps 8
    positive Target_budget 60.0
    boolean Track_motion_variance 1
    positive Pitch_range_st 2.0
    positive Time_stretch 0.15
    real Formant_shift_range 0.15
    positive Random_seed 1987
    boolean Skip_first 1
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

# v0.4.2 Tier 1: short preset name for output filename + viz.
# (v0.4.1 only had preset$ which is the form's full multi-word
# string with special chars; not ideal for filenames.)
if preset = 1
    presetName$ = "Custom"
elsif preset = 2
    presetName$ = "SmoothDrift"
elsif preset = 3
    presetName$ = "ViolentRupture"
else
    presetName$ = "NervousEnergy"
endif

# v0.4.2 Tier 2 fix: rebuild pacing_curve$ and overlap_mode$ from
# the FINAL numeric values. v0.4.1 left these as the form's
# original strings, so after a preset override the displayed name
# could disagree with the actual numeric used during synthesis.
# Cosmetic-only bug (audio was correct), but the info log and viz
# stat panel showed wrong labels under presets 2-4.
if pacing_curve = 1
    pacing_curve$ = "Linear"
elsif pacing_curve = 2
    pacing_curve$ = "Accelerate"
else
    pacing_curve$ = "Decelerate"
endif

if overlap_mode = 1
    overlap_mode$ = "Hide ruptures"
else
    overlap_mode$ = "Expose ruptures"
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
# v0.4.2: output filename now includes preset.
compositeName$ = user_name$ + "_canon_" + presetName$
Rename: compositeName$
final_name$ = selected$("Sound")

# Get final duration
final_duration = Get total duration

# ==============================================================================
# 7. VISUALIZATION
# ==============================================================================

###############################################################################
# VISUALIZATION  (8 x 8 canvas, suite styling)
# Title bar (suite light) + metadata subtitle
# Panel A: Original waveform              (left half, headline)
# Panel B: Canon waveform                 (right half, headline)
# Panel C: Dissimilarity trajectory       (left half, signature)
# Panel D: Variant transform scatter      (right half, signature)
# Panel E: Overlap analysis bars          (full width)
# Panel F: Light-grey 3-line summary      (suite standard)
###############################################################################

if draw_visualization
    Erase all
    Select outer viewport: 0, 8, 0, 8
    Black
    Plain line

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##GESTURAL ACCUMULATOR##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... user_name$
        ... + "  |  " + presetName$
        ... + "  |  " + string$(n_variants) + " variants -> " + string$(sel_count) + " sel"
        ... + "  |  Pacing: " + pacing_curve$
        ... + "  |  Overlap: " + overlap_mode$

    # ----------------------------------------------------------
    # PANEL A (left): ORIGINAL WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 2.30
    Select inner viewport: 0.55, 4.00, 0.95, 2.18

    selectObject: user_original_id
    Colour: "{0.55, 0.55, 0.60}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Original waveform  (" + fixed$(original_duration, 2) + " s)"
    Font size: 6
    Text left: "yes", "Amp"

    # ----------------------------------------------------------
    # PANEL B (right): CANON WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 2.30
    Select inner viewport: 4.55, 7.75, 0.95, 2.18

    selectObject: result_id
    Colour: "{0.20, 0.50, 0.80}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Canon result  (" + fixed$(final_duration, 2) + " s,  " + fixed$(final_duration / original_duration, 1) + "x)"
    Font size: 6
    Text left: "yes", "Amp"

    # ----------------------------------------------------------
    # PANEL C (left): DISSIMILARITY TRAJECTORY
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 2.40, 4.40
    Select inner viewport: 0.55, 4.00, 2.60, 4.30

    # Scale axis to the larger of (current_accum, max scheduled value)
    max_accum = current_accum
    for s from 1 to k_steps
        if sched_accum_'s' > max_accum
            max_accum = sched_accum_'s'
        endif
    endfor
    max_accum = max_accum * 1.1
    if max_accum < 0.01
        max_accum = 0.01
    endif

    Axes: 0, sel_count, 0, max_accum
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, sel_count, 0, max_accum

    # Target schedule (dotted grey)
    Colour: "{0.65, 0.65, 0.70}"
    Dotted line
    prev_sched = 0
    for s from 1 to k_steps
        if s <= sel_count
            Draw line: s - 1, prev_sched, s, sched_accum_'s'
            prev_sched = sched_accum_'s'
        endif
    endfor
    Solid line

    # Actual trajectory (red)
    Colour: "{0.90, 0.30, 0.30}"
    Line width: 2
    accum = 0
    Draw line: 0, 0, 1, 0
    for s from 2 to sel_count
        prev_accum = accum
        accum = accum + sel_dist_'s'
        Draw line: s - 1, prev_accum, s, accum
    endfor
    Line width: 1

    # Dots at each step
    accum = 0
    for s from 1 to sel_count
        if s > 1
            accum = accum + sel_dist_'s'
        endif
        Paint circle (mm): "{0.20, 0.50, 0.80}", s, accum, 1.0
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Dissimilarity trajectory  (grey dotted = target schedule)"
    Font size: 6
    Text left: "yes", "Cumulative dist"
    Text bottom: "yes", "Step"

    # ----------------------------------------------------------
    # PANEL D (right): VARIANT TRANSFORM SCATTER
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 2.40, 4.40
    Select inner viewport: 4.55, 7.75, 2.60, 4.30

    Axes: -pitch_range_st, pitch_range_st, 1.0 - formant_shift_range, 1.0 + formant_shift_range
    Paint rectangle: "{0.97, 0.97, 0.97}",
        ... -pitch_range_st, pitch_range_st, 1.0 - formant_shift_range, 1.0 + formant_shift_range

    # Reference cross (faint)
    Colour: "{0.78, 0.78, 0.82}"
    Dotted line
    Draw line: -pitch_range_st, 1.0, pitch_range_st, 1.0
    Draw line: 0, 1.0 - formant_shift_range, 0, 1.0 + formant_shift_range
    Solid line

    # All variants in grey
    for i to n_variants
        Paint circle (mm): "{0.78, 0.78, 0.82}",
            ... variant_pitch_shift[i], variant_formant_shift[i], 0.6
    endfor

    # Selected path connections (dotted, light)
    for s from 2 to sel_count
        prev_s = s - 1
        prev_idx = sel_idx_'prev_s'
        idx = sel_idx_'s'
        Colour: "{0.55, 0.55, 0.60}"
        Dotted line
        Draw line: variant_pitch_shift[prev_idx], variant_formant_shift[prev_idx],
            ... variant_pitch_shift[idx], variant_formant_shift[idx]
        Solid line
    endfor

    # Selected path dots (colored by sequence position)
    for s from 1 to sel_count
        idx = sel_idx_'s'
        hue = (s - 1) / max(sel_count - 1, 1)
        red = 0.20 + hue * 0.70
        green = 0.50
        blue = 0.90 - hue * 0.70
        dotColor$ = "{" + fixed$(red, 2) + ", " + fixed$(green, 2) + ", " + fixed$(blue, 2) + "}"
        Paint circle (mm): dotColor$,
            ... variant_pitch_shift[idx], variant_formant_shift[idx], 1.4
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Variant space  (grey = all, blue->red = selected path)"
    Font size: 6
    Text left: "yes", "Formant"
    Text bottom: "yes", "Pitch shift (st)"

    # ----------------------------------------------------------
    # PANEL E: OVERLAP ANALYSIS  (full width)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.50, 5.60
    Select inner viewport: 0.55, 7.72, 4.65, 5.50

    # v0.4.2 fix: gate on sel_count > start_pos (not sel_count > 1).
    # v0.4.1 had `if sel_count > 1` which entered the block when
    # skip_first=1 and sel_count=2 (start_pos=2), but the inner
    # loop `for i from start_pos+1 to sel_count` was a no-op and
    # max_overlap stayed at 0, producing Axes: 1, 2, 0, 0.
    if sel_count > start_pos
        max_overlap = 0
        for i from start_pos + 1 to sel_count
            if overlap_duration[i] > max_overlap
                max_overlap = overlap_duration[i]
            endif
        endfor
        if max_overlap < 0.001
            max_overlap = 0.001
        endif

        Axes: start_pos, sel_count, 0, max_overlap * 1.1
        Paint rectangle: "{0.97, 0.97, 0.97}",
            ... start_pos, sel_count, 0, max_overlap * 1.1

        for i from start_pos + 1 to sel_count
            norm = overlap_duration[i] / max(max_overlap, 0.001)
            if overlap_mode = 1
                # Hide: long = smooth (blue)
                barColor$ = "{" + fixed$(0.30 * (1 - norm), 2) + ", "
                    ... + fixed$(0.50, 2) + ", "
                    ... + fixed$(0.90 - 0.30 * (1 - norm), 2) + "}"
            else
                # Expose: short = harsh (red)
                barColor$ = "{" + fixed$(0.90 - 0.60 * norm, 2) + ", "
                    ... + fixed$(0.30 + 0.30 * norm, 2) + ", "
                    ... + fixed$(0.30 * norm, 2) + "}"
            endif
            Paint rectangle: barColor$, i - 0.4, i + 0.4, 0, overlap_duration[i]
        endfor

        Colour: "Black"
        Line width: 1
        Draw inner box
        Font size: 7
        Text top: "no", "Transition overlaps  (color encodes overlap magnitude per " + overlap_mode$ + ")"
        Font size: 6
        Text left: "yes", "Overlap (s)"
        Text bottom: "yes", "Transition #"
    else
        # Not enough transitions to plot
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
        Font size: 7
        Colour: "{0.55, 0.55, 0.60}"
        Text: 0.5, "centre", 0.5, "half",
            ... "(no transitions to display: sel_count=" + string$(sel_count)
            ... + ", start_pos=" + string$(start_pos) + ")"
        Colour: "Black"
        Line width: 1
        Draw inner box
        Font size: 7
        Text top: "no", "Transition overlaps"
    endif

    # ----------------------------------------------------------
    # PANEL F: SUMMARY BAR  (suite standard light grey)
    # ----------------------------------------------------------
    # v0.4.2 fix: explicit Axes: 0, 1, 0, 1 BEFORE any Text().
    # v0.4.1 inherited Axes from the panel above and placed text
    # at unpredictable outer y positions.
    Select outer viewport: 0, 8, 5.70, 6.40
    Select inner viewport: 0.55, 7.72, 5.77, 6.35
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"

    if track_motion_variance
        motionLabel$ = "On"
    else
        motionLabel$ = "Off"
    endif

    Text: 0.02, "left", 0.82, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + user_name$
        ... + "  |  Variants: " + string$(n_variants) + " -> Selected: " + string$(sel_count)
        ... + "  |  Budget actual/target: " + fixed$(current_accum, 1) + " / " + fixed$(target_budget, 1)

    Text: 0.02, "left", 0.50, "half",
        ... "Pacing: " + pacing_curve$
        ... + "  |  Overlap: " + overlap_mode$
        ... + "  |  Motion variance: " + motionLabel$
        ... + "  |  Pitch range: +/-" + fixed$(pitch_range_st, 1) + " st"
        ... + "  |  Formant range: +/-" + fixed$(formant_shift_range, 2)

    Text: 0.02, "left", 0.18, "half",
        ... "Output: " + compositeName$
        ... + "  |  Dur: " + fixed$(final_duration, 2) + " s ("
        ... + fixed$(final_duration / original_duration, 2) + "x)"
        ... + "  |  Median dist: " + fixed$(global_median_dist, 2)
        ... + "  |  Seed: " + string$(random_seed)
        ... + "  |  Skip first: " + string$(skip_first)

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
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