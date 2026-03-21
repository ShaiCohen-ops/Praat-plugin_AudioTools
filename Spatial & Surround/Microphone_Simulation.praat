# ============================================================
# Praat AudioTools - Microphone Simulation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Optimized
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Physically accurate microphone simulation
#   Supports various polar patterns and stereo configurations
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.2:
#   - Fixed critical delay calculation bug (was dividing by period, not rate)
#   - Modern selectObject: syntax throughout
#   - Preset comparison by index (more robust)
#   - Simplified sound selection (uses selected sound directly)
#   - Added visualization of polar patterns and mic configuration
#   - Added draw_visualization toggle
#   - Proper variable naming (samplePeriod vs sampleRate)
#   - Cleaner object cleanup
# ============================================================

clearinfo

# ============================================================
# FORM
# ============================================================

form Microphone Simulation
    comment ─────────────────────────────────────────
    comment Preset (overrides custom settings)
    optionmenu Preset: 1
        option Custom
        option Studio Vocal (Cardioid Mono, 30cm)
        option Blumlein Pair (Fig-8, 1m)
        option ORTF Standard (Cardioid, 1m)
        option Spaced Omnis AB (50cm spacing, 2m)
        option Mid-Side (Cardioid M + Fig-8 S, 1m)
        option Decca Tree (Omni, 3m)
        option Close XY (Cardioid, 50cm)
        option Hypercardioid Spot (Mono, 1.5m)
        option AB Wide (100cm spacing, 2m)
    comment ─────────────────────────────────────────
    comment Microphone Pattern
    optionmenu Pattern: 3
        option Omnidirectional
        option Figure-of-eight
        option Cardioid
        option Hypercardioid
    comment ─────────────────────────────────────────
    comment Stereo Configuration
    optionmenu Stereo_config: 1
        option Mono
        option Mid-Side
        option XY Pair
        option Blumlein Pair
        option AB Pair (omnis)
        option ORTF Pair
        option Decca Tree
    comment ─────────────────────────────────────────
    comment Source Position
    real Azimuth_degrees 0
    comment (0°=front, +90°=right, -90°=left, ±180°=back)
    real Distance_cm 100
    real Mic_spacing_cm 17
    comment ─────────────────────────────────────────
    boolean Apply_distance_attenuation 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESET SYSTEM
# ============================================================

if preset = 2
    # Studio Vocal
    pattern = 3
    stereo_config = 1
    azimuth_degrees = 0
    distance_cm = 30
    presetName$ = "StudioVocal"
elsif preset = 3
    # Blumlein
    pattern = 2
    stereo_config = 4
    azimuth_degrees = 0
    distance_cm = 100
    presetName$ = "Blumlein"
elsif preset = 4
    # ORTF Standard
    pattern = 3
    stereo_config = 6
    azimuth_degrees = 0
    distance_cm = 100
    mic_spacing_cm = 17
    presetName$ = "ORTF"
elsif preset = 5
    # Spaced Omnis AB
    pattern = 1
    stereo_config = 5
    azimuth_degrees = 0
    distance_cm = 200
    mic_spacing_cm = 50
    presetName$ = "AB50"
elsif preset = 6
    # Mid-Side
    pattern = 3
    stereo_config = 2
    azimuth_degrees = 0
    distance_cm = 100
    presetName$ = "MidSide"
elsif preset = 7
    # Decca Tree
    pattern = 1
    stereo_config = 7
    azimuth_degrees = 0
    distance_cm = 300
    presetName$ = "DeccaTree"
elsif preset = 8
    # Close XY
    pattern = 3
    stereo_config = 3
    azimuth_degrees = 0
    distance_cm = 50
    presetName$ = "XY"
elsif preset = 9
    # Hypercardioid Spot
    pattern = 4
    stereo_config = 1
    azimuth_degrees = 0
    distance_cm = 150
    presetName$ = "HyperSpot"
elsif preset = 10
    # AB Wide
    pattern = 1
    stereo_config = 5
    azimuth_degrees = 0
    distance_cm = 200
    mic_spacing_cm = 100
    presetName$ = "ABwide"
else
    presetName$ = "Custom"
