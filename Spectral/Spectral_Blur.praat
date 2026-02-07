# ============================================================
# Praat AudioTools - Spectral_Blur.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral blur effect via chunked spectrogram processing.
#   Smooths frequency bins to create dreamy, smeared textures.
#   Uses direct concatenation for crisp, artifact-rich results.
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

form Spectral Blur v1.0
    optionmenu Preset: 1
        option Standard Blur (Clean)
        option Ethereal Pad (Drone-like)
        option Underwater (Muffled)
        option Robotic / Metallic (Gritty)
        option Rhythmic Glitch (Stutter)
        option Custom
    comment === Performance ===
    optionmenu Speed_mode: 1
        option Full Quality (original sample rate)
        option Balanced (downsample to 22 kHz)
        option Fast (downsample to 11 kHz)
    comment === Custom Parameters ===
    positive Blur_radius 3.0
    positive Window_size_ms 25
    positive Chunk_size_sec 2.0
    comment === Blur Type ===
    optionmenu Blur_type: 1
        option Simple (3-point average)
        option Gaussian (5-point weighted)
        option Strong (Multiple passes)
    comment === Output ===
    positive Scale_peak 0.99
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Apply presets
if preset = 1
    blur_radius = 3.0
    window_size_ms = 25
    chunk_size_sec = 2.0
    blur_type = 1
    presetName$ = "StandardBlur"
elsif preset = 2
    blur_radius = 10.0
    window_size_ms = 80
    chunk_size_sec = 5.0
    blur_type = 2
    presetName$ = "EtherealPad"
elsif preset = 3
    blur_radius = 20.0
    window_size_ms = 30
    chunk_size_sec = 3.0
    blur_type = 3
    presetName$ = "Underwater"
elsif preset = 4
    blur_radius = 2.0
    window_size_ms = 8
    chunk_size_sec = 1.0
    blur_type = 1
    presetName$ = "Robotic"
elsif preset = 5
    blur_radius = 5.0
    window_size_ms = 20
    chunk_size_sec = 0.25
    blur_type = 1
    presetName$ = "RhythmicGlitch"
else
    presetName$ = "Custom"
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

window_size = window_size_ms / 1000

# Setup
selectObject: originalID
sampleRate = Get sampling frequency
totalDuration = Get total duration
totalSamples = Get number of samples
numChannels = Get number of channels

startTime = stopwatch

clearinfo
writeInfoLine: "=== Spectral Blur v1.0 ==="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Speed: ", speedStr$
appendInfoLine: "Duration: ", fixed$(totalDuration, 2), " s"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Blur: ", blur_radius, " | Window: ", fixed$(window_size * 1000, 1), " ms"
appendInfoLine: "Chunk: ", fixed$(chunk_size_sec, 2), " s"
appendInfoLine: ""

# Convert to mono
workingID = originalID
if numChannels > 1
    selectObject: originalID
    Convert to mono
    workingID = selected("Sound")
endif

# Optional downsampling
if targetSR > 0 and sampleRate > targetSR
    appendInfoLine: "[SPEED] Downsampling to ", targetSR, " Hz"
    selectObject: workingID
    Resample: targetSR, 50
    resampledID = selected("Sound")
    removeObject: workingID
    workingID = resampledID
    workingSR = targetSR
    
    # Recalculate
    selectObject: workingID
    totalSamples = Get number of samples
else
    workingSR = sampleRate
endif

# Chunk parameters
chunkSamples = round(chunk_size_sec * workingSR)
numChunks = ceiling(totalSamples / chunkSamples)

appendInfoLine: "Processing ", numChunks, " chunks..."

