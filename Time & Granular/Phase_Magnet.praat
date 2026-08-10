# ============================================================
# Praat AudioTools - Phase_Magnet.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.8 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Phase Magnet - phase-aware sound hybridization. Weaves two sounds
#   together by alternating between them at phase-compatible splice
#   points. A "magnetism" parameter keeps the cursors proportionally
#   aligned.
#
# Changelog v1.8:
#   - API COMPATIBILITY: the public form is unchanged byte-for-byte.
#   - FIX: Same-slope zero crossing is distinct again. v1.7 routed modes 1
#     and 2 through the same nearest-zero-crossing code and never checked
#     slope direction. v1.8 first uses the native nearest-ZC query, then
#     performs a bounded local probe only when a same-slope crossing is
#     required.
#   - FIX: processing copies are explicitly zero-based. Get nearest zero
#     crossing expects a time inside the Sound time domain; v1.7 converted
#     sample indices to times as if both inputs started at 0.
#   - FIX: Formula(part) source addressing now uses the output sample column
#     directly. v1.7 converted sample-centre time back to an index with
#     round(), which could shift reads by one sample.
#   - FIX: anchor acceptance uses Patience_ms and the requested segment
#     bounds instead of a hard-coded +2000-sample allowance whose duration
#     changed with sample rate.
#   - HARDENING: explicit validation for percentage/timing parameters and an
#     output-capacity guard prevent invalid custom settings or pathological
#     backward cursor corrections from writing past the preallocated buffer.
#   - COMPATIBILITY: output remains mono (channel 1 of each source), as in
#     v1.7; source names and output naming are unchanged.
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
# 1. Validate selection & parameters
# ------------------------------------------------------------------------------
if numberOfSelected ("Sound") <> 2
    exitScript: "Please select exactly two Sound objects, then run Phase Magnet."
endif

if crossfade_length_ms < 0
    exitScript: "Crossfade length must be >= 0 ms."
endif
if patience_ms < 0
    exitScript: "Patience must be >= 0 ms."
endif
if magnetism < 0 or magnetism > 100
    exitScript: "Magnetism must be between 0 and 100."
endif
if randomness < 0 or randomness > 100
    exitScript: "Randomness must be between 0 and 100."
endif
if minimum_segment_ms <= 0 or maximum_segment_ms <= 0
    exitScript: "Segment durations must be > 0 ms."
endif
if maximum_segment_ms < minimum_segment_ms
    exitScript: "Maximum segment duration must be >= minimum segment duration."
endif

id_A = selected ("Sound", 1)
id_B = selected ("Sound", 2)

selectObject: id_A
name_A$ = selected$ ("Sound")
sr_A = Get sampling frequency

selectObject: id_B
name_B$ = selected$ ("Sound")
sr_B = Get sampling frequency

writeInfoLine: "=== Phase Magnet v1.8 ==="

# ------------------------------------------------------------------------------
# 2. Create zero-based mono processing copies and handle sample-rate mismatch
# ------------------------------------------------------------------------------
# v1.7 already processed row/channel 1 only. Keep that output contract, but
# make it explicit and zero-based so sample-index <-> time conversions are valid.
selectObject: id_A
id_A_work = Extract one channel: 1
Shift times to: "start time", 0
selectObject: id_A_work
n_A = Get number of samples
dur_A = Get total duration

selectObject: id_B
id_B_mono = Extract one channel: 1
Shift times to: "start time", 0

resampled_B = 0
id_B_work = id_B_mono
if sr_A <> sr_B
    appendInfoLine: "  Note: resampling B from ", sr_B, " to ", sr_A, " Hz..."
    selectObject: id_B_mono
    id_B_work = Resample: sr_A, 50
    removeObject: id_B_mono
    resampled_B = 1
endif

selectObject: id_B_work
n_B = Get number of samples
dur_B = Get total duration

sr = sr_A
dt = 1.0 / sr

