# ============================================================
# Praat AudioTools - OT_CORPUS_CONCATENATOR.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026) - Standardized folder field (blank-to-dialog idiom)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   OT Corpus Concatenator - Optimality Theory-inspired audio
#   selection and concatenation based on weighted constraint violations.
#
# Changelog v0.5:
#   - Standardized the Folder field to the shared blank-to-dialog idiom
#     (as in VoidMosaic): the typed path is whitespace- and trailing-
#     slash-trimmed, a blank field falls back to a chooseFolder$ dialog,
#     and cancelling exits cleanly. Synced the version string across
#     header/form/banner (form title was still v0.3.2).
# Changelog v0.4:
#   - FIXED: analysis loop now converts to mono before To MFCC; stereo
#            corpus files previously crashed there (the concat loop
#            already converted - only the analysis loop was missed).
# Changelog v0.3.2:
#   - FIXED: "Unknown symbol Get" error. Moved 'Get sampling frequency'
#            outside the 'if' statement.
# ============================================================

form OT Corpus Concatenator v0.5
    comment === Preset ===
    optionmenu Preset: 1
        option Manual
        option Bright & Energetic
        option Dark & Stable
        option Balanced
        option Maximum Energy
        option Timbral Consistency
    comment === Selection ===
    integer Limit_files 10
    sentence Folder_path
    comment (Leave blank to pick a folder with a dialog)
    comment === OT Constraints (Weights) ===
    real Weight_darkness 0.0
    real Weight_brightness 1.0
    real Weight_energy 2.0
    real Weight_stability 1.0
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================
# PRESET LOGIC
# ============================================

if preset = 2
    # Bright & Energetic
    weight_darkness = 2.0
    weight_brightness = 0.0
    weight_energy = 3.0
    weight_stability = 0.5
    presetName$ = "BrightEnergetic"
elsif preset = 3
    # Dark & Stable
    weight_darkness = 0.0
    weight_brightness = 2.0
    weight_energy = 1.0
    weight_stability = 3.0
    presetName$ = "DarkStable"
elsif preset = 4
    # Balanced
    weight_darkness = 1.0
    weight_brightness = 1.0
    weight_energy = 1.0
    weight_stability = 1.0
    presetName$ = "Balanced"
elsif preset = 5
    # Maximum Energy
    weight_darkness = 0.5
    weight_brightness = 0.5
    weight_energy = 5.0
    weight_stability = 0.0
    presetName$ = "MaxEnergy"
elsif preset = 6
    # Timbral Consistency
    weight_darkness = 0.5
    weight_brightness = 0.5
    weight_energy = 0.5
    weight_stability = 5.0
    presetName$ = "TimbralConsistency"
else
    presetName$ = "Manual"
endif

# ============================================
# DIRECTORY SELECTION
# ============================================

clearinfo
writeInfoLine: "=== OT Corpus Concatenator v0.5 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""

n_target = limit_files

# --- FOLDER DISCOVERY ---
# Mirrors VoidMosaic: use the typed path, or fall back to a dialog when
# the Folder field is left blank. Trim whitespace and trailing slashes
# first; the OS-specific trailing-slash normalization just below re-adds
# the separator for the *.wav glob.
directory$ = replace_regex$(folder_path$, "^[ \t]*|[ \t]*$", "", 0)
directory$ = replace_regex$(directory$, "[\\/]+$", "", 0)

if directory$ == ""
    directory$ = chooseFolder$: "Choose the folder containing your audio files"
    directory$ = replace_regex$(directory$, "[\\/]+$", "", 0)
endif

if directory$ == ""
    exitScript: "Operation cancelled. Please supply a valid folder path."
endif

if right$(directory$, 1) <> "/" and right$(directory$, 1) <> "\"
    if environment$("OS") = "Windows"
        directory$ = directory$ + "\"
    else
        directory$ = directory$ + "/"
    endif
endif

stringsID = Create Strings as file list: "FileList", directory$ + "*.wav"
nFiles = Get number of strings

if nFiles = 0
    selectObject: stringsID
    Remove
    exitScript: "No .wav files found in that directory!"
endif

if n_target > nFiles
    n_target = nFiles
endif

appendInfoLine: "Found ", nFiles, " files, selecting top ", n_target

# ============================================
# ANALYSIS TABLE
# ============================================

