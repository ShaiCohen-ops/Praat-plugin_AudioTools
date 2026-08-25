# ============================================================
# Praat AudioTools - Adaptive_Wave_Shaper.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.8.1 (2026) - output-level terminology and multichannel visualization labels
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Voice-Calibrated Wave Shaper. Despite the filename and the
#   "Adaptive" branding inherited from earlier versions, this is
#   NOT a time-varying adaptive process. It performs a single
#   analysis pass over the input, measures global jitter (pitch
#   period variation) and global shimmer (amplitude variation),
#   and uses those two values to set fixed drive and fold-count
#   parameters that are then applied uniformly to every sample.
#
#   The "adaptive" framing is honest at the file level: a rough,
#   jittery source produces a more aggressive shaping setup than
#   a stable, clean source. Within a single source, the
#   processing is constant — there is no per-frame modulation.
#
#   Wave shaping pipeline:
#     1. Multiply by drive (raw level boost)
#     2. Apply N rounds of symmetric folding through ±threshold
#     3. Optional saturation (sin / tanh / none)
#     4. Output level stage (normalize / conditional attenuation /
#        preserve)
#
#   Folding behavior note: at high drive (>2x threshold) and
#   multiple folds, the operation chains reflections that move
#   samples chaotically within [-1, +1]. This is a wavefolder's
#   characteristic harmonic-rich sound, not a bug.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.8.1 (2026):
#   - TERMINOLOGY ONLY: renamed the second Output_level choice from
#     "Conditional limiter" to "Attenuate to 0.9 only if peak > 1".
#     The DSP is unchanged: when the pre-output peak exceeds 1.0, the
#     entire file is scaled uniformly to peak 0.9; no dynamic limiter
#     is involved.
#   - VISUALIZATION: multichannel waveform labels are now channel-
#     neutral (Ch 1 / Ch 2 rather than L / R). For outputs above two
#     channels the panel states that only the first two channels are
#     shown, while the summary and Info report the full retained
#     channel count. Audio/DSP unchanged.
#
# Changelog v0.8 (2026):
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
# Changelog v0.7:
#   - FIXED: the transfer function curve was clamped to +/-1.4 in
#     VALUE, which the audio engine never does. Whenever the shaper
#     produced more than 1.4 the panel drew a flat plateau instead
#     of the real function - drive 4, threshold 0.6, one fold turns
#     an input of 1.2 into -3.6, and the panel showed -1.4. Since
#     the title promises the shaping function BEFORE the output
#     level stage, that clamp rewrote the function rather than
#     cropping the view. The curve's extent is now measured in a
#     pre-pass and the Y axis sized to fit it (floor +/-1.5, 10%
#     headroom); the axis label reports the range, since this panel
#     draws no numeric marks.
#   - The header subtitle now reports satApplied$ rather than
#     satName$, so Drive-only fallback no longer shows "Sat: Sin"
#     while saturation is switched off. The summary bar already
#     did this.
#   - Added a final ordering guard on the derived period limits
#     after the one-sample floor is applied.
#
# Changelog v0.6:
#   - FIXED (the curve did not describe the sound): the transfer
#     function panel folded with two independent `if` statements,
#     so a positive reflection overshooting below -threshold was
#     reflected a SECOND time in the same pass. The audio Formula
#     uses `if ... else if ... fi fi` - at most one reflection per
#     pass, overshoot carried to the next. With the Default preset
#     an input of 1.2 gave -1.2 in the audio and 0 on the curve;
#     on Aggressive Drive the two disagreed across 37.5% of the
#     input range, max error 3.6. Both the curve and its prevY
#     seed now mirror the Formula exactly.
#   - FIXED: Base_drive / Jitter_sensitivity / Shimmer_sensitivity
#     were overwritten by every preset with no Custom path, so all
#     three were editable fields that could not affect anything.
#     Preset 6 "Custom" added; presets 1-5 unchanged.
#   - FIXED: the unpitched fallback reported "clean shaping (drive
#     only)" and then applied preset drive, one fold and
#     saturation - on Maximum Destruction that meant 5x drive, a
#     fold and a sine blend on an unpitched source. The message now
#     describes the actual behaviour, and Unpitched_fallback offers
#     genuine drive-only shaping.
#   - FIXED: pitch_detected served as both "pulses found" and
#     "jitter defined", and shimmer was computed regardless - so a
#     file could be reported as "no pitch detected" while its
#     shimmer was still setting the fold count. Now three separate
#     flags (pulsesValid / jitterValid / shimmerValid), reported
#     individually in the info window and the report panel.
#   - FIXED: jitter and shimmer used Praat's fixed 0.0001-0.02 s
#     period window regardless of Min/Max_pitch_Hz. The period
#     limits are now derived from the pitch range, and the range
#     itself is validated (min < max).
#   - CORRECTED: the "safe ranges" comment. Bounding drive at 8 and
#     folds at 8 bounds the PARAMETERS, not the peak - each pass
#     reduces the excess by only 2 * threshold, so drive 8 with
#     threshold 0.01 still leaves about 7.84 after eight folds. The
#     pre-output peak is now reported, Output_level replaces the
#     Normalize boolean (normalize / conditional attenuation /
#     preserve; originally labelled conditional limiter), and Preserve
#     warns when the peak exceeds 1.0.
#   - CORRECTED: the sin blend was described as non-monotonic. Its
#     derivative 0.6*cos(2x) + 0.7 stays within [0.1, 1.3] and never
#     reaches zero, so it is monotonically increasing everywhere -
#     a sinusoidally rippled monotonic saturation.
#   - CORRECTED: the transfer panel title now reads "Static shaping
#     function (before output level stage)", since the curve does
#     not include the file-dependent peak normalization.
#   - Fixed a duplicated "Changelog v0.4" heading in this header.
#
# Changelog v0.5:
#   - Removed the LTAS comparison panel (and its associated
#     Convert to mono / To Spectrum / To Ltas pipeline that ran
#     twice on every script invocation). The spectral diagnostic
#     was nice to have but added significant per-run latency on
#     a script users tweak iteratively. Speed now matches v0.2.
#   - Visualization simplified: Panel A = transfer function
#     (headline), Panel B = parameter report, Panel C = output
#     waveform, Panel D = summary bar. Standard suite layout
#     minus the spectral panel.
# Changelog v0.4b:
#   - (REVERTED in v0.5): LTAS comparison panel.
# Changelog v0.4:
#   - Reverted v0.3's time-varying mode (was too slow to be
#     practical). Static analysis only.
#   - Fix (BUG): undefined pitch fallback. v0.2 substituted 0.5
#     (50% jitter, extreme!) when pitch detection failed —
#     causing noise/percussive sources to silently get the most
#     aggressive shaping. v0.4+ falls back to 0 (assume clean)
#     and emits a warning.
#   - Speed: combined the two fold formulas into one if/else
#     branch. v0.2 ran 2 * fold_count formula passes; v0.4+ runs
#     fold_count passes. ~2x speedup on the fold step.
#   - NEW: Saturation_type form parameter. Sin / Tanh / None
#     (pure folding only). (The claim that the sin blend is
#     non-monotonic was wrong - corrected in v0.6.)
#   - NEW: Fold_threshold exposed as form parameter
#     (was hardcoded to 0.6 in v0.2).
#   - Form syntax modernized: optionmenu uses colon.
#   - Visualization rewritten to suite 8x8 standard.
# Changelog v0.2:
#   - Actually analyzes jitter/shimmer from audio
#   - Fixed input check and selection syntax
#   - Added visualization
#   - Added transfer function display
# ============================================================

