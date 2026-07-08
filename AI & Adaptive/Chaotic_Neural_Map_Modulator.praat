# ============================================================
# Praat AudioTools - Chaotic_Neural_Map_Modulator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v2.1 (2026):
#   - FIX: backpropagation computed hidden-layer deltas from output
#     weights that had ALREADY been updated in the same training
#     step (w_out was modified, then read for error propagation).
#     The update was therefore not the gradient. All deltas are now
#     computed from pre-update weights, then all updates applied.
#     (Same recurring pattern as in-place Formula reads: values
#     consumed after being overwritten within one conceptual step.)
#   - Ring-mod accumulated phase now wrapped mod 2*pi per segment
#     (precision hygiene for long inputs; audibly identical).
#   - Verified empirically (Praat 6.4.42): Spectrogram slices carry
#     zero imaginary parts, so the rolloff's re^2 power is correct;
#     PSOLA resynthesis preserves the sample count; out-of-range
#     object[] reads return 0 (dry/wet 1-sample mismatch is benign).
#
# Description:
#   Content-aware chaotic modulation. A small MLP is trained on
#   feature streams from the input, iterated with controlled
#   instability, and its output modulates pitch, amplitude, and
#   ring-frequency. The application is content-aware: pitch is
#   modulated RELATIVE to the input's tracked F0 contour and
#   quantized to a chosen scale; ring-modulation locks to
#   harmonic multiples of local F0; unvoiced frames skip
#   pitch-shift entirely; modulation depth reduces near transients.
#
# Design vs v1.x (substantial rewrite — not compatible):
#   v1.x treated the input as a texture to overwrite with chaos.
#   This produced inventive damage but wasn't musically coherent
#   for any input with pitch, tempo, or articulation.
#
#   v2.0 reframes the tool as a content-aware modulator:
#     * Pitch modulation follows the input's contour instead of
#       replacing it with a median. On speech, vowel intonation is
#       preserved + wobbled. On melody, note shape is retained.
#     * Ring-mod frequency locks to harmonic ratios of local F0
#       when F0 is confident. Sidebands sit at consonant intervals
#       (octave, fifth, fourth, etc.) instead of arbitrary Hz.
#     * Unvoiced frames (fricatives, drums, silence, noise) skip
#       the pitch-shift stage entirely — PSOLA never runs on them.
#       Amplitude and ring-mod still apply at reduced depth.
#     * 10 ms modulation control rate instead of 60 ms. Chaos is
#       still iterated at 60 ms (it's about slow dynamics), but
#       the tiers applied to audio are interpolated 6x finer.
#     * Mono only. Independent-chaos-per-channel stereo was a
#       design error. Run the tool twice with different seeds
#       and combine externally if you want stereo.
#     * Pitch deviations quantized to a chosen scale.
#     * Transient-aware: near onsets, modulation depth reduces.
#
# Scope (honest limits):
#   v2.0 is content-aware, not tempo-aware. Chaos rate is set by
#   the Modulation_rate_Hz knob; the user picks it to match their
#   piece's pulse (e.g., 4 Hz for 240 BPM quarter-note modulation,
#   2 Hz for 120 BPM). No beat tracker — that's out of scope for
#   pure Praat scripting.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

input_sound_original = selected("Sound")
input_name$ = selected$("Sound")

form Chaotic Neural Map Modulator v2.1
    comment === Presets ===
    optionmenu Preset: 2
        option Custom
        option Subtle Organic
        option Balanced Chaos
        option Wild Unstable
        option Tightly Controlled
        option Glitch Machine

    comment === Core Behavior ===
    real Instability 5.0
    real Modulation_rate_Hz 2.0

    comment === Pitch ===
    real Pitch_range_semitones 6
    optionmenu Pitch_scale: 3
        option Chromatic (no quantization)
        option Major
        option Minor (natural)
        option Pentatonic major
        option Whole tone
        option Stay on input pitch class

    comment === Other Modulations ===
    real Amplitude_mod_depth 0.5
    real Ring_mod_depth 0.3

    comment === Output ===
    real Dry_wet 0.7
    real HF_boost_dB 3
    boolean Draw_visualization 1
    boolean Play_output 1
endform

#=============================================================================
# APPLY PRESET OVERRIDES
#=============================================================================
# Each preset sets Instability + modulation depths + rate.
# Scale stays at user choice. Dry/wet stays at user choice.

if preset = 2
    # SubtleOrganic — quiet wobble, slow
    instability = 2.5
    modulation_rate_Hz = 1.0
    pitch_range_semitones = 3
    amplitude_mod_depth = 0.3
    ring_mod_depth = 0.10
    presetName$ = "SubtleOrganic"
elsif preset = 3
    # BalancedChaos — moderate everything
    instability = 5.0
    modulation_rate_Hz = 2.0
    pitch_range_semitones = 6
    amplitude_mod_depth = 0.5
    ring_mod_depth = 0.25
    presetName$ = "BalancedChaos"
elsif preset = 4
    # WildUnstable — fast, wide
    instability = 8.0
    modulation_rate_Hz = 4.0
    pitch_range_semitones = 12
    amplitude_mod_depth = 0.7
    ring_mod_depth = 0.45
    presetName$ = "WildUnstable"
elsif preset = 5
    # TightlyControlled — fast but shallow
    instability = 4.0
    modulation_rate_Hz = 3.0
    pitch_range_semitones = 4
    amplitude_mod_depth = 0.4
    ring_mod_depth = 0.20
    presetName$ = "TightlyControlled"
