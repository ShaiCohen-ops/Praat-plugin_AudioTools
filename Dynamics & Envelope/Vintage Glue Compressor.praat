# ============================================================
# Praat AudioTools - Vintage_Glue_Compressor.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Vintage-style compressor with analog saturation modeling.
#   Emulates Tube, Tape, and Transistor characteristics.
#
# Usage:
#   Select a Sound object in Praat and run this script.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Vintage Glue Compressor
    optionmenu Preset 1
        option Custom
        option Vocal Opto (LA-2A style)
        option Drum VCA (SSL style)
        option Mix Bus Glue (Classic)
        option Tape Squeeze (Saturated)
        option Tube Warmth (Gentle)
        option FET Punch (1176 style)
    comment === Dynamics ===
    real Threshold_dB -15.0
    positive Ratio 4.0
    real Knee_dB 6.0
    comment === Time Constants (ms) ===
    positive Attack_ms 10
    positive Release_ms 100
    comment === Analog Character ===
    optionmenu Saturation_type 1
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
    positive Scale_peak 0.99
    comment === Options ===
    boolean Draw_result 1
    boolean Show_stats 1
    boolean Play_result 1
    boolean Keep_original 1
endform

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
    # Vocal Opto (LA-2A)
    threshold_dB = -24.0
    ratio = 3.0
    knee_dB = 12.0
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
    # Drum VCA (SSL)
    threshold_dB = -18.0
    ratio = 8.0
    knee_dB = 3.0
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
    # Mix Bus Glue
    threshold_dB = -12.0
    ratio = 2.0
    knee_dB = 10.0
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
    # Tape Squeeze
    threshold_dB = -15.0
    ratio = 4.0
    knee_dB = 8.0
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
    # Tube Warmth
    threshold_dB = -20.0
    ratio = 2.5
    knee_dB = 15.0
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
    # FET Punch (1176)
    threshold_dB = -20.0
    ratio = 12.0
    knee_dB = 0.0
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
appendInfoLine: "VINTAGE GLUE COMPRESSOR v1.0"
appendInfoLine: "============================================"
appendInfoLine: ""
appendInfoLine: "Input: ", original_name$
appendInfoLine: "Duration: ", fixed$(dur, 2), "s | SR: ", sr, " Hz"
appendInfoLine: ""
appendInfoLine: "Input Peak: ", fixed$(in_peak_dB, 1), " dBFS"
appendInfoLine: "Input RMS:  ", fixed$(in_rms_dB, 1), " dBFS"
appendInfoLine: ""
appendInfoLine: "--- Compression ---"
appendInfoLine: "Threshold: ", fixed$(threshold_dB, 1), " dB | Ratio: ", ratio, ":1 | Knee: ", fixed$(knee_dB, 1), " dB"
appendInfoLine: "Attack: ", attack_ms, " ms | Release: ", release_ms, " ms"
appendInfoLine: ""
appendInfoLine: "--- Saturation ---"
appendInfoLine: "Type: ", saturation_type$
appendInfoLine: "Drive: ", fixed$(drive * 100, 0), "% | Harmonics Mix: ", fixed$(harmonics_mix * 100, 0), "%"
appendInfoLine: ""

# === ENVELOPE DETECTION ===
selectObject: sound
if n_channels > 1
    sidechain = Convert to mono
else
    sidechain = Copy: "sidechain"
endif

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

# === ATTACK/RELEASE SMOOTHING ===
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

# === GAIN REDUCTION WITH SOFT KNEE ===
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

# === AUTO MAKEUP GAIN ===
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

# === GR STATS ===
selectObject: gain_matrix
gr_min = Get minimum
gr_min_dB = 20 * log10(gr_min + 1e-10) - makeup_Gain_dB

# === CONVERT TO SOUND ===
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

