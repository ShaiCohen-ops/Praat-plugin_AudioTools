# ============================================================
# Praat AudioTools - Vintage_Glue_Compressor.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Vintage-style compressor with analog saturation modeling.
#   Emulates Tube, Tape, Transistor, and FET characteristics.
#
#   Pipeline:
#     1. Power sidechain: per-channel square, then channel-linked
#        mean power (never an amplitude downmix)
#     2. Causal one-pole RMS detector with its own window,
#        independent of Attack/Release
#     3. Absolute dBFS conversion (no per-file calibration)
#     4. Causal attack/release recursion on the dB level
#     5. Standard soft-knee gain computation
#     6. Gain applied by sample index at the audio rate
#     7. Optional analog saturation (4 models, optional
#        oversampling)
#     8. Optional dry/wet mix and optional output level stage
#
#   Stereo handling: the detector links channels by summing
#   POWER, so anti-phase material cannot cancel. The resulting
#   gain curve is applied to all channels uniformly.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v1.3.1 (2026):
#   - FIXED visualization-only regression: presetDisp$ was used in
#     the header and summary without ever being initialized, causing
#     an "Unknown variable" error when Draw_result was enabled.
#   - Added an explicit display-name mapping for all seven presets.
#     Audio analysis and DSP are unchanged from v1.3.
#
# Changelog v1.3 (2026):
#   - VISUALIZATION / UI STANDARDIZATION ONLY. Audio analysis,
#     DSP, scheduling and rendering are unchanged from the
#     previous version.
#   - Adopted the Praat AudioTools 8-inch visualization header,
#     suite typography, neutral panel backgrounds, summary-style
#     reporting and full-page Picture export restoration.
#   - Preserved the script-specific diagnostic / transformation
#     views rather than replacing them with generic plots.
#
# Changelog v1.2:
#   NOTE: v1.1 renders are NOT reproducible in v1.2. The detector was
#   rebuilt because its threshold was not a fixed quantity - see below.
#
#   - Output level stage is now a choice, default "Safety ceiling
#     (attenuate only)". v1.1 ran Scale peak unconditionally, which is
#     peak normalization: a -40 dBFS file with no compression, no
#     saturation and 0 dB makeup came out at -0.09 dBFS, i.e. amplified
#     by 40 dB for doing nothing. That also made Makeup_Gain_dB, Auto
#     makeup and Dry/wet unable to set an absolute level.
#   - Channel-linked POWER sidechain. v1.1 ran Convert to mono on the
#     audio before measuring, so L = s / R = -s cancelled and the
#     compressor barely engaged (loud/quiet ratio 10.00 anti-phase vs
#     2.99 in phase). Squaring now happens per channel first.
#   - Absolute dBFS threshold. v1.1 shifted the Intensity curve so its
#     maximum equalled the file's sample peak, so the threshold moved
#     with the crest factor: two signals of identical RMS 0.1 got ~0 dB
#     and ~6.6 dB of gain reduction. The detector now converts to dBFS
#     directly, and the field is Rms_threshold_dBFS. (Spelled Rms_, not
#     RMS_: Praat lowercases only the FIRST character of a form field
#     name, so RMS_threshold_dBFS would arrive as rMS_threshold_dBFS.)
#   - Detector window separated from the time constants. v1.1 derived
#     the To Intensity window from (attack+release)/2, so Attack and
#     Release acted twice and a 10 ms attack sat behind a 55 ms
#     zero-phase window - gain reduction began about 20 ms BEFORE the
#     level rose. There is now an explicit Rms_window_ms, and the
#     detector is causal.
#   - Short files work. The To Intensity window made the minimum usable
#     length roughly attack+release (Vocal Opto failed under ~510 ms,
#     Mix Bus Glue under ~230 ms). The new detector has no such limit.
#   - Soft knee corrected. v1.1 computed a gain reduction proportional
#     to -over^3/(2K^2) instead of the standard -over^2/(2K); with the
#     default -15 dB / 6 dB / 4:1 there was a band near -12.34 dB where
#     MORE input gave LESS output. Both the audio and the drawn curve
#     use the corrected form.
#   - Transistor model replaced. The old piecewise cubic was
#     discontinuous at |x*drive| = 0.5 (a jump from 0.227 to 0.313), and
#     above that it turned over: input +1 gave -0.92 and input -1 gave
#     -3.92, i.e. polarity inversion, foldover and an internal peak of
#     about 3.93 that the final Scale peak was hiding. It is now a
#     normalized cubic soft clip: continuous, monotonic, C1 at the knee,
#     bounded by +/-1.
#   - No gain-curve resampling. v1.1 built the curve on the Intensity
#     grid and resampled it to the audio rate without clamping, giving
#     gains up to 1.038 (+0.32 dB) in unity regions and altering the
#     signal even at 1:1. The curve is now computed at the audio rate
#     and applied by sample index, so no interpolation occurs at all.
#   - Optional saturation oversampling (off, 2x, 4x) with an explicit
#     aliasing note when it is off.
#   - Parameter validation on ratio, knee, drive, mixes and ceiling.
#   - "Estimated THD" was a constant times drive times mix, independent
#     of the signal. Renamed Saturation intensity index and labelled as
#     an arbitrary scale, not a measurement.
#   - Peaks measured with Get absolute extremum, max gain reduction
#     reported as a positive number, saturation panel draws the curve
#     including the Harmonics mix blend, and time panels follow the
#     Sound's own start and end time.
#
# Changelog v1.1 (Tier 2):
#   - Vectorized the gain-reduction calculation into a single Formula.
#   - Form syntax modernized: optionmenu uses colon.
#   - Visualization rewritten to suite 8x8 standard.
# Changelog v1.0:
#   - Initial release with five preset characters and three
#     transfer-function visualization panels.
# ============================================================

