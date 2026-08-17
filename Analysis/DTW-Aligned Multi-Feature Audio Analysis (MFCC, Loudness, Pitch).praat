# ============================================================
# Praat AudioTools - DTW-Aligned Multi-Feature Audio Analysis
# Author: Shai Cohen
# Version: 1.1 reviewed (2026)
# License: MIT License
#
# Measurement-first revision:
#   - Real dynamic time warping, not normalized-time pairing
#   - Combined MFCC + level-contour + pitch-contour local cost
#   - Strongest-RMS channel for multichannel Sounds
#   - Pooled per-coefficient MFCC standardization
#   - Gain-invariant loudness alignment; level offset reported separately
#   - Transposition-invariant pitch alignment; transposition reported separately
#   - Sakoe-Chiba style band around the duration-normalized diagonal
#   - Real backtracked alignment path and aligned measurement tables
#   - Visualization shows the measured DTW path and aligned residuals
#
# Usage:
#   Select exactly TWO Sound objects.
#   First selected = Reference; second selected = Test.
# ============================================================

clearinfo

number_of_selected_sounds = numberOfSelected("Sound")
if number_of_selected_sounds <> 2
    exitScript: "Please select exactly TWO Sound objects."
endif

sound1 = selected("Sound", 1)
sound2 = selected("Sound", 2)

form DTW-Aligned Multi-Feature Audio Analysis v1.1
    comment === Analysis ===
    positive Window_length_s 0.025
    positive Time_step_s 0.01
    natural Number_of_coefficients 12
    positive Pitch_floor_hz 75
    positive Pitch_ceiling_hz 600
    comment === DTW ===
    natural Max_dtw_points 140
    positive Warp_band_percent 20
    real Mfcc_weight 0.60
    real Loudness_weight 0.20
    real Pitch_weight 0.20
    comment === Output ===
    boolean Draw_visualization 1
endform

if pitch_floor_hz >= pitch_ceiling_hz
    exitScript: "Pitch floor must be lower than pitch ceiling."
endif
if number_of_coefficients < 2
    exitScript: "Use at least 2 MFCC coefficients."
endif
if max_dtw_points < 20
    max_dtw_points = 20
endif

warp_band_fraction = warp_band_percent / 100
warp_band_fraction = max(0.02, min(1, warp_band_fraction))

mfcc_weight = max(0, mfcc_weight)
loudness_weight = max(0, loudness_weight)
pitch_weight = max(0, pitch_weight)
weight_sum = mfcc_weight + loudness_weight + pitch_weight
if weight_sum <= 0
    exitScript: "At least one DTW feature weight must be greater than zero."
endif
mfcc_weight = mfcc_weight / weight_sum
loudness_weight = loudness_weight / weight_sum
pitch_weight = pitch_weight / weight_sum

# A small penalty discourages gratuitous horizontal/vertical wandering.
warp_step_penalty = 0.05
pitch_cost_scale_st = 3.0
voicing_mismatch_cost = 1.5
huge = 1e30

procedure getAnalysisChannel: .sound_id
    selectObject: .sound_id
    .channels = Get number of channels
    .result = .sound_id
    .is_copy = 0
    .channel = 1

    if .channels > 1
        .best_rms = -1
        for .ch to .channels
            selectObject: .sound_id
            .temp = Extract one channel: .ch
            .rms = Get root-mean-square: 0, 0
            if .rms > .best_rms
                .best_rms = .rms
                .channel = .ch
            endif
            removeObject: .temp
        endfor

        selectObject: .sound_id
        .result = Extract one channel: .channel
        .is_copy = 1
    endif
endproc

