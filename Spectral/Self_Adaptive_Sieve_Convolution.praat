# ============================================================
# Praat AudioTools - Self_Adaptive_Sieve_Convolution.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 5.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Self-adaptive sieve convolution. Each grain of the source is
#   routed through one of two impulse responses (IR_A or IR_B)
#   based on number-theoretic sieve conditions, or passed through
#   dry. IRs are harvested live from the source material and
#   crossfaded on an adaptive schedule, so the convolution
#   character evolves continuously with the source.
#
# Changelog v5.3 (2026):
#   - FIX: source Sounds with a non-zero start time are now processed correctly.
#     All grain/IR harvest times remain musical relative times, but extraction is
#     offset by the Sound x-min. v5.2 could render silence for shifted-time Sounds.
#   - FIX: frame scheduling now covers the complete source. If the regular hop grid
#     leaves a short uncovered suffix, one final grain is anchored to the source end.
#   - FORM/CORRECTNESS: sieve moduli, update interval and crossfade length are integer
#     grain counts and are validated as such; hop must be > 0. Tail and IR high-pass
#     may be 0, with 0-Hz IR HP meaning no high-pass.
#   - FORM: removed IR RMS dB from the user controls. Every wet grain is RMS-matched
#     to its source grain after convolution, so scalar IR-RMS normalization cancels
#     out and the old control was effectively inaudible/dead. Legacy preset values
#     remain internally for numerical continuity.
#   - CLARITY: simultaneous sieve hits route to A first (existing sound, now stated).
#   - VIZ: no redesign; source panel now marks the actual initial/adaptive IR harvest
#     positions, and the spectrogram range is Nyquist-safe.
#
# Changelog v5.2 (2026):
#   - FIX: sieve remainders >= modulus (e.g. rem 5, mod 3) made a
#     sieve silently unhittable -- the whole run came out dry with
#     no warning, and findIRStart constructed "hits" that the main
#     loop's test then rejected. Remainders are now folded
#     (rem mod mod), with an info note when folding occurs.
#   - VERIFIED on 6.4.42 (probes): 2-arg object[id, col] reads are
#     ROW-AWARE for matching channel counts and BROADCAST for mono
#     sources -- so the v5.1 per-channel stereo mix and the IR
#     crossfade blends are correct as written. mixIntoBuffer's two
#     identical branches (the else promised a channel-1 replicate
#     that Praat already performs) collapsed into one documented
#     call.
#   - VIZ: title strip uses an explicit inner viewport (the
#     outer-only form with a hand-tuned negative offset is the
#     margin-compression collision geometry).
#   - MEASURED, left as design: Slow Morph (hop 0.75) and Dissolve
#     (0.6) are non-COLA placements -- the inter-grain pulsation is
#     part of those presets' character (see info line). Micro Pulse
#     runs ~400 grains/second of source; expect it to be the slow
#     preset.
#
# Changelog v5.1 (2026):
#   - FIX: stray ";" inline comments replaced with "#" (Praat-correct)
#   - FIX: initial-IR harvest loop condition was inverted; rewrote
#     the search so it reliably finds the first in-bounds sieve hit
#   - FIX: stereo/multi-channel sources now convolve per-channel
#     (v5.0 silently downmixed to channel 1)
#   - PORT: all Formula strings migrated from backtick interpolation
#     ('.var') to fixed$() concatenation (more robust across Praat
#     versions and inside procedures)
#   - PORT: "goto/label" removed in favour of plain control flow
#   - PERF: grain_type[] replaced with grain_type# vector
#   - VIZ: sieve-hit marks thinned (top/bottom ticks) so they no
#     longer obscure the waveform; added IR-update markers
#   - VIZ: 8-inch canvas with title, source waveform, output with
#     sieve ticks, output spectrogram, grey summary panel
# ============================================================

form Self-Adaptive Sieve Convolution
    comment Select a Sound object first

    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Subtle Shimmer
        option Dense Reverb
        option Micro Pulse
        option Slow Morph
        option Prime Sieve
        option Sparse Scatter
        option Dissolve

    comment === Grain Parameters ===
    positive Segment_ms 50
    real Hop_fraction 0.5
    real Tail_ms 100

    comment === IR Parameters ===
    positive Ir_ms 300
    real Ir_hp_hz 500
    real Dry_gain 0.8

    comment === Sieve A (grain n routed when n mod m = r) ===
    integer Sieve_a_mod 3
    integer Sieve_a_rem 0

    comment === Sieve B (grain n routed when n mod m = r) ===
    integer Sieve_b_mod 5
    integer Sieve_b_rem 2

    comment === Adaptive IR Updates ===
    boolean Adaptive_updates 1
    integer Update_interval 100
    integer Crossfade_grains 10

    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Internal IR conditioning level. This is intentionally not a form control:
