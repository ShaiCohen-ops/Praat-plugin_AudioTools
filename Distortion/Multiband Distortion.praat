# ============================================================
# Praat AudioTools - Multiband Distortion
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Splits audio into Low, Mid, and High bands.
#   Applies independent distortion types and drive to each band.
#   Recombines using phase-coherent subtraction logic.
#   Leaves only Original and Result in the object list.
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# === Form ===
form Multiband Distortion
    comment Select a Preset
    optionmenu Preset 1
        option Manual
        option Warm Bass / Clean Highs
        option Frizz (Distorted Highs Only)
        option V-Shape Destruction
        option Mid-Range Crunch (Telephone)
        option Full Spectrum Fuzz

    comment Crossovers
    real Low_Split_Hz 200
    real High_Split_Hz 2500

    comment Low Band
    real Low_Drive 1.0
    optionmenu Low_Type 1
        option Soft Clip (Tanh)
        option Hard Clip
        option Sine Fold
    real Low_Gain 1.0

    comment Mid Band
    real Mid_Drive 1.0
    optionmenu Mid_Type 1
        option Soft Clip (Tanh)
        option Hard Clip
        option Sine Fold
    real Mid_Gain 1.0

    comment High Band
    real High_Drive 1.0
    optionmenu High_Type 1
        option Soft Clip (Tanh)
        option Hard Clip
        option Sine Fold
    real High_Gain 1.0

    comment Master
    real Mix_0_to_1 1.0
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
    presetName$ = "Warm Bass / Clean Highs"
    low_Drive = 3.0
    low_Type = 1
    low_Gain = 1.1
    mid_Drive = 1.0
    mid_Type = 1
    high_Drive = 0.5
    high_Type = 1
elsif preset = 3
    presetName$ = "Frizz (Distorted Highs)"
    low_Drive = 1.0
    low_Type = 1
    mid_Drive = 1.0
    mid_Type = 1
    high_Drive = 8.0
    high_Type = 2
    high_Split_Hz = 1500
elsif preset = 4
    presetName$ = "V-Shape Destruction"
    low_Drive = 4.0
    low_Type = 2
    mid_Drive = 0.5
    mid_Type = 1
    mid_Gain = 0.7
    high_Drive = 4.0
    high_Type = 2
elsif preset = 5
    presetName$ = "Mid-Range Crunch"
    low_Split_Hz = 400
    high_Split_Hz = 3000
    low_Drive = 0.5
    low_Gain = 0.5
    mid_Drive = 6.0
    mid_Type = 3
    mid_Gain = 1.2
    high_Drive = 0.5
    high_Gain = 0.5
elsif preset = 6
    presetName$ = "Full Spectrum Fuzz"
    low_Drive = 5.0
    mid_Drive = 5.0
    high_Drive = 5.0
    low_Type = 2
    mid_Type = 2
    high_Type = 2
endif

# === Setup ===
original = selected("Sound")
origName$ = selected$("Sound")
selectObject: original
xmin = Get start time
xmax = Get end time
sr = Get sampling frequency

# Safety check for crossovers
if low_Split_Hz >= high_Split_Hz
    temp = low_Split_Hz
    low_Split_Hz = high_Split_Hz - 1
    high_Split_Hz = temp + 1
endif

# ============================================================
# STEP 1: CROSSOVER SPLIT (Corrected Logic)
# ============================================================
# Fix: We do NOT use 'Copy' before Filter. 
# 'Filter' creates a new object automatically.
# This prevents leaving "ghost" copies behind.

# 1. Create Total Low Pass (Temp)
selectObject: original
Filter (pass Hann band): 0, high_Split_Hz, 20
Rename: "LP_Total_Temp"
lp_Total_Obj = selected("Sound")

# 2. Create Low Band
selectObject: original
Filter (pass Hann band): 0, low_Split_Hz, 20
Rename: "Low_Band"
low_Obj = selected("Sound")

# 3. Create Mid Band (LP_Total - Low)
selectObject: lp_Total_Obj
Copy: "Mid_Band"
mid_Obj = selected("Sound")
Formula: "self - object[" + string$(low_Obj) + "]"

# 4. Create High Band (Original - LP_Total)
selectObject: original
Copy: "High_Band"
high_Obj = selected("Sound")
Formula: "self - object[" + string$(lp_Total_Obj) + "]"

# Cleanup temp LP object
selectObject: lp_Total_Obj
Remove

# ============================================================
# STEP 2: APPLY DISTORTION PER BAND
# ============================================================

# --- Loop 1: LOW BAND ---
selectObject: low_Obj
cur_drive = low_Drive
cur_type = low_Type
cur_gain = low_Gain
call ApplyDistortion

# --- Loop 2: MID BAND ---
selectObject: mid_Obj
cur_drive = mid_Drive
cur_type = mid_Type
cur_gain = mid_Gain
call ApplyDistortion

# --- Loop 3: HIGH BAND ---
selectObject: high_Obj
cur_drive = high_Drive
cur_type = high_Type
cur_gain = high_Gain
call ApplyDistortion

# ============================================================
# STEP 3: SUM AND MIX
# ============================================================

# Sum the bands (Wet Signal)
selectObject: low_Obj
Copy: "Wet_Sum_Temp"
wet_Obj = selected("Sound")
Formula: "self + object[" + string$(mid_Obj) + "] + object[" + string$(high_Obj) + "]"

# CLEANUP: Remove the bands immediately
selectObject: low_Obj
plusObject: mid_Obj
plusObject: high_Obj
Remove

# Apply Output Gain to Wet Result
selectObject: wet_Obj
Formula: "self * " + string$(output_Gain)

