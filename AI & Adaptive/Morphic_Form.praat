# ============================================================
# Praat AudioTools - Morphic_Form.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Morphic Form - Spectral-preserving grain placement engine.
#   Generates MORPHIC FORM by controlling ONLY grain placement:
#   size, density, time jitter, backtrack probability, repeat
#   probability. Spectral content is never altered.
#
#   CONCEPTUAL MODEL:
#   Two attractors define placement behavior extremes.
#   A gradient-descent state walks smoothly from A toward B
#   over the output duration, modulated frame-by-frame by local
#   acoustic features extracted from the original.
#
#   Attractor A (Stable / Sparse / Coherent):
#     larger grains, lower density, low jitter, mostly forward,
#     rare repeats, occasional silence gaps.
#
#   Attractor B (Turbulent / Dense / Unstable):
#     shorter grains, higher density, high jitter,
#     more backtracks and repeats, no silence gaps.
#
#   OUTPUT DURATION CONTROL:
#   The output can be shorter or longer than the source.
#   Source read position is decoupled from output position
#   via a time ratio: src_pos = (out_t / out_dur) * src_dur.
#   Ratio < 1: compressed reading (time acceleration).
#   Ratio > 1: stretched reading (time dilation, with wrapping).
#
#   DESIGN LINEAGE from AudioTools library:
#   - OT_CORPUS_CONCATENATOR:    Attractor/constraint weight model.
#   - HMM_Timbre_Sequencing:     Feature extraction pipeline.
#   - Gestural_Accumulator:      Pacing curves + rolling concat.
#   - Genetic_Recomposer:        Grain schedule + assembly phases.
#   - Neural_Adaptive_Phonetic_Vibrato: GD adaptive parameters.
#   - Perceptual_Synchrony:      Activity proxy + feature norms.
#
# Changelog v1.1:
#   - Added output duration control (ratio or absolute seconds)
#   - Fixed: pacing_curve$ now defined before use
#   - Fixed: max() replaced with Praat-safe conditional
#   - Fixed: mod operator replaced with floor trick
#   - Fixed: grain fade formula uses xmin-relative positions
#   - Fixed: Unicode box chars replaced with ASCII
#   - Fixed: duration underrun padding after assembly
#   - Added max_grains scaling with output duration
#   - Improved presets (duration ratio per preset)
#   - Added two new presets (Time Stretch, Collapse)
#   - 8-inch viewport with legend strip
#   - Source read position decoupled from output timeline
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Category: Composition
# ============================================================

# ============================================================
# INPUT VALIDATION
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object before running."
endif

src_id = selected("Sound")
src_name$ = selected$("Sound")

# ============================================================
# FORM
# ============================================================

form Morphic Form v1.1  (Grain Placement Engine)
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Slow Bloom  (gentle A->B, large grains)
        option Tidal Surge  (aggressive A->B, accelerating)
        option Nervous Scatter  (B-dominant, dense + jittery)
        option Still Center  (A-dominant, minimal morphing)
        option Time Stretch  (2x duration, slow drift)
        option Collapse  (half duration, rapid compression)
    comment === Morphic Control ===
    real Morph_intensity 0.75
    comment (0.0 = stay at A entirely | 1.0 = fully reach B)
    positive Base_grain_ms 40.0
    positive Base_density_gps 25.0
    comment (grains per second)
    positive Max_jitter_ms 15.0
    comment === Duration ===
    positive Output_duration_ratio 1.0
    comment (1.0 = same as input, 2.0 = double, 0.5 = half)
    comment === Pacing Curve  (Gestural_Accumulator) ===
    optionmenu Pacing_curve 1
        option Linear
        option Accelerate  (slow start, rush to B)
        option Decelerate  (explosive start, then stabilize)
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESET LOGIC
# ============================================================

if preset = 2
    # Slow Bloom: gentle transition, large grains, natural duration
    morph_intensity = 0.60
    base_grain_ms = 52.0
    base_density_gps = 17.0
    max_jitter_ms = 7.0
    output_duration_ratio = 1.0
    pacing_curve = 1
    preset_name$ = "Slow Bloom"
elsif preset = 3
    # Tidal Surge: aggressive accelerating morph
    morph_intensity = 0.90
    base_grain_ms = 30.0
    base_density_gps = 38.0
    max_jitter_ms = 28.0
    output_duration_ratio = 1.2
    pacing_curve = 2
    preset_name$ = "Tidal Surge"
elsif preset = 4
    # Nervous Scatter: B-dominant from the start, very dense
    morph_intensity = 0.95
    base_grain_ms = 22.0
    base_density_gps = 52.0
    max_jitter_ms = 40.0
    output_duration_ratio = 0.85
    pacing_curve = 1
    preset_name$ = "Nervous Scatter"
