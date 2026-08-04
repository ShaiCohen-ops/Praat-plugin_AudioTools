# ============================================================
# Praat AudioTools - Time-domain RMS Envelope Follower
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Time-domain RMS Envelope Follower
#
#   Detection chain (Causal mode):
#     per-channel square -> mean power across channels -> optional
#     downsampling of the POWER signal -> causal attack/release
#     recursion -> square root
#
# Usage:
#   Select a Sound object in Praat and run this script.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v1.1:
#   - Replaced non-ASCII box-drawing/dash characters with ASCII for
#     console portability.
#   - Extract mode emits silence (not DC) when no signal exceeds threshold.
#   - Transfer mode documents the donor/recipient duration behaviour and
#     notes it in the stats when the recipient is longer than the donor.
#
# Changelog v1.2:
#   - Attack and Release are now real attack and release times. v1.1 built
#     two zero-phase "Filter (pass Hann band)" envelopes and took the max
#     or min of them, which is acausal: with Attack = 5 ms the envelope
#     started rising about 92 ms BEFORE the transient and took ~98 ms to
#     go 10%->90%. The default detector is now a causal one-pole
#     recursion with separate attack and release coefficients. The old
#     behaviour is preserved as Detector_mode = "Zero-phase (legacy)",
#     which is honestly a dual-timescale smoother, not a follower.
#   - Per-channel power before channel linking. v1.1 ran "Convert to mono"
#     and squared afterwards, so anti-phase stereo (L = s, R = -s)
#     cancelled to an envelope of exactly 0 - the detector saw silence
#     while both channels were loud. Squaring now happens first and the
#     mono fold averages POWER.
#   - Downsampling moved after rectification. v1.1 resampled the audio
#     first, and Resample anti-alias filters, so at the default 16 kHz a
#     12 kHz tone gave an envelope peak of 0 (0.99 with downsampling off).
#     The power signal is what gets decimated now, so full-band energy
#     reaches the detector at any processing rate.
#   - No-signal case fixed for every mode. Below threshold the envelope
#     used to sit at a constant threshold floor; Gate then attenuated the
#     source and Scale peak pushed it back up, so a -60 dB tone came out
#     at peak 0.99 through a -40 dB gate. The envelope is now forced to 0
#     when nothing exceeds threshold (Duck therefore passes at 1).
#   - Peak normalization is optional and OFF by default (was an
#     unconditional Scale peak in all five modes).
#   - Transfer maps by relative time. object(env, x) used the recipient's
#     ABSOLUTE time, so a donor in [0,1] with a recipient in [5,6] read
#     entirely outside the donor's domain and the output was silent.
#   - Range_dB renamed Input_span_above_threshold_dB, which is what it
#     always was: the input span over which the envelope rises 0 -> 1.
#     It is not closed-gate attenuation and not an expander ratio.
#   - Panel 1 no longer draws a memoryless transfer curve for Reverse and
#     Transfer, where none exists; those modes get the applied gain
#     envelope instead. Panel 2 draws source and envelope at their true
#     relative scale (v1.1 normalized each separately to 0.9 and 0.8).
#   - Parameter validation, and Peak is reported as an absolute value
#     (a constant -0.5 input used to report "Peak: -0.9900").
#
# Changelog v1.3:
#   - Input_span_above_threshold_dB now does what it says. v1.2 computed
#     the top of the mapping range as min(env_max, threshold + span), so
#     whenever the envelope peak fell below the declared top - which the
#     default -40 dB + 60 dB makes almost certain, since that top is
#     +20 dBFS - the file's own loudest point was mapped to gain 1 and
#     the span had no effect: constant tones at 0.02, 0.05, 0.10 and 0.50
#     all came out at gain 1.0. The top is now fixed by the parameter.
#     The old adaptive behaviour is available as
#     Normalize_envelope_to_detected_peak, off by default.
#   - Attack and Release are reported as POWER-domain time constants,
#     because the recursion runs before the square root. The amplitude
#     figures are attack 10%-90% = 1.6507 tau and release 90%-10% =
#     4.3945 tau, not the ln(9) tau v1.2 printed for both.
#   - The envelope's start condition is now a documented choice.
#     Apply_attack_at_file_start (default off) initialises the envelope
#     to 0 so a file that opens on a transient still climbs through the
#     attack; off keeps v1.2's behaviour of passing that transient.
#   - Envelope clamped to 0..1 after resampling, and the interpolated
#     gain read is clamped where it is applied (measured Extract peaks of
#     1.0008-1.0012 before this).
#   - Visualization restyled to the AudioTools house layout: 8-inch
#     canvas, inner viewports at 0.6/7.7, bold panel headers, library
#     palette, and a grey summary panel at the bottom. The half-width
#     top panel, the bare "Silver"/"Red"/"Black" colours and the missing
#     title and summary were this script's own, not the library's.
#
# Naming note:
#   square -> power-domain attack/release -> square root is a standard
#   power-based follower, but it is not a fixed-window RMS. On a 0.5-peak
#   sine the true RMS is 0.3536 while this envelope averages about 0.445
#   at a 100 Hz processing rate. "Power-domain Attack/Release Envelope
#   Follower" describes the chain more exactly than "RMS".
# ============================================================

