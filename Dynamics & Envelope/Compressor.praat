# ============================================================
# Praat AudioTools - Compressor.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Professional RMS compressor with separate attack/release,
#   soft knee, sidechain filtering, and visualization.
#
# Usage:
#   Select a Sound object in Praat and run this script.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Studio Dynamic Compressor (Hybrid)
    optionmenu Preset 1
        option Custom
        option Vocal Leveler (Smooth)
        option Drum Punch (Fast)
        option Mix Bus Glue (Gentle)
        option Hard Limiter
        option Squash (Heavy)
        option NUKE (Extreme)
    comment === Dynamics ===
    real Threshold_dB -20.0
    positive Ratio 4.0
    real Knee_dB 6.0
    comment === Time Constants (ms) ===
    positive Attack_ms 10
    positive Release_ms 100
    comment === Sidechain Filter ===
    optionmenu Sidechain_filter 1
        option Off
        option Highpass 80Hz (reduce bass pumping)
        option Highpass 150Hz (vocal focus)
        option Lowpass 8kHz (de-ess)
    comment === Output ===
    real Makeup_gain_dB 0.0
    boolean Auto_makeup 1
    positive Scale_peak 0.99
    comment === Options ===
    boolean Draw_result 1
    boolean Show_stats 1
    boolean Play_result 1
    boolean Keep_original 1
endform

# === APPLY PRESETS ===
suf$ = ""

if preset = 2
    # Vocal Leveler
    threshold_dB = -24.0
    ratio = 2.5
    knee_dB = 8.0
    attack_ms = 15
    release_ms = 150
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
    makeup_gain_dB = 2.0
    auto_makeup = 0
    sidechain_filter = 1
    suf$ = "_Bus"
elsif preset = 5
    # Hard Limiter
    threshold_dB = -3.0
    ratio = 20.0
    knee_dB = 0.0
    attack_ms = 0.5
    release_ms = 50
    makeup_gain_dB = 0.0
    auto_makeup = 0
    sidechain_filter = 1
    suf$ = "_Lim"
elsif preset = 6
    # Squash
    threshold_dB = -30.0
    ratio = 10.0
    knee_dB = 6.0
    attack_ms = 5
    release_ms = 80
    makeup_gain_dB = 8.0
    auto_makeup = 0
    sidechain_filter = 1
    suf$ = "_Squash"
elsif preset = 7
    # NUKE
    threshold_dB = -40.0
    ratio = 100.0
    knee_dB = 0.0
    attack_ms = 0.5
    release_ms = 30
    makeup_gain_dB = 15.0
    auto_makeup = 0
    sidechain_filter = 1
    suf$ = "_NUKE"
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

# === INPUT MEASUREMENTS ===
selectObject: sound
in_peak = Get maximum: 0, 0, "Sinc70"
in_peak_dB = 20 * log10(abs(in_peak) + 1e-10)
in_rms = Get root-mean-square: 0, 0
in_rms_dB = 20 * log10(in_rms + 1e-10)

# === INFO HEADER ===
writeInfoLine: "============================================"
appendInfoLine: "STUDIO COMPRESSOR HYBRID"
appendInfoLine: "============================================"
appendInfoLine: ""
appendInfoLine: "Input: ", original_name$
appendInfoLine: "Input Peak: ", fixed$(in_peak_dB, 1), " dBFS"
appendInfoLine: ""
appendInfoLine: "--- Settings ---"
appendInfoLine: "Threshold: ", fixed$(threshold_dB, 1), " dB"
appendInfoLine: "Ratio: ", ratio, ":1"
appendInfoLine: "Attack: ", attack_ms, " ms | Release: ", release_ms, " ms"
appendInfoLine: ""

# === CONVERT TO MONO FOR SIDECHAIN ===
selectObject: sound
if n_channels > 1
    sidechain = Convert to mono
else
    sidechain = Copy: "sidechain"
endif

# === APPLY SIDECHAIN FILTER ===
if sidechain_filter = 2
    selectObject: sidechain
    Filter (pass Hann band): 80, 0, 50
    filtered = selected("Sound")
    removeObject: sidechain
    sidechain = filtered
    Rename: "sidechain"
