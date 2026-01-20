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
# ============================================================

form Stereo Swirl Vibrato v3.1
    comment Requires a Sound object (Mono inputs will be converted)
    
    comment === PRESET ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Gentle Stereo Chorus (90 deg subtle)
        option Wide Stereo Swirl (180 deg dramatic)
        option Rotating Leslie (90 deg slow)
        option Psychedelic Spiral (270 deg intense)
        option Subtle Width (45 deg gentle)
        option Extreme Dizzy (180 deg fast)
    
    comment === PARAMETERS ===
    positive Base_delay_ms 6.0
    positive Modulation_depth 0.12
    positive Modulation_rate_Hz 4.5
    
    comment === STEREO FIELD ===
    real Phase_offset_degrees 90
    comment (0=Mono, 90=Circular, 180=Ping-Pong, 270=Reverse)
    
    comment === OUTPUT SAFETY ===
    positive Target_Peak_Level 0.90
    comment (0.90 prevents distortion/clipping)
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# 1. INPUT CHECK & AUTO-CONVERT
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sourceObject = selected("Sound")
selectObject: sourceObject
numberOfChannels = Get number of channels
wasMono = 0
tempStereo = 0

# === AUTO-STEREO CONVERSION ===
if numberOfChannels = 1
    # Convert Mono to Stereo
    Convert to stereo
    # We track this temp object to delete it later
    tempStereo = selected("Sound")
    original = tempStereo
    originalName$ = selected$("Sound")
    wasMono = 1
    appendInfoLine: "Note: Input was Mono. Converted to Stereo temporarily."
elsif numberOfChannels = 2
    original = sourceObject
    originalName$ = selected$("Sound")
else
    exitScript: "This script supports Mono (1) or Stereo (2) only."
endif

# Get attributes
selectObject: original
duration = Get total duration
sr = Get sampling frequency

# === SAFETY PRE-SCALE ===
# Ensure input isn't already clipping before we do math on it
Scale peak: 0.90

# ============================================================
# 2. PRESET MAPPING
# ============================================================

if preset > 1
    if preset = 2
        # Gentle Chorus
        base_delay_ms = 5.0
        modulation_depth = 0.10
        modulation_rate_Hz = 5.0
        phase_offset_degrees = 90
        presetName$ = "GentleChorus"
    elsif preset = 3
        # Wide Swirl
        base_delay_ms = 6.0
        modulation_depth = 0.15
        modulation_rate_Hz = 4.5
        phase_offset_degrees = 180
        presetName$ = "WideSwirl"
    elsif preset = 4
        # Leslie
        base_delay_ms = 8.0
        modulation_depth = 0.18
        modulation_rate_Hz = 1.5
        phase_offset_degrees = 90
        presetName$ = "Leslie"
    elsif preset = 5
        # Spiral
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
        # Extreme
        base_delay_ms = 10.0
        modulation_depth = 0.25
        modulation_rate_Hz = 8.0
        phase_offset_degrees = 180
        presetName$ = "ExtremeDizzy"
    endif
else
    presetName$ = "Custom"
endif

phase_offset_rad = phase_offset_degrees * pi / 180
base = round(base_delay_ms * sr / 1000)

writeInfoLine: "=== Stereo Swirl Vibrato v3.1 ==="
appendInfoLine: "Source: ", originalName$, " | Preset: ", presetName$

# ============================================================
# 3. SIGNAL PROCESSING
# ============================================================

selectObject: original
Copy: originalName$ + "_swirl_" + presetName$
result = selected("Sound")

# Convert vars to strings for the formula
base_str$ = string$(base)
depth_str$ = string$(modulation_depth)
rate_str$ = string$(modulation_rate_Hz)
phase_str$ = string$(phase_offset_rad)

# FORMULA:
# We shift the read pointer (x) by a modulated delay.
# Row 1 (Left) gets 0 offset. Row 2 (Right) gets phase_offset.
Formula: "self[row, max(1, min(ncol, col + round(" + base_str$ + " + " + base_str$ + " * " + depth_str$ + " * sin(2 * pi * " + rate_str$ + " * x + (row - 1) * " + phase_str$ + "))))]"

# === SAFETY POST-SCALE ===
# Normalize the result to the target peak (e.g., 0.90) to prevent clipping
selectObject: result
Scale peak: target_Peak_Level

