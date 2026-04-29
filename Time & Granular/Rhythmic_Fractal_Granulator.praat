# ============================================================
# Praat AudioTools - Rhythmic Fractal Granulator
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2025) - True overlap-add + reworked visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Extracts grains from a source sound at fractal time positions
#   (recursive binary subdivision with mirror symmetry), then
#   overlap-adds them onto a pre-allocated output buffer.
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

# === INITIALIZATION ===
clearinfo
writeInfoLine: "Granulating '", source_name$, "' (", source_ch, " ch) into Fractal..."
uid$ = string$(randomInteger(10000, 99999))

# Derived params
pivot_time = total_duration / 2
center_buffer = 0.05
jitter = 0.005
amp_decay = 0.15
seed_offset = 0.1

# Arrays for timing
max_events = 5000
event_times# = zero#(max_events)
event_gens# = zero#(max_events)

# Track parent indices too (for subdivision-diagram visualization).
# event_parents#[i] = index of the parent event that spawned event i,
# or 0 for seed/mirror events.
event_parents# = zero#(max_events)

# --- STEP 1: GENERATE LEFT HALF (FRACTAL) ---
half_dur = pivot_time - center_buffer
num_events = 1
event_times#[1] = seed_offset
event_gens#[1] = 0
event_parents#[1] = 0

for gen from 1 to generations
    shift = half_dur / (2 ^ gen)
    current_count = num_events
    for i from 1 to current_count
        parent_t = event_times#[i]
        new_t = parent_t + shift + randomUniform(-jitter, jitter)
        
        if new_t <= half_dur
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
    scan_step = (source_dur - grain_duration) / num_events
    scan_cursor = 0
endif

for i from 1 to num_events
    target_start = event_times#[i]
    gen = event_gens#[i]
    
    # A. Amplitude
    amp_factor = (1 - amp_decay) ^ gen
    
    # B. Pick source location
    if read_mode = 1
        read_start = randomUniform(0, source_dur - grain_duration)
    else
        read_start = scan_cursor
        scan_cursor = scan_cursor + scan_step
    endif
    if read_start > source_dur - grain_duration
        read_start = source_dur - grain_duration
    endif
    if read_start < 0
        read_start = 0
    endif
    read_end = read_start + grain_duration
    
    # C. Extract grain
    selectObject: source_id
    grain = Extract part: read_start, read_end, "rectangular", 1, "no"
    
    # D. Apply window + amplitude on the grain itself
    if window_shape = 1
        # Hanning bell
        nx = Get number of samples
        Formula: "self * " + string$(amp_factor) + " * (sin(pi * (col-1) / (" + string$(nx) + " - 1)))^2"
    else
        # Trapezoid plateau
        Formula: "self * " + string$(amp_factor)
        fade_dur = 0.2 * grain_duration
        Fade in: 0, 0, fade_dur, "yes"
        Fade out: 0, grain_duration - fade_dur, fade_dur, "yes"
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
    Scale peak: 0.95
endif

