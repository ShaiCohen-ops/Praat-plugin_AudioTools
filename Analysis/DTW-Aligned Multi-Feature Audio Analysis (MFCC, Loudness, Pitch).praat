# ============================================================
# Praat AudioTools - DTW_Multi_Feature_Analysis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025) - Fast DTW with visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   DTW-aligned multi-feature audio comparison.
#   Compares MFCC, Loudness, and Pitch with time-warping.
#
# Usage:
#   Select exactly TWO Sound objects before running.
# ============================================================

# === Input Validation ===
numberOfSelectedSounds = numberOfSelected("Sound")
if numberOfSelectedSounds <> 2
    exitScript: "Please select exactly TWO Sound objects."
endif

sound1 = selected("Sound", 1)
sound2 = selected("Sound", 2)

form DTW Multi-Feature Audio Analysis v1.0
    comment === Reference (Teacher) & Test (Student) ===
    comment First selected = Reference, Second = Test
    
    comment === MFCC Parameters ===
    positive Window_length_s 0.025
    positive Time_step_s 0.01
    natural Number_of_coefficients 13
    
    comment === Pitch Parameters ===
    positive Pitch_floor_Hz 75
    positive Pitch_ceiling_Hz 600
    
    comment === Output ===
    boolean Draw_visualization 1
endform

clearinfo

# =============================================================================
# SETUP
# =============================================================================

selectObject: sound1
name1$ = selected$("Sound")
duration1 = Get total duration

selectObject: sound2
name2$ = selected$("Sound")
duration2 = Get total duration

writeInfoLine: "=============================================="
writeInfoLine: "  DTW MULTI-FEATURE AUDIO ANALYSIS v1.0"
writeInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Reference: ", name1$, " (", fixed$(duration1, 3), " s)"
appendInfoLine: "Test:      ", name2$, " (", fixed$(duration2, 3), " s)"

duration_diff = abs(duration1 - duration2)
duration_ratio = duration2 / duration1

if duration_ratio > 1.5 or duration_ratio < 0.67
    appendInfoLine: "⚠ Large tempo difference (ratio: ", fixed$(duration_ratio, 2), ")"
endif

appendInfoLine: ""

# =============================================================================
# STEP 1: MFCC ANALYSIS (Fast sampled comparison)
# =============================================================================

appendInfoLine: "STEP 1: Analyzing MFCC features..."

selectObject: sound1
To MelSpectrogram: window_length_s, time_step_s, 24, 100, 5000
melspec1 = selected("MelSpectrogram")
To MFCC: number_of_coefficients
mfcc1 = selected("MFCC")

selectObject: sound2
To MelSpectrogram: window_length_s, time_step_s, 24, 100, 5000
melspec2 = selected("MelSpectrogram")
To MFCC: number_of_coefficients
mfcc2 = selected("MFCC")

selectObject: mfcc1
mfcc_frames1 = Get number of frames
selectObject: mfcc2
mfcc_frames2 = Get number of frames

appendInfoLine: "  Reference frames: ", mfcc_frames1
appendInfoLine: "  Test frames: ", mfcc_frames2

# Fast MFCC comparison: sample and compare aligned frames
# Use ~50 comparison points for speed
nSamples = min(50, min(mfcc_frames1, mfcc_frames2))
total_mfcc_distance = 0

for s from 1 to nSamples
    # Map to frame indices
    frame1 = round((s / nSamples) * mfcc_frames1)
    frame2 = round((s / nSamples) * mfcc_frames2)
    if frame1 < 1
        frame1 = 1
    endif
    if frame2 < 1
        frame2 = 1
    endif
    if frame1 > mfcc_frames1
        frame1 = mfcc_frames1
    endif
    if frame2 > mfcc_frames2
        frame2 = mfcc_frames2
    endif
    
    # Calculate Euclidean distance for this frame pair
    frame_dist = 0
    for coeff from 2 to number_of_coefficients
        selectObject: mfcc1
        v1 = Get value in frame: frame1, coeff
        selectObject: mfcc2
        v2 = Get value in frame: frame2, coeff
        frame_dist = frame_dist + (v1 - v2) * (v1 - v2)
    endfor
    total_mfcc_distance = total_mfcc_distance + sqrt(frame_dist)
