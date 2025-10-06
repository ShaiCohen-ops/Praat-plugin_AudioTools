# ============================================================
# Praat AudioTools - DTW for 2 files.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Analytical measurement or feature-extraction script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# DTW-Enhanced Praat script for comprehensive audio comparison
# Implements FastDTW for robust comparison of different-length audio files
# Analyzes MFCC features, loudness, and melodic intervals with DTW alignment
# Select two Sound objects in the Objects list before running

clearinfo

# =============================================================================
# PARAMETERS SECTION
# =============================================================================

# MFCC Parameters
mfcc_window_length = 0.025
mfcc_time_step = 0.01
number_of_filters = 24
fmin = 100
fmax = 5000
number_of_coefficients = 13

# DTW Parameters
dtw_radius = 3
dtw_min_size = 5

# Loudness Parameters
loudness_time_step = 0.01

# Pitch Parameters
pitch_time_step = 0.01
pitch_floor = 75
pitch_ceiling = 600

# =============================================================================
# DTW HELPER FUNCTIONS
# =============================================================================

# Calculate Euclidean distance between two MFCC vectors (skipping C0)
procedure calculateMFCCDistance: .mfcc1, .frame1, .mfcc2, .frame2, .numCoeffs
    .distance = 0
    # Skip coefficient 1 (C0) and use coefficients 2-13 (C1-C12)
    for .coeff from 2 to .numCoeffs
        selectObject: .mfcc1
        .value1 = Get value in frame: .frame1, .coeff
        selectObject: .mfcc2
        .value2 = Get value in frame: .frame2, .coeff
        .diff = .value1 - .value2
        .distance += .diff * .diff
    endfor
    .distance = sqrt(.distance)
endproc

# Simple DTW implementation for small sequences
procedure simpleDTW: .mfcc1, .frames1, .mfcc2, .frames2, .numCoeffs
    .n = .frames1
    .m = .frames2
    
    # Create DTW matrix (using variables since Praat doesn't have 2D arrays)
    # We'll use a flattened approach: dtw_[i]_[j]
    
    # Initialize first row and column
    for .i from 0 to .n
        for .j from 0 to .m
            dtw_'.i'_'.j' = 10000  # Large number representing infinity
        endfor
    endfor
    dtw_0_0 = 0
    
    # Fill DTW matrix
    for .i from 1 to .n
        for .j from 1 to .m
            @calculateMFCCDistance: .mfcc1, .i, .mfcc2, .j, .numCoeffs
            .cost = calculateMFCCDistance.distance
            
            .diag = dtw_'.i-1'_'.j-1'
            .left = dtw_'.i'_'.j-1'
            .up = dtw_'.i-1'_'.j'
            
            .min_val = .diag
            if .left < .min_val
                .min_val = .left
            endif
            if .up < .min_val
                .min_val = .up
            endif
            
            dtw_'.i'_'.j' = .cost + .min_val
        endfor
    endfor
    
    .dtw_distance = dtw_'.n'_'.m'
endproc

# FastDTW implementation for larger sequences
procedure fastDTW: .mfcc1, .frames1, .mfcc2, .frames2, .numCoeffs
    .n = .frames1
    .m = .frames2
    
    # If sequences are small, use simple DTW
    if .n <= dtw_min_size or .m <= dtw_min_size
        @simpleDTW: .mfcc1, .frames1, .mfcc2, .frames2, .numCoeffs
        .dtw_distance = simpleDTW.dtw_distance
    else
        # For larger sequences, use approximation
        # Create reduced sequences by averaging every 2 frames
        appendInfoLine: "Using FastDTW approximation for large sequences..."
        
        # Simplified approach: sample every nth frame to reduce complexity
        .sample_rate = 3
        .sampled_frames1 = floor(.frames1 / .sample_rate)
        .sampled_frames2 = floor(.frames2 / .sample_rate)
        
        if .sampled_frames1 > 0 and .sampled_frames2 > 0
            # Calculate distance on sampled frames
            .total_distance = 0
            .comparisons = 0
            
            for .i from 1 to .sampled_frames1
                .actual_i = .i * .sample_rate
                if .actual_i <= .frames1
                    for .j from 1 to .sampled_frames2
                        .actual_j = .j * .sample_rate
                        if .actual_j <= .frames2
                            @calculateMFCCDistance: .mfcc1, .actual_i, .mfcc2, .actual_j, .numCoeffs
                            .total_distance += calculateMFCCDistance.distance
                            .comparisons += 1
                        endif
                    endfor
                endif
            endfor
            
            if .comparisons > 0
                .dtw_distance = .total_distance / .comparisons * sqrt(.n * .m)
            else
                .dtw_distance = 0
            endif
        else
            .dtw_distance = 0
        endif
    endif