elsif preset = 5
    # Still Center: mostly A, minimal morphing
    morph_intensity = 0.15
    base_grain_ms = 68.0
    base_density_gps = 11.0
    max_jitter_ms = 4.0
    output_duration_ratio = 1.0
    pacing_curve = 3
    preset_name$ = "Still Center"
elsif preset = 6
    # Time Stretch: double duration with slow spectral drift
    morph_intensity = 0.45
    base_grain_ms = 60.0
    base_density_gps = 20.0
    max_jitter_ms = 12.0
    output_duration_ratio = 2.0
    pacing_curve = 3
    preset_name$ = "Time Stretch"
elsif preset = 7
    # Collapse: half duration, rapid compression
    morph_intensity = 0.80
    base_grain_ms = 25.0
    base_density_gps = 45.0
    max_jitter_ms = 20.0
    output_duration_ratio = 0.5
    pacing_curve = 2
    preset_name$ = "Collapse"
else
    preset_name$ = "Custom"
endif

# Pacing curve name
if pacing_curve = 2
    pacing_curve$ = "Accelerate"
elsif pacing_curve = 3
    pacing_curve$ = "Decelerate"
else
    pacing_curve$ = "Linear"
endif

# ============================================================
# PARAMETER CLAMPING
# ============================================================

if morph_intensity < 0.0
    morph_intensity = 0.0
endif
if morph_intensity > 1.0
    morph_intensity = 1.0
endif
if base_grain_ms < 10.0
    base_grain_ms = 10.0
endif
if base_grain_ms > 120.0
    base_grain_ms = 120.0
endif
if base_density_gps < 5.0
    base_density_gps = 5.0
endif
if base_density_gps > 80.0
    base_density_gps = 80.0
endif
if max_jitter_ms < 0.0
    max_jitter_ms = 0.0
endif
if max_jitter_ms > 50.0
    max_jitter_ms = 50.0
endif
if output_duration_ratio < 0.1
    output_duration_ratio = 0.1
endif
if output_duration_ratio > 10.0
    output_duration_ratio = 10.0
endif

# ============================================================
# SETUP
# ============================================================

selectObject: src_id
src_dur = Get total duration
src_sr = Get sampling frequency
src_ch = Get number of channels

if src_dur < 0.10
    exitScript: "Sound too short (minimum 100 ms required)."
endif

# Output duration
out_dur = src_dur * output_duration_ratio

# Time ratio: how fast we read source relative to output
# src_pos_base = (out_t / out_dur) * src_dur
time_ratio = src_dur / out_dur

clearinfo
writeInfoLine: "=================================================="
writeInfoLine: "  MORPHIC FORM v1.1  |  Grain Placement Engine"
writeInfoLine: "=================================================="
appendInfoLine: ""
appendInfoLine: "Source  : ", src_name$
appendInfoLine: "Preset  : ", preset_name$
appendInfoLine: "Morph   : ", fixed$(morph_intensity, 2),
    ... "  |  Pacing: ", pacing_curve$
appendInfoLine: ""
appendInfoLine: "Source duration : ", fixed$(src_dur, 3), " s"
appendInfoLine: "Output duration : ", fixed$(out_dur, 3), " s",
    ... " (ratio: ", fixed$(output_duration_ratio, 2), "x)"
appendInfoLine: "SR             : ", src_sr, " Hz"
appendInfoLine: "Channels       : ", src_ch

# ============================================================
# STEP 1: FEATURE EXTRACTION
#   Following HMM_Timbre_Sequencing pipeline:
#   intensity + pitch voicing confidence per analysis frame.
#   Activity proxy from Perceptual_Synchrony gesture detection.
#   Analysis frames span the OUTPUT duration, reading source
#   via time ratio.
# ============================================================

appendInfoLine: ""
appendInfoLine: "[1/6] Feature extraction (HMM pipeline)..."

af_hop_s = 0.050
n_af = floor(out_dur / af_hop_s)
if n_af < 2
    n_af = 2
endif

selectObject: src_id
src_mono_id = Convert to mono
Rename: "MorphicAnalysisMono"

selectObject: src_mono_id
To Intensity: 75, af_hop_s, "yes"
int_obj_id = selected("Intensity")

selectObject: src_mono_id
To Pitch (ac): 0, 75, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14, 600
pit_obj_id = selected("Pitch")

af_time# = zero#(n_af)
af_int_raw# = zero#(n_af)
af_voicing# = zero#(n_af)

