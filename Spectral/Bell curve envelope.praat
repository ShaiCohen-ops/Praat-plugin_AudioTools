# ============================================================
# Praat AudioTools - Bell_curve_envelope.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Added visualization & presets
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Applies spectral effect via sample-offset mixing, then
#   shapes result with Gaussian bell curve envelope.
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

form Bell Curve Envelope v0.2
    optionmenu Preset: 1
        option Custom
        option Narrow Bell
        option Wide Bell
        option Low Freq Emphasis
        option High Freq Emphasis
        option Bright Grain
        option Dark Grain
        option Metallic Bell
        option Soft Resonance
    comment === Spectral Effect ===
    positive Low_freq_factor 1.1
    positive High_freq_factor 1.1
    comment (Sample offset mixing creates spectral color)
    comment === Bell Envelope ===
    positive Bell_width 4
    comment (higher=narrower, lower=wider)
    real Bell_center 0.5
    comment (0=start, 0.5=middle, 1=end)
    comment === Output ===
    positive Scale_peak 0.99
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================

if preset = 2
    # Narrow Bell
    bell_width = 6
    bell_center = 0.5
    low_freq_factor = 1.1
    high_freq_factor = 1.1
    presetName$ = "NarrowBell"
elsif preset = 3
    # Wide Bell
    bell_width = 2
    bell_center = 0.5
    low_freq_factor = 1.1
    high_freq_factor = 1.1
    presetName$ = "WideBell"
elsif preset = 4
    # Low Freq Emphasis
    bell_width = 4
    bell_center = 0.5
    low_freq_factor = 1.5
    high_freq_factor = 1.0
    presetName$ = "LowEmphasis"
elsif preset = 5
    # High Freq Emphasis
    bell_width = 4
    bell_center = 0.5
    low_freq_factor = 1.0
    high_freq_factor = 1.5
    presetName$ = "HighEmphasis"
elsif preset = 6
    # Bright Grain
    bell_width = 8
    bell_center = 0.5
    low_freq_factor = 1.0
    high_freq_factor = 1.3
    presetName$ = "BrightGrain"
elsif preset = 7
    # Dark Grain
    bell_width = 8
    bell_center = 0.5
    low_freq_factor = 1.3
    high_freq_factor = 1.0
    presetName$ = "DarkGrain"
elsif preset = 8
    # Metallic Bell
    bell_width = 5
    bell_center = 0.5
    low_freq_factor = 1.2
    high_freq_factor = 1.2
    presetName$ = "MetallicBell"
elsif preset = 9
    # Soft Resonance
    bell_width = 2.5
    bell_center = 0.5
    low_freq_factor = 1.05
    high_freq_factor = 1.05
    presetName$ = "SoftResonance"
else
    presetName$ = "Custom"
endif

# ============================================================
# SETUP
# ============================================================

selectObject: originalID
duration = Get total duration
sampleRate = Get sampling frequency

# Calculate envelope parameters
centerTime = duration * bell_center
sigma = duration / bell_width

clearinfo
writeInfoLine: "=== Bell Curve Envelope v0.2 ==="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Duration: ", fixed$(duration, 3), " s"
appendInfoLine: ""
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Low freq factor: ", low_freq_factor
appendInfoLine: "High freq factor: ", high_freq_factor
appendInfoLine: "Bell center: ", fixed$(bell_center * 100, 0), "%"
appendInfoLine: "Bell width: ", bell_width
appendInfoLine: ""

# ============================================================
# PROCESS
# ============================================================

appendInfo: "Processing..."

selectObject: originalID
workingID = Copy: originalName$ + "_bell_" + presetName$

# Build formula strings
lowStr$ = fixed$(low_freq_factor, 6)
highStr$ = fixed$(high_freq_factor, 6)
centerStr$ = fixed$(bell_center, 6)
widthStr$ = fixed$(bell_width, 6)

# Apply spectral effect via sample-offset mixing
# self[col/low] reads earlier samples (lower pitch)
# self[col*high] reads later samples (higher pitch)
# Difference creates unique spectral coloration
selectObject: workingID
Formula: "self[col / " + lowStr$ + "] - self[col * " + highStr$ + "]"

# Apply Gaussian bell envelope
selectObject: workingID
Formula: "self * exp(-((x - (xmin + (xmax - xmin) * " + centerStr$ + ")) / ((xmax - xmin) / " + widthStr$ + "))^2)"

# Scale to peak
selectObject: workingID
Scale peak: scale_peak

appendInfoLine: " done"

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
    Text: 0.5, "centre", 0.5, "half", "Bell Curve Envelope: " + originalName$ + " [" + presetName$ + "]"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 2.2
    Select inner viewport: 0.6, 7.6, 0.75, 2.05
    
    selectObject: originalID
    Colour: "{0.7, 0.7, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 9
    Text top: "no", "Original"
    Text left: "yes", "Amp"
    
    # Processed waveform
    Select outer viewport: 0, 8, 2.3, 3.9
    Select inner viewport: 0.6, 7.6, 2.45, 3.75
    
    selectObject: workingID
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text top: "no", "Spectral Effect + Bell Envelope"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # Bell curve envelope shape
    Select outer viewport: 0, 5, 4.1, 5.8
    Select inner viewport: 0.6, 4.6, 4.3, 5.6
    
    Axes: 0, duration, 0, 1.1
    
    # Draw the Gaussian envelope
    Colour: "{0.9, 0.4, 0.2}"
    Line width: 3
    
    numPoints = 200
    for i from 0 to numPoints - 1
        t1 = duration * i / numPoints
        t2 = duration * (i + 1) / numPoints
        
        env1 = exp(-((t1 - centerTime) / sigma)^2)
        env2 = exp(-((t2 - centerTime) / sigma)^2)
        
        Draw line: t1, env1, t2, env2
    endfor
    
    # Mark center
    Colour: "{0.9, 0.3, 0.3}"
    Line width: 1
    Dotted line
    Draw line: centerTime, 0, centerTime, 1.1
    Solid line
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Bell Envelope"
    Text left: "yes", "Gain"
    Text bottom: "yes", "Time (s)"
    
    # Info panel
    Select outer viewport: 5, 8, 4.1, 5.8
    Select inner viewport: 5.2, 7.8, 4.3, 5.6
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.05, "left", 0.85, "half", "Low factor: " + fixed$(low_freq_factor, 2)
    Text: 0.05, "left", 0.65, "half", "High factor: " + fixed$(high_freq_factor, 2)
    Text: 0.05, "left", 0.45, "half", "Bell center: " + fixed$(bell_center * 100, 0) + "%"
    Text: 0.05, "left", 0.25, "half", "Bell width: " + fixed$(bell_width, 1)
    
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
appendInfoLine: "Created: ", originalName$, "_bell_", presetName$

if play_result
    selectObject: workingID
    Play
endif