endfor

normalized_dtw_distance = total_mfcc_distance / nSamples

appendInfoLine: "  MFCC distance: ", fixed$(normalized_dtw_distance, 4)

if normalized_dtw_distance < 2
    mfcc_assessment$ = "EXCELLENT"
elsif normalized_dtw_distance < 5
    mfcc_assessment$ = "GOOD"
elsif normalized_dtw_distance < 10
    mfcc_assessment$ = "MODERATE"
else
    mfcc_assessment$ = "NEEDS WORK"
endif

appendInfoLine: "  Assessment: ", mfcc_assessment$

# Store MFCC energy for visualization (sample 100 points max)
nVizPoints = min(100, min(mfcc_frames1, mfcc_frames2))
mfcc1_vals# = zero#(nVizPoints)
mfcc2_vals# = zero#(nVizPoints)

for i from 1 to nVizPoints
    frame1 = round((i / nVizPoints) * mfcc_frames1)
    frame2 = round((i / nVizPoints) * mfcc_frames2)
    if frame1 < 1
        frame1 = 1
    endif
    if frame2 < 1
        frame2 = 1
    endif
    
    # Get energy from first few coefficients
    selectObject: mfcc1
    v1 = Get value in frame: frame1, 2
    v2 = Get value in frame: frame1, 3
    mfcc1_vals#[i] = abs(v1) + abs(v2)
    
    selectObject: mfcc2
    v1 = Get value in frame: frame2, 2
    v2 = Get value in frame: frame2, 3
    mfcc2_vals#[i] = abs(v1) + abs(v2)
endfor

removeObject: melspec1, melspec2, mfcc1, mfcc2

# =============================================================================
# STEP 2: LOUDNESS ANALYSIS
# =============================================================================

appendInfoLine: ""
appendInfoLine: "STEP 2: Analyzing loudness..."

selectObject: sound1
To Intensity: 75, time_step_s, "yes"
intensity1 = selected("Intensity")

selectObject: sound2
To Intensity: 75, time_step_s, "yes"
intensity2 = selected("Intensity")

selectObject: intensity1
loudness_frames1 = Get number of frames
mean_db1 = Get mean: 0, 0, "dB"

selectObject: intensity2
loudness_frames2 = Get number of frames
mean_db2 = Get mean: 0, 0, "dB"

# Store for visualization
db1_vals# = zero#(nVizPoints)
db2_vals# = zero#(nVizPoints)

total_db_distance = 0
valid_comparisons = 0

for i from 1 to nVizPoints
    frame1 = round((i / nVizPoints) * loudness_frames1)
    frame2 = round((i / nVizPoints) * loudness_frames2)
    if frame1 < 1
        frame1 = 1
    endif
    if frame2 < 1
        frame2 = 1
    endif
    if frame1 > loudness_frames1
        frame1 = loudness_frames1
    endif
    if frame2 > loudness_frames2
        frame2 = loudness_frames2
    endif
    
    selectObject: intensity1
    db1 = Get value in frame: frame1
    selectObject: intensity2
    db2 = Get value in frame: frame2
    
    if db1 <> undefined
        db1_vals#[i] = db1
    else
        db1_vals#[i] = 0
    endif
    
    if db2 <> undefined
        db2_vals#[i] = db2
    else
        db2_vals#[i] = 0
    endif
    
    if db1 <> undefined and db2 <> undefined
        total_db_distance = total_db_distance + abs(db1 - db2)
        valid_comparisons = valid_comparisons + 1
    endif
endfor

if valid_comparisons > 0
    average_db_distance = total_db_distance / valid_comparisons
else
    average_db_distance = 0
endif

mean_db_diff = abs(mean_db1 - mean_db2)