elsif sidechain_filter = 3
    selectObject: sidechain
    Filter (pass Hann band): 150, 0, 50
    filtered = selected("Sound")
    removeObject: sidechain
    sidechain = filtered
    Rename: "sidechain"
elsif sidechain_filter = 4
    selectObject: sidechain
    Filter (pass Hann band): 0, 8000, 50
    filtered = selected("Sound")
    removeObject: sidechain
    sidechain = filtered
    Rename: "sidechain"
endif

# === ENVELOPE DETECTION (THE FIX) ===
attack_sec = attack_ms / 1000
release_sec = release_ms / 1000

# FIXED: High Resolution Detection
detect_freq = 400

selectObject: sidechain
intensity = To Intensity: detect_freq, 0, "yes"

# Calibrate to dBFS
env_max = Get maximum: 0, 0, "Parabolic"
offset = in_peak_dB - env_max
Formula: "self + offset"

# === APPLY ATTACK/RELEASE SMOOTHING ===
env_matrix = Down to Matrix

selectObject: env_matrix
env_nx = Get number of columns
env_dx = Get column distance

selectObject: env_matrix
env_smoothed = Copy: "env_smoothed"

# Recalculate samples based on the new fixed high resolution
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

# === COMPUTE GAIN REDUCTION ===
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
            knee_factor = (level - t + half_k) / k
            knee_factor = knee_factor * knee_factor / 2
            over_thresh = level - t + half_k
            gain_reduction_dB = -1 * knee_factor * over_thresh * (1 - 1/r)
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
    last_val = Get value at time: 1, gain_dur - 0.001, "Sinc70"
    extended = Create Sound from formula: "extended", 1, 0, dur, sr, string$(last_val)
    Formula (part): 0, gain_dur, 1, 1, "Sound_GainCurve(x)"
    removeObject: gain_sound
    gain_sound = extended
    Rename: "GainCurve"
endif

# === APPLY COMPRESSION ===
selectObject: sound
compressed = Copy: original_name$ + "_Comp"
Formula: "self * Sound_GainCurve(x)"

# === GAIN REDUCTION STATS ===
selectObject: gain_sound
gr_min = Get minimum: 0, 0, "Sinc70"
gr_min_dB = 20 * log10(gr_min + 1e-10) - makeup_gain_dB

# === FINAL SCALING ===
selectObject: compressed
Scale peak: scale_peak
Rename: original_name$ + suf$

# === OUTPUT MEASUREMENTS ===
out_peak = Get maximum: 0, 0, "Sinc70"
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
endif

# ============================================================
# FULL VISUALIZATION (RESTORED FROM V1.1)
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

    # Compression curve
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
                knee_factor = (in_lev - threshold_dB + knee_dB/2) / knee_dB
                knee_factor = knee_factor * knee_factor / 2
                out_lev = in_lev - knee_factor * (in_lev - threshold_dB + knee_dB/2) * (1 - 1/ratio)
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

    selectObject: sound
    wave_max = Get maximum: 0, 0, "Sinc70"
    wave_min = Get minimum: 0, 0, "Sinc70"
    wave_range = max(abs(wave_max), abs(wave_min)) * 1.1

    Axes: 0, dur, -wave_range, wave_range
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, dur, -wave_range, wave_range
    Colour: "{0.80, 0.80, 0.80}"
    Draw line: 0, 0, dur, 0

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

    Axes: 0, dur, gr_disp_min, 3

    # Background — red below 0, green above
    Paint rectangle: "{1, 0.96, 0.96}", 0, dur, gr_disp_min, 0
    Paint rectangle: "{0.96, 1, 0.96}", 0, dur, 0, 3

    # Zero line
    Colour: "{0.55, 0.55, 0.55}"
    Draw line: 0, 0, dur, 0

    # Fill GR area
    Colour: "{0.90, 0.30, 0.30}"
    n_draw_points = 500
    draw_step = dur / n_draw_points
    t_pos = 0
    while t_pos <= dur
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
    Draw: 0, dur, gr_disp_min, 3, "no", "Curve"

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
        ... + "  |  Peak: " + fixed$(in_peak_dB, 1) + " → " + fixed$(out_peak_dB, 1) + " dBFS"
        ... + "  |  RMS: " + fixed$(in_rms_dB, 1) + " → " + fixed$(out_rms_dB, 1) + " dBFS"
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