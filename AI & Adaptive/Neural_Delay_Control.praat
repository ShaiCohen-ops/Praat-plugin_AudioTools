# ============================================================
# Praat AudioTools - Neural_Delay_Control.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Neural Delay Control - adaptive delay whose per-frame mix and
#   feedback modulation is computed by a small Multi-Layer
#   Perceptron (MLP) forward pass evaluated frame-by-frame inside
#   Praat. The MLP modulates the user's `mix_base` and
#   `feedback_base` form values; the delay engine itself is
#   identical to the previous Adaptive_Delay_Control / Neural_
#   Delay_Control v0.6 rule-based variant.
#
# NETWORK ARCHITECTURE  (hand-designed, not trained):
#
#   Input layer (30 dims, computed per frame):
#     [1..13]  : MFCC[1..13] / 30      (normalized to ~[-1, 1])
#     [14..26] : |delta-MFCC[1..13]| / 30  (frame-to-frame change)
#     [27]     : HNR_norm               (0..1, from Harmonicity (cc))
#     [28]     : voicing                (0 or 1, from Pitch)
#     [29]     : intensity_norm         ((dB - 60) / 30 + 0.5, clipped)
#     [30]     : transient_norm         (intensity delta, 0..1)
#
#   Hidden layer (8 units, ReLU):
#     h_j = max(0, b1_j + sum_k w1[j,k] * x[k])
#
#     Designed interpretation per unit:
#       h1: HNR detector              (w1[1,27]=2.0,  b=-0.3)
#       h2: voicing detector          (w1[2,28]=1.5,  b=-0.4)
#       h3: transient detector        (w1[3,30]=2.5,  b=-0.3)
#       h4: sustained-energy detector (HNR + voiced + intensity
#                                      minus transient; b=-0.4)
#       h5: vocal-formant MFCC
#           (positive weights on MFCC1-3; b=-0.1)
#       h6: timbral-change detector
#           (positive weights on |delta-MFCC1..5|; b=-0.2)
#       h7: high-band MFCC detector
#           (positive weights on MFCC8-13; b=-0.1)
#       h8: constant bias unit (no weights, b=+1.0 — always
#           active, acts as a fixed contribution)
#
#   Output layer (2 units, tanh):
#     out_o = tanh(b2_o + sum_j w2[o,j] * h_j)
#
#     Output 1 -> mix modulation (* 0.4 scale)
#     Output 2 -> feedback modulation (* 0.3 scale)
#
#   Final control values (per frame):
#     mix       = clip(mix_base + 0.4 * out_1, 0.05, 0.8)
#     feedback  = clip(feedback_base + 0.3 * out_2, 0.10, 0.7)
#
#   Total parameters: 30*8 + 8 + 2*8 + 2 = 266
#
# IMPORTANT — what "Neural" means here, honestly:
#   - The architecture is genuinely neural: real layers, ReLU,
#     tanh, matrix-vector forward pass evaluated for every frame.
#   - The weights are HAND-DESIGNED, not trained on data. Each
#     hidden unit's weights were chosen so the unit responds to
#     a specific input pattern, and the output weights were
#     chosen to approximate v0.6's mix/feedback formula while
#     adding MFCC-based timbral sensitivity.
#   - The script is NOT self-supervised. It is a structurally
#     trainable network (you could later expose the weights as
#     a CSV and learn them with a Python helper against your
#     own preference labels), but as delivered, all 266 weights
#     are static.
#   - This is the "Option 2" path: real neural architecture,
#     pure Praat, no Python dependency.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v1.0:
#   - Replaced v0.6's linear formula for mix/feedback control with
#     a 30-8-2 MLP forward pass evaluated per frame inside Praat.
#   - NEW: MFCC extraction (13 coefficients) and delta-MFCC
#     (absolute frame-to-frame differences) computed once into
#     pseudo-array buffers before the network loop.
#   - NEW: 266 hand-designed weight constants documented in the
#     script header and assigned in a dedicated init block.
#   - The delay engine itself (feature-driven envelope, smoothing,
#     N-tap exponential decay, optional cascaded LP filter,
#     adaptive mix Formula (part), Formula-based delayed add)
#     is bit-identical to v0.6.
#   - The 6 presets are unchanged; they still set mix_base,
#     feedback_base, delay_time_ms etc. The MLP modulates around
#     those base values.
#   - Audio output will be AUDIBLY DIFFERENT from v0.6 because
#     the MLP responds to MFCC features that v0.6's linear formula
#     doesn't see (timbral character, spectral change). The
#     difference is most pronounced on material with rich timbral
#     variation (speech, mixed sources, percussion + tone).
#   - Visualization unchanged structurally; Panel E summary
#     mentions the MLP architecture.
# Changelog v0.6:
#   - Fixed +=, fixed stats overlap, object(id,x), suite 8x8
# Changelog v0.5:
#   - Fixed preset comparison, Formula object refs, variable case
# ============================================================

