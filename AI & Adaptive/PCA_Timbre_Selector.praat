# ============================================================
# Praat AudioTools - PCA_Timbre_Selector.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025) - Fixed syntax
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   PCA Timbre Selector - Analyzes timbre via PCA and selects
#   segments matching target timbre characteristics.
#
# Changelog v0.3:
#   - Fixed array access syntax (chunk_id_1 not chunk_id_[1])
#   - Added preset name to output
#   - Added visualization
#   - Added selectivity control for stronger effect
#   - Made presets more extreme (2.5 SD instead of 1.5)
# ============================================================

# === Input Validation ===
nSelected = numberOfSelected("Sound")
if nSelected <> 1
    exitScript: "Please select exactly one Sound object."
endif

snd = selected("Sound")
sndName$ = selected$("Sound")

form PCA Timbre Selector v0.3
    comment === Timbre Presets ===
    optionmenu Preset: 1
        option Custom
        option Bright/Clear (High Centroid)
        option Dark/Mellow (Low Centroid)
        option Noisy/Breathy (Low HNR)
        option Tonal/Focused (High HNR)
        option High Pitch
        option Low Pitch
        option Center (Average)
    comment === Analysis Parameters ===
    positive Segment_ms 25
    positive Frame_step_seconds 0.01
    positive F0_min 75
    positive F0_max 600
    comment === Selection Strength ===
    positive Selectivity 0.2
    comment === Custom Target (Standard Deviations) ===
    real Target_pc1 0.0
    real Target_pc2 0.0
    real Target_pc3 0.0
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ===== PRESET NAME =====
if preset = 1
    presetName$ = "Custom"
elsif preset = 2
    presetName$ = "Bright"
elsif preset = 3
    presetName$ = "Dark"
elsif preset = 4
    presetName$ = "Noisy"
elsif preset = 5
    presetName$ = "Tonal"
elsif preset = 6
    presetName$ = "HighPitch"
elsif preset = 7
    presetName$ = "LowPitch"
else
    presetName$ = "Center"
endif

# ===== 1. SETUP =====
clearinfo
writeInfoLine: "=== PCA Timbre Selector v0.3 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Selectivity: ", selectivity, " (lower = more selective)"
appendInfoLine: ""

selectObject: snd
dur = Get total duration
fs = Get sampling frequency
nch = Get number of channels

selectObject: snd
Copy: "Analysis_Work"
workSnd = selected("Sound")

if nch > 1
    selectObject: workSnd
    Convert to mono
    monoSnd = selected("Sound")
    selectObject: workSnd
    Remove
    workSnd = monoSnd
    selectObject: workSnd
    Rename: "Analysis_Work"
endif

if workSnd = 0
    exitScript: "Error: Failed to create analysis copy."
endif

# ===== 2. BATCH FEATURE EXTRACTION =====
appendInfoLine: "Extracting features..."

selectObject: workSnd
To Pitch: frame_step_seconds, f0_min, f0_max
pit = selected("Pitch")

selectObject: workSnd
To Intensity: 75, frame_step_seconds, "yes"
inten = selected("Intensity")

selectObject: workSnd
To Spectrogram: segment_ms/1000, fs/2, frame_step_seconds, 20, "Gaussian"
specg = selected("Spectrogram")

selectObject: workSnd
To Harmonicity (ac): frame_step_seconds, f0_min, 0.1, 4.5
harmo = selected("Harmonicity")

selectObject: pit
nF = Get number of frames
t0 = Get start time
dt = Get time step

if nF < 10
    removeObject: pit, inten, specg, harmo, workSnd
    exitScript: "Sound too short for analysis."
endif

Create TableOfReal: "raw_features", nF, 5
feat = selected("TableOfReal")

# Store feature values for visualization
pitch_vals# = zero#(nF)
intensity_vals# = zero#(nF)
centroid_vals# = zero#(nF)
hnr_vals# = zero#(nF)

# 1. Pitch
selectObject: pit
for i from 1 to nF
    v = Get value in frame: i, "Hertz"
    if v = undefined
        v = 0
    endif
    pitch_vals#[i] = v
    selectObject: feat
    Set value: i, 1, v
    selectObject: pit
endfor

# 2. Intensity
selectObject: inten
for i from 1 to nF
    v = Get value in frame: i
    if v = undefined
        v = -100
    endif
    intensity_vals#[i] = v
    selectObject: feat
    Set value: i, 2, v
    selectObject: inten
endfor