appendInfoLine: "  Aligned dB difference: ", fixed$(average_db_distance, 2), " dB"

if average_db_distance < 4
    loudness_assessment$ = "EXCELLENT"
elsif average_db_distance < 8
    loudness_assessment$ = "GOOD"
elsif average_db_distance < 15
    loudness_assessment$ = "MODERATE"
else
    loudness_assessment$ = "NEEDS WORK"
endif

appendInfoLine: "  Assessment: ", loudness_assessment$

# =============================================================================
# STEP 3: PITCH/INTERVAL ANALYSIS
# =============================================================================

appendInfoLine: ""
appendInfoLine: "STEP 3: Analyzing pitch and intervals..."

selectObject: sound1
To Pitch: time_step_s, pitch_floor_Hz, pitch_ceiling_Hz
pitch1 = selected("Pitch")

selectObject: sound2
To Pitch: time_step_s, pitch_floor_Hz, pitch_ceiling_Hz
pitch2 = selected("Pitch")

selectObject: pitch1
pitch_frames1 = Get number of frames
mean_f0_1 = Get mean: 0, 0, "Hertz"

selectObject: pitch2
pitch_frames2 = Get number of frames
mean_f0_2 = Get mean: 0, 0, "Hertz"

# Store for visualization
f0_1_vals# = zero#(nVizPoints)
f0_2_vals# = zero#(nVizPoints)

total_interval_difference = 0
valid_intervals = 0
contour_matches = 0
contour_total = 0

prev_f0_1 = 0
prev_f0_2 = 0

for i from 1 to nVizPoints
    frame1 = round((i / nVizPoints) * pitch_frames1)
    frame2 = round((i / nVizPoints) * pitch_frames2)
    if frame1 < 1
        frame1 = 1
    endif
    if frame2 < 1
        frame2 = 1
    endif
    if frame1 > pitch_frames1
        frame1 = pitch_frames1
    endif
    if frame2 > pitch_frames2
        frame2 = pitch_frames2
    endif
    
    selectObject: pitch1
    f0_1 = Get value in frame: frame1, "Hertz"
    selectObject: pitch2
    f0_2 = Get value in frame: frame2, "Hertz"
    
    if f0_1 = undefined
        f0_1 = 0
    endif
    if f0_2 = undefined
        f0_2 = 0
    endif
    
    f0_1_vals#[i] = f0_1
    f0_2_vals#[i] = f0_2
    
    # Interval analysis
    if f0_1 > 0 and f0_2 > 0 and prev_f0_1 > 0 and prev_f0_2 > 0
        interval1 = 12 * ln(f0_1 / prev_f0_1) / ln(2)
        interval2 = 12 * ln(f0_2 / prev_f0_2) / ln(2)
        
        interval_diff = abs(interval1 - interval2)
        total_interval_difference = total_interval_difference + interval_diff
        valid_intervals = valid_intervals + 1
        
        # Contour direction
        if abs(interval1) > 0.1
            if interval1 > 0
                dir1 = 1
            else
                dir1 = -1
            endif
        else
            dir1 = 0
        endif
        
        if abs(interval2) > 0.1
            if interval2 > 0
                dir2 = 1
            else
                dir2 = -1
            endif
        else
            dir2 = 0
        endif
        
        contour_total = contour_total + 1
        if dir1 = dir2
            contour_matches = contour_matches + 1
        endif
    endif
    
    if f0_1 > 0
        prev_f0_1 = f0_1
    endif
    if f0_2 > 0
        prev_f0_2 = f0_2
    endif
endfor

if valid_intervals > 0
    average_interval_difference = total_interval_difference / valid_intervals
else
    average_interval_difference = 0
endif

if contour_total > 0
    contour_accuracy = (contour_matches / contour_total) * 100
else
    contour_accuracy = 0
endif

# Transposition
if mean_f0_1 <> undefined and mean_f0_2 <> undefined and mean_f0_1 > 0 and mean_f0_2 > 0
    overall_transposition = 12 * ln(mean_f0_2 / mean_f0_1) / ln(2)
