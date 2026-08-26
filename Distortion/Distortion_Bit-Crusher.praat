# ============================================================
# Praat AudioTools - Distortion___Bit-Crusher.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Distortion & Bit-Crusher Suite — two distinct effect modes:
#
#   (1) Bit Crusher: amplitude quantization, producing a staircase
#       transfer function. Two quantizers are offered. The legacy
#       one sets a STEP of 1/N, which over -1..+1 yields 2N+1
#       levels (N=4 gives nine, not four) and does not bound
#       samples outside full scale. The second maps -1..+1 onto
#       exactly N levels with clamping. Smaller N = harsher.
#
#   (2) Harsh Distortion: replaces the input waveform entirely
#       with a synthesized texture whose ONLY connection to the
#       input is the sample-by-sample SIGN (positive vs negative).
#       The result is a square-wave-like signal modulated by an
#       AM oscillator and a periodic gate. The original waveform's
#       amplitude information is discarded; only zero-crossings
#       remain. This is intentionally extreme — useful for
#       industrial / glitch / noise applications. Note that a
#       sample of exactly zero has no sign; Zero_handling decides
#       what happens to it, and the default (negative) means
#       digital silence becomes full synthesized texture whenever
#       the gate is open.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.5.1 (2026):
#   - Validation is now mode-aware throughout: Harsh-only gate and AM
#     parameters are checked only in Harsh Distortion mode, and the
#     output target is checked only when an output-scaling mode uses it.
#   - Base_amplitude and Mod_amplitude are now real fields so 0 is a
#     valid Custom value; negative values are rejected in Harsh mode.
#   - Scale_peak renamed Target_peak. The former "Conditional limiter"
#     is now labelled "Attenuate to target only if peak > target"; the
#     DSP remains a single global peak-scaling operation, not a limiter.
#
# Changelog v0.5 (2026):
#   - VISUALIZATION STANDARDIZATION ONLY; audio/DSP, analysis,
#     parameter mapping and rendering logic are unchanged.
#   - Adopted the Praat AudioTools 8-inch page convention with
#     explicit inner viewports, standard title/subtitle, suite
#     typography, neutral panel backgrounds, summary strip and
#     full-page Picture export viewport.
#   - Preserved the script-specific nonlinear/diagnostic panels;
#     the visualization remains a direct explanation of the
#     transformation rather than a generic replacement plot.
#
# Changelog v0.4b:
#   - FIXED: the four Bit Crush presets are named "step 1/N" but set
#     only effect_type and quantization_steps, leaving Quantizer at
#     whatever the form held. Selecting "Bit Crush: Default
#     (step 1/4)" with Quantizer on "True N levels" produced 4
#     levels, not the 9 the name promises - the Info window
#     reported the truth while the preset name described a
#     different operation. Those presets now pin quantizer = 1.
#   - FIXED (ordering): validation ran BEFORE the presets were
#     applied, so it judged stale form values. Choosing "Harsh:
#     Balanced" with a leftover Quantization_steps of 1 aborted the
#     script over a parameter that mode never touches, and a Bit
#     Crush preset that would have replaced the value was blocked
#     by the value it was about to replace. Validation now runs
#     after the presets and only for the active mode.
#   - FIXED: normalization called Scale peak and only then tested
#     prePeak > 0 - the guard came after the operation it guards.
#     A silent result is a reachable state by design now that
#     Gate_duty_cycle_s may be 0 and Zero_handling can preserve
#     silence, so the order mattered. Reported as "silent output -
#     normalization skipped".
#   - FIXED: the zoom panel queried and drew 0..zoomDur, assuming
#     the time domain starts at 0 - on exactly the Sounds
#     Phase_origin was added to support (xmin = 12.4 s and such) it
#     was reading outside the data. It now runs from xmin.
#   - The character guide is keyed on the actual level count rather
#     than the raw parameter, and states it.
#   - The Harsh diagram's SIGN box shows what zero maps to.
#   - Scale_peak is capped at 1.0; above that the conditional
#     limiter would leave peaks past full scale and normalization
#     would aim deliberately beyond it.
#
# Changelog v0.4:
#   - FIXED (the central mislabel): Quantization_levels was not a
#     level count. `round(x * q) / q` sets a STEP of 1/q, and over
#     -1..+1 that gives 2q+1 distinct values - measured, q=2 gives
#     5 levels (-1, -0.5, 0, 0.5, 1), q=3 gives 7, q=4 gives 9,
#     q=8 gives 17. So the preset "Bit Crush: Extreme (2 levels)"
#     produced five. The "Effective bits" line compounded it,
#     reporting ~2 bits for q=4 when nine states need four. The
#     parameter is renamed Quantization_steps, the level count is
#     computed rather than assumed, the bit figure is derived from
#     the real state count, and the preset names now read
#     "step 1/N". Quantizer option 2 gives a genuine N levels
#     across -1..+1 with clamping.
#   - Quantization_steps is `integer` and validated. As `positive`
#     it accepted 3.7 or 0.5 while being used as a quantizer
#     divisor, a level count, a drawing loop bound and the base of
#     a log.
#   - NEW Zero_handling. `if self > 0 then 1 else -1 fi` maps a
#     sample of exactly ZERO to -1, so digital silence did not stay
#     silent: it became a full-amplitude negative-polarity texture
#     whenever the gate was open, and so did every digital pause
#     inside ordinary material. A zero sample has no sign and v0.3
#     chose one for it. Default keeps the v0.3 reading.
#   - NEW Phase_origin. The gate and AM read `x`, ABSOLUTE time, so
#     the v0.3 claim that the gate starts open only holds when the
#     Sound's domain starts at 0. A Sound extracted with times
#     preserved might start at 12.4 s, making the opening gate
#     phase 12.4 mod gate_period - possibly shut. Phase now runs
#     from the Sound's own start by default.
#   - Output_level replaces the unconditional `Scale peak`. Always
#     normalizing meant the ABSOLUTE scale of Base_amplitude and
#     Mod_amplitude stopped mattering - scaling both by the same
#     factor changed almost nothing, since only their ratio
#     survived. Normalize remains the default.
#   - The staircase panel now draws the selected quantizer and
#     carries the render's actual peak scaling, so it describes the
#     finished output rather than the pre-normalization function;
#     its vertical range follows the drawn curve.
#   - Gate_duty_cycle_s is clamped to Gate_period_s with a note.
#     Unbounded, duty > period made `x mod period < duty` always
#     true - a permanently open gate reported as e.g. "160% open".
#     The field is now `real`, so a fully closed gate (duty 0) can
#     be requested; `positive` forbade it.
#   - A note fires when Mod_amplitude > Base_amplitude, where the
#     AM envelope goes negative and adds polarity inversions from
#     the modulator rather than the input.
#   - The waveform panel legend no longer says "blue=L orange=R"
#     on files with more than two channels; it says how many of how
#     many are shown.
#
# Changelog v0.3:
#   - Fix (Harsh mode gate logic): v0.2's gate condition was
#       if (x mod gate_period > gate_duty) then 1 else 0 fi
#     which made gate_duty represent the SILENT portion at the
#     start of each cycle, not the ON portion as the parameter
#     name implied. v0.3 flips the comparison:
#       if (x mod gate_period < gate_duty) then 1 else 0 fi
#     so gate_duty_cycle_s now genuinely means "how long the gate
#     is open per cycle," matching the parameter name.
#     [v0.4 correction: this was overstated. The DUTY RATIO is
#     unchanged and the modulation rate is unchanged, but the gate
#     phase is inverted within each cycle, which moves it relative
#     to the source's zero crossings, the AM oscillator and the
#     transient structure. On periodic material the output waveform
#     — and potentially the spectrum — differs. The accurate claim
#     is "same duty ratio, inverted gate phase", not "identical".]
#     Transient onsets in the first ~milliseconds: v0.2 silenced
#     them; v0.3 keeps them. Bit Crusher mode is unchanged.
#   - Form syntax modernized: optionmenu and choice use colons.
#   - Visualization rewritten to suite 8x8 standard:
#       Title bar + metadata subtitle
#       Panel A (left, headline): mode-specific diagnostic —
#         staircase transfer function (Bit Crusher) or
#         component diagram (Harsh Distortion)
#       Panel B (right, headline): parameter report
#       Panel C: zoom overlay (original gray + result colored,
#         first 30 ms) — replaces v0.2's two side-by-side zoom
#         panels with a single overlaid panel that makes the
#         comparison immediately visible
#       Panel D: output waveform (full file, first two channels)
#       Panel E: summary stats bar
#   - Bit Crusher output is bit-identical to v0.2. Harsh
#     Distortion has the same duty ratio as v0.2 with the gate
#     phase inverted within each cycle (see the correction above).
# Changelog v0.2:
#   - Added visualization
#   - Improved preset organization
#   - Added detailed info output
# ============================================================