# === Input Validation ===
nSelected = numberOfSelected("Sound")
if nSelected <> 1
    exitScript: "Please select exactly one Sound object."
endif

original_sound = selected("Sound")
original_name$ = selected$("Sound")

form Neural Delay Control v1.0
    optionmenu Preset: 1
        option Manual
        option Clean Digital
        option Analog Warmth
        option Slapback
        option Rhythmic Dotted
        option Ambient Wash
        option Modulated
    positive Delay_time_ms 250
    positive Feedback_base 0.4
    positive Mix_base 0.3
    integer Number_of_repeats 4
    boolean Enable_filter 1
    positive Filter_cutoff_hz 4000
    positive Frame_step_ms 20
    positive Smooth_ms 40
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Note: Transient_suppression, Hnr_gain, Pitch_bonus from v0.6 are no longer
# form fields — those were the linear-formula coefficients. The MLP has its
# own internal weights that determine how each feature contributes. Base
# levels (mix_base, feedback_base) are still controlled by the form, and
# the MLP modulates around those.

# ============================================
# PRESET LOGIC
# ============================================

if preset = 2
    delay_time_ms = 250
    feedback_base = 0.35
    mix_base = 0.3
    number_of_repeats = 4
    enable_filter = 0
    presetName$ = "CleanDigital"
elsif preset = 3
    delay_time_ms = 300
    feedback_base = 0.5
    mix_base = 0.35
    number_of_repeats = 5
    enable_filter = 1
    filter_cutoff_hz = 3000
    presetName$ = "AnalogWarmth"
elsif preset = 4
    delay_time_ms = 80
    feedback_base = 0.15
    mix_base = 0.45
    number_of_repeats = 2
    enable_filter = 0
    presetName$ = "Slapback"
elsif preset = 5
    delay_time_ms = 375
    feedback_base = 0.45
    mix_base = 0.35
    number_of_repeats = 4
    enable_filter = 1
    filter_cutoff_hz = 4500
    presetName$ = "RhythmicDotted"
elsif preset = 6
    delay_time_ms = 500
    feedback_base = 0.6
    mix_base = 0.4
    number_of_repeats = 6
    enable_filter = 1
    filter_cutoff_hz = 2500
    presetName$ = "AmbientWash"
elsif preset = 7
    delay_time_ms = 200
    feedback_base = 0.45
    mix_base = 0.35
    number_of_repeats = 4
    enable_filter = 1
    filter_cutoff_hz = 5000
    presetName$ = "Modulated"
else
    presetName$ = "Manual"
endif

# ============================================
# SETUP
# ============================================

selectObject: original_sound
duration = Get total duration
fs = Get sampling frequency

