# ============================================================
# Praat AudioTools - Spectral Effects Suite
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3.2 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Character effects built from time-index resampling/differencing,
#   amplitude modulation, and temporal envelopes.
#
# IMPORTANT TERMINOLOGY:
#   The core transform operates on Sound sample indices (time), not
#   Spectrum bins. The historical suite name is retained for continuity,
#   but the implementation and visualization now describe the mechanism
#   accurately as a time-index / dual-rate transform.
#
# Changelog v1.3.2 (2026):
#   - Fixes Picture compatibility: Marks left every now uses the 5-argument
#     signature accepted by current Praat runtimes.
#
# Changelog v1.3.1 (2026):
#   - Fixes LTAS visualization compatibility: replaces version-sensitive
#     Get value at frequency interpolation enum with explicit nearest-bin lookup.
#   - Keeps the same light 3-point LTAS smoothing at 0.97f, f, and 1.03f.
#
# Changelog v1.3 (2026):
#   - Preserves original channels by default; no automatic stereo fold-down.
#   - Adds optional Legacy mono + 12 ms pseudo-stereo mode for v1.2 character.
#   - Wet = 0 is a true bypass: exact channel structure, no normalization.
#   - Adds optional output normalization instead of forcing Scale peak.
#   - Replaces misleading "cycles" controls with phase-span controls in radians;
#     defaults are numerically identical to v1.2, preserving modulation character.
#   - Makes Effect default vs Custom envelope explicit; Envelope type is no longer
#     silently overwritten when Custom envelope is selected.
#   - Generates the envelope as a real Sound object and uses that exact realization
#     for processing and visualization (including Random/Turbulent modes).
#   - Uses explicit object[id, row, col] reads for multichannel-safe processing.
#   - Adds safety clamp for wobble factors to avoid zero/negative divisors.
#   - Visualization now shows the actual mechanism: process diagram, shared-scale
#     waveforms, index-rate factors, exact envelope, and same-axis log-frequency LTAS.
#   - Visualization selects the strongest input channel instead of phase-cancelling
#     stereo fold-down.
#   - Renames misleading effect labels while retaining the original musical formulas.
#
# Changelog v1.2 (2026):
#   - Froze the pre-effect signal so col/f and col*f both read the input rather
#     than recursively reading already-written output samples.
# ============================================================

form Spectral Effects Suite v1.3.2
    comment === EFFECT TYPE ===
    optionmenu Effect: 1
        option Wobble (dual-rate + tremolo decay)
        option Wobbling Shift (dual-rate + turbulent decay)
        option Dual-Rate Decay
        option Underwater (multi-rate blur + bubbling)
        option Dual-Rate Crescendo
        option Pulsing Dual-Rate

    comment === PRESETS ===
    optionmenu Preset: 1
        option Custom
        option Subtle
        option Moderate
        option Strong
        option Extreme

    comment === TIME-INDEX TRANSFORM ===
    positive Shift_base: 1.1
    positive Shift_depth: 0.3
    positive Shift_phase_span: 50
    comment (Phase span in radians across the file; 2*pi = one full cycle)

    comment === AMPLITUDE ENVELOPE ===
    optionmenu Envelope_mode: 1
        option Effect default
        option Custom envelope
    optionmenu Envelope_type: 1
        option Exponential Decay
        option Exponential Crescendo
        option Tremolo with Decay
        option Random Bubbling
        option Turbulent Decay (Gaussian)
        option Rhythmic Pulsing (abs sin)
    positive Envelope_strength: 10
    comment (Higher than 1 gives stronger decay/crescendo shaping)

    comment === MODULATION ===
    positive Modulation_center: 1.0
    positive Modulation_depth: 0.5
    positive Modulation_phase_span: 20
    comment (Phase span in radians across the file; 2*pi = one full cycle)

    comment === MIX / CHANNELS ===
    real Wet_dry_percent: 100
    comment (0 = exact dry bypass, 100 = full wet)
    optionmenu Stereo_mode: 1
        option Preserve original channels
        option Legacy mono + 12 ms pseudo-stereo

    comment === OUTPUT ===
    boolean Normalize_output: 1
    positive Scale_peak: 0.99
    boolean Draw_visualization: 1
    boolean Play_after: 1
endform