form Adaptive Wave Shaper v0.8.1
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset: 1
        option Default
        option Gentle Saturation
        option Aggressive Drive
        option Fold Emphasis
        option Maximum Destruction
        option Custom (use Base Parameters below)
    
    comment === Base Parameters (Custom preset only) ===
    positive Base_drive 2.0
    positive Jitter_sensitivity 1.5
    comment (how much jitter affects drive)
    positive Shimmer_sensitivity 1.2
    comment (how much shimmer affects folding)
    
    comment === Wave Shaping ===
    optionmenu Saturation_type: 1
        option Sin blend (rippled)
        option Tanh (cleaner)
        option None (folding only)
    positive Fold_threshold 0.6
    
    comment === Analysis ===
    positive Min_pitch_Hz 75
    positive Max_pitch_Hz 600
    optionmenu Unpitched_fallback: 1
        option Base shaping (drive + 1 fold + saturation)
        option Drive only (no folding, no saturation)
    
    comment === Output ===
    optionmenu Output_level: 1
        option Normalize to 0.9
        option Attenuate to 0.9 only if peak > 1
        option Preserve
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

# === Apply Presets ===
if preset = 1
    presetName$ = "Default"
    base_drive = 2.0
    jitter_sensitivity = 1.5
    shimmer_sensitivity = 1.2
