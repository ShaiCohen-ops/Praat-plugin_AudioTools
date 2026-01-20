# ============================================================
# Praat AudioTools - HFD_Driven_Time_Warping.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   HFD_Driven_Time_Warping
#
# ============================================================

# --- 1. COMPACT STARTUP FORM ---
form HFD Time Warping v2.1
    comment PRESETS:
    optionmenu Preset 1
        option Custom
        option Subtle
        option Moderate
        option Dramatic
        option Extreme
        option Glitch
    
    comment SETTINGS:
    optionmenu Material_type 1
        option Speech
        option Music_Field_Recording
    
    boolean Draw_visualization 1
    boolean Play_result 1
    
    comment ADVANCED:
    boolean Show_advanced_settings 0
endform

# --- 2. DEFINE DEFAULT PARAMETERS ---
# (These are used if you don't open Advanced Settings)
frame_length_s = 0.05
hop_size_s = 0.05
k_max = 5
smoothing_window_size = 5
min_stretch_factor = 0.5
max_stretch_factor = 2.0
use_percentile_mapping = 1
mapping_curve = 1
use_voicing_gate = 1
voicing_influence = 0.7
voicing_smooth_window = 3
final_stretch_smooth = 3
max_stretch_change_per_sec = 5.0
minimum_pitch_Hz = 75
maximum_pitch_Hz = 600
downsample_factor = 6
skip_windowing = 0

# --- 3. SHOW ADVANCED SETTINGS (If Checked) ---
if show_advanced_settings
    beginPause: "Advanced HFD Parameters"
        comment: "Analysis Parameters:"
        positive: "Frame length s", frame_length_s
        positive: "Hop size s", hop_size_s
        integer: "K max", k_max
        
        comment: "Smoothing and Mapping:"
        integer: "Smoothing window size", smoothing_window_size
        real: "Min stretch factor", min_stretch_factor
        real: "Max stretch factor", max_stretch_factor
        boolean: "Use percentile mapping", use_percentile_mapping
        optionmenu: "Mapping curve", mapping_curve
            option: "Linear"
            option: "Emphasize extremes"
            option: "Emphasize changes"
            option: "Quantized steps"
        
        comment: "Voicing Control:"
        boolean: "Use voicing gate", use_voicing_gate
        real: "Voicing influence", voicing_influence
        integer: "Voicing smooth window", voicing_smooth_window
        
        comment: "Control Smoothing:"
        integer: "Final stretch smooth", final_stretch_smooth
        real: "Max stretch change per sec", max_stretch_change_per_sec
        
        comment: "Pitch settings:"
        positive: "Minimum pitch Hz", minimum_pitch_Hz
        positive: "Maximum pitch Hz", maximum_pitch_Hz
        
        comment: "Speed Optimization:"
        integer: "Downsample factor", downsample_factor
        boolean: "Skip windowing", skip_windowing
    clicked = endPause: "Cancel", "OK", 2, 1
    if clicked = 1
        exitScript: "Cancelled."
    endif
endif

# ==============================================================================
# APPLY PRESET
# ==============================================================================

if preset = 2
    # Subtle
    frame_length_s = 0.06
    hop_size_s = 0.06
    k_max = 4
    smoothing_window_size = 7
    min_stretch_factor = 0.85
    max_stretch_factor = 1.15
    use_percentile_mapping = 1
    mapping_curve = 2
    use_voicing_gate = 1
    voicing_influence = 0.8
    voicing_smooth_window = 5
    final_stretch_smooth = 5
    max_stretch_change_per_sec = 3.0
    skip_windowing = 0
    presetName$ = "Subtle"
elsif preset = 3
    # Moderate
    frame_length_s = 0.05
    hop_size_s = 0.05
    k_max = 5
    smoothing_window_size = 5
    min_stretch_factor = 0.7
    max_stretch_factor = 1.5
    use_percentile_mapping = 1
    mapping_curve = 1
    use_voicing_gate = 1
    voicing_influence = 0.7
    voicing_smooth_window = 4
    final_stretch_smooth = 4
    max_stretch_change_per_sec = 4.0
    skip_windowing = 0
    presetName$ = "Moderate"
