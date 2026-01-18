# ============================================================
# Praat AudioTools - Spatial_trajectory_tracker.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025) - Enhanced visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spatial Trajectory Tracker - Analyzes stereo image movement
#   and visualizes panning trajectory over time.
#
# Changelog v0.3:
#   - Added presets for analysis sensitivity
#   - Added polar stereo field visualization
#   - Fixed channel extraction
#   - Added statistics output
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Stereo Sound object."
endif

soundID = selected("Sound")
originalName$ = selected$("Sound")
numChans = Get number of channels

if numChans <> 2
    exitScript: "Input sound must be Stereo (2 channels)."
endif

form Spatial Trajectory Tracker v0.3
    comment === Preset ===
    optionmenu Preset: 1
        option Manual
        option Fast Overview
        option Detailed Analysis
        option Ultra Smooth
        option Transient Sensitive
    comment === Analysis Parameters ===
    positive Frame_length_s 0.02
    positive Hop_size_s 0.01
    real Silence_gate_dB -60.0
    integer Smoothing_frames 10
    comment === Visualization ===
    boolean Draw_visualization 1
    boolean Show_waveform 1
    boolean Show_polar_plot 1
endform

# ============================================================
# Presets
# ============================================================
if preset = 2
    # Fast Overview
    frame_length_s = 0.05
    hop_size_s = 0.025
    smoothing_frames = 5
    silence_gate_dB = -50
    presetName$ = "FastOverview"
elsif preset = 3
    # Detailed Analysis
    frame_length_s = 0.01
    hop_size_s = 0.005
    smoothing_frames = 15
    silence_gate_dB = -65
    presetName$ = "Detailed"
elsif preset = 4
    # Ultra Smooth
    frame_length_s = 0.03
    hop_size_s = 0.015
    smoothing_frames = 30
    silence_gate_dB = -55
    presetName$ = "UltraSmooth"
elsif preset = 5
    # Transient Sensitive
    frame_length_s = 0.005
    hop_size_s = 0.002
    smoothing_frames = 3
    silence_gate_dB = -70
    presetName$ = "Transient"
else
    presetName$ = "Manual"
endif

# ==============================================================================
# 1. SETUP
# ==============================================================================
clearinfo
writeInfoLine: "=== Spatial Trajectory Tracker v0.3 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Input: ", originalName$
appendInfoLine: ""

selectObject: soundID
dur = Get total duration
sr = Get sampling frequency

appendInfoLine: "Duration: ", fixed$(dur, 3), " s"
appendInfoLine: "Frame: ", frame_length_s * 1000, " ms, Hop: ", hop_size_s * 1000, " ms"
appendInfoLine: ""

# ==============================================================================
# 2. ANALYZE STEREO FIELD
# ==============================================================================
appendInfoLine: "Analyzing spatial trajectory..."

# Extract Channels (fixed: use explicit channel extraction)
selectObject: soundID
Extract one channel: 1
ch1ID = selected("Sound")

selectObject: soundID
Extract one channel: 2
ch2ID = selected("Sound")

# Calculate frame count
numFrames = floor((dur - frame_length_s) / hop_size_s)
if numFrames < 2
    removeObject: ch1ID, ch2ID
    exitScript: "Sound too short for analysis."
endif

appendInfoLine: "Frames: ", numFrames

# Create Table for data
Create Table with column names: "pan_data", numFrames, "time pan_raw pan_smooth energy_L energy_R width"
tableID = selected("Table")

# Threshold calculation
gateThreshold = 10 ^ (silence_gate_dB / 20)
epsilon = 0.0000001
lastValidPan = 0

# Statistics accumulators
sumPan = 0
sumPanSq = 0
maxPanL = 0
maxPanR = 0
validFrames = 0

