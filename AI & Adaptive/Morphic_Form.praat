# ============================================================
# Praat AudioTools - Morphic_Form.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.4 (2026) - Suite-standard visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v1.4 (2026):
#   - VISUALIZATION STANDARDIZATION ONLY; feature analysis, bounded
#     morph-state control, attractor interpolation, grain scheduling,
#     source-position logic and overlap-add rendering are unchanged.
#   - Adopted the Praat AudioTools 8-inch page convention with explicit
#     inner viewports, standard title/subtitle, suite typography,
#     neutral panel backgrounds, summary strip and full-page export.
#   - Preserved the script-specific views: source/output waveforms,
#     morph plus grain-size trajectory, density plus jitter, acoustic
#     feature trajectories and the output-to-source grain read map.
#   - Moved the dense legend/report text into aligned captions and a
#     compact Input / Attractors / Morph & Output summary.
#
# Changelog v1.3 (2026):
#
#   TWO REVIEWED ITEMS DID NOT HOLD - verified on Praat 6.4.42, and
#   recorded here so they are not "fixed" again later:
#
#   (a) Multi-channel input is NOT collapsed to mono. The claim was
#       that Object_<id>(x) inside a multi-channel Formula returns the
#       channel average. It does not: it is evaluated per cell and
#       reads the grain's corresponding channel. Probe with a grain
#       whose ch1 = +0.8 and ch2 = -0.2 (average +0.3), summed into a
#       2-channel buffer: buffer ch1 = 0.8000, ch2 = -0.2000. The
#       explicit object(id, x, y) form gives exactly the same result.
#       Measured end to end on a stereo source: L/R correlation
#       -0.0034 in the source, 0.0322 in the output - decorrelated
#       channels, not duplicates (a collapse would read 1.000).
#       The assembly is left as it was.
#
#   (b) The inertia table in the review is wrong. With gd_lr = 0.22 the
#       state follows 1 - 0.78^n, not the quoted values: 10 frames
#       reaches 0.9166 (not 0.65), 20 reaches 0.9931 (not 0.82), and
#       40 reaches 1.0000 to four places (not 0.91). "Fully reach B"
#       is effectively true after ~40 analysis frames, which even a
#       one-second input supplies. No endpoint correction is needed.
#
#   CRITICAL 1 - Morph_intensity did not bound the morph.
#     The local push was ADDED to the target and then clamped to 1.0,
#     not to what the user allowed. Measured: at Morph_intensity = 0,
#     documented as "stay at A entirely", an unvoiced high-activity
#     frame produced adj_target = 0.3000 - 30% of the way to B. At
#     Morph_intensity = 0.15 the same frame reached 0.4500, triple the
#     requested amount. v1.3 makes the local push move the target
#     WITHIN the permitted range:
#       adjusted = target + w * push * (morph_intensity - target)
#     so local features accelerate the approach to the ceiling instead
#     of raising it. Verified, reporting the highest morph state each
#     run actually reached:
#       Morph 0.00 -> 0.00000   (v1.2 reached 0.30)
#       Morph 0.15 -> 0.14474   (v1.2 reached up to 0.45)
#       Morph 0.75 -> 0.72371
#       Morph 1.00 -> 0.96495
#
#   CRITICAL 2 - the last grain could be cut before its own fade-out.
#     Grains are faded over their final 10%, but a grain whose onset
#     falls near the end is written only up to out_dur, which can land
#     before the fade region begins - ending the file at a non-zero
#     sample. A short fade is now applied to the assembled buffer, at
#     both ends.
#
#   CRITICAL 3 - the scheduling cap could silently truncate.
#     max_grains was floor(out_dur * 80), capped at 6000, while
#     Attractor B allows up to 100 grains/sec - so a dense, long output
#     could exhaust the budget while out_t was still short of out_dur,
#     leaving a silent tail and no warning. (I could not drive a
#     preset into it at the built-in 50 s duration ceiling; it is
#     reachable in principle, not a routine occurrence.) The cap is now
#     derived from the actual maximum density with a margin, and if it
#     is ever reached the script says so and reports how much of the
#     timeline went unscheduled.
#
#   4 - Random_seed added (0 = unpredictable). Grain jitter,
#     backtracking, repeats and silence gaps are all random and no take
#     could be recovered. The generator is returned to its safe state
#     at the end.
#
#   5 - Nervous Scatter now starts where it claims to. Every preset
#     began at gd_state = 0, i.e. at Attractor A, including the one
#     described as "B-dominant from the start". Presets can now set an
#     initial morph state; Nervous Scatter starts at 0.75.
#
#   6 - Source-edge pile-up. Jitter and backtrack were CLAMPED to the
#     source bounds, so every overshoot landed on exactly the first or
#     last legal start - over-selecting the beginning and end of the
#     source. Positions now REFLECT off the bounds instead.
#
#   7 - "Voicing confidence" is a binary voiced flag: 1 where Pitch is
#     defined, 0 where it is not. Renamed in the code and the report;
#     "when voicing is weak" meant "when the frame is unvoiced".
#
#   8 - A silent input is rejected up front instead of being run
#     through the whole pipeline and then handed to Scale peak.
#
#   9 - The form title, Info banner and visualization header all still
#     said v1.1. Synced.
#
#   10 - Description wording. "Spectral content is never altered" was
#     too strong: each grain's internal spectrum is untransformed, but
#     overlapping grains interfere and the spectrum of the SUM does
#     change. Restated.
#
# Changelog v1.2 (CHANGES AUDIO of every preset):
#   - Assembly redesigned to true time-placed overlap-add: grains
#     are summed into one output buffer at their scheduled onset
#     (out_t) instead of being concatenated end-to-end. Density
#     (grains/sec) now genuinely controls onset spacing and grain
#     overlap. out_dur is exact by construction.
#   - Silence behavior under OLA = a gap in onsets rather than an
#     inserted silent grain.
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

