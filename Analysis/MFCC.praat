# ============================================================
# Praat AudioTools - MFCC.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.2 (2026) - Reviewed extraction + visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Extract MFCC coefficients from one selected Sound, create a Table,
#   calculate frame-to-frame MFCC distance, and optionally draw an
#   explanatory visualization of waveform, coefficient activity, and
#   timbral change.
#
# Notes:
#   - C0 is queried separately because it is the constant/energy-related term.
#   - MFCC_Delta is Euclidean distance between successive C1..Cn vectors.
#   - The heatmap is row-standardized (z-score per coefficient) only for
#     visualization; the Table contains the original MFCC values.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
sound_name$ = selected$("Sound")

form MFCC Analysis v0.2
    natural Number_of_coefficients 12
    boolean Include_c0_energy 1
    boolean Add_timbral_change 1
    boolean Draw_visualization 1
endform

# Preserve the original analysis settings from v0.1.
window_length = 0.015
time_step_request = 0.005
first_filter_hz = 100
filter_distance_hz = 100
maximum_frequency_hz = 0

# ===== SOURCE GEOMETRY / REPRESENTATIVE CHANNEL =====
selectObject: sound
sound_tmin = Get start time
sound_tmax = Get end time
sound_duration = sound_tmax - sound_tmin
n_channels = Get number of channels

analysis_sound = sound
analysis_is_copy = 0
analysis_channel = 1
if n_channels > 1
    best_rms = -1
    for ch from 1 to n_channels
        selectObject: sound
        tmp_channel = Extract one channel: ch
        channel_rms = Get root-mean-square: sound_tmin, sound_tmax
        if channel_rms > best_rms
            best_rms = channel_rms
            analysis_channel = ch
        endif
        removeObject: tmp_channel
    endfor
    selectObject: sound
    analysis_sound = Extract one channel: analysis_channel
    analysis_is_copy = 1
endif

# ===== MFCC EXTRACTION =====
selectObject: analysis_sound
mfcc = To MFCC: number_of_coefficients, window_length, time_step_request, first_filter_hz, filter_distance_hz, maximum_frequency_hz

selectObject: mfcc
num_frames = Get number of frames
time_step = Get time step
if num_frames < 1
    if analysis_is_copy
        removeObject: analysis_sound
    endif
    removeObject: mfcc
    exitScript: "MFCC analysis produced no frames."
endif

# Matrix rows contain C1..Cn and columns contain frames.
selectObject: mfcc
matrix = To Matrix
selectObject: matrix
matrix_rows = Get number of rows
matrix_cols = Get number of columns
usable_coefficients = min(number_of_coefficients, matrix_rows)
num_frames = min(num_frames, matrix_cols)

if usable_coefficients < 1
    removeObject: matrix, mfcc
    if analysis_is_copy
        removeObject: analysis_sound
    endif
    exitScript: "MFCC matrix contains no usable coefficients."
endif

# Exact frame centres from the sampled MFCC/Matrix geometry.
selectObject: matrix
first_frame_time = Get x of column: 1
last_frame_time = Get x of column: num_frames
viz_tmin = max(sound_tmin, first_frame_time - 0.5 * time_step)
viz_tmax = min(sound_tmax, last_frame_time + 0.5 * time_step)
if viz_tmax <= viz_tmin
    viz_tmin = sound_tmin
    viz_tmax = sound_tmax
endif

# ===== OUTPUT TABLE =====
columns$ = "FrameTime"
if include_c0_energy
    columns$ = columns$ + " C0"
endif
for coef from 1 to usable_coefficients
    columns$ = columns$ + " C" + string$(coef)
endfor
if add_timbral_change
    columns$ = columns$ + " MFCC_Delta"
endif

Create Table with column names: "MFCC_Table", num_frames, columns$
table = selected("Table")

# Statistics used for QC and visualization.
coef_sum# = zero#(usable_coefficients)
coef_sumsq# = zero#(usable_coefficients)
previous# = zero#(usable_coefficients)
delta# = zero#(num_frames)
delta_sum = 0

