# ============================================================
# Praat AudioTools - Hysteresis_Distortion.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Hysteresis Distortion - applies nonlinear distortion with
#   state memory. Simulates magnetic tape saturation, transformer
#   core lag, and analog circuit inertia.
#   
#   Formula: y[n] = (1-mem) * tanh(drive * (x[n]+bias)) + mem * y[n-1]
#
# Changelog v0.2:
#   - Added transfer function visualization
#   - Improved info output
#   - Minor code cleanup
# ============================================================

# === Form ===
form Hysteresis Distortion
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Manual (use settings below)
        option Warm Tape Saturation
        option Dark Transformer
        option Offset Magnetics
        option Sluggish Fuzz
        option Infinite Sustain (Limiter)

    comment === Parameters ===
    real Drive 2.0
    comment (1=subtle, 5=moderate, 10+=heavy)
    real Hysteresis_Memory 0.3
    comment (0=no memory, 0.9=heavy lag)
    real Asymmetry_Bias 0.0
    comment (0=symmetric, ±0.3=asymmetric)
    real Output_Gain 0.9

    comment === Output ===
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
    presetName$ = "WarmTape"
    drive = 1.5
    hysteresis_Memory = 0.25
    asymmetry_Bias = 0.0
    output_Gain = 0.95
elsif preset = 3
    presetName$ = "DarkTransformer"
    drive = 2.5
    hysteresis_Memory = 0.75
    asymmetry_Bias = 0.0
    output_Gain = 0.8
elsif preset = 4
    presetName$ = "OffsetMagnetics"
    drive = 3.0
    hysteresis_Memory = 0.4
    asymmetry_Bias = 0.2
    output_Gain = 0.8
elsif preset = 5
    presetName$ = "SluggishFuzz"
    drive = 10.0
    hysteresis_Memory = 0.5
    asymmetry_Bias = 0.05
    output_Gain = 0.5
elsif preset = 6
    presetName$ = "InfiniteSustain"
    drive = 20.0
    hysteresis_Memory = 0.1
    asymmetry_Bias = 0.0
    output_Gain = 0.4
endif

# Safety Check - memory must be < 1 for stability
if hysteresis_Memory >= 1.0
    hysteresis_Memory = 0.99
endif
if hysteresis_Memory < 0
    hysteresis_Memory = 0
endif

# === Info ===
writeInfoLine: "=== Hysteresis Distortion ==="
appendInfoLine: "Source: ", origName$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Drive: ", drive
appendInfoLine: "Memory: ", hysteresis_Memory
appendInfoLine: "Bias: ", asymmetry_Bias
appendInfoLine: "Output gain: ", output_Gain
appendInfoLine: ""

# ============================================================
# PROCESSING: Hysteresis Loop
# ============================================================

appendInfoLine: "Applying hysteresis distortion..."

selectObject: original
Copy: origName$ + "_Hyst_" + presetName$
result = selected("Sound")

# Build formula strings for the recursive processing
# The Math:
#   Nonlinear Input = tanh((Input + Bias) * Drive)
#   Output = (Nonlinear * (1-Mem)) + (PreviousOutput * Mem)

d_str$ = string$(drive)
m_str$ = string$(hysteresis_Memory)
inv_m_str$ = string$(1.0 - hysteresis_Memory)
b_str$ = string$(asymmetry_Bias)

# Define the nonlinear component
nonlin$ = "tanh((self + " + b_str$ + ") * " + d_str$ + ")"

# Define the recursive formula
# col=1 has no previous sample, so just use nonlinear
formula$ = "if col = 1 then " + nonlin$ + " else (" + nonlin$ + " * " + inv_m_str$ + ") + (self[col-1] * " + m_str$ + ") fi"

# Apply Hysteresis
Formula: formula$

# Post-Processing
Subtract mean
Formula: ~ self * output_Gain

# Scale to prevent clipping
Scale peak: 0.95

