# ============================================================
# Praat AudioTools - Microtonal_Harmonic_Field_Engine.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Microtonal Harmonic Field Engine — analysis-driven microtonal
#   harmonization for existing audio. Detects stable (S), unstable (U),
#   and noisy (N) zones from pitch, harmonicity, and intensity analysis.
#   Derives local harmonic anchors phrase by phrase from the source
#   itself, then generates companion voices via phrase-granular
#   resampling (playback-rate pitch shifting). Each phrase segment is
#   extracted, pitch-shifted by the target interval ratio via SR
#   override and resample, faded, and placed into a timeline buffer.
#   This preserves spectral character across all zone types including
#   noise, breath, and unstable frames. Commas and wolf intervals are
#   tracked and used as compositional events — not corrected.
#   Harmony is source-derived, not score-imposed.
#
#
# Usage:
#   Select exactly one Sound object and run this script.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# ============================================================
# INPUT CHECK
# ============================================================
if numberOfSelected ("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original_id  = selected ("Sound")
src_name$    = selected$ ("Sound")

selectObject: original_id
total_dur  = Get total duration
src_sr     = Get sampling frequency
n_channels = Get number of channels

# ============================================================
# FORM
# Presets: 1=Just Bloom  2=Septimal Shadow  3=Wolf Corridor
#          4=Harmonic Gravity  5=Temperament Collapse
#          6=Dual Root Conflict  7=Comma Drift  8=Custom
# Field systems: 1=12-TET  2=Just  3=Pythagorean  4=19-TET
#                5=31-TET  6=Harmonic Series  7=Septimal  8=User
# Placement: 1=Align-start  2=Align-centre  3=Stretch-to-fit
# ============================================================
form Microtonal_Harmonic_Field_Engine v0.2
    comment === ENGINE PRESET ===
    optionmenu Preset_mode 1
        option Just Bloom
        option Septimal Shadow
        option Wolf Corridor
        option Harmonic Gravity
        option Temperament Collapse
        option Dual Root Conflict
        option Comma Drift
        option Custom

    comment === TUNING (used when Preset is Custom) ===
    optionmenu Field_A 2
        option 12-TET
        option Just Intonation
        option Pythagorean
        option 19-TET
        option 31-TET
        option Harmonic Series
        option Septimal 7-limit
        option User-Defined
    optionmenu Field_B 3
        option 12-TET
        option Just Intonation
        option Pythagorean
        option 19-TET
        option 31-TET
        option Harmonic Series
        option Septimal 7-limit
        option User-Defined

    comment === VOICES AND LEVELS ===
    integer N_voices 2
    real Companion_level 0.55
    real Original_level 0.80

    comment === BEHAVIOR (used when Preset is Custom) ===
    optionmenu Primary_behavior 2
        option Snap
        option Lean
        option Drift
        option Oscillate
        option Smear
        option Refuse

    comment === PLACEMENT ===
    optionmenu Placement_mode 1
        option Align start
        option Align centre
        option Stretch to fit

    comment === TIME CORRECTION (PSOLA sync to source phrase duration) ===
    optionmenu Time_correction 1
        option None
        option Snap to phrase
        option Elastic (PSOLA)

    comment === STEREO SPREAD (0=mono  1=full L-R) ===
    real Stereo_spread 0.8

    comment === OUTPUT ===
    real Output_peak 0.92
    boolean Visualize 1
    boolean Play_result 1
endform

# ---- Advanced parameters (fixed defaults; edit script to change) ----
pitch_floor_Hz          = 60.0
pitch_ceiling_Hz        = 800.0
analysis_step_sec       = 0.01
voicing_threshold       = 0.45
stability_threshold     = 0.60
silence_floor_dB        = 40.0
memory_weight           = 0.35
anchor_inertia_cents    = 60.0
lean_strength           = 0.70
drift_tau_sec           = 0.80
oscillate_rate_Hz       = 3.5
oscillate_depth_cents   = 10.0
smear_window_sec        = 0.12
unstable_smear          = 0.65
comma_accumulation_rate = 1.0
wolf_emphasis           = 1.4
comma_climax_threshold  = 38.0
comma_resolution        = 2
user_ratios_cents$      = "0, 150, 350, 702, 968"
fade_time_sec           = 0.015
max_speed_factor        = 3.0
min_speed_factor        = 0.25
layer_gain              = 1.0
entry_offset_sec        = 0.0

# Map form variables to internal names
engine_preset      = preset_mode
resample_placement = placement_mode

# ============================================================
# APPLY FORM PRESETS
# ============================================================
act_field_A   = field_A
act_field_B   = field_B
act_n_voices  = min (max (n_voices, 1), 5)
act_behavior  = primary_behavior
act_lean      = lean_strength
act_drift_tau = drift_tau_sec
act_osc_rate  = oscillate_rate_Hz
act_osc_depth = oscillate_depth_cents
act_comp_lvl  = companion_level

if engine_preset = 1
    act_field_A  = 2
    act_field_B  = 6
    act_n_voices = min (act_n_voices, 4)
    act_behavior = 2
    act_lean     = 0.78
elsif engine_preset = 2
    act_field_A  = 7
    act_field_B  = 1
    act_n_voices = 2
    act_behavior = 2
    act_lean     = 0.65
elsif engine_preset = 3
    act_field_A  = 3
    act_field_B  = 3
    act_n_voices = min (act_n_voices, 3)
    act_behavior = 3
    act_drift_tau = 1.2
elsif engine_preset = 4
    act_field_A  = 6
    act_field_B  = 6
    act_n_voices = min (act_n_voices, 4)
    act_behavior = 2
    act_lean     = 0.82
elsif engine_preset = 5
    act_field_A  = 5
    act_field_B  = 1
    act_n_voices = 2
    act_behavior = 2
elsif engine_preset = 6
    act_field_A  = 2
    act_field_B  = 3
    act_n_voices = min (act_n_voices, 2)
    act_behavior = 4
    act_osc_rate  = 2.5
    act_osc_depth = 15.0
elsif engine_preset = 7
    act_field_A  = 2
    act_field_B  = 2
    act_n_voices = min (act_n_voices, 3)
    act_behavior = 3
    act_drift_tau = 1.5
endif

# ============================================================
# PARSE USER-DEFINED RATIOS
# ============================================================
user_n_int = 0
user_int# = zero# (5)

temp_parse$ = user_ratios_cents$
for ci from 1 to 5
    comma_pos = index (temp_parse$, ",")
    if comma_pos > 0
        val_str$ = left$ (temp_parse$, comma_pos - 1)
        user_n_int += 1
        user_int# [user_n_int] = number (val_str$)
        temp_parse$ = right$ (temp_parse$, length (temp_parse$) - comma_pos)
    endif
endfor
if length (temp_parse$) > 0 and user_n_int < 5
    user_n_int += 1
    user_int# [user_n_int] = number (temp_parse$)
endif
if user_n_int = 0
    user_n_int = 5
    user_int# [1] = 0
    user_int# [2] = 150
    user_int# [3] = 350
    user_int# [4] = 702
    user_int# [5] = 968
endif

# ============================================================
# PREPARE SOURCE
# ============================================================
selectObject: original_id
if n_channels > 1
    src_work = Convert to mono
else
    src_work = Copy: "MHFE_src_work"
endif

selectObject: src_work
source_dur = Get total duration
source_sr  = Get sampling frequency

# ============================================================
# INFO HEADER
# ============================================================
clearinfo
writeInfoLine: "=== Microtonal Harmonic Field Engine v0.2 ==="
appendInfoLine: "Source: ", src_name$, "  (", fixed$ (source_dur, 3), " s)"
appendInfoLine: "Sample rate: ", source_sr, " Hz"

@fieldName: act_field_A
appendInfoLine: "Field A: ", fieldName.result$
@fieldName: act_field_B
appendInfoLine: "Field B: ", fieldName.result$
appendInfoLine: "Voices: ", act_n_voices
if resample_placement = 1
    appendInfoLine: "Placement: Align-start"
elsif resample_placement = 2
    appendInfoLine: "Placement: Align-centre"
else
    appendInfoLine: "Placement: Stretch-to-fit"
endif
appendInfoLine: ""

# ============================================================
# ANALYSIS PIPELINE
# ============================================================
appendInfoLine: "--- Running analysis ---"

selectObject: src_work
To Pitch: analysis_step_sec, pitch_floor_Hz, pitch_ceiling_Hz
pitch_id = selected ("Pitch")

selectObject: src_work
To Harmonicity (cc): analysis_step_sec, pitch_floor_Hz, 0.1, 1.0
harm_id = selected ("Harmonicity")

selectObject: src_work
To Intensity: pitch_floor_Hz, analysis_step_sec, "yes"
intens_id = selected ("Intensity")

selectObject: pitch_id
n_frames = Get number of frames
appendInfoLine: "Analysis frames: ", n_frames

# ============================================================
# FRAME-LEVEL LOOP: voicing weights and zone labels
# Zones: 1 = Stable (S)  |  2 = Unstable (U)  |  3 = Noisy/Unvoiced (N)
# ============================================================
f0_hz#     = zero# (n_frames)
voicing_w# = zero# (n_frames)
zone#      = zero# (n_frames)

n_voiced = 0
n_stable = 0

for t from 1 to n_frames
    t_sec = (t - 0.5) * analysis_step_sec

    selectObject: pitch_id
    f0_val = Get value in frame: t, "Hertz"

    selectObject: harm_id
    hnr_val = Get value in frame: t
    if hnr_val = undefined
        hnr_val = 0
    endif

    selectObject: intens_id
    int_val = Get value at time: t_sec, "Cubic"
    if int_val = undefined
        int_val = 0
    endif

    if f0_val = undefined or f0_val <= 0
        f0_hz#     [t] = 0
        voicing_w# [t] = 0
        zone#      [t] = 3
    else
        f0_hz# [t] = f0_val
        n_voiced += 1

        hnr_norm  = min (max (hnr_val / 30.0, 0), 1.0)
        pitch_str = min (max ((hnr_val - 5.0) / 25.0, 0), 1.0)
        voicing_w# [t] = 0.5 * pitch_str + 0.5 * hnr_norm

        if voicing_w# [t] >= stability_threshold and int_val >= silence_floor_dB
            zone# [t] = 1
            n_stable += 1
        elsif int_val >= silence_floor_dB
            zone# [t] = 2
        else
            zone# [t] = 3
            f0_hz#     [t] = 0
            voicing_w# [t] = 0
        endif
    endif
endfor

appendInfoLine: "Voiced frames:  ", n_voiced, " / ", n_frames
appendInfoLine: "Stable (Zone S): ", n_stable, " frames"

# ============================================================
# ZONE MERGING
# ============================================================
for t from 2 to n_frames - 1
    if zone# [t] <> zone# [t-1] and zone# [t] <> zone# [t+1]
        zone# [t] = zone# [t-1]
    endif
endfor

# ============================================================
# PHRASE DETECTION
# ============================================================
phrase_break_fr = round (0.18 / analysis_step_sec)
max_phrases = 200

for ph from 1 to max_phrases
    phrase_start [ph] = 0
    phrase_end   [ph] = 0
    anchor_cents [ph] = 0
    anchor_hz_p  [ph] = 0
    field_mix_p  [ph] = 0
    phrase_comma [ph] = 0
endfor

n_phrases    = 0
in_phrase    = 0
silent_count = 0

for t from 1 to n_frames
    if zone# [t] = 3
        silent_count += 1
        if in_phrase = 1 and silent_count >= phrase_break_fr
            if n_phrases > 0
                phrase_end [n_phrases] = t - silent_count
            endif
            in_phrase = 0
        endif
    else
        if in_phrase = 0
            n_phrases += 1
            if n_phrases <= max_phrases
                phrase_start [n_phrases] = t
                in_phrase = 1
            endif
        endif
        silent_count = 0
    endif
endfor

if in_phrase = 1 and n_phrases > 0
    phrase_end [n_phrases] = n_frames
endif

appendInfoLine: "Phrases detected: ", n_phrases

# ============================================================
# FRAME-TO-PHRASE MAP
# ============================================================
frame_phrase# = zero# (n_frames)
for ph from 1 to n_phrases
    p_s = phrase_start [ph]
    p_e = phrase_end   [ph]
    if p_e < p_s
        p_e = p_s
    endif
    for t from p_s to p_e
        if t >= 1 and t <= n_frames
            frame_phrase# [t] = ph
        endif
    endfor
endfor

# ============================================================
# ANCHOR DETECTION AND COMMA TRACKING
# ============================================================
comma_total  = 0
prev_a_cents = 0
wolf_events  = 0

for ph from 1 to n_phrases
    ps = phrase_start [ph]
    pe = phrase_end   [ph]
    if pe <= ps
        pe = ps + 1
    endif
    if pe > n_frames
        pe = n_frames
    endif

    @computeAnchor: ps, pe, prev_a_cents
    anchor_cents [ph] = computeAnchor.result_cents
    anchor_hz_p  [ph] = 440.0 * 2 ^ ((anchor_cents [ph] - 6900) / 1200)

    # Comma delta: octave-reduce step, compare to nearest fifth or fourth.
    # Steps not within 120 cents of either reference are skipped.
    if ph > 1 and prev_a_cents > 0
        step_raw = anchor_cents [ph] - prev_a_cents
        step_oct = step_raw - 1200 * round (step_raw / 1200)
        ref5a =  701.96 - 1200
        ref5b =  701.96
        ref4a = -498.04
        ref4b =  498.04
        d5 = min (abs (step_oct - ref5a), abs (step_oct - ref5b))
        d4 = min (abs (step_oct - ref4a), abs (step_oct - ref4b))
        comma_tolerance = 120
        if d5 <= d4 and d5 <= comma_tolerance
            if step_oct >= 0
                ref_step = ref5b
            else
                ref_step = ref5a
            endif
            comma_total += (step_oct - ref_step) * comma_accumulation_rate
        elsif d4 < d5 and d4 <= comma_tolerance
            if step_oct >= 0
                ref_step = ref4b
            else
                ref_step = ref4a
            endif
            comma_total += (step_oct - ref_step) * comma_accumulation_rate
        endif
    endif

    phrase_comma [ph] = comma_total

    if abs (comma_total) >= comma_climax_threshold
        wolf_events += 1
    endif

    @computeFieldMix: ph, n_phrases, comma_total
    field_mix_p [ph] = computeFieldMix.result

    prev_a_cents = anchor_cents [ph]
endfor

appendInfoLine: "Peak comma:  ", fixed$ (comma_total, 1), " cents"
appendInfoLine: "Wolf events: ", wolf_events

wolf_voice = 1
if act_n_voices >= 2
    wolf_voice = 2
endif

# ============================================================
# RESAMPLING-BASED VOICE GENERATION
# Per phrase: compute effective interval ratio, resample source
# segment to shift pitch via SR override, apply fades, place
# into a full-length silence buffer at the computed position.
# ============================================================
appendInfoLine: ""
appendInfoLine: "--- Generating companion voices (resampling) ---"

for v from 1 to act_n_voices
    appendInfoLine: "Voice ", v, "..."

    # Create a full-length silence buffer for this voice
    Create Sound from formula: "MHFE_buf", 1, 0, source_dur, source_sr, ~ 0
    buf_id = selected ("Sound")

    for ph from 1 to n_phrases
        ps = phrase_start [ph]
        pe = phrase_end   [ph]
        if pe < ps
            pe = ps
        endif

        t_start = max ((ps - 1) * analysis_step_sec, 0)
        t_end   = min (pe * analysis_step_sec, source_dur)
        if t_end - t_start < 0.005
            t_end = t_start + 0.005
        endif
        if t_end > source_dur
            t_end = source_dur
        endif

        # Compute effective interval for this voice and phrase
        @getInterval: act_field_A, v
        int_A = getInterval.result
        @getInterval: act_field_B, v
        int_B = getInterval.result

        fmix    = field_mix_p [ph]
        eff_int = (1 - fmix) * int_A + fmix * int_B

        # Wolf offset: nudge wolf voice when comma exceeds threshold
        if v = wolf_voice and abs (phrase_comma [ph]) >= comma_climax_threshold
            woff    = (phrase_comma [ph] / comma_climax_threshold) * 5.0
            eff_int = eff_int + woff
        endif

        # Compute per-phrase companion Hz via applyBehavior,
        # then derive the playback speed factor from the ratio
        anc_hz = anchor_hz_p [ph]
        if anc_hz <= 0
            anc_hz = 440
        endif
        tgt_hz_raw = anc_hz * 2 ^ (eff_int / 1200)

        @applyBehavior: anc_hz, tgt_hz_raw, act_behavior,
        ...    act_lean, 0, (t_end - t_start), 0
        final_hz = applyBehavior.out_hz

        if final_hz > 0 and anc_hz > 0
            speed_factor = final_hz / anc_hz
        else
            speed_factor = 2 ^ (eff_int / 1200)
        endif
        speed_factor = max (min (speed_factor, max_speed_factor), min_speed_factor)

        # Extract source material scaled by speed_factor so that after
        # resampling the result is exactly phrase_dur long.
        # (Messagesquisse idiom: reqDur = activeDur * pitchFactor)
        phrase_dur  = t_end - t_start
        req_dur     = phrase_dur * speed_factor
        src_extract_end = t_start + req_dur
        if src_extract_end > source_dur
            src_extract_end = source_dur
        endif
        if src_extract_end <= t_start
            src_extract_end = t_start + 0.01
        endif

        selectObject: src_work
        Extract part: t_start, src_extract_end, "rectangular", 1, "no"
        seg_orig = selected ("Sound")

        # If source ran short, pad with silence to reach req_dur
        selectObject: seg_orig
        seg_orig_dur = Get total duration
        if req_dur - seg_orig_dur > 0.001
            pad_req = req_dur - seg_orig_dur
            Create Sound from formula: "MHFE_req_pad", 1, 0, pad_req, source_sr, ~ 0
            req_pad = selected ("Sound")
            selectObject: seg_orig
            plusObject: req_pad
            Concatenate
            seg_orig_padded = selected ("Sound")
            removeObject: seg_orig
            removeObject: req_pad
            seg_orig = seg_orig_padded
        endif

        # Pitch-shift: Override SR then resample back.
        # After this, seg_pitched duration = req_dur / speed_factor = phrase_dur.
        new_sr_shift = round (source_sr * speed_factor)
        if new_sr_shift < 100
            new_sr_shift = 100
        endif
        if new_sr_shift > 655350
            new_sr_shift = 655350
        endif

        Override sampling frequency: new_sr_shift
        Resample: source_sr, 50
        seg_pitched = selected ("Sound")
        removeObject: seg_orig

        # Stretch-to-fit (placement mode 3): SR-based duration correction
        if resample_placement = 3
            selectObject: seg_pitched
            orig_phrase_dur = t_end - t_start
            seg_pitched_dur = Get total duration
            if seg_pitched_dur > 0.001 and orig_phrase_dur > 0.001
                stretch_sr = round (source_sr * seg_pitched_dur / orig_phrase_dur)
                if stretch_sr < 100
                    stretch_sr = 100
                endif
                if stretch_sr > 655350
                    stretch_sr = 655350
                endif
                Override sampling frequency: stretch_sr
                Resample: source_sr, 50
                seg_stretched = selected ("Sound")
                removeObject: seg_pitched
                seg_pitched = seg_stretched
            endif
        endif

        # Time correction: snap or elastically stretch seg_pitched to phrase_dur
        # Uses the Time_Manipulation PSOLA idiom for pitch-preserving duration fix.
        if time_correction > 1
            selectObject: seg_pitched
            tc_actual_dur = Get total duration
            tc_target_dur = phrase_dur
            if tc_actual_dur > 0.001 and tc_target_dur > 0.001
                tc_factor = tc_target_dur / tc_actual_dur
                if time_correction = 2
                    # Snap: only correct if drift exceeds 20 ms
                    if abs (tc_actual_dur - tc_target_dur) < 0.020
                        tc_factor = 1.0
                    endif
                endif
                if tc_factor <> 1.0
                    selectObject: seg_pitched
                    tc_manip = To Manipulation: 0.01, pitch_floor_Hz, pitch_ceiling_Hz
                    tc_dtier = Create DurationTier: "MHFE_tc_dur", 0, tc_actual_dur
                    Add point: 0, tc_factor
                    Add point: tc_actual_dur, tc_factor
                    selectObject: tc_manip
                    plusObject: tc_dtier
                    Replace duration tier
                    selectObject: tc_manip
                    tc_resynth = Get resynthesis (overlap-add)
                    removeObject: tc_manip, tc_dtier, seg_pitched
                    seg_pitched = tc_resynth
                endif
            endif
        endif

        # Apply fade using inline-if Formula -- xmin-agnostic (TSM idiom)
        selectObject: seg_pitched
        seg_dur_fade = Get total duration
        fade_dur_actual = min (fade_time_sec, seg_dur_fade / 4)
        if fade_dur_actual > 0.001
            fadExpr$ = "self * (if x-xmin < " + fixed$(fade_dur_actual,8) +
            ...    " then 0.5-0.5*cos(pi*(x-xmin)/" + fixed$(fade_dur_actual,8) +
            ...    ") else (if xmax-x < " + fixed$(fade_dur_actual,8) +
            ...    " then 0.5-0.5*cos(pi*(xmax-x)/" + fixed$(fade_dur_actual,8) +
            ...    ") else 1 fi) fi)"
            Formula: fadExpr$
        endif

        # Compute placement start time
        if resample_placement = 2
            selectObject: seg_pitched
            seg_dur_now   = Get total duration
            phrase_centre = (t_start + t_end) / 2
            place_t = phrase_centre - seg_dur_now / 2 + (v - 1) * entry_offset_sec
        else
            place_t = t_start + (v - 1) * entry_offset_sec
        endif
        if place_t < 0
            place_t = 0
        endif
        # Build full-length layer: silence-prefix + pitched seg + silence-suffix
        # then accumulate into buffer via object[id] formula, time-aligned.
        # This is the correct Praat idiom — no sample index arithmetic needed.
        if place_t > 0.001
            # Create sil_pre FIRST so its object ID is lower than seg_pitched.
            # Praat Concatenate orders by object ID (list position), not
            # selection order -- sil_pre must have the lower ID to go first.
            Create Sound from formula: "MHFE_sil_pre", 1,
            ...    0, place_t, source_sr, ~ 0
            sil_pre = selected ("Sound")
            # Re-copy seg_pitched so its ID is higher than sil_pre
            selectObject: seg_pitched
            seg_copy = Copy: "MHFE_seg_copy"
            removeObject: seg_pitched
            seg_pitched = seg_copy
            # Now sil_pre ID < seg_pitched ID -> Concatenate = [silence][audio]
            selectObject: sil_pre
            plusObject: seg_pitched
            Concatenate
            with_pre = selected ("Sound")
            removeObject: sil_pre
            removeObject: seg_pitched
        else
            with_pre = seg_pitched
        endif

        selectObject: with_pre
        layer_dur = Get total duration
        pad_needed = source_dur - layer_dur

        if pad_needed > 0.001
            Create Sound from formula: "MHFE_sil_post", 1,
            ...    0, pad_needed, source_sr, ~ 0
            sil_post = selected ("Sound")
            selectObject: with_pre
            plusObject: sil_post
            Concatenate
            full_layer = selected ("Sound")
            removeObject: sil_post
            removeObject: with_pre
        elsif pad_needed < -0.001
            selectObject: with_pre
            Extract part: 0, source_dur, "rectangular", 1, "no"
            full_layer = selected ("Sound")
            removeObject: with_pre
        else
            full_layer = with_pre
        endif

        layer_g = layer_gain * act_comp_lvl
        if v = wolf_voice and wolf_events > 0
            layer_g = layer_g * wolf_emphasis
        endif

        selectObject: buf_id
        Formula: ~ self + object[full_layer] * layer_g

        removeObject: full_layer
    endfor

    selectObject: buf_id
    Rename: "MHFE_comp_" + string$ (v)
    comp_ids [v] = buf_id
endfor

appendInfoLine: "Companion voices generated: ", act_n_voices

# ============================================================
# MIXING — stereo spread
# Original: centre (constant-power: L = R = 0.707)
# Companion voices: evenly distributed from -spread to +spread
# Pan law: angle = (pan+1)/4 * pi  ->  L = cos(angle), R = sin(angle)
# ============================================================
appendInfoLine: ""
appendInfoLine: "--- Mixing (stereo spread) ---"

Create Sound from formula: "MHFE_accumL", 1, 0, source_dur, source_sr, ~ 0
accumL_id = selected ("Sound")
Create Sound from formula: "MHFE_accumR", 1, 0, source_dur, source_sr, ~ 0
accumR_id = selected ("Sound")

dry_gain = original_level * 0.707

selectObject: accumL_id
Formula: ~ self + object[src_work] * dry_gain
selectObject: accumR_id
Formula: ~ self + object[src_work] * dry_gain

for v from 1 to act_n_voices
    if act_n_voices = 1
        pan_pos = 0
    else
        pan_pos = -stereo_spread + (v - 1) * (2 * stereo_spread / (act_n_voices - 1))
    endif
    pan_angle = (pan_pos + 1) / 4 * pi
    pan_gain_L = cos (pan_angle)
    pan_gain_R = sin (pan_angle)

    appendInfoLine: "  Voice ", v, "  pan=", fixed$(pan_pos,2),
    ...    "  L=", fixed$(pan_gain_L,3), "  R=", fixed$(pan_gain_R,3)

    selectObject: accumL_id
    Formula: ~ self + object[comp_ids[v]] * pan_gain_L
    selectObject: accumR_id
    Formula: ~ self + object[comp_ids[v]] * pan_gain_R
endfor

selectObject: accumL_id
plusObject: accumR_id
Combine to stereo
result_id = selected ("Sound")
removeObject: accumL_id, accumR_id

for v from 1 to act_n_voices
    removeObject: comp_ids [v]
endfor

selectObject: result_id
Scale peak: output_peak
Rename: src_name$ + "_MHFE_result"

appendInfoLine: "Output: ", selected$ ("Sound")

# ============================================================
# VISUALIZATION
# Three panels: Zone Map | Pitch Curves | Comma Graph
# ============================================================
draw_zone_map     = visualize
draw_pitch_curves = visualize
draw_comma_graph  = visualize

if visualize
    appendInfoLine: ""
    appendInfoLine: "--- Drawing visualization ---"
    Erase all

    Select outer viewport: 0, 8, 0.0, 0.42
    Black
    Font size: 11
    Text: 0.5, "centre", 0.5, "half",
    ...    "Microtonal Harmonic Field Engine: " + src_name$

    vp_top = 0.45

    if draw_zone_map
        vp_bot = vp_top + 0.85
        Select outer viewport: 0, 8, vp_top, vp_bot
        Select inner viewport: 0.6, 7.8, vp_top + 0.08, vp_bot - 0.05
        Axes: 0, source_dur, 0, 1

        for t from 1 to n_frames
            t_lo = (t - 1) * analysis_step_sec
            t_hi = t * analysis_step_sec
            zz   = zone# [t]
            if zz = 1
                Paint rectangle: "{0.18, 0.58, 0.22}", t_lo, t_hi, 0, 1
            elsif zz = 2
                Paint rectangle: "{0.90, 0.50, 0.08}", t_lo, t_hi, 0, 1
            else
                Paint rectangle: "{0.72, 0.72, 0.72}", t_lo, t_hi, 0, 1
            endif
        endfor

        Black
        Dotted line
        for ph from 1 to n_phrases
            tb = phrase_start [ph] * analysis_step_sec
            Draw line: tb, 0, tb, 1
        endfor
        Solid line
        Draw inner box
        Font size: 7
        Text left: "yes", "S(Grn) U(Org) N(Gry)"
        Text bottom: "yes", "Time (s)"

        vp_top = vp_bot + 0.12
    endif

    if draw_pitch_curves
        vp_bot = vp_top + 2.0
        Select outer viewport: 0, 8, vp_top, vp_bot
        Select inner viewport: 0.6, 7.8, vp_top + 0.10, vp_bot - 0.10

        Axes: 0, source_dur, pitch_floor_Hz, pitch_ceiling_Hz
        Paint rectangle: "{0.96, 0.96, 0.96}",
        ...    0, source_dur, pitch_floor_Hz, pitch_ceiling_Hz

        Colour: "{0.35, 0.35, 0.80}"
        Dotted line
        for ph from 1 to n_phrases
            tlo = phrase_start [ph] * analysis_step_sec
            thi = phrase_end   [ph] * analysis_step_sec
            ah  = anchor_hz_p  [ph]
            if ah > pitch_floor_Hz and ah < pitch_ceiling_Hz
                Draw line: tlo, ah, thi, ah
            endif
        endfor
        Solid line

        Colour: "{0.58, 0.58, 0.58}"
        Line width: 1.8
        prev_t = 0
        prev_f = 0
        for t from 1 to n_frames
            if f0_hz# [t] > 0
                t_m = (t - 0.5) * analysis_step_sec
                if prev_f > 0
                    Draw line: prev_t, prev_f, t_m, f0_hz# [t]
                endif
                prev_t = t_m
                prev_f = f0_hz# [t]
            else
                prev_f = 0
            endif
        endfor

        for v from 1 to act_n_voices
            if v = 1
                Colour: "{0.15, 0.38, 0.80}"
            elsif v = 2
                Colour: "{0.80, 0.18, 0.28}"
            elsif v = 3
                Colour: "{0.08, 0.58, 0.50}"
            elsif v = 4
                Colour: "{0.68, 0.25, 0.72}"
            else
                Colour: "{0.80, 0.58, 0.08}"
            endif
            Line width: 1.2

            # Intervals depend only on (field, voice) — compute once per voice
            @getInterval: act_field_A, v
            viz_iA = getInterval.result
            @getInterval: act_field_B, v
            viz_iB = getInterval.result

            prev_t2 = 0
            prev_f2 = 0
            for t from 1 to n_frames
                ph_t = frame_phrase# [t]
                if ph_t >= 1 and ph_t <= n_phrases and f0_hz# [t] > 0
                    fmx = field_mix_p [ph_t]
                    ei  = (1 - fmx) * viz_iA + fmx * viz_iB
                    tg  = anchor_hz_p [ph_t] * 2 ^ (ei / 1200)
                    t_m = (t - 0.5) * analysis_step_sec
                    if prev_f2 > 0 and tg > pitch_floor_Hz and tg < pitch_ceiling_Hz
                        Draw line: prev_t2, prev_f2, t_m, tg
                    endif
                    if tg > pitch_floor_Hz and tg < pitch_ceiling_Hz
                        prev_t2 = t_m
                        prev_f2 = tg
                    else
                        prev_f2 = 0
                    endif
                else
                    prev_f2 = 0
                endif
            endfor
        endfor

        Line width: 1
        Black
        Draw inner box
        Font size: 8
        Text left: "yes", "F0 (Hz)   Grey=source  Coloured=targets"
        Text bottom: "yes", "Time (s)"

        vp_top = vp_bot + 0.12
    endif

    if draw_comma_graph and n_phrases >= 2
        vp_bot = vp_top + 1.2
        Select outer viewport: 0, 8, vp_top, vp_bot
        Select inner viewport: 0.6, 7.8, vp_top + 0.10, vp_bot - 0.08

        max_c_ax = max (abs (comma_total) * 1.2, 30)
        Axes: 0, source_dur, -max_c_ax, max_c_ax
        Paint rectangle: "{0.97, 0.95, 0.92}",
        ...    0, source_dur, -max_c_ax, max_c_ax

        Colour: "{0.78, 0.78, 0.78}"
        Dotted line
        Draw line: 0, 0, source_dur, 0
        Draw line: 0,  comma_climax_threshold, source_dur,  comma_climax_threshold
        Draw line: 0, -comma_climax_threshold, source_dur, -comma_climax_threshold
        Solid line

        Colour: "{0.70, 0.15, 0.15}"
        Line width: 2.0
        prev_tc = 0
        prev_cc = 0
        for ph from 1 to n_phrases
            tc = phrase_start [ph] * analysis_step_sec
            cv = phrase_comma [ph]
            if ph > 1
                Draw line: prev_tc, prev_cc, tc, cv
            endif
            prev_tc = tc
            prev_cc = cv
        endfor
        Line width: 1

        Black
        Draw inner box
        Font size: 7
        Text left: "yes", "Comma (cents)"
        Text bottom: "yes", "Time (s)"
    endif

    Black
    Font size: 10
endif

# ============================================================
# CLEANUP ANALYSIS OBJECTS
# ============================================================
removeObject: pitch_id, harm_id, intens_id, src_work

# ============================================================
# FINAL INFO REPORT
# ============================================================
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", src_name$, "_MHFE_result"
appendInfoLine: "Phrases: ", n_phrases
appendInfoLine: "Zone S:  ", fixed$ (100.0 * n_stable / n_frames, 1), "%"
appendInfoLine: "Zone U:  ",
...    fixed$ (100.0 * (n_voiced - n_stable) / n_frames, 1), "%"
appendInfoLine: "Zone N:  ",
...    fixed$ (100.0 * (n_frames - n_voiced) / n_frames, 1), "%"
appendInfoLine: "Peak comma: ", fixed$ (comma_total, 1), " cents"
appendInfoLine: "Wolf events: ", wolf_events

if play_result
    selectObject: result_id
    Play
endif

selectObject: result_id

# ============================================================
# END OF MAIN SCRIPT
# ============================================================


# ============================================================
# PROCEDURES
# ============================================================

# ------------------------------------------------------------
# fieldName: return display name for a tuning system index
# ------------------------------------------------------------
procedure fieldName: .sys
    if .sys = 1
        .result$ = "12-TET"
    elsif .sys = 2
        .result$ = "Just Intonation (5-limit)"
    elsif .sys = 3
        .result$ = "Pythagorean"
    elsif .sys = 4
        .result$ = "19-TET"
    elsif .sys = 5
        .result$ = "31-TET"
    elsif .sys = 6
        .result$ = "Harmonic Series"
    elsif .sys = 7
        .result$ = "Septimal (7-limit)"
    else
        .result$ = "User-Defined"
    endif
endproc

# ------------------------------------------------------------
# computeAnchor: weighted mean f0 in cents for a phrase segment
#   Input:  .ps, .pe = start/end frame indices
#           .prev_c  = previous phrase anchor in cents (0 if first)
#   Output: .result_cents
# ------------------------------------------------------------
procedure computeAnchor: .ps, .pe, .prev_c
    .sum_w  = 0
    .sum_wf = 0

    # First pass: stable frames only (zone 1)
    for .t from .ps to .pe
        if zone# [.t] = 1 and f0_hz# [.t] > 0
            .f0c     = 6900 + 1200 * log2 (f0_hz# [.t] / 440)
            .sum_wf += .f0c * voicing_w# [.t]
            .sum_w  += voicing_w# [.t]
        endif
    endfor

    # Second pass: if no stable frames use unstable (zone 2) at half weight
    if .sum_w <= 0
        for .t from .ps to .pe
            if zone# [.t] = 2 and f0_hz# [.t] > 0
                .f0c     = 6900 + 1200 * log2 (f0_hz# [.t] / 440)
                .sum_wf += .f0c * voicing_w# [.t] * 0.5
                .sum_w  += voicing_w# [.t] * 0.5
            endif
        endfor
    endif

    if .sum_w > 0
        .raw = .sum_wf / .sum_w
    else
        # Last resort: first voiced frame in phrase
        .raw = 6900
        for .t from .ps to .pe
            if f0_hz# [.t] > 0
                .raw = 6900 + 1200 * log2 (f0_hz# [.t] / 440)
                .t   = .pe + 1
            endif
        endfor
    endif

    if .prev_c <= 0
        .result_cents = .raw
    else
        .diff = abs (.raw - .prev_c)
        if .diff <= anchor_inertia_cents
            .result_cents = (1 - memory_weight) * .raw
            ...            + memory_weight * .prev_c
        else
            # Larger jump: blend less aggressively
            .result_cents = (1 - memory_weight * 0.4) * .raw
            ...            + memory_weight * 0.4 * .prev_c
        endif
    endif
endproc

# ------------------------------------------------------------
# computeFieldMix: determine Field A / B blend weight for a phrase
#   Input:  .ph, .n_tot = phrase index and total phrase count
#           .comma      = current cumulative comma in cents
#   Output: .result  (0 = pure Field A, 1 = pure Field B)
# ------------------------------------------------------------
procedure computeFieldMix: .ph, .n_tot, .comma
    .progress = (.ph - 1) / max (.n_tot - 1, 1)

    if engine_preset = 5
        .result = .progress

    elsif engine_preset = 6
        .result = 0.5 + 0.45 * sin (.progress * 2 * pi)

    elsif engine_preset = 7
        .result = 0

    elsif abs (.comma) >= comma_climax_threshold
        if comma_resolution = 1
            .result = min (abs (.comma) / (comma_climax_threshold * 1.5), 1.0)
        elsif comma_resolution = 3
            .result = 1.0
        elsif comma_resolution = 4
            .result = 0.5
        else
            .result = 0.0
        endif
    else
        .result = 0.0
    endif
endproc

# ------------------------------------------------------------
# getInterval: preferred interval in cents for (system, voice)
#   Input:  .sys = tuning system index (1-8)
#           .v   = voice index (1-5)
#   Output: .result  (cents above anchor)
# Voice assignment:
#   1 = fifth / most consonant
#   2 = major or minor third
#   3 = complementary third
#   4 = fourth
#   5 = major second or characteristic interval
# ------------------------------------------------------------
procedure getInterval: .sys, .v
    .vv = min (max (.v, 1), 5)

    if .sys = 1
        if .vv = 1
            .result = 700.00
        elsif .vv = 2
            .result = 400.00
        elsif .vv = 3
            .result = 300.00
        elsif .vv = 4
            .result = 500.00
        else
            .result = 200.00
        endif

    elsif .sys = 2
        if .vv = 1
            .result = 701.96
        elsif .vv = 2
            .result = 386.31
        elsif .vv = 3
            .result = 315.64
        elsif .vv = 4
            .result = 498.04
        else
            .result = 203.91
        endif

    elsif .sys = 3
        if .vv = 1
            .result = 701.96
        elsif .vv = 2
            .result = 407.82
        elsif .vv = 3
            .result = 294.13
        elsif .vv = 4
            .result = 498.04
        else
            .result = 203.91
        endif

    elsif .sys = 4
        if .vv = 1
            .result = 694.74
        elsif .vv = 2
            .result = 378.95
        elsif .vv = 3
            .result = 315.79
        elsif .vv = 4
            .result = 505.26
        else
            .result = 189.47
        endif

    elsif .sys = 5
        if .vv = 1
            .result = 696.77
        elsif .vv = 2
            .result = 387.10
        elsif .vv = 3
            .result = 309.68
        elsif .vv = 4
            .result = 503.23
        else
            .result = 193.55
        endif

    elsif .sys = 6
        if .vv = 1
            .result = 701.96
        elsif .vv = 2
            .result = 386.31
        elsif .vv = 3
            .result = 968.83
        elsif .vv = 4
            .result = 203.91
        else
            .result = 1088.27
        endif

    elsif .sys = 7
        if .vv = 1
            .result = 968.83
        elsif .vv = 2
            .result = 266.87
        elsif .vv = 3
            .result = 582.51
        elsif .vv = 4
            .result = 435.08
        else
            .result = 231.17
        endif

    else
        if .vv <= user_n_int
            .result = user_int# [.vv]
        else
            .result = 701.96
        endif
    endif
endproc

# ------------------------------------------------------------
# applyBehavior: compute companion Hz for one phrase
#   Inputs:
#     .src_hz   = source anchor Hz
#     .tgt_hz   = harmonic target Hz
#     .beh      = behavior code (1-6)
#     .lean     = lean strength (0-1)
#     .d_in     = drift IIR state (Hz) — pass 0 per phrase
#     .dt       = phrase duration in seconds
#     .phase    = oscillator phase (radians) — pass 0 per phrase
#   Outputs:
#     .out_hz    = companion pitch in Hz
#     .drft_out  = updated drift state
#     .phase_out = updated oscillator phase
# Behavior codes:
#   1 = Snap       exact target
#   2 = Lean       blend source and target in log space
#   3 = Drift      one-pole IIR approach to target
#   4 = Oscillate  target +/- sinusoidal depth
#   5 = Smear      same as Snap (spatial smear applied at mix)
#   6 = Refuse     target + syntonic comma offset (21.5 cents)
# ------------------------------------------------------------
procedure applyBehavior: .src_hz, .tgt_hz, .beh, .lean,
...    .d_in, .dt, .phase
    .drft_out  = .d_in
    .phase_out = .phase
    .out_hz    = .tgt_hz

    if .src_hz <= 0 or .tgt_hz <= 0
        .out_hz   = 0
        .drft_out = 0

    elsif .beh = 1
        .out_hz = .tgt_hz

    elsif .beh = 2
        .src_c  = 6900 + 1200 * log2 (.src_hz / 440)
        .tgt_c  = 6900 + 1200 * log2 (.tgt_hz / 440)
        .bld_c  = .src_c + .lean * (.tgt_c - .src_c)
        .out_hz = 440 * 2 ^ ((.bld_c - 6900) / 1200)

    elsif .beh = 3
        if .d_in <= 0
            .drft_out = .tgt_hz
        else
            .alpha    = 1 - exp (- .dt / drift_tau_sec)
            .drft_out = .d_in + .alpha * (.tgt_hz - .d_in)
        endif
        .out_hz = .drft_out

    elsif .beh = 4
        .tgt_c     = 6900 + 1200 * log2 (.tgt_hz / 440)
        .osc_c     = oscillate_depth_cents * sin (.phase)
        .phase_out = .phase + 2 * pi * oscillate_rate_Hz * .dt
        .out_hz    = 440 * 2 ^ ((.tgt_c + .osc_c - 6900) / 1200)

    elsif .beh = 5
        .out_hz = .tgt_hz

    elsif .beh = 6
        .tgt_c  = 6900 + 1200 * log2 (.tgt_hz / 440)
        .out_hz = 440 * 2 ^ ((.tgt_c + 21.5 - 6900) / 1200)

    endif
endproc
