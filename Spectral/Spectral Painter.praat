# ============================================================
# Praat AudioTools - Spectral Painter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.4 (2025)
# License: MIT License
#
# Description:
#   Comprehensive spectral gain modulation tool with multiple
#   waveform types and experimental presets. Applies periodic or
#   shaped gain patterns across the frequency spectrum.
#   Includes visualization of modulation curve and spectrum.
#
# Usage:
#   Select a Sound object in Praat and run this script.
# ============================================================

form Spectral Painter 
    comment === PRESETS ===
    optionmenu Preset: 1
        option Custom
        option Broken Radio (destroyed transmission)
        option Demon Voice (sub harmonics)
        option Glass Shatter (extreme high diffusion)
        option Black Hole (spectral vacuum)
        option Bit Rot (digital decay)
        option Insect Swarm (dense buzzing)
        option Frozen Cathedral (icy reverb texture)
        option Dying Machine (mechanical failure)
        option Quantum Tunnel (phasing voids)
        option Vocal Destroyer (formant chaos)
        option Thunder Rumble (infrasonic boost)
        option Crystal Fracture (shattered harmonics)
        option Toxic Waste (corrosive texture)
        option Ghost Signal (barely there)
        option Nuclear Meltdown (total spectral chaos)
    comment === MODULATION TYPE ===
    optionmenu Modulation_type: 1
        option Sine Wave (Linear)
        option Sine Wave (Logarithmic/Musical)
        option Triangle Wave
        option Square Wave (Stepped)
        option Sawtooth
        option Exponential
        option Logarithmic
        option Random (Per-Bin Diffusion)
        option Dual Sine (Interference)
    comment === BASIC PARAMETERS ===
    positive cutoff_frequency 15000
    positive modulation_center 1.0
    real modulation_depth 0.8
    positive modulation_frequency_divisor 150
    comment === ADVANCED ===
    real phase_offset 0.01
    positive second_divisor 300
    positive randomness_amount 0.3
    boolean warn_phase_inversion 1
    comment === VISUALIZATION ===
    boolean show_visualization 1
    comment === OUTPUT ===
    positive scale_peak 0.95
    boolean play_after_processing 1
endform

# ===== PRESET APPLICATION =====
if preset = 2
    modulation_type = 4
    modulation_center = 0.3
    modulation_depth = 1.2
    modulation_frequency_divisor = 15
    cutoff_frequency = 4000
    randomness_amount = 0.6
elsif preset = 3
    modulation_type = 6
    modulation_center = 2.5
    modulation_depth = 2.0
    modulation_frequency_divisor = 50
    cutoff_frequency = 800
elsif preset = 4
    modulation_type = 8
    modulation_center = 0.2
    modulation_depth = 1.5
    modulation_frequency_divisor = 8
    cutoff_frequency = 20000
    randomness_amount = 0.95
elsif preset = 5
    modulation_type = 4
    modulation_center = 0.1
    modulation_depth = 0.9
    modulation_frequency_divisor = 80
    cutoff_frequency = 16000
elsif preset = 6
    modulation_type = 4
    modulation_center = 0.5
    modulation_depth = -0.8
    modulation_frequency_divisor = 25
    cutoff_frequency = 12000
elsif preset = 7
    modulation_type = 9
    modulation_center = 0.6
    modulation_depth = 0.9
    modulation_frequency_divisor = 12
    second_divisor = 13
    cutoff_frequency = 18000
elsif preset = 8
    modulation_type = 2
    modulation_center = 0.4
    modulation_depth = 0.8
    modulation_frequency_divisor = 300
    cutoff_frequency = 20000
    phase_offset = 1.57
elsif preset = 9
    modulation_type = 5
    modulation_center = 0.7
    modulation_depth = -1.2
    modulation_frequency_divisor = 35
    cutoff_frequency = 6000
elsif preset = 10
    modulation_type = 9
    modulation_center = 0.0
    modulation_depth = 1.0
    modulation_frequency_divisor = 100
    second_divisor = 103
    cutoff_frequency = 15000