form Time-domain RMS Envelope Follower
    # --- Mode & Selection ---
    optionmenu Mode: 2
        option Extract (envelope only)
        option Gate / Expand
        option Reverse (swell/ghost)
        option Duck (inverse)
        option Transfer (from donor)
        
    # --- Presets (New!) ---
    optionmenu Preset: 1
        option Custom (use settings below)
        option Snappy (Percussion)
        option Smooth (Vocals/Speech)
        option Sustain (Pads/Texture)
        option Crunch (Aggressive)
    
    comment -------------------------------------------------------------------
    comment Transfer: Select 2 sounds (1=Donor, 2=Recipient). Others: Select 1.
    
    # --- Envelope Timing ---
    optionmenu Detector_mode: 1
        option Causal attack/release
        option Zero-phase smoothing (legacy v1.1)
    positive Attack_time_ms 5
    positive Release_time_ms 50
    comment (POWER-domain time constants; in amplitude the attack 10%-90%
    comment  is about 1.65x and the release 90%-10% about 4.39x these values)
    boolean Apply_attack_at_file_start 0
    
    # --- Threshold & Shaping ---
    real Threshold_dB -40
    positive Input_span_above_threshold_dB 60
    comment (input span over which the envelope rises 0 -> 1)
    boolean Normalize_envelope_to_detected_peak 0
    comment (v1.2 behaviour: maps the loudest point in this file to gain 1)
    positive Curve_exponent 1.0
    
    # --- Performance & Output ---
    boolean Use_downsampling 1
    positive Processing_sample_rate 16000
    boolean Peak_normalize_output 0
    positive Normalization_peak 0.99
    boolean Show_visualization 1
    boolean Show_statistics 1
    boolean Play_after_processing 1
endform

# ============================================================
# 0. PRESET LOGIC (New!)
# ============================================================

# If a preset is selected (not Custom), overwrite variables
if preset = 2
    # Snappy (Percussion)
    attack_time_ms = 2
    release_time_ms = 30
    threshold_dB = -30
    input_span_above_threshold_dB = 60
    curve_exponent = 0.5
elsif preset = 3
    # Smooth (Vocals)
    attack_time_ms = 20
    release_time_ms = 200
    threshold_dB = -45
    input_span_above_threshold_dB = 40
    curve_exponent = 1.0
elsif preset = 4
    # Sustain (Pads)
    attack_time_ms = 200
    release_time_ms = 800
    threshold_dB = -50
    input_span_above_threshold_dB = 30
    curve_exponent = 1.5
elsif preset = 5
    # Crunch (Aggressive)
    attack_time_ms = 1
    release_time_ms = 10
    threshold_dB = -20
    input_span_above_threshold_dB = 80
    curve_exponent = 0.3
endif

# ============================================================
# 1. VALIDATION & SETUP
# ============================================================

n_selected = numberOfSelected("Sound")

# Validate selection based on mode
if mode = 5
    # Transfer mode requires exactly 2 sounds
    if n_selected <> 2
        exitScript: "Transfer mode requires exactly TWO Sound objects:" + newline$ +
        ... "  1st selected = Envelope DONOR" + newline$ +
        ... "  2nd selected = Sound RECIPIENT"
    endif
    donor_id = selected("Sound", 1)
    recipient_id = selected("Sound", 2)
    donor_name$ = selected$("Sound", 1)
    recipient_name$ = selected$("Sound", 2)
    source_id = donor_id
    source_name$ = donor_name$
