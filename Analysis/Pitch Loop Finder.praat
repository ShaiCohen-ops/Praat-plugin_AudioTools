# ============================================================
# Praat AudioTools - Pitch_Loop_Finder.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Finds repeating pitch patterns using self-similarity matrix (SSM)
#   analysis. Detects melodic loops, recurring phrases, and structural
#   repetitions in audio. Outputs annotated TextGrid and visualization.
#
# Changelog v0.3:
#   - Added visualization (SSM heatmap, waveform, pitch contour)
#   - Added presets for different music types
#   - Made View & Edit optional
#
# Usage:
#   Select a Sound object and run this script.
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

form Pitch Loop Finder
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Vocal Melody
        option Instrumental Riff
        option Speech Pattern
        option Bass Line
        option Full Range
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
    boolean Show_visualization 1
    boolean Open_textgrid_editor 1
endform

# === APPLY PRESETS ===
if preset = 2
    # Vocal Melody
    pitch_floor = 100
    pitch_ceiling = 500
    tolerance_hz = 40
    min_loop_duration = 0.5
    max_loop_duration = 8.0
    time_step = 0.03
    presetName$ = "VocalMelody"
elsif preset = 3
    # Instrumental Riff
    pitch_floor = 60
    pitch_ceiling = 800
    tolerance_hz = 60
    min_loop_duration = 0.3
    max_loop_duration = 4.0
    time_step = 0.04
    presetName$ = "InstrumentalRiff"
elsif preset = 4
    # Speech Pattern
    pitch_floor = 75
    pitch_ceiling = 400
    tolerance_hz = 30
    min_loop_duration = 0.2
    max_loop_duration = 3.0
    time_step = 0.02
    presetName$ = "SpeechPattern"
elsif preset = 5
    # Bass Line
    pitch_floor = 30
    pitch_ceiling = 200
    tolerance_hz = 20
    min_loop_duration = 0.5
    max_loop_duration = 8.0
    time_step = 0.05
    presetName$ = "BassLine"
elsif preset = 6
    # Full Range
    pitch_floor = 50
    pitch_ceiling = 1000
    tolerance_hz = 80
    min_loop_duration = 0.3
    max_loop_duration = 15.0
    time_step = 0.04
    presetName$ = "FullRange"
else
    presetName$ = "Custom"
endif

# ===================================================================
# 1. SETUP
# ===================================================================

selectObject: originalID
duration = Get total duration
sampleRate = Get sampling frequency

clearinfo
writeInfoLine: "=== Pitch Loop Finder v0.3 ==="
appendInfoLine: "Sound: ", originalName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: "Time step: ", time_step, " s"
appendInfoLine: "Pitch range: ", pitch_floor, "-", pitch_ceiling, " Hz"
appendInfoLine: "Tolerance: ", tolerance_hz, " Hz"
appendInfoLine: ""

# Extract Pitch
selectObject: originalID
pitchID = To Pitch: time_step, pitch_floor, pitch_ceiling
num_frames = Get number of frames

appendInfoLine: "Extracted ", num_frames, " pitch frames"

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

# Keep pitch object for visualization
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
    removeObject: dataID, ssmID, tableID, pitchID
    appendInfoLine: ""
    appendInfoLine: "No loops found. Try adjusting tolerance or duration."
    selectObject: originalID
    plusObject: textgridID
    exitScript: "No loops found."
endif

appendInfoLine: "Found ", nRows, " candidates, selecting best ", num_loops_to_find

Sort rows: "score"

# Store found loops for visualization
maxLoops = 10
for k from 1 to maxLoops
    loop_t1[k] = -1
    loop_t2[k] = -1
    rep_t1[k] = -1
    rep_t2[k] = -1
endfor

loops_found = 0
row_index = nRows