elsif preset = 11
    modulation_type = 8
    modulation_center = 0.5
    modulation_depth = 1.8
    modulation_frequency_divisor = 40
    cutoff_frequency = 5000
    randomness_amount = 0.7
elsif preset = 12
    modulation_type = 6
    modulation_center = 3.0
    modulation_depth = 2.5
    modulation_frequency_divisor = 20
    cutoff_frequency = 200
elsif preset = 13
    modulation_type = 4
    modulation_center = 0.3
    modulation_depth = 1.5
    modulation_frequency_divisor = 7
    cutoff_frequency = 16000
elsif preset = 14
    modulation_type = 8
    modulation_center = 0.6
    modulation_depth = -1.0
    modulation_frequency_divisor = 18
    cutoff_frequency = 10000
    randomness_amount = 0.85
elsif preset = 15
    modulation_type = 1
    modulation_center = 0.05
    modulation_depth = 0.1
    modulation_frequency_divisor = 500
    cutoff_frequency = 8000
elsif preset = 16
    modulation_type = 8
    modulation_center = 0.0
    modulation_depth = 2.0
    modulation_frequency_divisor = 5
    cutoff_frequency = 20000
    randomness_amount = 1.0
endif

# ===== SAFETY CHECK =====
if warn_phase_inversion
    min_gain = modulation_center - abs(modulation_depth)
    if min_gain < 0
        beginPause: "Phase Inversion Warning"
            comment: "Gain goes negative - creates hollow/inverted sound."
        clicked = endPause: "Abort", "Continue", 2
        if clicked = 1
            exitScript: "Aborted by user."
        endif
    endif
endif

# ===== PROCESSING =====
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")
selectObject: originalID
original_sr = Get sampling frequency
duration = Get total duration
n_channels = Get number of channels
nyquist = original_sr / 2

writeInfoLine: "=== Spectral Painter ==="
appendInfoLine: "Preset: ", preset
appendInfoLine: "Type: ", modulation_type
appendInfoLine: "Center: ", modulation_center, " | Depth: ", modulation_depth
appendInfoLine: ""

# Convert to mono
selectObject: originalID
if n_channels > 1
    workingID = Convert to mono
else
    workingID = Copy: "working"
endif

# To Spectrum (keep original for comparison)
selectObject: workingID
origSpecID = To Spectrum: "yes"
Rename: "original_spectrum"

# Copy for processing
selectObject: origSpecID
specID = Copy: "processed_spectrum"

# Build formula strings
cutStr$ = fixed$(cutoff_frequency, 0)
cenStr$ = fixed$(modulation_center, 4)
depStr$ = fixed$(modulation_depth, 4)
divStr$ = fixed$(modulation_frequency_divisor, 2)
phsStr$ = fixed$(phase_offset, 4)
secStr$ = fixed$(second_divisor, 2)
rndStr$ = fixed$(randomness_amount, 4)

# Get modulation type name for display
if modulation_type = 1
    modName$ = "Sine (Linear)"
elsif modulation_type = 2
    modName$ = "Sine (Log)"
elsif modulation_type = 3
    modName$ = "Triangle"
elsif modulation_type = 4
    modName$ = "Square"
elsif modulation_type = 5
    modName$ = "Sawtooth"
elsif modulation_type = 6
    modName$ = "Exponential"
elsif modulation_type = 7
    modName$ = "Logarithmic"
elsif modulation_type = 8
    modName$ = "Random"
else
    modName$ = "Dual Sine"
endif

selectObject: specID

if modulation_type = 1
    Formula: "if x < " + cutStr$ + " then self * (" + cenStr$ + " + " + depStr$ + " * sin(x / " + divStr$ + " + " + phsStr$ + ")) else self fi"
elsif modulation_type = 2
    density$ = fixed$(modulation_frequency_divisor / 10, 2)
    Formula: "if x < " + cutStr$ + " and x > 1 then self * (" + cenStr$ + " + " + depStr$ + " * sin(ln(x) * " + density$ + " + " + phsStr$ + ")) else self fi"
elsif modulation_type = 3
    Formula: "if x < " + cutStr$ + " then self * (" + cenStr$ + " + " + depStr$ + " * (2 * abs((x / " + divStr$ + ") - floor((x / " + divStr$ + ") + 0.5)) - 1)) else self fi"
