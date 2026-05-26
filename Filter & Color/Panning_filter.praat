# ============================================================
# Praat AudioTools - Panning filter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Filtering or timbral modification script
#
# Changelog v0.2:
#   - Crossover taper uses the actual (clamped) band span, so it stays
#     continuous even at extreme crossover/width settings.
#   - pan_depth clamped to 0..1 (>1 would phase-invert the off-side).
#   - Visualization rebuilt to the AudioTools standard: 8-inch canvas,
#     inner viewports, bold title, parameters in a grey summary panel
#     instead of overlapping the response curves.
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

# Clamp pan depth to a sane range (>1 would phase-invert the off-side).
if pan_depth > 1
    pan_depth = 1
elsif pan_depth < 0
    pan_depth = 0
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
    Colour: "Black"

    # Clamped crossover edges + the actual taper span (matches processing)
    vLowEdge = max(crossover_frequency - crossover_width / 2, 1)
    vHighEdge = min(crossover_frequency + crossover_width / 2, nyquist - 1)
    vSpan = vHighEdge - vLowEdge
    if vSpan < 1
        vSpan = 1
    endif

    # Channel gains by pan direction
    if low_frequencies_to = 1
        vLowL = 0.5 + 0.5 * pan_depth
        vLowR = 0.5 - 0.5 * pan_depth
        vHighL = 0.5 - 0.5 * pan_depth
        vHighR = 0.5 + 0.5 * pan_depth
        leftLabel$ = "Left = low band"
        rightLabel$ = "Right = high band"
    else
        vLowL = 0.5 - 0.5 * pan_depth
        vLowR = 0.5 + 0.5 * pan_depth
        vHighL = 0.5 + 0.5 * pan_depth
        vHighR = 0.5 - 0.5 * pan_depth
        leftLabel$ = "Left = high band"
        rightLabel$ = "Right = low band"
    endif

    # ---- Title ----
    Select inner viewport: 0.6, 7.7, 0.2, 0.7
    Axes: 0, 1, 0, 1
    Font size: 13
    Text: 0.5, "Centre", 0.5, "Half", "##Spectral Panner - channel frequency response##"

    # ---- Response panel ----
    Select inner viewport: 0.6, 7.7, 0.9, 4.3
    Axes: 0, nyquist, -0.05, 1.1

    # grid
    Colour: "{0.85, 0.85, 0.85}"
    Line width: 1
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

    # left channel (blue)
    Colour: "{0.20, 0.40, 0.80}"
    Line width: 2
    step = nyquist / 200
    prevX = 0
    prevY = vLowL
    plotFreq = step
    while plotFreq <= nyquist
        if plotFreq < vLowEdge
            yVal = vLowL
        elsif plotFreq > vHighEdge
            yVal = vHighL
        else
            phase = pi * (plotFreq - vLowEdge) / vSpan
            yVal = vLowL * (0.5 + 0.5 * cos(phase)) + vHighL * (0.5 - 0.5 * cos(phase))
        endif
        Draw line: prevX, prevY, plotFreq, yVal
        prevX = plotFreq
        prevY = yVal
        plotFreq = plotFreq + step
    endwhile

    # right channel (red)
    Colour: "{0.85, 0.25, 0.20}"
    prevX = 0
    prevY = vLowR
    plotFreq = step
    while plotFreq <= nyquist
        if plotFreq < vLowEdge
            yVal = vLowR
        elsif plotFreq > vHighEdge
            yVal = vHighR
        else
            phase = pi * (plotFreq - vLowEdge) / vSpan
            yVal = vLowR * (0.5 + 0.5 * cos(phase)) + vHighR * (0.5 - 0.5 * cos(phase))
        endif
        Draw line: prevX, prevY, plotFreq, yVal
        prevX = plotFreq
        prevY = yVal
        plotFreq = plotFreq + step
    endwhile

    # crossover band + centre line
    Line width: 1
    Colour: "{0.6, 0.6, 0.6}"
    Draw line: vLowEdge, 0, vLowEdge, 1
    Draw line: vHighEdge, 0, vHighEdge, 1
    Colour: "Black"
    Dotted line
    Draw line: crossover_frequency, 0, crossover_frequency, 1
    Solid line
    Font size: 8
    Text: crossover_frequency, "Centre", 1.04, "Half", string$(crossover_frequency) + " Hz"

    # frame + axes
    Colour: "Black"
    Line width: 1
    Draw inner box
    if nyquist > 15000
        Marks bottom every: 1, 5000, "yes", "yes", "no"
    elsif nyquist > 8000
        Marks bottom every: 1, 2000, "yes", "yes", "no"
    else
        Marks bottom every: 1, 1000, "yes", "yes", "no"
    endif
    Marks left every: 1, 0.5, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Frequency (Hz)"
    Text left: "yes", "Channel gain"

    # ---- Summary panel (grey) ----
    Select inner viewport: 0.6, 7.7, 5.0, 6.0
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.93, 0.93, 0.93}", 0, 1, 0, 1
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 9
    Text: 0.03, "Left", 0.70, "Half", "##Crossover## " + string$(crossover_frequency) + " Hz      ##Width## " + string$(crossover_width) + " Hz      ##Band## " + fixed$(vLowEdge, 0) + " to " + fixed$(vHighEdge, 0) + " Hz      ##Depth## " + fixed$(pan_depth * 100, 0) + "%"
    Colour: "{0.20, 0.40, 0.80}"
    Text: 0.03, "Left", 0.28, "Half", leftLabel$
    Colour: "{0.85, 0.25, 0.20}"
    Text: 0.45, "Left", 0.28, "Half", rightLabel$
    Colour: "Black"
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
span = highEdge - lowEdge
if span < 1
    span = 1
endif
spanStr$ = fixed$(span, 2)

# Lowpass spectrum
selectObject: spectrumFull
spectrumLow = Copy: "low"
selectObject: spectrumLow
Formula: "if x < " + lowEdgeStr$ + " then self else (if x > " + highEdgeStr$ + " then 0 else self * (0.5 + 0.5 * cos(pi * (x - " + lowEdgeStr$ + ") / " + spanStr$ + ")) fi) fi"

# Highpass spectrum
selectObject: spectrumFull
spectrumHigh = Copy: "high"
selectObject: spectrumHigh
Formula: "if x > " + highEdgeStr$ + " then self else (if x < " + lowEdgeStr$ + " then 0 else self * (0.5 - 0.5 * cos(pi * (x - " + lowEdgeStr$ + ") / " + spanStr$ + ")) fi) fi"

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
