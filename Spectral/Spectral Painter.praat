# ============================================================
# Praat AudioTools - Spectral Painter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Comprehensive spectral gain modulation
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
# ============================================================

form Spectral Painter v1.0 (Optimized)
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
    comment === PERFORMANCE ===
    optionmenu Speed_mode: 2
        option Full Quality (original sample rate)
        option Balanced (downsample to 22 kHz)
        option Fast (downsample to 11 kHz)
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
    comment === MIX ===
    real wet_dry_percent 100
    boolean stereo_output 1
    comment === VISUALIZATION ===
    boolean show_visualization 1
    comment === OUTPUT ===
    positive scale_peak 0.95
    boolean play_after_processing 1
endform

# ===== PRESET APPLICATION =====
presetName$ = "Custom"

if preset = 2
    modulation_type = 4
    modulation_center = 0.3
    modulation_depth = 1.2
    modulation_frequency_divisor = 15
    cutoff_frequency = 4000
    randomness_amount = 0.6
    presetName$ = "BrokenRadio"
elsif preset = 3
    modulation_type = 6
    modulation_center = 2.5
    modulation_depth = 2.0
    modulation_frequency_divisor = 50
    cutoff_frequency = 800
    presetName$ = "DemonVoice"
elsif preset = 4
    modulation_type = 8
    modulation_center = 0.2
    modulation_depth = 1.5
    modulation_frequency_divisor = 8
    cutoff_frequency = 20000
    randomness_amount = 0.95
    presetName$ = "GlassShatter"
elsif preset = 5
    modulation_type = 4
    modulation_center = 0.1
    modulation_depth = 0.9
    modulation_frequency_divisor = 80
    cutoff_frequency = 16000
    presetName$ = "BlackHole"
elsif preset = 6
    modulation_type = 4
    modulation_center = 0.5
    modulation_depth = -0.8
    modulation_frequency_divisor = 25
    cutoff_frequency = 12000
    presetName$ = "BitRot"
elsif preset = 7
    modulation_type = 9
    modulation_center = 0.6
    modulation_depth = 0.9
    modulation_frequency_divisor = 12
    second_divisor = 13
    cutoff_frequency = 18000
    presetName$ = "InsectSwarm"
elsif preset = 8
    modulation_type = 2
    modulation_center = 0.4
    modulation_depth = 0.8
    modulation_frequency_divisor = 300
    cutoff_frequency = 20000
    phase_offset = 1.57
    presetName$ = "FrozenCathedral"
elsif preset = 9
    modulation_type = 5
    modulation_center = 0.7
    modulation_depth = -1.2
    modulation_frequency_divisor = 35
    cutoff_frequency = 6000
    presetName$ = "DyingMachine"
elsif preset = 10
    modulation_type = 9
    modulation_center = 0.0
    modulation_depth = 1.0
    modulation_frequency_divisor = 100
    second_divisor = 103
    cutoff_frequency = 15000
    presetName$ = "QuantumTunnel"
elsif preset = 11
    modulation_type = 8
    modulation_center = 0.5
    modulation_depth = 1.8
    modulation_frequency_divisor = 40
    cutoff_frequency = 5000
    randomness_amount = 0.7
    presetName$ = "VocalDestroyer"
elsif preset = 12
    modulation_type = 6
    modulation_center = 3.0
    modulation_depth = 2.5
    modulation_frequency_divisor = 20
    cutoff_frequency = 200
    presetName$ = "ThunderRumble"
elsif preset = 13
    modulation_type = 4
    modulation_center = 0.3
    modulation_depth = 1.5
    modulation_frequency_divisor = 7
    cutoff_frequency = 16000
    presetName$ = "CrystalFracture"
elsif preset = 14
    modulation_type = 8
    modulation_center = 0.6
    modulation_depth = -1.0
    modulation_frequency_divisor = 18
    cutoff_frequency = 10000
    randomness_amount = 0.85
    presetName$ = "ToxicWaste"