elsif preset = 2
    presetName$ = "Gentle"
    base_drive = 1.2
    jitter_sensitivity = 1.0
    shimmer_sensitivity = 0.8
elsif preset = 3
    presetName$ = "Aggressive"
    base_drive = 4.0
    jitter_sensitivity = 2.0
    shimmer_sensitivity = 1.8
elsif preset = 4
    presetName$ = "FoldEmphasis"
    base_drive = 2.5
    jitter_sensitivity = 1.2
    shimmer_sensitivity = 2.5
elsif preset = 5
    presetName$ = "Maximum"
    base_drive = 5.0
    jitter_sensitivity = 3.0
    shimmer_sensitivity = 3.0
else
    # v0.6 (item 2): v0.5 had no Custom option, so Base_drive,
    # Jitter_sensitivity and Shimmer_sensitivity were overwritten on
    # every path through the form - three editable fields that could
    # never affect anything. Preset 6 keeps the entered values;
    # presets 1-5 keep their previous indices and values.
    presetName$ = "Custom"
endif

# v0.6 (item 5): validate the pitch range, and derive the jitter/shimmer
# period limits from it. v0.5 let the user set Min/Max_pitch_Hz for the
# To Pitch call while jitter and shimmer kept Praat's fixed 0.0001-0.02 s
# window (10000-50 Hz) - so changing the pitch range did not change which
# periods the perturbation measures were allowed to accept.
if min_pitch_Hz >= max_pitch_Hz
    exitScript: "Min_pitch_Hz (" + fixed$(min_pitch_Hz, 1) + ") must be below Max_pitch_Hz (" + fixed$(max_pitch_Hz, 1) + ")."
endif

shortestPeriod = 1 / max_pitch_Hz / 1.5
longestPeriod = 1 / min_pitch_Hz * 1.5
if shortestPeriod < 1 / sr
    shortestPeriod = 1 / sr
endif
# Final ordering guard: at an extreme sample rate the one-sample floor
# could in principle meet or pass longestPeriod.
if shortestPeriod >= longestPeriod
    exitScript: "Derived period limits are inconsistent (shortest "
        ... + fixed$(shortestPeriod, 6) + " s >= longest " + fixed$(longestPeriod, 6)
        ... + " s). Widen the pitch range or use a higher sample rate."
endif

# Saturation display name
if saturation_type = 1
    satName$ = "Sin"
elsif saturation_type = 2
    satName$ = "Tanh"
else
    satName$ = "None"
endif

# === Info ===
writeInfoLine: "=== Adaptive Wave Shaper v0.8.1 ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s, ", input_n_channels, " ch)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Saturation: ", satName$
appendInfoLine: "Fold threshold: ", fixed$(fold_threshold, 3)
appendInfoLine: ""

# ============================================================
# ANALYZE JITTER AND SHIMMER  (single global pass)
# ============================================================

appendInfoLine: "Analyzing voice quality metrics..."

selectObject: original

# Convert to mono for analysis (regardless of input channels)
mono = Convert to mono

# Pitch + PointProcess
selectObject: mono
To Pitch: 0.0, min_pitch_Hz, max_pitch_Hz
pitch = selected("Pitch")

selectObject: mono
plusObject: pitch
To PointProcess (cc)
pp = selected("PointProcess")

# v0.6 (item 4): v0.5 used one flag, pitch_detected, as both "pulses were
# found" and "jitter was defined" - and then went on to compute shimmer
# regardless. A file whose jitter was undefined but whose shimmer was
# fine had pitch_detected = 0, so the report and the visualization said
# "no pitch detected - clean fallback" while the shimmer value was still
# setting the fold count. The three conditions are now tracked
# separately and reported for what they are.
pulsesValid = 1
jitterValid = 0
shimmerValid = 0