form Morphic Form v1.4  (Grain Placement Engine)
    optionmenu Preset 1
        option Custom
        option Slow Bloom  (gentle A->B, large grains)
        option Tidal Surge  (aggressive A->B, accelerating)
        option Nervous Scatter  (B-dominant, dense + jittery)
        option Still Center  (A-dominant, minimal morphing)
        option Time Stretch  (2x duration, slow drift)
        option Collapse  (half duration, rapid compression)
    real Morph_intensity 0.75
    positive Base_grain_ms 40.0
    positive Base_density_gps 25.0
    positive Max_jitter_ms 15.0
    positive Output_duration_ratio 1.0
    optionmenu Pacing_curve 1
        option Linear
        option Accelerate  (slow start, rush to B)
        option Decelerate  (explosive start, then stabilize)
    integer Random_seed 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Morph_intensity: 0.0 keeps the state at Attractor A for the whole
# run; 1.0 lets it reach B. Local acoustic features move the state
# WITHIN this range (v1.3 CRITICAL 1) - they no longer push past it.
# Base_density_gps is grains per second. Output_duration_ratio is
# relative to the input: 1.0 same, 2.0 double, 0.5 half.
# Random_seed: 0 = unpredictable, any positive value = reproducible.

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
    # v1.3 fix 5: this preset is described as B-dominant FROM THE
    # START, but every preset used to begin at gd_state = 0, i.e. at
    # Attractor A, and only drifted toward B afterwards.
    initial_morph_state = 0.75
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

# Every other preset (and Custom) starts at Attractor A
if not variableExists("initial_morph_state")
    initial_morph_state = 0.0
endif
if initial_morph_state > morph_intensity
    initial_morph_state = morph_intensity
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

# v1.3 fix 8: a silent input would run the whole pipeline and then be
# handed to Scale peak with a peak of zero.
selectObject: src_id
src_peak_check = Get absolute extremum: 0, 0, "None"
if src_peak_check < 1e-6
    exitScript: "The selected Sound is silent (or near-silent); nothing to place."
endif

# v1.3 fix 4: reproducibility. Grain jitter, backtracking, repeats and
# silence gaps are all random and v1.2 had no seed.
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seed_label$ = string$(random_seed)
else
    random_initializeSafelyAndUnpredictably ()
    seed_label$ = "unpredictable"
endif

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
writeInfoLine: "  MORPHIC FORM v1.4  |  Grain Placement Engine"
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
appendInfoLine: "Seed           : ", seed_label$

