# ============================================================
# Praat AudioTools - Rhythmic Fractal Granulator
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5.1 (2026) - visualization QA alignment
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Extracts grains from a source sound at fractal time positions
#   (recursive binary subdivision with mirror symmetry), then
#   overlap-adds them onto a pre-allocated output buffer.
#
# Changelog v0.5.1:
#   - VISUALIZATION ONLY: preserves the existing recursive tree, IOI histogram,
#     and radial clock rather than replacing the script's distinctive visual identity.
#   - Fixes title/axis/legend collisions and gives every panel explicit headroom.
#   - Makes the radial clock physically circular by using an explicit square inner viewport.
#   - Source and Output now share one amplitude scale and use aligned explicit left labels.
#   - Source names are display-sanitized so underscores do not become Praat subscripts.
#   - Generation colour remains the only semantic colour encoding; IOI histogram/theory
#     and Output are neutral, avoiding reuse of generation colours for unrelated meanings.
#   - Adds real time marks where useful, adapts event marker size to event density, and
#     labels the clamped final generation colour as 7+ when generations exceed the palette.
#
# Changelog v0.5:
#   - API COMPATIBILITY: public form fields, order, types and defaults are
#     unchanged; output prefix remains Fractal_Granular_.
#   - CRITICAL FIX: source reads are now zero-based internally. v0.4 computed
#     read_start in 0..duration but extracted directly from the original Sound,
#     which fails or reads the wrong region when the source xmin is non-zero.
#   - Grain duration is internally clamped to the available source duration and
#     to at least two samples, preventing negative random/scan ranges and the
#     Hanning nx-1 denominator from becoming zero.
#   - Sequential Scan now spans the entire legal source-start range: the last
#     event reaches source_duration-grain_duration (num_events-1 denominator).
#     v0.4 divided by num_events and never reached the end.
#   - Fractal generation is capacity-guarded (max 5000 events) and generation
#     jitter is limited to 45% of the local subdivision shift, so deep custom
#     generations cannot reverse child/parent ordering when shift < jitter.
#   - Fixed short-output geometry: center buffer and seed offset scale down when
#     Total_duration is very short instead of creating a seed outside the
#     available left half.
#   - Plateau (Trapezoid) is now genuinely trapezoidal with linear attack and
#     release. v0.4 used Praat Fade in/out, whose ramps are raised cosine.
#   - Peak normalization is silent-safe.
#
# Changelog v0.4:
#   - Fix (correctness): replaced sequential silence+grain
#     concatenation with true overlap-add into a pre-allocated
#     output Sound. v0.3 silently dropped negative gaps and
#     concatenated grains back-to-back, so any time grains
#     were closer than grain_duration they drifted right and
#     the rhythm stopped matching the fractal. The default
#     preset (gen 5, grain 0.1 s) hit this constantly. Now
#     each grain is added at its target sample range via
#     Formula (part); overlap is handled correctly.
#   - Fix: source sample rate is read with
#     Get sampling frequency (the correct Praat command).
#     v0.3 used Get sample rate, which is not standard and
#     would error on most Praat builds.
#   - Visualization: replaced the redundant timing-diagram +
#     impulse-timeline pair with three panels that actually
#     show what's interesting about a fractal granulator:
#       * Recursive subdivision diagram — one row per
#         generation, parents connected to children with
#         drop-lines, mirror axis marked. This is the
#         canonical way to draw a binary fractal time tree.
#       * IOI log-histogram — inter-onset intervals on a
#         log axis. A clean fractal shows evenly spaced
#         peaks (one per generation level); jitter widens
#         them. Tells you whether the rhythm is still
#         hierarchical or has collapsed to a cloud.
#       * Radial clock view — events on a circle, radial
#         distance = generation, mirror symmetry visible
#         across the vertical diameter.
#   - Visualization: replaced the near-monochromatic blue
#     ramp with a warm->cool perceptual ramp. Gen 0 (the
#     seed events) is now warm/saturated; later generations
#     cool toward blue. This matches the amplitude decay
#     and makes the most musically important events the
#     most visually prominent.
# Changelog v0.3:
#   - Multi-track overlap (claimed; not actually implemented).
#   - Generation-based visualization.
# ============================================================