# === APPLY SATURATION ===
if saturation_type > 1
    selectObject: compressed
    
    # Drive amount (1.0 = unity, higher = more saturation)
    drive_amt = 1.0 + drive * 3.0
    
    if saturation_type = 2
        # TUBE - Symmetric soft clipping (tanh)
        # Warm, musical, odd harmonics
        Formula: "tanh(self * drive_amt) / tanh(drive_amt)"
        sat_name$ = "Tube"
        
    elsif saturation_type = 3
        # TAPE - Asymmetric soft clipping
        # Rich, adds even harmonics, slight compression
        Formula: "if self >= 0 then tanh(self * drive_amt * 1.2) / tanh(drive_amt * 1.2) else tanh(self * drive_amt * 0.9) / tanh(drive_amt * 0.9) fi"
        sat_name$ = "Tape"
        
    elsif saturation_type = 4
        # TRANSISTOR - Harder knee, more aggressive
        Formula: "if abs(self * drive_amt) < 0.5 then self else (if self >= 0 then (3 * self * drive_amt - (self * drive_amt)^3) / (2 * drive_amt) else (3 * self * drive_amt + (self * drive_amt)^3) / (2 * drive_amt) fi) fi"
        sat_name$ = "Transistor"
        
    elsif saturation_type = 5
        # FET - Very fast, punchy, slight asymmetry
        asym = 0.1
        Formula: "tanh((self + self * asym * abs(self)) * drive_amt) / tanh(drive_amt * (1 + asym))"
        sat_name$ = "FET"
    endif
    
    # Mix saturated with clean (harmonics_mix controls amount)
    if harmonics_mix < 1
        selectObject: sound
        clean_compressed = Copy: "clean_comp"
        Formula: "self * Sound_GainCurve(x)"
        
        selectObject: compressed
        Formula: "self * harmonics_mix + Sound_clean_comp(x) * (1 - harmonics_mix)"
        
        removeObject: clean_compressed
    endif
    
    appendInfoLine: "Saturation applied: ", sat_name$
endif

# === DRY/WET MIX ===
if dry_wet_mix < 1
    selectObject: compressed
    sound_str$ = string$(sound)
    Formula: "self * dry_wet_mix + object(" + sound_str$ + ", x) * (1 - dry_wet_mix)"
    appendInfoLine: "Dry/Wet: ", fixed$(dry_wet_mix * 100, 0), "% wet"
endif

# === FINAL SCALING ===
selectObject: compressed
Scale peak: scale_peak
Rename: original_name$ + suf$

# === OUTPUT MEASUREMENTS ===
out_peak = Get maximum: 0, 0, "Sinc70"
out_peak_dB = 20 * log10(abs(out_peak) + 1e-10)
out_rms = Get root-mean-square: 0, 0
out_rms_dB = 20 * log10(out_rms + 1e-10)

# === THD ESTIMATION ===
if saturation_type > 1
    if saturation_type = 2
        thd_estimate = drive * 3.0
    elsif saturation_type = 3
        thd_estimate = drive * 5.0
    elsif saturation_type = 4
        thd_estimate = drive * 7.0
    elsif saturation_type = 5
        thd_estimate = drive * 4.0
    endif
    thd_estimate = thd_estimate * harmonics_mix
else
    thd_estimate = 0
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
    appendInfoLine: "Max Gain Reduction: ", fixed$(gr_min_dB, 1), " dB"
    appendInfoLine: ""
    appendInfoLine: "Crest Factor:"
    appendInfoLine: "  Input:  ", fixed$(in_peak_dB - in_rms_dB, 1), " dB"
    appendInfoLine: "  Output: ", fixed$(out_peak_dB - out_rms_dB, 1), " dB"
    appendInfoLine: ""
    if saturation_type > 1
        appendInfoLine: "Estimated THD: ~", fixed$(thd_estimate, 1), "%"
    endif
endif