for i to n_af
    # Output time for this analysis frame
    t_out = (i - 0.5) * af_hop_s
    if t_out > out_dur - 0.001
        t_out = out_dur - 0.001
    endif
    af_time#[i] = t_out

    # Corresponding source time (wrapping for ratio > 1)
    t_src = t_out * time_ratio
    # Wrap into source range for stretched outputs
    while t_src >= src_dur
        t_src = t_src - src_dur
    endwhile
    if t_src < 0
        t_src = 0
    endif

    selectObject: int_obj_id
    iv = Get value at time: t_src, "Cubic"
    if iv = undefined
        iv = 60
    endif
    af_int_raw#[i] = iv

    selectObject: pit_obj_id
    pv = Get value at time: t_src, "Hertz", "Linear"
    if pv = undefined
        pv = 0
    endif
    if pv > 0
        af_voicing#[i] = 1
    else
        af_voicing#[i] = 0
    endif
endfor

removeObject: int_obj_id
removeObject: pit_obj_id
removeObject: src_mono_id

# Normalize intensity
min_iv = af_int_raw#[1]
max_iv = af_int_raw#[1]
for i from 2 to n_af
    if af_int_raw#[i] < min_iv
        min_iv = af_int_raw#[i]
    endif
    if af_int_raw#[i] > max_iv
        max_iv = af_int_raw#[i]
    endif
endfor
iv_range = max_iv - min_iv
if iv_range < 0.001
    iv_range = 0.001
endif

norm_int# = zero#(n_af)
for i to n_af
    norm_int#[i] = (af_int_raw#[i] - min_iv) / iv_range
endfor

# Activity = frame-to-frame intensity change
af_activity# = zero#(n_af)
for i from 2 to n_af
    af_activity#[i] = abs(norm_int#[i] - norm_int#[i - 1])
endfor
max_act = 0.001
for i to n_af
    if af_activity#[i] > max_act
        max_act = af_activity#[i]
    endif
endfor
for i to n_af
    af_activity#[i] = af_activity#[i] / max_act
endfor

appendInfoLine: "  Analysis frames : ", n_af,
    ... " (hop=", fixed$(af_hop_s * 1000, 0), " ms)"

# ============================================================
# STEP 2: MORPHIC CURVE
#   Gestural_Accumulator pacing_curve logic.
#   Linear / Accelerate / Decelerate ease functions.
# ============================================================

appendInfoLine: ""
appendInfoLine: "[2/6] Morphic curve (Gestural pacing)..."

morph_curve# = zero#(n_af)

divisor = n_af - 1
if divisor < 1
    divisor = 1
endif

for i to n_af
    t_norm = (i - 1) / divisor

    if pacing_curve = 2
        t_eased = t_norm * t_norm
    elsif pacing_curve = 3
        t_eased = 1.0 - (1.0 - t_norm) * (1.0 - t_norm)
    else
        t_eased = t_norm
    endif

    morph_curve#[i] = t_eased * morph_intensity
endfor

# ============================================================
# STEP 3: ATTRACTOR DEFINITIONS
#   A and B are behavioral poles.
#   Parameters interpolate linearly between them.
# ============================================================

appendInfoLine: ""
appendInfoLine: "[3/6] Attractor definitions..."

att_a_grain_ms = base_grain_ms * 1.35
att_a_density = base_density_gps * 0.55
att_a_jitter_ms = max_jitter_ms * 0.08
att_a_bt_prob = 0.02
att_a_rep_prob = 0.04
att_a_sil_prob = 0.07
att_a_sil_ms = 40.0

att_b_grain_ms = base_grain_ms * 0.67
att_b_density = base_density_gps * 1.90
att_b_jitter_ms = max_jitter_ms
att_b_bt_prob = 0.22
att_b_rep_prob = 0.28
att_b_sil_prob = 0.0
att_b_sil_ms = 0.0

if att_a_grain_ms < 15.0
    att_a_grain_ms = 15.0
endif
if att_a_grain_ms > 150.0
    att_a_grain_ms = 150.0
endif
if att_b_grain_ms < 10.0
    att_b_grain_ms = 10.0
endif
if att_b_grain_ms > 100.0
    att_b_grain_ms = 100.0
endif
if att_a_density < 3.0
    att_a_density = 3.0
endif
if att_b_density > 100.0
    att_b_density = 100.0
endif

appendInfoLine: "  A (stable):    grain=", fixed$(att_a_grain_ms, 0),
    ... " ms  dens=", fixed$(att_a_density, 0),
    ... " g/s  jit=", fixed$(att_a_jitter_ms, 1), " ms"
appendInfoLine: "  B (turbulent): grain=", fixed$(att_b_grain_ms, 0),
    ... " ms  dens=", fixed$(att_b_density, 0),
    ... " g/s  jit=", fixed$(att_b_jitter_ms, 1), " ms"

