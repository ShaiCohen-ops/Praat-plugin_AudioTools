# ============================================================
# Praat AudioTools - Golden_Ratio_Processor.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 3.0 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   A processing pipeline organised around the Golden Ratio
#   (phi = 1.618). Pitch, intensity, timbre and panning are shaped
#   against the Golden Time Structure:
#     T1 (development) = T / phi;  T2 (resolution) = T - T1
#
#   What each stage really does, stated plainly:
#     Pitch        - scaled deviation from the measured contour,
#                    rising to T1 and resolving over T2
#     Intensity    - envelope peaking at 0.618 T
#     Spectral     - see Spectral_scaling_mode below; the default
#                    warps the measured SPECTRAL ENVELOPE landmarks and
#                    preserves duration, pitch and complex-spectrum phase
#     Filtering    - band centred on the spectral centre of gravity,
#                    edges at cog / phi^k and cog * phi^k
#     Panning      - a mono-derived AUTO-PAN whose excursion blooms at
#                    T1. It is not stereo widening: there is no
#                    decorrelation, no time difference and no
#                    independent side signal. On mono noise the
#                    measured L/R correlation is 0.99 / 0.95 / 0.85 for
#                    the three presets, with Side 22.0 / 15.6 /
#                    10.5 dB below Mid.
#
# Changelog v2.4 - reviewed by running the script under Parselmouth,
# so the figures below are measurements.
#   - SPECTRAL SCALING WAS A VARISPEED. "Override sampling frequency"
#     followed by "Resample" shortens the file and raises pitch: a 1 s
#     220 Hz input came out 0.8436 s / 260.8 Hz (Subtle), 0.7295 s /
#     301.6 Hz (Standard) and 0.6180 s / 356.0 Hz (Pronounced) - the
#     last being exactly T/phi. That destroyed the script's own time
#     architecture, which is computed from the ORIGINAL duration: at
#     Pronounced the output ended exactly AT the climax and the
#     resolution phase never happened. Spectral_scaling_mode now
#     chooses. The default warps formants with Change gender at a
#     duration factor of 1, so duration and pitch survive and the
#     golden structure still means something. Varispeed remains
#     available, honestly named, and is applied FIRST so the time
#     structure is derived from the length that results.
#   - target_f2 is used. It was computed as mean_f2 * phi and then
#     never applied to anything; it is now the formant warp ratio.
#     f0_min, f0_max and cog are reported or used by the filter rather
#     than being dead ends.
#   - THE AUDIO IS NO LONGER FOLDED TO MONO. Only the ANALYSIS uses a
#     mono copy. v2.3 folded first, so stereo came back mono with
#     panning off, 4-channel came back mono, and anti-phase stereo
#     cancelled to a peak and RMS of exactly 0. Every channel is
#     processed; with panning on, a mono input expands to stereo and a
#     multichannel input has the pan gains applied to channels 1 and 2.
#   - RELATIVE TIME. PitchTier times were compared against
#     duration / phi and the vibrato used sin(...t) with t as ABSOLUTE
#     time, so the same signal at 0-1 s and at 5.137-6.137 s gave
#     correlations of -0.028 (pitch), 0.761 (micro modulation) and
#     0.230 (intensity), and the panning tiers, built over 0..duration,
#     missed the audio entirely - measured L/R difference 0.217 at
#     xmin 0 against exactly 0 at xmin 5.137, i.e. no panning at all.
#     All work now happens on a copy shifted to 0.
#   - True bypass and one output stage. With every component off, v2.3
#     still folded to mono and ran Scale peak: 0.95, taking a 0.05-peak
#     input to 0.95. The intensity stage also normalized internally and
#     then again at the end.
#   - Pan speed accelerates by phi, not phi squared. Base was 0.5/phi
#     and climax 0.5*phi, a ratio of phi^2 = 2.618, while the report
#     said "Accelerates x phi".
#   - The width report is per preset. It always said "Bloom to 100%"
#     although width is multiplied by scaling_strength: 30%, 60%, 100%.
#   - Short files are checked before analysis. A 50 ms file died inside
#     To Intensity; the minimum is 6.4 / Pitch_floor_Hz, about 85.3 ms
#     at the default 75 Hz.
#   - writeInfoLine was called five times in a row at the top, each
#     wiping the window, so only the last line survived.
#   - Object_N[col] and an inline if/then/else/fi inside a string
#     replaced with object[id, row, col] and a precomputed string.
#
# Changelog v3.0:
#   - Replaced Change gender formant resynthesis with a static spectral-
#     envelope landmark warp. FormantPath is ANALYSIS ONLY; measured F1-F5
#     are broad spectral landmarks, never resonator poles. The complex
#     spectrum keeps its original phase and receives a smooth magnitude
#     redistribution from each measured landmark to its phi-scaled target.
#   - The formant mapping is time-invariant, so one FFT per channel is used
#     rather than a grain loop. This keeps long-file processing fast.
#   - Golden auto-pan no longer normalizes left and right independently:
#     tiers contain relative dB gains and Multiply uses no scaling.
#   - True no-component bypass runs before duration-dependent analysis.
#
# Usage:
#   Select a Sound object and run.
# ============================================================