else
    # All other modes require exactly 1 sound
    if n_selected <> 1
        exitScript: "Please select exactly ONE Sound object."
    endif
    source_id = selected("Sound")
    source_name$ = selected$("Sound")
endif

# Get source properties
selectObject: source_id
orig_sr = Get sampling frequency
n_channels = Get number of channels
duration = Get total duration
recipient_dur = duration

# --- Parameter validation ---
if input_span_above_threshold_dB <= 0
    exitScript: "Input_span_above_threshold_dB must be greater than 0 dB: it is the " +
    ... "input range over which the envelope rises from 0 to 1."
endif

if normalization_peak <= 0 or normalization_peak > 1
    exitScript: "Normalization_peak must be greater than 0 and at most 1 (got " +
    ... fixed$(normalization_peak, 4) + ")."
endif

if use_downsampling and processing_sample_rate < 1000
    exitScript: "Processing_sample_rate of " + fixed$(processing_sample_rate, 0) +
    ... " Hz is too low to resolve an amplitude envelope. Use at least 1000 Hz, " +
    ... "or turn Use_downsampling off."
endif

# Mode suffix for output naming
if mode = 1
    suffix$ = "_Envelope"
    mode$ = "Extract"
elsif mode = 2
    suffix$ = "_Gated"
    mode$ = "Gate/Expand"
elsif mode = 3
    suffix$ = "_Reverse"
    mode$ = "Reverse"
elsif mode = 4
    suffix$ = "_Ducked"
    mode$ = "Duck"
else
    suffix$ = "_Transfer"
    mode$ = "Transfer"
endif

# Preset name for display
if preset = 1
    preset$ = "Custom"
elsif preset = 2
    preset$ = "Snappy"
elsif preset = 3
    preset$ = "Smooth"
elsif preset = 4
    preset$ = "Sustain"
else
    preset$ = "Crunch"
endif

if detector_mode = 1
    detector$ = "Causal attack/release"
else
    detector$ = "Zero-phase (legacy)"
endif

# ============================================================
# 2. POWER SIGNAL (rectify BEFORE any channel fold or decimation)
# ============================================================
# v1.1 folded to mono and then squared, so anti-phase channels cancelled
# to nothing. Squaring first means the fold averages power, which cannot
# cancel: p(t) = (xL^2 + xR^2) / 2.

if mode = 5
    selectObject: donor_id
else
    selectObject: source_id
endif

work_id = Copy: "power_signal"
selectObject: work_id
Formula: "self * self"

if n_channels > 1
    mono_power_id = Convert to mono
    removeObject: work_id
    work_id = mono_power_id
endif

# ============================================================
# 3. OPTIONAL DOWNSAMPLING (of the power signal, not the audio)
# ============================================================
# v1.1 resampled the audio first. Resample anti-alias filters, so every
# component above the processing Nyquist was discarded before it could
# contribute any energy. Decimating the power signal instead is safe:
# the energy has already been measured.

selectObject: work_id
current_sr = Get sampling frequency
did_downsample = 0
env_sr = current_sr

if use_downsampling and processing_sample_rate < current_sr
    downsampled_id = Resample: processing_sample_rate, 50
    removeObject: work_id
    work_id = downsampled_id
    did_downsample = 1
    env_sr = processing_sample_rate
    # Anti-alias ringing can push a power signal slightly negative
    selectObject: work_id
    Formula: "max(self, 0)"
endif

# ============================================================
# 4. RMS ENVELOPE EXTRACTION
# ============================================================

selectObject: work_id
env_id = Copy: "envelope_raw"

attack_sec = attack_time_ms / 1000
release_sec = release_time_ms / 1000

# Reported for the legacy path and for the stats
attack_hz = 1000 / (2 * pi * attack_time_ms)
release_hz = 1000 / (2 * pi * release_time_ms)

