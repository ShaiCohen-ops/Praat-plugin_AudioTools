# ============================================================
# Praat AudioTools - Spectral_Freeze_Glitch.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral Freeze & Glitch - creates stutter, freeze, and
#   glitch effects by looping small segments at random positions.
#   Adds sinusoidal artifacts for digital corruption aesthetic.
#   Creates CD-skip, buffer glitch, and broken playback effects.
#
# Changelog v0.2:
#   - Modern syntax
#   - Fixed Formula interpolation
#   - Added visualization
#   - Store freeze positions for display
# ============================================================

form Spectral Freeze and Glitch
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Default (balanced)
        option Short Bursts
        option Long Freeze
        option Artifact Storm
        option Custom
    
    comment === Freeze Parameters ===
    natural Freeze_points 12
    positive Freeze_duration_divisor 25
    positive Freeze_length_min_factor 0.5
    positive Freeze_length_max_factor 1.5
    positive Freeze_repeat_divisor 3
    
    comment === Artifacts ===
    positive Artifact_amplitude 0.1
    
    comment === Output ===
    positive Scale_peak 0.91
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 1
    # Default (balanced)
    freeze_points = 12
    freeze_duration_divisor = 25
    freeze_length_min_factor = 0.5
    freeze_length_max_factor = 1.5
    freeze_repeat_divisor = 3
    artifact_amplitude = 0.1
elsif preset = 2
    # Short Bursts
    freeze_points = 8
    freeze_duration_divisor = 15
    freeze_length_min_factor = 0.3
    freeze_length_max_factor = 1.0
    freeze_repeat_divisor = 2
    artifact_amplitude = 0.05
elsif preset = 3
    # Long Freeze
    freeze_points = 16
    freeze_duration_divisor = 40
    freeze_length_min_factor = 0.8
    freeze_length_max_factor = 2.0
    freeze_repeat_divisor = 4
    artifact_amplitude = 0.12
elsif preset = 4
    # Artifact Storm
    freeze_points = 20
    freeze_duration_divisor = 20
    freeze_length_min_factor = 0.4
    freeze_length_max_factor = 1.6
    freeze_repeat_divisor = 2
    artifact_amplitude = 0.25
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
sampleRate = Get sampling frequency
duration = Get total duration
totalSamples = Get number of samples

# === Get Preset Name ===
if preset = 1
    presetName$ = "Default"
elsif preset = 2
    presetName$ = "Short Bursts"
elsif preset = 3
    presetName$ = "Long Freeze"
elsif preset = 4
    presetName$ = "Artifact Storm"
else
    presetName$ = "Custom"
endif

# === Info ===
writeInfoLine: "=== Spectral Freeze & Glitch ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Freeze points: ", freeze_points
appendInfoLine: "Artifact amplitude: ", artifact_amplitude
appendInfoLine: ""

# === Copy for Processing ===
selectObject: original
Copy: original_name$ + "_glitch"
result = selected("Sound")

# === Calculate Base Freeze Duration ===
freezeDuration = floor(totalSamples / freeze_duration_divisor)

# === Store Freeze Positions for Visualization ===
freezePositions# = zero#(freeze_points)
freezeLengths# = zero#(freeze_points)

# === Main Freeze Processing Loop ===
appendInfoLine: "Processing freeze points..."

for point from 1 to freeze_points
    selectObject: result
    
    # Random freeze position
    minPos = floor(freezeDuration)
    maxPos = totalSamples - floor(freezeDuration)
    if maxPos <= minPos
        maxPos = minPos + 1
    endif
    freezePos = randomInteger(minPos, maxPos)
    
    # Random freeze length
    minLen = floor(freezeDuration * freeze_length_min_factor)
    maxLen = floor(freezeDuration * freeze_length_max_factor)
    if minLen < 1
        minLen = 1
    endif
    if maxLen <= minLen
        maxLen = minLen + 1
    endif
    freezeLength = randomInteger(minLen, maxLen)
    
    # Store for visualization
    freezePositions#[point] = freezePos / sampleRate
    freezeLengths#[point] = freezeLength / sampleRate
    
    # Calculate repeat segment length
    repeatSegment = floor(freezeLength / freeze_repeat_divisor)
    if repeatSegment < 1
        repeatSegment = 1
    endif
    
    appendInfoLine: "  Point ", point, ": pos=", fixed$(freezePositions#[point], 3), "s len=", fixed$(freezeLengths#[point] * 1000, 1), "ms"
    
    # Freeze and repeat segment (stutter effect)
    Formula: ~ if col >= freezePos and col < freezePos + freezeLength 
        ... then self[freezePos + ((col - freezePos) mod repeatSegment)] 
        ... else self fi
    
    # Add spectral artifacts
    Formula: ~ self * (1 + artifact_amplitude * sin(2 * pi * point * col / totalSamples))
endfor

# === Scale Peak ===
selectObject: result
Scale peak: scale_peak

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 1, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Spectral Freeze & Glitch: " + original_name$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 2.0
    Select inner viewport: 0.6, 7.6, 0.7, 1.9
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform with freeze markers
    Select outer viewport: 0, 8, 2.1, 3.5
    Select inner viewport: 0.6, 7.6, 2.2, 3.4
    selectObject: result
    Colour: "{0.6, 0.4, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    # Mark freeze positions
    Axes: 0, duration, -1, 1
    for p to freeze_points
        pos = freezePositions#[p]
        len = freezeLengths#[p]
        
        Colour: "{0.9, 0.3, 0.3}"
        Draw line: pos, -0.9, pos, 0.9
        Colour: "{0.9, 0.6, 0.6}"
        Paint rectangle: "{0.9, 0.8, 0.8}", pos, pos + len, -0.8, 0.8
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Glitched"
    Text bottom: "yes", "Time (s)"
    
    # Legend
    Font size: 6
    Colour: "{0.9, 0.3, 0.3}"
    Text: 0.02, "left", 1.05, "half", "Freeze zones"
    
    # Freeze position scatter plot
    Select outer viewport: 0, 8, 3.7, 5.1
    Select inner viewport: 0.6, 7.6, 3.9, 5.0
    
    Axes: 0, duration, 0, freeze_points + 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, 0, freeze_points + 1
    
    # Draw freeze zones as horizontal bars
    for p to freeze_points
        pos = freezePositions#[p]
        len = freezeLengths#[p]
        
        # Color intensity by length
        avgLen = (freeze_length_min_factor + freeze_length_max_factor) / 2
        lenNorm = (freezeLengths#[p] * sampleRate / freezeDuration) / avgLen
        r = 0.5 + 0.3 * lenNorm
        g = 0.3
        b = 0.5
        barColor$ = "{" + fixed$(r, 2) + ", " + fixed$(g, 2) + ", " + fixed$(b, 2) + "}"
        
        Paint rectangle: barColor$, pos, pos + len, p - 0.4, p + 0.4
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freeze #"
    Text bottom: "yes", "Position in source (s)"
    
    # Stats
    Select outer viewport: 0, 8, 5.3, 5.6
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Freeze points: " + string$(freeze_points) + " | Artifact: " + fixed$(artifact_amplitude, 2) + " | Repeat divisor: " + string$(freeze_repeat_divisor)
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result
finalDuration = Get total duration

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDuration, 2), " s"

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result