form Golden Ratio Processor v3.0
    optionmenu Preset: 1
        option Subtle (gentle phi influence)
        option Standard (moderate phi scaling)
        option Pronounced (strong phi transformation)
    comment === Components ===
    boolean Apply_pitch_architecture 1
    boolean Apply_intensity_structure 1
    optionmenu Spectral_scaling_mode: 2
        option Off
        option Spectral formant warp (keeps duration and pitch)
        option Varispeed (shortens and transposes by phi)
    boolean Apply_spectral_filtering 1
    boolean Apply_golden_panning 1
    boolean Apply_micro_modulation 0
    comment === Analysis ===
    positive Pitch_floor_Hz 75
    positive Pitch_ceiling_Hz 600
    positive Time_step_s 0.01
    comment === Output ===
    optionmenu Output_level_mode: 1
        option Natural level
        option Safety ceiling (attenuate only)
        option Match input RMS
        option Peak normalize
    positive Ceiling_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object first."
endif

phi = 1.618033988749895
phi_inv = 1 / phi

if preset = 1
    scaling_strength = 0.3
    presetName$ = "Subtle"
elsif preset = 2
    scaling_strength = 0.6
    presetName$ = "Standard"
else
    scaling_strength = 1.0
    presetName$ = "Pronounced"
endif

orig_id = selected("Sound")
orig_name$ = selected$("Sound")

selectObject: orig_id
sample_rate = Get sampling frequency
n_channels = Get number of channels
input_duration = Get total duration
original_xmin = Get start time
nyquist = sample_rate / 2
input_peak = Get absolute extremum: 0, 0, "None"
input_rms = Get root-mean-square: 0, 0

# --- Validation ---
if pitch_ceiling_Hz <= pitch_floor_Hz
    exitScript: "Pitch_ceiling_Hz must be above Pitch_floor_Hz."
endif
if ceiling_peak <= 0 or ceiling_peak > 1
    exitScript: "Ceiling_peak must be greater than 0 and at most 1."
endif
# Is anything actually enabled?
component_count = 0
if apply_pitch_architecture
    component_count = component_count + 1
endif
if apply_intensity_structure
    component_count = component_count + 1
endif
if spectral_scaling_mode > 1
    component_count = component_count + 1
endif
if apply_spectral_filtering
    component_count = component_count + 1
endif
if apply_micro_modulation
    component_count = component_count + 1
endif
if apply_golden_panning
    component_count = component_count + 1
endif

# Analysis-based stages need enough audio, but a full bypass does not.
min_dur = 6.4 / pitch_floor_Hz
if component_count > 0 and input_duration < min_dur
    exitScript: "Sound is too short: " + fixed$(input_duration * 1000, 1) + " ms. At a " +
    ... "pitch floor of " + fixed$(pitch_floor_Hz, 0) + " Hz the analysis needs at least " +
    ... fixed$(min_dur * 1000, 1) + " ms. Raise Pitch_floor_Hz or use a longer Sound."
endif

# ============================================================
# Info header
# ============================================================
# v2.3 used writeInfoLine five times in a row here; each call CLEARS
# the window, so only the last line ever survived.
clearinfo
writeInfoLine: "=== Golden Ratio Processor v3.0 ==="
appendInfoLine: "phi = ", fixed$(phi, 6)
appendInfoLine: "Input: ", orig_name$, " (", fixed$(input_duration, 3), " s, ",
    ... n_channels, " ch, ", sample_rate, " Hz)"
appendInfoLine: "Preset: ", presetName$, " (scaling strength ", fixed$(scaling_strength, 2), ")"
appendInfoLine: ""

if component_count = 0
    appendInfoLine: "No components enabled: returning the input unchanged."
    selectObject: orig_id
    bypass_out = Copy: orig_name$ + "_GoldenRatio_Bypass"
    selectObject: bypass_out
    if play_result
        Play
    endif
    exitScript: ""
endif

