# ============================================================
# Praat AudioTools - Neural_Delay_Control.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3 (2026) - Analysis time clamped inside the Sound
#
# Changelog v1.3 (2026):
#
#   1 - The last feature time could fall OUTSIDE the source. ceiling()
#     gives enough rendering intervals, but the centre of the final one
#     sits past the end whenever the remainder is under half a frame:
#     measured at a 20 ms step, a 1.005 s source gives 51 frames and a
#     last query at 1.0100 s - 5 ms beyond the audio. Every analysis
#     then returned its fallback (intensity 60 dB, HNR -10, unvoiced,
#     MFCC clamped to the last real frame), and that fabricated control
#     point also anchored the ramp across the preceding interval, so up
#     to ~25 ms of control was not derived from the source. Gains stayed
#     bounded, so this was never the full-gain burst of v1.1 - but the
#     values were invented. The analysis time is now clamped to half a
#     frame inside the end.
#
#   2 - CORRECTION: v1.2's changelog claimed an explicit
#     mfcc_n_frames >= 1 check. It was never written. Now implemented.
#
#   3 - Remaining user-facing strings and architectural comments moved
#     to the v1.2 terminology: "Feedback base" / "Mix base" / "fb base"
#     -> "Tap decay" / "Echo level", and the old "vocal-formant" and
#     "high-band" MFCC labels in the weight table replaced with the
#     cepstral-shape and cepstral-detail names the implementation
#     comments already use.
#
# Version: 1.2 (2026) - Continuous control envelope, tail coverage, honest naming
#
# Changelog v1.2 (2026):
#
#   AUDIO CHANGES in every preset. Four of these alter the sound.
#
#   CRITICAL 1 - the last fragment of every delayed copy kept FULL
#     gain. nFrames used floor(duration / frame_step), so whenever the
#     source length was not an exact multiple of the step, the
#     remainder was never touched by any Formula (part) and stayed at
#     gain 1.0 while the rest of the tap sat at echo * decay^rep.
#     Measured at a 20 ms step on a 1.013 s source (50 frames cover
#     1.000 s, leaving 13 ms), with Clean Digital's 0.30 / 0.35:
#       tap 1 covered 0.10500, tail 1.00000 ->   9.5x too loud
#       tap 2 covered 0.03675, tail 1.00000 ->  27.2x
#       tap 3 covered 0.01286, tail 1.00000 ->  77.7x
#       tap 4 covered 0.00450, tail 1.00000 -> 222.1x
#     So the LATER the echo, the worse it got - a short bright burst
#     at the end of every tap, and the quietest taps were the most
#     disfigured. Now ceiling(), with t_end clamped to the duration.
#
#   CRITICAL 2 - the smoothed control was applied as 20 ms STEPS.
#     ctrl_mix_smooth# and ctrl_fb_smooth# were moving-averaged and
#     then each value was multiplied over a whole block as a constant,
#     so the actual gain function was a staircase: 20 ms flat, jump,
#     20 ms flat, jump. Smoothing shrinks the jumps; it does not
#     remove them. Wherever the waveform is not near zero at a frame
#     boundary that is a discontinuity - zipper noise and amplitude
#     sidebands that belong to the control update rate, not to the
#     delay. v1.2 ramps LINEARLY between consecutive frame gains
#     inside each Formula (part), so the envelope is continuous:
#     frame i runs from g[i] to g[i+1] and frame i+1 starts where it
#     ended.
#
#   3 - Feedback_base renamed Tap_decay_base, and the engine is
#     described for what it is. Every repeat is built from the SOURCE,
#     not from the previous repeat or the accumulating output, so
#     nothing returns to a delay line: this is an MLP-controlled
#     feed-forward multi-tap delay with feedback-LIKE exponential
#     decay, not a recursive feedback system.
#
#   4 - The filter now accumulates with tap index. v1.1 applied one
#     filter pass to repeats 1-2 and two passes to repeats 3 and up,
#     so repeat 6 was no darker than repeat 3 and Ambient Wash stopped
#     evolving after the third echo. Each repeat is now filtered once
#     per round trip (rep passes, capped at 6), which is what a real
#     feedback filter would do to that tap.
#
#   5 - Mix_base renamed Echo_level, and the first tap is now
#     mix * decay^(rep-1) rather than mix * decay^rep. v1.1 applied
#     the decay once even to the first echo, so Clean Digital's
#     "mix 0.30" delivered 0.30 * 0.35 = 0.105. Echo_level now sets
#     the first echo and Tap_decay_base only sets the falloff.
#     Also: this is NOT a dry/wet mix. The output starts as a full
#     copy of the source and Echo_level scales only the taps; there is
#     no dry = 1 - mix anywhere.
#
#   6 - MFCC inputs are clipped, not merely scaled. "/30 (normalized
#     to ~[-1,1])" was a fixed division with no bound, so an MFCC of
#     90 entered the network as 3.0 and a delta of 120 as 4.0, far
#     outside the range the hand-designed weights assume, pushing the
#     ReLU units high and the tanh outputs into saturation. Now
#     clipped to [-1, 1] and the deltas to [0, 1].
#
#   7 - Undefined HNR now reads as "no harmonicity" instead of a
#     quarter of the range. hnr = 0 became (0 + 10)/40 = 0.25, which
#     partially ACTIVATED the HNR detector (2*0.25 - 0.3 = 0.2) on
#     frames where the analysis had simply failed.
#
#   8 - The two spectral units are renamed. MFCCs are DCT
#     coefficients of a Mel-scaled spectrum: a higher coefficient
#     index means faster variation of the spectral envelope along the
#     Mel axis, NOT a higher frequency band. So MFCC 8-13 is not a
#     high-band energy detector and MFCC 1-3 is not a validated
#     formant detector. They are now called low-order cepstral-shape
#     response and high-order cepstral-detail response.
#
#   9 - Validation: repeats >= 1, Echo_level and Tap_decay in range,
#     frame step and smoothing positive, and the filter cutoff kept
#     under Nyquist (4000 Hz was silently illegal on an 8 kHz file).
#
#   10 - Silent and too-short inputs are rejected, including an
#     explicit check that the MFCC analysis produced at least one
#     frame.
#
#   11 - The final Scale peak is now a CONDITIONAL limiter. It used to
#     run unconditionally, which normalised every result to the same
#     peak - erasing the level differences between presets and
#     amplifying a quiet input and its noise floor along with it.
#
#   ON THE FILTER (documented, unchanged): Filter (pass Hann band) is
#   a frequency-domain zero-phase filter with a symmetric impulse
#   response, so it is acausal and can place energy slightly BEFORE a
#   transient. Fine offline; not what an analog causal feedback filter
#   does.
#
#   ON INTENSITY (documented, unchanged): the intensity input is
#   measured against an absolute 60 dB reference, so the same material
#   at a different file gain produces different delay control. That is
#   usable as an aesthetic choice but it means the effect is NOT
#   level-invariant.
#
#   Multichannel input is downmixed to mono; the output is mono.
#
# Version: 1.1 (2026)
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
#       h5: low-order cepstral-shape response
#           (positive weights on MFCC1-3; b=-0.1)
#       h6: timbral-change detector
#           (positive weights on |delta-MFCC1..5|; b=-0.2)
#       h7: high-order cepstral-detail response
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
# Changelog v1.1 (2026):
#   - FIX (structural): the MLP's SECOND output was decorative.
#     ctrl_fb# was computed, smoothed, plotted and reported -- but
#     every tap's gain was still feedback_base^rep, the static form
#     value. The header's central claim ("per-frame mix AND
#     feedback modulation") was half false. v1.1 folds the
#     per-frame feedback into the tap gain: each repeat's frame
#     gain is mix(t) * fb(t)^rep, so sustained/harmonic material
#     (where the network raises fb) rings longer and transients
#     (where the transient detector suppresses fb) die faster --
#     exactly what the hand-designed output weights intended.
#   - SPEED: the delayed-add Formula uses indexed-column reads
#     (object[id, 1, col - offset]) instead of time-interpolated
#     object(id, x) -- the library-standard upgrade. Non-integer
#     delay-in-samples is quantized to the nearest sample
#     (<= half-sample shift; the old interpolated read was also a
#     mild lowpass near Nyquist).
#   - VIZ: title bar uses an explicit inner viewport (outer-only
#     form risks the margin-compression text collision).
#   - Verified on Praat 6.4.42: trailing ";" comments in the
#     weight-init block are legal (parser tolerates them), and 2D
#     comma-indexed pseudo-arrays (w1[j, k]) work as written.
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

