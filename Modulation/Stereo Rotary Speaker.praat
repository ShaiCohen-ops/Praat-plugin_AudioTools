# ============================================================
# Praat AudioTools - Stereo_Rotary_Speaker.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Stereo Rotary Speaker (Leslie Model) - simulates a rotating
#   speaker cabinet with Doppler pitch shift and amplitude tremolo.
#   Stereo image is created by virtual microphone placement angle.
#   Classic organ sound from Hammond B3 + Leslie combos.
#
# Changelog v0.2:
#   - Fixed input check
#   - Fixed formula syntax (use object IDs)
#   - Added bounds checking
#   - Removed rename hack
#   - Added visualization
# ============================================================

form Stereo Rotary Speaker
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Chorale (Slow / Hymn)
        option Tremolo (Fast / Rock)
        option Transition (Ramping Up)
        option Wide Stereo Spin
        option Broken Cabinet (Wobbly)
    
    comment === Rotation ===
    positive Rotation_Speed_Hz 6.8
    comment (Chorale ~0.8 Hz, Tremolo ~7 Hz)
    
    comment === Horn Physics ===
    positive Doppler_Depth 0.12
    comment (Pitch wobble: 0.05=subtle, 0.2=strong)
    positive Tremolo_Depth 0.5
    comment (Volume wobble: 0.3=subtle, 0.7=strong)
    
    comment === Microphone Placement ===
    positive Stereo_Width_Deg 140
    comment (Angle between L/R mics: 90=narrow, 180=wide)
    
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
original_name$ = selected$("Sound")

selectObject: original
duration = Get total duration
sr = Get sampling frequency

# === Apply Presets ===
if preset = 2
    # Chorale (Slow)
    rotation_Speed_Hz = 0.8
    doppler_Depth = 0.08
    tremolo_Depth = 0.3
    stereo_Width_Deg = 120
    presetName$ = "Chorale"
elsif preset = 3
    # Tremolo (Fast)
    rotation_Speed_Hz = 6.8
    doppler_Depth = 0.12
    tremolo_Depth = 0.5
    stereo_Width_Deg = 160
    presetName$ = "Tremolo"
elsif preset = 4
    # Transition
    rotation_Speed_Hz = 4.0
    doppler_Depth = 0.15
    tremolo_Depth = 0.4
    stereo_Width_Deg = 180
    presetName$ = "Transition"
elsif preset = 5
    # Wide Stereo Spin
    rotation_Speed_Hz = 2.5
    doppler_Depth = 0.10
    tremolo_Depth = 0.7
    stereo_Width_Deg = 180
    presetName$ = "WideSpin"
elsif preset = 6
    # Broken Cabinet
    rotation_Speed_Hz = 9.0
    doppler_Depth = 0.25
    tremolo_Depth = 0.6
    stereo_Width_Deg = 45
    presetName$ = "Broken"
else
    presetName$ = "Custom"
endif

# Convert stereo width to radians
width_rad = stereo_Width_Deg * pi / 180

# Base delay
base_delay_ms = 5.0
base_samp = round(base_delay_ms * sr / 1000)

# === Info ===
writeInfoLine: "=== Stereo Rotary Speaker (Leslie) ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Rotation: ", rotation_Speed_Hz, " Hz (", fixed$(rotation_Speed_Hz * 60, 0), " RPM)"
appendInfoLine: "Doppler depth: ", doppler_Depth
appendInfoLine: "Tremolo depth: ", tremolo_Depth
appendInfoLine: "Stereo width: ", stereo_Width_Deg, "°"
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Creating stereo field..."

# Force stereo
selectObject: original
Convert to stereo
stereoTemp = selected("Sound")

appendInfoLine: "Applying Leslie model..."

# Create output
selectObject: stereoTemp
Copy: original_name$ + "_leslie_" + presetName$
result = selected("Sound")

# Build formula strings
stereo_str$ = string$(stereoTemp)
base_str$ = string$(base_samp)
dopp_str$ = string$(doppler_Depth)
trem_str$ = string$(tremolo_Depth)
rate_str$ = string$(rotation_Speed_Hz)
width_str$ = string$(width_rad)

