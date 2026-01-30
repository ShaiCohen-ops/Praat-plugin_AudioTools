# ============================================================
# Praat AudioTools - Stereo_Delay_Splitter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Stereo Delay Splitter - applies differentiation (high-pass
#   comb filtering) with different delay times to L and R
#   channels. Creates stereo width and spectral separation
#   through phase cancellation at different frequencies.
#
# Changelog v0.2:
#   - Modern syntax
#   - Added mono-to-stereo conversion
#   - Added bounds checking
#   - Added visualization
# ============================================================

form Stereo Delay Splitter
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Default (L:2,4 | R:8,10)
        option Narrow Stereo (L:3,5 | R:6,8)
        option Wide Stereo (L:2,6 | R:12,18)
        option Alt Divisors (L:2,3 | R:9,15)
        option Custom
    
    comment === Left Channel Divisors ===
    positive Divisor_L1 2
    positive Divisor_L2 4
    
    comment === Right Channel Divisors ===
    positive Divisor_R1 8
    positive Divisor_R2 10
    
    comment === Output ===
    positive Scale_peak 0.99
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 1
    # Default
    divisor_L1 = 2
    divisor_L2 = 4
    divisor_R1 = 8
    divisor_R2 = 10
elsif preset = 2
    # Narrow Stereo
    divisor_L1 = 3
    divisor_L2 = 5
    divisor_R1 = 6
    divisor_R2 = 8
elsif preset = 3
    # Wide Stereo
    divisor_L1 = 2
    divisor_L2 = 6
    divisor_R1 = 12
    divisor_R2 = 18
elsif preset = 4
    # Alt Divisors
    divisor_L1 = 2
    divisor_L2 = 3
    divisor_R1 = 9
    divisor_R2 = 15
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
sampleRate = Get sampling frequency
duration = Get total duration
totalSamples = Get number of samples
numChannels = Get number of channels

# === Get Preset Name ===
if preset = 1
    presetName$ = "Default"
elsif preset = 2
    presetName$ = "Narrow"
elsif preset = 3
    presetName$ = "Wide"
elsif preset = 4
    presetName$ = "Alt"
else
    presetName$ = "Custom"
endif

# === Info ===
writeInfoLine: "=== Stereo Delay Splitter ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Left divisors: ", divisor_L1, ", ", divisor_L2
appendInfoLine: "Right divisors: ", divisor_R1, ", ", divisor_R2
appendInfoLine: ""

# === Prepare Source ===
if numChannels = 1
    selectObject: original
    Copy: "left_tmp"
    selectObject: original
    Copy: "right_tmp"
    selectObject: "Sound left_tmp", "Sound right_tmp"
    Combine to stereo
    sourceSound = selected("Sound")
    # Clean up the temporary mono copies
    removeObject: "Sound left_tmp", "Sound right_tmp"
    appendInfoLine: "Converted mono to stereo for processing"
else
    selectObject: original
    Copy: "stereo_temp"
    sourceSound = selected("Sound")
endif

# === Calculate Delays ===
delayL1 = round(totalSamples / divisor_L1)
delayL2 = round(totalSamples / divisor_L2)
delayR1 = round(totalSamples / divisor_R1)
delayR2 = round(totalSamples / divisor_R2)

appendInfoLine: "Left delays: ", delayL1, ", ", delayL2, " samples"
appendInfoLine: "Right delays: ", delayR1, ", ", delayR2, " samples"
appendInfoLine: ""

# === Process Left Channel ===
selectObject: sourceSound
Extract one channel: 1
leftChannel = selected("Sound")
Rename: "Left"

appendInfoLine: "Processing left channel..."

# Iteration 1
selectObject: leftChannel
Formula: ~ if col + delayL1 <= ncol then self[col + delayL1] - self else self fi

# Iteration 2
Formula: ~ if col + delayL2 <= ncol then self[col + delayL2] - self else self fi

# === Process Right Channel ===
selectObject: sourceSound
Extract one channel: 2
rightChannel = selected("Sound")
Rename: "Right"

appendInfoLine: "Processing right channel..."

# Iteration 1
selectObject: rightChannel
Formula: ~ if col + delayR1 <= ncol then self[col + delayR1] - self else self fi

# Iteration 2
Formula: ~ if col + delayR2 <= ncol then self[col + delayR2] - self else self fi

# === Combine to Stereo ===
selectObject: leftChannel, rightChannel
Combine to stereo
result = selected("Sound")
Rename: original_name$ + "_stereo_split"

Scale peak: scale_peak

# === Cleanup ===
removeObject: leftChannel, rightChannel, sourceSound

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 1, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Stereo Delay Splitter: " + original_name$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 2.0
    Select inner viewport: 0.6, 7.6, 0.7, 1.9
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform (stereo)
    Select outer viewport: 0, 8, 2.1, 3.5
    Select inner viewport: 0.6, 7.6, 2.2, 3.4
    selectObject: result
    Colour: "{0.5, 0.6, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Stereo Split"
    Text bottom: "yes", "Time (s)"
    
    # Original spectrum
    Select outer viewport: 0, 4, 3.7, 5.3
    Select inner viewport: 0.6, 3.8, 3.9, 5.2
    selectObject: original
    To Spectrum: "yes"
    origSpec = selected("Spectrum")
    Draw: 0, 5000, 0, 80, "no"
    removeObject: origSpec
    Colour: "{0.8, 0.5, 0.6}"
    Draw inner box
    Font size: 7
    Text left: "yes", "dB"
    Text bottom: "yes", "Original spectrum (Hz)"
    
    # Result spectrum (shows comb filtering)
    Select outer viewport: 4, 8, 3.7, 5.3
    Select inner viewport: 4.4, 7.6, 3.9, 5.2
    selectObject: result
    To Spectrum: "yes"
    resSpec = selected("Spectrum")
    Draw: 0, 5000, 0, 80, "no"
    removeObject: resSpec
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "dB"
    Text bottom: "yes", "Split spectrum (Hz)"
    
    # Divisor info
    Select outer viewport: 0, 8, 5.4, 5.7
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 4.5, "centre", 0.5, "half", "L: ÷" + string$(divisor_L1) + ", ÷" + string$(divisor_L2) + " | R: ÷" + string$(divisor_R1) + ", ÷" + string$(divisor_R2) + " | Effect: High-pass comb filter with stereo separation"
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result
finalDuration = Get total duration

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDuration, 2), " s"

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result