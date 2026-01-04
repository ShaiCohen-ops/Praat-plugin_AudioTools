# ============================================================
# Praat AudioTools - Hysteresis Distortion
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Applies nonlinear distortion with state memory (Hysteresis).
#   Simulates magnetic tape saturation, transformer core lag, 
#   and analog circuit inertia.
#   Math: y[n] = (1-mem) * tanh(drive * x[n]) + mem * y[n-1]
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# === Form ===
form Hysteresis Distortion
    comment Select a Preset
    optionmenu Preset 1
        option Manual
        option Warm Tape Saturation
        option Dark Transformer
        option Offset Magnetics
        option Sluggish Fuzz
        option Infinite Sustain (Limiter)

    comment Parameters
    real Drive 2.0
    real Hysteresis_Memory 0.3
    real Asymmetry_Bias 0.0
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
    presetName$ = "Warm Tape Saturation"
    drive = 1.5
    hysteresis_Memory = 0.25
    asymmetry_Bias = 0.0
    output_Gain = 0.95
elsif preset = 3
    presetName$ = "Dark Transformer"
    drive = 2.5
    hysteresis_Memory = 0.75
    asymmetry_Bias = 0.0
    output_Gain = 0.8
elsif preset = 4
    presetName$ = "Offset Magnetics"
    drive = 3.0
    hysteresis_Memory = 0.4
    asymmetry_Bias = 0.2
    output_Gain = 0.8
elsif preset = 5
    presetName$ = "Sluggish Fuzz"
    drive = 10.0
    hysteresis_Memory = 0.5
    asymmetry_Bias = 0.05
    output_Gain = 0.5
elsif preset = 6
    presetName$ = "Infinite Sustain"
    drive = 20.0
    hysteresis_Memory = 0.1
    asymmetry_Bias = 0.0
    output_Gain = 0.4
endif

# Safety Check
if hysteresis_Memory >= 1.0
    hysteresis_Memory = 0.99
endif

# === Setup ===
original = selected("Sound")
origName$ = selected$("Sound")
selectObject: original
xmin = Get start time
xmax = Get end time
sr = Get sampling frequency

# ============================================================
# PROCESSING: Hysteresis Loop
# ============================================================

selectObject: original
Copy: origName$ + "_Hyst_" + replace$(presetName$, " ", "", 0)
result = selected("Sound")

# Variables for formula
d_str$ = string$(drive)
m_str$ = string$(hysteresis_Memory)
inv_m_str$ = string$(1.0 - hysteresis_Memory)
b_str$ = string$(asymmetry_Bias)

# The Math:
# Nonlinear Input = tanh((Input + Bias) * Drive)
# Output = (Nonlinear * (1-Mem)) + (PreviousOutput * Mem)

# 1. Define the Nonlinear component (Current Input Shaping)
nonlin$ = "tanh((self + " + b_str$ + ") * " + d_str$ + ")"

# 2. Define the Recursive component (Previous Output)
# "if col = 1" handles the edge case of the first sample (where col-1 doesn't exist)
# For col > 1, we blend the nonlinear input with the previous output (self[col-1])
formula$ = "if col = 1 then " + nonlin$ + " else (" + nonlin$ + " * " + inv_m_str$ + ") + (self[col-1] * " + m_str$ + ") fi"

# Apply Hysteresis
Formula: formula$

# 3. Post-Processing
Subtract mean
Formula: "self * " + string$(output_Gain)

# ============================================================
# VISUALIZATION (Clean Style from Multiband v2.1)
# ============================================================
if draw_visualization
    Erase all
    
    # === Title ===
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 11
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Hysteresis Distortion - " + origName$
    
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
    
    # Box and labels
    Colour: "Black"
    Draw inner box
    Font size: 9
    Text left: "yes", "Power (dB)"
    Marks left every: 1, 20, "yes", "yes", "no"
    Marks bottom every: 1, freqStep, "yes", "yes", "no"
    Text bottom: "yes", "Frequency (Hz)"
    
    # Cleanup Spectra
    selectObject: spec_Orig
    plusObject: spec_Res
    Remove
    
    # === Parameter Info ===
    Select outer viewport: 0, 8, 5.0, 5.4
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    
    Text: 0.5, "centre", 0.6, "half", "Preset: " + presetName$
    Text: 0.5, "centre", 0.2, "half", "Drive: " + string$(drive) + " | Memory: " + string$(hysteresis_Memory) + " | Bias: " + string$(asymmetry_Bias)
    
    Font size: 10
    Colour: "Black"
endif

# === Finalize ===
selectObject: result
if play_result
    Play
endif

writeInfoLine: "Applied Hysteresis Distortion to: ", origName$
appendInfoLine: "Preset: ", presetName$

# === Final Cleanup ===
# Since we only created 'result' and spectrum helpers (which are deleted),
# we just need to select the right objects at the end.