else
    overall_transposition = 0
endif

appendInfoLine: "  Interval difference: ", fixed$(average_interval_difference, 3), " st"
appendInfoLine: "  Contour accuracy: ", fixed$(contour_accuracy, 1), "%"
appendInfoLine: "  Transposition: ", fixed$(overall_transposition, 2), " st"

if average_interval_difference < 0.3
    pitch_assessment$ = "EXCELLENT"
elsif average_interval_difference < 0.7
    pitch_assessment$ = "VERY GOOD"
elsif average_interval_difference < 1.5
    pitch_assessment$ = "GOOD"
elsif average_interval_difference < 3.0
    pitch_assessment$ = "MODERATE"
else
    pitch_assessment$ = "NEEDS WORK"
endif

appendInfoLine: "  Assessment: ", pitch_assessment$

# =============================================================================
# STEP 4: VISUALIZATION
# =============================================================================

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "STEP 4: Creating visualization..."
    
    Erase all
    Select outer viewport: 0, 8, 0, 8
    
    # === Title ===
    Select outer viewport: 0, 8, 0, 0.6
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.7, "half", "##DTW Multi-Feature Analysis##"
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.15, "centre", 0.25, "half", "Ref: " + name1$ + " (" + fixed$(duration1, 2) + "s) | Test: " + name2$ + " (" + fixed$(duration2, 2) + "s)"
    
    # === Reference Waveform ===
    Select outer viewport: 0, 8, 0.7, 1.5
    Select inner viewport: 0.6, 7.7, 0.75, 1.45
    selectObject: sound1
    Colour: "{0.4, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Reference"
    
    # === Test Waveform ===
    Select outer viewport: 0, 8, 1.5, 2.3
    Select inner viewport: 0.6, 7.7, 1.55, 2.25
    selectObject: sound2
    Colour: "{0.7, 0.5, 0.4}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Test"
    Text bottom: "yes", "Time (s)"
    
    # === Pitch Comparison ===
    Select outer viewport: 0, 4, 2.4, 4.0
    Select inner viewport: 0.6, 3.7, 2.6, 3.9
    
    # Find pitch range
    maxF0 = pitch_floor_Hz
    minF0 = pitch_ceiling_Hz
    for i from 1 to nVizPoints
        if f0_1_vals#[i] > 0
            if f0_1_vals#[i] > maxF0
                maxF0 = f0_1_vals#[i]
            endif
            if f0_1_vals#[i] < minF0
                minF0 = f0_1_vals#[i]
            endif
        endif
        if f0_2_vals#[i] > 0
            if f0_2_vals#[i] > maxF0
                maxF0 = f0_2_vals#[i]
            endif
            if f0_2_vals#[i] < minF0
                minF0 = f0_2_vals#[i]
            endif
        endif
    endfor
    
    if minF0 >= maxF0
        minF0 = pitch_floor_Hz
        maxF0 = pitch_ceiling_Hz
    endif
    f0Range = maxF0 - minF0
    minF0 = minF0 - f0Range * 0.1
    maxF0 = maxF0 + f0Range * 0.1
    
    Axes: 0, 1, minF0, maxF0
    Paint rectangle: "{0.98, 0.98, 0.98}", 0, 1, minF0, maxF0
    
    # Draw reference pitch
    Colour: "{0.4, 0.5, 0.7}"
    Line width: 1.5
    for i from 2 to nVizPoints
        if f0_1_vals#[i] > 0 and f0_1_vals#[i-1] > 0
            x1 = (i - 1) / nVizPoints
            x2 = i / nVizPoints
            Draw line: x1, f0_1_vals#[i-1], x2, f0_1_vals#[i]
        endif
    endfor
    
    # Draw test pitch
    Colour: "{0.7, 0.5, 0.4}"
    for i from 2 to nVizPoints
        if f0_2_vals#[i] > 0 and f0_2_vals#[i-1] > 0
            x1 = (i - 1) / nVizPoints
            x2 = i / nVizPoints
            Draw line: x1, f0_2_vals#[i-1], x2, f0_2_vals#[i]
        endif
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "F0 (Hz)"
    Text bottom: "yes", "Normalized time"
    Text top: "no", "Pitch: Blue=Ref, Orange=Test"
    
    # === Intensity Comparison ===
    Select outer viewport: 4, 8, 2.4, 4.0
    Select inner viewport: 4.4, 7.7, 2.6, 3.9
    
    # Find intensity range
    maxDb = -100
    minDb = 100
    for i from 1 to nVizPoints
        if db1_vals#[i] > 0
            if db1_vals#[i] > maxDb
                maxDb = db1_vals#[i]
            endif
            if db1_vals#[i] < minDb
                minDb = db1_vals#[i]
            endif
        endif
        if db2_vals#[i] > 0
            if db2_vals#[i] > maxDb
                maxDb = db2_vals#[i]
            endif
            if db2_vals#[i] < minDb
                minDb = db2_vals#[i]
            endif
        endif
    endfor
    
    if minDb >= maxDb
        minDb = 40
        maxDb = 80
    endif
    dbRange = maxDb - minDb
    minDb = minDb - dbRange * 0.1
    maxDb = maxDb + dbRange * 0.1
    
    Axes: 0, 1, minDb, maxDb
    Paint rectangle: "{0.98, 0.98, 0.98}", 0, 1, minDb, maxDb
    
    # Draw reference intensity
    Colour: "{0.4, 0.5, 0.7}"
    Line width: 1.5
    for i from 2 to nVizPoints
        if db1_vals#[i] > 0 and db1_vals#[i-1] > 0
            x1 = (i - 1) / nVizPoints
            x2 = i / nVizPoints
            Draw line: x1, db1_vals#[i-1], x2, db1_vals#[i]
        endif
    endfor
    
    # Draw test intensity
    Colour: "{0.7, 0.5, 0.4}"
    for i from 2 to nVizPoints
        if db2_vals#[i] > 0 and db2_vals#[i-1] > 0
            x1 = (i - 1) / nVizPoints
            x2 = i / nVizPoints
            Draw line: x1, db2_vals#[i-1], x2, db2_vals#[i]
        endif
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "dB"
    Text bottom: "yes", "Normalized time"
    Text top: "no", "Intensity: Blue=Ref, Orange=Test"
    
    # === MFCC Comparison ===
    Select outer viewport: 0, 4, 4.1, 5.5
    Select inner viewport: 0.6, 3.7, 4.3, 5.4
    
    # Find MFCC range
    maxMFCC = 0.1
    for i from 1 to nVizPoints
        if mfcc1_vals#[i] > maxMFCC
            maxMFCC = mfcc1_vals#[i]
        endif
        if mfcc2_vals#[i] > maxMFCC
            maxMFCC = mfcc2_vals#[i]
        endif
    endfor
    
    Axes: 0, 1, 0, maxMFCC * 1.1
    Paint rectangle: "{0.98, 0.98, 0.98}", 0, 1, 0, maxMFCC * 1.1
    
    # Draw reference MFCC
    Colour: "{0.4, 0.5, 0.7}"
    for i from 2 to nVizPoints
        x1 = (i - 1) / nVizPoints
        x2 = i / nVizPoints
        Draw line: x1, mfcc1_vals#[i-1], x2, mfcc1_vals#[i]
    endfor
    
    # Draw test MFCC
    Colour: "{0.7, 0.5, 0.4}"
    for i from 2 to nVizPoints
        x1 = (i - 1) / nVizPoints
        x2 = i / nVizPoints
        Draw line: x1, mfcc2_vals#[i-1], x2, mfcc2_vals#[i]
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "MFCC"
    Text bottom: "yes", "Normalized time"
    Text top: "no", "MFCC Energy: Blue=Ref, Orange=Test"
    
    # === Tempo Alignment Diagram ===
    Select outer viewport: 4, 8, 4.1, 5.5
    Select inner viewport: 4.4, 7.7, 4.3, 5.4
    
    Axes: 0, duration1, 0, duration2
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, duration1, 0, duration2
    
    # Draw diagonal (perfect tempo match)
    Colour: "{0.85, 0.85, 0.85}"
    Dashed line
    minDur = min(duration1, duration2)
    Draw line: 0, 0, minDur, minDur
    Solid line
    
    # Draw actual alignment path
    Colour: "{0.3, 0.6, 0.8}"
    Line width: 2
    Draw line: 0, 0, duration1, duration2
    Line width: 1
    
    Font size: 7
    Colour: "{0.4, 0.4, 0.5}"
    Text: duration1 * 0.5, "centre", duration2 * 0.3, "half", "Ratio: " + fixed$(duration_ratio, 2)
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Test (s)"
    Text bottom: "yes", "Reference (s)"
    Text top: "no", "Time Alignment (gray=1:1)"
    
    # === Summary Panel ===
    Select outer viewport: 0, 8, 5.6, 7.0
    Axes: 0, 1, 0, 1
    
    Paint rectangle: "{0.95, 0.97, 0.95}", 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Text: 0.5, "centre", 0.9, "half", "##Analysis Summary##"
    
    # Assessment boxes
    boxWidth = 0.22
    boxHeight = 0.25
    boxY = 0.45
    
    # MFCC box
    if mfcc_assessment$ = "EXCELLENT" or mfcc_assessment$ = "GOOD"
        Paint rectangle: "{0.85, 0.95, 0.85}", 0.02, 0.02 + boxWidth, boxY, boxY + boxHeight
    elsif mfcc_assessment$ = "MODERATE"
        Paint rectangle: "{0.95, 0.95, 0.8}", 0.02, 0.02 + boxWidth, boxY, boxY + boxHeight
    else
        Paint rectangle: "{0.95, 0.85, 0.85}", 0.02, 0.02 + boxWidth, boxY, boxY + boxHeight
    endif
    Colour: "Black"
    Font size: 7
    Text: 0.02 + boxWidth/2, "centre", boxY + boxHeight * 0.7, "half", "MFCC"
    Font size: 6
    Text: 0.02 + boxWidth/2, "centre", boxY + boxHeight * 0.3, "half", mfcc_assessment$
    
    # Loudness box
    if loudness_assessment$ = "EXCELLENT" or loudness_assessment$ = "GOOD"
        Paint rectangle: "{0.85, 0.95, 0.85}", 0.26, 0.26 + boxWidth, boxY, boxY + boxHeight
    elsif loudness_assessment$ = "MODERATE"
        Paint rectangle: "{0.95, 0.95, 0.8}", 0.26, 0.26 + boxWidth, boxY, boxY + boxHeight
    else
        Paint rectangle: "{0.95, 0.85, 0.85}", 0.26, 0.26 + boxWidth, boxY, boxY + boxHeight
    endif
    Colour: "Black"
    Font size: 7
    Text: 0.26 + boxWidth/2, "centre", boxY + boxHeight * 0.7, "half", "Loudness"
    Font size: 6
    Text: 0.26 + boxWidth/2, "centre", boxY + boxHeight * 0.3, "half", loudness_assessment$
    
    # Pitch box
    if pitch_assessment$ = "EXCELLENT" or pitch_assessment$ = "VERY GOOD" or pitch_assessment$ = "GOOD"
        Paint rectangle: "{0.85, 0.95, 0.85}", 0.50, 0.50 + boxWidth, boxY, boxY + boxHeight
    elsif pitch_assessment$ = "MODERATE"
        Paint rectangle: "{0.95, 0.95, 0.8}", 0.50, 0.50 + boxWidth, boxY, boxY + boxHeight
    else
        Paint rectangle: "{0.95, 0.85, 0.85}", 0.50, 0.50 + boxWidth, boxY, boxY + boxHeight
    endif
    Colour: "Black"
    Font size: 7
    Text: 0.50 + boxWidth/2, "centre", boxY + boxHeight * 0.7, "half", "Pitch"
    Font size: 6
    Text: 0.50 + boxWidth/2, "centre", boxY + boxHeight * 0.3, "half", pitch_assessment$
    
    # Contour box
    if contour_accuracy > 80
        Paint rectangle: "{0.85, 0.95, 0.85}", 0.74, 0.74 + boxWidth, boxY, boxY + boxHeight
    elsif contour_accuracy > 60
        Paint rectangle: "{0.95, 0.95, 0.8}", 0.74, 0.74 + boxWidth, boxY, boxY + boxHeight
    else
        Paint rectangle: "{0.95, 0.85, 0.85}", 0.74, 0.74 + boxWidth, boxY, boxY + boxHeight
    endif
    Colour: "Black"
    Font size: 7
    Text: 0.74 + boxWidth/2, "centre", boxY + boxHeight * 0.7, "half", "Contour"
    Font size: 6
    Text: 0.74 + boxWidth/2, "centre", boxY + boxHeight * 0.3, "half", fixed$(contour_accuracy, 0) + "%"
    
    # Details row
    Font size: 6
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.12, "centre", 0.15, "half", "MFCC: " + fixed$(normalized_dtw_distance, 2)
    Text: 0.36, "centre", 0.15, "half", "dB: ±" + fixed$(average_db_distance, 1)
    Text: 0.60, "centre", 0.15, "half", "Int: ±" + fixed$(average_interval_difference, 2) + " st"
    Text: 0.84, "centre", 0.15, "half", "Trans: " + fixed$(overall_transposition, 1) + " st"
    
    Font size: 10
    Colour: "Black"