# --- STEP 6: VISUALIZATION ---
if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # ---- Generation colour palette (warm -> cool perceptual ramp) ----
    # Hot pink/red for the seed (gen 0), warm orange, gold, teal, cool blue
    # for late generations. High contrast adjacent steps; the most musically
    # weighted events (seeds) read as visually loudest.
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
    
    # === TITLE ===
    Select outer viewport: 0, 8, 0.05, 0.55
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Rhythmic Fractal Granulator: " + source_name$ + "##"
    
    # === PANEL 1: SOURCE WAVEFORM ===
    Select outer viewport: 0, 8, 0.6, 1.55
    Select inner viewport: 0.6, 7.6, 0.7, 1.45
    selectObject: source_id
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Source"
    
    # === PANEL 2: RECURSIVE SUBDIVISION DIAGRAM ===
    # One horizontal lane per generation, top = gen 0 seed, descending.
    # Each lane shows the events at that generation as filled markers.
    # Vertical drop-lines connect each event to the nearest event one
    # generation up (its conceptual parent in the binary tree). The
    # mirror axis is drawn as a vertical line through pivot_time.
    Select outer viewport: 0, 8, 1.65, 3.95
    Select inner viewport: 0.6, 7.6, 1.75, 3.85
    
    n_lanes = generations + 1
    Axes: 0, total_duration, n_lanes, 0
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, total_duration, n_lanes, 0
    
    # Lane background bands (alternating tint for readability)
    for lane from 0 to n_lanes - 1
        if lane mod 2 = 0
            Colour: "{0.93, 0.93, 0.95}"
            Paint rectangle: "{0.93, 0.93, 0.95}", 0, total_duration, lane, lane + 1
        endif
    endfor
    
    # Mirror axis
    Colour: "{0.45, 0.45, 0.45}"
    Dotted line
    Line width: 1.5
    Draw line: pivot_time, 0, pivot_time, n_lanes
    Solid line
    Line width: 1
    Font size: 6
    Text: pivot_time, "centre", -0.15, "half", "mirror axis"
    
    # Drop-lines connecting each event to its lane-above neighbour.
    # Strategy: for each event at gen >= 1, find the nearest event at
    # gen-1 and draw a thin grey line. This is what the binary subdivision
    # actually computes (each new event lands halfway between two parents).
    Colour: "{0.75, 0.75, 0.78}"
    Line width: 1
    for i from 1 to num_events
        g = event_gens#[i]
        if g >= 1
            t = event_times#[i]
            # Find nearest event at gen - 1 (linear scan; num_events is small)
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
    
    # Event markers
    for i from 1 to num_events
        t = event_times#[i]
        g = event_gens#[i]
        @setGenColour: g
        Paint circle (mm): gen_colors$#[min(g, 7) + 1], t, g + 0.5, 1.6
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Generation (0 = seed)"
    Text bottom: "yes", "Time (s)"
    Font size: 7
    Text top: "no", "Recursive Subdivision (parents above, children below)"
    
    # Inline legend strip below this panel
    Select outer viewport: 0, 8, 4.00, 4.20
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.35, 0.35, 0.35}"
    Text: 0.01, "left", 0.5, "half", "Generation:"
    legend_x = 0.10
    legend_step = 0.085
    for g from 0 to min(generations, 7)
        @setGenColour: g
        Paint circle (mm): gen_colors$#[g + 1], legend_x + 0.005, 0.5, 1.4
        Colour: "{0.30, 0.30, 0.30}"
        Text: legend_x + 0.018, "left", 0.5, "half", string$(g)
        legend_x = legend_x + legend_step
    endfor
    Colour: "Black"
    
    # === PANEL 3: IOI LOG-HISTOGRAM ===
    # Inter-onset intervals tell you whether the fractal hierarchy is
    # still readable as discrete levels (peaks at half_dur/2^k) or has
    # collapsed into a continuum.
    Select outer viewport: 0, 4, 4.30, 5.85
    Select inner viewport: 0.55, 3.85, 4.45, 5.70
    
    # Compute IOIs (events are already sorted)
    n_iois = num_events - 1
    if n_iois > 0
        ioi# = zero#(n_iois)
        for i from 1 to n_iois
            ioi#[i] = event_times#[i + 1] - event_times#[i]
        endfor
        
        # Log10 range. Floor at 1 ms to avoid log(0).
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
        
        # Bin into 24 log-spaced bins
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
        
        # Theoretical fractal peaks: half_dur / 2^k for k=1..generations.
        # These are the IOIs you'd get with zero jitter at each generation
        # boundary. Drawing them as vertical guides shows whether the
        # histogram peaks line up with the theory.
        Colour: "{0.55, 0.70, 0.55}"
        Dotted line
        Line width: 1
        for k from 1 to generations
            theory_ioi = half_dur / (2 ^ k)
            if theory_ioi >= 10 ^ log_lo and theory_ioi <= 10 ^ log_hi
                Draw line: log10(theory_ioi), 0, log10(theory_ioi), max_bin * 1.15
            endif
        endfor
        Solid line
        
        # Histogram bars
        Colour: "{0.30, 0.45, 0.70}"
        bin_w = (log_hi - log_lo) / n_bins
        for i from 1 to n_bins
            if bins#[i] > 0
                xL = log_lo + (i - 1) * bin_w
                xR = xL + bin_w * 0.92
                Paint rectangle: "{0.30, 0.45, 0.70}", xL, xR, 0, bins#[i]
            endif
        endfor
        
        Colour: "Black"
        Draw inner box
        Font size: 6
        # Custom log-axis ticks at decade boundaries
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
                Text: tx, "centre", -max_bin * 0.06, "half", lvLabel$
            endif
        endfor
        Text left: "yes", "Count"
        Font size: 7
        Text top: "no", "IOI distribution (log time, green = theory)"
    endif
    
    # === PANEL 4: RADIAL CLOCK ===
    # Events placed on a circle; angle = time, radius = generation.
    # Mirror symmetry shows up as bilateral reflection across the
    # vertical (12 o'clock) axis.
    Select outer viewport: 4, 8, 4.30, 5.85
    Select inner viewport: 4.30, 7.80, 4.45, 5.70
    
    Axes: -1.2, 1.2, -1.2, 1.2
    Paint rectangle: "{0.97, 0.97, 0.97}", -1.2, 1.2, -1.2, 1.2
    
    # Concentric guide rings (one per generation)
    Colour: "{0.85, 0.85, 0.88}"
    Line width: 1
    for g from 0 to generations
        r = 0.25 + 0.65 * (g / max(generations, 1))
        # Draw a circle by sampling 64 points
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
    
    # Mirror axis (vertical: 12 o'clock <-> 6 o'clock)
    Colour: "{0.45, 0.45, 0.45}"
    Dotted line
    Draw line: 0, -1.1, 0, 1.1
    Solid line
    Font size: 5
    Colour: "{0.40, 0.40, 0.40}"
    Text: 0, "centre", 1.13, "half", "t = 0 / mirror axis"
    
    # Plot events
    for i from 1 to num_events
        t = event_times#[i]
        g = event_gens#[i]
        # Angle: t = 0 at 12 o'clock, going clockwise.
        # Praat draws y-up, so: angle measured from +y axis going clockwise.
        ang = 2 * pi * (t / total_duration)
        r = 0.25 + 0.65 * (g / max(generations, 1))
        cx = r * sin(ang)
        cy = r * cos(ang)
        @setGenColour: g
        Paint circle (mm): gen_colors$#[min(g, 7) + 1], cx, cy, 1.4
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Radial clock (angle = time, radius = generation)"
    
    # === PANEL 5: OUTPUT WAVEFORM ===
    Select outer viewport: 0, 8, 5.95, 6.85
    Select inner viewport: 0.6, 7.6, 6.05, 6.75
    selectObject: final_id
    Colour: "{0.30, 0.55, 0.45}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    
    # === PANEL 6: STATS BAR (AudioTools standard: grey, framed) ===
    Select outer viewport: 0, 8, 6.95, 7.30
    Select inner viewport: 0.6, 7.6, 7.00, 7.25
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
        ... + "  |  Grain: " + fixed$(grain_duration * 1000, 0) + " ms"
        ... + "  |  Window: " + window_name$
        ... + "  |  Read: " + read_name$
        ... + "  |  Total: " + fixed$(total_duration, 2) + " s"
    
    Font size: 10
    Colour: "Black"
endif

appendInfoLine: ""
appendInfoLine: "Done. Output sound: ", num_events, " events overlap-added across ", fixed$(total_duration, 2), " s."

selectObject: final_id
Play