# wet grains are RMS-matched after convolution, so this scalar cancels musically.
ir_condition_db = -18

# ============================================================
# APPLY PRESETS (write to the same form variables, so the rest
# of the script is preset-agnostic)
# ============================================================
if preset = 2
    segment_ms       = 25
    hop_fraction     = 0.5
    tail_ms          = 60
    ir_ms            = 150
    ir_condition_db  = -18
    ir_hp_hz         = 500
    dry_gain         = 0.8
    sieve_a_mod      = 3
    sieve_a_rem      = 0
    sieve_b_mod      = 5
    sieve_b_rem      = 2
    adaptive_updates = 1
    update_interval  = 200
    crossfade_grains = 20
elsif preset = 3
    segment_ms       = 80
    hop_fraction     = 0.5
    tail_ms          = 150
    ir_ms            = 500
    ir_condition_db  = -18
    ir_hp_hz         = 300
    dry_gain         = 0.7
    sieve_a_mod      = 2
    sieve_a_rem      = 0
    sieve_b_mod      = 3
    sieve_b_rem      = 1
    adaptive_updates = 1
    update_interval  = 50
    crossfade_grains = 5
elsif preset = 4
    segment_ms       = 10
    hop_fraction     = 0.25
    tail_ms          = 40
    ir_ms            = 80
    ir_condition_db  = -20
    ir_hp_hz         = 600
    dry_gain         = 0.9
    sieve_a_mod      = 3
    sieve_a_rem      = 0
    sieve_b_mod      = 4
    sieve_b_rem      = 1
    adaptive_updates = 1
    update_interval  = 150
    crossfade_grains = 15
elsif preset = 5
    segment_ms       = 150
    hop_fraction     = 0.75
    tail_ms          = 200
    ir_ms            = 600
    ir_condition_db  = -16
    ir_hp_hz         = 200
    dry_gain         = 0.75
    sieve_a_mod      = 4
    sieve_a_rem      = 0
    sieve_b_mod      = 7
    sieve_b_rem      = 3
    adaptive_updates = 1
    update_interval  = 300
    crossfade_grains = 30
elsif preset = 6
    segment_ms       = 50
    hop_fraction     = 0.5
    tail_ms          = 100
    ir_ms            = 300
    ir_condition_db  = -18
    ir_hp_hz         = 500
    dry_gain         = 0.8
    sieve_a_mod      = 2
    sieve_a_rem      = 0
    sieve_b_mod      = 3
    sieve_b_rem      = 1
    adaptive_updates = 1
    update_interval  = 100
    crossfade_grains = 10
elsif preset = 7
    segment_ms       = 60
    hop_fraction     = 0.5
    tail_ms          = 120
    ir_ms            = 350
    ir_condition_db  = -18
    ir_hp_hz         = 500
    dry_gain         = 0.85
    sieve_a_mod      = 7
    sieve_a_rem      = 0
    sieve_b_mod      = 11
    sieve_b_rem      = 3
    adaptive_updates = 1
    update_interval  = 120
    crossfade_grains = 12
elsif preset = 8
    segment_ms       = 100
    hop_fraction     = 0.6
    tail_ms          = 150
    ir_ms            = 400
    ir_condition_db  = -17
    ir_hp_hz         = 400
    dry_gain         = 0.7
    sieve_a_mod      = 3
    sieve_a_rem      = 1
    sieve_b_mod      = 5
    sieve_b_rem      = 0
    adaptive_updates = 1
    update_interval  = 250
    crossfade_grains = 40
endif

# ============================================================
# MAP FORM VARIABLES TO INTERNAL NAMES
# ============================================================
segment_duration         = segment_ms / 1000
tail_duration            = tail_ms    / 1000
ir_duration              = ir_ms      / 1000
ir_hp_freq               = ir_hp_hz
m1                       = sieve_a_mod
i1                       = sieve_a_rem
m2                       = sieve_b_mod
i2                       = sieve_b_rem
# v5.2: fold remainders into range -- rem >= mod (or negative)
# made the sieve silently unhittable (all-dry output)
i1_orig = i1
i2_orig = i2
i1 = ((i1 mod m1) + m1) mod m1
i2 = ((i2 mod m2) + m2) mod m2
adaptive_update_interval = update_interval
ir_crossfade_grains      = crossfade_grains
hop_duration             = segment_duration * hop_fraction

