# ============================================================
# Praat AudioTools - Wah-Wah Effect
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Wah-Wah Effect
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Wah-Wah Effect
    optionmenu Preset: 1
        option Custom
        option Classic Wah (slow)
        option Funky Wah (fast)
        option Auto-Wah (envelope)
        option Crying Baby
        option Talk Box Style
        option Subtle Sweep
    comment === Wah Parameters ===
    positive Wah_rate_(Hz) 1.5
    positive Min_frequency_(Hz) 300
    positive Max_frequency_(Hz) 2000
    positive Bandwidth_(Hz) 400
    positive Resonance 2.0
    comment (1=flat, higher=more resonant peak)
    comment === Stereo ===
    real Stereo_offset 0.1
    comment (phase offset between L/R, 0-0.5)
    comment === Output ===
    boolean Draw_response 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================
if preset = 2
    # Classic Wah (slow)
    wah_rate = 0.8
    min_frequency = 400
    max_frequency = 1800
    bandwidth = 350
    resonance = 2.5
    stereo_offset = 0.1
elsif preset = 3
    # Funky Wah (fast)
    wah_rate = 3.5
    min_frequency = 350
    max_frequency = 2500
    bandwidth = 300
    resonance = 3.0
    stereo_offset = 0.15
elsif preset = 4
    # Auto-Wah (envelope follower style - we simulate with faster rate)
    wah_rate = 2.0
    min_frequency = 250
    max_frequency = 2200
    bandwidth = 400
    resonance = 2.0
    stereo_offset = 0.05
elsif preset = 5
    # Crying Baby
    wah_rate = 1.2
    min_frequency = 500
    max_frequency = 2800
    bandwidth = 250
    resonance = 4.0
    stereo_offset = 0.08
elsif preset = 6
    # Talk Box Style
    wah_rate = 0.6
    min_frequency = 300
    max_frequency = 3500
    bandwidth = 500
    resonance = 1.8
    stereo_offset = 0.2
elsif preset = 7
    # Subtle Sweep
    wah_rate = 0.4
    min_frequency = 500
    max_frequency = 1500
    bandwidth = 600
    resonance = 1.5
    stereo_offset = 0.05
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
totalDuration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels
nyquist = sampleRate / 2

if max_frequency >= nyquist * 0.9
    max_frequency = nyquist * 0.8
endif

if totalDuration < 0.1
    exitScript: "Sound too short (min 0.1s)."
endif

# Calculate number of segments based on wah rate
# At least 20 segments per wah cycle for smooth sweep
segmentsPerCycle = 24
totalCycles = totalDuration * wah_rate
numSegments = max(10, round(totalCycles * segmentsPerCycle))
numSegments = min(numSegments, 500)
segmentDur = totalDuration / numSegments

writeInfoLine: "=== Wah-Wah Effect ==="
appendInfoLine: "Rate: ", fixed$(wah_rate, 2), " Hz"
appendInfoLine: "Frequency range: ", round(min_frequency), " - ", round(max_frequency), " Hz"
appendInfoLine: "Segments: ", numSegments
appendInfoLine: ""