# ============================================================
# STEP 4: GRADIENT DESCENT ON PLACEMENT PARAMETERS
#   Neural_Adaptive_Phonetic_Vibrato adaptive mixing model.
#   Per analysis frame: local feature push modulates target morph.
#   GD state tracks smoothly with inertia (learning rate).
# ============================================================

appendInfoLine: ""
appendInfoLine: "[4/6] Gradient descent on placement..."

gd_state = 0.0
gd_lr = 0.22
local_weight = 0.30

pf_grain_ms# = zero#(n_af)
pf_density# = zero#(n_af)
pf_jitter# = zero#(n_af)
pf_bt# = zero#(n_af)
pf_rep# = zero#(n_af)
pf_sil_prob# = zero#(n_af)

for i to n_af
    target_m = morph_curve#[i]

    # Local push toward B when activity is high or voicing is weak
    local_push = af_activity#[i] * 0.55 + (1.0 - af_voicing#[i]) * 0.45

    adj_target = target_m + local_weight * local_push
    if adj_target > 1.0
        adj_target = 1.0
    endif
    if adj_target < 0.0
        adj_target = 0.0
    endif

    # Gradient step (inertial update)
    gd_err = adj_target - gd_state
    gd_state = gd_state + gd_lr * gd_err
    if gd_state > 1.0
        gd_state = 1.0
    endif
    if gd_state < 0.0
        gd_state = 0.0
    endif

    m = gd_state

    pf_grain_ms#[i] = att_a_grain_ms + m * (att_b_grain_ms - att_a_grain_ms)
    pf_density#[i] = att_a_density + m * (att_b_density - att_a_density)
    pf_jitter#[i] = att_a_jitter_ms + m * (att_b_jitter_ms - att_a_jitter_ms)
    pf_bt#[i] = att_a_bt_prob + m * (att_b_bt_prob - att_a_bt_prob)
    pf_rep#[i] = att_a_rep_prob + m * (att_b_rep_prob - att_a_rep_prob)
    pf_sil_prob#[i] = att_a_sil_prob + m * (att_b_sil_prob - att_a_sil_prob)
endfor

# ============================================================
# STEP 5: GRAIN SCHEDULE GENERATION
#   Grain schedule walks the OUTPUT timeline (out_dur).
#   Source read position is mapped via time ratio with wrapping.
# ============================================================

appendInfoLine: ""
appendInfoLine: "[5/6] Grain schedule..."

# Scale max grains with output duration
max_grains = floor(out_dur * 80)
if max_grains < 500
    max_grains = 500
endif
if max_grains > 6000
    max_grains = 6000
endif

grain_count = 0
out_t = 0.0
last_src = 0.0

viz_grain_max = 800
viz_out_t# = zero#(viz_grain_max)
viz_src_t# = zero#(viz_grain_max)

while out_t < out_dur and grain_count < max_grains
    # Which analysis frame governs this output position?
    af_i = floor(out_t / af_hop_s) + 1
    if af_i > n_af
        af_i = n_af
    endif
    if af_i < 1
        af_i = 1
    endif

    cur_gr_ms = pf_grain_ms#[af_i]
    cur_dens = pf_density#[af_i]
    cur_jit = pf_jitter#[af_i]
    cur_bt = pf_bt#[af_i]
    cur_rep = pf_rep#[af_i]
    cur_sil = pf_sil_prob#[af_i]

    cur_gr_s = cur_gr_ms / 1000.0
    hop_s = 1.0 / cur_dens

    # Source position: proportional mapping from output to source
    src_pos = out_t * time_ratio + randomGauss(0.0, cur_jit / 1000.0)

    # Wrap into source range (for outputs longer than source)
    while src_pos >= src_dur
        src_pos = src_pos - src_dur
    endwhile

    # Backtrack: occasionally step backward in source
    if randomUniform(0.0, 1.0) < cur_bt
        src_pos = src_pos - randomUniform(0.04, 0.22)
    endif

    # Repeat: re-read from last valid source position
    if randomUniform(0.0, 1.0) < cur_rep
        src_pos = last_src
    endif

    # Clamp source position
    if src_pos < 0.0
        src_pos = 0.0
    endif
    if src_pos + cur_gr_s > src_dur - 0.001
        src_pos = src_dur - cur_gr_s - 0.001
    endif
    if src_pos < 0.0
        src_pos = 0.0
    endif

    actual_gr_s = cur_gr_s
    if actual_gr_s > src_dur - src_pos - 0.001
        actual_gr_s = src_dur - src_pos - 0.001
    endif

    if actual_gr_s >= 0.010
        grain_count = grain_count + 1
        g_src_'grain_count' = src_pos
        g_dur_'grain_count' = actual_gr_s
        g_sil_'grain_count' = 0
        last_src = src_pos

        if grain_count <= viz_grain_max
            viz_out_t#[grain_count] = out_t
            viz_src_t#[grain_count] = src_pos
        endif

        # Silence insertion (Attractor A behavior only)
        if randomUniform(0.0, 1.0) < cur_sil and grain_count < max_grains
            sil_dur = randomUniform(0.012, att_a_sil_ms / 1000.0)
            if sil_dur > 0.001
                grain_count = grain_count + 1
                g_src_'grain_count' = 0.0
                g_dur_'grain_count' = sil_dur
                g_sil_'grain_count' = 1
            endif
        endif
    endif

    out_t = out_t + hop_s
