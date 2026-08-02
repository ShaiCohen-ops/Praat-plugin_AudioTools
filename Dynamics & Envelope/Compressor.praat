# ============================================================
# Praat AudioTools - Compressor.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Studio RMS compressor with separate attack/release, soft knee,
#   sidechain filtering, and visualization.
#
# Usage:
#   Select a Sound object in Praat and run this script.
#
# --- Changelog v1.0 -> v1.1 (static review fixes) ---------------
#   FIX-1  Peak measurement used "Get maximum" (largest signed sample)
#          instead of true absolute peak. Now uses
#          "Get absolute extremum", applied to input, output, and the
#          post-compression signal before any limiting decision.
#   FIX-2  The detector envelope was recalibrated every run so its
#          maximum always equalled the input's true peak. This (a)
#          made the "RMS" detector track peak, not RMS, and (b)
#          silently cancelled the global attenuation of any sidechain
#          filter. Replaced with a FIXED physical constant
#          (dBFS = dB_SPL - 93.9794, from Praat's default assumption
#          that Sound samples represent Pascals and P_ref = 2e-5 Pa).
#          This is an approximation of true windowed RMS in dBFS
#          (Praat's Intensity uses a Kaiser-like analysis window, not
#          a rectangular one) but it no longer erases filtering.
#   FIX-3  Makeup gain and Auto makeup were multiplied into the gain
#          curve but then silently cancelled by an unconditional
#          "Scale peak" at the end, making them audibly meaningless.
#          Replaced with an explicit Output_mode: Preserve level /
#          Limiter (scale down only if needed) / Normalize to target.
#   FIX-4  Soft-knee formula was cubic in the knee region instead of
#          the standard quadratic soft knee. Fixed in both the gain
#          engine and the transfer-curve plot (they must match).
#   FIX-5  Multichannel sidechain used "Convert to mono" (plain
#          channel average), which can null out fully or partially
#          anti-phase material, silencing the detector. Replaced with
#          a phase-safe linked detector: sqrt(mean of squared
#          channels), computed natively per channel.
#   FIX-6  "detect_freq = 400" was an opaque pitch-analysis hack.
#          Replaced with explicit Rms_window_ms / Detector_update_ms
#          parameters (still implemented via Praat's Intensity
#          analysis window under the hood). "Hard Limiter" / "NUKE"
#          presets are documented as fast RMS compressors, not
#          sample-accurate peak limiters, and now use short analysis
#          windows appropriate to their speed.
#   FIX-7  Added validation: Ratio >= 1, Knee_dB >= 0, 0 < Scale_peak
#          <= 1, and a Nyquist check for the lowpass/highpass
#          sidechain filters against the file's sample rate.
#   FIX-8  Waveform and gain-reduction timeline panels assumed
#          xmin = 0. Now read the Sound's actual start/end time.
#   FIX-9  Waveform panel's vertical range was set from the input
#          only, which could clip the plotted (but not the audio)
#          output curve. Range now considers both input and output.
#   FIX-10 In "Custom" mode the final object was renamed back to the
#          original object's name (suf$ = ""), colliding with the
#          kept original. Custom now gets "_Comp" like the others.
#   Note:  Sidechain filters use "Filter (pass Hann band)", a
#          zero-phase frequency-domain filter. This can produce a
#          small amount of gain movement slightly before a transient
#          (an unstated lookahead). Documented here and in the Info
#          output; left as-is since it is a defensible choice for an
#          offline tool.
#   Note:  "Lowpass 8kHz" is not a dedicated de-esser (it still
#          passes bass/mid/most of the voice); label reworded so it
#          isn't oversold as de-essing.
#
# --- Changelog v1.1 -> v1.2 (second static review round) --------
#   FIX-11 The multichannel detector squared/linked channels BEFORE
#          the sidechain filter and BEFORE "To Intensity", then used
#          "Subtract mean = yes" on that already-rectified, always-
#          non-negative magnitude signal. Subtracting the local mean
#          of a rectified signal removes real energy, not DC offset:
#          an identical mono signal duplicated to stereo could drive
#          the detector ~7 dB differently than the mono original, and
#          the sidechain filter was filtering a rectified spectrum
#          instead of the file's real one. Reordered to filter each
#          channel's raw waveform first, then square/link/sqrt, then
#          "To Intensity ... 'no'". Mono and multichannel now share
#          one pipeline (the per-channel loop runs even for n=1), so
#          duplicating a mono channel to stereo no longer changes the
#          detector's behaviour.
#   FIX-12 Output_mode = Normalize called "Scale peak" unconditionally,
#          which fails/errors on a fully silent compressed output.
#          Added the same kind of silent-output guard the Limiter mode
#          already had implicitly.
#   FIX-13 When extending a short gain curve to the file's full
#          duration, both the leading and trailing edges were filled
#          with the curve's LAST value. The leading edge (before the
#          detector's first analysis frame) now uses the curve's own
#          first value instead.
#   FIX-14 The Normalize-mode Info message claimed makeup gain "shapes
#          dynamics only" under normalization. It doesn't shape
#          anything: it's a flat scalar multiply that normalization
#          fully cancels. Wording corrected.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Studio Dynamic Compressor (Hybrid)
    optionmenu Preset 1
        option Custom
        option Vocal Leveler (Smooth)
        option Drum Punch (Fast)
        option Mix Bus Glue (Gentle)
        option Fast Compressor RMS (was Hard Limiter)
        option Squash (Heavy)
        option NUKE Extreme RMS (was NUKE)
    comment === Dynamics ===
    real Threshold_dB -20.0
    positive Ratio 4.0
    real Knee_dB 6.0
    comment === Time Constants (ms) ===
    positive Attack_ms 10
    positive Release_ms 100
    comment === Detector (RMS analysis window) ===
    positive Rms_window_ms 8.0
    positive Detector_update_ms 2.0
    comment === Sidechain Filter (zero-phase, offline) ===
    optionmenu Sidechain_filter 1
        option Off
        option Highpass 80Hz (reduce bass pumping)
        option Highpass 150Hz (vocal focus)
        option Lowpass 8kHz (reduce HF content, not true de-essing)
    comment === Output ===
    real Makeup_gain_dB 0.0
    boolean Auto_makeup 1
    optionmenu Output_mode 2
        option Preserve level (no final scaling)
        option Limiter (scale down only if needed)
        option Normalize to target (old v1.0 behaviour)
    positive Scale_peak 0.99
    comment === Options ===
    boolean Draw_result 1
    boolean Show_stats 1
    boolean Play_result 1
    boolean Keep_original 1