tableID = Create Table with column names: "OT_Leaderboard", nFiles, 
    ... "Filename C0_Energy C1_Tilt Stability Viol_Darkness Viol_Brightness Viol_Energy Viol_Stability Harmony_Score"

appendInfoLine: "Analyzing files..."

# ============================================
# ANALYSIS LOOP
# ============================================

for i from 1 to nFiles
    selectObject: stringsID
    fileName$ = Get string: i
    
    soundID = Read from file: directory$ + fileName$

    # To MFCC requires a mono signal - convert if the corpus file is
    # multichannel (the concat loop below already does this; the analysis
    # loop must too, or stereo files crash at To MFCC).
    selectObject: soundID
    nCh = Get number of channels
    if nCh > 1
        monoID = Convert to mono
        removeObject: soundID
        soundID = monoID
    endif

    selectObject: soundID
    mfccID = To MFCC: 12, 0.015, 0.005, 100.0, 100.0, 0
    
    nFrames = Get number of frames
    
    sum_c0 = 0
    sum_c1 = 0
    
    for f from 1 to nFrames
        val_c0 = Get value in frame: f, 1
        val_c1 = Get value in frame: f, 2
        sum_c0 = sum_c0 + val_c0
        sum_c1 = sum_c1 + val_c1
    endfor
    
    if nFrames > 0
        mean_c0 = sum_c0 / nFrames
        mean_c1 = sum_c1 / nFrames
    else
        mean_c0 = 0
        mean_c1 = 0
    endif
    
    sum_sq_diff = 0
    selectObject: mfccID
    for f from 1 to nFrames
        val_c1 = Get value in frame: f, 2
        diff = val_c1 - mean_c1
        sum_sq_diff = sum_sq_diff + (diff * diff)
    endfor
    
    if nFrames > 1
        stdev_c1 = sqrt(sum_sq_diff / (nFrames - 1))
    else
        stdev_c1 = 0
    endif
    
    # --- VIOLATIONS ---
    viol_dark = 0
    if mean_c1 < 0
        viol_dark = abs(mean_c1)
    endif
    
    viol_bright = 0
    if mean_c1 > 0
        viol_bright = mean_c1
    endif
    
    viol_energy = 100 - mean_c0
    if viol_energy < 0
        viol_energy = 0
    endif
    
    viol_stable = stdev_c1 * 10
    
    harmony = (viol_dark * weight_darkness) + (viol_bright * weight_brightness) + (viol_energy * weight_energy) + (viol_stable * weight_stability)
    
    selectObject: tableID
    Set string value: i, "Filename", fileName$
    Set numeric value: i, "C0_Energy", mean_c0
    Set numeric value: i, "C1_Tilt", mean_c1
    Set numeric value: i, "Stability", stdev_c1
    Set numeric value: i, "Viol_Darkness", viol_dark
    Set numeric value: i, "Viol_Brightness", viol_bright
    Set numeric value: i, "Viol_Energy", viol_energy
    Set numeric value: i, "Viol_Stability", viol_stable
    Set numeric value: i, "Harmony_Score", harmony
    
    selectObject: soundID
    plusObject: mfccID
    Remove
    
    if i mod 10 = 0
        appendInfo: "."
    endif
endfor

appendInfoLine: " done"

# ============================================
# SORTING
# ============================================

selectObject: tableID
Sort rows: "Harmony_Score"

appendInfoLine: ""
appendInfoLine: "============================================"
appendInfoLine: "CONSTRAINT WEIGHTS:"
appendInfoLine: "  *DARKNESS     = ", fixed$(weight_darkness, 2)
appendInfoLine: "  *BRIGHTNESS   = ", fixed$(weight_brightness, 2)
appendInfoLine: "  *LOW-ENERGY   = ", fixed$(weight_energy, 2)
appendInfoLine: "  *UNSTABLE     = ", fixed$(weight_stability, 2)
appendInfoLine: "============================================"
appendInfoLine: ""
appendInfoLine: "RANKING: Top ", n_target, " files by Harmony Score"
appendInfoLine: "--------------------------------------------"

# Store harmony scores for visualization
harmony_scores# = zero#(n_target)
energy_vals# = zero#(n_target)
tilt_vals# = zero#(n_target)

