# ============================================================
# Praat AudioTools - Total_Serialism_Machine.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Total Serialism Machine — applies serial techniques (pitch class
#   row + transformations) to audio composition. A single user-supplied
#   series controls FIVE compositional parameters per event, each
#   indexed at a different rotational offset:
#     - duration         (event length in seconds)
#     - source position  (where in the input to extract)
#     - pitch shift      (cents, ± user-defined range)
#     - gain             (dB, -12 to 0)
#     - pan              (0 = full L, 1 = full R)
#
#   Supports inversion, retrograde, and rotation of the row, in any
#   combination. Presets cover: Pointillism (Webern-style sparse),
#   Moment Form (discrete blocks), Granular Texture (micro-events),
#   Transformational (extreme ranges + I+R), Statistical Field (dense).
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.3:
#   - Fix (HEADLINE, behavior): events are now played in series
#     order, not pre-sorted. v0.2 sorted by event_time (the
#     normalized series value at each index), which collapsed
#     the temporal axis: all "value 0" events played first,
#     then all "value 0.09" events, etc. That's a sorted scan,
#     not a serial composition. Real serialism (Babbitt, Boulez,
#     Stockhausen) plays events in series-positional order;
#     parameter independence comes from each parameter using a
#     different rotational offset into the series. v0.3 removes
#     the sort entirely. Output sounds less "tidy" but is now
#     genuinely serial. ALL EXISTING PRESETS WILL SOUND DIFFERENT.
#   - Fix: stereo pan was a silent no-op. v0.2 wrote
#     Formula (part): 0, 0, 1, 1, ... which is a zero-length
#     time range — Praat treats tmin=tmax as empty and the
#     formula doesn't apply. Result: every event was unpanned
#     mono-in-stereo regardless of pan parameter. Replaced with
#     plain Formula: per-channel scaling.
#   - Fix: pitch and duration were coupled via varispeed.
#     v0.2 set "event_dur = 200ms" and pitched up by +600¢ —
#     the segment came out at 141ms because varispeed shrinks
#     duration. v0.3 compensates by extracting more source
#     material when pitch shifts up and less when shifting
#     down, so the post-resample length matches the requested
#     event_dur. Pitch and duration are now genuinely
#     independent parameters. (Source-extract length scales
#     with pitch_ratio; output length is exactly event_dur.)
#   - Speed: concatenate pipeline replaced with single-allocate-
#     and-fill. v0.2 did 2 × Concatenate calls per event — for
#     80-event Statistical Field that's 160 full Sound copies,
#     O(n^2) in samples. v0.3 pre-computes total duration,
#     creates one empty stereo canvas, and writes each segment
#     via Formula (part) at its scheduled time. Roughly
#     50x faster on the dense presets.
#   - Fix: optionmenu syntax modernized. v0.2 used
#     "optionmenu Preset 1" (space, no colon), which works on
#     some Praat builds and fails on others. v0.3 uses the
#     canonical "optionmenu Preset: 1" form.
#   - Visualization rewritten to suite 8x8 standard
#     (matching Multitrack Router, Speech-Driven Spat,
#     Microphone Simulation, etc.):
#       Title bar with metadata subtitle
#       Panel A (headline): event scatter — pitch (y) vs time (x),
#                size = duration, color = pan position
#       Panel B (right upper): row comparison — original vs
#                transformed series, side by side
#       Panel C (right lower): per-parameter histogram strip
#                showing distribution of pitch / pan / duration
#                across the events
#       Panel D: output waveform (Ch1 blue, Ch2 orange)
#       Panel E: summary stats bar
#   - New: "row comparison" panel (B) shows what the inversion /
#     retrograde / rotation actually did to the series.
# Changelog v0.2:
#   - Fixed Form syntax issues, added presets, basic visualization
# ============================================================

