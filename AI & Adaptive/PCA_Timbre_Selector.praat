# ============================================================
# Praat AudioTools - PCA_Timbre_Selector.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3 (2025) - Direct selection + PCA visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   PCA Timbre Selector - Analyzes timbre and selects segments
#   using direct feature selection for presets, with PCA
#   visualization for understanding the timbre space.
#
# Changelog v1.3:
#   - Fixed info banner (3 writeInfoLine -> 1 + appendInfoLine; the
#     title line was being erased)
#   - Standardize feature columns (z-score) before PCA so the timbre
#     space isn't dominated by the Hz-scale features
#   - Output preserves stereo (chunks extracted from the original,
#     not the mono analysis copy)
#   - Subtitle centered; distance-panel label reflects the mode
#
# Changelog v1.2:
#   - Restored PCA scatter plots and eigenvector loadings
#   - Kept direct feature selection (presets sound different)
#   - Combined best of v1.0 and v1.1
# ============================================================

# === Input Validation ===
nSelected = numberOfSelected("Sound")
if nSelected <> 1
    exitScript: "Please select exactly one Sound object."
endif

snd = selected("Sound")
sndName$ = selected$("Sound")

form PCA Timbre Selector v1.3
    comment === Timbre Presets ===
    optionmenu Preset: 1
        option Custom (PCA targeting)
        option Bright (high spectral centroid)
        option Dark (low spectral centroid)
        option Noisy (low HNR)
        option Tonal (high HNR)
        option High Pitch
        option Low Pitch
        option Loud (high intensity)
        option Quiet (low intensity)
    comment === Analysis Parameters ===
    positive Segment_ms 25
    positive Frame_step_seconds 0.01
    positive F0_min 75
    positive F0_max 600
    comment === Selection Strength ===
    comment (Percentile: 20 = top/bottom 20%)
    positive Selection_percentile 25
    comment === Custom PCA Target (only for Custom preset) ===
    real Target_pc1 0.0
    real Target_pc2 0.0
    real Target_pc3 0.0
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ===== PRESET CONFIGURATION =====
if preset = 1
    presetName$ = "Custom"
    selectionFeature$ = "PCA"
    selectionDirection = 0
elsif preset = 2
    presetName$ = "Bright"
    selectionFeature$ = "centroid"
    selectionDirection = 1
elsif preset = 3
    presetName$ = "Dark"
    selectionFeature$ = "centroid"
    selectionDirection = -1
elsif preset = 4
    presetName$ = "Noisy"
    selectionFeature$ = "hnr"
    selectionDirection = -1
elsif preset = 5
    presetName$ = "Tonal"
    selectionFeature$ = "hnr"
    selectionDirection = 1
elsif preset = 6
    presetName$ = "HighPitch"
    selectionFeature$ = "pitch"
    selectionDirection = 1
elsif preset = 7
    presetName$ = "LowPitch"
    selectionFeature$ = "pitch"
    selectionDirection = -1
elsif preset = 8
    presetName$ = "Loud"
    selectionFeature$ = "intensity"
    selectionDirection = 1
elsif preset = 9
    presetName$ = "Quiet"
    selectionFeature$ = "intensity"
    selectionDirection = -1
endif

# ===== 1. SETUP =====
writeInfoLine: "=============================================="
appendInfoLine: "  PCA TIMBRE SELECTOR v1.3"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Source: ", sndName$
appendInfoLine: "Preset: ", presetName$
if selectionFeature$ <> "PCA"
    appendInfoLine: "Mode: Direct feature selection"
    appendInfoLine: "Feature: ", selectionFeature$
    if selectionDirection = 1
        appendInfoLine: "Direction: HIGH values (top ", selection_percentile, "%)"
    else
        appendInfoLine: "Direction: LOW values (bottom ", selection_percentile, "%)"
    endif
else
    appendInfoLine: "Mode: PCA targeting"
    appendInfoLine: "Target: (", target_pc1, ", ", target_pc2, ", ", target_pc3, ")"
endif
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

# ===== 2. FEATURE EXTRACTION =====
appendInfoLine: "STEP 1: Extracting features..."

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

# Feature names
feature$[1] = "Pitch"
feature$[2] = "Intensity"
feature$[3] = "Centroid"
feature$[4] = "Spread"
feature$[5] = "HNR"

