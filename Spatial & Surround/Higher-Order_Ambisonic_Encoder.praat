# ============================================================
# Praat AudioTools - Higher-Order Ambisonic Encoder.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Optimized
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Higher-Order Ambisonic (HOA) Encoder
#   Encodes a mono source into B-format ambisonic channels
#   Supports 1st, 2nd, and 3rd order ambisonics (ACN/SN3D)
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
#   - Modern selectObject: syntax throughout
#   - Added output format option (individual or combined multichannel)
#   - Array storage for channel objects and coefficients
#   - Robust formula string building
#   - Improved visualization with elevation indicator
#   - Added play_result toggle
#   - Better preset organization
#   - Proper cleanup of temporary objects
# ============================================================

# ============================================================
# FORM
# ============================================================

form Ambisonic Encoder
    comment Source Position
    comment ─────────────────────────────────────────
    optionmenu Position_preset: 1
        option Custom
        option Front center (0°, 0°)
        option Front left (315°, 0°)
        option Left (270°, 0°)
        option Rear left (225°, 0°)
        option Rear center (180°, 0°)
        option Rear right (135°, 0°)
        option Right (90°, 0°)
        option Front right (45°, 0°)
        option Above front (0°, 45°)
        option Above (0°, 90°)
        option Below (0°, -45°)
    comment ─────────────────────────────────────────
    real Azimuth_(degrees_0-360) 0
    real Elevation_(degrees_-90_to_90) 0
    real Distance_(meters) 1.0
    real Reference_distance_(meters) 1.0
    comment ─────────────────────────────────────────
    optionmenu Ambisonic_order: 1
        option 1st order (4 channels)
        option 2nd order (9 channels)
        option 3rd order (16 channels)
    comment ─────────────────────────────────────────
    optionmenu Output_format: 1
        option Individual channels (W, Y, Z, X, ...)
        option Combined multichannel B-format
        option Both
    comment ─────────────────────────────────────────
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 0
endform

clearinfo

# ============================================================
# PRESET SYSTEM
# ============================================================

if position_preset = 2
    # Front center
    azimuth = 0
    elevation = 0
    presetName$ = "front"
elsif position_preset = 3
    # Front left
    azimuth = 315
    elevation = 0
    presetName$ = "front_left"
elsif position_preset = 4
    # Left
    azimuth = 270
    elevation = 0
    presetName$ = "left"
elsif position_preset = 5
    # Rear left
    azimuth = 225
    elevation = 0
    presetName$ = "rear_left"
elsif position_preset = 6
    # Rear center
    azimuth = 180
    elevation = 0
    presetName$ = "rear"
elsif position_preset = 7
    # Rear right
    azimuth = 135
    elevation = 0
    presetName$ = "rear_right"
elsif position_preset = 8
    # Right
    azimuth = 90
    elevation = 0
    presetName$ = "right"
elsif position_preset = 9
    # Front right
    azimuth = 45
    elevation = 0
    presetName$ = "front_right"
elsif position_preset = 10
    # Above front
    azimuth = 0
    elevation = 45
    presetName$ = "above_front"
elsif position_preset = 11
    # Above
    azimuth = 0
    elevation = 90
    presetName$ = "above"
elsif position_preset = 12
    # Below
    azimuth = 0
    elevation = -45
    presetName$ = "below"
else
    # Custom
    presetName$ = "custom"
endif

# ============================================================
# VALIDATION
# ============================================================

if numberOfSelected("Sound") = 0
    exitScript: "Please select a Sound object first."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
nChannelsOrig = Get number of channels
duration = Get total duration
sr = Get sampling frequency

# Convert to mono if needed
if nChannelsOrig > 1
    selectObject: original
    workSound = Convert to mono
    wasStereo = 1
else
    selectObject: original
    workSound = Copy: "work_temp"
    wasStereo = 0
endif

# Validate distance
if distance <= 0
    distance = 0.001
endif
if reference_distance <= 0
    reference_distance = 1.0
endif

# Normalize azimuth to 0-360
while azimuth < 0
    azimuth = azimuth + 360
endwhile
while azimuth >= 360
    azimuth = azimuth - 360
endwhile

# Clamp elevation
if elevation > 90
    elevation = 90