if detector_mode = 1
    # --- Causal one-pole attack/release recursion ---
    # env[n] = c * env[n-1] + (1 - c) * p[n], with c chosen by whether the
    # power is rising or falling. Praat's Formula walks the samples in
    # order and writes in place, so self[row, col-1] is the envelope value
    # already computed for the previous sample - that is the recursion.
    # Two-index form on purpose: self[col-1] would cross-reference rows.
    a_coef = exp(-1 / (env_sr * attack_sec))
    r_coef = exp(-1 / (env_sr * release_sec))
    a_gain = 1 - a_coef
    r_gain = 1 - r_coef

    selectObject: env_id
    if apply_attack_at_file_start
        # Envelope initialised to 0, so a file that opens on a loud
        # transient still has to climb through the attack.
        Formula: "if col = 1 then a_gain * self else (if self > self[row, col - 1] then a_coef * self[row, col - 1] + a_gain * self else r_coef * self[row, col - 1] + r_gain * self fi) fi"
    else
        # Default: the envelope starts already tracking the first sample,
        # which preserves a transient that begins at time zero. A signal
        # that starts after some silence still gets the full attack.
        Formula: "if col = 1 then self else (if self > self[row, col - 1] then a_coef * self[row, col - 1] + a_gain * self else r_coef * self[row, col - 1] + r_gain * self fi) fi"
    endif

    # The recursion runs on POWER, and the user hears the square root of
    # it, so the amplitude transition is not ln(9)*tau. For a one-pole
    # power step: amplitude 10%->90% is -ln(0.19)*tau + ln(0.99)*tau and
    # amplitude 90%->10% is -2*ln(0.1)*tau + 2*ln(0.9)*tau.
    attack_1090_ms = 1.6507 * attack_time_ms
    release_9010_ms = 4.3945 * release_time_ms
else
    # --- Legacy v1.1 zero-phase smoothing ---
    # Kept for sonic continuity. This is NOT an attack/release follower:
    # the filters are zero-phase, so the envelope responds before the
    # event that caused it. The power-domain and channel fixes above
    # still apply - those were bugs, not a sound.
    nyq = env_sr / 2
    primary_hz = max(attack_hz, release_hz)
    secondary_hz = min(attack_hz, release_hz)
    legacy_clamped = 0
    if primary_hz >= nyq
        primary_hz = 0.45 * env_sr
        legacy_clamped = 1
    endif
    if secondary_hz >= nyq
        secondary_hz = 0.45 * env_sr
        legacy_clamped = 1
    endif

    selectObject: env_id
    filtered_id = Filter (pass Hann band): 0, primary_hz, primary_hz * 0.5
    removeObject: env_id
    env_id = filtered_id

    selectObject: env_id
    if attack_hz <> release_hz
        slow_env_id = Filter (pass Hann band): 0, secondary_hz, secondary_hz * 0.5
        selectObject: env_id
        slow_str$ = string$(slow_env_id)
        if attack_hz > release_hz
            Formula: "if self > object(" + slow_str$ + ", x) then self else object(" + slow_str$ + ", x) fi"
        else
            Formula: "if self < object(" + slow_str$ + ", x) then self else object(" + slow_str$ + ", x) fi"
        endif
        removeObject: slow_env_id
    endif

    attack_1090_ms = undefined
    release_9010_ms = undefined
endif

# C. Square root (power -> amplitude)
selectObject: env_id
Formula: "sqrt(abs(self))"

# ============================================================
# 5. THRESHOLD & RANGE PROCESSING
# ============================================================

selectObject: env_id
env_max = Get maximum: 0, 0, "Parabolic"
env_min = Get minimum: 0, 0, "Parabolic"
env_mean = Get mean: 0, 0
env_rms = Get root-mean-square: 0, 0

# Convert threshold/span
threshold_linear = 10 ^ (threshold_dB / 20)
span_linear = 10 ^ (input_span_above_threshold_dB / 20)
env_max_viz = env_max

signal_present = env_max > threshold_linear

# The top of the mapping range is fixed by the declared span. v1.2 used
# min(env_max, upper), so whenever the envelope peak fell below the top
# of the range - which is nearly always, since the default -40 dB + 60 dB
# puts the top at +20 dBFS - the file's own loudest point was mapped to
# gain 1 and the span parameter did nothing. A constant 0.02 tone with a
# -40 dB threshold and a 20 dB span should reach about 0.111, not 1.0.
upper_linear = threshold_linear * span_linear

if normalize_envelope_to_detected_peak
    # Opt-in adaptive contour: the loudest point in THIS file becomes 1,
    # so the mapping is no longer comparable between files.
    denom = min(env_max, upper_linear) - threshold_linear
else
    denom = upper_linear - threshold_linear
endif
if denom = 0
    denom = 1
endif

selectObject: env_id
if signal_present
    Formula: "max(self, threshold_linear)"
    Formula: "(self - threshold_linear) / denom"
    Formula: "min(max(self, 0), 1)"