# ============================================================
# 4. VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # --- Title ---
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Stereo Swirl: " + originalName$ + " (" + presetName$ + ")"
    
    # --- Layout Setup ---
    # We will draw Waveforms, LFOs, and Stereo Field
    
    # 1. Left Channel
    Select outer viewport: 0, 4, 0.6, 1.5
    Select inner viewport: 0.5, 3.8, 0.7, 1.4
    selectObject: result
    Extract one channel: 1
    tempL = selected("Sound")
    Colour: "{0.5, 0.6, 0.8}"
    Draw: 0, 0, -1, 1, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Left"
    
    # 2. Right Channel
    Select outer viewport: 4, 8, 0.6, 1.5
    Select inner viewport: 4.4, 7.6, 0.7, 1.4
    selectObject: result
    Extract one channel: 2
    tempR = selected("Sound")
    Colour: "{0.8, 0.5, 0.5}"
    Draw: 0, 0, -1, 1, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Right"
    
    removeObject: tempL, tempR
    
    # 3. LFO Visualization
    Select outer viewport: 0, 8, 1.7, 2.8
    Select inner viewport: 0.6, 7.6, 1.8, 2.7
    
    vizDur = min(2, duration)
    nPoints = 400
    
    Axes: 0, vizDur, -1.2, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, vizDur, -1.2, 1.2
    Colour: "{0.8, 0.8, 0.8}"
    Draw line: 0, 0, vizDur, 0
    
    # Draw LFO Lines
    # Left (Blue)
    Colour: "{0.5, 0.6, 0.8}" 
    Line width: 2
    for p from 2 to nPoints
        t1 = (p - 2) / nPoints * vizDur
        t2 = (p - 1) / nPoints * vizDur
        v1 = modulation_depth * sin(2 * pi * modulation_rate_Hz * t1)
        v2 = modulation_depth * sin(2 * pi * modulation_rate_Hz * t2)
        Draw line: t1, v1 * 4, t2, v2 * 4
    endfor
    
    # Right (Red)
    Colour: "{0.8, 0.5, 0.5}" 
    for p from 2 to nPoints
        t1 = (p - 2) / nPoints * vizDur
        t2 = (p - 1) / nPoints * vizDur
        v1 = modulation_depth * sin(2 * pi * modulation_rate_Hz * t1 + phase_offset_rad)
        v2 = modulation_depth * sin(2 * pi * modulation_rate_Hz * t2 + phase_offset_rad)
        Draw line: t1, v1 * 4, t2, v2 * 4
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Modulation"
    
    # 4. Stereo Pattern (Lissajous)
    Select outer viewport: 0, 4, 3.0, 5.0
    Select inner viewport: 1.0, 3.0, 3.1, 4.9
    
    Axes: -1.2, 1.2, -1.2, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", -1.2, 1.2, -1.2, 1.2
    Colour: "{0.8, 0.8, 0.8}"
    Draw line: -1.2, 0, 1.2, 0
    Draw line: 0, -1.2, 0, 1.2
    
    Colour: "{0.5, 0.4, 0.6}"
    Line width: 2
    nLiss = 100
    for p from 2 to nLiss
        t1 = (p - 2) / nLiss * (1/modulation_rate_Hz)
        t2 = (p - 1) / nLiss * (1/modulation_rate_Hz)
        x1 = sin(2 * pi * modulation_rate_Hz * t1)
        y1 = sin(2 * pi * modulation_rate_Hz * t1 + phase_offset_rad)
        x2 = sin(2 * pi * modulation_rate_Hz * t2)
        y2 = sin(2 * pi * modulation_rate_Hz * t2 + phase_offset_rad)
        Draw line: x1, y1, x2, y2
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Text bottom: "yes", "Stereo Spread Pattern"
    
    # 5. Info Box
    Select outer viewport: 4, 8, 3.0, 5.0
    Select inner viewport: 4.2, 7.8, 3.1, 4.9
    Axes: 0, 1, 0, 1
    
    Font size: 10
    Text: 0, "left", 0.8, "half", "Settings Used:"
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0, "left", 0.6, "half", "Rate: " + fixed$(modulation_rate_Hz, 1) + " Hz"
    Text: 0, "left", 0.45, "half", "Depth: " + fixed$(modulation_depth, 2)
    Text: 0, "left", 0.3, "half", "Delay: " + fixed$(base_delay_ms, 1) + " ms"
    Text: 0, "left", 0.15, "half", "Phase: " + fixed$(phase_offset_degrees, 0) + " degrees"
    
endif

# === CLEANUP & FINISH ===
selectObject: result
if play_result
    Play
endif

# Cleanup the temporary stereo file if we created one
if wasMono
    selectObject: tempStereo
    Remove
endif

selectObject: result