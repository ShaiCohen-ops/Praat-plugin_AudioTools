# ============================================================
# Praat AudioTools - Dynamic_Distortion.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Dynamic Distortion (Envelope Follower) - applies distortion
#   where the drive amount is modulated by the input signal's
#   amplitude envelope. Loud sections get more distortion,
#   quiet sections stay cleaner. Like touch-sensitive overdrive.
#
# Changelog v0.2:
#   - Fixed object reference (use ID instead of name)
#   - Added drive curve visualization
#   - Improved info output
# ============================================================

# === Form ===
form Dynamic Distortion
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Manual (use settings below)
        option Touch Sensitive Drive
        option Drum Pumper
        option Gated Crunch
        option Expressive Lead

    comment === Envelope Follower ===
    real Base_Drive 1.0
    comment (minimum drive when quiet)
    real Sensitivity 5.0
    comment (how much envelope adds to drive)
    real Response_Speed_Hz 20.0
    comment (higher = faster response, lower = smoother)

    comment === Output ===
    real Output_Gain 0.9
    
    comment === Visualization ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
origName$ = selected$("Sound")

selectObject: original
xmin = Get start time
xmax = Get end time
duration = Get total duration
sr = Get sampling frequency

# === Handle Presets ===
if preset = 1
    presetName$ = "Manual"
elsif preset = 2
    presetName$ = "TouchSensitive"
    base_Drive = 0.8
    sensitivity = 3.0
    response_Speed_Hz = 15.0
    output_Gain = 0.9
elsif preset = 3
    presetName$ = "DrumPumper"
    base_Drive = 1.0
    sensitivity = 8.0
    response_Speed_Hz = 50.0
    output_Gain = 0.8
elsif preset = 4
    presetName$ = "GatedCrunch"
    # Negative base drive acts like a gate/expander before distorting
    base_Drive = -0.5 
    sensitivity = 10.0
    response_Speed_Hz = 80.0
    output_Gain = 1.0
elsif preset = 5
    presetName$ = "ExpressiveLead"
    base_Drive = 1.2
    sensitivity = 4.0
    response_Speed_Hz = 10.0
    output_Gain = 0.9
endif

# === Info ===
writeInfoLine: "=== Dynamic Distortion ==="
appendInfoLine: "Source: ", origName$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Base drive: ", base_Drive
appendInfoLine: "Sensitivity: ", sensitivity
appendInfoLine: "Response: ", response_Speed_Hz, " Hz"
appendInfoLine: "Output gain: ", output_Gain
appendInfoLine: ""

# === Step 1: Create the Envelope Follower ===
appendInfoLine: "Creating envelope follower..."

selectObject: original
env_Sound = Convert to mono
Rename: "Envelope_Temp"

# Rectify (Absolute value)
Formula: ~ abs(self)

# Low Pass Filter to smooth the envelope
filter_Sound = Filter (pass Hann band): 0, response_Speed_Hz, 20
Rename: "Envelope_Filtered"
envelopeID = selected("Sound")

# Clean up rectified copy
removeObject: env_Sound

# === Step 2: Prepare the "Stereo Container" ===
# Combine Original (Ch1) and Envelope (Ch2) into one object 
appendInfoLine: "Preparing processing container..."

selectObject: original
orig_Mono = Convert to mono
selectObject: orig_Mono
plusObject: envelopeID
container = Combine to stereo
Rename: "Processing_Container"
containerID = selected("Sound")

# === Step 3: Apply Dynamic Distortion ===
appendInfoLine: "Applying dynamic distortion..."

selectObject: containerID

# The Logic:
# Channel 1 (row=1) is Audio. Channel 2 (row=2) is Envelope.
# drive = base_drive + (envelope * sensitivity)
# output = tanh(input * drive) * output_gain

# Build formula string with object ID reference
container_str$ = string$(containerID)
b_str$ = string$(base_Drive)
s_str$ = string$(sensitivity)
g_str$ = string$(output_Gain)

# Use object ID reference instead of name
formula_str$ = "if row = 1 then "
formula_str$ = formula_str$ + "tanh(self * (" + b_str$ + " + (object[" + container_str$ + ", 2, col] * " + s_str$ + "))) * " + g_str$
formula_str$ = formula_str$ + " else self fi"

Formula: formula_str$

# === Step 4: Extract Result ===
selectObject: containerID
result = Extract one channel: 1
Rename: origName$ + "_DynDist_" + presetName$
Scale peak: 0.95