elsif preset = 6
    # GlitchMachine — fast, wide, aggressive; still content-aware
    instability = 9.0
    modulation_rate_Hz = 6.0
    pitch_range_semitones = 18
    amplitude_mod_depth = 0.8
    ring_mod_depth = 0.60
    presetName$ = "GlitchMachine"
else
    presetName$ = "Custom"
endif

#=============================================================================
# INTERNAL CONSTANTS (exposed in v1.x, now baked in for form simplicity)
#=============================================================================

# Chaos iteration rate: 60 ms (reasonable for slow organic dynamics)
chaos_step_ms = 60
# Application control rate: 10 ms (finer modulation, supports articulation)
control_step_ms = 10
# MLP size
hidden_neurons = 10
training_iterations = 150
# Random kick and mutation scaled from Instability (0..10)
autonomy = 0.6 + instability / 25
if autonomy > 0.98
    autonomy = 0.98
endif
chaos_volatility = 1.0 + instability * 0.4
kick_interval_ms = 1000 / (modulation_rate_Hz + 0.001)
chaos_mutation = instability / 12
if chaos_mutation > 0.9
    chaos_mutation = 0.9
endif

# Ring-mod harmonic ratios: F0 multipliers for consonant sidebands.
# Excludes unison (collapses signal).
nRingRatios = 7
ringRatio# = {0.5, 0.75, 1.333, 1.5, 2.0, 2.5, 3.0}

#=============================================================================
# INITIALIZATION
#=============================================================================

selectObject: input_sound_original
duration = Get total duration
sr = Get sampling frequency
original_channels = Get number of channels

if original_channels > 1
    input_sound = Convert to mono
    Rename: input_name$ + "_mono"
else
    input_sound = Copy: input_name$ + "_mono"
endif

clearinfo
writeInfoLine: "=== CHAOTIC NEURAL MAP MODULATOR v2.1 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Instability: ", fixed$(instability, 1), "/10"
appendInfoLine: "Modulation rate: ", fixed$(modulation_rate_Hz, 2), " Hz"
appendInfoLine: "Pitch range: ±", fixed$(pitch_range_semitones, 1), " semitones"
scaleName1$ = "Chromatic"
scaleName2$ = "Major"
scaleName3$ = "Minor"
scaleName4$ = "Pentatonic"
scaleName5$ = "Whole-tone"
scaleName6$ = "Stay-on-pitch"
if pitch_scale = 1
    scaleName$ = scaleName1$
elsif pitch_scale = 2
    scaleName$ = scaleName2$
elsif pitch_scale = 3
    scaleName$ = scaleName3$
elsif pitch_scale = 4
    scaleName$ = scaleName4$
elsif pitch_scale = 5
    scaleName$ = scaleName5$
else
    scaleName$ = scaleName6$
endif
appendInfoLine: "Pitch scale: ", scaleName$
appendInfoLine: ""

#=============================================================================
# FEATURE EXTRACTION (at chaos_step_ms)
#=============================================================================

appendInfoLine: "Extracting features..."

chaos_step_s = chaos_step_ms / 1000
num_frames = floor(duration / chaos_step_s)

if num_frames < 4
    removeObject: input_sound
    exitScript: "Input too short. Need at least "
        ... + fixed$(4 * chaos_step_s, 2) + " s of audio."
endif

time# = zero#(num_frames)
feat_amp# = zero#(num_frames)
feat_centroid# = zero#(num_frames)
feat_rolloff# = zero#(num_frames)
feat_amp_raw# = zero#(num_frames)

for i to num_frames
    time#[i] = (i - 1) * chaos_step_s
endfor

# Intensity (amplitude)
selectObject: input_sound
intensity = To Intensity: 75, chaos_step_s, "yes"
for i to num_frames
    selectObject: intensity
    val = Get value at time: time#[i], "Cubic"
    if val = undefined
        feat_amp#[i] = 70
    else
        feat_amp#[i] = val
    endif
    feat_amp_raw#[i] = feat_amp#[i]
endfor
removeObject: intensity

# Spectrogram for centroid and rolloff
selectObject: input_sound
spectrogram = To Spectrogram: 0.005, 5000, chaos_step_s, 20, "Gaussian"

for i to num_frames
    selectObject: spectrogram
    slice = To Spectrum (slice): time#[i]

    selectObject: slice
    cog = Get centre of gravity: 2
    if cog <> undefined and cog > 0
        feat_centroid#[i] = cog
    else
        feat_centroid#[i] = 2000
    endif

    n_bins = Get number of bins
    total_energy = 0
    for bin to n_bins
        freq = Get frequency from bin number: bin
        if freq > 100 and freq < 5000
            power = Get real value in bin: bin
            total_energy = total_energy + power^2
        endif
    endfor

    target = total_energy * 0.85
    cumulative = 0
    rolloff_freq = 2500
    rolloff_done = 0
    for bin to n_bins
        if rolloff_done = 0
            freq = Get frequency from bin number: bin
            if freq > 100 and freq < 5000
                power = Get real value in bin: bin
                cumulative = cumulative + power^2
                if cumulative >= target
                    rolloff_freq = freq
                    rolloff_done = 1
                endif
            endif
        endif
    endfor

    feat_rolloff#[i] = rolloff_freq
    removeObject: slice
endfor
removeObject: spectrogram

