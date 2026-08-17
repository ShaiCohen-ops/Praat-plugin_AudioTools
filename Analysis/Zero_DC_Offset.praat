# ============================================================
# Praat AudioTools - Zero DC Offset
# Author: Shai Cohen
# Version: 0.1.1 (2026)
# License: MIT License
#
# Purpose:
#   Remove constant DC offset from a selected Sound by subtracting
#   the mean amplitude independently from every channel.
#
# Algorithm:
#   x_out[c,n] = x_in[c,n] - mean_c
#
# Notes:
#   - No high-pass filtering.
#   - No normalization or peak scaling.
#   - Channel count, sample rate, samples and time domain are preserved.
#   - The optional DC trajectory is a QC display; global mean removal
#     does not attempt to correct time-varying baseline drift.
# ============================================================

clearinfo

number_of_selected_sounds = numberOfSelected ("Sound")
if number_of_selected_sounds <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

source_id = selected ("Sound")
selectObject: source_id
source_name$ = selected$ ("Sound")
start_time = Get start time
end_time = Get end time
duration = Get total duration
channels = Get number of channels
sample_rate = Get sampling frequency
sample_period = Get sampling period

form Zero DC Offset v0.1.1
    comment Constant DC removal: subtract each channel mean; no filtering or normalization.
    positive Dc_trajectory_window_s 0.25
    boolean Draw_visualization 1
    boolean Create_measurement_table 1
endform

if duration <= 0
    exitScript: "The selected Sound has zero duration."
endif

# ------------------------------------------------------------
# 1. Measure each input channel
# ------------------------------------------------------------
strong_channel = 1
strong_rms = -1
max_abs_dc_before = 0
max_peak_before = 0

for c from 1 to channels
    selectObject: source_id
    if channels = 1
        dc_before[c] = Get mean: 0, 0
        rms_before[c] = Get root-mean-square: 0, 0
        peak_before[c] = Get absolute extremum: 0, 0, "None"
    else
        Extract one channel: c
        temp_channel_id = selected ("Sound")
        dc_before[c] = Get mean: 0, 0
        rms_before[c] = Get root-mean-square: 0, 0
        peak_before[c] = Get absolute extremum: 0, 0, "None"
        removeObject: temp_channel_id
    endif

    if rms_before[c] > strong_rms
        strong_rms = rms_before[c]
        strong_channel = c
    endif

    if abs(dc_before[c]) > max_abs_dc_before
        max_abs_dc_before = abs(dc_before[c])
    endif
    if peak_before[c] > max_peak_before
        max_peak_before = peak_before[c]
    endif
endfor

# ------------------------------------------------------------
# 2. Copy and remove the exact per-channel mean
# ------------------------------------------------------------
selectObject: source_id
output_name$ = source_name$ + "_ZeroDC"
corrected_id = Copy: output_name$

for c from 1 to channels
    selectObject: corrected_id
    c_string$ = string$ (c)
    dc_string$ = fixed$ (dc_before[c], 17)
    Formula: "if row = " + c_string$ + " then self - (" + dc_string$ + ") else self fi"
endfor

# ------------------------------------------------------------
# 3. Measure corrected channels and QC
# ------------------------------------------------------------
max_abs_dc_after = 0
max_peak_after = 0
max_dc_percent_before = 0
max_dc_percent_after = 0

for c from 1 to channels
    selectObject: corrected_id
    if channels = 1
        dc_after[c] = Get mean: 0, 0
        rms_after[c] = Get root-mean-square: 0, 0
        peak_after[c] = Get absolute extremum: 0, 0, "None"
    else
        Extract one channel: c
        temp_channel_id = selected ("Sound")
        dc_after[c] = Get mean: 0, 0
        rms_after[c] = Get root-mean-square: 0, 0
        peak_after[c] = Get absolute extremum: 0, 0, "None"
        removeObject: temp_channel_id
    endif

    if rms_before[c] > 1e-30
        dc_percent_before[c] = 100 * abs(dc_before[c]) / rms_before[c]
    else
        dc_percent_before[c] = 0
    endif

    if rms_after[c] > 1e-30
        dc_percent_after[c] = 100 * abs(dc_after[c]) / rms_after[c]
    else
        dc_percent_after[c] = 0
    endif

    if peak_before[c] > 1e-30
        peak_dbfs_before[c] = 20 * ln(peak_before[c]) / ln(10)
    else
        peak_dbfs_before[c] = undefined
    endif
    if peak_after[c] > 1e-30
        peak_dbfs_after[c] = 20 * ln(peak_after[c]) / ln(10)
    else
        peak_dbfs_after[c] = undefined
    endif

    if abs(dc_after[c]) > max_abs_dc_after
        max_abs_dc_after = abs(dc_after[c])
    endif
    if peak_after[c] > max_peak_after
        max_peak_after = peak_after[c]
    endif
    if dc_percent_before[c] > max_dc_percent_before
        max_dc_percent_before = dc_percent_before[c]
    endif
    if dc_percent_after[c] > max_dc_percent_after
        max_dc_percent_after = dc_percent_after[c]
    endif
