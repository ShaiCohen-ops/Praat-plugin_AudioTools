# ============================================================
# Praat AudioTools - Stochastic_Time_Folding.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Stochastic Time Folding - creates blurry, smeared textures
#   through probabilistic time-domain averaging. Each iteration
#   randomly decides whether to average samples from past,
#   present, and future, creating evolving diffuse sounds.
#
# Changelog v0.2:
#   - Modern syntax
#   - Added bounds checking
#   - Fixed Formula interpolation
#   - Added visualization
# ============================================================

form Stochastic Time Folding
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Default (balanced)
        option Gentle Folds
        option Aggressive Folds
        option Micro Glitch
        option Custom
    
    comment === Folding ===
    natural Fold_iterations 6
    positive Initial_threshold 0.5
    
    comment === Threshold Evolution ===
    positive Threshold_var_min 0.2
    positive Threshold_var_max 0.2
    positive Threshold_limit_min 0.1
    positive Threshold_limit_max 0.9
    
    comment === Fold Distance ===
    positive Fold_distance_min 3
    positive Fold_distance_max 12
    
    comment === Amplitude Variation ===
    positive Amplitude_min 0.7
    positive Amplitude_max 1.2
    
    comment === Averaging ===
    positive Fold_average_divisor 3
    positive Fold_backward_divisor 2
    
    comment === Output ===
    positive Scale_peak 0.96
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 1
    # Default (balanced)
    fold_iterations = 6
    initial_threshold = 0.5
    threshold_var_min = 0.2
    threshold_var_max = 0.2
    threshold_limit_min = 0.1
    threshold_limit_max = 0.9
    fold_distance_min = 3
    fold_distance_max = 12
    amplitude_min = 0.7
    amplitude_max = 1.2
    fold_average_divisor = 3
    fold_backward_divisor = 2
elsif preset = 2
    # Gentle Folds
    fold_iterations = 4
    initial_threshold = 0.4
    threshold_var_min = 0.10
    threshold_var_max = 0.15
    threshold_limit_min = 0.15
    threshold_limit_max = 0.85
    fold_distance_min = 5
    fold_distance_max = 15
    amplitude_min = 0.9
    amplitude_max = 1.1
    fold_average_divisor = 3
    fold_backward_divisor = 2
elsif preset = 3
    # Aggressive Folds
    fold_iterations = 9
    initial_threshold = 0.6
    threshold_var_min = 0.25
    threshold_var_max = 0.35
    threshold_limit_min = 0.05
    threshold_limit_max = 0.95
    fold_distance_min = 2
    fold_distance_max = 10
    amplitude_min = 0.5
    amplitude_max = 1.5
    fold_average_divisor = 2
    fold_backward_divisor = 2
elsif preset = 4
    # Micro Glitch
    fold_iterations = 12
    initial_threshold = 0.55
    threshold_var_min = 0.15
    threshold_var_max = 0.25
    threshold_limit_min = 0.10
    threshold_limit_max = 0.90
    fold_distance_min = 2
    fold_distance_max = 6
    amplitude_min = 0.6
    amplitude_max = 1.4
    fold_average_divisor = 2
    fold_backward_divisor = 3
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
sampleRate = Get sampling frequency
duration = Get total duration
totalSamples = Get number of samples

# === Get Preset Name ===
if preset = 1
    presetName$ = "Default"
elsif preset = 2
    presetName$ = "Gentle"
elsif preset = 3
    presetName$ = "Aggressive"
elsif preset = 4
    presetName$ = "Micro Glitch"
else
    presetName$ = "Custom"
endif

# === Info ===
writeInfoLine: "=== Stochastic Time Folding ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Iterations: ", fold_iterations
appendInfoLine: "Initial threshold: ", initial_threshold
appendInfoLine: "Fold distance range: ", fold_distance_min, "-", fold_distance_max
appendInfoLine: ""

# === Copy for Processing ===
selectObject: original
Copy: original_name$ + "_folded"
result = selected("Sound")

# === Store Threshold Evolution for Visualization ===
thresholds# = zero#(fold_iterations)
foldDistances# = zero#(fold_iterations)

# === Initialize Adaptive Threshold ===
adaptiveThreshold = initial_threshold

# === Main Folding Processing Loop ===
appendInfoLine: "Processing folds..."