endif

# Pattern names
if pattern = 1
    pattern$ = "Omnidirectional"
elsif pattern = 2
    pattern$ = "Figure-of-eight"
elsif pattern = 3
    pattern$ = "Cardioid"
else
    pattern$ = "Hypercardioid"
endif

# Config names
if stereo_config = 1
    config$ = "Mono"
elsif stereo_config = 2
    config$ = "Mid-Side"
elsif stereo_config = 3
    config$ = "XY"
elsif stereo_config = 4
    config$ = "Blumlein"
elsif stereo_config = 5
    config$ = "AB"
elsif stereo_config = 6
    config$ = "ORTF"
else
    config$ = "Decca"
endif

# ============================================================
# VALIDATION
# ============================================================

if numberOfSelected("Sound") = 0
    exitScript: "Please select a Sound object first."
endif

# XY requires directional mics
if stereo_config = 3 and pattern = 1
    exitScript: "XY pair requires directional microphones." + newline$ + "Please select Cardioid, Figure-of-eight, or Hypercardioid." + newline$ + "For omnidirectional spacing, use AB Pair instead."
endif

# AB requires omnis
if stereo_config = 5 and pattern <> 1
    appendInfoLine: "Note: AB pair typically uses omnidirectional mics. Proceeding with selected pattern."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
nChannelsOrig = Get number of channels
duration = Get total duration
samplePeriod = Get sample period
sr = 1 / samplePeriod

# Convert to mono
if nChannelsOrig > 1
    selectObject: original
    monoSound = Convert to mono
else
    selectObject: original
    monoSound = Copy: "mono_work"
endif

# ============================================================
# CONSTANTS
# ============================================================

speedOfSound = 343
azimuthRad = azimuth_degrees * pi / 180
distance_m = distance_cm / 100

# Distance attenuation (1/r, normalized to 1m)
if apply_distance_attenuation
    distanceAmp = 1.0 / max(distance_m, 0.01)
else
    distanceAmp = 1.0
endif

# ============================================================
# INFO OUTPUT
# ============================================================

writeInfoLine: "============================================"
writeInfoLine: "Microphone Simulation v0.2"
writeInfoLine: "============================================"
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Duration: ", fixed$(duration, 3), " s"
appendInfoLine: "Sample rate: ", sr, " Hz"
appendInfoLine: "--------------------------------------------"
if preset > 1
    appendInfoLine: "Preset: ", presetName$
endif
appendInfoLine: "Pattern: ", pattern$
appendInfoLine: "Configuration: ", config$
appendInfoLine: "Azimuth: ", azimuth_degrees, "°"
appendInfoLine: "Distance: ", distance_cm, " cm"
if stereo_config >= 5
    appendInfoLine: "Mic spacing: ", mic_spacing_cm, " cm"
endif
appendInfoLine: "Distance attenuation: ", if apply_distance_attenuation then "ON (1/r)" else "OFF" fi
appendInfoLine: "--------------------------------------------"
appendInfoLine: ""

# ============================================================
# PROCEDURE: Apply polar pattern
# ============================================================

procedure applyPattern: .sound, .azimuth, .patternType
    selectObject: .sound
    if .patternType = 1
        # Omnidirectional: gain = 1
        # No formula needed
    elsif .patternType = 2
        # Figure-of-eight: cos(θ)
        Formula: "self * cos(" + string$(.azimuth) + ")"
    elsif .patternType = 3
        # Cardioid: 0.5 + 0.5*cos(θ)
        Formula: "self * (0.5 + 0.5 * cos(" + string$(.azimuth) + "))"
    elsif .patternType = 4
        # Hypercardioid: 0.25 + 0.75*cos(θ)
        Formula: "self * (0.25 + 0.75 * cos(" + string$(.azimuth) + "))"
    endif
endproc

# ============================================================
# PROCEDURE: Apply fractional sample delay
# ============================================================

procedure applyDelay: .sound, .delaySec
    selectObject: .sound
    .result = .sound
    if abs(.delaySec) > 0.00001
        Shift times by: .delaySec
        .dur = Get total duration
        .newSound = Extract part: 0, .dur, "rectangular", 1, "no"
        removeObject: .sound
        .result = .newSound
    endif