# ============================================================
# GUARD
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object before running this script."
endif

source_id    = selected("Sound")
source_name$ = selected$("Sound")

selectObject: source_id
src_dur = Get total duration
src_sr  = Get sampling frequency
src_ch  = Get number of channels
src_t0  = Get start time

if hop_fraction <= 0
    exitScript: "Hop fraction must be greater than 0."
endif
if tail_ms < 0
    exitScript: "Tail duration must be 0 ms or greater."
endif
if ir_hp_hz < 0 or ir_hp_hz >= src_sr / 2
    exitScript: "IR high-pass must be at least 0 Hz and below Nyquist."
endif
if sieve_a_mod < 1 or sieve_b_mod < 1
    exitScript: "Sieve moduli must be positive integers."
endif
if update_interval < 1
    exitScript: "Update interval must be at least 1 grain."
endif
if crossfade_grains < 1
    exitScript: "Crossfade length must be at least 1 grain."
endif

writeInfoLine:  "=== Self-Adaptive Sieve Convolution v5.3 ==="
appendInfoLine: "Source: ", source_name$, "  (", fixed$(src_dur, 3), " s  ", src_sr, " Hz  ", src_ch, " ch)"
appendInfoLine: "Sieve A: n mod ", m1, " = ", i1,
    ... "   Sieve B: n mod ", m2, " = ", i2
appendInfoLine: "Routing rule: A has priority when both sieves hit the same grain."
if i1 <> i1_orig or i2 <> i2_orig
    appendInfoLine: "NOTE: remainder(s) folded into range (were ", i1_orig, " / ", i2_orig, ")"
endif

# ============================================================
# PROCEDURE: half-Hann fade, in-place
# Migrated to fixed$() concatenation (no backtick interpolation).
# ============================================================
procedure applyHalfHann: .obj_id, .fade_type$, .fade_len
    selectObject: .obj_id
    .dur = Get total duration
    if .fade_len <= 0
        .fade_len = 1 / src_sr
    endif
    if .fade_len > .dur
        .fade_len = .dur
    endif
    .fl$ = fixed$(.fade_len, 6)
    if .fade_type$ = "in"
        Formula: "if x < " + .fl$
            ... + " then 0.5*(1-cos(pi*x/" + .fl$ + "))*self else self fi"
    elsif .fade_type$ = "out"
        .rs = .dur - .fade_len
        .rs$ = fixed$(.rs, 6)
        .du$ = fixed$(.dur, 6)
        Formula: "if x > " + .rs$
            ... + " then 0.5*(1-cos(pi*(" + .du$ + "-x)/" + .fl$ + "))*self else self fi"
    endif
endproc

# ============================================================
# PROCEDURE: RMS-normalise to target dBFS, in-place
# ============================================================
procedure rmsNormalise: .obj_id, .target_db
    selectObject: .obj_id
    .rms = Get root-mean-square: 0, 0
    if .rms > 1e-9
        .lin = 10 ^ (.target_db / 20)
        .g   = .lin / .rms
        Formula: "self * " + fixed$(.g, 9)
    endif
endproc

# ============================================================
# PROCEDURE: get RMS — result in global proc_rms
# ============================================================
procedure getRMS: .obj_id
    selectObject: .obj_id
    proc_rms = Get root-mean-square: 0, 0
endproc

# ============================================================
# PROCEDURE: scale a Sound in place by a gain literal.
# ============================================================
procedure scaleBy: .obj_id, .gain
    selectObject: .obj_id
    Formula: "self * " + fixed$(.gain, 9)
endproc

# ============================================================
# PROCEDURE: harvest and condition one IR
# Uses ALL channels of the source (so stereo IRs remain stereo).
# Result object ID → global new_ir_id
# ============================================================
procedure harvestIR: .start_t, .label$
    .end_t = .start_t + ir_duration
    if .end_t > src_dur
        .end_t = src_dur
    endif
    if .end_t <= .start_t
        .end_t = .start_t + 1 / src_sr
    endif

    selectObject: source_id
    .abs_start = src_t0 + .start_t
    .abs_end = src_t0 + .end_t
    new_ir_id = Extract part: .abs_start, .abs_end, "Hanning", 1, "no"
    Rename: "IR_raw_" + .label$

    # Optional high-pass to reduce tonal carry-over. 0 Hz = bypass.
    if ir_hp_freq > 0
        selectObject: new_ir_id
        Filter (pass Hann band): ir_hp_freq, 0, 100
        filtered_id = selected("Sound")
        removeObject: new_ir_id
        new_ir_id = filtered_id
    endif
    selectObject: new_ir_id
    Rename: "IR_" + .label$

    # Internal scalar conditioning. Wet-grain RMS matching later cancels this
    # scalar musically; retained only for numerical continuity with older presets.
    @rmsNormalise: new_ir_id, ir_condition_db

    # Edge fades to avoid clicks
    .fi = 0.005
    if ir_duration * 0.05 < .fi
        .fi = ir_duration * 0.05
    endif
    .fo = 0.010
    if ir_duration * 0.10 < .fo
        .fo = ir_duration * 0.10
    endif
    @applyHalfHann: new_ir_id, "in",  .fi
    @applyHalfHann: new_ir_id, "out", .fo
