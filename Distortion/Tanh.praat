# ============================================================
# Praat AudioTools - Tanh_Soft_Clip.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Tanh Soft Clipping - classic tube/tape-style saturation using
#   hyperbolic tangent function. Smoothly compresses peaks without
#   harsh hard clipping, adding warm harmonics. Drive controls
#   saturation intensity from subtle warmth to heavy overdrive.
#
# Changelog v0.3:
#   - Added "Apply scale peak" toggle (default ON = identical to v0.2).
#     With Scale peak always on, output_level was a uniform post-gain that
#     normalization cancelled out (audibly inert). Turn the toggle OFF to
#     let drive + output_level set the actual level.
#   - Viz: set world axes explicitly before the title text (#32 standard)
#
# Changelog v0.2:
#   - Fixed input check
#   - Fixed formula syntax
#   - Added visualization
#   - Added info output
# ============================================================

form Tanh Soft Clipping
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Default (balanced)
        option Warm Saturation
        option Heavy Overdrive
        option Tape Style
        option Subtle Warmth
        option Custom (use settings below)
    
    comment === Distortion Parameters ===
    positive Drive_amount 8
    comment (2=subtle, 8=moderate, 15=heavy)
    positive Output_level 0.7
    
    comment === Output ===
    boolean Apply_scale_peak 1
    comment (OFF = let drive/output_level set the level)
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
duration = Get total duration
sr = Get sampling frequency

# === Apply Presets ===
if preset = 1
    # Default (balanced)
    drive_amount = 8
    output_level = 0.7
    presetName$ = "Default"
elsif preset = 2
    # Warm Saturation
    drive_amount = 4
    output_level = 0.8
    presetName$ = "WarmSat"
elsif preset = 3
    # Heavy Overdrive
    drive_amount = 12
    output_level = 0.6
    presetName$ = "HeavyOD"
elsif preset = 4
    # Tape Style
    drive_amount = 6
    output_level = 0.75
    presetName$ = "Tape"
elsif preset = 5
    # Subtle Warmth
    drive_amount = 2.5
    output_level = 0.85
    presetName$ = "Subtle"
else
    presetName$ = "Custom"
endif

# === Info ===
writeInfoLine: "=== Tanh Soft Clipping ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Drive: ", drive_amount
appendInfoLine: "Output level: ", output_level
if apply_scale_peak
    appendInfoLine: "Scale peak: ", scale_peak, " (output_level normalized away)"
else
    appendInfoLine: "Scale peak: OFF (output_level active)"
endif
appendInfoLine: ""
appendInfoLine: "Formula: tanh(x × drive) × output_level"
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Applying soft clipping..."

selectObject: original
Copy: originalName$ + "_tanh_" + presetName$
result = selected("Sound")

# Apply soft clipping: tanh(x * drive) * output_level
drive_str$ = string$(drive_amount)
level_str$ = string$(output_level)

Formula: "tanh(self * " + drive_str$ + ") * " + level_str$

# Scale to peak (optional)
if apply_scale_peak
    Scale peak: scale_peak