form Vintage Glue Compressor v1.3.1
    optionmenu Preset: 1
        option Custom
        option Vocal Opto (LA-2A style)
        option Drum VCA (SSL style)
        option Mix Bus Glue (Classic)
        option Tape Squeeze (Saturated)
        option Tube Warmth (Gentle)
        option FET Punch (1176 style)
    comment === Dynamics ===
    real Rms_threshold_dBFS -15.0
    positive Ratio 4.0
    real Knee_dB 6.0
    positive Attack_ms 10
    positive Release_ms 100
    comment === Analog Character ===
    optionmenu Saturation_type: 1
        option Off (Clean Digital)
        option Tube (Warm, Symmetric)
        option Tape (Rich, Asymmetric)
        option Transistor (Aggressive)
        option FET (Punchy)
    real Drive 0.3
    real Harmonics_mix 0.5
    comment === Output ===
    real Makeup_Gain_dB 0.0
    boolean Auto_makeup 1
    real Dry_wet_mix 1.0
    boolean Advanced_settings 0
    boolean Draw_result 1
    boolean Play_result 1
endform
# === Advanced defaults (identical to the v1.2 main-form defaults) ===
rms_window_ms = 10
saturation_oversampling = 1
output_level_mode = 2
ceiling_peak = 0.99
show_stats = 1
keep_original = 1

if advanced_settings
    beginPause: "Vintage Glue Compressor v1.3.1 - Advanced settings"
        comment: "=== Detector / saturation quality ==="
        positive: "Rms_window_ms", "10"
        optionmenu: "Saturation_oversampling", 1
            option: "Off (source rate)"
            option: "2x"
            option: "4x"
        comment: "=== Output policy ==="
        optionmenu: "Output_level_mode", 2
            option: "None (leave level as processed)"
            option: "Safety ceiling (attenuate only if above)"
            option: "Peak normalize (always scale to ceiling)"
        positive: "Ceiling_peak", "0.99"
        boolean: "Show_stats", 1
        boolean: "Keep_original", 1
    clicked = endPause: "Continue", 1
endif

# === GET SATURATION TYPE NAME ===
if saturation_type = 1
    saturation_type$ = "Clean"
elsif saturation_type = 2
    saturation_type$ = "Tube"
elsif saturation_type = 3
    saturation_type$ = "Tape"
elsif saturation_type = 4
    saturation_type$ = "Transistor"
else
    saturation_type$ = "FET"
endif

# === APPLY PRESETS ===
suf$ = ""

if preset = 2
    rms_threshold_dBFS = -24.0
    ratio = 3.0
    knee_dB = 12.0
    rms_window_ms = 20
    attack_ms = 10
    release_ms = 500
    saturation_type = 2
    saturation_type$ = "Tube"
    drive = 0.25
    harmonics_mix = 0.4
    makeup_Gain_dB = 4.0
    auto_makeup = 0
    suf$ = "_Opto"
elsif preset = 3
    rms_threshold_dBFS = -18.0
    ratio = 8.0
    knee_dB = 3.0
    rms_window_ms = 3
    attack_ms = 1
    release_ms = 50
    saturation_type = 4
    saturation_type$ = "Transistor"
    drive = 0.4
    harmonics_mix = 0.5
    makeup_Gain_dB = 4.0
    auto_makeup = 0
    suf$ = "_VCA"
elsif preset = 4
    rms_threshold_dBFS = -12.0
    ratio = 2.0
    knee_dB = 10.0
    rms_window_ms = 15
    attack_ms = 30
    release_ms = 200
    saturation_type = 2
    saturation_type$ = "Tube"
    drive = 0.15
    harmonics_mix = 0.3
    makeup_Gain_dB = 2.0
    auto_makeup = 0
    suf$ = "_Glue"