elsif preset = 15
    modulation_type = 1
    modulation_center = 0.05
    modulation_depth = 0.1
    modulation_frequency_divisor = 500
    cutoff_frequency = 8000
    presetName$ = "GhostSignal"
elsif preset = 16
    modulation_type = 8
    modulation_center = 0.0
    modulation_depth = 2.0
    modulation_frequency_divisor = 5
    cutoff_frequency = 20000
    randomness_amount = 1.0
    presetName$ = "NuclearMeltdown"
endif

# Set target sample rate
if speed_mode = 1
    targetSR = 0
    speedStr$ = "Full Quality"
elsif speed_mode = 2
    targetSR = 22050
    speedStr$ = "Balanced"
else
    targetSR = 11025
    speedStr$ = "Fast"
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

wet_dry_percent = max(0, min(100, wet_dry_percent))
wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

startTime = stopwatch

writeInfoLine: "╔══════════════════════════════════════════════════════════════╗"
writeInfoLine: "║        SPECTRAL PAINTER v1.0 (Optimized)                    ║"
writeInfoLine: "╚══════════════════════════════════════════════════════════════╝"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Speed: ", speedStr$
appendInfoLine: "Type: ", modulation_type
appendInfoLine: "Center: ", modulation_center, " | Depth: ", modulation_depth
appendInfoLine: "Wet/Dry: ", fixed$(wet_dry_percent, 0), "%"
appendInfoLine: ""

# Convert to mono
selectObject: originalID
if n_channels > 1
    Convert to mono
    workingID = selected("Sound")
else
    Copy: "working"
    workingID = selected("Sound")
endif

# Keep dry copy
selectObject: originalID
if n_channels > 1
    Convert to mono
    dry_sound = selected("Sound")
else
    Copy: "dry"
    dry_sound = selected("Sound")
endif

# === OPTIONAL DOWNSAMPLING ===
if targetSR > 0 and original_sr > targetSR
    appendInfoLine: "[1/4] Downsampling to ", targetSR, " Hz..."
    
    selectObject: workingID
    Resample: targetSR, 50
    resampledID = selected("Sound")
    removeObject: workingID
    workingID = resampledID
    
    selectObject: dry_sound
    Resample: targetSR, 50
    resampledDry = selected("Sound")
    removeObject: dry_sound
    dry_sound = resampledDry
    
    workingSR = targetSR
else
    appendInfoLine: "[1/4] Using original sample rate..."
    workingSR = original_sr
endif

# === TO SPECTRUM ===
appendInfoLine: ""
appendInfoLine: "[2/4] Creating spectrum..."

selectObject: workingID
To Spectrum: "no"
origSpecID = selected("Spectrum")

Copy: "modulated"
specID = selected("Spectrum")

# === APPLY MODULATION ===
appendInfoLine: ""
appendInfoLine: "[3/4] Applying modulation..."

# Build formula strings
cenStr$ = string$(modulation_center)
depStr$ = string$(modulation_depth)
divStr$ = string$(modulation_frequency_divisor)
cutStr$ = string$(cutoff_frequency)
phaseStr$ = string$(phase_offset)
rndStr$ = string$(randomness_amount)
secStr$ = string$(second_divisor)

selectObject: specID

if modulation_type = 1
    modName$ = "Sine (Linear)"
    Formula: "if x < " + cutStr$ + " then self * (" + cenStr$ + " + " + depStr$ + " * sin(x / " + divStr$ + " + " + phaseStr$ + ")) else self fi"
elsif modulation_type = 2
    modName$ = "Sine (Log)"
    density_str$ = string$(modulation_frequency_divisor / 10)
    Formula: "if x < " + cutStr$ + " and x > 1 then self * (" + cenStr$ + " + " + depStr$ + " * sin(ln(x) * " + density_str$ + " + " + phaseStr$ + ")) else self fi"
