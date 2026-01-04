# ============================================================
# Praat AudioTools - Asymmetric Soft Clipping (Tube Distortion)
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Applies asymmetric soft clipping (tube-style bias distortion).
#   Uses pure boolean math for maximum Praat version compatibility.
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# === Form ===
form Asymmetric Soft Clipping
    comment Select a Preset (overrides sliders below)
    optionmenu Preset 1
        option Manual (Use settings below)
        option Warm Tube Saturation
        option Hard Overdrive
        option Asymmetric Fuzz
        option Broken/Gated Bias
        option Subtle Warmer
    
    comment Manual Parameters
    real Drive 2.0
    real Bias 0.1
    real Pos_Shape 1.0
    real Neg_Shape 3.0
    real Output_Gain 0.8
    
    comment Visualization
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

# === Handle Presets ===
# If a preset is chosen, we overwrite the form variables
presetName$ = "Manual"

if preset = 2
    presetName$ = "Warm Tube Saturation"
    drive = 1.5
    bias = 0.05
    pos_Shape = 0.8
    neg_Shape = 1.2
    output_Gain = 0.9
elsif preset = 3
    presetName$ = "Hard Overdrive"
    drive = 5.0
    bias = 0.0
    pos_Shape = 2.0
    neg_Shape = 2.0
    output_Gain = 0.5
elsif preset = 4
    presetName$ = "Asymmetric Fuzz"
    drive = 3.5
    bias = 0.3
    pos_Shape = 5.0
    neg_Shape = 0.5
    output_Gain = 0.6
elsif preset = 5
    presetName$ = "Broken/Gated Bias"
    # High bias pushes signal into the flat part of tanh, silencing quiet parts
    drive = 4.0
    bias = 0.8 
    pos_Shape = 4.0
    neg_Shape = 0.5
    output_Gain = 0.6
elsif preset = 6
    presetName$ = "Subtle Warmer"
    drive = 1.1
    bias = 0.02
    pos_Shape = 0.5
    neg_Shape = 0.6
    output_Gain = 0.95
endif

# Get original object details
original = selected("Sound")
origName$ = selected$("Sound")
selectObject: original
xmin = Get start time
xmax = Get end time

# === Process Audio ===
selectObject: original
Copy: origName$ + "_Tube_" + replace$(presetName$, " ", "", 0)
result = selected("Sound")

# -----------------------------------------------------------------------
# ROBUST FORMULA GENERATION
# -----------------------------------------------------------------------

# 1. Define the Input Signal chunk: (self * drive + bias)
in$ = "(self * " + string$(drive) + " + " + string$(bias) + ")"

# 2. Define the Boolean Switch for the Shape
shape_logic$ = "( (" + in$ + " >= 0) * " + string$(pos_Shape) + " + (" + in$ + " < 0) * " + string$(neg_Shape) + " )"

# 3. Combine into final tanh formula
formula$ = "tanh(" + in$ + " * " + shape_logic$ + ") * " + string$(output_Gain)

# Apply
Formula: formula$

# === Visualization ===
if draw_visualization
    Erase all
    
    # 1. Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Tube Distortion: " + origName$
    
    # 2. Original Waveform
    Select outer viewport: 0, 8, 0.6, 1.6
    Select inner viewport: 0.6, 7.6, 0.7, 1.5
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # 3. Distorted Waveform
    Select outer viewport: 0, 8, 1.7, 2.7
    Select inner viewport: 0.6, 7.6, 1.8, 2.6
    selectObject: result
    Colour: "{0.8, 0.4, 0.4}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Distorted"
    Text bottom: "yes", "Time (s)"
    
    # 4. Transfer Function (Input vs Output Curve)
    Select outer viewport: 0, 8, 2.9, 5.0
    Select inner viewport: 0.6, 7.6, 3.1, 4.8
    
    Axes: -1.5, 1.5, -1.5, 1.5
    Paint rectangle: "{0.95, 0.95, 0.95}", -1.5, 1.5, -1.5, 1.5
    
    Colour: "{0.8, 0.8, 0.8}"
    Dotted line
    Draw line: -1.5, 0, 1.5, 0
    Draw line: 0, -1.5, 0, 1.5
    Draw line: -1.5, -1.5, 1.5, 1.5
    Solid line
    
    Colour: "{0.3, 0.3, 0.8}"
    Line width: 2.5
    
    steps = 100
    prev_x = -1.5
    
    # Pre-calc first point
    val_prev = prev_x * drive + bias
    # Boolean logic for pre-calc (manual equivalent)
    if val_prev >= 0
        shape_p = pos_Shape
    else
        shape_p = neg_Shape
    endif
    prev_y = tanh(val_prev * shape_p) * output_Gain
    
    for i from 1 to steps
        curr_x = -1.5 + (i * (3.0 / steps))
        
        # Calc Y
        val = curr_x * drive + bias
        if val >= 0
            shape = pos_Shape
        else
            shape = neg_Shape
        endif
        curr_y = tanh(val * shape) * output_Gain
        
        Draw line: prev_x, prev_y, curr_x, curr_y
        
        prev_x = curr_x
        prev_y = curr_y
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text bottom: "yes", "Input Amplitude"
    Text left: "yes", "Output Amplitude"
    
    # 5. Stats
    Select outer viewport: 0, 8, 5.1, 5.5
    Font size: 8
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.5, "centre", 0.5, "half", "Preset: " + presetName$
    Text: 0.5, "centre", 0.2, "half", "Drive: " + string$(drive) + " | Bias: " + string$(bias) + " | Pos/Neg Shape: " + string$(pos_Shape) + " / " + string$(neg_Shape)
    
    Font size: 10
    Colour: "Black"
endif

# === Finalize ===
selectObject: result
if play_result
    Play
endif

writeInfoLine: "Applied Asymmetric Soft Clipping to: ", origName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Drive: ", drive, " | Bias: ", bias