endif

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
    Text: 0.5, "centre", 0.5, "half", "Tanh Soft Clipping: " + originalName$ + " (" + presetName$ + ")"
    
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
    Colour: "{0.7, 0.6, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Soft Clipped"
    Text bottom: "yes", "Time (s)"
    
    # Zoomed comparison
    zoomDur = min(0.02, duration)
    
    Select outer viewport: 0, 4, 2.7, 3.8
    Select inner viewport: 0.6, 3.8, 2.8, 3.7
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, zoomDur, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Orig (zoom)"
    
    Select outer viewport: 4, 8, 2.7, 3.8
    Select inner viewport: 4.4, 7.6, 2.8, 3.7
    selectObject: result
    Colour: "{0.7, 0.6, 0.5}"
    Draw: 0, zoomDur, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Clipped (zoom)"
    Text bottom: "yes", "Time (s)"
    
    # Transfer function
    Select outer viewport: 0, 4, 4.0, 5.4
    Select inner viewport: 0.6, 3.8, 4.1, 5.3
    
    Axes: -1.2, 1.2, -1.2, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", -1.2, 1.2, -1.2, 1.2
    
    # Grid
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: -1.2, 0, 1.2, 0
    Draw line: 0, -1.2, 0, 1.2
    
    # Linear reference (dotted)
    Dotted line
    Draw line: -1, -1, 1, 1
    Solid line
    
    # Draw tanh transfer function
    Colour: "{0.7, 0.6, 0.5}"
    Line width: 2
    nPoints = 200
    for p from 2 to nPoints
        x1 = -1.0 + (p - 2) / nPoints * 2.0
        x2 = -1.0 + (p - 1) / nPoints * 2.0
        
        y1 = tanh(x1 * drive_amount) * output_level
        y2 = tanh(x2 * drive_amount) * output_level
        
        # Clamp for display
        if y1 > 1.1
            y1 = 1.1
        elsif y1 < -1.1
            y1 = -1.1
        endif
        if y2 > 1.1
            y2 = 1.1
        elsif y2 < -1.1
            y2 = -1.1
        endif
        
        Draw line: x1, y1, x2, y2
    endfor
    Line width: 1
    
    # Saturation region indicator
    Colour: "{0.8, 0.7, 0.6}"
    satPoint = 0.5 / drive_amount
    if satPoint < 1
        Dotted line
        Draw line: satPoint, -1.2, satPoint, 1.2
        Draw line: -satPoint, -1.2, -satPoint, 1.2
        Solid line
    endif
    
    Colour: "Black"
    Draw inner box
    Font size: 5
    Text left: "yes", "Output"
    Text bottom: "yes", "Input"
    Text: 0, "centre", 1.35, "half", "y = tanh(x × " + fixed$(drive_amount, 0) + ")"
    
    # Drive comparison
    Select outer viewport: 4, 8, 4.0, 5.4
    Select inner viewport: 4.4, 7.6, 4.1, 5.3
    
    Axes: -1.2, 1.2, -1.2, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", -1.2, 1.2, -1.2, 1.2
    
    # Grid
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: -1.2, 0, 1.2, 0
    Draw line: 0, -1.2, 0, 1.2
    Dotted line
    Draw line: -1, -1, 1, 1
    Solid line
    
    # Draw different drive levels for comparison
    Line width: 1.5
    
    # Low drive (2)
    Colour: "{0.6, 0.8, 0.6}"
    for p from 2 to nPoints
        x1 = -1.0 + (p - 2) / nPoints * 2.0
        x2 = -1.0 + (p - 1) / nPoints * 2.0
        y1 = tanh(x1 * 2)
        y2 = tanh(x2 * 2)
        Draw line: x1, y1, x2, y2
    endfor
    
    # Medium drive (8)
    Colour: "{0.6, 0.6, 0.8}"
    for p from 2 to nPoints
        x1 = -1.0 + (p - 2) / nPoints * 2.0
        x2 = -1.0 + (p - 1) / nPoints * 2.0
        y1 = tanh(x1 * 8)
        y2 = tanh(x2 * 8)
        Draw line: x1, y1, x2, y2
    endfor
    
    # High drive (15)
    Colour: "{0.8, 0.6, 0.6}"
    for p from 2 to nPoints
        x1 = -1.0 + (p - 2) / nPoints * 2.0
        x2 = -1.0 + (p - 1) / nPoints * 2.0
        y1 = tanh(x1 * 15)
        y2 = tanh(x2 * 15)
        Draw line: x1, y1, x2, y2
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 5
    Text left: "yes", "Output"
    Text bottom: "yes", "Input"
    Text: 0, "centre", 1.35, "half", "Drive Comparison"
    
    # Legend
    Font size: 4
    Colour: "{0.6, 0.8, 0.6}"
    Text: -1.0, "left", -0.9, "half", "Drive 2"
    Colour: "{0.6, 0.6, 0.8}"
    Text: -1.0, "left", -1.05, "half", "Drive 8"
    Colour: "{0.8, 0.6, 0.6}"
    Text: -1.0, "left", -1.2, "half", "Drive 15"
    
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