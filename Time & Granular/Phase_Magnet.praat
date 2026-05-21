# ============================================================
# Praat AudioTools - Phase_Magnet.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.7 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Phase Magnet - phase-aware sound hybridization. Weaves two sounds
#   together by alternating between them at phase-compatible splice
#   points. A "magnetism" parameter keeps the cursors proportionally
#   aligned.
#
# Changelog v1.7:
#   - TIER 3 (performance): the real bottleneck was the splice search,
#     not the blends. The anchor scan and findSpliceFast used scalar
#     `Get value at sample number` inside loops spanning the whole
#     patience window (2*patience iterations, two reads each) -- up to
#     millions of per-sample command calls, which is what made it slow
#     despite the "linear-time" blend formulas. For the zero-crossing
#     modes (1 = Zero crossing, 2 = Same-slope ZC) both searches are now
#     a single native `Get nearest zero crossing` call, turning thousands
#     of per-sample reads into one command. Splice points are now the
#     nearest clean zero crossing to the magnetism-predicted position
#     (was the distance/slope-scored best within the window) -- still
#     click-free, audio differs slightly. Mode 3 (Nearest amplitude
#     match) has no native equivalent, so it keeps a scan but the window
#     is now bounded (<= 100 ms each side) so it cannot blow up on large
#     patience settings.
#   - TIER 2 (visualization): added a suite 8x8 visualization --
#     input A / input B waveforms, the hybridized output, and a
#     splice-source timeline (blue = A, orange = B) showing how the two
#     sources alternate over the output, plus a summary panel.
#
# Changelog v1.6:
#   - TIER 1 (polish): Added standard AudioTools Play mechanism.
#   - TIER 2 (features): Integrated stylistic presets (Glitch,
#     Ambient, Rhythmic, Chaotic) via UI override block.
#   - TIER 3 (performance): Maintained v1.4 linear-time
#     vectorized matching engine and native Praat C++ block blends.
# ============================================================

form Phase Magnet
    comment --- Presets ---
    optionmenu Preset: 1
        option Custom
        option Glitch Stutter (Fast)
        option Ambient Morph (Slow)
        option Rhythmic Alternation
        option Chaotic Scatter

    comment --- Timing ---
    real    Crossfade_length_ms   10
    real    Patience_ms          100
    integer Magnetism             80
    real    Minimum_segment_ms    50
    real    Maximum_segment_ms   500
 
    comment --- Splice mode ---
    optionmenu Matching_mode: 2
        option Zero crossing
        option Same-slope zero crossing
        option Nearest amplitude match
    
    comment --- Variation ---
    integer Randomness 20
    
    comment --- Start and alternation ---
    optionmenu Start_source: 1
        option A
        option B
    optionmenu Alternation_mode: 1
        option Strict A-B-A-B
        option Probabilistic

    comment --- Output ---
    boolean Play_result 1
    boolean Draw_visualization 1
endform

# ------------------------------------------------------------------------------
# 0. Apply Presets (Overrides UI if not "Custom")
# ------------------------------------------------------------------------------
if preset$ = "Glitch Stutter (Fast)"
    crossfade_length_ms = 2
    patience_ms         = 20
    magnetism           = 95
    minimum_segment_ms  = 10
    maximum_segment_ms  = 45
    matching_mode       = 1
    randomness          = 50
    alternation_mode    = 1
elsif preset$ = "Ambient Morph (Slow)"
    crossfade_length_ms = 150
    patience_ms         = 500
    magnetism           = 60
    minimum_segment_ms  = 400
    maximum_segment_ms  = 1200
    matching_mode       = 2
    randomness          = 10
    alternation_mode    = 2
elsif preset$ = "Rhythmic Alternation"
    crossfade_length_ms = 5
    patience_ms         = 50
    magnetism           = 100
    minimum_segment_ms  = 125
    maximum_segment_ms  = 250
    matching_mode       = 2
    randomness          = 0
    alternation_mode    = 1