elsif preset = 5
    rms_threshold_dBFS = -15.0
    ratio = 4.0
    knee_dB = 8.0
    rms_window_ms = 10
    attack_ms = 5
    release_ms = 100
    saturation_type = 3
    saturation_type$ = "Tape"
    drive = 0.6
    harmonics_mix = 0.7
    makeup_Gain_dB = 3.0
    auto_makeup = 0
    suf$ = "_Tape"
elsif preset = 6
    rms_threshold_dBFS = -20.0
    ratio = 2.5
    knee_dB = 15.0
    rms_window_ms = 20
    attack_ms = 20
    release_ms = 300
    saturation_type = 2
    saturation_type$ = "Tube"
    drive = 0.35
    harmonics_mix = 0.5
    makeup_Gain_dB = 3.0
    auto_makeup = 0
    suf$ = "_Tube"
elsif preset = 7
    rms_threshold_dBFS = -20.0
    ratio = 12.0
    knee_dB = 0.0
    rms_window_ms = 2
    attack_ms = 0.5
    release_ms = 50
    saturation_type = 5
    saturation_type$ = "FET"
    drive = 0.5
    harmonics_mix = 0.6
    makeup_Gain_dB = 6.0
    auto_makeup = 0
    suf$ = "_FET"
endif

# Display-only preset label used by the visualization.
if preset = 1
    presetDisp$ = "Custom"
elsif preset = 2
    presetDisp$ = "Vocal Opto"
elsif preset = 3
    presetDisp$ = "Drum VCA"
elsif preset = 4
    presetDisp$ = "Mix Bus Glue"
elsif preset = 5
    presetDisp$ = "Tape Squeeze"
elsif preset = 6
    presetDisp$ = "Tube Warmth"
else
    presetDisp$ = "FET Punch"
endif

# === VALIDATION ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
original_name$ = selected$("Sound")
sr = Get sampling frequency
dur = Get total duration
n_channels = Get number of channels
x_start = Get start time
x_end = Get end time

if ratio < 1
    exitScript: "Ratio must be at least 1 (got " + fixed$(ratio, 2) +
    ... "). A ratio below 1 is an expander, which this script does not model."
endif
if knee_dB < 0
    exitScript: "Knee_dB must be 0 or greater (got " + fixed$(knee_dB, 2) + ")."
endif
if drive < 0
    exitScript: "Drive must be 0 or greater (got " + fixed$(drive, 3) +
    ... "). Negative drive collapses the saturation normalizer."
endif
if harmonics_mix < 0 or harmonics_mix > 1
    exitScript: "Harmonics_mix must be between 0 and 1 (got " + fixed$(harmonics_mix, 3) + ")."
endif
if dry_wet_mix < 0 or dry_wet_mix > 1
    exitScript: "Dry_wet_mix must be between 0 and 1 (got " + fixed$(dry_wet_mix, 3) + ")."
endif
if ceiling_peak <= 0 or ceiling_peak > 1
    exitScript: "Ceiling_peak must be greater than 0 and at most 1 (got " +
    ... fixed$(ceiling_peak, 3) + "). Samples outside -1..+1 are clipped when " +
    ... "saved to integer PCM."
endif

# === INPUT MEASUREMENTS ===
selectObject: sound
in_peak = Get absolute extremum: 0, 0, "None"
in_peak_dB = 20 * log10(in_peak + 1e-10)
in_rms = Get root-mean-square: 0, 0
in_rms_dB = 20 * log10(in_rms + 1e-10)

# === INFO HEADER ===
writeInfoLine: "============================================"
appendInfoLine: "VINTAGE GLUE COMPRESSOR v1.3"
appendInfoLine: "============================================"
appendInfoLine: ""
appendInfoLine: "Input: ", original_name$
appendInfoLine: "Duration: ", fixed$(dur, 2), "s | SR: ", sr, " Hz | Channels: ", n_channels
appendInfoLine: ""
appendInfoLine: "Input Peak: ", fixed$(in_peak_dB, 1), " dBFS"
appendInfoLine: "Input RMS:  ", fixed$(in_rms_dB, 1), " dBFS"
appendInfoLine: ""
appendInfoLine: "--- Compression ---"
appendInfoLine: "Threshold: ", fixed$(rms_threshold_dBFS, 1), " dBFS (RMS) | Ratio: ", ratio,
... ":1 | Knee: ", fixed$(knee_dB, 1), " dB"
appendInfoLine: "  Input RMS sits ", fixed$(in_rms_dB - rms_threshold_dBFS, 1),
... " dB relative to the threshold"
appendInfoLine: "Detector window: ", fixed$(rms_window_ms, 2), " ms"
if rms_window_ms * sr / 1000 < 4
    appendInfoLine: "  NOTE: that is under 4 samples at ", fixed$(sr, 0), " Hz. The detector"
    appendInfoLine: "        will follow individual cycles rather than a level, which"
    appendInfoLine: "        modulates the waveform instead of compressing it."
