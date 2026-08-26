# ============================================================
# Praat AudioTools - Intensity_Envelope_Processor.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.6 (2026)
#
# Description:
#   Multi-mode intensity envelope processor with power shaping,
#   tremolo, gating, time manipulation, and envelope inversion.
#
# Changelog v1.6 (2026):
#   - FIX: Peak normalization now checks for a non-zero output peak before
#     calling Scale peak; fully silent outputs are left unchanged and reported.
#   - FIX: Gate_min/Gate_max are clamped to 0-1 after any min/max swap, and
#     Gate_duty_percent is clamped to 0-100 so the UI and displayed envelope
#     match the actual gain range.
#   - FIX: Synthetic Tremolo/Gate rates are capped below audio Nyquist, and
#     Tremolo/Gate/Random control-Sound construction now has explicit rate and
#     sample-count safety limits instead of allowing arbitrarily huge objects.
#   - FIX: Time Scaling's minimum-output-sample check now estimates samples in
#     the final resampled output (new_duration * original_sample_rate), rather
#     than a product that algebraically collapsed back to the source count.
#   - FIX: Info-window header/reporting now uses appendInfoLine after the first
#     writeInfoLine, so earlier lines are not erased by subsequent writes.
#
# Changelog v1.5 (2026):
#   - VISUALIZATION / UI STANDARDIZATION ONLY. Audio analysis,
#     DSP, scheduling and rendering are unchanged from the
#     previous version.
#   - Adopted the Praat AudioTools 8-inch visualization header,
#     suite typography, neutral panel backgrounds, summary-style
#     reporting and full-page Picture export restoration.
#   - Preserved the script-specific diagnostic / transformation
#     views rather than replacing them with generic plots.
#
# Changelog v1.4 (code-review fixes):
#   - The v1.3 "fine grid" guard had its comparison backwards (it silently
#     coarsened the grid on almost every ordinary-length file). Rather than
#     patch the inequality, Tremolo/Gate/Random no longer use To Intensity
#     at all: they get their own synthetic modulator (Create Sound from
#     formula) at a fixed rate that scales with the requested effect rate.
#     Power Shaping/Inversion are unaffected (still a real 100 Hz-floor
#     Intensity analysis).
#   - Random Modulation now generates one genuine random control point
#     every 1/Random_rate_Hz seconds and interpolates between them, so
#     Random_rate_Hz means what it says. (The old version drew a new
#     random value on every analysis frame and comb-filtered it, so the
#     rate parameter barely affected anything.)
#   - Gate rise/fall width is now capped against the duty cycle itself
#     (min(riseWidth, duty, 1-duty)), not just against 49% of the period,
#     so smoothing can no longer overrun short on/off segments.
#   - Tremolo_center, Tremolo_depth, Gate_min/Gate_max, and Random_depth
#     are validated up front: center is clamped to 0-1, depths to >= 0
#     (Random_depth to 0-1), and Gate_max/Gate_min are swapped if inverted.
#   - The envelope panel in the visualization now uses the Sound's actual
#     start/end time for its axes and unity line, instead of hardcoded
#     0..duration (which misaligned for Sounds that don't start at 0).
#   - Negative Time Shift now reports the requested and actually-applied
#     trim amounts separately, instead of reporting the requested amount
#     even when it was clamped to preserve 1 ms of audio.
#   - Time Scaling now also rejects Scale_factor values that would push
#     the intermediate sampling frequency absurdly high or leave fewer
#     than ~10 output samples (previously only the "too low"/"too long"
#     directions were guarded).
#
# Changelog v1.3 (code-review fixes):
#   - Removed the hidden "Sound & IntensityTier: Multiply" normalization
#     (that command silently rescales its output to 0.9 peak). Envelope
#     modes now multiply the waveform directly with an explicit gain
#     modulator: Formula: ~ self * object(modulator_id, x)
#   - Power Shaping and Envelope Inversion now build a proper
#     multiplicative GAIN (r^(exponent-1) and (1-r)/r) instead of trying
#     to apply the target ratio directly, and both are capped at
#     Max_gain to avoid blowing up near silence.
#   - Time Shift is now audible: positive shift prepends real silence,
#     negative shift trims real samples from the start, using the
#     Sound's own start/end time rather than assuming it starts at 0.
#   - Time Scaling now exitScript's instead of only warning when
#     Scale_factor would produce an unreasonably low sample rate or an
#     excessively long output.
#   - Gate now has explicit 0% and 100% duty special cases.
#   - Tremolo and Gate phase are computed relative to the Sound's own
#     start time, not absolute time 0.
#   - Tremolo, Gate, and Random Modulation are now built on a much
#     finer analysis grid (~0.8 ms steps) than Power Shaping/Inversion
#     (~8 ms steps), since the former don't need real loudness analysis
#     and were being quantized to the coarse grid.
#   - Random_seed is now actually used (random_initializeWithSeedUnsafelyButPredictably)
#     and the generator is reset afterward.
#   - Power Shaping report says "Neutral" (not "Expansion") at Exponent = 1.
#   - Envelope Inversion report describes the gain limit instead of
#     implying a full, unlimited inversion.
#   - Silent input is detected (undefined Intensity maximum) and handled
#     by skipping Power Shaping/Inversion instead of propagating
#     undefined values.
#   - vis_modulator is always cleaned up, even when Visualize is off.
#
# Changelog v1.2:
#   - Fixed Random Modulation smoothing window (was sized by audio SR,
#     not Intensity frame rate)
#
# Changelog v1.1:
#   - Added presets
#   - Added gate duty cycle and smoothing
#   - Added tremolo phase control
#   - Added info output
#   - Improved visualization with comparison
#   - Added random modulation mode
#   - Fixed gating clicks with smoothing
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Intensity Envelope Processor v1.6
    optionmenu Preset 1
        option Custom
        option Soft Compression
        option Hard Expansion
        option Gentle Tremolo
        option Fast Tremolo
        option Rhythmic Chop
        option Smooth Gate
        option Tape Slowdown
        option Reverse Dynamics
        option Random Flutter
    optionmenu Mode 3
        option Power Shaping (dynamics)
        option Sine Modulation (tremolo)
        option Rhythmic Gating (chopper)
        option Time Shift
        option Time Scaling (tape speed)
        option Envelope Inversion
        option Random Modulation
    boolean Normalize 1
    boolean Advanced_settings 0
    boolean Visualize 1
    boolean Play 1