# ============================================================
# STEP 1: FEATURE EXTRACTION
#   Following HMM_Timbre_Sequencing pipeline:
#   intensity + pitch voiced flag (1 = Pitch defined, 0 = unvoiced) per analysis frame.
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
af_voiced# = zero#(n_af)

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
        af_voiced#[i] = 1
    else
        af_voiced#[i] = 0
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

# v1.3 fix 5: presets may start away from A
gd_state = initial_morph_state
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

    # Local push toward B when activity is high or the frame is
    # UNVOICED (af_voiced# is a 0/1 flag, not a continuous confidence).
    local_push = af_activity#[i] * 0.55 + (1.0 - af_voiced#[i]) * 0.45

    # v1.3 CRITICAL 1: the push moves the target WITHIN the range the
    # user allowed, instead of being added on top and then clamped to
    # 1.0. Measured on v1.2: Morph_intensity = 0, documented as "stay
    # at A entirely", gave adj_target = 0.3000 on an unvoiced
    # high-activity frame; Morph_intensity = 0.15 gave 0.4500. Local
    # features now accelerate the approach to the ceiling rather than
    # raising it, so Morph 0 stays exactly at A.
    adj_target = target_m + local_weight * local_push * (morph_intensity - target_m)
    if adj_target > morph_intensity
        adj_target = morph_intensity
    endif
    if adj_target < 0.0
        adj_target = 0.0
    endif

    # Gradient step (inertial update)
    gd_err = adj_target - gd_state
    gd_state = gd_state + gd_lr * gd_err
    if gd_state > morph_intensity
        gd_state = morph_intensity
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
# v1.3 CRITICAL 3: derive the budget from the density the model can
# actually ask for. v1.2 used floor(out_dur * 80) capped at 6000 while
# Attractor B allows up to att_b_density grains/sec, so a dense long
# output could exhaust the budget with out_t still short of out_dur -
# a silent tail, reported as success. The margin covers silence gaps
# and rounding.
peak_density = att_a_density
if att_b_density > peak_density
    peak_density = att_b_density
endif
max_grains = ceiling(out_dur * peak_density * 1.25) + 64
if max_grains < 500
    max_grains = 500
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

    # v1.3 fix 6: REFLECT off the source bounds rather than clamping.
    # v1.2 pinned every overshoot to exactly the first or last legal
    # start, so large negative jitter piled up on the source's opening
    # and large positive jitter on its ending - visible as
    # over-selection of both edges, worst in Nervous Scatter.
    src_hi = src_dur - cur_gr_s - 0.001
    if src_hi < 0.0
        src_hi = 0.0
    endif
    if src_hi > 0.0
        reflect_guard = 0
        while (src_pos < 0.0 or src_pos > src_hi) and reflect_guard < 8
            if src_pos < 0.0
                src_pos = -src_pos
            endif
            if src_pos > src_hi
                src_pos = 2.0 * src_hi - src_pos
            endif
            reflect_guard = reflect_guard + 1
        endwhile
    endif
    if src_pos < 0.0
        src_pos = 0.0
    endif
    if src_pos > src_hi
        src_pos = src_hi
    endif

    actual_gr_s = cur_gr_s
    if actual_gr_s > src_dur - src_pos - 0.001
        actual_gr_s = src_dur - src_pos - 0.001
    endif

    if actual_gr_s >= 0.010
        grain_count = grain_count + 1
        g_src_'grain_count' = src_pos
        g_dur_'grain_count' = actual_gr_s
        g_out_'grain_count' = out_t
        last_src = src_pos

        if grain_count <= viz_grain_max
            viz_out_t#[grain_count] = out_t
            viz_src_t#[grain_count] = src_pos
        endif

        # Silence (Attractor A): under overlap-add a silence is simply
        # a GAP in onsets - advance the output clock so the next grain
        # starts later, leaving the buffer at zero in between.
        if randomUniform(0.0, 1.0) < cur_sil
            sil_dur = randomUniform(0.012, att_a_sil_ms / 1000.0)
            if sil_dur > 0.001
                out_t = out_t + sil_dur
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
    ... " (budget: ", max_grains, ")"

# v1.3 CRITICAL 3: never truncate in silence.
sched_shortfall = out_dur - out_t
if grain_count >= max_grains and sched_shortfall > 0.01
    appendInfoLine: "  ! Scheduling budget reached with ",
        ... fixed$(sched_shortfall, 3), " s (",
        ... fixed$(100 * sched_shortfall / out_dur, 1),
        ... "%) of the timeline unscheduled."
    appendInfoLine: "    That tail will be SILENT. Lower the density or"
    appendInfoLine: "    shorten Output_duration_ratio."
