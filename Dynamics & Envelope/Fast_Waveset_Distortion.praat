# ============================================================
# Praat AudioTools - Fast Waveset Distortion.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.7 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Fast waveset-inspired audio distortion with stereo processing.
#   Processes L/R differently for wide stereo image.
#   Applies Hann windowing to eliminate clicks.
#
#   ENGINEERING NOTES:
#   - The chunk[], order[], result, and n_chunks identifiers are
#     used as SCRIPT-LEVEL (global) variables for inter-procedure
#     communication, even though they are written inside
#     processAudio. This is intentional for this two-call flow
#     (one call for L channel, one for R) — each call overwrites
#     the array entries 1..n_chunks with its own chunk IDs and
#     cleans them up before returning. Fragile if extended to
#     more than two calls per session; consider passing IDs
#     explicitly if doing so.
#   - The procedure communicates the final result Sound to the
#     caller via selection state, not return value.
#   - Concatenate-based assembly is O(N^2) in sample count but
#     algorithmically inherent given Praat's Sound primitives.
#
# Changelog v1.7:
#   - Audio pipeline UNCHANGED. Output is bit-identical to v1.6
#     for the same form parameters and the same RNG state
#     (shuffle mode draws from Praat's RNG; reset Praat for
#     reproducible shuffles).
#   - Added Play_result boolean form field (default 1). v1.6
#     had a stray unconditional `Play` at the end of the script
#     with no way to disable it; v1.7 guards it with the form
#     toggle.
#   - Dropped the 4 `comment === ... ===` decorative form lines
#     to keep the form compact (same lesson as the rest of the
#     suite — decorative comments cost vertical screen real
#     estate without functional value).
#   - Visualization rewritten to suite 8x8 standard:
#       Title bar + metadata subtitle (preset, mode, chunk count)
#       Panel A (left, headline): source waveform with chunk-
#         boundary grid overlay — shows what is being chopped up
#       Panel B (right, headline): mode description + parameter
#         report — explains per-mode what happens to each chunk
#       Panel C: zoom overlay (first 200 ms, gray = source,
#         blue = L, orange = R) — shows transformation at small
#         scale
#       Panel D: output waveform (full file, L blue, R orange)
#       Panel E: light-grey summary stats bar (suite standard)
#     v1.6 had 4 panels (title, original, L, R, parameter line).
#     v1.7 has 5 panels matching the rest of the suite.
#   - Added header documentation of the global-variable pattern.
# Changelog v1.6:
#   - Added presets
#   - Matched visualization style to other AudioTools scripts
#   - Added preset name to output filename
#
# Usage:
#   Select a Sound object and run this script.
# ============================================================

form Fast Waveset Distortion v1.7
    optionmenu Preset: 1
        option Custom
        option Glitch Stutter
        option Rhythmic Gaps
        option Backwards Chunks
        option Random Shuffle
        option Slow Motion
        option Fast Forward
        option Sidechain Pump
        option Robot Voice
        option Lo-Fi Crush
        option Wobble Tremolo
    optionmenu Mode: 1
        option 1. Stutter (repeat chunks)
        option 2. Gaps (silence chunks)
        option 3. Reverse chunks
        option 4. Shuffle order
        option 5. Time stretch
        option 6. Time compress
        option 7. Pumping (alt. volume)
        option 8. Ring modulator
        option 9. Bitcrush
        option 10. Tremolo
    real Amount 3.0
    positive Chunk_ms 40
    real Fade_ms 5
    real Stereo_spread 0.2
    real Mix 1.0
    boolean Normalize_output 1
    boolean Show_visualization 1
    boolean Play_result 1
endform

# === APPLY PRESETS ===
if preset = 2
    # Glitch Stutter
    mode = 1
    amount = 4.0
    chunk_ms = 30
    fade_ms = 3
    stereo_spread = 0.3
    presetName$ = "GlitchStutter"
elsif preset = 3
    # Rhythmic Gaps
    mode = 2
    amount = 3.0
    chunk_ms = 50
    fade_ms = 5
    stereo_spread = 0.1
    presetName$ = "RhythmicGaps"
elsif preset = 4
    # Backwards Chunks
    mode = 3
    amount = 1.0
    chunk_ms = 80
    fade_ms = 8
    stereo_spread = 0.15
    presetName$ = "BackwardsChunks"