form Distortion and Bit-Crusher Suite v0.5.1
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset: 1
        option Custom (use settings below)
        option Bit Crush: Default (step 1/4)
        option Bit Crush: Mild (step 1/8)
        option Bit Crush: Lo-Fi (step 1/3)
        option Bit Crush: Extreme (step 1/2)
        option Harsh: Balanced
        option Harsh: Light Drive
        option Harsh: Industrial
        option Harsh: Stutter Gate
    
    comment === Mode Selection ===
    choice Effect_type: 1
        button Bit Crusher
        button Harsh Distortion
    
    comment === Bit Crusher Parameters ===
    integer Quantization_steps 4
    comment (steps per unit; smaller = harsher)
    optionmenu Quantizer: 1
        option Steps per unit, 2N+1 levels (v0.2/v0.3)
        option True N levels over -1..+1
    
    comment === Harsh Distortion Parameters ===
    real Base_amplitude 0.5
    real Mod_amplitude 0.3
    positive Mod_frequency_Hz 100
    positive Gate_period_s 0.05
    real Gate_duty_cycle_s 0.025
    optionmenu Zero_handling: 1
        option Treat zero as negative (v0.2/v0.3)
        option Preserve silence
        option Treat zero as positive
    optionmenu Phase_origin: 1
        option Start of this Sound (v0.2/v0.3 if xmin=0)
        option Absolute time axis
    
    comment === Output ===
    optionmenu Output_level: 3
        option Preserve
        option Attenuate to target only if peak > target
        option Normalize to target
    positive Target_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
duration = Get total duration
sr = Get sampling frequency
input_n_channels = Get number of channels
xminOrig = Get start time

# === Apply Presets ===
if preset = 2
    effect_type = 1
    quantizer = 1
    quantization_steps = 4
    presetName$ = "BC_Default"