elsif modulation_type = 4
    Formula: "if x < " + cutStr$ + " then self * (" + cenStr$ + " + " + depStr$ + " * (if sin(x / " + divStr$ + ") > 0 then 1 else -1 fi)) else self fi"
elsif modulation_type = 5
    Formula: "if x < " + cutStr$ + " then self * (" + cenStr$ + " + " + depStr$ + " * (2 * ((x / " + divStr$ + ") - floor((x / " + divStr$ + ") + 0.5)))) else self fi"
elsif modulation_type = 6
    Formula: "if x < " + cutStr$ + " then self * (" + cenStr$ + " + " + depStr$ + " * exp(-x / " + divStr$ + ")) else self fi"
elsif modulation_type = 7
    Formula: "if x < " + cutStr$ + " and x > 1 then self * (" + cenStr$ + " + " + depStr$ + " * ln(1 + x / " + divStr$ + ")) else self fi"
elsif modulation_type = 8
    Formula: "if x < " + cutStr$ + " then self * (" + cenStr$ + " + " + depStr$ + " * (sin(x / " + divStr$ + ") + " + rndStr$ + " * randomGauss(0, 1))) else self fi"
else
    Formula: "if x < " + cutStr$ + " then self * (" + cenStr$ + " + " + depStr$ + " * (sin(x / " + divStr$ + ") + 0.5 * sin(x / " + secStr$ + ")) / 1.5) else self fi"
endif

appendInfoLine: "Applied: ", modName$