while loops_found < num_loops_to_find and row_index > 0
    selectObject: tableID
    start_f = Get value: row_index, "start_frame"
    len_f = Get value: row_index, "length_frames"
    gap_f = Get value: row_index, "gap_frames"
    
    t1 = (start_f - 1) * time_step
    dur_loop = len_f * time_step
    t2 = t1 + dur_loop
    r_t1 = (start_f + gap_f - 1) * time_step
    r_t2 = r_t1 + dur_loop
    
    # Clamp to valid range
    if t1 < 0
        t1 = 0
    endif
    if t2 > duration
        t2 = duration
    endif
    if r_t1 < 0
        r_t1 = 0
    endif
    if r_t2 > duration
        r_t2 = duration
    endif
    
    # Overlap Check with previously saved loops
    is_overlap = 0
    for k from 1 to loops_found
        st1 = loop_t1[k]
        st2 = loop_t2[k]
        if t1 < st2 and t2 > st1
            is_overlap = 1
        endif
    endfor
    
    if is_overlap = 0 and t2 > t1 and r_t2 > r_t1
        loops_found = loops_found + 1
        loop_t1[loops_found] = t1
        loop_t2[loops_found] = t2
        rep_t1[loops_found] = r_t1
        rep_t2[loops_found] = r_t2
        
        # Annotate TextGrid
        selectObject: textgridID
        
        # Tier 1: Source loop
        nocheck Insert boundary: 1, t1
        nocheck Insert boundary: 1, t2
        int_idx = Get interval at time: 1, t1 + 0.001
        Set interval text: 1, int_idx, "Loop " + string$(loops_found)
        
        # Tier 2: Repeat location
        nocheck Insert boundary: 2, r_t1
        nocheck Insert boundary: 2, r_t2
        int_idx = Get interval at time: 2, r_t1 + 0.001
        Set interval text: 2, int_idx, "Repeat " + string$(loops_found)
        
        appendInfoLine: "Loop ", loops_found, ": ", fixed$(t1, 2), "-", fixed$(t2, 2), " s -> ", fixed$(r_t1, 2), "-", fixed$(r_t2, 2), " s (", fixed$(dur_loop, 2), " s)"
    endif
    
    row_index = row_index - 1
endwhile

# ===================================================================
# 5. VISUALIZATION
# ===================================================================