# ===================================================================
# SETUP
# ===================================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
original_name$ = selected$("Sound")
selectObject: original
original_sr = Get sampling frequency
original_dur = Get total duration
num_channels = Get number of channels
input_rms = Get root-mean-square: 0, 0
input_peak = Get absolute extremum: 0, 0, "none"

# Clamp wet/dry.
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif
wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level
bypass = 0
factor_clamped = 0

# ===================================================================
# PRESET APPLICATION
# ===================================================================

if preset = 2
    shift_depth = 0.1
    modulation_depth = 0.2
    envelope_strength = 5
    preset_name$ = "Subtle"
elsif preset = 3
    shift_depth = 0.3
    modulation_depth = 0.5
    envelope_strength = 10
    preset_name$ = "Moderate"
elsif preset = 4
    shift_depth = 0.5
    modulation_depth = 0.7
    envelope_strength = 15
    preset_name$ = "Strong"
elsif preset = 5
    shift_depth = 0.7
    modulation_depth = 0.9
    envelope_strength = 25
    shift_phase_span = 80
    modulation_phase_span = 40
    preset_name$ = "Extreme"
else
    preset_name$ = "Custom"
endif

# ===================================================================
# EFFECT-SPECIFIC DEFAULTS
# ===================================================================

if effect = 1
    effect_name$ = "Wobble"
    transform_name$ = "dual-rate wobble"
    default_envelope = 3
elsif effect = 2
    effect_name$ = "WobblingShift"
    transform_name$ = "dual-rate wobble (reduced depth)"
    shift_depth = shift_depth * 0.3
    default_envelope = 5
elsif effect = 3
    effect_name$ = "DualRateDecay"
    transform_name$ = "constant dual-rate difference"
    shift_base = 1.1
    default_envelope = 1
elsif effect = 4
    effect_name$ = "Underwater"
    transform_name$ = "multi-rate blur minus faster branch"
    default_envelope = 4
    if preset = 4 or preset = 5
        shift_base = 1.15
    endif
elsif effect = 5
    effect_name$ = "DualRateCrescendo"
    transform_name$ = "constant dual-rate difference"
    shift_base = 1.1
    default_envelope = 2
else
    effect_name$ = "PulsingDualRate"
    transform_name$ = "constant dual-rate difference"
    shift_base = 1.2
    default_envelope = 6
    if preset = 1
        modulation_phase_span = 15
    endif
endif

if envelope_mode = 1
    envelope_type = default_envelope
endif

# Wobble branches use shift_base +/- shift_depth. Keep the divisor positive.
if (effect = 1 or effect = 2) and shift_depth >= shift_base
    shift_depth = 0.95 * shift_base
    factor_clamped = 1
endif

if stereo_mode = 1
    stereo_name$ = "preserve channels"
else
    stereo_name$ = "legacy pseudo-stereo"
endif

writeInfoLine: "=== Spectral Effects Suite v1.3 ==="
appendInfoLine: "Effect: ", effect_name$
appendInfoLine: "Mechanism: ", transform_name$
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Envelope mode: ", if envelope_mode = 1 then "effect default" else "custom" fi
appendInfoLine: "Wet/Dry: ", fixed$(wet_dry_percent, 0), "%"
appendInfoLine: "Channels: ", stereo_name$
if factor_clamped
    appendInfoLine: "Safety: Shift depth was limited to 95% of shift base to keep divisors positive."
endif
appendInfoLine: ""

# ===================================================================
# TRUE DRY BYPASS
# ===================================================================

if wet_level = 0
    selectObject: original
    sound = Copy: "SES_bypass"
    bypass = 1
    envelope_sound = 0
    appendInfoLine: "Wet = 0: exact dry bypass; transform and normalization skipped."
endif

# ===================================================================
# PROCESSING INPUT / DRY REFERENCE
# ===================================================================