for frame from 1 to num_frames
    selectObject: matrix
    frame_time = Get x of column: frame
    selectObject: table
    Set numeric value: frame, "FrameTime", frame_time

    if include_c0_energy
        selectObject: mfcc
        c0_value = Get c0 value in frame: frame
        if c0_value = undefined
            c0_value = 0
        endif
        selectObject: table
        Set numeric value: frame, "C0", c0_value
    endif

    delta_sq = 0
    for coef from 1 to usable_coefficients
        selectObject: matrix
        coef_value = Get value in cell: coef, frame
        if coef_value = undefined
            coef_value = 0
        endif

        coef_sum#[coef] = coef_sum#[coef] + coef_value
        coef_sumsq#[coef] = coef_sumsq#[coef] + coef_value * coef_value

        if frame > 1
            d = coef_value - previous#[coef]
            delta_sq = delta_sq + d * d
        endif
        previous#[coef] = coef_value

        selectObject: table
        Set numeric value: frame, "C" + string$(coef), coef_value
    endfor

    if frame > 1
        delta#[frame] = sqrt(delta_sq)
        delta_sum = delta_sum + delta#[frame]
    else
        delta#[frame] = 0
    endif

    if add_timbral_change
        selectObject: table
        Set numeric value: frame, "MFCC_Delta", delta#[frame]
    endif
endfor

# Per-coefficient statistics for an honest row-standardized heatmap.
coef_mean# = zero#(usable_coefficients)
coef_sd# = zero#(usable_coefficients)
for coef from 1 to usable_coefficients
    coef_mean#[coef] = coef_sum#[coef] / num_frames
    variance = coef_sumsq#[coef] / num_frames - coef_mean#[coef] * coef_mean#[coef]
    if variance < 0
        variance = 0
    endif
    coef_sd#[coef] = sqrt(variance)
    if coef_sd#[coef] < 1e-12
        coef_sd#[coef] = 1
    endif
endfor

if num_frames > 1
    mean_delta = delta_sum / (num_frames - 1)
else
    mean_delta = 0
endif

delta_sorted# = sort#(delta#)
p95_index = max(1, min(num_frames, ceiling(0.95 * num_frames)))
p95_delta = delta_sorted#[p95_index]
if p95_delta <= 1e-12
    p95_delta = 1
endif

