## ============================================================
# Praat AudioTools - Fast_Chunked_Spectral_Blur.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.4 (2025) - Fixed To Sound syntax
# License: MIT License
#
# Description:
#   Spectral blur effect - smooths the frequency spectrum,
#   creating dreamy, smeared textures via Spectrogram processing.
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

form Spectral Blur v0.4
    optionmenu Preset: 1
        option Standard Blur (Clean)
        option Ethereal Pad (Drone-like)
        option Underwater (Muffled)
        option Robotic / Metallic (Gritty)
        option Rhythmic Glitch (Stutter)
        option Custom
    comment === Custom Parameters ===
    positive Blur_radius 3.0
    positive Window_size_ms 25
    positive Chunk_size_sec 2.0
    comment === Output ===
    positive Scale_peak 0.99
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================

if preset = 1
    blur_radius = 3.0
    window_size_ms = 25
    chunk_size_sec = 2.0
    presetName$ = "StandardBlur"
elsif preset = 2
    blur_radius = 10.0
    window_size_ms = 80
    chunk_size_sec = 5.0
    presetName$ = "EtherealPad"
elsif preset = 3
    blur_radius = 20.0
    window_size_ms = 30
    chunk_size_sec = 3.0
    presetName$ = "Underwater"
elsif preset = 4
    blur_radius = 2.0
    window_size_ms = 8
    chunk_size_sec = 1.0
    presetName$ = "Robotic"
elsif preset = 5
    blur_radius = 5.0
    window_size_ms = 20
    chunk_size_sec = 0.25
    presetName$ = "RhythmicGlitch"
else
    presetName$ = "Custom"
endif

# Convert to seconds
window_size = window_size_ms / 1000

# ============================================================
# SETUP
# ============================================================

selectObject: originalID
sampleRate = Get sampling frequency
totalDuration = Get total duration
totalSamples = Get number of samples
numChannels = Get number of channels

clearinfo
writeInfoLine: "=== Spectral Blur v0.4 ==="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Duration: ", fixed$(totalDuration, 2), " s"
appendInfoLine: ""
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Blur radius: ", blur_radius
appendInfoLine: "Window: ", fixed$(window_size * 1000, 1), " ms"
appendInfoLine: "Chunk size: ", fixed$(chunk_size_sec, 2), " s"
appendInfoLine: ""

# ============================================================
# PREPARE
# ============================================================

# Convert to mono if stereo
workingID = originalID
didMono = 0

if numChannels > 1
    selectObject: originalID
    workingID = Convert to mono
    didMono = 1
endif

# Chunk parameters
chunkSamples = round(chunk_size_sec * sampleRate)
numChunks = ceiling(totalSamples / chunkSamples)

appendInfoLine: "Processing ", numChunks, " chunks..."

# ============================================================
# PROCESS CHUNKS
# ============================================================

for i from 1 to numChunks
    selectObject: workingID
    
    startSample = (i - 1) * chunkSamples + 1
    endSample = min(startSample + chunkSamples - 1, totalSamples)
    
    startTime = (startSample - 1) / sampleRate
    endTime = (endSample - 1) / sampleRate
    
    if endTime > startTime
        # Extract chunk
        chunkID = Extract part: startTime, endTime, "rectangular", 1.0, "no"
        
        # To Spectrogram
        timeStep = window_size / 8
        selectObject: chunkID
        specID = To Spectrogram: window_size, 5000, timeStep, 20, "Gaussian"
        
        # Blur: smooth across frequency bins (row = frequency)
        if blur_radius >= 1
            loopCount = round(blur_radius)
            for k from 1 to loopCount
                selectObject: specID
                Formula: "if row > 1 and row < nrow then (self[row-1, col] + 2*self + self[row+1, col]) / 4 else self endif"
            endfor
        endif
        
        # Back to Sound - FIXED: include sample rate
        selectObject: specID
        processedID = To Sound: sampleRate
        
        # Store chunk ID using indexed variable
        chunk_'i' = processedID
        
        # Cleanup
        removeObject: chunkID, specID
        
        if i mod 10 = 0 or i = numChunks
            appendInfoLine: "  Chunk ", i, "/", numChunks
        endif
    else
        chunk_'i' = 0
    endif
endfor

# ============================================================
# CONCATENATE
# ============================================================

appendInfo: "Concatenating..."

# Select first valid chunk
firstChunk = chunk_1
selectObject: firstChunk

# Add remaining chunks
for i from 2 to numChunks
    cid = chunk_'i'
    if cid > 0
        plusObject: cid
    endif
endfor

resultID = Concatenate
Rename: originalName$ + "_blur_" + presetName$
Scale peak: scale_peak

appendInfoLine: " done"

# Cleanup chunks
for i from 1 to numChunks
    cid = chunk_'i'
    if cid > 0
        removeObject: cid
    endif
endfor

# Cleanup mono if created
if didMono = 1
    removeObject: workingID
endif

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
    Text left: "yes", "Amp"
    
    # Processed waveform
    Select outer viewport: 4, 8, 0.6, 2.0
    Select inner viewport: 4.5, 7.7, 0.75, 1.85
    selectObject: resultID
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text top: "no", "Blurred"
    Text left: "yes", "Amp"
    
    # Original spectrogram
    Select outer viewport: 0, 4, 2.2, 4.2
    selectObject: originalID
    origSpecID = To Spectrogram: 0.01, 5000, 0.002, 20, "Gaussian"
    selectObject: origSpecID
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Font size: 9
    Text top: "no", "Original Spectrogram"
    removeObject: origSpecID
    
    # Processed spectrogram
    Select outer viewport: 4, 8, 2.2, 4.2
    selectObject: resultID
    resSpecID = To Spectrogram: 0.01, 5000, 0.002, 20, "Gaussian"
    selectObject: resSpecID
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
    Text: 0.02, "left", 0.5, "half", "Blur radius: " + fixed$(blur_radius, 1)
    Text: 0.25, "left", 0.5, "half", "Window: " + fixed$(window_size * 1000, 1) + " ms"
    Text: 0.5, "left", 0.5, "half", "Chunks: " + string$(numChunks) + " x " + fixed$(chunk_size_sec, 2) + " s"
    
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
appendInfoLine: "Created: ", originalName$, "_blur_", presetName$

if play_result
    selectObject: resultID
    Play
endif
