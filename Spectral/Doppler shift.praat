# ============================================================
# Praat AudioTools - Doppler_shift.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Fixed syntax, added visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Simulates Doppler effect - accelerating pitch shift with
#   amplitude decay as sound source passes by.
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

form Doppler Shift Effect v0.2
    optionmenu Preset: 1
        option Custom
        option Passing Car
        option Passing Train
        option Flyby (fast)
        option Subtle Approach
        option Heavy Decay
        option Sci-Fi Whoosh
        option Reverse Doppler
        option Ambulance Siren
    comment === Pitch Shift ===
    positive Base_shift 1.0
    positive Shift_amount 0.5
    comment (Total shift range: base to base+amount)
    positive Acceleration 2
    comment (Higher = more dramatic acceleration)
    comment === Distance Decay ===
    positive Decay_amount 15
    comment (Simulates amplitude loss with distance)
    comment === Output ===
    positive Scale_peak 0.99
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================

if preset = 2
    # Passing Car
    base_shift = 1.0
    shift_amount = 0.4
    acceleration = 2
    decay_amount = 12
    presetName$ = "PassingCar"
elsif preset = 3
    # Passing Train
    base_shift = 1.0
    shift_amount = 0.3
    acceleration = 1.5
    decay_amount = 8
    presetName$ = "PassingTrain"
elsif preset = 4
    # Flyby (fast)
    base_shift = 1.0
    shift_amount = 0.8
    acceleration = 4
    decay_amount = 20
    presetName$ = "Flyby"
elsif preset = 5
    # Subtle Approach
    base_shift = 1.0
    shift_amount = 0.2
    acceleration = 1.5
    decay_amount = 5
    presetName$ = "SubtleApproach"
elsif preset = 6
    # Heavy Decay
    base_shift = 1.0
    shift_amount = 0.5
    acceleration = 2
    decay_amount = 30
    presetName$ = "HeavyDecay"
elsif preset = 7
    # Sci-Fi Whoosh
    base_shift = 0.8
    shift_amount = 1.2
    acceleration = 3
    decay_amount = 25
    presetName$ = "SciFiWhoosh"
elsif preset = 8
    # Reverse Doppler (approaching)
    base_shift = 1.5
    shift_amount = -0.5
    acceleration = 2
    decay_amount = -10
    presetName$ = "ReverseDoppler"
elsif preset = 9
    # Ambulance Siren
    base_shift = 1.0
    shift_amount = 0.35
    acceleration = 2.5
    decay_amount = 15
    presetName$ = "Ambulance"
else
    presetName$ = "Custom"
endif

# ============================================================
# SETUP
# ============================================================

selectObject: originalID
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels

clearinfo
writeInfoLine: "=== Doppler Shift Effect v0.2 ==="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Duration: ", fixed$(duration, 3), " s"
appendInfoLine: ""
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Base shift: ", base_shift
appendInfoLine: "Shift amount: ", shift_amount
appendInfoLine: "Acceleration: ", acceleration
appendInfoLine: "Decay: ", decay_amount
appendInfoLine: ""

# ============================================================
# PROCESS
# ============================================================

appendInfo: "Processing..."

selectObject: originalID
workingID = Copy: originalName$ + "_doppler_" + presetName$

# Build formula strings
baseStr$ = fixed$(base_shift, 6)
amountStr$ = fixed$(shift_amount, 6)
accelStr$ = fixed$(acceleration, 6)
decayStr$ = fixed$(decay_amount, 6)

# Apply Doppler shift with accelerating frequency change
# Reads samples at time-varying offsets (creates pitch shift)
# shift = base + amount * (normalized_time ^ acceleration)
selectObject: workingID
Formula: "self[col / (" + baseStr$ + " + " + amountStr$ + " * ((x - xmin) / (xmax - xmin))^" + accelStr$ + ")] - self[col * (" + baseStr$ + " + " + amountStr$ + " * ((x - xmin) / (xmax - xmin))^" + accelStr$ + ")]"