# ============================================================
# Work copy at time 0
# ============================================================
# Every stage here compares times against duration / phi or feeds them
# to sin(), and x in a Praat Formula is ABSOLUTE time. v2.3 therefore
# gave completely different results for the same signal at 0-1 s and at
# 5.137-6.137 s, and the panning tiers missed the audio altogether.
selectObject: orig_id
work_sound = Copy: "gr_work"
Shift times to: "start time", 0

# ============================================================
# PHASE 0: Varispeed, if chosen, BEFORE the time structure
# ============================================================
# If the length is going to change, the golden structure has to be
# computed from the length that results - otherwise the climax lands
# past the end of the file, which is what happened at Pronounced.
adjusted_ratio = 1 + (phi - 1) * scaling_strength
varispeed_done = 0

if spectral_scaling_mode = 3
    appendInfoLine: "PHASE 0: Varispeed x", fixed$(adjusted_ratio, 4),
        ... " (duration and pitch both change)"
    selectObject: work_sound
    current_rate = Get sampling frequency
    Override sampling frequency: current_rate * adjusted_ratio
    Resample: current_rate, 50
    vari = selected("Sound")
    removeObject: work_sound
    work_sound = vari
    selectObject: work_sound
    Shift times to: "start time", 0
    varispeed_done = 1
endif

selectObject: work_sound
total_duration = Get total duration

t1 = total_duration * phi_inv
t2 = total_duration - t1
climax_time = t1

# ============================================================
# PHASE 1: Analysis (on a mono copy - analysis only)
# ============================================================
# v2.3 folded the AUDIO to mono, so stereo returned mono, 4 channels
# returned mono, and anti-phase stereo cancelled to peak 0 / RMS 0.
appendInfoLine: "PHASE 1: Global analysis"

if n_channels > 1
    selectObject: work_sound
    mono_id = Convert to mono
    selectObject: mono_id
    mono_rms = Get root-mean-square: 0, 0
    if mono_rms < 0.0000001
        # The fold cancelled; fall back to the loudest channel.
        removeObject: mono_id
        best_rms = -1
        pick_ch = 1
        for ch from 1 to n_channels
            selectObject: work_sound
            probe = Extract one channel: ch
            probe_rms = Get root-mean-square: 0, 0
            removeObject: probe
            if probe_rms > best_rms
                best_rms = probe_rms
                pick_ch = ch
            endif
        endfor
        selectObject: work_sound
        mono_id = Extract one channel: pick_ch
        appendInfoLine: "  Mono fold cancelled (anti-phase): analysing channel ", pick_ch
    endif
else
    selectObject: work_sound
    mono_id = Copy: "gr_mono"
endif

selectObject: mono_id
pitch_obj = To Pitch: time_step_s, pitch_floor_Hz, pitch_ceiling_Hz
mean_f0 = Get mean: 0, 0, "Hertz"
if mean_f0 = undefined
    mean_f0 = 200
endif
f0_min = Get minimum: 0, 0, "Hertz", "Parabolic"
f0_max = Get maximum: 0, 0, "Hertz", "Parabolic"
if f0_min = undefined
    f0_min = mean_f0 * 0.8
endif
if f0_max = undefined
    f0_max = mean_f0 * 1.2
endif

selectObject: mono_id
intensity_obj = To Intensity: pitch_floor_Hz, time_step_s, "yes"
mean_intensity = Get mean: 0, 0, "energy"
intensity_stddev = Get standard deviation: 0, 0

selectObject: mono_id
spectrum_obj = To Spectrum: "yes"
cog = Get centre of gravity: 2
if cog = undefined or cog <= 0
    cog = 1000
endif

# Spectral-envelope formant landmarks. FormantPath is ANALYSIS ONLY.
# No measured pole or bandwidth is used directly as a synthesis filter.
spectral_warp_available = 0
mean_f2 = 1500
target_f2 = mean_f2 * adjusted_ratio
formant_shape_db = 5 + 15 * scaling_strength
region_fraction = 0.24
region_floor_1 = 180
region_floor_2 = 260
region_floor_3 = 360
region_floor_4 = 450
region_floor_5 = 550
formant_expr$ = ""
formant_terms = 0
valid_formants = 0