else
    # Nothing crossed the threshold. v1.1 left the envelope pinned at the
    # threshold floor, so Gate attenuated the source by that factor and
    # the unconditional Scale peak then restored it to full level - a
    # -60 dB tone came out of a -40 dB gate at peak 0.99. A closed gate
    # is a closed gate.
    Formula: "0"
endif

# ============================================================
# 6. ENVELOPE CURVE SHAPING
# ============================================================

selectObject: env_id
if curve_exponent <> 1.0
    Formula: "self ^ curve_exponent"
endif

# ============================================================
# 7. MODE-SPECIFIC PROCESSING
# ============================================================

# Relative-time mapping: the envelope carries the donor's (or source's)
# own time domain, and the recipient may sit somewhere else entirely.
selectObject: env_id
env_start = Get start time

# --- MODE 1: Extract ---
if mode = 1
    selectObject: env_id
    if did_downsample
        result_id = Resample: orig_sr, 50
        Rename: source_name$ + suffix$
        # Resampling overshoots slightly (measured peaks of 1.0008-1.0012);
        # the envelope is defined on 0..1, so put it back.
        Formula: "min(max(self, 0), 1)"
    else
        result_id = Copy: source_name$ + suffix$
    endif
    if peak_normalize_output and signal_present
        Scale peak: normalization_peak
    endif

# --- MODE 2: Gate / Expand ---
elsif mode = 2
    selectObject: source_id
    recip_start = Get start time
    result_id = Copy: source_name$ + suffix$
    env_str$ = string$(env_id)
    Formula: "self * min(max(object(" + env_str$ + ", env_start + (x - recip_start)), 0), 1)"
    if peak_normalize_output
        Scale peak: normalization_peak
    endif

# --- MODE 3: Reverse ---
elsif mode = 3
    selectObject: env_id
    Reverse
    selectObject: source_id
    recip_start = Get start time
    result_id = Copy: source_name$ + suffix$
    env_str$ = string$(env_id)
    Formula: "self * min(max(object(" + env_str$ + ", env_start + (x - recip_start)), 0), 1)"
    if peak_normalize_output
        Scale peak: normalization_peak
    endif

# --- MODE 4: Duck ---
elsif mode = 4
    selectObject: env_id
    Formula: "1 - self"
    selectObject: source_id
    recip_start = Get start time
    result_id = Copy: source_name$ + suffix$
    env_str$ = string$(env_id)
    Formula: "self * min(max(object(" + env_str$ + ", env_start + (x - recip_start)), 0), 1)"
    if peak_normalize_output
        Scale peak: normalization_peak
    endif

# --- MODE 5: Transfer ---
# The donor envelope is sampled by RELATIVE time, so donor and recipient
# no longer have to occupy the same absolute time domain. If the
# recipient is longer than the donor, object() returns 0 past the donor's
# end (output silent there); a longer donor is truncated.
elsif mode = 5
    selectObject: recipient_id
    recipient_dur = Get total duration
    recip_start = Get start time
    result_id = Copy: recipient_name$ + "_from_" + donor_name$
    env_str$ = string$(env_id)
    Formula: "self * min(max(object(" + env_str$ + ", env_start + (x - recip_start)), 0), 1)"
    if peak_normalize_output
        Scale peak: normalization_peak
    endif
endif

# ============================================================
# 8. VISUALIZATION
# ============================================================

