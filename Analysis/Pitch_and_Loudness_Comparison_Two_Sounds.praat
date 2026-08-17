# ============================================================
# Praat AudioTools - Pitch and Loudness Comparison: Two Sounds
# Version 1.0 (2026) - reviewed comparison / visualization
#
# Select exactly two Sound objects before running.
# Sound 1 = Teacher / Reference
# Sound 2 = Student / Comparison
#
# v1.0 changes
# - Compare at matched times rather than matching frame indices.
# - Relative-progress alignment (0..100%) is the default; elapsed-time alignment
#   remains available when timing itself should be preserved.
# - Stereo/multichannel Sounds use the strongest-RMS channel independently.
# - Pitch comparison is expressed in semitones, including signed offset,
#   absolute/RMS error, voicing mismatch, centred contour error, and correlation.
# - Intensity comparison separates fixed level offset from contour-shape mismatch.
# - Undefined/unvoiced samples are counted honestly and never included in divisors.
# - Creates a per-sample comparison Table and an 8x8 mechanism visualization.
# ============================================================

clearinfo

# ===== INPUT =====
n_sounds = numberOfSelected("Sound")
if n_sounds <> 2
    exitScript: "Please select exactly two Sound objects (Teacher/Reference first, Student/Comparison second)."
endif

sound1 = selected("Sound", 1)
sound2 = selected("Sound", 2)

form Compare teacher vs student v1.0
    optionmenu Analysis_type: 3
        option Loudness / intensity only
        option Pitch only
        option Both pitch and loudness
    optionmenu Alignment: 1
        option Relative progress (0-100%, recommended)
        option Elapsed time from each Sound start
    positive Time_step_s 0.01
    positive Pitch_floor_Hz 75
    positive Pitch_ceiling_Hz 600
    boolean Draw_visualization 1
endform

if time_step_s <= 0
    exitScript: "Time step must be positive."
endif
if pitch_floor_Hz <= 0
    exitScript: "Pitch floor must be positive."
endif
if pitch_ceiling_Hz <= pitch_floor_Hz
    exitScript: "Pitch ceiling must be higher than pitch floor."
endif

pitch_enabled = 0
intensity_enabled = 0
if analysis_type = 1
    intensity_enabled = 1
elsif analysis_type = 2
    pitch_enabled = 1
else
    pitch_enabled = 1
    intensity_enabled = 1
endif

# ===== SOURCE GEOMETRY =====
selectObject: sound1
name1$ = selected$("Sound")
xmin1 = Get start time
xmax1 = Get end time
duration1 = xmax1 - xmin1
channels1 = Get number of channels

selectObject: sound2
name2$ = selected$("Sound")
xmin2 = Get start time
xmax2 = Get end time
duration2 = xmax2 - xmin2
channels2 = Get number of channels

if duration1 <= 0 or duration2 <= 0
    exitScript: "Both Sounds must have positive duration."
endif

# ===== REPRESENTATIVE CHANNEL =====
procedure strongestChannel: .sound, .xmin, .xmax
    selectObject: .sound
    .n_channels = Get number of channels
    .result = .sound
    .channel = 1
    .is_copy = 0
    if .n_channels > 1
        .best_rms = -1
        for .ch from 1 to .n_channels
            selectObject: .sound
            .tmp = Extract one channel: .ch
            .rms = Get root-mean-square: .xmin, .xmax
            if .rms > .best_rms
                .best_rms = .rms
                .channel = .ch
            endif
            removeObject: .tmp
        endfor
        selectObject: .sound
        .result = Extract one channel: .channel
        .is_copy = 1
    endif
endproc

@strongestChannel: sound1, xmin1, xmax1
analysis1 = strongestChannel.result
analysis_channel1 = strongestChannel.channel
analysis1_is_copy = strongestChannel.is_copy

@strongestChannel: sound2, xmin2, xmax2
analysis2 = strongestChannel.result
analysis_channel2 = strongestChannel.channel
analysis2_is_copy = strongestChannel.is_copy

# ===== ANALYSIS OBJECTS =====
pitch1 = 0
pitch2 = 0
intensity1 = 0
intensity2 = 0

if pitch_enabled
    selectObject: analysis1
    pitch1 = To Pitch: time_step_s, pitch_floor_Hz, pitch_ceiling_Hz
    selectObject: analysis2
    pitch2 = To Pitch: time_step_s, pitch_floor_Hz, pitch_ceiling_Hz