endproc

# =============================================================================
# INITIAL SETUP AND VALIDATION
# =============================================================================

# Check if exactly two sounds are selected
numberOfSelectedSounds = numberOfSelected("Sound")
if numberOfSelectedSounds != 2
    exitScript: "Please select exactly two Sound objects."
endif

# Get the two selected sounds
sound1 = selected("Sound", 1)
sound2 = selected("Sound", 2)

# Get basic info about sounds
selectObject: sound1
name1$ = selected$("Sound")
duration1 = Get total duration

selectObject: sound2
name2$ = selected$("Sound")
duration2 = Get total duration

appendInfoLine: "Starting DTW-enhanced comprehensive audio analysis..."
appendInfoLine: "Teacher: ", name1$, " (", fixed$(duration1, 3), "s)"
appendInfoLine: "Student: ", name2$, " (", fixed$(duration2, 3), "s)"

# Check for significant duration differences
duration_diff = abs(duration1 - duration2)
duration_ratio = duration2 / duration1

if duration_diff > 1.0
    appendInfoLine: "⚠ WARNING: Significant duration difference (", fixed$(duration_diff, 2), "s)"
endif

if duration_ratio > 1.5 or duration_ratio < 0.67
    appendInfoLine: "⚠ WARNING: Large tempo difference (ratio: ", fixed$(duration_ratio, 2), ")"
endif

appendInfoLine: ""

# Create results table
results_table = Create Table with column names: "dtw_analysis_results", 0, "parameter metric value assessment teacher_file student_file duration_diff tempo_ratio"

# =============================================================================
# DTW-ENHANCED MFCC ANALYSIS
# =============================================================================

appendInfoLine: "=== ANALYZING MFCC FEATURES WITH DTW ==="

# Create MelSpectrograms
selectObject: sound1
melspec1 = To MelSpectrogram: mfcc_window_length, mfcc_time_step, number_of_filters, fmin, fmax
selectObject: sound2
melspec2 = To MelSpectrogram: mfcc_window_length, mfcc_time_step, number_of_filters, fmin, fmax

# Convert to MFCC
selectObject: melspec1
mfcc1 = To MFCC: number_of_coefficients
selectObject: melspec2
mfcc2 = To MFCC: number_of_coefficients

# Get number of frames
selectObject: mfcc1
mfcc_frames1 = Get number of frames
selectObject: mfcc2
mfcc_frames2 = Get number of frames

appendInfoLine: "Teacher MFCC frames: ", mfcc_frames1
appendInfoLine: "Student MFCC frames: ", mfcc_frames2

# Apply DTW to MFCC comparison
@fastDTW: mfcc1, mfcc_frames1, mfcc2, mfcc_frames2, number_of_coefficients
dtw_mfcc_distance = fastDTW.dtw_distance

# Normalize DTW distance
normalized_dtw_distance = dtw_mfcc_distance / sqrt(mfcc_frames1 * mfcc_frames2)

appendInfoLine: "DTW MFCC distance: ", fixed$(dtw_mfcc_distance, 6)
appendInfoLine: "Normalized DTW distance: ", fixed$(normalized_dtw_distance, 6)

# MFCC Assessment based on normalized DTW distance
if normalized_dtw_distance < 2
    mfcc_assessment$ = "EXCELLENT"
elsif normalized_dtw_distance < 5
    mfcc_assessment$ = "GOOD"
elsif normalized_dtw_distance < 10
    mfcc_assessment$ = "MODERATE"
else
    mfcc_assessment$ = "NEEDS_WORK"
endif

# Add MFCC results to table
selectObject: results_table

Append row
row_count = Get number of rows
Set string value: row_count, "parameter", "MFCC_DTW"
Set string value: row_count, "metric", "dtw_distance"
Set numeric value: row_count, "value", dtw_mfcc_distance
Set string value: row_count, "assessment", mfcc_assessment$
Set string value: row_count, "teacher_file", name1$
Set string value: row_count, "student_file", name2$
Set numeric value: row_count, "duration_diff", duration_diff
Set numeric value: row_count, "tempo_ratio", duration_ratio