elsif modulation_type = 3
    modName$ = "Triangle"
    Formula: "if x < " + cutStr$ + " then self * (" + cenStr$ + " + " + depStr$ + " * (2 * abs((x / " + divStr$ + ") - floor((x / " + divStr$ + ") + 0.5)) - 1)) else self fi"
elsif modulation_type = 4
    modName$ = "Square"
    Formula: "if x < " + cutStr$ + " then self * if sin(x / " + divStr$ + ") > 0 then " + cenStr$ + " + " + depStr$ + " else " + cenStr$ + " - " + depStr$ + " fi else self fi"
elsif modulation_type = 5
    modName$ = "Sawtooth"
    Formula: "if x < " + cutStr$ + " then self * (" + cenStr$ + " + " + depStr$ + " * (2 * ((x / " + divStr$ + ") - floor((x / " + divStr$ + ") + 0.5)))) else self fi"
elsif modulation_type = 6
    modName$ = "Exponential"
    Formula: "if x < " + cutStr$ + " then self * (" + cenStr$ + " + " + depStr$ + " * exp(-x / " + divStr$ + ")) else self fi"
elsif modulation_type = 7
    modName$ = "Logarithmic"
    Formula: "if x < " + cutStr$ + " and x > 1 then self * (" + cenStr$ + " + " + depStr$ + " * ln(1 + x / " + divStr$ + ")) else self fi"
elsif modulation_type = 8
    modName$ = "Random Diffusion"
    Formula: "if x < " + cutStr$ + " then self * (" + cenStr$ + " + " + depStr$ + " * (sin(x / " + divStr$ + ") + " + rndStr$ + " * randomGauss(0, 1))) else self fi"
else
    modName$ = "Dual Sine"
    Formula: "if x < " + cutStr$ + " then self * (" + cenStr$ + " + " + depStr$ + " * (sin(x / " + divStr$ + ") + 0.5 * sin(x / " + secStr$ + ")) / 1.5) else self fi"
endif

appendInfoLine: "      Applied: ", modName$

# === BACK TO SOUND ===
appendInfoLine: ""
appendInfoLine: "[4/4] Reconstructing audio..."

selectObject: specID
To Sound
resultID = selected("Sound")

# Trim
selectObject: resultID
resultDur = Get total duration
if resultDur > duration
    Extract part: 0, duration, "rectangular", 1, "no"
    trimmed = selected("Sound")
    removeObject: resultID
    resultID = trimmed
endif

# Upsample if needed
if targetSR > 0 and original_sr > targetSR
    appendInfoLine: "      Upsampling to ", original_sr, " Hz..."
    
    selectObject: resultID
    Resample: original_sr, 50
    upsampledID = selected("Sound")
    removeObject: resultID
    resultID = upsampledID
    
    selectObject: dry_sound
    Resample: original_sr, 50
    upsampledDry = selected("Sound")
    removeObject: dry_sound
    dry_sound = upsampledDry
endif

# === WET/DRY MIX ===
if dry_level > 0
    appendInfoLine: "      Mixing wet/dry..."
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    dry_id_str$ = string$(dry_sound)
    
    selectObject: resultID
    Formula: "self * " + wet_str$ + " + object[" + dry_id_str$ + "] * " + dry_str$
endif

# === STEREO OUTPUT ===
if stereo_output
    appendInfoLine: "      Creating stereo output..."
    
    if n_channels > 1
        selectObject: resultID
        mono_result = resultID
        Convert to stereo
        resultID = selected("Sound")
        removeObject: mono_result
    elsif n_channels = 1
        selectObject: resultID
        mono_result = resultID
        delay_samples = round(0.012 * original_sr)
        delay_str$ = string$(delay_samples)
        mono_str$ = string$(mono_result)
        
        Create Sound from formula: "left", 1, 0, duration, original_sr, "object[" + mono_str$ + "]"
        left_ch = selected("Sound")
        
        Create Sound from formula: "right", 1, 0, duration, original_sr, 
            ... "if col > " + delay_str$ + " then object[" + mono_str$ + ", col - " + delay_str$ + "] else 0 fi"
        right_ch = selected("Sound")
        
        selectObject: left_ch
        plusObject: right_ch
        Combine to stereo
        resultID = selected("Sound")
        
        removeObject: mono_result, left_ch, right_ch
    endif