endif
appendInfoLine: "Attack: ", attack_ms, " ms | Release: ", release_ms, " ms"
appendInfoLine: ""
appendInfoLine: "--- Saturation ---"
appendInfoLine: "Type: ", saturation_type$
appendInfoLine: "Drive: ", fixed$(drive * 100, 0), "% | Harmonics Mix: ",
... fixed$(harmonics_mix * 100, 0), "%"
appendInfoLine: ""

# ============================================================
# DETECTOR
# ============================================================
# Channel-linked POWER, not an amplitude downmix. Squaring first means
# the channel fold averages non-negative powers, which cannot cancel:
# p(t) = (xL^2 + xR^2) / 2.

selectObject: sound
detector = Copy: "detector_power"
Formula: "self * self"

if n_channels > 1
    mono_power = Convert to mono
    removeObject: detector
    detector = mono_power
endif

# Causal one-pole RMS window. Its time constant is a separate parameter:
# v1.1 derived the detector window from (attack+release)/2, so the time
# constants acted twice, and the window was zero-phase, so the detector
# saw transients before they happened.
rms_window_sec = rms_window_ms / 1000
rms_coef = exp(-1 / (sr * rms_window_sec))
rms_gain = 1 - rms_coef

selectObject: detector
Formula: "if col = 1 then self else rms_coef * self[row, col - 1] + rms_gain * self fi"

# Power -> amplitude -> absolute dBFS. No per-file calibration: v1.1 used
# offset = in_peak_dB - env_max, which made the threshold move with the
# crest factor of whatever was loaded.
Formula: "20 * log10(sqrt(max(self, 0)) + 1e-10)"

# === ATTACK / RELEASE (causal, on the dB level, at the audio rate) ===
attack_sec = attack_ms / 1000
release_sec = release_ms / 1000
a_coef = exp(-1 / (sr * attack_sec))
r_coef = exp(-1 / (sr * release_sec))
a_gain = 1 - a_coef
r_gain = 1 - r_coef

selectObject: detector
Formula: "if col = 1 then self else (if self > self[row, col - 1] then a_coef * self[row, col - 1] + a_gain * self else r_coef * self[row, col - 1] + r_gain * self fi) fi"

# ============================================================
# GAIN REDUCTION WITH SOFT KNEE
# ============================================================
# Standard soft knee. Inside the knee the gain reduction is
#   -(1 - 1/r) * (L - T + K/2)^2 / (2K)
# v1.1 used -(1 - 1/r) * (L - T + K/2)^3 / (2K^2), which meets the right
# values at both edges but not the right slope at the top, producing a
# band where more input gave less output.

selectObject: detector
gain_sound = Copy: "GainCurve"

t = rms_threshold_dBFS
r = ratio
k = knee_dB
half_k = k / 2

t_str$ = string$(t)
k_str$ = string$(k)
half_k_str$ = string$(half_k)
slope = 1 - 1/r
slope_str$ = string$(slope)

selectObject: gain_sound

if k <= 0
    Formula: "if self > " + t_str$
        ... + " then 10 ^ (-(self - " + t_str$ + ") * " + slope_str$ + " / 20)"
        ... + " else 1 fi"
else
    Formula: "if self < (" + t_str$ + " - " + half_k_str$ + ")"
        ... + " then 1"
        ... + " else if self > (" + t_str$ + " + " + half_k_str$ + ")"
            ... + " then 10 ^ (-(self - " + t_str$ + ") * " + slope_str$ + " / 20)"
            ... + " else 10 ^ ("
                ... + "-(self - " + t_str$ + " + " + half_k_str$ + ")^2"
                ... + " * " + slope_str$ + " / (2 * " + k_str$ + ") / 20"
            ... + ")"
        ... + " fi"
        ... + " fi"
endif

# === GR STATS (before makeup, so it is gain reduction and not net gain) ===
selectObject: gain_sound
gr_min_lin = Get minimum: 0, 0, "None"
gr_max_reduction_dB = -20 * log10(gr_min_lin + 1e-10)

# === AUTO MAKEUP GAIN ===
if auto_makeup
    typical_over = 10
    typical_gr = typical_over * (1 - 1/r)
    makeup_Gain_dB = typical_gr * 0.5
    appendInfoLine: "Auto Makeup: +", fixed$(makeup_Gain_dB, 1), " dB (heuristic: half the"
    appendInfoLine: "  reduction a signal 10 dB over threshold would receive)"