if spectral_scaling_mode = 2
    formant_ceiling = min(5500, (nyquist - 50) / 1.22)
    if formant_ceiling >= 1000
        selectObject: mono_id
        formant_path = To FormantPath (burg): time_step_s, 5, formant_ceiling, 0.030, 35, 0.05, 4
        formant_obj = Extract Formant
        for fn from 1 to 5
            selectObject: formant_obj
            formant_'fn' = Get quantile: fn, 0, 0, "Hertz", 0.5
            old_'fn' = formant_'fn'
            target_'fn' = formant_'fn'
            if formant_'fn' <> undefined and formant_'fn' > 0
                valid_formants = valid_formants + 1
                target_'fn' = formant_'fn' * adjusted_ratio
                if target_'fn' > nyquist - 80
                    target_'fn' = nyquist - 80
                endif
                if target_'fn' < 80
                    target_'fn' = 80
                endif
            endif
        endfor
        removeObject: formant_path, formant_obj

        if formant_2 <> undefined and formant_2 > 0
            mean_f2 = formant_2
            target_f2 = target_2
        endif

        if valid_formants >= 2
            for fn from 1 to 5
                if old_'fn' <> undefined and old_'fn' > 0 and abs(target_'fn' - old_'fn') > 0.5
                    if fn = 1
                        floor_w = region_floor_1
                    elsif fn = 2
                        floor_w = region_floor_2
                    elsif fn = 3
                        floor_w = region_floor_3
                    elsif fn = 4
                        floor_w = region_floor_4
                    else
                        floor_w = region_floor_5
                    endif
                    env_width = max(floor_w, old_'fn' * region_fraction)
                    if env_width > 900
                        env_width = 900
                    endif
                    if formant_terms > 0
                        formant_expr$ = formant_expr$ + " + "
                    endif
                    formant_expr$ = formant_expr$ + fixed$(formant_shape_db, 4) +
                        ... " * (exp(-0.5*((x-" + fixed$(target_'fn', 3) + ")/" +
                        ... fixed$(env_width, 3) + ")^2) - exp(-0.5*((x-" +
                        ... fixed$(old_'fn', 3) + ")/" + fixed$(env_width, 3) + ")^2))"
                    formant_terms = formant_terms + 1
                endif
            endfor
            if formant_terms > 0
                spectral_warp_available = 1
            endif
        endif
    endif

    if spectral_warp_available = 0
        appendInfoLine: "  WARNING: insufficient reliable formant landmarks; spectral warp skipped."
    else
        appendInfoLine: "  Spectral landmarks: ", valid_formants, " | shape limit +/-",
            ... fixed$(formant_shape_db, 1), " dB | one FFT per channel"
    endif
endif

appendInfoLine: "  Mean F0: ", fixed$(mean_f0, 1), " Hz (measured range ",
    ... fixed$(f0_min, 1), "-", fixed$(f0_max, 1), " Hz)"
appendInfoLine: "  Mean intensity: ", fixed$(mean_intensity, 1), " dB"
appendInfoLine: "  Spectral centre of gravity: ", fixed$(cog, 1), " Hz"
appendInfoLine: ""

appendInfoLine: "PHASE 2: Golden time structure"
appendInfoLine: "  Duration used: ", fixed$(total_duration, 3), " s"
if varispeed_done
    appendInfoLine: "    (after varispeed; input was ", fixed$(input_duration, 3), " s)"
endif
appendInfoLine: "  T1 (development): ", fixed$(t1, 3), " s | T2 (resolution): ",
    ... fixed$(t2, 3), " s"
appendInfoLine: "  Climax at: ", fixed$(climax_time, 3), " s"
appendInfoLine: ""

upper_pitch_factor = 1 + scaling_strength * (phi - 1)
lower_pitch_factor = 1 - scaling_strength * (1 - phi_inv)

delta_intensity = intensity_stddev * 2
peak_intensity = mean_intensity + delta_intensity * (phi - 1)
soft_intensity = mean_intensity - delta_intensity * phi_inv

# Filter band, now genuinely derived from phi and from cog.
# v2.3 used 0.3, 0.5 and 20 + 30 * (1 - strength) - no phi anywhere,
# while calling itself "phi-scaled bandwidth".
filter_exp = 1 + scaling_strength
gentle_lower = max(50, cog / phi ^ filter_exp)
gentle_upper = min(nyquist * 0.95, cog * phi ^ filter_exp)
if gentle_upper <= gentle_lower + 50
    gentle_upper = min(nyquist * 0.95, gentle_lower + 50)
endif
filter_smoothing = max(20, (gentle_upper - gentle_lower) * 0.1)

base_vibrato_rate = mean_f0 / (phi * 40)
rate_1 = base_vibrato_rate
rate_2 = base_vibrato_rate * phi_inv

# Panning speed accelerates by phi. v2.3 used 0.5/phi to 0.5*phi,
# which is a ratio of phi^2 = 2.618, while reporting "x phi".
pan_speed_base = 0.5 / phi
pan_speed_climax = pan_speed_base * phi
max_width_pct = scaling_strength * 100

appendInfoLine: "PHASE 3: phi-derived targets"
if apply_pitch_architecture
    appendInfoLine: "  Pitch: T1 = x", fixed$(upper_pitch_factor, 3), " | T2 = x",
        ... fixed$(lower_pitch_factor, 3)