endform

# === APPLY PRESETS ===
suf$ = "_Comp"

if preset = 2
    # Vocal Leveler
    threshold_dB = -24.0
    ratio = 2.5
    knee_dB = 8.0
    attack_ms = 15
    release_ms = 150
    rms_window_ms = 15
    detector_update_ms = 3
    makeup_gain_dB = 4.0
    auto_makeup = 0
    sidechain_filter = 3
    suf$ = "_Vocal"
elsif preset = 3
    # Drum Punch
    threshold_dB = -18.0
    ratio = 6.0
    knee_dB = 3.0
    attack_ms = 1
    release_ms = 50
    rms_window_ms = 3
    detector_update_ms = 1
    makeup_gain_dB = 3.0
    auto_makeup = 0
    sidechain_filter = 1
    suf$ = "_Drum"
elsif preset = 4
    # Mix Bus Glue
    threshold_dB = -14.0
    ratio = 2.0
    knee_dB = 10.0
    attack_ms = 30
    release_ms = 200
    rms_window_ms = 25
    detector_update_ms = 5
    makeup_gain_dB = 2.0
    auto_makeup = 0
    sidechain_filter = 1
    suf$ = "_Bus"
elsif preset = 5
    # Fast Compressor RMS (formerly "Hard Limiter")
    threshold_dB = -3.0
    ratio = 20.0
    knee_dB = 0.0
    attack_ms = 0.5
    release_ms = 50
    rms_window_ms = 2
    detector_update_ms = 0.5
    makeup_gain_dB = 0.0
    auto_makeup = 0
    sidechain_filter = 1
    suf$ = "_FastComp"