for fold from 1 to fold_iterations
    selectObject: result
    
    # Evolve threshold (except first iteration)
    if fold > 1
        thresholdChange = randomUniform(threshold_var_min, threshold_var_max)
        # Randomly add or subtract
        if randomUniform(0, 1) > 0.5
            adaptiveThreshold = adaptiveThreshold + thresholdChange
        else
            adaptiveThreshold = adaptiveThreshold - thresholdChange
        endif
        # Clamp to limits
        adaptiveThreshold = max(threshold_limit_min, min(threshold_limit_max, adaptiveThreshold))
    endif
    
    thresholds#[fold] = adaptiveThreshold
    
    # Random fold distance for this iteration
    foldDivisor = randomUniform(fold_distance_min, fold_distance_max)
    foldDistance = round(totalSamples / foldDivisor)
    backwardDistance = round(foldDistance / fold_backward_divisor)
    
    foldDistances#[fold] = foldDistance / sampleRate * 1000
    
    # Random probability for this iteration
    probMask = randomUniform(0, 1)
    
    # Amplitude variation range
    ampMin = amplitude_min
    ampMax = amplitude_max
    avgDiv = fold_average_divisor
    
    appendInfoLine: "  Fold ", fold, ": thresh=", fixed$(adaptiveThreshold, 2), " dist=", foldDistance, " prob=", fixed$(probMask, 2)
    
    # Conditional time-folding with bounds checking
    Formula: ~ if probMask < adaptiveThreshold 
        ... then (if col + foldDistance <= ncol and col - backwardDistance >= 1 
            ... then (self + self[col + foldDistance] + self[col - backwardDistance]) / avgDiv 
            ... else self fi) 
        ... else self * randomUniform(ampMin, ampMax) fi
endfor

# === Scale Peak ===
selectObject: result
Scale peak: scale_peak

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Stochastic Time Folding: " + original_name$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 2.0
    Select inner viewport: 0.6, 7.6, 0.7, 1.9
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 2.1, 3.5
    Select inner viewport: 0.6, 7.6, 2.2, 3.4
    selectObject: result
    Colour: "{0.6, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Folded"
    Text bottom: "yes", "Time (s)"
    
    # Threshold evolution
    Select outer viewport: 0, 4, 3.7, 5.3
    Select inner viewport: 0.6, 3.8, 3.9, 5.2
    
    Axes: 0, fold_iterations + 1, 0, 1.1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, fold_iterations + 1, 0, 1.1
    
    # Draw threshold limits
    Colour: "{0.8, 0.8, 0.8}"
    Dotted line
    Draw line: 0, threshold_limit_min, fold_iterations + 1, threshold_limit_min
    Draw line: 0, threshold_limit_max, fold_iterations + 1, threshold_limit_max
    Solid line
    
    # Draw threshold evolution
    Colour: "{0.4, 0.6, 0.8}"
    Line width: 2
    for f from 1 to fold_iterations
        Paint circle (mm): "{0.4, 0.6, 0.8}", f, thresholds#[f], 1.5
        if f > 1
            Draw line: f - 1, thresholds#[f - 1], f, thresholds#[f]
        endif
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Threshold"
    Text bottom: "yes", "Iteration"
    
    # Fold distances
    Select outer viewport: 4, 8, 3.7, 5.3
    Select inner viewport: 4.4, 7.6, 3.9, 5.2
    
    # Find max distance for scaling
    maxDist = foldDistances#[1]
    for f from 2 to fold_iterations
        if foldDistances#[f] > maxDist
            maxDist = foldDistances#[f]
        endif
    endfor
    
    Axes: 0, fold_iterations + 1, 0, maxDist * 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, fold_iterations + 1, 0, maxDist * 1.2
    
    # Draw fold distance bars
    for f from 1 to fold_iterations
        barColor$ = "{0.7, 0.5, 0.5}"
        Paint rectangle: barColor$, f - 0.35, f + 0.35, 0, foldDistances#[f]
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Dist (ms)"
    Text bottom: "yes", "Iteration"
    
    # Legend
    Select outer viewport: 0, 8, 5.4, 5.7
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Iterations: " + string$(fold_iterations) + " | Threshold: " + fixed$(threshold_limit_min, 2) + "-" + fixed$(threshold_limit_max, 2) + " | Avg divisor: " + string$(fold_average_divisor)
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result
finalDuration = Get total duration

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDuration, 2), " s"

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result