# === VISUALIZATION ===
if draw_result
    Erase all
    Font size: 12
    
    # === TOP: Saturation Transfer Curve ===
    Select outer viewport: 0, 8, 0, 2.8
    Axes: -1.5, 1.5, -1.5, 1.5
    
    # Draw grid
    Colour: "Silver"
    Draw line: -1.5, 0, 1.5, 0
    Draw line: 0, -1.5, 0, 1.5
    Draw line: -1, -1.5, -1, 1.5
    Draw line: 1, -1.5, 1, 1.5
    Draw line: -1.5, -1, 1.5, -1
    Draw line: -1.5, 1, 1.5, 1
    
    # Draw unity line
    Colour: "{0.6,0.6,0.6}"
    Dashed line
    Draw line: -1.5, -1.5, 1.5, 1.5
    Solid line
    
    # Draw saturation curve
    if saturation_type > 1
        Colour: "{0.8,0.2,0.2}"
    else
        Colour: "{0.3,0.3,0.8}"
    endif
    Line width: 3
    
    drive_amt = 1.0 + drive * 3.0
    
    in_val = -1.5
    while in_val <= 1.5
        if saturation_type = 1
            # Clean - unity
            out_val = in_val
        elsif saturation_type = 2
            # Tube - tanh
            out_val = tanh(in_val * drive_amt) / tanh(drive_amt)
        elsif saturation_type = 3
            # Tape - asymmetric
            if in_val >= 0
                out_val = tanh(in_val * drive_amt * 1.2) / tanh(drive_amt * 1.2)
            else
                out_val = tanh(in_val * drive_amt * 0.9) / tanh(drive_amt * 0.9)
            endif
        elsif saturation_type = 4
            # Transistor
            if abs(in_val * drive_amt) < 0.5
                out_val = in_val
            else
                if in_val >= 0
                    out_val = (3 * in_val * drive_amt - (in_val * drive_amt)^3) / (2 * drive_amt)
                else
                    out_val = (3 * in_val * drive_amt + (in_val * drive_amt)^3) / (2 * drive_amt)
                endif
            endif
        elsif saturation_type = 5
            # FET
            asym = 0.1
            out_val = tanh((in_val + in_val * asym * abs(in_val)) * drive_amt) / tanh(drive_amt * (1 + asym))
        endif
        
        # Clamp output for display
        out_val = max(-1.5, min(1.5, out_val))
        
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
    
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    Marks left every: 1, 0.5, "yes", "yes", "no"
    Text bottom: "yes", "Input Amplitude"
    Text left: "yes", "Output Amplitude"
    
    Font size: 14
    if saturation_type = 1
        Text top: "yes", "##Saturation Curve## — Clean (No Saturation)"
    else
        Text top: "yes", "##Saturation Curve## — " + saturation_type$ + " | Drive: " + fixed$(drive * 100, 0) + "%"
    endif
    Font size: 12
    
    # === MIDDLE: Compression Transfer Curve ===
    Select outer viewport: 0, 8, 2.9, 5.2
    Axes: -60, 0, -60, 0
    
    # Draw grid
    Colour: "Silver"
    grid_line = -50
    while grid_line <= -10
        Draw line: grid_line, -60, grid_line, 0
        Draw line: -60, grid_line, 0, grid_line
        grid_line = grid_line + 10
    endwhile
    
    # Unity line
    Colour: "{0.6,0.6,0.6}"
    Dashed line
    Draw line: -60, -60, 0, 0
    Solid line
    
    # Threshold
    Colour: "{0.3,0.3,0.8}"
    Dashed line
    Draw line: t, -60, t, 0
    Solid line
    
    # Knee region
    if k > 0
        Paint rectangle: "{0.9,0.9,1}", t - half_k, t + half_k, -60, 0
    endif
    
    # Compression curve
    Colour: "{0.2,0.6,0.2}"
    Line width: 3
    
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
                knee_factor = (in_lev - t + half_k) / k
                knee_factor = knee_factor * knee_factor / 2
                out_lev = in_lev - knee_factor * (in_lev - t + half_k) * (1 - 1/r)
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
    
    Marks bottom every: 1, 10, "yes", "yes", "no"
    Marks left every: 1, 10, "yes", "yes", "no"
    Text bottom: "yes", "Input (dB)"
    Text left: "yes", "Output (dB)"
    
    Font size: 14
    Text top: "yes", "##Compression## — Thresh: " + fixed$(t, 0) + "dB | Ratio: " + fixed$(ratio, 1) + ":1 | Knee: " + fixed$(knee_dB, 0) + "dB"
    Font size: 12
    
    # === BOTTOM: Gain Reduction Over Time ===
    Select outer viewport: 0, 8, 5.3, 7.3
    
    selectObject: gain_sound
    gr_display = Copy: "gr_display"
    Formula: "20 * log10(self + 1e-10) - makeup_Gain_dB"
    
    gr_disp_min = Get minimum: 0, 0, "Sinc70"
    gr_disp_min = min(-6, floor(gr_disp_min / 3) * 3 - 3)
    
    Axes: 0, dur, gr_disp_min, 3
    
    Paint rectangle: "{1,0.95,0.95}", 0, dur, gr_disp_min, 0
    
    Colour: "{0.5,0.5,0.5}"
    Draw line: 0, 0, dur, 0
    
    # Fill GR area
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
    
    Colour: "{0.6,0,0}"
    Line width: 2
    selectObject: gr_display
    Draw: 0, dur, gr_disp_min, 3, "no", "Curve"
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    Marks left every: 1, 3, "yes", "yes", "no"
    One mark left: 0, "no", "yes", "yes", "0"
    
    Text bottom: "yes", "Time (seconds)"
    Text left: "yes", "GR (dB)"
    
    Font size: 14
    Text top: "yes", "##Gain Reduction## — Max: " + fixed$(gr_min_dB, 1) + " dB | Atk: " + fixed$(attack_ms, 0) + "ms | Rel: " + fixed$(release_ms, 0) + "ms"
    Font size: 12
    
    removeObject: gr_display
    
    Select outer viewport: 0, 8, 0, 7.3
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