selectObject: pp
nPulses = Get number of points
if nPulses < 4
    pulsesValid = 0
endif

if pulsesValid = 1
    selectObject: pp
    jitter_local = Get jitter (local): 0, 0, shortestPeriod, longestPeriod, 1.3
    if jitter_local = undefined
        jitter_local = 0
    else
        jitterValid = 1
    endif
    
    selectObject: mono
    plusObject: pp
    shimmer_local = Get shimmer (local): 0, 0, shortestPeriod, longestPeriod, 1.3, 1.6
    if shimmer_local = undefined
        shimmer_local = 0
    else
        shimmerValid = 1
    endif
else
    # FIX v0.4+: undefined pitch falls back to 0 (clean), not 0.5.
    # v0.2 silently treated unpitched audio (noise, percussion) as
    # 50% jitter, triggering maximum aggression on these sources.
    jitter_local = 0
    shimmer_local = 0
endif

# v0.6 (item 3): v0.5 printed "falling back to clean shaping (drive
# only)" and then applied preset drive, one fold and saturation anyway -
# on Maximum Destruction an unpitched source still got 5x drive, a fold
# and a sine blend, which is not clean shaping by any reading. The
# message now describes what actually happens, and Unpitched_fallback
# offers real drive-only shaping for those who wanted it.
calibrated = 1
if pulsesValid = 0
    appendInfoLine: "  No usable pulses (", nPulses, " found, need 4) - calibration skipped"
    calibrated = 0
elsif jitterValid = 0 and shimmerValid = 0
    appendInfoLine: "  Pulses found but neither jitter nor shimmer was defined - calibration skipped"
    calibrated = 0
else
    if jitterValid = 0
        appendInfoLine: "  Jitter undefined - drive left at the preset base"
    endif
    if shimmerValid = 0
        appendInfoLine: "  Shimmer undefined - fold count left at 1"
    endif
endif

if unpitched_fallback = 2
    fallbackLabel$ = "drive only"
else
    fallbackLabel$ = "base shaping"
endif

if calibrated = 0
    if unpitched_fallback = 2
        appendInfoLine: "  Fallback: drive only (no folding, no saturation)"
    else
        appendInfoLine: "  Fallback: base shaping (preset drive + 1 fold + saturation)"
    endif
endif

jitter_percent = jitter_local * 100
shimmer_percent = shimmer_local * 100

appendInfoLine: "Jitter (local): ", fixed$(jitter_percent, 2), "%"
appendInfoLine: "Shimmer (local): ", fixed$(shimmer_percent, 2), "%"
appendInfoLine: ""

# Cleanup analysis objects
removeObject: mono, pitch, pp

# ============================================================
# CALCULATE CALIBRATED PARAMETERS
# ============================================================

# Drive increases with jitter (pitch instability -> more drive)
adaptive_drive = base_drive * (1 + (jitter_percent * jitter_sensitivity / 100))

# Fold count increases with shimmer (amplitude instability -> more folds)
adaptive_fold = 1 + round(shimmer_percent * shimmer_sensitivity / 20)

# v0.6 (item 3): true drive-only fallback when the user asks for it.
applySaturation = 1
if calibrated = 0 and unpitched_fallback = 2
    adaptive_fold = 0
    applySaturation = 0
endif

# Bound drive and fold count.
# v0.6 (item 6): these were labelled "safe ranges", which they are not.
# Each fold pass only reduces the excess by 2 * fold_threshold, so with a
# small threshold the cap of 8 folds does not bring the signal back into
# range at all: drive 8, threshold 0.01 and a full-scale input still
# leaves about 7.84 after eight reflections. The bounds limit the
# PARAMETERS, not the output peak - the peak is handled by Output_level,
# and the pre-normalization peak is now reported so the choice is
# informed rather than assumed.
if adaptive_drive < 0.5
    adaptive_drive = 0.5
endif
if adaptive_drive > 8.0
    adaptive_drive = 8.0
endif
if adaptive_fold < 0
    adaptive_fold = 0
endif
if adaptive_fold > 8
    adaptive_fold = 8
endif

