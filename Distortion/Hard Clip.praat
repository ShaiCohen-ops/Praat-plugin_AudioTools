# ============================================================
# Praat AudioTools - Hard Clip (Variable Knee)
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Applies hard clipping with a configurable "Soft Knee".
#   - Below (Threshold - Knee): Linear (1:1)
#   - Between (Threshold +/- Knee): Smooth Quadratic Curve
#   - Above (Threshold + Knee): Hard Clamp
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# === Form ===
form Hard Clip (Variable Knee)
    comment Select a Preset (overrides sliders below)
    optionmenu Preset 1
        option Manual (Use settings below)
        option Brickwall Limiter
        option Soft Clipper
        option Hard Distortion
        option Subtle Glue
        option Fuzz Face (Low Thresh)

    comment Parameters
    real Drive 1.0
    real Threshold 0.5
    real Knee_Width 0.2
    real Output_Gain 0.9
    
    comment Visualization
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

# === Handle Presets ===
# Praat automatically makes form variables lowercase (Preset -> preset)
presetName$ = "Manual"

if preset = 2
    presetName$ = "Brickwall Limiter"
    drive = 1.2
    threshold = 0.8
    knee_Width = 0.05
    output_Gain = 0.95
elsif preset = 3
    presetName$ = "Soft Clipper"
    drive = 2.0
    threshold = 0.6
    knee_Width = 0.4
    output_Gain = 0.8
elsif preset = 4
    presetName$ = "Hard Distortion"
    drive = 5.0
    threshold = 0.4
    knee_Width = 0.01
    output_Gain = 0.6
elsif preset = 5
    presetName$ = "Subtle Glue"
    drive = 1.0
    threshold = 0.7
    knee_Width = 0.5
    output_Gain = 1.0
elsif preset = 6
    presetName$ = "Fuzz Face (Low Thresh)"
    drive = 8.0
    threshold = 0.1
    knee_Width = 0.1
    output_Gain = 0.5
endif

# === Safety Checks ===
if knee_Width < 0.001
    knee_Width = 0.001
endif
if threshold < 0.01
    threshold = 0.01
endif

# Get original object details
original = selected("Sound")
origName$ = selected$("Sound")
selectObject: original
xmin = Get start time
xmax = Get end time

# === Process Audio ===
selectObject: original
Copy: origName$ + "_Clip_" + replace$(presetName$, " ", "", 0)
result = selected("Sound")

# -----------------------------------------------------------------------
# ROBUST FORMULA GENERATION (Boolean Math)
# All variables here must start with lowercase to avoid syntax errors
# -----------------------------------------------------------------------

# 1. Define Constants (String representations)
t_str$ = string$(threshold)
k_str$ = string$(knee_Width)
t_minus_k$ = string$(threshold - knee_Width)
t_plus_k$ = string$(threshold + knee_Width)
drive_str$ = string$(drive)

# 2. Input Definition
# We calculate Input and Absolute Input
in$ = "(self * " + drive_str$ + ")"
absIn$ = "abs(" + in$ + ")"

# 3. Zone Logic (Boolean Switches)
# Returns 1 if true, 0 if false
# Using lowercase variable names for the strings
is_linear$ = "(" + absIn$ + " <= " + t_minus_k$ + ")"
is_flat$   = "(" + absIn$ + " >= " + t_plus_k$ + ")"
is_knee$   = "((" + absIn$ + " > " + t_minus_k$ + ") * (" + absIn$ + " < " + t_plus_k$ + "))"

# 4. Zone Math
# Linear Zone: Just pass the absolute input
val_linear$ = absIn$

# Flat Zone: Clamp to Threshold
val_flat$   = t_str$

# Knee Zone: Quadratic Bezier Curve
# Formula: T - ( (T+K - AbsIn)^2 / (4K) )
numerator$ = "(" + t_plus_k$ + " - " + absIn$ + ")^2"
denominator$ = "(4 * " + k_str$ + ")"
val_knee$   = "(" + t_str$ + " - (" + numerator$ + " / " + denominator$ + "))"

