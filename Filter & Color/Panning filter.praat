# ============================================================
# Praat AudioTools - Panning filter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Filtering or timbral modification script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Spectral Panner
    optionmenu Preset: 1
        option Custom
        option Subtle Split (800 Hz)
        option Classic Mid (500 Hz)
        option Deep Bass Left (200 Hz)
        option High Split (2000 Hz)
        option Wide Separation
    comment === Crossover ===
    positive Crossover_frequency_(Hz) 500
    positive Crossover_width_(Hz) 100
    comment === Panning ===
    optionmenu Low_frequencies_to: 1
        option Left
        option Right
    real Pan_depth 1.0
    comment === Output ===
    boolean Draw_response 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================
if preset = 2
    crossover_frequency = 800
    crossover_width = 150
    pan_depth = 0.7
elsif preset = 3
    crossover_frequency = 500
    crossover_width = 100
    pan_depth = 1.0
elsif preset = 4
    crossover_frequency = 200
    crossover_width = 50
    pan_depth = 1.0
elsif preset = 5
    crossover_frequency = 2000
    crossover_width = 300
    pan_depth = 0.8
elsif preset = 6
    crossover_frequency = 600
    crossover_width = 400
    pan_depth = 1.0
endif

# ============================================================
# INPUT VALIDATION
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")
selectObject: originalID
originalDur = Get total duration
sampleRate = Get sampling frequency
numChan = Get number of channels

nyquist = sampleRate / 2
if crossover_frequency >= nyquist * 0.9
    exitScript: "Crossover frequency too high for this sample rate."
endif

# ============================================================
# DRAW FREQUENCY RESPONSE
# ============================================================
if draw_response
    Erase all
    
    # Set up drawing area with more bottom margin
    Select outer viewport: 0, 6, 0, 4.5
    Axes: 0, nyquist, -0.2, 1.15
    
    # Draw frame
    Colour: "Black"
    Draw inner box
    
    # Draw grid lines
    Colour: "{0.7,0.7,0.7}"
    
    # Adaptive grid spacing based on nyquist
    if nyquist > 15000
        gridStep = 5000
    elsif nyquist > 8000
        gridStep = 2000
    else
        gridStep = 1000
    endif
    
    gridFreq = gridStep
    while gridFreq < nyquist
        Draw line: gridFreq, 0, gridFreq, 1
        gridFreq = gridFreq + gridStep
    endwhile
    Draw line: 0, 0.5, nyquist, 0.5
    
    # Calculate crossover edges
    lowEdge = crossover_frequency - crossover_width / 2
    highEdge = crossover_frequency + crossover_width / 2
    lowEdge = max(lowEdge, 1)
    highEdge = min(highEdge, nyquist - 1)
    
    # Calculate channel gains based on pan direction
    if low_frequencies_to = 1
        lowL = 0.5 + 0.5 * pan_depth
        lowR = 0.5 - 0.5 * pan_depth
        highL = 0.5 - 0.5 * pan_depth
        highR = 0.5 + 0.5 * pan_depth
        leftLabel$ = "LEFT (Low)"
        rightLabel$ = "RIGHT (High)"
    else
        lowL = 0.5 - 0.5 * pan_depth
        lowR = 0.5 + 0.5 * pan_depth
        highL = 0.5 + 0.5 * pan_depth
        highR = 0.5 - 0.5 * pan_depth
        leftLabel$ = "LEFT (High)"
        rightLabel$ = "RIGHT (Low)"
    endif
    
    # Draw LEFT channel response (Blue)
    Colour: "Blue"
    Line width: 2
    
    step = nyquist / 200
    prevX = 0
    prevY = lowL
    plotFreq = step
    
    while plotFreq <= nyquist
        if plotFreq < lowEdge
            yVal = lowL
        elsif plotFreq > highEdge
            yVal = highL
        else
            phase = pi * (plotFreq - lowEdge) / crossover_width
            yVal = lowL * (0.5 + 0.5 * cos(phase)) + highL * (0.5 - 0.5 * cos(phase))
        endif
        Draw line: prevX, prevY, plotFreq, yVal
        prevX = plotFreq
        prevY = yVal
        plotFreq = plotFreq + step
    endwhile
    
    # Draw RIGHT channel response (Red)
    Colour: "Red"
    prevX = 0
    prevY = lowR
    plotFreq = step
    
    while plotFreq <= nyquist
        if plotFreq < lowEdge
            yVal = lowR
        elsif plotFreq > highEdge
            yVal = highR
        else
            phase = pi * (plotFreq - lowEdge) / crossover_width
            yVal = lowR * (0.5 + 0.5 * cos(phase)) + highR * (0.5 - 0.5 * cos(phase))
        endif
        Draw line: prevX, prevY, plotFreq, yVal
        prevX = plotFreq
        prevY = yVal
        plotFreq = plotFreq + step
    endwhile
    
    # Draw crossover region
    Line width: 1
    Colour: "{0.6,0.6,0.6}"
    Draw line: lowEdge, 0, lowEdge, 1
    Draw line: highEdge, 0, highEdge, 1
    
    # Mark crossover frequency
    Colour: "Black"
    Line width: 1
    Dotted line
    Draw line: crossover_frequency, 0, crossover_frequency, 1
    Solid line
    
    # Crossover label (above the graph)
    Font size: 10
    Text: crossover_frequency, "Centre", 1.08, "Half", string$(crossover_frequency) + " Hz"
    
    # Title
    Font size: 14
    Text: nyquist / 2, "Centre", 1.12, "Half", "Spectral Panner"
    
    # Legend
    Font size: 10
    Colour: "Blue"
    Text: nyquist * 0.88, "Centre", 0.95, "Half", leftLabel$
    Colour: "Red"
    Text: nyquist * 0.88, "Centre", 0.85, "Half", rightLabel$
    
    # Axis labels
    Colour: "Black"
    Font size: 10
    Text: nyquist / 2, "Centre", -0.15, "Half", "Frequency (Hz)"
    
    # Axis markers - adaptive spacing
    if nyquist > 15000
        Marks bottom every: 1, 5000, "yes", "yes", "no"
    elsif nyquist > 8000
        Marks bottom every: 1, 2000, "yes", "yes", "no"
    else
        Marks bottom every: 1, 1000, "yes", "yes", "no"
    endif
    Marks left every: 1, 0.5, "yes", "yes", "no"
    
    # Parameter info
    Colour: "{0.4,0.4,0.4}"
    Font size: 9
    Text: nyquist * 0.12, "Centre", 0.95, "Half", "Depth: " + fixed$(pan_depth * 100, 0) + "%"
    Text: nyquist * 0.12, "Centre", 0.85, "Half", "Width: " + string$(crossover_width) + " Hz"
    
    Line width: 1