elsif preset = 4
    # Dramatic
    frame_length_s = 0.05
    hop_size_s = 0.05
    k_max = 5
    smoothing_window_size = 4
    min_stretch_factor = 0.5
    max_stretch_factor = 2.0
    use_percentile_mapping = 1
    mapping_curve = 3
    use_voicing_gate = 1
    voicing_influence = 0.6
    voicing_smooth_window = 3
    final_stretch_smooth = 3
    max_stretch_change_per_sec = 6.0
    skip_windowing = 1
    presetName$ = "Dramatic"
elsif preset = 5
    # Extreme
    frame_length_s = 0.04
    hop_size_s = 0.04
    k_max = 5
    smoothing_window_size = 3
    min_stretch_factor = 0.4
    max_stretch_factor = 2.5
    use_percentile_mapping = 1
    mapping_curve = 3
    use_voicing_gate = 1
    voicing_influence = 0.5
    voicing_smooth_window = 2
    final_stretch_smooth = 2
    max_stretch_change_per_sec = 8.0
    skip_windowing = 1
    presetName$ = "Extreme"
elsif preset = 6
    # Glitch
    frame_length_s = 0.03
    hop_size_s = 0.03
    k_max = 4
    smoothing_window_size = 2
    min_stretch_factor = 0.4
    max_stretch_factor = 2.5
    use_percentile_mapping = 0
    mapping_curve = 4
    use_voicing_gate = 0
    voicing_influence = 0.0
    voicing_smooth_window = 1
    final_stretch_smooth = 1
    max_stretch_change_per_sec = 20.0
    skip_windowing = 1
    presetName$ = "Glitch"
else
    presetName$ = "Custom"
endif

# ==============================================================================
# 1. SETUP
# ==============================================================================

writeInfoLine: "=== HFD Time Warping v2.1 ==="

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original_sound = selected("Sound")
original_name$ = selected$("Sound")

appendInfoLine: "Source: ", original_name$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""

# Mono conversion
selectObject: original_sound
n_channels = Get number of channels
if n_channels > 1
    mono_sound = Convert to mono
    working_sound = mono_sound
else
    working_sound = original_sound
endif

selectObject: working_sound
total_duration = Get total duration
start_time = Get start time
sample_rate = Get sampling frequency

appendInfoLine: "Duration: ", fixed$(total_duration, 2), " s"
appendInfoLine: "Sample rate: ", sample_rate, " Hz"
appendInfoLine: ""

# Downsampling for analysis
appendInfoLine: "Preparing analysis..."
selectObject: working_sound
target_rate = sample_rate / downsample_factor
Resample: target_rate, 50
analysis_sound = selected("Sound")

# High-pass filter (material-dependent)
if material_type = 1
    Filter (pass Hann band): 100, 0, 100
elsif material_type = 2
    Filter (pass Hann band): 30, 0, 100
endif
filtered_sound = selected("Sound")
removeObject: analysis_sound
analysis_sound = filtered_sound

# Convert to matrix once
selectObject: analysis_sound
Down to Matrix
full_matrix = selected("Matrix")
matrix_cols = Get number of columns

# Calculate frames
num_frames = floor((total_duration - frame_length_s) / hop_size_s) + 1

if num_frames < 3
    removeObject: full_matrix, analysis_sound
    if n_channels > 1
        removeObject: working_sound
    endif
    exitScript: "ERROR: Audio too short for analysis."
endif

appendInfoLine: "Frames: ", num_frames, " | K_max: ", k_max
appendInfoLine: ""

t_points# = zero#(num_frames)
hfd_values# = zero#(num_frames)
voicing# = zero#(num_frames)

# ==============================================================================
# 2. VOICING ANALYSIS (Continuous measure)
# ==============================================================================