endif

if intensity_enabled
    # Use the same low-frequency scale as the pitch floor so that window length is
    # explicit rather than hidden at a hard-coded value.
    selectObject: analysis1
    intensity1 = To Intensity: pitch_floor_Hz, time_step_s, "yes"
    selectObject: analysis2
    intensity2 = To Intensity: pitch_floor_Hz, time_step_s, "yes"
endif

# ===== MATCHED SAMPLE GRID =====
common_duration = min(duration1, duration2)
n_samples = floor(common_duration / time_step_s) + 1
if n_samples < 2
    n_samples = 2
endif

x# = zero#(n_samples)
time1# = zero#(n_samples)
time2# = zero#(n_samples)

pitch1_hz# = zero#(n_samples)
pitch2_hz# = zero#(n_samples)
pitch1_st# = zero#(n_samples)
pitch2_st# = zero#(n_samples)
pitch_error_st# = zero#(n_samples)
pitch1_valid# = zero#(n_samples)
pitch2_valid# = zero#(n_samples)
pitch_pair_valid# = zero#(n_samples)

intensity1_db# = zero#(n_samples)
intensity2_db# = zero#(n_samples)
level_error_db# = zero#(n_samples)
intensity_pair_valid# = zero#(n_samples)

paired_pitch_count = 0
voicing_mismatch_count = 0
both_unvoiced_count = 0
sum_pitch1_st = 0
sum_pitch2_st = 0
sum_pitch_signed = 0
sum_pitch_abs = 0
sum_pitch_sq = 0
max_pitch_abs = 0

paired_intensity_count = 0
sum_intensity1 = 0
sum_intensity2 = 0
sum_level_signed = 0
sum_level_abs = 0
sum_level_sq = 0
max_level_abs = 0