# ============================================================
# VISUALIZATION
# ============================================================
if draw_visualization
    Erase all
    
    # === Title ===
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 11
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Hysteresis Distortion: " + origName$ + " (" + presetName$ + ")"
    
    # === Original Waveform ===
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.6, 0.7, 1.4
    
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # === Result Waveform ===
    Select outer viewport: 0, 8, 1.6, 2.5
    Select inner viewport: 0.6, 7.6, 1.7, 2.4
    
    selectObject: result
    Colour: "{0.8, 0.4, 0.4}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Distorted"
    Text bottom: "yes", "Time (s)"
    
    # === Transfer Function (tanh curve) ===
    Select outer viewport: 0, 4, 2.7, 4.2
    Select inner viewport: 0.6, 3.8, 2.8, 4.1
    
    Axes: -1.2, 1.2, -1.2, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", -1.2, 1.2, -1.2, 1.2
    
    # Grid
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: -1.2, 0, 1.2, 0
    Draw line: 0, -1.2, 0, 1.2
    Dotted line
    Draw line: -1, -1, 1, 1
    Solid line
    
    # Draw tanh transfer curve
    Colour: "{0.8, 0.4, 0.4}"
    Line width: 2
    nPoints = 100
    for p from 2 to nPoints
        x1 = -1.0 + (p - 2) / nPoints * 2.0
        x2 = -1.0 + (p - 1) / nPoints * 2.0
        y1 = tanh((x1 + asymmetry_Bias) * drive)
        y2 = tanh((x2 + asymmetry_Bias) * drive)
        Draw line: x1, y1, x2, y2
    endfor
    Line width: 1
    
    # Show saturation limits
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: -1.2, 1, 1.2, 1
    Draw line: -1.2, -1, 1.2, -1
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Output"
    Text bottom: "yes", "Input"
    Text: 0, "centre", 1.35, "half", "Transfer: tanh(drive×x)"
    
    # === Hysteresis Loop Visualization ===
    Select outer viewport: 4, 8, 2.7, 4.2
    Select inner viewport: 4.4, 7.6, 2.8, 4.1
    
    Axes: -1.2, 1.2, -1.2, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", -1.2, 1.2, -1.2, 1.2
    
    # Grid
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: -1.2, 0, 1.2, 0
    Draw line: 0, -1.2, 0, 1.2
    
    # Simulate hysteresis loop (ascending and descending paths differ)
    # This is a simplified visualization showing the lag effect
    Colour: "{0.4, 0.4, 0.8}"
    Line width: 1.5
    
    # Ascending path
    prevY = 0
    for p from 1 to nPoints
        x = -1.0 + (p - 1) / nPoints * 2.0
        newInput = tanh((x + asymmetry_Bias) * drive)
        y = (1 - hysteresis_Memory) * newInput + hysteresis_Memory * prevY
        if p > 1
            prevX = -1.0 + (p - 2) / nPoints * 2.0
            Draw line: prevX, prevY, x, y
        endif
        prevY = y
    endfor
    
    # Descending path (different due to memory)
    Colour: "{0.8, 0.4, 0.4}"
    for p from 1 to nPoints
        x = 1.0 - (p - 1) / nPoints * 2.0
        newInput = tanh((x + asymmetry_Bias) * drive)
        y = (1 - hysteresis_Memory) * newInput + hysteresis_Memory * prevY
        if p > 1
            prevX = 1.0 - (p - 2) / nPoints * 2.0
            Draw line: prevX, prevY, x, y
        endif
        prevY = y
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Output"
    Text bottom: "yes", "Input"
    Text: 0, "centre", 1.35, "half", "Hysteresis Loop (mem=" + fixed$(hysteresis_Memory, 2) + ")"
    
    # === Spectral Analysis ===
    Select outer viewport: 0, 8, 4.4, 5.6
    Select inner viewport: 0.6, 7.6, 4.5, 5.5
    
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
    else
        freqMax = maxFreq
    endif
    
    Axes: 0, freqMax, minDB, maxDB
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, freqMax, minDB, maxDB
    
    # Draw Original (Grey)
    selectObject: spec_Orig
    Colour: "{0.6, 0.6, 0.6}"
    Line width: 1
    Draw: 0, freqMax, minDB, maxDB, "no"
    
    # Draw Result (Red)
    selectObject: spec_Res
    Colour: "{0.8, 0.4, 0.4}"
    Line width: 1.5
    Draw: 0, freqMax, minDB, maxDB, "no"
    Line width: 1
    
    # Box and labels
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "dB"
    Text bottom: "yes", "Frequency (Hz)"
    
    # Cleanup Spectra
    removeObject: spec_Orig, spec_Res
    
    # === Parameter Info ===
    Select outer viewport: 0, 8, 5.7, 6.1
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    
    Text: 0.5, "centre", 0.5, "half", "Drive: " + fixed$(drive, 1) + " | Memory: " + fixed$(hysteresis_Memory, 2) + " | Bias: " + fixed$(asymmetry_Bias, 2) + " | Gain: " + fixed$(output_Gain, 2)
    
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
