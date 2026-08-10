# ============================================================
# Praat AudioTools - Reich Generator (Auto-Phasing Tool)
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.2 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Reich Generator (Auto-Phasing Tool) -- extracts a loop from a
#   source recording and phases it against a pitch/tempo-drifting
#   copy (and an optional static anchor voice), Steve Reich style.
#
# Changelog v0.4.2 (2026) - compatibility/hardening pass:
#   - API COMPATIBILITY: the complete public form is byte-for-byte
#     unchanged, and the final output naming contract is unchanged.
#   - FIX: Random_seed=0 now explicitly returns Praat to safe/unpredictable
#     RNG mode before this script draws random values. A caller that had
#     previously installed a predictable global seed can no longer leak that
#     deterministic state into a nominally fresh Reich render.
#   - FIX: non-zero source time domains are handled through a zero-based
#     private analysis copy; random loop positions no longer assume xmin=0.
#   - FIX: quiet-but-valid sources are not rejected by an absolute 0.001 RMS
#     gate. The historical gate is retained for normal-level material but is
#     relaxed relative to the source RMS when the whole source is quiet.
#   - FIX: Start_Offset is measured against the ACTUAL post-drift V2 loop
#     duration. 50% now means exactly half of V2's loop (180 degrees), and
#     Random is uniform over one actual V2 cycle. The phase wheel uses the
#     same measured V2 duration, so picture and audio agree.
#   - FIX: phase normalization after adding the start offset uses modulo/floor
#     rather than a one-step >1 subtraction, making the monitor robust at
#     exact wrap points.
#   - HARDENING: Manual loop limits and flutter amount are validated before
#     any random draw; temporary source-analysis objects are cleaned early.
#
# Changelog v0.4.1 (2026) — second review pass:
#   - FIX: Classic Reich (the default preset) still forced
#     p_cycle = 2.0 while the default Total_Duration_min is 1.0 min,
#     so the default demo run ended halfway through the first phase
#     cycle. Classic Reich's cycle is now 1.0 min, matching the
#     default render length.
#   - FIX: the "no voiced material" notice only checked
#     pitch_ratio <> 1.0, so on unpitched loops with the V2 interval
#     left at Unison but Flutter_Amount_st > 0 (e.g. Broken Tape on
#     unvoiced material), flutter silently did nothing with no
#     warning. Notice now also fires when only flutter needed the
#     (empty) PitchTier.
#   - FIX: the phase wheel sampled t = (i-1) * (actual_duration /
#     num_samples), so the last sample landed one interval short of
#     the piece's actual end. For a duration that's an exact multiple
#     of the phase cycle, the drawn path approached but never
#     crossed the wrap point, undercounting cycle_count by one.
#     Sample interval is now actual_duration / (num_samples - 1) so
#     the last sample lands exactly at the end.
#
# Changelog v0.4 (2026) — response to internal review:
#   - FIX (audible, real bug): Flutter_Amount_st was labelled in
#     semitones but applied as "self + randomGauss(0, p_flut)"
#     directly to the PitchTier, whose values are in Hz. A "0.3"
#     setting was a 0.3 Hz standard deviation -- inaudibly small,
#     and its audible size depended on the loop's register. Flutter
#     is now applied multiplicatively/exponentially in log-frequency
#     space ("self * 2^(randomGauss(0, p_flut)/12)"), so the field
#     is genuinely in semitones and scales correctly with pitch.
#   - FIX (structural, real bug): a non-zero Start_Offset trimmed
#     the head off Voice 2 and the tail off Voice 1/3 to align them,
#     which shortened the final render to Total_Duration - Offset
#     instead of the requested Total_Duration. Voice 2's wall is now
#     built Offset_sec longer up front and only then has its head
#     trimmed, so every voice -- and the final mix -- lands at
#     exactly Total_Duration_min regardless of offset.
#   - ADDED: Random_seed (0 = fresh random sequence every run, any
#     other integer = reproducible loop pick / offset / flutter via
#     random_initializeWithSeedUnsafelyButPredictably).
#   - RENAMED: the form title, changelog, and output object name were
#     three different names ("Random Reich Generator",
#     "Harmonic Reich Generator [PRO]", "...ProReich..."). Unified to
#     "Reich Generator" everywhere.
#   - CHANGED: demo-friendlier defaults -- Cycle_Duration_min and
#     Total_Duration_min both default to 1.0 min (was 2.0 / 3.0), so
#     a full phase cycle completes within the default render.
#   - FIX: Voice 3 ("the anchor") was set with "Scale intensity: 65",
#     an absolute dB SPL-equivalent target unrelated to how loud the
#     actual source recording is. It's now set relative to the loop's
#     own intensity via a new V3_Level_dB_relative field (default
#     -6 dB under the loop), so the anchor sits under the other
#     voices instead of at an arbitrary absolute level.
#   - ADDED: final peak normalisation on the mixed output.
#
# Changelog v0.3 (2026):
#   - FIX (audible): loops were cut rectangularly at random
#     positions -- a hard discontinuity clicked at EVERY
#     repetition, metronomically, in both channels. Loop bounds
#     now snap to the nearest zero crossings (the standard looper
#     cure; no amplitude dips, no character change beyond the
#     tick's absence). If you ever want the raw splice ticks back
#     as a rhythm layer, say so -- it is one boolean.
#   - FIX: the phase wheel's cycle markers (C1, C2...) could
#     never draw -- prev_phase_norm was updated BEFORE the marker
#     test re-compared it against the current value. The cycle
#     COUNT was right (tested before the update); only the labels
#     were dead code. Wrapped-flag fix.
#   - Play is now gated by a form flag (house convention;
#     previously unconditional).
#   - NOTE printed when the pitch tier is empty (unvoiced loop):
#     Fifth/Octave settings act through PSOLA and silently do
#     nothing on unpitched material.
#   - AUDIT: the drift math verified exact -- Override to
#     base_sr*(n+1)/n makes V2's loop n/(n+1) shorter, so full
#     realignment lands at precisely Cycle_Duration; the ~0.8%
#     pitch lift is the authentic tape-phasing artifact.
#
# Changelog v0.2:
#   - Robustness: clamp the loop range (Min/Max_loop_sec) to the source
#     duration. Previously a source shorter than the loop length made
#     randomUniform(0, total_src_dur - ldur) negative and Extract part read
#     out of bounds, causing degenerate/silent loops or a misleading
#     "Could not find non-silent audio" exit.
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Reich Generator
    comment --- Presets ---
    optionmenu Preset 1
        option Classic Reich (Speech / Unison)
        option Deep Space (Sub-Bass Shadow)
        option Holy Trinity (5th + High Anchor)
        option Broken Tape (Flutter + Random Offset)
        option Manual (Settings below)

    comment --- Source Extraction ---
    real Min_loop_sec 0.6
    real Max_loop_sec 1.5
    
    comment --- Voice 2 (The Drifter) ---
    optionmenu V2_Interval 2
        option Unison
        option Perfect Fifth (+7st)
        option Octave Down
        option Octave Up
    
    comment --- Voice 3 (The Glue) ---
    optionmenu V3_Mode 1
        option None
        option Center Anchor (Unison Static)
        option Low Shadow (Octave Down Static)
        option High Shimmer (Octave Up Static)
    real V3_Level_dB_relative -6.0
    
    comment --- Structure & Feel ---
    positive Cycle_Duration_min 1.0
    
    optionmenu Start_Offset 3
        option 0% (Unison Start)
        option 50% (Anti-Phase)
        option Random
    
    real Flutter_Amount_st 0.05
    positive Total_Duration_min 1.0
    
    comment --- Reproducibility [0 = fresh random sequence each run] ---
    integer Random_seed 0
    
    comment --- Visualizations ---
    boolean Create_polar_phase_wheel 1
    comment --- Output ---
    boolean Play_result 1