endfor

# ------------------------------------------------------------
# 4. Measurement table
# ------------------------------------------------------------
measurement_table_id = 0
if create_measurement_table
    Create Table with column names: "ZeroDC_Measurements", channels, "Channel DC_before DC_after DCpctRMS_before DCpctRMS_after RMS_before RMS_after Peak_before Peak_after Peak_dBFS_before Peak_dBFS_after"
    measurement_table_id = selected ("Table")

    for c from 1 to channels
        selectObject: measurement_table_id
        Set numeric value: c, "Channel", c
        Set numeric value: c, "DC_before", dc_before[c]
        Set numeric value: c, "DC_after", dc_after[c]
        Set numeric value: c, "DCpctRMS_before", dc_percent_before[c]
        Set numeric value: c, "DCpctRMS_after", dc_percent_after[c]
        Set numeric value: c, "RMS_before", rms_before[c]
        Set numeric value: c, "RMS_after", rms_after[c]
        Set numeric value: c, "Peak_before", peak_before[c]
        Set numeric value: c, "Peak_after", peak_after[c]
        Set numeric value: c, "Peak_dBFS_before", peak_dbfs_before[c]
        Set numeric value: c, "Peak_dBFS_after", peak_dbfs_after[c]
    endfor
endif

# ------------------------------------------------------------
# 5. Information summary
# ------------------------------------------------------------
clearinfo
appendInfoLine: "=============================================="
appendInfoLine: "ZERO DC OFFSET v0.1.1"
appendInfoLine: "=============================================="
appendInfoLine: "Source: ", source_name$
appendInfoLine: "Output: ", output_name$
appendInfoLine: "Channels: ", channels, "   Sample rate: ", fixed$ (sample_rate, 0), " Hz"
appendInfoLine: "Operation: x_out = x_in - mean(channel)"
appendInfoLine: "No filtering; no normalization."
appendInfoLine: ""

for c from 1 to channels
    appendInfoLine: "Channel ", c, ": DC ", fixed$ (dc_before[c], 9), " -> ", fixed$ (dc_after[c], 12), "   (", fixed$ (dc_percent_before[c], 4), "% RMS -> ", fixed$ (dc_percent_after[c], 6), "% RMS)"
    appendInfoLine: "           Peak ", fixed$ (peak_before[c], 6), " -> ", fixed$ (peak_after[c], 6), "   RMS ", fixed$ (rms_before[c], 6), " -> ", fixed$ (rms_after[c], 6)
endfor

appendInfoLine: ""
if max_peak_after > 1
    appendInfoLine: "QC WARNING: corrected peak exceeds +/-1 (max abs = ", fixed$ (max_peak_after, 6), "). No normalization was applied."
endif
if max_abs_dc_after <= 1e-12
    appendInfoLine: "QC: residual global DC is at numerical-zero scale (<= 1e-12)."
else
    appendInfoLine: "QC: maximum residual global DC = ", string$ (max_abs_dc_after)
endif