endproc

# ============================================================
# PROCEDURE: blend two IRs by weight → result in global blend_ir_id.
# Uses object[id, col] to read old IR by numeric ID (no name needed).
# ============================================================
procedure blendIRs: .new_id, .old_id, .w_new
    .w_old = 1 - .w_new

    selectObject: .new_id
    .new_dur = Get total duration
    selectObject: .old_id
    .old_dur = Get total duration
    .mlen = .new_dur
    if .old_dur < .mlen
        .mlen = .old_dur
    endif

    selectObject: .new_id
    blend_ir_id = Extract part: 0, .mlen, "rectangular", 1, "no"
    Rename: "IR_blend_tmp"

    # Weighted sum: new * w_new + old * w_old (stringified for portability)
    .wn$  = fixed$(.w_new, 9)
    .wo$  = fixed$(.w_old, 9)
    .oid$ = fixed$(.old_id, 0)
    selectObject: blend_ir_id
    Formula: "self * " + .wn$ + " + object[" + .oid$ + ", col] * " + .wo$
endproc

# ============================================================
# PROCEDURE: overlap-add one grain into the output buffer.
# No temporary Sound objects created.
#
# Index math (worked example so future-you doesn't re-derive it):
#   Praat's Formula exposes `col` = 1-based sample index in the
#   target buffer. The buffer sample at col c has time (c-1)/sr.
#   To read the grain sample at time (buffer_time - t_start):
#       grain_col = c - round(t_start * sr)
#   so we precompute  off = round(t_start * sr)  and write
#       Formula: "self + object[gid, col - off]"
#
# For multi-channel sources we loop over channels and restrict
# Formula (part) to each channel slice individually.
# ============================================================
procedure mixIntoBuffer: .buf_id, .grain_id, .t_start
    selectObject: .grain_id
    .g_dur = Get total duration
    .g_ch  = Get number of channels

    selectObject: .buf_id
    .b_dur = Get total duration
    .b_ch  = Get number of channels

    .mix_s = .t_start
    .mix_e = .t_start + .g_dur
    if .mix_e > .b_dur
        .mix_e = .b_dur
    endif
    if .mix_s < .b_dur
        .off = round(.t_start * src_sr)
        .gid$ = fixed$(.grain_id, 0)
        .off$ = fixed$(.off, 0)
        # v5.2 (probed on 6.4.42): the 2-arg object[id, col] read is
        # row-aware when channel counts match and BROADCASTS mono
        # sources across all buffer rows -- one call covers both
        # cases (the old if/else had two identical branches).
        selectObject: .buf_id
        Formula (part): .mix_s, .mix_e, 1, .b_ch,
            ... "self + object[" + .gid$ + ", col - " + .off$ + "]"
    endif
endproc

# ============================================================
# PROCEDURE: find a valid IR-harvest start time for a given sieve.
# Tries `start = n * hop_duration` for successive hits of the sieve
# (n mod m = r), skipping any whose IR window [start, start+ir_duration]
# falls entirely outside the source. Returns via .ok / .start_t.
# ============================================================
procedure findIRStart: .m, .r
    .n = .r
    .ok = 0
    .start_t = 0
    .tries = 0
    while .tries < 100000 and .ok = 0
        .st = .n * hop_duration
        # Accept if the IR window starts in-bounds AND has at least
        # a minimum of audio available (enough for a non-trivial IR).
        .min_useful = ir_duration * 0.25
        .avail = src_dur - .st
        if .st >= 0 and .st < src_dur and .avail >= .min_useful
            .start_t = .st
            .ok = 1
        else
            # Still searching. Advance to next hit or give up.
            if .st >= src_dur
                # We've gone past the end without success; fail.
                .tries = 100000
            else
                .n = .n + .m
                .tries = .tries + 1
            endif
        endif
    endwhile
