# ============================================================
# Praat AudioTools - Chaos_Distortion.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Chaos Distortion - combines multiple lo-fi/distortion effects:
#   wave folding (harmonic complexity), bit crushing (quantization),
#   sample rate reduction (aliasing), and optional noise. Creates
#   everything from gentle grit to extreme lo-fi destruction.
#
# Changelog v0.2:
#   - Fixed resampling bug (orphan objects)
#   - Fixed input check and selection syntax
#   - Added visualization
#   - Added info output
# ============================================================

form Chaos Distortion
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Default (balanced)
        option Gentle Grit
        option Heavy Crush
        option Lo-Fi Glitch
        option Clean Boost
        option Custom (use settings below)
    
    comment === Drive & Folding ===
    positive Drive 3.0
    natural Fold_count 3
    comment (0 = no folding, higher = more complex)
    
    comment === Bit Crushing ===
    natural Bit_crush 6
    comment (16 = CD quality, 4 = extreme)
    
    comment === Sample Rate ===
    positive Sample_rate_percent 30
    comment (100 = original, lower = more aliasing)
    
    comment === Extras ===
    boolean Add_noise 1
    real Noise_amount 0.03
    
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
    # Default (balanced)
    drive = 3.0
    fold_count = 3
    bit_crush = 6
    sample_rate_percent = 30
    add_noise = 1
    noise_amount = 0.03
    presetName$ = "Default"
elsif preset = 2
    # Gentle Grit
    drive = 1.6
    fold_count = 1
    bit_crush = 8
    sample_rate_percent = 85
    add_noise = 0
    noise_amount = 0
    presetName$ = "GentleGrit"
elsif preset = 3
    # Heavy Crush
    drive = 4.5
    fold_count = 5
    bit_crush = 4
    sample_rate_percent = 40
    add_noise = 1
    noise_amount = 0.05
    presetName$ = "HeavyCrush"
elsif preset = 4
    # Lo-Fi Glitch
    drive = 2.2
    fold_count = 2
    bit_crush = 3
    sample_rate_percent = 20
    add_noise = 1
    noise_amount = 0.04
    presetName$ = "LoFiGlitch"
elsif preset = 5
    # Clean Boost
    drive = 1.25
    fold_count = 0
    bit_crush = 12
    sample_rate_percent = 100
    add_noise = 0
    noise_amount = 0
    presetName$ = "CleanBoost"
else
    presetName$ = "Custom"
endif

# === Info ===
writeInfoLine: "=== Chaos Distortion ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Drive: ", drive
appendInfoLine: "Fold count: ", fold_count
appendInfoLine: "Bit depth: ", bit_crush, " bits (", 2^bit_crush, " levels)"
appendInfoLine: "Sample rate: ", sample_rate_percent, "% (", round(sr * sample_rate_percent / 100), " Hz)"
appendInfoLine: "Noise: ", if add_noise then "yes (" + fixed$(noise_amount, 2) + ")" else "no" fi
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Processing..."

selectObject: original
Copy: original_name$ + "_chaos_" + presetName$
result = selected("Sound")

# 1. Apply drive
appendInfoLine: "  Applying drive (", drive, "x)..."
Formula: ~ self * drive

# 2. Apply wave folding
if fold_count > 0
    appendInfoLine: "  Applying ", fold_count, " fold(s)..."
    fold_threshold = 0.7
    for i from 1 to fold_count
        # Fold positive peaks
        Formula: ~ if self > fold_threshold then fold_threshold - (self - fold_threshold) else self fi
        # Fold negative peaks
        Formula: ~ if self < -fold_threshold then -fold_threshold - (self + fold_threshold) else self fi
    endfor
endif

# 3. Apply bit crushing
appendInfoLine: "  Applying bit crush (", bit_crush, " bits)..."
levels = 2 ^ bit_crush
Formula: ~ round(self * levels) / levels

# 4. Apply sample rate reduction (if < 100%)
if sample_rate_percent < 100
    appendInfoLine: "  Applying sample rate reduction..."
    new_rate = sr * (sample_rate_percent / 100)
    if new_rate < 1000
        new_rate = 1000
    endif
    
    # Resample down
    selectObject: result
    Resample: new_rate, 50
    downsampled = selected("Sound")
    
    # Resample back up
    Resample: sr, 50
    resampled = selected("Sound")
    
    # Copy data back and cleanup
    selectObject: result
    Formula: ~ object[resampled]
    
    removeObject: downsampled, resampled
endif

# 5. Add noise if requested
if add_noise
    appendInfoLine: "  Adding noise..."
    selectObject: result
    Formula: ~ self + randomUniform(-noise_amount, noise_amount)
endif