endif
if spectral_scaling_mode = 2
    appendInfoLine: "  Spectral formant warp: x", fixed$(adjusted_ratio, 3), " (F2 landmark ",
        ... fixed$(mean_f2, 0), " -> ", fixed$(target_f2, 0), " Hz), duration preserved"
elsif spectral_scaling_mode = 3
    appendInfoLine: "  Varispeed: x", fixed$(adjusted_ratio, 3), " (already applied)"
endif
if apply_spectral_filtering
    appendInfoLine: "  Filter band: ", fixed$(gentle_lower, 0), "-", fixed$(gentle_upper, 0),
        ... " Hz (cog / phi^", fixed$(filter_exp, 2), " to cog * phi^", fixed$(filter_exp, 2), ")"
endif
if apply_golden_panning
    appendInfoLine: "  Auto-pan: excursion blooms to ", fixed$(max_width_pct, 0),
        ... "% at ", fixed$(climax_time, 2), " s"
    appendInfoLine: "    Speed ", fixed$(pan_speed_base, 3), " -> ",
        ... fixed$(pan_speed_climax, 3), " Hz (x phi)"
    appendInfoLine: "    This is auto-panning of one signal, not stereo widening."
endif
appendInfoLine: ""

# ============================================================
# PHASE 4: Per-channel processing
# ============================================================
appendInfoLine: "PHASE 4: Applying transformations to ", n_channels, " channel(s)..."

t1$ = fixed$(t1, 9)
t2$ = fixed$(t2, 9)
climax$ = fixed$(climax_time, 9)
soft$ = fixed$(soft_intensity, 6)
peak$ = fixed$(peak_intensity, 6)
mean_int$ = fixed$(mean_intensity, 6)

for ch from 1 to n_channels
    if n_channels = 1
        selectObject: work_sound
        chan = Copy: "gr_ch"
    else
        selectObject: work_sound
        chan = Extract one channel: ch
    endif

    # --- Pitch architecture ---
    if apply_pitch_architecture
        selectObject: chan
        manip_obj = To Manipulation: time_step_s, pitch_floor_Hz, pitch_ceiling_Hz
        Extract pitch tier
        pitch_tier = selected("PitchTier")
        n_points = Get number of points
        for i to n_points
            t = Get time from index: i
            f0 = Get value at index: i
            if t <= t1
                progress = t / t1
                scale_factor = 1 + progress * (upper_pitch_factor - 1)
            else
                progress = (t - t1) / t2
                scale_factor = upper_pitch_factor - progress * (upper_pitch_factor - lower_pitch_factor)
            endif
            new_f0 = f0 * scale_factor
            new_f0 = max(pitch_floor_Hz, min(pitch_ceiling_Hz, new_f0))
            Remove point: i
            Add point: t, new_f0
        endfor
        selectObject: manip_obj
        plusObject: pitch_tier
        Replace pitch tier
        selectObject: manip_obj
        Get resynthesis (overlap-add)
        pitched = selected("Sound")
        removeObject: manip_obj, pitch_tier, chan
        chan = pitched
    endif

    # --- Intensity structure ---
    # No Scale peak here. v2.3 normalized inside this stage and again at
    # the end, which hid the envelope it had just applied.
    if apply_intensity_structure
        selectObject: chan
        Formula: "if x <= " + climax$ + " then self * 10^((( " + soft$ + " + (" + peak$ +
            ... " - " + soft$ + ") * (x / " + climax$ + ")) - " + mean_int$ +
            ... ") / 20) else self * 10^((( " + peak$ + " - (" + peak$ + " - " + soft$ +
            ... ") * ((x - " + climax$ + ") / " + t2$ + ")) - " + mean_int$ + ") / 20) fi"
    endif

    # --- Static spectral-envelope formant warp (duration/pitch preserving) ---
    # The same smooth real-valued gain multiplies real and imaginary FFT rows,
    # so complex-spectrum phase is preserved. Nothing here is an LPC pole.
    if spectral_scaling_mode = 2 and spectral_warp_available = 1
        selectObject: chan
        warp_dur = Get total duration
        warp_spec = To Spectrum: "yes"
        selectObject: warp_spec
        warp_limit$ = fixed$(formant_shape_db, 4)
        Formula: "self * 10^(min(" + warp_limit$ + ",max(-" + warp_limit$ + "," + formant_expr$ + "))/20)"
        selectObject: warp_spec
        warp_full = To Sound
        removeObject: warp_spec
        selectObject: warp_full
        warped = Extract part: 0, warp_dur, "rectangular", 1, "no"
        removeObject: warp_full, chan
        chan = warped
    endif

    # --- Spectral filtering ---
    if apply_spectral_filtering
        selectObject: chan
        filtered = Filter (pass Hann band): gentle_lower, gentle_upper, filter_smoothing
        selectObject: chan
        Formula: "self * " + fixed$(1 - scaling_strength * 0.5, 6) + " + object[" +
            ... string$(filtered) + ", 1, col] * " + fixed$(scaling_strength * 0.5, 6)
        removeObject: filtered
    endif

    # --- Micro modulation ---
    if apply_micro_modulation
        selectObject: chan
        manip_obj = To Manipulation: time_step_s, pitch_floor_Hz, pitch_ceiling_Hz
        Extract pitch tier
        pitch_tier = selected("PitchTier")
        depth_cents = 20 * scaling_strength
        n_points = Get number of points
        for i to n_points
            t = Get time from index: i
            f0 = Get value at index: i
            mod_1 = sin(2 * pi * rate_1 * t)
            mod_2 = sin(2 * pi * rate_2 * t)
            combined_mod = (mod_1 + 0.5 * mod_2) / 1.5
            cents_offset = depth_cents * combined_mod
            new_f0 = f0 * 2 ^ (cents_offset / 1200)
            Remove point: i
            Add point: t, new_f0
        endfor
        selectObject: manip_obj
        plusObject: pitch_tier
        Replace pitch tier
        selectObject: manip_obj
        Get resynthesis (overlap-add)
        vibed = selected("Sound")
        removeObject: manip_obj, pitch_tier, chan
        chan = vibed
    endif

    chOut[ch] = chan
    appendInfo: "."