# --- ANALYSIS LOOP ---
for i from 1 to numFrames
    tStart = (i - 1) * hop_size_s
    tEnd = tStart + frame_length_s
    tMid = (tStart + tEnd) / 2
    
    selectObject: ch1ID
    rmsL = Get root-mean-square: tStart, tEnd
    selectObject: ch2ID
    rmsR = Get root-mean-square: tStart, tEnd
    
    energyL = rmsL * rmsL
    energyR = rmsR * rmsR
    totalRMS = sqrt(energyL + energyR)
    
    # Calculate stereo width (correlation-based approximation)
    if energyL + energyR > epsilon
        width = 1 - abs(energyL - energyR) / (energyL + energyR + epsilon)
    else
        width = 0
    endif
    
    # Calculate Pan (-1 to +1)
    if totalRMS > gateThreshold
        calcPan = (energyR - energyL) / (energyR + energyL + epsilon)
        
        # Clamp
        if calcPan > 1
            calcPan = 1
        elsif calcPan < -1
            calcPan = -1
        endif
        lastValidPan = calcPan
        
        # Statistics
        sumPan = sumPan + calcPan
        sumPanSq = sumPanSq + calcPan * calcPan
        validFrames = validFrames + 1
        
        if calcPan < maxPanL
            maxPanL = calcPan
        endif
        if calcPan > maxPanR
            maxPanR = calcPan
        endif
    else
        calcPan = lastValidPan
    endif
    
    selectObject: tableID
    Set numeric value: i, "time", tMid
    Set numeric value: i, "pan_raw", calcPan
    Set numeric value: i, "energy_L", energyL
    Set numeric value: i, "energy_R", energyR
    Set numeric value: i, "width", width
    Set numeric value: i, "pan_smooth", calcPan
endfor

removeObject: ch1ID, ch2ID

# --- SMOOTHING LOOP ---
if smoothing_frames > 1
    selectObject: tableID
    halfWin = floor(smoothing_frames / 2)
    
    for i from 1 to numFrames
        startF = max(1, i - halfWin)
        endF = min(numFrames, i + halfWin)
        sum = 0
        count = 0
        
        for j from startF to endF
            val = Get value: j, "pan_raw"
            sum = sum + val
            count = count + 1
        endfor
        
        avg = sum / count
        Set numeric value: i, "pan_smooth", avg
    endfor
endif

# --- STATISTICS ---
if validFrames > 0
    meanPan = sumPan / validFrames
    variancePan = (sumPanSq / validFrames) - (meanPan * meanPan)
    if variancePan < 0
        variancePan = 0
    endif
    stdPan = sqrt(variancePan)
    panRange = maxPanR - maxPanL
else
    meanPan = 0
    stdPan = 0
    panRange = 0
    maxPanL = 0
    maxPanR = 0
endif

# Determine bias description (fixed: no inline if)
if meanPan < -0.1
    biasDesc$ = "left-biased"
elsif meanPan > 0.1
    biasDesc$ = "right-biased"
else
    biasDesc$ = "centered"
endif

# Determine movement description
if stdPan < 0.1
    moveDesc$ = "static"
elsif stdPan < 0.3
    moveDesc$ = "moderate movement"
else
    moveDesc$ = "dynamic"
endif

appendInfoLine: ""
appendInfoLine: "=== Statistics ==="
appendInfoLine: "Mean pan: ", fixed$(meanPan, 3), " (", biasDesc$, ")"
appendInfoLine: "Pan std: ", fixed$(stdPan, 3), " (", moveDesc$, ")"
appendInfoLine: "Pan range: ", fixed$(maxPanL, 2), " to ", fixed$(maxPanR, 2), " (", fixed$(panRange, 2), " total)"

