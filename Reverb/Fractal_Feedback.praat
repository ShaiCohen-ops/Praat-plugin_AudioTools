# ============================================================
# Praat AudioTools - Fractal_Feedback.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Fractal Feedback - multi-scale self-similar delay effect.
#   Applies delays at progressively finer temporal divisions
#   (2, 4, 8, 16... segments), creating fractal-like echo
#   patterns. Each layer adds finer temporal detail while
#   feedback decreases with depth. Segment boundaries are
#   smoothed with sinusoidal windowing.
#
# Changelog v0.2:
#   - Fixed delay formula (was looking forward, not backward)
#   - Added bounds checking
#   - Fixed selection and formula syntax
#   - Added presets
#   - Added wet/dry mix control
#   - Added visualization
#
# Changelog v0.3:
#   - FIX: only the left channel was processed (Formula part was channel 1
#     only); now processes all channels (self[col-delay] reads each channel's
#     own samples).
#   - Fixed visualization: title and parameter line spilled off the left edge
#     (centred against a stale/seconds world window); now pinned to a 0..1 axis.
#   - Wet/dry references the dry signal per-channel (object[id, row, col]);
#     removed unused per-segment arrays.
# ============================================================

form Fractal Feedback
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Subtle Fractal
        option Medium Fractal
        option Deep Fractal
        option Extreme Fractal
    
    comment === Fractal Parameters ===
    natural Depth_layers 3
    comment (number of recursive divisions: 2^n segments)
    
    comment === Delay Range ===
    positive Delay_min_ms 20
    positive Delay_max_ms 150
    
    comment === Feedback ===
    positive Feedback_base 0.5
    comment (decreases by 1/layer at each depth)
    
    comment === Mix ===
    real Wet_dry_percent 60
    comment (0 = dry only, 100 = wet only)
    
    comment === Output ===
    positive Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
originalDur = Get total duration
sr = Get sampling frequency
nSamples = Get number of samples
numChannels = Get number of channels

# === Apply Presets ===
if preset = 2
    # Subtle Fractal
    depth_layers = 2
    delay_min_ms = 15
    delay_max_ms = 80
    feedback_base = 0.4
    presetName$ = "Subtle"
elsif preset = 3
    # Medium Fractal
    depth_layers = 3
    delay_min_ms = 20
    delay_max_ms = 150
    feedback_base = 0.5
    presetName$ = "Medium"
elsif preset = 4
    # Deep Fractal
    depth_layers = 4
    delay_min_ms = 25
    delay_max_ms = 200
    feedback_base = 0.55
    presetName$ = "Deep"
elsif preset = 5
    # Extreme Fractal
    depth_layers = 5
    delay_min_ms = 30
    delay_max_ms = 300
    feedback_base = 0.6
    presetName$ = "Extreme"
else
    presetName$ = "Custom"
endif

# Clamp wet/dry
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif

wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

# Convert ms to samples
delay_min_samp = round(delay_min_ms / 1000 * sr)
delay_max_samp = round(delay_max_ms / 1000 * sr)

# Calculate total segments for info
totalSegments = 0
for layer from 1 to depth_layers
    totalSegments = totalSegments + 2^layer
endfor

# === Info ===
writeInfoLine: "=== Fractal Feedback ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Depth layers: ", depth_layers
appendInfoLine: "Total segments: ", totalSegments
appendInfoLine: "Delay range: ", delay_min_ms, "-", delay_max_ms, " ms"
appendInfoLine: "Feedback base: ", feedback_base
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
appendInfoLine: ""

# Store delay info for visualization
segIndex = 0
for layer from 1 to depth_layers
    divisions = 2 ^ layer
    for seg from 1 to divisions
        segIndex = segIndex + 1
        segDelay[segIndex] = round(randomUniform(delay_min_samp, delay_max_samp))
    endfor
endfor

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Processing..."

# Create wet signal (copy of original)
selectObject: original
Copy: "wet_signal"
wetSignal = selected("Sound")

# Process each layer
segIndex = 0

