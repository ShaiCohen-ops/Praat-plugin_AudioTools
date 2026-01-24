# ============================================================
# Praat AudioTools - Multi-Layer_Audio_Visualizer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.1 (2025) - Professional Visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Multi-Layer Audio Visualizer (EAnalysis Style)
#   Displays multiple synchronized analysis streams in horizontal layers.
#   Professional visualization with labeled axes and color-coded tracks.
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

soundID = selected("Sound")
sound$ = selected$("Sound")

form Multi-Layer Audio Visualizer v2.1
    comment === Layers to Display ===
    boolean Draw_spectrogram 1
    boolean Draw_waveform 1
    boolean Draw_intensity 1
    boolean Draw_pitch 1
    boolean Draw_spectral_centroid 1
    boolean Draw_formants 1
    boolean Draw_pulses 1
    comment === Formant Options ===
    boolean Draw_F1 1
    boolean Draw_F2 1
    boolean Draw_F3 1
    comment === Analysis Parameters ===
    positive Time_step 0.01
    positive Pitch_floor 75
    positive Pitch_ceiling 600
    positive Spectrogram_max_freq 5000
    comment === Intensity Range ===
    positive Intensity_min_dB 40
    positive Intensity_max_dB 80
endform

# === Setup ===
selectObject: soundID
duration = Get total duration
startTime = Get start time
endTime = Get end time
sampleRate = Get sampling frequency

clearinfo
writeInfoLine: "=== Multi-Layer Audio Visualizer v2.1 ==="
appendInfoLine: "Sound: ", sound$
appendInfoLine: "Duration: ", fixed$(duration, 3), " s"
appendInfoLine: ""

# ============================================================
# CREATE ANALYSIS OBJECTS
# ============================================================

appendInfoLine: "Creating analysis objects..."

if draw_spectrogram or draw_spectral_centroid
    selectObject: soundID
    spectrogramID = To Spectrogram: 0.005, spectrogram_max_freq, 0.002, 20, "Gaussian"
endif

if draw_intensity
    selectObject: soundID
    intensityID = To Intensity: 75, time_step, "yes"
endif

if draw_pitch or draw_pulses
    selectObject: soundID
    pitchID_raw = To Pitch: time_step, pitch_floor, pitch_ceiling
    selectObject: pitchID_raw
    pitchID = Smooth: 10
    removeObject: pitchID_raw
endif

if draw_pulses
    selectObject: soundID
    plusObject: pitchID
    pulsesID = To PointProcess (cc)
endif

if draw_formants
    selectObject: soundID
    formantID = To Formant (burg): time_step, 5, 5500, 0.025, 50
endif

appendInfoLine: "Drawing layers..."

# ============================================================
# LAYOUT CALCULATION
# ============================================================

numLayers = 0
if draw_spectrogram
    numLayers += 1
endif
if draw_waveform
    numLayers += 1
endif
if draw_intensity
    numLayers += 1
endif
if draw_pitch
    numLayers += 1
endif
if draw_spectral_centroid
    numLayers += 1
endif
if draw_formants
    numLayers += 1
endif
if draw_pulses
    numLayers += 1
endif

if numLayers = 0
    exitScript: "Please select at least one layer to draw."
endif

# --- VIEWPORT SETTINGS ---
totalWidth = 8.0
totalHeight = 7.0
titleHeight = 0.4
timeAxisHeight = 0.5
labelWidth = 1.2
scaleWidth = 0.5
dataLeft = labelWidth
dataRight = totalWidth - scaleWidth

availableHeight = totalHeight - titleHeight - timeAxisHeight
layerHeight = availableHeight / numLayers

# Minimum layer height for readability
if layerHeight < 0.5
    layerHeight = 0.5
endif

# ============================================================
# DRAWING
# ============================================================

Erase all
Font size: 10
Line width: 1

# --- Title Bar (clean, no dark background) ---
Select outer viewport: 0, totalWidth, 0, titleHeight
Axes: 0, 1, 0, 1

Colour: "Black"
Font size: 12
Text: 0.5, "centre", 0.5, "half", "##Multi-Layer Audio Visualizer:## " + sound$

currentY = titleHeight
layerNum = 0

# ============================================================
# LAYER: SPECTROGRAM
# ============================================================