endwhile

n_viz_grains = grain_count
if n_viz_grains > viz_grain_max
    n_viz_grains = viz_grain_max
endif

appendInfoLine: "  Grains scheduled : ", grain_count,
    ... " (max: ", max_grains, ")"

if grain_count < 1
    exitScript: "No grains generated. Try reducing density or increasing duration."
endif

# ============================================================
# STEP 6: GRAIN EXTRACTION + ROLLING ASSEMBLY
#   Each grain is extracted with 10% fade in/out (xmin-relative).
#   Grain+grain boundaries use crossfade; silence boundaries
#   use hard concatenation.
# ============================================================

appendInfoLine: ""
appendInfoLine: "[6/6] Assembling grains..."

# Extract first grain or silence
k = 1
sil_val_k = g_sil_'k'
if sil_val_k = 1
    Create Sound from formula: "mg_sil", src_ch, 0.0, g_dur_'k', src_sr, "0"
    result_id = selected("Sound")
else
    selectObject: src_id
    g_start = g_src_'k'
    g_end = g_start + g_dur_'k'
    Extract part: g_start, g_end, "rectangular", 1.0, "no"
    result_id = selected("Sound")
    # Fade in/out using xmin-relative positions
    selectObject: result_id
    Formula: "if x - xmin < (xmax - xmin) * 0.10"
        ... + " then self * ((x - xmin) / ((xmax - xmin) * 0.10))"
        ... + " else (if x > xmax - (xmax - xmin) * 0.10"
        ... + " then self * ((xmax - x) / ((xmax - xmin) * 0.10))"
        ... + " else self fi) fi"
endif

for k from 2 to grain_count
    sil_val_k = g_sil_'k'
    if sil_val_k = 1
        Create Sound from formula: "mg_sil", src_ch, 0.0, g_dur_'k', src_sr, "0"
        next_id = selected("Sound")
    else
        selectObject: src_id
        g_start = g_src_'k'
        g_end = g_start + g_dur_'k'
        Extract part: g_start, g_end, "rectangular", 1.0, "no"
        next_id = selected("Sound")
        selectObject: next_id
        Formula: "if x - xmin < (xmax - xmin) * 0.10"
            ... + " then self * ((x - xmin) / ((xmax - xmin) * 0.10))"
            ... + " else (if x > xmax - (xmax - xmin) * 0.10"
            ... + " then self * ((xmax - x) / ((xmax - xmin) * 0.10))"
            ... + " else self fi) fi"
    endif

    # Determine crossfade (grain+grain only)
    prev_k = k - 1
    prev_sil_val = g_sil_'prev_k'
    xfade = 0.0
    if prev_sil_val = 0 and sil_val_k = 0
        prev_dur = g_dur_'prev_k'
        cur_dur = g_dur_'k'
        min_dur = prev_dur
        if cur_dur < min_dur
            min_dur = cur_dur
        endif
        xfade = min_dur * 0.08
        if xfade < 0.001
            xfade = 0.0
        endif
        if xfade > 0.020
            xfade = 0.020
        endif
    endif

    selectObject: result_id
    plusObject: next_id

    if xfade > 0.001
        Concatenate with overlap: xfade
    else
        Concatenate
    endif

    assembled_id = selected("Sound")
    removeObject: result_id
    removeObject: next_id
    result_id = assembled_id

    kDiv200 = k - floor(k / 200) * 200
    if kDiv200 = 0
        appendInfo: "."
    endif
endfor

appendInfoLine: ""

# Trim or pad to target output duration
selectObject: result_id
assembled_dur = Get total duration

if assembled_dur > out_dur + 0.01
    Extract part: 0.0, out_dur, "rectangular", 1.0, "no"
    trimmed_id = selected("Sound")
    removeObject: result_id
    result_id = trimmed_id