# ===== VISUALIZATION =====
if show_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    Font size: 11
    Line width: 1
    
    # Calculate gain range for Y axis
    minGain = modulation_center - abs(modulation_depth) - 0.3
    maxGain = modulation_center + abs(modulation_depth) + 0.3
    if minGain > -0.5
        minGain = -0.5
    endif
    if maxGain < 2
        maxGain = 2
    endif
    
    # === PANEL 1: MODULATION CURVE ===
    Select outer viewport: 0, 6, 0, 3
    Axes: 0, cutoff_frequency, minGain, maxGain
    
    Draw inner box
    Marks left every: 1, 0.5, "yes", "yes", "no"
    Marks bottom every: 1, 2000, "yes", "yes", "no"
    
    # Reference lines
    Colour: "{0.8, 0.8, 0.8}"
    Draw line: 0, 1, cutoff_frequency, 1
    
    # Zero line (pink if gain goes negative)
    if minGain < 0
        Colour: "{1, 0.7, 0.7}"
        Line width: 2
        Draw line: 0, 0, cutoff_frequency, 0
        Line width: 1
    endif
    
    # Draw modulation curve
    Colour: "Blue"
    Line width: 2
    
    numPoints = 500
    freqStep = cutoff_frequency / numPoints
    
    for i from 1 to numPoints
        freq = (i - 1) * freqStep + 1
        
        if modulation_type = 1
            gain = modulation_center + modulation_depth * sin(freq / modulation_frequency_divisor + phase_offset)
        elsif modulation_type = 2
            if freq > 1
                density = modulation_frequency_divisor / 10
                gain = modulation_center + modulation_depth * sin(ln(freq) * density + phase_offset)
            else
                gain = modulation_center
            endif
        elsif modulation_type = 3
            gain = modulation_center + modulation_depth * (2 * abs((freq / modulation_frequency_divisor) - floor((freq / modulation_frequency_divisor) + 0.5)) - 1)
        elsif modulation_type = 4
            if sin(freq / modulation_frequency_divisor) > 0
                gain = modulation_center + modulation_depth
            else
                gain = modulation_center - modulation_depth
            endif
        elsif modulation_type = 5
            gain = modulation_center + modulation_depth * (2 * ((freq / modulation_frequency_divisor) - floor((freq / modulation_frequency_divisor) + 0.5)))
        elsif modulation_type = 6
            gain = modulation_center + modulation_depth * exp(-freq / modulation_frequency_divisor)
        elsif modulation_type = 7
            if freq > 1
                gain = modulation_center + modulation_depth * ln(1 + freq / modulation_frequency_divisor)
            else
                gain = modulation_center
            endif
        elsif modulation_type = 8
            gain = modulation_center + modulation_depth * sin(freq / modulation_frequency_divisor)
        else
            gain = modulation_center + modulation_depth * (sin(freq / modulation_frequency_divisor) + 0.5 * sin(freq / second_divisor)) / 1.5
        endif
        
        if i = 1
            prevFreq = freq
            prevGain = gain
        else
            Draw line: prevFreq, prevGain, freq, gain
            prevFreq = freq
            prevGain = gain
        endif
    endfor
    
    # Cutoff marker (dotted)
    Colour: "Red"
    Line width: 1
    dashLen = (maxGain - minGain) / 20
    for d from 0 to 9
        y1 = minGain + d * 2 * dashLen
        y2 = y1 + dashLen
        if y2 > maxGain
            y2 = maxGain
        endif
        Draw line: cutoff_frequency, y1, cutoff_frequency, y2
    endfor
    
    Colour: "Black"
    Line width: 1
    Font size: 12
    Text top: "yes", "##Modulation: " + modName$ + "##  |  Cutoff: " + string$(cutoff_frequency) + " Hz"
    Font size: 10
    Text left: "yes", "Gain"
    Text bottom: "yes", "Frequency (Hz)"
    
    # === PANEL 2: ORIGINAL SPECTRUM ===
    Select outer viewport: 0, 6, 3, 5.5
    selectObject: origSpecID
    Colour: "{0.3, 0.3, 0.8}"
    Draw: 0, 0, 0, 80, "no"
    Draw inner box
    Marks left every: 1, 20, "yes", "yes", "no"
    Marks bottom every: 1, 2000, "yes", "yes", "no"
    Colour: "Black"
    Font size: 11
    Text top: "yes", "Original Spectrum"
    Font size: 10
    Text left: "yes", "dB"
    Text bottom: "yes", "Frequency (Hz)"
    
    # === PANEL 3: PROCESSED SPECTRUM ===
    Select outer viewport: 0, 6, 5.5, 8
    selectObject: specID
    Colour: "{0.8, 0.3, 0.3}"
    Draw: 0, 0, 0, 80, "no"
    Draw inner box
    Marks left every: 1, 20, "yes", "yes", "no"
    Marks bottom every: 1, 2000, "yes", "yes", "no"
    Colour: "Black"
    Font size: 11
    Text top: "yes", "Processed Spectrum"
    Font size: 10
    Text left: "yes", "dB"
    Text bottom: "yes", "Frequency (Hz)"
    
    # === PANEL 4: INFO ===
    Select outer viewport: 0, 6, 8, 9
    Axes: 0, 10, 0, 1
    
    Font size: 10
    Colour: "Black"
    
    info1$ = "Center: " + fixed$(modulation_center, 2) + "  |  Depth: " + fixed$(modulation_depth, 2) + "  |  Divisor: " + string$(modulation_frequency_divisor)
    info2$ = "Gain range: " + fixed$(modulation_center - abs(modulation_depth), 2) + " to " + fixed$(modulation_center + abs(modulation_depth), 2)
    
    if modulation_center - abs(modulation_depth) < 0
        info2$ = info2$ + "  ##[PHASE INVERSION]##"
        Colour: "Red"
    endif
    
    Text: 0.2, "left", 0.65, "half", info1$
    Text: 0.2, "left", 0.25, "half", info2$
    
    Font size: 12
    appendInfoLine: "Visualization complete."
endif

# Back to Sound
selectObject: specID
resultID = To Sound

# Trim
selectObject: resultID
resultDur = Get total duration
if resultDur > duration
    trimmed = Extract part: 0, duration, "rectangular", 1, "no"
    removeObject: resultID
    resultID = trimmed
endif

selectObject: resultID
Rename: originalName$ + "_painted"
Scale peak: scale_peak

# Cleanup
removeObject: workingID, origSpecID, specID

appendInfoLine: ""
appendInfoLine: "Complete!"

selectObject: resultID
if play_after_processing
    Play
endif