endif

selectObject: gain_sound
makeup_linear = 10 ^ (makeup_Gain_dB / 20)
Formula: "self * makeup_linear"

# ============================================================
# APPLY COMPRESSION
# ============================================================
# By sample INDEX. The curve was computed at the audio rate on a copy of
# the source, so the grids are identical and nothing is interpolated.
# v1.1 built the curve on the Intensity grid and resampled it without a
# clamp, which produced gains up to 1.038 in regions that should have
# been unity.

selectObject: sound
compressed = Copy: original_name$ + "_Comp"
gain_str$ = string$(gain_sound)
Formula: "self * object[" + gain_str$ + ", 1, col]"

# ============================================================
# SATURATION
# ============================================================
os_factor = 1
if saturation_oversampling = 2
    os_factor = 2
elsif saturation_oversampling = 3
    os_factor = 4
endif

if saturation_type > 1
    # Keep a clean copy for the harmonics blend before anything nonlinear
    if harmonics_mix < 1
        selectObject: sound
        clean_compressed = Copy: "clean_comp"
        Formula: "self * object[" + gain_str$ + ", 1, col]"
    endif

    selectObject: compressed
    if os_factor > 1
        up_sound = Resample: sr * os_factor, 50
        removeObject: compressed
        compressed = up_sound
        selectObject: compressed
    endif

    drive_amt = 1.0 + drive * 3.0

    if saturation_type = 2
        Formula: "tanh(self * drive_amt) / tanh(drive_amt)"
        sat_name$ = "Tube"
    elsif saturation_type = 3
        Formula: "if self >= 0 then tanh(self * drive_amt * 1.2) / tanh(drive_amt * 1.2) else tanh(self * drive_amt * 0.9) / tanh(drive_amt * 0.9) fi"
        sat_name$ = "Tape"
    elsif saturation_type = 4
        # Normalized cubic soft clip: y = 1.5 * (u - u^3/3) for |u| <= 1,
        # +/-1 beyond. Continuous, monotonic, C1 at |u| = 1, bounded.
        # The v1.1 curve jumped at |u| = 0.5 and inverted polarity above it.
        Formula: "if self * drive_amt > 1 then 1 else (if self * drive_amt < -1 then -1 else 1.5 * (self * drive_amt - (self * drive_amt)^3 / 3) fi) fi"
        sat_name$ = "Transistor"
    elsif saturation_type = 5
        asym = 0.1
        Formula: "tanh((self + self * asym * abs(self)) * drive_amt) / tanh(drive_amt * (1 + asym))"
        sat_name$ = "FET"
    endif

    if os_factor > 1
        selectObject: compressed
        down_sound = Resample: sr, 50
        removeObject: compressed
        compressed = down_sound
    endif

    if harmonics_mix < 1
        selectObject: compressed
        clean_str$ = string$(clean_compressed)
        Formula: "self * harmonics_mix + object(" + clean_str$ + ", x) * (1 - harmonics_mix)"
        removeObject: clean_compressed
    endif

    appendInfoLine: "Saturation applied: ", sat_name$
    if os_factor > 1
        appendInfoLine: "  Oversampled ", os_factor, "x for the nonlinearity"
    else
        appendInfoLine: "  NOTE: no oversampling. Harmonics above Nyquist fold back into"
        appendInfoLine: "        the audible band, most audibly on Transistor and FET at"
        appendInfoLine: "        high drive. Set Saturation_oversampling to 2x or 4x."
    endif
endif

# === DRY/WET MIX ===
if dry_wet_mix < 1
    selectObject: compressed
    sound_str$ = string$(sound)
    Formula: "self * dry_wet_mix + object(" + sound_str$ + ", x) * (1 - dry_wet_mix)"
    appendInfoLine: "Dry/Wet: ", fixed$(dry_wet_mix * 100, 0), "% wet"
endif

# ============================================================
# OUTPUT LEVEL STAGE
# ============================================================
selectObject: compressed
pre_level_peak = Get absolute extremum: 0, 0, "None"
level_gain = 1
level_action$ = "none"

if output_level_mode = 2
    # Attenuate only if above the ceiling. Quiet material is left alone.
    if pre_level_peak > ceiling_peak and pre_level_peak > 0
        Scale peak: ceiling_peak
        level_gain = ceiling_peak / pre_level_peak
        level_action$ = "ceiling applied"
    else
        level_action$ = "ceiling not needed"
    endif
elsif output_level_mode = 3
    if pre_level_peak > 0
        Scale peak: ceiling_peak
        level_gain = ceiling_peak / pre_level_peak
        level_action$ = "peak normalized"
    endif
endif

Rename: original_name$ + suf$