for i from 1 to n_target
    selectObject: tableID
    name$ = Get value: i, "Filename"
    score = Get value: i, "Harmony_Score"
    
    harmony_scores#[i] = score
    
    v_dark = Get value: i, "Viol_Darkness"
    v_bright = Get value: i, "Viol_Brightness"
    v_energy = Get value: i, "Viol_Energy"
    v_stable = Get value: i, "Viol_Stability"
    
    c0 = Get value: i, "C0_Energy"
    c1 = Get value: i, "C1_Tilt"
    
    energy_vals#[i] = c0
    tilt_vals#[i] = c1
    
    appendInfoLine: i, ". ", name$, " -> Harmony: ", fixed$(score, 2)
    appendInfoLine: "   Features: Energy=", fixed$(c0, 1), " | Tilt=", fixed$(c1, 2)
    
    if v_dark > 0 or v_bright > 0 or v_energy > 0 or v_stable > 0
        appendInfoLine: "   Violations:"
        if v_dark > 0
            appendInfoLine: "      *DARKNESS    = ", fixed$(v_dark, 2), " x ", weight_darkness, " = ", fixed$(v_dark * weight_darkness, 2)
        endif
        if v_bright > 0
            appendInfoLine: "      *BRIGHTNESS  = ", fixed$(v_bright, 2), " x ", weight_brightness, " = ", fixed$(v_bright * weight_brightness, 2)
        endif
        if v_energy > 0
            appendInfoLine: "      *LOW-ENERGY  = ", fixed$(v_energy, 2), " x ", weight_energy, " = ", fixed$(v_energy * weight_energy, 2)
        endif
        if v_stable > 0
            appendInfoLine: "      *UNSTABLE    = ", fixed$(v_stable, 2), " x ", weight_stability, " = ", fixed$(v_stable * weight_stability, 2)
        endif
    endif
    
    appendInfoLine: ""
endfor

appendInfoLine: "--------------------------------------------"

# ============================================
# CONCATENATION (FIXED FOR SAMPLING RATES)
# ============================================

appendInfoLine: "Loading and concatenating files..."

# Create array to store sound IDs
soundIDs# = zero#(n_target)

# We set a standard sample rate to prevent "Unequal sampling frequencies" error
target_sample_rate = 44100

for i from 1 to n_target
    selectObject: tableID
    fileName$ = Get value: i, "Filename"
    
    # Read the file
    readID = Read from file: directory$ + fileName$
    
    # Check frequency and resample if necessary
    # FIX: Get frequency first, then check variable in IF statement
    current_fs = Get sampling frequency
    
    if current_fs <> target_sample_rate
        soundID = Resample: target_sample_rate, 50
        selectObject: readID
        Remove
    else
        soundID = readID
    endif

    # Fix channel mismatch: convert to mono if needed
    selectObject: soundID
    nCh = Get number of channels
    if nCh > 1
        monoID = Convert to mono
        removeObject: soundID
        soundID = monoID
    endif

    soundIDs#[i] = soundID
endfor

# Select all sounds for concatenation
selectObject: soundIDs#[1]
for i from 2 to n_target
    plusObject: soundIDs#[i]
endfor

# Concatenate
Concatenate
finalID = selected("Sound")
Rename: "OT_Concat_" + presetName$

# Scale to prevent clipping
selectObject: finalID
Scale peak: 0.99

# Get duration for display
selectObject: finalID
finalDur = Get total duration