# Handle Mix
if mix_0_to_1 >= 1.0
    # 100% Wet: Just rename the Wet object
    selectObject: wet_Obj
    Rename: origName$ + "_MultiDist_" + replace$(presetName$, " ", "", 0)
    result = wet_Obj
else
    # Partial Mix: Create a Dry Copy and mix
    selectObject: original
    Copy: "Dry_Temp"
    dry_Obj = selected("Sound")
    
    wet_Mix = mix_0_to_1
    dry_Mix = 1.0 - mix_0_to_1
    
    # Mix into the Dry object (which becomes the result)
    Formula: "self * " + string$(dry_Mix) + " + object[" + string$(wet_Obj) + "] * " + string$(wet_Mix)
    
    Rename: origName$ + "_MultiDist_" + replace$(presetName$, " ", "", 0)
    result = dry_Obj
    
    # CLEANUP: Remove the Wet object
    selectObject: wet_Obj
    Remove
endif

# ============================================================
# VISUALIZATION (Restored to v1.5 Style)
# ============================================================
if draw_visualization
    Erase all
    
    # === Title ===
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 11
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Multiband Distortion - " + origName$
    
    # === Original Waveform ===
    Select outer viewport: 0, 8, 0.6, 1.6
    Select inner viewport: 0.6, 7.6, 0.7, 1.5
    
    selectObject: original
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Draw inner box
    Colour: "Black"
    Font size: 9
    Text left: "yes", "Original"
    
    # === Result Waveform ===
    Select outer viewport: 0, 8, 1.7, 2.7
    Select inner viewport: 0.6, 7.6, 1.8, 2.6
    
    selectObject: result
    Colour: "{0.8, 0.3, 0.3}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Draw inner box
    Colour: "Black"
    Text left: "yes", "Processed"
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    
    # === Spectral Analysis ===
    Select outer viewport: 0, 8, 2.9, 4.8
    Select inner viewport: 0.6, 7.6, 3.1, 4.6
    
    # Get spectra
    selectObject: original
    spec_Orig = To Spectrum: "yes"
    selectObject: result
    spec_Res = To Spectrum: "yes"
    
    # Set dB range
    maxDB = 80
    minDB = 0
    
    # Determine frequency range
    maxFreq = sr / 2
    if maxFreq > 8000
        freqMax = 8000
        freqStep = 2000
    else
        freqMax = maxFreq
        freqStep = 1000
    endif
    
    Axes: 0, freqMax, minDB, maxDB
    
    # Draw Original (Grey)
    selectObject: spec_Orig
    Colour: "{0.6, 0.6, 0.6}"
    Line width: 1
    Draw: 0, freqMax, minDB, maxDB, "no"
    
    # Draw Result (Red)
    selectObject: spec_Res
    Colour: "{0.8, 0.3, 0.3}"
    Line width: 1.5
    Draw: 0, freqMax, minDB, maxDB, "no"
    Line width: 1
    
    # Draw Crossover Lines
    Colour: "{0.2, 0.6, 0.2}"
    Dotted line
    if low_Split_Hz < freqMax
        Draw line: low_Split_Hz, minDB, low_Split_Hz, maxDB
    endif
    if high_Split_Hz < freqMax
        Draw line: high_Split_Hz, minDB, high_Split_Hz, maxDB
    endif
    Solid line
    
    # Box and labels
    Colour: "Black"
    Draw inner box
    Font size: 9
    Text left: "yes", "Power (dB)"
    Marks left every: 1, 20, "yes", "yes", "no"
    Marks bottom every: 1, freqStep, "yes", "yes", "no"
    Text bottom: "yes", "Frequency (Hz)"
    
    # Crossover labels
    Font size: 8
    Colour: "{0.2, 0.6, 0.2}"
    if low_Split_Hz < freqMax
        Text: low_Split_Hz, "centre", maxDB - 8, "bottom", string$(low_Split_Hz)
    endif
    if high_Split_Hz < freqMax
        Text: high_Split_Hz, "centre", maxDB - 8, "bottom", string$(high_Split_Hz)
    endif
    
    # Cleanup Spectra
    selectObject: spec_Orig
    plusObject: spec_Res
    Remove
    
    # === Parameter Info ===
    Select outer viewport: 0, 8, 5.0, 5.4
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    
    Text: 0.5, "centre", 0.6, "half", "Preset: " + presetName$
    Text: 0.5, "centre", 0.2, "half", "Low: " + string$(low_Drive) + "x | Mid: " + string$(mid_Drive) + "x | High: " + string$(high_Drive) + "x | Mix: " + string$(round(mix_0_to_1 * 100)) + "%"
    
    Font size: 10
    Colour: "Black"
endif

# === Finalize ===
selectObject: result
if play_result
    Play
endif

writeInfoLine: "Applied Multiband Distortion to: ", origName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Splits: ", low_Split_Hz, "Hz / ", high_Split_Hz, "Hz"

# ============================================================
# PROCEDURE: Apply Distortion
# ============================================================
procedure ApplyDistortion
    d_str$ = string$(cur_drive)
    g_str$ = string$(cur_gain)
    
    if cur_type = 1
        # Soft Clip
        Formula: "tanh(self * " + d_str$ + ") * " + g_str$
        
    elsif cur_type = 2
        # Hard Clip
        in$ = "(self * " + d_str$ + ")"
        pos$ = "(" + in$ + " > 1)"
        neg$ = "(" + in$ + " < -1)"
        lin$ = "(abs(" + in$ + ") <= 1)"
        Formula: "(" + pos$ + " * 1.0 + " + neg$ + " * -1.0 + " + lin$ + " * " + in$ + ") * " + g_str$
        
    elsif cur_type = 3
        # Sine Fold
        Formula: "sin(self * " + d_str$ + ") * " + g_str$
    endif
endproc