endif

if grain_count < 1
    exitScript: "No grains generated. Try reducing density or increasing duration."
endif

# ============================================================
# STEP 6: GRAIN EXTRACTION + TIME-PLACED OVERLAP-ADD
#   One output buffer of length out_dur is created up front.
#   Each grain is extracted, faded (10% in/out, xmin-relative),
#   and SUMMED into the buffer at its scheduled onset (g_out).
#   Density therefore controls onset spacing and overlap, and
#   out_dur is exact by construction.
# ============================================================

appendInfoLine: ""
appendInfoLine: "[6/6] Overlap-add assembly..."

# Output buffer (matches source channel count)
Create Sound from formula: "morphic_buf", src_ch, 0.0, out_dur, src_sr, "0"
result_id = selected("Sound")

for k from 1 to grain_count
    g_start = g_src_'k'
    g_end = g_start + g_dur_'k'
    g_onset = g_out_'k'

    # Skip grains whose onset is past the buffer end
    if g_onset < out_dur - 0.0005
        selectObject: src_id
        Extract part: g_start, g_end, "rectangular", 1.0, "no"
        grain_id = selected("Sound")

        # 10% raised-linear fade in/out (xmin-relative) for click-free OLA
        selectObject: grain_id
        Formula: "if x - xmin < (xmax - xmin) * 0.10"
            ... + " then self * ((x - xmin) / ((xmax - xmin) * 0.10))"
            ... + " else (if x > xmax - (xmax - xmin) * 0.10"
            ... + " then self * ((xmax - x) / ((xmax - xmin) * 0.10))"
            ... + " else self fi) fi"

        # Sum into the buffer at the scheduled onset. Object_<id>(x)
        # reads the grain in its own 0..dur time frame, returning 0
        # outside it, so we offset by g_onset.
        grainStr$ = string$(grain_id)
        onsetStr$ = string$(g_onset)
        g_tail = g_onset + g_dur_'k'
        if g_tail > out_dur
            g_tail = out_dur
        endif
        selectObject: result_id
        Formula (part): g_onset, g_tail, 1, src_ch,
            ... "self + Object_" + grainStr$ + "(x - " + onsetStr$ + ")"

        removeObject: grain_id
    endif

    kDiv200 = k - floor(k / 200) * 200
    if kDiv200 = 0
        appendInfo: "."
    endif
endfor

appendInfoLine: ""

# v1.3 CRITICAL 2: a grain whose onset falls near the end is written
# only as far as out_dur, which can cut it before its own 10% fade-out
# region begins - ending the file at a non-zero sample. One short fade
# on the assembled buffer covers that, and the head as well.
selectObject: result_id
buf_dur_now = Get total duration
edge_fade = 0.005
if edge_fade > buf_dur_now * 0.1
    edge_fade = buf_dur_now * 0.1
endif
if edge_fade > 0.0002
    ef_str$ = fixed$(edge_fade, 8)
    selectObject: result_id
    Formula: "if x - xmin < " + ef_str$ +
        ... " then self * ((x - xmin) / " + ef_str$ + ") else self fi"
    selectObject: result_id
    Formula: "if xmax - x < " + ef_str$ +
        ... " then self * ((xmax - x) / " + ef_str$ + ") else self fi"
endif

selectObject: result_id
Scale peak: 0.99
Rename: src_name$ + "_morphic"