# ============================================
# VISUALIZATION
# ============================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # Title
    Select outer viewport: 1, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "OT Corpus Concatenator [" + presetName$ + "]"
    
    # Output waveform
    Select outer viewport: 0, 8, 0.6, 1.8
    Select inner viewport: 0.6, 7.6, 0.8, 1.7
    selectObject: finalID
    Colour: "{0.3, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Duration: " + fixed$(finalDur, 2) + " s"
    
    # Harmony scores bar chart
    Select outer viewport: 0, 4, 2.0, 3.5
    Select inner viewport: 0.6, 3.6, 2.2, 3.4
    
    maxHarmony = harmony_scores#[n_target]
    if maxHarmony < 1
        maxHarmony = 1
    endif
    
    Axes: 0, n_target + 1, 0, maxHarmony * 1.1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, n_target + 1, 0, maxHarmony * 1.1
    
    for i from 1 to n_target
        intensity = 1 - (i / n_target) * 0.7
        rVal$ = fixed$(0.2 + intensity * 0.3, 2)
        gVal$ = fixed$(0.5 + intensity * 0.3, 2)
        bVal$ = fixed$(0.3 + intensity * 0.4, 2)
        Paint rectangle: "{" + rVal$ + ", " + gVal$ + ", " + bVal$ + "}", i - 0.4, i + 0.4, 0, harmony_scores#[i]
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Harmony"
    Text bottom: "yes", "Rank"
    
    # Energy vs Tilt scatter
    Select outer viewport: 4, 8, 2.0, 3.5
    Select inner viewport: 4.4, 7.6, 2.2, 3.4
    
    minEnergy = energy_vals#[1]
    maxEnergy = energy_vals#[1]
    minTilt = tilt_vals#[1]
    maxTilt = tilt_vals#[1]
    
    for i from 2 to n_target
        if energy_vals#[i] < minEnergy
            minEnergy = energy_vals#[i]
        endif
        if energy_vals#[i] > maxEnergy
            maxEnergy = energy_vals#[i]
        endif
        if tilt_vals#[i] < minTilt
            minTilt = tilt_vals#[i]
        endif
        if tilt_vals#[i] > maxTilt
            maxTilt = tilt_vals#[i]
        endif
    endfor
    
    energyRange = maxEnergy - minEnergy
    if energyRange < 1
        energyRange = 1
    endif
    tiltRange = maxTilt - minTilt
    if tiltRange < 1
        tiltRange = 1
    endif
    
    Axes: minEnergy - energyRange * 0.1, maxEnergy + energyRange * 0.1, minTilt - tiltRange * 0.1, maxTilt + tiltRange * 0.1
    Paint rectangle: "{0.97, 0.97, 0.97}", minEnergy - energyRange * 0.1, maxEnergy + energyRange * 0.1, minTilt - tiltRange * 0.1, maxTilt + tiltRange * 0.1
    
    # Draw points as small rectangles
    pointSize = energyRange * 0.03
    pointSizeY = tiltRange * 0.03
    
    for i from 1 to n_target
        intensity = 1 - (i / n_target) * 0.7
        rVal = 0.2 + intensity * 0.5
        gVal = 0.4 + intensity * 0.4
        bVal = 0.6 + intensity * 0.2
        # Clamp to valid range
        rVal = max(0, min(1, rVal))
        gVal = max(0, min(1, gVal))
        bVal = max(0, min(1, bVal))
        rVal$ = fixed$(rVal, 2)
        gVal$ = fixed$(gVal, 2)
        bVal$ = fixed$(bVal, 2)
        
        # Use Paint rectangle instead of Paint circle
        x = energy_vals#[i]
        y = tilt_vals#[i]
        Paint rectangle: "{" + rVal$ + ", " + gVal$ + ", " + bVal$ + "}", x - pointSize, x + pointSize, y - pointSizeY, y + pointSizeY
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Tilt (C1)"
    Text bottom: "yes", "Energy (C0)"
    
    # Constraint weights
    Select outer viewport: 0, 8, 3.7, 4.3
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.15, "centre", 0.5, "half", "*DARK: " + fixed$(weight_darkness, 1)
    Text: 0.38, "centre", 0.5, "half", "*BRIGHT: " + fixed$(weight_brightness, 1)
    Text: 0.62, "centre", 0.5, "half", "*ENERGY: " + fixed$(weight_energy, 1)
    Text: 0.85, "centre", 0.5, "half", "*STABLE: " + fixed$(weight_stability, 1)
    
    Font size: 10
    Colour: "Black"
endif

# ============================================
# CLEANUP
# ============================================

# Remove individual sound files
for i from 1 to n_target
    removeObject: soundIDs#[i]
endfor

# Remove temporary objects
removeObject: stringsID, tableID

# ============================================
# OUTPUT
# ============================================

selectObject: finalID

appendInfoLine: ""
appendInfoLine: "============================================"
appendInfoLine: "SUCCESS!"
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Contains ", n_target, " concatenated files"
appendInfoLine: "Duration: ", fixed$(finalDur, 2), " s"
appendInfoLine: "============================================"

if play_result
    Play
endif

selectObject: finalID