if show_visualization
    Erase all
    
    # --- Title ---
    Select outer viewport: 1, 8, 0.0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Pitch Loop Finder: " + originalName$ + " [" + presetName$ + "]"
    
    # --- Waveform with loop markers ---
    Select outer viewport: 0, 8, 0.6, 1.8
    Select inner viewport: 0.5, 7.5, 0.7, 1.7
    
    selectObject: originalID
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    # Draw loop regions
    selectObject: originalID
    ampMax = Get maximum: 0, 0, "Sinc70"
    ampMin = Get minimum: 0, 0, "Sinc70"
    
    # Colors for loops
    for k from 1 to loops_found
        if loop_t1[k] >= 0
            # Source loop - blue
            if k = 1
                col$ = "{0.2, 0.5, 0.8}"
            elsif k = 2
                col$ = "{0.8, 0.4, 0.2}"
            elsif k = 3
                col$ = "{0.3, 0.7, 0.3}"
            elsif k = 4
                col$ = "{0.7, 0.3, 0.7}"
            else
                col$ = "{0.5, 0.5, 0.5}"
            endif
            
            Colour: col$
            Paint rectangle: col$, loop_t1[k], loop_t2[k], ampMin * 0.9, ampMax * 0.9
            
            # Repeat - same color, lighter
            if k = 1
                col2$ = "{0.6, 0.8, 1.0}"
            elsif k = 2
                col2$ = "{1.0, 0.7, 0.5}"
            elsif k = 3
                col2$ = "{0.6, 0.9, 0.6}"
            elsif k = 4
                col2$ = "{0.9, 0.6, 0.9}"
            else
                col2$ = "{0.7, 0.7, 0.7}"
            endif
            Paint rectangle: col2$, rep_t1[k], rep_t2[k], ampMin * 0.9, ampMax * 0.9
        endif
    endfor
    
    # Redraw waveform on top
    selectObject: originalID
    Colour: "{0.3, 0.3, 0.3}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Waveform"
    
    # --- Pitch contour ---
    Select outer viewport: 0, 8, 2.0, 3.0
    Select inner viewport: 0.5, 7.5, 2.1, 2.9
    
    selectObject: pitchID
    minF0 = Get minimum: 0, 0, "Hertz", "Parabolic"
    maxF0 = Get maximum: 0, 0, "Hertz", "Parabolic"
    
    # Handle case with no voiced frames
    if minF0 = undefined or maxF0 = undefined or maxF0 <= minF0
        minF0 = pitch_floor
        maxF0 = pitch_ceiling
    endif
    
    Axes: 0, duration, minF0 * 0.9, maxF0 * 1.1
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, minF0 * 0.9, maxF0 * 1.1
    
    Colour: "{0.2, 0.6, 0.4}"
    Line width: 1.5
    Draw: 0, 0, minF0 * 0.9, maxF0 * 1.1, "no"
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "F0 (Hz)"
    Text bottom: "yes", "Time (s)"
    
    # --- Self-Similarity Matrix (simplified) ---
    Select outer viewport: 0, 4, 3.2, 5.5
    Select inner viewport: 0.5, 3.8, 3.3, 5.4
    
    Axes: 0, duration, 0, duration
    Colour: "{0.9, 0.9, 0.9}"
    Paint rectangle: "{0.9, 0.9, 0.9}", 0, duration, 0, duration
    
    # Main diagonal (reference)
    Colour: "{0.7, 0.7, 0.7}"
    Line width: 1
    Dotted line
    Draw line: 0, 0, duration, duration
    Solid line
    
    # Draw the loop diagonals
    Line width: 2
    
    for k from 1 to loops_found
        if loop_t1[k] >= 0
            # Color per loop
            if k = 1
                Colour: "{0.2, 0.5, 0.8}"
            elsif k = 2
                Colour: "{0.8, 0.4, 0.2}"
            elsif k = 3
                Colour: "{0.3, 0.7, 0.3}"
            elsif k = 4
                Colour: "{0.7, 0.3, 0.7}"
            else
                Colour: "Red"
            endif
            
            gap_time = rep_t1[k] - loop_t1[k]
            Draw line: loop_t1[k], loop_t1[k] + gap_time, loop_t2[k], loop_t2[k] + gap_time
        endif
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Time (s)"
    Text bottom: "yes", "Loop Structure"
    
    # --- Loop legend ---
    Select outer viewport: 4, 8, 3.2, 5.5
    Select inner viewport: 4.5, 7.8, 3.3, 5.4
    
    Axes: 0, 10, 0, loops_found + 1
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 10, 0, loops_found + 1
    
    Font size: 8
    for k from 1 to loops_found
        y = loops_found - k + 0.5
        
        if k = 1
            col$ = "{0.2, 0.5, 0.8}"
            col2$ = "{0.6, 0.8, 1.0}"
        elsif k = 2
            col$ = "{0.8, 0.4, 0.2}"
            col2$ = "{1.0, 0.7, 0.5}"
        elsif k = 3
            col$ = "{0.3, 0.7, 0.3}"
            col2$ = "{0.6, 0.9, 0.6}"
        elsif k = 4
            col$ = "{0.7, 0.3, 0.7}"
            col2$ = "{0.9, 0.6, 0.9}"
        else
            col$ = "{0.5, 0.5, 0.5}"
            col2$ = "{0.7, 0.7, 0.7}"
        endif
        
        # Source box
        Paint rectangle: col$, 0.2, 1.2, y, y + 0.8
        # Repeat box
        Paint rectangle: col2$, 1.5, 2.5, y, y + 0.8
        
        Colour: "Black"
        dur_loop = loop_t2[k] - loop_t1[k]
        Text: 3, "left", y + 0.4, "half", "Loop " + string$(k) + ": " + fixed$(loop_t1[k], 2) + "-" + fixed$(loop_t2[k], 2) + "s"
        Text: 6.5, "left", y + 0.4, "half", "-> " + fixed$(rep_t1[k], 2) + "-" + fixed$(rep_t2[k], 2) + "s"
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text: 5, "centre", loops_found + 0.7, "half", "Detected Loops"
    
    # --- Parameters ---
    Select outer viewport: 0, 8, 5.6, 6.0
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 1.5, "centre", 0.5, "half", "Tolerance: " + string$(tolerance_hz) + " Hz | Loop duration: " + fixed$(min_loop_duration, 1) + "-" + fixed$(max_loop_duration, 1) + "s | Candidates: " + string$(nRows) + " | Found: " + string$(loops_found)
    
    Font size: 10
    Colour: "Black"
endif

# ===================================================================
# 6. CLEANUP & OUTPUT
# ===================================================================

removeObject: dataID, ssmID, tableID, pitchID

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Found ", loops_found, " loop(s)"
appendInfoLine: ""
appendInfoLine: "TextGrid shows:"
appendInfoLine: "  Tier 1 (Loops): Original loop regions"
appendInfoLine: "  Tier 2 (Repeats): Where they repeat"

selectObject: originalID
plusObject: textgridID

if open_textgrid_editor
    View & Edit
endif