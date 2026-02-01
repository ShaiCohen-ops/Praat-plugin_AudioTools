# ============================================================
# Praat AudioTools - Fractal_Convolution_Matrix.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Fractal Convolution Matrix - creates self-similar textures
#   by convolving sound with delayed versions of itself at
#   multiple time scales. Each depth level adds echoes at
#   geometrically decreasing intervals (2^depth), creating
#   fractal-like temporal patterns.
#
# Changelog v0.2:
#   - Modern syntax
#   - Added visualization
#   - Fixed Formula interpolation
# ============================================================

form Fractal Convolution
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Subtle Fractal
        option Medium Fractal
        option Heavy Fractal
        option Extreme Fractal
    
    comment === Fractal Parameters ===
    positive Tail_duration_s 2.0
    natural Fractal_depth 5
    natural Convolution_width 3
    
    comment === Scaling ===
    positive Kernel_divisor 10
    positive Amplitude_reduction 0.15
    
    comment === Output ===
    positive Scale_peak 0.90
    positive Fadeout_duration_s 1.0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Subtle Fractal
    tail_duration_s = 1.5
    fractal_depth = 3
    convolution_width = 2
    kernel_divisor = 12
    amplitude_reduction = 0.12
    scale_peak = 0.92
    fadeout_duration_s = 0.8
elsif preset = 3
    # Medium Fractal
    tail_duration_s = 2.0
    fractal_depth = 5
    convolution_width = 3
    kernel_divisor = 10
    amplitude_reduction = 0.15
    scale_peak = 0.90
    fadeout_duration_s = 1.0
elsif preset = 4
    # Heavy Fractal
    tail_duration_s = 2.8
    fractal_depth = 7
    convolution_width = 4
    kernel_divisor = 8
    amplitude_reduction = 0.18
    scale_peak = 0.88
    fadeout_duration_s = 1.4
elsif preset = 5
    # Extreme Fractal
    tail_duration_s = 4.0
    fractal_depth = 10
    convolution_width = 5
    kernel_divisor = 6
    amplitude_reduction = 0.22
    scale_peak = 0.86
    fadeout_duration_s = 1.8
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
sampling_rate = Get sampling frequency
channels = Get number of channels
originalDuration = Get total duration

# === Info ===
writeInfoLine: "=== Fractal Convolution Matrix ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(originalDuration, 2), " s)"
appendInfoLine: ""
appendInfoLine: "Fractal depth: ", fractal_depth
appendInfoLine: "Convolution width: ", convolution_width
appendInfoLine: "Kernel divisor: ", kernel_divisor
appendInfoLine: ""

# === Create Silent Tail ===
if channels = 2
    Create Sound from formula: "silent_tail", 2, 0, tail_duration_s, sampling_rate, "0"
else
    Create Sound from formula: "silent_tail", 1, 0, tail_duration_s, sampling_rate, "0"
endif
silentTail = selected("Sound")

# === Concatenate ===
selectObject: original, silentTail
Concatenate
extended = selected("Sound")
Rename: "extended"

removeObject: silentTail

# === Copy for Processing ===
selectObject: extended
Copy: "fractal_work"
result = selected("Sound")

totalSamples = Get number of samples

# === Main Fractal Processing Loop ===
appendInfoLine: "Processing fractal depths..."
appendInfoLine: ""
appendInfoLine: "Depth | Scale | Kernel Size | Delays"
appendInfoLine: "------|-------|-------------|-------"

for depth from 1 to fractal_depth
    scaleFactor = 2 ^ depth
    kernelSize = round(totalSamples / (kernel_divisor * scaleFactor))
    
    # Info
    delayMs = kernelSize / sampling_rate * 1000
    appendInfoLine: "  ", depth, "   |  ", scaleFactor, "   |    ", kernelSize, "     | ", fixed$(delayMs, 1), " ms"
    
    # Fractal convolution kernel
    selectObject: result
    for kernel from -convolution_width to convolution_width
        kernelWeight = 1 / (1 + abs(kernel))
        kernelShift = kernel * kernelSize
        depthFactor = depth + 2
        
        Formula: "self + if col + kernelShift >= 1 and col + kernelShift <= ncol then self[col + kernelShift] * kernelWeight / depthFactor else 0 fi"
    endfor
    
    # Fractal amplitude scaling
    ampScale = 1 - depth * amplitude_reduction
    Formula: "self * ampScale"
endfor

# === Scale Peak ===
selectObject: result
Scale peak: scale_peak

# === Apply Fadeout ===
totalDuration = Get total duration
fadeStart = totalDuration - fadeout_duration_s

Formula: "if x > fadeStart then self * (0.5 + 0.5 * cos(pi * (x - fadeStart) / fadeout_duration_s)) else self fi"

Rename: original_name$ + "_fractal"

# === Cleanup ===
removeObject: extended

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 1, 8, 0.2, 0.6
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Fractal Convolution: " + original_name$
    
    # Original waveform
    Select outer viewport: 0, 8, 0.8, 2.2
    Select inner viewport: 0.6, 7.6, 0.9, 2.1
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Select outer viewport: 0.1, 8, 0.5, 2.8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 2.3, 3.7
    Select inner viewport: 0.6, 7.6, 2.4, 3.6
    selectObject: result
    Colour: "{0.2, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Fractal"
    Text bottom: "yes", "Time (s)"
    
    # Original spectrogram
    Select outer viewport: 0, 4, 3.9, 5.5
    Select inner viewport: 0.6, 3.8, 4.1, 5.4
    selectObject: original
    To Spectrogram: 0.03, 5000, 0.01, 20, "Gaussian"
    origSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: origSpec
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq"
    Text bottom: "yes", "Original (s)"
    
    # Result spectrogram
    Select outer viewport: 4, 8, 3.9, 5.5
    Select inner viewport: 4.4, 7.6, 4.1, 5.4
    selectObject: result
    To Spectrogram: 0.03, 5000, 0.01, 20, "Gaussian"
    resSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: resSpec
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq"
    Text bottom: "yes", "Fractal (s)"
    
    # Legend
    Select outer viewport: 0, 8, 5.6, 5.9
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 1.5, "centre", 0.5, "half", "Depth: " + string$(fractal_depth) + " | Width: " + string$(convolution_width) + " | Divisor: " + string$(kernel_divisor)
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result
finalDuration = Get total duration

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Original: ", fixed$(originalDuration, 2), " s"
appendInfoLine: "Result: ", fixed$(finalDuration, 2), " s"
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result