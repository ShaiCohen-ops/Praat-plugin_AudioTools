# ============================================================
# Praat AudioTools - Pitch_Loop_Finder.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Fixed syntax
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Finds repeating pitch patterns using self-similarity matrix
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

form Pitch Loop Finder v0.2
    comment === Speed Settings ===
    positive Time_step 0.05
    comment (0.05 = Fast, 0.02 = High Precision)
    comment === Pitch Settings ===
    positive Pitch_floor 75
    positive Pitch_ceiling 600
    positive Tolerance_hz 50
    comment === Loop Timing ===
    positive Min_loop_duration 0.4
    positive Max_loop_duration 10.0
    comment === Output ===
    positive Num_loops_to_find 5
endform

# ===================================================================
# 1. SETUP
# ===================================================================

selectObject: originalID
duration = Get total duration

clearinfo
writeInfoLine: "=== Pitch Loop Finder v0.2 ==="
appendInfoLine: "Sound: ", originalName$
appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: "Time step: ", time_step, " s"
appendInfoLine: ""

# Extract Pitch
selectObject: originalID
pitchID = To Pitch: time_step, pitch_floor, pitch_ceiling
num_frames = Get number of frames

appendInfoLine: "Extracted ", num_frames, " frames"

# ===================================================================
# 2. BUILD SELF-SIMILARITY MATRIX
# ===================================================================

# Convert Pitch to Matrix for fast Formula access
Create simple Matrix: "ThePitchData", num_frames, 1, "0"
dataID = selected("Matrix")

selectObject: pitchID
pitch_vals# = zero#(num_frames)
for i from 1 to num_frames
    val = Get value in frame: i, "Hertz"
    if val = undefined
        val = 0
    endif
    pitch_vals#[i] = val
endfor
removeObject: pitchID

selectObject: dataID
for i from 1 to num_frames
    Set value: i, 1, pitch_vals#[i]
endfor

# Create SSM
Create simple Matrix: "SSM", num_frames, num_frames, "0"
ssmID = selected("Matrix")

appendInfo: "Calculating similarity matrix..."

# Fast Formula-based SSM calculation
tol$ = string$(tolerance_hz)
Formula: "if Matrix_ThePitchData[row, 1] > 0 and Matrix_ThePitchData[col, 1] > 0 and abs(Matrix_ThePitchData[row, 1] - Matrix_ThePitchData[col, 1]) < " + tol$ + " then 1 - (abs(Matrix_ThePitchData[row, 1] - Matrix_ThePitchData[col, 1]) / " + tol$ + ") else 0 endif"

appendInfoLine: " done!"

# ===================================================================
# 3. FIND LOOPS (scan diagonals)
# ===================================================================

# Create TextGrid for output
selectObject: originalID
textgridID = To TextGrid: "Loops Repeats", ""

Create Table with column names: "candidates", 0, "start_frame length_frames gap_frames score"
tableID = selected("Table")

selectObject: ssmID
frame_rate = 1 / time_step
min_len = round(min_loop_duration * frame_rate)
max_len = round(max_loop_duration * frame_rate)
max_gap = num_frames - min_len

gap = min_len
step = 1

# Speed up for long files
if num_frames > 2000
    step = 2
endif

appendInfo: "Scanning diagonals..."

while gap <= max_gap
    path_len = 0
    path_start = 0
    path_score = 0
    search_limit = num_frames - gap
    
    for i from 1 to search_limit
        j = i + gap
        selectObject: ssmID
        val = Get value in cell: i, j
        
        if val > 0.5
            if path_len = 0
                path_start = i
            endif
            path_len = path_len + 1
            path_score = path_score + val
        else
            if path_len >= min_len and path_len <= max_len
                selectObject: tableID
                Append row
                row = Get number of rows
                Set numeric value: row, "start_frame", path_start
                Set numeric value: row, "length_frames", path_len
                Set numeric value: row, "gap_frames", gap
                Set numeric value: row, "score", path_score
            endif
            path_len = 0
            path_score = 0
        endif
    endfor
    
    # Check final segment
    if path_len >= min_len and path_len <= max_len
        selectObject: tableID
        Append row
        row = Get number of rows
        Set numeric value: row, "start_frame", path_start
        Set numeric value: row, "length_frames", path_len
        Set numeric value: row, "gap_frames", gap
        Set numeric value: row, "score", path_score
    endif
    
    gap = gap + step