elsif preset = 5
    # Random Shuffle
    mode = 4
    amount = 1.0
    chunk_ms = 60
    fade_ms = 6
    stereo_spread = 0.25
    presetName$ = "RandomShuffle"
elsif preset = 6
    # Slow Motion
    mode = 5
    amount = 4.0
    chunk_ms = 100
    fade_ms = 10
    stereo_spread = 0.1
    presetName$ = "SlowMotion"
elsif preset = 7
    # Fast Forward
    mode = 6
    amount = 3.0
    chunk_ms = 50
    fade_ms = 5
    stereo_spread = 0.1
    presetName$ = "FastForward"
elsif preset = 8
    # Sidechain Pump
    mode = 7
    amount = 4.0
    chunk_ms = 125
    fade_ms = 10
    stereo_spread = 0.05
    presetName$ = "SidechainPump"
elsif preset = 9
    # Robot Voice
    mode = 8
    amount = 2.5
    chunk_ms = 20
    fade_ms = 2
    stereo_spread = 0.4
    presetName$ = "RobotVoice"
elsif preset = 10
    # Lo-Fi Crush
    mode = 9
    amount = 4.0
    chunk_ms = 30
    fade_ms = 3
    stereo_spread = 0.2
    presetName$ = "LoFiCrush"
elsif preset = 11
    # Wobble Tremolo
    mode = 10
    amount = 5.0
    chunk_ms = 40
    fade_ms = 5
    stereo_spread = 0.3
    presetName$ = "WobbleTremolo"
else
    presetName$ = "Custom"
endif

# === VALIDATION ===
if numberOfSelected("Sound") <> 1
    exitScript: "Select a Sound object."
endif

original = selected("Sound")
name$ = selected$("Sound")
sr = Get sampling frequency
dur = Get total duration
n_channels = Get number of channels

# Ensure fade doesn't exceed half chunk
fade_ms = min(fade_ms, chunk_ms / 2 - 1)
fade_sec = fade_ms / 1000

# Pre-compute chunk grid for display
chunk_sec_disp = chunk_ms / 1000
n_chunks_disp = ceiling(dur / chunk_sec_disp)

# Resolve short mode name for visualization
if mode = 1
    modeShort$ = "Stutter"
    modeDesc$ = "Each chunk repeated R times (R = round(amount), clamped 2-8), with 0.85^(r-1) decay"
elsif mode = 2
    modeShort$ = "Gaps"
    modeDesc$ = "Every Nth chunk silenced (N = max(2, round(amount)))"
elsif mode = 3
    modeShort$ = "Reverse"
    modeDesc$ = "Each chunk played backwards (order preserved)"
elsif mode = 4
    modeShort$ = "Shuffle"
    modeDesc$ = "Chunks reordered randomly (ascending Fisher-Yates)"
elsif mode = 5
    modeShort$ = "Stretch"
    modeDesc$ = "Each chunk slowed by factor = max(1.1, amount/2) via SR override"
elsif mode = 6
    modeShort$ = "Compress"
    modeDesc$ = "Each chunk sped up by factor = max(1.1, amount/2) via SR override"
elsif mode = 7
    modeShort$ = "Pumping"
    modeDesc$ = "Alternating gain per chunk (odd = hi, even = lo)"
elsif mode = 8
    modeShort$ = "RingMod"
    modeDesc$ = "Each chunk multiplied by sin(2pi*f*t), f = 50 + amount*80 Hz"
elsif mode = 9
    modeShort$ = "Bitcrush"
    modeDesc$ = "Per-chunk quantization to max(2, round(16/amount)) levels"
elsif mode = 10
    modeShort$ = "Tremolo"
    modeDesc$ = "Per-chunk tremolo at 2 + amount*3 Hz, depth min(0.9, amount*0.15)"
endif

writeInfoLine: "=== Fast Waveset Distortion v1.7 ==="
appendInfoLine: "Input: ", name$, " | ", fixed$(dur, 2), "s | ", n_channels, " ch"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Mode: ", mode$
appendInfoLine: "Amount: ", amount, " | Chunk: ", chunk_ms, "ms | Fade: ", fade_ms, "ms"
appendInfoLine: "Stereo spread: ", stereo_spread, " | Mix: ", fixed$(mix, 2)
appendInfoLine: "Chunks: ", n_chunks_disp, " (", fixed$(chunk_sec_disp * 1000, 1), " ms each)"
appendInfoLine: ""