appendInfoLine: "Calibrated drive: ", fixed$(adaptive_drive, 2)
appendInfoLine: "Calibrated folds: ", adaptive_fold
appendInfoLine: ""

# ============================================================
# APPLY WAVE SHAPING
# ============================================================

appendInfoLine: "Applying wave shaping..."

selectObject: original
result = Copy: original_name$ + "_shaped_" + presetName$

# 1. Drive
selectObject: result
Formula: ~ self * adaptive_drive

# 2. Wave folding (combined one-formula version, ~2x faster than v0.2)
for i from 1 to adaptive_fold
    selectObject: result
    Formula: ~ if self > fold_threshold then fold_threshold - (self - fold_threshold)
        ... else if self < -fold_threshold then -fold_threshold - (self + fold_threshold)
        ... else self fi fi
endfor

# 3. Saturation
if applySaturation = 1
    if saturation_type = 1
        # Sin blend: 0.3*sin(2x) + 0.7x. v0.5 called this non-monotonic,
        # but its derivative 0.6*cos(2x) + 0.7 stays within [0.1, 1.3] and
        # never reaches zero, so the function is monotonically increasing
        # everywhere. It is a sinusoidally rippled monotonic saturation.
        selectObject: result
        Formula: ~ sin(self * 2) * 0.3 + self * 0.7
    elsif saturation_type = 2
        # Tanh - clean monotonic saturation
        selectObject: result
        Formula: ~ tanh(self * 1.5)
    endif
    # Type 3 = None: folding only
endif

# 4. Output level
selectObject: result
prePeak = Get absolute extremum: 0, 0, "None"
appendInfoLine: "Peak before output stage: ", fixed$(prePeak, 3)

if output_level = 1
    selectObject: result
    Scale peak: 0.9
    levelDesc$ = "normalized to 0.9"
elsif output_level = 2
    if prePeak > 1.0
        selectObject: result
        Scale peak: 0.9
        levelDesc$ = "attenuated to 0.9 (peak was " + fixed$(prePeak, 2) + ")"
    else
        levelDesc$ = "unchanged (peak " + fixed$(prePeak, 3) + ")"
    endif
else
    levelDesc$ = "preserved (peak " + fixed$(prePeak, 3) + ")"
    if prePeak > 1.0
        appendInfoLine: "  WARNING: peak exceeds 1.0 and output level is set to Preserve - this will clip on playback or export."
    endif
endif
appendInfoLine: "Output level: ", levelDesc$

if applySaturation = 1
    satApplied$ = satName$
else
    satApplied$ = "None (fallback)"
endif