# === OUTPUT MEASUREMENTS ===
selectObject: compressed
out_peak = Get absolute extremum: 0, 0, "None"
out_peak_dB = 20 * log10(out_peak + 1e-10)
out_rms = Get root-mean-square: 0, 0
out_rms_dB = 20 * log10(out_rms + 1e-10)

# === SATURATION INTENSITY INDEX ===
# NOT a THD measurement. It depends only on the settings, never on the
# signal, its level, its frequency content or the harmonics actually
# generated. It is a relative scale for comparing settings.
if saturation_type > 1
    if saturation_type = 2
        sat_index = drive * 3.0
    elsif saturation_type = 3
        sat_index = drive * 5.0
    elsif saturation_type = 4
        sat_index = drive * 7.0
    elsif saturation_type = 5
        sat_index = drive * 4.0
    endif
    sat_index = sat_index * harmonics_mix
else
    sat_index = 0
endif

# === STATS OUTPUT ===
if show_stats
    appendInfoLine: ""
    appendInfoLine: "--- Results ---"
    appendInfoLine: "Output Peak: ", fixed$(out_peak_dB, 1), " dBFS"
    appendInfoLine: "Output RMS:  ", fixed$(out_rms_dB, 1), " dBFS"
    appendInfoLine: ""
    appendInfoLine: "Peak Change: ", fixed$(out_peak_dB - in_peak_dB, 1), " dB"
    appendInfoLine: "RMS Change:  ", fixed$(out_rms_dB - in_rms_dB, 1), " dB"
    appendInfoLine: ""
    appendInfoLine: "Max Gain Reduction: ", fixed$(gr_max_reduction_dB, 1), " dB"
    appendInfoLine: "Makeup: +", fixed$(makeup_Gain_dB, 1), " dB"
    appendInfoLine: "Peak before output stage: ", fixed$(pre_level_peak, 4)
    if output_level_mode = 1
        appendInfoLine: "Output stage: none"
    elsif output_level_mode = 2
        appendInfoLine: "Output stage: safety ceiling ", fixed$(ceiling_peak, 2), " - ", level_action$
    else
        appendInfoLine: "Output stage: peak normalize to ", fixed$(ceiling_peak, 2),
        ... " (x", fixed$(level_gain, 4), ")"
        appendInfoLine: "  NOTE: this is a constant gain over the whole file, so Makeup and"
        appendInfoLine: "        Dry/wet no longer set the absolute output level."
    endif
    if output_level_mode <> 3 and out_peak > 1
        appendInfoLine: "WARNING: output peak exceeds 1.0 and will clip when saved to integer PCM."
    endif
    appendInfoLine: ""
    appendInfoLine: "Crest Factor:"
    appendInfoLine: "  Input:  ", fixed$(in_peak_dB - in_rms_dB, 1), " dB"
    appendInfoLine: "  Output: ", fixed$(out_peak_dB - out_rms_dB, 1), " dB"
    appendInfoLine: ""
    if saturation_type > 1
        appendInfoLine: "Saturation intensity index: ", fixed$(sat_index, 2)
        appendInfoLine: "  (arbitrary scale from Drive and Harmonics mix; not measured THD)"
    endif
