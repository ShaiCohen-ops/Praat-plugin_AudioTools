# ============================================================
# Praat AudioTools - HFD_Driven_Time_Warping.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.4 (2026)
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
# Changelog v2.4:
#   - VISUALIZATION-ONLY AudioTools uniformity pass; DSP and HFD mapping are unchanged.
#   - Input/output waveforms now share one amplitude scale. Input stays neutral grey;
#     warped output uses the library blue.
#   - One semantic colour per process layer: amber = HFD complexity, red = stretch
#     command, green = voicing gate, blue = rendered output. Raw/final variants use
#     lighter/darker values within the same semantic hue.
#   - User-facing panel titles now explain the process rather than reading like an
#     analysis figure: complexity, time-warp command, and voicing gate.
#   - Title/subtitle, panel grounds, two-column geometry, fonts and summary colours
#     aligned to the current AudioTools visual standard. Underscores in source names
#     are escaped for Picture text.
#   - The page height now follows the actual content instead of exporting a large
#     blank lower area. The full-page viewport is explicitly reselected at the end,
#     fixing PNG/EPS/clipboard export of only the summary strip.
#
# Changelog v2.3:
#   - PRESERVES MULTICHANNEL OUTPUT. v2.2 analyzed a mono fold and then also
#     resynthesized that mono Sound, so stereo/multichannel input became mono.
#     v2.3 keeps mono only for analysis, then applies the same DurationTier to
#     every original channel independently and recombines them in channel order.
#   - NON-ZERO TIME DOMAINS fixed by zero-basing the analysis/render copies.
#     DurationTier construction and visualization now consistently use 0..T.
#   - SILENCE/FLAT-FRAME handling fixed. Degenerate HFD no longer defaults to
#     1.5 (artificial medium complexity). HFD is clamped to its theoretical
#     1..2 range, and frames below a configurable RMS gate map to unity stretch.
#   - HANN mean correction: windowed mean is divided by sum(window), not N.
#     Constant frames therefore remain constant after mean removal/windowing.
#   - Percentile normalization excludes inactive/silent frames and uses Praat's
#     built-in sort# instead of the O(n^2) nested-loop sort.
#   - DurationTier is created directly rather than extracted/cleared from a
#     Manipulation. The predicted target duration is queried before synthesis.
#   - Mapping-curve labels now describe the actual math: x^2 emphasizes high
#     complexity; sqrt(x) lifts lower-complexity values. No false "changes" label.
#   - Added parameter validation (analysis sizes, pitch bounds, smoothing,
#     downsampling, stretch bounds, voicing influence, slew rate).
#   - Peak scaling is now a safety ceiling only; quiet inputs are not boosted.
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
form HFD Time Warping v2.4
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
silence_gate_dB = -50

# --- 3. SHOW ADVANCED SETTINGS (If Checked) ---
if show_advanced_settings
    beginPause: "Advanced HFD Parameters"
        comment: "Analysis Parameters:"
        positive: "Frame length s", frame_length_s
        positive: "Hop size s", hop_size_s
        integer: "K max", k_max
        real: "Silence gate dB relative RMS", silence_gate_dB
        
        comment: "Smoothing and Mapping:"
        integer: "Smoothing window size", smoothing_window_size
        real: "Min stretch factor", min_stretch_factor
        real: "Max stretch factor", max_stretch_factor
        boolean: "Use percentile mapping", use_percentile_mapping
        optionmenu: "Mapping curve", mapping_curve
            option: "Linear"
            option: "High-complexity emphasis (x^2)"
            option: "Low-complexity lift (sqrt)"
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

writeInfoLine: "=== HFD Time Warping v2.4 ==="

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original_sound = selected("Sound")
original_name$ = selected$("Sound")

# Parameter validation
if frame_length_s <= 0 or hop_size_s <= 0
    exitScript: "Frame length and hop size must be > 0."
endif
if k_max < 3
    exitScript: "K max must be at least 3 for a stable HFD slope."
