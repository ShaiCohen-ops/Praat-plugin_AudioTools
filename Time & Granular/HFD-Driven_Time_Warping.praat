# ============================================================
# Praat AudioTools - HFD_Driven_Time_Warping.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.2 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   HFD-Driven Time Warping. Computes the Higuchi Fractal Dimension
#   (signal complexity) per frame, maps it to a per-frame time-stretch
#   factor (with curve shaping, voicing gating and slew limiting), and
#   resynthesizes via a DurationTier on a Manipulation object. Complex
#   passages stretch; simple ones contract (or vice-versa via curves).
#
# Changelog v2.2:
#   - Version unified to 2.2 (header / form title / info log were
#     previously inconsistent at 0.2 vs 2.1).
#   - PERFORMANCE: the HFD analysis read every sample via per-cell
#     "Get value in cell" inside the nested k/m/j loops -- each cell read
#     ~k_max+1 times. The downsampled matrix is now read once into a
#     Praat vector (samples#) and the procedure indexes that, cutting the
#     per-cell queries by roughly an order of magnitude. Output is
#     behavior-identical.
#   - VISUALIZATION: rebuilt to the AudioTools suite 8x8 standard
#     (title bar + subtitle, original/warped waveform pair, HFD curve,
#     stretch-factor curve, voicing track, light-grey summary).
#   - FORM: dropped decorative comment rows; added colons to the Preset
#     and Material_type menus. (The advanced-settings beginPause block is
#     a deliberate two-stage UX and is unchanged.)
#
# ============================================================

# --- 1. COMPACT STARTUP FORM ---
form HFD Time Warping v2.2
    optionmenu Preset: 1
        option Custom
        option Subtle
        option Moderate
        option Dramatic
        option Extreme
        option Glitch
    
    optionmenu Material_type: 1
        option Speech
        option Music_Field_Recording
    
    boolean Draw_visualization 1
    boolean Play_result 1
    
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

writeInfoLine: "=== HFD Time Warping v2.2 ==="

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

# Read the matrix into a vector once. windowedHFD then indexes samples#
# instead of querying the Matrix per cell (~order-of-magnitude fewer
# Get value in cell calls; behavior-identical).
samples# = zero#(matrix_cols)
for c from 1 to matrix_cols
    samples#[c] = Get value in cell: 1, c