elsif preset = 6
    # Squash
    threshold_dB = -30.0
    ratio = 10.0
    knee_dB = 6.0
    attack_ms = 5
    release_ms = 80
    rms_window_ms = 5
    detector_update_ms = 1
    makeup_gain_dB = 8.0
    auto_makeup = 0
    sidechain_filter = 1
    suf$ = "_Squash"
elsif preset = 7
    # NUKE Extreme RMS
    threshold_dB = -40.0
    ratio = 100.0
    knee_dB = 0.0
    attack_ms = 0.5
    release_ms = 30
    rms_window_ms = 2
    detector_update_ms = 0.5
    makeup_gain_dB = 15.0
    auto_makeup = 0
    sidechain_filter = 1
    suf$ = "_NUKE"
endif

# === VALIDATION ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

# FIX-7: parameter validation
if ratio < 1
    exitScript: "Ratio must be at least 1:1 (values below 1 would expand, not compress, the signal)."
endif
if knee_dB < 0
    exitScript: "Knee_dB cannot be negative. Use 0 for a hard knee."
endif
if scale_peak <= 0 or scale_peak > 1
    exitScript: "Scale_peak must be greater than 0 and at most 1.0 (digital full scale)."
endif

sound = selected("Sound")
original_name$ = selected$("Sound")
sr = Get sampling frequency
dur = Get total duration
n_channels = Get number of channels

# FIX-8: real start/end time instead of assuming 0..dur
xminOrig = Get start time
xmaxOrig = Get end time

# FIX-7: Nyquist check for sidechain filters
nyquist = sr / 2
if sidechain_filter = 2 and nyquist <= 80
    exitScript: "Sample rate too low for the 80 Hz highpass sidechain filter (Nyquist = " + fixed$(nyquist, 0) + " Hz)."
elsif sidechain_filter = 3 and nyquist <= 150
    exitScript: "Sample rate too low for the 150 Hz highpass sidechain filter (Nyquist = " + fixed$(nyquist, 0) + " Hz)."
elsif sidechain_filter = 4 and nyquist <= 8000
    exitScript: "Sample rate too low for the 8 kHz lowpass sidechain filter (Nyquist = " + fixed$(nyquist, 0) + " Hz). Choose a different sidechain filter or use a higher sample rate."
endif

# === INPUT MEASUREMENTS ===
selectObject: sound
# FIX-1: absolute peak, not signed maximum
in_peak = Get absolute extremum: 0, 0, "Sinc70"
in_peak_dB = 20 * log10(abs(in_peak) + 1e-10)
in_rms = Get root-mean-square: 0, 0
in_rms_dB = 20 * log10(in_rms + 1e-10)

# === INFO HEADER ===
writeInfoLine: "============================================"
appendInfoLine: "STUDIO COMPRESSOR HYBRID  (v1.2)"
appendInfoLine: "============================================"
appendInfoLine: ""
appendInfoLine: "Input: ", original_name$
appendInfoLine: "Input Peak: ", fixed$(in_peak_dB, 1), " dBFS"
appendInfoLine: ""
appendInfoLine: "--- Settings ---"
appendInfoLine: "Threshold: ", fixed$(threshold_dB, 1), " dB"
appendInfoLine: "Ratio: ", ratio, ":1"
appendInfoLine: "Attack: ", attack_ms, " ms | Release: ", release_ms, " ms"
appendInfoLine: "Detector window: ", rms_window_ms, " ms | update: ", detector_update_ms, " ms"
if sidechain_filter > 1
    appendInfoLine: "Sidechain filter is zero-phase (offline); may cause slight pre-transient gain movement."