endif
if smoothing_window_size < 1 or voicing_smooth_window < 1 or final_stretch_smooth < 1
    exitScript: "Smoothing window sizes must be at least 1."
endif
if min_stretch_factor <= 0 or max_stretch_factor <= 0 or max_stretch_factor < min_stretch_factor
    exitScript: "Stretch factors must satisfy 0 < min <= max."
endif
if voicing_influence < 0 or voicing_influence > 1
    exitScript: "Voicing influence must be between 0 and 1."
endif
if max_stretch_change_per_sec < 0
    exitScript: "Max stretch change per second must be >= 0."
endif
if minimum_pitch_Hz <= 0 or maximum_pitch_Hz <= minimum_pitch_Hz
    exitScript: "Maximum pitch must be greater than minimum pitch, both > 0."
endif
if downsample_factor < 1
    exitScript: "Downsample factor must be at least 1."
endif
if silence_gate_dB > 0
    exitScript: "Silence gate dB should be <= 0 (relative to analysis RMS)."
endif

appendInfoLine: "Source: ", original_name$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""

# Mono fold is for analysis only. Always make a disposable, zero-based copy.
selectObject: original_sound
n_channels = Get number of channels
source_start = Get start time
source_end = Get end time
total_duration = Get total duration
sample_rate = Get sampling frequency

if n_channels > 1
    analysis_base = Convert to mono
else
    analysis_base = Copy: "HFD_analysis_base"
endif
selectObject: analysis_base
Shift times to: "start time", 0
start_time = 0

appendInfoLine: "Duration: ", fixed$(total_duration, 2), " s"
appendInfoLine: "Sample rate: ", sample_rate, " Hz | Channels: ", n_channels
appendInfoLine: ""

# Downsampling for analysis
appendInfoLine: "Preparing analysis..."
target_rate = sample_rate / downsample_factor
if target_rate <= 2 * maximum_pitch_Hz
    removeObject: analysis_base
    exitScript: "Downsampled analysis rate is too low for the selected pitch ceiling. Reduce Downsample factor."
endif

selectObject: analysis_base
Resample: target_rate, 50
analysis_sound = selected("Sound")
removeObject: analysis_base

# High-pass filter (material-dependent). In Praat, To frequency = 0 means high-pass.
selectObject: analysis_sound
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
analysis_sum_sq = 0
for c from 1 to matrix_cols
    samples#[c] = Get value in cell: 1, c
    analysis_sum_sq = analysis_sum_sq + samples#[c] ^ 2
endfor
if matrix_cols > 0
    analysis_global_rms = sqrt(analysis_sum_sq / matrix_cols)
else
    analysis_global_rms = 0
endif
silence_threshold_rms = analysis_global_rms * 10 ^ (silence_gate_dB / 20)

# Calculate frames
num_frames = floor((total_duration - frame_length_s) / hop_size_s) + 1

if num_frames < 3
    removeObject: full_matrix, analysis_sound
    if n_channels > 1
        removeObject: working_sound
    endif
    exitScript: "ERROR: Audio too short for analysis."
endif

frame_samples = round(frame_length_s * target_rate)
if frame_samples < 20
    removeObject: full_matrix, analysis_sound
    exitScript: "Analysis frame has fewer than 20 samples after downsampling."
endif
if frame_samples < 3 * k_max
    removeObject: full_matrix, analysis_sound
    exitScript: "K max is too large for the downsampled frame size."
endif

appendInfoLine: "Frames: ", num_frames, " | K_max: ", k_max
appendInfoLine: "Analysis RMS gate: ", fixed$(silence_gate_dB, 1), " dB relative"
appendInfoLine: ""

t_points# = zero#(num_frames)
hfd_values# = zero#(num_frames)
frame_rms# = zero#(num_frames)
active_frame# = zero#(num_frames)
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