# Apply exponential decay (distance effect)
# Amplitude decreases as sound "passes by"
selectObject: workingID
Formula: "self * " + decayStr$ + "^(-(x - xmin) / (xmax - xmin))"

# Scale to peak
selectObject: workingID
Scale peak: scale_peak

appendInfoLine: " done"

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Doppler Shift: " + originalName$ + " [" + presetName$ + "]"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 2.0
    Select inner viewport: 0.6, 7.6, 0.75, 1.85
    
    selectObject: originalID
    Colour: "{0.7, 0.7, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 9
    Text top: "no", "Original"
    Text left: "yes", "Amp"
    
    # Processed waveform
    Select outer viewport: 0, 8, 2.1, 3.5
    Select inner viewport: 0.6, 7.6, 2.25, 3.35
    
    selectObject: workingID
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text top: "no", "With Doppler Effect"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # Pitch shift curve
    Select outer viewport: 0, 4, 3.7, 5.4
    Select inner viewport: 0.6, 3.6, 3.9, 5.2
    
    # Calculate shift range for axis
    minShift = base_shift
    maxShift = base_shift + abs(shift_amount)
    if shift_amount < 0
        minShift = base_shift + shift_amount
        maxShift = base_shift
    endif
    
    Axes: 0, duration, minShift - 0.1, maxShift + 0.1
    
    # Draw pitch shift curve
    Colour: "{0.9, 0.4, 0.2}"
    Line width: 3
    
    numPoints = 200
    for i from 0 to numPoints - 1
        t1 = duration * i / numPoints
        t2 = duration * (i + 1) / numPoints
        
        norm1 = t1 / duration
        norm2 = t2 / duration
        
        shift1 = base_shift + shift_amount * (norm1 ^ acceleration)
        shift2 = base_shift + shift_amount * (norm2 ^ acceleration)
        
        Draw line: t1, shift1, t2, shift2
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Pitch Shift Factor"
    Text left: "yes", "Shift"
    Text bottom: "yes", "Time (s)"
    
    # Decay curve
    Select outer viewport: 4, 8, 3.7, 5.4
    Select inner viewport: 4.6, 7.6, 3.9, 5.2
    
    Axes: 0, duration, 0, 1.1
    
    # Draw decay curve
    Colour: "{0.2, 0.7, 0.4}"
    Line width: 3
    
    for i from 0 to numPoints - 1
        t1 = duration * i / numPoints
        t2 = duration * (i + 1) / numPoints
        
        norm1 = t1 / duration
        norm2 = t2 / duration
        
        dec1 = decay_amount ^ (-norm1)
        dec2 = decay_amount ^ (-norm2)
        
        # Clamp to visible range
        if dec1 > 1
            dec1 = 1
        endif
        if dec2 > 1
            dec2 = 1
        endif
        if dec1 < 0
            dec1 = 0
        endif
        if dec2 < 0
            dec2 = 0
        endif
        
        Draw line: t1, dec1, t2, dec2
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Amplitude Decay"
    Text left: "yes", "Gain"
    Text bottom: "yes", "Time (s)"
    
    # Info panel
    Select outer viewport: 0, 8, 5.5, 6.1
    Select inner viewport: 0.5, 7.7, 5.55, 6.05
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.5, "half", "Base: " + fixed$(base_shift, 2)
    Text: 0.18, "left", 0.5, "half", "Amount: " + fixed$(shift_amount, 2)
    Text: 0.38, "left", 0.5, "half", "Accel: " + fixed$(acceleration, 1)
    Text: 0.55, "left", 0.5, "half", "Decay: " + fixed$(decay_amount, 0)
    Text: 0.72, "left", 0.5, "half", "Range: " + fixed$(minShift, 2) + "→" + fixed$(maxShift, 2)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
endif

# ============================================================
# OUTPUT
# ============================================================

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: ""
appendInfoLine: "Created: ", originalName$, "_doppler_", presetName$

if play_result
    selectObject: workingID
    Play
endif
