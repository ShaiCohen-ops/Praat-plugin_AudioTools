# ============================================================
# Praat AudioTools - Timbral_Similarity_Browser.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 (2026) - Folder field with blank-to-dialog fallback
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Timbral Similarity Browser - Orders sounds from a folder by
#   MFCC-based timbral similarity using nearest-neighbor path.
#
# Changelog v1.2:
#   - Added a "Folder" form field (mirrors VoidMosaic): type a path, or
#     leave it blank to fall back to a folder-selection dialog. The path
#     is whitespace- and trailing-slash-trimmed; cancelling the dialog
#     exits cleanly. Synced the version string across header/form/banner.
#
# Changelog v1.1:
#   - Guard against a single-sound batch (n = 1): no path/stats
#     division-by-zero; the one sound is output directly.
#   - Sounds too short to analyze (no MFCC) no longer pollute the
#     ordering with an all-zero feature vector. Their distance to
#     everything is set just above the max, so the nearest-neighbor
#     path visits them LAST instead of treating silence-like zero
#     vectors as mutually similar. (Changes ordering only for
#     batches that contain an un-analyzable file.)
#
# Changelog v1.0:
#   - Added path sequence display
#   - Added sound boundaries on waveform
#   - Added total path length metric
#   - Improved visualization layout
# ============================================================

form Timbral Similarity Browser v1.2
    comment === Audio Folder ===
    comment (Leave blank to pick a folder with a dialog)
    sentence Folder 
    comment === Preset ===
    optionmenu Preset: 1
        option Standard (12 MFCC)
        option Detailed (24 MFCC)
        option Fast (6 MFCC)
    comment === Loading Options ===
    integer Max_files_to_load 0 (= all)
    comment === Analysis Parameters ===
    integer Num_coefficients 12
    positive Window_length 0.015
    positive Time_step 0.005
    comment === Output ===
    boolean Draw_visualization 1
    boolean Auto_play 1
endform

# ===== PRESET LOGIC =====
if preset = 1
    num_coefficients = 12
    window_length = 0.015
    time_step = 0.005
    presetName$ = "Standard"
elsif preset = 2
    num_coefficients = 24
    window_length = 0.020
    time_step = 0.005
    presetName$ = "Detailed"
elsif preset = 3
    num_coefficients = 6
    window_length = 0.015
    time_step = 0.010
    presetName$ = "Fast"
else
    presetName$ = "Custom"
endif

clearinfo
writeInfoLine: "=== Timbral Similarity Browser v1.2 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "MFCC coefficients: ", num_coefficients
appendInfoLine: ""

# ========== STEP 1: LOAD SOUNDS ==========
appendInfoLine: "STEP 1: Loading sounds from folder"
appendInfoLine: "------------------------------------"

# --- FOLDER DISCOVERY ---
# Mirrors VoidMosaic: use the typed path, or fall back to a dialog when
# the Folder field is left blank. Trim whitespace and trailing slashes
# first; the trailing-slash normalization just below re-adds it for the
# *.wav glob.
directory$ = replace_regex$(folder$, "^[ \t]*|[ \t]*$", "", 0)
directory$ = replace_regex$(directory$, "[\\/]+$", "", 0)

if directory$ == ""
    directory$ = chooseFolder$: "Select folder containing .wav files"
    directory$ = replace_regex$(directory$, "[\\/]+$", "", 0)
endif

if directory$ == ""
    exitScript: "Operation cancelled. Please supply a valid folder path."
endif

