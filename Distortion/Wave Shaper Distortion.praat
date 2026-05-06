# ============================================================
# Praat AudioTools - Wave_Shaper_Distortion.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Wave Shaper Distortion - comprehensive waveshaping toolkit
#   with 12 different transfer function algorithms and 5
#   processing modes. From subtle saturation to extreme folding.
#   Includes frequency-split, asymmetric, multi-stage, and
#   stereo M/S processing options.
#
# Algorithms:
#   1. Hyperbolic Tangent (soft clip)
#   2. Sine Fold (warm harmonics)
#   3. Arc Tangent (smooth saturation)
#   4. Polynomial (gentle curve)
#   5. Absolute Value (rectifier)
#   6. Square Law (fuzzy)
#   7. Chebyshev (harmonic control)
#   8. Sigmoid (tube-like)
#   9. Exponential Fold (chaotic)
#   10. Bitcrush (lo-fi)
#   11. Wave Wrap (circular)
#   12. Diode Ladder (analog asymmetric)
#
# Changelog v0.2:
#   - Fixed input check
#   - Fixed selection syntax (use object IDs)
#   - Fixed formula syntax (string building)
#   - Fixed procedure call syntax (@)
#   - Fixed frequency split high band filter
#   - Fixed M/S stereo mode
#   - Added visualization
#   - Added info output
# ============================================================

form Wave Shaper Distortion
    comment Select a Sound object first
    
    comment === Waveshaping Algorithm ===
    choice Shape 1
        option 1. Hyperbolic Tangent (soft)
        option 2. Sine Fold (warm)
        option 3. Arc Tangent (smooth)
        option 4. Polynomial (aggressive)
        option 5. Absolute Value (digital)
        option 6. Square Law (fuzzy)
        option 7. Chebyshev (harmonic)
        option 8. Sigmoid (tube-like)
        option 9. Exponential Fold (chaotic)
        option 10. Bitcrush (lo-fi)
        option 11. Wave Wrap (circular)
        option 12. Diode Ladder (analog)
    
    comment === Parameters ===
    positive Drive 2.0
    positive Mix_percent 80
    
    comment === Processing Mode ===
    optionmenu Mode 1
        option Standard
        option Frequency Split (800 Hz)
        option Asymmetric (+/- different)
        option Multi-Stage (3x cascade)
        option Stereo Wide (M/S)
    
    comment === Output ===
    boolean Normalize 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
duration = Get total duration
sr = Get sampling frequency
numChannels = Get number of channels
if numChannels = 2
    is_stereo = 1
else
    is_stereo = 0
endif

# === Get Shape and Mode Names ===

# === Get Shape and Mode Names ===
@getShapeName: shape
@getModeName: mode

# === Info ===
writeInfoLine: "=== Wave Shaper Distortion ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Shape: ", shape_name$
appendInfoLine: "Mode: ", mode_name$
appendInfoLine: "Drive: ", drive
appendInfoLine: "Mix: ", mix_percent, "%"
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Processing..."

selectObject: original
Copy: "processing_temp"
proc_sound = selected("Sound")

# Convert drive to string for formulas
drive_str$ = string$(drive)

# ====== MODE-SPECIFIC PROCESSING ======

if mode = 1
    # === STANDARD MODE ===
    appendInfoLine: "  Mode: Standard"
    selectObject: proc_sound
    Formula: "self * " + drive_str$
    @applyWaveShaping: proc_sound, shape

elsif mode = 2
    # === FREQUENCY SPLIT MODE ===
    appendInfoLine: "  Mode: Frequency Split (800 Hz)"
    freq_split = 800
    
    # Extract low band
    selectObject: proc_sound
    Filter (pass Hann band): 20, freq_split, 100
    low_band = selected("Sound")
    
    # Extract high band
    selectObject: proc_sound
    Filter (pass Hann band): freq_split, sr/2, 100
    high_band = selected("Sound")
    
    # Process low band (normal drive)
    selectObject: low_band
    Formula: "self * " + drive_str$
    @applyWaveShaping: low_band, shape
    
    # Process high band (1.5x drive for brightness)
    drive_high_str$ = string$(drive * 1.5)
    selectObject: high_band
    Formula: "self * " + drive_high_str$
    @applyWaveShaping: high_band, shape
    
    # Recombine
    low_str$ = string$(low_band)
    high_str$ = string$(high_band)
    
    selectObject: proc_sound
    Formula: "object[" + low_str$ + "] + object[" + high_str$ + "]"
    
    removeObject: low_band, high_band