form Neural Delay Control v1.3
    optionmenu Preset: 1
        option Manual
        option Clean Digital
        option Analog Warmth
        option Slapback
        option Rhythmic Dotted
        option Ambient Wash
        option Modulated
    positive Delay_time_ms 250
    positive Echo_level 0.3
    positive Tap_decay_base 0.4
    integer Number_of_repeats 4
    boolean Enable_filter 1
    positive Filter_cutoff_hz 4000
    positive Frame_step_ms 20
    positive Smooth_ms 40
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Echo_level sets the FIRST echo; Tap_decay_base sets how fast the
# later taps fall away (tap n = Echo_level * Tap_decay^(n-1)). This is
# not a dry/wet mix: the output starts as a full copy of the source
# and Echo_level scales only the taps.
# Each repeat is built from the SOURCE, so this is a feed-forward
# multi-tap delay with feedback-like decay, not a recursive feedback
# line. Output is mono.
mix_base = echo_level
feedback_base = tap_decay_base

# ============================================
# VALIDATION  (v1.2 fix 9)
# ============================================
warnLines$ = ""
if number_of_repeats < 1
    number_of_repeats = 1
    warnLines$ = warnLines$ + "  ! Number_of_repeats < 1 -> 1 (a non-positive count"
        ... + " gives an invalid tail length)" + newline$
