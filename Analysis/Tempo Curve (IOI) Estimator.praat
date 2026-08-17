# ============================================================
# Praat AudioTools - Tempo_Curve_IOI_Estimator.praat  
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.6.3 (2026) - Fast Intensity default + title spacing
# License: MIT License
#
# Description:
#   Tempo Curve (IOI) Estimator with autocorrelation-based
#   periodicity detection and octave disambiguation.
#
# Changelog v0.6.3:
#   - Intensity slope + autocorrelation is now the default and is labelled
#     Fast / Recommended in the form.
#   - Main visualization title and subtitle now use independent title strips
#     to prevent text collisions across Praat font/rendering configurations.
#   - Analysis algorithms and numerical settings are otherwise unchanged.
#
# Changelog v0.6.2:
#   - Intensity method now estimates global tempo from autocorrelation of the full
#     intensity-slope ODF instead of adjacent-onset IOI histogram alone.
#   - Local Intensity tempo remains IOI-based, but is anchored to the stabilized
#     global tempo through the existing metrical-continuity scoring.
#   - Spectral-flux + IOI method remains unchanged.
#
# Changelog v0.6.1:
#   - Visualization-only polish: separated panel titles from data viewports,
#     increased main title/subtitle spacing, and lifted summary text slightly.
#   - Analysis, tempo estimation, onset detection, and performance are unchanged.
#
# Changelog v0.6:
#   - Nyquist-safe analysis: downsample target raised to 22050 Hz and all
#     analysis/filter limits are derived from the actual working sample rate.
#   - Stereo/multichannel analysis uses the strongest-RMS channel instead of
#     an implicit fold-down that could cancel anti-phase material.
#   - Spectral flux is computed from magnitude (sqrt power) changes, with
#     actual Spectrogram/Matrix time and frequency geometry.
#   - Global autocorrelation no longer gets blindly remapped after estimation;
#     octave/subdivision preference is now a weak tie-break, not the main score.
#   - Local tempo continuity uses ratio/log distance and a restricted set of
#     musically plausible metrical alternatives.
#   - Long-file analysis uses an adaptive ODF time step and decimated global ACF.
#   - Non-zero Sound origins are handled explicitly.
#   - Detected points are labelled as onsets (not beats) in the TextGrid.
#   - Tempo table now includes relative time, normalized confidence, and IOI support.
#   - Visualization rebuilt as an 8x8 mechanism view: waveform/onsets, actual ODF,
#     tempo/support, and concise QC summary with explicit symmetric waveform scale.
#
# Changelog v0.5:
#   - Added autocorrelation on ODF for robust period detection
#   - Added "prefer lower BPM" bias for subdivision-heavy material
#   - Fixed octave doubling bug (180 vs 90 BPM)
#   - Added tempo prior weighting
# ============================================================

# Input validation
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")

form Tempo Curve Estimator v0.6.3
    comment === Presets ===
    optionmenu Preset: 1
        option Custom
        option Pop/Rock (90-180 BPM)
        option Classical (40-120 BPM)
        option Electronic (100-160 BPM)
        option Jazz (60-200 BPM)
        option Slow Ballad (50-80 BPM)
        option Fast Metal (140-220 BPM)
    comment === Tempo Range ===
    positive Min_BPM 60
    positive Max_BPM 180
    comment === Detection ===
    optionmenu Method: 3
        option Autocorrelation (spectral ODF)
        option Spectral flux + IOI histogram
        option Intensity slope + autocorrelation (Fast / Recommended)
    positive Sensitivity 1.5
    comment === Octave Preference ===
    optionmenu Tempo_preference: 2
        option Prefer higher BPM (fast subdivisions)
        option Prefer lower BPM (quarter note feel)
        option Neutral (closest to range center)
    comment === Smoothing ===
    positive Smoothing_Hz 0.5
    real Tempo_continuity_weight 0.3
    boolean Zero_phase_smoothing 1
    boolean Draw_visualization 1
endform

# Apply presets
if preset = 2
    min_BPM = 90
    max_BPM = 180
    sensitivity = 1.5
    smoothing_Hz = 0.5
    tempo_continuity_weight = 0.3
    tempo_preference = 2
    presetName$ = "Pop/Rock"
elsif preset = 3
    min_BPM = 40
    max_BPM = 120
    sensitivity = 1.2
    smoothing_Hz = 0.3
    tempo_continuity_weight = 0.4
    tempo_preference = 2
    presetName$ = "Classical"
elsif preset = 4
    min_BPM = 100
    max_BPM = 160
    sensitivity = 2.0
    smoothing_Hz = 0.6
    tempo_continuity_weight = 0.2
    tempo_preference = 2
    presetName$ = "Electronic"
elsif preset = 5
    min_BPM = 60
    max_BPM = 200
    sensitivity = 1.3
    smoothing_Hz = 0.4
    tempo_continuity_weight = 0.3
    tempo_preference = 2
    presetName$ = "Jazz"
elsif preset = 6
    min_BPM = 50
    max_BPM = 80
    sensitivity = 1.0
    smoothing_Hz = 0.2
    tempo_continuity_weight = 0.5
    tempo_preference = 2
    presetName$ = "SlowBallad"
elsif preset = 7
    min_BPM = 140
    max_BPM = 220
    sensitivity = 1.8
    smoothing_Hz = 0.7
    tempo_continuity_weight = 0.2
    tempo_preference = 1
    presetName$ = "FastMetal"
else
    presetName$ = "Custom"
endif