elsif preset$ = "Chaotic Scatter"
    crossfade_length_ms = 15
    patience_ms         = 300
    magnetism           = 20
    minimum_segment_ms  = 20
    maximum_segment_ms  = 800
    matching_mode       = 3
    randomness          = 100
    alternation_mode    = 2
endif

# ------------------------------------------------------------------------------
# 1. Validate selection & lengths
# ------------------------------------------------------------------------------
if numberOfSelected ("Sound") <> 2
    exitScript: "Please select exactly two Sound objects, then run Phase Magnet."
endif

id_A = selected ("Sound", 1)
id_B = selected ("Sound", 2)

selectObject: id_A
name_A$ = selected$ ("Sound")
sr_A  = Get sampling frequency
n_A   = Get number of samples
dur_A = Get total duration

selectObject: id_B
name_B$ = selected$ ("Sound")
sr_B  = Get sampling frequency
n_B   = Get number of samples
dur_B = Get total duration

writeInfoLine: "=== Phase Magnet v1.7 ==="

# ------------------------------------------------------------------------------
# 2. Handle sample-rate mismatch
# ------------------------------------------------------------------------------
resampled_B = 0
id_B_work   = id_B

if sr_A <> sr_B
    appendInfoLine: "  Note: resampling B from ", sr_B, " to ", sr_A, " Hz..."
    selectObject: id_B
    id_B_work   = Resample: sr_A, 50
    resampled_B = 1
    selectObject: id_B_work
    n_B   = Get number of samples
    dur_B = Get total duration
endif

sr = sr_A
dt = 1.0 / sr

# Convert parameters to samples
xf_len   = max (2, round (crossfade_length_ms / 1000.0 * sr))
patience = max (1, round (patience_ms / 1000.0 * sr))
min_seg  = max (xf_len + 2, round (minimum_segment_ms / 1000.0 * sr))
max_seg  = max (min_seg + 2, round (maximum_segment_ms / 1000.0 * sr))
magnetism_f = magnetism / 100.0

if n_A <= xf_len + max_seg or n_B <= xf_len + max_seg
    exitScript: "One or both sounds are too short for the chosen settings."
endif

# ------------------------------------------------------------------------------
# 3. Allocate Output Buffer
# ------------------------------------------------------------------------------
out_n   = n_A + n_B
out_dur = out_n * dt
out_id  = Create Sound from formula: "tmp_phasemag", 1, 0, out_dur, sr, "0"

# ------------------------------------------------------------------------------
# 4. Instant Linear-Time Splicing Loop
# ------------------------------------------------------------------------------
pos_A   = 1
pos_B   = 1
out_pos = 1
active  = start_source
n_seg   = 0

appendInfoLine: "Phase Magnet: Rendering [", preset$, "] via native zero-crossing splicing..."