# ===== VISUALIZATION =====
if draw_visualization
    display_name$ = replace$(sound_name$, "_", " ", 0)

    # Create a display-only copy. Values become per-row z-scores, clipped to +/-3.
    selectObject: matrix
    z_matrix = Copy: "MFCC_z"
    Formula: "max(-3, min(3, (self - coef_mean#[row]) / coef_sd#[row]))"

    selectObject: analysis_sound
    wave_peak = Get absolute extremum: sound_tmin, sound_tmax, "Sinc70"
    if wave_peak = undefined or wave_peak <= 0
        wave_peak = 1
    endif
    wave_peak = wave_peak * 1.03

    Erase all

    # Main title strip.
    Select outer viewport: 0, 8, 0.00, 0.38
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Font size: 14
    Text: 0.5, "centre", 0.55, "half", "##MFCC Analysis##"

    # Metadata strip, deliberately separate from title.
    Select outer viewport: 0, 8, 0.39, 0.66
    Axes: 0, 1, 0, 1
    Font size: 8
    Text: 0.5, "centre", 0.58, "half", display_name$ + "  |  C1-C" + string$(usable_coefficients) + "  |  " + fixed$(time_step * 1000, 1) + " ms frame step"

    # Panel 1 title.
    Select outer viewport: 0.72, 7.45, 0.72, 0.94
    Axes: 0, 1, 0, 1
    Font size: 9
    Text: 0.5, "centre", 0.58, "half", "##Analyzed waveform##"

    # Panel 1: waveform on explicit symmetric scale.
    Select outer viewport: 0, 8, 0.95, 2.45
    Select inner viewport: 0.72, 7.45, 1.10, 2.30
    selectObject: analysis_sound
    Colour: "{0.32, 0.40, 0.56}"
    Draw: sound_tmin, sound_tmax, -wave_peak, wave_peak, "no", "Curve"
    Select inner viewport: 0.72, 7.45, 1.10, 2.30
    Axes: sound_tmin, sound_tmax, -wave_peak, wave_peak
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.72, 7.45, 1.10, 2.30
    Axes: sound_tmin, sound_tmax, -wave_peak, wave_peak
    Font size: 7
    Marks left: 2, "yes", "yes", "no"
    Select inner viewport: 0.72, 7.45, 1.10, 2.30
    Axes: sound_tmin, sound_tmax, -wave_peak, wave_peak
    Text left: "yes", "Amplitude"

    # Panel 2 title.
    Select outer viewport: 0.72, 7.45, 2.53, 2.78
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.5, "centre", 0.58, "half", "##MFCC coefficient activity##   row z-score, clipped at +/-3"

    # Panel 2: actual coefficient matrix, standardized only for display.
    Select outer viewport: 0, 8, 2.79, 5.05
    Select inner viewport: 0.72, 7.45, 2.97, 4.88
    selectObject: z_matrix
    Paint cells: viz_tmin, viz_tmax, 1, usable_coefficients, -3, 3
    Select inner viewport: 0.72, 7.45, 2.97, 4.88
    Axes: viz_tmin, viz_tmax, 1, usable_coefficients
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.72, 7.45, 2.97, 4.88
    Axes: viz_tmin, viz_tmax, 1, usable_coefficients
    Font size: 7
    Marks left every: 1, max(1, round(usable_coefficients / 6)), "yes", "yes", "no"
    Select inner viewport: 0.72, 7.45, 2.97, 4.88
    Axes: viz_tmin, viz_tmax, 1, usable_coefficients
    Text left: "yes", "Coefficient"

    # Panel 3 title.
    Select outer viewport: 0.72, 7.45, 5.12, 5.37
    Axes: 0, 1, 0, 1
    Font size: 9
    Text: 0.5, "centre", 0.58, "half", "##Timbral motion##   frame-to-frame Euclidean MFCC distance"

    # Panel 3: normalized delta, using measured 95th percentile as scale reference.
    Select outer viewport: 0, 8, 5.38, 6.95
    Select inner viewport: 0.72, 7.45, 5.57, 6.76
    Axes: viz_tmin, viz_tmax, 0, 1.2
    Paint rectangle: "{0.97, 0.97, 0.98}", viz_tmin, viz_tmax, 0, 1.2
    viz_stride = max(1, ceiling(num_frames / 3000))
    prev_frame = 1
    frame = 1 + viz_stride
    Colour: "{0.22, 0.44, 0.72}"
    Line width: 1.3
    while frame <= num_frames
        selectObject: matrix
        t0 = Get x of column: prev_frame
        t1 = Get x of column: frame
        y0 = min(1.2, delta#[prev_frame] / p95_delta)
        y1 = min(1.2, delta#[frame] / p95_delta)
        Draw line: t0, y0, t1, y1
        prev_frame = frame
        frame = frame + viz_stride
    endwhile
    Select inner viewport: 0.72, 7.45, 5.57, 6.76
    Axes: viz_tmin, viz_tmax, 0, 1.2
    Colour: "{0.60, 0.60, 0.60}"
    Dotted line
    Draw line: viz_tmin, 1, viz_tmax, 1
    Solid line
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.72, 7.45, 5.57, 6.76
    Axes: viz_tmin, viz_tmax, 0, 1.2
    Font size: 7
    Marks left: 3, "yes", "yes", "no"
    Select inner viewport: 0.72, 7.45, 5.57, 6.76
    Axes: viz_tmin, viz_tmax, 0, 1.2
    Text left: "yes", "Delta / p95"
    Marks bottom every: 1, max(0.1, round(sound_duration / 8)), "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"

    # Summary strip.
    Select outer viewport: 0, 8, 7.06, 7.90
    Select inner viewport: 0.55, 7.55, 7.13, 7.82
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Select inner viewport: 0.55, 7.55, 7.13, 7.82
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Font size: 9
    Text: 0.02, "left", 0.72, "half", "##MFCC summary##"
    Font size: 8
    Text: 0.02, "left", 0.39, "half", "Frames " + string$(num_frames) + "   Coefficients " + string$(usable_coefficients) + "   Mean delta " + fixed$(mean_delta, 3) + "   p95 delta " + fixed$(p95_delta, 3)
    if n_channels > 1
        Text: 0.02, "left", 0.13, "half", "Analyzed channel " + string$(analysis_channel) + " of " + string$(n_channels) + " (strongest RMS); heatmap is display-standardized only"
    else
        Text: 0.02, "left", 0.13, "half", "Heatmap is display-standardized only; Table retains original MFCC values"
    endif
    Draw rectangle: 0, 1, 0, 1

    removeObject: z_matrix
endif

# ===== CLEANUP / OUTPUT =====
removeObject: matrix, mfcc
if analysis_is_copy
    removeObject: analysis_sound
endif

selectObject: sound, table
clearinfo
writeInfoLine: "=== MFCC Analysis v0.2 ==="
appendInfoLine: "Source: ", sound_name$
appendInfoLine: "Frames: ", num_frames, "   step: ", fixed$(time_step * 1000, 2), " ms"
appendInfoLine: "Coefficients: C1-C", usable_coefficients
if include_c0_energy
    appendInfoLine: "C0 included as energy-related constant term."
endif
if add_timbral_change
    appendInfoLine: "MFCC_Delta added: Euclidean distance between successive C1-C", usable_coefficients, " vectors."
endif
if n_channels > 1
    appendInfoLine: "Analysis channel: ", analysis_channel, " of ", n_channels, " (strongest RMS)"
endif
appendInfoLine: "Table 'MFCC_Table' created."
appendInfoLine: "Done."