# ------------------------------------------------------------
# 6. Visualization
# ------------------------------------------------------------
if draw_visualization
    # Create temporary mono copies of the strongest input channel for drawing.
    selectObject: source_id
    if channels = 1
        before_viz_id = Copy: "__ZeroDC_before_viz"
    else
        Extract one channel: strong_channel
        before_viz_id = selected ("Sound")
        Rename: "__ZeroDC_before_viz"
    endif

    selectObject: corrected_id
    if channels = 1
        after_viz_id = Copy: "__ZeroDC_after_viz"
    else
        Extract one channel: strong_channel
        after_viz_id = selected ("Sound")
        Rename: "__ZeroDC_after_viz"
    endif

    wave_peak = max(peak_before[strong_channel], peak_after[strong_channel])
    if wave_peak < 1e-12
        wave_peak = 1e-6
    else
        wave_peak = 1.08 * wave_peak
    endif

    # DC trajectory: evenly sampled across the complete Sound duration.
    trajectory_window = max(2 * sample_period, min(dc_trajectory_window_s, duration))
    n_trajectory = ceiling(duration / trajectory_window)
    n_trajectory = max(2, min(200, n_trajectory))
    trajectory_step = duration / n_trajectory

    for k from 1 to n_trajectory
        trajectory_time[k] = start_time + (k - 0.5) * trajectory_step
        half_window = 0.5 * trajectory_window
        trajectory_t1 = max(start_time, trajectory_time[k] - half_window)
        trajectory_t2 = min(end_time, trajectory_time[k] + half_window)

        selectObject: before_viz_id
        trajectory_before[k] = Get mean: trajectory_t1, trajectory_t2
        selectObject: after_viz_id
        trajectory_after[k] = Get mean: trajectory_t1, trajectory_t2
    endfor

    trajectory_abs_max = max_abs_dc_before
    for k from 1 to n_trajectory
        if abs(trajectory_before[k]) > trajectory_abs_max
            trajectory_abs_max = abs(trajectory_before[k])
        endif
        if abs(trajectory_after[k]) > trajectory_abs_max
            trajectory_abs_max = abs(trajectory_after[k])
        endif
    endfor
    if trajectory_abs_max < 1e-12
        trajectory_abs_max = 1e-6
    else
        trajectory_abs_max = 1.12 * trajectory_abs_max
    endif

    display_name$ = replace$ (source_name$, "_", " ", 0)
    display_name$ = replace$ (display_name$, "%", "pct", 0)

    Erase all

    # Main title strip.
    Select outer viewport: 0, 8, 0.02, 0.36
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.52, "half", "##Zero DC Offset##"

    # Metadata strip.
    Select outer viewport: 0, 8, 0.39, 0.68
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.32, 0.32, 0.32}"
    Text: 0.5, "centre", 0.50, "half", display_name$ + "  |  channel " + string$ (strong_channel) + " shown  |  " + string$ (channels) + " ch  |  " + fixed$ (sample_rate, 0) + " Hz"

    # Panel 1 title.
    Select outer viewport: 0, 8, 0.72, 0.96
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.5, "centre", 0.50, "half", "##Waveform before##   shared amplitude scale"

    # Panel 1 data.
    Select outer viewport: 0, 8, 0.96, 2.45
    Select inner viewport: 0.68, 7.66, 1.08, 2.30
    selectObject: before_viz_id
    Draw: start_time, end_time, -wave_peak, wave_peak, "no", "Curve"
    Select inner viewport: 0.68, 7.66, 1.08, 2.30
    Axes: start_time, end_time, -wave_peak, wave_peak
    Colour: "{0.70, 0.70, 0.70}"
    Line width: 1
    Draw line: start_time, 0, end_time, 0
    Colour: "Black"
    Draw inner box
    Font size: 7
    Marks left: 3, "yes", "yes", "no"

    # Panel 2 title.
    Select outer viewport: 0, 8, 2.48, 2.72
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.5, "centre", 0.50, "half", "##Waveform after##   exact same amplitude scale"

    # Panel 2 data.
    Select outer viewport: 0, 8, 2.72, 4.21
    Select inner viewport: 0.68, 7.66, 2.84, 4.06
    selectObject: after_viz_id
    Draw: start_time, end_time, -wave_peak, wave_peak, "no", "Curve"
    Select inner viewport: 0.68, 7.66, 2.84, 4.06
    Axes: start_time, end_time, -wave_peak, wave_peak
    Colour: "{0.70, 0.70, 0.70}"
    Line width: 1
    Draw line: start_time, 0, end_time, 0
    Colour: "Black"
    Draw inner box
    Font size: 7
    Marks left: 3, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"

    # Panel 3 title.
    Select outer viewport: 0, 8, 4.25, 4.50
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.5, "centre", 0.50, "half", "##Local mean trajectory##   global DC removal does not hide baseline drift"

    # Panel 3 data.
    Select outer viewport: 0, 8, 4.50, 6.45
    Select inner viewport: 0.72, 7.64, 4.64, 6.28
    Axes: start_time, end_time, -trajectory_abs_max, trajectory_abs_max
    Paint rectangle: "{0.985, 0.985, 0.985}", start_time, end_time, -trajectory_abs_max, trajectory_abs_max
    Colour: "{0.78, 0.78, 0.78}"
    Draw line: start_time, 0, end_time, 0

    # Before trajectory.
    Colour: "{0.25, 0.42, 0.70}"
    Line width: 1.5
    for k from 2 to n_trajectory
        Draw line: trajectory_time[k - 1], trajectory_before[k - 1], trajectory_time[k], trajectory_before[k]
    endfor

    # After trajectory.
    Colour: "{0.72, 0.34, 0.25}"
    Line width: 1.5
    for k from 2 to n_trajectory
        Draw line: trajectory_time[k - 1], trajectory_after[k - 1], trajectory_time[k], trajectory_after[k]
    endfor

    # Measured global means as reference lines.
    Colour: "{0.25, 0.42, 0.70}"
    Dotted line
    Draw line: start_time, dc_before[strong_channel], end_time, dc_before[strong_channel]
    Colour: "{0.72, 0.34, 0.25}"
    Draw line: start_time, dc_after[strong_channel], end_time, dc_after[strong_channel]
    Solid line

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Marks left: 4, "yes", "yes", "no"
    Text left: "yes", "Local mean"
    Text bottom: "yes", "Time (s)"

    # Manual legend kept inside the panel.
    Select inner viewport: 0.72, 7.64, 4.64, 6.28
    Axes: start_time, end_time, -trajectory_abs_max, trajectory_abs_max
    legend_x = start_time + 0.02 * duration
    legend_y1 = trajectory_abs_max * 0.84
    legend_y2 = trajectory_abs_max * 0.64
    legend_dx = 0.06 * duration
    Colour: "{0.25, 0.42, 0.70}"
    Draw line: legend_x, legend_y1, legend_x + legend_dx, legend_y1
    Colour: "Black"
    Font size: 7
    Text: legend_x + 1.25 * legend_dx, "left", legend_y1, "half", "Before"
    Colour: "{0.72, 0.34, 0.25}"
    Draw line: legend_x, legend_y2, legend_x + legend_dx, legend_y2
    Colour: "Black"
    Text: legend_x + 1.25 * legend_dx, "left", legend_y2, "half", "After"

    # Summary / process strip.
    Select outer viewport: 0, 8, 6.58, 7.92
    Select inner viewport: 0.48, 7.58, 6.68, 7.82
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.955, 0.955, 0.955}", 0, 1, 0, 1
    Colour: "Black"
    Font size: 9
    Text: 0.03, "left", 0.78, "half", "##Correction##   x_out[c,n] = x_in[c,n] - mean_c"
    Font size: 8
    Text: 0.03, "left", 0.53, "half", "Max |DC|: " + string$ (max_abs_dc_before) + " -> " + string$ (max_abs_dc_after) + "   |   strongest channel: " + string$ (strong_channel)
    Text: 0.03, "left", 0.30, "half", "Peak abs: " + fixed$ (max_peak_before, 6) + " -> " + fixed$ (max_peak_after, 6) + "   |   no filtering / no normalization"
    if max_peak_after > 1
        Colour: "{0.55, 0.18, 0.12}"
        Text: 0.03, "left", 0.10, "half", "QC: corrected peak exceeds +/-1; inspect before export."
    else
        Colour: "{0.22, 0.42, 0.24}"
        Text: 0.03, "left", 0.10, "half", "QC: constant per-channel DC removed; trajectory reveals any remaining drift."
    endif
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    removeObject: before_viz_id, after_viz_id
endif

# ------------------------------------------------------------
# 7. Return useful objects to the Objects list selection
# ------------------------------------------------------------
selectObject: source_id
plusObject: corrected_id

appendInfoLine: ""
appendInfoLine: "Created Sound: ", output_name$
if create_measurement_table
    appendInfoLine: "Created Table: ZeroDC_Measurements"
endif
if draw_visualization
    appendInfoLine: "Picture: before/after waveform + DC trajectory + QC summary"
endif
appendInfoLine: "Done."