endif
appendInfoLine: ""

# === BUILD SIDECHAIN (PHASE-SAFE, FIX-5 / v1.2 reorder) ===
# Order matters: the sidechain filter must see each channel's own
# waveform (which can go negative and has the file's real spectrum),
# not an already-rectified, already-linked magnitude signal. So the
# per-channel loop now filters -> squares -> accumulates, and only
# THEN links channels together. This one loop also handles the mono
# case (n_channels = 1), so mono and multichannel share one pipeline
# and a mono file duplicated to stereo drives the detector the same
# way.
selectObject: sound
sc_accum = Create Sound from formula: "sc_accum", 1, xminOrig, xmaxOrig, sr, "0"
for ch from 1 to n_channels
    selectObject: sound
    sc_ch = Extract one channel: ch
    chname$ = "sc_ch" + string$(ch)
    Rename: chname$

    # Filter this channel's raw waveform (zero-phase, offline) BEFORE
    # any squaring, so the filter sees the file's actual spectrum.
    if sidechain_filter = 2
        selectObject: sc_ch
        Filter (pass Hann band): 80, 0, 50
        filtered_ch = selected("Sound")
        removeObject: sc_ch
        sc_ch = filtered_ch
        Rename: chname$
    elsif sidechain_filter = 3
        selectObject: sc_ch
        Filter (pass Hann band): 150, 0, 50
        filtered_ch = selected("Sound")
        removeObject: sc_ch
        sc_ch = filtered_ch
        Rename: chname$
    elsif sidechain_filter = 4
        selectObject: sc_ch
        Filter (pass Hann band): 0, 8000, 50
        filtered_ch = selected("Sound")
        removeObject: sc_ch
        sc_ch = filtered_ch
        Rename: chname$
    endif

    selectObject: sc_accum
    Formula: "self + Sound_" + chname$ + "(x)^2"
    removeObject: sc_ch
endfor

selectObject: sc_accum
Formula: "sqrt(self / 'n_channels')"
sidechain = sc_accum
Rename: "sidechain"

# === ENVELOPE DETECTION ===
attack_sec = attack_ms / 1000
release_sec = release_ms / 1000

# FIX-6: explicit RMS window / update rate instead of "detect_freq" hack
pitch_floor = 3.2 / (rms_window_ms / 1000)
time_step = detector_update_ms / 1000

# "sidechain" is now a non-negative energy-linked signal (it's already
# been squared and sqrt'd), not a raw pressure waveform. Subtracting
# its local mean would remove real energy, not DC offset, so
# subtract-mean = "no" here (this was the bug the previous review
# caught: "yes" is correct for a normal signed waveform, but wrong
# once the signal has been rectified).
selectObject: sidechain
intensity = To Intensity: pitch_floor, time_step, "no"

# FIX-2: fixed physical calibration, NOT re-derived from this file's peak.
# Praat's Intensity assumes Sound samples represent pressure in Pascals,
# with reference pressure P_ref = 2e-5 Pa (0 dB SPL). To express that on
# a dBFS scale (relative to digital full scale = 1.0):
#   dBFS = dB_SPL + 20*log10(P_ref) = dB_SPL - 93.9794
# Using a fixed constant (rather than matching this file's peak) keeps
# any sidechain filter's global attenuation intact, and keeps the
# detector's shape close to true RMS rather than tracking the peak.
dBFS_offset = -93.9794
selectObject: intensity
Formula: "self + dBFS_offset"

# === APPLY ATTACK/RELEASE SMOOTHING ===
env_matrix = Down to Matrix

selectObject: env_matrix
env_nx = Get number of columns
env_dx = Get column distance

selectObject: env_matrix
env_smoothed = Copy: "env_smoothed"

attack_samples = max(1, round(attack_sec / env_dx))
release_samples = max(1, round(release_sec / env_dx))