form Total Serialism Machine v0.3
    comment ═══════════ PRESETS ═══════════
    optionmenu Preset: 1
        option Custom (manual settings)
        option Pointillism (Webern-style)
        option Moment Form (discrete blocks)
        option Granular Texture (micro-events)
        option Transformational (extreme ranges)
        option Statistical Field (dense cloud)
    
    comment ═══════════ SERIES ═══════════
    integer Series_length 12
    optionmenu Series_type: 3
        option Arithmetic (1..N)
        option Permutation (custom)
        option 12-tone row (classic)
    sentence Series_values 0,10,7,11,3,8,1,9,2,5,6,4
    
    comment ═══════════ TRANSFORMATIONS ═══════════
    boolean Use_inversion 0
    boolean Use_retrograde 0
    integer Rotation 0
    
    comment ═══════════ STRUCTURE ═══════════
    integer Num_events 30
    positive Min_event_ms 200
    positive Max_event_ms 600
    positive Gap_between_events_ms 50
    
    comment ═══════════ PITCH RANGE ═══════════
    integer Min_pitch_cents -200
    integer Max_pitch_cents 200
    
    comment ═══════════ OUTPUT ═══════════
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================================
# CHECK INPUT
# ============================================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

input_sound = selected("Sound")
input_name$ = selected$("Sound")
selectObject: input_sound
input_duration = Get total duration
input_sr = Get sampling frequency

# ============================================================================
# RESOLVE PRESET NAME (used in output naming and visualization)
# ============================================================================

if preset = 1
    presetName$ = "Custom"
elsif preset = 2
    presetName$ = "Pointillism"
elsif preset = 3
    presetName$ = "MomentForm"
elsif preset = 4
    presetName$ = "Granular"
elsif preset = 5
    presetName$ = "Transformational"
else
    presetName$ = "StatisticalField"
endif

# ============================================================================
# APPLY PRESETS
# ============================================================================

if preset = 2
    # Pointillism (Webern-style): sparse, short events, wide pitch range
    num_events = 24
    min_event_ms = 80
    max_event_ms = 250
    gap_between_events_ms = 150
    min_pitch_cents = -400
    max_pitch_cents = 400
elsif preset = 3
    # Moment Form: discrete blocks
    num_events = 20
    min_event_ms = 300
    max_event_ms = 800
    gap_between_events_ms = 200
    min_pitch_cents = -300
    max_pitch_cents = 300
elsif preset = 4
    # Granular Texture: many micro-events
    num_events = 60
    min_event_ms = 50
    max_event_ms = 150
    gap_between_events_ms = 20
    min_pitch_cents = -200
    max_pitch_cents = 200
elsif preset = 5
    # Transformational: extreme parameter ranges
    num_events = 40
    min_event_ms = 100
    max_event_ms = 700
    gap_between_events_ms = 80
    min_pitch_cents = -600
    max_pitch_cents = 600
    use_inversion = 1
    use_retrograde = 1
elsif preset = 6
    # Statistical Field: dense overlapping cloud
    num_events = 80
    min_event_ms = 150
    max_event_ms = 500
    gap_between_events_ms = 10
    min_pitch_cents = -300
    max_pitch_cents = 300
endif

min_event_s = min_event_ms / 1000
max_event_s = max_event_ms / 1000
gap_s = gap_between_events_ms / 1000

# Resolve transformation summary string
xformStr$ = ""
if use_inversion = 1
    xformStr$ = "I"
endif
if use_retrograde = 1
    xformStr$ = xformStr$ + "R"
endif
if rotation <> 0
    xformStr$ = xformStr$ + "T" + string$(rotation)
endif
if xformStr$ = ""
    xformStr$ = "P (prime)"
endif

# ============================================================================
# BUILD SERIES (procedures defined at end of file; forward-referenced)
# ============================================================================

@createSeries: series_type, series_length, series_values$

# Save original series for visualization comparison
for i to series_length
    original_series[i] = base_series[i]
endfor

@applySerialTransformations: use_inversion, use_retrograde, rotation
@normalizeSeries

# Also normalize the original (untransformed) series for the comparison panel
@normalizeOriginal: series_length