# Validate and calculate dependent parameters
if min_BPM >= max_BPM
    exitScript: "Min BPM must be lower than Max BPM."
endif
if tempo_continuity_weight < 0
    tempo_continuity_weight = 0
elsif tempo_continuity_weight > 1
    tempo_continuity_weight = 1
endif

min_period = 60 / max_BPM
max_period = 60 / min_BPM
refractory_period = min_period * 0.4
window_size = max(4.0, 4 * max_period)
hop_size = window_size / 6
center_bpm = (min_BPM + max_BPM) / 2
if tempo_preference = 1
    preferenceName$ = "Prefer higher BPM"
elsif tempo_preference = 2
    preferenceName$ = "Prefer lower BPM"
else
    preferenceName$ = "Neutral"
endif

# Source geometry and representative analysis channel.
selectObject: sound
sound_tmin = Get start time
sound_tmax = Get end time
duration = sound_tmax - sound_tmin
sampleRate = Get sampling frequency
nChannels = Get number of channels

analysis_source = sound
analysis_is_copy = 0
analysis_channel = 1
if nChannels > 1
    best_rms = -1
    for ch from 1 to nChannels
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
    analysis_source = Extract one channel: analysis_channel
    analysis_is_copy = 1
endif

clearinfo
writeInfoLine: "=== Tempo Curve Estimator v0.6.2 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Tempo range: ", min_BPM, " - ", max_BPM, " BPM"
appendInfoLine: "Period range: ", fixed$(min_period, 3), " - ", fixed$(max_period, 3), " s"
appendInfoLine: "Preference: ", preferenceName$
if nChannels > 1
    appendInfoLine: "Analysis channel: ", analysis_channel, " of ", nChannels, " (strongest RMS)"
endif
appendInfoLine: ""

# === HELPER PROCEDURES ===

