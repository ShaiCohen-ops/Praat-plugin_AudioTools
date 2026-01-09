# ============================================================
# Praat AudioTools - Stereo_Swirl_Vibrato.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Stereo Swirl Vibrato - delay-line vibrato with phase offset
#   between left and right channels. Creates rotating, swirling
#   spatial effects. 90° gives circular motion, 180° gives
#   ping-pong width. Requires stereo input.
#
# Changelog v0.2:
#   - Fixed input check
#   - Fixed formula syntax
#   - Added visualization
#   - Improved description
# ============================================================

form Stereo Swirl Vibrato
    comment Requires a STEREO (2-channel) sound
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Gentle Stereo Chorus (90° subtle)
        option Wide Stereo Swirl (180° dramatic)
        option Rotating Leslie (90° slow)
        option Psychedelic Spiral (270° intense)
        option Subtle Width (45° gentle)
        option Extreme Dizzy (180° fast)
    
    comment === Delay Parameters ===
    positive Base_delay_ms 6.0
    positive Modulation_depth 0.12
    positive Modulation_rate_Hz 4.5
    
    comment === Stereo Phase Offset ===
    real Phase_offset_degrees 90
    comment (0=mono, 90=circular, 180=ping-pong)
    
    comment === Output ===
    positive Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
numberOfChannels = Get number of channels
if numberOfChannels <> 2
    exitScript: "This script requires a stereo (2-channel) sound. Current: " + string$(numberOfChannels) + " channel(s)."
endif

duration = Get total duration
sr = Get sampling frequency

# === Apply Presets ===
if preset = 2
    # Gentle Stereo Chorus
    base_delay_ms = 5.0
    modulation_depth = 0.10
    modulation_rate_Hz = 5.0
    phase_offset_degrees = 90
    presetName$ = "GentleChorus"
elsif preset = 3
    # Wide Stereo Swirl
    base_delay_ms = 6.0
    modulation_depth = 0.15
    modulation_rate_Hz = 4.5
    phase_offset_degrees = 180
    presetName$ = "WideSwirl"
elsif preset = 4
    # Rotating Leslie
    base_delay_ms = 8.0
    modulation_depth = 0.18
    modulation_rate_Hz = 1.5
    phase_offset_degrees = 90
    presetName$ = "Leslie"
elsif preset = 5
    # Psychedelic Spiral
    base_delay_ms = 7.0
    modulation_depth = 0.20
    modulation_rate_Hz = 6.0
    phase_offset_degrees = 270
    presetName$ = "Spiral"
elsif preset = 6
    # Subtle Width
    base_delay_ms = 4.0
    modulation_depth = 0.08
    modulation_rate_Hz = 4.0
    phase_offset_degrees = 45
    presetName$ = "SubtleWidth"
elsif preset = 7
    # Extreme Dizzy
    base_delay_ms = 10.0
    modulation_depth = 0.25
    modulation_rate_Hz = 8.0
    phase_offset_degrees = 180
    presetName$ = "ExtremeDizzy"
else
    presetName$ = "Custom"
endif

# Convert degrees to radians
phase_offset_rad = phase_offset_degrees * pi / 180

# Calculate base delay in samples
base = round(base_delay_ms * sr / 1000)

# === Info ===
writeInfoLine: "=== Stereo Swirl Vibrato ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(duration, 2), " s, stereo)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Rate: ", modulation_rate_Hz, " Hz"
appendInfoLine: "Depth: ", modulation_depth
appendInfoLine: "Delay: ", base_delay_ms, " ms"
appendInfoLine: "Phase offset: ", phase_offset_degrees, "° (", fixed$(phase_offset_rad, 3), " rad)"
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Applying stereo swirl vibrato..."

selectObject: original
Copy: originalName$ + "_swirl_" + presetName$
result = selected("Sound")

# Build formula strings
base_str$ = string$(base)
depth_str$ = string$(modulation_depth)
rate_str$ = string$(modulation_rate_Hz)
phase_str$ = string$(phase_offset_rad)

# Apply stereo swirl vibrato
# row=1 is Left, row=2 is Right
# Each channel gets phase offset: (row - 1) * phase_step
Formula: "self[row, max(1, min(ncol, col + round(" + base_str$ + " + " + base_str$ + " * " + depth_str$ + " * sin(2 * pi * " + rate_str$ + " * x + (row - 1) * " + phase_str$ + "))))]"

