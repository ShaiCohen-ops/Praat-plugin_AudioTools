# ============================================================
# Praat AudioTools - Timbral_Similarity_Browser.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025) - Fixed syntax
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Timbral Similarity Browser - Orders sounds from a folder by
#   MFCC-based timbral similarity using nearest-neighbor path.
#
# Changelog v0.3:
#   - Fixed old select/plus syntax to modern selectObject/plusObject
#   - Added presets for analysis parameters
#   - Added visualization
#   - Fixed directory separator for Windows
#   - Improved cleanup with removeObject
# ============================================================

form Timbral Similarity Browser v0.3
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
    # Standard
    num_coefficients = 12
    window_length = 0.015
    time_step = 0.005
    presetName$ = "Standard"
elsif preset = 2
    # Detailed
    num_coefficients = 24
    window_length = 0.020
    time_step = 0.005
    presetName$ = "Detailed"
elsif preset = 3
    # Fast
    num_coefficients = 6
    window_length = 0.015
    time_step = 0.010
    presetName$ = "Fast"
else
    presetName$ = "Custom"
endif

clearinfo
writeInfoLine: "=== Timbral Similarity Browser v0.3 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "MFCC coefficients: ", num_coefficients
appendInfoLine: ""

# ========== STEP 1: LOAD SOUNDS ==========
appendInfoLine: "STEP 1: Loading sounds from folder"
appendInfoLine: "------------------------------------"

directory$ = chooseDirectory$: "Select folder containing .wav files"
if directory$ = ""
    exitScript: "No folder selected."
endif

# Handle both Unix and Windows separators
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
    endif
endfor

appendInfoLine: ""
appendInfoLine: "Loaded: ", loadCount, " sounds"

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
    else
        To MFCC: num_coefficients, window_length, time_step, 100, 100, 0.0
        mfcc_'i' = selected("MFCC")
        
        selectObject: mfcc_'i'
        nFrames = Get number of frames
        appendInfoLine: "[", i, "] ", name$, " - ", nFrames, " frames"
        analyzed = analyzed + 1
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

# Store names for visualization
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

# Store distances for visualization
dist_vals# = zero#(n * n)

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
        
        # Store for visualization
        dist_vals#[(i-1)*n + j] = dist
        dist_vals#[(j-1)*n + i] = dist
    endfor
endfor

appendInfoLine: "Max distance: ", fixed$(maxDist, 2)

appendInfoLine: "Creating nearest-neighbor path..."

visited# = zero#(n)
path# = zero#(n)
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

first_idx = path#[1]
selectObject: sound_'first_idx'

for i from 2 to n
    idx = path#[i]
    plusObject: sound_'idx'
endfor

Concatenate
outputSound = selected("Sound")
Rename: "Timbral_Similarity_" + presetName$

Scale peak: 0.99

totalDur = Get total duration
appendInfoLine: "Output duration: ", fixed$(totalDur, 2), " s"

# ========== VISUALIZATION ==========
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Timbral Similarity Browser [" + presetName$ + "] - " + string$(n) + " sounds"
    
    # Output waveform
    Select outer viewport: 0, 8, 0.6, 1.8
    Select inner viewport: 0.6, 7.6, 0.8, 1.7
    selectObject: outputSound
    Colour: "{0.3, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Duration: " + fixed$(totalDur, 2) + " s"
    
    # Distance matrix heatmap (if not too large)
    if n <= 20
        Select outer viewport: 0, 4, 2.0, 4.5
        Select inner viewport: 0.6, 3.6, 2.3, 4.3
        
        Axes: 0, n, 0, n
        
        for i from 1 to n
            for j from 1 to n
                selectObject: distMatrix
                dist = Get value: i, j
                
                # Normalize to 0-1
                if maxDist > 0
                    intensity = dist / maxDist
                else
                    intensity = 0
                endif
                
                # Blue (similar) to Red (different)
                rVal = intensity
                gVal = 0.2
                bVal = 1 - intensity
                
                rVal$ = fixed$(rVal, 2)
                gVal$ = fixed$(gVal, 2)
                bVal$ = fixed$(bVal, 2)
                
                Paint rectangle: "{" + rVal$ + ", " + gVal$ + ", " + bVal$ + "}", i - 1, i, n - j, n - j + 1
            endfor
        endfor
        
        Colour: "Black"
        Draw inner box
        Font size: 8
        Text left: "yes", "Sound"
        Text bottom: "yes", "Sound"
        Text top: "no", "Distance Matrix"
    endif
    
    # Path distances
    Select outer viewport: 4, 8, 2.0, 4.5
    Select inner viewport: 4.4, 7.6, 2.3, 4.3
    
    # Compute path distances
    pathDist# = zero#(n - 1)
    maxPathDist = 0
    for i from 1 to n - 1
        idx1 = path#[i]
        idx2 = path#[i + 1]
        selectObject: distMatrix
        d = Get value: idx1, idx2
        pathDist#[i] = d
        if d > maxPathDist
            maxPathDist = d
        endif
    endfor
    
    if maxPathDist < 0.1
        maxPathDist = 1
    endif
    
    Axes: 0, n, 0, maxPathDist * 1.1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, n, 0, maxPathDist * 1.1
    
    # Draw path distances as bars
    for i from 1 to n - 1
        intensity = pathDist#[i] / maxPathDist
        rVal = 0.3 + intensity * 0.5
        gVal = 0.6 - intensity * 0.3
        bVal = 0.4
        rVal$ = fixed$(rVal, 2)
        gVal$ = fixed$(gVal, 2)
        bVal$ = fixed$(bVal, 2)
        Paint rectangle: "{" + rVal$ + ", " + gVal$ + ", " + bVal$ + "}", i - 0.4, i + 0.4, 0, pathDist#[i]
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Distance"
    Text bottom: "yes", "Step in path"
    Text top: "no", "Path Distances"
    
    # Stats
    Select outer viewport: 0, 8, 4.6, 5.1
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.15, "centre", 0.5, "half", "Sounds: " + string$(n)
    Text: 0.35, "centre", 0.5, "half", "MFCC: " + string$(num_coefficients)
    Text: 0.55, "centre", 0.5, "half", "Max dist: " + fixed$(maxDist, 1)
    Text: 0.8, "centre", 0.5, "half", "Duration: " + fixed$(totalDur, 1) + " s"
    
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

if auto_play
    appendInfoLine: ""
    appendInfoLine: "Playing..."
    selectObject: outputSound
    Play
endif

selectObject: outputSound