# Normalize features to [0, 1]
min_v = feat_amp#[1]
max_v = feat_amp#[1]
for i from 2 to num_frames
    if feat_amp#[i] < min_v
        min_v = feat_amp#[i]
    endif
    if feat_amp#[i] > max_v
        max_v = feat_amp#[i]
    endif
endfor
range_v = max_v - min_v + 0.001
for i to num_frames
    feat_amp#[i] = (feat_amp#[i] - min_v) / range_v
endfor

min_v = feat_centroid#[1]
max_v = feat_centroid#[1]
for i from 2 to num_frames
    if feat_centroid#[i] < min_v
        min_v = feat_centroid#[i]
    endif
    if feat_centroid#[i] > max_v
        max_v = feat_centroid#[i]
    endif
endfor
range_v = max_v - min_v + 0.001
for i to num_frames
    feat_centroid#[i] = (feat_centroid#[i] - min_v) / range_v
endfor

min_v = feat_rolloff#[1]
max_v = feat_rolloff#[1]
for i from 2 to num_frames
    if feat_rolloff#[i] < min_v
        min_v = feat_rolloff#[i]
    endif
    if feat_rolloff#[i] > max_v
        max_v = feat_rolloff#[i]
    endif
endfor
range_v = max_v - min_v + 0.001
for i to num_frames
    feat_rolloff#[i] = (feat_rolloff#[i] - min_v) / range_v
endfor

appendInfoLine: "  ", num_frames, " frames extracted"

#=============================================================================
# F0 TRACKING
#=============================================================================

appendInfoLine: "Tracking F0..."

selectObject: input_sound
pitch_obj = To Pitch: chaos_step_s, 75, 600
median_f0 = Get quantile: 0, 0, 0.5, "Hertz"
if median_f0 = undefined or median_f0 < 75
    median_f0 = 200
    appendInfoLine: "  F0 undefined, fallback median = 200 Hz"
else
    appendInfoLine: "  Median F0 = ", fixed$(median_f0, 1), " Hz"
endif

# Per-chaos-frame F0 and voiced flag
f0_chaos# = zero#(num_frames)
voiced_chaos# = zero#(num_frames)
for i to num_frames
    selectObject: pitch_obj
    f0val = Get value at time: time#[i], "Hertz", "Linear"
    if f0val = undefined
        f0_chaos#[i] = median_f0
        voiced_chaos#[i] = 0
    else
        f0_chaos#[i] = f0val
        voiced_chaos#[i] = 1
    endif
endfor
removeObject: pitch_obj

nVoiced = 0
for i to num_frames
    if voiced_chaos#[i] = 1
        nVoiced = nVoiced + 1
    endif
endfor
appendInfoLine: "  Voiced: ", nVoiced, "/", num_frames,
    ... " frames (", fixed$(100 * nVoiced / num_frames, 1), "%)"

#=============================================================================
# TRANSIENT DETECTION
#=============================================================================

appendInfoLine: "Detecting transients..."

modDepthScale# = zero#(num_frames)
for i to num_frames
    modDepthScale#[i] = 1
endfor

transient_dB = 6.0
guard_frames = 3
nTransients = 0
for i from 2 to num_frames
    di = feat_amp_raw#[i] - feat_amp_raw#[i - 1]
    if di >= transient_dB
        nTransients = nTransients + 1
        gEnd = i + guard_frames
        if gEnd > num_frames
            gEnd = num_frames
        endif
        for j from i to gEnd
            frac = (j - i) / guard_frames
            if frac > 1
                frac = 1
            endif
            if modDepthScale#[j] > frac
                modDepthScale#[j] = frac
            endif
        endfor
    endif
endfor
appendInfoLine: "  ", nTransients, " transients flagged"

#=============================================================================
# TRAIN MLP
#=============================================================================

appendInfoLine: "Training neural network (", hidden_neurons,
    ... " hidden, ", training_iterations, " iter)..."

for h to hidden_neurons
    w_in_'h'_1 = randomUniform(-0.5, 0.5)
    w_in_'h'_2 = randomUniform(-0.5, 0.5)
    w_in_'h'_3 = randomUniform(-0.5, 0.5)
    b_h_'h' = randomUniform(-0.5, 0.5)
endfor
for d to 3
    for h to hidden_neurons
        w_out_'d'_'h' = randomUniform(-0.5, 0.5)
    endfor
    b_o_'d' = randomUniform(-0.5, 0.5)
endfor

learning_rate = 0.12
trainLoss# = zero#(training_iterations)