if show_visualization
    selectObject: env_id
    if did_downsample
        vis_env_id = Resample: orig_sr, 50
        Formula: "min(max(self, 0), 1)"
    else
        vis_env_id = Copy: "vis_envelope"
    endif

    if mode = 5
        selectObject: recipient_id
    else
        selectObject: source_id
    endif
    vis_source_id = Copy: "vis_source"

    Erase all

    # ---- Title ----
    Select outer viewport: 0, 8, 0, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.62, "half", "##Envelope Follower##"
    Font size: 8
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -1.15, "half",
        ... source_name$ + "  |  " + mode$ + "  |  " + preset$
        ... + "  |  " + detector$
        ... + "  |  thr: " + fixed$(threshold_dB, 0) + " dB"
        ... + "  span: " + fixed$(input_span_above_threshold_dB, 0) + " dB"

    # ---- PANEL 1: mapping curve, or applied gain for the modes that
    #      have no memoryless mapping ----
    Select outer viewport: 0, 8, 0.55, 2.05
    Select inner viewport: 0.6, 7.7, 0.62, 1.98

    if mode = 3 or mode = 5
        # There is no memoryless input->output mapping for these modes:
        # Reverse reads the envelope from a different instant and Transfer
        # reads it from a different Sound. Draw the gain that was actually
        # applied instead of a curve that cannot describe either.
        selectObject: vis_env_id
        vis_env_start = Get start time
        vis_env_end = Get end time
        gain_top = Get maximum: 0, 0, "None"
        if gain_top <= 0
            gain_top = 1
        endif
        gain_top = gain_top * 1.10

        Axes: vis_env_start, vis_env_end, -0.02, gain_top
        Paint rectangle: "{0.96, 0.96, 0.98}", vis_env_start, vis_env_end, -0.02, gain_top

        selectObject: vis_env_id
        Colour: "{0.20, 0.60, 0.35}"
        Line width: 2
        Draw: vis_env_start, vis_env_end, -0.02, gain_top, "no", "Curve"
        Line width: 1

        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Applied gain"
        Text bottom: "yes", "Time (s)"
        Text top: "no", "##Applied Gain Envelope##  (" + mode$ + ")"
        Marks left every: 1, 0.25, "yes", "yes", "no"
    else
        Axes: -60, 0, -60, 0
        Paint rectangle: "{0.96, 0.96, 0.98}", -60, 0, -60, 0

        Colour: "{0.75, 0.75, 0.75}"
        Line width: 1
        grid_line = -50
        while grid_line <= -10
            Draw line: grid_line, -60, grid_line, 0
            Draw line: -60, grid_line, 0, grid_line
            grid_line = grid_line + 10
        endwhile

        Colour: "{0.60, 0.60, 0.60}"
        Line width: 1
        Dashed line
        Draw line: -60, -60, 0, 0
        Solid line

        Colour: "{0.30, 0.30, 0.80}"
        Dashed line
        Draw line: threshold_dB, -60, threshold_dB, 0
        Solid line

        # --- MAPPING CURVE ---
        # Steady state only: attack and release are history-dependent and
        # do not appear here.
        Colour: "{0.20, 0.60, 0.35}"
        Line width: 3

        if normalize_envelope_to_detected_peak
            denom_viz = min(env_max_viz, threshold_linear * span_linear) - threshold_linear
        else
            denom_viz = threshold_linear * span_linear - threshold_linear
        endif
        if denom_viz = 0
            denom_viz = 1
        endif

        in_lev = -60
        prev_out = -60

        while in_lev <= 0
            in_lin = 10 ^ (in_lev / 20)
            sim_env = max(in_lin, threshold_linear)

            if signal_present
                 sim_norm = (sim_env - threshold_linear) / denom_viz
                 sim_norm = min(max(sim_norm, 0), 1)
            else
                 sim_norm = 0
            endif

            if curve_exponent <> 1.0
                sim_norm = sim_norm ^ curve_exponent
            endif

            if mode = 1
                 out_lin = sim_norm
            elsif mode = 4
                 out_lin = in_lin * (1 - sim_norm)
            else
                 out_lin = in_lin * sim_norm
            endif

            out_lev = 20 * log10(out_lin + 1e-10)

            # Clamp to bounds
            if out_lev < -60
                out_lev = -60
            endif
            if out_lev > 0
                out_lev = 0
            endif

            if in_lev > -60
                Draw line: in_lev - 1, prev_out, in_lev, out_lev
            endif
            prev_out = out_lev
            in_lev = in_lev + 1
        endwhile

        Line width: 1
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text bottom: "yes", "Input level (dB)"
        Text left: "yes", "Output level (dB)"
        Text top: "no", "##Steady-State Mapping##  (" + mode$ + ")  |  blue dashes = threshold"
        Marks bottom every: 1, 20, "yes", "yes", "no"
        Marks left every: 1, 20, "yes", "yes", "no"
    endif

    # ---- PANEL 2: source + envelope, true relative scale ----
    Select outer viewport: 0, 8, 2.10, 3.60
    Select inner viewport: 0.6, 7.7, 2.17, 3.53

    selectObject: vis_source_id
    src_peak_viz = Get absolute extremum: 0, 0, "None"
    selectObject: vis_env_id
    env_peak_viz = Get absolute extremum: 0, 0, "None"
    y_top = max(src_peak_viz, env_peak_viz)
    if y_top <= 0
        y_top = 1
    endif
    y_top = y_top * 1.05

    selectObject: vis_source_id
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, -y_top, y_top, "no", "Curve"

    if mode = 5
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Recipient"
        Text top: "no", "##Recipient##  (donor envelope drawn above, on its own time axis)"
    else
        selectObject: vis_env_id
        Colour: "{0.80, 0.35, 0.15}"
        Line width: 2
        Draw: 0, 0, -y_top, y_top, "no", "Curve"

        selectObject: vis_env_id
        Formula: "-self"
        Draw: 0, 0, -y_top, y_top, "no", "Curve"
        Line width: 1

        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Source"
        Text top: "no", "##Source & Envelope##  (true relative scale; orange = envelope)"
    endif

    # ---- PANEL 3: result ----
    Select outer viewport: 0, 8, 3.65, 5.15
    Select inner viewport: 0.6, 7.7, 3.72, 5.08

    selectObject: result_id
    Colour: "{0.18, 0.52, 0.72}"
    Draw: 0, 0, 0, 0, "no", "Curve"

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Result"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "##Result##  " + selected$("Sound")

    # ---- PANEL 4: summary ----
    Select outer viewport: 0, 8, 5.20, 6.30
    Select inner viewport: 0.6, 7.7, 5.27, 6.23
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    selectObject: result_id
    sum_peak = Get absolute extremum: 0, 0, "None"
    sum_rms = Get root-mean-square: 0, 0

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.87, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.65, "half",
        ... "Source: " + source_name$
        ... + "  |  " + fixed$(duration, 3) + " s"
        ... + "  |  " + string$(n_channels) + " ch"
        ... + "  |  " + string$(orig_sr) + " Hz"
        ... + "  |  detection at " + fixed$(env_sr, 0) + " Hz"

    if detector_mode = 1
        timing$ = "Attack: " + fixed$(attack_time_ms, 1) + " ms tau (amp 10-90% " +
        ... fixed$(attack_1090_ms, 1) + " ms)  |  Release: " + fixed$(release_time_ms, 1) +
        ... " ms tau (amp 90-10% " + fixed$(release_9010_ms, 1) + " ms)"
    else
        timing$ = "Zero-phase smoothing: " + fixed$(attack_hz, 1) + " Hz / " +
        ... fixed$(release_hz, 1) + " Hz  |  responds before the event"
    endif
    Text: 0.02, "left", 0.44, "half", timing$

    if normalize_envelope_to_detected_peak
        span$ = "adaptive (file peak -> 1)"
    else
        span$ = "gain 1 at " + fixed$(threshold_dB + input_span_above_threshold_dB, 0) + " dBFS"
    endif
    if peak_normalize_output
        norm$ = "on (" + fixed$(normalization_peak, 2) + ")"
    else
        norm$ = "off"
    endif
    Text: 0.02, "left", 0.23, "half",
        ... "Threshold: " + fixed$(threshold_dB, 0) + " dB"
        ... + "  |  Span: " + fixed$(input_span_above_threshold_dB, 0) + " dB, " + span$
        ... + "  |  Curve: " + fixed$(curve_exponent, 2)
        ... + "  |  Norm: " + norm$
        ... + "  |  Peak: " + fixed$(sum_peak, 3)
        ... + "  RMS: " + fixed$(sum_rms, 4)

    Colour: "Black"
    Draw inner box

    Font size: 10
    Colour: "Black"

    removeObject: vis_env_id, vis_source_id