endfor
appendInfoLine: ""

# --- Assemble ---
if n_channels = 1
    selectObject: chOut[1]
    processed = Copy: "gr_processed"
    removeObject: chOut[1]
else
    selectObject: chOut[1]
    out_dur = Get total duration
    Create Sound from formula: "gr_processed", n_channels, 0, out_dur, sample_rate, "0"
    processed = selected("Sound")
    for ch from 1 to n_channels
        selectObject: processed
        Formula (part): 0, out_dur, ch, ch,
            ... "object[" + string$(chOut[ch]) + ", 1, col]"
    endfor
    for ch from 1 to n_channels
        removeObject: chOut[ch]
    endfor
endif

# ============================================================
# PHASE 5: Golden auto-pan
# ============================================================
if apply_golden_panning
    appendInfoLine: "PHASE 5: Golden auto-pan..."

    selectObject: processed
    pan_dur = Get total duration

    leftTier = Create IntensityTier: "left_pan", 0, pan_dur
    rightTier = Create IntensityTier: "right_pan", 0, pan_dur

    pan_steps = 200
    phase_accum = 0
    for i from 0 to pan_steps
        t = i * pan_dur / pan_steps
        if t <= t1
            width = t / t1
            current_speed = pan_speed_base + (pan_speed_climax - pan_speed_base) * (t / t1)
        else
            width = 1 - (t - t1) / t2
            current_speed = pan_speed_climax - (pan_speed_climax - pan_speed_base) * ((t - t1) / t2)
        endif
        if width < 0
            width = 0
        endif
        width = width * scaling_strength
        phase_accum = phase_accum + current_speed * (pan_dur / pan_steps)
        osc = sin(2 * pi * phase_accum)
        pan = 0.5 + (osc * 0.5 * width)
        angle = pan * pi / 2
        gainL = cos(angle)
        gainR = sin(angle)
        selectObject: leftTier
        Add point: t, 20 * log10(gainL + 0.000001)
        selectObject: rightTier
        Add point: t, 20 * log10(gainR + 0.000001)
    endfor

    if n_channels = 1
        selectObject: processed
        leftCh = Copy: "L"
        selectObject: processed
        rightCh = Copy: "R"
        selectObject: leftCh
        plusObject: leftTier
        leftRes = Multiply: "no"
        selectObject: rightCh
        plusObject: rightTier
        rightRes = Multiply: "no"
        selectObject: leftRes
        plusObject: rightRes
        panned = Combine to stereo
        removeObject: leftCh, rightCh, leftRes, rightRes, processed
        processed = panned
        appendInfoLine: "  Mono input expanded to stereo"
    else
        # Existing channels are kept. The pan gains are applied to
        # channels 1 and 2; anything beyond is passed through, since
        # there is no defined golden placement for it.
        selectObject: processed
        p1 = Extract one channel: 1
        plusObject: leftTier
        p1r = Multiply: "no"
        selectObject: processed
        p2 = Extract one channel: 2
        plusObject: rightTier
        p2r = Multiply: "no"

        selectObject: processed
        Formula (part): 0, pan_dur, 1, 1, "object[" + string$(p1r) + ", 1, col]"
        Formula (part): 0, pan_dur, 2, 2, "object[" + string$(p2r) + ", 1, col]"
        removeObject: p1, p2, p1r, p2r
        appendInfoLine: "  Pan gains applied to channels 1 and 2; ", n_channels,
            ... " channels preserved"
    endif
    removeObject: leftTier, rightTier