for iter to training_iterations
    iterSSE = 0
    iterCount = 0
    for frame from 2 to num_frames - 1
        inp_1 = feat_amp#[frame]
        inp_2 = feat_centroid#[frame]
        inp_3 = feat_rolloff#[frame]
        targ_1 = feat_amp#[frame + 1]
        targ_2 = feat_centroid#[frame + 1]
        targ_3 = feat_rolloff#[frame + 1]

        for h to hidden_neurons
            sum = b_h_'h'
            sum = sum + inp_1 * w_in_'h'_1
            sum = sum + inp_2 * w_in_'h'_2
            sum = sum + inp_3 * w_in_'h'_3
            if sum > 20
                hid_'h' = 1
            elsif sum < -20
                hid_'h' = -1
            else
                hid_'h' = (exp(sum) - exp(-sum)) / (exp(sum) + exp(-sum))
            endif
        endfor

        for d to 3
            sum = b_o_'d'
            for h to hidden_neurons
                hidVal = hid_'h'
                wVal = w_out_'d'_'h'
                sum = sum + hidVal * wVal
            endfor
            if sum > 20
                out_'d' = 1
            elsif sum < -20
                out_'d' = -1
            else
                out_'d' = (exp(sum) - exp(-sum)) / (exp(sum) + exp(-sum))
            endif
        endfor

        # v2.1: correct gradient ordering. All deltas are computed
        # BEFORE any weight is touched -- v2.0 updated w_out first
        # and then read the updated values when backpropagating to
        # the hidden layer, so the hidden update wasn't the gradient.

        # 1) Output deltas (and loss accounting)
        for d to 3
            if d = 1
                targVal = targ_1
            elsif d = 2
                targVal = targ_2
            else
                targVal = targ_3
            endif
            outVal = out_'d'
            err = targVal - outVal
            iterSSE = iterSSE + err * err
            iterCount = iterCount + 1
            delta_o_'d' = err * (1 - outVal^2)
        endfor

        # 2) Hidden deltas from PRE-UPDATE output weights
        for h to hidden_neurons
            dh = 0
            for d to 3
                deltaO = delta_o_'d'
                wOut = w_out_'d'_'h'
                dh = dh + deltaO * wOut
            endfor
            hidVal = hid_'h'
            delta_h_'h' = dh * (1 - hidVal^2)
        endfor

        # 3) Apply all updates
        for d to 3
            deltaVal = delta_o_'d'
            for h to hidden_neurons
                hidVal = hid_'h'
                w_out_'d'_'h' = w_out_'d'_'h' + learning_rate * deltaVal * hidVal
            endfor
            b_o_'d' = b_o_'d' + learning_rate * deltaVal
        endfor

        for h to hidden_neurons
            dh = delta_h_'h'
            w_in_'h'_1 = w_in_'h'_1 + learning_rate * dh * inp_1
            w_in_'h'_2 = w_in_'h'_2 + learning_rate * dh * inp_2
            w_in_'h'_3 = w_in_'h'_3 + learning_rate * dh * inp_3
            b_h_'h' = b_h_'h' + learning_rate * dh
        endfor
    endfor
    if iterCount > 0
        trainLoss#[iter] = iterSSE / iterCount
    endif