endform
# === Advanced defaults (identical to the v1.4 main-form defaults) ===
exponent = 2.0
tremolo_rate_Hz = 5.0
tremolo_depth = 0.5
tremolo_center = 0.5
tremolo_phase = 0
gate_rate_Hz = 4.0
gate_duty_percent = 50
gate_max = 1.0
gate_min = 0.0
gate_smoothing_ms = 5
shift_seconds = 0.1
scale_factor = 1.5
random_rate_Hz = 8
random_depth = 0.3
random_seed = 0
max_gain = 20

if advanced_settings
    beginPause: "Intensity Envelope Processor v1.6 - Advanced settings"
        comment: "=== Power shaping ==="
        real: "Exponent", "2.0"
        comment: "=== Tremolo ==="
        positive: "Tremolo_rate_Hz", "5.0"
        real: "Tremolo_depth", "0.5"
        real: "Tremolo_center", "0.5"
        real: "Tremolo_phase", "0"
        comment: "=== Rhythmic gate ==="
        positive: "Gate_rate_Hz", "4.0"
        real: "Gate_duty_percent", "50"
        real: "Gate_max", "1.0"
        real: "Gate_min", "0.0"
        positive: "Gate_smoothing_ms", "5"
        comment: "=== Time / random modes ==="
        real: "Shift_seconds", "0.1"
        positive: "Scale_factor", "1.5"
        positive: "Random_rate_Hz", "8"
        real: "Random_depth", "0.3"
        integer: "Random_seed", "0"
        comment: "=== Safety ==="
        positive: "Max_gain", "20"
    clicked = endPause: "Continue", 1
endif

# === INPUT VALIDATION ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

source_id = selected("Sound")
source_name$ = selected$("Sound")

selectObject: source_id
dur = Get total duration
orig_sr = Get sampling frequency
sourceStart = Get start time
sourceEnd = Get end time

if dur <= 0
    exitScript: "Selected Sound has zero or negative duration."
endif

# === APPLY PRESETS ===
if preset = 2
    # Soft Compression
    mode = 1
    exponent = 0.5
    presetName$ = "SoftComp"
elsif preset = 3
    # Hard Expansion
    mode = 1
    exponent = 3.0
    presetName$ = "HardExp"
elsif preset = 4
    # Gentle Tremolo
    mode = 2
    tremolo_rate_Hz = 3
    tremolo_depth = 0.3
    tremolo_center = 0.7
    presetName$ = "GentleTrem"