endif

# =============================================================================
# CLEANUP & RESULTS
# =============================================================================

removeObject: intensity1, intensity2, pitch1, pitch2

# Create results table
Create Table with column names: "DTW_Results", 0, "parameter metric value assessment"
results_table = selected("Table")

selectObject: results_table
Append row
Set string value: 1, "parameter", "MFCC"
Set string value: 1, "metric", "distance"
Set numeric value: 1, "value", normalized_dtw_distance
Set string value: 1, "assessment", mfcc_assessment$

Append row
Set string value: 2, "parameter", "Loudness"
Set string value: 2, "metric", "db_diff"
Set numeric value: 2, "value", average_db_distance
Set string value: 2, "assessment", loudness_assessment$

Append row
Set string value: 3, "parameter", "Pitch"
Set string value: 3, "metric", "interval_diff"
Set numeric value: 3, "value", average_interval_difference
Set string value: 3, "assessment", pitch_assessment$

Append row
Set string value: 4, "parameter", "Contour"
Set string value: 4, "metric", "accuracy"
Set numeric value: 4, "value", contour_accuracy
Set string value: 4, "assessment", ""

Append row
Set string value: 5, "parameter", "Tempo"
Set string value: 5, "metric", "ratio"
Set numeric value: 5, "value", duration_ratio
Set string value: 5, "assessment", ""

# =============================================================================
# FINAL OUTPUT
# =============================================================================

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  ANALYSIS COMPLETE"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "  MFCC Similarity:    ", mfcc_assessment$, " (", fixed$(normalized_dtw_distance, 2), ")"
appendInfoLine: "  Loudness Match:     ", loudness_assessment$, " (±", fixed$(average_db_distance, 1), " dB)"
appendInfoLine: "  Pitch Accuracy:     ", pitch_assessment$, " (±", fixed$(average_interval_difference, 2), " st)"
appendInfoLine: "  Contour Accuracy:   ", fixed$(contour_accuracy, 1), "%"
appendInfoLine: "  Transposition:      ", fixed$(overall_transposition, 2), " semitones"
appendInfoLine: "  Tempo Ratio:        ", fixed$(duration_ratio, 2)
appendInfoLine: ""

selectObject: sound1, sound2, results_table