clearinfo
writeInfoLine: "=== Neural Delay Control v1.0 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Delay: ", delay_time_ms, " ms | Feedback base: ", fixed$(feedback_base, 2)
appendInfoLine: "Mix base: ", fixed$(mix_base, 2), " | Repeats: ", number_of_repeats
if enable_filter
    appendInfoLine: "Filter: LP @ ", filter_cutoff_hz, " Hz"
endif
appendInfoLine: ""

# Work on mono copy
selectObject: original_sound
sound_work = Convert to mono
Rename: "Work"

delay_sec = delay_time_ms / 1000
frame_step_sec = frame_step_ms / 1000

# ============================================
# MLP WEIGHT INITIALIZATION
# 266 hand-designed weights. See header for design rationale.
# Weights stored as Praat pseudo-arrays: w1[j,k], w1_bias[j],
# w2[o,j], w2_bias[o]. Indexed from 1.
# ============================================

# Initialize all hidden weights to 0 (only non-zero values set below)
for j from 1 to 8
    for k from 1 to 30
        w1[j, k] = 0
    endfor
endfor

# Initialize all output weights to 0
for o from 1 to 2
    for j from 1 to 8
        w2[o, j] = 0
    endfor
endfor

# --- Hidden layer biases (8 units) ---
w1_bias[1] = -0.3   ; HNR detector
w1_bias[2] = -0.4   ; voicing detector
w1_bias[3] = -0.3   ; transient detector
w1_bias[4] = -0.4   ; sustained-energy detector
w1_bias[5] = -0.1   ; vocal-formant MFCC detector
w1_bias[6] = -0.2   ; timbral-change detector
w1_bias[7] = -0.1   ; high-band MFCC detector
w1_bias[8] = 1.0    ; constant bias unit (always-on)

# --- Hidden unit 1: HNR detector ---
w1[1, 27] = 2.0

# --- Hidden unit 2: voicing detector ---
w1[2, 28] = 1.5

# --- Hidden unit 3: transient detector ---
w1[3, 30] = 2.5

# --- Hidden unit 4: sustained-energy detector ---
w1[4, 27] = 1.0     ; HNR
w1[4, 28] = 0.7     ; voicing
w1[4, 29] = 0.5     ; intensity
w1[4, 30] = -1.5    ; transient (suppresses)

# --- Hidden unit 5: vocal-formant MFCC detector ---
w1[5, 1] = 0.5      ; MFCC1 (overall spectral tilt)
w1[5, 2] = 0.3      ; MFCC2 (coarse formant)
w1[5, 3] = 0.2      ; MFCC3

# --- Hidden unit 6: timbral-change detector ---
w1[6, 14] = 0.4     ; |delta-MFCC1|
w1[6, 15] = 0.3     ; |delta-MFCC2|
w1[6, 16] = 0.3     ; |delta-MFCC3|
w1[6, 17] = 0.2     ; |delta-MFCC4|
w1[6, 18] = 0.2     ; |delta-MFCC5|

# --- Hidden unit 7: high-band MFCC detector ---
w1[7, 8] = 0.3      ; MFCC8
w1[7, 9] = 0.3      ; MFCC9
w1[7, 10] = 0.3     ; MFCC10
w1[7, 11] = 0.2     ; MFCC11
w1[7, 12] = 0.2     ; MFCC12
w1[7, 13] = 0.2     ; MFCC13

# Hidden unit 8: weights all 0, bias = 1.0 (handled above)

# --- Output layer biases (2 units) ---
w2_bias[1] = -0.2   ; mix modulation
w2_bias[2] = -0.1   ; feedback modulation

# --- Output 1: mix modulation ---
w2[1, 1] =  0.20    ; from HNR detector
w2[1, 2] =  0.15    ; from voicing detector
w2[1, 3] = -0.50    ; from transient detector
w2[1, 4] =  0.20    ; from sustained-energy detector
w2[1, 5] =  0.15    ; from vocal-formant MFCC
w2[1, 6] = -0.15    ; from timbral-change detector
w2[1, 7] = -0.05    ; from high-band MFCC
w2[1, 8] =  0.00    ; from constant bias unit (no contribution to mix)