endif

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_result
    Erase all
    vizName$ = replace$(original_name$, "_", "\_ ", 0)
    pageWidth = 8
    # === Header ===
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Vintage Glue Compressor v1.3.1##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", vizName$ + " | " + presetDisp$ + " | T " + fixed$(t, 0) + " dB | " + fixed$(ratio, 1) + ":1 | " + saturation_type$ + " | GR max " + fixed$(gr_max_reduction_dB, 1) + " dB"

    # PANEL A: SATURATION TRANSFER CURVE  (left, headline)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    Axes: -1.5, 1.5, -1.5, 1.5
    Paint rectangle: "{0.97, 0.97, 0.97}", -1.5, 1.5, -1.5, 1.5
    
    # Grid
    Colour: "{0.85, 0.85, 0.88}"
    Line width: 1
    Draw line: -1.5, 0, 1.5, 0
    Draw line: 0, -1.5, 0, 1.5
    Draw line: -1, -1.5, -1, 1.5
    Draw line: 1, -1.5, 1, 1.5
    Draw line: -1.5, -1, 1.5, -1
    Draw line: -1.5, 1, 1.5, 1
    
    # Unity reference
    Dotted line
    Colour: "{0.65, 0.65, 0.70}"
    Draw line: -1.5, -1.5, 1.5, 1.5
    Solid line
    
    # Saturation curve
    if saturation_type > 1
        Colour: "{0.80, 0.30, 0.30}"
    else
        Colour: "{0.30, 0.45, 0.78}"
    endif
    Line width: 2.5
    
    drive_amt = 1.0 + drive * 3.0
    
    in_val = -1.5
    while in_val <= 1.5
        if saturation_type = 1
            sat_val = in_val
        elsif saturation_type = 2
            sat_val = tanh(in_val * drive_amt) / tanh(drive_amt)
        elsif saturation_type = 3
            if in_val >= 0
                sat_val = tanh(in_val * drive_amt * 1.3) / tanh(drive_amt * 1.3)
            else
                sat_val = tanh(in_val * drive_amt * 0.9) / tanh(drive_amt * 0.9)
            endif
        elsif saturation_type = 4
            u_val = in_val * drive_amt
            if u_val > 1
                sat_val = 1
            elsif u_val < -1
                sat_val = -1
            else
                sat_val = 1.5 * (u_val - u_val * u_val * u_val / 3)
            endif
        elsif saturation_type = 5
            asym = 0.1
            sat_val = tanh((in_val + in_val * asym * abs(in_val)) * drive_amt) / tanh(drive_amt * (1 + asym))
        endif

        # The applied curve includes the harmonics blend: v1.1 drew 100%
        # saturation even at a 30% mix.
        if saturation_type > 1
            out_val = sat_val * harmonics_mix + in_val * (1 - harmonics_mix)
        else
            out_val = sat_val
        endif
        
        if out_val > 1.5
            out_val = 1.5
        endif
        if out_val < -1.5
            out_val = -1.5
        endif
        
        if in_val = -1.5
            prev_out = out_val
        else
            Draw line: in_val - 0.02, prev_out, in_val, out_val
            prev_out = out_val
        endif
        
        in_val = in_val + 0.02
    endwhile
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Output amplitude"
    Text bottom: "yes", "Input amplitude"
    
    # ----------------------------------------------------------
    # PANEL B: COMPRESSION TRANSFER CURVE  (right, headline)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40
    
    Axes: -60, 0, -60, 0
    Paint rectangle: "{0.97, 0.97, 0.97}", -60, 0, -60, 0
    
    # Grid
    Colour: "{0.85, 0.85, 0.88}"
    Line width: 1
    grid_line = -50
    while grid_line <= -10
        Draw line: grid_line, -60, grid_line, 0
        Draw line: -60, grid_line, 0, grid_line
        grid_line = grid_line + 10
    endwhile
    
    # Unity reference
    Dotted line
    Colour: "{0.65, 0.65, 0.70}"
    Draw line: -60, -60, 0, 0
    Solid line
    
    # Knee region (highlighted)
    if k > 0
        Paint rectangle: "{0.92, 0.92, 1}", t - half_k, t + half_k, -60, 0
    endif
    
    # Threshold line
    Colour: "{0.30, 0.45, 0.78}"
    Dotted line
    Draw line: t, -60, t, 0
    Solid line
    Font size: 6
    Colour: "{0.20, 0.30, 0.55}"
    Text: t, "right", -57, "half", "T " + fixed$(t, 0) + " "
    
    # Compression curve (same soft-knee form as the audio path)
    Colour: "{0.30, 0.65, 0.30}"
    Line width: 2.5
    
    in_lev = -60
    while in_lev <= 0
        if k <= 0
            if in_lev > t
                out_lev = t + (in_lev - t) / r
            else
                out_lev = in_lev
            endif
        else
            if in_lev < (t - half_k)
                out_lev = in_lev
            elsif in_lev > (t + half_k)
                out_lev = t + (in_lev - t) / r
            else
                over_k = in_lev - t + half_k
                out_lev = in_lev - slope * over_k * over_k / (2 * k)
            endif
        endif
        
        if in_lev = -60
            prev_out_lev = out_lev
        else
            Draw line: in_lev - 1, prev_out_lev, in_lev, out_lev
            prev_out_lev = out_lev
        endif
        
        in_lev = in_lev + 1
    endwhile
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Output (dB)"
    Text bottom: "yes", "Input RMS (dBFS)"
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Saturation: " + saturation_type$ +
    ... " (mix " + fixed$(harmonics_mix * 100, 0) + "%)"
    Text: 6.10, "centre", 7.30, "half", "Compression: " + fixed$(ratio, 1) +
    ... ":1 (knee " + fixed$(knee_dB, 0) + " dB)"
    
    # ----------------------------------------------------------
    # PANEL C: GAIN REDUCTION TIMELINE  (full width)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.95
    Select inner viewport: 0.55, 7.72, 4.75, 5.85
    
    selectObject: gain_sound
    gr_display = Copy: "gr_display"
    Formula: "20 * log10(self + 1e-10) - makeup_Gain_dB"
    
    gr_disp_min = Get minimum: 0, 0, "None"
    gr_disp_min = min(-6, floor(gr_disp_min / 3) * 3 - 3)
    
    Axes: x_start, x_end, gr_disp_min, 3
    Paint rectangle: "{1, 0.96, 0.96}", x_start, x_end, gr_disp_min, 0
    Paint rectangle: "{0.96, 1, 0.96}", x_start, x_end, 0, 3
    
    # Zero line
    Colour: "{0.55, 0.55, 0.55}"
    Draw line: x_start, 0, x_end, 0
    
    # Fill GR area below zero
    Colour: "{0.95, 0.55, 0.55}"
    selectObject: gr_display
    n_draw_points = 400
    draw_step = dur / n_draw_points
    t_pos = x_start
    while t_pos <= x_end
        val = Get value at time: 1, t_pos, "Nearest"
        if val <> undefined and val < 0
            Draw line: t_pos, 0, t_pos, val
        endif
        t_pos = t_pos + draw_step
    endwhile
    
    # GR curve on top
    Colour: "{0.65, 0.10, 0.10}"
    Line width: 1.5
    selectObject: gr_display
    Draw: x_start, x_end, gr_disp_min, 3, "no", "Curve"
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Gain reduction over time  (max " + fixed$(gr_max_reduction_dB, 1) + " dB)"
    Text left: "yes", "GR (dB)"
    Text bottom: "yes", "Time (s)"
    
    removeObject: gr_display
    
    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM (full file)
    # ----------------------------------------------------------
    selectObject: compressed
    n_ch_result = Get number of channels
    
    Select outer viewport: 0, 8, 6.02, 6.95
    Select inner viewport: 0.55, 7.72, 6.09, 6.88
    
    selectObject: compressed
    outPeakViz = Get absolute extremum: 0, 0, "None"
    if outPeakViz < 0.001
        outPeakViz = 0.001
    endif
    ampViz = outPeakViz * 1.15
    
    Axes: x_start, x_end, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", x_start, x_end, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: x_start, 0, x_end, 0
    
    selectObject: compressed
    if n_ch_result = 1
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
        
        if n_ch_result >= 2
            selectObject: compressed
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
    if n_ch_result > 2
        Text top: "no", "Output (compressed)  (blue=ch1  orange=ch2 of " +
        ... string$(n_ch_result) + ")"
    elsif n_ch_result = 2
        Text top: "no", "Output (compressed)  (blue=L  orange=R)"
    else
        Text top: "no", "Output (compressed, mono)"
    endif
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 7.02, 7.70
    Select inner viewport: 0.55, 7.72, 7.08, 7.64
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    if auto_makeup
        makeupStr$ = "auto +" + fixed$(makeup_Gain_dB, 1) + " dB"
    else
        makeupStr$ = "+" + fixed$(makeup_Gain_dB, 1) + " dB"
    endif
    if output_level_mode = 1
        levelStr$ = "none"
    elsif output_level_mode = 2
        levelStr$ = "ceiling " + fixed$(ceiling_peak, 2) + " (" + level_action$ + ")"
    else
        levelStr$ = "normalized to " + fixed$(ceiling_peak, 2)
    endif
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetDisp$ + "##"
        ... + "  " + original_name$
        ... + "  |  In peak: " + fixed$(in_peak_dB, 1) + " dB"
        ... + "  |  In RMS: " + fixed$(in_rms_dB, 1) + " dB"
        ... + "  |  Thr: " + fixed$(t, 1) + " dBFS"
        ... + "  |  GR max: " + fixed$(gr_max_reduction_dB, 1) + " dB"
        ... + "  |  Makeup: " + makeupStr$
    
    Text: 0.02, "left", 0.28, "half",
        ... "Sat: " + saturation_type$ + " (drive " + fixed$(drive * 100, 0) + "%, mix " + fixed$(harmonics_mix * 100, 0) + "%"
        ... + ", " + string$(os_factor) + "x)"
        ... + "  |  Out peak: " + fixed$(out_peak_dB, 1) + " dB"
        ... + "  |  Out RMS: " + fixed$(out_rms_dB, 1) + " dB"
        ... + "  |  Crest: " + fixed$(in_peak_dB - in_rms_dB, 1) + " -> " + fixed$(out_peak_dB - out_rms_dB, 1) + " dB"
        ... + "  |  Level: " + levelStr$
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
    # Restore complete page for Picture export / clipboard.
    pageHeight = 8.15
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line

endif

# === CLEANUP ===
removeObject: detector, gain_sound

if keep_original = 0
    removeObject: sound
endif

selectObject: compressed

appendInfoLine: ""
appendInfoLine: "============================================"
appendInfoLine: "Done! Output: ", original_name$, suf$
appendInfoLine: "============================================"

if play_result
    Play
endif

selectObject: compressed
