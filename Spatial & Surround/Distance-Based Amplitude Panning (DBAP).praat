# ============================================================
# Praat AudioTools - Distance-Based_Amplitude_Panning_(DBAP).praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Static DBAP Panner - Places mono/stereo source at a position
#   and outputs multichannel sound with distance-based gains.
#
# Changelog v0.2:
#   - Fixed: Now takes mono/stereo input, creates multichannel output
#   - Fixed form placement
#   - Added visualization
#   - Added play toggle
#   - Support up to 8 channels
# ============================================================

form DBAP Static Panner
    comment === PRESET ===
    optionmenu Preset: 1
        option: "1. Stereo Center (2ch)"
        option: "2. Stereo Left (2ch)"
        option: "3. Stereo Right (2ch)"
        option: "4. Triangle Center (3ch)"
        option: "5. Triangle Front (3ch)"
        option: "6. Quad Center (4ch)"
        option: "7. Quad Front-Left (4ch)"
        option: "8. Hexagon Center (6ch)"
        option: "9. Surround 5.1 (6ch)"
        option: "10. Octagon Center (8ch)"
        option: "11. Octagon Front (8ch)"
        option: "12. Custom"
    
    comment === DBAP Settings ===
    real Distance_exponent 1.0
    real Minimum_distance 0.01
    boolean Normalize_gains 1
    
    comment === Custom source position (-1 to 1) ===
    real Source_x 0.0
    real Source_y 0.0
    
    comment === Custom speaker count (for preset 12) ===
    natural Number_of_speakers 2
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")
selectObject: sound
numCh = Get number of channels
duration = Get total duration
sr = Get sampling frequency

# === Convert to mono ===
if numCh > 1
    Convert to mono
    monoID = selected("Sound")
else
    Copy: "mono_work"
    monoID = selected("Sound")
endif

# === Apply presets ===
if preset = 1
    # Stereo Center
    numSpk = 2
    source_x = 0.0
    source_y = 0.0
    spkX[1] = -1.0
    spkY[1] = 0.0
    spkX[2] = 1.0
    spkY[2] = 0.0
    presetName$ = "StereoCenter"
elsif preset = 2
    # Stereo Left
    numSpk = 2
    source_x = -0.8
    source_y = 0.0
    spkX[1] = -1.0
    spkY[1] = 0.0
    spkX[2] = 1.0
    spkY[2] = 0.0
    presetName$ = "StereoLeft"
elsif preset = 3
    # Stereo Right
    numSpk = 2
    source_x = 0.8
    source_y = 0.0
    spkX[1] = -1.0
    spkY[1] = 0.0
    spkX[2] = 1.0
    spkY[2] = 0.0
    presetName$ = "StereoRight"
elsif preset = 4
    # Triangle Center
    numSpk = 3
    source_x = 0.0
    source_y = 0.0
    spkX[1] = -0.866
    spkY[1] = -0.5
    spkX[2] = 0.866
    spkY[2] = -0.5
    spkX[3] = 0.0
    spkY[3] = 1.0
    presetName$ = "TriCenter"
elsif preset = 5
    # Triangle Front
    numSpk = 3
    source_x = 0.0
    source_y = 0.7
    spkX[1] = -0.866
    spkY[1] = -0.5
    spkX[2] = 0.866
    spkY[2] = -0.5
    spkX[3] = 0.0
    spkY[3] = 1.0
    presetName$ = "TriFront"
elsif preset = 6
    # Quad Center
    numSpk = 4
    source_x = 0.0
    source_y = 0.0
    for i from 1 to 4
        angle = (i - 1) * 2 * pi / 4 + pi/4
        spkX[i] = cos(angle)
        spkY[i] = sin(angle)
    endfor
    presetName$ = "QuadCenter"
elsif preset = 7
    # Quad Front-Left
    numSpk = 4
    source_x = -0.5
    source_y = 0.5
    for i from 1 to 4
        angle = (i - 1) * 2 * pi / 4 + pi/4
        spkX[i] = cos(angle)
        spkY[i] = sin(angle)
    endfor
    presetName$ = "QuadFL"
elsif preset = 8
    # Hexagon Center
    numSpk = 6
    source_x = 0.0
    source_y = 0.0
    for i from 1 to 6
        angle = (i - 1) * 2 * pi / 6
        spkX[i] = cos(angle)
        spkY[i] = sin(angle)
    endfor
    presetName$ = "HexCenter"
elsif preset = 9
    # Surround 5.1
    numSpk = 6
    source_x = 0.0
    source_y = 0.3
    spkX[1] = -0.7
    spkY[1] = 0.7
    spkX[2] = 0.7
    spkY[2] = 0.7
    spkX[3] = 0.0
    spkY[3] = 1.0
    spkX[4] = -0.7
    spkY[4] = -0.7
    spkX[5] = 0.7
    spkY[5] = -0.7
    spkX[6] = 0.0
    spkY[6] = 0.0
    presetName$ = "5.1"
elsif preset = 10
    # Octagon Center
    numSpk = 8
    source_x = 0.0
    source_y = 0.0
    for i from 1 to 8
        angle = (i - 1) * 2 * pi / 8
        spkX[i] = cos(angle)
        spkY[i] = sin(angle)
    endfor
    presetName$ = "OctCenter"