prev_val = Get value in cell: 1, 1

for col from 1 to env_nx
    selectObject: env_matrix
    curr_val = Get value in cell: 1, col

    if curr_val > prev_val
        alpha = 1 - exp(-2.2 / attack_samples)
    else
        alpha = 1 - exp(-2.2 / release_samples)
    endif

    smoothed = prev_val + alpha * (curr_val - prev_val)

    selectObject: env_smoothed
    Set value: 1, col, smoothed

    prev_val = smoothed
endfor

removeObject: env_matrix

# === COMPUTE GAIN REDUCTION (FIX-4: quadratic soft knee) ===
selectObject: env_smoothed
gain_matrix = Copy: "gain_reduction"

t = threshold_dB
r = ratio
k = knee_dB
half_k = k / 2

selectObject: gain_matrix

for col from 1 to env_nx
    level = Get value in cell: 1, col

    if k <= 0
        if level > t
            gain_reduction_dB = -1 * (level - t) * (1 - 1/r)
        else
            gain_reduction_dB = 0
        endif
    else
        if level < (t - half_k)
            gain_reduction_dB = 0
        elsif level > (t + half_k)
            gain_reduction_dB = -1 * (level - t) * (1 - 1/r)
        else
            over_thresh = level - t + half_k
            gain_reduction_dB = -1 * (over_thresh^2 / (2 * k)) * (1 - 1/r)
        endif
    endif

    gain_linear = 10 ^ (gain_reduction_dB / 20)
    Set value: 1, col, gain_linear
endfor

# === CALCULATE AUTO MAKEUP GAIN ===
if auto_makeup
    headroom = abs(t)
    if headroom > 20
        headroom = 20
    endif
    makeup_gain_dB = (headroom / 2) * (1 - 1/r)
    appendInfoLine: "Auto Makeup: +", fixed$(makeup_gain_dB, 1), " dB"
endif

# Apply makeup gain
selectObject: gain_matrix
makeup_linear = 10 ^ (makeup_gain_dB / 20)
Formula: "self * makeup_linear"

# === CONVERT GAIN CURVE TO SOUND ===
selectObject: gain_matrix
gain_sound = To Sound
Rename: "GainCurve"

gain_sr = Get sampling frequency
if gain_sr <> sr
    Resample: sr, 50
    resampled = selected("Sound")
    removeObject: gain_sound
    gain_sound = resampled
    Rename: "GainCurve"
endif

selectObject: gain_sound
gain_dur = Get total duration
if gain_dur < dur
    selectObject: gain_sound
    gsxmin = Get start time
    gsxmax = Get end time
    # FIX (v1.2): extrapolate each edge with ITS OWN nearest value, not
    # last_val on both ends. The tail before the curve's first frame
    # gets the curve's own first value; the tail after its last frame
    # gets the curve's own last value.
    first_val = Get value at time: 1, gsxmin + 0.001, "Sinc70"
    last_val = Get value at time: 1, gsxmax - 0.001, "Sinc70"
    extended = Create Sound from formula: "extended", 1, xminOrig, xmaxOrig, sr, string$(first_val)
    Formula (part): gsxmax, xmaxOrig, 1, 1, string$(last_val)
    Formula (part): gsxmin, gsxmax, 1, 1, "Sound_GainCurve(x)"
    removeObject: gain_sound
    gain_sound = extended
    Rename: "GainCurve"
endif

# === APPLY COMPRESSION ===
selectObject: sound
compressed = Copy: original_name$ + suf$
Formula: "self * Sound_GainCurve(x)"

# === GAIN REDUCTION STATS ===
selectObject: gain_sound
gr_min = Get minimum: 0, 0, "Sinc70"
gr_min_dB = 20 * log10(gr_min + 1e-10) - makeup_gain_dB