# Feature arrays
pitch_vals# = zero#(nF)
intensity_vals# = zero#(nF)
centroid_vals# = zero#(nF)
spread_vals# = zero#(nF)
hnr_vals# = zero#(nF)
time_vals# = zero#(nF)

# Create TableOfReal for PCA
Create TableOfReal: "raw_features", nF, 5
feat = selected("TableOfReal")

for c from 1 to 5
    Set column label (index): c, feature$[c]
endfor

# Extract all features
for i from 1 to nF
    time_vals#[i] = t0 + (i-1)*dt
    
    # Pitch
    selectObject: pit
    v = Get value in frame: i, "Hertz"
    if v = undefined or v <= 0
        v = 0
    endif
    pitch_vals#[i] = v
    selectObject: feat
    Set value: i, 1, v
    
    # Intensity
    selectObject: inten
    v = Get value in frame: i
    if v = undefined
        v = -100
    endif
    intensity_vals#[i] = v
    selectObject: feat
    Set value: i, 2, v
    
    # Centroid & Spread
    t = time_vals#[i]
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
    spread_vals#[i] = spread
    selectObject: feat
    Set value: i, 3, cent
    Set value: i, 4, spread
    
    # HNR
    selectObject: harmo
    v = Get value in frame: i
    if v = undefined
        v = -50
    endif
    hnr_vals#[i] = v
    selectObject: feat
    Set value: i, 5, v
endfor

removeObject: pit, inten, specg, harmo

appendInfoLine: "  ", nF, " frames analyzed"

# ===== 3. PCA (for visualization) =====
appendInfoLine: ""
appendInfoLine: "STEP 2: Running PCA..."

# Standardize feature columns (z-score) so PCA weights the Hz-scale
# and dB-scale features comparably, not by raw variance.
for c from 1 to 5
    selectObject: feat
    colMean = Get column mean (index): c
    colSd = Get column stdev (index): c
    if colSd <= 0
        colSd = 1
    endif
    for r from 1 to nF
        selectObject: feat
        v = Get value: r, c
        Set value: r, c, (v - colMean) / colSd
    endfor
endfor

selectObject: feat
To PCA
pca = selected("PCA")

# Store eigenvector loadings
for pc from 1 to 3
    for f from 1 to 5
        selectObject: pca
        loading[pc, f] = Get eigenvector element: pc, f
    endfor
endfor

# Variance explained
selectObject: pca
var1 = Get fraction variance accounted for: 1, 1
var2 = Get fraction variance accounted for: 2, 2
var3 = Get fraction variance accounted for: 3, 3

appendInfoLine: "  Variance explained: PC1=", fixed$(var1 * 100, 1), "%, PC2=", fixed$(var2 * 100, 1), "%, PC3=", fixed$(var3 * 100, 1), "%"

# Project to PC space
selectObject: feat
plusObject: pca
To Configuration: 3
scores = selected("Configuration")
To TableOfReal
scoresTbl = selected("TableOfReal")
removeObject: scores

# Store PCA scores
pc1_vals# = zero#(nF)
pc2_vals# = zero#(nF)
pc3_vals# = zero#(nF)

for i from 1 to nF
    selectObject: scoresTbl
    pc1_vals#[i] = Get value: i, 1
    pc2_vals#[i] = Get value: i, 2
    pc3_vals#[i] = Get value: i, 3
endfor

# ===== 4. COMPUTE FEATURE STATISTICS =====
appendInfoLine: ""
appendInfoLine: "STEP 3: Computing statistics..."

# Centroid stats
sumCent = 0
countCent = 0
for i from 1 to nF
    if centroid_vals#[i] > 0
        sumCent += centroid_vals#[i]
        countCent += 1
    endif
endfor
meanCent = if countCent > 0 then sumCent / countCent else 1000 fi