# 3. Spectral Features
selectObject: specg
for i from 1 to nF
    t = t0 + (i-1)*dt
    selectObject: specg
    To Spectrum (slice): t
    spec = selected("Spectrum")
    cent = Get centre of gravity: 2
    spread = Get standard deviation: 2
    Remove
    
    if cent = undefined
        cent = 0
    endif
    if spread = undefined
        spread = 0
    endif
    centroid_vals#[i] = cent
    
    selectObject: feat
    Set value: i, 3, cent
    Set value: i, 4, spread
endfor

# 4. Harmonicity
selectObject: harmo
for i from 1 to nF
    v = Get value in frame: i
    if v = undefined
        v = -50
    endif
    hnr_vals#[i] = v
    selectObject: feat
    Set value: i, 5, v
    selectObject: harmo
endfor

removeObject: pit, inten, specg, harmo

appendInfoLine: "  ", nF, " frames analyzed"

# ===== 3. PCA & STANDARDIZATION =====
appendInfoLine: "Running PCA..."

selectObject: feat
To PCA
pca = selected("PCA")

# Smart Axis Detection
selectObject: pca
eig_f0 = Get eigenvector element: 1, 1
eig_int = Get eigenvector element: 1, 2
eig_cent = Get eigenvector element: 1, 3
eig_hnr = Get eigenvector element: 1, 5

idx_bright = 1
sign_bright = 1
idx_hnr = 2
sign_hnr = 1
idx_pitch = 3
sign_pitch = 1

if abs(eig_cent) > 0.5
    idx_bright = 1
    if eig_cent < 0
        sign_bright = -1
    else
        sign_bright = 1
    endif
elsif abs(eig_hnr) > 0.5
    idx_hnr = 1
    if eig_hnr < 0
        sign_hnr = -1
    else
        sign_hnr = 1
    endif
elsif abs(eig_f0) > 0.5
    idx_pitch = 1
    if eig_f0 < 0
        sign_pitch = -1
    else
        sign_pitch = 1
    endif
endif

selectObject: feat
plusObject: pca
To Configuration: 3
scores = selected("Configuration")
To TableOfReal
scoresTbl = selected("TableOfReal")
removeObject: scores

# Store PCA scores for visualization
pc1_vals# = zero#(nF)
pc2_vals# = zero#(nF)
pc3_vals# = zero#(nF)

for i from 1 to nF
    selectObject: scoresTbl
    pc1_vals#[i] = Get value: i, 1
    pc2_vals#[i] = Get value: i, 2
    pc3_vals#[i] = Get value: i, 3
endfor

# ===== 4. APPLY PRESETS =====
t1 = target_pc1
t2 = target_pc2
t3 = target_pc3

# Use stronger target values (2.5 SD instead of 1.5) for more audible effect
if preset = 2
    # Bright
    if idx_bright = 1
        t1 = 2.5 * sign_bright
    elsif idx_bright = 2
        t2 = 2.5 * sign_bright
    else
        t3 = 2.5 * sign_bright
    endif
elsif preset = 3
    # Dark
    if idx_bright = 1
        t1 = -2.5 * sign_bright
    elsif idx_bright = 2
        t2 = -2.5 * sign_bright
    else
        t3 = -2.5 * sign_bright
    endif
elsif preset = 4
    # Noisy
    if idx_hnr = 1
        t1 = -2.5 * sign_hnr
    elsif idx_hnr = 2
        t2 = -2.5 * sign_hnr
    else
        t3 = -2.5 * sign_hnr
    endif
elsif preset = 5
    # Tonal
    if idx_hnr = 1
        t1 = 2.5 * sign_hnr
    elsif idx_hnr = 2
        t2 = 2.5 * sign_hnr
    else
        t3 = 2.5 * sign_hnr
    endif
elsif preset = 6
    # High Pitch
    if idx_pitch = 1
        t1 = 2.5 * sign_pitch
    elsif idx_pitch = 2
        t2 = 2.5 * sign_pitch
    else
        t3 = 2.5 * sign_pitch
    endif
elsif preset = 7
    # Low Pitch
    if idx_pitch = 1
        t1 = -2.5 * sign_pitch
    elsif idx_pitch = 2
        t2 = -2.5 * sign_pitch
    else
        t3 = -2.5 * sign_pitch
    endif
endif

appendInfoLine: "Target PCA: ", fixed$(t1, 2), " / ", fixed$(t2, 2), " / ", fixed$(t3, 2)

# ===== 5. SELECTION & RECONSTRUCTION =====

Create TableOfReal: "Distance", nF, 1
distTbl = selected("TableOfReal")