# === CONVERT TO MONO FOR PROCESSING ===
selectObject: original
mono = Convert to mono
Rename: "mono_source"

# === PROCESS LEFT CHANNEL ===
appendInfoLine: "Processing LEFT channel..."
selectObject: mono
left_source = Copy: "left_source"

amount_L = amount
chunk_ms_L = chunk_ms
tag$ = "L"

@processAudio: left_source, mode, amount_L, chunk_ms_L, fade_sec, tag$
left_result = selected("Sound")

# === PROCESS RIGHT CHANNEL ===
appendInfoLine: "Processing RIGHT channel..."
selectObject: mono
right_source = Copy: "right_source"

amount_R = amount * (1 + stereo_spread * 0.5)
chunk_ms_R = chunk_ms * (1 + stereo_spread)
tag$ = "R"

@processAudio: right_source, mode, amount_R, chunk_ms_R, fade_sec, tag$
right_result = selected("Sound")

# === MATCH DURATIONS ===
selectObject: left_result
dur_L = Get total duration
selectObject: right_result
dur_R = Get total duration

min_dur = min(dur_L, dur_R)

if dur_L > min_dur
    selectObject: left_result
    left_trimmed = Extract part: 0, min_dur, "rectangular", 1, "no"
    removeObject: left_result
    left_result = left_trimmed
endif

if dur_R > min_dur
    selectObject: right_result
    right_trimmed = Extract part: 0, min_dur, "rectangular", 1, "no"
    removeObject: right_result
    right_result = right_trimmed
endif

# === COMBINE TO STEREO ===
selectObject: left_result
plusObject: right_result
stereo_result = Combine to stereo
Rename: name$ + "_WSD_" + presetName$

removeObject: left_result, right_result, mono

# === MIX WITH ORIGINAL ===
if mix < 1
    selectObject: stereo_result
    result_dur = Get total duration
    
    selectObject: original
    if n_channels = 1
        orig_stereo = Convert to stereo
    else
        orig_stereo = Copy: "orig_stereo"
    endif
    
    orig_dur = Get total duration
    use_dur = min(result_dur, orig_dur)
    
    if orig_dur > use_dur
        orig_part = Extract part: 0, use_dur, "rectangular", 1, "no"
        removeObject: orig_stereo
        orig_stereo = orig_part
    endif
    
    selectObject: stereo_result
    orig_str$ = string$(orig_stereo)
    Formula: "self * mix + object[" + orig_str$ + ", x, y] * (1 - mix)"
    
    removeObject: orig_stereo
endif

# === NORMALIZE ===
selectObject: stereo_result
if normalize_output
    Scale peak: 0.95
endif