elsif preset = 5
    # Fast Tremolo
    mode = 2
    tremolo_rate_Hz = 8
    tremolo_depth = 0.5
    tremolo_center = 0.5
    presetName$ = "FastTrem"
elsif preset = 6
    # Rhythmic Chop
    mode = 3
    gate_rate_Hz = 4
    gate_duty_percent = 50
    gate_max = 1
    gate_min = 0
    gate_smoothing_ms = 2
    presetName$ = "RhythmChop"
elsif preset = 7
    # Smooth Gate
    mode = 3
    gate_rate_Hz = 2
    gate_duty_percent = 70
    gate_max = 1
    gate_min = 0.1
    gate_smoothing_ms = 20
    presetName$ = "SmoothGate"
elsif preset = 8
    # Tape Slowdown
    mode = 5
    scale_factor = 2.0
    presetName$ = "TapeSlowdown"
elsif preset = 9
    # Reverse Dynamics
    mode = 6
    presetName$ = "ReverseDyn"
elsif preset = 10
    # Random Flutter
    mode = 7
    random_rate_Hz = 12
    random_depth = 0.25
    presetName$ = "Flutter"
else
    presetName$ = "Custom"
endif

# === VALIDATE / CLAMP USER PARAMETERS ===
paramNotes$ = ""

origCenter = tremolo_center
origDepth = tremolo_depth
tremolo_center = min(max(tremolo_center, 0), 1)
tremolo_depth = max(tremolo_depth, 0)
if tremolo_center <> origCenter or tremolo_depth <> origDepth
    paramNotes$ = paramNotes$ + "Note: Tremolo_center/Tremolo_depth clamped to valid ranges (center 0-1, depth >= 0)." + newline$
endif

if gate_max < gate_min
    gateSwapTmp = gate_max
    gate_max = gate_min
    gate_min = gateSwapTmp
    paramNotes$ = paramNotes$ + "Note: Gate_max was below Gate_min; the two were swapped." + newline$
endif

# v1.6: gate levels are literal multiplicative gains and the visualization is
# defined on a normalized 0-1 envelope range. Enforce that contract explicitly.
origGateMin = gate_min
origGateMax = gate_max
origGateDuty = gate_duty_percent
gate_min = min(max(gate_min, 0), 1)
gate_max = min(max(gate_max, 0), 1)
gate_duty_percent = min(max(gate_duty_percent, 0), 100)
if gate_min <> origGateMin or gate_max <> origGateMax
    paramNotes$ = paramNotes$ + "Note: Gate_min/Gate_max clamped to the 0-1 range." + newline$
endif
if gate_duty_percent <> origGateDuty
    paramNotes$ = paramNotes$ + "Note: Gate_duty_percent clamped to the 0-100 range." + newline$
endif

# v1.6: Tremolo and Gate are periodic audio-rate gain controls. Frequencies at
# or above Nyquist cannot be represented in the final audio, so clamp them.
modNyquist = orig_sr / 2 - 1
if modNyquist <= 0
    exitScript: "Sampling frequency is too low for synthetic modulation."
endif
maxSyntheticRate = 5000
periodicRateCap = min(modNyquist, maxSyntheticRate)
if tremolo_rate_Hz > periodicRateCap
    tremolo_rate_Hz = periodicRateCap
    paramNotes$ = paramNotes$ + "Note: Tremolo_rate_Hz clamped to " + fixed$(periodicRateCap, 1) + " Hz (synthetic-control/Nyquist safety limit)." + newline$
endif
if gate_rate_Hz > periodicRateCap
    gate_rate_Hz = periodicRateCap
    paramNotes$ = paramNotes$ + "Note: Gate_rate_Hz clamped to " + fixed$(periodicRateCap, 1) + " Hz (synthetic-control/Nyquist safety limit)." + newline$
endif
if random_rate_Hz > maxSyntheticRate
    random_rate_Hz = maxSyntheticRate
    paramNotes$ = paramNotes$ + "Note: Random_rate_Hz clamped to " + fixed$(maxSyntheticRate, 0) + " Hz by the synthetic-control safety limit." + newline$
endif

origRandomDepth = random_depth
random_depth = min(max(random_depth, 0), 1)
if random_depth <> origRandomDepth
    paramNotes$ = paramNotes$ + "Note: Random_depth clamped to the 0-1 range." + newline$
endif

# === GET MODE NAME ===
if mode = 1
    modeName$ = "Power Shaping"
elsif mode = 2
    modeName$ = "Tremolo"
elsif mode = 3
    modeName$ = "Gating"
elsif mode = 4
    modeName$ = "Time Shift"
