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
    Select outer viewport: 0, 8, 0, 8

    # ----------------------------------------------------------
    # Title
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##DBAP Static Panner##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.25, "half",
        ... soundName$ + "  |  " + presetName$
        ... + "  |  " + string$(numSpk) + " ch"
        ... + "  |  src=(" + fixed$(source_x, 2) + ", " + fixed$(source_y, 2) + ")"

    # ----------------------------------------------------------
    # Speaker layout diagram (left half)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.5, 0.52, 3.82
    Select inner viewport: 0.50, 4.20, 0.62, 3.70

    Axes: -1.6, 1.6, -1.6, 1.6
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.6, 1.6, -1.6, 1.6

    # Unit circle reference
    Colour: "{0.88, 0.88, 0.88}"
    Line width: 1
    Draw circle: 0, 0, 1.0

    # Crosshairs
    Draw line: 0, -1.45, 0, 1.45
    Draw line: -1.45, 0, 1.45, 0

    # Lines from source to speakers (thickness = gain)
    for i from 1 to numSpk
        lineW = 0.5 + gain[i] * 3.0
        if lineW > 4
            lineW = 4
        endif
        Colour: "{0.75, 0.75, 0.75}"
        Line width: lineW
        Draw line: source_x, source_y, spkX[i], spkY[i]
    endfor
    Line width: 1

    # Speaker dots (size = gain)
    for i from 1 to numSpk
        sz = 1.5 + gain[i] * 4.0
        if sz > 6
            sz = 6
        endif
        Paint circle (mm): "{0.25, 0.50, 0.72}", spkX[i], spkY[i], sz

        # Channel number — offset outward from centre
        dx = spkX[i]
        dy = spkY[i]
        dLen = sqrt(dx * dx + dy * dy)
        if dLen < 0.01
            dLen = 0.01
        endif
        lblX = spkX[i] + dx / dLen * 0.20
        lblY = spkY[i] + dy / dLen * 0.20
        Font size: 6
        Colour: "{0.20, 0.40, 0.60}"
        Text: lblX, "centre", lblY, "half", string$(i)

        # Gain value below speaker
        gLblY = spkY[i] - dy / dLen * 0.18
        Font size: 5
        Colour: "{0.45, 0.45, 0.45}"
        Text: spkX[i], "centre", gLblY, "half", fixed$(gain[i], 3)
    endfor

    # Listener at centre
    Paint circle (mm): "{0.22, 0.62, 0.30}", 0, 0, 2.0
    Font size: 5
    Colour: "{0.15, 0.45, 0.18}"
    Text: 0, "centre", -0.18, "half", "Listener"

    # Source
    Paint circle (mm): "{0.82, 0.28, 0.28}", source_x, source_y, 3.5
    Font size: 6
    Colour: "{0.60, 0.20, 0.20}"
    # Adaptive label: place away from centre
    srcLblX = source_x
    srcLblY = source_y
    if source_y >= 0
        srcLblY = source_y + 0.18
    else
        srcLblY = source_y - 0.18
    endif
    Text: srcLblX, "centre", srcLblY, "half", "SRC"

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Speaker layout  (dot size = gain,  line thickness = gain)"

    # ----------------------------------------------------------
    # Gain bar chart (right half)
    # ----------------------------------------------------------
    Select outer viewport: 4.5, 8, 0.52, 2.42
    Select inner viewport: 4.80, 7.65, 0.62, 2.30

    maxGainViz = 0
    for i from 1 to numSpk
        if gain[i] > maxGainViz
            maxGainViz = gain[i]
        endif
    endfor
    if maxGainViz < 0.01
        maxGainViz = 1.0
    endif
    gTop = maxGainViz * 1.25

    Axes: 0.3, numSpk + 0.7, 0, gTop
    Paint rectangle: "{0.96, 0.96, 0.96}", 0.3, numSpk + 0.7, 0, gTop

    # Unity reference
    if gTop >= 1.0
        Colour: "{0.78, 0.78, 0.78}"
        Dotted line
        Draw line: 0.3, 1.0, numSpk + 0.7, 1.0
        Solid line
    endif

    for i from 1 to numSpk
        g = gain[i]
        # Colour matches speaker layout
        Paint rectangle: "{0.25, 0.50, 0.72}", i - 0.32, i + 0.32, 0, g
        Colour: "{0.18, 0.38, 0.58}"
        Draw rectangle: i - 0.32, i + 0.32, 0, g
        # Gain value above bar
        Font size: 5
        Colour: "{0.30, 0.30, 0.30}"
        Text: i, "centre", g + gTop * 0.04, "half", fixed$(g, 3)
        # Channel number below
        Font size: 6
        Text: i, "centre", -gTop * 0.06, "half", string$(i)
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Gain"
    Text bottom: "yes", "Channel"
    Text top: "no", "DBAP gains"

    # ----------------------------------------------------------
    # Output waveform (mono downmix of multichannel result)
    # ----------------------------------------------------------
    Select outer viewport: 4.5, 8, 2.52, 3.82
    Select inner viewport: 4.80, 7.65, 2.60, 3.72

    selectObject: result
    vizDown = Convert to mono
    Colour: "{0.35, 0.50, 0.65}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    removeObject: vizDown
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Mix"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Mono downmix"

    # ----------------------------------------------------------
    # Summary panel
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 3.92, 4.82
    Select inner viewport: 0.50, 7.65, 3.98, 4.76
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.82, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"

    # Build gain list
    gainList$ = ""
    for i from 1 to numSpk
        if i > 1
            gainList$ = gainList$ + "  "
        endif
        gainList$ = gainList$ + string$(i) + ":" + fixed$(gain[i], 3)
    endfor

    Text: 0.02, "left", 0.55, "half",
        ... "Preset: " + presetName$
        ... + "  |  Speakers: " + string$(numSpk)
        ... + "  |  Source: (" + fixed$(source_x, 2) + ", " + fixed$(source_y, 2) + ")"
        ... + "  |  Exponent: " + fixed$(distance_exponent, 1)
    Text: 0.02, "left", 0.22, "half",
        ... "Gains:  " + gainList$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# === Done ===
selectObject: result
appendInfoLine: "=== Done ==="
appendInfoLine: "Output: ", selected$("Sound")

if play_result
    selectObject: result
    Play
endif

selectObject: result