endform

# ============================================
# 1. PRESET LOGIC
# ============================================

p_min = min_loop_sec
p_max = max_loop_sec
p_v2$ = v2_Interval$
p_v3$ = v3_Mode$
p_v3_level = v3_Level_dB_relative
p_cycle = cycle_Duration_min
p_off$ = start_Offset$
p_flut = flutter_Amount_st

if preset$ = "Classic Reich (Speech / Unison)"
    p_min = 0.5; p_max = 1.0
    p_v2$ = "Unison"; p_v3$ = "None"
    # v0.4.1 FIX: was 2.0, which meant the (also default-selected)
    # Classic Reich preset needed a 2-minute cycle to complete, but
    # Total_Duration_min defaults to 1.0 -- the default demo run
    # ended halfway through the first phase cycle. Matches the
    # 1-minute default duration so a full cycle completes.
    p_cycle = 1.0; p_off$ = "0% (Unison Start)"
    p_flut = 0.0

elsif preset$ = "Deep Space (Sub-Bass Shadow)"
    p_min = 2.0; p_max = 4.0
    p_v2$ = "Unison"; p_v3$ = "Low Shadow (Octave Down Static)"
    p_cycle = 5.0; p_off$ = "50% (Anti-Phase)"
    p_flut = 0.1

elsif preset$ = "Holy Trinity (5th + High Anchor)"
    p_min = 0.8; p_max = 1.2
    p_v2$ = "Perfect Fifth (+7st)"; p_v3$ = "High Shimmer (Octave Up Static)"
    p_cycle = 3.0; p_off$ = "Random"
    p_flut = 0.02