if draw_spectrogram
    layerNum += 1
    layerTop = currentY
    layerBottom = currentY + layerHeight
    
    appendInfoLine: "  [", layerNum, "] Spectrogram"
    
    # --- Data pane ---
    Select outer viewport: dataLeft, dataRight, layerTop, layerBottom
    Select inner viewport: dataLeft + 0.05, dataRight - 0.05, layerTop + 0.03, layerBottom - 0.03
    
    selectObject: spectrogramID
    Paint: startTime, endTime, 0, spectrogram_max_freq, 100, "yes", 50, 6, 0, "no"
    
    Colour: "{0.3, 0.3, 0.3}"
    Line width: 0.5
    Draw inner box
    
    # --- Label pane (no background) ---
    Select outer viewport: 0, labelWidth, layerTop, layerBottom
    Axes: 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.2, 0.2, 0.3}"
    Text: 0.95, "right", 0.6, "half", "Spectrogram"
    Font size: 7
    Colour: "{0.5, 0.5, 0.55}"
    Text: 1.95, "right", 0.25, "half", "0-" + string$(spectrogram_max_freq) + " Hz"
    
    # --- Scale pane ---
    Select outer viewport: dataRight, totalWidth, layerTop, layerBottom
    Axes: 0, 1, 0, spectrogram_max_freq
    
    Font size: 6
    Colour: "{0.4, 0.4, 0.45}"
    Text: 0.15, "left", spectrogram_max_freq * 0.92, "half", string$(spectrogram_max_freq)
    Text: 0.15, "left", spectrogram_max_freq * 0.5, "half", string$(round(spectrogram_max_freq / 2))
    Text: 0.15, "left", spectrogram_max_freq * 0.08, "half", "0"
    
    currentY = layerBottom
endif

# ============================================================
# LAYER: WAVEFORM
# ============================================================

if draw_waveform
    layerNum += 1
    layerTop = currentY
    layerBottom = currentY + layerHeight
    
    appendInfoLine: "  [", layerNum, "] Waveform"
    
    # --- Data pane ---
    Select outer viewport: dataLeft, dataRight, layerTop, layerBottom
    Select inner viewport: dataLeft + 0.05, dataRight - 0.05, layerTop + 0.03, layerBottom - 0.03
    
    Axes: startTime, endTime, -1, 1
    
    # Background
    Colour: "{0.97, 0.97, 0.98}"
    Paint rectangle: "{0.97, 0.97, 0.98}", startTime, endTime, -1, 1
    
    # Zero line
    Colour: "{0.85, 0.85, 0.88}"
    Line width: 0.5
    Dotted line
    Draw line: startTime, 0, endTime, 0
    Solid line
    
    # Waveform
    selectObject: soundID
    Colour: "{0.25, 0.35, 0.5}"
    Line width: 0.8
    Draw: startTime, endTime, -1, 1, "no", "Curve"
    
    Colour: "{0.3, 0.3, 0.3}"
    Line width: 0.5
    Draw inner box
    
    # --- Label pane (no background) ---
    Select outer viewport: 0, labelWidth, layerTop, layerBottom
    Axes: 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.25, 0.35, 0.5}"
    Text: 0.95, "right", 0.6, "half", "Waveform"
    Font size: 7
    Colour: "{0.5, 0.5, 0.55}"
    Text: 1.95, "right", 0.25, "half", "Amplitude"
    
    # --- Scale pane ---
    Select outer viewport: dataRight, totalWidth, layerTop, layerBottom
    Axes: 0, 1, -1, 1
    
    Font size: 6
    Colour: "{0.4, 0.4, 0.45}"
    Text: 0.15, "left", 0.85, "half", "+1"
    Text: 0.15, "left", 0, "half", "0"
    Text: 0.15, "left", -0.85, "half", "-1"
    
    currentY = layerBottom
endif

# ============================================================
# LAYER: INTENSITY
# ============================================================