elsif mode = 3
    # === ASYMMETRIC MODE ===
    appendInfoLine: "  Mode: Asymmetric"
    selectObject: proc_sound
    Formula: "self * " + drive_str$
    @applyWaveShaping: proc_sound, shape
    # Different gain for positive/negative
    Formula: ~ if self > 0 then self * 1.3 else self * 0.8 fi

elsif mode = 4
    # === MULTI-STAGE MODE ===
    appendInfoLine: "  Mode: Multi-Stage (3 cascaded)"
    # Divide drive across 3 stages: total_drive = stage^3
    stage_drive = drive ^ (1/3)
    stage_drive_str$ = string$(stage_drive)
    
    selectObject: proc_sound
    for stage from 1 to 3
        appendInfoLine: "    Stage ", stage, "/3..."
        Formula: "self * " + stage_drive_str$
        @applyWaveShaping: proc_sound, shape
    endfor

elsif mode = 5
    # === STEREO WIDE MODE (M/S Processing) ===
    appendInfoLine: "  Mode: Stereo Wide (M/S)"
    
    if is_stereo
        # Extract channels
        selectObject: proc_sound
        Extract one channel: 1
        left_ch = selected("Sound")
        
        selectObject: proc_sound
        Extract one channel: 2
        right_ch = selected("Sound")
        
        left_str$ = string$(left_ch)
        right_str$ = string$(right_ch)
        
        # Create Mid signal: (L + R) / 2
        selectObject: left_ch
        Copy: "mid_temp"
        mid_signal = selected("Sound")
        Formula: "(object[" + left_str$ + "] + object[" + right_str$ + "]) / 2"
        
        # Process Mid with normal drive
        Formula: "self * " + drive_str$
        @applyWaveShaping: mid_signal, shape
        
        # Create Side signal: (L - R) / 2
        selectObject: left_ch
        Copy: "side_temp"
        side_signal = selected("Sound")
        Formula: "(object[" + left_str$ + "] - object[" + right_str$ + "]) / 2"
        
        # Process Side with 1.5x drive (enhances width)
        drive_side_str$ = string$(drive * 1.5)
        Formula: "self * " + drive_side_str$
        @applyWaveShaping: side_signal, shape
        
        mid_str$ = string$(mid_signal)
        side_str$ = string$(side_signal)
        
        # Reconstruct L = Mid + Side
        selectObject: left_ch
        Formula: "object[" + mid_str$ + "] + object[" + side_str$ + "]"
        
        # Reconstruct R = Mid - Side
        selectObject: right_ch
        Formula: "object[" + mid_str$ + "] - object[" + side_str$ + "]"
        
        # Combine back to stereo
        selectObject: left_ch, right_ch
        Combine to stereo
        new_stereo = selected("Sound")
        
        # Replace proc_sound
        removeObject: proc_sound, mid_signal, side_signal
        proc_sound = new_stereo
    else
        # Fallback to standard for mono
        appendInfoLine: "    (Mono input - using Standard mode)"
        selectObject: proc_sound
        Formula: "self * " + drive_str$
        @applyWaveShaping: proc_sound, shape
    endif
endif

# ====== MIX DRY/WET ======

if mix_percent < 100
    appendInfoLine: "Mixing dry/wet (", mix_percent, "% wet)..."
    
    wet_level = mix_percent / 100
    dry_level = 1 - wet_level
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    orig_str$ = string$(original)
    
    selectObject: proc_sound
    Formula: "(self * " + wet_str$ + ") + (object[" + orig_str$ + "] * " + dry_str$ + ")"
endif

# ====== NORMALIZE ======

if normalize
    selectObject: proc_sound
    Scale peak: 0.95
endif

# ====== FINAL NAMING ======