output = stereo_result
final_dur = Get total duration

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if show_visualization
    
    Erase all
    Black
    Plain line
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##FAST WAVESET DISTORTION##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... name$
        ... + "  |  " + presetName$
        ... + "  |  " + modeShort$
        ... + "  |  " + string$(n_chunks_disp) + " chunks x " + fixed$(chunk_ms, 0) + " ms"
        ... + "  |  amount " + fixed$(amount, 1)
        ... + "  |  spread " + fixed$(stereo_spread, 2)
    
    # ----------------------------------------------------------
    # PANEL A: SOURCE + CHUNK GRID OVERLAY  (left, headline)
    # Shows the source waveform with vertical dotted lines at
    # chunk boundaries — visualises what is being chopped up.
    # If there are too many chunks to render legibly, the grid
    # is thinned so at most ~60 lines are drawn.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    selectObject: original
    src_peak = Get absolute extremum: 0, 0, "None"
    if src_peak < 0.001
        src_peak = 0.001
    endif
    src_amp = src_peak * 1.15
    
    Axes: 0, dur, -src_amp, src_amp
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, dur, -src_amp, src_amp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, dur, 0
    
    # Draw source waveform behind the grid
    selectObject: original
    Colour: "{0.55, 0.55, 0.55}"
    Line width: 1
    Draw: 0, dur, -src_amp, src_amp, "no", "Curve"
    
    # Chunk boundary grid (thinned if too many)
    if n_chunks_disp > 60
        grid_step = ceiling(n_chunks_disp / 60)
    else
        grid_step = 1
    endif
    
    Colour: "{0.65, 0.35, 0.70}"
    Line width: 1
    Dotted line
    for gc from 1 to n_chunks_disp - 1
        if gc mod grid_step = 0
            gx = gc * chunk_sec_disp
            Draw line: gx, -src_amp, gx, src_amp
        endif
    endfor
    Solid line
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL B: MODE DESCRIPTION + PARAMETER REPORT  (right, headline)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.93, "half", "Mode:"
    
    Font size: 11
    Colour: "{0.65, 0.35, 0.70}"
    Text: 0.10, "left", 0.84, "half", "##" + modeShort$ + "##"
    
    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.10, "left", 0.76, "half", modeDesc$
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.66, "half", "Chunks:"
    
    Font size: 10
    Colour: "{0.70, 0.45, 0.20}"
    Text: 0.10, "left", 0.59, "half", string$(n_chunks_disp) + " chunks"
    Text: 0.10, "left", 0.52, "half", "Size: " + fixed$(chunk_ms, 0) + " ms (" + fixed$(chunk_sec_disp * 1000, 1) + " ms)"
    Text: 0.10, "left", 0.45, "half", "Fade: " + fixed$(fade_ms, 1) + " ms (Hann)"
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.36, "half", "Parameters:"
    
    Font size: 10
    Colour: "{0.30, 0.55, 0.30}"
    Text: 0.10, "left", 0.29, "half", "Amount:  " + fixed$(amount, 2)
    Text: 0.10, "left", 0.22, "half", "Spread:  " + fixed$(stereo_spread, 2) + " (L vs R)"
    Text: 0.10, "left", 0.15, "half", "Mix:     " + fixed$(mix, 2) + " (dry/wet)"
    
    Font size: 7
    if normalize_output
        Colour: "{0.20, 0.55, 0.30}"
        Text: 0.10, "left", 0.06, "half", "Normalized (peak 0.95)"
    else
        Colour: "{0.55, 0.30, 0.20}"
        Text: 0.10, "left", 0.06, "half", "Not normalized"
    endif
    
    Colour: "Black"
    Draw inner box
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    if grid_step > 1
        gridLabel$ = "Source + chunk grid (every " + string$(grid_step) + "th boundary shown)"
    else
        gridLabel$ = "Source + chunk grid (every chunk boundary)"
    endif
    Text: 2.10, "centre", 7.30, "half", gridLabel$
    Text: 6.10, "centre", 7.30, "half", "Mode and parameter report"
    
    # ----------------------------------------------------------
    # PANEL C: ZOOM OVERLAY  (first 200 ms)
    # Gray = source, blue = L, orange = R.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.75, 5.48
    
    zoomDur = 0.2
    if zoomDur > dur
        zoomDur = dur
    endif
    if zoomDur > final_dur
        zoomDur = final_dur
    endif
    
    # Probe peaks across all three sources for axis scaling
    selectObject: original
    z_peak1 = Get absolute extremum: 0, zoomDur, "None"
    selectObject: output
    Extract one channel: 1
    output_L_tmp = selected("Sound")
    z_peak2 = Get absolute extremum: 0, zoomDur, "None"
    
    selectObject: output
    Extract one channel: 2
    output_R_tmp = selected("Sound")
    z_peak3 = Get absolute extremum: 0, zoomDur, "None"
    
    z_max = z_peak1
    if z_peak2 > z_max
        z_max = z_peak2
    endif
    if z_peak3 > z_max
        z_max = z_peak3
    endif
    if z_max < 0.001
        z_max = 0.001
    endif
    z_amp = z_max * 1.15
    
    Axes: 0, zoomDur, -z_amp, z_amp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, zoomDur, -z_amp, z_amp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, zoomDur, 0
    
    # Light chunk-boundary marks in the zoom window
    Colour: "{0.88, 0.85, 0.92}"
    Line width: 1
    Dotted line
    n_zoom_chunks = floor(zoomDur / chunk_sec_disp)
    for gc from 1 to n_zoom_chunks
        gx = gc * chunk_sec_disp
        if gx < zoomDur
            Draw line: gx, -z_amp, gx, z_amp
        endif
    endfor
    Solid line
    
    # Source behind
    selectObject: original
    Colour: "{0.65, 0.65, 0.65}"
    Line width: 1
    Draw: 0, zoomDur, -z_amp, z_amp, "no", "Curve"
    
    # Output L
    selectObject: output_L_tmp
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, zoomDur, -z_amp, z_amp, "no", "Curve"
    
    # Output R
    selectObject: output_R_tmp
    Colour: "{0.82, 0.45, 0.25}"
    Line width: 1
    Draw: 0, zoomDur, -z_amp, z_amp, "no", "Curve"
    
    removeObject: output_L_tmp, output_R_tmp
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Zoom: first " + fixed$(zoomDur * 1000, 0) + " ms  (gray = source, blue = L, orange = R)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM (FULL FILE)  L blue, R orange
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.55, 7.72, 5.69, 6.48
    
    selectObject: output
    out_peak = Get absolute extremum: 0, 0, "None"
    if out_peak < 0.001
        out_peak = 0.001
    endif
    out_amp = out_peak * 1.15
    
    Axes: 0, final_dur, -out_amp, out_amp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, final_dur, -out_amp, out_amp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, final_dur, 0
    
    # L channel
    selectObject: output
    Extract one channel: 1
    output_L_full = selected("Sound")
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, final_dur, -out_amp, out_amp, "no", "Curve"
    removeObject: output_L_full
    
    # R channel
    selectObject: output
    Extract one channel: 2
    output_R_full = selected("Sound")
    Colour: "{0.82, 0.45, 0.25}"
    Line width: 1
    Draw: 0, final_dur, -out_amp, out_amp, "no", "Curve"
    removeObject: output_R_full
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Output (full file)  blue = L, orange = R"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR  (suite standard — light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.55, 7.72, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    if normalize_output
        normStr$ = "norm 0.95"
    else
        normStr$ = "no norm"
    endif
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + name$
        ... + "  |  Mode: " + modeShort$ + "  (" + mode$ + ")"
        ... + "  |  Chunks: " + string$(n_chunks_disp) + " x " + fixed$(chunk_ms, 0) + " ms"
        ... + "  |  Fade: " + fixed$(fade_ms, 1) + " ms"
    
    Text: 0.02, "left", 0.28, "half",
        ... "Amount: " + fixed$(amount, 2)
        ... + "  |  Spread: " + fixed$(stereo_spread, 2)
        ... + "  |  Mix: " + fixed$(mix, 2)
        ... + "  |  " + normStr$
        ... + "  |  In: " + fixed$(dur, 2) + " s (" + string$(n_channels) + " ch)"
        ... + "  |  Out: " + fixed$(final_dur, 2) + " s (stereo)"
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endif