elsif preset = 3
    effect_type = 1
    quantizer = 1
    quantization_steps = 8
    presetName$ = "BC_Mild"
elsif preset = 4
    effect_type = 1
    quantizer = 1
    quantization_steps = 3
    presetName$ = "BC_LoFi"
elsif preset = 5
    effect_type = 1
    quantizer = 1
    quantization_steps = 2
    presetName$ = "BC_Extreme"
elsif preset = 6
    effect_type = 2
    base_amplitude = 0.5
    mod_amplitude = 0.3
    mod_frequency_Hz = 100
    gate_period_s = 0.05
    gate_duty_cycle_s = 0.025
    presetName$ = "HD_Balanced"
elsif preset = 7
    effect_type = 2
    base_amplitude = 0.4
    mod_amplitude = 0.2
    mod_frequency_Hz = 80
    gate_period_s = 0.07
    gate_duty_cycle_s = 0.035
    presetName$ = "HD_Light"
elsif preset = 8
    effect_type = 2
    base_amplitude = 0.7
    mod_amplitude = 0.4
    mod_frequency_Hz = 150
    gate_period_s = 0.03
    gate_duty_cycle_s = 0.015
    presetName$ = "HD_Industrial"
elsif preset = 9
    effect_type = 2
    base_amplitude = 0.6
    mod_amplitude = 0.25
    mod_frequency_Hz = 90
    gate_period_s = 0.02
    gate_duty_cycle_s = 0.01
    presetName$ = "HD_Stutter"
else
    presetName$ = "Custom"
endif

# v0.4b (items 1 and 2): validation runs AFTER the presets, and only for
# the mode that is actually active.
#   - v0.4 checked quantization_steps before any preset had been
#     applied, so choosing "Harsh: Balanced" with a leftover
#     Quantization_steps of 1 aborted the script over a parameter that
#     mode never uses - and a Bit Crush preset that would have replaced
#     the value with 4 or 8 was blocked by the stale form value.
#   - The four Bit Crush presets are NAMED "step 1/N", so they now pin
#     quantizer = 1 as well. Previously a user could select
#     "Bit Crush: Default (step 1/4)" while Quantizer was set to
#     "True N levels" and get 4 levels, not the 9 the preset name
#     promises. The Info window reported the truth, but the preset name
#     described a different operation.
if effect_type = 1
    if quantization_steps < 1
        exitScript: "Quantization steps must be at least 1."
    endif
    if quantizer = 2 and quantization_steps < 2
        exitScript: "True N-level quantization needs at least 2 levels."
    endif
endif

# v0.5.1: Target_peak is used only by the two scaling modes. Preserve
# does not consult it, so a stale form value must not block that mode.
if output_level <> 1 and target_peak > 1
    exitScript: "Target peak must be 1.0 or below (it is a full-scale target)."
endif

if input_n_channels = 1
    chanLegend$ = "(mono)"
elsif input_n_channels = 2
    chanLegend$ = "(blue=ch1  orange=ch2)"
else
    chanLegend$ = "(first 2 of " + string$(input_n_channels) + " channels shown)"
endif

if zero_handling = 2
    signBoxLabel$ = "-1 / 0 / +1"
elsif zero_handling = 3
    signBoxLabel$ = "+/- 1  (0 -> +1)"
else
    signBoxLabel$ = "+/- 1  (0 -> -1)"
endif

if zero_handling = 2
    zeroDesc$ = "preserved as silence"
elsif zero_handling = 3
    zeroDesc$ = "treated as positive"
else
    zeroDesc$ = "treated as negative (generates texture from silence)"
endif

# Get mode name and suffix
if effect_type = 1
    modeName$ = "BitCrusher"
    modeNameDisplay$ = "Bit Crusher"
    suffix$ = "_crushed"
else
    modeName$ = "HarshDistortion"
    modeNameDisplay$ = "Harsh Distortion"
    suffix$ = "_harsh"
endif

# v0.4 (item 7): Gate_duty_cycle_s had no upper bound. With
# duty > period the test `x mod period < duty` is always true, so the
# gate is permanently open while the report showed impossible figures
# like "160% open". The field was also `positive`, so a fully closed
# gate (duty 0) could not be requested at all; it is now `real` with an
# explicit range.
dutyNote$ = ""
if effect_type = 2
    if base_amplitude < 0
        exitScript: "Base amplitude cannot be negative."
    endif
    if mod_amplitude < 0
        exitScript: "Mod amplitude cannot be negative."
    endif
    if gate_duty_cycle_s < 0
        exitScript: "Gate duty cycle cannot be negative."
    endif
    if gate_duty_cycle_s > gate_period_s
        dutyNote$ = "  NOTE: duty (" + fixed$(gate_duty_cycle_s * 1000, 1)
            ... + " ms) exceeded the period (" + fixed$(gate_period_s * 1000, 1)
            ... + " ms) - the gate would never close. Clamped to the period."
        gate_duty_cycle_s = gate_period_s
    endif
endif

# v0.4 (item 8): the AM envelope is base + mod*sin(wt). When
# mod > base it goes negative for part of each cycle, so the output
# carries sign inversions coming from the MODULATOR, not from the input
# - which contradicts the description's "the ONLY connection to the
# input is the sample-by-sample SIGN". The presets all keep base > mod;
# Custom never checked. Allowed, but no longer silent.
amNote$ = ""
if effect_type = 2 and mod_amplitude > base_amplitude
    amNote$ = "  NOTE: Mod_amplitude > Base_amplitude - the AM envelope goes negative, adding polarity inversions from the modulator itself (bipolar AM)."