endproc

# ============================================================
# INITIAL IR HARVEST
# ============================================================
appendInfoLine: ""
appendInfoLine: "--- Harvesting initial IRs ---"

@findIRStart: m1, i1
if findIRStart.ok = 0
    exitScript: "Could not find a valid IR_A harvest location. Source may be too short for the requested grain/IR sizes."
endif
start_A = findIRStart.start_t
@harvestIR: start_A, "A"
ir_A_id = new_ir_id
appendInfoLine: "IR_A at t=", fixed$(start_A, 4), " s"

@findIRStart: m2, i2
if findIRStart.ok = 0
    removeObject: ir_A_id
    exitScript: "Could not find a valid IR_B harvest location. Source may be too short for the requested grain/IR sizes."
endif
start_B = findIRStart.start_t
@harvestIR: start_B, "B"
ir_B_id = new_ir_id
appendInfoLine: "IR_B at t=", fixed$(start_B, 4), " s"

# Crossfade state
xfade_A_active  = 0
xfade_A_counter = 0
xfade_B_active  = 0
xfade_B_counter = 0
ir_A_old_id     = -1
ir_B_old_id     = -1

# ============================================================
# CREATE OUTPUT BUFFER (silent, full length, matches source channels)
# ============================================================
out_dur = src_dur + tail_duration
out_buf_id = Create Sound from formula: "out_buf",
    ... src_ch, 0, out_dur, src_sr, "0"
appendInfoLine: "Output buffer: ", fixed$(out_dur, 3),
    ... " s  (", src_ch, " ch)"

# ============================================================
# MAIN LOOP
# ============================================================
if src_dur <= segment_duration
    n_segments = 1
else
    n_segments = floor((src_dur - segment_duration) / hop_duration) + 1
    last_regular_end = (n_segments - 1) * hop_duration + segment_duration
    # Add one end-anchored grain only when the regular grid leaves >= one sample.
    if last_regular_end < src_dur - 0.5 / src_sr
        n_segments = n_segments + 1
    endif
endif
appendInfoLine: ""
appendInfoLine: "Grains to process: ", n_segments
appendInfoLine: "--- Processing ---"

# Pre-allocated bookkeeping vector (replaces per-grain scalar variables).
# 0 = unused, 1 = sieve A, 2 = sieve B, 3 = dry
grain_type# = zero#(n_segments)

# Remember IR-update events for the visualization
updateCap = 1024
irUpdateTimes# = zero#(updateCap)
irUpdateKinds# = zero#(updateCap)
nIrUpdates = 0