elsif elevation < -90
    elevation = -90
endif

# Determine number of channels
if ambisonic_order = 1
    numChannels = 4
    orderName$ = "1st"
elsif ambisonic_order = 2
    numChannels = 9
    orderName$ = "2nd"
else
    numChannels = 16
    orderName$ = "3rd"
endif

# Channel names (ACN ordering)
channelLabel$[1] = "W"
channelLabel$[2] = "Y"
channelLabel$[3] = "Z"
channelLabel$[4] = "X"
if ambisonic_order >= 2
    channelLabel$[5] = "V"
    channelLabel$[6] = "T"
    channelLabel$[7] = "R"
    channelLabel$[8] = "S"
    channelLabel$[9] = "U"
endif
if ambisonic_order >= 3
    channelLabel$[10] = "Q"
    channelLabel$[11] = "O"
    channelLabel$[12] = "M"
    channelLabel$[13] = "K"
    channelLabel$[14] = "L"
    channelLabel$[15] = "N"
    channelLabel$[16] = "P"
endif

# ============================================================
# INFO OUTPUT
# ============================================================

writeInfoLine: "============================================"
writeInfoLine: "Higher-Order Ambisonic Encoder v0.2"
writeInfoLine: "============================================"
appendInfoLine: "Input: ", originalName$
if wasStereo
    appendInfoLine: "  (converted from stereo to mono)"
endif
appendInfoLine: "Duration: ", fixed$(duration, 3), " s"
appendInfoLine: "Sample rate: ", sr, " Hz"
appendInfoLine: "--------------------------------------------"
appendInfoLine: "Source position:"
appendInfoLine: "  Azimuth: ", fixed$(azimuth, 1), "°"
appendInfoLine: "  Elevation: ", fixed$(elevation, 1), "°"
appendInfoLine: "  Distance: ", fixed$(distance, 2), " m"
appendInfoLine: "  Reference: ", fixed$(reference_distance, 2), " m"
appendInfoLine: "--------------------------------------------"
appendInfoLine: "Ambisonic order: ", orderName$, " (", numChannels, " channels)"
appendInfoLine: "Output format: ", if output_format = 1 then "Individual" else if output_format = 2 then "Combined" else "Both" fi fi
appendInfoLine: "--------------------------------------------"
appendInfoLine: ""

# ============================================================
# CALCULATE ENCODING COEFFICIENTS
# ============================================================

appendInfoLine: "Calculating encoding coefficients..."

# Distance attenuation (inverse distance law)
distanceGain = reference_distance / distance
distanceGain_dB = 20 * log10(distanceGain)

appendInfoLine: "  Distance gain: ", fixed$(distanceGain, 4), " (", fixed$(distanceGain_dB, 1), " dB)"

# Convert to radians
azRad = azimuth * pi / 180
elRad = elevation * pi / 180

# Trigonometric values
cos_az = cos(azRad)
sin_az = sin(azRad)
cos_el = cos(elRad)
sin_el = sin(elRad)
cos_el_sq = cos_el * cos_el
sin_el_sq = sin_el * sin_el

# Constants
sqrt3 = sqrt(3)
sqrt5 = sqrt(5)
sqrt15 = sqrt(15)

# 1st order coefficients (ACN/SN3D)
# W = 1 (omnidirectional)
# Y = sin(az) * cos(el)
# Z = sin(el)
# X = cos(az) * cos(el)

coeff[1] = 1.0
coeff[2] = sin_az * cos_el
coeff[3] = sin_el
coeff[4] = cos_az * cos_el

# 2nd order coefficients
if ambisonic_order >= 2
    cos_2az = cos(2 * azRad)
    sin_2az = sin(2 * azRad)
    
    coeff[5] = sqrt3 * sin_2az * cos_el_sq * 0.5
    coeff[6] = sqrt3 * sin_az * sin_el * cos_el
    coeff[7] = 0.5 * (3 * sin_el_sq - 1)
    coeff[8] = sqrt3 * cos_az * sin_el * cos_el
    coeff[9] = sqrt3 * cos_2az * cos_el_sq * 0.5
endif

