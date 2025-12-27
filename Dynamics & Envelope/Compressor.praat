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

form Studio Dynamic Compressor
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
    real Makeup_Gain_dB 0.0
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
    makeup_Gain_dB = 4.0
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
    makeup_Gain_dB = 3.0
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
    makeup_Gain_dB = 2.0
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
    makeup_Gain_dB = 0.0
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
    makeup_Gain_dB = 8.0
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
    makeup_Gain_dB = 15.0
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
appendInfoLine: "STUDIO DYNAMIC COMPRESSOR v1.0"
appendInfoLine: "============================================"
appendInfoLine: ""
appendInfoLine: "Input: ", original_name$
appendInfoLine: "Duration: ", fixed$(dur, 2), "s | SR: ", sr, " Hz | Ch: ", n_channels
appendInfoLine: ""
appendInfoLine: "Input Peak: ", fixed$(in_peak_dB, 1), " dBFS"
appendInfoLine: "Input RMS:  ", fixed$(in_rms_dB, 1), " dBFS"
appendInfoLine: ""
appendInfoLine: "--- Settings ---"
appendInfoLine: "Threshold: ", fixed$(threshold_dB, 1), " dB"
appendInfoLine: "Ratio: ", ratio, ":1"
appendInfoLine: "Knee: ", fixed$(knee_dB, 1), " dB"
appendInfoLine: "Attack: ", attack_ms, " ms"
appendInfoLine: "Release: ", release_ms, " ms"
if sidechain_filter > 1
    appendInfoLine: "Sidechain: ", sidechain_filter$
endif
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

# === ENVELOPE DETECTION ===
attack_sec = attack_ms / 1000
release_sec = release_ms / 1000

avg_time = (attack_sec + release_sec) / 2
detect_freq = 3.2 / avg_time
detect_freq = max(10, min(1000, detect_freq))

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
    typical_over = 10
    typical_gr = typical_over * (1 - 1/r)
    makeup_Gain_dB = typical_gr * 0.5
    appendInfoLine: "Auto Makeup: +", fixed$(makeup_Gain_dB, 1), " dB"
endif

# Apply makeup gain
selectObject: gain_matrix
makeup_linear = 10 ^ (makeup_Gain_dB / 20)
Formula: "self * makeup_linear"

# === GAIN REDUCTION STATS (before converting) ===
selectObject: gain_matrix
gr_min = Get minimum
gr_max = Get maximum
gr_min_dB = 20 * log10(gr_min + 1e-10) - makeup_Gain_dB
gr_max_dB = 20 * log10(gr_max + 1e-10) - makeup_Gain_dB

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
    appendInfoLine: ""
    appendInfoLine: "Peak Change: ", fixed$(out_peak_dB - in_peak_dB, 1), " dB"
    appendInfoLine: "RMS Change:  ", fixed$(out_rms_dB - in_rms_dB, 1), " dB"
    appendInfoLine: ""
    appendInfoLine: "Max Gain Reduction: ", fixed$(gr_min_dB, 1), " dB"
    appendInfoLine: ""
    appendInfoLine: "Crest Factor (Peak/RMS):"
    appendInfoLine: "  Input:  ", fixed$(in_peak_dB - in_rms_dB, 1), " dB"
    appendInfoLine: "  Output: ", fixed$(out_peak_dB - out_rms_dB, 1), " dB"
endif