for n from 0 to n_segments - 1

    t_start = n * hop_duration
    if t_start + segment_duration > src_dur
        t_start = max(0, src_dur - segment_duration)
    endif
    t_end   = t_start + segment_duration
    if t_end > src_dur
        t_end = src_dur
    endif

    # Grain must have positive duration; otherwise mark as dry-skip
    # and move on without a goto.
    if t_end > t_start

        # Extract grain — Hanning window applied by Extract part
        selectObject: source_id
        grain_id = Extract part: src_t0 + t_start, src_t0 + t_end, "Hanning", 1, "no"
        Rename: "grain_raw"

        # Measure dry RMS for gain-matching wet grains
        @getRMS: grain_id
        dry_rms = proc_rms

        sieve_A_hit = 0
        sieve_B_hit = 0
        if (n mod m1) = i1
            sieve_A_hit = 1
        endif
        if (n mod m2) = i2
            sieve_B_hit = 1
        endif

        processed_id = -1

        if sieve_A_hit = 1
            grain_type#[n + 1] = 1

            # Choose or blend IR_A
            if xfade_A_active = 1
                xfade_A_counter = xfade_A_counter + 1
                w_new = xfade_A_counter / ir_crossfade_grains
                if w_new > 1
                    w_new = 1
                endif
                @blendIRs: ir_A_id, ir_A_old_id, w_new
                ir_use_A  = blend_ir_id
                owns_ir_A = 1
                if xfade_A_counter >= ir_crossfade_grains
                    xfade_A_active = 0
                    removeObject: ir_A_old_id
                    ir_A_old_id = -1
                endif
            else
                ir_use_A  = ir_A_id
                owns_ir_A = 0
            endif

            # Convolve
            selectObject: grain_id
            plusObject: ir_use_A
            conv_id = Convolve: "sum", "zero"
            removeObject: grain_id
            if owns_ir_A = 1
                removeObject: ir_use_A
            endif

            # Trim to segment + tail
            selectObject: conv_id
            conv_dur = Get total duration
            keep_end = segment_duration + tail_duration
            if keep_end > conv_dur
                keep_end = conv_dur
            endif
            wet_id = Extract part: 0, keep_end, "rectangular", 1, "no"
            removeObject: conv_id

            # RMS-match to dry grain level
            @getRMS: wet_id
            wet_rms = proc_rms
            if wet_rms > 1e-9 and dry_rms > 1e-9
                match_gain = dry_rms / wet_rms
                @scaleBy: wet_id, match_gain
            endif

            # Fade in + out (portable min via explicit compare).
            # Note: 'fi' is a Praat keyword (Formula-if terminator),
            # so we must not use it as a variable name here.
            fadeIn = hop_duration * 0.5
            if keep_end * 0.1 < fadeIn
                fadeIn = keep_end * 0.1
            endif
            fadeOut = hop_duration
            if keep_end * 0.3 < fadeOut
                fadeOut = keep_end * 0.3
            endif
            @applyHalfHann: wet_id, "in",  fadeIn
            @applyHalfHann: wet_id, "out", fadeOut

            processed_id = wet_id

        elsif sieve_B_hit = 1
            grain_type#[n + 1] = 2

            if xfade_B_active = 1
                xfade_B_counter = xfade_B_counter + 1
                w_new = xfade_B_counter / ir_crossfade_grains
                if w_new > 1
                    w_new = 1
                endif
                @blendIRs: ir_B_id, ir_B_old_id, w_new
                ir_use_B  = blend_ir_id
                owns_ir_B = 1
                if xfade_B_counter >= ir_crossfade_grains
                    xfade_B_active = 0
                    removeObject: ir_B_old_id
                    ir_B_old_id = -1
                endif
            else
                ir_use_B  = ir_B_id
                owns_ir_B = 0
            endif

            selectObject: grain_id
            plusObject: ir_use_B
            conv_id = Convolve: "sum", "zero"
            removeObject: grain_id
            if owns_ir_B = 1
                removeObject: ir_use_B
            endif

            selectObject: conv_id
            conv_dur = Get total duration
            keep_end = segment_duration + tail_duration
            if keep_end > conv_dur
                keep_end = conv_dur
            endif
            wet_id = Extract part: 0, keep_end, "rectangular", 1, "no"
            removeObject: conv_id

            @getRMS: wet_id
            wet_rms = proc_rms
            if wet_rms > 1e-9 and dry_rms > 1e-9
                match_gain = dry_rms / wet_rms
                @scaleBy: wet_id, match_gain
            endif

            fadeIn = hop_duration * 0.5
            if keep_end * 0.1 < fadeIn
                fadeIn = keep_end * 0.1
            endif
            fadeOut = hop_duration
            if keep_end * 0.3 < fadeOut
                fadeOut = keep_end * 0.3
            endif
            @applyHalfHann: wet_id, "in",  fadeIn
            @applyHalfHann: wet_id, "out", fadeOut

            processed_id = wet_id

        else
            grain_type#[n + 1] = 3

            # Dry: already Hann-windowed; just scale
            @scaleBy: grain_id, dry_gain
            processed_id = grain_id
        endif

        # OLA mix into output buffer
        @mixIntoBuffer: out_buf_id, processed_id, t_start
        removeObject: processed_id

        # Adaptive IR re-harvest
        if adaptive_updates = 1 and n > 0 and (n mod adaptive_update_interval) = 0

            # Next sieve-A-consistent grain index from current n
            candidate_A = n
            if (candidate_A mod m1) <> i1
                candidate_A = candidate_A + ((m1 - (candidate_A mod m1) + i1) mod m1)
            endif
            cand_A_start = candidate_A * hop_duration
            cand_A_avail = src_dur - cand_A_start
            if cand_A_avail >= ir_duration * 0.25 and cand_A_start < src_dur
                if ir_A_old_id <> -1
                    removeObject: ir_A_old_id
                endif
                ir_A_old_id     = ir_A_id
                @harvestIR: cand_A_start, "A_new"
                ir_A_id         = new_ir_id
                xfade_A_active  = 1
                xfade_A_counter = 0
                if nIrUpdates < updateCap
                    nIrUpdates = nIrUpdates + 1
                    irUpdateTimes#[nIrUpdates] = cand_A_start
                    irUpdateKinds#[nIrUpdates] = 1
                endif
                appendInfoLine: "Adaptive: IR_A updating at grain ", n,
                    ... " t=", fixed$(cand_A_start, 3)
            endif

            candidate_B = n
            if (candidate_B mod m2) <> i2
                candidate_B = candidate_B + ((m2 - (candidate_B mod m2) + i2) mod m2)
            endif
            cand_B_start = candidate_B * hop_duration
            cand_B_avail = src_dur - cand_B_start
            if cand_B_avail >= ir_duration * 0.25 and cand_B_start < src_dur
                if ir_B_old_id <> -1
                    removeObject: ir_B_old_id
                endif
                ir_B_old_id     = ir_B_id
                @harvestIR: cand_B_start, "B_new"
                ir_B_id         = new_ir_id
                xfade_B_active  = 1
                xfade_B_counter = 0
                if nIrUpdates < updateCap
                    nIrUpdates = nIrUpdates + 1
                    irUpdateTimes#[nIrUpdates] = cand_B_start
                    irUpdateKinds#[nIrUpdates] = 2
                endif
                appendInfoLine: "Adaptive: IR_B updating at grain ", n,
                    ... " t=", fixed$(cand_B_start, 3)
            endif
        endif

    else
        # Degenerate grain (zero-length slice at end-of-source).
        grain_type#[n + 1] = 3
    endif