# v1.3 fix 4: all random draws are done.
random_initializeSafelyAndUnpredictably ()
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

    selectObject: result_id
    vizPeak = Get absolute extremum: 0, 0, "None"

    vizName$ = replace$(src_name$, "_", "\_ ", 0)

    if sched_shortfall > 0.01
        scheduleText$ = "shortfall " + fixed$(sched_shortfall, 3) + " s"
    else
        scheduleText$ = "full timeline scheduled"
    endif

    pageHeight = 7.55
    Erase all
    Line width: 1
    Colour: "Black"
    Solid line
    Select outer viewport: 0, 8, 0, pageHeight

    # === Header ===
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Morphic Form v1.4##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", vizName$ + " | " + preset_name$ + " | morph " + fixed$(morph_intensity, 2) + " | " + pacing_curve$ + " | " + string$(grain_count) + " grains"

    # === Original waveform ===
    Select outer viewport: 0, 4, 0.68, 1.62
    Select inner viewport: 0.60, 3.85, 0.82, 1.44
    selectObject: src_id
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Amp"
    Text top: "no", "Original | " + fixed$(src_dur, 2) + " s"

    # === Output waveform ===
    Select outer viewport: 4, 8, 0.68, 1.62
    Select inner viewport: 4.45, 7.70, 0.82, 1.44
    selectObject: result_id
    Colour: "{0.25, 0.45, 0.75}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Amp"
    Text top: "no", "Morphic Output | " + fixed$(final_dur, 2) + " s | peak " + fixed$(vizPeak, 3)

    # === Morph state and grain size ===
    Select outer viewport: 0, 4, 1.84, 3.28
    Select inner viewport: 0.60, 3.85, 2.08, 3.04
    Axes: 0, out_dur, 0, 1.05
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, out_dur, 0, 1.05

    for i to n_af
        t_l = af_time#[i] - af_hop_s * 0.5
        t_r = af_time#[i] + af_hop_s * 0.5
        if t_l < 0.0
            t_l = 0.0
        endif
        if t_r > out_dur
            t_r = out_dur
        endif
        Paint rectangle: "{0.90, 0.92, 0.97}", t_l, t_r, 0, morph_curve#[i]
    endfor

    Colour: "{0.75, 0.25, 0.25}"
    Line width: 2
    for i from 1 to n_af - 1
        Draw line: af_time#[i], morph_curve#[i], af_time#[i + 1], morph_curve#[i + 1]
    endfor

    gn_range = att_a_grain_ms - att_b_grain_ms
    if gn_range < 0.001
        gn_range = 0.001
    endif

    Colour: "{0.25, 0.55, 0.25}"
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
    Text left: "yes", "Normalized"
    Text bottom: "no", "Time (s)"
    Text top: "no", "Morph / Grain Size | red morph state | green normalized grain size"

    # === Density and jitter ===
    Select outer viewport: 4, 8, 1.84, 3.28
    Select inner viewport: 4.45, 7.70, 2.08, 3.04

    max_d_axis = att_b_density * 1.12
    if att_a_density > att_b_density
        max_d_axis = att_a_density * 1.12
    endif
    if max_d_axis < 1
        max_d_axis = 1
    endif

    Axes: 0, out_dur, 0, max_d_axis
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, out_dur, 0, max_d_axis

    Colour: "{0.25, 0.45, 0.75}"
    Line width: 2
    for i from 1 to n_af - 1
        Draw line: af_time#[i], pf_density#[i], af_time#[i + 1], pf_density#[i + 1]
    endfor

    max_jit_ax = att_a_jitter_ms
    if att_b_jitter_ms > max_jit_ax
        max_jit_ax = att_b_jitter_ms
    endif
    if max_jit_ax < 1.0
        max_jit_ax = 1.0
    endif
    jit_scale = max_d_axis / max_jit_ax

    Colour: "{0.80, 0.55, 0.20}"
    Line width: 1.5
    for i from 1 to n_af - 1
        Draw line: af_time#[i], pf_jitter#[i] * jit_scale, af_time#[i + 1], pf_jitter#[i + 1] * jit_scale
    endfor

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Grains/s"
    Text bottom: "no", "Time (s)"
    Text top: "no", "Density / Jitter | blue density | amber jitter scaled to axis"

    # === Acoustic feature trajectories ===
    Select outer viewport: 0, 8, 3.50, 4.72
    Select inner viewport: 0.60, 7.70, 3.72, 4.50
    Axes: 0, out_dur, 0, 1.0
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, out_dur, 0, 1.0

    for i to n_af
        if af_voiced#[i] = 1
            t_l = af_time#[i] - af_hop_s * 0.5
            t_r = af_time#[i] + af_hop_s * 0.5
            if t_l < 0.0
                t_l = 0.0
            endif
            if t_r > out_dur
                t_r = out_dur
            endif
            Paint rectangle: "{0.92, 0.94, 0.97}", t_l, t_r, 0, 1.0
        endif
    endfor

    Colour: "{0.80, 0.80, 0.80}"
    Dashed line
    Draw line: 0, 0.5, out_dur, 0.5
    Solid line

    Colour: "{0.25, 0.45, 0.75}"
    Line width: 1.8
    for i from 1 to n_af - 1
        Draw line: af_time#[i], norm_int#[i], af_time#[i + 1], norm_int#[i + 1]
    endfor

    Colour: "{0.75, 0.25, 0.25}"
    Line width: 1.3
    for i from 1 to n_af - 1
        Draw line: af_time#[i], af_activity#[i], af_time#[i + 1], af_activity#[i + 1]
    endfor

    Colour: "{0.25, 0.55, 0.25}"
    Line width: 1.2
    for i from 1 to n_af - 1
        Draw line: af_time#[i], af_voiced#[i] * 0.92, af_time#[i + 1], af_voiced#[i + 1] * 0.92
    endfor

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Normalized"
    Text bottom: "no", "Time (s)"
    Text top: "no", "Acoustic Features | blue intensity | red activity | green voiced flag | shaded = voiced"

    # === Grain read map ===
    Select outer viewport: 0, 8, 4.94, 6.36
    Select inner viewport: 0.60, 7.70, 5.18, 6.12
    Axes: 0, out_dur, 0, src_dur
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, out_dur, 0, src_dur

    Colour: "{0.75, 0.75, 0.75}"
    Dashed line
    nRefPts = 50
    for ri from 1 to nRefPts
        riPrev = ri - 1
        t1 = riPrev / nRefPts * out_dur
        t2 = ri / nRefPts * out_dur
        s1 = t1 * time_ratio
        s2 = t2 * time_ratio

        while s1 >= src_dur
            s1 = s1 - src_dur
        endwhile
        while s2 >= src_dur
            s2 = s2 - src_dur
        endwhile

        sDiff = s2 - s1
        if sDiff < 0
            sDiff = -sDiff
        endif
        if sDiff < src_dur * 0.5
            Draw line: t1, s1, t2, s2
        endif
    endfor
    Solid line

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
            rv = 0.25 + norm_pos * 0.50
            gv = 0.50 - norm_pos * 0.20
            bv = 0.75 - norm_pos * 0.35
            if rv > 1.0
                rv = 1.0
            endif
            if gv < 0.0
                gv = 0.0
            endif
            if bv < 0.18
                bv = 0.18
            endif
            rstr$ = fixed$(rv, 3)
            gstr$ = fixed$(gv, 3)
            bstr$ = fixed$(bv, 3)
            dot_col$ = "{" + rstr$ + ", " + gstr$ + ", " + bstr$ + "}"
            Paint circle (mm): dot_col$, vt_out, vt_src, 0.55
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Source time (s)"
    Text bottom: "no", "Output time (s)"
    Text top: "no", "Grain Read Map | dashed = proportional read | points = scheduled source positions"

    # === Summary strip ===
    Select outer viewport: 0, 8, 6.58, 7.50
    Select inner viewport: 0.60, 7.70, 6.66, 7.42
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    summary1$ = "##Input##  " + vizName$ + " | " + fixed$(src_dur, 2) + " s | " + string$(src_sr) + " Hz | " + string$(src_ch) + " ch | output ratio " + fixed$(output_duration_ratio, 2) + "x | seed " + seed_label$
    summary2$ = "##Attractors##  A grain " + fixed$(att_a_grain_ms, 0) + " ms, density " + fixed$(att_a_density, 1) + " g/s, jitter " + fixed$(att_a_jitter_ms, 1) + " ms | B grain " + fixed$(att_b_grain_ms, 0) + " ms, density " + fixed$(att_b_density, 1) + " g/s, jitter " + fixed$(att_b_jitter_ms, 1) + " ms"
    summary3$ = "##Morph & output##  intensity " + fixed$(morph_intensity, 2) + " | " + pacing_curve$ + " | local weight " + fixed$(local_weight, 2) + " | " + string$(grain_count) + " grains | " + scheduleText$ + " | " + fixed$(final_dur, 2) + " s"
    Text: 0.02, "left", 0.78, "half", summary1$
    Text: 0.02, "left", 0.50, "half", summary2$
    Text: 0.02, "left", 0.22, "half", summary3$

    Colour: "Black"
    Draw inner box

    # Restore complete page for Picture export / clipboard.
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line

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