endif

# ============================================================
# 9. STATISTICS OUTPUT
# ============================================================

if show_statistics
    selectObject: result_id
    result_peak = Get absolute extremum: 0, 0, "None"
    result_rms = Get root-mean-square: 0, 0
    result_duration = Get total duration
    
    result_name$ = selected$("Sound")
    
    writeInfoLine: "======================================================="
    appendInfoLine: "        TIME-DOMAIN RMS ENVELOPE FOLLOWER - STATS"
    appendInfoLine: "======================================================="
    appendInfoLine: ""
    appendInfoLine: "MODE: ", mode$, " (", preset$, ")"
    appendInfoLine: "DETECTOR: ", detector$
    appendInfoLine: ""
    appendInfoLine: "--- Source ---"
    appendInfoLine: "  Name:         ", source_name$
    appendInfoLine: "  Duration:     ", fixed$(duration, 3), " s"
    appendInfoLine: "  Sample rate:  ", orig_sr, " Hz"
    appendInfoLine: "  Channels:     ", n_channels
    appendInfoLine: ""
    appendInfoLine: "--- Envelope Parameters ---"
    if detector_mode = 1
        appendInfoLine: "  Attack:       ", attack_time_ms, " ms POWER-domain time constant"
        appendInfoLine: "                (amplitude 10%-90% approx ", fixed$(attack_1090_ms, 2), " ms)"
        appendInfoLine: "  Release:      ", release_time_ms, " ms POWER-domain time constant"
        appendInfoLine: "                (amplitude 90%-10% approx ", fixed$(release_9010_ms, 2), " ms)"
        if apply_attack_at_file_start
            appendInfoLine: "  Start:        envelope initialised to 0 (attack applies at time zero)"
        else
            appendInfoLine: "  Start:        envelope initialised to the first sample, so a"
            appendInfoLine: "                transient at time zero is passed intact"
        endif
        if attack_sec * env_sr < 2
            appendInfoLine: "                NOTE: attack is under 2 samples at ", fixed$(env_sr, 0),
            ... " Hz - the detector follows the power signal instantly."
        endif
        if release_sec * env_sr < 2
            appendInfoLine: "                NOTE: release is under 2 samples at ", fixed$(env_sr, 0),
            ... " Hz - the detector follows the power signal instantly."
        endif
    else
        appendInfoLine: "  Attack:       ", attack_time_ms, " ms (", fixed$(attack_hz, 1), " Hz)"
        appendInfoLine: "  Release:      ", release_time_ms, " ms (", fixed$(release_hz, 1), " Hz)"
        appendInfoLine: "                Zero-phase: the envelope responds BEFORE the event"
        appendInfoLine: "                that caused it. These are smoothing scales, not"
        appendInfoLine: "                attack and release times."
        if legacy_clamped
            appendInfoLine: "                NOTE: a cutoff exceeded Nyquist at ", fixed$(env_sr, 0),
            ... " Hz and was clamped."
        endif
    endif
    appendInfoLine: "  Threshold:    ", threshold_dB, " dB"
    appendInfoLine: "  Input span:   ", input_span_above_threshold_dB, " dB above threshold (gain 1 at ",
    ... fixed$(threshold_dB + input_span_above_threshold_dB, 1), " dBFS)"
    if normalize_envelope_to_detected_peak
        appendInfoLine: "                ADAPTIVE: the loudest point in this file is mapped to"
        appendInfoLine: "                gain 1, so the mapping is not comparable between files."
    endif
    appendInfoLine: "  Curve:        ", curve_exponent
    appendInfoLine: ""
    appendInfoLine: "--- Raw Envelope Stats (pre-threshold) ---"
    appendInfoLine: "  Max:          ", fixed$(env_max, 6)
    appendInfoLine: "  Min:          ", fixed$(env_min, 6)
    appendInfoLine: "  Mean:         ", fixed$(env_mean, 6)
    appendInfoLine: "  RMS:          ", fixed$(env_rms, 6)
    if not signal_present
        appendInfoLine: "  Nothing exceeded the threshold: envelope forced to 0."
    endif
    appendInfoLine: ""
    appendInfoLine: "--- Result ---"
    appendInfoLine: "  Name:         ", result_name$
    appendInfoLine: "  Peak (abs):   ", fixed$(result_peak, 4)
    appendInfoLine: "  RMS:          ", fixed$(result_rms, 6)
    if peak_normalize_output
        appendInfoLine: "  Peak normalization: ON (target ", fixed$(normalization_peak, 2), ")"
    else
        appendInfoLine: "  Peak normalization: off"
        if result_peak > 1
            appendInfoLine: "  WARNING: peak exceeds 1.0 and will clip on playback or save."
        endif
    endif
    if mode = 5 and recipient_dur > duration + 0.001
        appendInfoLine: "  Note: recipient longer than donor (", fixed$(recipient_dur, 2), "s > ", fixed$(duration, 2), "s); silent past donor end."
    endif
    if did_downsample
        appendInfoLine: "  (Power signal decimated to ", processing_sample_rate, " Hz before detection)"
    endif
    appendInfoLine: ""
    appendInfoLine: "======================================================="
endif

# ============================================================
# 10. PLAYBACK & CLEANUP
# ============================================================

if play_after_processing
    selectObject: result_id
    Play
endif

removeObject: env_id, work_id
selectObject: result_id

if not show_statistics
    writeInfoLine: "Done! Created: ", selected$("Sound")
endif