procedure getMedian: .data#
    .n = size(.data#)
    if .n = 0
        .result = 0
    elsif .n = 1
        .result = .data#[1]
    else
        .sorted# = sort#(.data#)
        if .n mod 2 = 1
            .result = .sorted#[floor(.n / 2) + 1]
        else
            .result = (.sorted#[.n / 2] + .sorted#[.n / 2 + 1]) / 2
        endif
    endif
endproc

procedure getMAD: .data#, .median
    .n = size(.data#)
    if .n = 0
        .result = 0
    else
        .deviations# = zero#(.n)
        for .i to .n
            .deviations#[.i] = abs(.data#[.i] - .median)
        endfor
        @getMedian: .deviations#
        .result = getMedian.result
    endif
endproc

procedure trimArray: .data#, .newSize
    if .newSize <= 0
        .result# = zero#(0)
    else
        .result# = zero#(.newSize)
        for .i to .newSize
            .result#[.i] = .data#[.i]
        endfor
    endif
endproc

# Score a BPM candidate based on preference
procedure scoreBPM: .bpm, .prev_bpm, .global_bpm
    .score = 0

    # Preference is deliberately weak: it breaks close metrical ties but must not
    # override the measured periodicity by itself.
    .range = max_BPM - min_BPM
    if .range <= 0
        .range = 1
    endif
    .pos = (.bpm - min_BPM) / .range
    if tempo_preference = 1
        .score = .score + 1.5 * .pos
    elsif tempo_preference = 2
        .score = .score + 1.5 * (1 - .pos)
    else
        .center_dist = abs(.bpm - center_bpm) / (.range / 2 + 1e-12)
        .score = .score + 1.0 * max(0, 1 - .center_dist)
    endif

    # Tempo relationships are multiplicative, so continuity is measured in
    # log2 ratio rather than absolute BPM difference.
    if .prev_bpm > 0 and .bpm > 0
        .ratio_dist = abs(ln(.bpm / .prev_bpm) / ln(2))
        .score = .score - 35 * .ratio_dist * tempo_continuity_weight
    endif
    if .global_bpm > 0 and .bpm > 0
        .ratio_dist = abs(ln(.bpm / .global_bpm) / ln(2))
        .score = .score - 12 * .ratio_dist
    endif
    .result = .score
endproc

# Resolve local metrical ambiguity. The raw period detector remains the primary
# evidence; only common half/double and 3:2 alternatives are considered.
procedure findBestBPM: .raw_bpm, .prev_bpm, .global_bpm
    .n_candidates = 0
    .candidates# = zero#(8)
    .multipliers# = {0.5, 0.667, 1.0, 1.5, 2.0}

    for .m to 5
        .candidate = .raw_bpm * .multipliers#[.m]
        if .candidate >= min_BPM and .candidate <= max_BPM
            .n_candidates = .n_candidates + 1
            .candidates#[.n_candidates] = .candidate
        endif
    endfor

    .best_bpm = min(max(.raw_bpm, min_BPM), max_BPM)
    .best_score = -1e30
    for .c to .n_candidates
        .candidate = .candidates#[.c]
        @scoreBPM: .candidate, .prev_bpm, .global_bpm
        # Small cost for moving away from the measured raw candidate.
        .raw_dist = abs(ln(.candidate / .raw_bpm) / ln(2))
        .candidate_score = scoreBPM.result - 1.5 * .raw_dist
        if .candidate_score > .best_score
            .best_score = .candidate_score
            .best_bpm = .candidate
        endif
    endfor

    .result = .best_bpm
endproc

# AUTOCORRELATION-BASED PERIOD DETECTION
procedure findPeriodByAutocorr: .odf#, .n_frames, .t_step
    .min_lag = floor(min_period / .t_step)
    .max_lag = ceiling(max_period / .t_step)
    if .max_lag > .n_frames / 2
        .max_lag = floor(.n_frames / 2)
    endif
    if .min_lag < 1
        .min_lag = 1
    endif

    .n_lags = .max_lag - .min_lag + 1
    .strength = 0
    if .n_lags < 3 or .n_frames < 8
        .result = (min_period + max_period) / 2
    else
        .acf# = zero#(.n_lags)
        .sum = 0
        for .i to .n_frames
            .sum = .sum + .odf#[.i]
        endfor
        .mean = .sum / .n_frames

        .var_sum = 0
        for .i to .n_frames
            .var_sum = .var_sum + (.odf#[.i] - .mean) ^ 2
        endfor
        .variance = .var_sum / .n_frames
        if .variance < 1e-20
            .variance = 1e-20
        endif

        for .l to .n_lags
            .lag = .min_lag + .l - 1
            .sum = 0
            .count = .n_frames - .lag
            if .count > 0
                for .i to .count
                    .sum = .sum + (.odf#[.i] - .mean) * (.odf#[.i + .lag] - .mean)
                endfor
                .acf#[.l] = .sum / (.count * .variance)
            endif
        endfor

        # First find the strongest measured local peak without any tempo prior.
        # The preference stage may choose an octave relative, but it should not
        # drift to arbitrary 3x/4x lags just because they are slower.
        .anchor_idx = 1
        .anchor_val = -1e30
        .found_peak = 0
        for .l from 2 to .n_lags - 1
            if .acf#[.l] >= .acf#[.l - 1] and .acf#[.l] >= .acf#[.l + 1]
                .found_peak = 1
                if .acf#[.l] > .anchor_val
                    .anchor_val = .acf#[.l]
                    .anchor_idx = .l
                endif
            endif
        endfor
        if not .found_peak
            for .l to .n_lags
                if .acf#[.l] > .anchor_val
                    .anchor_val = .acf#[.l]
                    .anchor_idx = .l
                endif
            endfor
        endif

        .anchor_lag = .min_lag + .anchor_idx - 1
        .best_lag_idx = .anchor_idx
        .best_score = -1e30
        for .l from 2 to .n_lags - 1
            if .acf#[.l] >= .acf#[.l - 1] and .acf#[.l] >= .acf#[.l + 1]
                .lag = .min_lag + .l - 1
                .bpm = 60 / (.lag * .t_step)
                .pref_bonus = 0
                if tempo_preference = 1
                    .pref_bonus = 0.05 * (1 - (.l - 1) / max(1, .n_lags - 1))
                elsif tempo_preference = 2
                    .pref_bonus = 0.05 * ((.l - 1) / max(1, .n_lags - 1))
                else
                    .pref_bonus = 0.03 * max(0, 1 - abs(.bpm - center_bpm) / ((max_BPM - min_BPM) / 2 + 1e-12))
                endif

                .ratio = .lag / .anchor_lag
                .octave_dist = min(abs(ln(.ratio) / ln(2)), abs(ln(.ratio / 2) / ln(2)), abs(ln(.ratio * 2) / ln(2)))
                .three_two_dist = min(abs(ln(.ratio / 1.5) / ln(2)), abs(ln(.ratio * 1.5) / ln(2)))
                if .octave_dist < 0.08
                    .relation_penalty = 0
                elsif .three_two_dist < 0.08
                    .relation_penalty = 0.03
                else
                    .relation_penalty = 0.08
                endif

                .score = .acf#[.l] + .pref_bonus - .relation_penalty
                if .score > .best_score
                    .best_score = .score
                    .best_lag_idx = .l
                endif
            endif
        endfor
        if not .found_peak
            .best_lag_idx = .anchor_idx
        endif

        .raw_peak = .acf#[.best_lag_idx]
        .strength = max(0, min(1, .raw_peak))

        if .best_lag_idx > 1 and .best_lag_idx < .n_lags
            .y0 = .acf#[.best_lag_idx - 1]
            .y1 = .acf#[.best_lag_idx]
            .y2 = .acf#[.best_lag_idx + 1]
            .denom = .y0 - 2 * .y1 + .y2
            if abs(.denom) > 1e-12
                .offset = 0.5 * (.y0 - .y2) / .denom
                .offset = max(-0.5, min(0.5, .offset))
            else
                .offset = 0
            endif
            .refined_idx = .best_lag_idx + .offset
        else
            .refined_idx = .best_lag_idx
        endif

        .best_lag = .min_lag + .refined_idx - 1
        .result = .best_lag * .t_step
    endif
endproc

# IOI histogram period detector
procedure findPeriodByHistogram: .ioi#, .n_ioi
    .strength = 0
    if .n_ioi < 2
        .result = (min_period + max_period) / 2
    else
        .n_bins = 80
        .bin_width = (max_period - min_period) / .n_bins
        .hist# = zero#(.n_bins)
        .sigma = max(.bin_width * 1.5, 1e-6)

        for .i to .n_ioi
            .period = .ioi#[.i]
            # IOI, octave relatives, and weaker 3:2 relatives.
            .periods# = {.period, .period * 2, .period / 2, .period * 1.5, .period / 1.5}
            .weights# = {1.0, 0.55, 0.55, 0.25, 0.25}
            for .k to 5
                .p = .periods#[.k]
                .weight = .weights#[.k]
                if .p >= min_period and .p <= max_period
                    .bin = floor((.p - min_period) / .bin_width) + 1
                    .bin = max(1, min(.n_bins, .bin))
                    for .b from max(1, .bin - 2) to min(.n_bins, .bin + 2)
                        .dist = abs(.b - .bin) * .bin_width
                        .hist#[.b] = .hist#[.b] + exp(-0.5 * (.dist / .sigma) ^ 2) * .weight
                    endfor
                endif
            endfor
        endfor

        # Preference is only a small tie-break after the measured IOI evidence.
        for .b to .n_bins
            .pos = (.b - 1) / max(1, .n_bins - 1)
            if tempo_preference = 1
                .hist#[.b] = .hist#[.b] * (1 + 0.05 * (1 - .pos))
            elsif tempo_preference = 2
                .hist#[.b] = .hist#[.b] * (1 + 0.05 * .pos)
            endif
        endfor

        .max_val = -1
        .max_bin = 1
        .hist_sum = 0
        for .b to .n_bins
            .hist_sum = .hist_sum + .hist#[.b]
            if .hist#[.b] > .max_val
                .max_val = .hist#[.b]
                .max_bin = .b
            endif
        endfor
        .mean_hist = .hist_sum / .n_bins
        if .max_val > 0
            .strength = max(0, min(1, (.max_val - .mean_hist) / (.max_val + 1e-12)))
        endif

        if .max_bin > 1 and .max_bin < .n_bins
            .y0 = .hist#[.max_bin - 1]
            .y1 = .hist#[.max_bin]
            .y2 = .hist#[.max_bin + 1]
            .denom = .y0 - 2 * .y1 + .y2
            if abs(.denom) > 1e-12
                .offset = 0.5 * (.y0 - .y2) / .denom
                .offset = max(-0.5, min(0.5, .offset))
            else
                .offset = 0
            endif
            .refined_bin = .max_bin + .offset
        else
            .refined_bin = .max_bin
        endif
        .result = min_period + (.refined_bin - 0.5) * .bin_width
    endif
endproc

# === ANALYSIS SOUND / NYQUIST-SAFE PREPROCESSING ===
target_sr = 22050
selectObject: analysis_source
analysis_sr = Get sampling frequency
sound_work = analysis_source
work_is_copy = 0
if analysis_sr > target_sr
    appendInfoLine: "Resampling analysis channel to ", target_sr, " Hz..."
    sound_work = Resample: target_sr, 50
    work_is_copy = 1
endif

selectObject: sound_work
work_sr = Get sampling frequency
nyquist = work_sr / 2
analysis_max_freq = min(8000, nyquist * 0.96)
if analysis_max_freq <= 80
    analysis_max_freq = nyquist * 0.90
endif
filter_low = min(50, analysis_max_freq * 0.25)
filter_smoothing = min(100, max(10, analysis_max_freq * 0.02))
sound_filt = Filter (pass Hann band): filter_low, analysis_max_freq, filter_smoothing

# Adaptive ODF rate: retain fine onset timing on normal files but avoid millions of
# frames on long recordings. Praat may further adjust the actual Spectrogram step.
max_odf_frames = 120000
odf_requested_step = max(0.005, duration / max_odf_frames)
odf_requested_step = min(0.020, odf_requested_step)

appendInfoLine: "Analysis SR: ", fixed$(work_sr, 0), " Hz; spectral ceiling: ", fixed$(analysis_max_freq, 0), " Hz"
appendInfoLine: "Requested ODF step: ", fixed$(odf_requested_step * 1000, 2), " ms"
appendInfoLine: "Computing onset detection function..."

selectObject: sound_filt
if method = 1 or method = 2
    spec = To Spectrogram: 0.023, analysis_max_freq, odf_requested_step, 20, "Gaussian"
    mat = To Matrix
    nRows = Get number of rows
    nCols = Get number of columns
    tFirst = Get x of column: 1
    if nCols >= 2
        tSecond = Get x of column: 2
        tStep = tSecond - tFirst
    else
        tStep = odf_requested_step
    endif
    yFirst = Get y of row: 1
    if nRows >= 2
        ySecond = Get y of row: 2
        yStep = ySecond - yFirst
    else
        yStep = analysis_max_freq
    endif

    odf# = zero#(nCols)
    band_edges# = {0, 80, 250, 500, 2000, 4000, 8000}
    band_weights# = {0.6, 1.2, 1.0, 0.9, 0.7, 0.5}

    for col from 2 to nCols
        flux = 0
        for band to 6
            f_low = band_edges#[band]
            f_high = min(band_edges#[band + 1], analysis_max_freq)
            if f_low < analysis_max_freq and f_high > f_low
                row_low = floor((f_low - yFirst) / yStep) + 1
                row_high = ceiling((f_high - yFirst) / yStep) + 1
                row_low = max(1, min(nRows, row_low))
                row_high = max(row_low, min(nRows, row_high))
                band_flux = 0
                for row from row_low to row_high
                    v_curr = Get value in cell: row, col
                    v_prev = Get value in cell: row, col - 1
                    if v_curr = undefined
                        v_curr = 0
                    elsif v_curr < 0
                        v_curr = 0
                    endif
                    if v_prev = undefined
                        v_prev = 0
                    elsif v_prev < 0
                        v_prev = 0
                    endif
                    # Spectrogram cells are power density; sqrt converts to a
                    # magnitude-like domain before half-wave spectral differencing.
                    delta_mag = sqrt(v_curr) - sqrt(v_prev)
                    if delta_mag > 0
                        band_flux = band_flux + delta_mag
                    endif
                endfor
                flux = flux + band_flux * band_weights#[band]
            endif
        endfor
        odf#[col] = flux
    endfor
    removeObject: spec, mat
else
    intensity = To Intensity: 50, odf_requested_step, "yes"
    nCols = Get number of frames
    tStep = Get time step
    if nCols >= 1
        tFirst = Get time from frame number: 1
    else
        tFirst = sound_tmin
    endif

    int_raw# = zero#(nCols)
    for i to nCols
        t = Get time from frame number: i
        int_raw#[i] = Get value at time: t, "Cubic"
        if int_raw#[i] = undefined
            int_raw#[i] = 0
        endif
    endfor

    int_filt# = zero#(nCols)
    if nCols >= 5
        for i from 3 to nCols - 2
            vals# = {int_raw#[i - 2], int_raw#[i - 1], int_raw#[i], int_raw#[i + 1], int_raw#[i + 2]}
            vals# = sort#(vals#)
            int_filt#[i] = vals#[3]
        endfor
        int_filt#[1] = int_raw#[1]
        int_filt#[2] = int_raw#[2]
        int_filt#[nCols - 1] = int_raw#[nCols - 1]
        int_filt#[nCols] = int_raw#[nCols]
    else
        for i to nCols
            int_filt#[i] = int_raw#[i]
        endfor
    endif

    odf# = zero#(nCols)
    for i from 2 to nCols
        odf#[i] = max(0, int_filt#[i] - int_filt#[i - 1])
    endfor
    removeObject: intensity
endif

appendInfoLine: "Actual ODF step: ", fixed$(tStep * 1000, 2), " ms; frames: ", nCols

# === 2. GLOBAL TEMPO ESTIMATION ===
appendInfoLine: "Estimating global tempo..."
global_confidence = 0
if method = 1 or method = 3
    # Decimate only for the global ACF. Peak picking still uses the
    # full-resolution ODF. Keep at least ~25 Hz ACF sampling for tempo range.
    acf_decim = max(1, ceiling(0.020 / tStep))
    if nCols / acf_decim > 60000
        acf_decim = ceiling(nCols / 60000)
    endif
    max_decim = max(1, floor(0.040 / tStep))
    acf_decim = min(acf_decim, max_decim)
    nAcf = floor((nCols - 1) / acf_decim) + 1
    acf_odf# = zero#(nAcf)
    for a to nAcf
        block_start = 1 + (a - 1) * acf_decim
        block_end = min(nCols, block_start + acf_decim - 1)
        block_max = 0
        for k from block_start to block_end
            if odf#[k] > block_max
                block_max = odf#[k]
            endif
        endfor
        acf_odf#[a] = block_max
    endfor
    acf_step = tStep * acf_decim
    @findPeriodByAutocorr: acf_odf#, nAcf, acf_step
    global_period = findPeriodByAutocorr.result
    global_confidence = findPeriodByAutocorr.strength
    global_bpm = 60 / global_period
    global_bpm = min(max(global_bpm, min_BPM), max_BPM)
    appendInfoLine: "Global ACF BPM: ", fixed$(global_bpm, 1), " (ACF strength ", fixed$(global_confidence, 2), ")"
else
    global_period = (min_period + max_period) / 2
    global_bpm = 60 / global_period
endif

# === 3. ONSET PEAK PICKING ===
appendInfoLine: "Detecting onsets..."

@getMedian: odf#
odf_median = getMedian.result
@getMAD: odf#, odf_median
odf_mad = getMAD.result
if odf_mad < 0.0001
    odf_mad = 0.0001
endif

window_frames = round(0.25 / tStep)
if window_frames < 2
    window_frames = 2
endif

onsets# = zero#(nCols)
threshold_curve# = zero#(nCols)
nOnsets = 0
last_onset_time = -999

for col from 4 to nCols - 3
    local_sum = 0
    local_count = 0
    for offset from -window_frames to window_frames
        idx = col + offset
        if idx >= 1 and idx <= nCols
            local_sum += odf#[idx]
            local_count += 1
        endif
    endfor
    local_mean = local_sum / local_count
    
    threshold = local_mean + sensitivity * odf_mad
    threshold_curve#[col] = threshold

    isMax = 1
    if odf#[col] <= threshold
        isMax = 0
    endif
    
    for offset from -3 to 3
        if offset <> 0 and col + offset >= 1 and col + offset <= nCols
            if odf#[col] <= odf#[col + offset]
                isMax = 0
            endif
        endif
    endfor
    
    if isMax
        t = tFirst + (col - 1) * tStep
        if t - last_onset_time >= refractory_period
            nOnsets += 1
            onsets#[nOnsets] = t
            last_onset_time = t
        endif
    endif
endfor

@trimArray: onsets#, nOnsets
onsets# = trimArray.result#

removeObject: sound_filt
if work_is_copy
    removeObject: sound_work
endif

appendInfoLine: "Found ", nOnsets, " onsets"

# === 4. CREATE TEXTGRID ===
# These are detected onset candidates, not guaranteed metrical beats.
selectObject: sound
textGrid = To TextGrid: "onsets", "onsets"
if nOnsets > 0
    for i to nOnsets
        selectObject: textGrid
        Insert point: 1, onsets#[i], "onset"
    endfor
endif

# === 5. CALCULATE BPM CURVE ===
if nOnsets > 2
    appendInfoLine: "Calculating tempo curve..."

    ioi# = zero#(nOnsets - 1)
    for i to nOnsets - 1
        ioi#[i] = onsets#[i + 1] - onsets#[i]
    endfor

    # Spectral-flux + IOI mode estimates global tempo only after onset extraction.
    # Intensity mode already has a full-ODF ACF estimate, which is deliberately
    # retained so different percussion event densities do not overwrite it.
    if method = 2
        @findPeriodByHistogram: ioi#, nOnsets - 1
        global_period = findPeriodByHistogram.result
        global_confidence = findPeriodByHistogram.strength
        global_bpm = 60 / global_period
        global_bpm = min(max(global_bpm, min_BPM), max_BPM)
        appendInfoLine: "Global IOI BPM: ", fixed$(global_bpm, 1), " (histogram confidence ", fixed$(global_confidence, 2), ")"
    endif

    if duration <= window_size
        nSteps = 1
    else
        nSteps = floor((duration - window_size) / hop_size) + 1
    endif

    time# = zero#(nSteps)
    time_rel# = zero#(nSteps)
    bpm# = zero#(nSteps)
    confidence# = zero#(nSteps)
    support# = zero#(nSteps)
    prev_bpm = global_bpm

    for step to nSteps
        if nSteps = 1
            t_center_rel = duration / 2
            t_start = sound_tmin
            t_end = sound_tmax
        else
            t_center_rel = (step - 1) * hop_size + window_size / 2
            t_start = sound_tmin + t_center_rel - window_size / 2
            t_end = sound_tmin + t_center_rel + window_size / 2
        endif
        t_center = sound_tmin + t_center_rel
        time#[step] = t_center
        time_rel#[step] = t_center_rel

        window_ioi# = zero#(nOnsets)
        n_window = 0
        for i to nOnsets - 1
            if onsets#[i] >= t_start and onsets#[i + 1] <= t_end
                n_window = n_window + 1
                window_ioi#[n_window] = ioi#[i]
            endif
        endfor
        support#[step] = n_window

        if n_window >= 2
            @trimArray: window_ioi#, n_window
            window_ioi# = trimArray.result#
            @findPeriodByHistogram: window_ioi#, n_window
            local_period = findPeriodByHistogram.result
            raw_bpm = 60 / local_period
            @findBestBPM: raw_bpm, prev_bpm, global_bpm
            bpm#[step] = findBestBPM.result
            confidence#[step] = findPeriodByHistogram.strength * min(1, n_window / 4)
            prev_bpm = bpm#[step]
        elsif n_window = 1
            raw_bpm = 60 / window_ioi#[1]
            @findBestBPM: raw_bpm, prev_bpm, global_bpm
            bpm#[step] = findBestBPM.result
            confidence#[step] = 0.10
            prev_bpm = bpm#[step]
        else
            # Carry internally for smoothing/continuity, but expose zero support.
            bpm#[step] = prev_bpm
            confidence#[step] = 0
        endif
    endfor

    # Median pre-filter, only replacing a supported centre with neighboring values.
    if nSteps >= 5
        filtered# = zero#(nSteps)
        for i to nSteps
            filtered#[i] = bpm#[i]
        endfor
        for i from 3 to nSteps - 2
            if support#[i] > 0
                vals# = {bpm#[i - 2], bpm#[i - 1], bpm#[i], bpm#[i + 1], bpm#[i + 2]}
                vals# = sort#(vals#)
                filtered#[i] = vals#[3]
            endif
        endfor
        bpm# = filtered#
    endif

    # Optional one-pole smoothing. Zero-phase mode applies forward/backward passes.
    if smoothing_Hz > 0 and nSteps >= 2
        alpha = 1 - exp(-2 * pi * smoothing_Hz * hop_size)
        alpha = min(1, max(0, alpha))
        smoothed# = zero#(nSteps)
        smoothed#[1] = bpm#[1]
        for i from 2 to nSteps
            smoothed#[i] = smoothed#[i - 1] + alpha * (bpm#[i] - smoothed#[i - 1])
        endfor
        if zero_phase_smoothing
            for i from nSteps - 1 to 1
                smoothed#[i] = smoothed#[i + 1] + alpha * (smoothed#[i] - smoothed#[i + 1])
            endfor
        endif
        bpm# = smoothed#
    endif

    # Table: confidence is normalized 0..1; support_iois states the actual amount
    # of local evidence. A carried tempo with support=0 should not be read as data.
    table = Create Table with column names: "TempoCurve_" + soundName$, nSteps, "time time_rel bpm confidence support_iois"
    for i to nSteps
        selectObject: table
        Set numeric value: i, "time", time#[i]
        Set numeric value: i, "time_rel", time_rel#[i]
        Set numeric value: i, "bpm", bpm#[i]
        Set numeric value: i, "confidence", confidence#[i]
        Set numeric value: i, "support_iois", support#[i]
    endfor

    valid_bpm# = zero#(nSteps)
    valid_count = 0
    confidence_sum = 0
    for i to nSteps
        if support#[i] >= 2
            valid_count = valid_count + 1
            valid_bpm#[valid_count] = bpm#[i]
            confidence_sum = confidence_sum + confidence#[i]
        endif
    endfor

    if valid_count > 0
        @trimArray: valid_bpm#, valid_count
        valid_bpm# = trimArray.result#
        @getMedian: valid_bpm#
        median_bpm = getMedian.result
        bpm_sum = 0
        bpm_min = 1e30
        bpm_max = -1e30
        for i to valid_count
            bpm_sum = bpm_sum + valid_bpm#[i]
            if valid_bpm#[i] < bpm_min
                bpm_min = valid_bpm#[i]
            endif
            if valid_bpm#[i] > bpm_max
                bpm_max = valid_bpm#[i]
            endif
        endfor
        mean_bpm = bpm_sum / valid_count
        mean_confidence = confidence_sum / valid_count
    else
        mean_bpm = global_bpm
        median_bpm = global_bpm
        bpm_min = global_bpm
        bpm_max = global_bpm
        mean_confidence = 0
    endif

    if draw_visualization
        displayName$ = replace$(soundName$, "_", " ", 0)
        selectObject: analysis_source
        wave_peak = Get absolute extremum: sound_tmin, sound_tmax, "Sinc70"
        if wave_peak = undefined
            wave_peak = 1
        elsif wave_peak <= 0
            wave_peak = 1
        endif
        wave_peak = wave_peak * 1.03

        odf_max = 0
        for i to nCols
            if odf#[i] > odf_max
                odf_max = odf#[i]
            endif
        endfor
        if odf_max <= 0
            odf_max = 1
        endif

        Erase all

        # Main title and subtitle use separate viewport strips so text cannot collide.
        Select outer viewport: 0, 8, 0.02, 0.34
        Axes: 0, 1, 0, 1
        Font size: 14
        Colour: "Black"
        Text: 0.5, "centre", 0.50, "half", "##Tempo Curve (IOI) Estimator##"

        Select outer viewport: 0, 8, 0.39, 0.65
        Axes: 0, 1, 0, 1
        Font size: 8
        Colour: "Black"
        Text: 0.5, "centre", 0.50, "half", displayName$ + "  |  " + presetName$ + "  |  " + fixed$(global_bpm, 1) + " BPM global"

        # Panel 1: representative channel waveform + detected onsets
        Select outer viewport: 0, 8, 0.72, 2.34
        Select inner viewport: 0.72, 7.45, 0.94, 2.18
        selectObject: analysis_source
        Colour: "{0.35, 0.42, 0.55}"
        Draw: sound_tmin, sound_tmax, -wave_peak, wave_peak, "no", "Curve"
        Select inner viewport: 0.72, 7.45, 0.94, 2.18
        Axes: sound_tmin, sound_tmax, -wave_peak, wave_peak
        Colour: "{0.82, 0.25, 0.20}"
        Line width: 1
        for i to nOnsets
            Draw line: onsets#[i], -0.92 * wave_peak, onsets#[i], 0.92 * wave_peak
        endfor
        Select inner viewport: 0.72, 7.45, 0.94, 2.18
        Axes: sound_tmin, sound_tmax, -wave_peak, wave_peak
        Colour: "Black"
        Draw inner box
        Select inner viewport: 0.72, 7.45, 0.94, 2.18
        Axes: sound_tmin, sound_tmax, -wave_peak, wave_peak
        Font size: 7
        Marks left: 2, "yes", "yes", "no"
        Select inner viewport: 0.72, 7.45, 0.94, 2.18
        Axes: sound_tmin, sound_tmax, -wave_peak, wave_peak
        Text left: "yes", "Amplitude"
        Select outer viewport: 0.72, 7.45, 0.73, 0.93
        Axes: 0, 1, 0, 1
        Font size: 9
        Colour: "Black"
        Text: 0.5, "centre", 0.60, "half", "##Waveform + detected onsets##"

        # Panel 2: actual ODF and adaptive threshold, normalized to its measured max.
        Select outer viewport: 0, 8, 2.42, 4.24
        Select inner viewport: 0.72, 7.45, 2.66, 4.08
        Axes: sound_tmin, sound_tmax, 0, 1.05
        Paint rectangle: "{0.97, 0.97, 0.98}", sound_tmin, sound_tmax, 0, 1.05
        Select inner viewport: 0.72, 7.45, 2.66, 4.08
        Axes: sound_tmin, sound_tmax, 0, 1.05
        viz_stride = max(1, ceiling(nCols / 3000))
        Colour: "{0.20, 0.42, 0.72}"
        Line width: 1.2
        prev_idx = 1
        i = 1 + viz_stride
        while i <= nCols
            t0 = tFirst + (prev_idx - 1) * tStep
            t1 = tFirst + (i - 1) * tStep
            Draw line: t0, min(1, odf#[prev_idx] / odf_max), t1, min(1, odf#[i] / odf_max)
            prev_idx = i
            i = i + viz_stride
        endwhile
        Colour: "{0.80, 0.35, 0.20}"
        Dotted line
        prev_idx = 4
        i = 4 + viz_stride
        while i <= nCols - 3
            t0 = tFirst + (prev_idx - 1) * tStep
            t1 = tFirst + (i - 1) * tStep
            Draw line: t0, min(1, threshold_curve#[prev_idx] / odf_max), t1, min(1, threshold_curve#[i] / odf_max)
            prev_idx = i
            i = i + viz_stride
        endwhile
        Solid line
        Select inner viewport: 0.72, 7.45, 2.66, 4.08
        Axes: sound_tmin, sound_tmax, 0, 1.05
        Colour: "Black"
        Draw inner box
        Select inner viewport: 0.72, 7.45, 2.66, 4.08
        Axes: sound_tmin, sound_tmax, 0, 1.05
        Font size: 7
        Marks left: 2, "yes", "yes", "no"
        Select inner viewport: 0.72, 7.45, 2.66, 4.08
        Axes: sound_tmin, sound_tmax, 0, 1.05
        Text left: "yes", "Norm. ODF"
        Select outer viewport: 0.72, 7.45, 2.43, 2.64
        Axes: 0, 1, 0, 1
        Font size: 9
        Colour: "Black"
        Text: 0.5, "centre", 0.60, "half", "##Onset detection function##   blue=data   red=adaptive threshold"

        # Panel 3: supported tempo curve. Unsupported windows are lightly shaded;
        # lines are only connected where both endpoints contain IOI evidence.
        Select outer viewport: 0, 8, 4.32, 6.66
        Select inner viewport: 0.72, 7.45, 4.56, 6.45
        y_min = max(1, min_BPM - 10)
        y_max = max_BPM + 10
        Axes: sound_tmin, sound_tmax, y_min, y_max
        Paint rectangle: "{0.97, 0.97, 0.97}", sound_tmin, sound_tmax, y_min, y_max
        for i to nSteps
            if support#[i] = 0
                t1 = max(sound_tmin, time#[i] - hop_size / 2)
                t2 = min(sound_tmax, time#[i] + hop_size / 2)
                Paint rectangle: "{0.91, 0.91, 0.95}", t1, t2, y_min, y_max
            endif
        endfor
        Select inner viewport: 0.72, 7.45, 4.56, 6.45
        Axes: sound_tmin, sound_tmax, y_min, y_max
        Colour: "{0.70, 0.70, 0.72}"
        Dotted line
        Draw line: sound_tmin, global_bpm, sound_tmax, global_bpm
        Colour: "{0.30, 0.62, 0.35}"
        Draw line: sound_tmin, median_bpm, sound_tmax, median_bpm
        Solid line
        Colour: "{0.18, 0.36, 0.76}"
        Line width: 2
        for i from 2 to nSteps
            if support#[i - 1] > 0 and support#[i] > 0
                Draw line: time#[i - 1], bpm#[i - 1], time#[i], bpm#[i]
            endif
        endfor
        Select inner viewport: 0.72, 7.45, 4.56, 6.45
        Axes: sound_tmin, sound_tmax, y_min, y_max
        Colour: "Black"
        Line width: 1
        Draw inner box
        Select inner viewport: 0.72, 7.45, 4.56, 6.45
        Axes: sound_tmin, sound_tmax, y_min, y_max
        Font size: 7
        Marks left every: 1, 20, "yes", "yes", "no"
        Select inner viewport: 0.72, 7.45, 4.56, 6.45
        Axes: sound_tmin, sound_tmax, y_min, y_max
        Marks bottom every: 1, max(1, round(duration / 8)), "yes", "yes", "no"
        Select inner viewport: 0.72, 7.45, 4.56, 6.45
        Axes: sound_tmin, sound_tmax, y_min, y_max
        Text left: "yes", "BPM"
        Text bottom: "yes", "Time (s)"
        Select outer viewport: 0.72, 7.45, 4.33, 4.54
        Axes: 0, 1, 0, 1
        Font size: 9
        Colour: "Black"
        Text: 0.5, "centre", 0.60, "half", "##Local tempo##   blue=supported   grey=global   green=median"

        # Summary strip
        Select outer viewport: 0, 8, 6.78, 7.90
        Select inner viewport: 0.55, 7.55, 6.86, 7.82
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
        Select inner viewport: 0.55, 7.55, 6.86, 7.82
        Axes: 0, 1, 0, 1
        Colour: "Black"
        Font size: 9
        Text: 0.02, "left", 0.78, "half", "##Tempo summary##"
        Select inner viewport: 0.55, 7.55, 6.86, 7.82
        Axes: 0, 1, 0, 1
        Font size: 8
        Text: 0.02, "left", 0.49, "half", "Global " + fixed$(global_bpm, 1) + "   Median " + fixed$(median_bpm, 1) + "   Mean " + fixed$(mean_bpm, 1) + " BPM   Range " + fixed$(bpm_min, 1) + "-" + fixed$(bpm_max, 1)
        Select inner viewport: 0.55, 7.55, 6.86, 7.82
        Axes: 0, 1, 0, 1
        Text: 0.02, "left", 0.22, "half", "Onsets " + string$(nOnsets) + "   Mean local confidence " + fixed$(mean_confidence, 2) + "   ODF step " + fixed$(tStep * 1000, 1) + " ms   Window " + fixed$(window_size, 2) + " s"
        Select inner viewport: 0.55, 7.55, 6.86, 7.82
        Axes: 0, 1, 0, 1
        Draw rectangle: 0, 1, 0, 1
    endif

    if analysis_is_copy
        removeObject: analysis_source
    endif

    selectObject: textGrid, table
    appendInfoLine: ""
    appendInfoLine: "=== RESULTS ==="
    appendInfoLine: "Global BPM: ", fixed$(global_bpm, 1), "   confidence: ", fixed$(global_confidence, 2)
    appendInfoLine: "Median supported BPM: ", fixed$(median_bpm, 1)
    appendInfoLine: "Mean supported BPM: ", fixed$(mean_bpm, 1)
    appendInfoLine: "Supported range: ", fixed$(bpm_min, 1), " - ", fixed$(bpm_max, 1)
    appendInfoLine: "Detected onsets: ", nOnsets
    appendInfoLine: "Table confidence is 0..1; support_iois = local evidence count."
    appendInfoLine: "Done!"
else
    if analysis_is_copy
        removeObject: analysis_source
    endif
    selectObject: textGrid
    appendInfoLine: ""
    appendInfoLine: "Not enough onsets for a local tempo curve (need at least 3)."
    if method = 1 or method = 3
        appendInfoLine: "Global ACF estimate: ", fixed$(global_bpm, 1), " BPM; strength ", fixed$(global_confidence, 2)
    endif
endif