while pos_A <= n_A - xf_len - max_seg and pos_B <= n_B - xf_len - max_seg
    
    if active = 1
        curr_src = id_A
        curr_n   = n_A
        curr_pos = pos_A
        other_src = id_B_work
        other_n   = n_B
        other_pos = pos_B
    else
        curr_src = id_B_work
        curr_n   = n_B
        curr_pos = pos_B
        other_src = id_A
        other_n   = n_A
        other_pos = pos_A
    endif

    # Choose a targeted segment range
    target_seg = round(min_seg + randomUniform(0, 1) * (max_seg - min_seg))
    
    # Establish an anchor point (segment end) in the current sound.
    # v1.7: native Get nearest zero crossing instead of a per-sample scan.
    idx = curr_pos + target_seg
    found_anchor = 0
    
    selectObject: curr_src
    if matching_mode = 1 or matching_mode = 2
        anchor_time = (idx - 1) * dt
        zc_anchor = Get nearest zero crossing: 1, anchor_time
        if zc_anchor <> undefined
            cand = round (zc_anchor * sr) + 1
            anchor_hi = min (curr_n - xf_len - 2, (curr_pos + target_seg) + 2000)
            if cand >= curr_pos + min_seg and cand <= anchor_hi
                idx = cand
                found_anchor = 1
            endif
        endif
    else
        found_anchor = 1
    endif
    
    # Fallback if no clean cross point was found within the window
    if found_anchor = 0
        idx = curr_pos + target_seg
    endif

    seg_len = idx - curr_pos + 1
    
    # Capture splice event for the visualization (source of THIS segment)
    n_seg = n_seg + 1
    vizStart[n_seg] = out_pos
    vizLen[n_seg]   = seg_len
    vizSrc[n_seg]   = active
    
    # Collect properties from our chosen anchor
    v_cur = Get value at sample number: 1, idx
    if idx > 1
        v_pm1 = Get value at sample number: 1, idx - 1
    else
        v_pm1 = 0
    endif
    from_slope = v_cur - v_pm1
    from_amp = v_cur
    
    # Calculate target destination inside the alternate audio stream
    time_from = (idx - 1) * dt
    if active = 1
        ideal_tgt = round (time_from / dur_A * dur_B * sr) + 1
    else
        ideal_tgt = round (time_from / dur_B * dur_A * sr) + 1
    endif
    drift_tgt = other_pos
    
    exp_target = round (magnetism_f * ideal_tgt + (1.0 - magnetism_f) * drift_tgt)
    
    # Apply creative variation directly to the search center displacement
    if randomness > 0
        max_drift = round(randomness / 100.0 * patience)
        exp_target = exp_target + randomInteger(-max_drift, max_drift)
    endif
    exp_target = max (2, min (other_n - xf_len - 2, exp_target))
    
    # Search the alternate space exactly once per block
    @findSpliceFast: other_src, other_n, exp_target, patience, from_amp, from_slope, xf_len
    chosen_other_splice = result_sample

    # --------------------------------------------------------------------------
    # NATIVE VECTOR OPERATION 1: Copy Steady Part
    # --------------------------------------------------------------------------
    t_start = (out_pos - 1.5) * dt
    t_end   = (out_pos + seg_len - 0.5) * dt
    base_t  = (out_pos - 1) * dt
    
    selectObject: out_id
    Formula (part): t_start, t_end, 1, 1, "object[" + string$(curr_src) + ", 1, " + string$(curr_pos) + " + round((x - " + string$(base_t) + ") / " + string$(dt) + ")]"

    # --------------------------------------------------------------------------
    # NATIVE VECTOR OPERATION 2: Compiled C++ Crossfade Blend
    # --------------------------------------------------------------------------
    xf_t_start = (out_pos + seg_len - 1.5) * dt
    xf_t_end   = (out_pos + seg_len + xf_len - 0.5) * dt
    base_out_t = (out_pos + seg_len - 1) * dt
    
    formula_str$ = "sqrt(max(0, 1.0 - ((x - " + string$(base_out_t) + ") / (" + string$(xf_len * dt) + ")))) * object[" + string$(curr_src) + ", 1, " + string$(curr_pos + seg_len) + " + round((x - " + string$(base_out_t) + ") / " + string$(dt) + ")] + sqrt(max(0, ((x - " + string$(base_out_t) + ") / (" + string$(xf_len * dt) + ")))) * object[" + string$(other_src) + ", 1, " + string$(chosen_other_splice) + " + round((x - " + string$(base_out_t) + ") / " + string$(dt) + ")]"
    
    Formula (part): xf_t_start, xf_t_end, 1, 1, formula_str$

    # Advance pointer states
    if active = 1
        pos_A = curr_pos + seg_len + xf_len
        pos_B = chosen_other_splice + xf_len
    else
        pos_B = curr_pos + seg_len + xf_len
        pos_A = chosen_other_splice + xf_len
    endif
    
    out_pos = out_pos + seg_len + xf_len
    
    # Handle block alternation state shifts
    if alternation_mode = 1
        active = 3 - active
    else
        prob = (seg_len - min_seg + 1.0) / (max_seg - min_seg + 1.0)
        if prob > 1
            prob = 1
        endif
        if randomUniform (0, 1) < prob
            active = 3 - active
        endif
    endif