elsif assembled_dur < out_dur - 0.01
    # Pad with silence to reach target
    padNeeded = out_dur - assembled_dur
    Create Sound from formula: "pad", src_ch, 0, padNeeded, src_sr, "0"
    padSnd = selected("Sound")
    selectObject: result_id, padSnd
    Concatenate
    padded_id = selected("Sound")
    removeObject: result_id, padSnd
    result_id = padded_id
endif

selectObject: result_id
Scale peak: 0.99
Rename: src_name$ + "_morphic"
final_name$ = selected$("Sound")

selectObject: result_id
final_dur = Get total duration

appendInfoLine: "  Output: ", final_name$
appendInfoLine: "  Duration: ", fixed$(final_dur, 3), " s",
    ... " (target: ", fixed$(out_dur, 3), " s)"

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    Erase all

    # === TITLE ===
    Select outer viewport: 0, 8, 0.0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half",
        ... "##Morphic Form v1.1##"
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -0.3, "half",
        ... preset_name$ + " | morph="
        ... + fixed$(morph_intensity, 2)
        ... + " | " + pacing_curve$
        ... + " | ratio=" + fixed$(output_duration_ratio, 2)
        ... + "x | " + string$(grain_count) + " grains"

    # === PANEL 1: Original waveform ===
    Select outer viewport: 0, 4, 0.6, 1.5
    Select inner viewport: 0.6, 3.7, 0.65, 1.45
    selectObject: src_id
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Amp"
    Text top: "no", "Original (" + fixed$(src_dur, 2) + " s)"

    # === PANEL 2: Output waveform ===
    Select outer viewport: 4, 8, 0.6, 1.5
    Select inner viewport: 4.4, 7.7, 0.65, 1.45
    selectObject: result_id
    Colour: "{0.2, 0.45, 0.82}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Amp"
    Text top: "no", "Morphic (" + fixed$(final_dur, 2) + " s)"

    # === PANEL 3: Morphic curve + grain size ===
    Select outer viewport: 0, 4, 1.6, 2.7
    Select inner viewport: 0.6, 3.7, 1.65, 2.65

    Axes: 0, out_dur, 0, 1.05
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, out_dur, 0, 1.05

    # Filled morph area
    for i to n_af
        t_l = af_time#[i] - af_hop_s * 0.5
        t_r = af_time#[i] + af_hop_s * 0.5
        if t_l < 0.0
            t_l = 0.0
        endif
        if t_r > out_dur
            t_r = out_dur
        endif
        Paint rectangle: "{0.82, 0.88, 1.0}", t_l, t_r, 0, morph_curve#[i]
    endfor

    # Morph curve line
    Colour: "{0.82, 0.28, 0.28}"
    Line width: 2
    for i from 1 to n_af - 1
        Draw line: af_time#[i], morph_curve#[i],
            ... af_time#[i + 1], morph_curve#[i + 1]
    endfor

    # Grain size normalized (A=1, B=0)
    gn_range = att_a_grain_ms - att_b_grain_ms
    if gn_range < 0.001
        gn_range = 0.001
    endif
    Colour: "{0.28, 0.62, 0.32}"
    Line width: 1.5
    for i from 1 to n_af - 1
        v1 = (pf_grain_ms#[i] - att_b_grain_ms) / gn_range
        v2 = (pf_grain_ms#[i + 1] - att_b_grain_ms) / gn_range
        Draw line: af_time#[i], v1, af_time#[i + 1], v2
    endfor

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "[0..1]"
    Text top: "no", "Morph Curve + Grain Size"

    # === PANEL 4: Density + Jitter ===
    Select outer viewport: 4, 8, 1.6, 2.7
    Select inner viewport: 4.4, 7.7, 1.65, 2.65

    max_d_axis = att_b_density * 1.12
    Axes: 0, out_dur, 0, max_d_axis
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, out_dur, 0, max_d_axis

    # Density
    Colour: "{0.18, 0.40, 0.82}"
    Line width: 2
    for i from 1 to n_af - 1
        Draw line: af_time#[i], pf_density#[i],
            ... af_time#[i + 1], pf_density#[i + 1]
    endfor

    # Jitter (scaled to axis)
    max_jit_ax = att_b_jitter_ms
    if max_jit_ax < 1.0
        max_jit_ax = 1.0
    endif
    jit_scale = max_d_axis / max_jit_ax
    Colour: "{0.85, 0.50, 0.15}"
    Line width: 1.5
    for i from 1 to n_af - 1
        Draw line: af_time#[i], pf_jitter#[i] * jit_scale,
            ... af_time#[i + 1], pf_jitter#[i + 1] * jit_scale
    endfor

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "g/s"
    Text top: "no", "Density + Jitter"

    # === PANEL 5: Feature trajectories ===
    Select outer viewport: 0, 8, 2.8, 3.8
    Select inner viewport: 0.6, 7.7, 2.85, 3.75

    Axes: 0, out_dur, 0, 1.0
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, out_dur, 0, 1.0

    # Voicing regions shaded
    for i to n_af
        if af_voicing#[i] = 1
            t_l = af_time#[i] - af_hop_s * 0.5
            t_r = af_time#[i] + af_hop_s * 0.5
            if t_l < 0.0
                t_l = 0.0
            endif
            if t_r > out_dur
                t_r = out_dur
            endif
            Paint rectangle: "{0.86, 0.86, 0.94}", t_l, t_r, 0, 1.0
        endif
    endfor

    # Grid midline
    Colour: "{0.88, 0.88, 0.88}"
    Draw line: 0, 0.5, out_dur, 0.5

    # Intensity
    Colour: "{0.22, 0.48, 0.82}"
    Line width: 1.8
    for i from 1 to n_af - 1
        Draw line: af_time#[i], norm_int#[i],
            ... af_time#[i + 1], norm_int#[i + 1]
    endfor

    # Activity
    Colour: "{0.82, 0.28, 0.28}"
    Line width: 1.3
    for i from 1 to n_af - 1
        Draw line: af_time#[i], af_activity#[i],
            ... af_time#[i + 1], af_activity#[i + 1]
    endfor

    # Voicing
    Colour: "{0.28, 0.65, 0.32}"
    Line width: 1.2
    for i from 1 to n_af - 1
        Draw line: af_time#[i], af_voicing#[i] * 0.92,
            ... af_time#[i + 1], af_voicing#[i + 1] * 0.92
    endfor

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Norm"
    Text top: "no", "Features (voiced regions shaded)"
    Text bottom: "yes", "Time (s)"

    # === PANEL 6: Grain read scatter map ===
    Select outer viewport: 0, 8, 3.9, 5.3
    Select inner viewport: 0.6, 7.7, 3.95, 5.25

    Axes: 0, out_dur, 0, src_dur
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, out_dur, 0, src_dur

    # Reference line: proportional read (diagonal if ratio=1)
    Colour: "{0.78, 0.78, 0.78}"
    Line width: 1
    # Draw proportional reference
    nRefPts = 50
    for ri from 1 to nRefPts
        riPrev = ri - 1
        t1 = riPrev / nRefPts * out_dur
        t2 = ri / nRefPts * out_dur
        s1 = t1 * time_ratio
        s2 = t2 * time_ratio
        # Wrap
        while s1 >= src_dur
            s1 = s1 - src_dur
        endwhile
        while s2 >= src_dur
            s2 = s2 - src_dur
        endwhile
        # Only draw if not wrapping across boundary
        sDiff = s2 - s1
        if sDiff < 0
            sDiff = -sDiff
        endif
        if sDiff < src_dur * 0.5
            Draw line: t1, s1, t2, s2
        endif
    endfor

    # Grain positions
    step_viz = 1
    if n_viz_grains > 400
        step_viz = floor(n_viz_grains / 400)
    endif
    if step_viz < 1
        step_viz = 1
    endif

    for vi from 1 to n_viz_grains
        viDiv = vi - floor(vi / step_viz) * step_viz
        if viDiv = 0 or step_viz = 1
            vt_out = viz_out_t#[vi]
            vt_src = viz_src_t#[vi]
            norm_pos = vt_out / out_dur
            rv = 0.22 + norm_pos * 0.60
            gv = 0.45 - norm_pos * 0.20
            bv = 0.82 - norm_pos * 0.50
            if rv > 1.0
                rv = 1.0
            endif
            if gv < 0.0
                gv = 0.0
            endif
            if bv < 0.18
                bv = 0.18
            endif
            rstr$ = fixed$(rv, 2)
            gstr$ = fixed$(gv, 2)
            bstr$ = fixed$(bv, 2)
            dot_col$ = "{" + rstr$ + ", " + gstr$ + ", " + bstr$ + "}"
            Paint circle (mm): dot_col$, vt_out, vt_src, 0.5
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Source (s)"
    Text bottom: "yes", "Output time (s)"
    Text top: "no", "Grain Read Map (ref line = proportional read)"

    # === STATS PANEL ===
    Select outer viewport: 0, 8, 5.4, 6.15
    Select inner viewport: 0.5, 7.8, 5.45, 6.1
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.85, "half", "##Morphic Summary##"
    Font size: 6
    Colour: "{0.3, 0.3, 0.35}"

    Text: 0.02, "left", 0.62, "half",
        ... "Source: " + src_name$
        ... + " (" + fixed$(src_dur, 2) + " s)"
        ... + " | Output: " + fixed$(final_dur, 2) + " s"
        ... + " (ratio " + fixed$(output_duration_ratio, 2) + "x)"
        ... + " | Grains: " + string$(grain_count)
        ... + " | Preset: " + preset_name$
    Text: 0.02, "left", 0.38, "half",
        ... "A: grain=" + fixed$(att_a_grain_ms, 0)
        ... + "ms dens=" + fixed$(att_a_density, 0)
        ... + "g/s jit=" + fixed$(att_a_jitter_ms, 1)
        ... + "ms bt=" + fixed$(att_a_bt_prob, 2)
        ... + " rep=" + fixed$(att_a_rep_prob, 2)
        ... + " sil=" + fixed$(att_a_sil_prob, 2)
        ... + "  |  B: grain=" + fixed$(att_b_grain_ms, 0)
        ... + "ms dens=" + fixed$(att_b_density, 0)
        ... + "g/s jit=" + fixed$(att_b_jitter_ms, 1)
        ... + "ms"
    Text: 0.02, "left", 0.14, "half",
        ... "Morph: " + fixed$(morph_intensity, 2)
        ... + " | Pacing: " + pacing_curve$
        ... + " | GD lr: " + fixed$(gd_lr, 2)
        ... + " | Local weight: " + fixed$(local_weight, 2)
        ... + " | Base grain: " + fixed$(base_grain_ms, 0)
        ... + " ms | Base density: " + fixed$(base_density_gps, 0)
        ... + " g/s"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # === LEGEND ===
    Select outer viewport: 0, 8, 6.2, 6.5
    Axes: 0, 1, 0, 1
    Font size: 6

    Colour: "{0.82, 0.28, 0.28}"
    Line width: 2
    Draw line: 0.02, 0.5, 0.06, 0.5
    Line width: 1
    Colour: "Black"
    Text: 0.07, "left", 0.5, "half", "Morph"

    Colour: "{0.28, 0.62, 0.32}"
    Draw line: 0.14, 0.5, 0.18, 0.5
    Colour: "Black"
    Text: 0.19, "left", 0.5, "half", "Grain sz"

    Colour: "{0.18, 0.40, 0.82}"
    Draw line: 0.28, 0.5, 0.32, 0.5
    Colour: "Black"
    Text: 0.33, "left", 0.5, "half", "Density"

    Colour: "{0.85, 0.50, 0.15}"
    Draw line: 0.42, 0.5, 0.46, 0.5
    Colour: "Black"
    Text: 0.47, "left", 0.5, "half", "Jitter"

    Colour: "{0.22, 0.48, 0.82}"
    Draw line: 0.55, 0.5, 0.59, 0.5
    Colour: "Black"
    Text: 0.60, "left", 0.5, "half", "Intensity"

    Colour: "{0.82, 0.28, 0.28}"
    Line width: 1
    Draw line: 0.69, 0.5, 0.73, 0.5
    Colour: "Black"
    Text: 0.74, "left", 0.5, "half", "Activity"

    Colour: "{0.28, 0.65, 0.32}"
    Draw line: 0.83, 0.5, 0.87, 0.5
    Colour: "Black"
    Text: 0.88, "left", 0.5, "half", "Voiced"

    Paint rectangle: "{0.86, 0.86, 0.94}", 0.95, 0.98, 0.3, 0.7
    Text: 0.99, "left", 0.5, "half", "V"

    Font size: 10
    Colour: "Black"
    Line width: 1

    appendInfoLine: "  Visualization complete."
endif

# ============================================================
# OUTPUT
# ============================================================

appendInfoLine: ""
appendInfoLine: "=================================================="
appendInfoLine: "  DONE"
appendInfoLine: "=================================================="
appendInfoLine: ""
appendInfoLine: "Output   : ", final_name$
appendInfoLine: "Duration : ", fixed$(final_dur, 3), " s",
    ... " (source: ", fixed$(src_dur, 3), " s, ratio: ",
    ... fixed$(output_duration_ratio, 2), "x)"
appendInfoLine: "Grains   : ", grain_count
appendInfoLine: ""
appendInfoLine: "Attractor A (stable):    grain=", fixed$(att_a_grain_ms, 1),
    ... " ms  dens=", fixed$(att_a_density, 1),
    ... " g/s  jit=", fixed$(att_a_jitter_ms, 1), " ms"
appendInfoLine: "Attractor B (turbulent): grain=", fixed$(att_b_grain_ms, 1),
    ... " ms  dens=", fixed$(att_b_density, 1),
    ... " g/s  jit=", fixed$(att_b_jitter_ms, 1), " ms"

selectObject: result_id

if play_result
    appendInfoLine: ""
    appendInfoLine: "Playing..."
    Play
endif