selectObject: proc_sound
Rename: original_name$ + "_" + shape_name$ + "_" + mode_name$
result = selected("Sound")

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Wave Shaper: " + shape_name$ + " / " + mode_name$
    
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
    Colour: "{0.6, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Shaped"
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
    Colour: "{0.6, 0.5, 0.7}"
    Draw: 0, zoomDur, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Shaped (zoom)"
    Text bottom: "yes", "Time (s)"
    
    # Transfer function
    Select outer viewport: 0, 4, 4.0, 5.5
    Select inner viewport: 0.6, 3.8, 4.1, 5.4
    
    Axes: -1.5, 1.5, -1.5, 1.5
    Paint rectangle: "{0.95, 0.95, 0.95}", -1.5, 1.5, -1.5, 1.5
    
    # Grid
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: -1.5, 0, 1.5, 0
    Draw line: 0, -1.5, 0, 1.5
    Dotted line
    Draw line: -1.2, -1.2, 1.2, 1.2
    Solid line
    
    # Draw transfer function
    Colour: "{0.6, 0.5, 0.7}"
    Line width: 2
    nPoints = 300
    
    for p from 2 to nPoints
        x1 = -1.2 + (p - 2) / nPoints * 2.4
        x2 = -1.2 + (p - 1) / nPoints * 2.4
        
        # Apply drive
        in1 = x1 * drive
        in2 = x2 * drive
        
        # Apply shaping function
        @computeShape: in1, shape
        y1 = result_value
        @computeShape: in2, shape
        y2 = result_value
        
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
    
    Colour: "Black"
    Draw inner box
    Font size: 5
    Text left: "yes", "Output"
    Text bottom: "yes", "Input"
    Text: 0, "centre", 1.6, "half", shape_name$ + " (drive=" + fixed$(drive, 1) + ")"
    
    # Algorithm list
    Select outer viewport: 4, 8, 4.0, 5.5
    Select inner viewport: 4.4, 7.6, 4.1, 5.4
    
    Axes: 0, 4, 0, 12
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 4, 0, 12
    
    Font size: 5
    
    # List all algorithms, highlight current
    algorithms$[1] = "1. Tanh (soft)"
    algorithms$[2] = "2. Sine Fold"
    algorithms$[3] = "3. Arctan"
    algorithms$[4] = "4. Polynomial"
    algorithms$[5] = "5. Abs (rectify)"
    algorithms$[6] = "6. Square Law"
    algorithms$[7] = "7. Chebyshev"
    algorithms$[8] = "8. Sigmoid"
    algorithms$[9] = "9. Exp Fold"
    algorithms$[10] = "10. Bitcrush"
    algorithms$[11] = "11. Wave Wrap"
    algorithms$[12] = "12. Diode"
    
    for i from 1 to 12
        yPos = 12 - i + 0.5
        if i = shape
            Colour: "{0.6, 0.5, 0.7}"
            Paint rectangle: "{0.85, 0.8, 0.9}", 0.1, 3.9, yPos - 0.4, yPos + 0.4
            Colour: "Black"
            Text: 0.2, "left", yPos, "half", "► " + algorithms$[i]
        else
            Colour: "{0.5, 0.5, 0.5}"
            Text: 0.2, "left", yPos, "half", algorithms$[i]
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    
    # Parameters
    Select outer viewport: 0, 8, 5.6, 6.0
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Drive: " + fixed$(drive, 1) + " | Mix: " + fixed$(mix_percent, 0) + "% | Mode: " + mode_name$ + " | Normalize: " + if normalize then "ON" else "OFF" fi
    
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

# ============================================================
# PROCEDURES
# ============================================================