# --- CHECK SELECTION ---
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object to use as the source!"
endif
source_id = selected("Sound")
source_dur = Get total duration
source_sr = Get sampling frequency
source_ch = Get number of channels
source_t0 = Get start time
source_t1 = Get end time
source_name$ = selected$("Sound")

# --- FORM ---
form Fractal Granulator Settings
    comment --- Presets ---
    optionmenu Preset 1
        option Custom
        option Dense Texture (short grains, many generations)
        option Sparse Rhythmic (long grains, few generations)
        option Glitchy (very short grains, high generations)
        option Ambient Cloud (medium grains, medium generations)
        option Percussive (short grains, low generations)
    
    comment --- Output Structure ---
    real Total_duration_(s) 4.0
    real Grain_duration_(s) 0.1
    integer Generations 5
    
    comment --- Grain Envelope ---
    choice Window_shape 2
        button Bell (Hanning)
        button Plateau (Trapezoid)
    
    comment --- Source Reading ---
    choice Read_mode 1
        button Random Offset
        button Sequential Scan
    
    comment --- Output ---
    boolean Stereo yes
    boolean Normalize yes
    boolean Draw_visualization yes
endform

# === APPLY PRESET ===
if preset = 2
    total_duration = 6.0
    grain_duration = 0.05
    generations = 6
    window_shape = 1
    read_mode = 1
elsif preset = 3
    total_duration = 8.0
    grain_duration = 0.2
    generations = 3
    window_shape = 2
    read_mode = 2
elsif preset = 4
    total_duration = 3.0
    grain_duration = 0.02
    generations = 7
    window_shape = 1
    read_mode = 1
elsif preset = 5
    total_duration = 10.0
    grain_duration = 0.15
    generations = 4
    window_shape = 1
    read_mode = 1
elsif preset = 6
    total_duration = 4.0
    grain_duration = 0.08
    generations = 3
    window_shape = 2
    read_mode = 2
endif

# === INTERNAL VALIDATION / DOMAIN-SAFE SOURCE ===
if total_duration <= 0
    exitScript: "Total duration must be > 0 s"
endif
if grain_duration <= 0
    exitScript: "Grain duration must be > 0 s"
endif
if generations < 0
    exitScript: "Generations must be >= 0"
endif

# max_events=5000 below supports at most 2^(11+1)=4096 events in the
# worst-case full binary tree after mirroring. Guard before array writes.
if generations > 11
    exitScript: "Generations > 11 can exceed the 5000-event safety limit"
endif

source_sample_period = 1 / source_sr
if source_dur < 2 * source_sample_period
    exitScript: "Source is too short: at least two samples are required"
endif

effective_grain_duration = grain_duration
if effective_grain_duration > source_dur
    effective_grain_duration = source_dur
endif
if effective_grain_duration < 2 * source_sample_period
    effective_grain_duration = 2 * source_sample_period
endif
if effective_grain_duration > source_dur
    effective_grain_duration = source_dur
endif

# The synthesis code uses 0..duration source coordinates. Make that true
# without modifying the user's original Sound.
createdSourceWork = 0
if abs(source_t0) > 1e-12
    selectObject: source_id
    source_work = Extract part: source_t0, source_t1, "rectangular", 1, "no"
    Rename: "rfg_source_zero"
    createdSourceWork = 1
else
    source_work = source_id
endif

# === INITIALIZATION ===
clearinfo
writeInfoLine: "Granulating '", source_name$, "' (", source_ch, " ch) into Fractal..."
if abs(effective_grain_duration - grain_duration) > 1e-12
    appendInfoLine: "NOTE: effective grain duration clamped to ", fixed$(effective_grain_duration, 6), " s for this source."