# Process chunks
for i from 1 to numChunks
    selectObject: workingID
    
    startSample = (i - 1) * chunkSamples + 1
    endSample = min(startSample + chunkSamples - 1, totalSamples)
    
    startTime_chunk = (startSample - 1) / workingSR
    endTime_chunk = (endSample - 1) / workingSR
    
    if endTime_chunk > startTime_chunk
        # Extract chunk
        Extract part: startTime_chunk, endTime_chunk, "rectangular", 1.0, "no"
        chunkID = selected("Sound")
        
        # To Spectrogram
        timeStep = window_size / 8
        selectObject: chunkID
        To Spectrogram: window_size, 5000, timeStep, 20, "Gaussian"
        specID = selected("Spectrogram")
        
        # Blur
        if blur_radius >= 1
            loopCount = round(blur_radius)
            for k from 1 to loopCount
                selectObject: specID
                
                if blur_type = 1
                    # Simple 3-point
                    Formula: "if row > 1 and row < nrow then (self[row-1, col] + 2*self + self[row+1, col]) / 4 else self endif"
                elsif blur_type = 2
                    # Gaussian 5-point
                    Formula: "if row > 2 and row < nrow - 1 then (self[row-2, col] + 4*self[row-1, col] + 6*self + 4*self[row+1, col] + self[row+2, col]) / 16 else self endif"
                else
                    # Strong (simple repeated)
                    Formula: "if row > 1 and row < nrow then (self[row-1, col] + 2*self + self[row+1, col]) / 4 else self endif"
                endif
            endfor
        endif
        
        # Back to Sound
        selectObject: specID
        To Sound: workingSR
        processedID = selected("Sound")
        
        # Store chunk
        chunk_'i' = processedID
        
        removeObject: chunkID, specID
        
        if i mod 10 = 0 or i = numChunks
            appendInfoLine: "  Chunk ", i, "/", numChunks
        endif
    else
        chunk_'i' = 0
    endif
endfor

# Concatenate chunks
appendInfo: "Concatenating..."

firstChunk = chunk_1
selectObject: firstChunk

for i from 2 to numChunks
    cid = chunk_'i'
    if cid > 0
        plusObject: cid
    endif
endfor

Concatenate
resultID = selected("Sound")

# Upsample if needed
if targetSR > 0 and sampleRate > targetSR
    appendInfo: " upsampling..."
    selectObject: resultID
    Resample: sampleRate, 50
    upsampledID = selected("Sound")
    removeObject: resultID
    resultID = upsampledID
endif

appendInfoLine: " done"

# Cleanup chunks
for i from 1 to numChunks
    cid = chunk_'i'
    if cid > 0
        removeObject: cid
    endif
endfor

if numChannels > 1
    removeObject: workingID
endif

# Finalize
selectObject: resultID
Rename: originalName$ + "_blur_" + presetName$
Scale peak: scale_peak

processingTime = stopwatch - startTime

# Visualization
if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Spectral Blur: " + originalName$ + " [" + presetName$ + "]"
    
    # Original waveform
    Select outer viewport: 0, 4, 0.6, 2.0
    Select inner viewport: 0.5, 3.7, 0.75, 1.85
    selectObject: originalID
    Colour: "{0.7, 0.7, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 9
    Text top: "no", "Original"
    Text left: "yes", "Amplitude"
    
    # Processed waveform
    Select outer viewport: 4, 8, 0.6, 2.0
    Select inner viewport: 4.5, 7.7, 0.75, 1.85
    selectObject: resultID
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text top: "no", "Blurred"
    Text left: "yes", "Amplitude"
    
    # Original spectrogram
    Select outer viewport: 0, 4, 2.2, 4.2
    selectObject: originalID
    To Spectrogram: 0.01, 5000, 0.002, 20, "Gaussian"
    origSpecID = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Font size: 9
    Text top: "no", "Original Spectrogram"
    removeObject: origSpecID
    
    # Processed spectrogram
    Select outer viewport: 4, 8, 2.2, 4.2
    selectObject: resultID
    To Spectrogram: 0.01, 5000, 0.002, 20, "Gaussian"
    resSpecID = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Text top: "no", "Blurred Spectrogram"
    removeObject: resSpecID
    
    # Info panel
    Select outer viewport: 0, 8, 4.4, 5.0
    Select inner viewport: 0.5, 7.7, 4.45, 4.95
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.5, "half", "Blur: " + fixed$(blur_radius, 1)
    Text: 0.25, "left", 0.5, "half", "Window: " + fixed$(window_size * 1000, 1) + " ms"
    Text: 0.5, "left", 0.5, "half", "Chunks: " + string$(numChunks)
    Text: 0.75, "left", 0.5, "half", "Time: " + fixed$(processingTime, 2) + " s"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
endif

# Output
appendInfoLine: ""
appendInfoLine: "Processing time: ", fixed$(processingTime, 2), " seconds"
appendInfoLine: "Created: ", originalName$ + "_blur_" + presetName$

selectObject: resultID

if play_result
    Play
endif

selectObject: originalID