active_count = 0
for i from 1 to num_frames
    t_start = (i - 1) * hop_size_s
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
    frame_rms#[i] = windowedHFD.rms
    if analysis_global_rms > 0 and frame_rms#[i] >= silence_threshold_rms
        active_frame#[i] = 1
        active_count = active_count + 1
    else
        active_frame#[i] = 0
    endif
    
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
        if active_frame#[j]
            s = s + hfd_values#[j]
            c = c + 1
        endif
    endfor
    if c > 0
        smoothed_hfd#[i] = s / c
    else
        smoothed_hfd#[i] = 1.0
    endif
endfor

# Percentile or min-max normalization, ACTIVE frames only.
appendInfoLine: "Normalizing..."
hfd_mapping_available = 0
if active_count >= 2
    active_hfd# = zero#(active_count)
    ai = 0
    for i from 1 to num_frames
        if active_frame#[i]
            ai = ai + 1
            active_hfd#[ai] = smoothed_hfd#[i]
        endif
    endfor
    
    if use_percentile_mapping
        sorted# = sort#(active_hfd#)
        idx_5 = max(1, round(active_count * 0.05))
        idx_95 = min(active_count, round(active_count * 0.95))
        min_h = sorted#[idx_5]
        max_h = sorted#[idx_95]
    else
        min_h = active_hfd#[1]
        max_h = active_hfd#[1]
        for i from 2 to active_count
            if active_hfd#[i] < min_h
                min_h = active_hfd#[i]
            endif
            if active_hfd#[i] > max_h
                max_h = active_hfd#[i]
            endif
        endfor
    endif
    
    range_h = max_h - min_h
    if range_h > 0.000001
        hfd_mapping_available = 1
    else
        range_h = 1
    endif
else
    min_h = 1
    max_h = 2
    range_h = 1
endif

appendInfoLine: "Active HFD frames: ", active_count, "/", num_frames
if not hfd_mapping_available
    appendInfoLine: "Note: insufficient HFD variation; warp defaults toward unity."
endif

# Map to stretch factors with curves and voicing
appendInfoLine: "Mapping to stretch factors..."
raw_stretch# = zero#(num_frames)