endif
if number_of_repeats > 12
    number_of_repeats = 12
    warnLines$ = warnLines$ + "  ! Number_of_repeats capped at 12" + newline$
endif
if echo_level < 0
    echo_level = 0
    warnLines$ = warnLines$ + "  ! Echo_level < 0 -> 0" + newline$
endif
if echo_level > 1
    echo_level = 1
    warnLines$ = warnLines$ + "  ! Echo_level > 1 -> 1" + newline$
endif
if tap_decay_base < 0
    tap_decay_base = 0
    warnLines$ = warnLines$ + "  ! Tap_decay_base < 0 -> 0" + newline$
endif
if tap_decay_base > 0.95
    tap_decay_base = 0.95
    warnLines$ = warnLines$ + "  ! Tap_decay_base >= 1 would not decay -> 0.95" + newline$
endif
if frame_step_ms < 1
    frame_step_ms = 1
    warnLines$ = warnLines$ + "  ! Frame_step_ms < 1 -> 1" + newline$
endif
if smooth_ms < 0
    smooth_ms = 0
    warnLines$ = warnLines$ + "  ! Smooth_ms < 0 -> 0" + newline$
endif
mix_base = echo_level
feedback_base = tap_decay_base

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
    tap_decay_base = 0.35
    mix_base = 0.3
    echo_level = 0.3
    number_of_repeats = 4
    enable_filter = 0
    presetName$ = "CleanDigital"
elsif preset = 3
    delay_time_ms = 300
    feedback_base = 0.5
    tap_decay_base = 0.5
    mix_base = 0.35
    echo_level = 0.35
    number_of_repeats = 5
    enable_filter = 1
    filter_cutoff_hz = 3000
    presetName$ = "AnalogWarmth"
elsif preset = 4
    delay_time_ms = 80
    feedback_base = 0.15
    tap_decay_base = 0.15
    mix_base = 0.45
    echo_level = 0.45
    number_of_repeats = 2
    enable_filter = 0
    presetName$ = "Slapback"
elsif preset = 5
    delay_time_ms = 375
    feedback_base = 0.45
    tap_decay_base = 0.45
    mix_base = 0.35
    echo_level = 0.35
    number_of_repeats = 4
    enable_filter = 1
    filter_cutoff_hz = 4500
    presetName$ = "RhythmicDotted"
elsif preset = 6
    delay_time_ms = 500
    feedback_base = 0.6
    tap_decay_base = 0.6
    mix_base = 0.4
    echo_level = 0.4
    number_of_repeats = 6
    enable_filter = 1
    filter_cutoff_hz = 2500
    presetName$ = "AmbientWash"
elsif preset = 7
    delay_time_ms = 200
    feedback_base = 0.45
    tap_decay_base = 0.45
    mix_base = 0.35
    echo_level = 0.35
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
writeInfoLine: "=== Neural Delay Control v1.3 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Delay: ", delay_time_ms, " ms | Tap decay: ", fixed$(tap_decay_base, 2)
appendInfoLine: "Echo level: ", fixed$(echo_level, 2), " | Repeats: ", number_of_repeats
if enable_filter
    appendInfoLine: "Filter: LP @ ", filter_cutoff_hz, " Hz"
endif
appendInfoLine: ""

# Work on mono copy
selectObject: original_sound
sound_work = Convert to mono

# v1.2 fix 10: reject silent / too-short input before any analysis.
selectObject: sound_work
srcPeak = Get absolute extremum: 0, 0, "None"
if srcPeak < 1e-6
    removeObject: sound_work
    exitScript: "The selected Sound is silent (or near-silent); nothing to control."
endif
if duration < 0.1
    removeObject: sound_work
    exitScript: "Sound too short: need at least 0.1 s for MFCC analysis."
endif