# Phase offset for Doppler (90° = π/2 ≈ 1.57)
# This puts the pitch modulation in quadrature with amplitude
doppler_phase_str$ = "1.5708"

# LEFT CHANNEL (row=1): phase = 0
# RIGHT CHANNEL (row=2): phase = width_rad

# Formula combines:
# 1. Amplitude modulation (tremolo): (1 - depth * 0.5 * (1 + sin(ωt + φ)))
# 2. Delay modulation (Doppler): col - round(base * (1 + depth * sin(ωt + φ + π/2)))

left_amp$ = "(1 - " + trem_str$ + " * 0.5 * (1 + sin(2*pi*" + rate_str$ + "*x)))"
left_delay$ = "max(1, min(ncol, col - round(" + base_str$ + " * (1 + " + dopp_str$ + " * sin(2*pi*" + rate_str$ + "*x + " + doppler_phase_str$ + ")))))"

right_amp$ = "(1 - " + trem_str$ + " * 0.5 * (1 + sin(2*pi*" + rate_str$ + "*x + " + width_str$ + ")))"
right_delay$ = "max(1, min(ncol, col - round(" + base_str$ + " * (1 + " + dopp_str$ + " * sin(2*pi*" + rate_str$ + "*x + " + width_str$ + " + " + doppler_phase_str$ + ")))))"

formula$ = "if row = 1 then " + left_amp$ + " * object[" + stereo_str$ + ", 1, " + left_delay$ + "] else " + right_amp$ + " * object[" + stereo_str$ + ", 2, " + right_delay$ + "] fi"

Formula: formula$

# Cleanup temp stereo
removeObject: stereoTemp