endfor

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

    if material_type = 1
        matName$ = "Speech"
    else
        matName$ = "Music/Field"
    endif
    if mapping_curve = 1
        curveName$ = "Linear"
    elsif mapping_curve = 2
        curveName$ = "Emph. extremes"
    elsif mapping_curve = 3
        curveName$ = "Emph. changes"
    else
        curveName$ = "Quantized"
    endif

    Erase all
    Select outer viewport: 0, 8, 0, 8
    Black
    Plain line

    # ---- TITLE BAR ----
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##HFD-DRIVEN TIME WARPING##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... original_name$
        ... + "  |  " + presetName$
        ... + "  |  stretch " + fixed$(min_stretch_factor, 2) + "-" + fixed$(max_stretch_factor, 2) + "x"
        ... + "  |  " + fixed$(total_duration, 2) + " s -> " + fixed$(warped_duration, 2) + " s"

    # ---- ORIGINAL WAVEFORM (left) ----
    Select outer viewport: 0, 4.2, 0.75, 2.10
    Select inner viewport: 0.55, 4.00, 0.95, 1.98
    selectObject: original_sound
    Colour: "{0.55, 0.55, 0.60}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Original"
    Font size: 6
    Text left: "yes", "Amp"

    # ---- WARPED WAVEFORM (right) ----
    Select outer viewport: 4.2, 8, 0.75, 2.10
    Select inner viewport: 4.55, 7.75, 0.95, 1.98
    selectObject: warped
    Colour: "{0.55, 0.45, 0.70}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Warped"
    Font size: 6
    Text left: "yes", "Amp"

    # ---- HFD CURVE (full width) ----
    Select outer viewport: 0, 8, 2.20, 3.30
    Select inner viewport: 0.55, 7.75, 2.38, 3.18
    Axes: 0, total_duration, minHFD - hfdMargin, maxHFD + hfdMargin
    Paint rectangle: "{0.96, 0.96, 0.97}", 0, total_duration, minHFD - hfdMargin, maxHFD + hfdMargin
    Colour: "{0.80, 0.80, 0.90}"
    for i from 2 to num_frames
        Draw line: t_points#[i-1], hfd_values#[i-1], t_points#[i], hfd_values#[i]
    endfor
    Colour: "{0.50, 0.50, 0.70}"
    Line width: 1.5
    for i from 2 to num_frames
        Draw line: t_points#[i-1], smoothed_hfd#[i-1], t_points#[i], smoothed_hfd#[i]
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Higuchi Fractal Dimension  (light = raw, dark = smoothed)"
    Font size: 6
    Text left: "yes", "HFD"

    # ---- STRETCH FACTORS (full width) ----
    Select outer viewport: 0, 8, 3.40, 4.50
    Select inner viewport: 0.55, 7.75, 3.58, 4.38
    stretchMargin = (max_stretch_factor - min_stretch_factor) * 0.1
    Axes: 0, total_duration, min_stretch_factor - stretchMargin, max_stretch_factor + stretchMargin
    Paint rectangle: "{0.96, 0.96, 0.97}", 0, total_duration, min_stretch_factor - stretchMargin, max_stretch_factor + stretchMargin
    Colour: "{0.80, 0.80, 0.80}"
    Dotted line
    Draw line: 0, 1.0, total_duration, 1.0
    Solid line
    Colour: "{0.90, 0.80, 0.80}"
    for i from 2 to num_frames
        Draw line: t_points#[i-1], raw_stretch#[i-1], t_points#[i], raw_stretch#[i]
    endfor
    Colour: "{0.70, 0.50, 0.50}"
    Line width: 1.5
    for i from 2 to num_frames
        Draw line: t_points#[i-1], stretch_factors#[i-1], t_points#[i], stretch_factors#[i]
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Stretch factor  (dotted = unity; light = raw, dark = final/slewed)"
    Font size: 6
    Text left: "yes", "x"
    Text bottom: "yes", "Time (s)"

    # ---- VOICING TRACK (full width, if used) ----
    if use_voicing_gate
        Select outer viewport: 0, 8, 4.60, 5.40
        Select inner viewport: 0.55, 7.75, 4.74, 5.28
        Axes: 0, total_duration, 0, 1.1
        Paint rectangle: "{0.96, 0.96, 0.97}", 0, total_duration, 0, 1.1
        Colour: "{0.50, 0.70, 0.50}"
        Line width: 1.5
        for i from 2 to num_frames
            Draw line: t_points#[i-1], smoothed_voicing#[i-1], t_points#[i], smoothed_voicing#[i]
        endfor
        Line width: 1
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text top: "no", "Voicing (HNR)  -  gates the warp toward unity where unvoiced"
        Font size: 6
        Text left: "yes", "0-1"
        Text bottom: "yes", "Time (s)"
        sumY1 = 5.50
        sumY2 = 6.20
    else
        sumY1 = 4.60
        sumY2 = 5.30
    endif

    # ---- SUMMARY BAR ----
    Select outer viewport: 0, 8, sumY1, sumY2
    Select inner viewport: 0.55, 7.75, sumY1 + 0.07, sumY2 - 0.06
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + original_name$
        ... + "  |  material: " + matName$
        ... + "  |  stretch " + fixed$(min_stretch_factor, 2) + "-" + fixed$(max_stretch_factor, 2) + "x"
        ... + "  |  HFD " + fixed$(minHFD, 2) + "-" + fixed$(maxHFD, 2)
        ... + "  |  " + fixed$(total_duration, 2) + " s -> " + fixed$(warped_duration, 2) + " s"
    Text: 0.02, "left", 0.28, "half",
        ... "K=" + string$(k_max)
        ... + "  |  smooth=" + string$(smoothing_window_size)
        ... + "  |  curve: " + curveName$
        ... + "  |  slew=" + fixed$(max_stretch_change_per_sec, 1) + "/s"
        ... + "  |  voicing=" + fixed$(voicing_influence * 100, 0) + "%"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
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
        
        # Get samples with mean removal (read from the global samples# vector)
        .mean = 0
        for .i from 1 to .n
            .col = .start + .i - 1
            .val = samples#[.col]
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
                        
                        .v1 = samples#[.c1]
                        .v2 = samples#[.c2]
                        
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