endif

selectObject: resultID
Rename: originalName$ + "_" + presetName$
Scale peak: scale_peak

# ===== VISUALIZATION (OPTIMIZED) =====
if show_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Spectral Painter: " + presetName$ + " (" + speedStr$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 4, 0.6, 1.6
    Select inner viewport: 0.4, 3.8, 0.7, 1.5
    selectObject: originalID
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"
    
    # Original spectrum
    Select outer viewport: 4, 8, 0.6, 1.6
    Select inner viewport: 4.4, 7.8, 0.7, 1.5
    selectObject: origSpecID
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, cutoff_frequency, 0, 80, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Spectrum"
    
    # Result waveform
    Select outer viewport: 0, 4, 1.8, 2.8
    Select inner viewport: 0.4, 3.8, 1.9, 2.7
    selectObject: resultID
    Colour: "{0.3, 0.6, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    
    # Result spectrum
    Select outer viewport: 4, 8, 1.8, 2.8
    Select inner viewport: 4.4, 7.8, 1.9, 2.7
    selectObject: specID
    Colour: "{0.8, 0.4, 0.2}"
    Draw: 0, cutoff_frequency, 0, 80, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Spectrum"
    Text bottom: "yes", "Frequency (Hz)"
    
    # Modulation curve (reduced to 200 points)
    Select outer viewport: 0, 8, 3.0, 4.2
    Select inner viewport: 0.4, 7.6, 3.1, 4.1
    
    minGain = modulation_center - abs(modulation_depth) - 0.2
    maxGain = modulation_center + abs(modulation_depth) + 0.2
    if minGain > -0.3
        minGain = -0.3
    endif
    if maxGain < 1.5
        maxGain = 1.5
    endif
    
    Axes: 0, cutoff_frequency, minGain, maxGain
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, cutoff_frequency, minGain, maxGain
    
    Colour: "{0.8, 0.8, 0.8}"
    Draw line: 0, 1, cutoff_frequency, 1
    
    if minGain < 0
        Colour: "{1, 0.8, 0.8}"
        Draw line: 0, 0, cutoff_frequency, 0
    endif
    
    # Draw curve (200 points instead of 400)
    Colour: "{0.2, 0.5, 0.8}"
    Line width: 1.5
    
    numPoints = 200
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
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Gain"
    Text bottom: "yes", "Frequency (Hz)"
    
    # Parameters
    Select outer viewport: 0, 8, 4.3, 4.7
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    
    processingTime = stopwatch - startTime
    
    param_text$ = "Center: " + fixed$(modulation_center, 2) +
        ... " | Depth: " + fixed$(modulation_depth, 2) +
        ... " | Divisor: " + string$(modulation_frequency_divisor) +
        ... " | Wet: " + fixed$(wet_dry_percent, 0) + "%" +
        ... " | Time: " + fixed$(processingTime, 2) + "s"
    
    Text: 0.5, "centre", 0.5, "half", param_text$
    
    Font size: 10
    Colour: "Black"
endif

# Cleanup
removeObject: workingID, origSpecID, specID, dry_sound

processingTime = stopwatch - startTime

selectObject: resultID

appendInfoLine: ""
appendInfoLine: "╔══════════════════════════════════════════════════════════════╗"
appendInfoLine: "║                    COMPLETE                                  ║"
appendInfoLine: "╚══════════════════════════════════════════════════════════════╝"
appendInfoLine: "Processing time: ", fixed$(processingTime, 2), " seconds"
appendInfoLine: "Output: ", selected$("Sound")

if play_after_processing
    Play
endif

selectObject: resultID