endif

# v0.4 (item 6): the gate and the AM oscillator read `x`, Praat's
# ABSOLUTE time. The v0.3 changelog claims the gate starts open so
# transient onsets survive, but that is only true when the Sound's time
# domain starts at 0. A Sound extracted with times preserved can start
# at, say, 12.4 s, in which case the opening gate phase is
# 12.4 mod gate_period and the gate may well be shut. Phase is now
# measured from the Sound's own start by default.
if phase_origin = 2
    phaseOffset = 0
    phaseDesc$ = "absolute time axis"
else
    phaseOffset = xminOrig
    phaseDesc$ = "start of this Sound"
endif

# === Info ===
writeInfoLine: "=== Distortion & Bit-Crusher Suite v0.5.1 ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s, ", input_n_channels, " ch, starts at ", fixed$(xminOrig, 3), " s)"
appendInfoLine: "Mode: ", modeNameDisplay$
appendInfoLine: "Preset: ", presetName$
if dutyNote$ <> ""
    appendInfoLine: dutyNote$
endif
if amNote$ <> ""
    appendInfoLine: amNote$
endif
appendInfoLine: ""

if effect_type = 1
    # v0.4 CRITICAL (item 1): the parameter was called
    # Quantization_levels and the presets were named "4 levels",
    # "2 levels" and so on - but `round(x * q) / q` sets a STEP of 1/q,
    # and over -1..+1 that yields 2q+1 distinct values, not q. Measured:
    # q=2 gives 5 levels (-1, -0.5, 0, 0.5, 1), q=3 gives 7, q=4 gives 9,
    # q=8 gives 17. The "effective bits" line was wrong by roughly a
    # factor of two in the same direction - it reported ~2 bits for q=4
    # while nine states need four. The parameter is renamed to what it
    # is, the level count is computed rather than assumed, and Quantizer
    # option 2 provides a genuine N-level mapping.
    if quantizer = 2
        actualLevels = quantization_steps
        appendInfoLine: "Quantization: ", actualLevels, " levels over -1..+1 (clamped)"
    else
        actualLevels = 2 * quantization_steps + 1
        appendInfoLine: "Quantization: step 1/", quantization_steps, " -> ", actualLevels, " levels over -1..+1 (unbounded)"
    endif
    appendInfoLine: "Bits needed: ", ceiling(ln(actualLevels)/ln(2)), " (for ", actualLevels, " states)"
    if quantizer = 2
        quantSummary$ = string$(actualLevels) + " levels"
    else
        quantSummary$ = "step 1/" + string$(quantization_steps) + " (" + string$(actualLevels) + " levels)"
    endif
else
    appendInfoLine: "Base amplitude: ", fixed$(base_amplitude, 2)
    appendInfoLine: "Mod amplitude: ", fixed$(mod_amplitude, 2)
    appendInfoLine: "Mod frequency: ", fixed$(mod_frequency_Hz, 0), " Hz"
    appendInfoLine: "Gate period: ", fixed$(gate_period_s * 1000, 1), " ms"
    appendInfoLine: "Gate duty: ", fixed$(gate_duty_cycle_s * 1000, 1), " ms (",
        ... fixed$(gate_duty_cycle_s / gate_period_s * 100, 0), "% open)"
    appendInfoLine: "Zero samples: ", zeroDesc$
    appendInfoLine: "Phase origin: ", phaseDesc$
    actualLevels = 0
    quantSummary$ = ""
endif
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Processing..."

selectObject: original
Copy: original_name$ + suffix$ + "_" + presetName$
result = selected("Sound")

if effect_type = 1
    # === BIT CRUSHER ===
    q_str$ = string$(quantization_steps)
    selectObject: result
    if quantizer = 2
        # True N levels across -1..+1, clamped first so nothing outside
        # full scale extends the quantizer's range.
        lm1$ = string$(quantization_steps - 1)
        Formula: "2 * round((min(max(self, -1), 1) + 1) / 2 * " + lm1$ + ") / " + lm1$ + " - 1"
    else
        # Legacy: step of 1/q, giving 2q+1 levels over -1..+1.
        Formula: "round(self * " + q_str$ + ") / " + q_str$
    endif
    