elsif preset$ = "Broken Tape (Flutter + Random Offset)"
    p_min = 0.4; p_max = 0.9
    p_v2$ = "Unison"; p_v3$ = "Center Anchor (Unison Static)"
    p_cycle = 1.5; p_off$ = "Random"
    p_flut = 0.3
endif
# NOTE: p_v3_level (Voice 3's level relative to the loop) is
# deliberately never touched by a preset -- like Source pitch in
# Messagesquisse Opening, it's a mix-balance knob the user set for
# their own source material, not a trait of the compositional preset.

# RNG initialization is deliberately deferred until after input/parameter
# validation. This avoids leaving a caller in predictable RNG mode if the
# script has to stop before it draws anything.

# ============================================
# 2. SOURCE EXTRACTION (CLEAN)
# ============================================

if numberOfSelected("Sound") <> 1
    exitScript: "Select exactly one Sound object."
endif

source_id = selected("Sound")
source_name$ = selected$("Sound")
selectObject: source_id
source_xmin = Get start time
source_xmax = Get end time
total_src_dur = Get total duration

# Public parameters are unchanged; validate the Manual values before any RNG
# state is installed or any random draw occurs. Presets already provide valid
# positive values.
if p_min <= 0 or p_max <= 0
    exitScript: "Min_loop_sec and Max_loop_sec must be > 0."
endif
if p_min > p_max
    exitScript: "Min_loop_sec must be <= Max_loop_sec."
endif
if p_flut < 0
    exitScript: "Flutter_Amount_st must be >= 0."
endif

# Private zero-based source copy. Extract part with preserve-times=no gives a
# domain of 0..duration, so all existing random-loop math remains valid even
# when the selected Sound itself starts at a non-zero time.
selectObject: source_id
Extract part: source_xmin, source_xmax, "rectangular", 1, "no"
Rename: "Reich_Source_Work"
source_work = selected("Sound")
Convert to mono
Rename: "Reich_Source_Analysis"
source_analysis = selected("Sound")
selectObject: source_work
Remove
source_work = 0

selectObject: source_analysis
source_rms = Get root-mean-square: 0, 0
if source_rms <= 1e-12
    removeObject: source_analysis
    exitScript: "Selected Sound is silent."
endif
# Preserve v0.4.1's absolute 0.001 gate for normal-level material, but relax
# it for globally quiet sources so final peak normalization can still make
# them usable. The floor remains safely above numerical zero.
activity_rms_floor = min(0.001, source_rms * 0.05)
if activity_rms_floor < 1e-12
    activity_rms_floor = 1e-12
endif

# Guard: if the source is shorter than the requested loop length, clamp the
# range to available material. This preserves the established v0.2 behavior.
if p_max > total_src_dur
    p_max = total_src_dur
endif
if p_min > p_max
    p_min = p_max
endif
if p_min <= 0
    removeObject: source_analysis
    exitScript: "Source is too short for a positive loop duration."
endif

# Explicit RNG policy. Praat's predictable seed persists globally until safe
# initialization is called, so seed=0 must actively undo any predictable mode
# inherited from a caller. Non-zero seeds remain exactly reproducible here.
if random_seed <> 0
    seedResult = random_initializeWithSeedUnsafelyButPredictably (random_seed)