# 6. Normalize if requested
if normalize
    selectObject: result
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
    Text: 0.5, "centre", 0.5, "half", "Chaos Distortion: " + original_name$ + " (" + presetName$ + ")"
    
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
    Colour: "{0.7, 0.5, 0.4}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Chaos"
    Text bottom: "yes", "Time (s)"
    
    # Zoomed comparison (first 50ms)
    zoomDur = min(0.05, duration)
    
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
    Colour: "{0.7, 0.5, 0.4}"
    Draw: 0, zoomDur, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Chaos (zoom)"
    Text bottom: "yes", "Time (s)"
    
    # Transfer function (wave folding)
    Select outer viewport: 0, 4, 4.0, 5.2
    Select inner viewport: 0.6, 3.8, 4.1, 5.1
    
    Axes: -1.2, 1.2, -1.2, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", -1.2, 1.2, -1.2, 1.2
    
    # Grid
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: -1.2, 0, 1.2, 0
    Draw line: 0, -1.2, 0, 1.2
    Dotted line
    Draw line: -1, -1, 1, 1
    Solid line
    
    # Draw transfer function
    Colour: "{0.7, 0.5, 0.4}"
    Line width: 2
    nPoints = 200
    for p from 2 to nPoints
        x1 = -1.0 + (p - 2) / nPoints * 2.0
        x2 = -1.0 + (p - 1) / nPoints * 2.0
        
        # Apply drive
        y1 = x1 * drive
        y2 = x2 * drive
        
        # Apply folding
        for f from 1 to fold_count
            if y1 > 0.7
                y1 = 0.7 - (y1 - 0.7)
            endif
            if y1 < -0.7
                y1 = -0.7 - (y1 + 0.7)
            endif
            if y2 > 0.7
                y2 = 0.7 - (y2 - 0.7)
            endif
            if y2 < -0.7
                y2 = -0.7 - (y2 + 0.7)
            endif
        endfor
        
        # Apply bit crush (simplified for display)
        levels_disp = 2 ^ bit_crush
        y1 = round(y1 * levels_disp) / levels_disp
        y2 = round(y2 * levels_disp) / levels_disp
        
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
    
    Colour: "Black"
    Draw inner box
    Font size: 5
    Text left: "yes", "Out"
    Text bottom: "yes", "In"
    Text: 0, "centre", 1.3, "half", "Transfer (Drive+Fold+Crush)"
    
    # Processing chain diagram
    Select outer viewport: 4, 8, 4.0, 5.2
    Select inner viewport: 4.4, 7.6, 4.1, 5.1
    
    Axes: 0, 5, 0, 3
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 5, 0, 3
    
    Font size: 5
    
    # Chain boxes
    Paint rectangle: "{0.8, 0.7, 0.6}", 0.1, 0.9, 1.2, 1.8
    Colour: "Black"
    Text: 0.5, "centre", 1.5, "half", "Drive"
    Text: 0.5, "centre", 1.1, "half", fixed$(drive, 1) + "x"
    
    Draw arrow: 0.9, 1.5, 1.1, 1.5
    
    Paint rectangle: "{0.7, 0.8, 0.6}", 1.1, 1.9, 1.2, 1.8
    Text: 1.5, "centre", 1.5, "half", "Fold"
    Text: 1.5, "centre", 1.1, "half", string$(fold_count) + "x"
    
    Draw arrow: 1.9, 1.5, 2.1, 1.5
    
    Paint rectangle: "{0.6, 0.7, 0.8}", 2.1, 2.9, 1.2, 1.8
    Text: 2.5, "centre", 1.5, "half", "Crush"
    Text: 2.5, "centre", 1.1, "half", string$(bit_crush) + " bit"
    
    Draw arrow: 2.9, 1.5, 3.1, 1.5
    
    Paint rectangle: "{0.6, 0.8, 0.7}", 3.1, 3.9, 1.2, 1.8
    Text: 3.5, "centre", 1.5, "half", "SR"
    Text: 3.5, "centre", 1.1, "half", fixed$(sample_rate_percent, 0) + "%"
    
    Draw arrow: 3.9, 1.5, 4.1, 1.5
    
    if add_noise
        Paint rectangle: "{0.8, 0.6, 0.6}", 4.1, 4.9, 1.2, 1.8
    else
        Paint rectangle: "{0.85, 0.85, 0.85}", 4.1, 4.9, 1.2, 1.8
    endif
    Text: 4.5, "centre", 1.5, "half", "Noise"
    if add_noise
        Text: 4.5, "centre", 1.1, "half", "ON"
    else
        Colour: "{0.6, 0.6, 0.6}"
        Text: 4.5, "centre", 1.1, "half", "OFF"
    endif
    
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