endif

# ============================================================
# PHASE 6: Output level
# ============================================================
selectObject: processed
pre_level_peak = Get absolute extremum: 0, 0, "None"
pre_level_rms = Get root-mean-square: 0, 0
level_gain = 1
level_action$ = "natural level"

if component_count = 0
    level_action$ = "bypass - no components enabled"
elsif output_level_mode = 2
    if pre_level_peak > ceiling_peak and pre_level_peak > 0
        Scale peak: ceiling_peak
        level_gain = ceiling_peak / pre_level_peak
        level_action$ = "ceiling applied"
    else
        level_action$ = "ceiling not needed"
    endif
elsif output_level_mode = 3
    if pre_level_rms > 0 and input_rms > 0
        level_gain = input_rms / pre_level_rms
        selectObject: processed
        Formula: "self * " + string$(level_gain)
        level_action$ = "matched to input RMS"
    endif
elsif output_level_mode = 4
    if pre_level_peak > 0
        Scale peak: ceiling_peak
        level_gain = ceiling_peak / pre_level_peak
        level_action$ = "peak normalized"
    endif
endif

selectObject: processed
out_peak = Get absolute extremum: 0, 0, "None"
final_duration = Get total duration
out_channels = Get number of channels

# ============================================================
# VISUALIZATION  (drawn at t = 0, before the domain is restored)
# ============================================================
if draw_visualization
    Erase all

    if apply_golden_panning
        panStr$ = "auto-pan to " + fixed$(max_width_pct, 0) + "%"
    else
        panStr$ = "no panning"
    endif
    if spectral_scaling_mode = 1
        specStr$ = "no spectral warp"
    elsif spectral_scaling_mode = 2
        specStr$ = "spectral-envelope warp x" + fixed$(adjusted_ratio, 2)
    else
        specStr$ = "varispeed x" + fixed$(adjusted_ratio, 2)
    endif

    # --- Title ---
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Golden Ratio Processor##"
    Font size: 7
    Colour: "{0.40, 0.40, 0.50}"
    Text: 0.5, "centre", -0.30, "half",
        ... orig_name$ + "  |  " + presetName$
        ... + "  |  " + specStr$
        ... + "  |  " + panStr$
        ... + "  |  " + string$(n_channels) + " ch in, " + string$(out_channels) + " out"

    # --- Input waveform (the work copy, all channels) ---
    Select outer viewport: 0, 4, 0.6, 2.0
    Select inner viewport: 0.6, 3.75, 0.7, 1.95
    selectObject: work_sound
    viz_in_peak = Get absolute extremum: 0, 0, "None"
    viz_amp = max(viz_in_peak, out_peak)
    if viz_amp < 0.001
        viz_amp = 0.001
    endif
    viz_amp = viz_amp * 1.1

    selectObject: work_sound
    Colour: "{0.60, 0.60, 0.60}"
    Draw: 0, total_duration, -viz_amp, viz_amp, "no", "Curve"
    Axes: 0, total_duration, -viz_amp, viz_amp
    Colour: "{0.80, 0.30, 0.30}"
    Dotted line
    Draw line: climax_time, -viz_amp, climax_time, viz_amp
    Solid line
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"
    Text top: "no", "Input, " + string$(n_channels) + " ch (shared scale)"

    # --- Auto-pan architecture ---
    Select outer viewport: 4, 8, 0.6, 2.0
    Select inner viewport: 4.55, 7.7, 0.7, 1.95
    Axes: 0, total_duration, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, total_duration, 0, 1

    if apply_golden_panning
        # The actual pan position, not only its envelope. v2.3 drew the
        # width envelope alone and called it the panning.
        n_viz = 400
        ph_v = 0
        prev_set = 0
        for i from 0 to n_viz
            t_ev = i * total_duration / n_viz
            if t_ev <= t1
                w_v = t_ev / t1
                s_v = pan_speed_base + (pan_speed_climax - pan_speed_base) * (t_ev / t1)
            else
                w_v = 1 - (t_ev - t1) / t2
                s_v = pan_speed_climax - (pan_speed_climax - pan_speed_base) * ((t_ev - t1) / t2)
            endif
            if w_v < 0
                w_v = 0
            endif
            w_v = w_v * scaling_strength
            ph_v = ph_v + s_v * (total_duration / n_viz)
            pan_v = 0.5 + sin(2 * pi * ph_v) * 0.5 * w_v

            Colour: "{0.90, 0.85, 0.70}"
            Line width: 1
            if prev_set = 1
                Draw line: t_prev_v, 0.5 + w_prev_v * 0.5, t_ev, 0.5 + w_v * 0.5
                Draw line: t_prev_v, 0.5 - w_prev_v * 0.5, t_ev, 0.5 - w_v * 0.5
                Colour: "{0.20, 0.45, 0.75}"
                Line width: 1.5
                Draw line: t_prev_v, pan_prev_v, t_ev, pan_v
            endif
            t_prev_v = t_ev
            w_prev_v = w_v
            pan_prev_v = pan_v
            prev_set = 1
        endfor
        Line width: 1
        Colour: "{0.75, 0.75, 0.75}"
        Draw line: 0, 0.5, total_duration, 0.5
    else
        Font size: 8
        Colour: "{0.50, 0.50, 0.50}"
        Text: total_duration / 2, "centre", 0.5, "half", "(Panning off)"
    endif

    Colour: "{0.80, 0.30, 0.30}"
    Dotted line
    Draw line: climax_time, 0, climax_time, 1
    Solid line
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Pan position"
    Text top: "no", "Auto-pan: position (blue) inside its bloom envelope"

    # --- Output waveform ---
    Select outer viewport: 0, 8, 2.1, 3.5
    Select inner viewport: 0.6, 7.7, 2.2, 3.4
    selectObject: processed
    Colour: "{0.30, 0.60, 0.50}"
    Draw: 0, total_duration, -viz_amp, viz_amp, "no", "Curve"
    Axes: 0, total_duration, -viz_amp, viz_amp
    Colour: "{0.80, 0.30, 0.30}"
    Dotted line
    Draw line: climax_time, -viz_amp, climax_time, viz_amp
    Solid line
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Output, " + fixed$(final_duration, 3) + " s (same axis as input)"

    # --- Summary ---
    Select outer viewport: 0, 8, 3.6, 4.4
    Select inner viewport: 0.6, 7.7, 3.65, 4.35
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.78, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.48, "half",
        ... "phi = " + fixed$(phi, 4)
        ... + "  |  T1 = " + fixed$(t1, 3) + " s  T2 = " + fixed$(t2, 3) + " s"
        ... + "  |  Climax " + fixed$(climax_time, 3) + " s"
        ... + "  |  In " + fixed$(input_duration, 3) + " s -> out " + fixed$(final_duration, 3) + " s"
        ... + "  |  " + specStr$
    Text: 0.02, "left", 0.18, "half",
        ... "Pitch T1 x" + fixed$(upper_pitch_factor, 2) + " / T2 x" + fixed$(lower_pitch_factor, 2)
        ... + "  |  Filter " + fixed$(gentle_lower, 0) + "-" + fixed$(gentle_upper, 0) + " Hz"
        ... + "  |  " + panStr$
        ... + "  |  Peak " + fixed$(input_peak, 3) + " -> " + fixed$(out_peak, 3)
        ... + "  |  " + level_action$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# Restore the source time domain and finish