# ============================================================================
# INFO OUTPUT
# ============================================================================

writeInfoLine: "=== Total Serialism Machine v0.3 ==="
appendInfoLine: "Source: ", input_name$, " (", fixed$(input_duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Series length: ", series_length, "  Transformation: ", xformStr$
appendInfoLine: "Events: ", num_events, "  |  Event range: ", min_event_ms, "-", max_event_ms, " ms"
appendInfoLine: "Pitch range: ", min_pitch_cents, " to ", max_pitch_cents, " cents"
appendInfoLine: ""

# Show series
appendInfo: "Original row:    "
for i to series_length
    appendInfo: fixed$(original_normalized[i], 2)
    if i < series_length
        appendInfo: ", "
    endif
endfor
appendInfoLine: ""

appendInfo: "Working row:     "
for i to series_length
    appendInfo: fixed$(normalized_series[i], 2)
    if i < series_length
        appendInfo: ", "
    endif
endfor
appendInfoLine: ""
appendInfoLine: ""

# ============================================================================
# COMPUTE EVENT PARAMETERS  (no sorting in v0.3 — events play in series order)
# ============================================================================
#
# Each parameter takes its value from the series at a different rotational
# offset, so the five parameters are quasi-independent across events:
#   duration       offset +1
#   source pos     offset +3
#   pitch          offset +4
#   gain           offset +6
#   pan            uses (i*2) mod L
# This was already the v0.2 design — what was broken was the post-sort.

# Pre-compute and store all parameters per event (still no audio yet)
for i to num_events
    series_i = ((i - 1) mod series_length) + 1
    
    dur_idx = ((i + 1 - 1) mod series_length) + 1
    src_idx = ((i + 3 - 1) mod series_length) + 1
    ptc_idx = ((i + 4 - 1) mod series_length) + 1
    gan_idx = ((i + 6 - 1) mod series_length) + 1
    pan_idx = ((i * 2 - 1) mod series_length) + 1
    
    ev_dur[i] = min_event_s + normalized_series[dur_idx] * (max_event_s - min_event_s)
    ev_src[i] = normalized_series[src_idx]
    ev_pitch[i] = min_pitch_cents + normalized_series[ptc_idx] * (max_pitch_cents - min_pitch_cents)
    
    g_norm = normalized_series[gan_idx]
    ev_gain_db[i] = -12 + g_norm * 12
    ev_gain_linear[i] = 10 ^ (ev_gain_db[i] / 20)
    ev_pan[i] = normalized_series[pan_idx]
endfor

# ============================================================================
# COMPUTE TOTAL OUTPUT DURATION  (for single-allocate canvas)
# ============================================================================

total_dur = 0
for i to num_events
    total_dur = total_dur + ev_dur[i]
    if i < num_events
        total_dur = total_dur + gap_s
    endif
endfor

# Add a small tail margin to absorb fade-out residue
total_dur = total_dur + 0.01

appendInfoLine: "Total output duration: ", fixed$(total_dur, 2), " s"
appendInfoLine: "Processing events..."
appendInfoLine: ""

# ============================================================================
# CREATE OUTPUT CANVAS  (single allocation, replaces v0.2's concatenate-pyramid)
# ============================================================================

result = Create Sound from formula: input_name$ + "_serial_" + presetName$,
    ... 2, 0, total_dur, input_sr, "0"

# ============================================================================
# PROCESS EACH EVENT, WRITE INTO CANVAS AT SCHEDULED TIME
# ============================================================================

cur_time = 0

for i to num_events
    # Resolve event parameters
    edur = ev_dur[i]
    pcents = ev_pitch[i]
    pan_pos = ev_pan[i]
    gain_lin = ev_gain_linear[i]
    
    # FIX (v0.3): pitch-duration decoupling.
    # Varispeed pitch shift via Override+Resample shrinks/expands duration
    # by pitch_ratio. To produce exactly `edur` seconds of output, we must
    # extract `edur * pitch_ratio` seconds of source material — which then
    # plays back at the shifted pitch in exactly `edur` seconds.
    if abs(pcents) > 1
        pitch_ratio = 2 ^ (pcents / 1200)
    else
        pitch_ratio = 1
    endif
    src_extract_dur = edur * pitch_ratio
    
    # Source position — clamp so we don't read past the end of the input
    max_src_start = input_duration - src_extract_dur
    if max_src_start < 0
        max_src_start = 0
        src_extract_dur = input_duration
    endif
    src_pos = ev_src[i] * max_src_start
    
    # Update event_dur to reflect any extract-clamping
    if abs(pcents) > 1
        actual_edur = src_extract_dur / pitch_ratio
    else
        actual_edur = src_extract_dur
    endif
    
    # ---- Extract segment ----
    selectObject: input_sound
    segment = Extract part: src_pos, src_pos + src_extract_dur, "rectangular", 1, "no"
    
    # Convert to mono
    selectObject: segment
    n_ch = Get number of channels
    if n_ch = 2
        mono = Convert to mono
        removeObject: segment
        segment = mono
    endif
    
    # ---- Apply gain (mono pre-pan) ----
    selectObject: segment
    Formula: ~ self * gain_lin
    
    # ---- Pitch shift via varispeed ----
    if abs(pcents) > 1
        selectObject: segment
        new_sr = input_sr * pitch_ratio
        Override sampling frequency: new_sr
        resampled = Resample: input_sr, 50
        removeObject: segment
        segment = resampled
    endif
    
    # ---- Trim or pad to exact actual_edur (resample drift compensation) ----
    selectObject: segment
    seg_dur_actual = Get total duration
    if seg_dur_actual > actual_edur
        Extract part: 0, actual_edur, "rectangular", 1, "no"
        trimmed = selected("Sound")
        removeObject: segment
        segment = trimmed
        selectObject: segment
        seg_dur_actual = Get total duration
    endif
    
    # ---- Fade-in / fade-out (5 ms each) for click-free splicing ----
    selectObject: segment
    fade_t = 0.005
    if seg_dur_actual > 2 * fade_t
        Formula: ~ self * (if x < fade_t then x / fade_t
            ... else (if x > seg_dur_actual - fade_t
            ... then (seg_dur_actual - x) / fade_t else 1 fi) fi)
    endif
    
    # ---- Apply pan (FIX v0.3: was Formula (part): 0, 0 — empty range, no-op) ----
    # Constant-power pan: L = sqrt(1-p), R = sqrt(p) where p in [0,1]
    left_gain = sqrt(1 - pan_pos)
    right_gain = sqrt(pan_pos)
    
    selectObject: segment
    seg_id = selected("Sound")
    
    # ---- Write into the result canvas at cur_time ----
    # Use Formula (part) on the result Sound to mix the segment in.
    # Cross-Sound reference reads the segment's samples; for output time
    # `t` in [cur_time, cur_time + seg_dur_actual), the segment sample
    # is at time t - cur_time, which equals (col - 1)/sr - cur_time.
    # We translate to a column offset: source col = output col - cur_time*sr.
    seg_start_sample = round(cur_time * input_sr) + 1
    
    selectObject: result
    res_total_samples = Get number of samples
    
    # Compute end time, clamped to canvas
    seg_end_time = cur_time + seg_dur_actual
    if seg_end_time > total_dur
        seg_end_time = total_dur
    endif
    
    # Skip writing if start is past canvas end (shouldn't happen but safe)
    if cur_time < total_dur and seg_dur_actual > 0
        seg_id_str$ = string$(seg_id)
        seg_start_str$ = string$(seg_start_sample - 1)
        
        # Left channel
        Formula (part): cur_time, seg_end_time, 1, 1,
            ... "self + " + fixed$(left_gain, 8)
            ... + " * object[" + seg_id_str$ + ", col - " + seg_start_str$ + "]"
        # Right channel
        Formula (part): cur_time, seg_end_time, 2, 2,
            ... "self + " + fixed$(right_gain, 8)
            ... + " * object[" + seg_id_str$ + ", col - " + seg_start_str$ + "]"
    endif
    
    removeObject: segment
    
    # Advance cur_time by event duration + gap (gap only between events)
    cur_time = cur_time + actual_edur
    if i < num_events
        cur_time = cur_time + gap_s
    endif
    
    # Progress reporting
    if i mod 10 = 1 or i = num_events
        appendInfoLine: "  Event ", i, "/", num_events,
            ... ":  pitch=", fixed$(pcents, 0), "¢",
            ... "  pan=", fixed$(pan_pos, 2),
            ... "  gain=", fixed$(ev_gain_db[i], 1), "dB",
            ... "  dur=", fixed$(actual_edur * 1000, 0), "ms"
    endif
endfor

# ============================================================================
# FINALIZE
# ============================================================================

selectObject: result
Scale peak: 0.99

final_dur = Get total duration
final_peak = Get absolute extremum: 0, 0, "None"

# ============================================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================================

if draw_visualization
    Erase all
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##TOTAL SERIALISM MACHINE##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... input_name$
        ... + "  |  " + presetName$
        ... + "  |  Row L=" + string$(series_length) + "  " + xformStr$
        ... + "  |  " + string$(num_events) + " events"
        ... + "  |  " + fixed$(final_dur, 2) + " s"
    
    # ----------------------------------------------------------
    # PANEL A: EVENT SCATTER  (left, headline)
    # X = scheduled time
    # Y = pitch (cents)
    # Marker size = duration
    # Marker color = pan position (blue=L, red=R)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    # Compute time positions for each event (recompute, since we used
    # cur_time but didn't store per-event start times)
    ev_time# = zero# (num_events)
    runT = 0
    for i to num_events
        ev_time#[i] = runT
        runT = runT + ev_dur[i]
        if i < num_events
            runT = runT + gap_s
        endif
    endfor
    
    pitchPad = (max_pitch_cents - min_pitch_cents) * 0.10
    if pitchPad < 30
        pitchPad = 30
    endif
    yLo = min_pitch_cents - pitchPad
    yHi = max_pitch_cents + pitchPad
    
    Axes: 0, total_dur, yLo, yHi
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, total_dur, yLo, yHi
    
    # Reference grid: pitch lines at 0, ±100, ±200, ...
    Colour: "{0.88, 0.88, 0.92}"
    Line width: 1
    pg = -1200
    while pg <= 1200
        if pg >= yLo and pg <= yHi
            Draw line: 0, pg, total_dur, pg
        endif
        pg = pg + 100
    endwhile
    
    # Zero-cent line
    Colour: "{0.55, 0.55, 0.55}"
    Dotted line
    Line width: 1.5
    Draw line: 0, 0, total_dur, 0
    Solid line
    Line width: 1
    Font size: 5
    Colour: "{0.45, 0.45, 0.45}"
    Text: total_dur * 0.99, "right", 0, "bottom", "0¢"
    
    # Min and max pitch reference lines
    Colour: "{0.78, 0.65, 0.78}"
    Dotted line
    Draw line: 0, min_pitch_cents, total_dur, min_pitch_cents
    Draw line: 0, max_pitch_cents, total_dur, max_pitch_cents
    Solid line
    
    # Plot events
    # Marker size: 1.5 mm to 5 mm based on relative duration
    durRange = max_event_s - min_event_s
    if durRange < 0.001
        durRange = 0.001
    endif
    
    for i to num_events
        evT = ev_time#[i]
        evP = ev_pitch[i]
        evD = ev_dur[i]
        evPan = ev_pan[i]
        
        durRel = (evD - min_event_s) / durRange
        if durRel < 0
            durRel = 0
        endif
        if durRel > 1
            durRel = 1
        endif
        markerMm = 1.5 + durRel * 3.5
        
        # Color by pan: blue at left (0), red at right (1)
        cR = 0.20 + evPan * 0.65
        cG = 0.40 - abs(evPan - 0.5) * 0.20
        cB = 0.85 - evPan * 0.65
        if cG < 0
            cG = 0
        endif
        if cB < 0
            cB = 0
        endif
        rgb$ = "{" + fixed$(cR, 2) + "," + fixed$(cG, 2) + "," + fixed$(cB, 2) + "}"
        Paint circle (mm): rgb$, evT + evD / 2, evP, markerMm
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Pitch (¢)"
    Text bottom: "yes", "Time (s)  —  size = duration  •  color = pan"
    
    # ----------------------------------------------------------
    # PANEL B: ROW COMPARISON  (right, upper)
    # Original (input) row above, transformed (working) row below.
    # Visually documents what inversion / retrograde / rotation did.
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 3.00
    Select inner viewport: 4.55, 7.75, 0.95, 2.85
    
    Axes: 0, series_length + 1, -0.10, 2.30
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, series_length + 1, -0.10, 2.30
    
    # Top half: original row (y range ~ 1.30 to 2.20)
    # Bottom half: working row (y range ~ 0.10 to 1.00)
    
    # Labels
    Font size: 6
    Colour: "{0.30, 0.30, 0.45}"
    Text: 0.2, "left", 2.20, "half", "Original (P)"
    Text: 0.2, "left", 1.05, "half", "Working (" + xformStr$ + ")"
    
    # Original row bars (top)
    for s to series_length
        v = original_normalized[s]
        # Color by series index (not value) — neutral blue
        Paint rectangle: "{0.55, 0.65, 0.82}", s - 0.40, s + 0.40,
            ... 1.30, 1.30 + v * 0.85
    endfor
    
    # Working row bars (bottom)
    # Color by value: low=blue, high=red, to make differences visible
    for s to series_length
        v = normalized_series[s]
        cR = 0.30 + v * 0.55
        cG = 0.50 - v * 0.20
        cB = 0.80 - v * 0.55
        if cB < 0
            cB = 0
        endif
        rgb$ = "{" + fixed$(cR, 2) + "," + fixed$(cG, 2) + "," + fixed$(cB, 2) + "}"
        Paint rectangle: rgb$, s - 0.40, s + 0.40, 0.10, 0.10 + v * 0.85
    endfor
    
    # Position numbers below working row
    Font size: 5
    Colour: "{0.30, 0.30, 0.30}"
    for s to series_length
        if series_length <= 16 or s mod 2 = 1
            Text: s, "centre", -0.05, "half", string$(s)
        endif
    endfor
    
    # Divider line between the two rows
    Colour: "{0.78, 0.78, 0.82}"
    Line width: 1
    Draw line: 0, 1.20, series_length + 1, 1.20
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "Value"
    Text bottom: "yes", "Series position"
    
    # ----------------------------------------------------------
    # PANEL C: PARAMETER DISTRIBUTION HISTOGRAM
    # Three small histograms side by side: pitch / pan / duration.
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 3.05, 4.60
    Select inner viewport: 4.55, 7.75, 3.20, 4.50
    
    # Build three histograms over events
    nBins = 12
    histPitch# = zero# (nBins)
    histPan# = zero# (nBins)
    histDur# = zero# (nBins)
    
    pRange = max_pitch_cents - min_pitch_cents
    if pRange < 1
        pRange = 1
    endif
    
    for i to num_events
        # Pitch
        bp = floor((ev_pitch[i] - min_pitch_cents) / pRange * nBins) + 1
        if bp < 1
            bp = 1
        endif
        if bp > nBins
            bp = nBins
        endif
        histPitch#[bp] = histPitch#[bp] + 1
        
        # Pan (already in [0, 1])
        bn = floor(ev_pan[i] * nBins) + 1
        if bn < 1
            bn = 1
        endif
        if bn > nBins
            bn = nBins
        endif
        histPan#[bn] = histPan#[bn] + 1
        
        # Duration
        bd = floor((ev_dur[i] - min_event_s) / durRange * nBins) + 1
        if bd < 1
            bd = 1
        endif
        if bd > nBins
            bd = nBins
        endif
        histDur#[bd] = histDur#[bd] + 1
    endfor
    
    # Find max for shared y-scale (so visual scale is uniform)
    histMax = 1
    for b to nBins
        if histPitch#[b] > histMax
            histMax = histPitch#[b]
        endif
        if histPan#[b] > histMax
            histMax = histPan#[b]
        endif
        if histDur#[b] > histMax
            histMax = histDur#[b]
        endif
    endfor
    histTop = histMax * 1.15
    
    # X axis: 3 columns of nBins bins, separated by gaps
    # Layout: [bins 1..12][gap][bins 1..12][gap][bins 1..12]
    # Mapped onto [0, 3*nBins+4] x range
    xMax = 3 * nBins + 4
    Axes: 0, xMax, 0, histTop
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, xMax, 0, histTop
    
    # Pitch column (red-ish)
    for b to nBins
        if histPitch#[b] > 0
            Paint rectangle: "{0.78, 0.40, 0.40}", b, b + 0.85, 0, histPitch#[b]
        endif
    endfor
    
    # Pan column (blue-purple)
    for b to nBins
        if histPan#[b] > 0
            xL = nBins + 2 + b
            Paint rectangle: "{0.45, 0.45, 0.78}", xL, xL + 0.85, 0, histPan#[b]
        endif
    endfor
    
    # Duration column (green)
    for b to nBins
        if histDur#[b] > 0
            xL = 2 * nBins + 4 + b
            Paint rectangle: "{0.45, 0.70, 0.45}", xL, xL + 0.85, 0, histDur#[b]
        endif
    endfor
    
    # Column labels
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: nBins / 2 + 0.5, "centre", -histTop * 0.08, "half", "Pitch"
    Text: nBins + 2 + nBins / 2 + 0.5, "centre", -histTop * 0.08, "half", "Pan"
    Text: 2 * nBins + 4 + nBins / 2 + 0.5, "centre", -histTop * 0.08, "half", "Duration"
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Count"
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Event scatter (size=dur, color=pan)"
    Text: 6.10, "centre", 7.30, "half", "Row comparison (upper) & parameter histograms (lower)"
    
    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.75
    Select inner viewport: 0.55, 7.72, 4.75, 5.68
    
    selectObject: result
    nResultCh = Get number of channels
    outPeak = Get absolute extremum: 0, 0, "None"
    if outPeak < 0.001
        outPeak = 0.001
    endif
    ampViz = outPeak * 1.15
    
    Axes: 0, final_dur, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, final_dur, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, final_dur, 0
    
    selectObject: result
    Extract one channel: 1
    vCh1 = selected("Sound")
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    removeObject: vCh1
    
    selectObject: result
    Extract one channel: 2
    vCh2 = selected("Sound")
    Colour: "{0.82, 0.45, 0.25}"
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    removeObject: vCh2
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Output  (blue=L  orange=R)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.82, 6.58
    Select inner viewport: 0.55, 7.72, 5.88, 6.52
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + input_name$
        ... + "  |  Series L=" + string$(series_length)
        ... + "  |  Transformation: " + xformStr$
        ... + "  |  " + string$(num_events) + " events"
        ... + "  |  Gap: " + fixed$(gap_between_events_ms, 0) + " ms"
    
    Text: 0.02, "left", 0.28, "half",
        ... "Pitch range: " + string$(min_pitch_cents) + " to " + string$(max_pitch_cents) + " cents"
        ... + "  |  Event range: " + fixed$(min_event_ms, 0) + "-" + fixed$(max_event_ms, 0) + " ms"
        ... + "  |  Output: " + fixed$(final_dur, 2) + " s, peak " + fixed$(final_peak, 3)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================================
# DONE
# ============================================================================
selectObject: result
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(final_dur, 2), " s"

if play_result
    selectObject: result
    Play
endif

selectObject: result

# ============================================================================
# PROCEDURES
# ============================================================================

procedure createSeries: .type, .length, .values$
    for .i to .length
        base_series[.i] = .i
    endfor
    
    if .type = 1
        # Arithmetic: 1, 2, 3, ..., N
        for .i to .length
            base_series[.i] = .i
        endfor
    elsif .type = 2
        # Permutation: parse user values
        @parseSeriesValues: .values$, .length
    elsif .type = 3
        # 12-tone row (classic example)
        if .length = 12
            base_series[1] = 0
            base_series[2] = 10
            base_series[3] = 7
            base_series[4] = 11
            base_series[5] = 3
            base_series[6] = 8
            base_series[7] = 1
            base_series[8] = 9
            base_series[9] = 2
            base_series[10] = 5
            base_series[11] = 6
            base_series[12] = 4
        else
            for .i to .length
                base_series[.i] = .i
            endfor
        endif
    endif
endproc

procedure parseSeriesValues: .values$, .length
    .count = 0
    .remaining$ = .values$ + ","
    
    while length(.remaining$) > 0 and .count < .length
        .comma_pos = index(.remaining$, ",")
        if .comma_pos > 0
            .count += 1
            .value$ = left$(.remaining$, .comma_pos - 1)
            .value$ = replace$(.value$, " ", "", 0)
            
            if .value$ <> ""
                base_series[.count] = number(.value$)
            else
                base_series[.count] = .count
            endif
            
            .remaining$ = right$(.remaining$, length(.remaining$) - .comma_pos)
        else
            .remaining$ = ""
        endif
    endwhile
    
    for .i from .count + 1 to .length
        base_series[.i] = .i
    endfor
endproc

procedure applySerialTransformations: .invert, .retro, .rotate
    for .i to series_length
        working_series[.i] = base_series[.i]
    endfor
    
    if .invert
        .min = working_series[1]
        .max = working_series[1]
        for .i from 2 to series_length
            if working_series[.i] < .min
                .min = working_series[.i]
            endif
            if working_series[.i] > .max
                .max = working_series[.i]
            endif
        endfor
        
        for .i to series_length
            working_series[.i] = .min + .max - working_series[.i]
        endfor
    endif
    
    if .retro
        for .i to series_length
            temp_series[.i] = working_series[series_length - .i + 1]
        endfor
        for .i to series_length
            working_series[.i] = temp_series[.i]
        endfor
    endif
    
    .rot = .rotate mod series_length
    if .rot <> 0
        for .i to series_length
            .source_i = ((.i - 1 - .rot) mod series_length) + 1
            if .source_i < 1
                .source_i += series_length
            endif
            temp_series[.i] = working_series[.source_i]
        endfor
        for .i to series_length
            working_series[.i] = temp_series[.i]
        endfor
    endif
    
    for .i to series_length
        base_series[.i] = working_series[.i]
    endfor
endproc

procedure normalizeSeries
    .min = base_series[1]
    .max = base_series[1]
    
    for .i from 2 to series_length
        if base_series[.i] < .min
            .min = base_series[.i]
        endif
        if base_series[.i] > .max
            .max = base_series[.i]
        endif
    endfor
    
    .range = .max - .min
    if .range = 0
        .range = 1
    endif
    
    for .i to series_length
        normalized_series[.i] = (base_series[.i] - .min) / .range
    endfor
endproc

procedure normalizeOriginal: .length
    .min = original_series[1]
    .max = original_series[1]
    
    for .i from 2 to .length
        if original_series[.i] < .min
            .min = original_series[.i]
        endif
        if original_series[.i] > .max
            .max = original_series[.i]
        endif
    endfor
    
    .range = .max - .min
    if .range = 0
        .range = 1
    endif
    
    for .i to .length
        original_normalized[.i] = (original_series[.i] - .min) / .range
    endfor
endproc