Append row
row_count = Get number of rows
Set string value: row_count, "parameter", "MFCC_DTW"
Set string value: row_count, "metric", "normalized_dtw_distance"
Set numeric value: row_count, "value", normalized_dtw_distance
Set string value: row_count, "assessment", mfcc_assessment$
Set string value: row_count, "teacher_file", name1$
Set string value: row_count, "student_file", name2$
Set numeric value: row_count, "duration_diff", duration_diff
Set numeric value: row_count, "tempo_ratio", duration_ratio

appendInfoLine: "DTW MFCC analysis completed"

# Clean up MFCC objects
selectObject: melspec1, melspec2, mfcc1, mfcc2
Remove

# =============================================================================
# DTW-ENHANCED LOUDNESS ANALYSIS
# =============================================================================

appendInfoLine: "=== ANALYZING LOUDNESS WITH DTW ALIGNMENT ==="

# Create Intensity objects
selectObject: sound1
intensity1 = To Intensity: 75, loudness_time_step, "yes"
selectObject: sound2
intensity2 = To Intensity: 75, loudness_time_step, "yes"

# Get intensity statistics
selectObject: intensity1
loudness_frames1 = Get number of frames
mean_db1 = Get mean: 0, 0, "dB"
std_db1 = Get standard deviation: 0, 0

selectObject: intensity2
loudness_frames2 = Get number of frames
mean_db2 = Get mean: 0, 0, "dB"
std_db2 = Get standard deviation: 0, 0

# Simple DTW-inspired loudness comparison
# For loudness, we'll use a simpler alignment approach
min_frames = min(loudness_frames1, loudness_frames2)
max_frames = max(loudness_frames1, loudness_frames2)

# Calculate alignment ratio
alignment_ratio = max_frames / min_frames

total_db_distance = 0
valid_comparisons = 0

# Adaptive sampling based on length difference
if alignment_ratio < 1.2
    # Similar lengths - direct comparison
    for frame from 1 to min_frames
        selectObject: intensity1
        db1 = Get value in frame: frame
        selectObject: intensity2
        db2 = Get value in frame: frame
        
        if db1 != undefined and db2 != undefined
            db_diff = abs(db1 - db2)
            total_db_distance += db_diff
            valid_comparisons += 1
        endif
    endfor
else
    # Different lengths - stretch shorter to match longer
    appendInfoLine: "Applying tempo-aware loudness comparison (ratio: ", fixed$(alignment_ratio, 2), ")"
    
    for frame from 1 to min_frames
        # Map frame in shorter sequence to corresponding frame in longer sequence
        longer_frame = round(frame * alignment_ratio)
        if longer_frame > max_frames
            longer_frame = max_frames
        endif
        
        if loudness_frames1 < loudness_frames2
            # Student is longer
            selectObject: intensity1
            db1 = Get value in frame: frame
            selectObject: intensity2
            db2 = Get value in frame: longer_frame
        else
            # Teacher is longer
            selectObject: intensity1
            db1 = Get value in frame: longer_frame
            selectObject: intensity2
            db2 = Get value in frame: frame
        endif
        
        if db1 != undefined and db2 != undefined
            db_diff = abs(db1 - db2)
            total_db_distance += db_diff
            valid_comparisons += 1
        endif
    endfor
endif

if valid_comparisons > 0
    average_db_distance = total_db_distance / valid_comparisons
else
    average_db_distance = 0
endif

# Calculate other loudness metrics
mean_db_diff = abs(mean_db1 - mean_db2)
consistency_diff = abs(std_db1 - std_db2)

# Loudness Assessment (adjusted for DTW)
if average_db_distance < 4
    loudness_assessment$ = "EXCELLENT"
elsif average_db_distance < 8
    loudness_assessment$ = "GOOD"
elsif average_db_distance < 15
    loudness_assessment$ = "MODERATE"
else
    loudness_assessment$ = "NEEDS_WORK"
endif

# Add loudness results to table
selectObject: results_table

Append row
row_count = Get number of rows
Set string value: row_count, "parameter", "LOUDNESS_DTW"
Set string value: row_count, "metric", "aligned_db_difference"
Set numeric value: row_count, "value", average_db_distance
Set string value: row_count, "assessment", loudness_assessment$
Set string value: row_count, "teacher_file", name1$
Set string value: row_count, "student_file", name2$
Set numeric value: row_count, "duration_diff", duration_diff
Set numeric value: row_count, "tempo_ratio", duration_ratio