# === FINAL SCALING (FIX-3: makeup gain no longer silently erased) ===
selectObject: compressed
# FIX-1: absolute peak here too, before deciding whether to scale
comp_peak = Get absolute extremum: 0, 0, "Sinc70"
comp_peak_dB = 20 * log10(abs(comp_peak) + 1e-10)
target_peak_dB = 20 * log10(scale_peak)

if output_mode = 1
    # Preserve level: no scaling, warn if it would clip
    if comp_peak_dB > 0
        appendInfoLine: "WARNING: output peak is ", fixed$(comp_peak_dB, 1), " dBFS and may clip (Output_mode = Preserve level)."
    endif
elsif output_mode = 2
    # Limiter: only scale DOWN, never up, so makeup gain still audibly matters
    if comp_peak_dB > target_peak_dB
        Scale peak: scale_peak
    endif
else
    # Normalize to target: old v1.0 behaviour, kept as an explicit choice.
    # Guard against a silent (all-zero) output, which would otherwise
    # be handed to "Scale peak" with a peak of 0.
    if comp_peak > 0
        Scale peak: scale_peak
    else
        appendInfoLine: "Output is silent — normalization skipped."
    endif
endif

# === OUTPUT MEASUREMENTS ===
out_peak = Get absolute extremum: 0, 0, "Sinc70"
out_peak_dB = 20 * log10(abs(out_peak) + 1e-10)
out_rms = Get root-mean-square: 0, 0
out_rms_dB = 20 * log10(out_rms + 1e-10)