else
    # === HARSH DISTORTION ===
    # sign(x) * (base + mod*sin(omega*t)) * gate
    #
    # FIX v0.3: gate condition flipped from "> duty" (v0.2 — duty
    # was actually the silent portion) to "< duty" (v0.3 — duty
    # is now the open portion, matching the parameter name).
    #
    # v0.4 (item 5): the sign extraction was
    # `if self > 0 then 1 else -1 fi`, which maps a sample of exactly
    # ZERO to -1. Digital silence therefore did not stay silent - it
    # became a full-amplitude synthesized texture of negative polarity
    # whenever the gate was open, and any digital pause inside ordinary
    # material did the same. A zero sample has no sign; v0.3 picked one
    # for it. All three readings are now available, with the legacy one
    # as default.
    #
    # v0.4 (item 6): `x` is absolute time, so phase now runs from
    # (x - phaseOffset) where phaseOffset is the Sound's own start.
    
    base$ = string$(base_amplitude)
    mod_amp$ = string$(mod_amplitude)
    mod_freq$ = string$(mod_frequency_Hz)
    gate_per$ = string$(gate_period_s)
    gate_duty$ = string$(gate_duty_cycle_s)
    phase$ = string$(phaseOffset)
    
    if zero_handling = 2
        sign$ = "(if self > 0 then 1 else if self < 0 then -1 else 0 fi fi)"
    elsif zero_handling = 3
        sign$ = "(if self < 0 then -1 else 1 fi)"
    else
        sign$ = "(if self > 0 then 1 else -1 fi)"
    endif
    
    t$ = "(x - " + phase$ + ")"
    
    selectObject: result
    Formula: sign$
        ... + " * (" + base$ + " + " + mod_amp$ + " * sin(2*pi*" + mod_freq$ + " * " + t$ + "))"
        ... + " * (if (" + t$ + " mod " + gate_per$ + " < " + gate_duty$ + ") then 1 else 0 fi)"
endif

# Output level
# v0.4 (items 3 and 4): v0.3 always applied peak scaling.
# That is normalization, not a ceiling: a quiet source was lifted to the
# target, a loud one pulled down, and the ABSOLUTE scale of
# Base_amplitude and Mod_amplitude stopped mattering - scaling both by
# the same factor in Harsh mode produced almost no change, since only
# their ratio survived. Normalize stays the default so v0.3 renders are
# reproducible.
selectObject: result
prePeak = Get absolute extremum: 0, 0, "None"
appendInfoLine: "  Peak before output stage: ", fixed$(prePeak, 4)

levelScale = 1
if output_level = 1
    levelDesc$ = "preserved"
    if prePeak > 1.0
        appendInfoLine: "  WARNING: peak is ", fixed$(prePeak, 3), " - above 1.0 it will clip on playback or export."
    endif
elsif output_level = 2
    if prePeak > target_peak
        selectObject: result
        Scale peak: target_peak
        levelScale = target_peak / prePeak
        levelDesc$ = "attenuated to " + fixed$(target_peak, 2)
    else
        levelDesc$ = "unchanged"
    endif
else
    # v0.4b (item 3): v0.4 called Scale peak first and only then tested
    # prePeak > 0, so the guard arrived after the operation it was meant
    # to protect. A fully silent result is now reachable by design -
    # Gate_duty_cycle_s may legitimately be 0, and Zero_handling
    # "Preserve silence" on a silent source does the same - so this is a
    # real path, not a theoretical one.
    if prePeak > 0
        selectObject: result
        Scale peak: target_peak
        levelScale = target_peak / prePeak
        levelDesc$ = "normalized to " + fixed$(target_peak, 2)
    else
        levelDesc$ = "silent output - normalization skipped"
    endif
endif
appendInfoLine: "  Output level: ", levelDesc$