# Scale output
selectObject: result
Scale peak: scale_peak

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 1, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Rotary Speaker (Leslie): " + original_name$ + " (" + presetName$ + ")"
    
    # Original waveform (mono display)
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.6, 0.7, 1.3
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result L channel
    Select outer viewport: 0, 4, 1.5, 2.3
    Select inner viewport: 0.5, 3.8, 1.6, 2.2
    selectObject: result
    Extract one channel: 1
    resultL = selected("Sound")
    Colour: "{0.5, 0.6, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Left"
    
    # Result R channel
    Select outer viewport: 4, 8, 1.5, 2.3
    Select inner viewport: 4.4, 7.6, 1.6, 2.2
    selectObject: result
    Extract one channel: 2
    resultR = selected("Sound")
    Colour: "{0.8, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Right"
    Text bottom: "yes", "Time (s)"
    
    removeObject: resultL, resultR
    
    # Modulation curves
    Select outer viewport: 0, 8, 2.5, 3.7
    Select inner viewport: 0.6, 7.6, 2.6, 3.6
    
    vizDur = min(2, duration)
    nPoints = 400
    
    Axes: 0, vizDur, -0.2, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, vizDur, -0.2, 1.2
    
    # Tremolo envelope L (blue)
    Colour: "{0.5, 0.6, 0.8}"
    Line width: 1.5
    for p from 2 to nPoints
        t1 = (p - 2) / nPoints * vizDur
        t2 = (p - 1) / nPoints * vizDur
        amp1 = 1 - tremolo_Depth * 0.5 * (1 + sin(2*pi*rotation_Speed_Hz*t1))
        amp2 = 1 - tremolo_Depth * 0.5 * (1 + sin(2*pi*rotation_Speed_Hz*t2))
        Draw line: t1, amp1, t2, amp2
    endfor
    
    # Tremolo envelope R (red)
    Colour: "{0.8, 0.5, 0.5}"
    for p from 2 to nPoints
        t1 = (p - 2) / nPoints * vizDur
        t2 = (p - 1) / nPoints * vizDur
        amp1 = 1 - tremolo_Depth * 0.5 * (1 + sin(2*pi*rotation_Speed_Hz*t1 + width_rad))
        amp2 = 1 - tremolo_Depth * 0.5 * (1 + sin(2*pi*rotation_Speed_Hz*t2 + width_rad))
        Draw line: t1, amp1, t2, amp2
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Tremolo"
    Text bottom: "yes", "Time (s)"
    
    # Doppler curves
    Select outer viewport: 0, 8, 3.9, 5.1
    Select inner viewport: 0.6, 7.6, 4.0, 5.0
    
    Axes: 0, vizDur, -0.3, 0.3
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, vizDur, -0.3, 0.3
    
    # Zero line
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, vizDur, 0
    
    # Doppler L (blue)
    Colour: "{0.5, 0.6, 0.8}"
    Line width: 1.5
    for p from 2 to nPoints
        t1 = (p - 2) / nPoints * vizDur
        t2 = (p - 1) / nPoints * vizDur
        dopp1 = doppler_Depth * sin(2*pi*rotation_Speed_Hz*t1 + 1.5708)
        dopp2 = doppler_Depth * sin(2*pi*rotation_Speed_Hz*t2 + 1.5708)
        Draw line: t1, dopp1, t2, dopp2
    endfor
    
    # Doppler R (red)
    Colour: "{0.8, 0.5, 0.5}"
    for p from 2 to nPoints
        t1 = (p - 2) / nPoints * vizDur
        t2 = (p - 1) / nPoints * vizDur
        dopp1 = doppler_Depth * sin(2*pi*rotation_Speed_Hz*t1 + width_rad + 1.5708)
        dopp2 = doppler_Depth * sin(2*pi*rotation_Speed_Hz*t2 + width_rad + 1.5708)
        Draw line: t1, dopp1, t2, dopp2
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Doppler"
    Text bottom: "yes", "Time (s)"
    
    # Cabinet diagram
    Select outer viewport: 0, 4, 5.3, 6.3
    Select inner viewport: 0.6, 3.8, 5.4, 6.2
    
    Axes: -1.5, 1.5, -1.5, 1.5
    Paint rectangle: "{0.95, 0.95, 0.95}", -1.5, 1.5, -1.5, 1.5
    
    # Cabinet outline
    Colour: "{0.7, 0.6, 0.5}"
    Paint circle: "{0.85, 0.8, 0.75}", 0, 0, 0.8
    Colour: "{0.6, 0.5, 0.4}"
    Draw circle: 0, 0, 0.8
    
    # Rotating horn
    Colour: "{0.4, 0.4, 0.5}"
    Line width: 3
    Draw arrow: 0, 0, 0.6, 0.4
    Line width: 1
    
    # Microphones
    Colour: "{0.5, 0.6, 0.8}"
    Paint circle: "{0.5, 0.6, 0.8}", -1.1, 0.5, 0.08
    Font size: 5
    Text: -1.1, "centre", 0.7, "half", "L"
    
    Colour: "{0.8, 0.5, 0.5}"
    # Calculate R mic position based on stereo width
    rMicX = -1.1 * cos(width_rad)
    rMicY = 0.5 - 1.1 * sin(width_rad) + 0.5
    Paint circle: "{0.8, 0.5, 0.5}", 1.1, 0.3, 0.08
    Text: 1.1, "centre", 0.5, "half", "R"
    
    Colour: "Black"
    Draw inner box
    Font size: 5
    Text: 0, "centre", -1.3, "half", "Leslie Cabinet"
    
    # Parameters
    Select outer viewport: 4, 8, 5.3, 6.3
    Select inner viewport: 4.4, 7.6, 5.4, 6.2
    
    Axes: 0, 4, 0, 5
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 4, 0, 5
    
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.2, "left", 4.5, "half", "Speed: " + fixed$(rotation_Speed_Hz, 1) + " Hz (" + fixed$(rotation_Speed_Hz * 60, 0) + " RPM)"
    Text: 0.2, "left", 3.7, "half", "Doppler: " + fixed$(doppler_Depth, 2)
    Text: 0.2, "left", 2.9, "half", "Tremolo: " + fixed$(tremolo_Depth, 2)
    Text: 0.2, "left", 2.1, "half", "Stereo: " + fixed$(stereo_Width_Deg, 0) + "°"
    
    # Speed indicator
    if rotation_Speed_Hz < 2
        speedLabel$ = "(Chorale)"
    elsif rotation_Speed_Hz < 5
        speedLabel$ = "(Transition)"
    else
        speedLabel$ = "(Tremolo)"
    endif
    Colour: "{0.5, 0.5, 0.6}"
    Text: 0.2, "left", 1.3, "half", speedLabel$
    
    Colour: "Black"
    Draw inner box
    
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