else
    random_initializeSafelyAndUnpredictably ()
endif

found = 0
attempts = 0
writeInfoLine: "Searching for audio..."

while found = 0 and attempts < 40
    ldur = randomUniform(p_min, p_max)
    st = randomUniform(0, total_src_dur - ldur)
    
    selectObject: source_analysis
    Extract part: st, st + ldur, "rectangular", 1, "no"
    check_id = selected("Sound")
    
    selectObject: check_id
    rms = Get root-mean-square: 0, 0
    if rms > activity_rms_floor
        # v0.3: snap loop bounds to zero crossings -- rectangular
        # random cuts clicked at every repetition
        .cd = Get total duration
        z1 = Get nearest zero crossing: 1, 0.003
        z2 = Get nearest zero crossing: 1, .cd - 0.003
        if z1 = undefined
            z1 = 0
        endif
        if z2 = undefined or z2 <= z1 + 0.05
            z2 = .cd
        endif
        snapped = Extract part: z1, z2, "rectangular", 1, "no"
        removeObject: check_id
        check_id = snapped
        found = 1
        Rename: "Loop_Base"
        loop_base = check_id
    else
        Remove
        attempts = attempts + 1
    endif
endwhile

if found = 0
    removeObject: source_analysis
    random_initializeSafelyAndUnpredictably ()
    exitScript: "Could not find non-silent audio."
endif

# The loop is now independent; release the full analysis copy early.
removeObject: source_analysis

selectObject: loop_base
base_sr = Get sampling frequency
dur_base = Get duration
loopBaseIntensity_dB = Get intensity (dB)

# ============================================
# 3. CALCULATE DRIFT
# ============================================

cycle_sec = p_cycle * 60
loops_in_cycle = cycle_sec / dur_base
drift_ratio = (loops_in_cycle + 1) / loops_in_cycle

appendInfoLine: "Loop: " + fixed$(dur_base, 3) + "s"
appendInfoLine: "Cycle: " + string$(p_cycle) + " min"
appendInfoLine: "Ratio: " + fixed$(drift_ratio, 6)

# ============================================
# 4. PROCESS VOICE 2 (Pitch + Flutter + Drift)
# ============================================

selectObject: loop_base
Copy: "V2_Temp"
v2_id = selected("Sound")

pitch_ratio = 1.0
if p_v2$ = "Perfect Fifth (+7st)"
    pitch_ratio = 1.4983
elsif p_v2$ = "Octave Down"
    pitch_ratio = 0.5
elsif p_v2$ = "Octave Up"
    pitch_ratio = 2.0
endif

if pitch_ratio <> 1.0 or p_flut > 0
    To Manipulation: 0.01, 75, 600
    manip_id = selected("Manipulation")
    
    Extract pitch tier
    pitch_id = selected("PitchTier")
    nPitchPts = Get number of points
    if nPitchPts = 0 and (pitch_ratio <> 1.0 or p_flut > 0)
        appendInfoLine: "NOTE: no voiced material in the loop -- V2 pitch interval and flutter will have no effect."
    endif
    
    if pitch_ratio <> 1.0
        Formula: "self * " + string$(pitch_ratio)
    endif
    
    if p_flut > 0
        # v0.4 FIX: PitchTier values are in Hz, so "self + randomGauss(0, st)"
        # was adding a fraction-of-a-Hz jitter, not a semitone-scaled one --
        # audibly negligible and register-dependent. Semitones are a ratio,
        # so the jitter has to be multiplicative/exponential in log-frequency
        # space: self * 2^(randomGauss(0, semitones)/12).
        Formula: "self * 2 ^ (randomGauss(0, " + string$(p_flut) + ") / 12)"
    endif
    
    selectObject: manip_id
    plusObject: pitch_id
    Replace pitch tier
    
    selectObject: manip_id
    Get resynthesis (overlap-add)
    Rename: "V2_Processed"
    
    v2_new = selected("Sound")
    selectObject: v2_id
    plusObject: manip_id
    plusObject: pitch_id
    Remove
    v2_id = v2_new
endif