# 3rd order coefficients
if ambisonic_order >= 3
    cos_2az = cos(2 * azRad)
    sin_2az = sin(2 * azRad)
    cos_3az = cos(3 * azRad)
    sin_3az = sin(3 * azRad)
    
    coeff[10] = sqrt5 * sin_3az * cos_el * cos_el_sq * 0.25
    coeff[11] = sqrt15 * sin_2az * sin_el * cos_el_sq * 0.5
    coeff[12] = sqrt3 * sin_az * cos_el * (5 * sin_el_sq - 1) * 0.25
    coeff[13] = 0.5 * sin_el * (5 * sin_el_sq - 3)
    coeff[14] = sqrt3 * cos_az * cos_el * (5 * sin_el_sq - 1) * 0.25
    coeff[15] = sqrt15 * cos_2az * sin_el * cos_el_sq * 0.5
    coeff[16] = sqrt5 * cos_3az * cos_el * cos_el_sq * 0.25
endif

# Display coefficients
appendInfoLine: ""
appendInfoLine: "Encoding coefficients:"
for ch from 1 to numChannels
    appendInfoLine: "  ", channelLabel$[ch], ": ", fixed$(coeff[ch], 6)
endfor
appendInfoLine: ""

# ============================================================
# ENCODE: CREATE AMBISONIC CHANNELS
# ============================================================

appendInfoLine: "Encoding ambisonic channels..."

for ch from 1 to numChannels
    # Calculate final gain (coefficient * distance attenuation)
    finalGain = coeff[ch] * distanceGain
    gainStr$ = fixed$(finalGain, 10)
    
    # Create channel
    selectObject: workSound
    ambiChannel[ch] = Copy: originalName$ + "_" + channelLabel$[ch]
    
    selectObject: ambiChannel[ch]
    Formula: "self * " + gainStr$
    
    appendInfoLine: "  Channel ", ch, " (", channelLabel$[ch], "): gain = ", fixed$(finalGain, 6)
endfor

appendInfoLine: ""

# ============================================================
# NORMALIZE (if requested)
# ============================================================

if normalize_output
    appendInfoLine: "Normalizing channels..."
    
    # Find global peak across all channels
    globalPeak = 0
    for ch from 1 to numChannels
        selectObject: ambiChannel[ch]
        peak = Get absolute extremum: 0, 0, "None"
        if peak > globalPeak
            globalPeak = peak
        endif
    endfor
    
    # Apply uniform scaling
    if globalPeak > 0
        scaleFactor = 0.99 / globalPeak
        scaleStr$ = fixed$(scaleFactor, 10)
        
        for ch from 1 to numChannels
            selectObject: ambiChannel[ch]
            Formula: "self * " + scaleStr$
        endfor
        
        appendInfoLine: "  Global peak: ", fixed$(globalPeak, 4)
        appendInfoLine: "  Scale factor: ", fixed$(scaleFactor, 4)
    endif
    
    appendInfoLine: ""
endif

# ============================================================
# CREATE COMBINED OUTPUT (if requested)
# ============================================================

if output_format >= 2
    appendInfoLine: "Creating combined multichannel B-format..."
    
    selectObject: ambiChannel[1]
    for ch from 2 to numChannels
        plusObject: ambiChannel[ch]
    endfor
    
    combinedResult = Combine to stereo
    selectObject: combinedResult
    Rename: originalName$ + "_Bformat_" + orderName$ + "_" + presetName$
    
    appendInfoLine: "  Created: ", selected$("Sound")
    appendInfoLine: ""
endif

# ============================================================
# CLEANUP INDIVIDUAL CHANNELS (if only combined output)
# ============================================================

if output_format = 2
    # Remove individual channels, keep only combined
    for ch from 1 to numChannels
        removeObject: ambiChannel[ch]
    endfor
endif