if draw_intensity
    layerNum += 1
    layerTop = currentY
    layerBottom = currentY + layerHeight
    
    appendInfoLine: "  [", layerNum, "] Intensity"
    
    # --- Data pane ---
    Select outer viewport: dataLeft, dataRight, layerTop, layerBottom
    Select inner viewport: dataLeft + 0.05, dataRight - 0.05, layerTop + 0.03, layerBottom - 0.03
    
    Axes: startTime, endTime, intensity_min_dB, intensity_max_dB
    
    # Background
    Colour: "{0.94, 0.96, 0.99}"
    Paint rectangle: "{0.94, 0.96, 0.99}", startTime, endTime, intensity_min_dB, intensity_max_dB
    
    # Grid lines
    Colour: "{0.88, 0.90, 0.94}"
    Line width: 0.5
    gridDB = intensity_min_dB + 10
    while gridDB < intensity_max_dB
        Draw line: startTime, gridDB, endTime, gridDB
        gridDB = gridDB + 10
    endwhile
    
    # Intensity curve with fill
    selectObject: intensityID
    
    # Fill area under curve
    Colour: "{0.75, 0.85, 0.95}"
    numFrames = floor(duration / time_step)
    for i from 1 to numFrames
        t = startTime + (i - 1) * time_step
        if t <= endTime
            selectObject: intensityID
            val = Get value at time: t, "Cubic"
            if val <> undefined and val > intensity_min_dB
                Paint rectangle: "{0.75, 0.85, 0.95}", t, t + time_step, intensity_min_dB, val
            endif
        endif
    endfor
    
    # Curve line
    selectObject: intensityID
    Colour: "{0.2, 0.45, 0.75}"
    Line width: 2
    Draw: startTime, endTime, intensity_min_dB, intensity_max_dB, "no"
    
    Colour: "{0.3, 0.3, 0.3}"
    Line width: 0.5
    Draw inner box
    
    # --- Label pane (no background) ---
    Select outer viewport: 0, labelWidth, layerTop, layerBottom
    Axes: 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.2, 0.45, 0.75}"
    Text: 0.95, "right", 0.6, "half", "Intensity"
    Font size: 7
    Colour: "{0.5, 0.5, 0.55}"
    Text: 1.95, "right", 0.25, "half", "dB SPL"
    
    # --- Scale pane ---
    Select outer viewport: dataRight, totalWidth, layerTop, layerBottom
    Axes: 0, 1, intensity_min_dB, intensity_max_dB
    
    Font size: 6
    Colour: "{0.4, 0.4, 0.45}"
    Text: 0.15, "left", intensity_max_dB - 3, "half", string$(intensity_max_dB)
    midDB = (intensity_min_dB + intensity_max_dB) / 2
    Text: 0.15, "left", midDB, "half", string$(midDB)
    Text: 0.15, "left", intensity_min_dB + 3, "half", string$(intensity_min_dB)
    
    currentY = layerBottom
endif

# ============================================================
# LAYER: PITCH (F0)
# ============================================================

if draw_pitch
    layerNum += 1
    layerTop = currentY
    layerBottom = currentY + layerHeight
    
    appendInfoLine: "  [", layerNum, "] Pitch (F0)"
    
    # --- Data pane ---
    Select outer viewport: dataLeft, dataRight, layerTop, layerBottom
    Select inner viewport: dataLeft + 0.05, dataRight - 0.05, layerTop + 0.03, layerBottom - 0.03
    
    Axes: startTime, endTime, pitch_floor, pitch_ceiling
    
    # Background
    Colour: "{0.98, 0.94, 0.97}"
    Paint rectangle: "{0.98, 0.94, 0.97}", startTime, endTime, pitch_floor, pitch_ceiling
    
    # Musical reference lines (octaves from A=110)
    Colour: "{0.92, 0.88, 0.91}"
    Line width: 0.5
    Dotted line
    refPitch = 110
    while refPitch <= pitch_ceiling
        if refPitch >= pitch_floor
            Draw line: startTime, refPitch, endTime, refPitch
        endif
        refPitch = refPitch * 2
    endwhile
    Solid line
    
    # Pitch contour
    selectObject: pitchID
    Colour: "{0.75, 0.15, 0.55}"
    Line width: 2.5
    
    numFrames = floor(duration / time_step)
    prevVoiced = 0
    prevT = 0
    prevP = 0
    
    for i from 1 to numFrames
        t = startTime + (i - 1) * time_step
        if t <= endTime
            selectObject: pitchID
            p = Get value at time: t, "Hertz", "Linear"
            if p <> undefined and p >= pitch_floor and p <= pitch_ceiling
                if prevVoiced = 1
                    Draw line: prevT, prevP, t, p
                endif
                prevVoiced = 1
                prevT = t
                prevP = p
            else
                prevVoiced = 0
            endif
        endif
    endfor
    
    Colour: "{0.3, 0.3, 0.3}"
    Line width: 0.5
    Draw inner box
    
    # --- Label pane (no background) ---
    Select outer viewport: 0, labelWidth, layerTop, layerBottom
    Axes: 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.75, 0.15, 0.55}"
    Text: 0.95, "right", 0.6, "half", "Pitch (F%%0%)"
    Font size: 7
    Colour: "{0.5, 0.5, 0.55}"
    Text: 1.95, "right", 0.25, "half", "Hz"
    
    # --- Scale pane ---
    Select outer viewport: dataRight, totalWidth, layerTop, layerBottom
    Axes: 0, 1, pitch_floor, pitch_ceiling
    
    Font size: 6
    Colour: "{0.4, 0.4, 0.45}"
    Text: 0.15, "left", pitch_ceiling - 25, "half", string$(pitch_ceiling)
    midP = (pitch_floor + pitch_ceiling) / 2
    Text: 0.15, "left", midP, "half", string$(round(midP))
    Text: 0.15, "left", pitch_floor + 20, "half", string$(pitch_floor)
    
    currentY = layerBottom