elsif preset = 11
    # Octagon Front
    numSpk = 8
    source_x = 0.0
    source_y = 0.7
    for i from 1 to 8
        angle = (i - 1) * 2 * pi / 8
        spkX[i] = cos(angle)
        spkY[i] = sin(angle)
    endfor
    presetName$ = "OctFront"
else
    # Custom (preset 12)
    numSpk = number_of_speakers
    for i from 1 to numSpk
        angle = (i - 1) * 2 * pi / numSpk
        spkX[i] = cos(angle)
        spkY[i] = sin(angle)
    endfor
    presetName$ = "Custom"
endif

# === Info ===
writeInfoLine: "=== DBAP Static Panner ==="
appendInfoLine: "Source: ", soundName$
appendInfoLine: "Output channels: ", numSpk
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Source position: (", fixed$(source_x, 2), ", ", fixed$(source_y, 2), ")"
appendInfoLine: "Distance exponent: ", distance_exponent
appendInfoLine: ""

# === Calculate DBAP gains ===
totalPower = 0
for i from 1 to numSpk
    dx = source_x - spkX[i]
    dy = source_y - spkY[i]
    dist = sqrt(dx * dx + dy * dy)
    if dist < minimum_distance
        dist = minimum_distance
    endif
    gain[i] = 1 / (dist ^ distance_exponent)
    totalPower = totalPower + gain[i] * gain[i]
endfor

# Normalize
if normalize_gains and totalPower > 0
    norm = sqrt(totalPower)
    for i from 1 to numSpk
        gain[i] = gain[i] / norm
    endfor
endif

# === Display gains ===
appendInfoLine: "Speaker gains:"
for i from 1 to numSpk
    appendInfoLine: "  Ch", i, " at (", fixed$(spkX[i], 2), ", ", fixed$(spkY[i], 2), "): ", fixed$(gain[i], 4)
endfor
appendInfoLine: ""

# === Create output channels ===
for i from 1 to numSpk
    selectObject: monoID
    Copy: "ch" + string$(i)
    chID[i] = selected("Sound")
    g = gain[i]
    Formula: "self * 'g'"
endfor

# === Combine channels ===
selectObject: chID[1]
for i from 2 to numSpk
    plusObject: chID[i]
endfor
Combine to stereo
result = selected("Sound")
Scale peak: 0.95
Rename: soundName$ + "_DBAP_" + presetName$ + "_" + string$(numSpk) + "ch"

# === Cleanup ===
removeObject: monoID
for i from 1 to numSpk
    removeObject: chID[i]
endfor

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 10, 0, 0.6
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "DBAP Static Panner: " + presetName$ + " (" + string$(numSpk) + "ch) | " + soundName$
    
    # Speaker layout with source
    Select outer viewport: 0.5, 5.5, 0.8, 4.5
    Select inner viewport: 0.8, 5.2, 1.1, 4.2
    
    Axes: -1.5, 1.5, -1.5, 1.5
    Paint rectangle: "{0.95, 0.95, 0.95}", -1.5, 1.5, -1.5, 1.5
    
    # Draw lines from source to speakers
    Line width: 1
    Colour: "{0.7, 0.7, 0.7}"
    for i from 1 to numSpk
        Draw line: source_x, source_y, spkX[i], spkY[i]
    endfor
    
    # Draw speakers (size based on gain)
    for i from 1 to numSpk
        # Size based on gain
        sz = 2 + gain[i] * 5
        Paint circle (mm): "{0.3, 0.5, 0.7}", spkX[i], spkY[i], sz
        Colour: "White"
        Font size: 6
        Text: spkX[i], "centre", spkY[i], "half", string$(i)
    endfor
    
    # Listener at center
    Paint circle (mm): "{0.2, 0.6, 0.3}", 0, 0, 2
    
    # Draw source
    Paint circle (mm): "{0.8, 0.3, 0.3}", source_x, source_y, 4
    Font size: 6
    Colour: "Black"
    Text: source_x + 0.12, "left", source_y + 0.1, "half", "SRC"
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Source & Speakers (size = gain)"
    
    # Gain bar chart
    Select outer viewport: 5.7, 9.5, 0.8, 2.8
    Select inner viewport: 5.9, 9.3, 1.0, 2.6
    
    Axes: 0, numSpk + 1, 0, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, numSpk + 1, 0, 1.2
    
    # Unity line
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: 0.5, 1.0, numSpk + 0.5, 1.0
    Solid line
    
    # Bars
    for i from 1 to numSpk
        g = gain[i]
        if g > 1.2
            g = 1.2
        endif
        Paint rectangle: "{0.3, 0.5, 0.7}", i - 0.35, i + 0.35, 0, g
        Colour: "Black"
        Draw rectangle: i - 0.35, i + 0.35, 0, g
        Font size: 6
        Text: i, "centre", -0.08, "half", string$(i)
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text bottom: "yes", "Channel"
    Text left: "yes", "Gain"
    
    # Output waveform
    Select outer viewport: 5.7, 9.5, 3.0, 4.5
    Select inner viewport: 5.9, 9.3, 3.2, 4.3
    selectObject: result
    Colour: "{0.4, 0.5, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Output"
    
    Font size: 10
    Colour: "Black"
endif

# === Done ===
appendInfoLine: "=== Done ==="
appendInfoLine: "Output: ", selected$("Sound")

if play_result
    selectObject: result
    Play
endif

selectObject: result