# ============================================================
# DRAW WAH RESPONSE
# ============================================================
if draw_response
    Erase all
    Select outer viewport: 0, 6, 0, 4.5
    
    # Show frequency sweep over time
    Axes: 0, totalDuration, 0, nyquist * 0.5
    
    Colour: "Black"
    Draw inner box
    
    # Grid
    Colour: "{0.8,0.8,0.8}"
    
    # Horizontal grid (frequency)
    gridF = 500
    while gridF < nyquist * 0.5
        Draw line: 0, gridF, totalDuration, gridF
        gridF = gridF + 500
    endwhile
    
    # Draw wah sweep - Left channel (Blue)
    Colour: "Blue"
    Line width: 2
    
    step = totalDuration / 200
    plotTime = 0
    
    # First point
    phase = 0
    wahPos = 0.5 + 0.5 * sin(2 * pi * phase)
    centerFreq = min_frequency + wahPos * (max_frequency - min_frequency)
    prevTime = 0
    prevFreq = centerFreq
    
    plotTime = step
    while plotTime <= totalDuration
        phase = wah_rate * plotTime
        wahPos = 0.5 + 0.5 * sin(2 * pi * phase)
        centerFreq = min_frequency + wahPos * (max_frequency - min_frequency)
        
        Draw line: prevTime, prevFreq, plotTime, centerFreq
        prevTime = plotTime
        prevFreq = centerFreq
        plotTime = plotTime + step
    endwhile
    
    # Draw wah sweep - Right channel (Red) with offset
    Colour: "Red"
    
    plotTime = 0
    phase = stereo_offset
    wahPos = 0.5 + 0.5 * sin(2 * pi * phase)
    centerFreq = min_frequency + wahPos * (max_frequency - min_frequency)
    prevTime = 0
    prevFreq = centerFreq
    
    plotTime = step
    while plotTime <= totalDuration
        phase = wah_rate * plotTime + stereo_offset
        wahPos = 0.5 + 0.5 * sin(2 * pi * phase)
        centerFreq = min_frequency + wahPos * (max_frequency - min_frequency)
        
        Draw line: prevTime, prevFreq, plotTime, centerFreq
        prevTime = plotTime
        prevFreq = centerFreq
        plotTime = plotTime + step
    endwhile
    
    # Draw bandwidth region (shaded)
    Colour: "{0.9,0.9,1.0}"
    # Just indicate with dashed lines at min/max
    Colour: "{0.6,0.6,0.6}"
    Line width: 1
    Dotted line
    Draw line: 0, min_frequency, totalDuration, min_frequency
    Draw line: 0, max_frequency, totalDuration, max_frequency
    Solid line
    
    # Labels
    Colour: "Black"
    Font size: 12
    Text: totalDuration / 2, "Centre", nyquist * 0.5 + 300, "Half", "Wah-Wah Frequency Sweep"
    
    Font size: 10
    Text: totalDuration / 2, "Centre", -200, "Half", "Time (s)"
    
    # Legend
    Font size: 9
    Colour: "Blue"
    Text: totalDuration * 0.85, "Centre", nyquist * 0.45, "Half", "Left"
    Colour: "Red"
    Text: totalDuration * 0.85, "Centre", nyquist * 0.40, "Half", "Right"
    
    Colour: "{0.4,0.4,0.4}"
    Text: totalDuration * 0.15, "Centre", nyquist * 0.45, "Half", "Rate: " + fixed$(wah_rate, 1) + " Hz"
    Text: totalDuration * 0.15, "Centre", nyquist * 0.40, "Half", "BW: " + string$(round(bandwidth)) + " Hz"
    
    # Axis marks
    Colour: "Black"
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    Marks left every: 1, 500, "yes", "yes", "no"
    
    Line width: 1
endif

# ============================================================
# PREPARE SOURCE
# ============================================================
selectObject: originalID
if numChannels > 1
    monoSource = Convert to mono
else
    monoSource = Copy: "mono"
endif

# ============================================================
# PROCESS WAH-WAH
# ============================================================
appendInfoLine: "Processing..."

# Create output channels
leftOut = Create Sound from formula: "leftOut", 1, 0, totalDuration, sampleRate, "0"
rightOut = Create Sound from formula: "rightOut", 1, 0, totalDuration, sampleRate, "0"