endif
uid$ = string$(randomInteger(10000, 99999))

# Derived params
pivot_time = total_duration / 2
# Preserve the historical 50 ms / 100 ms values for normal renders, but
# scale them down safely for very short custom durations.
center_buffer = min(0.05, total_duration * 0.10)
jitter = 0.005
amp_decay = 0.15

half_dur = pivot_time - center_buffer
seed_offset = min(0.1, half_dur * 0.25)
if seed_offset < 0
    seed_offset = 0
endif

# Arrays for timing
max_events = 5000
event_times# = zero#(max_events)
event_gens# = zero#(max_events)

# Track parent indices too (for subdivision-diagram visualization).
# event_parents#[i] = index of the parent event that spawned event i,
# or 0 for seed/mirror events.
event_parents# = zero#(max_events)

# --- STEP 1: GENERATE LEFT HALF (FRACTAL) ---
num_events = 1
event_times#[1] = seed_offset
event_gens#[1] = 0
event_parents#[1] = 0

for gen from 1 to generations
    shift = half_dur / (2 ^ gen)
    gen_jitter = min(jitter, shift * 0.45)
    current_count = num_events
    for i from 1 to current_count
        parent_t = event_times#[i]
        new_t = parent_t + shift + randomUniform(-gen_jitter, gen_jitter)
        
        if new_t <= half_dur
            if num_events >= max_events
                exitScript: "Fractal event limit exceeded (5000)"
            endif
            num_events = num_events + 1
            event_times#[num_events] = new_t
            event_gens#[num_events] = gen
            event_parents#[num_events] = i
        endif
    endfor
endfor

# Snapshot left-half count BEFORE mirror (used by viz to mark mirror axis)
left_count = num_events

# --- STEP 2: MIRROR TO RIGHT ---
for i from 1 to left_count
    t_left = event_times#[i]
    gen = event_gens#[i]
    t_right = total_duration - t_left
    
    if num_events >= max_events
        exitScript: "Fractal event limit exceeded while mirroring (5000)"
    endif
    num_events = num_events + 1
    event_times#[num_events] = t_right
    event_gens#[num_events] = gen
    event_parents#[num_events] = 0
endfor

# --- STEP 3: SORT TIMINGS (carrying gens + parents along) ---
# Note: parent indices become stale after sorting (they pointed into the
# pre-sort array). The subdivision diagram doesn't need post-sort parent
# links — it builds its own per-generation index. We keep event_parents#
# only conceptually; nothing reads it after this point.
for i from 1 to num_events - 1
    for j from i + 1 to num_events
        if event_times#[j] < event_times#[i]
            temp_t = event_times#[i]
            event_times#[i] = event_times#[j]
            event_times#[j] = temp_t
            
            temp_g = event_gens#[i]
            event_gens#[i] = event_gens#[j]
            event_gens#[j] = temp_g
        endif
    endfor
endfor

appendInfoLine: "Generated ", num_events, " fractal events (", left_count, " + ", left_count, " mirrored)"

# --- STEP 4: SYNTHESIS — TRUE OVERLAP-ADD ---
appendInfoLine: "Synthesizing with overlap-add..."

# Pre-allocate the full output buffer (silence).
output_id = Create Sound from formula: "fractal_out", source_ch, 0, total_duration, source_sr, "0"
out_ns = Get number of samples

if read_mode = 2
    if num_events > 1
        scan_step = (source_dur - effective_grain_duration) / (num_events - 1)
    else
        scan_step = 0
    endif
    scan_cursor = 0
endif