endwhile

appendInfoLine: " done."

# ===================================================================
# 4. FILTER & ANNOTATE
# ===================================================================

selectObject: tableID
nRows = Get number of rows

if nRows = 0
    removeObject: dataID, ssmID, tableID
    appendInfoLine: ""
    appendInfoLine: "No loops found. Try adjusting tolerance or duration."
    selectObject: originalID
    plusObject: textgridID
    exitScript: "No loops found."
endif

appendInfoLine: "Found ", nRows, " candidates, selecting best ", num_loops_to_find

Sort rows: "score"

# Initialize saved regions (for overlap checking)
for k from 1 to num_loops_to_find
    saved_t1_'k' = -1
    saved_t2_'k' = -1
endfor

loops_found = 0
row_index = nRows

while loops_found < num_loops_to_find and row_index > 0
    selectObject: tableID
    start_f = Get value: row_index, "start_frame"
    len_f = Get value: row_index, "length_frames"
    gap_f = Get value: row_index, "gap_frames"
    
    t1 = (start_f - 1) * time_step
    dur = len_f * time_step
    t2 = t1 + dur
    rep_t1 = (start_f + gap_f - 1) * time_step
    rep_t2 = rep_t1 + dur
    
    # Clamp to valid range
    if t1 < 0
        t1 = 0
    endif
    if t2 > duration
        t2 = duration
    endif
    if rep_t1 < 0
        rep_t1 = 0
    endif
    if rep_t2 > duration
        rep_t2 = duration
    endif
    
    # Overlap Check with previously saved loops
    is_overlap = 0
    for k from 1 to loops_found
        st1 = saved_t1_'k'
        st2 = saved_t2_'k'
        if t1 < st2 and t2 > st1
            is_overlap = 1
        endif
    endfor
    
    if is_overlap = 0 and t2 > t1 and rep_t2 > rep_t1
        loops_found = loops_found + 1
        saved_t1_'loops_found' = t1
        saved_t2_'loops_found' = t2
        
        # Annotate TextGrid
        selectObject: textgridID
        
        # Tier 1: Source loop
        nocheck Insert boundary: 1, t1
        nocheck Insert boundary: 1, t2
        int_idx = Get interval at time: 1, t1 + 0.001
        Set interval text: 1, int_idx, "Loop " + string$(loops_found)
        
        # Tier 2: Repeat location
        nocheck Insert boundary: 2, rep_t1
        nocheck Insert boundary: 2, rep_t2
        int_idx = Get interval at time: 2, rep_t1 + 0.001
        Set interval text: 2, int_idx, "Repeat " + string$(loops_found)
        
        appendInfoLine: "Loop ", loops_found, ": ", fixed$(t1, 2), "-", fixed$(t2, 2), " s -> ", fixed$(rep_t1, 2), "-", fixed$(rep_t2, 2), " s (", fixed$(dur, 2), " s)"
    endif
    
    row_index = row_index - 1
endwhile

# ===================================================================
# 5. CLEANUP & OUTPUT
# ===================================================================

removeObject: dataID, ssmID, tableID

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Found ", loops_found, " loop(s)"
appendInfoLine: ""
appendInfoLine: "TextGrid shows:"
appendInfoLine: "  Tier 1 (Loops): Original loop regions"
appendInfoLine: "  Tier 2 (Repeats): Where they repeat"

selectObject: originalID
plusObject: textgridID
View & Edit