for seg from 1 to numSegments
    # Segment time boundaries
    segStart = (seg - 1) * segmentDur
    segEnd = seg * segmentDur
    segMid = (segStart + segEnd) / 2
    
    # Calculate wah position (0-1) based on sine wave
    phaseL = wah_rate * segMid
    phaseR = wah_rate * segMid + stereo_offset
    
    wahPosL = 0.5 + 0.5 * sin(2 * pi * phaseL)
    wahPosR = 0.5 + 0.5 * sin(2 * pi * phaseR)
    
    # Calculate center frequencies
    centerL = min_frequency + wahPosL * (max_frequency - min_frequency)
    centerR = min_frequency + wahPosR * (max_frequency - min_frequency)
    
    # Calculate filter bounds
    lowL = max(20, centerL - bandwidth / 2)
    highL = min(nyquist - 100, centerL + bandwidth / 2)
    lowR = max(20, centerR - bandwidth / 2)
    highR = min(nyquist - 100, centerR + bandwidth / 2)
    
    # Ensure valid range
    if highL <= lowL
        highL = lowL + 100
    endif
    if highR <= lowR
        highR = lowR + 100
    endif
    
    # Extract segment with small overlap for crossfade
    overlapDur = min(0.01, segmentDur * 0.1)
    extractStart = max(0, segStart - overlapDur)
    extractEnd = min(totalDuration, segEnd + overlapDur)
    
    selectObject: monoSource
    segSound = Extract part: extractStart, extractEnd, "Hanning", 1, "no"
    
    # Process Left channel
    selectObject: segSound
    segLeft = Filter (pass Hann band): lowL, highL, bandwidth * 0.25
    
    # Apply resonance boost at center frequency
    if resonance > 1
        selectObject: segLeft
        To Spectrum: "yes"
        specL = selected("Spectrum")
        
        # Boost around center frequency
        boostWidth = bandwidth * 0.3
        centerLStr$ = fixed$(centerL, 2)
        boostWidthStr$ = fixed$(boostWidth, 2)
        resStr$ = fixed$(resonance, 3)
        
        selectObject: specL
        Formula: "self * (1 + (" + resStr$ + " - 1) * exp(-((x - " + centerLStr$ + ")/" + boostWidthStr$ + ")^2))"
        
        resynthL = To Sound
        removeObject: specL
        
        # Replace segLeft with resonant version
        removeObject: segLeft
        segLeft = resynthL
    endif
    
    # Process Right channel
    selectObject: segSound
    segRight = Filter (pass Hann band): lowR, highR, bandwidth * 0.25
    
    if resonance > 1
        selectObject: segRight
        To Spectrum: "yes"
        specR = selected("Spectrum")
        
        centerRStr$ = fixed$(centerR, 2)
        
        selectObject: specR
        Formula: "self * (1 + (" + resStr$ + " - 1) * exp(-((x - " + centerRStr$ + ")/" + boostWidthStr$ + ")^2))"
        
        resynthR = To Sound
        removeObject: specR
        
        removeObject: segRight
        segRight = resynthR
    endif
    
    # Crop to actual segment duration (remove overlap tails)
    offsetInExtract = segStart - extractStart
    
    selectObject: segLeft
    Rename: "segL"
    selectObject: segRight
    Rename: "segR"
    
    # Add to output channels
    segStartStr$ = fixed$(segStart, 8)
    offsetStr$ = fixed$(offsetInExtract, 8)
    
    selectObject: leftOut
    Formula (part): segStart, segEnd, 1, 1, "self + Sound_segL(x - " + segStartStr$ + " + " + offsetStr$ + ")"
    
    selectObject: rightOut
    Formula (part): segStart, segEnd, 1, 1, "self + Sound_segR(x - " + segStartStr$ + " + " + offsetStr$ + ")"
    
    # Cleanup segment objects
    removeObject: segSound, segLeft, segRight
    
    # Progress
    if seg mod 20 = 0
        appendInfoLine: "  ", seg, "/", numSegments
    endif
endfor

# ============================================================
# COMBINE TO STEREO
# ============================================================
appendInfoLine: "Finalizing..."

selectObject: leftOut
plusObject: rightOut
stereoOut = Combine to stereo
Rename: originalName$ + "_wahwah"

# Normalize
selectObject: stereoOut
Scale peak: 0.95

# Cleanup
removeObject: monoSource, leftOut, rightOut

# ============================================================
# OUTPUT
# ============================================================
appendInfoLine: ""
appendInfoLine: "Complete!"
appendInfoLine: "Output: ", originalName$, "_wahwah"

if play_result
    selectObject: stereoOut
    Play
endif