selectObject: v2_id
Override sampling frequency: base_sr * drift_ratio
Resample: base_sr, 50
Rename: "V2_Drifting"
v2_final = selected("Sound")
selectObject: v2_final
dur_v2 = Get total duration
selectObject: v2_id
Remove

# ============================================
# 5. PROCESS VOICE 3 (The Anchor)
# ============================================

has_v3 = 0
v3_id = 0

if p_v3$ <> "None"
    has_v3 = 1
    selectObject: loop_base
    Copy: "V3_Temp"
    v3_temp = selected("Sound")
    
    v3_ratio = 1.0
    if p_v3$ = "Low Shadow (Octave Down Static)"
        v3_ratio = 0.5
    elsif p_v3$ = "High Shimmer (Octave Up Static)"
        v3_ratio = 2.0
    endif
    
    if v3_ratio <> 1.0
        To Manipulation: 0.01, 75, 600
        manip_id = selected("Manipulation")
        
        Extract pitch tier
        v3_pitch_id = selected("PitchTier")
        nV3Pts = Get number of points
        if nV3Pts = 0
            appendInfoLine: "NOTE: no voiced material in the loop -- the V3 octave acts through PSOLA and will have no effect."
        endif
        
        Formula: "self * " + string$(v3_ratio)
        
        selectObject: manip_id
        plusObject: v3_pitch_id
        Replace pitch tier
        
        selectObject: manip_id
        Get resynthesis (overlap-add)
        Rename: "V3_Final"
        v3_id = selected("Sound")
        
        selectObject: manip_id
        plusObject: v3_pitch_id
        plusObject: v3_temp
        Remove
    else
        Rename: "V3_Final"
        v3_id = selected("Sound")
    endif
    
    selectObject: v3_id
    # v0.4 FIX: was "Scale intensity: 65", an absolute dB SPL-equivalent
    # target with no relation to how loud the actual source recording is.
    # Set relative to the loop's own measured intensity instead, so the
    # anchor sits a controlled number of dB under/over the other voices
    # regardless of the source's absolute level.
    Scale intensity: loopBaseIntensity_dB + p_v3_level
endif

# ============================================
# 6. OFFSET (computed before the walls are built --
#    Voice 2's wall needs extra length up front so trimming its
#    head doesn't shorten the final render)
# ============================================

offset_sec = 0
if p_off$ = "50% (Anti-Phase)"
    offset_sec = dur_v2 * 0.5
elsif p_off$ = "Random"
    offset_sec = randomUniform(0, dur_v2)
endif

# All random choices (loop pick, PitchTier flutter, start offset) are complete.
# Return the global generator to Praat's safe/unpredictable mode so a seeded
# Reich render does not make subsequently-called scripts deterministic.
random_initializeSafelyAndUnpredictably ()

# ============================================
# 7. BUILD TRACKS
# ============================================

total_sec = total_Duration_min * 60

procedure make_wall .src .len .name$
    selectObject: .src
    Copy: .name$
    .id = selected("Sound")
    .dur = Get duration
    while .dur < .len
        selectObject: .id
        Copy: "tmp"
        .c = selected("Sound")
        selectObject: .id
        plusObject: .c
        Concatenate
        .new = selected("Sound")
        selectObject: .id
        plusObject: .c
        Remove
        .id = .new
        selectObject: .id
        Rename: .name$
        .dur = Get duration
    endwhile
    selectObject: .id
    Extract part: 0, .len, "rectangular", 1, "no"
    .fin = selected("Sound")
    Rename: .name$
    selectObject: .id
    Remove
    selectObject: .fin
endproc

call make_wall loop_base total_sec "Track_1_Static"
t1 = selected("Sound")

# v0.4 FIX: previously built at total_sec and then had its HEAD cut by
# offset_sec afterwards, which shortened the whole render to
# total_sec - offset_sec instead of the requested Total_Duration_min.
# Build it offset_sec longer up front, then trim the head to length --
# the tail lands exactly at total_sec either way.
v2_wall_len = total_sec + offset_sec
call make_wall v2_final v2_wall_len "Track_2_Drift_Raw"
t2_raw = selected("Sound")

if offset_sec > 0
    selectObject: t2_raw
    Extract part: offset_sec, offset_sec + total_sec, "rectangular", 1, "no"
    Rename: "Track_2_Drift"
    t2 = selected("Sound")
    removeObject: t2_raw