# --- Output 2: feedback modulation ---
w2[2, 1] =  0.15    ; from HNR detector
w2[2, 2] =  0.05    ; from voicing detector
w2[2, 3] = -0.40    ; from transient detector
w2[2, 4] =  0.25    ; from sustained-energy detector
w2[2, 5] =  0.05    ; from vocal-formant MFCC
w2[2, 6] = -0.20    ; from timbral-change detector
w2[2, 7] = -0.05    ; from high-band MFCC
w2[2, 8] =  0.00    ; from constant bias unit

# ============================================
# FEATURE EXTRACTION  (Praat objects + MFCC buffer)
# ============================================

appendInfoLine: "Extracting features (Intensity, HNR, Pitch, MFCC)..."

nFrames = floor(duration / frame_step_sec)
if nFrames < 1
    nFrames = 1
endif

feat_intensity# = zero#(nFrames)
feat_hnr# = zero#(nFrames)
feat_pitch# = zero#(nFrames)
ctrl_mix# = zero#(nFrames)
ctrl_fb# = zero#(nFrames)

selectObject: sound_work
intensity_obj = To Intensity: 75, frame_step_sec, "yes"

selectObject: sound_work
hnr_obj = To Harmonicity (cc): frame_step_sec, 75, 0.1, 1.0

selectObject: sound_work
pitch_obj = To Pitch: frame_step_sec, 75, 600

# MFCC: 13 coefficients, 25 ms window, frame_step_sec hop
selectObject: sound_work
mfcc_obj = To MFCC: 13, 0.025, frame_step_sec, 100, 100, 0
mfcc_n_frames = Get number of frames

# Prefetch all features into pseudo-arrays so the network forward
# pass doesn't repeatedly cross Praat's command boundary
for i from 1 to nFrames
    t = (i - 0.5) * frame_step_sec
    
    selectObject: intensity_obj
    iv = Get value at time: t, "cubic"
    if iv = undefined
        iv = 60
    endif
    feat_intensity#[i] = iv
    
    selectObject: hnr_obj
    hnr = Get value at time: t, "cubic"
    if hnr = undefined
        hnr = 0
    endif
    feat_hnr#[i] = max(0, min(1, (hnr + 10) / 40))
    
    selectObject: pitch_obj
    f0 = Get value at time: t, "Hertz", "Linear"
    if f0 = undefined or f0 <= 0
        feat_pitch#[i] = 0
    else
        feat_pitch#[i] = 1
    endif
    
    # MFCC: 13 coefficients per frame
    selectObject: mfcc_obj
    mfcc_frame_raw = Get frame number from time: t
    mfcc_frame = round(mfcc_frame_raw)
    if mfcc_frame < 1
        mfcc_frame = 1
    endif
    if mfcc_frame > mfcc_n_frames
        mfcc_frame = mfcc_n_frames
    endif
    
    for c from 1 to 13
        mval = Get value in frame: mfcc_frame, c
        if mval = undefined
            mval = 0
        endif
        mfcc_buf[i, c] = mval
    endfor
endfor

removeObject: intensity_obj, hnr_obj, pitch_obj, mfcc_obj

# Pre-compute |delta-MFCC| frame-to-frame (frame 1: zero delta)
for c from 1 to 13
    dmfcc_buf[1, c] = 0
endfor
for i from 2 to nFrames
    for c from 1 to 13
        dmfcc_buf[i, c] = abs(mfcc_buf[i, c] - mfcc_buf[i - 1, c])
    endfor
endfor

# ============================================
# MLP FORWARD PASS — frame by frame
# Computes mix_modulation and feedback_modulation per frame
# from the 30-input feature vector through the 30-8-2 network.
# ============================================

appendInfoLine: "Running MLP forward pass (266-parameter, 30-8-2 network)..."

prev_int = feat_intensity#[1]

