# ============================================================
# Praat AudioTools - Brightness Analyzer
# Author: Shai Cohen
# Reviewed revision: v1.1 (2026)
#
# Measurement-first revision of BrightnessClassifier.praat.
# Raw continuous descriptors are primary; threshold categories are secondary.
# ============================================================

clearinfo

number_of_selected_sounds = numberOfSelected("Sound")
if number_of_selected_sounds = 0
    exitScript: "Please select at least one Sound object first."
endif

for index to number_of_selected_sounds
    sound'index' = selected("Sound", index)
endfor

form Brightness Analyzer v1.1
    comment === Reference preset (classification only) ===
    optionmenu Preset 3
        option Custom
        option Speech
        option Music
        option Percussion
        option Ambient
        option Bright sources
    comment === Frequency regions ===
    positive Bass_upper_Hz 200
    positive Low_mid_upper_Hz 800
    positive High_mid_upper_Hz 4000
    positive Analysis_high_Hz 12000
    positive HF_split_Hz 2000
    comment === Reference thresholds for centroid categories ===
    positive Threshold_very_dark_Hz 300
    positive Threshold_dark_Hz 600
    positive Threshold_medium_Hz 1200
    positive Threshold_bright_Hz 2000
    comment === Temporal measurement ===
    positive Time_step_s 0.05
    positive Frame_window_s 0.04
    positive Silence_gate_below_peak_dB 40
    positive Rolloff_percent 85
    boolean Time_varying_measurement 1
    boolean Draw_visualization 1
endform

# Presets alter reference regions/thresholds only; the raw measurements remain raw.
if preset = 2
    bass_upper_Hz = 250
    low_mid_upper_Hz = 1000
    high_mid_upper_Hz = 4000
    analysis_high_Hz = 8000
    hf_split_Hz = 2000
    threshold_very_dark_Hz = 400
    threshold_dark_Hz = 700
    threshold_medium_Hz = 1100
    threshold_bright_Hz = 1600
    presetName$ = "Speech"
elsif preset = 3
    bass_upper_Hz = 200
    low_mid_upper_Hz = 800
    high_mid_upper_Hz = 4000
    analysis_high_Hz = 12000
    hf_split_Hz = 2000
    threshold_very_dark_Hz = 300
    threshold_dark_Hz = 600
    threshold_medium_Hz = 1200
    threshold_bright_Hz = 2000
    presetName$ = "Music"
elsif preset = 4
    bass_upper_Hz = 150
    low_mid_upper_Hz = 500
    high_mid_upper_Hz = 3000
    analysis_high_Hz = 10000
    hf_split_Hz = 2000
    threshold_very_dark_Hz = 500
    threshold_dark_Hz = 1000
    threshold_medium_Hz = 2000
    threshold_bright_Hz = 3500
    presetName$ = "Percussion"
elsif preset = 5
    bass_upper_Hz = 300
    low_mid_upper_Hz = 1200
    high_mid_upper_Hz = 5000
    analysis_high_Hz = 10000
    hf_split_Hz = 2000
    threshold_very_dark_Hz = 200
    threshold_dark_Hz = 400
    threshold_medium_Hz = 800
    threshold_bright_Hz = 1400
    presetName$ = "Ambient"
elsif preset = 6
    bass_upper_Hz = 200
    low_mid_upper_Hz = 600
    high_mid_upper_Hz = 3000
    analysis_high_Hz = 15000
    hf_split_Hz = 2500
    threshold_very_dark_Hz = 600
    threshold_dark_Hz = 1200
    threshold_medium_Hz = 2200
    threshold_bright_Hz = 3500
    presetName$ = "BrightSources"
else
    presetName$ = "Custom"
endif

if bass_upper_Hz <= 20
    exitScript: "Bass upper frequency must be above 20 Hz."
endif
if low_mid_upper_Hz <= bass_upper_Hz
    exitScript: "Low-mid upper frequency must exceed bass upper frequency."
endif
if high_mid_upper_Hz <= low_mid_upper_Hz
    exitScript: "High-mid upper frequency must exceed low-mid upper frequency."
endif
if analysis_high_Hz <= high_mid_upper_Hz
    exitScript: "Analysis high frequency must exceed the high-mid boundary."
endif
if hf_split_Hz <= 20 or hf_split_Hz >= analysis_high_Hz
    exitScript: "HF split must lie inside the analysis band."
endif
if threshold_very_dark_Hz >= threshold_dark_Hz or threshold_dark_Hz >= threshold_medium_Hz or threshold_medium_Hz >= threshold_bright_Hz
    exitScript: "Brightness thresholds must increase from very-dark to bright."
endif
if rolloff_percent <= 0 or rolloff_percent >= 100
    exitScript: "Rolloff percent must be between 0 and 100."
endif

# Fixed frequency resolution for global descriptors. This avoids dependence on
# whole-file FFT bin spacing when files have different durations.
descriptor_band_Hz = 20
time_band_Hz = 100
max_time_frames = 300
minimum_frequency_Hz = 20

procedure trimArray: .data#, .count
    if .count <= 0
        .result# = zero#(0)
    else
        .result# = zero#(.count)
        for .i to .count
            .result#[.i] = .data#[.i]
        endfor
    endif