else
    t2 = t2_raw
    selectObject: t2
    Rename: "Track_2_Drift"
endif

t3 = 0
if has_v3
    call make_wall v3_id total_sec "Track_3_Anchor"
    t3 = selected("Sound")
endif

# ============================================
# 8. POLAR PHASE WHEEL (Visual)
# ============================================

if create_polar_phase_wheel

    appendInfoLine: ""
    appendInfoLine: "=== GENERATING PROCESS MONITOR ==="

    # v0.4: the render is now always exactly total_sec, offset or not
    # (see section 6/7 fix), so no separate "shortened" duration exists.
    actual_duration = total_sec

    num_samples = 1200
    # v0.4.1 FIX: was actual_duration / num_samples, whose last sample
    # (t at i=num_samples) lands one interval short of actual_duration.
    # For a duration that's an exact multiple of the phase cycle, the
    # drawn path approaches but never crosses the 360deg wrap point, so
    # cycle_count could read one lower than the true number of cycles.
    # Dividing by (num_samples - 1) makes the last sample land exactly
    # at the end of the piece.
    sample_interval = actual_duration / (num_samples - 1)
    
    # --- VIEWPORT ---
    Erase all
    Select outer viewport: 0, 7, 0, 7
    # 6x6 area inside the viewport
    Axes: 0, 100, 0, 100
    
    # 1. Background / Zones
    Colour: {0.85, 0.85, 0.85}
    Line width: 1
    # Outer Ring
    for i from 1 to 360
        ang = i * pi / 180
        x1 = 50 + 35 * sin(ang)
        y1 = 50 + 35 * cos(ang)
        x2 = 50 + 40 * sin(ang)
        y2 = 50 + 40 * cos(ang)
        Draw line: x1, y1, x2, y2
    endfor
    
    # Inner Ring
    Colour: {1.0, 0.3, 0.3}
    for i from 1 to 360
        ang = i * pi / 180
        x1 = 50 + 2 * sin(ang)
        y1 = 50 + 2 * cos(ang)
        x2 = 50 + 8 * sin(ang)
        y2 = 50 + 8 * cos(ang)
        Draw line: x1, y1, x2, y2
    endfor
    
    # 2. Grid & Labels
    Colour: "Black"
    Line width: 1
    Dotted line
    
    Draw line: 50, 50, 50, 90   ; 0 deg
    Draw line: 50, 50, 90, 50   ; 90 deg
    Draw line: 50, 50, 50, 10   ; 180 deg
    Draw line: 50, 50, 10, 50   ; 270 deg
    
    Solid line
    Text special: 50, "centre", 94, "bottom", "Helvetica", 11, "0", "0° Unison"
    Text special: 94, "left", 50, "half", "Helvetica", 9, "0", "90°"
    Text special: 50, "centre", 6, "top", "Helvetica", 11, "0", "180° Anti"
    Text special: 6, "right", 50, "half", "Helvetica", 9, "0", "270°"
    
    # 3. Draw Process Line
    prev_x = 0
    prev_y = 0
    final_x = 0
    final_y = 0
    cycle_count = 0
    prev_phase_norm = 0
    
    for i from 1 to num_samples
        t = (i - 1) * sample_interval
        
        v1_loops = t / dur_base
        v2_loops = t / dur_v2
        phase_raw = v2_loops - v1_loops
        phase_norm = phase_raw - floor(phase_raw)
        
        if offset_sec > 0
             offset_ratio = offset_sec / dur_v2
             phase_norm = phase_norm + offset_ratio
             phase_norm = phase_norm - floor(phase_norm)
        endif
        
        # Cycle check (v0.3: wrapped flag -- the marker block below
        # used to re-test prev vs current AFTER this update, i.e.
        # compare a value with itself: markers never drew)
        wrapped = 0
        if i > 1 and prev_phase_norm > 0.9 and phase_norm < 0.1
            cycle_count = cycle_count + 1
            wrapped = 1
        endif
        prev_phase_norm = phase_norm
        
        # Drawing
        angle_rad = phase_norm * 2 * pi
        beat_amp = 0.5 + 0.5 * cos(angle_rad)
        
        r = 5 + (beat_amp * 35)
        x = 50 + r * sin(angle_rad)
        y = 50 + r * cos(angle_rad)
        
        # Gradient
        red_val = 1.0 - beat_amp
        blue_val = beat_amp
        Colour: {red_val, 0, blue_val}
        Line width: 2
        
        if i > 1
             dist = sqrt((x-prev_x)^2 + (y-prev_y)^2)
             if dist < 20
                 Draw line: prev_x, prev_y, x, y
             endif
        endif
        
        # Time markers
        if t mod 30 < sample_interval and t > 0
            Colour: "Black"
            Paint circle (mm): "Black", x, y, 0.8
            time_label$ = fixed$(t, 0) + "s"
            Text special: x+2, "left", y, "half", "Helvetica", 7, "0", time_label$
            Colour: {red_val, 0, blue_val}
        endif
        
        # Cycle markers
        if wrapped
            Colour: "Black"
            Paint circle (mm): "White", x, y, 1.2
            Draw circle (mm): x, y, 1.2
            cycle_label$ = "C" + string$(cycle_count)
            Text special: x, "centre", y-3, "top", "Helvetica", 8, "0", cycle_label$
            Colour: {red_val, 0, blue_val}
        endif
        
        prev_x = x
        prev_y = y
        
        if i = num_samples
            final_x = x
            final_y = y
        endif
    endfor
    
    # 4. End State
    Paint circle (mm): "Red", final_x, final_y, 2
    Draw circle (mm): final_x, final_y, 2
    
    # End Label
    t_final_val = actual_duration
    v1_calc_final = t_final_val / dur_base
    v2_calc_final = t_final_val / dur_v2
    
    phase_final = v2_calc_final - v1_calc_final
    phase_norm_final = phase_final - floor(phase_final)
    if offset_sec > 0
        phase_norm_final = phase_norm_final + offset_sec / dur_v2
        phase_norm_final = phase_norm_final - floor(phase_norm_final)
    endif
    
    final_degrees = phase_norm_final * 360
    final_label$ = "End: " + fixed$(final_degrees, 0) + "°"
    Text special: final_x-3, "right", final_y-3, "top", "Helvetica", 9, "0", final_label$
    
    # 5. Bottom Legend
    Colour: "Black"
    Text special: 50, "centre", 0, "bottom", "Helvetica", 10, "0", "Total Cycles: " + string$(cycle_count) + " | Duration: " + fixed$(actual_duration/60, 1) + " min"
    
    Colour: "Blue"
    Draw line: 2, 96, 8, 96
    Colour: "Black"
    Text special: 10, "left", 96, "half", "Helvetica", 8, "0", "= Unison"
    
    Colour: "Red"
    Draw line: 2, 92, 8, 92
    Colour: "Black"
    Text special: 10, "left", 92, "half", "Helvetica", 8, "0", "= Anti-Phase"