endif

# ============================================================
# LAYER: SPECTRAL CENTROID
# ============================================================

if draw_spectral_centroid
    layerNum += 1
    layerTop = currentY
    layerBottom = currentY + layerHeight
    
    appendInfoLine: "  [", layerNum, "] Spectral Centroid"
    
    # --- Data pane ---
    Select outer viewport: dataLeft, dataRight, layerTop, layerBottom
    Select inner viewport: dataLeft + 0.05, dataRight - 0.05, layerTop + 0.03, layerBottom - 0.03
    
    centroidMin = 500
    centroidMax = 4000
    
    Axes: startTime, endTime, centroidMin, centroidMax
    
    # Background
    Colour: "{0.99, 0.96, 0.92}"
    Paint rectangle: "{0.99, 0.96, 0.92}", startTime, endTime, centroidMin, centroidMax
    
    # Grid lines
    Colour: "{0.94, 0.91, 0.87}"
    Line width: 0.5
    gridHz = 1000
    while gridHz <= 3500
        Draw line: startTime, gridHz, endTime, gridHz
        gridHz = gridHz + 1000
    endwhile
    
    # Centroid curve
    selectObject: spectrogramID
    Colour: "{0.85, 0.45, 0.1}"
    Line width: 2.5
    
    prevCentroid = undefined
    prevT = undefined
    numFrames = floor(duration / time_step)
    
    for i from 1 to numFrames
        t = startTime + (i - 1) * time_step
        if t <= endTime
            selectObject: spectrogramID
            totalPower = 0
            weightedSum = 0
            freq = 100
            while freq <= spectrogram_max_freq
                power = Get power at: t, freq
                if power <> undefined and power > 0
                    totalPower = totalPower + power
                    weightedSum = weightedSum + freq * power
                endif
                freq = freq + 100
            endwhile
            
            if totalPower > 0
                centroid = weightedSum / totalPower
                if centroid < centroidMin
                    centroid = centroidMin
                endif
                if centroid > centroidMax
                    centroid = centroidMax
                endif
                
                if prevCentroid <> undefined
                    Draw line: prevT, prevCentroid, t, centroid
                endif
                prevCentroid = centroid
                prevT = t
            else
                prevCentroid = undefined
            endif
        endif
    endfor
    
    Colour: "{0.3, 0.3, 0.3}"
    Line width: 0.5
    Draw inner box
    
    # --- Label pane (no background) ---
    Select outer viewport: 0, labelWidth, layerTop, layerBottom
    Axes: 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.85, 0.45, 0.1}"
    Text: 0.95, "right", 0.6, "half", "Centroid"
    Font size: 7
    Colour: "{0.5, 0.5, 0.55}"
    Text: 1.95, "right", 0.25, "half", "Hz"
    
    # --- Scale pane ---
    Select outer viewport: dataRight, totalWidth, layerTop, layerBottom
    Axes: 0, 1, centroidMin, centroidMax
    
    Font size: 6
    Colour: "{0.4, 0.4, 0.45}"
    Text: 0.15, "left", 3800, "half", "4k"
    Text: 0.15, "left", 2250, "half", "2k"
    Text: 0.15, "left", 700, "half", "500"
    
    currentY = layerBottom