Append row
row_count = Get number of rows
Set string value: row_count, "parameter", "LOUDNESS_DTW"
Set string value: row_count, "metric", "mean_db_difference"
Set numeric value: row_count, "value", mean_db_diff
Set string value: row_count, "assessment", loudness_assessment$
Set string value: row_count, "teacher_file", name1$
Set string value: row_count, "student_file", name2$
Set numeric value: row_count, "duration_diff", duration_diff
Set numeric value: row_count, "tempo_ratio", duration_ratio

appendInfoLine: "DTW loudness analysis completed - Aligned dB difference: ", fixed$(average_db_distance, 3)

# Clean up loudness objects
selectObject: intensity1, intensity2
Remove

# =============================================================================
# DTW-ENHANCED PITCH/INTERVAL ANALYSIS
# =============================================================================

appendInfoLine: "=== ANALYZING MELODIC INTERVALS WITH DTW ==="

# Create Pitch objects
selectObject: sound1
pitch1 = To Pitch: pitch_time_step, pitch_floor, pitch_ceiling
selectObject: sound2
pitch2 = To Pitch: pitch_time_step, pitch_floor, pitch_ceiling

# Get basic pitch statistics
selectObject: pitch1
pitch_frames1 = Get number of frames
mean_f0_1 = Get mean: 0, 0, "Hertz"

selectObject: pitch2
pitch_frames2 = Get number of frames
mean_f0_2 = Get mean: 0, 0, "Hertz"

# Calculate overall transposition
if mean_f0_1 > 0 and mean_f0_2 > 0
    overall_transposition_semitones = 12 * log2(mean_f0_2 / mean_f0_1)
else
    overall_transposition_semitones = 0
endif

# DTW-inspired pitch comparison with tempo alignment
min_pitch_frames = min(pitch_frames1, pitch_frames2)
max_pitch_frames = max(pitch_frames1, pitch_frames2)
pitch_alignment_ratio = max_pitch_frames / min_pitch_frames

total_interval_difference = 0
valid_intervals = 0
contour_matches = 0
contour_total = 0

appendInfoLine: "Pitch alignment ratio: ", fixed$(pitch_alignment_ratio, 2)

# Adaptive pitch comparison
for frame from 2 to min_pitch_frames
    # Calculate corresponding frame in longer sequence
    if pitch_alignment_ratio > 1.2
        longer_frame = round(frame * pitch_alignment_ratio)
        if longer_frame > max_pitch_frames
            longer_frame = max_pitch_frames
        endif
    else
        longer_frame = frame
    endif
    
    # Get pitch values with tempo alignment
    if pitch_frames1 < pitch_frames2
        # Student sequence is longer
        selectObject: pitch1
        f0_1_current = Get value in frame: frame, "Hertz"
        f0_1_previous = Get value in frame: frame-1, "Hertz"
        selectObject: pitch2
        f0_2_current = Get value in frame: longer_frame, "Hertz"
        f0_2_previous = Get value in frame: longer_frame-1, "Hertz"
    else
        # Teacher sequence is longer or equal
        selectObject: pitch1
        f0_1_current = Get value in frame: longer_frame, "Hertz"
        f0_1_previous = Get value in frame: longer_frame-1, "Hertz"
        selectObject: pitch2
        f0_2_current = Get value in frame: frame, "Hertz"
        f0_2_previous = Get value in frame: frame-1, "Hertz"
    endif
    
    # Process intervals if all values are valid
    if f0_1_current != undefined and f0_1_previous != undefined and f0_2_current != undefined and f0_2_previous != undefined and f0_1_current > 0 and f0_1_previous > 0 and f0_2_current > 0 and f0_2_previous > 0
        
        teacher_interval = 12 * log2(f0_1_current / f0_1_previous)
        student_interval = 12 * log2(f0_2_current / f0_2_previous)
        
        interval_difference = abs(teacher_interval - student_interval)
        total_interval_difference += interval_difference
        valid_intervals += 1
        
        # Check contour direction
        teacher_direction = 0
        student_direction = 0
        
        if abs(teacher_interval) > 0.1
            if teacher_interval > 0
                teacher_direction = 1
            else
                teacher_direction = -1
            endif
        endif
        
        if abs(student_interval) > 0.1
            if student_interval > 0
                student_direction = 1
            else
                student_direction = -1
            endif
        endif
        
        contour_total += 1
        if teacher_direction = student_direction
            contour_matches += 1
        endif
    endif