endfor
appendInfoLine: "  Final MSE: ", fixed$(trainLoss#[training_iterations], 6)

#=============================================================================
# GENERATE CHAOS (at chaos_step_ms)
#=============================================================================

appendInfoLine: "Generating chaos..."

chaos_pitch# = zero#(num_frames)
chaos_amp# = zero#(num_frames)
chaos_ring# = zero#(num_frames)

kick_interval_s = kick_interval_ms / 1000
injection_rate = 1 - autonomy

state_1 = randomUniform(0.2, 0.8)
state_2 = randomUniform(0.2, 0.8)
state_3 = randomUniform(0.2, 0.8)
last_kick = 0

for frame to num_frames
    inject = 0
    if time#[frame] - last_kick >= kick_interval_s
        inject = 1
        last_kick = time#[frame]
    endif
    if randomUniform(0, 1) < chaos_mutation * 0.3
        inject = 1 - inject
    endif

    if inject = 1
        inp_1 = feat_amp#[frame] * injection_rate + state_1 * (1 - injection_rate)
        inp_2 = feat_centroid#[frame] * injection_rate + state_2 * (1 - injection_rate)
        inp_3 = feat_rolloff#[frame] * injection_rate + state_3 * (1 - injection_rate)
    else
        inp_1 = state_1
        inp_2 = state_2
        inp_3 = state_3
    endif

    if chaos_mutation > 0
        inp_1 = inp_1 + randomUniform(-1, 1) * chaos_mutation * 0.2
        inp_2 = inp_2 + randomUniform(-1, 1) * chaos_mutation * 0.2
        inp_3 = inp_3 + randomUniform(-1, 1) * chaos_mutation * 0.2
        inp_1 = max(0, min(1, inp_1))
        inp_2 = max(0, min(1, inp_2))
        inp_3 = max(0, min(1, inp_3))
    endif

    for h to hidden_neurons
        sum = b_h_'h'
        sum = sum + inp_1 * w_in_'h'_1
        sum = sum + inp_2 * w_in_'h'_2
        sum = sum + inp_3 * w_in_'h'_3
        if sum > 20
            hid_'h' = 1
        elsif sum < -20
            hid_'h' = -1
        else
            hid_'h' = (exp(sum) - exp(-sum)) / (exp(sum) + exp(-sum))
        endif
    endfor

    for d to 3
        sum = b_o_'d'
        for h to hidden_neurons
            hidVal = hid_'h'
            wVal = w_out_'d'_'h'
            sum = sum + hidVal * wVal
        endfor
        if sum > 20
            new_state = 1
        elsif sum < -20
            new_state = -1
        else
            new_state = (exp(sum) - exp(-sum)) / (exp(sum) + exp(-sum))
        endif

        volatility_factor = chaos_volatility * randomUniform(0.8, 1.2)
        new_state = (new_state - 0.5) * volatility_factor + 0.5
        new_state = max(0, min(1, new_state))

        chaos_val = new_state * 2 - 1

        if d = 1
            chaos_pitch#[frame] = chaos_val
            state_1 = new_state
        elsif d = 2
            chaos_amp#[frame] = chaos_val
            state_2 = new_state
        else
            chaos_ring#[frame] = chaos_val
            state_3 = new_state
        endif
    endfor
endfor

#=============================================================================
# BUILD CONTROL-RATE SIGNALS (at control_step_ms)
#
# The chaos stream lives at 60 ms; the modulation applied to audio
# needs finer resolution for articulation. We build:
#   tCtrl#[]            — control-rate timestamps
#   pitchShiftCents#[]  — per-tick pitch shift in cents (scale-quantized,
#                         zero on unvoiced frames)
#   intensityDeltadB#[] — per-tick intensity delta in dB
#   ringFreq#[]         — per-tick ring-mod frequency (F0-locked when
#                         voiced, fallback band when unvoiced)
#   ringMix#[]          — per-tick ring-mod mix (reduced when unvoiced)
#   voicedAtCtrl#[]     — 1 if this tick's nearest chaos frame is voiced
#=============================================================================

appendInfoLine: "Building control-rate signals..."

control_step_s = control_step_ms / 1000
num_ctrl = floor(duration / control_step_s)

tCtrl# = zero#(num_ctrl)
pitchShiftCents# = zero#(num_ctrl)
intensityDeltadB# = zero#(num_ctrl)
ringFreq# = zero#(num_ctrl)
ringMix# = zero#(num_ctrl)
voicedAtCtrl# = zero#(num_ctrl)
f0AtCtrl# = zero#(num_ctrl)

# Helper procedure: quantize a semitone delta to the chosen scale.
procedure quantizeScale: .st_in, .scaleChoice

    if .scaleChoice = 1
        # Chromatic: no quantization
        quantizeScale.st_out = .st_in

    elsif .scaleChoice = 6
        # Stay on input pitch class: snap to 0, ±12, ±24
        .oct = round(.st_in / 12)
        quantizeScale.st_out = .oct * 12

    else
        # Snap to nearest scale tone, modulo octave.
        if .scaleChoice = 2
            .scaleTones# = {0, 2, 4, 5, 7, 9, 11}
            .nST = 7
        elsif .scaleChoice = 3
            .scaleTones# = {0, 2, 3, 5, 7, 8, 10}
            .nST = 7
        elsif .scaleChoice = 4
            .scaleTones# = {0, 2, 4, 7, 9}
            .nST = 5
        elsif .scaleChoice = 5
            .scaleTones# = {0, 2, 4, 6, 8, 10}
            .nST = 6
        else
            .scaleTones# = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11}
            .nST = 12
        endif

        .oct = floor(.st_in / 12)
        .residue = .st_in - .oct * 12
        .bestDist = 100
        .bestTone = 0
        for .k from 1 to .nST
            .tone = .scaleTones#[.k]
            .d = abs(.residue - .tone)
            if .d < .bestDist
                .bestDist = .d
                .bestTone = .tone
            endif
        endfor
        .dWrap = abs(.residue - 12)
        if .dWrap < .bestDist
            .bestTone = 0
            .oct = .oct + 1
        endif
        quantizeScale.st_out = .oct * 12 + .bestTone
    endif
endproc

# Helper procedure: pick the ring-mod frequency.
procedure pickRingFreq: .voiced, .f0, .chaos
    if .voiced = 1 and .f0 > 40 and .f0 < 1200
        .idx = round((.chaos + 1) / 2 * (nRingRatios - 1)) + 1
        if .idx < 1
            .idx = 1
        endif
        if .idx > nRingRatios
            .idx = nRingRatios
        endif
        pickRingFreq.freq = .f0 * ringRatio#[.idx]
    else
        pickRingFreq.freq = 350 + .chaos * 150
    endif
endproc

# Build the control-rate vectors
for ci to num_ctrl
    tCtrl#[ci] = (ci - 1) * control_step_s

    chaos_frame = floor(tCtrl#[ci] / chaos_step_s) + 1
    if chaos_frame < 1
        chaos_frame = 1
    endif
    if chaos_frame > num_frames
        chaos_frame = num_frames
    endif

    chaos_frame_next = chaos_frame + 1
    if chaos_frame_next > num_frames
        chaos_frame_next = num_frames
    endif
    chaos_frac = (tCtrl#[ci] - time#[chaos_frame]) / chaos_step_s
    if chaos_frac < 0
        chaos_frac = 0
    endif
    if chaos_frac > 1
        chaos_frac = 1
    endif

    cp = chaos_pitch#[chaos_frame] * (1 - chaos_frac)
        ... + chaos_pitch#[chaos_frame_next] * chaos_frac
    ca = chaos_amp#[chaos_frame] * (1 - chaos_frac)
        ... + chaos_amp#[chaos_frame_next] * chaos_frac
    cr = chaos_ring#[chaos_frame] * (1 - chaos_frac)
        ... + chaos_ring#[chaos_frame_next] * chaos_frac

    depth_scale = modDepthScale#[chaos_frame] * (1 - chaos_frac)
        ... + modDepthScale#[chaos_frame_next] * chaos_frac

    voicedAtCtrl#[ci] = voiced_chaos#[chaos_frame]
    f0AtCtrl#[ci] = f0_chaos#[chaos_frame]

    # --- Pitch shift ---
    if voicedAtCtrl#[ci] = 1
        raw_st = cp * pitch_range_semitones * depth_scale
        @quantizeScale: raw_st, pitch_scale
        pitchShiftCents#[ci] = quantizeScale.st_out * 100
    else
        pitchShiftCents#[ci] = 0
    endif

    # --- Amplitude ---
    if voicedAtCtrl#[ci] = 1
        amp_scale = depth_scale
    else
        amp_scale = depth_scale * 0.5
    endif
    intensityDeltadB#[ci] = ca * 15 * amplitude_mod_depth * amp_scale

    # --- Ring modulation ---
    @pickRingFreq: voicedAtCtrl#[ci], f0AtCtrl#[ci], cr
    ringFreq#[ci] = pickRingFreq.freq
    if voicedAtCtrl#[ci] = 1
        ringMix#[ci] = ring_mod_depth * depth_scale
    else
        ringMix#[ci] = ring_mod_depth * depth_scale * 0.4
    endif
endfor

#=============================================================================
# APPLY PITCH MODULATION (follows input contour, voiced-only)
#=============================================================================

appendInfoLine: "Applying pitch modulation..."

pitch_tier = Create PitchTier: "chaos_pitch", 0, duration

# Guard: if the input is fully unvoiced, PSOLA has nothing to do.
# An empty PitchTier causes "Replace pitch tier" to fail. Seed the
# tier with the fallback median_f0 at both endpoints so resynthesis
# is well-defined. Since every voicedAtCtrl flag is 0, no per-frame
# points will be added and the result is effectively a resynthesis
# at median_f0 — which we then overwrite by dry at mix time if
# dry_wet < 1. For drum/unvoiced material with dry_wet near 1,
# this branch never runs in practice because PSOLA is bypassed
# semantically by the mix. Either way, the seed prevents a crash.
if nVoiced = 0
    selectObject: pitch_tier
    Add point: 0, median_f0
    Add point: duration, median_f0
endif

for ci to num_ctrl
    if voicedAtCtrl#[ci] = 1
        selectObject: pitch_tier
        semis = pitchShiftCents#[ci] / 100
        newF0 = f0AtCtrl#[ci] * 2 ^ (semis / 12)
        if newF0 < 50
            newF0 = 50
        endif
        if newF0 > 1200
            newF0 = 1200
        endif
        Add point: tCtrl#[ci], newF0
    endif
endfor

selectObject: input_sound
manip = To Manipulation: 0.01, 75, 600
selectObject: manip
plusObject: pitch_tier
Replace pitch tier
selectObject: manip
work_pitched = Get resynthesis (overlap-add)
removeObject: manip, pitch_tier

#=============================================================================
# APPLY AMPLITUDE MODULATION (at control rate)
#=============================================================================

appendInfoLine: "Applying amplitude modulation..."

amp_tier = Create IntensityTier: "chaos_amp", 0, duration
for ci to num_ctrl
    selectObject: amp_tier
    Add point: tCtrl#[ci], 70 + intensityDeltadB#[ci]
endfor

selectObject: work_pitched
plusObject: amp_tier
work_amp = Multiply: "yes"
removeObject: amp_tier, work_pitched

#=============================================================================
# APPLY RING MODULATION (F0-locked, phase-continuous)
#=============================================================================

if ring_mod_depth > 0
    appendInfoLine: "Applying ring modulation..."

    selectObject: work_amp
    ring_carrier = Create Sound from formula: "ring_carrier", 1,
        ... 0, duration, sr, "0"

    accum_phase = 0
    for ci to num_ctrl
        t1 = tCtrl#[ci]
        if ci < num_ctrl
            t2 = tCtrl#[ci + 1]
            f1 = ringFreq#[ci]
            f2 = ringFreq#[ci + 1]
            m1 = ringMix#[ci]
            m2 = ringMix#[ci + 1]
        else
            t2 = duration
            f1 = ringFreq#[ci]
            f2 = ringFreq#[ci]
            m1 = ringMix#[ci]
            m2 = ringMix#[ci]
        endif
        span = t2 - t1
        if span > 1e-9
            f1Str$ = fixed$(f1, 4)
            f2Str$ = fixed$(f2, 4)
            m1Str$ = fixed$(m1, 4)
            m2Str$ = fixed$(m2, 4)
            t1Str$ = fixed$(t1, 6)
            spanStr$ = fixed$(span, 6)
            phaseStr$ = fixed$(accum_phase, 6)

            selectObject: ring_carrier
            Formula (part): t1, t2, 1, 1,
                ... "(1 - (" + m1Str$ + " + (" + m2Str$ + " - " + m1Str$
                ... + ") * (x - " + t1Str$ + ") / " + spanStr$ + "))"
                ... + " + (" + m1Str$ + " + (" + m2Str$ + " - " + m1Str$
                ... + ") * (x - " + t1Str$ + ") / " + spanStr$ + ")"
                ... + " * cos(" + phaseStr$
                ... + " + 2 * pi * (" + f1Str$
                ... + " * (x - " + t1Str$
                ... + ") + 0.5 * (" + f2Str$ + " - " + f1Str$
                ... + ") * (x - " + t1Str$ + ")^2 / " + spanStr$ + "))"

            accum_phase = accum_phase + 2 * pi * 0.5 * (f1 + f2) * span
            # v2.1: wrap to keep the formula-string phase small
            accum_phase = accum_phase mod (2 * pi)
        endif
    endfor

    ringId$ = fixed$(ring_carrier, 0)
    selectObject: work_amp
    Formula: "self * object[" + ringId$ + ", col]"
    removeObject: ring_carrier
endif

#=============================================================================
# HF BOOST
#=============================================================================

if hF_boost_dB > 0
    appendInfoLine: "Applying HF boost..."
    selectObject: work_amp
    highBand = Filter (pass Hann band): 2000, sr / 2, 100
    hbGainDelta = 10 ^ (hF_boost_dB / 20) - 1
    hbGainStr$ = fixed$(hbGainDelta, 6)
    hbIdStr$ = fixed$(highBand, 0)
    selectObject: work_amp
    Formula: "self + " + hbGainStr$
        ... + " * object[" + hbIdStr$ + ", col]"
    removeObject: highBand
endif

#=============================================================================
# DRY/WET MIX
#=============================================================================

appendInfoLine: "Mixing dry/wet..."

selectObject: work_amp
wet_dur = Get total duration

selectObject: input_sound
dry = Copy: "dry"
selectObject: dry
dry_dur = Get total duration

if wet_dur < dry_dur
    selectObject: dry
    dry_trimmed = Extract part: 0, wet_dur, "rectangular", 1.0, "no"
    removeObject: dry
    dry = dry_trimmed
elsif dry_dur < wet_dur
    selectObject: work_amp
    wet_trimmed = Extract part: 0, dry_dur, "rectangular", 1.0, "no"
    removeObject: work_amp
    work_amp = wet_trimmed
endif

dryWetStr$ = fixed$(dry_wet, 6)
dryAmtStr$ = fixed$(1 - dry_wet, 6)
wetIdStr$ = fixed$(work_amp, 0)

selectObject: dry
Formula: "self * " + dryAmtStr$ + " + "
    ... + dryWetStr$ + " * object[" + wetIdStr$ + ", col]"

output_sound = dry
selectObject: output_sound
Rename: input_name$ + "_chaotic_" + presetName$
removeObject: work_amp

#=============================================================================
# FINALIZE
#=============================================================================

selectObject: output_sound
Scale peak: 0.99

#=============================================================================
# VISUALIZATION
#=============================================================================

if draw_visualization
    appendInfoLine: "Creating visualization..."
    Erase all
    Select outer viewport: 0, 8, 0, 8

    # Title
    Select outer viewport: 0, 8, 0, 0.45
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", -1.7, "half",
        ... "##Chaotic Neural Map Modulator v2.1##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.20, "half",
        ... input_name$ + " | " + presetName$
        ... + " | Instab " + fixed$(instability, 1)
        ... + " | ModRate " + fixed$(modulation_rate_Hz, 2) + " Hz"
        ... + " | " + scaleName$

    # Input waveform
    Select outer viewport: 0, 8, 0.50, 1.40
    Select inner viewport: 0.6, 7.7, 0.55, 1.35
    selectObject: input_sound_original
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"

    # Output waveform
    Select outer viewport: 0, 8, 1.45, 2.35
    Select inner viewport: 0.6, 7.7, 1.50, 2.30
    selectObject: output_sound
    Colour: "{0.30, 0.55, 0.70}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"

    # F0 contour with voiced/unvoiced shading
    Select outer viewport: 0, 8, 2.40, 3.55
    Select inner viewport: 0.6, 7.7, 2.50, 3.50

    f0Lo = 1200
    f0Hi = 50
    for i to num_frames
        if voiced_chaos#[i] = 1
            if f0_chaos#[i] < f0Lo
                f0Lo = f0_chaos#[i]
            endif
            if f0_chaos#[i] > f0Hi
                f0Hi = f0_chaos#[i]
            endif
        endif
    endfor
    if f0Hi <= f0Lo
        f0Lo = 100
        f0Hi = 400
    endif
    f0Lo = f0Lo * 0.8
    f0Hi = f0Hi * 1.2

    Axes: 0, duration, f0Lo, f0Hi
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, duration, f0Lo, f0Hi

    # Shade unvoiced regions
    for i from 2 to num_frames
        if voiced_chaos#[i] = 0
            Paint rectangle: "{0.93, 0.88, 0.88}",
                ... time#[i - 1], time#[i], f0Lo, f0Hi
        endif
    endfor

    # Input F0 contour (grey)
    Colour: "{0.55, 0.55, 0.55}"
    Line width: 1.2
    prevVoiced = 0
    for i to num_frames
        if voiced_chaos#[i] = 1
            if prevVoiced = 1 and i > 1
                Draw line: time#[i - 1], f0_chaos#[i - 1],
                    ... time#[i], f0_chaos#[i]
            endif
            prevVoiced = 1
        else
            prevVoiced = 0
        endif
    endfor

    # Output F0 contour (blue)
    Colour: "{0.25, 0.45, 0.75}"
    Line width: 1.5
    prevCtrlVoiced = 0
    prevF0Out = 0
    prevT = 0
    for ci to num_ctrl
        if voicedAtCtrl#[ci] = 1
            f0out = f0AtCtrl#[ci] * 2 ^ ((pitchShiftCents#[ci] / 100) / 12)
            if prevCtrlVoiced = 1
                Draw line: prevT, prevF0Out, tCtrl#[ci], f0out
            endif
            prevT = tCtrl#[ci]
            prevF0Out = f0out
            prevCtrlVoiced = 1
        else
            prevCtrlVoiced = 0
        endif
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "F0 (Hz)"
    Text top: "no", "F0 contour: grey=input, blue=output, pink=unvoiced"

    # Ring-mod frequency trajectory
    Select outer viewport: 0, 4, 3.60, 4.70
    Select inner viewport: 0.6, 3.85, 3.70, 4.60

    rfLo = 1e9
    rfHi = 0
    for ci to num_ctrl
        if ringFreq#[ci] < rfLo
            rfLo = ringFreq#[ci]
        endif
        if ringFreq#[ci] > rfHi
            rfHi = ringFreq#[ci]
        endif
    endfor
    if rfHi <= rfLo
        rfLo = 100
        rfHi = 600
    endif
    rfLo = rfLo * 0.9
    rfHi = rfHi * 1.1

    Axes: 0, duration, rfLo, rfHi
    Paint rectangle: "{0.97, 0.98, 0.97}", 0, duration, rfLo, rfHi

    for ci from 2 to num_ctrl
        if voicedAtCtrl#[ci] = 0
            Paint rectangle: "{0.93, 0.88, 0.88}",
                ... tCtrl#[ci - 1], tCtrl#[ci], rfLo, rfHi
        endif
    endfor

    Colour: "{0.35, 0.60, 0.40}"
    Line width: 1.2
    for ci from 2 to num_ctrl
        Draw line: tCtrl#[ci - 1], ringFreq#[ci - 1],
            ... tCtrl#[ci], ringFreq#[ci]
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text top: "no", "Ring-mod frequency"

    # Pitch-shift trajectory
    Select outer viewport: 4, 8, 3.60, 4.70
    Select inner viewport: 4.2, 7.7, 3.70, 4.60

    Axes: 0, duration, -pitch_range_semitones * 1.2, pitch_range_semitones * 1.2
    Paint rectangle: "{0.97, 0.97, 0.98}",
        ... 0, duration, -pitch_range_semitones * 1.2,
        ... pitch_range_semitones * 1.2

    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, duration, 0

    for ci from 2 to num_ctrl
        if voicedAtCtrl#[ci] = 0
            Paint rectangle: "{0.93, 0.88, 0.88}",
                ... tCtrl#[ci - 1], tCtrl#[ci],
                ... -pitch_range_semitones * 1.2, pitch_range_semitones * 1.2
        endif
    endfor

    Colour: "{0.30, 0.45, 0.75}"
    Line width: 1.2
    prevSt = 0
    for ci from 2 to num_ctrl
        st = pitchShiftCents#[ci] / 100
        Draw line: tCtrl#[ci - 1], prevSt, tCtrl#[ci], st
        prevSt = st
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Semitones"
    Text top: "no", "Pitch shift (scale-quantized)"

    # Output spectrogram
    Select outer viewport: 0, 8, 4.75, 6.20
    Select inner viewport: 0.6, 7.7, 4.85, 6.15
    selectObject: output_sound
    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    specOut = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Output spectrogram"
    removeObject: specOut

    # Training loss
    Select outer viewport: 0, 8, 6.25, 7.10
    Select inner viewport: 0.6, 7.7, 6.35, 7.00

    lossMin = trainLoss#[1]
    lossMax = trainLoss#[1]
    for li from 2 to training_iterations
        if trainLoss#[li] < lossMin
            lossMin = trainLoss#[li]
        endif
        if trainLoss#[li] > lossMax
            lossMax = trainLoss#[li]
        endif
    endfor
    lossRange = lossMax - lossMin
    if lossRange < 1e-6
        lossRange = 1e-6
    endif
    lossYlo = lossMin - lossRange * 0.05
    lossYhi = lossMax + lossRange * 0.05

    Axes: 0, training_iterations + 1, lossYlo, lossYhi
    Paint rectangle: "{0.97, 0.97, 0.99}",
        ... 0, training_iterations + 1, lossYlo, lossYhi
    Colour: "{0.20, 0.40, 0.70}"
    Line width: 1.5
    for li from 2 to training_iterations
        Draw line: li - 1, trainLoss#[li - 1], li, trainLoss#[li]
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "MSE"
    Text top: "no", "Training loss"

    # Summary strip
    Select outer viewport: 0, 8, 7.20, 7.70
    Select inner viewport: 0.6, 7.7, 7.25, 7.65
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.02, "left", 0.78, "half",
        ... "##Pitch##  range=±" + fixed$(pitch_range_semitones, 1) + "st"
        ... + "  scale=" + scaleName$
        ... + "  voiced=" + string$(nVoiced) + "/" + string$(num_frames) + " frames"
        ... + "  F0 median=" + fixed$(median_f0, 1) + " Hz"
    Text: 0.02, "left", 0.48, "half",
        ... "##Amp##  depth=" + fixed$(amplitude_mod_depth, 2)
        ... + "   ##Ring##  depth=" + fixed$(ring_mod_depth, 2)
        ... + "  (F0-locked on voiced)"
        ... + "   ##Transients##  " + string$(nTransients) + " flagged"
    Text: 0.02, "left", 0.18, "half",
        ... "##Chaos##  iter=60ms apply=10ms"
        ... + "  autonomy=" + fixed$(autonomy, 2)
        ... + "  volatility=" + fixed$(chaos_volatility, 2)
        ... + "  mutation=" + fixed$(chaos_mutation, 2)
        ... + "  kick=" + fixed$(kick_interval_ms, 0) + "ms"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

#=============================================================================
# CLEANUP
#=============================================================================

removeObject: input_sound

selectObject: output_sound
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", selected$("Sound")

if play_output
    appendInfoLine: "Playing..."
    selectObject: output_sound
    Play
endif

selectObject: output_sound