endproc

# ============================================================
# PROCESS: MONO
# ============================================================

if stereo_config = 1
    # Mono - single mic
    selectObject: monoSound
    finalSound = Copy: originalName$ + "_" + pattern$ + "_mono"
    @applyPattern: finalSound, azimuthRad, pattern

# ============================================================
# PROCESS: MID-SIDE
# ============================================================

elsif stereo_config = 2
    # Mid mic (selected pattern, faces forward)
    selectObject: monoSound
    mid = Copy: "mid"
    @applyPattern: mid, azimuthRad, pattern
    
    # Side mic (figure-8, faces sideways)
    # cos(θ + π/2) = -sin(θ) for positive-left convention
    selectObject: monoSound
    side = Copy: "side"
    sideAngle = azimuthRad + pi/2
    selectObject: side
    Formula: "self * cos(" + string$(sideAngle) + ")"
    
    # M/S Decode: L = (M+S)/√2, R = (M-S)/√2
    midId$ = string$(mid)
    sideId$ = string$(side)
    
    selectObject: mid
    left = Copy: "left"
    selectObject: left
    Formula: "(Object_" + midId$ + "[col] + Object_" + sideId$ + "[col]) / sqrt(2)"
    
    selectObject: mid
    right = Copy: "right"
    selectObject: right
    Formula: "(Object_" + midId$ + "[col] - Object_" + sideId$ + "[col]) / sqrt(2)"
    
    selectObject: left
    plusObject: right
    finalSound = Combine to stereo
    selectObject: finalSound
    Rename: originalName$ + "_MS_" + pattern$
    
    removeObject: mid, side, left, right

# ============================================================
# PROCESS: XY PAIR
# ============================================================

elsif stereo_config = 3
    # Two directional mics at ±45°
    selectObject: monoSound
    left = Copy: "xy_L"
    @applyPattern: left, azimuthRad + pi/4, pattern
    
    selectObject: monoSound
    right = Copy: "xy_R"
    @applyPattern: right, azimuthRad - pi/4, pattern
    
    selectObject: left
    plusObject: right
    finalSound = Combine to stereo
    selectObject: finalSound
    Rename: originalName$ + "_XY_" + pattern$
    
    removeObject: left, right

# ============================================================
# PROCESS: BLUMLEIN PAIR
# ============================================================

elsif stereo_config = 4
    # Two figure-8s at ±45°
    selectObject: monoSound
    left = Copy: "blum_L"
    leftAngle = azimuthRad + pi/4
    selectObject: left
    Formula: "self * cos(" + string$(leftAngle) + ")"
    
    selectObject: monoSound
    right = Copy: "blum_R"
    rightAngle = azimuthRad - pi/4
    selectObject: right
    Formula: "self * cos(" + string$(rightAngle) + ")"
    
    selectObject: left
    plusObject: right
    finalSound = Combine to stereo
    selectObject: finalSound
    Rename: originalName$ + "_Blumlein"
    
    removeObject: left, right

# ============================================================
# PROCESS: AB PAIR (spaced omnis)
# ============================================================

elsif stereo_config = 5
    spacing_m = mic_spacing_cm / 100
    
    # Source position in Cartesian (origin at array center)
    sourceX = distance_m * sin(azimuthRad)
    sourceY = distance_m * cos(azimuthRad)
    
    # Distance from source to each mic
    # Left at (-spacing/2, 0), Right at (+spacing/2, 0)
    distL = sqrt((sourceX + spacing_m/2)^2 + sourceY^2)
    distR = sqrt((sourceX - spacing_m/2)^2 + sourceY^2)
    
    # Reference to closest mic
    minDist = min(distL, distR)
    
    # Delays (seconds)
    delayL = (distL - minDist) / speedOfSound
    delayR = (distR - minDist) / speedOfSound
    
    appendInfoLine: "AB delays: L=", fixed$(delayL * 1000, 3), "ms, R=", fixed$(delayR * 1000, 3), "ms"
    
    selectObject: monoSound
    left = Copy: "ab_L"
    @applyDelay: left, delayL
    left = applyDelay.result
    
    selectObject: monoSound
    right = Copy: "ab_R"
    @applyDelay: right, delayR
    right = applyDelay.result
    
    # Apply inverse-distance amplitude
    selectObject: left
    Formula: "self * " + string$(minDist / distL)
    
    selectObject: right
    Formula: "self * " + string$(minDist / distR)
    
    selectObject: left
    plusObject: right
    finalSound = Combine to stereo
    selectObject: finalSound
    Rename: originalName$ + "_AB_" + string$(mic_spacing_cm) + "cm"
    
    removeObject: left, right