# 5. Combine Logic
# sum = (isLinear * valLin) + (isFlat * valFlat) + (isKnee * valKnee)
combined_abs$ = "( (" + is_linear$ + " * " + val_linear$ + ") + (" + is_flat$ + " * " + val_flat$ + ") + (" + is_knee$ + " * " + val_knee$ + ") )"

# 6. Restore Sign and Apply Gain
# sign(x) is approximated by ((x>0) - (x<0)) to be version-safe
sign_restore$ = "((" + in$ + ">0) - (" + in$ + "<0))"
final_formula$ = combined_abs$ + " * " + sign_restore$ + " * " + string$(output_Gain)

# Apply
Formula: final_formula$

# === Visualization ===
if draw_visualization
    Erase all
    
    # 1. Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Hard Clip (Knee): " + origName$
    
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
    Text left: "yes", "Clipped"
    Text bottom: "yes", "Time (s)"
    
    # 4. Transfer Function (Knee Visualizer)
    Select outer viewport: 0, 8, 2.9, 5.0
    Select inner viewport: 0.6, 7.6, 3.1, 4.8
    
    # Determine axes
    viewLimit = threshold * 1.5
    if viewLimit < 1.0
        viewLimit = 1.0
    endif
    
    Axes: -viewLimit, viewLimit, -viewLimit, viewLimit
    Paint rectangle: "{0.95, 0.95, 0.95}", -viewLimit, viewLimit, -viewLimit, viewLimit
    
    # Reference Grid
    Colour: "{0.8, 0.8, 0.8}"
    Dotted line
    Draw line: -viewLimit, 0, viewLimit, 0
    Draw line: 0, -viewLimit, 0, viewLimit
    Draw line: -viewLimit, -viewLimit, viewLimit, viewLimit
    
    # Draw Threshold Lines
    Colour: "{0.6, 0.6, 0.6}"
    Draw line: -viewLimit, threshold * output_Gain, viewLimit, threshold * output_Gain
    Draw line: -viewLimit, -threshold * output_Gain, viewLimit, -threshold * output_Gain
    Solid line
    
    # Calculate and Draw Curve
    Colour: "{0.2, 0.5, 0.2}"
    Line width: 2.5
    
    steps = 100
    prev_x = -viewLimit
    
    # Initial point calc
    val_in = prev_x * drive
    abs_v = abs(val_in)
    
    if abs_v <= (threshold - knee_Width)
        y_abs = abs_v
    elsif abs_v >= (threshold + knee_Width)
        y_abs = threshold
    else
        # Knee Math
        y_abs = threshold - ((threshold + knee_Width - abs_v)^2) / (4 * knee_Width)
    endif
    
    sign_v = -1
    if val_in > 0
        sign_v = 1
    endif
    if val_in = 0
        sign_v = 0
    endif
    
    prev_y = y_abs * sign_v * output_Gain

    # Plot Loop
    for i from 1 to steps
        curr_x = -viewLimit + (i * (2 * viewLimit / steps))
        
        val_in = curr_x * drive
        abs_v = abs(val_in)
        
        if abs_v <= (threshold - knee_Width)
            y_abs = abs_v
        elsif abs_v >= (threshold + knee_Width)
            y_abs = threshold
        else
            y_abs = threshold - ((threshold + knee_Width - abs_v)^2) / (4 * knee_Width)
        endif
        
        sign_v = 1
        if val_in < 0
            sign_v = -1
        endif
        
        curr_y = y_abs * sign_v * output_Gain
        
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
    Text: 0.5, "centre", 0.2, "half", "Thresh: " + string$(threshold) + " | Knee: " + string$(knee_Width) + " | Drive: " + string$(drive)
    
    Font size: 10
    Colour: "Black"
endif

# === Finalize ===
selectObject: result
if play_result
    Play
endif

writeInfoLine: "Applied Hard Clip (Knee) to: ", origName$
appendInfoLine: "Preset: ", presetName$