# Convert parameters to samples. Keep the historical minimum two-sample fade.
xf_len = max (2, round (crossfade_length_ms / 1000.0 * sr))
patience = max (1, round (patience_ms / 1000.0 * sr))
min_seg = max (xf_len + 2, round (minimum_segment_ms / 1000.0 * sr))
max_seg = max (min_seg + 2, round (maximum_segment_ms / 1000.0 * sr))
magnetism_f = magnetism / 100.0

if n_A <= xf_len + max_seg or n_B <= xf_len + max_seg
    removeObject: id_A_work, id_B_work
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

while pos_A <= n_A - xf_len - max_seg and pos_B <= n_B - xf_len - max_seg and out_pos <= out_n - max_seg - xf_len - 2
    
    if active = 1
        curr_src = id_A_work
        curr_n   = n_A
        curr_pos = pos_A
        other_src = id_B_work
        other_n   = n_B
        other_pos = pos_B
    else
        curr_src = id_B_work
        curr_n   = n_B
        curr_pos = pos_B
        other_src = id_A_work
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
            anchor_lo = max (curr_pos + min_seg, curr_pos + target_seg - patience)
            anchor_hi = min (curr_n - xf_len - 2, curr_pos + max_seg, curr_pos + target_seg + patience)
            if cand >= anchor_lo and cand <= anchor_hi
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
    steady_first = out_pos
    steady_last = out_pos + seg_len - 1
    t_start = (steady_first - 1) * dt
    t_end   = steady_last * dt
    
    selectObject: out_id
    Formula (part): t_start, t_end, 1, 1, "object[" + string$(curr_src) + ", 1, " + string$(curr_pos - out_pos) + " + col]"

    # --------------------------------------------------------------------------
    # NATIVE VECTOR OPERATION 2: Compiled C++ Crossfade Blend
    # --------------------------------------------------------------------------
    xf_first = out_pos + seg_len
    xf_last = xf_first + xf_len - 1
    xf_t_start = (xf_first - 1) * dt
    xf_t_end   = xf_last * dt
    
    # Equal-power crossfade. u runs from 0 to (xf_len-1)/xf_len across the
    # written samples, reaching exactly 1 at the last crossfade sample.
    u_expr$ = "((col - " + string$(xf_first) + ") / " + string$(xf_len - 1) + ")"
    formula_str$ = "sqrt(max(0, 1 - " + u_expr$ + ")) * object[" + string$(curr_src) + ", 1, " + string$(curr_pos + seg_len - xf_first) + " + col] + sqrt(max(0, " + u_expr$ + ")) * object[" + string$(other_src) + ", 1, " + string$(chosen_other_splice - xf_first) + " + col]"
    
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

# Visualization (draws the original inputs and the trimmed output)
if draw_visualization
    @drawViz
endif

removeObject: id_A_work, id_B_work

selectObject: trimmed_id
appendInfoLine: "Phase Magnet complete! Processed ", actual_samples, " samples."

if play_result
    selectObject: trimmed_id
    Play
endif