endwhile

# ------------------------------------------------------------------------------
# 5. Clean up and extract final output
# ------------------------------------------------------------------------------
actual_samples = out_pos - 1
actual_dur     = actual_samples * dt

selectObject: out_id
trimmed_id = Extract part: 0, actual_dur, "rectangular", 1, "no"
Rename: "PhaseMagnet_" + name_A$ + "_" + name_B$
removeObject: out_id

# Visualization (before removing the working copy of B, which it draws)
if draw_visualization
    @drawViz
endif

if resampled_B
    removeObject: id_B_work
endif

selectObject: trimmed_id
appendInfoLine: "Phase Magnet complete! Processed ", actual_samples, " samples."

if play_result
    selectObject: trimmed_id
    Play
endif

# ==============================================================================
# PROCEDURE: findSpliceFast (native zero-crossing matcher)
#   Modes 1 & 2 (zero-crossing): one Get nearest zero crossing call.
#   Mode 3 (amplitude): bounded scan (no native equivalent).
#   Reads globals sr, dt, matching_mode. Returns result_sample.
# ==============================================================================
procedure findSpliceFast: .src_id, .src_n, .exp_pos, .pat, .from_amp, .from_slope, .xf_len
    .lo = max (2, .exp_pos - .pat)
    .hi = min (.src_n - .xf_len - 2, .exp_pos + .pat)

    if .lo >= .hi
        result_sample = max (2, min (.src_n - .xf_len - 2, .exp_pos))

    elsif matching_mode = 1 or matching_mode = 2
        # Native zero-crossing lookup: nearest clean splice point to the
        # magnetism-predicted position. Replaces the per-sample scoring scan.
        selectObject: .src_id
        .exp_time = (.exp_pos - 1) * dt
        .zc_time = Get nearest zero crossing: 1, .exp_time
        if .zc_time = undefined
            result_sample = .exp_pos
        else
            result_sample = round (.zc_time * sr) + 1
            # If the nearest crossing falls outside the patience window,
            # fall back to the expected position (matches the old
            # "no candidate in window" behaviour).
            if result_sample < .lo or result_sample > .hi
                result_sample = .exp_pos
            endif
        endif

    else
        # Mode 3: nearest amplitude match. No native command, so scan -- but
        # bound the half-window to <= 100 ms so large patience values cannot
        # blow the search up.
        .cap = round (0.1 * sr)
        .ws = max (2, .exp_pos - min (.pat, .cap))
        .we = min (.src_n - .xf_len - 2, .exp_pos + min (.pat, .cap))
        .best_score = 1e30
        result_sample = .exp_pos
        selectObject: .src_id
        for .i from .ws to .we
            .v0 = Get value at sample number: 1, .i
            .v1 = Get value at sample number: 1, .i + 1
            .d = abs (.i - .exp_pos) / (.pat + 1)
            .amp_diff = abs (.v0 - .from_amp)
            .slp = .v1 - .v0
            if (.slp > 0 and .from_slope > 0) or (.slp < 0 and .from_slope < 0)
                .slope_pen = 0.0
            else
                .slope_pen = 0.2
            endif
            .score = .amp_diff + .slope_pen + 0.5 * .d
            if .score < .best_score
                .best_score = .score
                result_sample = .i
            endif
        endfor
    endif