# === Final stats ===
selectObject: result
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"
nResultCh = Get number of channels

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_visualization
    pageHeight = 8.0
    Line width: 1
    Colour: "Black"
    Solid line
    vizName$ = replace$(original_name$, "_", "\_ ", 0)
    Erase all
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Distortion & Bit-Crusher Suite v0.5.1##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    if effect_type = 1
        Text: 0.5, "centre", 0.22, "half",
            ... vizName$
            ... + "  |  " + modeNameDisplay$
            ... + "  |  " + presetName$
            ... + "  |  " + quantSummary$
    else
        Text: 0.5, "centre", 0.22, "half",
            ... vizName$
            ... + "  |  " + modeNameDisplay$
            ... + "  |  " + presetName$
            ... + "  |  Base+Mod: " + fixed$(base_amplitude, 2) + "+" + fixed$(mod_amplitude, 2)
            ... + " @ " + fixed$(mod_frequency_Hz, 0) + " Hz"
            ... + "  |  Gate: " + fixed$(gate_period_s * 1000, 0) + "/"
            ... + fixed$(gate_duty_cycle_s * 1000, 0) + " ms"
    endif
    
    # ----------------------------------------------------------
    # PANEL A: MODE-SPECIFIC DIAGNOSTIC  (left, headline)
    # Bit Crusher: staircase transfer function
    # Harsh Distortion: component pipeline diagram
    # ----------------------------------------------------------
    Select outer viewport: 0, 4, 0.75, 4.60
    Select inner viewport: 0.60, 3.85, 0.95, 4.40
    
    if effect_type = 1
        # ==== BIT CRUSHER STAIRCASE ====
        # v0.4: the staircase can now exceed +/-1 once levelScale is
        # folded in, so the vertical range follows the drawn function.
        yLimQ = 1.2
        if levelScale > 1
            yLimQ = 1.2 * levelScale
        endif
        
        Axes: -1.2, 1.2, -yLimQ, yLimQ
        Paint rectangle: "{0.97, 0.97, 0.97}", -1.2, 1.2, -yLimQ, yLimQ
        
        # Grid
        Colour: "{0.85, 0.85, 0.88}"
        Line width: 1
        Draw line: -1.2, 0, 1.2, 0
        Draw line: 0, -yLimQ, 0, yLimQ
        
        # y=x reference
        Dotted line
        Colour: "{0.65, 0.65, 0.70}"
        Draw line: -1.2, -1.2, 1.2, 1.2
        Solid line
        
        # Draw staircase
        # v0.4: draws whichever quantizer is selected, and carries the
        # render's actual peak scaling so the panel describes the
        # finished output rather than the pre-normalization function.
        Colour: "{0.30, 0.50, 0.78}"
        Line width: 2
        if quantizer = 2
            nLev = quantization_steps
            for i from 0 to nLev - 1
                yVal = (2 * i / (nLev - 1) - 1) * levelScale
                xCentre = 2 * i / (nLev - 1) - 1
                xStart = xCentre - 1 / (nLev - 1)
                xEnd = xCentre + 1 / (nLev - 1)
                if xStart < -1
                    xStart = -1
                endif
                if xEnd > 1
                    xEnd = 1
                endif
                if xStart < xEnd
                    Draw line: xStart, yVal, xEnd, yVal
                endif
            endfor
        else
            step = 1 / quantization_steps
            for i from -quantization_steps to quantization_steps
                xStart = (i - 0.5) * step
                xEnd = (i + 0.5) * step
                yVal = i * step * levelScale
                
                if xStart < -1
                    xStart = -1
                endif
                if xEnd > 1
                    xEnd = 1
                endif
                
                if xStart < xEnd
                    Draw line: xStart, yVal, xEnd, yVal
                endif
            endfor
        endif
        
        # Vertical risers between steps (so it looks like a true staircase)
        Colour: "{0.55, 0.70, 0.85}"
        Line width: 1
        if quantizer = 2
            nLev = quantization_steps
            for i from 0 to nLev - 2
                xRiser = 2 * i / (nLev - 1) - 1 + 1 / (nLev - 1)
                yLow = (2 * i / (nLev - 1) - 1) * levelScale
                yHigh = (2 * (i + 1) / (nLev - 1) - 1) * levelScale
                if xRiser >= -1 and xRiser <= 1
                    Draw line: xRiser, yLow, xRiser, yHigh
                endif
            endfor
        else
            for i from -quantization_steps to quantization_steps - 1
                xRiser = (i + 0.5) * step
                yLow = i * step * levelScale
                yHigh = (i + 1) * step * levelScale
                if xRiser >= -1 and xRiser <= 1 and abs(yLow) <= yLimQ and abs(yHigh) <= yLimQ
                    Draw line: xRiser, yLow, xRiser, yHigh
                endif
            endfor
        endif
        Line width: 1
        
        Colour: "Black"
        Draw inner box
        Font size: 6
        Text left: "yes", "Output"
        Text bottom: "yes", "Input"
        
    else
        # ==== HARSH DISTORTION COMPONENT DIAGRAM ====
        Axes: 0, 1, 0, 6
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 6
        
        # Five vertical stages (input -> sign -> mod -> gate -> output)
        # Stage 1: Input
        yTop = 5.6
        yBot = 5.0
        Paint rectangle: "{0.85, 0.85, 0.88}", 0.10, 0.90, yBot, yTop
        Colour: "Black"
        Font size: 7
        Text: 0.50, "centre", (yTop + yBot) / 2 + 0.10, "half", "INPUT"
        Font size: 7
        Colour: "{0.45, 0.45, 0.45}"
        Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half", "(audio)"
        
        Colour: "{0.45, 0.45, 0.45}"
        Draw arrow: 0.50, 5.0, 0.50, 4.7
        
        # Stage 2: Sign extraction
        yTop = 4.6
        yBot = 4.0
        Paint rectangle: "{0.85, 0.65, 0.65}", 0.10, 0.90, yBot, yTop
        Colour: "Black"
        Font size: 7
        Text: 0.50, "centre", (yTop + yBot) / 2 + 0.10, "half", "SIGN(x)"
        Font size: 7
        Colour: "{0.40, 0.15, 0.15}"
        Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half", signBoxLabel$
        
        Colour: "{0.45, 0.45, 0.45}"
        Draw arrow: 0.50, 4.0, 0.50, 3.7
        
        # Stage 3: AM
        yTop = 3.6
        yBot = 3.0
        Paint rectangle: "{0.65, 0.85, 0.65}", 0.10, 0.90, yBot, yTop
        Colour: "Black"
        Font size: 7
        Text: 0.50, "centre", (yTop + yBot) / 2 + 0.10, "half", "AM"
        Font size: 7
        Colour: "{0.15, 0.40, 0.15}"
        Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half",
            ... fixed$(base_amplitude, 2) + " + " + fixed$(mod_amplitude, 2)
            ... + "*sin(" + fixed$(mod_frequency_Hz, 0) + " Hz)"
        
        Colour: "{0.45, 0.45, 0.45}"
        Draw arrow: 0.50, 3.0, 0.50, 2.7
        
        # Stage 4: Gate
        yTop = 2.6
        yBot = 2.0
        Paint rectangle: "{0.65, 0.65, 0.85}", 0.10, 0.90, yBot, yTop
        Colour: "Black"
        Font size: 7
        Text: 0.50, "centre", (yTop + yBot) / 2 + 0.10, "half", "GATE"
        Font size: 7
        Colour: "{0.15, 0.15, 0.40}"
        Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half",
            ... fixed$(gate_duty_cycle_s * 1000, 1) + "/"
            ... + fixed$(gate_period_s * 1000, 1) + " ms ("
            ... + fixed$(gate_duty_cycle_s / gate_period_s * 100, 0) + "% open)"
        
        Colour: "{0.45, 0.45, 0.45}"
        Draw arrow: 0.50, 2.0, 0.50, 1.7
        
        # Stage 5: Output
        yTop = 1.6
        yBot = 1.0
        Paint rectangle: "{0.65, 0.85, 0.75}", 0.10, 0.90, yBot, yTop
        Colour: "Black"
        Font size: 7
        Text: 0.50, "centre", (yTop + yBot) / 2 + 0.10, "half", "OUTPUT"
        Font size: 7
        Colour: "{0.15, 0.40, 0.30}"
        Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half", "(harsh)"
        
        # Formula at bottom
        Font size: 6
        Colour: "{0.35, 0.35, 0.45}"
        Text: 0.50, "centre", 0.50, "half", "y = sign(x) x AM(t) x gate(t)"
        
        Colour: "Black"
        Draw inner box
    endif
    
    # ----------------------------------------------------------
    # PANEL B: PARAMETER REPORT  (right, headline-height)
    # ----------------------------------------------------------
    Select outer viewport: 4, 8, 0.75, 4.60
    Select inner viewport: 4.45, 7.70, 0.95, 4.40
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
    
    if effect_type = 1
        # ==== BIT CRUSHER PARAMS ====
        Font size: 7
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.05, "left", 0.92, "half", "Mode: Bit Crusher"
        
        Font size: 7
        Colour: "{0.30, 0.45, 0.78}"
        Text: 0.10, "left", 0.82, "half", "Steps:   " + string$(quantization_steps)
        Text: 0.10, "left", 0.74, "half", "Levels:  " + string$(actualLevels)
        
        # Character guide
        Font size: 7
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.05, "left", 0.60, "half", "Character guide:"
        
        Font size: 7
        Colour: "{0.55, 0.55, 0.55}"
        Text: 0.10, "left", 0.51, "half", "2-3 levels:  extreme square"
        Text: 0.10, "left", 0.43, "half", "5-9 levels:  heavy lo-fi"
        Text: 0.10, "left", 0.35, "half", "17 levels:   mild crush"
        Text: 0.10, "left", 0.27, "half", "33+ levels:  subtle"
        
        # Highlight current setting in the guide
        # v0.4b: keyed on actualLevels, not the raw parameter. With the
        # legacy quantizer, steps = 4 means NINE levels, so keying on
        # steps put the marker in the "3-4" band while the audio sat in
        # the heavy-lo-fi range for a quite different reason.
        Font size: 7
        Colour: "{0.78, 0.30, 0.30}"
        if actualLevels <= 3
            Text: 0.10, "left", 0.16, "half", "(current: " + string$(actualLevels) + " levels, extreme)"
        elsif actualLevels <= 9
            Text: 0.10, "left", 0.16, "half", "(current: " + string$(actualLevels) + " levels, heavy lo-fi)"
        elsif actualLevels <= 17
            Text: 0.10, "left", 0.16, "half", "(current: " + string$(actualLevels) + " levels, mild crush)"
        else
            Text: 0.10, "left", 0.16, "half", "(current: " + string$(actualLevels) + " levels, subtle)"
        endif
    else
        # ==== HARSH DISTORTION PARAMS ====
        Font size: 7
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.05, "left", 0.92, "half", "Mode: Harsh Distortion"
        
        Font size: 7
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.05, "left", 0.82, "half", "Amplitude:"
        
        Font size: 7
        Colour: "{0.30, 0.45, 0.78}"
        Text: 0.10, "left", 0.74, "half", "Base:    " + fixed$(base_amplitude, 2)
        Text: 0.10, "left", 0.66, "half", "Mod:     " + fixed$(mod_amplitude, 2)
        
        Font size: 7
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.05, "left", 0.55, "half", "Modulator:"
        
        Font size: 7
        Colour: "{0.78, 0.50, 0.30}"
        Text: 0.10, "left", 0.47, "half", "Freq:    " + fixed$(mod_frequency_Hz, 0) + " Hz"
        
        Font size: 7
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.05, "left", 0.36, "half", "Gate:"
        
        Font size: 7
        Colour: "{0.40, 0.65, 0.40}"
        Text: 0.10, "left", 0.28, "half", "Period:  " + fixed$(gate_period_s * 1000, 1) + " ms"
        Text: 0.10, "left", 0.20, "half", "Open:    " + fixed$(gate_duty_cycle_s * 1000, 1) + " ms"
        
        Font size: 7
        Colour: "{0.55, 0.55, 0.55}"
        Text: 0.10, "left", 0.10, "half", "(" + fixed$(gate_duty_cycle_s / gate_period_s * 100, 0) + "% duty cycle)"
    endif
    
    Colour: "Black"
    Draw inner box
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    if effect_type = 1
        Text: 2.10, "centre", 7.30, "half", "Quantization staircase"
    else
        Text: 2.10, "centre", 7.30, "half", "Component pipeline"
    endif
    Text: 6.10, "centre", 7.30, "half", "Parameter report"
    
    # ----------------------------------------------------------
    # PANEL C: ZOOM OVERLAY  (full width, first 30 ms)
    # Original (gray) and result (mode color) overlaid.
    # Reveals quantization steps (BC) or gate pattern (HD)
    # that the full-file waveform can't show clearly.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.60, 7.70, 4.75, 5.48
    
    # v0.4b (item 4): the panel queried and drew 0..zoomDur, i.e. it
    # assumed the Sound's time domain starts at 0. Phase_origin exists
    # precisely to support Sounds extracted with times preserved
    # (xmin = 12.4 s and the like), and on exactly those Sounds this
    # panel was reading a window outside the data. It now runs from the
    # Sound's own start.
    zoomDur = 0.03
    if zoomDur > duration
        zoomDur = duration
    endif
    
    selectObject: original
    zoomStart = xminOrig
    zoomEnd = xminOrig + zoomDur
    origPeak = Get absolute extremum: zoomStart, zoomEnd, "None"
    selectObject: result
    resPeak = Get absolute extremum: zoomStart, zoomEnd, "None"
    zoomMax = origPeak
    if resPeak > zoomMax
        zoomMax = resPeak
    endif
    if zoomMax < 0.001
        zoomMax = 0.001
    endif
    zAmpViz = zoomMax * 1.15
    
    Axes: zoomStart, zoomEnd, -zAmpViz, zAmpViz
    Paint rectangle: "{0.97, 0.97, 0.97}", zoomStart, zoomEnd, -zAmpViz, zAmpViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: zoomStart, 0, zoomEnd, 0
    
    # Original (gray, behind)
    selectObject: original
    if input_n_channels > 1
        Extract one channel: 1
        zOrig = selected("Sound")
        Colour: "{0.65, 0.65, 0.65}"
        Line width: 1
        Draw: zoomStart, zoomEnd, -zAmpViz, zAmpViz, "no", "Curve"
        removeObject: zOrig
    else
        Colour: "{0.65, 0.65, 0.65}"
        Line width: 1
        Draw: zoomStart, zoomEnd, -zAmpViz, zAmpViz, "no", "Curve"
    endif
    
    # Result (colored, on top)
    selectObject: result
    if effect_type = 1
        modeColor$ = "{0.30, 0.50, 0.78}"
    else
        modeColor$ = "{0.78, 0.40, 0.40}"
    endif
    if nResultCh > 1
        Extract one channel: 1
        zRes = selected("Sound")
        Colour: modeColor$
        Line width: 1.3
        Draw: zoomStart, zoomEnd, -zAmpViz, zAmpViz, "no", "Curve"
        removeObject: zRes
    else
        Colour: modeColor$
        Line width: 1.3
        Draw: zoomStart, zoomEnd, -zAmpViz, zAmpViz, "no", "Curve"
    endif
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Zoom: first " + fixed$(zoomDur * 1000, 0) + " ms  (gray = original, color = " + modeNameDisplay$ + ")"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM (full file)
    # Only the first two channels are drawn; see the legend note below.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.60, 7.70, 5.69, 6.48
    
    selectObject: result
    outPeakViz = Get absolute extremum: 0, 0, "None"
    if outPeakViz < 0.001
        outPeakViz = 0.001
    endif
    ampViz = outPeakViz * 1.15
    
    Axes: 0, finalDur, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDur, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, finalDur, 0
    
    selectObject: result
    if nResultCh = 1
        Colour: modeColor$
        Line width: 1
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    else
        Extract one channel: 1
        vCh1 = selected("Sound")
        Colour: "{0.25, 0.50, 0.82}"
        Line width: 1
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
        removeObject: vCh1
        
        if nResultCh >= 2
            selectObject: result
            Extract one channel: 2
            vCh2 = selected("Sound")
            Colour: "{0.82, 0.45, 0.25}"
            Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
            removeObject: vCh2
        endif
    endif
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    if nResultCh > 1
        # v0.4 (item 10): processing covers every channel, but this
        # panel draws only the first two - the legend said "blue=L
        # orange=R" on 4- and 6-channel files where channels 3+ were
        # processed and simply not shown.
        Text top: "no", "Output (full file)  " + chanLegend$
    else
        Text top: "no", "Output (full file, mono)"
    endif
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.60, 7.70, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    if effect_type = 1
        Text: 0.02, "left", 0.75, "half",
            ... "##" + presetName$ + "##"
            ... + "  " + vizName$
            ... + "  |  Mode: Bit Crusher"
            ... + "  |  " + quantSummary$
        
        Text: 0.02, "left", 0.28, "half",
            ... "Level: " + levelDesc$
            ... + "  |  Output: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
    else
        Text: 0.02, "left", 0.75, "half",
            ... "##" + presetName$ + "##"
            ... + "  " + vizName$
            ... + "  |  Mode: Harsh Distortion"
            ... + "  |  Base: " + fixed$(base_amplitude, 2)
            ... + "  |  Mod: " + fixed$(mod_amplitude, 2) + " @ " + fixed$(mod_frequency_Hz, 0) + " Hz"
        
        Text: 0.02, "left", 0.28, "half",
            ... "Gate: " + fixed$(gate_duty_cycle_s * 1000, 1) + "/"
            ... + fixed$(gate_period_s * 1000, 1) + " ms ("
            ... + fixed$(gate_duty_cycle_s / gate_period_s * 100, 0) + "% open)"
            ... + "  |  Level: " + levelDesc$
            ... + "  |  Output: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
    endif
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 7
    Colour: "Black"
    Line width: 1

    # Restore complete page for Picture export / clipboard.
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDur, 2), " s"
appendInfoLine: "Peak: ", fixed$(finalPeak, 4)

if play_result
    selectObject: result
    Play
endif

selectObject: result