# Store distances and selection mask for visualization
dist_vals# = zero#(nF)
selected_mask# = zero#(nF)

for i from 1 to nF
    selectObject: scoresTbl
    v1 = Get value: i, 1
    v2 = Get value: i, 2
    v3 = Get value: i, 3
    d2 = (v1-t1)^2 + (v2-t2)^2 + (v3-t3)^2
    dist_vals#[i] = sqrt(d2)
    selectObject: distTbl
    Set value: i, 1, d2
endfor

# Threshold Logic - use selectivity parameter for stronger effect
selectObject: distTbl
meanD = Get column mean (index): 1
thresh = meanD * selectivity

appendInfoLine: "Threshold: ", fixed$(sqrt(thresh), 2), " (mean distance: ", fixed$(sqrt(meanD), 2), ")"

# Create a Table to store Chunk IDs
Create TableOfReal: "ChunkIDs", nF, 1
chunkTable = selected("TableOfReal")
chunk_count = 0

selectObject: workSnd
chunk_start = -1
chunk_end = -1

# Count selected frames for info
selected_frame_count = 0

# Scan frames and build Chunks
for i from 1 to nF
    selectObject: distTbl
    d = Get value: i, 1
    
    is_selected = 0
    if d < thresh
        is_selected = 1
        selected_mask#[i] = 1
        selected_frame_count = selected_frame_count + 1
    endif
    
    t_frame = t0 + (i-1)*dt
    t_s = t_frame
    t_e = t_frame + dt
    
    if is_selected
        if chunk_start = -1
            chunk_start = t_s
        endif
        chunk_end = t_e
    else
        if chunk_start <> -1
            selectObject: workSnd
            Extract part: chunk_start, chunk_end, "rectangular", 1, "no"
            chunkID = selected("Sound")
            
            chunk_count = chunk_count + 1
            selectObject: chunkTable
            Set value: chunk_count, 1, chunkID
            
            # Store in indexed variable
            chunk_id_'chunk_count' = chunkID
            
            chunk_start = -1
        endif
    endif
endfor

# Handle final chunk
if chunk_start <> -1
    selectObject: workSnd
    Extract part: chunk_start, chunk_end, "rectangular", 1, "no"
    chunkID = selected("Sound")
    
    chunk_count = chunk_count + 1
    selectObject: chunkTable
    Set value: chunk_count, 1, chunkID
    
    chunk_id_'chunk_count' = chunkID
endif

appendInfoLine: "Selected ", selected_frame_count, " of ", nF, " frames (", fixed$(100 * selected_frame_count / nF, 1), "%)"

# Concatenate Chunks
if chunk_count > 0
    # Select first chunk
    first = chunk_id_1
    selectObject: first
    
    # Select rest
    for i from 2 to chunk_count
        nxt = chunk_id_'i'
        plusObject: nxt
    endfor
    
    Concatenate
    Rename: sndName$ + "_Timbre_" + presetName$
    finalSnd = selected("Sound")
    
    # Scale output
    Scale peak: 0.99
    
    # Get output duration
    selectObject: finalSnd
    finalDur = Get total duration
    
    # Remove chunks
    for i from 1 to chunk_count
        del = chunk_id_'i'
        removeObject: del
    endfor
    
    appendInfoLine: "Success: Combined ", chunk_count, " segments"
    appendInfoLine: "Output duration: ", fixed$(finalDur, 2), " s (", fixed$(100 * finalDur / dur, 1), "% of original)"
else
    removeObject: feat, pca, scoresTbl, distTbl, workSnd, chunkTable
    exitScript: "No segments matched the target timbre criteria. Try increasing Selectivity value."
endif