endif

# ============================================================
# LAYER: FORMANTS (F1, F2, F3)
# ============================================================

if draw_formants
    layerNum += 1
    layerTop = currentY
    layerBottom = currentY + layerHeight
    
    appendInfoLine: "  [", layerNum, "] Formants"
    
    # --- Data pane ---
    Select outer viewport: dataLeft, dataRight, layerTop, layerBottom
    Select inner viewport: dataLeft + 0.05, dataRight - 0.05, layerTop + 0.03, layerBottom - 0.03
    
    formantMin = 0
    formantMax = 4000
    
    Axes: startTime, endTime, formantMin, formantMax
    
    # Background
    Colour: "{0.94, 0.98, 0.94}"
    Paint rectangle: "{0.94, 0.98, 0.94}", startTime, endTime, formantMin, formantMax
    
    # Grid lines
    Colour: "{0.88, 0.92, 0.88}"
    Line width: 0.5
    gridHz = 1000
    while gridHz <= 3500
        Draw line: startTime, gridHz, endTime, gridHz
        gridHz = gridHz + 1000
    endwhile
    
    selectObject: formantID
    numFrames = floor(duration / time_step)
    
    # F3 (draw first - back layer)
    if draw_F3
        Colour: "{0.35, 0.55, 0.8}"
        Line width: 1.8
        prevVoiced = 0
        prevT = 0
        prevF = 0
        for i from 1 to numFrames
            t = startTime + (i - 1) * time_step
            if t <= endTime
                selectObject: formantID
                f = Get value at time: 3, t, "hertz", "Linear"
                if f <> undefined and f >= formantMin and f <= formantMax
                    if prevVoiced = 1
                        Draw line: prevT, prevF, t, f
                    endif
                    prevVoiced = 1
                    prevT = t
                    prevF = f
                else
                    prevVoiced = 0
                endif
            endif
        endfor
    endif
    
    # F2 (middle layer)
    if draw_F2
        Colour: "{0.2, 0.65, 0.35}"
        Line width: 2.2
        prevVoiced = 0
        prevT = 0
        prevF = 0
        for i from 1 to numFrames
            t = startTime + (i - 1) * time_step
            if t <= endTime
                selectObject: formantID
                f = Get value at time: 2, t, "hertz", "Linear"
                if f <> undefined and f >= formantMin and f <= formantMax
                    if prevVoiced = 1
                        Draw line: prevT, prevF, t, f
                    endif
                    prevVoiced = 1
                    prevT = t
                    prevF = f
                else
                    prevVoiced = 0
                endif
            endif
        endfor
    endif
    
    # F1 (front layer - thickest)
    if draw_F1
        Colour: "{0.85, 0.25, 0.25}"
        Line width: 2.8
        prevVoiced = 0
        prevT = 0
        prevF = 0
        for i from 1 to numFrames
            t = startTime + (i - 1) * time_step
            if t <= endTime
                selectObject: formantID
                f = Get value at time: 1, t, "hertz", "Linear"
                if f <> undefined and f >= formantMin and f <= formantMax
                    if prevVoiced = 1
                        Draw line: prevT, prevF, t, f
                    endif
                    prevVoiced = 1
                    prevT = t
                    prevF = f
                else
                    prevVoiced = 0
                endif
            endif
        endfor
    endif
    
    Colour: "{0.3, 0.3, 0.3}"
    Line width: 0.5
    Draw inner box
    
    # --- Label pane (no background) ---
    Select outer viewport: 0, labelWidth, layerTop, layerBottom
    Axes: 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.3, 0.3, 0.35}"
    Text: 0.95, "right", 0.82, "half", "Formants"
    
    Font size: 7
    if draw_F1
        Colour: "{0.85, 0.25, 0.25}"
        Text: 1.95, "right", 0.58, "half", "F%%1%"
    endif
    if draw_F2
        Colour: "{0.2, 0.65, 0.35}"
        Text: 1.95, "right", 0.38, "half", "F%%2%"
    endif
    if draw_F3
        Colour: "{0.35, 0.55, 0.8}"
        Text: 1.95, "right", 0.18, "half", "F%%3%"
    endif
    
    # --- Scale pane ---
    Select outer viewport: dataRight, totalWidth, layerTop, layerBottom
    Axes: 0, 1, formantMin, formantMax
    
    Font size: 6
    Colour: "{0.4, 0.4, 0.45}"
    Text: 0.15, "left", 3800, "half", "4k"
    Text: 0.15, "left", 2000, "half", "2k"
    Text: 0.15, "left", 200, "half", "0"
    
    currentY = layerBottom