endproc

procedure quantileSorted: .data#, .q
    .n = size(.data#)
    if .n = 0
        .result = undefined
    elsif .n = 1
        .result = .data#[1]
    else
        .pos = 1 + .q * (.n - 1)
        .lo = floor(.pos)
        .hi = ceiling(.pos)
        if .lo = .hi
            .result = .data#[.lo]
        else
            .frac = .pos - .lo
            .result = .data#[.lo] + .frac * (.data#[.hi] - .data#[.lo])
        endif
    endif
endproc

procedure formatValue: .value, .decimals
    if .value = undefined
        .result$ = "NA"
    else
        .result$ = fixed$(.value, .decimals)
    endif
endproc

procedure categoryFromCentroid: .centroid
    if .centroid = undefined
        .result$ = "unavailable"
    elsif .centroid < threshold_very_dark_Hz
        .result$ = "very_dark"
    elsif .centroid < threshold_dark_Hz
        .result$ = "dark"
    elsif .centroid < threshold_medium_Hz
        .result$ = "medium"
    elsif .centroid < threshold_bright_Hz
        .result$ = "bright"
    else
        .result$ = "very_bright"
    endif
endproc

# Result arrays retained for batch comparison visualization.
duration_values# = zero#(number_of_selected_sounds)
channel_values# = zero#(number_of_selected_sounds)
centroid_values# = zero#(number_of_selected_sounds)
spread_values# = zero#(number_of_selected_sounds)
rolloff_values# = zero#(number_of_selected_sounds)
hf_percent_values# = zero#(number_of_selected_sounds)
hf_ratio_values# = zero#(number_of_selected_sounds)
slope_values# = zero#(number_of_selected_sounds)
crest_values# = zero#(number_of_selected_sounds)
temporal_median_values# = zero#(number_of_selected_sounds)
temporal_iqr_values# = zero#(number_of_selected_sounds)
bright_time_values# = zero#(number_of_selected_sounds)
coverage_values# = zero#(number_of_selected_sounds)
motion_values# = zero#(number_of_selected_sounds)

resultsTable = Create Table with column names: "Brightness_Measurements", number_of_selected_sounds,
    ... "SoundName Duration_s AnalysisChannel Centroid_Hz Spread_Hz Rolloff_Hz HF_Energy_percent HF_to_Low_dB SpectralSlope_dB_per_oct CrestFactor TemporalCentroidMedian_Hz TemporalCentroidIQR_Hz BrightOrAboveTime_percent ValidFrameCoverage_percent CentroidMotion_Hz_per_s Category"

appendInfoLine: "Brightness Analyzer v1.1"
appendInfoLine: "========================"
appendInfoLine: "Raw descriptors are primary; category labels are threshold-based references only."
appendInfoLine: "Global spectrum uses fixed ", descriptor_band_Hz, "-Hz bands. Temporal sampling spans the full Sound."
appendInfoLine: "Silence gate: ", fixed$(silence_gate_below_peak_dB, 1), " dB below the Sound's peak intensity."
appendInfoLine: ""

for s from 1 to number_of_selected_sounds
    source_sound = sound's'
    selectObject: source_sound
    sound_name$ = selected$("Sound")
    duration = Get total duration
    sound_tmin = Get start time
    sound_tmax = Get end time
    sample_rate = Get sampling frequency
    nyquist = sample_rate / 2
    n_channels = Get number of channels

    # Representative analysis channel: strongest RMS channel avoids stereo phase cancellation.
    analysis_sound = source_sound
    analysis_is_copy = 0
    analysis_channel = 1
    if n_channels > 1
        best_rms = -1
        for ch from 1 to n_channels
            selectObject: source_sound
            tmp_channel = Extract one channel: ch
            channel_rms = Get root-mean-square: 0, 0
            if channel_rms > best_rms
                best_rms = channel_rms
                analysis_channel = ch
            endif
            removeObject: tmp_channel
        endfor
        selectObject: source_sound
        analysis_sound = Extract one channel: analysis_channel
        analysis_is_copy = 1
    endif

    effective_high_Hz = min(analysis_high_Hz, nyquist * 0.98)
    if effective_high_Hz <= minimum_frequency_Hz + descriptor_band_Hz
        if analysis_is_copy
            removeObject: analysis_sound
        endif
        exitScript: "Nyquist frequency is too low for the requested brightness analysis."
    endif

    # ---------- WHOLE-SOUND SPECTRUM ----------
    selectObject: analysis_sound
    spectrum = To Spectrum: "yes"
    nBins = object[spectrum].nx
    binWidth = object[spectrum].dx

    n_descriptor_bands = max(1, ceiling(effective_high_Hz / descriptor_band_Hz))
    band_power# = zero#(n_descriptor_bands)
    for b from 1 to nBins
        selectObject: spectrum
        re = Get real value in bin: b
        im = Get imaginary value in bin: b
        p = re * re + im * im
        f = (b - 1) * binWidth
        if f >= minimum_frequency_Hz and f <= effective_high_Hz
            band = floor(f / descriptor_band_Hz) + 1
            band = max(1, min(n_descriptor_bands, band))
            band_power#[band] = band_power#[band] + p
        endif
    endfor

    total_power = 0
    weighted_frequency_sum = 0
    max_band_power = 0
    low_power = 0
    high_power = 0
    bass_power = 0
    low_mid_power = 0
    high_mid_power = 0
    top_power = 0

    for band from 1 to n_descriptor_bands
        f = (band - 0.5) * descriptor_band_Hz
        p = band_power#[band]
        if f >= minimum_frequency_Hz and f <= effective_high_Hz
            total_power = total_power + p
            weighted_frequency_sum = weighted_frequency_sum + f * p
            if p > max_band_power
                max_band_power = p
            endif
            if f < hf_split_Hz
                low_power = low_power + p
            else
                high_power = high_power + p
            endif
            if f < bass_upper_Hz
                bass_power = bass_power + p
            elsif f < low_mid_upper_Hz
                low_mid_power = low_mid_power + p
            elsif f < high_mid_upper_Hz
                high_mid_power = high_mid_power + p
            else
                top_power = top_power + p
            endif
        endif
    endfor

    centroid = undefined
    spread = undefined
    rolloff = undefined
    hf_percent = undefined
    hf_ratio_dB = undefined
    spectral_slope = undefined

    if total_power > 1e-30
        centroid = weighted_frequency_sum / total_power
        variance_sum = 0
        for band from 1 to n_descriptor_bands
            f = (band - 0.5) * descriptor_band_Hz
            p = band_power#[band]
            if f >= minimum_frequency_Hz and f <= effective_high_Hz
                variance_sum = variance_sum + p * (f - centroid) ^ 2
            endif
        endfor
        spread = sqrt(variance_sum / total_power)

        target_power = total_power * rolloff_percent / 100
        cumulative_power = 0
        found_rolloff = 0
        for band from 1 to n_descriptor_bands
            f = (band - 0.5) * descriptor_band_Hz
            if f >= minimum_frequency_Hz and f <= effective_high_Hz and found_rolloff = 0
                cumulative_power = cumulative_power + band_power#[band]
                if cumulative_power >= target_power
                    rolloff = f
                    found_rolloff = 1
                endif
            endif
        endfor

        hf_percent = 100 * high_power / total_power
        if low_power > 1e-30 and high_power > 1e-30
            hf_ratio_dB = 10 * ln(high_power / low_power) / ln(10)
        elsif high_power <= 1e-30
            hf_ratio_dB = -120
        else
            hf_ratio_dB = 120
        endif

        # Least-squares spectral slope in dB per octave. Very weak bands below
        # -60 dB relative to the strongest descriptor band are excluded.
        slope_n = 0
        slope_sx = 0
        slope_sy = 0
        slope_sxx = 0
        slope_sxy = 0
        slope_floor = max_band_power * 1e-6
        for band from 1 to n_descriptor_bands
            f = (band - 0.5) * descriptor_band_Hz
            p = band_power#[band]
            if f >= max(80, minimum_frequency_Hz) and f <= effective_high_Hz and p >= slope_floor and p > 0
                x = ln(f) / ln(2)
                y = 10 * ln(p) / ln(10)
                slope_n = slope_n + 1
                slope_sx = slope_sx + x
                slope_sy = slope_sy + y
                slope_sxx = slope_sxx + x * x
                slope_sxy = slope_sxy + x * y
            endif
        endfor
        slope_denom = slope_n * slope_sxx - slope_sx * slope_sx
        if slope_n >= 3 and abs(slope_denom) > 1e-12
            spectral_slope = (slope_n * slope_sxy - slope_sx * slope_sy) / slope_denom
        endif
    endif

    selectObject: analysis_sound
    rms = Get root-mean-square: 0, 0
    absolute_peak = Get absolute extremum: sound_tmin, sound_tmax, "Sinc70"
    if rms > 0 and absolute_peak <> undefined
        crest = absolute_peak / rms
    else
        crest = undefined
    endif

    @categoryFromCentroid: centroid
    category$ = categoryFromCentroid.result$

    # ---------- TIME-VARYING MEASUREMENT ----------
    temporal_median = undefined
    temporal_iqr = undefined
    bright_time_percent = undefined
    coverage_percent = undefined
    centroid_motion = undefined
    time_centroid# = zero#(0)
    time_point# = zero#(0)
    time_valid# = zero#(0)
    n_time_frames = 0

    if time_varying_measurement
        selectObject: analysis_sound
        intensity = To Intensity: 50, 0, "yes"
        intensity_peak = Get maximum: sound_tmin, sound_tmax, "Parabolic"
        if intensity_peak = undefined
            intensity_peak = -300
        endif
        gate_dB = intensity_peak - silence_gate_below_peak_dB

        requested_frames = floor(duration / time_step_s) + 1
        n_time_frames = max(2, min(max_time_frames, requested_frames))
        if n_time_frames > 1
            actual_time_step = duration / (n_time_frames - 1)
        else
            actual_time_step = duration
        endif

        time_centroid# = zero#(n_time_frames)
        time_point# = zero#(n_time_frames)
        time_valid# = zero#(n_time_frames)
        valid_centroids# = zero#(n_time_frames)
        valid_count = 0
        bright_count = 0
        motion_sum = 0
        motion_time = 0
        previous_valid = 0
        previous_centroid = 0
        previous_time = 0

        for frame from 1 to n_time_frames
            frame_mid = sound_tmin + (frame - 1) * actual_time_step
            frame_mid = min(sound_tmax, max(sound_tmin, frame_mid))
            time_point#[frame] = frame_mid

            selectObject: intensity
            frame_intensity = Get value at time: frame_mid, "Cubic"
            active = 0
            if frame_intensity <> undefined
                if frame_intensity >= gate_dB
                    active = 1
                endif
            endif

            if active
                frame_start = max(sound_tmin, frame_mid - frame_window_s / 2)
                frame_end = min(sound_tmax, frame_mid + frame_window_s / 2)
                if frame_end > frame_start
                    selectObject: analysis_sound
                    frame_sound = Extract part: frame_start, frame_end, "Hanning", 1, "no"
                    frame_spectrum = To Spectrum: "yes"

                    frame_total = 0
                    frame_weighted = 0
                    f0 = minimum_frequency_Hz
                    while f0 < effective_high_Hz
                        f1 = min(effective_high_Hz, f0 + time_band_Hz)
                        selectObject: frame_spectrum
                        frame_band_energy = Get band energy: f0, f1
                        if frame_band_energy <> undefined and frame_band_energy > 0
                            fc = (f0 + f1) / 2
                            frame_total = frame_total + frame_band_energy
                            frame_weighted = frame_weighted + fc * frame_band_energy
                        endif
                        f0 = f1
                    endwhile

                    if frame_total > 1e-30
                        frame_centroid = frame_weighted / frame_total
                        time_centroid#[frame] = frame_centroid
                        time_valid#[frame] = 1
                        valid_count = valid_count + 1
                        valid_centroids#[valid_count] = frame_centroid
                        if frame_centroid >= threshold_medium_Hz
                            bright_count = bright_count + 1
                        endif
                        if previous_valid
                            dt = frame_mid - previous_time
                            if dt > 0
                                motion_sum = motion_sum + abs(frame_centroid - previous_centroid)
                                motion_time = motion_time + dt
                            endif
                        endif
                        previous_valid = 1
                        previous_centroid = frame_centroid
                        previous_time = frame_mid
                    else
                        previous_valid = 0
                    endif

                    removeObject: frame_sound, frame_spectrum
                endif
            else
                previous_valid = 0
            endif
        endfor

        removeObject: intensity

        coverage_percent = 100 * valid_count / n_time_frames
        if valid_count > 0
            bright_time_percent = 100 * bright_count / valid_count
            @trimArray: valid_centroids#, valid_count
            valid_centroids# = trimArray.result#
            sorted_centroids# = sort#(valid_centroids#)
            @quantileSorted: sorted_centroids#, 0.25
            temporal_q25 = quantileSorted.result
            @quantileSorted: sorted_centroids#, 0.50
            temporal_median = quantileSorted.result
            @quantileSorted: sorted_centroids#, 0.75
            temporal_q75 = quantileSorted.result
            temporal_iqr = temporal_q75 - temporal_q25
        endif
        if motion_time > 0
            centroid_motion = motion_sum / motion_time
        endif
    endif

    duration_values#[s] = duration
    channel_values#[s] = analysis_channel
    centroid_values#[s] = centroid
    spread_values#[s] = spread
    rolloff_values#[s] = rolloff
    hf_percent_values#[s] = hf_percent
    hf_ratio_values#[s] = hf_ratio_dB
    slope_values#[s] = spectral_slope
    crest_values#[s] = crest
    temporal_median_values#[s] = temporal_median
    temporal_iqr_values#[s] = temporal_iqr
    bright_time_values#[s] = bright_time_percent
    coverage_values#[s] = coverage_percent
    motion_values#[s] = centroid_motion
    sound_names$[s] = sound_name$
    categories$[s] = category$

    selectObject: resultsTable
    Set string value: s, "SoundName", sound_name$
    Set numeric value: s, "Duration_s", duration
    Set numeric value: s, "AnalysisChannel", analysis_channel
    Set numeric value: s, "Centroid_Hz", centroid
    Set numeric value: s, "Spread_Hz", spread
    Set numeric value: s, "Rolloff_Hz", rolloff
    Set numeric value: s, "HF_Energy_percent", hf_percent
    Set numeric value: s, "HF_to_Low_dB", hf_ratio_dB
    Set numeric value: s, "SpectralSlope_dB_per_oct", spectral_slope
    Set numeric value: s, "CrestFactor", crest
    Set numeric value: s, "TemporalCentroidMedian_Hz", temporal_median
    Set numeric value: s, "TemporalCentroidIQR_Hz", temporal_iqr
    Set numeric value: s, "BrightOrAboveTime_percent", bright_time_percent
    Set numeric value: s, "ValidFrameCoverage_percent", coverage_percent
    Set numeric value: s, "CentroidMotion_Hz_per_s", centroid_motion
    Set string value: s, "Category", category$

    appendInfoLine: sound_name$, "  [ch ", analysis_channel, "]"
    @formatValue: centroid, 0
    appendInfoLine: "  Centroid: ", formatValue.result$, " Hz   category: ", category$
    @formatValue: spread, 0
    appendInfoLine: "  Spread: ", formatValue.result$, " Hz"
    @formatValue: rolloff, 0
    appendInfoLine: "  Rolloff ", fixed$(rolloff_percent, 0), "%: ", formatValue.result$, " Hz"
    @formatValue: hf_percent, 1
    hfText$ = formatValue.result$
    @formatValue: hf_ratio_dB, 2
    appendInfoLine: "  HF energy >= ", fixed$(hf_split_Hz, 0), " Hz: ", hfText$, "%   HF/low: ", formatValue.result$, " dB"
    @formatValue: spectral_slope, 2
    appendInfoLine: "  Spectral slope: ", formatValue.result$, " dB/oct"
    if time_varying_measurement
        @formatValue: temporal_median, 0
        medianText$ = formatValue.result$
        @formatValue: temporal_iqr, 0
        iqrText$ = formatValue.result$
        @formatValue: bright_time_percent, 1
        brightText$ = formatValue.result$
        @formatValue: coverage_percent, 1
        coverageText$ = formatValue.result$
        appendInfoLine: "  Temporal centroid median/IQR: ", medianText$, " / ", iqrText$, " Hz   bright-or-above time: ", brightText$, "%   coverage: ", coverageText$, "%"
    endif
    appendInfoLine: ""

    # ---------- SINGLE-SOUND MEASUREMENT VISUALIZATION ----------
    if draw_visualization and number_of_selected_sounds = 1
        Erase all
        displayName$ = replace$(sound_name$, "_", " ", 0)
        displayName$ = replace$(displayName$, "%", "pct", 0)

        # Title and metadata strips are separated to avoid text collisions.
        Select outer viewport: 0, 8, 0.00, 0.48
        Axes: 0, 1, 0, 1
        Font size: 14
        Colour: "Black"
        Text: 0.5, "centre", 0.62, "half", "##Brightness Analyzer##"

        Select outer viewport: 0, 8, 0.48, 0.82
        Axes: 0, 1, 0, 1
        Font size: 8
        Text: 0.5, "centre", 0.58, "half", displayName$ + "  |  preset " + presetName$ + "  |  channel " + string$(analysis_channel) + "  |  category is secondary"

        # Panel 1: measured whole-sound spectral shape, normalized to its own maximum.
        Select outer viewport: 0, 8, 0.90, 3.10
        Select inner viewport: 0.72, 7.45, 1.18, 2.88
        Axes: 0, 1, -68, 3
        Paint rectangle: "{0.98, 0.98, 0.98}", 0, 1, -68, 3
        min_log_f = ln(max(20, minimum_frequency_Hz))
        max_log_f = ln(effective_high_Hz)
        previous_x = undefined
        previous_y = undefined
        if max_band_power > 0
            for band from 1 to n_descriptor_bands
                f = (band - 0.5) * descriptor_band_Hz
                p = band_power#[band]
                if f >= minimum_frequency_Hz and f <= effective_high_Hz and p > 0
                    x = (ln(f) - min_log_f) / (max_log_f - min_log_f)
                    y = 10 * ln(p / max_band_power) / ln(10)
                    y = max(-60, min(0, y))
                    if previous_x <> undefined
                        Colour: "{0.22, 0.38, 0.68}"
                        Line width: 1.2
                        Draw line: previous_x, previous_y, x, y
                    endif
                    previous_x = x
                    previous_y = y
                endif
            endfor
        endif

        if centroid <> undefined and centroid > minimum_frequency_Hz
            cx = (ln(centroid) - min_log_f) / (max_log_f - min_log_f)
            cx = max(0, min(1, cx))
            Colour: "{0.78, 0.25, 0.20}"
            Dotted line
            Draw line: cx, -60, cx, 2
            Solid line
        endif
        if rolloff <> undefined and rolloff > minimum_frequency_Hz
            rx = (ln(rolloff) - min_log_f) / (max_log_f - min_log_f)
            rx = max(0, min(1, rx))
            Colour: "{0.25, 0.58, 0.32}"
            Dotted line
            Draw line: rx, -60, rx, 2
            Solid line
        endif

        Select inner viewport: 0.72, 7.45, 1.18, 2.88
        Axes: 0, 1, -68, 3
        Colour: "Black"
        Line width: 1
        Draw inner box
        Font size: 7
        Marks left every: 1, 20, "yes", "yes", "no"
        Text left: "yes", "Relative band power (dB)"

        # Manual logarithmic frequency labels.
        freqTicks# = {50, 100, 200, 500, 1000, 2000, 5000, 10000}
        for ti to 8
            tf = freqTicks#[ti]
            if ti = 1
                tickLabel$ = "50"
            elsif ti = 2
                tickLabel$ = "100"
            elsif ti = 3
                tickLabel$ = "200"
            elsif ti = 4
                tickLabel$ = "500"
            elsif ti = 5
                tickLabel$ = "1k"
            elsif ti = 6
                tickLabel$ = "2k"
            elsif ti = 7
                tickLabel$ = "5k"
            else
                tickLabel$ = "10k"
            endif
            if tf >= minimum_frequency_Hz and tf <= effective_high_Hz
                tx = (ln(tf) - min_log_f) / (max_log_f - min_log_f)
                Draw line: tx, -60, tx, -58.5
                Text: tx, "centre", -64.0, "half", tickLabel$
            endif
        endfor

        Select outer viewport: 0.72, 7.45, 0.92, 1.15
        Axes: 0, 1, 0, 1
        Font size: 9
        Text: 0.5, "centre", 0.60, "half", "##Measured spectral shape##   red=centroid   green=rolloff"

        # Panel 2: temporal centroid trajectory with silence-gated invalid gaps.
        if time_varying_measurement and n_time_frames >= 2
            temporal_min = effective_high_Hz
            temporal_max = minimum_frequency_Hz
            for frame from 1 to n_time_frames
                if time_valid#[frame] > 0
                    temporal_min = min(temporal_min, time_centroid#[frame])
                    temporal_max = max(temporal_max, time_centroid#[frame])
                endif
            endfor
            if temporal_max <= temporal_min
                temporal_min = max(minimum_frequency_Hz, threshold_very_dark_Hz * 0.5)
                temporal_max = min(effective_high_Hz, threshold_bright_Hz * 1.5)
            else
                temporal_pad = max(100, 0.12 * (temporal_max - temporal_min))
                temporal_min = max(minimum_frequency_Hz, temporal_min - temporal_pad)
                temporal_max = min(effective_high_Hz, temporal_max + temporal_pad)
            endif

            Select outer viewport: 0, 8, 3.20, 5.35
            Select inner viewport: 0.72, 7.45, 3.48, 5.12
            Axes: sound_tmin, sound_tmax, temporal_min, temporal_max
            Paint rectangle: "{0.98, 0.98, 0.98}", sound_tmin, sound_tmax, temporal_min, temporal_max

            thresholdValues# = {threshold_very_dark_Hz, threshold_dark_Hz, threshold_medium_Hz, threshold_bright_Hz}
            Colour: "{0.78, 0.78, 0.80}"
            Dotted line
            for ti to 4
                thresholdValue = thresholdValues#[ti]
                if thresholdValue > temporal_min and thresholdValue < temporal_max
                    Draw line: sound_tmin, thresholdValue, sound_tmax, thresholdValue
                endif
            endfor
            Solid line

            Colour: "{0.20, 0.42, 0.72}"
            Line width: 2
            for frame from 2 to n_time_frames
                if time_valid#[frame - 1] > 0 and time_valid#[frame] > 0
                    Draw line: time_point#[frame - 1], time_centroid#[frame - 1], time_point#[frame], time_centroid#[frame]
                endif
            endfor
            if temporal_median <> undefined and temporal_median > temporal_min and temporal_median < temporal_max
                Colour: "{0.25, 0.58, 0.32}"
                Dotted line
                Draw line: sound_tmin, temporal_median, sound_tmax, temporal_median
                Solid line
            endif

            Select inner viewport: 0.72, 7.45, 3.48, 5.12
            Axes: sound_tmin, sound_tmax, temporal_min, temporal_max
            Colour: "Black"
            Line width: 1
            Draw inner box
            Font size: 7
            Marks left: 4, "yes", "yes", "no"
            Marks bottom: 5, "yes", "yes", "no"
            Text left: "yes", "Centroid (Hz)"
            Text bottom: "yes", "Time (s)"

            Select outer viewport: 0.72, 7.45, 3.22, 3.45
            Axes: 0, 1, 0, 1
            Font size: 9
            Text: 0.5, "centre", 0.60, "half", "##Brightness trajectory##   silence-gated; green=temporal median"
        endif

        # Panel 3: true band energy percentages, summing to ~100% in the analysis band.
        if time_varying_measurement
            band_outer_top = 5.48
            band_inner_top = 5.78
            band_bottom = 6.82
        else
            band_outer_top = 3.30
            band_inner_top = 3.60
            band_bottom = 5.85
        endif
        Select outer viewport: 0, 4.05, band_outer_top, band_bottom
        Select inner viewport: 0.70, 3.75, band_inner_top, band_bottom - 0.18
        Axes: 0.5, 4.5, 0, 105
        Paint rectangle: "{0.98, 0.98, 0.98}", 0.5, 4.5, 0, 105
        if total_power > 0
            bass_pct = 100 * bass_power / total_power
            low_mid_pct = 100 * low_mid_power / total_power
            high_mid_pct = 100 * high_mid_power / total_power
            top_pct = 100 * top_power / total_power
        else
            bass_pct = 0
            low_mid_pct = 0
            high_mid_pct = 0
            top_pct = 0
        endif
        Paint rectangle: "{0.34, 0.43, 0.68}", 0.65, 1.35, 0, bass_pct
        Paint rectangle: "{0.38, 0.58, 0.52}", 1.65, 2.35, 0, low_mid_pct
        Paint rectangle: "{0.70, 0.60, 0.34}", 2.65, 3.35, 0, high_mid_pct
        Paint rectangle: "{0.76, 0.36, 0.32}", 3.65, 4.35, 0, top_pct
        Colour: "Black"
        Draw inner box
        Font size: 7
        Marks left every: 1, 25, "yes", "yes", "no"
        Text left: "yes", "Power (%)"
        Text: 1, "centre", -7, "half", "Bass"
        Text: 2, "centre", -7, "half", "Low-mid"
        Text: 3, "centre", -7, "half", "High-mid"
        Text: 4, "centre", -7, "half", "High"

        Select outer viewport: 0.70, 3.75, band_outer_top + 0.02, band_inner_top - 0.04
        Axes: 0, 1, 0, 1
        Font size: 9
        Text: 0.5, "centre", 0.60, "half", "##Energy distribution##"

        # Metrics/QC panel.
        Select outer viewport: 4.05, 8, band_outer_top, band_bottom
        Select inner viewport: 4.35, 7.65, band_inner_top, band_bottom - 0.18
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1
        Font size: 8
        Colour: "Black"
        Text: 0.04, "left", 0.88, "half", "##Measurement summary##"
        @formatValue: centroid, 0
        Text: 0.06, "left", 0.72, "half", "Centroid  " + formatValue.result$ + " Hz"
        @formatValue: rolloff, 0
        Text: 0.06, "left", 0.60, "half", "Rolloff  " + formatValue.result$ + " Hz"
        @formatValue: hf_percent, 1
        Text: 0.06, "left", 0.48, "half", "HF energy  " + formatValue.result$ + " %"
        @formatValue: spectral_slope, 2
        Text: 0.06, "left", 0.36, "half", "Slope  " + formatValue.result$ + " dB/oct"
        @formatValue: crest, 2
        Text: 0.06, "left", 0.24, "half", "Crest  " + formatValue.result$
        if time_varying_measurement
            @formatValue: coverage_percent, 1
            Text: 0.54, "left", 0.72, "half", "Coverage  " + formatValue.result$ + " %"
            @formatValue: temporal_iqr, 0
            Text: 0.54, "left", 0.60, "half", "Centroid IQR  " + formatValue.result$ + " Hz"
            @formatValue: bright_time_percent, 1
            Text: 0.54, "left", 0.48, "half", "Bright time  " + formatValue.result$ + " %"
            @formatValue: centroid_motion, 1
            Text: 0.54, "left", 0.36, "half", "Centroid motion  " + formatValue.result$ + " Hz/s"
        endif
        Font size: 7
        Text: 0.06, "left", 0.08, "half", "Category: " + category$ + " (threshold interpretation, not the measurement itself)"
        Draw rectangle: 0, 1, 0, 1

        # Bottom QC strip.
        Select outer viewport: 0, 8, 7.00, 7.92
        Select inner viewport: 0.48, 7.55, 7.10, 7.82
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
        Font size: 8
        Colour: "Black"
        Text: 0.02, "left", 0.66, "half", "Analysis band " + fixed$(minimum_frequency_Hz, 0) + "-" + fixed$(effective_high_Hz, 0) + " Hz   |   HF split " + fixed$(hf_split_Hz, 0) + " Hz   |   descriptor bands " + string$(descriptor_band_Hz) + " Hz"
        if time_varying_measurement
            Text: 0.02, "left", 0.28, "half", "Temporal frames " + string$(n_time_frames) + " spanning the full Sound   |   gate " + fixed$(silence_gate_below_peak_dB, 0) + " dB below peak intensity"
        else
            Text: 0.02, "left", 0.28, "half", "Temporal measurement disabled"
        endif
        Draw rectangle: 0, 1, 0, 1
    endif

    removeObject: spectrum
    if analysis_is_copy
        removeObject: analysis_sound
    endif
endfor

# ---------- MULTI-SOUND COMPARISON VISUALIZATION ----------
if draw_visualization and number_of_selected_sounds >= 2
    Erase all

    Select outer viewport: 0, 8, 0.00, 0.48
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.62, "half", "##Brightness Measurement Comparison##"

    Select outer viewport: 0, 8, 0.48, 0.82
    Axes: 0, 1, 0, 1
    Font size: 8
    Text: 0.5, "centre", 0.58, "half", string$(number_of_selected_sounds) + " Sounds  |  raw continuous descriptors  |  categories are threshold references"

    # Panel 1: centroid vs HF energy percentage. This compares two independent
    # brightness-related measurements instead of a single category label.
    centroid_min = 1e30
    centroid_max = -1e30
    hf_min = 1e30
    hf_max = -1e30
    valid_compare = 0
    for s to number_of_selected_sounds
        if centroid_values#[s] <> undefined and hf_percent_values#[s] <> undefined
            centroid_min = min(centroid_min, centroid_values#[s])
            centroid_max = max(centroid_max, centroid_values#[s])
            hf_min = min(hf_min, hf_percent_values#[s])
            hf_max = max(hf_max, hf_percent_values#[s])
            valid_compare = valid_compare + 1
        endif
    endfor
    if valid_compare > 0
        centroid_pad = max(100, 0.10 * max(1, centroid_max - centroid_min))
        hf_pad = max(2, 0.10 * max(1, hf_max - hf_min))
        x_min = max(0, centroid_min - centroid_pad)
        x_max = centroid_max + centroid_pad
        y_min = max(0, hf_min - hf_pad)
        y_max = min(100, hf_max + hf_pad)
        if y_max <= y_min
            y_max = min(100, y_min + 10)
        endif

        Select outer viewport: 0, 8, 0.95, 4.05
        Select inner viewport: 0.82, 7.45, 1.28, 3.82
        Axes: x_min, x_max, y_min, y_max
        Paint rectangle: "{0.98, 0.98, 0.98}", x_min, x_max, y_min, y_max
        for s to number_of_selected_sounds
            if centroid_values#[s] <> undefined and hf_percent_values#[s] <> undefined
                Colour: "{0.22, 0.38, 0.68}"
                Paint circle (mm): "{0.22, 0.38, 0.68}", centroid_values#[s], hf_percent_values#[s], 1.4
                Colour: "Black"
                Font size: 6
                label$ = replace$(sound_names$[s], "_", " ", 0)
                label$ = replace$(label$, "%", "pct", 0)
                label$ = left$(label$, 16)
                Text: centroid_values#[s], "left", hf_percent_values#[s], "bottom", label$
            endif
        endfor
        Colour: "Black"
        Draw inner box
        Font size: 7
        Marks left: 5, "yes", "yes", "no"
        Marks bottom: 5, "yes", "yes", "no"
        Text left: "yes", "HF energy (%)"
        Text bottom: "yes", "Spectral centroid (Hz)"

        Select outer viewport: 0.82, 7.45, 0.98, 1.24
        Axes: 0, 1, 0, 1
        Font size: 9
        Text: 0.5, "centre", 0.60, "half", "##Independent brightness evidence##   centroid vs high-frequency energy"
    endif

    # Panel 2: centroid and rolloff on the same Hz scale for each Sound.
    freq_max_compare = 0
    for s to number_of_selected_sounds
        if rolloff_values#[s] <> undefined
            freq_max_compare = max(freq_max_compare, rolloff_values#[s])
        endif
        if centroid_values#[s] <> undefined
            freq_max_compare = max(freq_max_compare, centroid_values#[s])
        endif
    endfor
    freq_max_compare = max(1000, freq_max_compare * 1.10)
    viz_rows = min(number_of_selected_sounds, 12)

    Select outer viewport: 0, 8, 4.20, 6.90
    Select inner viewport: 1.25, 7.45, 4.50, 6.68
    Axes: 0, freq_max_compare, 0, viz_rows + 1
    Paint rectangle: "{0.98, 0.98, 0.98}", 0, freq_max_compare, 0, viz_rows + 1
    for vr from 1 to viz_rows
        if viz_rows = 1
            actual_row = 1
        else
            actual_row = 1 + round((vr - 1) * (number_of_selected_sounds - 1) / (viz_rows - 1))
        endif
        y = viz_rows - vr + 0.5
        if centroid_values#[actual_row] <> undefined and rolloff_values#[actual_row] <> undefined
            Colour: "{0.72, 0.72, 0.74}"
            Line width: 2
            Draw line: centroid_values#[actual_row], y, rolloff_values#[actual_row], y
            Colour: "{0.78, 0.25, 0.20}"
            Paint circle (mm): "{0.78, 0.25, 0.20}", centroid_values#[actual_row], y, 1.2
            Colour: "{0.25, 0.58, 0.32}"
            Paint circle (mm): "{0.25, 0.58, 0.32}", rolloff_values#[actual_row], y, 1.2
        endif
        Colour: "Black"
        Font size: 6
        label$ = replace$(sound_names$[actual_row], "_", " ", 0)
        label$ = replace$(label$, "%", "pct", 0)
        label$ = left$(label$, 18)
        Text: 0.01 * freq_max_compare, "left", y, "half", label$
    endfor
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Marks bottom: 5, "yes", "yes", "no"
    Text bottom: "yes", "Frequency (Hz)"

    Select outer viewport: 1.25, 7.45, 4.23, 4.46
    Axes: 0, 1, 0, 1
    Font size: 9
    Text: 0.5, "centre", 0.60, "half", "##Centroid to rolloff span##   red=centroid   green=rolloff"

    Select outer viewport: 0, 8, 7.05, 7.92
    Select inner viewport: 0.48, 7.55, 7.14, 7.82
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    if number_of_selected_sounds > viz_rows
        displayText$ = "Comparison panel displays " + string$(viz_rows) + " evenly sampled Sounds of " + string$(number_of_selected_sounds)
    else
        displayText$ = "Comparison panel displays all " + string$(number_of_selected_sounds) + " Sounds"
    endif
    Text: 0.02, "left", 0.66, "half", displayText$ + "   |   all raw values are in Table Brightness Measurements"
    Text: 0.02, "left", 0.28, "half", "HF energy is integrated power above " + fixed$(hf_split_Hz, 0) + " Hz; centroid/rolloff use the same Nyquist-limited analysis band"
    Draw rectangle: 0, 1, 0, 1
endif

# Reselect useful output table only.
selectObject: resultsTable
appendInfoLine: "=== OUTPUT ==="
appendInfoLine: "Table Brightness_Measurements contains raw continuous descriptors and QC."
appendInfoLine: "Category is a threshold interpretation of centroid, not a substitute for the measurements."
appendInfoLine: "BrightOrAboveTime_percent uses centroid >= the Medium/Bright boundary and only valid silence-gated frames."
appendInfoLine: "Done."