# ============================================================
# PROCESS: ORTF PAIR
# ============================================================

elsif stereo_config = 6
    # ORTF: 17cm spacing, ±55° angle
    spacing_m = 0.17
    
    # Time difference based on spacing
    deltaT = (spacing_m / speedOfSound) * sin(azimuthRad)
    
    delayL = -deltaT / 2
    delayR = deltaT / 2
    
    # Ensure positive delays (shift reference)
    if delayL < 0
        delayR = delayR - delayL
        delayL = 0
    endif
    if delayR < 0
        delayL = delayL - delayR
        delayR = 0
    endif
    
    appendInfoLine: "ORTF delays: L=", fixed$(delayL * 1000, 3), "ms, R=", fixed$(delayR * 1000, 3), "ms"
    
    # Left cardioid at +55° from center
    selectObject: monoSound
    left = Copy: "ortf_L"
    @applyPattern: left, azimuthRad + 55*pi/180, 3
    @applyDelay: left, delayL
    left = applyDelay.result
    
    # Right cardioid at -55° from center
    selectObject: monoSound
    right = Copy: "ortf_R"
    @applyPattern: right, azimuthRad - 55*pi/180, 3
    @applyDelay: right, delayR
    right = applyDelay.result
    
    selectObject: left
    plusObject: right
    finalSound = Combine to stereo
    selectObject: finalSound
    Rename: originalName$ + "_ORTF"
    
    removeObject: left, right

# ============================================================
# PROCESS: DECCA TREE
# ============================================================

elsif stereo_config = 7
    # Classic Decca: L-C-R omnis, 2m L-R spacing, 1.5m center forward
    deccaSpacing = 2.0
    centerForward = 1.5
    
    # Source position
    sourceX = distance_m * sin(azimuthRad)
    sourceY = distance_m * cos(azimuthRad)
    
    # Distances to each mic
    distL = sqrt((sourceX + deccaSpacing/2)^2 + sourceY^2)
    distC = sqrt(sourceX^2 + (sourceY - centerForward)^2)
    distR = sqrt((sourceX - deccaSpacing/2)^2 + sourceY^2)
    
    minDist = min(distL, min(distC, distR))
    
    # Delays
    delayL = (distL - minDist) / speedOfSound
    delayC = (distC - minDist) / speedOfSound
    delayR = (distR - minDist) / speedOfSound
    
    appendInfoLine: "Decca delays: L=", fixed$(delayL * 1000, 2), "ms, C=", fixed$(delayC * 1000, 2), "ms, R=", fixed$(delayR * 1000, 2), "ms"
    
    selectObject: monoSound
    left = Copy: "decca_L"
    @applyDelay: left, delayL
    left = applyDelay.result
    
    selectObject: monoSound
    center = Copy: "decca_C"
    @applyDelay: center, delayC
    center = applyDelay.result
    
    selectObject: monoSound
    right = Copy: "decca_R"
    @applyDelay: right, delayR
    right = applyDelay.result
    
    # Apply inverse-distance amplitude
    selectObject: left
    Formula: "self * " + string$(minDist / distL)
    
    selectObject: center
    Formula: "self * " + string$(minDist / distC)
    
    selectObject: right
    Formula: "self * " + string$(minDist / distR)
    
    # Mix: L+0.7C and R+0.7C
    centerId$ = string$(center)
    
    selectObject: left
    leftMix = Copy: "left_mix"
    selectObject: leftMix
    Formula: "self + 0.7 * Object_" + centerId$ + "[col]"
    
    selectObject: right
    rightMix = Copy: "right_mix"
    selectObject: rightMix
    Formula: "self + 0.7 * Object_" + centerId$ + "[col]"
    
    selectObject: leftMix
    plusObject: rightMix
    finalSound = Combine to stereo
    selectObject: finalSound
    Rename: originalName$ + "_DeccaTree"
    
    removeObject: left, center, right, leftMix, rightMix
