# ============================================================
# Praat AudioTools - Dynamic Distortion (Envelope Follower)
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Applies distortion where the Drive amount is modulated by
#   the input signal's amplitude envelope.
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# === Form ===
form Dynamic Distortion
    comment Select a Preset
    optionmenu Preset 1
        option Manual
        option Touch Sensitive Drive
        option Drum Pumper
        option Gated Crunch
        option Expressive Lead

    comment Envelope Follower
    real Base_Drive 1.0
    real Sensitivity 5.0
    real Response_Speed_Hz 20.0
    comment (Higher Hz = Fast attack/release, Lower Hz = Smooth/Slow)

    comment Output
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
presetName$ = "Manual"

if preset = 2
    presetName$ = "Touch Sensitive Drive"
    base_Drive = 0.8
    sensitivity = 3.0
    response_Speed_Hz = 15.0
    output_Gain = 0.9
elsif preset = 3
    presetName$ = "Drum Pumper"
    base_Drive = 1.0
    sensitivity = 8.0
    response_Speed_Hz = 50.0
    output_Gain = 0.8
elsif preset = 4
    presetName$ = "Gated Crunch"
    # Negative base drive acts like a gate/expander before distorting
    base_Drive = -0.5 
    sensitivity = 10.0
    response_Speed_Hz = 80.0
    output_Gain = 1.0
elsif preset = 5
    presetName$ = "Expressive Lead"
    base_Drive = 1.2
    sensitivity = 4.0
    response_Speed_Hz = 10.0
    output_Gain = 0.9
endif

# Get original object details
original = selected("Sound")
origName$ = selected$("Sound")
selectObject: original
xmin = Get start time
xmax = Get end time

# === Step 1: Create the Envelope Follower ===
selectObject: original
# Create a Mono copy for analysis
env_Sound = Convert to mono
Rename: "Envelope_Temp"

# Rectify (Absolute value)
Formula: "abs(self)"

# Low Pass Filter to smooth the envelope
filter_Sound = Filter (pass Hann band): 0, response_Speed_Hz, 20
Rename: "Envelope_Filtered"

# Clean up rect copy
selectObject: env_Sound
Remove

# === Step 2: Prepare the "Stereo Container" ===
# We combine Original (Ch1) and Envelope (Ch2) into one object 
selectObject: original
orig_Mono = Convert to mono
selectObject: orig_Mono
plusObject: filter_Sound
container = Combine to stereo
Rename: "Processing_Container"

# === Step 3: Apply Dynamic Distortion ===
selectObject: container

# Define string variables for formula
b_str$ = string$(base_Drive)
s_str$ = string$(sensitivity)
g_str$ = string$(output_Gain)

# The Logic:
# We strictly reference the object by name to avoid ambiguity.
# Channel 1 (row=1) is Audio. Channel 2 (row=2) is Envelope.
# We access the envelope value using Sound_Processing_Container[2, col]
# 'col' is the built-in variable for the current sample index.

formula_str$ = "if row = 1 then "
formula_str$ = formula_str$ + "tanh(self * (" + b_str$ + " + (Sound_Processing_Container[2, col] * " + s_str$ + "))) * " + g_str$
formula_str$ = formula_str$ + " else self fi"

Formula: formula_str$

# === Step 4: Extract Result ===
selectObject: container
result = Extract one channel: 1
Rename: origName$ + "_DynDist_" + replace$(presetName$, " ", "", 0)
Scale peak: 0.99

# === Cleanup ===
selectObject: filter_Sound
plusObject: orig_Mono
plusObject: container
Remove

# === Visualization ===
if draw_visualization
    Erase all
    
    # 1. Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Dynamic Distortion: " + origName$
    
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
    
    # 3. Dynamic Result
    Select outer viewport: 0, 8, 1.7, 2.7
    Select inner viewport: 0.6, 7.6, 1.8, 2.6
    selectObject: result
    Colour: "{0.8, 0.4, 0.4}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Result"
    
    # 4. Analysis: Envelope
    Select outer viewport: 0, 8, 2.9, 4.5
    Select inner viewport: 0.6, 7.6, 3.1, 4.3
    
    # Recreate envelope just for display
    selectObject: original
    temp_Disp = Convert to mono
    Formula: "abs(self)"
    temp_Env = Filter (pass Hann band): 0, response_Speed_Hz, 20
    
    Colour: "{0.2, 0.5, 0.2}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Control Env"
    Text bottom: "yes", "Time (s)"
    
    # Cleanup display objects
    selectObject: temp_Disp
    plusObject: temp_Env
    Remove
    
    # 5. Stats
    Select outer viewport: 0, 8, 4.6, 5.0
    Font size: 8
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.5, "centre", 0.5, "half", "Preset: " + presetName$
    Text: 0.5, "centre", 0.2, "half", "Base: " + string$(base_Drive) + " | Sens: " + string$(sensitivity) + " | Speed: " + string$(response_Speed_Hz) + " Hz"
    
    Font size: 10
    Colour: "Black"
endif

# === Finalize ===
selectObject: result
if play_result
    Play
endif

writeInfoLine: "Applied Dynamic Distortion to: ", origName$
appendInfoLine: "Preset: ", presetName$