# === STATS OUTPUT ===
if show_stats
    appendInfoLine: ""
    appendInfoLine: "--- Results ---"
    appendInfoLine: "Output Peak: ", fixed$(out_peak_dB, 1), " dBFS"
    appendInfoLine: "Output RMS:  ", fixed$(out_rms_dB, 1), " dBFS"
    appendInfoLine: "Max Gain Reduction: ", fixed$(gr_min_dB, 1), " dB"
    if output_mode = 3
        appendInfoLine: "Output_mode = Normalize cancels the magnitude of Makeup_gain_dB entirely (it is a flat post-multiply); final peak is set solely by Scale_peak."
    endif
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_result
    appendInfoLine: ""
    appendInfoLine: "Creating visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # ----------------------------------------------------------
    # Title
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.85, "half", "##Studio Dynamic Compressor##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.25, "half",
        ... original_name$ + "  |  Ratio " + fixed$(ratio, 1) + ":1"
        ... + "  |  Thresh " + fixed$(threshold_dB, 0) + " dB"
        ... + "  |  A=" + fixed$(attack_ms, 0) + " R=" + fixed$(release_ms, 0) + " ms"

    # ----------------------------------------------------------
    # Transfer curve (left half)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.1, 0.52, 3.52
    Select inner viewport: 0.55, 3.85, 0.72, 3.40

    Axes: -60, 0, -60, 0
    Paint rectangle: "{0.97, 0.97, 0.97}", -60, 0, -60, 0

    # Grid
    Colour: "{0.86, 0.86, 0.86}"
    Line width: 1
    grid_line = -50
    while grid_line <= -10
        Draw line: grid_line, -60, grid_line, 0
        Draw line: -60, grid_line, 0, grid_line
        grid_line = grid_line + 10
    endwhile

    # 1:1 reference
    Colour: "{0.62, 0.62, 0.62}"
    Dashed line
    Draw line: -60, -60, 0, 0
    Solid line

    # Threshold lines
    Colour: "{0.30, 0.30, 0.80}"
    Dashed line
    Draw line: threshold_dB, -60, threshold_dB, 0
    Draw line: -60, threshold_dB, 0, threshold_dB
    Solid line

    # Knee region
    if knee_dB > 0
        Paint rectangle: "{0.92, 0.92, 1.00}",
            ... threshold_dB - knee_dB/2, threshold_dB + knee_dB/2, -60, 0
    endif

    # Compression curve (FIX-4: matches the quadratic engine formula)
    Colour: "{0.80, 0.20, 0.20}"
    Line width: 3
    prev_out = -60
    for in_lev from -60 to 0
        if knee_dB <= 0
            if in_lev > threshold_dB
                out_lev = threshold_dB + (in_lev - threshold_dB) / ratio
            else
                out_lev = in_lev
            endif
        else
            if in_lev < (threshold_dB - knee_dB/2)
                out_lev = in_lev
            elsif in_lev > (threshold_dB + knee_dB/2)
                out_lev = threshold_dB + (in_lev - threshold_dB) / ratio
            else
                over_thresh = in_lev - threshold_dB + knee_dB/2
                out_lev = in_lev - (over_thresh^2 / (2 * knee_dB)) * (1 - 1/ratio)
            endif
        endif
        if in_lev > -60
            Draw line: in_lev - 1, prev_out, in_lev, out_lev
        endif
        prev_out = out_lev
    endfor

    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, 10, "yes", "yes", "no"
    Marks left every: 1, 10, "yes", "yes", "no"
    Font size: 7
    Text bottom: "yes", "Input (dB)"
    Text left: "yes", "Output (dB)"
    Text top: "no", "Transfer curve"

    # ----------------------------------------------------------
    # Waveform comparison (right upper)
    # ----------------------------------------------------------
    Select outer viewport: 4.1, 8, 0.52, 2.12
    Select inner viewport: 4.40, 7.65, 0.62, 2.02

    # FIX-9: range considers BOTH input and output, so the plotted
    # output curve can't extend past the drawn axes.
    selectObject: sound
    wave_max_in = Get maximum: 0, 0, "Sinc70"
    wave_min_in = Get minimum: 0, 0, "Sinc70"
    selectObject: compressed
    wave_max_out = Get maximum: 0, 0, "Sinc70"
    wave_min_out = Get minimum: 0, 0, "Sinc70"
    wave_range = max(max(abs(wave_max_in), abs(wave_min_in)), max(abs(wave_max_out), abs(wave_min_out))) * 1.1

    # FIX-8: real start/end time, not assumed 0..dur
    Axes: xminOrig, xmaxOrig, -wave_range, wave_range
    Paint rectangle: "{0.97, 0.97, 0.97}", xminOrig, xmaxOrig, -wave_range, wave_range
    Colour: "{0.80, 0.80, 0.80}"
    Draw line: xminOrig, 0, xmaxOrig, 0

    # Input (grey)
    selectObject: sound
    Colour: "{0.62, 0.62, 0.62}"
    Line width: 1
    Draw: 0, 0, 0, 0, "no", "Curve"

    # Output (green)
    selectObject: compressed
    Colour: "{0.20, 0.60, 0.30}"
    Line width: 1.5
    Draw: 0, 0, 0, 0, "no", "Curve"

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Waveform  (grey=in  green=out)"

    # ----------------------------------------------------------
    # Stats panel (right lower)
    # ----------------------------------------------------------
    Select outer viewport: 4.1, 8, 2.18, 3.52
    Select inner viewport: 4.40, 7.65, 2.26, 3.42
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.08, "left", 0.88, "half", "##Metering##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.08, "left", 0.72, "half", "In Peak:   " + fixed$(in_peak_dB, 1) + " dBFS"
    Text: 0.08, "left", 0.56, "half", "Out Peak: " + fixed$(out_peak_dB, 1) + " dBFS"
    Text: 0.08, "left", 0.40, "half", "In RMS:   " + fixed$(in_rms_dB, 1) + " dBFS"
    Text: 0.08, "left", 0.24, "half", "Out RMS: " + fixed$(out_rms_dB, 1) + " dBFS"

    # Max GR indicator
    Font size: 7
    Colour: "{0.70, 0.15, 0.15}"
    Text: 0.60, "left", 0.72, "half", "Max GR:"
    Font size: 6
    Text: 0.60, "left", 0.56, "half", fixed$(gr_min_dB, 1) + " dB"
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.60, "left", 0.40, "half", "Makeup:"
    Text: 0.60, "left", 0.24, "half", "+" + fixed$(makeup_gain_dB, 1) + " dB"

    Colour: "Black"
    Draw inner box

    # ----------------------------------------------------------
    # Gain Reduction timeline (full width)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 3.60, 5.10
    Select inner viewport: 0.55, 7.65, 3.70, 5.00

    # Create GR display in dB
    selectObject: gain_sound
    gr_display = Copy: "gr_display"
    Formula: "20 * log10(self + 1e-10) - makeup_gain_dB"

    gr_disp_min = Get minimum: 0, 0, "Sinc70"
    gr_disp_min = min(-6, floor(gr_disp_min / 3) * 3 - 3)

    # FIX-8: real start/end time
    Axes: xminOrig, xmaxOrig, gr_disp_min, 3

    # Background — red below 0, green above
    Paint rectangle: "{1, 0.96, 0.96}", xminOrig, xmaxOrig, gr_disp_min, 0
    Paint rectangle: "{0.96, 1, 0.96}", xminOrig, xmaxOrig, 0, 3

    # Zero line
    Colour: "{0.55, 0.55, 0.55}"
    Draw line: xminOrig, 0, xmaxOrig, 0

    # Fill GR area
    Colour: "{0.90, 0.30, 0.30}"
    n_draw_points = 500
    draw_step = dur / n_draw_points
    t_pos = xminOrig
    while t_pos <= xmaxOrig
        selectObject: gr_display
        val = Get value at time: 1, t_pos, "Sinc70"
        if val < 0
            Draw line: t_pos, 0, t_pos, val
        endif
        t_pos = t_pos + draw_step
    endwhile

    # GR curve on top
    Colour: "{0.60, 0, 0}"
    Line width: 2
    selectObject: gr_display
    Draw: 0, 0, gr_disp_min, 3, "no", "Curve"

    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    Marks left every: 1, 3, "yes", "yes", "no"
    One mark left: 0, "no", "yes", "yes", "0"
    Font size: 7
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "GR (dB)"
    Text top: "no", "Gain reduction timeline"

    removeObject: gr_display

    # ----------------------------------------------------------
    # Summary panel
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.20, 5.98
    Select inner viewport: 0.55, 7.65, 5.26, 5.92
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.82, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"

    if sidechain_filter = 2
        scStr$ = "HP 80Hz"
    elsif sidechain_filter = 3
        scStr$ = "HP 150Hz"
    elsif sidechain_filter = 4
        scStr$ = "LP 8kHz"
    else
        scStr$ = "Off"
    endif

    Text: 0.02, "left", 0.52, "half",
        ... "Thresh: " + fixed$(threshold_dB, 0) + " dB"
        ... + "  |  Ratio: " + fixed$(ratio, 1) + ":1"
        ... + "  |  Knee: " + fixed$(knee_dB, 0) + " dB"
        ... + "  |  Attack: " + fixed$(attack_ms, 0) + " ms"
        ... + "  |  Release: " + fixed$(release_ms, 0) + " ms"
        ... + "  |  SC: " + scStr$
    Text: 0.02, "left", 0.18, "half",
        ... "Makeup: +" + fixed$(makeup_gain_dB, 1) + " dB"
        ... + "  |  Max GR: " + fixed$(gr_min_dB, 1) + " dB"
        ... + "  |  Peak: " + fixed$(in_peak_dB, 1) + " -> " + fixed$(out_peak_dB, 1) + " dBFS"
        ... + "  |  RMS: " + fixed$(in_rms_dB, 1) + " -> " + fixed$(out_rms_dB, 1) + " dBFS"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# === CLEANUP ===
removeObject: sidechain, intensity, env_smoothed, gain_matrix, gain_sound

if keep_original = 0
    removeObject: sound
endif

selectObject: compressed

appendInfoLine: ""
appendInfoLine: "Complete."

if play_result
    Play
endif