endfor

# ============================================================
# FINALISE
# ============================================================
if ir_A_old_id <> -1
    removeObject: ir_A_old_id
endif
if ir_B_old_id <> -1
    removeObject: ir_B_old_id
endif
removeObject: ir_A_id
removeObject: ir_B_id

selectObject: out_buf_id
Scale peak: 0.9
@applyHalfHann: out_buf_id, "in",  0.01
@applyHalfHann: out_buf_id, "out", 0.02
Rename: "SieveConv_" + source_name$
output_id = selected("Sound")

selectObject: output_id
out_dur_final = Get total duration
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Output duration: ", fixed$(out_dur_final, 3), " s"

# Count grain types for the summary
nA = 0
nB = 0
nD = 0
for n from 1 to n_segments
    if grain_type#[n] = 1
        nA = nA + 1
    elsif grain_type#[n] = 2
        nB = nB + 1
    else
        nD = nD + 1
    endif
endfor

# ============================================================
# VISUALIZATION — 8-inch canvas, matches the library standard
# ============================================================
if draw_visualization
    appendInfoLine: "Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # --- Title ---
    # v5.2: explicit inner viewport (the hand-tuned -1.22 offset
    # depended on the margin-compressed mapping)
    Select outer viewport: 0, 8, 0, 0.50
    Select inner viewport: 0, 8, 0, 0.50
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half", "##Self-Adaptive Sieve Convolution v5.3##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.24, "half",
        ... source_name$
        ... + "   |   A: n mod " + string$(m1) + "=" + string$(i1)
        ... + "   B: n mod " + string$(m2) + "=" + string$(i2)
        ... + "   |   grain=" + string$(segment_ms) + "ms"
        ... + "   IR=" + string$(ir_ms) + "ms"

    # --- Source waveform ---
    Select outer viewport: 0, 8, 0.55, 1.85
    Select inner viewport: 0.6, 7.7, 0.65, 1.80
    selectObject: source_id
    srcPeakViz = Get absolute extremum: 0, 0, "None"
    if srcPeakViz < 1e-12
        srcPeakViz = 1
    endif
    srcPeakViz = 1.05 * srcPeakViz
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, -srcPeakViz, srcPeakViz, "no", "Curve"
    Select inner viewport: 0.6, 7.7, 0.65, 1.80
    Axes: src_t0, src_t0 + src_dur, -srcPeakViz, srcPeakViz

    # Initial and adaptive IR harvest positions on the source itself.
    Line width: 1
    Colour: "{0.80, 0.30, 0.30}"
    Draw line: src_t0 + start_A, -srcPeakViz, src_t0 + start_A, srcPeakViz
    Colour: "{0.30, 0.70, 0.30}"
    Draw line: src_t0 + start_B, -srcPeakViz, src_t0 + start_B, srcPeakViz
    Line width: 0.6
    for u from 1 to nIrUpdates
        if irUpdateKinds#[u] = 1
            Colour: "{0.60, 0.15, 0.15}"
        else
            Colour: "{0.15, 0.50, 0.15}"
        endif
        Draw line: src_t0 + irUpdateTimes#[u], -srcPeakViz, src_t0 + irUpdateTimes#[u], srcPeakViz
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Source"
    Text top: "no", "Source (red/green = IR harvest positions)"

    # --- Output waveform ---
    Select outer viewport: 0, 8, 1.90, 3.40
    Select inner viewport: 0.6, 7.7, 2.00, 3.35
    selectObject: output_id
    Colour: "{0.20, 0.45, 0.75}"
    Draw: 0, 0, 0, 0, "no", "Curve"

    # Set axes explicitly so sieve ticks land where we intend.
    Axes: 0, out_dur_final, -1, 1

    # Sieve-hit ticks — thin, at top and bottom edges only, so the
    # waveform stays readable.
    Line width: 0.6
    for n from 0 to n_segments - 1
        t_s = n * hop_duration
        if t_s + segment_duration > src_dur
            t_s = max(0, src_dur - segment_duration)
        endif
        if grain_type#[n + 1] = 1
            Colour: "{0.80, 0.30, 0.30}"
            Draw line: t_s, -0.98, t_s, -0.88
            Draw line: t_s,  0.88, t_s,  0.98
        elsif grain_type#[n + 1] = 2
            Colour: "{0.30, 0.70, 0.30}"
            Draw line: t_s, -0.98, t_s, -0.88
            Draw line: t_s,  0.88, t_s,  0.98
        endif
    endfor

    # IR-update markers — thin vertical lines across the full height
    # to show where the adaptive re-harvest fires.
    Line width: 1.0
    for u from 1 to nIrUpdates
        t_u = irUpdateTimes#[u]
        if irUpdateKinds#[u] = 1
            Colour: "{0.60, 0.15, 0.15}"
        else
            Colour: "{0.15, 0.50, 0.15}"
        endif
        Draw line: t_u, -0.98, t_u, 0.98
    endfor

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text top: "no", "Output waveform (ticks = sieve hits; full lines = IR updates)"

    # --- Spectrogram of output ---
    Select outer viewport: 0, 8, 3.45, 5.45
    Select inner viewport: 0.6, 7.7, 3.55, 5.40

    if src_ch > 1
        selectObject: output_id
        tmp_mono_id = Extract one channel: 1
        selectObject: tmp_mono_id
    else
        selectObject: output_id
        Copy: "spec_src_tmp"
        tmp_mono_id = selected("Sound")
    endif
    vizFreqMax = min(5000, src_sr / 2)
    To Spectrogram: 0.03, vizFreqMax, 0.002, 20, "Gaussian"
    spectrogram_id = selected("Spectrogram")
    Paint: 0, 0, 0, vizFreqMax, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Output spectrogram"
    removeObject: spectrogram_id
    removeObject: tmp_mono_id

    # --- Summary panel ---
    Select outer viewport: 0, 8, 5.55, 7.75
    Select inner viewport: 0.6, 7.7, 5.65, 7.70
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    # Colour-key row inside the summary panel (top line)
    Font size: 7
    Colour: "{0.80, 0.30, 0.30}"
    Text: 0.04, "left", 0.88, "half", "■ Sieve A hit"
    Colour: "{0.30, 0.70, 0.30}"
    Text: 0.22, "left", 0.88, "half", "■ Sieve B hit"
    Colour: "{0.60, 0.15, 0.15}"
    Text: 0.42, "left", 0.88, "half", "│ IR_A update"
    Colour: "{0.15, 0.50, 0.15}"
    Text: 0.62, "left", 0.88, "half", "│ IR_B update"

    Font size: 7
    Colour: "Black"
    Text: 0.04, "left", 0.68, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.04, "left", 0.54, "half",
        ... "Grains: " + string$(n_segments)
        ... + "   |   Sieve-A hits: " + string$(nA)
        ... + "   |   Sieve-B hits: " + string$(nB)
        ... + "   |   Dry: " + string$(nD)
        ... + "   |   IR updates: " + string$(nIrUpdates)
    Text: 0.04, "left", 0.36, "half",
        ... "Hop: " + fixed$(hop_duration * 1000, 1) + "ms"
        ... + "   |   Tail: " + string$(tail_ms) + "ms"
        ... + "   |   IR HP: " + string$(ir_hp_hz) + " Hz"
        ... + "   |   Dry gain: " + fixed$(dry_gain, 2)
    Text: 0.04, "left", 0.18, "half",
        ... "Adaptive: " + string$(adaptive_updates)
        ... + "   |   Update every: " + string$(adaptive_update_interval) + " grains"
        ... + "   |   Crossfade: " + string$(ir_crossfade_grains) + " grains"
        ... + "   |   Source: " + string$(src_ch) + " ch"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================
# PLAY
# ============================================================
if play_result
    selectObject: output_id
    Play
endif

selectObject: output_id
