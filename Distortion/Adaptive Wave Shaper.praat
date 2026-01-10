# ============================================================
# Praat AudioTools - Adaptive_Wave_Shaper.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Adaptive Wave Shaper - analyzes voice quality metrics
#   (jitter and shimmer) from the input audio and uses them
#   to control waveshaping parameters. Rougher/unstable audio
#   gets more aggressive processing. Creates content-aware
#   distortion that responds to the character of the sound.
#
# Changelog v0.2:
#   - Actually analyzes jitter/shimmer from audio!
#   - Fixed input check and selection syntax
#   - Added visualization
#   - Added transfer function display
# ============================================================

form Adaptive Wave Shaper
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Default
        option Gentle Saturation
        option Aggressive Drive
        option Fold Emphasis
        option Maximum Destruction
    
    comment === Base Parameters ===
    positive Base_drive 2.0
    positive Jitter_sensitivity 1.5
    comment (how much jitter affects drive)
    positive Shimmer_sensitivity 1.2
    comment (how much shimmer affects folding)
    
    comment === Analysis ===
    positive Min_pitch_Hz 75
    positive Max_pitch_Hz 600
    
    comment === Output ===
    boolean Normalize 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
duration = Get total duration
sr = Get sampling frequency

# === Apply Presets ===
if preset = 1
    presetName$ = "Default"
    base_drive = 2.0
    jitter_sensitivity = 1.5
    shimmer_sensitivity = 1.2
elsif preset = 2
    presetName$ = "Gentle"
    base_drive = 1.2
    jitter_sensitivity = 1.0
    shimmer_sensitivity = 0.8
elsif preset = 3
    presetName$ = "Aggressive"
    base_drive = 4.0
    jitter_sensitivity = 2.0
    shimmer_sensitivity = 1.8
elsif preset = 4
    presetName$ = "FoldEmphasis"
    base_drive = 2.5
    jitter_sensitivity = 1.2
    shimmer_sensitivity = 2.5
elsif preset = 5
    presetName$ = "Maximum"
    base_drive = 5.0
    jitter_sensitivity = 3.0
    shimmer_sensitivity = 3.0
endif

# === Info ===
writeInfoLine: "=== Adaptive Wave Shaper ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""

# ============================================================
# ANALYZE JITTER AND SHIMMER
# ============================================================

appendInfoLine: "Analyzing voice quality metrics..."

selectObject: original

# Convert to mono for analysis
mono = Convert to mono

# Create pitch object for periodicity analysis
selectObject: mono
To Pitch: 0.0, min_pitch_Hz, max_pitch_Hz
pitch = selected("Pitch")

# Create PointProcess (pulse train) from pitch
selectObject: mono
plusObject: pitch
To PointProcess (cc)
pp = selected("PointProcess")

# Analyze jitter (pitch period variation)
selectObject: pp
jitter_local = Get jitter (local): 0, 0, 0.0001, 0.02, 1.3
if jitter_local = undefined
    jitter_local = 0.5
endif
jitter_percent = jitter_local * 100

# Analyze shimmer (amplitude variation)
selectObject: mono
plusObject: pp
shimmer_local = Get shimmer (local): 0, 0, 0.0001, 0.02, 1.3, 1.6
if shimmer_local = undefined
    shimmer_local = 0.03
endif
shimmer_percent = shimmer_local * 100

appendInfoLine: "Jitter (local): ", fixed$(jitter_percent, 2), "%"
appendInfoLine: "Shimmer (local): ", fixed$(shimmer_percent, 2), "%"
appendInfoLine: ""

# Cleanup analysis objects
removeObject: mono, pitch, pp

# ============================================================
# CALCULATE ADAPTIVE PARAMETERS
# ============================================================

# Drive increases with jitter (pitch instability → more drive)
adaptive_drive = base_drive * (1 + (jitter_percent * jitter_sensitivity / 100))

# Fold count increases with shimmer (amplitude instability → more folds)
adaptive_fold = 1 + round(shimmer_percent * shimmer_sensitivity / 20)

# Limit parameters to safe ranges
if adaptive_drive < 0.5
    adaptive_drive = 0.5
elsif adaptive_drive > 8.0
    adaptive_drive = 8.0
endif

if adaptive_fold < 1
    adaptive_fold = 1
elsif adaptive_fold > 8
    adaptive_fold = 8
endif

appendInfoLine: "Adaptive drive: ", fixed$(adaptive_drive, 2)
appendInfoLine: "Adaptive folds: ", adaptive_fold
appendInfoLine: ""

# ============================================================
# APPLY WAVE SHAPING
# ============================================================

appendInfoLine: "Applying adaptive wave shaping..."

selectObject: original
Copy: original_name$ + "_adaptive_" + presetName$
result = selected("Sound")