if bypass = 0
    if num_channels > 1 and stereo_mode = 2
        # Explicit legacy path: this deliberately reproduces the v1.2 mono core.
        selectObject: original
        sound = Convert to mono
        Rename: "SES_processing_mono"
        selectObject: original
        dry_mix_sound = Convert to mono
        Rename: "SES_dry_mono"
    else
        # Correct default: preserve every channel and process each row independently.
        selectObject: original
        sound = Copy: "SES_processing"
        selectObject: original
        dry_mix_sound = Copy: "SES_dry"
    endif

    # ===================================================================
    # STEP 1: TIME-INDEX / DUAL-RATE TRANSFORM
    # ===================================================================

    selectObject: sound
    frozen = Copy: "SES_frozen_src"
    frozId$ = string$(frozen)
    selectObject: sound

    if effect = 1 or effect = 2
        appendInfoLine: "Applying dual-rate wobble transform..."
        Formula: "object[" + frozId$ + ", row, col/(shift_base + shift_depth * sin(shift_phase_span * (x-xmin)/(xmax-xmin)))] - object[" + frozId$ + ", row, col*(shift_base + shift_depth * cos(shift_phase_span * (x-xmin)/(xmax-xmin)))]"

    elsif effect = 3 or effect = 5 or effect = 6
        appendInfoLine: "Applying constant dual-rate difference..."
        high_factor = shift_base
        low_factor = shift_base
        Formula: "object[" + frozId$ + ", row, col/low_factor] - object[" + frozId$ + ", row, col*high_factor]"

    else
        appendInfoLine: "Applying multi-rate underwater transform..."
        f1 = shift_base
        f2 = shift_base + 0.03
        f3 = shift_base + 0.07
        hf = shift_base + 0.2
        Formula: "(object[" + frozId$ + ", row, col/f1] + object[" + frozId$ + ", row, col/f2] + object[" + frozId$ + ", row, col/f3]) / 3 - object[" + frozId$ + ", row, col*hf]"
    endif

    removeObject: frozen

    # ===================================================================
    # STEP 2: EXACT ENVELOPE REALIZATION
    # ===================================================================

    appendInfoLine: "Creating exact envelope realization..."

    if envelope_type = 1
        Create Sound from formula: "SES_envelope", 1, 0, original_dur, original_sr, "envelope_strength^(-x/xmax)"
    elsif envelope_type = 2
        Create Sound from formula: "SES_envelope", 1, 0, original_dur, original_sr, "envelope_strength^(x/xmax-1)"
    elsif envelope_type = 3
        Create Sound from formula: "SES_envelope", 1, 0, original_dur, original_sr, "envelope_strength^(-x/xmax) * (modulation_center + modulation_depth * sin(modulation_phase_span * x/xmax))"
    elsif envelope_type = 4
        Create Sound from formula: "SES_envelope", 1, 0, original_dur, original_sr, "envelope_strength^(-x/xmax) * (modulation_center + modulation_depth * randomUniform(-1, 1))"
    elsif envelope_type = 5
        Create Sound from formula: "SES_envelope", 1, 0, original_dur, original_sr, "envelope_strength^(-x/xmax) * (modulation_center + modulation_depth * randomGauss(0, 1))"
    else
        Create Sound from formula: "SES_envelope", 1, 0, original_dur, original_sr, "abs(sin(modulation_phase_span * x/xmax)) * envelope_strength^(-x/xmax)"
    endif
    envelope_sound = selected("Sound")
    envId$ = string$(envelope_sound)

    selectObject: sound
    Formula: "self * object[" + envId$ + ", 1, col]"

    # ===================================================================
    # WET/DRY MIX
    # ===================================================================

    if dry_level > 0
        appendInfoLine: "Mixing wet/dry with matched channel structure..."
        wet_str$ = string$(wet_level)
        dry_str$ = string$(dry_level)
        dry_id_str$ = string$(dry_mix_sound)
        selectObject: sound
        Formula: "self * " + wet_str$ + " + object[" + dry_id_str$ + ", row, col] * " + dry_str$
    endif

    removeObject: dry_mix_sound

    # ===================================================================
    # OPTIONAL LEGACY PSEUDO-STEREO
    # ===================================================================

    if num_channels > 1 and stereo_mode = 2
        appendInfoLine: "Applying legacy 12 ms pseudo-stereo output..."
        selectObject: sound
        mono_result = sound
        delay_samples = round(0.012 * original_sr)
        delay_str$ = string$(delay_samples)
        mono_str$ = string$(mono_result)

        Create Sound from formula: "SES_left", 1, 0, original_dur, original_sr, "object[" + mono_str$ + ", 1, col]"
        left_ch = selected("Sound")
        Create Sound from formula: "SES_right", 1, 0, original_dur, original_sr, "if col > " + delay_str$ + " then object[" + mono_str$ + ", 1, col - " + delay_str$ + "] else 0 fi"
        right_ch = selected("Sound")

        selectObject: left_ch
        plusObject: right_ch
        sound = Combine to stereo
        removeObject: mono_result, left_ch, right_ch
    endif

    # ===================================================================
    # OPTIONAL NORMALIZATION
    # ===================================================================

    if normalize_output
        selectObject: sound
        appendInfoLine: "Normalizing processed output peak to ", fixed$(scale_peak, 3), "..."
        Scale peak: scale_peak
    else
        appendInfoLine: "Output normalization disabled."
    endif