# Clean up work sound
removeObject: workSound

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
    Text: 0.5, "centre", 0.65, "half", "##Ambisonic Encoder##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.25, "half",
        ... originalName$ + "  |  " + orderName$ + " order (" + string$(numChannels) + " ch)"
        ... + "  |  az=" + fixed$(azimuth, 0) + "°  el=" + fixed$(elevation, 0) + "°"
        ... + "  |  d=" + fixed$(distance, 2) + "m"

    # ----------------------------------------------------------
    # Top-down view — azimuth (left half)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.52, 3.52
    Select inner viewport: 0.45, 3.95, 0.62, 3.40

    Axes: -1.5, 1.5, -1.5, 1.5
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.5, 1.5, -1.5, 1.5

    # Distance circles
    Colour: "{0.86, 0.86, 0.86}"
    Line width: 1
    maxDist = max(distance, 1) * 1.2
    for r from 1 to 4
        radius = r / 4 * maxDist
        if radius <= 1.3
            Draw circle: 0, 0, radius
        endif
    endfor

    # Crosshairs
    Colour: "{0.78, 0.78, 0.78}"
    Draw line: 0, -1.4, 0, 1.4
    Draw line: -1.4, 0, 1.4, 0
    Dotted line
    Draw line: -1, -1, 1, 1
    Draw line: -1, 1, 1, -1
    Solid line

    # Direction labels
    Font size: 6
    Colour: "{0.50, 0.50, 0.50}"
    Text: 0.08, "left", 1.38, "half", "0° Front"
    Text: 0.08, "left", -1.38, "half", "180° Rear"
    Text: -1.42, "right", -0.12, "half", "270° L"
    Text: 1.42, "left", -0.12, "half", "90° R"

    # Listener
    Paint circle (mm): "{0.35, 0.35, 0.35}", 0, 0, 2.5

    # Source arrow + marker
    displayDist = min(distance, maxDist) / maxDist * 1.2
    srcX = displayDist * sin(azRad)
    srcY = displayDist * cos(azRad)
    Colour: "{0.82, 0.28, 0.28}"
    Line width: 2
    Draw arrow: 0, 0, srcX, srcY

    markerSize = 2.5 + abs(elevation) / 90 * 1.5
    if elevation >= 0
        Paint circle (mm): "{0.90, 0.30, 0.30}", srcX, srcY, markerSize
    else
        Colour: "{0.90, 0.30, 0.30}"
        Draw circle (mm): srcX, srcY, markerSize
    endif

    Font size: 5
    Colour: "{0.60, 0.22, 0.22}"
    if srcY >= 0
        Text: srcX, "centre", srcY + 0.16, "half", "Src"
    else
        Text: srcX, "centre", srcY - 0.16, "half", "Src"
    endif

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Top view (azimuth)  •=filled above horizon  ○=below"

    # ----------------------------------------------------------
    # Side view — elevation (right, upper)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.52, 2.22
    Select inner viewport: 4.50, 7.65, 0.62, 2.10

    Axes: -0.2, 1.5, -1.2, 1.2
    Paint rectangle: "{0.96, 0.96, 0.96}", -0.2, 1.5, -1.2, 1.2

    # Horizon
    Colour: "{0.78, 0.78, 0.78}"
    Draw line: 0, 0, 1.4, 0

    # Elevation arc
    Colour: "{0.86, 0.86, 0.86}"
    Dotted line
    for a from -90 to 90
        aRad = a * pi / 180
        x1 = cos(aRad)
        y1 = sin(aRad)
        if a > -90
            Draw line: prevArcX, prevArcY, x1, y1
        endif
        prevArcX = x1
        prevArcY = y1
    endfor
    Solid line

    Font size: 6
    Colour: "{0.50, 0.50, 0.50}"
    Text: -0.08, "right", 1.05, "half", "+90°"
    Text: -0.08, "right", -1.05, "half", "-90°"
    Text: 1.25, "centre", 0.12, "half", "0°"

    # Listener
    Paint circle (mm): "{0.35, 0.35, 0.35}", 0, 0, 2

    # Source in side view
    sideX = displayDist * cos(elRad)
    sideY = displayDist * sin(elRad)
    Colour: "{0.82, 0.28, 0.28}"
    Line width: 2
    Draw arrow: 0, 0, sideX, sideY
    Paint circle (mm): "{0.90, 0.30, 0.30}", sideX, sideY, 2.5
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Side view (elevation)"

    # ----------------------------------------------------------
    # Coefficient bar chart (right, lower)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 2.30, 3.52
    Select inner viewport: 4.50, 7.65, 2.40, 3.40

    maxCoeff = 0
    for ch from 1 to numChannels
        if abs(coeff[ch]) > maxCoeff
            maxCoeff = abs(coeff[ch])
        endif
    endfor
    if maxCoeff < 0.01
        maxCoeff = 1
    endif
    cTop = maxCoeff * 1.2

    Axes: 0.3, numChannels + 0.7, -cTop, cTop
    Paint rectangle: "{0.96, 0.96, 0.96}", 0.3, numChannels + 0.7, -cTop, cTop

    # Zero line
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0.3, 0, numChannels + 0.7, 0

    for ch from 1 to numChannels
        c = coeff[ch]
        if c >= 0
            barCol$ = "{0.35, 0.58, 0.78}"
        else
            barCol$ = "{0.78, 0.48, 0.35}"
        endif
        Paint rectangle: barCol$, ch - 0.30, ch + 0.30, 0, c
        Font size: 5
        Colour: "{0.35, 0.35, 0.35}"
        Text: ch, "centre", -cTop * 0.92, "half", channelLabel$[ch]
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Coeff"
    Text top: "no", "Encoding coefficients (ACN/SN3D)"

    # ----------------------------------------------------------
    # Summary panel
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 3.62, 4.42
    Select inner viewport: 0.45, 7.65, 3.68, 4.36
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.82, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"

    # Build coefficient list
    coeffList$ = ""
    for ch from 1 to numChannels
        if ch > 1
            coeffList$ = coeffList$ + "  "
        endif
        coeffList$ = coeffList$ + channelLabel$[ch] + "=" + fixed$(coeff[ch], 3)
    endfor

    Text: 0.02, "left", 0.55, "half",
        ... "Order: " + orderName$ + "  (" + string$(numChannels) + " ch)"
        ... + "  |  Az: " + fixed$(azimuth, 1) + "°"
        ... + "  |  El: " + fixed$(elevation, 1) + "°"
        ... + "  |  Dist: " + fixed$(distance, 2) + "m"
        ... + "  |  Gain: " + fixed$(distanceGain_dB, 1) + " dB"
    Text: 0.02, "left", 0.22, "half",
        ... "Coefficients:  " + coeffList$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================