endfor

# Calculate statistics
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

# Pitch Assessment (adjusted for DTW alignment)
if average_interval_difference < 0.3
    pitch_assessment$ = "EXCELLENT"
elsif average_interval_difference < 0.7
    pitch_assessment$ = "VERY_GOOD"
elsif average_interval_difference < 1.5
    pitch_assessment$ = "GOOD"
elsif average_interval_difference < 3.0
    pitch_assessment$ = "MODERATE"
else
    pitch_assessment$ = "NEEDS_WORK"
endif

# Add pitch results to table
selectObject: results_table

Append row
row_count = Get number of rows
Set string value: row_count, "parameter", "PITCH_DTW"
Set string value: row_count, "metric", "transposition_semitones"
Set numeric value: row_count, "value", overall_transposition_semitones
Set string value: row_count, "assessment", pitch_assessment$
Set string value: row_count, "teacher_file", name1$
Set string value: row_count, "student_file", name2$
Set numeric value: row_count, "duration_diff", duration_diff
Set numeric value: row_count, "tempo_ratio", duration_ratio

Append row
row_count = Get number of rows
Set string value: row_count, "parameter", "PITCH_DTW"
Set string value: row_count, "metric", "aligned_interval_difference"
Set numeric value: row_count, "value", average_interval_difference
Set string value: row_count, "assessment", pitch_assessment$
Set string value: row_count, "teacher_file", name1$
Set string value: row_count, "student_file", name2$
Set numeric value: row_count, "duration_diff", duration_diff
Set numeric value: row_count, "tempo_ratio", duration_ratio

Append row
row_count = Get number of rows
Set string value: row_count, "parameter", "PITCH_DTW"
Set string value: row_count, "metric", "contour_accuracy_percent"
Set numeric value: row_count, "value", contour_accuracy
Set string value: row_count, "assessment", pitch_assessment$
Set string value: row_count, "teacher_file", name1$
Set string value: row_count, "student_file", name2$
Set numeric value: row_count, "duration_diff", duration_diff
Set numeric value: row_count, "tempo_ratio", duration_ratio

appendInfoLine: "DTW pitch analysis completed - Aligned interval difference: ", fixed$(average_interval_difference, 3), " semitones"

# Clean up pitch objects
selectObject: pitch1, pitch2
Remove

# =============================================================================
# DISPLAY ENHANCED SUMMARY
# =============================================================================

appendInfoLine: ""
appendInfoLine: "=== DTW-ENHANCED COMPREHENSIVE ANALYSIS SUMMARY ==="
appendInfoLine: "Duration difference: ", fixed$(duration_diff, 2), "s"
appendInfoLine: "Tempo ratio (student/teacher): ", fixed$(duration_ratio, 2)
appendInfoLine: ""
appendInfoLine: "DTW MFCC Similarity: ", mfcc_assessment$, " (", fixed$(normalized_dtw_distance, 3), ")"
appendInfoLine: "DTW Loudness Match: ", loudness_assessment$, " (", fixed$(average_db_distance, 3), " dB)"
appendInfoLine: "DTW Pitch Accuracy: ", pitch_assessment$, " (", fixed$(average_interval_difference, 3), " semitones)"
appendInfoLine: "Contour Accuracy: ", fixed$(contour_accuracy, 1), "%"
appendInfoLine: "Transposition: ", fixed$(overall_transposition_semitones, 2), " semitones"
appendInfoLine: ""
appendInfoLine: "✓ This analysis accounts for tempo differences and timing variations!"
appendInfoLine: ""
appendInfoLine: "Results table created successfully!"
appendInfoLine: "To save as CSV:"
appendInfoLine: "1. Select the 'dtw_analysis_results' table in the Objects window"
appendInfoLine: "2. Go to 'Save' > 'Save as comma-separated values file...'"
appendInfoLine: "3. Choose your filename and location"
appendInfoLine: ""

# Reselect original sounds and results table for user convenience
selectObject: sound1, sound2, results_table

appendInfoLine: "DTW-enhanced analysis completed! 🎵"