endif

# ===================================================================
# FINALIZE
# ===================================================================

selectObject: sound
Rename: original_name$ + "_" + effect_name$ + "_" + preset_name$ + "_v1.3"
result = sound
result_dur = Get total duration
result_ch = Get number of channels
output_rms = Get root-mean-square: 0, 0
output_peak = Get absolute extremum: 0, 0, "none"

if input_rms > 0
    rms_ratio = output_rms / input_rms
else
    rms_ratio = 0
endif

# ===================================================================
# VISUALIZATION
# ===================================================================

if draw_visualization
    # ---------------------------------------------------------------
    # Choose one representative input channel by RMS. This avoids the
    # phase cancellation that can occur in stereo-to-mono fold-down.
    # ---------------------------------------------------------------
    representative_channel = 1
    strongest_rms = -1

    if num_channels > 1
        for ch from 1 to num_channels
            selectObject: original
            Extract one channel: ch
            temp_ch = selected("Sound")
            temp_rms = Get root-mean-square: 0, 0
            if temp_rms > strongest_rms
                strongest_rms = temp_rms
                representative_channel = ch
            endif
            removeObject: temp_ch
        endfor
    endif

    selectObject: original
    if num_channels > 1
        Extract one channel: representative_channel
        vis_input = selected("Sound")
        Rename: "SES_vis_input"
    else
        vis_input = Copy: "SES_vis_input"
    endif

    selectObject: result
    if result_ch > 1
        vis_result_channel = representative_channel
        if vis_result_channel > result_ch
            vis_result_channel = 1
        endif
        Extract one channel: vis_result_channel
        vis_output = selected("Sound")
        Rename: "SES_vis_output"
    else
        vis_output = Copy: "SES_vis_output"
    endif

    # Shared waveform range.
    selectObject: vis_input
    input_vis_peak = Get absolute extremum: 0, 0, "none"
    selectObject: vis_output
    output_vis_peak = Get absolute extremum: 0, 0, "none"
    wave_peak = input_vis_peak
    if output_vis_peak > wave_peak
        wave_peak = output_vis_peak
    endif
    if wave_peak <= 0
        wave_peak = 1
    endif
    wave_peak = wave_peak * 1.08

    # Exact envelope for bypass: unity line so the visualization remains complete.
    if bypass
        Create Sound from formula: "SES_envelope_bypass", 1, 0, original_dur, original_sr, "1"
        envelope_sound = selected("Sound")
    endif

    # Envelope bounds.
    selectObject: envelope_sound
    env_min = Get minimum: 0, 0, "none"
    env_max = Get maximum: 0, 0, "none"
    env_span = env_max - env_min
    if env_span <= 0
        env_span = 1
    endif
    env_ymin = env_min - 0.08 * env_span
    env_ymax = env_max + 0.08 * env_span

    # LTAS for same-axis spectral comparison.
    selectObject: vis_input
    in_spectrum = To Spectrum: "yes"
    To Ltas (1-to-1)
    in_ltas = selected("Ltas")

    selectObject: vis_output
    out_spectrum = To Spectrum: "yes"
    To Ltas (1-to-1)
    out_ltas = selected("Ltas")

    spec_fmin = 50
    spec_fmax = 0.45 * original_sr
    if spec_fmax > 16000
        spec_fmax = 16000
    endif
    if spec_fmax <= spec_fmin * 1.5
        spec_fmin = 10
    endif

    # Determine one shared dB scale from lightly smoothed log-spaced samples.
    n_spec_points = 80
    spec_min = 1e30
    spec_max = -1e30
    for i from 1 to n_spec_points
        frac = (i - 1) / (n_spec_points - 1)
        freq = spec_fmin * (spec_fmax / spec_fmin)^frac

        selectObject: in_ltas
        bin1 = Get bin number from frequency: 0.97 * freq
        bin1 = round (bin1)
        bin2 = Get bin number from frequency: freq
        bin2 = round (bin2)
        bin3 = Get bin number from frequency: 1.03 * freq
        bin3 = round (bin3)
        a1 = Get value in bin: bin1
        a2 = Get value in bin: bin2
        a3 = Get value in bin: bin3
        in_db = (a1 + a2 + a3) / 3

        selectObject: out_ltas
        bin1 = Get bin number from frequency: 0.97 * freq
        bin1 = round (bin1)
        bin2 = Get bin number from frequency: freq
        bin2 = round (bin2)
        bin3 = Get bin number from frequency: 1.03 * freq
        bin3 = round (bin3)
        b1 = Get value in bin: bin1
        b2 = Get value in bin: bin2
        b3 = Get value in bin: bin3
        out_db = (b1 + b2 + b3) / 3

        if in_db < spec_min
            spec_min = in_db
        endif
        if out_db < spec_min
            spec_min = out_db
        endif
        if in_db > spec_max
            spec_max = in_db
        endif
        if out_db > spec_max
            spec_max = out_db
        endif
    endfor

    spec_ymin = floor((spec_min - 5) / 10) * 10
    spec_ymax = ceiling((spec_max + 5) / 10) * 10
    if spec_ymax - spec_ymin < 40
        spec_ymin = spec_ymax - 40
    endif

    # Factor bounds for the mechanism panel.
    if effect = 1 or effect = 2
        factor_min = shift_base - shift_depth
        factor_max = shift_base + shift_depth
    elsif effect = 4
        factor_min = shift_base
        factor_max = shift_base + 0.2
    else
        factor_min = shift_base
        factor_max = shift_base
    endif
    factor_span = factor_max - factor_min
    if factor_span <= 0
        factor_span = 0.2
    endif
    factor_ymin = factor_min - 0.25 * factor_span
    factor_ymax = factor_max + 0.25 * factor_span
    if factor_ymin < 0
        factor_ymin = 0
    endif

    # ---------------------------------------------------------------
    # DRAW
    # ---------------------------------------------------------------
    Erase all
    Helvetica

    # Title strip.
    Select outer viewport: 0, 8, 0.0, 0.45
    Select inner viewport: 0, 8, 0.0, 0.45
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Font size: 14
    Text: 0.5, "centre", 0.62, "half", "Spectral Effects Suite v1.3 - " + effect_name$ + " (" + preset_name$ + ")"
    Font size: 7
    Colour: "{0.35, 0.35, 0.35}"
    Text: 0.5, "centre", 0.18, "half", "Actual mechanism: Sound sample-index resampling / differencing, not Spectrum-bin processing"

    # Process diagram strip.
    Select outer viewport: 0.2, 7.8, 0.55, 1.35
    Select inner viewport: 0.2, 7.8, 0.55, 1.35
    Axes: 0, 10, 0, 1
    Font size: 7
    Colour: "{0.94, 0.94, 0.94}"
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 10, 0, 1
    Colour: "Black"
    Draw inner box
    Text: 1.0, "centre", 0.62, "half", "Input x[n]"
    Text: 3.2, "centre", 0.62, "half", "Read x[n/a(t)]"
    Text: 5.1, "centre", 0.62, "half", "minus / blur"
    Text: 6.9, "centre", 0.62, "half", "Envelope e(t)"
    Text: 8.8, "centre", 0.62, "half", "Wet/Dry -> Output"
    Draw line: 1.7, 0.62, 2.45, 0.62
    Text: 2.42, "centre", 0.62, "half", ">"
    Draw line: 3.95, 0.62, 4.45, 0.62
    Text: 4.42, "centre", 0.62, "half", ">"
    Draw line: 5.7, 0.62, 6.25, 0.62
    Text: 6.22, "centre", 0.62, "half", ">"
    Draw line: 7.6, 0.62, 8.05, 0.62
    Text: 8.02, "centre", 0.62, "half", ">"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    if effect = 4
        if bypass
            Text: 5.0, "centre", 0.22, "half", "Wet=0: exact dry bypass; configured transform/envelope are not applied"
        else
            Text: 5.0, "centre", 0.22, "half", "y[n] = (x[n/f1]+x[n/f2]+x[n/f3])/3 - x[n/hf]"
        endif
    else
        if bypass
            Text: 5.0, "centre", 0.22, "half", "Wet=0: exact dry bypass; configured transform/envelope are not applied"
        else
            Text: 5.0, "centre", 0.22, "half", "y[n] = x[n/a(t)] - x[n*b(t)]"
        endif
    endif

    # Input waveform panel.
    Select outer viewport: 0.2, 4.0, 1.55, 2.65
    Select inner viewport: 0.55, 3.85, 1.72, 2.50
    Axes: 0, original_dur, -wave_peak, wave_peak
    selectObject: vis_input
    Colour: "{0.42, 0.42, 0.42}"
    Draw: 0, original_dur, -wave_peak, wave_peak, "no", "Curve"
    Select inner viewport: 0.55, 3.85, 1.72, 2.50
    Axes: 0, original_dur, -wave_peak, wave_peak
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text: 0.02 * original_dur, "left", 0.82 * wave_peak, "half", "Input waveform - ch " + fixed$(representative_channel, 0)

    # Output waveform panel, exact same range.
    Select outer viewport: 4.0, 7.8, 1.55, 2.65
    Select inner viewport: 4.15, 7.45, 1.72, 2.50
    Axes: 0, original_dur, -wave_peak, wave_peak
    selectObject: vis_output
    Colour: "{0.18, 0.42, 0.62}"
    Draw: 0, original_dur, -wave_peak, wave_peak, "no", "Curve"
    Select inner viewport: 4.15, 7.45, 1.72, 2.50
    Axes: 0, original_dur, -wave_peak, wave_peak
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text: 0.02 * original_dur, "left", 0.82 * wave_peak, "half", "Output waveform - same scale"

    # Index-rate factor panel.
    Select outer viewport: 0.2, 4.0, 2.85, 3.85
    Select inner viewport: 0.55, 3.85, 3.00, 3.68
    Axes: 0, 1, factor_ymin, factor_ymax
    Colour: "{0.97, 0.97, 0.97}"
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, factor_ymin, factor_ymax
    n_factor_points = 160
    for i from 1 to n_factor_points
        tt = (i - 1) / (n_factor_points - 1)
        if effect = 1 or effect = 2
            fa = shift_base + shift_depth * sin(shift_phase_span * tt)
            fb = shift_base + shift_depth * cos(shift_phase_span * tt)
            if i > 1
                Colour: "{0.15, 0.45, 0.65}"
                Draw line: prev_tt, prev_fa, tt, fa
                Colour: "{0.65, 0.35, 0.18}"
                Draw line: prev_tt, prev_fb, tt, fb
            endif
            prev_fa = fa
            prev_fb = fb
        elsif effect = 4
            fa = shift_base
            fb = shift_base + 0.03
            fc = shift_base + 0.07
            fd = shift_base + 0.2
            if i > 1
                Colour: "{0.15, 0.45, 0.65}"
                Draw line: prev_tt, prev_fa, tt, fa
                Colour: "{0.32, 0.52, 0.58}"
                Draw line: prev_tt, prev_fb, tt, fb
                Colour: "{0.50, 0.48, 0.42}"
                Draw line: prev_tt, prev_fc, tt, fc
                Colour: "{0.65, 0.35, 0.18}"
                Draw line: prev_tt, prev_fd, tt, fd
            endif
            prev_fa = fa
            prev_fb = fb
            prev_fc = fc
            prev_fd = fd
        else
            fa = shift_base
            if i > 1
                Colour: "{0.15, 0.45, 0.65}"
                Draw line: prev_tt, prev_fa, tt, fa
            endif
            prev_fa = fa
        endif
        prev_tt = tt
    endfor
    Colour: "Black"
    Draw inner box
    Font size: 7
    if bypass
        Text: 0.03, "left", factor_ymax - 0.12 * (factor_ymax-factor_ymin), "half", "Configured index-rate factors (bypassed)"
    else
        Text: 0.03, "left", factor_ymax - 0.12 * (factor_ymax-factor_ymin), "half", "Index-rate factors used by transform"
    endif
    Font size: 6
    if effect = 1 or effect = 2
        Colour: "{0.15, 0.45, 0.65}"
        Text: 0.72, "left", factor_ymax - 0.12 * (factor_ymax-factor_ymin), "half", "a(t): n/a"
        Colour: "{0.65, 0.35, 0.18}"
        Text: 0.72, "left", factor_ymax - 0.27 * (factor_ymax-factor_ymin), "half", "b(t): n*b"
    elsif effect = 4
        Colour: "{0.15, 0.45, 0.65}"
        Text: 0.68, "left", factor_ymax - 0.12 * (factor_ymax-factor_ymin), "half", "f1"
        Colour: "{0.32, 0.52, 0.58}"
        Text: 0.76, "left", factor_ymax - 0.12 * (factor_ymax-factor_ymin), "half", "f2"
        Colour: "{0.50, 0.48, 0.42}"
        Text: 0.84, "left", factor_ymax - 0.12 * (factor_ymax-factor_ymin), "half", "f3"
        Colour: "{0.65, 0.35, 0.18}"
        Text: 0.92, "left", factor_ymax - 0.12 * (factor_ymax-factor_ymin), "half", "hf"
    else
        Colour: "{0.15, 0.45, 0.65}"
        Text: 0.68, "left", factor_ymax - 0.12 * (factor_ymax-factor_ymin), "half", "a(t)=b(t)=base"
    endif

    # Exact envelope panel.
    Select outer viewport: 4.0, 7.8, 2.85, 3.85
    Select inner viewport: 4.15, 7.45, 3.00, 3.68
    Axes: 0, original_dur, env_ymin, env_ymax
    selectObject: envelope_sound
    Colour: "{0.22, 0.52, 0.32}"
    Draw: 0, original_dur, env_ymin, env_ymax, "no", "Curve"
    Select inner viewport: 4.15, 7.45, 3.00, 3.68
    Axes: 0, original_dur, env_ymin, env_ymax
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text: 0.02 * original_dur, "left", env_ymax - 0.12 * (env_ymax-env_ymin), "half", "Exact envelope realization e(t)"

    # Same-axis log-frequency LTAS panel.
    Select outer viewport: 0.2, 7.8, 4.05, 5.45
    Select inner viewport: 0.65, 7.45, 4.20, 5.23
    log_fmin = log10(spec_fmin)
    log_fmax = log10(spec_fmax)
    Axes: log_fmin, log_fmax, spec_ymin, spec_ymax
    Colour: "{0.98, 0.98, 0.98}"
    Paint rectangle: "{0.98, 0.98, 0.98}", log_fmin, log_fmax, spec_ymin, spec_ymax

    for i from 1 to n_spec_points
        frac = (i - 1) / (n_spec_points - 1)
        freq = spec_fmin * (spec_fmax / spec_fmin)^frac
        logf = log10(freq)

        selectObject: in_ltas
        bin1 = Get bin number from frequency: 0.97 * freq
        bin1 = round (bin1)
        bin2 = Get bin number from frequency: freq
        bin2 = round (bin2)
        bin3 = Get bin number from frequency: 1.03 * freq
        bin3 = round (bin3)
        a1 = Get value in bin: bin1
        a2 = Get value in bin: bin2
        a3 = Get value in bin: bin3
        in_db = (a1 + a2 + a3) / 3

        selectObject: out_ltas
        bin1 = Get bin number from frequency: 0.97 * freq
        bin1 = round (bin1)
        bin2 = Get bin number from frequency: freq
        bin2 = round (bin2)
        bin3 = Get bin number from frequency: 1.03 * freq
        bin3 = round (bin3)
        b1 = Get value in bin: bin1
        b2 = Get value in bin: bin2
        b3 = Get value in bin: bin3
        out_db = (b1 + b2 + b3) / 3

        if i > 1
            Colour: "{0.42, 0.42, 0.42}"
            Line width: 1
            Draw line: prev_logf, prev_in_db, logf, in_db
            Colour: "{0.18, 0.42, 0.62}"
            Line width: 1.5
            Draw line: prev_logf, prev_out_db, logf, out_db
        endif
        prev_logf = logf
        prev_in_db = in_db
        prev_out_db = out_db
    endfor

    # Reset axes/viewport after data drawing before garnish.
    Select inner viewport: 0.65, 7.45, 4.20, 5.23
    Axes: log_fmin, log_fmax, spec_ymin, spec_ymax
    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left every: 1, 10, "yes", "yes", "no"
    Font size: 6
    Text: log_fmin + 0.02 * (log_fmax-log_fmin), "left", spec_ymax - 0.10 * (spec_ymax-spec_ymin), "half", "LTAS comparison - same dB scale; log-frequency sampling"

    # Manual readable logarithmic ticks.
    if spec_fmin <= 50 and spec_fmax >= 50
        One mark bottom: log10(50), "no", "yes", "no", "50"
    endif
    if spec_fmin <= 100 and spec_fmax >= 100
        One mark bottom: log10(100), "no", "yes", "no", "100"
    endif
    if spec_fmin <= 200 and spec_fmax >= 200
        One mark bottom: log10(200), "no", "yes", "no", "200"
    endif
    if spec_fmin <= 500 and spec_fmax >= 500
        One mark bottom: log10(500), "no", "yes", "no", "500"
    endif
    if spec_fmin <= 1000 and spec_fmax >= 1000
        One mark bottom: log10(1000), "no", "yes", "no", "1k"
    endif
    if spec_fmin <= 2000 and spec_fmax >= 2000
        One mark bottom: log10(2000), "no", "yes", "no", "2k"
    endif
    if spec_fmin <= 5000 and spec_fmax >= 5000
        One mark bottom: log10(5000), "no", "yes", "no", "5k"
    endif
    if spec_fmin <= 10000 and spec_fmax >= 10000
        One mark bottom: log10(10000), "no", "yes", "no", "10k"
    endif
    if spec_fmax >= 16000
        One mark bottom: log10(16000), "no", "yes", "no", "16k"
    endif

    # Manual legend.
    Colour: "{0.42, 0.42, 0.42}"
    Draw line: log_fmax - 0.22 * (log_fmax-log_fmin), spec_ymin + 0.15 * (spec_ymax-spec_ymin), log_fmax - 0.16 * (log_fmax-log_fmin), spec_ymin + 0.15 * (spec_ymax-spec_ymin)
    Colour: "Black"
    Text: log_fmax - 0.15 * (log_fmax-log_fmin), "left", spec_ymin + 0.15 * (spec_ymax-spec_ymin), "half", "input"
    Colour: "{0.18, 0.42, 0.62}"
    Line width: 1.5
    Draw line: log_fmax - 0.22 * (log_fmax-log_fmin), spec_ymin + 0.07 * (spec_ymax-spec_ymin), log_fmax - 0.16 * (log_fmax-log_fmin), spec_ymin + 0.07 * (spec_ymax-spec_ymin)
    Colour: "Black"
    Line width: 1
    Text: log_fmax - 0.15 * (log_fmax-log_fmin), "left", spec_ymin + 0.07 * (spec_ymax-spec_ymin), "half", "output"

    # Bottom summary strip.
    Select outer viewport: 0.2, 7.8, 5.60, 6.05
    Select inner viewport: 0.2, 7.8, 5.60, 6.05
    Axes: 0, 1, 0, 1
    Colour: "{0.94, 0.94, 0.94}"
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text: 0.5, "centre", 0.68, "half", "base=" + fixed$(shift_base, 2) + " | depth=" + fixed$(shift_depth, 2) + " | shift phase=" + fixed$(shift_phase_span, 1) + " rad | env=" + fixed$(envelope_strength, 1) + " | mod depth=" + fixed$(modulation_depth, 2) + " | mod phase=" + fixed$(modulation_phase_span, 1) + " rad | wet=" + fixed$(wet_dry_percent, 0) + "%"
    Text: 0.5, "centre", 0.28, "half", "QC: input peak=" + fixed$(input_peak, 4) + " | output peak=" + fixed$(output_peak, 4) + " | RMS ratio=" + fixed$(rms_ratio, 3) + " | output channels=" + fixed$(result_ch, 0)

    # Cleanup visualization objects.
    removeObject: vis_input, vis_output, in_spectrum, out_spectrum, in_ltas, out_ltas
endif

# Remove the processing envelope only after visualization has used it.
if envelope_sound <> 0
    removeObject: envelope_sound
endif

# ===================================================================
# FINAL INFO
# ===================================================================

selectObject: result
appendInfoLine: ""
appendInfoLine: "Processing complete."
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Channels: ", result_ch
appendInfoLine: "Input peak: ", fixed$(input_peak, 5), " | Output peak: ", fixed$(output_peak, 5)
appendInfoLine: "RMS ratio (out/in): ", fixed$(rms_ratio, 3)
if bypass
    appendInfoLine: "QC: exact dry bypass path used."
endif

if play_after
    Play
endif

selectObject: result