for i from 1 to n_samples
    progress = (i - 1) / (n_samples - 1)
    if alignment = 1
        t1 = xmin1 + progress * duration1
        t2 = xmin2 + progress * duration2
        x#[i] = progress * 100
    else
        elapsed = progress * common_duration
        t1 = xmin1 + elapsed
        t2 = xmin2 + elapsed
        x#[i] = elapsed
    endif
    time1#[i] = t1
    time2#[i] = t2

    if pitch_enabled
        selectObject: pitch1
        f1 = Get value at time: t1, "Hertz", "linear"
        selectObject: pitch2
        f2 = Get value at time: t2, "Hertz", "linear"

        voiced1 = 0
        voiced2 = 0
        if f1 <> undefined
            if f1 > 0
                voiced1 = 1
                pitch1_hz#[i] = f1
                pitch1_st#[i] = 12 * ln(f1 / 440) / ln(2)
                pitch1_valid#[i] = 1
            endif
        endif
        if f2 <> undefined
            if f2 > 0
                voiced2 = 1
                pitch2_hz#[i] = f2
                pitch2_st#[i] = 12 * ln(f2 / 440) / ln(2)
                pitch2_valid#[i] = 1
            endif
        endif

        if voiced1 and voiced2
            pitch_pair_valid#[i] = 1
            paired_pitch_count = paired_pitch_count + 1
            pitch_error_st#[i] = pitch2_st#[i] - pitch1_st#[i]
            pitch_abs = abs(pitch_error_st#[i])
            sum_pitch1_st = sum_pitch1_st + pitch1_st#[i]
            sum_pitch2_st = sum_pitch2_st + pitch2_st#[i]
            sum_pitch_signed = sum_pitch_signed + pitch_error_st#[i]
            sum_pitch_abs = sum_pitch_abs + pitch_abs
            sum_pitch_sq = sum_pitch_sq + pitch_error_st#[i] ^ 2
            if pitch_abs > max_pitch_abs
                max_pitch_abs = pitch_abs
            endif
        elsif voiced1 <> voiced2
            voicing_mismatch_count = voicing_mismatch_count + 1
        else
            both_unvoiced_count = both_unvoiced_count + 1
        endif
    endif

    if intensity_enabled
        selectObject: intensity1
        db1 = Get value at time: t1, "cubic"
        selectObject: intensity2
        db2 = Get value at time: t2, "cubic"
        if db1 <> undefined and db2 <> undefined
            intensity_pair_valid#[i] = 1
            intensity1_db#[i] = db1
            intensity2_db#[i] = db2
            level_error_db#[i] = db2 - db1
            level_abs = abs(level_error_db#[i])
            paired_intensity_count = paired_intensity_count + 1
            sum_intensity1 = sum_intensity1 + db1
            sum_intensity2 = sum_intensity2 + db2
            sum_level_signed = sum_level_signed + level_error_db#[i]
            sum_level_abs = sum_level_abs + level_abs
            sum_level_sq = sum_level_sq + level_error_db#[i] ^ 2
            if level_abs > max_level_abs
                max_level_abs = level_abs
            endif
        endif
    endif
endfor

# ===== SUMMARY METRICS =====
mean_pitch1_st = 0
mean_pitch2_st = 0
mean_pitch_offset_st = 0
pitch_mae_st = 0
pitch_rms_st = 0
pitch_contour_mae_st = 0
pitch_correlation = undefined
pitch_overlap_percent = 0
voicing_mismatch_percent = 0

if pitch_enabled
    if paired_pitch_count > 0
        mean_pitch1_st = sum_pitch1_st / paired_pitch_count
        mean_pitch2_st = sum_pitch2_st / paired_pitch_count
        mean_pitch_offset_st = sum_pitch_signed / paired_pitch_count
        pitch_mae_st = sum_pitch_abs / paired_pitch_count
        pitch_rms_st = sqrt(sum_pitch_sq / paired_pitch_count)
        pitch_overlap_percent = 100 * paired_pitch_count / n_samples

        pitch_shape_abs_sum = 0
        pitch_var1 = 0
        pitch_var2 = 0
        pitch_cov = 0
        for i from 1 to n_samples
            if pitch_pair_valid#[i]
                c1 = pitch1_st#[i] - mean_pitch1_st
                c2 = pitch2_st#[i] - mean_pitch2_st
                pitch_shape_abs_sum = pitch_shape_abs_sum + abs(c2 - c1)
                pitch_var1 = pitch_var1 + c1 ^ 2
                pitch_var2 = pitch_var2 + c2 ^ 2
                pitch_cov = pitch_cov + c1 * c2
            endif
        endfor
        pitch_contour_mae_st = pitch_shape_abs_sum / paired_pitch_count
        if pitch_var1 > 1e-12 and pitch_var2 > 1e-12
            pitch_correlation = pitch_cov / sqrt(pitch_var1 * pitch_var2)
            pitch_correlation = max(-1, min(1, pitch_correlation))
        endif
    endif
    voicing_mismatch_percent = 100 * voicing_mismatch_count / n_samples
endif

mean_intensity1 = 0
mean_intensity2 = 0
mean_level_offset_db = 0
level_mae_db = 0
level_rms_db = 0
level_contour_mae_db = 0
level_correlation = undefined

if intensity_enabled
    if paired_intensity_count > 0
        mean_intensity1 = sum_intensity1 / paired_intensity_count
        mean_intensity2 = sum_intensity2 / paired_intensity_count
        mean_level_offset_db = sum_level_signed / paired_intensity_count
        level_mae_db = sum_level_abs / paired_intensity_count
        level_rms_db = sqrt(sum_level_sq / paired_intensity_count)

        level_shape_abs_sum = 0
        level_var1 = 0
        level_var2 = 0
        level_cov = 0
        for i from 1 to n_samples
            if intensity_pair_valid#[i]
                c1 = intensity1_db#[i] - mean_intensity1
                c2 = intensity2_db#[i] - mean_intensity2
                level_shape_abs_sum = level_shape_abs_sum + abs(c2 - c1)
                level_var1 = level_var1 + c1 ^ 2
                level_var2 = level_var2 + c2 ^ 2
                level_cov = level_cov + c1 * c2
            endif
        endfor
        level_contour_mae_db = level_shape_abs_sum / paired_intensity_count
        if level_var1 > 1e-12 and level_var2 > 1e-12
            level_correlation = level_cov / sqrt(level_var1 * level_var2)
            level_correlation = max(-1, min(1, level_correlation))
        endif
    endif
endif

# ===== OUTPUT TABLE =====
clean_name2$ = replace$(name2$, " ", "_", 0)
if analysis_type = 1
    table = Create Table with column names: "Compare_" + clean_name2$, n_samples, "x reference_time comparison_time reference_intensity_db comparison_intensity_db level_error_db"
elsif analysis_type = 2
    table = Create Table with column names: "Compare_" + clean_name2$, n_samples, "x reference_time comparison_time reference_pitch_hz comparison_pitch_hz pitch_error_st"
else
    table = Create Table with column names: "Compare_" + clean_name2$, n_samples, "x reference_time comparison_time reference_pitch_hz comparison_pitch_hz pitch_error_st reference_intensity_db comparison_intensity_db level_error_db"
endif

for i from 1 to n_samples
    selectObject: table
    Set numeric value: i, "x", x#[i]
    Set numeric value: i, "reference_time", time1#[i]
    Set numeric value: i, "comparison_time", time2#[i]

    if pitch_enabled
        if pitch1_valid#[i]
            Set numeric value: i, "reference_pitch_hz", pitch1_hz#[i]
        else
            Set numeric value: i, "reference_pitch_hz", undefined
        endif
        if pitch2_valid#[i]
            Set numeric value: i, "comparison_pitch_hz", pitch2_hz#[i]
        else
            Set numeric value: i, "comparison_pitch_hz", undefined
        endif
        if pitch_pair_valid#[i]
            Set numeric value: i, "pitch_error_st", pitch_error_st#[i]
        else
            Set numeric value: i, "pitch_error_st", undefined
        endif
    endif

    if intensity_enabled
        if intensity_pair_valid#[i]
            Set numeric value: i, "reference_intensity_db", intensity1_db#[i]
            Set numeric value: i, "comparison_intensity_db", intensity2_db#[i]
            Set numeric value: i, "level_error_db", level_error_db#[i]
        else
            Set numeric value: i, "reference_intensity_db", undefined
            Set numeric value: i, "comparison_intensity_db", undefined
            Set numeric value: i, "level_error_db", undefined
        endif
    endif
endfor

# ===== INFO REPORT =====
writeInfoLine: "=== Pitch and Loudness Comparison v1.0 ==="
appendInfoLine: "Teacher / Reference: ", name1$, "   duration ", fixed$(duration1, 3), " s"
appendInfoLine: "Student / Comparison: ", name2$, "   duration ", fixed$(duration2, 3), " s"
if channels1 > 1
    appendInfoLine: "Reference analysis channel: ", analysis_channel1, " of ", channels1, " (strongest RMS)"
endif
if channels2 > 1
    appendInfoLine: "Comparison analysis channel: ", analysis_channel2, " of ", channels2, " (strongest RMS)"
endif
if alignment = 1
    appendInfoLine: "Alignment: relative progress (0-100%)"
else
    appendInfoLine: "Alignment: elapsed time from each Sound start; common duration ", fixed$(common_duration, 3), " s"
endif
appendInfoLine: "Samples compared: ", n_samples, "   requested step ", fixed$(time_step_s, 4), " s"

if pitch_enabled
    appendInfoLine: ""
    appendInfoLine: "=== PITCH ==="
    appendInfoLine: "Paired voiced samples: ", paired_pitch_count, " / ", n_samples, " (", fixed$(pitch_overlap_percent, 1), "%)"
    appendInfoLine: "Voicing mismatch: ", voicing_mismatch_count, " / ", n_samples, " (", fixed$(voicing_mismatch_percent, 1), "%)"
    if paired_pitch_count > 0
        appendInfoLine: "Mean signed pitch offset (Comparison - Reference): ", fixed$(mean_pitch_offset_st, 3), " st"
        appendInfoLine: "Pitch MAE: ", fixed$(pitch_mae_st, 3), " st   RMS: ", fixed$(pitch_rms_st, 3), " st   Max: ", fixed$(max_pitch_abs, 3), " st"
        appendInfoLine: "Centred contour MAE: ", fixed$(pitch_contour_mae_st, 3), " st"
        if pitch_correlation <> undefined
            appendInfoLine: "Pitch contour correlation: ", fixed$(pitch_correlation, 3)
        else
            appendInfoLine: "Pitch contour correlation: undefined (insufficient contour variance)"
        endif
    else
        appendInfoLine: "No paired voiced samples; pitch-distance metrics are unavailable."
    endif
endif

if intensity_enabled
    appendInfoLine: ""
    appendInfoLine: "=== INTENSITY / LEVEL ==="
    appendInfoLine: "Paired valid samples: ", paired_intensity_count, " / ", n_samples
    if paired_intensity_count > 0
        appendInfoLine: "Mean signed level offset (Comparison - Reference): ", fixed$(mean_level_offset_db, 3), " dB"
        appendInfoLine: "Raw level MAE: ", fixed$(level_mae_db, 3), " dB   RMS: ", fixed$(level_rms_db, 3), " dB   Max: ", fixed$(max_level_abs, 3), " dB"
        appendInfoLine: "Centred intensity-contour MAE: ", fixed$(level_contour_mae_db, 3), " dB"
        if level_correlation <> undefined
            appendInfoLine: "Intensity contour correlation: ", fixed$(level_correlation, 3)
        else
            appendInfoLine: "Intensity contour correlation: undefined (insufficient contour variance)"
        endif
    else
        appendInfoLine: "No paired valid intensity samples."
    endif
endif

# ===== VISUALIZATION =====
if draw_visualization
    display1$ = replace$(name1$, "_", " ", 0)
    display2$ = replace$(name2$, "_", " ", 0)
    if alignment = 1
        x_min = 0
        x_max = 100
        x_label$ = "Relative progress (%)"
        alignment_label$ = "relative progress"
    else
        x_min = 0
        x_max = common_duration
        x_label$ = "Elapsed time (s)"
        alignment_label$ = "elapsed time"
    endif
    if x_max <= x_min
        x_max = x_min + 1
    endif

    Erase all

    # Main title and metadata live in separate strips.
    Select outer viewport: 0, 8, 0.00, 0.38
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.55, "half", "##Pitch + Loudness Comparison##"

    Select outer viewport: 0, 8, 0.40, 0.72
    Axes: 0, 1, 0, 1
    Font size: 8
    Text: 0.5, "centre", 0.58, "half", display1$ + "  vs  " + display2$ + "  |  " + alignment_label$

    # -------- Pitch trajectories --------
    if pitch_enabled
        pitch_plot_min = 1e30
        pitch_plot_max = -1e30
        for i from 1 to n_samples
            if pitch1_valid#[i]
                pitch_plot_min = min(pitch_plot_min, pitch1_st#[i])
                pitch_plot_max = max(pitch_plot_max, pitch1_st#[i])
            endif
            if pitch2_valid#[i]
                pitch_plot_min = min(pitch_plot_min, pitch2_st#[i])
                pitch_plot_max = max(pitch_plot_max, pitch2_st#[i])
            endif
        endfor
        if pitch_plot_max <= pitch_plot_min or pitch_plot_min > 1e20
            pitch_plot_min = -12
            pitch_plot_max = 12
        endif
        pitch_pad = max(1, 0.08 * (pitch_plot_max - pitch_plot_min))
        pitch_plot_min = pitch_plot_min - pitch_pad
        pitch_plot_max = pitch_plot_max + pitch_pad

        Select outer viewport: 0, 8, 0.82, 2.95
        Select inner viewport: 0.78, 7.55, 1.10, 2.78
        Axes: x_min, x_max, pitch_plot_min, pitch_plot_max
        Paint rectangle: "{0.97, 0.97, 0.98}", x_min, x_max, pitch_plot_min, pitch_plot_max
        Colour: "{0.20, 0.38, 0.72}"
        Line width: 1.5
        for i from 2 to n_samples
            if pitch1_valid#[i - 1] and pitch1_valid#[i]
                Draw line: x#[i - 1], pitch1_st#[i - 1], x#[i], pitch1_st#[i]
            endif
        endfor
        Colour: "{0.78, 0.28, 0.22}"
        for i from 2 to n_samples
            if pitch2_valid#[i - 1] and pitch2_valid#[i]
                Draw line: x#[i - 1], pitch2_st#[i - 1], x#[i], pitch2_st#[i]
            endif
        endfor
        Select inner viewport: 0.78, 7.55, 1.10, 2.78
        Axes: x_min, x_max, pitch_plot_min, pitch_plot_max
        Colour: "Black"
        Line width: 1
        Draw inner box
        Font size: 7
        Marks left: 4, "yes", "yes", "no"
        Text left: "yes", "Semitones re A4"

        Select outer viewport: 0.78, 7.55, 0.83, 1.05
        Axes: 0, 1, 0, 1
        Font size: 9
        Text: 0.5, "centre", 0.58, "half", "##Pitch trajectories##   blue=Reference   red=Comparison"
    endif

    # -------- Intensity trajectories --------
    if intensity_enabled
        intensity_plot_min = 1e30
        intensity_plot_max = -1e30
        for i from 1 to n_samples
            if intensity_pair_valid#[i]
                intensity_plot_min = min(intensity_plot_min, min(intensity1_db#[i], intensity2_db#[i]))
                intensity_plot_max = max(intensity_plot_max, max(intensity1_db#[i], intensity2_db#[i]))
            endif
        endfor
        if intensity_plot_max <= intensity_plot_min or intensity_plot_min > 1e20
            intensity_plot_min = 20
            intensity_plot_max = 80
        endif
        intensity_pad = max(2, 0.08 * (intensity_plot_max - intensity_plot_min))
        intensity_plot_min = intensity_plot_min - intensity_pad
        intensity_plot_max = intensity_plot_max + intensity_pad

        Select outer viewport: 0, 8, 3.08, 5.20
        Select inner viewport: 0.78, 7.55, 3.36, 5.03
        Axes: x_min, x_max, intensity_plot_min, intensity_plot_max
        Paint rectangle: "{0.97, 0.97, 0.98}", x_min, x_max, intensity_plot_min, intensity_plot_max
        Colour: "{0.20, 0.38, 0.72}"
        Line width: 1.5
        for i from 2 to n_samples
            if intensity_pair_valid#[i - 1] and intensity_pair_valid#[i]
                Draw line: x#[i - 1], intensity1_db#[i - 1], x#[i], intensity1_db#[i]
            endif
        endfor
        Colour: "{0.78, 0.28, 0.22}"
        for i from 2 to n_samples
            if intensity_pair_valid#[i - 1] and intensity_pair_valid#[i]
                Draw line: x#[i - 1], intensity2_db#[i - 1], x#[i], intensity2_db#[i]
            endif
        endfor
        Select inner viewport: 0.78, 7.55, 3.36, 5.03
        Axes: x_min, x_max, intensity_plot_min, intensity_plot_max
        Colour: "Black"
        Line width: 1
        Draw inner box
        Font size: 7
        Marks left: 4, "yes", "yes", "no"
        Text left: "yes", "Intensity (dB)"
        Marks bottom: 5, "yes", "yes", "no"
        Text bottom: "yes", x_label$

        Select outer viewport: 0.78, 7.55, 3.09, 3.31
        Axes: 0, 1, 0, 1
        Font size: 9
        Text: 0.5, "centre", 0.58, "half", "##Intensity trajectories##   blue=Reference   red=Comparison"
    endif

    # If pitch is the only analysis, give its main panel an x-axis label.
    if pitch_enabled and not intensity_enabled
        Select inner viewport: 0.78, 7.55, 1.10, 2.78
        Axes: x_min, x_max, pitch_plot_min, pitch_plot_max
        Font size: 7
        Marks bottom: 5, "yes", "yes", "no"
        Text bottom: "yes", x_label$
    endif

    # -------- Signed error panels --------
    if pitch_enabled
        if intensity_enabled
            p_err_left = 0.72
            p_err_right = 3.78
        else
            p_err_left = 0.78
            p_err_right = 7.55
        endif
        p_err_max = max(1, max_pitch_abs * 1.08)
        Select outer viewport: p_err_left, p_err_right, 5.42, 6.78
        Select inner viewport: p_err_left + 0.32, p_err_right - 0.12, 5.72, 6.62
        Axes: x_min, x_max, -p_err_max, p_err_max
        Paint rectangle: "{0.98, 0.98, 0.98}", x_min, x_max, -p_err_max, p_err_max
        Colour: "{0.60, 0.60, 0.62}"
        Dotted line
        Draw line: x_min, 0, x_max, 0
        Solid line
        Colour: "{0.45, 0.25, 0.62}"
        Line width: 1.2
        for i from 2 to n_samples
            if pitch_pair_valid#[i - 1] and pitch_pair_valid#[i]
                Draw line: x#[i - 1], pitch_error_st#[i - 1], x#[i], pitch_error_st#[i]
            endif
        endfor
        Select inner viewport: p_err_left + 0.32, p_err_right - 0.12, 5.72, 6.62
        Axes: x_min, x_max, -p_err_max, p_err_max
        Colour: "Black"
        Line width: 1
        Draw inner box
        Font size: 6
        Marks left: 3, "yes", "yes", "no"
        Select outer viewport: p_err_left + 0.05, p_err_right - 0.05, 5.43, 5.68
        Axes: 0, 1, 0, 1
        Font size: 8
        Text: 0.5, "centre", 0.55, "half", "##Signed pitch error (st)##   + = Comparison higher"
    endif

    if intensity_enabled
        if pitch_enabled
            l_err_left = 4.18
            l_err_right = 7.58
        else
            l_err_left = 0.78
            l_err_right = 7.55
        endif
        l_err_max = max(1, max_level_abs * 1.08)
        Select outer viewport: l_err_left, l_err_right, 5.42, 6.78
        Select inner viewport: l_err_left + 0.32, l_err_right - 0.12, 5.72, 6.62
        Axes: x_min, x_max, -l_err_max, l_err_max
        Paint rectangle: "{0.98, 0.98, 0.98}", x_min, x_max, -l_err_max, l_err_max
        Colour: "{0.60, 0.60, 0.62}"
        Dotted line
        Draw line: x_min, 0, x_max, 0
        Solid line
        Colour: "{0.20, 0.52, 0.48}"
        Line width: 1.2
        for i from 2 to n_samples
            if intensity_pair_valid#[i - 1] and intensity_pair_valid#[i]
                Draw line: x#[i - 1], level_error_db#[i - 1], x#[i], level_error_db#[i]
            endif
        endfor
        Select inner viewport: l_err_left + 0.32, l_err_right - 0.12, 5.72, 6.62
        Axes: x_min, x_max, -l_err_max, l_err_max
        Colour: "Black"
        Line width: 1
        Draw inner box
        Font size: 6
        Marks left: 3, "yes", "yes", "no"
        Select outer viewport: l_err_left + 0.05, l_err_right - 0.05, 5.43, 5.68
        Axes: 0, 1, 0, 1
        Font size: 8
        Text: 0.5, "centre", 0.55, "half", "##Signed level error (dB)##   + = Comparison louder"
    endif

    # -------- Summary strip --------
    Select outer viewport: 0, 8, 6.96, 7.92
    Select inner viewport: 0.50, 7.55, 7.03, 7.84
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Select inner viewport: 0.50, 7.55, 7.03, 7.84
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Font size: 9
    Text: 0.02, "left", 0.78, "half", "##Comparison summary##"
    Font size: 8
    if pitch_enabled and intensity_enabled
        Text: 0.02, "left", 0.48, "half", "Pitch offset " + fixed$(mean_pitch_offset_st, 2) + " st   MAE " + fixed$(pitch_mae_st, 2) + "   centred MAE " + fixed$(pitch_contour_mae_st, 2) + "   voicing mismatch " + fixed$(voicing_mismatch_percent, 1) + "%"
        Text: 0.02, "left", 0.19, "half", "Level offset " + fixed$(mean_level_offset_db, 2) + " dB   MAE " + fixed$(level_mae_db, 2) + "   centred MAE " + fixed$(level_contour_mae_db, 2) + " dB"
    elsif pitch_enabled
        Text: 0.02, "left", 0.38, "half", "Offset " + fixed$(mean_pitch_offset_st, 2) + " st   MAE " + fixed$(pitch_mae_st, 2) + "   centred MAE " + fixed$(pitch_contour_mae_st, 2) + "   voicing mismatch " + fixed$(voicing_mismatch_percent, 1) + "%"
    else
        Text: 0.02, "left", 0.38, "half", "Level offset " + fixed$(mean_level_offset_db, 2) + " dB   MAE " + fixed$(level_mae_db, 2) + "   centred MAE " + fixed$(level_contour_mae_db, 2) + " dB"
    endif
    Select inner viewport: 0.50, 7.55, 7.03, 7.84
    Axes: 0, 1, 0, 1
    Draw rectangle: 0, 1, 0, 1
endif

# ===== CLEANUP =====
if pitch_enabled
    removeObject: pitch1, pitch2
endif
if intensity_enabled
    removeObject: intensity1, intensity2
endif
if analysis1_is_copy
    removeObject: analysis1
endif
if analysis2_is_copy
    removeObject: analysis2
endif

selectObject: sound1
plusObject: sound2
plusObject: table
appendInfoLine: ""
appendInfoLine: "Created Table: Compare_", clean_name2$
appendInfoLine: "Done."