procedure medianPositive: .values#, .n
    .temp# = zero#(.n)
    .count = 0
    for .i to .n
        if .values#[.i] > 0
            .count = .count + 1
            .temp#[.count] = .values#[.i]
        endif
    endfor

    if .count = 0
        .result = undefined
    else
        .used# = zero#(.count)
        for .i to .count
            .used#[.i] = .temp#[.i]
        endfor
        .used# = sort#(.used#)
        if .count mod 2 = 1
            .result = .used#[(.count + 1) / 2]
        else
            .result = 0.5 * (.used#[.count / 2] + .used#[.count / 2 + 1])
        endif
    endif
    .count_result = .count
endproc

# =============================================================================
# SETUP / REPRESENTATIVE CHANNELS
# =============================================================================

@getAnalysisChannel: sound1
analysis1 = getAnalysisChannel.result
analysis1_is_copy = getAnalysisChannel.is_copy
analysis1_channel = getAnalysisChannel.channel

@getAnalysisChannel: sound2
analysis2 = getAnalysisChannel.result
analysis2_is_copy = getAnalysisChannel.is_copy
analysis2_channel = getAnalysisChannel.channel

selectObject: sound1
name1$ = selected$("Sound")
tmin1 = Get start time
tmax1 = Get end time
duration1 = tmax1 - tmin1

selectObject: sound2
name2$ = selected$("Sound")
tmin2 = Get start time
tmax2 = Get end time
duration2 = tmax2 - tmin2

if duration1 <= 0 or duration2 <= 0
    exitScript: "Both Sounds must have positive duration."
endif

selectObject: analysis1
sr1 = Get sampling frequency
selectObject: analysis2
sr2 = Get sampling frequency
shared_nyquist = min(sr1, sr2) / 2
max_mel_frequency = min(5000, 0.95 * shared_nyquist)
if max_mel_frequency <= 500
    exitScript: "Sampling rate is too low for the requested MFCC analysis."
endif

duration_ratio = duration2 / duration1

display1$ = replace$(name1$, "_", " ", 0)
display1$ = replace$(display1$, "%", "pct", 0)
display2$ = replace$(name2$, "_", " ", 0)
display2$ = replace$(display2$, "%", "pct", 0)

writeInfoLine: "================================================"
writeInfoLine: "  DTW MULTI-FEATURE AUDIO ANALYSIS v1.1"
writeInfoLine: "================================================"
appendInfoLine: "Reference: ", name1$, " (", fixed$(duration1, 3), " s; channel ", analysis1_channel, ")"
appendInfoLine: "Test:      ", name2$, " (", fixed$(duration2, 3), " s; channel ", analysis2_channel, ")"
appendInfoLine: "Weights: MFCC ", fixed$(mfcc_weight, 2), " | Loudness ", fixed$(loudness_weight, 2), " | Pitch ", fixed$(pitch_weight, 2)
appendInfoLine: "Warp band: ", fixed$(100 * warp_band_fraction, 1), "% | Duration ratio test/ref: ", fixed$(duration_ratio, 3)
appendInfoLine: ""

# =============================================================================
# FEATURE EXTRACTION OBJECTS
# =============================================================================

appendInfoLine: "Extracting MFCC, intensity, and pitch..."

selectObject: analysis1
melspec1 = To MelSpectrogram: window_length_s, time_step_s, 24, 100, max_mel_frequency
mfcc1 = To MFCC: number_of_coefficients
selectObject: analysis1
intensity1 = To Intensity: pitch_floor_hz, time_step_s, "yes"
selectObject: analysis1
pitch1 = To Pitch: time_step_s, pitch_floor_hz, pitch_ceiling_hz

selectObject: analysis2
melspec2 = To MelSpectrogram: window_length_s, time_step_s, 24, 100, max_mel_frequency
mfcc2 = To MFCC: number_of_coefficients
selectObject: analysis2
intensity2 = To Intensity: pitch_floor_hz, time_step_s, "yes"
selectObject: analysis2
pitch2 = To Pitch: time_step_s, pitch_floor_hz, pitch_ceiling_hz

selectObject: mfcc1
mfcc_frames1 = Get number of frames
selectObject: mfcc2
mfcc_frames2 = Get number of frames
selectObject: intensity1
intensity_frames1 = Get number of frames
selectObject: intensity2
intensity_frames2 = Get number of frames
selectObject: pitch1
pitch_frames1 = Get number of frames
selectObject: pitch2
pitch_frames2 = Get number of frames

available1 = min(mfcc_frames1, min(intensity_frames1, pitch_frames1))
available2 = min(mfcc_frames2, min(intensity_frames2, pitch_frames2))
n1 = min(max_dtw_points, available1)
n2 = min(max_dtw_points, available2)

if n1 < 2 or n2 < 2
    exitScript: "Not enough analysis frames for DTW."
endif

appendInfoLine: "DTW samples: reference ", n1, " | test ", n2

# =============================================================================
# SAMPLE FEATURES ACROSS EACH COMPLETE SOUND
# =============================================================================

mfcc_a# = zero#(n1 * number_of_coefficients)
mfcc_b# = zero#(n2 * number_of_coefficients)
db_a# = zero#(n1)
db_b# = zero#(n2)
pitch_st_a# = zero#(n1)
pitch_st_b# = zero#(n2)
voiced_a# = zero#(n1)
voiced_b# = zero#(n2)
time_a# = zero#(n1)
time_b# = zero#(n2)

for i to n1
    rel = (i - 1) / max(1, n1 - 1)
    time_a#[i] = tmin1 + rel * duration1

    mf = 1 + round(rel * max(0, mfcc_frames1 - 1))
    inf = 1 + round(rel * max(0, intensity_frames1 - 1))
    pf = 1 + round(rel * max(0, pitch_frames1 - 1))

    for c to number_of_coefficients
        selectObject: mfcc1
        v = Get value in frame: mf, c
        if v = undefined
            v = 0
        endif
        idx = (i - 1) * number_of_coefficients + c
        mfcc_a#[idx] = v
    endfor

    selectObject: intensity1
    v = Get value in frame: inf
    if v = undefined
        v = -300
    endif
    db_a#[i] = v

    selectObject: pitch1
    f0 = Get value in frame: pf, "Hertz"
    if f0 <> undefined
        if f0 > 0
            pitch_st_a#[i] = 12 * ln(f0) / ln(2)
            voiced_a#[i] = 1
        endif
    endif
endfor

for j to n2
    rel = (j - 1) / max(1, n2 - 1)
    time_b#[j] = tmin2 + rel * duration2

    mf = 1 + round(rel * max(0, mfcc_frames2 - 1))
    inf = 1 + round(rel * max(0, intensity_frames2 - 1))
    pf = 1 + round(rel * max(0, pitch_frames2 - 1))

    for c to number_of_coefficients
        selectObject: mfcc2
        v = Get value in frame: mf, c
        if v = undefined
            v = 0
        endif
        idx = (j - 1) * number_of_coefficients + c
        mfcc_b#[idx] = v
    endfor

    selectObject: intensity2
    v = Get value in frame: inf
    if v = undefined
        v = -300
    endif
    db_b#[j] = v

    selectObject: pitch2
    f0 = Get value in frame: pf, "Hertz"
    if f0 <> undefined
        if f0 > 0
            pitch_st_b#[j] = 12 * ln(f0) / ln(2)
            voiced_b#[j] = 1
        endif
    endif
endfor

# The analysis objects are no longer needed after the sampled vectors exist.
removeObject: melspec1, melspec2, mfcc1, mfcc2, intensity1, intensity2, pitch1, pitch2

# =============================================================================
# NORMALIZATION / NUISANCE OFFSETS
# =============================================================================

# Pooled MFCC scaling preserves genuine between-sound timbral differences while
# preventing one coefficient from dominating only because of numeric scale.
mfcc_mean# = zero#(number_of_coefficients)
mfcc_sd# = zero#(number_of_coefficients)

for c to number_of_coefficients
    sum = 0
    count = 0
    for i to n1
        idx = (i - 1) * number_of_coefficients + c
        sum = sum + mfcc_a#[idx]
        count = count + 1
    endfor
    for j to n2
        idx = (j - 1) * number_of_coefficients + c
        sum = sum + mfcc_b#[idx]
        count = count + 1
    endfor
    mfcc_mean#[c] = sum / count

    ss = 0
    for i to n1
        idx = (i - 1) * number_of_coefficients + c
        d = mfcc_a#[idx] - mfcc_mean#[c]
        ss = ss + d * d
    endfor
    for j to n2
        idx = (j - 1) * number_of_coefficients + c
        d = mfcc_b#[idx] - mfcc_mean#[c]
        ss = ss + d * d
    endfor
    mfcc_sd#[c] = sqrt(ss / max(1, count - 1))
    if mfcc_sd#[c] < 1e-9
        mfcc_sd#[c] = 1
    endif
endfor

# Loudness alignment uses contour shape; absolute gain offset is measured later.
sum_db1 = 0
for i to n1
    sum_db1 = sum_db1 + db_a#[i]
endfor
mean_db1 = sum_db1 / n1

sum_db2 = 0
for j to n2
    sum_db2 = sum_db2 + db_b#[j]
endfor
mean_db2 = sum_db2 / n2

ss_db = 0
for i to n1
    d = db_a#[i] - mean_db1
    ss_db = ss_db + d * d
endfor
for j to n2
    d = db_b#[j] - mean_db2
    ss_db = ss_db + d * d
endfor
db_shape_sd = sqrt(ss_db / max(1, n1 + n2 - 2))
if db_shape_sd < 1
    db_shape_sd = 1
endif

# A robust seed transposition lets pitch guide timing without forcing the
# reference and test to be in the same key. The actual offset is measured
# again after DTW from the aligned pairs.
@medianPositive: pitch_st_a#, n1
median_pitch_a = medianPositive.result
@medianPositive: pitch_st_b#, n2
median_pitch_b = medianPositive.result

pitch_offset_seed = 0
if median_pitch_a <> undefined
    if median_pitch_b <> undefined
        pitch_offset_seed = median_pitch_b - median_pitch_a
    endif
endif

# =============================================================================
# REAL MULTI-FEATURE DTW
# =============================================================================

appendInfoLine: "Computing real multi-feature DTW..."

matrix_size = n1 * n2
cum# = zero#(matrix_size)
local_cost# = zero#(matrix_size)
for z to matrix_size
    cum#[z] = huge
    local_cost#[z] = huge
endfor

band_j = max(2, ceiling(warp_band_fraction * n2))

for i to n1
    expected_j = 1 + (i - 1) * (n2 - 1) / max(1, n1 - 1)
    j_start = max(1, floor(expected_j - band_j))
    j_end = min(n2, ceiling(expected_j + band_j))

    for j from j_start to j_end
        # MFCC: root-mean-square z-distance across coefficients.
        mfcc_ss = 0
        for c to number_of_coefficients
            idx_a = (i - 1) * number_of_coefficients + c
            idx_b = (j - 1) * number_of_coefficients + c
            dz = (mfcc_a#[idx_a] - mfcc_b#[idx_b]) / mfcc_sd#[c]
            mfcc_ss = mfcc_ss + dz * dz
        endfor
        mfcc_cost = sqrt(mfcc_ss / number_of_coefficients)

        # Loudness: compare contour after removing each sound's mean level.
        level_a = db_a#[i] - mean_db1
        level_b = db_b#[j] - mean_db2
        loud_cost = abs(level_a - level_b) / db_shape_sd

        # Pitch: compare contour after removing robust seed transposition.
        if voiced_a#[i] = 1
            if voiced_b#[j] = 1
                pitch_delta = (pitch_st_b#[j] - pitch_offset_seed) - pitch_st_a#[i]
                pitch_cost = min(4, abs(pitch_delta) / pitch_cost_scale_st)
            else
                pitch_cost = voicing_mismatch_cost
            endif
        else
            if voiced_b#[j] = 1
                pitch_cost = voicing_mismatch_cost
            else
                pitch_cost = 0
            endif
        endif

        local = mfcc_weight * mfcc_cost + loudness_weight * loud_cost + pitch_weight * pitch_cost
        idx = (i - 1) * n2 + j
        local_cost#[idx] = local

        if i = 1 and j = 1
            cum#[idx] = local
        else
            best = huge

            if i > 1
                up_idx = (i - 2) * n2 + j
                candidate = cum#[up_idx] + warp_step_penalty
                if candidate < best
                    best = candidate
                endif
            endif

            if j > 1
                left_idx = (i - 1) * n2 + j - 1
                candidate = cum#[left_idx] + warp_step_penalty
                if candidate < best
                    best = candidate
                endif
            endif

            if i > 1 and j > 1
                diag_idx = (i - 2) * n2 + j - 1
                candidate = cum#[diag_idx]
                if candidate < best
                    best = candidate
                endif
            endif

            if best < huge / 2
                cum#[idx] = local + best
            endif
        endif
    endfor
endfor

end_idx = (n1 - 1) * n2 + n2
if cum#[end_idx] >= huge / 2
    exitScript: "No DTW path found. Increase Warp band percent."
endif

# =============================================================================
# BACKTRACK THE ACTUAL PATH
# =============================================================================

max_path = n1 + n2 + 4
path_i# = zero#(max_path)
path_j# = zero#(max_path)
path_length = 0
i = n1
j = n2

while i > 1 or j > 1
    path_length = path_length + 1
    path_i#[path_length] = i
    path_j#[path_length] = j

    best = huge
    move = 0

    if i > 1 and j > 1
        diag_idx = (i - 2) * n2 + j - 1
        candidate = cum#[diag_idx]
        if candidate < best
            best = candidate
            move = 1
        endif
    endif

    if i > 1
        up_idx = (i - 2) * n2 + j
        candidate = cum#[up_idx] + warp_step_penalty
        if candidate < best
            best = candidate
            move = 2
        endif
    endif

    if j > 1
        left_idx = (i - 1) * n2 + j - 1
        candidate = cum#[left_idx] + warp_step_penalty
        if candidate < best
            best = candidate
            move = 3
        endif
    endif

    if move = 1
        i = i - 1
        j = j - 1
    elsif move = 2
        i = i - 1
    elsif move = 3
        j = j - 1
    else
        exitScript: "DTW backtracking failed."
    endif
endwhile

path_length = path_length + 1
path_i#[path_length] = 1
path_j#[path_length] = 1

# =============================================================================
# ALIGNED MEASUREMENTS
# =============================================================================

sum_local = 0
sum_mfcc = 0
sum_level_diff = 0
sum_level_abs = 0
sum_pitch_diff = 0
sum_pitch_abs = 0
pitch_pairs = 0
voicing_mismatches = 0
warp_sum = 0

path_mfcc# = zero#(path_length)
path_level_diff# = zero#(path_length)
path_pitch_diff# = zero#(path_length)
path_pitch_valid# = zero#(path_length)
path_local# = zero#(path_length)
path_ref_progress# = zero#(path_length)
path_test_progress# = zero#(path_length)

for step to path_length
    k = path_length - step + 1
    i = path_i#[k]
    j = path_j#[k]

    ref_progress = (i - 1) / max(1, n1 - 1)
    test_progress = (j - 1) / max(1, n2 - 1)
    path_ref_progress#[step] = ref_progress
    path_test_progress#[step] = test_progress
    warp_sum = warp_sum + abs(ref_progress - test_progress)

    idx = (i - 1) * n2 + j
    local = local_cost#[idx]
    path_local#[step] = local
    sum_local = sum_local + local

    mfcc_ss = 0
    for c to number_of_coefficients
        idx_a = (i - 1) * number_of_coefficients + c
        idx_b = (j - 1) * number_of_coefficients + c
        dz = (mfcc_a#[idx_a] - mfcc_b#[idx_b]) / mfcc_sd#[c]
        mfcc_ss = mfcc_ss + dz * dz
    endfor
    mfcc_dist = sqrt(mfcc_ss / number_of_coefficients)
    path_mfcc#[step] = mfcc_dist
    sum_mfcc = sum_mfcc + mfcc_dist

    level_diff = db_b#[j] - db_a#[i]
    path_level_diff#[step] = level_diff
    sum_level_diff = sum_level_diff + level_diff
    sum_level_abs = sum_level_abs + abs(level_diff)

    if voiced_a#[i] = 1
        if voiced_b#[j] = 1
            pdiff = pitch_st_b#[j] - pitch_st_a#[i]
            path_pitch_diff#[step] = pdiff
            path_pitch_valid#[step] = 1
            sum_pitch_diff = sum_pitch_diff + pdiff
            sum_pitch_abs = sum_pitch_abs + abs(pdiff)
            pitch_pairs = pitch_pairs + 1
        else
            voicing_mismatches = voicing_mismatches + 1
        endif
    else
        if voiced_b#[j] = 1
            voicing_mismatches = voicing_mismatches + 1
        endif
    endif
endfor

mean_local_cost = sum_local / path_length
mean_mfcc_distance = sum_mfcc / path_length
level_offset_db = sum_level_diff / path_length
raw_level_mae_db = sum_level_abs / path_length
warp_deviation_percent = 100 * warp_sum / path_length
voicing_mismatch_percent = 100 * voicing_mismatches / path_length

pitch_offset_st = undefined
raw_pitch_mae_st = undefined
pitch_contour_mae_st = undefined
if pitch_pairs > 0
    pitch_offset_st = sum_pitch_diff / pitch_pairs
    raw_pitch_mae_st = sum_pitch_abs / pitch_pairs
endif

sum_level_shape_abs = 0
sum_pitch_shape_abs = 0
for step to path_length
    sum_level_shape_abs = sum_level_shape_abs + abs(path_level_diff#[step] - level_offset_db)
    if path_pitch_valid#[step] = 1
        sum_pitch_shape_abs = sum_pitch_shape_abs + abs(path_pitch_diff#[step] - pitch_offset_st)
    endif
endfor
level_contour_mae_db = sum_level_shape_abs / path_length
if pitch_pairs > 0
    pitch_contour_mae_st = sum_pitch_shape_abs / pitch_pairs
endif

normalized_total_cost = cum#[end_idx] / path_length

# =============================================================================
# OUTPUT TABLES
# =============================================================================

alignment_table = Create Table with column names: "DTW_Alignment", path_length, "step ref_time_s test_time_s ref_progress_pct test_progress_pct local_cost mfcc_zdistance level_diff_dB pitch_diff_st voiced_pair voicing_mismatch"

for step to path_length
    k = path_length - step + 1
    i = path_i#[k]
    j = path_j#[k]

    selectObject: alignment_table
    Set numeric value: step, "step", step
    Set numeric value: step, "ref_time_s", time_a#[i]
    Set numeric value: step, "test_time_s", time_b#[j]
    Set numeric value: step, "ref_progress_pct", 100 * path_ref_progress#[step]
    Set numeric value: step, "test_progress_pct", 100 * path_test_progress#[step]
    Set numeric value: step, "local_cost", path_local#[step]
    Set numeric value: step, "mfcc_zdistance", path_mfcc#[step]
    Set numeric value: step, "level_diff_dB", path_level_diff#[step]

    if path_pitch_valid#[step] = 1
        Set numeric value: step, "pitch_diff_st", path_pitch_diff#[step]
        Set numeric value: step, "voiced_pair", 1
        Set numeric value: step, "voicing_mismatch", 0
    else
        Set numeric value: step, "pitch_diff_st", undefined
        Set numeric value: step, "voiced_pair", 0
        k2 = path_length - step + 1
        i2 = path_i#[k2]
        j2 = path_j#[k2]
        mismatch = 0
        if voiced_a#[i2] <> voiced_b#[j2]
            mismatch = 1
        endif
        Set numeric value: step, "voicing_mismatch", mismatch
    endif
endfor

summary_table = Create Table with column names: "DTW_Summary", 14, "metric value unit"

selectObject: summary_table
Set string value: 1, "metric", "duration_ratio_test_over_ref"
Set numeric value: 1, "value", duration_ratio
Set string value: 1, "unit", "ratio"

Set string value: 2, "metric", "dtw_mean_local_cost"
Set numeric value: 2, "value", mean_local_cost
Set string value: 2, "unit", "normalized"

Set string value: 3, "metric", "dtw_total_cost_per_path_step"
Set numeric value: 3, "value", normalized_total_cost
Set string value: 3, "unit", "normalized"

Set string value: 4, "metric", "mfcc_path_distance"
Set numeric value: 4, "value", mean_mfcc_distance
Set string value: 4, "unit", "z_rms"

Set string value: 5, "metric", "level_offset"
Set numeric value: 5, "value", level_offset_db
Set string value: 5, "unit", "dB"

Set string value: 6, "metric", "level_raw_mae"
Set numeric value: 6, "value", raw_level_mae_db
Set string value: 6, "unit", "dB"

Set string value: 7, "metric", "level_contour_mae_after_offset"
Set numeric value: 7, "value", level_contour_mae_db
Set string value: 7, "unit", "dB"

Set string value: 8, "metric", "pitch_offset"
Set numeric value: 8, "value", pitch_offset_st
Set string value: 8, "unit", "semitones"

Set string value: 9, "metric", "pitch_raw_mae"
Set numeric value: 9, "value", raw_pitch_mae_st
Set string value: 9, "unit", "semitones"

Set string value: 10, "metric", "pitch_contour_mae_after_offset"
Set numeric value: 10, "value", pitch_contour_mae_st
Set string value: 10, "unit", "semitones"

Set string value: 11, "metric", "voicing_mismatch"
Set numeric value: 11, "value", voicing_mismatch_percent
Set string value: 11, "unit", "percent"

Set string value: 12, "metric", "nonlinear_warp_deviation"
Set numeric value: 12, "value", warp_deviation_percent
Set string value: 12, "unit", "percentage_points"

Set string value: 13, "metric", "path_length"
Set numeric value: 13, "value", path_length
Set string value: 13, "unit", "steps"

Set string value: 14, "metric", "valid_pitch_pairs"
Set numeric value: 14, "value", pitch_pairs
Set string value: 14, "unit", "pairs"

# =============================================================================
# INFO SUMMARY
# =============================================================================

appendInfoLine: ""
appendInfoLine: "=== DTW MEASUREMENTS ==="
appendInfoLine: "Mean combined local cost: ", fixed$(mean_local_cost, 3)
appendInfoLine: "MFCC path distance: ", fixed$(mean_mfcc_distance, 3), " z-RMS"
appendInfoLine: "Level offset (test-ref): ", fixed$(level_offset_db, 2), " dB"
appendInfoLine: "Level contour MAE after offset: ", fixed$(level_contour_mae_db, 2), " dB"
if pitch_pairs > 0
    appendInfoLine: "Pitch offset (test-ref): ", fixed$(pitch_offset_st, 2), " st"
    appendInfoLine: "Pitch contour MAE after offset: ", fixed$(pitch_contour_mae_st, 2), " st"
else
    appendInfoLine: "Pitch offset/contour: NA (no aligned voiced pairs)"
endif
appendInfoLine: "Voicing mismatch: ", fixed$(voicing_mismatch_percent, 1), "%"
appendInfoLine: "Nonlinear warp deviation: ", fixed$(warp_deviation_percent, 1), " percentage points"
appendInfoLine: "Path length: ", path_length, " steps"
appendInfoLine: ""

# =============================================================================
# VISUALIZATION
# =============================================================================

if draw_visualization
    Erase all

    # Title
    Select outer viewport: 0, 8, 0.00, 0.48
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.62, "half", "##DTW-Aligned Multi-Feature Audio Analysis##"

    # Metadata
    Select outer viewport: 0, 8, 0.48, 0.88
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.35, 0.35, 0.42}"
    metadata$ = "Ref " + display1$ + "  |  Test " + display2$ + "  |  MFCC/Loud/Pitch " + fixed$(mfcc_weight, 2) + "/" + fixed$(loudness_weight, 2) + "/" + fixed$(pitch_weight, 2) + "  |  band " + fixed$(100 * warp_band_fraction, 0) + " pct"
    Text: 0.5, "centre", 0.58, "half", metadata$

    # -------------------------------------------------------------------------
    # Panel 1: real DTW path
    # -------------------------------------------------------------------------
    Select outer viewport: 0, 4, 0.92, 3.92
    Select inner viewport: 0.62, 3.76, 1.22, 3.62
    Axes: 0, 100, 0, 100
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, 100, 0, 100

    Colour: "{0.72, 0.72, 0.74}"
    Dashed line
    Draw line: 0, 0, 100, 100
    Solid line

    Colour: "{0.20, 0.42, 0.72}"
    Line width: 2
    for step from 2 to path_length
        x1 = 100 * path_ref_progress#[step - 1]
        y1 = 100 * path_test_progress#[step - 1]
        x2 = 100 * path_ref_progress#[step]
        y2 = 100 * path_test_progress#[step]
        Draw line: x1, y1, x2, y2
    endfor
    Line width: 1

    Paint circle (mm): "Black", 0, 0, 1.0
    Paint circle (mm): "Black", 100, 100, 1.0

    Select inner viewport: 0.62, 3.76, 1.22, 3.62
    Axes: 0, 100, 0, 100
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.62, 3.76, 1.22, 3.62
    Axes: 0, 100, 0, 100
    Font size: 7
    Marks left every: 1, 25, "yes", "yes", "no"
    Marks bottom every: 1, 25, "yes", "yes", "no"
    Text left: "yes", "Test progress (pct)"
    Text bottom: "yes", "Reference progress (pct)"

    Select outer viewport: 0.62, 3.76, 0.96, 1.18
    Axes: 0, 1, 0, 1
    Font size: 9
    Text: 0.5, "centre", 0.58, "half", "##Measured DTW path##   grey = no nonlinear warp"

    # -------------------------------------------------------------------------
    # Panel 2: local feature cost along the aligned path
    # -------------------------------------------------------------------------
    cost_max = 0.1
    for step to path_length
        if path_local#[step] > cost_max
            cost_max = path_local#[step]
        endif
        if path_mfcc#[step] > cost_max
            cost_max = path_mfcc#[step]
        endif
    endfor
    cost_max = cost_max * 1.08

    Select outer viewport: 4, 8, 0.92, 3.92
    Select inner viewport: 4.58, 7.76, 1.22, 3.62
    Axes: 0, 100, 0, cost_max
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, 100, 0, cost_max

    Colour: "{0.20, 0.42, 0.72}"
    Line width: 1.7
    for step from 2 to path_length
        Draw line: 100 * path_ref_progress#[step - 1], path_local#[step - 1], 100 * path_ref_progress#[step], path_local#[step]
    endfor

    Colour: "{0.72, 0.35, 0.20}"
    Line width: 1
    for step from 2 to path_length
        Draw line: 100 * path_ref_progress#[step - 1], path_mfcc#[step - 1], 100 * path_ref_progress#[step], path_mfcc#[step]
    endfor
    Line width: 1

    Select inner viewport: 4.58, 7.76, 1.22, 3.62
    Axes: 0, 100, 0, cost_max
    Colour: "Black"
    Draw inner box
    Select inner viewport: 4.58, 7.76, 1.22, 3.62
    Axes: 0, 100, 0, cost_max
    Font size: 7
    Marks left: 3, "yes", "yes", "no"
    Marks bottom every: 1, 25, "yes", "yes", "no"
    Text left: "yes", "Normalized cost"
    Text bottom: "yes", "Reference progress (pct)"

    Select outer viewport: 4.58, 7.76, 0.96, 1.18
    Axes: 0, 1, 0, 1
    Font size: 9
    Text: 0.5, "centre", 0.58, "half", "##Aligned feature cost##   blue=combined   orange=MFCC"

    # -------------------------------------------------------------------------
    # Panel 3: pitch residual after removing measured transposition
    # -------------------------------------------------------------------------
    pitch_err_max = 1
    if pitch_pairs > 0
        for step to path_length
            if path_pitch_valid#[step] = 1
                pe = abs(path_pitch_diff#[step] - pitch_offset_st)
                if pe > pitch_err_max
                    pitch_err_max = pe
                endif
            endif
        endfor
    endif
    pitch_err_max = min(max(1, pitch_err_max * 1.08), 24)

    Select outer viewport: 0, 4, 4.00, 6.58
    Select inner viewport: 0.62, 3.76, 4.31, 6.27
    Axes: 0, 100, -pitch_err_max, pitch_err_max
    Paint rectangle: "{0.98, 0.98, 0.98}", 0, 100, -pitch_err_max, pitch_err_max
    Colour: "{0.72, 0.72, 0.72}"
    Dotted line
    Draw line: 0, 0, 100, 0
    Solid line

    Colour: "{0.28, 0.50, 0.35}"
    Line width: 1.5
    have_prev = 0
    prev_x = 0
    prev_y = 0
    for step to path_length
        if path_pitch_valid#[step] = 1
            x = 100 * path_ref_progress#[step]
            y = path_pitch_diff#[step] - pitch_offset_st
            if have_prev = 1
                Draw line: prev_x, prev_y, x, y
            endif
            prev_x = x
            prev_y = y
            have_prev = 1
        else
            have_prev = 0
        endif
    endfor
    Line width: 1

    Select inner viewport: 0.62, 3.76, 4.31, 6.27
    Axes: 0, 100, -pitch_err_max, pitch_err_max
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.62, 3.76, 4.31, 6.27
    Axes: 0, 100, -pitch_err_max, pitch_err_max
    Font size: 7
    Marks left: 3, "yes", "yes", "no"
    Marks bottom every: 1, 25, "yes", "yes", "no"
    Text left: "yes", "Pitch residual (st)"
    Text bottom: "yes", "Reference progress (pct)"

    Select outer viewport: 0.62, 3.76, 4.04, 4.27
    Axes: 0, 1, 0, 1
    Font size: 9
    Text: 0.5, "centre", 0.58, "half", "##Pitch contour error##   transposition removed"

    # -------------------------------------------------------------------------
    # Panel 4: level residual after removing measured gain offset
    # -------------------------------------------------------------------------
    level_err_max = 3
    for step to path_length
        le = abs(path_level_diff#[step] - level_offset_db)
        if le > level_err_max
            level_err_max = le
        endif
    endfor
    level_err_max = min(max(3, level_err_max * 1.08), 60)

    Select outer viewport: 4, 8, 4.00, 6.58
    Select inner viewport: 4.58, 7.76, 4.31, 6.27
    Axes: 0, 100, -level_err_max, level_err_max
    Paint rectangle: "{0.98, 0.98, 0.98}", 0, 100, -level_err_max, level_err_max
    Colour: "{0.72, 0.72, 0.72}"
    Dotted line
    Draw line: 0, 0, 100, 0
    Solid line

    Colour: "{0.42, 0.42, 0.68}"
    Line width: 1.5
    for step from 2 to path_length
        y1 = path_level_diff#[step - 1] - level_offset_db
        y2 = path_level_diff#[step] - level_offset_db
        Draw line: 100 * path_ref_progress#[step - 1], y1, 100 * path_ref_progress#[step], y2
    endfor
    Line width: 1

    Select inner viewport: 4.58, 7.76, 4.31, 6.27
    Axes: 0, 100, -level_err_max, level_err_max
    Colour: "Black"
    Draw inner box
    Select inner viewport: 4.58, 7.76, 4.31, 6.27
    Axes: 0, 100, -level_err_max, level_err_max
    Font size: 7
    Marks left: 3, "yes", "yes", "no"
    Marks bottom every: 1, 25, "yes", "yes", "no"
    Text left: "yes", "Level residual (dB)"
    Text bottom: "yes", "Reference progress (pct)"

    Select outer viewport: 4.58, 7.76, 4.04, 4.27
    Axes: 0, 1, 0, 1
    Font size: 9
    Text: 0.5, "centre", 0.58, "half", "##Loudness contour error##   gain offset removed"

    # Summary strip
    Select outer viewport: 0, 8, 6.70, 7.92
    Select inner viewport: 0.48, 7.55, 6.80, 7.82
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 9
    Text: 0.02, "left", 0.78, "half", "##DTW measurement summary##"
    Font size: 8
    line1$ = "MFCC " + fixed$(mean_mfcc_distance, 2) + " z-RMS   |   level offset " + fixed$(level_offset_db, 1) + " dB   |   level contour MAE " + fixed$(level_contour_mae_db, 1) + " dB"
    Text: 0.02, "left", 0.49, "half", line1$

    if pitch_pairs > 0
        pitch_summary$ = "pitch offset " + fixed$(pitch_offset_st, 1) + " st   |   pitch contour MAE " + fixed$(pitch_contour_mae_st, 2) + " st"
    else
        pitch_summary$ = "pitch: NA (no aligned voiced pairs)"
    endif
    line2$ = pitch_summary$ + "   |   warp dev " + fixed$(warp_deviation_percent, 1) + " pp   |   voice mismatch " + fixed$(voicing_mismatch_percent, 1) + " pct"
    Text: 0.02, "left", 0.21, "half", line2$
endif

# =============================================================================
# CLEANUP / FINAL SELECTION
# =============================================================================

if analysis1_is_copy
    removeObject: analysis1
endif
if analysis2_is_copy
    removeObject: analysis2
endif

selectObject: sound1
plusObject: sound2
plusObject: summary_table
plusObject: alignment_table

appendInfoLine: "Outputs: Table DTW_Summary + Table DTW_Alignment"
appendInfoLine: "Done."