# v1.2 fix 9: the filter cutoff must stay under Nyquist. 4000 Hz is
# silently illegal on an 8 kHz file, where Nyquist is 4000.
nyquist = fs / 2
if filter_cutoff_hz > nyquist * 0.9
    filter_cutoff_hz = nyquist * 0.9
    warnLines$ = warnLines$ + "  ! Filter_cutoff_hz above Nyquist -> capped to "
        ... + fixed$(filter_cutoff_hz, 0) + " Hz" + newline$
endif
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
w1_bias[5] = -0.1   ; low-order cepstral-shape response
w1_bias[6] = -0.2   ; timbral-change detector
w1_bias[7] = -0.1   ; high-order cepstral-detail response
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

# --- Hidden unit 5: low-order cepstral-shape response ---
w1[5, 1] = 0.5      ; MFCC1 (overall spectral tilt)
w1[5, 2] = 0.3      ; MFCC2 (coarse formant)
w1[5, 3] = 0.2      ; MFCC3

# --- Hidden unit 6: timbral-change detector ---
w1[6, 14] = 0.4     ; |delta-MFCC1|
w1[6, 15] = 0.3     ; |delta-MFCC2|
w1[6, 16] = 0.3     ; |delta-MFCC3|
w1[6, 17] = 0.2     ; |delta-MFCC4|
w1[6, 18] = 0.2     ; |delta-MFCC5|

# --- Hidden unit 7: high-order cepstral-detail response ---
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
w2[1, 5] =  0.15    ; from low-order cepstral shape
w2[1, 6] = -0.15    ; from timbral-change detector
w2[1, 7] = -0.05    ; from high-order cepstral detail
w2[1, 8] =  0.00    ; from constant bias unit (no contribution to mix)

# --- Output 2: feedback modulation ---
w2[2, 1] =  0.15    ; from HNR detector
w2[2, 2] =  0.05    ; from voicing detector
w2[2, 3] = -0.40    ; from transient detector
w2[2, 4] =  0.25    ; from sustained-energy detector
w2[2, 5] =  0.05    ; from low-order cepstral shape
w2[2, 6] = -0.20    ; from timbral-change detector
w2[2, 7] = -0.05    ; from high-order cepstral detail
w2[2, 8] =  0.00    ; from constant bias unit

# ============================================
# FEATURE EXTRACTION  (Praat objects + MFCC buffer)
# ============================================

appendInfoLine: "Extracting features (Intensity, HNR, Pitch, MFCC)..."

# v1.2 CRITICAL 1: ceiling, so the final partial frame is covered.
# floor() left the remainder untouched by any Formula (part), i.e. at
# gain 1.0 while the rest of the tap sat at echo * decay^rep - at a
# 20 ms step and a 1.013 s source that is the last 13 ms of every echo
# roughly ten times too loud, once per repeat.
nFrames = ceiling(duration / frame_step_sec)
if nFrames < 1
    nFrames = 1
endif
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

# v1.3: this check was claimed in v1.2's changelog and never written.
# The 100 ms minimum duration makes it unlikely, but an MFCC analysis
# that yields no frame would leave every feature read clamped to a
# frame index of zero.
if mfcc_n_frames < 1
    exitScript: "MFCC analysis produced no frames; the input is too short"
        ... + " or too quiet for a 25 ms analysis window."
endif