# ===== VISUALIZATION =====
if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "PCA Timbre Selector: " + sndName$ + " [" + presetName$ + "]"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.6
    Select inner viewport: 0.6, 7.6, 0.7, 1.5
    selectObject: snd
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    Text top: "no", fixed$(dur, 2) + " s"
    
    # Output waveform
    Select outer viewport: 0, 8, 1.7, 2.7
    Select inner viewport: 0.6, 7.6, 1.8, 2.6
    selectObject: finalSnd
    Colour: "{0.3, 0.6, 0.4}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Selected"
    Text bottom: "yes", "Time (s)"
    Text top: "no", fixed$(finalDur, 2) + " s (" + string$(chunk_count) + " segments, " + fixed$(100 * finalDur / dur, 0) + "%)"
    
    # PCA scatter (PC1 vs PC2)
    Select outer viewport: 0, 4, 2.9, 4.5
    Select inner viewport: 0.6, 3.6, 3.1, 4.4
    
    # Find ranges
    minPC1 = pc1_vals#[1]
    maxPC1 = pc1_vals#[1]
    minPC2 = pc2_vals#[1]
    maxPC2 = pc2_vals#[1]
    
    for i from 2 to nF
        if pc1_vals#[i] < minPC1
            minPC1 = pc1_vals#[i]
        endif
        if pc1_vals#[i] > maxPC1
            maxPC1 = pc1_vals#[i]
        endif
        if pc2_vals#[i] < minPC2
            minPC2 = pc2_vals#[i]
        endif
        if pc2_vals#[i] > maxPC2
            maxPC2 = pc2_vals#[i]
        endif
    endfor
    
    pc1Range = maxPC1 - minPC1
    pc2Range = maxPC2 - minPC2
    if pc1Range < 0.1
        pc1Range = 1
    endif
    if pc2Range < 0.1
        pc2Range = 1
    endif
    
    Axes: minPC1 - pc1Range * 0.1, maxPC1 + pc1Range * 0.1, minPC2 - pc2Range * 0.1, maxPC2 + pc2Range * 0.1
    Paint rectangle: "{0.97, 0.97, 0.97}", minPC1 - pc1Range * 0.1, maxPC1 + pc1Range * 0.1, minPC2 - pc2Range * 0.1, maxPC2 + pc2Range * 0.1
    
    # Draw points - compute size based on range
    pointSize = pc1Range * 0.015
    pointSizeY = pc2Range * 0.015
    
    for i from 1 to nF
        x = pc1_vals#[i]
        y = pc2_vals#[i]
        if selected_mask#[i] = 1
            # Selected points in green
            Paint rectangle: "{0.3, 0.7, 0.4}", x - pointSize, x + pointSize, y - pointSizeY, y + pointSizeY
        else
            # Unselected points in gray
            Paint rectangle: "{0.75, 0.75, 0.75}", x - pointSize, x + pointSize, y - pointSizeY, y + pointSizeY
        endif
    endfor
    
    # Draw target point in red
    targetSize = pointSize * 3
    targetSizeY = pointSizeY * 3
    Paint rectangle: "{0.9, 0.2, 0.2}", t1 - targetSize, t1 + targetSize, t2 - targetSizeY, t2 + targetSizeY
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "PC2"
    Text bottom: "yes", "PC1"
    
    # Distance over time
    Select outer viewport: 4, 8, 2.9, 4.5
    Select inner viewport: 4.4, 7.6, 3.1, 4.4
    
    maxDist = dist_vals#[1]
    for i from 2 to nF
        if dist_vals#[i] > maxDist
            maxDist = dist_vals#[i]
        endif
    endfor
    if maxDist < 0.1
        maxDist = 1
    endif
    
    Axes: 0, dur, 0, maxDist * 1.1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, dur, 0, maxDist * 1.1
    
    # Threshold line
    Colour: "{0.8, 0.3, 0.3}"
    Dotted line
    Draw line: 0, sqrt(thresh), dur, sqrt(thresh)
    Solid line
    
    # Distance curve
    Colour: "{0.4, 0.5, 0.7}"
    for i from 2 to nF
        t1_pt = t0 + (i - 2) * dt
        t2_pt = t0 + (i - 1) * dt
        Draw line: t1_pt, dist_vals#[i-1], t2_pt, dist_vals#[i]
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Distance"
    Text bottom: "yes", "Time (s)"
    
    # Legend / stats
    Select outer viewport: 0, 8, 4.6, 5.1
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.15, "centre", 0.5, "half", "Target: (" + fixed$(t1, 1) + ", " + fixed$(t2, 1) + ", " + fixed$(t3, 1) + ")"
    Text: 0.4, "centre", 0.5, "half", "Selectivity: " + fixed$(selectivity, 2)
    Text: 0.65, "centre", 0.5, "half", "Selected: " + fixed$(100 * selected_frame_count / nF, 0) + "%"
    Text: 0.85, "centre", 0.5, "half", "Segments: " + string$(chunk_count)
    
    Font size: 10
    Colour: "Black"
endif

# ===== CLEANUP =====
selectObject: feat
plusObject: pca
plusObject: scoresTbl
plusObject: distTbl
plusObject: workSnd
plusObject: chunkTable
Remove

# ===== OUTPUT =====
selectObject: snd
plusObject: finalSnd

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="

if play_result
    selectObject: finalSnd
    Play
endif

selectObject: finalSnd