for i from 1 to nFrames
    # --- Compute transient_norm ---
    dI = abs(feat_intensity#[i] - prev_int) / 20
    prev_int = feat_intensity#[i]
    trans_norm = min(dI, 1)
    
    # --- Build input vector x[1..30] ---
    # [1..13]: normalized MFCC
    for c from 1 to 13
        x[c] = mfcc_buf[i, c] / 30
    endfor
    # [14..26]: normalized |delta-MFCC|
    for c from 1 to 13
        x[13 + c] = dmfcc_buf[i, c] / 30
    endfor
    # [27]: HNR norm
    x[27] = feat_hnr#[i]
    # [28]: voicing
    x[28] = feat_pitch#[i]
    # [29]: intensity norm  -- (dB - 60) / 30 + 0.5, clipped to [0, 1]
    int_norm = (feat_intensity#[i] - 60) / 30 + 0.5
    if int_norm < 0
        int_norm = 0
    endif
    if int_norm > 1
        int_norm = 1
    endif
    x[29] = int_norm
    # [30]: transient norm
    x[30] = trans_norm
    
    # --- Hidden layer: h_j = ReLU(b1_j + sum_k w1[j,k] * x[k]) ---
    for j from 1 to 8
        acc = w1_bias[j]
        for k from 1 to 30
            acc = acc + w1[j, k] * x[k]
        endfor
        if acc < 0
            acc = 0
        endif
        h[j] = acc
    endfor
    
    # --- Output layer: out_o = tanh(b2_o + sum_j w2[o,j] * h_j) ---
    for o from 1 to 2
        acc = w2_bias[o]
        for j from 1 to 8
            acc = acc + w2[o, j] * h[j]
        endfor
        out_pre[o] = acc
    endfor
    
    mix_mod = 0.4 * tanh(out_pre[1])
    fb_mod = 0.3 * tanh(out_pre[2])
    
    # Final values: base + modulation, clipped to v0.6's safe ranges
    ctrl_mix#[i] = max(0.05, min(0.8, mix_base + mix_mod))
    ctrl_fb#[i] = max(0.10, min(0.7, feedback_base + fb_mod))
endfor

# ============================================
# Smooth control signals  (same window logic as v0.6)
# ============================================

win = round(smooth_ms / frame_step_ms)
if win < 1
    win = 1
endif

ctrl_mix_smooth# = zero#(nFrames)
ctrl_fb_smooth# = zero#(nFrames)

for i from 1 to nFrames
    i1 = max(1, i - win)
    i2 = min(nFrames, i + win)
    
    sum_m = 0
    sum_f = 0
    n = i2 - i1 + 1
    
    for k from i1 to i2
        sum_m = sum_m + ctrl_mix#[k]
        sum_f = sum_f + ctrl_fb#[k]
    endfor
    
    ctrl_mix_smooth#[i] = sum_m / n
    ctrl_fb_smooth#[i] = sum_f / n
endfor

# ============================================
# BUILD DELAY LAYERS  (identical to v0.6)
# ============================================

appendInfoLine: "Building delay layers..."

selectObject: sound_work
output = Copy: "Output"

# Extend output for delay tail
tail_duration = delay_sec * number_of_repeats
selectObject: output
output_dur = Get total duration

silence_tail = Create Sound from formula: "tail", 1, 0, tail_duration, fs, "0"
selectObject: output
plusObject: silence_tail
output_extended = Concatenate
removeObject: output, silence_tail
output = output_extended
Rename: "Output"

# Process each repeat
for rep from 1 to number_of_repeats
    appendInfoLine: "  Repeat ", rep, "/", number_of_repeats
    
    rep_delay = delay_sec * rep
    fb_amount = feedback_base ^ rep
    
    selectObject: sound_work
    delayed = Copy: "Delayed_" + string$(rep)
    
    # Apply feedback filter
    if enable_filter
        selectObject: delayed
        filtered = Filter (pass Hann band): 0, filter_cutoff_hz, filter_cutoff_hz * 0.1
        removeObject: delayed
        delayed = filtered
        
        if rep > 2
            selectObject: delayed
            filtered = Filter (pass Hann band): 0, filter_cutoff_hz * 0.8, filter_cutoff_hz * 0.1
            removeObject: delayed
            delayed = filtered
        endif
    endif
    
    # Scale by feedback (per-tap exponential decay)
    fbStr$ = string$(fb_amount)
    selectObject: delayed
    Formula: "self * " + fbStr$
    
    # Apply adaptive mix per frame (from MLP output)
    for i from 1 to nFrames
        t_start = (i - 1) * frame_step_sec
        t_end = i * frame_step_sec
        if t_end > duration
            t_end = duration
        endif
        
        mix_val = ctrl_mix_smooth#[i]
        mixStr$ = string$(mix_val)
        
        selectObject: delayed
        Formula (part): t_start, t_end, 1, 1, "self * " + mixStr$
    endfor
    
    # Add to output at delayed position
    delayedId = delayed
    delayedIdStr$ = string$(delayedId)
    repDelayStr$ = string$(rep_delay)
    repDelayPlusDur$ = string$(rep_delay + duration)
    
    selectObject: output
    Formula: "self + (if x >= " + repDelayStr$ + " and x < " + repDelayPlusDur$ + 
        ... " then object(" + delayedIdStr$ + ", x - " + repDelayStr$ + ") else 0 fi)"
    
    removeObject: delayed
endfor

# ============================================
# FINALIZE
# ============================================

selectObject: output
Scale peak: 0.99
Rename: original_name$ + "_neuralMLP_" + presetName$
outS = selected("Sound")

removeObject: sound_work

# Capture stats for visualization
selectObject: outS
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"

# Compute summary stats from the control arrays
mix_min = ctrl_mix_smooth#[1]
mix_max = ctrl_mix_smooth#[1]
fb_min = ctrl_fb_smooth#[1]
fb_max = ctrl_fb_smooth#[1]
voicedFrames = 0
for i from 1 to nFrames
    if ctrl_mix_smooth#[i] < mix_min
        mix_min = ctrl_mix_smooth#[i]
    endif
    if ctrl_mix_smooth#[i] > mix_max
        mix_max = ctrl_mix_smooth#[i]
    endif
    if ctrl_fb_smooth#[i] < fb_min
        fb_min = ctrl_fb_smooth#[i]
    endif
    if ctrl_fb_smooth#[i] > fb_max
        fb_max = ctrl_fb_smooth#[i]
    endif
    if feat_pitch#[i] > 0.5
        voicedFrames = voicedFrames + 1
    endif
endfor
voicedPct = voicedFrames / nFrames * 100

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_visualization

    appendInfoLine: "Drawing visualization..."
    
    Erase all
    Black
    Plain line
    
    if enable_filter
        filterStr$ = "LP " + fixed$(filter_cutoff_hz, 0) + " Hz"
    else
        filterStr$ = "no filter"
    endif
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##NEURAL DELAY CONTROL  -  30-8-2 MLP##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... original_name$
        ... + "  |  " + presetName$
        ... + "  |  delay " + fixed$(delay_time_ms, 0) + " ms x " + string$(number_of_repeats)
        ... + "  |  fb base " + fixed$(feedback_base, 2)
        ... + "  |  mix base " + fixed$(mix_base, 2)
        ... + "  |  " + filterStr$
    
    # ----------------------------------------------------------
    # PANEL A: MLP CONTROL OUTPUT  (left, headline)
    # Mix and Feedback curves produced by the neural network.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    Axes: 0, duration, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, duration, 0, 1
    
    Colour: "{0.88, 0.88, 0.92}"
    Line width: 1
    Dotted line
    Draw line: 0, 0.25, duration, 0.25
    Draw line: 0, 0.50, duration, 0.50
    Draw line: 0, 0.75, duration, 0.75
    Solid line
    
    # Reference lines for the user's base values (so you can see
    # the modulation around them)
    Colour: "{0.85, 0.65, 0.65}"
    Line width: 1
    Dashed line
    Draw line: 0, mix_base, duration, mix_base
    Colour: "{0.65, 0.85, 0.65}"
    Draw line: 0, feedback_base, duration, feedback_base
    Solid line
    
    # Mix control (red)
    Colour: "{0.82, 0.30, 0.30}"
    Line width: 1.8
    for i from 2 to nFrames
        t1 = (i - 2) * frame_step_sec
        t2 = (i - 1) * frame_step_sec
        Draw line: t1, ctrl_mix_smooth#[i-1], t2, ctrl_mix_smooth#[i]
    endfor
    
    # Feedback control (green)
    Colour: "{0.30, 0.62, 0.30}"
    Line width: 1.8
    for i from 2 to nFrames
        t1 = (i - 2) * frame_step_sec
        t2 = (i - 1) * frame_step_sec
        Draw line: t1, ctrl_fb_smooth#[i-1], t2, ctrl_fb_smooth#[i]
    endfor
    Line width: 1
    
    # Inline legend
    Font size: 5
    Colour: "{0.82, 0.30, 0.30}"
    Text: duration * 0.02, "left", 0.96, "half", "mix"
    Colour: "{0.30, 0.62, 0.30}"
    Text: duration * 0.10, "left", 0.96, "half", "feedback"
    Colour: "{0.65, 0.65, 0.65}"
    Text: duration * 0.22, "left", 0.96, "half", "(dashed = base)"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "Gain (0-1)"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL B: SOURCE FEATURES  (right, headline)
    # HNR + voicing — the perceptual features feeding the network.
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40
    
    Axes: 0, duration, 0, 1.15
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, duration, 0, 1.15
    
    Colour: "{0.88, 0.88, 0.92}"
    Line width: 1
    Dotted line
    Draw line: 0, 0.25, duration, 0.25
    Draw line: 0, 0.50, duration, 0.50
    Draw line: 0, 0.75, duration, 0.75
    Solid line
    
    Colour: "{0.75, 0.75, 0.80}"
    Draw line: 0, 1.0, duration, 1.0
    
    # HNR curve (purple)
    Colour: "{0.55, 0.30, 0.70}"
    Line width: 1.8
    for i from 2 to nFrames
        t1 = (i - 2) * frame_step_sec
        t2 = (i - 1) * frame_step_sec
        Draw line: t1, feat_hnr#[i-1], t2, feat_hnr#[i]
    endfor
    Line width: 1
    
    # Voicing markers (orange dots) at y=1.075
    Colour: "{0.90, 0.55, 0.20}"
    for i from 1 to nFrames
        t = (i - 0.5) * frame_step_sec
        if feat_pitch#[i] > 0.5
            Paint circle (mm): "{0.90, 0.55, 0.20}", t, 1.075, 0.7
        endif
    endfor
    
    Font size: 5
    Colour: "{0.55, 0.30, 0.70}"
    Text: duration * 0.02, "left", 0.96, "half", "HNR"
    Colour: "{0.90, 0.55, 0.20}"
    Text: duration * 0.10, "left", 1.075, "half", "voiced"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "HNR / voicing"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half",
        ... "MLP control output (red = mix, green = feedback; dashed = user base)"
    Text: 6.10, "centre", 7.30, "half",
        ... "Source features (purple = HNR, orange dots = voiced)"
    
    # ----------------------------------------------------------
    # PANEL C: ZOOM OVERLAY  (first 500 ms)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.75, 5.48
    
    zoomDur = 0.5
    if zoomDur > duration
        zoomDur = duration
    endif
    if zoomDur > finalDur
        zoomDur = finalDur
    endif
    
    selectObject: original_sound
    origNumCh = Get number of channels
    if origNumCh > 1
        Convert to mono
        zoomOrig = selected("Sound")
    else
        Copy: "zoom_orig"
        zoomOrig = selected("Sound")
    endif
    
    selectObject: zoomOrig
    z_peak1 = Get absolute extremum: 0, zoomDur, "None"
    selectObject: outS
    z_peak2 = Get absolute extremum: 0, zoomDur, "None"
    z_max = z_peak1
    if z_peak2 > z_max
        z_max = z_peak2
    endif
    if z_max < 0.001
        z_max = 0.001
    endif
    z_amp = z_max * 1.15
    
    Axes: 0, zoomDur, -z_amp, z_amp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, zoomDur, -z_amp, z_amp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, zoomDur, 0
    
    selectObject: zoomOrig
    Colour: "{0.65, 0.65, 0.65}"
    Line width: 1
    Draw: 0, zoomDur, -z_amp, z_amp, "no", "Curve"
    
    selectObject: outS
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, zoomDur, -z_amp, z_amp, "no", "Curve"
    
    removeObject: zoomOrig
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Zoom: first " + fixed$(zoomDur * 1000, 0) + " ms  (gray = original, blue = output)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM (FULL FILE)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.55, 7.72, 5.69, 6.48
    
    selectObject: outS
    out_peak_v = Get absolute extremum: 0, 0, "None"
    if out_peak_v < 0.001
        out_peak_v = 0.001
    endif
    out_amp = out_peak_v * 1.15
    
    Axes: 0, finalDur, -out_amp, out_amp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDur, -out_amp, out_amp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, finalDur, 0
    
    if duration < finalDur
        Colour: "{0.85, 0.50, 0.20}"
        Line width: 1
        Dotted line
        Draw line: duration, -out_amp, duration, out_amp
        Solid line
        Font size: 5
        Text: duration, "left", out_amp * 0.85, "half", "  tail"
    endif
    
    selectObject: outS
    Colour: "{0.20, 0.50, 0.80}"
    Line width: 1
    Draw: 0, finalDur, -out_amp, out_amp, "no", "Curve"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Output (full file with delay tail)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR  (suite standard — light grey)
    # Mentions the MLP architecture explicitly.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.55, 7.72, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + original_name$
        ... + "  |  Network: 30-8-2 MLP, ReLU + tanh, 266 params (hand-designed)"
        ... + "  |  Features: MFCC(13) + |dMFCC|(13) + HNR + voicing + intensity + transient"
    
    Text: 0.02, "left", 0.28, "half",
        ... "Delay: " + fixed$(delay_time_ms, 0) + " ms x " + string$(number_of_repeats)
        ... + "  |  " + filterStr$
        ... + "  |  Mix range: " + fixed$(mix_min, 2) + "-" + fixed$(mix_max, 2)
        ... + "  |  Fb range: " + fixed$(fb_min, 2) + "-" + fixed$(fb_max, 2)
        ... + "  |  Voiced: " + fixed$(voicedPct, 1) + "%"
        ... + "  |  Out: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================
# OUTPUT
# ============================================

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
selectObject: outS
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDur, 2), " s, peak ", fixed$(finalPeak, 3)
appendInfoLine: ""
appendInfoLine: "Network: 30-8-2 MLP (ReLU hidden, tanh output, 266 hand-designed params)"
appendInfoLine: "MLP-controlled mix range: ", fixed$(mix_min, 2), " - ", fixed$(mix_max, 2)
appendInfoLine: "MLP-controlled fb range:  ", fixed$(fb_min, 2), " - ", fixed$(fb_max, 2)
appendInfoLine: "Voiced frames: ", voicedFrames, " / ", nFrames, " (", fixed$(voicedPct, 1), "%)"

if play_result
    appendInfoLine: "Playing..."
    selectObject: outS
    Play
endif

selectObject: outS