endif

# ============================================================
# LAYER: PULSES
# ============================================================

if draw_pulses
    layerNum += 1
    layerTop = currentY
    layerBottom = currentY + layerHeight
    
    appendInfoLine: "  [", layerNum, "] Glottal Pulses"
    
    # --- Data pane ---
    Select outer viewport: dataLeft, dataRight, layerTop, layerBottom
    Select inner viewport: dataLeft + 0.05, dataRight - 0.05, layerTop + 0.03, layerBottom - 0.03
    
    Axes: startTime, endTime, 0, 1
    
    # Background
    Colour: "{0.98, 0.96, 0.96}"
    Paint rectangle: "{0.98, 0.96, 0.96}", startTime, endTime, 0, 1
    
    # Pulses
    selectObject: pulsesID
    numPulses = Get number of points
    Colour: "{0.75, 0.2, 0.2}"
    Line width: 1
    
    for p from 1 to numPulses
        selectObject: pulsesID
        t = Get time from index: p
        if t >= startTime and t <= endTime
            Draw line: t, 0.1, t, 0.9
        endif
    endfor
    
    Colour: "{0.3, 0.3, 0.3}"
    Line width: 0.5
    Draw inner box
    
    # --- Label pane (no background) ---
    Select outer viewport: 0, labelWidth, layerTop, layerBottom
    Axes: 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.75, 0.2, 0.2}"
    Text: 0.95, "right", 0.6, "half", "Pulses"
    Font size: 7
    Colour: "{0.5, 0.5, 0.55}"
    Text: 1.95, "right", 0.25, "half", "Glottal"
    
    currentY = layerBottom
endif

# ============================================================
# TIME AXIS
# ============================================================

timeAxisTop = totalHeight - timeAxisHeight
timeAxisBottom = totalHeight

# Time axis
Select outer viewport: dataLeft, dataRight, timeAxisTop, timeAxisBottom
Select inner viewport: dataLeft + 0.05, dataRight - 0.05, timeAxisTop, timeAxisBottom - 0.15

Axes: startTime, endTime, 0, 1

# Axis line
Colour: "{0.3, 0.3, 0.35}"
Line width: 1
Draw line: startTime, 1, endTime, 1

# Calculate nice tick interval
if duration <= 1
    tickInterval = 0.1
elsif duration <= 5
    tickInterval = 0.5
elsif duration <= 10
    tickInterval = 1
elsif duration <= 30
    tickInterval = 2
else
    tickInterval = 5
endif

# Draw ticks and labels
Font size: 8
Colour: "{0.3, 0.3, 0.35}"

t = 0
while t <= endTime
    if t >= startTime
        # Major tick
        Draw line: t, 1, t, 0.65
        # Label
        Text: t, "centre", 0.25, "half", fixed$(t, 1)
    endif
    t = t + tickInterval
endwhile

# Axis title
Font size: 10
Colour: "{0.2, 0.2, 0.25}"
Text: (startTime + endTime) / 2, "centre", -0.4, "half", "##Time (s)##"

# ============================================================
# CLEANUP
# ============================================================

Colour: "Black"
Line width: 1
Font size: 10

if draw_spectrogram or draw_spectral_centroid
    removeObject: spectrogramID
endif
if draw_intensity
    removeObject: intensityID
endif
if draw_pitch or draw_pulses
    removeObject: pitchID
endif
if draw_formants
    removeObject: formantID
endif
if draw_pulses
    removeObject: pulsesID
endif

selectObject: soundID

appendInfoLine: ""
appendInfoLine: "=== Complete ==="
appendInfoLine: "Layers drawn: ", numLayers