endif

# ============================================
# 9. MIXING & CLEANUP
# ============================================

selectObject: t1
Rename: "Left"

selectObject: t2
Rename: "Right"

if has_v3
    selectObject: t1
    plusObject: t3
    Combine to stereo
    temp_st = selected("Sound")
    Convert to mono
    Rename: "Left_Final"
    t1_final = selected("Sound")
    selectObject: temp_st
    plusObject: t1
    Remove
    t1 = t1_final

    selectObject: t2
    plusObject: t3
    Combine to stereo
    temp_st = selected("Sound")
    Convert to mono
    Rename: "Right_Final"
    t2_final = selected("Sound")
    selectObject: temp_st
    plusObject: t2
    Remove
    t2 = t2_final
    
    selectObject: t3
    Remove
endif

selectObject: t1
plusObject: t2
Combine to stereo
Rename: source_name$ + "_ReichGen_" + preset$
final_id = selected("Sound")

# Final Cleanup
selectObject: loop_base
plusObject: v2_final
plusObject: t1
plusObject: t2
if has_v3
   plusObject: v3_id
endif
Remove

# v0.4: final peak normalisation -- previously absent, so overall
# loudness depended entirely on the source recording's own level
# plus however the three voices happened to sum.
selectObject: final_id
Scale peak: 0.99

selectObject: final_id
if play_result
    Play
endif
selectObject: final_id