# Prefetch all features into pseudo-arrays so the network forward
# pass doesn't repeatedly cross Praat's command boundary
for i from 1 to nFrames
    # v1.3: keep the analysis point inside the Sound. ceiling() gives
    # enough RENDERING intervals, but the centre of the last one can
    # sit past the end when the final remainder is under half a frame:
    # at a 20 ms step and a 1.005 s source, frame 51 queries 1.0100 s,
    # 5 ms beyond the audio. Every analysis then falls back to its
    # default - intensity 60 dB, HNR -10, unvoiced, MFCC clamped to the
    # last real frame - and that fabricated control point also anchors
    # the ramp across the preceding interval. Clamped to half a frame
    # inside the end, so the last control value is still measured from
    # real audio.
    t = (i - 0.5) * frame_step_sec
    tMax = duration - frame_step_sec / 2
    if tMax < 0
        tMax = duration / 2
    endif
    if t > tMax
        t = tMax
    endif

    selectObject: intensity_obj
    iv = Get value at time: t, "cubic"
    if iv = undefined
        iv = 60
    endif
    feat_intensity#[i] = iv
    
    selectObject: hnr_obj
    hnr = Get value at time: t, "cubic"
    if hnr = undefined
        # v1.2 fix 7: undefined HNR means NO harmonicity. The old
        # hnr = 0 became (0 + 10)/40 = 0.25 and partially activated
        # the HNR detector on frames where the analysis had failed.
        hnr = -10
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
        # v1.2 fix 6: CLIP, do not merely scale. An MFCC of 90
        # entered as 3.0 under the old "/30", far outside the range
        # the hand-designed weights assume.
        x[c] = mfcc_buf[i, c] / 30
        if x[c] > 1
            x[c] = 1
        endif
        if x[c] < -1
            x[c] = -1
        endif
    endfor
    # [14..26]: normalized |delta-MFCC|
    for c from 1 to 13
        x[13 + c] = dmfcc_buf[i, c] / 30
        if x[13 + c] > 1
            x[13 + c] = 1
        endif
        if x[13 + c] < 0
            x[13 + c] = 0
        endif
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
    
    selectObject: sound_work
    delayed = Copy: "Delayed_" + string$(rep)
    
    # v1.2 fix 4: the filter accumulates with tap index - one pass per
    # round trip. v1.1 gave repeats 1-2 a single pass and everything
    # from 3 up exactly two, so repeat 6 was no darker than repeat 3
    # and Ambient Wash stopped evolving after the third echo.
    if enable_filter
        nPasses = rep
        if nPasses > 6
            nPasses = 6
        endif
        for pass from 1 to nPasses
            selectObject: delayed
            filtered = Filter (pass Hann band): 0, filter_cutoff_hz, filter_cutoff_hz * 0.1
            removeObject: delayed
            delayed = filtered
        endfor
    endif

    # v1.2 CRITICAL 2: ramp the gain LINEARLY across each frame rather
    # than holding it constant. v1.1 multiplied a whole 20 ms block by
    # one number, so the envelope was a staircase - smoothing shrinks
    # those jumps but does not remove them, and every jump on a
    # non-zero sample is a discontinuity. Frame i now runs from g[i] to
    # g[i+1] and frame i+1 begins exactly where it ended, so the
    # envelope is continuous.
    #
    # v1.2 fix 5: exponent is rep-1, so Echo_level sets the FIRST echo
    # and the decay only shapes the ones after it. v1.1 used rep, so
    # Clean Digital's stated mix of 0.30 actually delivered
    # 0.30 * 0.35 = 0.105.
    for i from 1 to nFrames
        t_start = (i - 1) * frame_step_sec
        t_end = i * frame_step_sec
        if t_end > duration
            t_end = duration
        endif

        gain_a = ctrl_mix_smooth#[i] * ctrl_fb_smooth#[i] ^ (rep - 1)
        if i < nFrames
            gain_b = ctrl_mix_smooth#[i + 1] * ctrl_fb_smooth#[i + 1] ^ (rep - 1)
        else
            gain_b = gain_a
        endif

        segLen = t_end - t_start
        if segLen > 1e-9
            aStr$ = fixed$(gain_a, 9)
            slopeStr$ = fixed$((gain_b - gain_a) / segLen, 9)
            t0Str$ = fixed$(t_start, 9)
            selectObject: delayed
            Formula (part): t_start, t_end, 1, 1,
                ... "self * (" + aStr$ + " + " + slopeStr$ + " * (x - " + t0Str$ + "))"
        endif
    endfor
    
    # Add to output at delayed position.
    # v1.1: indexed-column read (out-of-range object[] reads return
    # 0, so no explicit bounds condition is needed). Non-integer
    # delay-in-samples quantizes to the nearest sample.
    delayedIdStr$ = string$(delayed)
    offsetCol = round(rep_delay * fs)
    offsetColStr$ = string$(offsetCol)
    
    selectObject: output
    Formula: "self + object[" + delayedIdStr$ + ", 1, col - " + offsetColStr$ + "]"
    
    removeObject: delayed
endfor

# ============================================
# FINALIZE
# ============================================

# v1.2 fix 11: a CONDITIONAL limiter. Running Scale peak
# unconditionally normalised every result to the same peak, erasing
# the level differences between presets and lifting a quiet input and
# its noise floor along with it.
selectObject: output
outPeak = Get absolute extremum: 0, 0, "None"
if outPeak > 0.99
    selectObject: output
    Scale peak: 0.99
    appendInfoLine: "  Limiter engaged (peak was ", fixed$(outPeak, 3), ")"
endif

selectObject: output
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
    Select inner viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half", "##NEURAL DELAY CONTROL  -  30-8-2 MLP##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.26, "half",
        ... original_name$
        ... + "  |  " + presetName$
        ... + "  |  delay " + fixed$(delay_time_ms, 0) + " ms x " + string$(number_of_repeats)
        ... + "  |  tap decay " + fixed$(tap_decay_base, 2)
        ... + "  |  echo level " + fixed$(mix_base, 2)
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