# Scale output
selectObject: result
Scale peak: scale_peak

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Stereo Swirl Vibrato: " + originalName$ + " (" + presetName$ + ")"
    
    # Original L waveform
    Select outer viewport: 0, 4, 0.6, 1.3
    Select inner viewport: 0.5, 3.8, 0.7, 1.2
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Orig L"
    
    # Original R waveform
    Select outer viewport: 4, 8, 0.6, 1.3
    Select inner viewport: 4.4, 7.6, 0.7, 1.2
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Orig R"
    
    # Result L waveform
    Select outer viewport: 0, 4, 1.4, 2.1
    Select inner viewport: 0.5, 3.8, 1.5, 2.0
    selectObject: result
    Extract one channel: 1
    resultL = selected("Sound")
    Colour: "{0.5, 0.6, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Swirl L"
    
    # Result R waveform
    Select outer viewport: 4, 8, 1.4, 2.1
    Select inner viewport: 4.4, 7.6, 1.5, 2.0
    selectObject: result
    Extract one channel: 2
    resultR = selected("Sound")
    Colour: "{0.8, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Swirl R"
    Text bottom: "yes", "Time (s)"
    
    removeObject: resultL, resultR
    
    # LFO curves (L and R)
    Select outer viewport: 0, 8, 2.3, 3.5
    Select inner viewport: 0.6, 7.6, 2.4, 3.4
    
    vizDur = min(2, duration)
    nPoints = 400
    
    Axes: 0, vizDur, -1.2, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, vizDur, -1.2, 1.2
    
    # Zero line
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, vizDur, 0
    
    # Left LFO (blue)
    Colour: "{0.5, 0.6, 0.8}"
    Line width: 1.5
    for p from 2 to nPoints
        t1 = (p - 2) / nPoints * vizDur
        t2 = (p - 1) / nPoints * vizDur
        lfoL1 = modulation_depth * sin(2 * pi * modulation_rate_Hz * t1)
        lfoL2 = modulation_depth * sin(2 * pi * modulation_rate_Hz * t2)
        Draw line: t1, lfoL1 * 4, t2, lfoL2 * 4
    endfor
    
    # Right LFO (red)
    Colour: "{0.8, 0.5, 0.5}"
    for p from 2 to nPoints
        t1 = (p - 2) / nPoints * vizDur
        t2 = (p - 1) / nPoints * vizDur
        lfoR1 = modulation_depth * sin(2 * pi * modulation_rate_Hz * t1 + phase_offset_rad)
        lfoR2 = modulation_depth * sin(2 * pi * modulation_rate_Hz * t2 + phase_offset_rad)
        Draw line: t1, lfoR1 * 4, t2, lfoR2 * 4
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "LFO"
    Text bottom: "yes", "Time (s)"
    
    # Legend
    Font size: 5
    Colour: "{0.5, 0.6, 0.8}"
    Text: vizDur * 0.85, "left", 1.0, "half", "Left"
    Colour: "{0.8, 0.5, 0.5}"
    Text: vizDur * 0.85, "left", 0.7, "half", "Right (+" + fixed$(phase_offset_degrees, 0) + "°)"
    
    # Stereo field visualization (Lissajous-style)
    Select outer viewport: 0, 4, 3.7, 5.2
    Select inner viewport: 0.6, 3.8, 3.8, 5.1
    
    Axes: -1.2, 1.2, -1.2, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", -1.2, 1.2, -1.2, 1.2
    
    # Grid
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: -1.2, 0, 1.2, 0
    Draw line: 0, -1.2, 0, 1.2
    
    # Draw Lissajous pattern (L vs R LFO)
    Colour: "{0.6, 0.5, 0.7}"
    Line width: 1.5
    nLiss = 200
    for p from 2 to nLiss
        t1 = (p - 2) / nLiss * (1 / modulation_rate_Hz)
        t2 = (p - 1) / nLiss * (1 / modulation_rate_Hz)
        lfoL1 = sin(2 * pi * modulation_rate_Hz * t1)
        lfoL2 = sin(2 * pi * modulation_rate_Hz * t2)
        lfoR1 = sin(2 * pi * modulation_rate_Hz * t1 + phase_offset_rad)
        lfoR2 = sin(2 * pi * modulation_rate_Hz * t2 + phase_offset_rad)
        Draw line: lfoL1, lfoR1, lfoL2, lfoR2
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "R"
    Text bottom: "yes", "L"
    Text: 0, "centre", 1.35, "half", "Stereo Pattern"
    
    # Phase offset explanation
    Select outer viewport: 4, 8, 3.7, 5.2
    Select inner viewport: 4.4, 7.6, 3.8, 5.1
    
    Axes: 0, 4, 0, 5
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 4, 0, 5
    
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    
    # Show phase offset options
    Text: 0.2, "left", 4.5, "half", "Phase Offset Effects:"
    Text: 0.2, "left", 3.8, "half", "0° = Mono (no width)"
    Text: 0.2, "left", 3.2, "half", "45° = Subtle stereo"
    Text: 0.2, "left", 2.6, "half", "90° = Circular rotation"
    Text: 0.2, "left", 2.0, "half", "180° = Ping-pong (max width)"
    Text: 0.2, "left", 1.4, "half", "270° = Reverse rotation"
    
    # Highlight current
    Colour: "{0.6, 0.5, 0.7}"
    Text: 0.2, "left", 0.6, "half", "Current: " + fixed$(phase_offset_degrees, 0) + "°"
    
    Colour: "Black"
    Draw inner box
    
    # Parameters
    Select outer viewport: 0, 8, 5.3, 5.7
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Rate: " + fixed$(modulation_rate_Hz, 1) + " Hz | Depth: " + fixed$(modulation_depth, 2) + " | Delay: " + fixed$(base_delay_ms, 1) + " ms | Phase: " + fixed$(phase_offset_degrees, 0) + "°"
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result