# ==============================================================================
# 3. VISUALIZATION
# ==============================================================================
if draw_visualization
    Erase all
    Font size: 10
    
    # Determine layout based on options
    if show_waveform and show_polar_plot
        # 3 panels
        trajTop = 0
        trajBottom = 2.5
        polarTop = 2.6
        polarBottom = 5.0
        waveTop = 5.1
        waveBottom = 6.5
    elsif show_waveform
        # 2 panels: trajectory + waveform
        trajTop = 0
        trajBottom = 3.5
        waveTop = 3.8
        waveBottom = 5.5
        polarTop = 0
        polarBottom = 0
    elsif show_polar_plot
        # 2 panels: trajectory + polar
        trajTop = 0
        trajBottom = 3.0
        polarTop = 3.2
        polarBottom = 6.0
        waveTop = 0
        waveBottom = 0
    else
        # 1 panel: trajectory only
        trajTop = 0
        trajBottom = 5.0
        polarTop = 0
        polarBottom = 0
        waveTop = 0
        waveBottom = 0
    endif
    
    # === PLOT 1: PANNING TRAJECTORY ===
    Select outer viewport: 0, 8, trajTop, trajBottom
    Select inner viewport: 0.8, 7.5, trajTop + 0.4, trajBottom - 0.3
    
    Axes: 0, dur, -1.1, 1.1
    
    # Background & Guides
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, dur, -1.1, 1.1
    
    # Left/Right zones
    Paint rectangle: "{0.95, 0.95, 1.0}", 0, dur, 0, 1.1
    Paint rectangle: "{1.0, 0.95, 0.95}", 0, dur, -1.1, 0
    
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, dur, 0
    Dotted line
    Draw line: 0, 0.5, dur, 0.5
    Draw line: 0, -0.5, dur, -0.5
    Solid line
    
    # Labels
    Colour: "{0.5, 0.5, 0.5}"
    Font size: 8
    Text: -dur*0.02, "right", 1, "half", "R"
    Text: -dur*0.02, "right", 0, "half", "C"
    Text: -dur*0.02, "right", -1, "half", "L"
    Font size: 10
    
    # Draw raw data (light)
    selectObject: tableID
    Colour: "{0.8, 0.8, 0.9}"
    Line width: 1
    
    for i from 1 to numFrames - 1
        t1 = Get value: i, "time"
        p1 = Get value: i, "pan_raw"
        t2 = Get value: i+1, "time"
        p2 = Get value: i+1, "pan_raw"
        
        if p1 <> undefined and p2 <> undefined
            Draw line: t1, p1, t2, p2
        endif
    endfor
    
    # Draw smoothed data (bold)
    Colour: "{0.0, 0.3, 0.8}"
    Line width: 2
    
    for i from 1 to numFrames - 1
        t1 = Get value: i, "time"
        p1 = Get value: i, "pan_smooth"
        t2 = Get value: i+1, "time"
        p2 = Get value: i+1, "pan_smooth"
        
        if p1 <> undefined and p2 <> undefined
            Draw line: t1, p1, t2, p2
        endif
    endfor
    
    # Mean line
    Colour: "{0.8, 0.2, 0.2}"
    Line width: 1
    Dotted line
    Draw line: 0, meanPan, dur, meanPan
    Solid line
    
    # Frame
    Colour: "Black"
    Line width: 1
    Draw inner box
    Text top: "no", "Spatial Trajectory: " + originalName$ + " [" + presetName$ + "]"
    Text left: "yes", "Pan"
    
    # === PLOT 2: POLAR STEREO FIELD ===
    if show_polar_plot
        Select outer viewport: 0, 4, polarTop, polarBottom
        Select inner viewport: 0.5, 3.5, polarTop + 0.3, polarBottom - 0.2
        
        # Circular axes
        Axes: -1.3, 1.3, -0.3, 1.3
        
        # Draw semicircle outline
        Colour: "{0.8, 0.8, 0.8}"
        Line width: 1
        for angle from 0 to 180
            a1 = (angle - 90) * pi / 180
            a2 = (angle + 1 - 90) * pi / 180
            Draw line: cos(a1), sin(a1), cos(a2), sin(a2)
        endfor
        
        # Draw guide lines
        Dotted line
        Draw line: 0, 0, 0, 1
        Draw line: 0, 0, -0.707, 0.707
        Draw line: 0, 0, 0.707, 0.707
        Draw line: 0, 0, -1, 0
        Draw line: 0, 0, 1, 0
        Solid line
        
        # Labels
        Font size: 8
        Colour: "{0.5, 0.5, 0.5}"
        Text: 0, "centre", 1.15, "half", "C"
        Text: -1.1, "centre", 0, "half", "L"
        Text: 1.1, "centre", 0, "half", "R"
        
        # Plot points (pan → angle, energy → radius)
        selectObject: tableID
        
        for i from 1 to numFrames
            pan = Get value: i, "pan_smooth"
            eL = Get value: i, "energy_L"
            eR = Get value: i, "energy_R"
            
            if pan <> undefined
                # Convert pan to angle (-1=left=180°, 0=center=90°, +1=right=0°)
                angle = (90 - pan * 90) * pi / 180
                
                # Radius based on total energy (normalized)
                totalE = sqrt(eL + eR)
                radius = min(1, totalE * 10)
                
                x = cos(angle) * radius
                y = sin(angle) * radius
                
                # Color by time (blue→red)
                progress = i / numFrames
                rVal = progress
                bVal = 1 - progress
                rVal$ = fixed$(rVal, 2)
                bVal$ = fixed$(bVal, 2)
                
                pointSize = 0.02
                Paint rectangle: "{" + rVal$ + ", 0.2, " + bVal$ + "}", x - pointSize, x + pointSize, y - pointSize, y + pointSize
            endif
        endfor
        
        Colour: "Black"
        Font size: 9
        Text: 0, "centre", -0.15, "half", "Stereo Field (blue=start, red=end)"
        Font size: 10
        
        # Stats panel
        Select outer viewport: 4, 8, polarTop, polarBottom
        Select inner viewport: 4.3, 7.7, polarTop + 0.5, polarBottom - 0.3
        
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
        
        Colour: "{0.3, 0.3, 0.3}"
        Font size: 9
        Text: 0.05, "left", 0.9, "half", "Mean pan: " + fixed$(meanPan, 3)
        Text: 0.05, "left", 0.75, "half", "Std dev: " + fixed$(stdPan, 3)
        Text: 0.05, "left", 0.6, "half", "Range: " + fixed$(maxPanL, 2) + " to " + fixed$(maxPanR, 2)
        Text: 0.05, "left", 0.45, "half", "Frames: " + string$(numFrames)
        validPercent = round(100 * validFrames / numFrames)
        Text: 0.05, "left", 0.3, "half", "Valid: " + string$(validFrames) + " (" + string$(validPercent) + "%)"
        
        # Bias indicator (fixed: no inline if)
        if meanPan < -0.1
            biasText$ = "LEFT-BIASED"
            Colour: "{0.8, 0.3, 0.3}"
        elsif meanPan > 0.1
            biasText$ = "RIGHT-BIASED"
            Colour: "{0.3, 0.3, 0.8}"
        else
            biasText$ = "CENTERED"
            Colour: "{0.3, 0.6, 0.3}"
        endif
        Font size: 11
        Text: 0.5, "centre", 0.12, "half", biasText$
        
        Colour: "Black"
        Line width: 1
        Draw inner box
        Font size: 10
    endif
    
    # === PLOT 3: WAVEFORM ===
    if show_waveform
        Select outer viewport: 0, 8, waveTop, waveBottom
        Select inner viewport: 0.8, 7.5, waveTop + 0.15, waveBottom - 0.15
        
        selectObject: soundID
        Colour: "{0.4, 0.4, 0.4}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        
        Colour: "Black"
        Draw inner box
        Text bottom: "yes", "Time (s)"
        Text left: "yes", "Amp"
    endif
endif

# ==============================================================================
# FINAL SELECTION
# ==============================================================================
selectObject: tableID
Rename: "SpatialAnalysis_" + originalName$ + "_" + presetName$

selectObject: soundID
plusObject: tableID

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Analysis table: SpatialAnalysis_", originalName$, "_", presetName$