if use_voicing_gate
    appendInfoLine: "Computing voicing..."
    selectObject: analysis_sound
    
    # Use Harmonicity (HNR) as continuous voicing measure
    To Harmonicity (cc): 0.01, minimum_pitch_Hz, 0.1, 1.0
    harmonicity_obj = selected("Harmonicity")
    
    # Extract voicing strength per frame
    for i from 1 to num_frames
        t_mid = start_time + (i - 1) * hop_size_s + (frame_length_s / 2)
        selectObject: harmonicity_obj
        hnr = Get value at time: t_mid, "Linear"
        
        if hnr = undefined
            voicing#[i] = 0
        else
            # Convert HNR (dB) to 0-1 scale
            # HNR > 10 dB = very voiced, < 0 dB = unvoiced
            voicing#[i] = (hnr + 5) / 20
            if voicing#[i] < 0
                voicing#[i] = 0
            endif
            if voicing#[i] > 1
                voicing#[i] = 1
            endif
        endif
    endfor
    
    # Smooth voicing track to prevent flicker
    smoothed_voicing# = zero#(num_frames)
    half_v = floor(voicing_smooth_window / 2)
    for i from 1 to num_frames
        s = 0
        c = 0
        for j from max(1, i-half_v) to min(num_frames, i+half_v)
            s = s + voicing#[j]
            c = c + 1
        endfor
        smoothed_voicing#[i] = s / c
    endfor
    
    removeObject: harmonicity_obj
endif

# ==============================================================================
# 3. HFD ANALYSIS (with windowing)
# ==============================================================================

appendInfoLine: "Analyzing HFD..."

frame_samples = round(frame_length_s * target_rate)

for i from 1 to num_frames
    t_start = start_time + (i - 1) * hop_size_s
    t_mid = t_start + (frame_length_s / 2)
    
    # Calculate sample indices
    start_col = round((t_start - start_time) * target_rate) + 1
    end_col = start_col + frame_samples - 1
    
    if end_col > matrix_cols
        end_col = matrix_cols
    endif
    if start_col < 1
        start_col = 1
    endif
    
    @windowedHFD: full_matrix, start_col, end_col, k_max, skip_windowing
    
    t_points#[i] = t_mid
    hfd_values#[i] = windowedHFD.result
    
    if i mod 10 = 0 or i = num_frames
        percent = (i / num_frames) * 100
        appendInfoLine: "  ", fixed$(percent, 0), "% (", i, "/", num_frames, ")"
    endif
endfor

removeObject: full_matrix, analysis_sound

# ==============================================================================
# 4. ROBUST SMOOTHING AND MAPPING
# ==============================================================================

appendInfoLine: ""
appendInfoLine: "Smoothing HFD..."

# Smooth HFD
smoothed_hfd# = zero#(num_frames)
half_w = floor(smoothing_window_size / 2)

for i from 1 to num_frames
    s = 0
    c = 0
    for j from max(1, i-half_w) to min(num_frames, i+half_w)
        s = s + hfd_values#[j]
        c = c + 1
    endfor
    smoothed_hfd#[i] = s / c
endfor

# Percentile or min-max normalization
appendInfoLine: "Normalizing..."
if use_percentile_mapping
    sorted# = zero#(num_frames)
    for i from 1 to num_frames
        sorted#[i] = smoothed_hfd#[i]
    endfor
    
    for i from 1 to num_frames - 1
        for j from i + 1 to num_frames
            if sorted#[j] < sorted#[i]
                temp = sorted#[i]
                sorted#[i] = sorted#[j]
                sorted#[j] = temp
            endif
        endfor
    endfor
    
    idx_5 = max(1, round(num_frames * 0.05))
    idx_95 = min(num_frames, round(num_frames * 0.95))
    min_h = sorted#[idx_5]
    max_h = sorted#[idx_95]
else
    min_h = smoothed_hfd#[1]
    max_h = smoothed_hfd#[1]
    for i from 2 to num_frames
        if smoothed_hfd#[i] < min_h
            min_h = smoothed_hfd#[i]
        endif
        if smoothed_hfd#[i] > max_h
            max_h = smoothed_hfd#[i]
        endif
    endfor
endif

range_h = max_h - min_h
if range_h = 0
    range_h = 1
endif