for i from 1 to num_events
    target_start = event_times#[i]
    gen = event_gens#[i]
    
    # A. Amplitude
    amp_factor = (1 - amp_decay) ^ gen
    
    # B. Pick source location
    if read_mode = 1
        read_start = randomUniform(0, source_dur - effective_grain_duration)
    else
        read_start = scan_cursor
        scan_cursor = scan_cursor + scan_step
    endif
    if read_start > source_dur - effective_grain_duration
        read_start = source_dur - effective_grain_duration
    endif
    if read_start < 0
        read_start = 0
    endif
    read_end = read_start + effective_grain_duration
    
    # C. Extract grain from the zero-based internal source copy.
    selectObject: source_work
    grain = Extract part: read_start, read_end, "rectangular", 1, "no"
    
    # D. Apply window + amplitude on the grain itself
    if window_shape = 1
        # Hanning bell (effective grain is guaranteed to contain >=2 samples).
        nx = Get number of samples
        Formula: "self * " + string$(amp_factor) + " * (sin(pi * (col-1) / (" + string$(nx) + " - 1)))^2"
    else
        # True trapezoid: linear 20% attack, 60% plateau, linear 20% release.
        # Praat Fade in/out is raised-cosine, so implement the label literally.
        fade_dur = 0.2 * effective_grain_duration
        grain_end = effective_grain_duration
        Formula: ~ if x < fade_dur then self * amp_factor * x / fade_dur
            ... else if x > grain_end - fade_dur then self * amp_factor * (grain_end - x) / fade_dur
            ... else self * amp_factor fi fi
    endif
    
    # E. Overlap-add into the output buffer.
    # Compute target sample range, clip to buffer bounds, then use
    # Formula (part) so Praat only scans the destination samples that
    # actually receive grain data — not the whole output.
    selectObject: grain
    grain_ns = Get number of samples

    # Target start sample on the output (1-indexed)
    s1 = round(target_start * source_sr) + 1
    if s1 < 1
        s1 = 1
    endif
    s2 = s1 + grain_ns - 1
    if s2 > out_ns
        s2 = out_ns
    endif
    
    if s2 >= s1
        # Sample-offset between output column and grain column.
        # output[col] += grain[col - s_off]   where  s_off = s1 - 1
        s_off = s1 - 1
        
        # Convert sample range to time range for Formula (part) bounds
        t_lo = (s1 - 1) / source_sr
        t_hi = s2 / source_sr
        
        selectObject: output_id
        Formula (part): t_lo, t_hi, 1, source_ch,
            ... "self + object[" + string$(grain) + ", row, col - " + string$(s_off) + "]"
    endif
    
    removeObject: grain
endfor

# --- STEP 5: POST-PROCESS ---
selectObject: output_id
Rename: "Fractal_Granular_" + uid$
final_id = output_id

# Stereo conversion if requested
if stereo and source_ch = 1
    selectObject: final_id
    Convert to stereo
    stereo_id = selected("Sound")
    removeObject: final_id
    selectObject: stereo_id
    final_id = stereo_id
endif

if normalize
    selectObject: final_id
    final_peak = Get absolute extremum: 0, 0, "Sinc70"
    if final_peak > 0
        Scale peak: 0.95
    endif
endif