# === VISUALIZATION ===
if draw_result
    Erase all
    Font size: 12
    
    # === TOP: Transfer Curve (larger, square) ===
    Select outer viewport: 0, 6, 0, 4.5
    Axes: -60, 0, -60, 0
    
    # Draw grid
    Colour: "Silver"
    Line width: 1
    grid_line = -50
    while grid_line <= -10
        Draw line: grid_line, -60, grid_line, 0
        Draw line: -60, grid_line, 0, grid_line
        grid_line = grid_line + 10
    endwhile
    
    # Draw 1:1 reference line (unity)
    Colour: "{0.6,0.6,0.6}"
    Line width: 1
    Dashed line
    Draw line: -60, -60, 0, 0
    Solid line
    
    # Draw threshold lines
    Colour: "{0.3,0.3,0.8}"
    Line width: 1
    Dashed line
    Draw line: t, -60, t, 0
    Draw line: -60, t, 0, t
    Solid line
    
    # Draw knee region if soft knee
    if k > 0
        Colour: "{0.8,0.8,1}"
        Paint rectangle: "{0.9,0.9,1}", t - half_k, t + half_k, -60, 0
    endif
    
    # Draw compression curve
    Colour: "{0.8,0.2,0.2}"
    Line width: 3
    
    in_lev = -60
    while in_lev <= 0
        if k <= 0
            # Hard knee
            if in_lev > t
                out_lev = t + (in_lev - t) / r
            else
                out_lev = in_lev
            endif
        else
            # Soft knee
            if in_lev < (t - half_k)
                out_lev = in_lev
            elsif in_lev > (t + half_k)
                out_lev = t + (in_lev - t) / r
            else
                knee_factor = (in_lev - t + half_k) / k
                knee_factor = knee_factor * knee_factor / 2
                out_lev = in_lev - knee_factor * (in_lev - t + half_k) * (1 - 1/r)
            endif
        endif
        
        if in_lev = -60
            prev_out = out_lev
        else
            Draw line: in_lev - 1, prev_out, in_lev, out_lev
            prev_out = out_lev
        endif
        
        in_lev = in_lev + 1
    endwhile
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    
    # Axis labels
    Marks bottom every: 1, 10, "yes", "yes", "no"
    Marks left every: 1, 10, "yes", "yes", "no"
    Text bottom: "yes", "Input Level (dB)"
    Text left: "yes", "Output Level (dB)"
    
    # Title with settings
    Font size: 14
    Text top: "yes", "##Transfer Curve## — Threshold: " + fixed$(t, 0) + "dB | Ratio: " + fixed$(ratio, 1) + ":1 | Knee: " + fixed$(knee_dB, 0) + "dB"
    Font size: 12
    
    # === BOTTOM: Gain Reduction Over Time ===
    Select outer viewport: 0, 6, 4.5, 7.5
    
    # Create GR display in dB
    selectObject: gain_sound
    gr_display = Copy: "gr_display"
    Formula: "20 * log10(self + 1e-10) - makeup_Gain_dB"
    
    gr_disp_min = Get minimum: 0, 0, "Sinc70"
    gr_disp_min = min(-6, floor(gr_disp_min / 3) * 3 - 3)
    
    # Set axes
    Axes: 0, dur, gr_disp_min, 3
    
    # Background for GR area
    Paint rectangle: "{1,0.95,0.95}", 0, dur, gr_disp_min, 0
    
    # Draw zero line
    Colour: "{0.5,0.5,0.5}"
    Line width: 1
    Draw line: 0, 0, dur, 0
    
    # Fill gain reduction area
    Colour: "{0.9,0.3,0.3}"
    selectObject: gr_display
    n_draw_points = 400
    draw_step = dur / n_draw_points
    t_pos = 0
    while t_pos <= dur
        val = Get value at time: 1, t_pos, "Sinc70"
        if val < 0
            Draw line: t_pos, 0, t_pos, val
        endif
        t_pos = t_pos + draw_step
    endwhile
    
    # Draw GR curve on top
    Colour: "{0.6,0,0}"
    Line width: 2
    selectObject: gr_display
    Draw: 0, dur, gr_disp_min, 3, "no", "Curve"
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    
    # Axis marks
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    Marks left every: 1, 3, "yes", "yes", "no"
    One mark left: 0, "no", "yes", "yes", "0"
    
    Text bottom: "yes", "Time (seconds)"
    Text left: "yes", "Gain Reduction (dB)"
    
    # Title
    Font size: 14
    Text top: "yes", "##Gain Reduction## — Max: " + fixed$(gr_min_dB, 1) + " dB | Attack: " + fixed$(attack_ms, 0) + "ms | Release: " + fixed$(release_ms, 0) + "ms"
    Font size: 12
    
    removeObject: gr_display
    
    # Reset viewport
    Select outer viewport: 0, 6, 0, 7.5
endif

# === CLEANUP ===
removeObject: sidechain, intensity, env_smoothed, gain_matrix, gain_sound

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