# Map to stretch factors with curves and voicing
appendInfoLine: "Mapping to stretch factors..."
raw_stretch# = zero#(num_frames)

for i from 1 to num_frames
    # Normalize
    norm = (smoothed_hfd#[i] - min_h) / range_h
    if norm < 0
        norm = 0
    endif
    if norm > 1
        norm = 1
    endif
    
    # Apply mapping curve
    if mapping_curve = 2
        norm = norm * norm
    elsif mapping_curve = 3
        norm = sqrt(norm)
    elsif mapping_curve = 4
        if norm < 0.25
            norm = 0.125
        elsif norm < 0.5
            norm = 0.375
        elsif norm < 0.75
            norm = 0.625
        else
            norm = 0.875
        endif
    endif
    
    # Calculate stretch factor
    stretch = min_stretch_factor + norm * (max_stretch_factor - min_stretch_factor)
    
    # Apply voicing influence: effectiveStretch = 1 + voicedness * (stretch - 1)
    if use_voicing_gate
        v = smoothed_voicing#[i]
        deviation = stretch - 1.0
        effective_stretch = 1.0 + v * deviation
        # Blend based on voicing_influence
        raw_stretch#[i] = (1 - voicing_influence) * stretch + voicing_influence * effective_stretch
    else
        raw_stretch#[i] = stretch
    endif
endfor

# Final smoothing on stretch factors
appendInfoLine: "Final smoothing..."
stretch_factors# = zero#(num_frames)
half_f = floor(final_stretch_smooth / 2)

for i from 1 to num_frames
    s = 0
    c = 0
    for j from max(1, i-half_f) to min(num_frames, i+half_f)
        s = s + raw_stretch#[j]
        c = c + 1
    endfor
    stretch_factors#[i] = s / c
endfor

# Slew rate limiting (prevent zipper artifacts)
appendInfoLine: "Applying slew limiting..."
max_change_per_frame = max_stretch_change_per_sec * hop_size_s

for i from 2 to num_frames
    change = stretch_factors#[i] - stretch_factors#[i-1]
    if abs(change) > max_change_per_frame
        if change > 0
            stretch_factors#[i] = stretch_factors#[i-1] + max_change_per_frame
        else
            stretch_factors#[i] = stretch_factors#[i-1] - max_change_per_frame
        endif
    endif
endfor

# ==============================================================================
# 5. TIME WARPING
# ==============================================================================

appendInfoLine: ""
appendInfoLine: "Building duration tier..."

selectObject: working_sound
To Manipulation: 0.01, minimum_pitch_Hz, maximum_pitch_Hz
manip = selected("Manipulation")

Extract duration tier
dur_tier = selected("DurationTier")

Remove points between: 0, total_duration

# Anchor start
Add point: start_time, stretch_factors#[1]

# Add all points
for i from 1 to num_frames
    Add point: t_points#[i], stretch_factors#[i]
endfor

# Anchor end
Add point: start_time + total_duration, stretch_factors#[num_frames]

appendInfoLine: "Resynthesizing audio..."

selectObject: dur_tier
plusObject: manip
Replace duration tier

selectObject: manip
Get resynthesis (overlap-add)
warped = selected("Sound")
Rename: original_name$ + "_HFDwarp_" + presetName$

# Scale output
selectObject: warped
Scale peak: 0.95

# Get warped duration for stats
selectObject: warped
warped_duration = Get total duration

# ==============================================================================
# 6. VISUALIZATION
# ==============================================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "HFD Time Warping: " + original_name$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.6, 0.7, 1.3
    selectObject: original_sound
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Warped waveform
    Select outer viewport: 0, 8, 1.5, 2.3
    Select inner viewport: 0.6, 7.6, 1.6, 2.2
    selectObject: warped
    Colour: "{0.6, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Warped"
    Text bottom: "yes", "Time (s)"
    
    # HFD curve
    Select outer viewport: 0, 8, 2.5, 3.5
    Select inner viewport: 0.6, 7.6, 2.6, 3.4
    
    # Find HFD range for display
    minHFD = smoothed_hfd#[1]
    maxHFD = smoothed_hfd#[1]
    for i from 2 to num_frames
        if smoothed_hfd#[i] < minHFD
            minHFD = smoothed_hfd#[i]
        endif
        if smoothed_hfd#[i] > maxHFD
            maxHFD = smoothed_hfd#[i]
        endif
    endfor
    hfdMargin = (maxHFD - minHFD) * 0.1
    if hfdMargin < 0.05
        hfdMargin = 0.05
    endif
    
    Axes: 0, total_duration, minHFD - hfdMargin, maxHFD + hfdMargin
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, total_duration, minHFD - hfdMargin, maxHFD + hfdMargin
    
    # Draw raw HFD (light)
    Colour: "{0.8, 0.8, 0.9}"
    for i from 2 to num_frames
        Draw line: t_points#[i-1], hfd_values#[i-1], t_points#[i], hfd_values#[i]
    endfor
    
    # Draw smoothed HFD (dark)
    Colour: "{0.5, 0.5, 0.7}"
    Line width: 1.5
    for i from 2 to num_frames
        Draw line: t_points#[i-1], smoothed_hfd#[i-1], t_points#[i], smoothed_hfd#[i]
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "HFD"
    
    # Stretch factors
    Select outer viewport: 0, 8, 3.7, 4.7
    Select inner viewport: 0.6, 7.6, 3.8, 4.6
    
    stretchMargin = (max_stretch_factor - min_stretch_factor) * 0.1
    Axes: 0, total_duration, min_stretch_factor - stretchMargin, max_stretch_factor + stretchMargin
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, total_duration, min_stretch_factor - stretchMargin, max_stretch_factor + stretchMargin
    
    # Unity line
    Colour: "{0.8, 0.8, 0.8}"
    Dotted line
    Draw line: 0, 1.0, total_duration, 1.0
    Solid line
    
    # Draw raw stretch (light)
    Colour: "{0.9, 0.8, 0.8}"
    for i from 2 to num_frames
        Draw line: t_points#[i-1], raw_stretch#[i-1], t_points#[i], raw_stretch#[i]
    endfor
    
    # Draw final stretch (dark)
    Colour: "{0.7, 0.5, 0.5}"
    Line width: 1.5
    for i from 2 to num_frames
        Draw line: t_points#[i-1], stretch_factors#[i-1], t_points#[i], stretch_factors#[i]
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Stretch"
    Text bottom: "yes", "Time (s)"
    
    # Voicing curve (if used)
    if use_voicing_gate
        Select outer viewport: 0, 4, 4.9, 5.6
        Select inner viewport: 0.6, 3.8, 5.0, 5.5
        
        Axes: 0, total_duration, 0, 1.1
        Paint rectangle: "{0.95, 0.95, 0.95}", 0, total_duration, 0, 1.1
        
        Colour: "{0.5, 0.7, 0.5}"
        Line width: 1.5
        for i from 2 to num_frames
            Draw line: t_points#[i-1], smoothed_voicing#[i-1], t_points#[i], smoothed_voicing#[i]
        endfor
        Line width: 1
        
        Colour: "Black"
        Draw inner box
        Font size: 6
        Text left: "yes", "Voicing"
    endif
    
    # Stats box
    Select outer viewport: 4, 8, 4.9, 5.6
    Select inner viewport: 4.4, 7.6, 5.0, 5.5
    
    Axes: 0, 4, 0, 3
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 4, 0, 3
    
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 2, "centre", 2.5, "half", "Stretch: " + fixed$(min_stretch_factor, 2) + "x - " + fixed$(max_stretch_factor, 2) + "x"
    Text: 2, "centre", 1.5, "half", "HFD range: " + fixed$(minHFD, 2) + " - " + fixed$(maxHFD, 2)
    Text: 2, "centre", 0.5, "half", "Duration: " + fixed$(total_duration, 2) + "s -> " + fixed$(warped_duration, 2) + "s"
    
    Colour: "Black"
    Draw inner box
    
    # Legend
    Select outer viewport: 0, 8, 5.7, 6.0
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "K=" + string$(k_max) + " | Smooth=" + string$(smoothing_window_size) + " | Slew=" + fixed$(max_stretch_change_per_sec, 1) + "/s | Voicing=" + fixed$(voicing_influence * 100, 0) + "%"
    
    Font size: 10
    Colour: "Black"
endif

# ==============================================================================
# 7. CLEANUP
# ==============================================================================

selectObject: manip, dur_tier
if n_channels > 1
    plusObject: working_sound
endif
Remove

selectObject: warped

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Original: ", fixed$(total_duration, 2), " s"
appendInfoLine: "Warped: ", fixed$(warped_duration, 2), " s"
appendInfoLine: "Stretch range: ", fixed$(min_stretch_factor, 2), " - ", fixed$(max_stretch_factor, 2), "x"
if use_voicing_gate
    appendInfoLine: "Voicing influence: ", fixed$(voicing_influence * 100, 0), "%"
endif
appendInfoLine: ""
appendInfoLine: "Created: ", selected$("Sound")

if play_result
    Play
endif

selectObject: warped

# ==============================================================================
# WINDOWED HFD CALCULATION PROCEDURE
# ==============================================================================
procedure windowedHFD: .mat, .start, .end, .kmax, .skip_win
    selectObject: .mat
    .n = .end - .start + 1
    
    if .n < 20
        .result = 1.5
    else
        # Conditionally generate Hann window
        if .skip_win = 0
            hann# = zero#(.n)
            for .i from 1 to .n
                hann#[.i] = 0.5 * (1 - cos(2 * pi * (.i - 1) / (.n - 1)))
            endfor
        endif
        
        # Get samples with mean removal
        .mean = 0
        for .i from 1 to .n
            .col = .start + .i - 1
            .val = Get value in cell: 1, .col
            if .skip_win = 0
                .mean = .mean + .val * hann#[.i]
            else
                .mean = .mean + .val
            endif
        endfor
        .mean = .mean / .n
        
        .sx = 0
        .sy = 0
        .sxy = 0
        .sxx = 0
        .np = 0
        
        # Loop over k scales
        for .k from 1 to .kmax
            .lk_sum = 0
            .m_count = 0
            
            for .m from 1 to .k
                .diff = 0
                .jmax = floor((.n - .m) / .k)
                
                if .jmax > 1
                    for .j from 1 to .jmax
                        .c1 = .start + .m + (.j - 1) * .k - 1
                        .c2 = .start + .m + .j * .k - 1
                        
                        .v1 = Get value in cell: 1, .c1
                        .v2 = Get value in cell: 1, .c2
                        
                        # Conditionally apply windowing
                        if .skip_win = 0
                            .idx1 = .m + (.j - 1) * .k
                            .idx2 = .m + .j * .k
                            if .idx1 >= 1 and .idx1 <= .n and .idx2 >= 1 and .idx2 <= .n
                                .v1w = (.v1 - .mean) * hann#[.idx1]
                                .v2w = (.v2 - .mean) * hann#[.idx2]
                                .diff = .diff + abs(.v2w - .v1w)
                            endif
                        else
                            .diff = .diff + abs((.v2 - .mean) - (.v1 - .mean))
                        endif
                    endfor
                    
                    .norm = (.n - 1) / (.jmax * .k)
                    .lm = (.diff * .norm) / .k
                    .lk_sum = .lk_sum + .lm
                    .m_count = .m_count + 1
                endif
            endfor
            
            if .m_count > 0
                .lk = .lk_sum / .m_count
                
                if .lk > 0
                    .x = ln(1/.k)
                    .y = ln(.lk)
                    .sx = .sx + .x
                    .sy = .sy + .y
                    .sxy = .sxy + .x * .y
                    .sxx = .sxx + .x * .x
                    .np = .np + 1
                endif
            endif
        endfor
        
        if .np > 2
            .denom = .np * .sxx - .sx * .sx
            if .denom <> 0
                .result = (.np * .sxy - .sx * .sy) / .denom
            else
                .result = 1.5
            endif
        else
            .result = 1.5
        endif
    endif
endproc