# --- STEP 6: VISUALIZATION ---
if draw_visualization
    appendInfoLine: "Drawing visualization..."

    Erase all

    # Display-safe source name only. The real object name is unchanged.
    display_name$ = replace$(source_name$, "_", " ", 0)

    # Source and Output share the same amplitude scale for honest visual comparison.
    selectObject: source_id
    source_plot_peak = Get absolute extremum: 0, 0, "Sinc70"
    selectObject: final_id
    output_plot_peak = Get absolute extremum: 0, 0, "Sinc70"
    shared_amp = max(source_plot_peak, output_plot_peak) * 1.08
    if shared_amp <= 0
        shared_amp = 1
    endif

    # ---- Generation colour palette (warm -> cool perceptual ramp) ----
    # Colour has one semantic meaning in this visualization: generation.
    gen_colors$# = {
        ... "{0.85, 0.20, 0.35}",
        ... "{0.95, 0.50, 0.20}",
        ... "{0.92, 0.75, 0.20}",
        ... "{0.45, 0.75, 0.45}",
        ... "{0.25, 0.60, 0.75}",
        ... "{0.30, 0.40, 0.75}",
        ... "{0.45, 0.40, 0.65}",
        ... "{0.55, 0.50, 0.65}"}

    procedure setGenColour: .g
        if .g < 0
            .g = 0
        endif
        if .g > 7
            .g = 7
        endif
        Colour: gen_colors$#[.g + 1]
    endproc

    # Physical marker size adapts to density while retaining a readable floor.
    if num_events <= 128
        event_marker_mm = 1.60
    elsif num_events <= 300
        event_marker_mm = 1.25
    elsif num_events <= 700
        event_marker_mm = 0.95
    else
        event_marker_mm = 0.70
    endif
    radial_marker_mm = max(0.70, event_marker_mm * 0.90)

    # === TITLE ===
    Select outer viewport: 0, 8, 0.03, 0.38
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Rhythmic Fractal Granulator: " + display_name$ + "##"

    # === PANEL 1: SOURCE WAVEFORM ===
    Select outer viewport: 0, 8, 0.45, 1.28
    Select inner viewport: 0.62, 7.75, 0.53, 1.17
    selectObject: source_id
    Colour: "{0.62, 0.62, 0.62}"
    Draw: 0, 0, -shared_amp, shared_amp, "no", "Curve"
    Select outer viewport: 0, 8, 0.45, 1.28
    Select inner viewport: 0.62, 7.75, 0.53, 1.17
    Axes: source_t0, source_t1, -shared_amp, shared_amp
    Colour: "Black"
    Draw inner box
    Font size: 10
    Colour: "{0.45, 0.45, 0.45}"
    source_label_x = source_t0 - 0.04920 * (source_t1 - source_t0)
    Text special: source_label_x, "centre", 0, "half", "Times", 6, "90", "Source"

    # === PANEL 2: RECURSIVE SUBDIVISION DIAGRAM ===
    Select outer viewport: 0, 8, 1.38, 3.88
    Select inner viewport: 0.62, 7.75, 1.57, 3.57

    n_lanes = generations + 1
    Axes: 0, total_duration, n_lanes, 0
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, total_duration, n_lanes, 0

    for lane from 0 to n_lanes - 1
        if lane mod 2 = 0
            Paint rectangle: "{0.93, 0.93, 0.95}", 0, total_duration, lane, lane + 1
        endif
    endfor

    Colour: "{0.45, 0.45, 0.45}"
    Dotted line
    Line width: 1.2
    Draw line: pivot_time, 0, pivot_time, n_lanes
    Solid line
    Line width: 1
    Font size: 5
    Text: pivot_time, "centre", 0.18, "half", "mirror axis"

    Colour: "{0.75, 0.75, 0.78}"
    Line width: 0.8
    for i from 1 to num_events
        g = event_gens#[i]
        if g >= 1
            t = event_times#[i]
            best_dt = total_duration + 1
            best_t = t
            for j from 1 to num_events
                if event_gens#[j] = g - 1
                    dt = abs(event_times#[j] - t)
                    if dt < best_dt
                        best_dt = dt
                        best_t = event_times#[j]
                    endif
                endif
            endfor
            Draw line: best_t, g - 1 + 0.5, t, g + 0.5
        endif
    endfor
    Line width: 1

    for i from 1 to num_events
        t = event_times#[i]
        g = event_gens#[i]
        @setGenColour: g
        Paint circle (mm): gen_colors$#[min(g, 7) + 1], t, g + 0.5, event_marker_mm
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Generation (0 = seed)"
    Marks bottom: 5, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    Font size: 7
    Text top: "yes", "Recursive Subdivision (parents above, children below)"

    # Dedicated legend band. It does not share space with the time-axis label.
    Select outer viewport: 0, 8, 3.93, 4.18
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.35, 0.35, 0.35}"
    Text: 0.01, "left", 0.5, "half", "Generation:"
    legend_x = 0.10
    legend_step = 0.085
    for g from 0 to min(generations, 7)
        @setGenColour: g
        Paint circle (mm): gen_colors$#[g + 1], legend_x + 0.005, 0.5, 1.25
        Colour: "{0.30, 0.30, 0.30}"
        if generations > 7 and g = 7
            gen_label$ = "7+"
        else
            gen_label$ = string$(g)
        endif
        Text: legend_x + 0.018, "left", 0.5, "half", gen_label$
        legend_x = legend_x + legend_step
    endfor
    Colour: "Black"

    # === PANEL 3: IOI LOG-HISTOGRAM ===
    Select outer viewport: 0, 4, 4.28, 5.88
    Select inner viewport: 0.62, 3.82, 4.47, 5.70

    n_iois = num_events - 1
    if n_iois > 0
        ioi# = zero#(n_iois)
        for i from 1 to n_iois
            ioi#[i] = event_times#[i + 1] - event_times#[i]
        endfor

        ioi_min = 0.001
        for i from 1 to n_iois
            if ioi#[i] > 0 and (ioi_min = 0.001 or ioi#[i] < ioi_min)
                ioi_min = ioi#[i]
            endif
        endfor
        ioi_max = 0.001
        for i from 1 to n_iois
            if ioi#[i] > ioi_max
                ioi_max = ioi#[i]
            endif
        endfor
        if ioi_min < 0.001
            ioi_min = 0.001
        endif
        if ioi_max < ioi_min * 2
            ioi_max = ioi_min * 2
        endif

        log_lo = log10(ioi_min) - 0.15
        log_hi = log10(ioi_max) + 0.15

        n_bins = 24
        bins# = zero#(n_bins)
        for i from 1 to n_iois
            if ioi#[i] > 0
                lv = log10(ioi#[i])
                bidx = floor((lv - log_lo) / (log_hi - log_lo) * n_bins) + 1
                if bidx >= 1 and bidx <= n_bins
                    bins#[bidx] = bins#[bidx] + 1
                endif
            endif
        endfor
        max_bin = 1
        for i from 1 to n_bins
            if bins#[i] > max_bin
                max_bin = bins#[i]
            endif
        endfor

        Axes: log_lo, log_hi, 0, max_bin * 1.15
        Paint rectangle: "{0.97, 0.97, 0.97}", log_lo, log_hi, 0, max_bin * 1.15

        # Theory is line style, not a second semantic colour.
        Colour: "{0.66, 0.66, 0.68}"
        Dotted line
        Line width: 1
        for k from 1 to generations
            theory_ioi = half_dur / (2 ^ k)
            if theory_ioi >= 10 ^ log_lo and theory_ioi <= 10 ^ log_hi
                Draw line: log10(theory_ioi), 0, log10(theory_ioi), max_bin * 1.15
            endif
        endfor
        Solid line

        # Neutral bars preserve generation colours for generation only.
        for i from 1 to n_bins
            if bins#[i] > 0
                xL = log_lo + (i - 1) * (log_hi - log_lo) / n_bins
                xR = xL + ((log_hi - log_lo) / n_bins) * 0.92
                Paint rectangle: "{0.42, 0.42, 0.45}", xL, xR, 0, bins#[i]
            endif
        endfor

        Colour: "Black"
        Draw inner box
        Font size: 6
        for lv from -3 to 1
            tx = lv
            if tx >= log_lo and tx <= log_hi
                lvLabel$ = ""
                if lv = -3
                    lvLabel$ = "1 ms"
                elsif lv = -2
                    lvLabel$ = "10 ms"
                elsif lv = -1
                    lvLabel$ = "100 ms"
                elsif lv = 0
                    lvLabel$ = "1 s"
                elsif lv = 1
                    lvLabel$ = "10 s"
                endif
                Text: tx, "centre", -max_bin * 0.07, "half", lvLabel$
            endif
        endfor
        Marks left: 3, "yes", "yes", "no"
        Text left: "yes", "Count"
        Font size: 7
        Text top: "yes", "IOI distribution (log time; dotted = theory)"
    endif

    # === PANEL 4: RADIAL CLOCK ===
    # Explicitly square inner viewport: circles stay circles in physical Picture space.
    Select outer viewport: 4, 8, 4.28, 5.88
    Select inner viewport: 5.31, 6.69, 4.43, 5.81

    Axes: -1.2, 1.2, -1.2, 1.2
    Paint rectangle: "{0.97, 0.97, 0.97}", -1.2, 1.2, -1.2, 1.2

    Colour: "{0.85, 0.85, 0.88}"
    Line width: 0.8
    for g from 0 to generations
        r = 0.25 + 0.65 * (g / max(generations, 1))
        prev_x = r
        prev_y = 0
        for k from 1 to 64
            ang = 2 * pi * k / 64
            cx = r * cos(ang)
            cy = r * sin(ang)
            Draw line: prev_x, prev_y, cx, cy
            prev_x = cx
            prev_y = cy
        endfor
    endfor

    Colour: "{0.45, 0.45, 0.45}"
    Dotted line
    Draw line: 0, -1.08, 0, 1.08
    Solid line
    Font size: 5
    Text: 0, "centre", 1.05, "half", "mirror axis"

    for i from 1 to num_events
        t = event_times#[i]
        g = event_gens#[i]
        ang = 2 * pi * (t / total_duration)
        r = 0.25 + 0.65 * (g / max(generations, 1))
        cx = r * sin(ang)
        cy = r * cos(ang)
        @setGenColour: g
        Paint circle (mm): gen_colors$#[min(g, 7) + 1], cx, cy, radial_marker_mm
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "yes", "Radial clock (angle = time, radius = generation)"

    # === PANEL 5: OUTPUT WAVEFORM ===
    Select outer viewport: 0, 8, 5.98, 6.88
    Select inner viewport: 0.62, 7.75, 6.11, 6.72
    selectObject: final_id
    Colour: "{0.34, 0.34, 0.36}"
    Draw: 0, 0, -shared_amp, shared_amp, "no", "Curve"
    Select outer viewport: 0, 8, 5.98, 6.88
    Select inner viewport: 0.62, 7.75, 6.11, 6.72
    Axes: 0, total_duration, -shared_amp, shared_amp
    Colour: "Black"
    Draw inner box
    Font size: 10
    Colour: "{0.45, 0.45, 0.45}"
    output_label_x = -0.04920 * total_duration
    Text special: output_label_x, "centre", 0, "half", "Times", 6, "90", "Output"
    Font size: 6
    Colour: "Black"
    Marks bottom: 5, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"

    # === PANEL 6: SUMMARY ===
    Select outer viewport: 0, 8, 7.00, 7.42
    Select inner viewport: 0.30, 7.80, 7.06, 7.36
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    if window_shape = 1
        window_name$ = "Bell (Hanning)"
    else
        window_name$ = "Plateau (Trapezoid)"
    endif
    if read_mode = 1
        read_name$ = "Random"
    else
        read_name$ = "Sequential"
    endif

    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.5, "centre", 0.5, "half",
        ... "Events: " + string$(num_events)
        ... + " (" + string$(left_count) + " + " + string$(left_count) + " mirrored)"
        ... + "  |  Generations: " + string$(generations)
        ... + "  |  Grain: " + fixed$(effective_grain_duration * 1000, 0) + " ms"
        ... + "  |  Window: " + window_name$
        ... + "  |  Read: " + read_name$
        ... + "  |  Total: " + fixed$(total_duration, 2) + " s"

    Font size: 10
    Colour: "Black"
endif

appendInfoLine: ""
appendInfoLine: "Done. Output sound: ", num_events, " events overlap-added across ", fixed$(total_duration, 2), " s."

if createdSourceWork = 1
    removeObject: source_work
endif

selectObject: final_id
Play