for i from 1 to num_frames
    if not active_frame#[i] or not hfd_mapping_available
        raw_stretch#[i] = 1.0
    else
        # Normalize HFD into 0..1.
        norm = (smoothed_hfd#[i] - min_h) / range_h
        if norm < 0
            norm = 0
        endif
        if norm > 1
            norm = 1
        endif
        
        # Curve 2 emphasizes only the high-complexity end; curve 3 lifts
        # lower-complexity values. These are value mappings, not derivatives.
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
        
        stretch = min_stretch_factor + norm * (max_stretch_factor - min_stretch_factor)
        
        if use_voicing_gate
            v = smoothed_voicing#[i]
            effective_stretch = 1.0 + v * (stretch - 1.0)
            raw_stretch#[i] = (1 - voicing_influence) * stretch + voicing_influence * effective_stretch
        else
            raw_stretch#[i] = stretch
        endif
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

# Build a clean zero-based tier directly. DurationTier interpolates linearly
# between these points, which is appropriate for a continuous control curve.
Create DurationTier: "HFD_duration", 0, total_duration
dur_tier = selected("DurationTier")

selectObject: dur_tier
Add point: 0, stretch_factors#[1]
for i from 1 to num_frames
    Add point: t_points#[i], stretch_factors#[i]
endfor
Add point: total_duration, stretch_factors#[num_frames]

predicted_duration = Get target duration: 0, total_duration
appendInfoLine: "Predicted target duration: ", fixed$(predicted_duration, 4), " s"
appendInfoLine: "Resynthesizing ", n_channels, " channel(s)..."

# Apply the same temporal map independently to every original channel.
for ch from 1 to n_channels
    selectObject: original_sound
    if n_channels = 1
        channel_source = Copy: "HFD_ch1"
    else
        Extract one channel: ch
        channel_source = selected("Sound")
    endif
    selectObject: channel_source
    Shift times to: "start time", 0
    To Manipulation: 0.01, minimum_pitch_Hz, maximum_pitch_Hz
    channel_manip = selected("Manipulation")
    
    selectObject: channel_manip
    plusObject: dur_tier
    Replace duration tier
    
    selectObject: channel_manip
    Get resynthesis (overlap-add)
    warped_channel[ch] = selected("Sound")
    Rename: "HFDwarp_ch" + string$(ch)
    
    removeObject: channel_manip, channel_source
endfor

if n_channels = 1
    warped = warped_channel[1]
else
    # Channel Sounds were created in channel order; Combine to stereo uses
    # object-list order, preserving channel 1..N.
    selectObject: warped_channel[1]
    for ch from 2 to n_channels
        plusObject: warped_channel[ch]
    endfor
    Combine to stereo
    warped = selected("Sound")
    for ch from 1 to n_channels
        removeObject: warped_channel[ch]
    endfor
endif

selectObject: warped
Rename: original_name$ + "_HFDwarp_" + presetName$

# Safety ceiling only; do not boost quiet material.
warped_peak = Get absolute extremum: 0, 0, "Sinc70"
if warped_peak > 0.95
    Formula: "self * 0.95 / warped_peak"
endif

warped_duration = Get total duration
duration_error_ms = (warped_duration - predicted_duration) * 1000

# ==============================================================================
# 6. VISUALIZATION
# ============================================================================== 

if draw_visualization
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
    if material_type = 1
        matName$ = "Speech"
    else
        matName$ = "Music/Field"
    endif
    if mapping_curve = 1
        curveName$ = "Linear"
    elsif mapping_curve = 2
        curveName$ = "High-complexity x^2"
    elsif mapping_curve = 3
        curveName$ = "Low-complexity sqrt"
    else
        curveName$ = "Quantized"
    endif

    vizName$ = replace$(original_name$, "_", "\_ ", 0)

    selectObject: original_sound
    sourceVizPeak = Get absolute extremum: 0, 0, "Sinc70"
    selectObject: warped
    warpedVizPeak = Get absolute extremum: 0, 0, "Sinc70"
    waveAmp = max(sourceVizPeak, warpedVizPeak) * 1.05
    if waveAmp < 1e-12
        waveAmp = 1
    endif

    if use_voicing_gate
        pageHeight = 6.42
        sumY1 = 5.84
        sumY2 = 6.40
    else
        pageHeight = 5.40
        sumY1 = 4.82
        sumY2 = 5.38
    endif

    Erase all
    Select outer viewport: 0, 8, 0, pageHeight
    Black
    Plain line

    # ---- TITLE BAR ----
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##HFD-Driven Time Warping v2.4##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half",
        ... vizName$
        ... + " | " + presetName$
        ... + " | " + matName$
        ... + " | " + string$(n_channels) + " ch"
        ... + " | stretch " + fixed$(min_stretch_factor, 2) + "-" + fixed$(max_stretch_factor, 2) + "x"
        ... + " | " + fixed$(total_duration, 2) + " s -> " + fixed$(warped_duration, 2) + " s"

    # ---- ORIGINAL WAVEFORM (left) ----
    Select outer viewport: 0, 4, 0.65, 2.05
    Select inner viewport: 0.60, 3.85, 0.78, 1.92
    selectObject: original_sound
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, -waveAmp, waveAmp, "no", "Curve"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Original"
    Text left: "yes", "Amplitude"

    # ---- WARPED WAVEFORM (right) ----
    Select outer viewport: 4, 8, 0.65, 2.05
    Select inner viewport: 4.45, 7.70, 0.78, 1.92
    selectObject: warped
    Colour: "{0.25, 0.45, 0.75}"
    Draw: 0, 0, -waveAmp, waveAmp, "no", "Curve"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Warped output"
    Text left: "yes", "Amplitude"

    # ---- HFD COMPLEXITY ----
    Select outer viewport: 0, 8, 2.20, 3.32
    Select inner viewport: 0.60, 7.70, 2.33, 3.19
    Axes: 0, total_duration, 1.0, 2.0
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, total_duration, 1.0, 2.0
    Colour: "{0.92, 0.82, 0.60}"
    for i from 2 to num_frames
        Draw line: t_points#[i-1], hfd_values#[i-1], t_points#[i], hfd_values#[i]
    endfor
    Colour: "{0.80, 0.60, 0.20}"
    Line width: 1.5
    for i from 2 to num_frames
        Draw line: t_points#[i-1], smoothed_hfd#[i-1], t_points#[i], smoothed_hfd#[i]
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Signal complexity (HFD)  -  higher = more irregular  |  light = raw, dark = smoothed"
    Text left: "yes", "HFD"

    # ---- TIME-WARP COMMAND ----
    Select outer viewport: 0, 8, 3.48, 4.60
    Select inner viewport: 0.60, 7.70, 3.61, 4.47
    stretchMargin = (max_stretch_factor - min_stretch_factor) * 0.1
    if stretchMargin < 0.05
        stretchMargin = 0.05
    endif
    stretchLo = min_stretch_factor - stretchMargin
    stretchHi = max_stretch_factor + stretchMargin
    Axes: 0, total_duration, stretchLo, stretchHi
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, total_duration, stretchLo, stretchHi
    Colour: "{0.75, 0.75, 0.75}"
    Dotted line
    Draw line: 0, 1.0, total_duration, 1.0
    Solid line
    Colour: "{0.92, 0.72, 0.70}"
    for i from 2 to num_frames
        Draw line: t_points#[i-1], raw_stretch#[i-1], t_points#[i], raw_stretch#[i]
    endfor
    Colour: "{0.78, 0.28, 0.22}"
    Line width: 1.5
    for i from 2 to num_frames
        Draw line: t_points#[i-1], stretch_factors#[i-1], t_points#[i], stretch_factors#[i]
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Time-warp command  -  above 1x stretches, below 1x contracts  |  light = raw, dark = final"
    One mark left: 1.0, "no", "yes", "no", "1x"
    if not use_voicing_gate
        Text bottom: "yes", "Time (s)"
        One mark bottom: 0, "no", "yes", "no", "0"
        One mark bottom: total_duration * 0.5, "no", "yes", "no", fixed$(total_duration * 0.5, 1)
        One mark bottom: total_duration, "no", "yes", "no", fixed$(total_duration, 1)
    endif

    # ---- VOICING GATE ----
    if use_voicing_gate
        Select outer viewport: 0, 8, 4.76, 5.68
        Select inner viewport: 0.60, 7.70, 4.89, 5.55
        Axes: 0, total_duration, 0, 1.1
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, total_duration, 0, 1.1
        Colour: "{0.35, 0.60, 0.40}"
        Line width: 1.5
        for i from 2 to num_frames
            Draw line: t_points#[i-1], smoothed_voicing#[i-1], t_points#[i], smoothed_voicing#[i]
        endfor
        Line width: 1
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text top: "no", "Voicing gate  -  unvoiced regions pull the warp back toward 1x"
        Text left: "yes", "Voicing"
        Text bottom: "yes", "Time (s)"
        One mark bottom: 0, "no", "yes", "no", "0"
        One mark bottom: total_duration * 0.5, "no", "yes", "no", fixed$(total_duration * 0.5, 1)
        One mark bottom: total_duration, "no", "yes", "no", fixed$(total_duration, 1)
    endif

    # ---- SUMMARY BAR ----
    Select outer viewport: 0, 8, sumY1, sumY2
    Select inner viewport: 0.60, 7.70, sumY1 + 0.04, sumY2 - 0.03
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    if use_voicing_gate
        processText$ = "##Process:## audio -> HFD complexity -> curve mapping -> voicing gate -> DurationTier warp"
    else
        processText$ = "##Process:## audio -> HFD complexity -> curve mapping -> DurationTier warp"
    endif
    Text: 0.02, "left", 0.72, "half", processText$
    Text: 0.02, "left", 0.28, "half",
        ... "##Result:## " + fixed$(total_duration, 2) + " s -> " + fixed$(warped_duration, 2) + " s"
        ... + " | HFD " + fixed$(minHFD, 2) + "-" + fixed$(maxHFD, 2)
        ... + " | active " + string$(active_count) + "/" + string$(num_frames)
        ... + " | curve " + curveName$
        ... + " | slew " + fixed$(max_stretch_change_per_sec, 1) + "/s"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1

    Select outer viewport: 0, 8, 0, pageHeight
endif

# ==============================================================================
# 7. CLEANUP
# ==============================================================================

removeObject: dur_tier

selectObject: warped
resultName$ = selected$("Sound")

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Original: ", fixed$(total_duration, 4), " s"
appendInfoLine: "Predicted: ", fixed$(predicted_duration, 4), " s"
appendInfoLine: "Warped: ", fixed$(warped_duration, 4), " s"
appendInfoLine: "Prediction error: ", fixed$(duration_error_ms, 2), " ms"
appendInfoLine: "Channels preserved: ", n_channels
appendInfoLine: "Stretch range: ", fixed$(min_stretch_factor, 2), " - ", fixed$(max_stretch_factor, 2), "x"
if use_voicing_gate
    appendInfoLine: "Voicing influence: ", fixed$(voicing_influence * 100, 0), "%"
endif
appendInfoLine: ""
appendInfoLine: "Created: ", resultName$

if play_result
    selectObject: warped
    Play
endif

selectObject: warped

# ==============================================================================
# WINDOWED HFD CALCULATION PROCEDURE
# ==============================================================================
procedure windowedHFD: .mat, .start, .end, .kmax, .skip_win
    .n = .end - .start + 1
    
    # Prepare optional Hann window and a correctly normalized mean.
    .sum = 0
    .sum_sq = 0
    .sum_w = 0
    if .skip_win = 0 and .n > 1
        hann# = zero#(.n)
    endif
    
    for .i from 1 to .n
        .col = .start + .i - 1
        .val = samples#[.col]
        .sum_sq = .sum_sq + .val ^ 2
        if .skip_win = 0 and .n > 1
            hann#[.i] = 0.5 * (1 - cos(2 * pi * (.i - 1) / (.n - 1)))
            .sum = .sum + .val * hann#[.i]
            .sum_w = .sum_w + hann#[.i]
        else
            .sum = .sum + .val
        endif
    endfor
    
    if .n > 0
        .rms = sqrt(.sum_sq / .n)
    else
        .rms = 0
    endif
    
    if .skip_win = 0 and .sum_w > 0
        .mean = .sum / .sum_w
    elsif .n > 0
        .mean = .sum / .n
    else
        .mean = 0
    endif
    
    if .n < 20 or .rms <= 1e-15
        # A flat/silent trace has the minimum curve dimension, not arbitrary 1.5.
        .result = 1.0
    else
        .sx = 0
        .sy = 0
        .sxy = 0
        .sxx = 0
        .np = 0
        
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
                        
                        if .skip_win = 0
                            .idx1 = .m + (.j - 1) * .k
                            .idx2 = .m + .j * .k
                            .v1w = (.v1 - .mean) * hann#[.idx1]
                            .v2w = (.v2 - .mean) * hann#[.idx2]
                            .diff = .diff + abs(.v2w - .v1w)
                        else
                            # Mean cancels in a difference, but keep this form explicit.
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
                .result = 1.0
            endif
        else
            .result = 1.0
        endif
        
        # Higuchi dimension of a 1-D graph should lie in [1,2].
        if .result < 1
            .result = 1
        elsif .result > 2
            .result = 2
        endif
    endif
endproc