elsif mode = 5
    modeName$ = "Time Scale"
elsif mode = 6
    modeName$ = "Inversion"
else
    modeName$ = "Random"
endif

# === INFO HEADER ===
clearinfo
writeInfoLine: "=============================================="
appendInfoLine: "  INTENSITY ENVELOPE PROCESSOR v1.6"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Input: ", source_name$, " (", fixed$(dur, 3), "s, starts at ", fixed$(sourceStart, 3), "s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Mode: ", modeName$
if paramNotes$ <> ""
    appendInfoLine: ""
    appendInfoLine: paramNotes$
endif
appendInfoLine: ""

# ============================================================
# CREATE MODULATOR
# ============================================================

intensity_id = 0
modulator_id = 0
vis_modulator_id = 0

if mode = 1 or mode = 6
    # Power Shaping / Inversion need genuine loudness analysis, so their
    # modulator is built on Praat's normal Intensity grid (100 Hz pitch
    # floor -> ~8 ms time step).
    selectObject: source_id
    To Intensity: 100, 0, "yes"
    intensity_id = selected("Intensity")

    # Start with flat unity gain (no change)
    Formula: ~ 1
    Rename: "modulator"
    modulator_id = selected("Intensity")

elsif mode = 2 or mode = 3 or mode = 7
    # Tremolo / Gate / Random are synthetic envelopes, not loudness
    # analysis, so they get their own fixed-rate time grid instead of
    # being tied to Intensity's pitch-floor-derived time step (which
    # depends on the sound's duration and was being coarsened on most
    # ordinary files). The grid rate scales with the requested effect
    # rate so it always has plenty of points per cycle.
    if mode = 2
        reqRate = tremolo_rate_Hz
    elsif mode = 3
        reqRate = gate_rate_Hz
    else
        reqRate = random_rate_Hz
    endif

    # v1.6: keep the normal fine grid, but bound both rate and total sample
    # count. If a very long file makes the 2 kHz baseline excessive, relax the
    # baseline only as far as needed while still keeping >=20 samples per
    # requested control cycle and at least 200 Hz control resolution.
    desiredModulatorRate = max(2000, ceiling(reqRate * 20))
    maxModulatorRate = 100000
    maxModulatorSamples = 5000000
    minAdequateRate = max(200, ceiling(reqRate * 20))
    maxRateByLength = floor(maxModulatorSamples / dur)
    if maxRateByLength < minAdequateRate
        exitScript: modeName$ + " at " + fixed$(reqRate, 3) + " Hz over " + fixed$(dur, 3) + " s would require more than " + string$(maxModulatorSamples) + " control samples. Lower the rate or process a shorter Sound."
    endif
    modulatorRate = min(desiredModulatorRate, min(maxModulatorRate, maxRateByLength))
    if modulatorRate < desiredModulatorRate
        appendInfoLine: "  Note: synthetic modulator grid reduced from ", desiredModulatorRate, " to ", modulatorRate, " Hz by safety limits."
    endif

    modulator_id = Create Sound from formula: "modulator", 1, sourceStart, sourceEnd, modulatorRate, "1"
endif

# ============================================================
# APPLY MODE-SPECIFIC ENVELOPE
# ============================================================

appendInfoLine: "Processing mode: ", modeName$, "..."

if mode = 1
    # === POWER SHAPING ===
    selectObject: source_id
    To Intensity: 100, 0, "yes"
    temp_int_id = selected("Intensity")
    max_db = Get maximum: 0, 0, "Parabolic"

    if max_db = undefined
        appendInfoLine: "  Input appears to be silent; Power Shaping skipped (unity gain)."
        selectObject: modulator_id
        Formula: ~ 1
        vis_modulator_id = Copy: "vis_mod"
    else
        selectObject: modulator_id
        # r = local linear amplitude ratio relative to the loudest point, in (0, 1]
        Formula: ~ 10 ^ ((object(temp_int_id, x) - max_db) / 20)
        Formula: ~ max(self, 0.0001)

        # Visualise the actual target envelope r_out = r^exponent (bounded 0..1)
        vis_modulator_id = Copy: "vis_mod"
        selectObject: vis_modulator_id
        Formula: ~ self ^ exponent

        # Convert r to the GAIN that must multiply the raw waveform so that
        # (input envelope r) * gain = r^exponent, i.e. gain = r^(exponent - 1)
        selectObject: modulator_id
        Formula: ~ self ^ (exponent - 1)
        Formula: ~ min(self, max_gain)
    endif

    removeObject: temp_int_id

    appendInfoLine: "  Exponent: ", fixed$(exponent, 2)
    if exponent = 1
        appendInfoLine: "  Effect: Neutral (no change)"
    elsif exponent < 1
        appendInfoLine: "  Effect: Compression (louder parts reduced, quiet parts boosted up to ", fixed$(max_gain, 0), "x)"
    else
        appendInfoLine: "  Effect: Expansion (louder parts boosted, quiet parts reduced)"
    endif

elsif mode = 2
    # === TREMOLO ===
    selectObject: modulator_id

    # Auto-limit depth (beyond the 0-1/>=0 clamp already applied above) so the
    # sine never needs to be clipped (flat-topped) at this particular center
    safeDepth = min(tremolo_depth, min(tremolo_center, 1 - tremolo_center))
    if safeDepth < tremolo_depth
        appendInfoLine: "  Note: effective depth reduced from ", fixed$(tremolo_depth, 2), " to ", fixed$(safeDepth, 2), " to avoid clipping at this center."
    endif

    Formula: ~ tremolo_center + safeDepth * sin(2 * pi * tremolo_rate_Hz * (x - sourceStart) + tremolo_phase * pi / 180)
    Formula: ~ min(max(self, 0), 1)

    vis_modulator_id = Copy: "vis_mod"

    appendInfoLine: "  Rate: ", fixed$(tremolo_rate_Hz, 1), " Hz"
    appendInfoLine: "  Depth: ", fixed$(safeDepth * 100, 0), "%"
    appendInfoLine: "  Center: ", fixed$(tremolo_center, 2)

elsif mode = 3
    # === RHYTHMIC GATING (with smoothing) ===
    duty = gate_duty_percent / 100
    smoothSec = gate_smoothing_ms / 1000
    riseWidth = smoothSec * gate_rate_Hz
    # Keep the rise/fall edges from overrunning the on- or off-segment they
    # sit inside (e.g. a 10% duty cycle must not get a 49%-of-cycle rise).
    riseWidth = min(riseWidth, min(duty, 1 - duty) * 0.98)
    if riseWidth < 0.0001
        riseWidth = 0.0001
    endif

    selectObject: modulator_id

    if duty <= 0
        Formula: ~ gate_min
    elsif duty >= 1
        Formula: ~ gate_max
    else
        # Gating formula with smooth transitions using cosine interpolation.
        # Phase is measured relative to the Sound's own start time, so the
        # effect always begins at the same relative phase regardless of the
        # Sound's absolute position on the time axis.
        Formula: ~ if (((x - sourceStart) * gate_rate_Hz) mod 1) < riseWidth then gate_min + (gate_max - gate_min) * (0.5 - 0.5 * cos(pi * (((x - sourceStart) * gate_rate_Hz) mod 1) / riseWidth)) else if (((x - sourceStart) * gate_rate_Hz) mod 1) < duty then gate_max else if (((x - sourceStart) * gate_rate_Hz) mod 1) < duty + riseWidth then gate_max - (gate_max - gate_min) * (0.5 - 0.5 * cos(pi * ((((x - sourceStart) * gate_rate_Hz) mod 1) - duty) / riseWidth)) else gate_min fi fi fi
    endif

    vis_modulator_id = Copy: "vis_mod"

    appendInfoLine: "  Rate: ", fixed$(gate_rate_Hz, 1), " Hz"
    appendInfoLine: "  Duty: ", fixed$(gate_duty_percent, 0), "%"
    appendInfoLine: "  Smoothing: ", fixed$(gate_smoothing_ms, 0), " ms"

elsif mode = 6
    # === ENVELOPE INVERSION ===
    selectObject: source_id
    To Intensity: 100, 0, "yes"
    temp_int_id = selected("Intensity")
    max_db = Get maximum: 0, 0, "Parabolic"

    if max_db = undefined
        appendInfoLine: "  Input appears to be silent; Inversion skipped (unity gain)."
        selectObject: modulator_id
        Formula: ~ 1
        vis_modulator_id = Copy: "vis_mod"
    else
        selectObject: modulator_id
        Formula: ~ 10 ^ ((object(temp_int_id, x) - max_db) / 20)
        Formula: ~ max(self, 0.0001)

        # Visualise the actual target envelope r_out = 1 - r (bounded 0..1)
        vis_modulator_id = Copy: "vis_mod"
        selectObject: vis_modulator_id
        Formula: ~ 1 - self

        # Convert r to the GAIN that must multiply the raw waveform so that
        # (input envelope r) * gain = 1 - r, i.e. gain = (1 - r) / r
        selectObject: modulator_id
        Formula: ~ (1 - self) / self
        Formula: ~ min(self, max_gain)
    endif

    removeObject: temp_int_id

    appendInfoLine: "  Effect: Gain-limited envelope inversion (loud gets quieter;"
    appendInfoLine: "           very quiet regions are boosted up to ", fixed$(max_gain, 0), "x, not fully inverted)"

elsif mode = 7
    # === RANDOM MODULATION ===
    if random_seed <> 0
        random_initializeWithSeedUnsafelyButPredictably (random_seed)
    else
        random_initializeSafelyAndUnpredictably ()
    endif

    # Generate one independent random control point every 1/Random_rate_Hz
    # seconds -- so Random_rate_Hz literally means "N new random decisions
    # per second" -- then linearly interpolate the modulator between them.
    # A couple of extra points pad past sourceEnd so interpolation never
    # falls outside the control sound's own domain (which would read as 0).
    controlDur = sourceEnd - sourceStart
    numControls = ceiling(controlDur * random_rate_Hz) + 2
    controlEnd = sourceStart + numControls / random_rate_Hz
    control_id = Create Sound from formula: "randomControl", 1, sourceStart, controlEnd, random_rate_Hz, "1 - randomUniform(0, random_depth)"

    selectObject: modulator_id
    Formula: ~ object(control_id, x)

    removeObject: control_id

    # Restore Praat's normal unpredictable random state so later effects in
    # this session aren't left running on a fixed seed.
    random_initializeSafelyAndUnpredictably ()

    vis_modulator_id = Copy: "vis_mod"

    appendInfoLine: "  Rate: ", fixed$(random_rate_Hz, 1), " Hz (", numControls, " control points generated)"
    appendInfoLine: "  Depth: ", fixed$(random_depth * 100, 0), "%"
    if random_seed <> 0
        appendInfoLine: "  Seed: ", random_seed, " (reproducible)"
    else
        appendInfoLine: "  Seed: random (not reproducible)"
    endif

endif

# ============================================================
# APPLY PROCESSING
# ============================================================

if mode = 4
    # === TIME SHIFT (audible) ===
    if shift_seconds = 0
        selectObject: source_id
        result_id = Copy: source_name$ + "_shifted"
        appendInfoLine: "  Shift: 0 s (no change)"

    elsif shift_seconds > 0
        # Prepend real silence. Build it before copying the source so the
        # silence object gets a lower ID than the source copy, which keeps
        # "Concatenate" (which orders by object-list position) in the
        # intended silence-then-audio order.
        selectObject: source_id
        channels = Get number of channels
        silence_id = Create Sound from formula: "silence_pad", channels, 0, shift_seconds, orig_sr, "0"
        selectObject: source_id
        sourceCopy_id = Copy: source_name$ + "_srccopy"
        selectObject: silence_id
        plusObject: sourceCopy_id
        result_id = Concatenate
        Rename: source_name$ + "_shifted"
        removeObject: silence_id
        removeObject: sourceCopy_id

        appendInfoLine: "  Shift: +", fixed$(shift_seconds, 3), " s (silence added at the start)"

    else
        # Trim real samples from the start, using the Sound's own absolute
        # start/end time rather than assuming it begins at 0. At least 1 ms
        # is always preserved, so the requested and actual trim amounts are
        # tracked and reported separately.
        requestedTrim = -shift_seconds
        maxTrim = dur - 0.001
        if maxTrim < 0
            maxTrim = 0
        endif
        trimAmount = min(requestedTrim, maxTrim)

        if trimAmount <= 0
            appendInfoLine: "  Shift: ", fixed$(shift_seconds, 3), " s requested; sound too short to trim, left unchanged"
            selectObject: source_id
            result_id = Copy: source_name$ + "_shifted"
        else
            selectObject: source_id
            result_id = Extract part: sourceStart + trimAmount, sourceEnd, "rectangular", 1, "no"
            Rename: source_name$ + "_shifted"

            if trimAmount < requestedTrim
                appendInfoLine: "  Shift: ", fixed$(shift_seconds, 3), " s requested; limited to -", fixed$(trimAmount, 3), " s to preserve at least 1 ms of audio"
            else
                appendInfoLine: "  Shift: ", fixed$(shift_seconds, 3), " s (", fixed$(trimAmount, 3), " s trimmed from the start)"
            endif
        endif
    endif

elsif mode = 5
    # === TIME SCALING (Tape Speed) ===
    resultingSR = orig_sr / scale_factor
    new_dur = dur * scale_factor
    max_output_duration_s = 1800
    min_resulting_sr = 100
    max_resulting_sr = 500000
    min_output_samples = 10
    estimatedSamples = round(new_dur * orig_sr)

    if resultingSR < min_resulting_sr
        exitScript: "Scale_factor ", fixed$(scale_factor, 6), " would drop the sampling frequency to ", fixed$(resultingSR, 1), " Hz (below ", min_resulting_sr, " Hz). Choose a smaller Scale_factor."
    elsif resultingSR > max_resulting_sr
        exitScript: "Scale_factor ", fixed$(scale_factor, 6), " would raise the intermediate sampling frequency to ", fixed$(resultingSR, 0), " Hz (over ", max_resulting_sr, " Hz). Choose a larger Scale_factor."
    elsif new_dur > max_output_duration_s
        exitScript: "Scale_factor ", fixed$(scale_factor, 6), " would produce ", fixed$(new_dur, 1), " s of audio (over the ", max_output_duration_s, " s safety limit). Choose a smaller Scale_factor."
    elsif estimatedSamples < min_output_samples
        exitScript: "Scale_factor ", fixed$(scale_factor, 6), " would produce only about ", estimatedSamples, " samples in the final output. Choose a Scale_factor closer to 1."
    endif

    selectObject: source_id
    temp_id = Copy: source_name$ + "_temp"
    Override sampling frequency: resultingSR
    Resample: orig_sr, 50
    Rename: source_name$ + "_scaled"
    result_id = selected("Sound")
    removeObject: temp_id

    appendInfoLine: "  Scale: ", fixed$(scale_factor, 2), "x"
    appendInfoLine: "  New duration: ", fixed$(new_dur, 3), " s"
    if scale_factor > 1
        appendInfoLine: "  Effect: Slower, lower pitch"
    else
        appendInfoLine: "  Effect: Faster, higher pitch"
    endif

else
    # === ENVELOPE-BASED MODES ===
    # Multiply the raw waveform directly by the gain modulator. No
    # "Sound & IntensityTier: Multiply" is used here, because that command
    # silently rescales its output to 0.9 peak amplitude, which would hide
    # gate levels, tremolo depth, and defeat Normalize = no.
    selectObject: source_id
    result_id = Copy: source_name$ + "_" + presetName$
    selectObject: result_id
    Formula: ~ self * object(modulator_id, x)
endif

# === NORMALIZE ===
normalizationApplied = 0
if normalize
    selectObject: result_id
    preNormalizePeak = Get absolute extremum: 0, 0, "Sinc70"
    if preNormalizePeak > 0
        Scale peak: 0.95
        normalizationApplied = 1
    else
        appendInfoLine: "Output is silent; normalization skipped."
    endif
endif

# ============================================================
# VISUALIZATION
# ============================================================

if visualize
    appendInfoLine: ""
    appendInfoLine: "Creating visualization..."

    Erase all
    vizName$ = replace$(source_name$, "_", "\_ ", 0)
    pageWidth = 8
    # === Header ===
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Intensity Envelope Processor v1.6##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", vizName$ + " | " + modeName$ + " | " + presetName$

    if mode = 4 or mode = 5
        # --- TIME MANIPULATION MODES ---

        # Original
        Select outer viewport: 0, 8, 0.5, 2.2
        Select inner viewport: 0.8, 7.6, 0.7, 2.0
        selectObject: source_id
        Colour: "{0.5, 0.5, 0.5}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Font size: 7
        Select outer viewport: 0.15, 8, 0.5, 2.2
        Text left: "yes", "Original"

        # Result
        Select outer viewport: 0, 8, 2.3, 4.0
        Select inner viewport: 0.8, 7.6, 2.5, 3.8
        selectObject: result_id
        Colour: "{0.3, 0.6, 0.4}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Font size: 7
        Select outer viewport: 0.15, 8, 2.3, 4.0
        Text left: "yes", "Result"
        Text bottom: "yes", "Time (s)"

    else
        # --- ENVELOPE MODES ---

        # Original waveform (top)
        Select outer viewport: 0, 8, 0.5, 1.7
        Select inner viewport: 0.8, 7.6, 0.6, 1.5
        selectObject: source_id
        Colour: "{0.5, 0.5, 0.5}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Font size: 7
        Select outer viewport: 0.15, 8, 0.5, 1.7
        Text left: "yes", "Input"

        # Envelope (middle)
        Select outer viewport: 0, 8, 1.8, 3.0
        Select inner viewport: 0.8, 7.6, 1.9, 2.8

        # Background
        Axes: sourceStart, sourceEnd, 0, 1.1
        Paint rectangle: "{0.95, 0.98, 0.95}", sourceStart, sourceEnd, 0, 1.1

        # Unity reference
        Colour: "{0.7, 0.7, 0.7}"
        Dashed line
        Draw line: sourceStart, 1, sourceEnd, 1
        Solid line

        # Envelope curve
        selectObject: vis_modulator_id
        Colour: "{0.2, 0.7, 0.3}"
        Line width: 2
        Draw: 0, 0, 0, 1.1, "no"
        Line width: 1

        Colour: "Black"
        Draw inner box
        Font size: 7
        Select outer viewport: 0.15, 8, 1.8, 3.0
        Text left: "yes", "Envelope"

        # Result waveform (bottom)
        Select outer viewport: 0, 8, 3.1, 4.3
        Select inner viewport: 0.8, 7.6, 3.2, 4.1
        selectObject: result_id
        Colour: "{0.3, 0.5, 0.7}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Font size: 7
        Select outer viewport: 0.15, 8, 3.1, 4.3
        Text left: "yes", "Result"
        Text bottom: "yes", "Time (s)"

        removeObject: vis_modulator_id
    endif

    # === Summary strip ===
    selectObject: result_id
    resultVizDur = Get total duration
    resultVizPeak = Get absolute extremum: 0, 0, "None"

    if normalize
        if normalizationApplied
            normalizeViz$ = "on (0.95 peak)"
        else
            normalizeViz$ = "requested; skipped (silent output)"
        endif
    else
        normalizeViz$ = "off"
    endif

    if mode = 1
        modeDetail$ = "exponent " + fixed$(exponent, 2) + " | gain cap " + fixed$(max_gain, 1) + "x"
    elsif mode = 2
        modeDetail$ = "rate " + fixed$(tremolo_rate_Hz, 2) + " Hz | depth " + fixed$(safeDepth * 100, 0) + "\% | center " + fixed$(tremolo_center, 2)
    elsif mode = 3
        modeDetail$ = "rate " + fixed$(gate_rate_Hz, 2) + " Hz | duty " + fixed$(gate_duty_percent, 0) + "\% | levels " + fixed$(gate_min, 2) + "-" + fixed$(gate_max, 2) + " | smooth " + fixed$(gate_smoothing_ms, 1) + " ms"
    elsif mode = 4
        modeDetail$ = "requested shift " + fixed$(shift_seconds, 3) + " s"
    elsif mode = 5
        modeDetail$ = "time scale " + fixed$(scale_factor, 3) + "x | intermediate SR " + fixed$(resultingSR, 0) + " Hz"
    elsif mode = 6
        modeDetail$ = "inverse intensity gain | gain cap " + fixed$(max_gain, 1) + "x"
    else
        if random_seed = 0
            seedViz$ = "random"
        else
            seedViz$ = string$(random_seed)
        endif
        modeDetail$ = "rate ~" + fixed$(random_rate_Hz, 2) + " Hz | depth " + fixed$(random_depth * 100, 0) + "\% | seed " + seedViz$
    endif

    Select outer viewport: 0, 8, 4.48, 5.86
    Select inner viewport: 0.60, 7.70, 4.58, 5.76
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.02, "left", 0.78, "half", "##Input##  " + vizName$ + " | " + fixed$(dur, 3) + " s | " + fixed$(orig_sr, 0) + " Hz | time domain " + fixed$(sourceStart, 3) + "-" + fixed$(sourceEnd, 3) + " s"
    Text: 0.02, "left", 0.50, "half", "##Processing##  " + modeName$ + " | " + modeDetail$
    Text: 0.02, "left", 0.22, "half", "##Output##  preset " + presetName$ + " | normalize " + normalizeViz$ + " | " + fixed$(resultVizDur, 3) + " s | peak " + fixed$(resultVizPeak, 3)
    Colour: "Black"
    Draw inner box

    # Restore complete page for Picture export / clipboard.
    pageHeight = 6.10
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line

endif

# ============================================================
# CLEANUP & OUTPUT
# ============================================================

nocheck removeObject: intensity_id
nocheck removeObject: modulator_id
nocheck removeObject: vis_modulator_id

selectObject: result_id

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE: ", selected$("Sound")
appendInfoLine: "=============================================="

if play
    appendInfoLine: "Playing..."
    Play
endif

selectObject: result_id