# FINAL OUTPUT
# ============================================================

appendInfoLine: "============================================"
appendInfoLine: "ENCODING COMPLETE"
appendInfoLine: "============================================"
appendInfoLine: "Source: ", originalName$
appendInfoLine: "Position: az=", fixed$(azimuth, 1), "°, el=", fixed$(elevation, 1), "°, dist=", fixed$(distance, 2), "m"
appendInfoLine: "Order: ", orderName$, " (", numChannels, " channels)"
appendInfoLine: ""

if output_format = 1
    appendInfoLine: "Output: ", numChannels, " individual channel sounds"
    appendInfoLine: "Channels created:"
    for ch from 1 to numChannels
        selectObject: ambiChannel[ch]
        appendInfoLine: "  ", selected$("Sound")
    endfor
    # Select all channels
    selectObject: ambiChannel[1]
    for ch from 2 to numChannels
        plusObject: ambiChannel[ch]
    endfor
elsif output_format = 2
    appendInfoLine: "Output: Combined multichannel B-format"
    selectObject: combinedResult
    appendInfoLine: "  ", selected$("Sound")
else
    appendInfoLine: "Output: Both individual and combined"
    appendInfoLine: "Individual channels:"
    for ch from 1 to numChannels
        selectObject: ambiChannel[ch]
        appendInfoLine: "  ", selected$("Sound")
    endfor
    selectObject: combinedResult
    appendInfoLine: "Combined: ", selected$("Sound")
    # Select combined as primary result
    selectObject: combinedResult
endif

appendInfoLine: ""
appendInfoLine: "Use with Ambisonic Decoder for speaker playback."

# ============================================================
# PLAY RESULT
# ============================================================

if play_result
    if output_format >= 2
        selectObject: combinedResult
        Play
    else
        # Play W channel (omnidirectional)
        selectObject: ambiChannel[1]
        Play
    endif
endif

# Final selection
if output_format >= 2
    selectObject: combinedResult
else
    selectObject: ambiChannel[1]
    for ch from 2 to numChannels
        plusObject: ambiChannel[ch]
    endfor
endif