selectObject: output

appendInfoLine: ""
appendInfoLine: "Original: ", fixed$(dur, 2), "s (", n_channels, " ch)"
appendInfoLine: "Output:   ", fixed$(final_dur, 2), "s (stereo)"
appendInfoLine: ""
appendInfoLine: "Done! -> ", name$, "_WSD_", presetName$

# ============================================================
# APPLY HANN WINDOW FADES TO CHUNK
# ============================================================
procedure applyWindow: .snd, .fade_sec
    selectObject: .snd
    .chunk_dur = Get total duration
    
    if .fade_sec > 0 and .fade_sec < .chunk_dur / 2
        # Fade in: Hann window rise (0 to 1)
        Formula (part): 0, .fade_sec, 1, 1, "self * (0.5 - 0.5 * cos(pi * x / .fade_sec))"
        
        # Fade out: Hann window fall (1 to 0)
        .fade_start = .chunk_dur - .fade_sec
        Formula (part): .fade_start, .chunk_dur, 1, 1, "self * (0.5 + 0.5 * cos(pi * (x - .fade_start) / .fade_sec))"
    endif
endproc

# ============================================================
# MAIN PROCESSING PROCEDURE
# Uses script-level (global) variables chunk[], order[], result,
# and n_chunks for inter-procedure communication. This is safe
# for the two-call flow used by this script (L then R) — each
# call overwrites entries 1..n_chunks and removes them before
# returning. Fragile if extended.
# ============================================================
procedure processAudio: .source, .mode, .amount, .chunk_ms, .fade_sec, .tag$
    selectObject: .source
    .sr = Get sampling frequency
    .dur = Get total duration
    
    .chunk_sec = .chunk_ms / 1000
    .n_chunks = ceiling(.dur / .chunk_sec)
    
    # Extract chunks into GLOBAL array
    for c from 1 to .n_chunks
        .t1 = (c - 1) * .chunk_sec
        .t2 = min(c * .chunk_sec, .dur)
        
        if .t2 > .t1
            selectObject: .source
            chunk[c] = Extract part: .t1, .t2, "rectangular", 1, "no"
            Rename: "chunk_" + .tag$ + "_" + string$(c)
        else
            chunk[c] = 0
        endif
    endfor
    
    n_chunks = .n_chunks
    
    # Process by mode
    if .mode = 1
        # STUTTER
        .reps = max(2, min(8, round(.amount)))
        
        selectObject: chunk[1]
        @applyWindow: chunk[1], .fade_sec
        result = Copy: "result_" + .tag$
        
        for .r from 2 to .reps
            selectObject: chunk[1]
            .temp = Copy: "temp"
            .decay = 0.85 ^ (.r - 1)
            Formula: "self * .decay"
            @applyWindow: .temp, .fade_sec
            selectObject: result
            plusObject: .temp
            .new_result = Concatenate
            removeObject: result, .temp
            result = .new_result
        endfor
        
        for c from 2 to n_chunks
            if chunk[c] <> 0
                @applyWindow: chunk[c], .fade_sec
                for .r from 1 to .reps
                    selectObject: chunk[c]
                    .temp = Copy: "temp"
                    if .r > 1
                        .decay = 0.85 ^ (.r - 1)
                        Formula: "self * .decay"
                    endif
                    selectObject: result
                    plusObject: .temp
                    .new_result = Concatenate
                    removeObject: result, .temp
                    result = .new_result
                endfor
            endif
        endfor
        
    elsif .mode = 2
        # GAPS
        .skip_n = max(2, round(.amount))
        
        for c from 1 to n_chunks
            if chunk[c] <> 0
                if c mod .skip_n = 0
                    selectObject: chunk[c]
                    Formula: "0"
                else
                    @applyWindow: chunk[c], .fade_sec
                endif
            endif
        endfor
        
        selectObject: chunk[1]
        result = Copy: "result_" + .tag$
        for c from 2 to n_chunks
            if chunk[c] <> 0
                selectObject: result
                plusObject: chunk[c]
                .new_result = Concatenate
                removeObject: result
                result = .new_result
            endif
        endfor
        
    elsif .mode = 3
        # REVERSE
        for c from 1 to n_chunks
            if chunk[c] <> 0
                selectObject: chunk[c]
                Reverse
                @applyWindow: chunk[c], .fade_sec
            endif
        endfor
        
        selectObject: chunk[1]
        result = Copy: "result_" + .tag$
        for c from 2 to n_chunks
            if chunk[c] <> 0
                selectObject: result
                plusObject: chunk[c]
                .new_result = Concatenate
                removeObject: result
                result = .new_result
            endif
        endfor
        
    elsif .mode = 4
        # SHUFFLE
        for c from 1 to n_chunks
            order[c] = c
        endfor
        # Ascending Fisher-Yates (Praat for-loops only increment)
        for c from 1 to n_chunks - 1
            .j = randomInteger(c, n_chunks)
            .tmp = order[c]
            order[c] = order[.j]
            order[.j] = .tmp
        endfor
        
        # Apply windows to all chunks
        for c from 1 to n_chunks
            if chunk[c] <> 0
                @applyWindow: chunk[c], .fade_sec
            endif
        endfor
        
        .first_idx = order[1]
        if chunk[.first_idx] <> 0
            selectObject: chunk[.first_idx]
            result = Copy: "result_" + .tag$
        endif
        
        for c from 2 to n_chunks
            .idx = order[c]
            if chunk[.idx] <> 0
                selectObject: result
                plusObject: chunk[.idx]
                .new_result = Concatenate
                removeObject: result
                result = .new_result
            endif
        endfor
        
    elsif .mode = 5
        # STRETCH
        .factor = max(1.1, .amount / 2)
        
        for c from 1 to n_chunks
            if chunk[c] <> 0
                selectObject: chunk[c]
                .chunk_sr = Get sampling frequency
                .new_sr = .chunk_sr / .factor
                if .new_sr >= 100
                    Resample: .new_sr, 50
                    .new_chunk = selected("Sound")
                    removeObject: chunk[c]
                    selectObject: .new_chunk
                    Override sampling frequency: .chunk_sr
                    chunk[c] = .new_chunk
                    Rename: "chunk_" + .tag$ + "_" + string$(c)
                endif
                @applyWindow: chunk[c], .fade_sec
            endif
        endfor
        
        selectObject: chunk[1]
        result = Copy: "result_" + .tag$
        for c from 2 to n_chunks
            if chunk[c] <> 0
                selectObject: result
                plusObject: chunk[c]
                .new_result = Concatenate
                removeObject: result
                result = .new_result
            endif
        endfor
        
    elsif .mode = 6
        # COMPRESS
        .factor = max(1.1, .amount / 2)
        
        for c from 1 to n_chunks
            if chunk[c] <> 0
                selectObject: chunk[c]
                .chunk_sr = Get sampling frequency
                .new_sr = .chunk_sr * .factor
                if .new_sr <= 96000
                    Resample: .new_sr, 50
                    .new_chunk = selected("Sound")
                    removeObject: chunk[c]
                    selectObject: .new_chunk
                    Override sampling frequency: .chunk_sr
                    chunk[c] = .new_chunk
                    Rename: "chunk_" + .tag$ + "_" + string$(c)
                endif
                @applyWindow: chunk[c], .fade_sec
            endif
        endfor
        
        selectObject: chunk[1]
        result = Copy: "result_" + .tag$
        for c from 2 to n_chunks
            if chunk[c] <> 0
                selectObject: result
                plusObject: chunk[c]
                .new_result = Concatenate
                removeObject: result
                result = .new_result
            endif
        endfor
        
    elsif .mode = 7
        # PUMPING
        .gain_hi = 1 + (.amount - 1) * 0.5
        .gain_lo = 1 / .gain_hi
        
        for c from 1 to n_chunks
            if chunk[c] <> 0
                selectObject: chunk[c]
                if c mod 2 = 1
                    Formula: "self * .gain_hi"
                else
                    Formula: "self * .gain_lo"
                endif
                @applyWindow: chunk[c], .fade_sec
            endif
        endfor
        
        selectObject: chunk[1]
        result = Copy: "result_" + .tag$
        for c from 2 to n_chunks
            if chunk[c] <> 0
                selectObject: result
                plusObject: chunk[c]
                .new_result = Concatenate
                removeObject: result
                result = .new_result
            endif
        endfor
        
    elsif .mode = 8
        # RING MOD
        .ring_freq = 50 + .amount * 80
        
        for c from 1 to n_chunks
            if chunk[c] <> 0
                selectObject: chunk[c]
                Formula: "self * sin(2 * pi * .ring_freq * x)"
                @applyWindow: chunk[c], .fade_sec
            endif
        endfor
        
        selectObject: chunk[1]
        result = Copy: "result_" + .tag$
        for c from 2 to n_chunks
            if chunk[c] <> 0
                selectObject: result
                plusObject: chunk[c]
                .new_result = Concatenate
                removeObject: result
                result = .new_result
            endif
        endfor
        
    elsif .mode = 9
        # BITCRUSH
        .levels = max(2, round(16 / .amount))
        
        for c from 1 to n_chunks
            if chunk[c] <> 0
                selectObject: chunk[c]
                Formula: "round(self * .levels) / .levels"
                @applyWindow: chunk[c], .fade_sec
            endif
        endfor
        
        selectObject: chunk[1]
        result = Copy: "result_" + .tag$
        for c from 2 to n_chunks
            if chunk[c] <> 0
                selectObject: result
                plusObject: chunk[c]
                .new_result = Concatenate
                removeObject: result
                result = .new_result
            endif
        endfor
        
    elsif .mode = 10
        # TREMOLO
        .trem_freq = 2 + .amount * 3
        .trem_depth = min(0.9, .amount * 0.15)
        
        for c from 1 to n_chunks
            if chunk[c] <> 0
                selectObject: chunk[c]
                Formula: "self * (1 - .trem_depth * (0.5 + 0.5 * sin(2 * pi * .trem_freq * x)))"
                @applyWindow: chunk[c], .fade_sec
            endif
        endfor
        
        selectObject: chunk[1]
        result = Copy: "result_" + .tag$
        for c from 2 to n_chunks
            if chunk[c] <> 0
                selectObject: result
                plusObject: chunk[c]
                .new_result = Concatenate
                removeObject: result
                result = .new_result
            endif
        endfor
    endif
    
    # Cleanup chunks
    for c from 1 to n_chunks
        if chunk[c] <> 0
            removeObject: chunk[c]
        endif
    endfor
    
    removeObject: .source
    
    selectObject: result
endproc

if play_result
    selectObject: output
    Play
endif