# ==============================================================================
# PROCEDURE: findSpliceFast (native zero-crossing matcher)
#   Mode 1: one native nearest-zero-crossing query.
#   Mode 2: native nearest-ZC plus bounded same-slope probing when needed.
#   Mode 3: bounded amplitude scan (no native equivalent).
#   Reads globals sr, dt, matching_mode. Returns result_sample.
# ==============================================================================
procedure findSpliceFast: .src_id, .src_n, .exp_pos, .pat, .from_amp, .from_slope, .xf_len
    .lo = max (2, .exp_pos - .pat)
    .hi = min (.src_n - .xf_len - 2, .exp_pos + .pat)

    if .lo >= .hi
        result_sample = max (2, min (.src_n - .xf_len - 2, .exp_pos))

    elsif matching_mode = 1
        # Nearest zero crossing, native and fast.
        selectObject: .src_id
        .exp_time = (.exp_pos - 1) * dt
        .zc_time = Get nearest zero crossing: 1, .exp_time
        if .zc_time = undefined
            result_sample = .exp_pos
        else
            .cand = round (.zc_time * sr) + 1
            if .cand < .lo or .cand > .hi
                result_sample = .exp_pos
            else
                result_sample = .cand
            endif
        endif

    elsif matching_mode = 2
        # Same-slope zero crossing. v1.7 accidentally made this identical to
        # mode 1. Start with the native nearest crossing, then probe locally
        # only if its crossing direction differs from the source anchor.
        .best_dist = 1e30
        .best = .exp_pos
        .found = 0
        .fallback = .exp_pos
        selectObject: .src_id
        .zc0 = Get nearest zero crossing: 1, (.exp_pos - 1) * dt
        if .zc0 <> undefined
            .cand0 = round (.zc0 * sr) + 1
            if .cand0 >= .lo and .cand0 <= .hi
                .fallback = .cand0
            endif
        endif

        # Fine probes cover +/-100 ms at 1-ms spacing; beyond that, if the
        # user requested more patience, use 10-ms probes. Each probe itself
        # uses Praat's native nearest-zero-crossing query.
        .fine_step = max (1, round (0.001 * sr))
        .fine_radius = min (.pat, round (0.100 * sr))
        .fine_n = ceiling (.fine_radius / .fine_step)

        for .q from 0 to .fine_n
            .off = .q * .fine_step
            for .sgn from -1 to 1
                if .q = 0
                    .probe_ok = (.sgn = 0)
                else
                    .probe_ok = (.sgn <> 0)
                endif
                if .probe_ok
                    .probe = .exp_pos + .sgn * .off
                    if .probe >= .lo and .probe <= .hi
                        .zc = Get nearest zero crossing: 1, (.probe - 1) * dt
                        if .zc <> undefined
                            .cand = round (.zc * sr) + 1
                            if .cand >= .lo and .cand <= .hi
                                .vL = Get value at sample number: 1, max(1, .cand - 1)
                                .vR = Get value at sample number: 1, min(.src_n, .cand + 1)
                                .slp = .vR - .vL
                                if .from_slope = 0 or (.slp > 0 and .from_slope > 0) or (.slp < 0 and .from_slope < 0)
                                    .dd = abs (.cand - .exp_pos)
                                    if .dd < .best_dist
                                        .best_dist = .dd
                                        .best = .cand
                                        .found = 1
                                    endif
                                endif
                            endif
                        endif
                    endif
                endif
            endfor
        endfor

        if .found = 0 and .pat > .fine_radius
            .coarse_step = max (1, round (0.010 * sr))
            .coarse_n = ceiling ((.pat - .fine_radius) / .coarse_step)
            for .q from 1 to .coarse_n
                .off = .fine_radius + .q * .coarse_step
                for .sgn from -1 to 1
                    if .sgn <> 0
                        .probe = .exp_pos + .sgn * .off
                        if .probe >= .lo and .probe <= .hi
                            .zc = Get nearest zero crossing: 1, (.probe - 1) * dt
                            if .zc <> undefined
                                .cand = round (.zc * sr) + 1
                                if .cand >= .lo and .cand <= .hi
                                    .vL = Get value at sample number: 1, max(1, .cand - 1)
                                    .vR = Get value at sample number: 1, min(.src_n, .cand + 1)
                                    .slp = .vR - .vL
                                    if .from_slope = 0 or (.slp > 0 and .from_slope > 0) or (.slp < 0 and .from_slope < 0)
                                        .dd = abs (.cand - .exp_pos)
                                        if .dd < .best_dist
                                            .best_dist = .dd
                                            .best = .cand
                                            .found = 1
                                        endif
                                    endif
                                endif
                            endif
                        endif
                    endif
                endfor
            endfor
        endif

        if .found
            result_sample = .best
        else
            # Preserve zero-crossing behaviour even if no matching direction
            # exists in the patience window.
            result_sample = .fallback
        endif

    else
        # Mode 3: nearest amplitude match. No native command, so scan -- but
        # keep the historical <=100-ms half-window performance bound.
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
    selectObject: id_B
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