endproc
# ==============================================================================
# PROCEDURE: drawViz  (suite 8 x 8 visualization)
#   Title bar + metadata
#   Input A / Input B waveforms (headline pair)
#   Hybridized output waveform (full width)
#   Splice-source timeline (full width, signature: blue = A, orange = B)
#   Light-grey summary
# ==============================================================================
procedure drawViz
    if matching_mode = 1
        .modeName$ = "Zero crossing"
    elsif matching_mode = 2
        .modeName$ = "Same-slope ZC"
    else
        .modeName$ = "Amplitude match"
    endif

    .nA = 0
    .nB = 0
    for .k from 1 to n_seg
        if vizSrc[.k] = 1
            .nA = .nA + 1
        else
            .nB = .nB + 1
        endif
    endfor

    Erase all
    Select outer viewport: 0, 8, 0, 8
    Black
    Plain line

    # ---- TITLE BAR ----
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##PHASE MAGNET##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... name_A$ + " + " + name_B$
        ... + "  |  " + preset$
        ... + "  |  magnetism " + string$(magnetism) + "%"
        ... + "  |  " + .modeName$
        ... + "  |  " + string$(n_seg) + " splices"

    # ---- INPUT A (left) ----
    Select outer viewport: 0, 4.2, 0.75, 2.30
    Select inner viewport: 0.55, 4.00, 0.95, 2.18
    selectObject: id_A
    Colour: "{0.20, 0.45, 0.80}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Source A: " + name_A$
    Font size: 6
    Text left: "yes", "Amp"

    # ---- INPUT B (right) ----
    Select outer viewport: 4.2, 8, 0.75, 2.30
    Select inner viewport: 4.55, 7.75, 0.95, 2.18
    selectObject: id_B_work
    Colour: "{0.90, 0.55, 0.20}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Source B: " + name_B$
    Font size: 6
    Text left: "yes", "Amp"

    # ---- OUTPUT WAVEFORM (full width) ----
    Select outer viewport: 0, 8, 2.40, 3.70
    Select inner viewport: 0.55, 7.75, 2.58, 3.58
    selectObject: trimmed_id
    Colour: "{0.30, 0.30, 0.35}"
    Draw: 0, actual_dur, 0, 0, "no", "Curve"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Hybridized output  (" + fixed$(actual_dur, 2) + " s)"
    Font size: 6
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"

    # ---- SPLICE-SOURCE TIMELINE (full width, signature) ----
    Select outer viewport: 0, 8, 3.80, 4.80
    Select inner viewport: 0.55, 7.75, 3.98, 4.68
    Axes: 0, actual_dur, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, actual_dur, 0, 1
    for .k from 1 to n_seg
        .ts = (vizStart[.k] - 1) * dt
        .te = (vizStart[.k] + vizLen[.k] - 1) * dt
        if vizSrc[.k] = 1
            .col$ = "{0.20, 0.45, 0.80}"
        else
            .col$ = "{0.90, 0.55, 0.20}"
        endif
        Paint rectangle: .col$, .ts, .te, 0.08, 0.92
    endfor
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Splice-source timeline  (blue = A, orange = B)"
    Font size: 6
    Text bottom: "yes", "Output time (s)"

    # ---- SUMMARY BAR (suite light grey) ----
    Select outer viewport: 0, 8, 4.90, 5.60
    Select inner viewport: 0.55, 7.75, 4.97, 5.54
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + preset$ + "##"
        ... + "  A: " + name_A$ + "  +  B: " + name_B$
        ... + "  |  match: " + .modeName$
        ... + "  |  magnetism " + string$(magnetism) + "%"
        ... + "  |  randomness " + string$(randomness) + "%"
    Text: 0.02, "left", 0.28, "half",
        ... "Splices: " + string$(n_seg)
        ... + "  (A " + string$(.nA) + " / B " + string$(.nB) + ")"
        ... + "  |  crossfade " + fixed$(crossfade_length_ms, 0) + " ms"
        ... + "  |  segment " + fixed$(minimum_segment_ms, 0) + "-" + fixed$(maximum_segment_ms, 0) + " ms"
        ... + "  |  out " + fixed$(actual_dur, 2) + " s"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endproc