sumSqCent = 0
for i from 1 to nF
    if centroid_vals#[i] > 0
        sumSqCent += (centroid_vals#[i] - meanCent)^2
    endif
endfor
sdCent = if countCent > 1 then sqrt(sumSqCent / (countCent - 1)) else 1 fi

# HNR stats
sumHNR = 0
countHNR = 0
for i from 1 to nF
    if hnr_vals#[i] > -40
        sumHNR += hnr_vals#[i]
        countHNR += 1
    endif
endfor
meanHNR = if countHNR > 0 then sumHNR / countHNR else 0 fi

sumSqHNR = 0
for i from 1 to nF
    if hnr_vals#[i] > -40
        sumSqHNR += (hnr_vals#[i] - meanHNR)^2
    endif
endfor
sdHNR = if countHNR > 1 then sqrt(sumSqHNR / (countHNR - 1)) else 1 fi

# Pitch stats
sumPitch = 0
countPitch = 0
for i from 1 to nF
    if pitch_vals#[i] > 0
        sumPitch += pitch_vals#[i]
        countPitch += 1
    endif
endfor
meanPitch = if countPitch > 0 then sumPitch / countPitch else 200 fi

sumSqPitch = 0
for i from 1 to nF
    if pitch_vals#[i] > 0
        sumSqPitch += (pitch_vals#[i] - meanPitch)^2
    endif
endfor
sdPitch = if countPitch > 1 then sqrt(sumSqPitch / (countPitch - 1)) else 50 fi

# Intensity stats
sumInt = 0
countInt = 0
for i from 1 to nF
    if intensity_vals#[i] > -90
        sumInt += intensity_vals#[i]
        countInt += 1
    endif
endfor
meanInt = if countInt > 0 then sumInt / countInt else 60 fi

sumSqInt = 0
for i from 1 to nF
    if intensity_vals#[i] > -90
        sumSqInt += (intensity_vals#[i] - meanInt)^2
    endif
endfor
sdInt = if countInt > 1 then sqrt(sumSqInt / (countInt - 1)) else 10 fi

appendInfoLine: "  Centroid: ", fixed$(meanCent, 0), " ± ", fixed$(sdCent, 0), " Hz"
appendInfoLine: "  HNR: ", fixed$(meanHNR, 1), " ± ", fixed$(sdHNR, 1), " dB"
appendInfoLine: "  Pitch: ", fixed$(meanPitch, 0), " ± ", fixed$(sdPitch, 0), " Hz"
appendInfoLine: "  Intensity: ", fixed$(meanInt, 1), " ± ", fixed$(sdInt, 1), " dB"

# ===== 5. SELECTION =====
appendInfoLine: ""
appendInfoLine: "STEP 4: Selecting frames..."

selected_mask# = zero#(nF)
dist_vals# = zero#(nF)

# Percentile to z-score
if selection_percentile <= 10
    zThresh = 1.28
elsif selection_percentile <= 20
    zThresh = 0.84
elsif selection_percentile <= 25
    zThresh = 0.67
elsif selection_percentile <= 30
    zThresh = 0.52
elsif selection_percentile <= 40
    zThresh = 0.25
else
    zThresh = 0
endif

if selectionFeature$ = "centroid"
    for i from 1 to nF
        if centroid_vals#[i] > 0
            zScore = (centroid_vals#[i] - meanCent) / sdCent
            dist_vals#[i] = abs(zScore)
            if selectionDirection = 1
                if zScore >= zThresh
                    selected_mask#[i] = 1
                endif
            else
                if zScore <= -zThresh
                    selected_mask#[i] = 1
                endif
            endif
        endif
    endfor

elsif selectionFeature$ = "hnr"
    for i from 1 to nF
        if hnr_vals#[i] > -40
            zScore = (hnr_vals#[i] - meanHNR) / sdHNR
            dist_vals#[i] = abs(zScore)
            if selectionDirection = 1
                if zScore >= zThresh
                    selected_mask#[i] = 1
                endif
            else
                if zScore <= -zThresh
                    selected_mask#[i] = 1
                endif
            endif
        endif
    endfor

elsif selectionFeature$ = "pitch"
    for i from 1 to nF
        if pitch_vals#[i] > 0
            zScore = (pitch_vals#[i] - meanPitch) / sdPitch
            dist_vals#[i] = abs(zScore)
            if selectionDirection = 1
                if zScore >= zThresh
                    selected_mask#[i] = 1
                endif
            else
                if zScore <= -zThresh
                    selected_mask#[i] = 1
                endif
            endif
        endif
    endfor

elsif selectionFeature$ = "intensity"
    for i from 1 to nF
        if intensity_vals#[i] > -90
            zScore = (intensity_vals#[i] - meanInt) / sdInt
            dist_vals#[i] = abs(zScore)
            if selectionDirection = 1
                if zScore >= zThresh
                    selected_mask#[i] = 1
                endif
            else
                if zScore <= -zThresh
                    selected_mask#[i] = 1
                endif
            endif
        endif
    endfor

else
    # PCA mode (Custom)
    t1 = target_pc1
    t2 = target_pc2
    t3 = target_pc3
    
    for i from 1 to nF
        d = sqrt((pc1_vals#[i] - t1)^2 + (pc2_vals#[i] - t2)^2 + (pc3_vals#[i] - t3)^2)
        dist_vals#[i] = d
    endfor
    
    # Find threshold
    sumDist = 0
    for i from 1 to nF
        sumDist += dist_vals#[i]
    endfor
    meanDist = sumDist / nF
    distThresh = meanDist * (selection_percentile / 50)
    
    for i from 1 to nF
        if dist_vals#[i] < distThresh
            selected_mask#[i] = 1
        endif
    endfor
endif

# Count selected
selected_frame_count = 0
for i from 1 to nF
    if selected_mask#[i] = 1
        selected_frame_count += 1
    endif
endfor

appendInfoLine: "  Selected: ", selected_frame_count, " of ", nF, " frames (", fixed$(100 * selected_frame_count / nF, 1), "%)"

# ===== 6. BUILD OUTPUT =====
appendInfoLine: ""
appendInfoLine: "STEP 5: Building output..."

if selected_frame_count < 2
    removeObject: feat, pca, scoresTbl, workSnd
    exitScript: "Too few frames selected. Try increasing Selection percentile."
endif

chunk_count = 0
chunk_start = -1
chunk_end = -1

for i from 1 to nF
    t_s = time_vals#[i]
    t_e = t_s + dt
    
    if selected_mask#[i] = 1
        if chunk_start = -1
            chunk_start = t_s
        endif
        chunk_end = t_e
    else
        if chunk_start <> -1
            selectObject: snd
            Extract part: chunk_start, chunk_end, "Hanning", 1, "no"
            chunkID = selected("Sound")
            chunk_count += 1
            chunk_id_'chunk_count' = chunkID
            chunk_start = -1
        endif
    endif
endfor

if chunk_start <> -1
    selectObject: snd
    Extract part: chunk_start, chunk_end, "Hanning", 1, "no"
    chunkID = selected("Sound")
    chunk_count += 1
    chunk_id_'chunk_count' = chunkID
endif

appendInfoLine: "  Segments: ", chunk_count

if chunk_count > 0
    selectObject: chunk_id_1
    for i from 2 to chunk_count
        plusObject: chunk_id_'i'
    endfor
    
    Concatenate with overlap: 0.01
    Rename: sndName$ + "_" + presetName$
    finalSnd = selected("Sound")
    Scale peak: 0.99
    
    selectObject: finalSnd
    finalDur = Get total duration
    
    for i from 1 to chunk_count
        removeObject: chunk_id_'i'
    endfor
    
    appendInfoLine: "  Output: ", fixed$(finalDur, 2), " s (", fixed$(100 * finalDur / dur, 1), "%)"
else
    removeObject: feat, pca, scoresTbl, workSnd
    exitScript: "No segments created."
endif

# ===== 7. VISUALIZATION (Restored from v1.0) =====
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "STEP 6: Visualization..."
    
    Erase all
    Select outer viewport: 0, 8, 0, 8
    
    # === Title ===
    Select outer viewport: 0, 8, 0, 0.6
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##PCA Timbre Selector## | " + sndName$
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -1.0, "half", presetName$ + " | " + fixed$(100 * selected_frame_count / nF, 0) + "% selected | " + string$(chunk_count) + " segments"
    
    # === Waveforms ===
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.7, 0.65, 1.45
    selectObject: snd
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    
    Select outer viewport: 0, 8, 1.5, 2.4
    Select inner viewport: 0.6, 7.7, 1.55, 2.35
    selectObject: finalSnd
    Colour: "{0.3, 0.65, 0.4}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", presetName$
    Text bottom: "yes", "Time (s)"
    
    # === Selection Timeline ===
    Select outer viewport: 0, 8, 2.5, 3.0
    Select inner viewport: 0.6, 7.7, 2.55, 2.95
    Axes: 0, dur, 0, 1
    
    for i from 1 to nF
        t_s = time_vals#[i]
        t_e = t_s + dt
        if selected_mask#[i] = 1
            Paint rectangle: "{0.3, 0.75, 0.45}", t_s, t_e, 0, 1
        else
            Paint rectangle: "{0.88, 0.88, 0.88}", t_s, t_e, 0, 1
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Mask"
    
    # === PCA Scatter Plots ===
    minPC1 = min(pc1_vals#)
    maxPC1 = max(pc1_vals#)
    minPC2 = min(pc2_vals#)
    maxPC2 = max(pc2_vals#)
    minPC3 = min(pc3_vals#)
    maxPC3 = max(pc3_vals#)
    
    pc1Range = max(maxPC1 - minPC1, 0.1)
    pc2Range = max(maxPC2 - minPC2, 0.1)
    pc3Range = max(maxPC3 - minPC3, 0.1)
    
    # PC1 vs PC2
    Select outer viewport: 0, 2.7, 3.1, 5.0
    Select inner viewport: 0.5, 2.5, 3.3, 4.9
    
    Axes: minPC1 - pc1Range * 0.1, maxPC1 + pc1Range * 0.1, minPC2 - pc2Range * 0.1, maxPC2 + pc2Range * 0.1
    Paint rectangle: "{0.97, 0.97, 0.98}", minPC1 - pc1Range * 0.1, maxPC1 + pc1Range * 0.1, minPC2 - pc2Range * 0.1, maxPC2 + pc2Range * 0.1
    
    for i from 1 to nF
        if selected_mask#[i] = 1
            Paint circle: "{0.3, 0.7, 0.4}", pc1_vals#[i], pc2_vals#[i], pc1Range * 0.015
        else
            Paint circle: "{0.8, 0.8, 0.8}", pc1_vals#[i], pc2_vals#[i], pc1Range * 0.012
        endif
    endfor
    
    if selectionFeature$ = "PCA"
        Paint circle: "{0.9, 0.2, 0.2}", t1, t2, pc1Range * 0.04
    endif
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "PC2"
    Text bottom: "yes", "PC1"
    Text top: "no", "PC1 vs PC2"
    
    # PC1 vs PC3
    Select outer viewport: 2.7, 5.4, 3.1, 5.0
    Select inner viewport: 3.1, 5.2, 3.3, 4.9
    
    Axes: minPC1 - pc1Range * 0.1, maxPC1 + pc1Range * 0.1, minPC3 - pc3Range * 0.1, maxPC3 + pc3Range * 0.1
    Paint rectangle: "{0.97, 0.97, 0.98}", minPC1 - pc1Range * 0.1, maxPC1 + pc1Range * 0.1, minPC3 - pc3Range * 0.1, maxPC3 + pc3Range * 0.1
    
    for i from 1 to nF
        if selected_mask#[i] = 1
            Paint circle: "{0.3, 0.7, 0.4}", pc1_vals#[i], pc3_vals#[i], pc1Range * 0.015
        else
            Paint circle: "{0.8, 0.8, 0.8}", pc1_vals#[i], pc3_vals#[i], pc1Range * 0.012
        endif
    endfor
    
    if selectionFeature$ = "PCA"
        Paint circle: "{0.9, 0.2, 0.2}", t1, t3, pc1Range * 0.04
    endif
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "PC3"
    Text bottom: "yes", "PC1"
    Text top: "no", "PC1 vs PC3"
    
    # PC2 vs PC3
    Select outer viewport: 5.4, 8, 3.1, 5.0
    Select inner viewport: 5.7, 7.8, 3.3, 4.9
    
    Axes: minPC2 - pc2Range * 0.1, maxPC2 + pc2Range * 0.1, minPC3 - pc3Range * 0.1, maxPC3 + pc3Range * 0.1
    Paint rectangle: "{0.97, 0.97, 0.98}", minPC2 - pc2Range * 0.1, maxPC2 + pc2Range * 0.1, minPC3 - pc3Range * 0.1, maxPC3 + pc3Range * 0.1
    
    for i from 1 to nF
        if selected_mask#[i] = 1
            Paint circle: "{0.3, 0.7, 0.4}", pc2_vals#[i], pc3_vals#[i], pc2Range * 0.015
        else
            Paint circle: "{0.8, 0.8, 0.8}", pc2_vals#[i], pc3_vals#[i], pc2Range * 0.012
        endif
    endfor
    
    if selectionFeature$ = "PCA"
        Paint circle: "{0.9, 0.2, 0.2}", t2, t3, pc2Range * 0.04
    endif
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "PC3"
    Text bottom: "yes", "PC2"
    Text top: "no", "PC2 vs PC3"
    
    # === Eigenvector Loadings ===
    Select outer viewport: 0, 4, 5.1, 6.5
    Select inner viewport: 0.6, 3.8, 5.3, 6.4
    
    Axes: 0, 6, -1, 1
    Paint rectangle: "{0.98, 0.98, 0.98}", 0, 6, -1, 1
    
    Colour: "{0.7, 0.7, 0.7}"
    Draw line: 0, 0, 6, 0
    
    barWidth = 0.25
    colours$[1] = "{0.8, 0.4, 0.4}"
    colours$[2] = "{0.4, 0.6, 0.8}"
    colours$[3] = "{0.5, 0.8, 0.5}"
    
    for f from 1 to 5
        baseX = f - 0.3
        for pc from 1 to 3
            x1 = baseX + (pc - 1) * barWidth
            x2 = x1 + barWidth * 0.8
            val = loading[pc, f]
            Paint rectangle: colours$[pc], x1, x2, 0, val
        endfor
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 5
    
    for f from 1 to 5
        Text: f, "centre", -1.15, "top", feature$[f]
    endfor
    
    Text left: "yes", "Loading"
    Text top: "no", "PCA Loadings"
    
    # Loadings legend
    Font size: 5
    Paint rectangle: colours$[1], 0.3, 0.5, 0.8, 0.95
    Text: 0.55, "left", 0.875, "half", "PC1"
    Paint rectangle: colours$[2], 1.3, 1.5, 0.8, 0.95
    Text: 1.55, "left", 0.875, "half", "PC2"
    Paint rectangle: colours$[3], 2.3, 2.5, 0.8, 0.95
    Text: 2.55, "left", 0.875, "half", "PC3"
    
    # === Distance Over Time ===
    Select outer viewport: 4, 8, 5.1, 6.5
    Select inner viewport: 4.5, 7.8, 5.3, 6.4
    
    maxDist = max(dist_vals#)
    if maxDist < 0.1
        maxDist = 1
    endif
    
    Axes: 0, dur, 0, maxDist * 1.1
    Paint rectangle: "{0.98, 0.98, 0.98}", 0, dur, 0, maxDist * 1.1
    
    Colour: "{0.4, 0.5, 0.7}"
    for i from 2 to nF
        Draw line: time_vals#[i-1], dist_vals#[i-1], time_vals#[i], dist_vals#[i]
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    if selectionFeature$ = "PCA"
        Text left: "yes", "Distance"
    else
        Text left: "yes", "|z-score|"
    endif
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Selection Score"
    
    # === Legend ===
    Select outer viewport: 0, 8, 6.6, 7.0
    Axes: 0, 1, 0, 1
    Font size: 7
    
    Paint circle: "{0.3, 0.7, 0.4}", 0.1, 0.5, 0.015
    Text: 0.13, "left", 0.5, "half", "Selected"
    
    Paint circle: "{0.8, 0.8, 0.8}", 0.35, 0.5, 0.012
    Text: 0.38, "left", 0.5, "half", "Rejected"
    
    if selectionFeature$ = "PCA"
        Paint circle: "{0.9, 0.2, 0.2}", 0.58, 0.5, 0.02
        Text: 0.61, "left", 0.5, "half", "Target"
    endif
    
    Colour: "{0.5, 0.5, 0.5}"
    Text: 0.85, "centre", 0.5, "half", "Var: " + fixed$(var1*100,0) + "/" + fixed$(var2*100,0) + "/" + fixed$(var3*100,0) + "%"
    
    Font size: 10
    Colour: "Black"
endif

# ===== CLEANUP =====
removeObject: feat, pca, scoresTbl, workSnd

# ===== OUTPUT =====
selectObject: snd
plusObject: finalSnd

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=============================================="

if play_result
    selectObject: finalSnd
    Play
endif

selectObject: finalSnd