endif

# ============================================================
# PREPARE MONO SOURCE
# ============================================================
selectObject: originalID

if numChan = 2
    monoSound = Convert to mono
else
    monoSound = Copy: "mono"
endif

# ============================================================
# SPECTRAL PROCESSING
# ============================================================
selectObject: monoSound
spectrumFull = To Spectrum: "yes"

lowEdge = crossover_frequency - crossover_width / 2
highEdge = crossover_frequency + crossover_width / 2
lowEdge = max(lowEdge, 1)
highEdge = min(highEdge, nyquist - 1)

lowEdgeStr$ = fixed$(lowEdge, 2)
highEdgeStr$ = fixed$(highEdge, 2)
widthStr$ = fixed$(crossover_width, 2)

# Lowpass spectrum
selectObject: spectrumFull
spectrumLow = Copy: "low"
selectObject: spectrumLow
Formula: "if x < " + lowEdgeStr$ + " then self else (if x > " + highEdgeStr$ + " then 0 else self * (0.5 + 0.5 * cos(pi * (x - " + lowEdgeStr$ + ") / " + widthStr$ + ")) fi) fi"

# Highpass spectrum
selectObject: spectrumFull
spectrumHigh = Copy: "high"
selectObject: spectrumHigh
Formula: "if x > " + highEdgeStr$ + " then self else (if x < " + lowEdgeStr$ + " then 0 else self * (0.5 - 0.5 * cos(pi * (x - " + lowEdgeStr$ + ") / " + widthStr$ + ")) fi) fi"

# Convert back to sound
selectObject: spectrumLow
soundLow = To Sound
selectObject: spectrumHigh
soundHigh = To Sound

# Crop to original duration
selectObject: soundLow
soundLowCrop = Extract part: 0, originalDur, "rectangular", 1, "no"
selectObject: soundHigh
soundHighCrop = Extract part: 0, originalDur, "rectangular", 1, "no"
Rename: "high_part"

# ============================================================
# CREATE STEREO OUTPUT
# ============================================================
if low_frequencies_to = 1
    lowL = 0.5 + 0.5 * pan_depth
    lowR = 0.5 - 0.5 * pan_depth
    highL = 0.5 - 0.5 * pan_depth
    highR = 0.5 + 0.5 * pan_depth
else
    lowL = 0.5 - 0.5 * pan_depth
    lowR = 0.5 + 0.5 * pan_depth
    highL = 0.5 + 0.5 * pan_depth
    highR = 0.5 - 0.5 * pan_depth
endif

lowLStr$ = fixed$(lowL, 4)
lowRStr$ = fixed$(lowR, 4)
highLStr$ = fixed$(highL, 4)
highRStr$ = fixed$(highR, 4)

# Left channel
selectObject: soundLowCrop
leftChan = Copy: "L"
selectObject: leftChan
Formula: "self * " + lowLStr$ + " + Sound_high_part[] * " + highLStr$

# Right channel
selectObject: soundLowCrop
rightChan = Copy: "R"
selectObject: rightChan
Formula: "self * " + lowRStr$ + " + Sound_high_part[] * " + highRStr$

# Combine
selectObject: leftChan
plusObject: rightChan
stereoOutput = Combine to stereo
Rename: originalName$ + "_specpan"

# ============================================================
# CLEANUP
# ============================================================
removeObject: monoSound, spectrumFull, spectrumLow, spectrumHigh
removeObject: soundLow, soundHigh, soundLowCrop, soundHighCrop
removeObject: leftChan, rightChan

selectObject: stereoOutput
Scale peak: 0.95

# ============================================================
# INFO OUTPUT
# ============================================================
writeInfoLine: "Spectral Panner Complete"
appendInfoLine: "========================"
appendInfoLine: "Crossover: ", crossover_frequency, " Hz"
appendInfoLine: "Width: ±", crossover_width/2, " Hz"
appendInfoLine: "Depth: ", fixed$(pan_depth * 100, 0), "%"
if low_frequencies_to = 1
    appendInfoLine: "Low → Left, High → Right"
else
    appendInfoLine: "Low → Right, High → Left"
endif

if play_result
    selectObject: stereoOutput
    Play
endif