procedure applyWaveShaping: .sound, .shape
    selectObject: .sound
    
    if .shape = 1
        # Hyperbolic Tangent (soft clip)
        Formula: ~ tanh(self * 1.5) / 1.5
    elsif .shape = 2
        # Sine Fold (warm)
        Formula: ~ sin(self * 2.5) * 0.85
    elsif .shape = 3
        # Arc Tangent (smooth)
        Formula: ~ 2 * arctan(self * 1.8) / pi
    elsif .shape = 4
        # Polynomial (aggressive)
        Formula: ~ self - (self * self * self) * 0.33
    elsif .shape = 5
        # Absolute Value (rectifier)
        Formula: ~ abs(self)
    elsif .shape = 6
        # Square Law (fuzzy)
        Formula: ~ self * abs(self) * 0.8
    elsif .shape = 7
        # Chebyshev polynomials (harmonic control)
        # T1 + 0.2*T2 + 0.1*T3
        Formula: ~ self * 0.7 + (2 * self * self - 1) * 0.2 + (4 * self^3 - 3 * self) * 0.1
    elsif .shape = 8
        # Sigmoid (tube-like)
        Formula: ~ (2 / (1 + exp(-self * 2))) - 1
    elsif .shape = 9
        # Exponential Fold (chaotic)
        Formula: ~ (exp(self) - exp(-self)) / (exp(self) + exp(-self) + 0.1)
    elsif .shape = 10
        # Bitcrush (lo-fi)
        Formula: ~ floor(self * 16 + 0.5) / 16
    elsif .shape = 11
        # Wave Wrap (circular)
        Formula: ~ if abs(self) > 1 then -self / abs(self) * (2 - abs(self)) else self fi
    elsif .shape = 12
        # Diode Ladder (analog asymmetric)
        Formula: ~ if self > 0 then (1 - exp(-self * 2)) * 0.5 else (exp(self * 2) - 1) * 0.3 fi
    endif
endproc

procedure computeShape: .input, .shape
    # Compute waveshaping for visualization (returns result_value)
    
    if .shape = 1
        result_value = tanh(.input * 1.5) / 1.5
    elsif .shape = 2
        result_value = sin(.input * 2.5) * 0.85
    elsif .shape = 3
        result_value = 2 * arctan(.input * 1.8) / pi
    elsif .shape = 4
        result_value = .input - (.input * .input * .input) * 0.33
    elsif .shape = 5
        result_value = abs(.input)
    elsif .shape = 6
        result_value = .input * abs(.input) * 0.8
    elsif .shape = 7
        result_value = .input * 0.7 + (2 * .input * .input - 1) * 0.2 + (4 * .input^3 - 3 * .input) * 0.1
    elsif .shape = 8
        result_value = (2 / (1 + exp(-.input * 2))) - 1
    elsif .shape = 9
        result_value = (exp(.input) - exp(-.input)) / (exp(.input) + exp(-.input) + 0.1)
    elsif .shape = 10
        result_value = floor(.input * 16 + 0.5) / 16
    elsif .shape = 11
        if abs(.input) > 1
            result_value = -.input / abs(.input) * (2 - abs(.input))
        else
            result_value = .input
        endif
    elsif .shape = 12
        if .input > 0
            result_value = (1 - exp(-.input * 2)) * 0.5
        else
            result_value = (exp(.input * 2) - 1) * 0.3
        endif
    endif
endproc

procedure getShapeName: .shape
    if .shape = 1
        shape_name$ = "Tanh"
    elsif .shape = 2
        shape_name$ = "SineFold"
    elsif .shape = 3
        shape_name$ = "Arctan"
    elsif .shape = 4
        shape_name$ = "Polynomial"
    elsif .shape = 5
        shape_name$ = "Abs"
    elsif .shape = 6
        shape_name$ = "SquareLaw"
    elsif .shape = 7
        shape_name$ = "Chebyshev"
    elsif .shape = 8
        shape_name$ = "Sigmoid"
    elsif .shape = 9
        shape_name$ = "ExpFold"
    elsif .shape = 10
        shape_name$ = "Bitcrush"
    elsif .shape = 11
        shape_name$ = "WaveWrap"
    elsif .shape = 12
        shape_name$ = "DiodeLadder"
    endif
endproc

procedure getModeName: .mode
    if .mode = 1
        mode_name$ = "Standard"
    elsif .mode = 2
        mode_name$ = "FreqSplit"
    elsif .mode = 3
        mode_name$ = "Asymmetric"
    elsif .mode = 4
        mode_name$ = "MultiStage"
    elsif .mode = 5
        mode_name$ = "StereoWide"
    endif
endproc