# 1. Apply drive
Formula: ~ self * adaptive_drive

# 2. Apply wave folding based on shimmer
fold_threshold = 0.6
for i from 1 to adaptive_fold
    # Fold positive peaks
    Formula: ~ if self > fold_threshold then fold_threshold - (self - fold_threshold) else self fi
    # Fold negative peaks
    Formula: ~ if self < -fold_threshold then -fold_threshold - (self + fold_threshold) else self fi
endfor

# 3. Add wave shaping character (soft saturation blend)
Formula: ~ sin(self * 2) * 0.3 + self * 0.7

# 4. Normalize if requested
if normalize
    Scale peak: 0.9
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Adaptive Wave Shaper: " + original_name$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.6, 0.7, 1.4
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.6, 2.5
    Select inner viewport: 0.6, 7.6, 1.7, 2.4
    selectObject: result
    Colour: "{0.7, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Shaped"
    Text bottom: "yes", "Time (s)"
    
    # Transfer function (wave folding illustration)
    Select outer viewport: 0, 4, 2.7, 4.2
    Select inner viewport: 0.6, 3.8, 2.8, 4.1
    
    Axes: -1.5, 1.5, -1.5, 1.5
    Paint rectangle: "{0.95, 0.95, 0.95}", -1.5, 1.5, -1.5, 1.5
    
    # Grid
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: -1.5, 0, 1.5, 0
    Draw line: 0, -1.5, 0, 1.5
    Dotted line
    Draw line: -1.5, -1.5, 1.5, 1.5
    Solid line
    
    # Draw transfer function with folding
    Colour: "{0.7, 0.5, 0.5}"
    Line width: 2
    nPoints = 200
    for p from 2 to nPoints
        x1 = -1.2 + (p - 2) / nPoints * 2.4
        x2 = -1.2 + (p - 1) / nPoints * 2.4
        
        # Apply drive
        y1 = x1 * adaptive_drive
        y2 = x2 * adaptive_drive
        
        # Apply folding
        for f from 1 to adaptive_fold
            if y1 > fold_threshold
                y1 = fold_threshold - (y1 - fold_threshold)
            endif
            if y1 < -fold_threshold
                y1 = -fold_threshold - (y1 + fold_threshold)
            endif
            if y2 > fold_threshold
                y2 = fold_threshold - (y2 - fold_threshold)
            endif
            if y2 < -fold_threshold
                y2 = -fold_threshold - (y2 + fold_threshold)
            endif
        endfor
        
        # Apply sin shaping
        y1 = sin(y1 * 2) * 0.3 + y1 * 0.7
        y2 = sin(y2 * 2) * 0.3 + y2 * 0.7
        
        # Clamp for display
        if y1 > 1.4
            y1 = 1.4
        elsif y1 < -1.4
            y1 = -1.4
        endif
        if y2 > 1.4
            y2 = 1.4
        elsif y2 < -1.4
            y2 = -1.4
        endif
        
        Draw line: x1, y1, x2, y2
    endfor
    Line width: 1
    
    # Fold threshold lines
    Colour: "{0.5, 0.7, 0.5}"
    Dotted line
    Draw line: -1.5, fold_threshold, 1.5, fold_threshold
    Draw line: -1.5, -fold_threshold, 1.5, -fold_threshold
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Output"
    Text bottom: "yes", "Input"
    Text: 0, "centre", 1.6, "half", "Transfer Function"
    
    # Analysis results
    Select outer viewport: 4, 8, 2.7, 4.2
    Select inner viewport: 4.4, 7.6, 2.8, 4.1
    
    Axes: 0, 4, 0, 6
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 4, 0, 6
    
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    
    # Analyzed values
    Text: 0.2, "left", 5.5, "half", "Analyzed from audio:"
    Colour: "{0.5, 0.5, 0.7}"
    Text: 0.4, "left", 4.8, "half", "Jitter: " + fixed$(jitter_percent, 2) + "%"
    Text: 0.4, "left", 4.1, "half", "Shimmer: " + fixed$(shimmer_percent, 2) + "%"
    
    # Computed parameters
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.2, "left", 3.2, "half", "Computed parameters:"
    Colour: "{0.7, 0.5, 0.5}"
    Text: 0.4, "left", 2.5, "half", "Drive: " + fixed$(adaptive_drive, 2)
    Text: 0.4, "left", 1.8, "half", "Folds: " + string$(adaptive_fold)
    
    # Sensitivity settings
    Colour: "{0.5, 0.5, 0.5}"
    Font size: 5
    Text: 0.2, "left", 0.8, "half", "Jitter sens: " + fixed$(jitter_sensitivity, 1) + " | Shimmer sens: " + fixed$(shimmer_sensitivity, 1)
    
    Colour: "Black"
    Draw inner box
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result