if right$(directory$, 1) <> "/" and right$(directory$, 1) <> "\"
    if index(directory$, "\") > 0
        directory$ = directory$ + "\"
    else
        directory$ = directory$ + "/"
    endif
endif

appendInfoLine: "Loading from: ", directory$

files$# = fileNames_caseInsensitive$#(directory$ + "*.wav")
nFiles = size(files$#)

if nFiles = 0
    exitScript: "No .wav files found in folder."
endif

appendInfoLine: "Found ", nFiles, " file(s)"

if max_files_to_load > 0 and max_files_to_load < nFiles
    nFiles = max_files_to_load
    appendInfoLine: "Loading first ", nFiles, " file(s)"
endif

appendInfoLine: ""

loadCount = 0
targetSR = 0

for i from 1 to nFiles
    f$ = files$#[i]
    appendInfoLine: "[", i, "/", nFiles, "] ", f$
    
    nocheck Read from file: directory$ + f$
    
    if numberOfSelected("Sound") = 0
        appendInfoLine: "    FAILED to load"
    else
        loadCount = loadCount + 1
        s_id = selected("Sound")
        name$ = selected$("Sound")
        nCh = Get number of channels
        
        if nCh > 1
            appendInfoLine: "    OK (stereo -> mono)"
            Convert to mono
            mono_id = selected("Sound")
            removeObject: s_id
            selectObject: mono_id
            Rename: name$
            sound_'loadCount' = mono_id
        else
            appendInfoLine: "    OK (mono)"
            sound_'loadCount' = s_id
        endif
        
        # On first sound: set target SR for the session
        selectObject: sound_'loadCount'
        fileSR = Get sampling frequency
        if targetSR = 0
            targetSR = fileSR
            appendInfoLine: "    SR: ", targetSR, " Hz  [reference]"
        elsif fileSR <> targetSR
            # Resample to match target SR
            appendInfoLine: "    SR: ", fileSR, " Hz -> resampling to ", targetSR, " Hz"
            Resample: targetSR, 50
            resampled_id = selected("Sound")
            removeObject: sound_'loadCount'
            Rename: name$
            sound_'loadCount' = resampled_id
        else
            appendInfoLine: "    SR: ", fileSR, " Hz  [OK]"
        endif
        
        # Store duration for visualization
        selectObject: sound_'loadCount'
        sound_dur_'loadCount' = Get total duration
    endif
endfor

appendInfoLine: ""
appendInfoLine: "Loaded: ", loadCount, " sounds  (target SR: ", targetSR, " Hz)"

if loadCount = 0
    exitScript: "No sounds were loaded successfully."
endif

number_of_sounds = loadCount

# ========== STEP 2: MFCC ANALYSIS ==========
appendInfoLine: ""
appendInfoLine: "STEP 2: MFCC Analysis"
appendInfoLine: "---------------------"

analyzed = 0
failed_mfcc = 0

for i from 1 to number_of_sounds
    selectObject: sound_'i'
    name$ = selected$("Sound")
    
    dur = Get total duration
    
    if dur < 0.02
        appendInfoLine: "[", i, "] ", name$, " - SKIPPED (too short)"
        failed_mfcc = failed_mfcc + 1
        mfcc_'i' = 0
        analyzed_'i' = 0
    else
        To MFCC: num_coefficients, window_length, time_step, 100, 100, 0.0
        mfcc_'i' = selected("MFCC")
        
        selectObject: mfcc_'i'
        nFrames = Get number of frames
        appendInfoLine: "[", i, "] ", name$, " - ", nFrames, " frames"
        analyzed = analyzed + 1
        analyzed_'i' = 1
    endif
endfor

appendInfoLine: ""
appendInfoLine: "Analyzed: ", analyzed, " | Skipped: ", failed_mfcc

if analyzed = 0
    exitScript: "No sounds were successfully analyzed."
endif

n = number_of_sounds

# ========== STEP 3: COMPUTE SIMILARITY ==========
appendInfoLine: ""
appendInfoLine: "STEP 3: Computing Similarity"
appendInfoLine: "----------------------------"

appendInfoLine: "Computing mean MFCC vectors..."

Create TableOfReal: "MFCC_Features", n, num_coefficients
featureTable = selected("TableOfReal")

for i from 1 to n
    selectObject: sound_'i'
    name$ = selected$("Sound")
    sound_name_'i'$ = name$
    
    if mfcc_'i' <> 0
        selectObject: mfcc_'i'
        nFrames = Get number of frames
        
        for coef from 1 to num_coefficients
            sum = 0
            count = 0
            
            selectObject: mfcc_'i'
            for frame from 1 to nFrames
                value = Get value in frame: frame, coef
                if value <> undefined
                    sum = sum + value
                    count = count + 1
                endif
            endfor
            
            if count > 0
                mean_value = sum / count
            else
                mean_value = 0
            endif
            
            selectObject: featureTable
            Set value: i, coef, mean_value
        endfor
    endif
    
    selectObject: featureTable
    Set row label (index): i, name$
endfor

appendInfoLine: "Computing pairwise distances..."

Create TableOfReal: "Distance_Matrix", n, n
distMatrix = selected("TableOfReal")

for i from 1 to n
    selectObject: sound_'i'
    name$ = selected$("Sound")
    
    selectObject: distMatrix
    Set row label (index): i, name$
    Set column label (index): i, name$
endfor

maxDist = 0
for i from 1 to n
    for j from i to n
        dist = 0
        
        selectObject: featureTable
        for coef from 1 to num_coefficients
            val_i = Get value: i, coef
            val_j = Get value: j, coef
            diff = val_i - val_j
            dist = dist + diff * diff
        endfor
        
        dist = sqrt(dist)
        
        if dist > maxDist
            maxDist = dist
        endif
        
        selectObject: distMatrix
        Set value: i, j, dist
        Set value: j, i, dist
    endfor
endfor

appendInfoLine: "Max distance: ", fixed$(maxDist, 2)

# Sounds with no MFCC have an all-zero feature row, which would place
# them at a phantom origin in MFCC space. Push their pairwise distances
# just above the real maximum so the nearest-neighbor path defers them
# to the end rather than clustering them as "similar".
penalty = maxDist + 1.0
any_skipped = 0
for i from 1 to n
    if analyzed_'i' = 0
        any_skipped = 1
        selectObject: distMatrix
        for j from 1 to n
            if j <> i
                Set value: i, j, penalty
                Set value: j, i, penalty
            endif
        endfor
    endif
endfor
if any_skipped = 1
    appendInfoLine: "  (un-analyzable sounds deferred to end of path)"
endif

appendInfoLine: "Creating nearest-neighbor path..."

path# = zero#(n)
if n = 1
    # Single sound: the path is trivially that one sound.
    path#[1] = 1
else
    visited# = zero#(n)
    current = 1
    path#[1] = 1
    visited#[1] = 1

    for step from 2 to n
        min_dist = 1e30
        next_sound = 0
        
        selectObject: distMatrix
        for candidate from 1 to n
            if visited#[candidate] = 0
                dist = Get value: current, candidate
                if dist < min_dist
                    min_dist = dist
                    next_sound = candidate
                endif
            endif
        endfor
        
        if next_sound > 0
            path#[step] = next_sound
            visited#[next_sound] = 1
            current = next_sound
        endif
    endfor
endif

appendInfoLine: ""
appendInfoLine: "SIMILARITY PATH:"
appendInfoLine: ""

for i from 1 to n
    idx = path#[i]
    selectObject: sound_'idx'
    name$ = selected$("Sound")
    appendInfoLine: "  ", i, ". ", name$
endfor

# ========== STEP 4: CONCATENATE ==========
appendInfoLine: ""
appendInfoLine: "STEP 4: Concatenating"
appendInfoLine: "---------------------"

# Store cumulative positions for boundary visualization
cumulative_pos# = zero#(n + 1)
cumulative_pos#[1] = 0

first_idx = path#[1]
selectObject: sound_'first_idx'
cumulative_pos#[2] = sound_dur_'first_idx'

for i from 2 to n
    idx = path#[i]
    plusObject: sound_'idx'
    cumulative_pos#[i + 1] = cumulative_pos#[i] + sound_dur_'idx'
endfor

Concatenate
outputSound = selected("Sound")
Rename: "Timbral_Similarity_" + presetName$

Scale peak: 0.99

totalDur = Get total duration
appendInfoLine: "Output duration: ", fixed$(totalDur, 2), " s"

# Compute path distances and total path length
totalPathLength = 0
maxPathDist = 0
meanPathDist = 0

if n > 1
    pathDist# = zero#(n - 1)
    for i from 1 to n - 1
        idx1 = path#[i]
        idx2 = path#[i + 1]
        selectObject: distMatrix
        d = Get value: idx1, idx2
        pathDist#[i] = d
        totalPathLength = totalPathLength + d
        if d > maxPathDist
            maxPathDist = d
        endif
    endfor
    meanPathDist = totalPathLength / (n - 1)
    appendInfoLine: "Total path length: ", fixed$(totalPathLength, 2)
    appendInfoLine: "Mean step distance: ", fixed$(meanPathDist, 3)
else
    appendInfoLine: "Single sound: no path distances."
endif

# ========== VISUALIZATION ==========
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    Select outer viewport: 0, 8, 0, 8
    
    # === Title ===
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half", "##Timbral Similarity Browser##"
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.2, "centre", -1, "half", presetName$ + " | " + string$(n) + " sounds | " + string$(num_coefficients) + " MFCCs"
    
    # === Output Waveform with Boundaries ===
    Select outer viewport: 0, 8, 0.6, 1.9
    Select inner viewport: 0.6, 7.7, 0.75, 1.8
    
    selectObject: outputSound
    Colour: "{0.4, 0.55, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    # Draw sound boundaries
    Colour: "{0.8, 0.5, 0.4}"
    Dashed line
    for i from 2 to n
        boundaryTime = cumulative_pos#[i]
        Draw line: boundaryTime, -0.95, boundaryTime, 0.95
    endfor
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "no", "Time (s)"
    Text top: "no", "Concatenated (" + fixed$(totalDur, 2) + " s) - dashed lines = boundaries"
    
    # === Distance Matrix Heatmap ===
    if n <= 20
        Select outer viewport: 0, 4, 2.0, 4.3
        Select inner viewport: 0.6, 3.7, 2.2, 4.1
        
        Axes: 0, n, 0, n
        
        for i from 1 to n
            for j from 1 to n
                selectObject: distMatrix
                dist = Get value: i, j
                
                if maxDist > 0
                    intensity = dist / maxDist
                else
                    intensity = 0
                endif
                
                # Blue (similar) to Orange (different)
                rVal = 0.3 + intensity * 0.5
                gVal = 0.5 - intensity * 0.2
                bVal = 0.7 - intensity * 0.4
                
                rVal$ = fixed$(rVal, 2)
                gVal$ = fixed$(gVal, 2)
                bVal$ = fixed$(bVal, 2)
                
                Paint rectangle: "{" + rVal$ + ", " + gVal$ + ", " + bVal$ + "}", i - 1, i, n - j, n - j + 1
            endfor
        endfor
        
        # Highlight path on matrix
        Colour: "{0.9, 0.3, 0.3}"
        Line width: 2
        for i from 1 to n - 1
            idx1 = path#[i]
            idx2 = path#[i + 1]
            x1 = idx1 - 0.5
            y1 = n - idx1 + 0.5
            x2 = idx2 - 0.5
            y2 = n - idx2 + 0.5
            Draw line: x1, y1, x2, y2
        endfor
        Line width: 1
        
        Colour: "Black"
        Draw inner box
        Font size: 6
        Text left: "yes", "Sound #"
        Text bottom: "no", "Sound #"
        Text top: "no", "Distance Matrix (red line = path)"
    else
        # Too many sounds - show message
        Select outer viewport: 0, 4, 2.0, 4.3
        Select inner viewport: 0.6, 3.7, 2.2, 4.1
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
        Font size: 9
        Colour: "{0.5, 0.5, 0.5}"
        Text: 0.5, "centre", 0.5, "half", "Distance matrix too large to display"
        Text: 0.5, "centre", 0.3, "half", "(" + string$(n) + " × " + string$(n) + " = " + string$(n*n) + " cells)"
        Colour: "Black"
        Draw inner box
    endif
    
    # === Path Distances ===
    Select outer viewport: 4, 8, 2.0, 4.3
    Select inner viewport: 4.4, 7.7, 2.2, 4.1
    
    if maxPathDist < 0.1
        maxPathDist = 1
    endif
    
    Axes: 0, n, 0, maxPathDist * 1.15
    Paint rectangle: "{0.97, 0.98, 0.97}", 0, n, 0, maxPathDist * 1.15
    
    # Mean line
    Colour: "{0.8, 0.8, 0.8}"
    Dashed line
    Draw line: 0, meanPathDist, n, meanPathDist
    Solid line
    
    # Draw path distances as bars
    for i from 1 to n - 1
        intensity = pathDist#[i] / maxPathDist
        rVal = 0.4 + intensity * 0.4
        gVal = 0.65 - intensity * 0.25
        bVal = 0.5 - intensity * 0.2
        rVal$ = fixed$(rVal, 2)
        gVal$ = fixed$(gVal, 2)
        bVal$ = fixed$(bVal, 2)
        Paint rectangle: "{" + rVal$ + ", " + gVal$ + ", " + bVal$ + "}", i - 0.35, i + 0.35, 0, pathDist#[i]
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Distance"
    Text bottom: "no", "Step"
    Text top: "no", "Path Distances (mean=" + fixed$(meanPathDist, 2) + ")"
    
    # === Path Sequence ===
    Select outer viewport: 0, 8, 4.4, 5.8
    Select inner viewport: 0.6, 7.7, 4.55, 5.7
    
    Axes: 0, n + 1, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, n + 1, 0, 1
    
    Font size: 5
    Colour: "{0.3, 0.3, 0.4}"
    
    # Show path sequence (truncate names if needed)
    maxNameLen = 12
    for i from 1 to n
        idx = path#[i]
        name$ = sound_name_'idx'$
        if length(name$) > maxNameLen
            name$ = left$(name$, maxNameLen - 2) + ".."
        endif
        
        # Alternate colors for readability
        if i mod 2 = 0
            Paint rectangle: "{0.92, 0.94, 0.96}", i - 0.45, i + 0.45, 0.15, 0.85
        else
            Paint rectangle: "{0.96, 0.94, 0.92}", i - 0.45, i + 0.45, 0.15, 0.85
        endif
        
        Colour: "{0.2, 0.2, 0.3}"
        Text: i, "centre", 0.5, "half", string$(i) + ":" + name$
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text top: "no", "Similarity Path: Start → Most Similar → ... → End"
    
    # === Summary Stats ===
    Select outer viewport: 0, 8, 5.9, 6.5
    Axes: 0, 1, 0, 1
    
    Paint rectangle: "{0.95, 0.97, 0.95}", 0, 1, 0, 1
    
    Font size: 7
    Colour: "{0.3, 0.3, 0.4}"
    
    Text: 0.12, "centre", 0.5, "half", "Sounds: " + string$(n)
    Text: 0.30, "centre", 0.5, "half", "MFCCs: " + string$(num_coefficients)
    Text: 0.50, "centre", 0.5, "half", "Max dist: " + fixed$(maxDist, 2)
    Text: 0.70, "centre", 0.5, "half", "Path length: " + fixed$(totalPathLength, 2)
    Text: 0.88, "centre", 0.5, "half", "Duration: " + fixed$(totalDur, 1) + "s"
    
    Font size: 10
    Colour: "Black"
endif

# ========== CLEANUP ==========
appendInfoLine: ""
appendInfoLine: "STEP 5: Cleanup"
appendInfoLine: "---------------"

for i from 1 to n
    removeObject: sound_'i'
    if mfcc_'i' <> 0
        removeObject: mfcc_'i'
    endif
endfor

removeObject: featureTable, distMatrix

appendInfoLine: "Cleanup complete!"

# ========== OUTPUT ==========
selectObject: outputSound

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(totalDur, 2), " s"
appendInfoLine: "Total path length: ", fixed$(totalPathLength, 2)

if auto_play
    appendInfoLine: ""
    appendInfoLine: "Playing..."
    selectObject: outputSound
    Play
endif

selectObject: outputSound