endif

# ============================================================
# APPLY DISTANCE ATTENUATION
# ============================================================

if distanceAmp <> 1.0
    selectObject: finalSound
    Formula: "self * " + string$(distanceAmp)
endif

# Scale output
selectObject: finalSound
Scale peak: 0.99

# ============================================================
# CLEANUP
# ============================================================

removeObject: monoSound

# ============================================================
# VISUALIZATION
# ============================================================

# Pre-build summary strings
attenStr$ = "OFF"
if apply_distance_attenuation
    attenStr$ = "1/r"
endif

if draw_visualization
    Erase all
    Select outer viewport: 0, 8, 0, 8

    # ----------------------------------------------------------
    # Title
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.75
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##Microphone Simulation##"
    Font size: 8
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.15, "half",
        ... originalName$ + "  |  " + config$ + "  " + pattern$
        ... + "  |  " + presetName$

    # ----------------------------------------------------------
    # Polar pattern diagram (left half)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.1, 0.52, 3.42
    Select inner viewport: 0.45, 3.85, 0.62, 3.30

    Axes: -1.35, 1.35, -1.35, 1.35
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.35, 1.35, -1.35, 1.35

    # Grid circles
    Colour: "{0.85, 0.85, 0.85}"
    Line width: 1
    Draw circle: 0, 0, 0.25
    Draw circle: 0, 0, 0.50
    Draw circle: 0, 0, 0.75
    Draw circle: 0, 0, 1.00

    # Crosshairs
    Draw line: 0, -1.25, 0, 1.25
    Draw line: -1.25, 0, 1.25, 0

    # Direction labels
    Font size: 6
    Colour: "{0.50, 0.50, 0.50}"
    Text: 0.08, "left", 1.22, "half", "0° Front"
    Text: 0.08, "left", -1.22, "half", "180° Back"
    Text: -1.28, "right", -0.12, "half", "-90° L"
    Text: 1.28, "left", -0.12, "half", "+90° R"

    # Draw polar pattern curve
    Colour: "{0.25, 0.50, 0.72}"
    Line width: 2
    nPoints = 360
    for i from 0 to nPoints
        angle = i * 2 * pi / nPoints
        if pattern = 1
            pGain = 1.0
        elsif pattern = 2
            pGain = abs(cos(angle))
        elsif pattern = 3
            pGain = 0.5 + 0.5 * cos(angle)
        else
            pGain = max(0, 0.25 + 0.75 * cos(angle))
        endif
        px = pGain * sin(angle)
        py = pGain * cos(angle)
        if i > 0
            Draw line: prevX, prevY, px, py
        endif
        prevX = px
        prevY = py
    endfor

    # Draw source position
    srcDist = min(distance_m / 3, 1.15)
    srcPx = srcDist * sin(azimuthRad)
    srcPy = srcDist * cos(azimuthRad)

    Colour: "{0.82, 0.28, 0.28}"
    Line width: 2
    Draw arrow: 0, 0, srcPx, srcPy
    Paint circle (mm): "{0.90, 0.30, 0.30}", srcPx, srcPy, 2.5
    Line width: 1

    # Source label — position adaptively to avoid clipping
    Font size: 6
    Colour: "{0.60, 0.25, 0.25}"
    if srcPy > 0
        Text: srcPx, "centre", srcPy + 0.14, "half", "Src " + string$(azimuth_degrees) + "°"
    else
        Text: srcPx, "centre", srcPy - 0.14, "half", "Src " + string$(azimuth_degrees) + "°"
    endif

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Polar pattern: " + pattern$

    # ----------------------------------------------------------
    # Configuration diagram (right half)
    # ----------------------------------------------------------
    Select outer viewport: 4.1, 8, 0.52, 3.42
    Select inner viewport: 4.40, 7.70, 0.62, 3.30

    Axes: -1.6, 1.6, -0.4, 2.2
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.6, 1.6, -0.4, 2.2

    # Mic positions (blue = L, red = R, grey = C)
    Colour: "{0.25, 0.50, 0.72}"
    Line width: 2

    if stereo_config = 1
        # Mono
        Paint circle (mm): "{0.25, 0.50, 0.72}", 0, 0.6, 3.5
        Font size: 7
        Colour: "{0.25, 0.25, 0.25}"
        Text: 0, "centre", 0.30, "half", "Mono"

    elsif stereo_config = 2
        # M/S
        Paint circle (mm): "{0.25, 0.50, 0.72}", 0, 0.6, 3.5
        Paint circle (mm): "{0.82, 0.35, 0.35}", 0.22, 0.6, 2.8
        Font size: 6
        Colour: "{0.25, 0.25, 0.25}"
        Text: 0, "centre", 0.30, "half", "M"
        Text: 0.22, "centre", 0.30, "half", "S"
        # M points forward, S points sideways
        Draw line: 0, 0.6, 0, 1.0
        Colour: "{0.82, 0.35, 0.35}"
        Draw line: 0.22, 0.6, 0.55, 0.6

    elsif stereo_config = 3 or stereo_config = 4
        # XY or Blumlein — coincident pair at ±45°
        Paint circle (mm): "{0.25, 0.50, 0.72}", -0.12, 0.6, 2.8
        Paint circle (mm): "{0.82, 0.35, 0.35}", 0.12, 0.6, 2.8
        # Direction lines at ±45°
        Colour: "{0.25, 0.50, 0.72}"
        Draw line: -0.12, 0.6, -0.12 + 0.35 * sin(-pi/4), 0.6 + 0.35 * cos(-pi/4)
        Colour: "{0.82, 0.35, 0.35}"
        Draw line: 0.12, 0.6, 0.12 + 0.35 * sin(pi/4), 0.6 + 0.35 * cos(pi/4)
        Font size: 6
        Colour: "{0.25, 0.25, 0.25}"
        if stereo_config = 3
            Text: 0, "centre", 0.28, "half", "XY ±45°"
        else
            Text: 0, "centre", 0.28, "half", "Blumlein ±45°"
        endif

    elsif stereo_config = 5
        # AB spaced omnis
        spacing_vis = min(mic_spacing_cm / 100, 1.2)
        Paint circle (mm): "{0.25, 0.50, 0.72}", -spacing_vis/2, 0.6, 2.8
        Paint circle (mm): "{0.82, 0.35, 0.35}", spacing_vis/2, 0.6, 2.8
        Colour: "{0.65, 0.65, 0.65}"
        Line width: 1
        Draw line: -spacing_vis/2, 0.42, spacing_vis/2, 0.42
        Font size: 6
        Colour: "{0.25, 0.25, 0.25}"
        Text: 0, "centre", 0.26, "half", "AB " + string$(mic_spacing_cm) + " cm"

    elsif stereo_config = 6
        # ORTF — 17cm spacing, ±55°
        Paint circle (mm): "{0.25, 0.50, 0.72}", -0.12, 0.6, 2.8
        Paint circle (mm): "{0.82, 0.35, 0.35}", 0.12, 0.6, 2.8
        Colour: "{0.25, 0.50, 0.72}"
        Draw line: -0.12, 0.6, -0.12 + 0.30 * sin(-55*pi/180), 0.6 + 0.30 * cos(-55*pi/180)
        Colour: "{0.82, 0.35, 0.35}"
        Draw line: 0.12, 0.6, 0.12 + 0.30 * sin(55*pi/180), 0.6 + 0.30 * cos(55*pi/180)
        Font size: 6
        Colour: "{0.25, 0.25, 0.25}"
        Text: 0, "centre", 0.26, "half", "ORTF 17cm 110°"

    elsif stereo_config = 7
        # Decca Tree — L C R
        Paint circle (mm): "{0.25, 0.50, 0.72}", -0.55, 0.4, 2.8
        Paint circle (mm): "{0.55, 0.55, 0.55}", 0, 0.95, 2.8
        Paint circle (mm): "{0.82, 0.35, 0.35}", 0.55, 0.4, 2.8
        # Connecting lines
        Colour: "{0.78, 0.78, 0.78}"
        Line width: 1
        Dotted line
        Draw line: -0.55, 0.4, 0, 0.95
        Draw line: 0, 0.95, 0.55, 0.4
        Draw line: -0.55, 0.4, 0.55, 0.4
        Solid line
        Font size: 6
        Colour: "{0.25, 0.25, 0.25}"
        Text: -0.55, "centre", 0.18, "half", "L"
        Text: 0, "centre", 1.12, "half", "C"
        Text: 0.55, "centre", 0.18, "half", "R"
    endif

    # Source position indicator
    cfgSrcY = 1.75
    cfgSrcX = cfgSrcY * sin(azimuthRad)
    if abs(cfgSrcX) > 1.35
        cfgSrcX = 1.35 * (cfgSrcX / abs(cfgSrcX))
    endif
    Colour: "{0.82, 0.28, 0.28}"
    Paint circle (mm): "{0.90, 0.30, 0.30}", cfgSrcX, cfgSrcY, 2
    # Dotted line from array centre to source
    Colour: "{0.82, 0.65, 0.65}"
    Dotted line
    Draw line: 0, 0.6, cfgSrcX, cfgSrcY
    Solid line
    Font size: 6
    Colour: "{0.60, 0.25, 0.25}"
    Text: cfgSrcX, "centre", cfgSrcY - 0.18, "half",
        ... string$(azimuth_degrees) + "°  " + string$(distance_cm) + "cm"

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Configuration: " + config$

    # ----------------------------------------------------------
    # Output waveform (L blue, R orange)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 3.50, 4.60
    Select inner viewport: 0.55, 7.70, 3.58, 4.52

    selectObject: finalSound
    nChOut = Get number of channels
    outPeak = Get absolute extremum: 0, 0, "None"
    if outPeak < 0.001
        outPeak = 0.001
    endif
    ampMax = outPeak * 1.15

    Axes: 0, duration, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, -ampMax, ampMax
    Colour: "{0.80, 0.80, 0.80}"
    Draw line: 0, 0, duration, 0

    if nChOut > 1
        selectObject: finalSound
        Extract one channel: 1
        vizL = selected("Sound")
        Colour: "{0.25, 0.50, 0.82}"
        Draw: 0, 0, -ampMax, ampMax, "no", "Curve"

        selectObject: finalSound
        Extract one channel: 2
        vizR = selected("Sound")
        Colour: "{0.82, 0.45, 0.25}"
        Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
        removeObject: vizL, vizR
    else
        selectObject: finalSound
        Colour: "{0.25, 0.50, 0.82}"
        Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    endif

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    if nChOut > 1
        Text top: "no", "Stereo output  (blue=L  orange=R)"
    else
        Text top: "no", "Mono output"
    endif
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # Summary panel
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.70, 5.45
    Select inner viewport: 0.55, 7.70, 4.76, 5.38
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.82, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.52, "half",
        ... "Source: " + originalName$
        ... + "  |  Config: " + config$ + "  " + pattern$
        ... + "  |  Preset: " + presetName$
    Text: 0.02, "left", 0.20, "half",
        ... "Azimuth: " + string$(azimuth_degrees) + "°"
        ... + "  |  Dist: " + string$(distance_cm) + " cm"
        ... + "  |  Spacing: " + string$(mic_spacing_cm) + " cm"
        ... + "  |  Dist atten: " + attenStr$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================
# FINAL OUTPUT
# ============================================================

selectObject: finalSound

appendInfoLine: ""
appendInfoLine: "============================================"
appendInfoLine: "PROCESSING COMPLETE"
appendInfoLine: "============================================"
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: ""
appendInfoLine: "Configuration: ", config$
appendInfoLine: "Pattern: ", pattern$
appendInfoLine: "Source: ", azimuth_degrees, "° at ", distance_cm, "cm"

# ============================================================
# PLAY RESULT
# ============================================================

if play_result
    selectObject: finalSound
    Play
endif

selectObject: finalSound