# === Cleanup ===
removeObject: envelopeID, orig_Mono, containerID

# === Visualization ===
if draw_visualization
    Erase all
    
    # 1. Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Dynamic Distortion: " + origName$ + " (" + presetName$ + ")"
    
    # 2. Original Waveform
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.6, 0.7, 1.4
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # 3. Dynamic Result
    Select outer viewport: 0, 8, 1.6, 2.5
    Select inner viewport: 0.6, 7.6, 1.7, 2.4
    selectObject: result
    Colour: "{0.8, 0.4, 0.4}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Result"
    Text bottom: "yes", "Time (s)"
    
    # 4. Recreate envelope for display
    selectObject: original
    temp_Disp = Convert to mono
    Formula: ~ abs(self)
    temp_Env = Filter (pass Hann band): 0, response_Speed_Hz, 20
    
    # Get envelope stats for drive calculation display
    selectObject: temp_Env
    envMax = Get maximum: 0, 0, "Parabolic"
    envMin = Get minimum: 0, 0, "Parabolic"
    
    # 5. Envelope
    Select outer viewport: 0, 4, 2.7, 3.7
    Select inner viewport: 0.6, 3.8, 2.8, 3.6
    
    selectObject: temp_Env
    Colour: "{0.3, 0.6, 0.3}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Envelope"
    Text bottom: "yes", "Time (s)"
    
    # 6. Computed Drive (envelope * sensitivity + base)
    Select outer viewport: 4, 8, 2.7, 3.7
    Select inner viewport: 4.4, 7.6, 2.8, 3.6
    
    # Create drive signal for display
    selectObject: temp_Env
    Copy: "Drive_Display"
    driveDisp = selected("Sound")
    Formula: ~ base_Drive + self * sensitivity
    
    # Get drive range
    selectObject: driveDisp
    driveMax = Get maximum: 0, 0, "Parabolic"
    driveMin = Get minimum: 0, 0, "Parabolic"
    
    Colour: "{0.6, 0.4, 0.3}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Drive"
    Text bottom: "yes", "Time (s)"
    
    # Cleanup display objects
    removeObject: temp_Disp, temp_Env, driveDisp
    
    # 7. Transfer function illustration
    Select outer viewport: 0, 8, 3.9, 5.0
    Select inner viewport: 0.6, 7.6, 4.0, 4.9
    
    Axes: -1.2, 1.2, -1.2, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", -1.2, 1.2, -1.2, 1.2
    
    # Grid
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: -1.2, 0, 1.2, 0
    Draw line: 0, -1.2, 0, 1.2
    Dotted line
    Draw line: -1, -1, 1, 1
    Solid line
    
    # Draw multiple tanh curves for different drives
    nPoints = 100
    
    # Low drive (base only)
    Colour: "{0.7, 0.7, 0.7}"
    lowDrive = max(0.5, base_Drive)
    for p from 2 to nPoints
        x1 = -1.0 + (p - 2) / nPoints * 2.0
        x2 = -1.0 + (p - 1) / nPoints * 2.0
        y1 = tanh(x1 * lowDrive)
        y2 = tanh(x2 * lowDrive)
        Draw line: x1, y1, x2, y2
    endfor
    
    # High drive (base + sensitivity)
    Colour: "{0.8, 0.4, 0.4}"
    Line width: 1.5
    highDrive = base_Drive + sensitivity * 0.5
    for p from 2 to nPoints
        x1 = -1.0 + (p - 2) / nPoints * 2.0
        x2 = -1.0 + (p - 1) / nPoints * 2.0
        y1 = tanh(x1 * highDrive)
        y2 = tanh(x2 * highDrive)
        Draw line: x1, y1, x2, y2
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Output"
    Text bottom: "yes", "Input"
    Text: 0, "centre", 1.35, "half", "Gray: quiet (low drive) | Red: loud (high drive)"
    
    # 8. Stats
    Select outer viewport: 0, 8, 5.1, 5.5
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Base: " + fixed$(base_Drive, 1) + " | Sens: " + fixed$(sensitivity, 1) + " | Speed: " + fixed$(response_Speed_Hz, 0) + " Hz | Drive range: " + fixed$(driveMin, 1) + " - " + fixed$(driveMax, 1)
    
    Font size: 10
    Colour: "Black"
endif

# === Finalize ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

if play_result
    selectObject: result
    Play
endif

selectObject: result