for layer from 1 to depth_layers
    divisions = 2 ^ layer
    segment_samples = floor(nSamples / divisions)
    feedback = feedback_base / layer
    
    appendInfoLine: "  Layer ", layer, ": ", divisions, " segments, feedback=", fixed$(feedback, 3)
    
    for seg from 1 to divisions
        segIndex = segIndex + 1
        
        # Segment boundaries (in samples)
        segStart = (seg - 1) * segment_samples + 1
        segEnd = seg * segment_samples
        if segEnd > nSamples
            segEnd = nSamples
        endif
        
        # Convert to time
        tStart = (segStart - 1) / sr
        tEnd = segEnd / sr
        
        # Get delay for this segment
        delay_samp = segDelay[segIndex]
        
        # Build formula strings
        delay_str$ = string$(delay_samp)
        feedback_str$ = string$(feedback)
        segSize_str$ = string$(segment_samples)
        segStart_str$ = string$(segStart)
        
        # Apply delayed feedback with sinusoidal window
        # Window smooths segment boundaries
        selectObject: wetSignal
        Formula (part): tStart, tEnd, 1, numChannels, "if col > " + delay_str$ + " then self + " + feedback_str$ + " * self[col - " + delay_str$ + "] * sin(pi * (col - " + segStart_str$ + ") / " + segSize_str$ + ") else self fi"
    endfor
endfor

# Apply wet/dry mix
if dry_level > 0
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    orig_str$ = string$(original)
    
    selectObject: wetSignal
    Formula: "self * " + wet_str$ + " + object[" + orig_str$ + ", row, col] * " + dry_str$
endif

selectObject: wetSignal
Scale peak: scale_peak
Rename: originalName$ + "_fractal_" + presetName$
result = selected("Sound")

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Fractal Feedback: " + originalName$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.6, 0.7, 1.3
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Dry"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.5, 2.3
    Select inner viewport: 0.6, 7.6, 1.6, 2.2
    selectObject: result
    Colour: "{0.5, 0.6, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Fractal " + fixed$(wet_dry_percent, 0) + "%"
    Text bottom: "yes", "Time (s)"
    
    # Fractal structure diagram
    Select outer viewport: 0, 8, 2.5, 4.2
    Select inner viewport: 0.6, 7.6, 2.6, 4.1
    
    Axes: 0, originalDur, 0, depth_layers + 0.5
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, originalDur, 0, depth_layers + 0.5
    
    # Draw fractal layers
    for layer from 1 to depth_layers
        divisions = 2 ^ layer
        y = depth_layers - layer + 1
        
        # Color based on layer
        r = 0.4 + layer * 0.1
        g = 0.5
        b = 0.7 - layer * 0.08
        
        for seg from 1 to divisions
            segStart = (seg - 1) / divisions * originalDur
            segEnd = seg / divisions * originalDur
            
            # Draw segment box
            Colour: "{" + fixed$(r, 2) + ", " + fixed$(g, 2) + ", " + fixed$(b, 2) + "}"
            Paint rectangle: "{" + fixed$(r, 2) + ", " + fixed$(g, 2) + ", " + fixed$(b, 2) + "}", segStart + 0.002, segEnd - 0.002, y - 0.35, y + 0.35
            
            # Draw segment boundary
            Colour: "White"
            Draw line: segEnd, y - 0.35, segEnd, y + 0.35
        endfor
        
        # Layer label
        Colour: "Black"
        Font size: 5
        Text: -0.02 * originalDur, "right", y, "half", "L" + string$(layer)
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Layers"
    Text bottom: "yes", "Time (s)"
    
    # Legend
    Font size: 5
    Colour: "{0.4, 0.4, 0.4}"
    Text: originalDur * 0.5, "centre", 0.15, "half", "Each segment: random delay (" + string$(delay_min_ms) + "-" + string$(delay_max_ms) + "ms) × feedback"
    
    # Parameters
    Select outer viewport: 0, 8, 4.3, 4.7
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Layers: " + string$(depth_layers) + " | Segments: " + string$(totalSegments) + " | Feedback base: " + fixed$(feedback_base, 2) + " (÷layer)"
    
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