# ============================================================
selectObject: processed
if original_xmin <> 0
    Shift times to: "start time", original_xmin
endif
Rename: orig_name$ + "_GoldenRatio_" + presetName$
final_name$ = selected$("Sound")

removeObject: pitch_obj, intensity_obj, spectrum_obj, mono_id, work_sound

appendInfoLine: ""
appendInfoLine: "=== Complete ==="
appendInfoLine: "Output: ", final_name$
appendInfoLine: "  Duration: ", fixed$(input_duration, 3), " s -> ",
    ... fixed$(final_duration, 3), " s"
appendInfoLine: "  Channels: ", n_channels, " -> ", out_channels
appendInfoLine: "  Peak: ", fixed$(input_peak, 4), " -> ", fixed$(out_peak, 4),
    ... " (", level_action$, ")"
if output_level_mode <> 4 and out_peak > 1
    appendInfoLine: "  WARNING: peak exceeds 1.0 and will clip when saved to integer PCM."
endif

selectObject: processed
if play_result
    if out_peak > 1
        appendInfoLine: "Playing a scaled copy (peak exceeds 1.0)..."
        playCopy = Copy: "play_safe"
        Scale peak: 0.95
        Play
        removeObject: playCopy
    else
        Play
    endif
endif

selectObject: processed