# === Final stats ===
selectObject: result
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"
nResultCh = Get number of channels

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard, minus LTAS panel)
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
    Text: 0.5, "centre", 0.68, "half", "##Adaptive Wave Shaper v0.8.1##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.22, "half",
        ... vizName$
        ... + "  |  " + presetName$
        ... + "  |  Drive: " + fixed$(adaptive_drive, 2)
        ... + "  |  Folds: " + string$(adaptive_fold)
        ... + "  |  Sat: " + satApplied$
        ... + "  |  Jitter: " + fixed$(jitter_percent, 2) + "%"
        ... + "  |  Shimmer: " + fixed$(shimmer_percent, 2) + "%"
    
    # ----------------------------------------------------------
    # PANEL A: TRANSFER FUNCTION  (left, headline)
    # The defining diagnostic for a wave shaper.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4, 0.75, 4.60
    Select inner viewport: 0.60, 3.85, 0.95, 4.40
    
    # v0.7: the curve used to be clamped to +/-1.4 in VALUE, which is not
    # something the audio engine does - so whenever the shaper produced
    # more than 1.4 the panel drew a flat plateau instead of the real
    # function. With drive 4, threshold 0.6 and one fold, an input of 1.2
    # actually yields -3.6; the panel showed -1.4. Since the title
    # promises the shaping function BEFORE the output level stage, that
    # clamp was rewriting the function, not merely cropping the view.
    # The extent is now measured first and the Y axis sized to fit.
    nPoints = 200
    yLim = 1.5
    for p from 1 to nPoints
        xs = -1.2 + (p - 1) / (nPoints - 1) * 2.4
        ys = xs * adaptive_drive
        for f from 1 to adaptive_fold
            if ys > fold_threshold
                ys = fold_threshold - (ys - fold_threshold)
            elsif ys < -fold_threshold
                ys = -fold_threshold - (ys + fold_threshold)
            endif
        endfor
        if applySaturation = 1
            if saturation_type = 1
                ys = sin(ys * 2) * 0.3 + ys * 0.7
            elsif saturation_type = 2
                ys = tanh(ys * 1.5)
            endif
        endif
        if abs(ys) * 1.1 > yLim
            yLim = abs(ys) * 1.1
        endif
    endfor
    
    Axes: -1.5, 1.5, -yLim, yLim
    Paint rectangle: "{0.97, 0.97, 0.97}", -1.5, 1.5, -yLim, yLim
    
    # Grid
    Colour: "{0.85, 0.85, 0.88}"
    Line width: 1
    Draw line: -1.5, 0, 1.5, 0
    Draw line: 0, -yLim, 0, yLim
    
    # y=x reference (no shaping)
    Dotted line
    Colour: "{0.65, 0.65, 0.70}"
    Draw line: -1.5, -1.5, 1.5, 1.5
    Solid line
    
    # Fold threshold lines
    Colour: "{0.55, 0.78, 0.55}"
    Dotted line
    Draw line: -1.5, fold_threshold, 1.5, fold_threshold
    Draw line: -1.5, -fold_threshold, 1.5, -fold_threshold
    Solid line
    Font size: 6
    Text: -1.4, "left", fold_threshold, "bottom", " thresh"
    Text: -1.4, "left", -fold_threshold, "top", " -thresh"
    
    # Draw transfer function with current calibrated params
    # v0.6 CRITICAL (item 1): v0.5 folded the curve with TWO independent
    # `if` statements, so a positive reflection that overshot below
    # -threshold was reflected a second time within the same pass. The
    # audio formula uses `if ... else if ... fi fi`, i.e. at most ONE
    # reflection per pass, with the overshoot carried into the next pass.
    # The two diverged exactly where the effect lives: with the Default
    # preset an input of 1.2 gave -1.2 in the audio and 0 on the curve,
    # and on Aggressive Drive the curve disagreed with the sound across
    # 37.5% of the input range (max error 3.6). The diagnostic that the
    # whole panel exists to provide was misreporting the process.
    # Both branches below now mirror the Formula exactly.
    Colour: "{0.80, 0.40, 0.40}"
    Line width: 2
    prevX = -1.2
    prevY = -1.2 * adaptive_drive
    for f from 1 to adaptive_fold
        if prevY > fold_threshold
            prevY = fold_threshold - (prevY - fold_threshold)
        elsif prevY < -fold_threshold
            prevY = -fold_threshold - (prevY + fold_threshold)
        endif
    endfor
    if applySaturation = 1
        if saturation_type = 1
            prevY = sin(prevY * 2) * 0.3 + prevY * 0.7
        elsif saturation_type = 2
            prevY = tanh(prevY * 1.5)
        endif
    endif
    
    for p from 2 to nPoints
        x = -1.2 + (p - 1) / (nPoints - 1) * 2.4
        y = x * adaptive_drive
        for f from 1 to adaptive_fold
            if y > fold_threshold
                y = fold_threshold - (y - fold_threshold)
            elsif y < -fold_threshold
                y = -fold_threshold - (y + fold_threshold)
            endif
        endfor
        if applySaturation = 1
            if saturation_type = 1
                y = sin(y * 2) * 0.3 + y * 0.7
            elsif saturation_type = 2
                y = tanh(y * 1.5)
            endif
        endif
        Draw line: prevX, prevY, x, y
        prevX = x
        prevY = y
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Output (+/-" + fixed$(yLim, 2) + ")"
    Text bottom: "yes", "Input"
    
    # ----------------------------------------------------------
    # PANEL B: PARAMETER REPORT  (right, headline-height)
    # Compact text panel showing the analysis-derived parameters.
    # Replaces the LTAS panel (which was too slow on every run).
    # ----------------------------------------------------------
    Select outer viewport: 4, 8, 0.75, 4.60
    Select inner viewport: 4.45, 7.70, 0.95, 4.40
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
    
    # Section: Voice quality
    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.92, "half", "Voice quality (analyzed):"
    
    Font size: 7
    Colour: "{0.30, 0.45, 0.78}"
    Text: 0.10, "left", 0.83, "half", "Jitter:  " + fixed$(jitter_percent, 2) + " %"
    Text: 0.10, "left", 0.75, "half", "Shimmer: " + fixed$(shimmer_percent, 2) + " %"
    
    Font size: 7
    Colour: "{0.78, 0.45, 0.30}"
    if pulsesValid = 0
        Text: 0.10, "left", 0.68, "half", "(no usable pulses — " + fallbackLabel$ + ")"
    elsif jitterValid = 0 and shimmerValid = 0
        Text: 0.10, "left", 0.68, "half", "(jitter and shimmer undefined — " + fallbackLabel$ + ")"
    elsif jitterValid = 0
        Text: 0.10, "left", 0.68, "half", "(jitter undefined — drive at preset base)"
    elsif shimmerValid = 0
        Text: 0.10, "left", 0.68, "half", "(shimmer undefined — fold count 1)"
    endif
    
    # Section: Calibrated parameters
    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.58, "half", "Calibrated parameters:"
    
    Font size: 7
    Colour: "{0.80, 0.40, 0.40}"
    Text: 0.10, "left", 0.49, "half", "Drive:   " + fixed$(adaptive_drive, 2) + " x"
    Colour: "{0.40, 0.65, 0.40}"
    Text: 0.10, "left", 0.41, "half", "Folds:   " + string$(adaptive_fold)
    
    # Section: Sensitivities
    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.27, "half", "Sensitivities:"
    
    Font size: 7
    Colour: "{0.55, 0.55, 0.55}"
    Text: 0.10, "left", 0.18, "half", "Jitter sens:  " + fixed$(jitter_sensitivity, 2)
    Text: 0.10, "left", 0.10, "half", "Shimmer sens: " + fixed$(shimmer_sensitivity, 2)
    
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
    Text: 2.10, "centre", 7.30, "half", "Static shaping function (before output level stage)"
    Text: 6.10, "centre", 7.30, "half", "Analysis report"
    
    # ----------------------------------------------------------
    # PANEL C: OUTPUT WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.75
    Select inner viewport: 0.60, 7.70, 4.75, 5.68
    
    selectObject: result
    outPeak = Get absolute extremum: 0, 0, "None"
    if outPeak < 0.001
        outPeak = 0.001
    endif
    ampViz = outPeak * 1.15
    
    Axes: 0, finalDur, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDur, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, finalDur, 0
    
    selectObject: result
    if nResultCh = 1
        Colour: "{0.20, 0.55, 0.55}"
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
    if nResultCh = 2
        Text top: "no", "Output  (blue=Ch 1  orange=Ch 2)"
    elsif nResultCh > 2
        Text top: "no", "Output  (blue=Ch 1  orange=Ch 2; showing 2 of " + string$(nResultCh) + " ch)"
    else
        Text top: "no", "Output (mono)"
    endif
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: SUMMARY BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.82, 6.58
    Select inner viewport: 0.60, 7.70, 5.88, 6.52
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + vizName$
        ... + "  |  Jitter: " + fixed$(jitter_percent, 2) + "%"
        ... + "  |  Shimmer: " + fixed$(shimmer_percent, 2) + "%"
        ... + "  |  Drive: " + fixed$(adaptive_drive, 2)
        ... + "  |  Folds: " + string$(adaptive_fold)
    
    Text: 0.02, "left", 0.28, "half",
        ... "Saturation: " + satApplied$
        ... + "  |  Threshold: " + fixed$(fold_threshold, 2)
        ... + "  |  J-sens: " + fixed$(jitter_sensitivity, 1)
        ... + "  |  S-sens: " + fixed$(shimmer_sensitivity, 1)
        ... + "  |  Level: " + levelDesc$
        ... + "  |  Output: " + fixed$(finalDur, 2) + " s, " + string$(nResultCh) + " ch, peak " + fixed$(finalPeak, 3)
    
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
appendInfoLine: "Channels: ", nResultCh
appendInfoLine: "Peak: ", fixed$(finalPeak, 4)

if play_result
    selectObject: result
    Play
endif

selectObject: result
