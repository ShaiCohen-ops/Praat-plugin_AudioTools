# ============================================================
# Praat AudioTools - Higher-Order Ambisonic Decoder.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Optimized
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Higher-Order Ambisonic (HOA) Decoder
#   Decodes B-format ambisonic channels to speaker feeds
#   Supports 1st, 2nd, and 3rd order ambisonics
#
# Usage:
#   Select ambisonic channel sounds (W, Y, Z, X, ...) in correct order
#   then run this script.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.2:
#   - Efficient channel summing using Formula (not Combine to stereo)
#   - Modern selectObject: syntax throughout
#   - Added speaker layout visualization
#   - Added play_result toggle
#   - Proper array storage for object IDs
#   - Robust formula string building
#   - Cleaner coefficient calculation
# ============================================================

# ============================================================
# FORM
# ============================================================

form Ambisonic Decoder
    comment Select ambisonic channel sounds (W, Y, Z, X, etc.)
    comment in correct ACN order before running.
    comment ─────────────────────────────────────────
    optionmenu Ambisonic_order: 1
        option 1st order (4 channels: W,Y,Z,X)
        option 2nd order (9 channels: W,Y,Z,X,V,T,R,S,U)
        option 3rd order (16 channels: W,Y,Z,X,V,T,R,S,U,Q,O,M,K,L,N,P)
    comment ─────────────────────────────────────────
    optionmenu Speaker_preset: 1
        option Stereo (2 speakers)
        option Triangle (3 speakers)
        option Quad (4 speakers)
        option Pentagon (5 speakers)
        option Hexagon (6 speakers)
        option Surround 5.1 (6 speakers)
        option Surround 7.1 (8 speakers)
        option Octagon (8 speakers)
    comment ─────────────────────────────────────────
    optionmenu Decode_method: 1
        option Basic (simple projection)
        option Max-rE (energy optimized)
        option In-phase (controlled)
    comment ─────────────────────────────────────────
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

clearinfo

# ============================================================
# VALIDATION
# ============================================================

# Determine expected channels based on order
if ambisonic_order = 1
    expectedChannels = 4
    orderName$ = "1st"
elsif ambisonic_order = 2
    expectedChannels = 9
    orderName$ = "2nd"
else
    expectedChannels = 16
    orderName$ = "3rd"
endif

# Check selection
numSelected = numberOfSelected("Sound")
if numSelected <> expectedChannels
    exitScript: "Please select exactly " + string$(expectedChannels) + " Sound objects for " + orderName$ + " order ambisonics." + newline$ + "Currently selected: " + string$(numSelected)
endif

# Store selected ambisonic channels
for i from 1 to expectedChannels
    ambiChannel[i] = selected("Sound", i)
endfor

# Get channel names and verify properties
for i from 1 to expectedChannels
    selectObject: ambiChannel[i]
    channelName$[i] = selected$("Sound")
endfor

# Get audio properties from first channel
selectObject: ambiChannel[1]
duration = Get total duration
sr = Get sampling frequency
numSamples = Get number of samples

# ============================================================
# SPEAKER CONFIGURATION
# ============================================================

# Speaker preset names for output
if speaker_preset = 1
    presetName$ = "stereo"
    numSpeakers = 2
elsif speaker_preset = 2
    presetName$ = "triangle"
    numSpeakers = 3
elsif speaker_preset = 3
    presetName$ = "quad"
    numSpeakers = 4
elsif speaker_preset = 4
    presetName$ = "pentagon"
    numSpeakers = 5
elsif speaker_preset = 5
    presetName$ = "hexagon"
    numSpeakers = 6
elsif speaker_preset = 6
    presetName$ = "surround51"
    numSpeakers = 6
elsif speaker_preset = 7
    presetName$ = "surround71"
    numSpeakers = 8
else
    presetName$ = "octagon"
    numSpeakers = 8
endif

# Decode method name
if decode_method = 1
    methodName$ = "basic"
elsif decode_method = 2
    methodName$ = "maxrE"
else
    methodName$ = "inphase"
endif

# Define speaker positions (azimuth in radians, 0 = front, clockwise)
# Using Cartesian coordinates: x = right, y = front

if speaker_preset = 1
    # Stereo: L at 270° (left), R at 90° (right)
    speakerAz[1] = 270 * pi / 180
    speakerAz[2] = 90 * pi / 180
    speakerEl[1] = 0
    speakerEl[2] = 0

elsif speaker_preset = 2
    # Triangle: front and two rear
    speakerAz[1] = 0
    speakerAz[2] = 240 * pi / 180
    speakerAz[3] = 120 * pi / 180
    for i from 1 to 3
        speakerEl[i] = 0
    endfor

elsif speaker_preset = 3
    # Quad: FL, FR, RL, RR
    speakerAz[1] = 315 * pi / 180
    speakerAz[2] = 45 * pi / 180
    speakerAz[3] = 225 * pi / 180
    speakerAz[4] = 135 * pi / 180
    for i from 1 to 4
        speakerEl[i] = 0
    endfor

elsif speaker_preset = 4
    # Pentagon: 5 speakers evenly spaced, front center
    for i from 1 to 5
        speakerAz[i] = (i - 1) * 2 * pi / 5
        speakerEl[i] = 0
    endfor

elsif speaker_preset = 5
    # Hexagon: 6 speakers evenly spaced
    for i from 1 to 6
        speakerAz[i] = (i - 1) * 2 * pi / 6
        speakerEl[i] = 0
    endfor

elsif speaker_preset = 6
    # 5.1 Surround: L, R, C, LFE (center), Ls, Rs
    speakerAz[1] = 330 * pi / 180
    speakerAz[2] = 30 * pi / 180
    speakerAz[3] = 0
    speakerAz[4] = 0
    speakerAz[5] = 250 * pi / 180
    speakerAz[6] = 110 * pi / 180
    for i from 1 to 6
        speakerEl[i] = 0
    endfor

elsif speaker_preset = 7
    # 7.1 Surround: L, R, C, LFE, Ls, Rs, Lb, Rb
    speakerAz[1] = 330 * pi / 180
    speakerAz[2] = 30 * pi / 180
    speakerAz[3] = 0
    speakerAz[4] = 0
    speakerAz[5] = 270 * pi / 180
    speakerAz[6] = 90 * pi / 180
    speakerAz[7] = 225 * pi / 180
    speakerAz[8] = 135 * pi / 180
    for i from 1 to 8
        speakerEl[i] = 0
    endfor

else
    # Octagon: 8 speakers evenly spaced
    for i from 1 to 8
        speakerAz[i] = (i - 1) * 2 * pi / 8
        speakerEl[i] = 0
    endfor
endif

# ============================================================
# INFO OUTPUT
# ============================================================

writeInfoLine: "============================================"
writeInfoLine: "Higher-Order Ambisonic Decoder v0.2"
writeInfoLine: "============================================"
appendInfoLine: "Ambisonic order: ", orderName$, " (", expectedChannels, " channels)"
appendInfoLine: "Speaker layout: ", presetName$, " (", numSpeakers, " speakers)"
appendInfoLine: "Decode method: ", methodName$
appendInfoLine: "--------------------------------------------"
appendInfoLine: "Duration: ", fixed$(duration, 3), " s"
appendInfoLine: "Sample rate: ", sr, " Hz"
appendInfoLine: "--------------------------------------------"
appendInfoLine: "Input channels:"
for i from 1 to expectedChannels
    appendInfoLine: "  ", i, ": ", channelName$[i]
endfor
appendInfoLine: "--------------------------------------------"
appendInfoLine: "Speaker positions:"
for spk from 1 to numSpeakers
    azDeg = speakerAz[spk] * 180 / pi
    elDeg = speakerEl[spk] * 180 / pi
    appendInfoLine: "  Spk ", spk, ": az=", fixed$(azDeg, 1), "°, el=", fixed$(elDeg, 1), "°"
endfor
appendInfoLine: ""

# ============================================================
# CONSTANTS
# ============================================================

sqrt2 = sqrt(2)
sqrt3 = sqrt(3)
sqrt5 = sqrt(5)
sqrt15 = sqrt(15)

# ============================================================
# CALCULATE DECODER MATRIX
# ============================================================

appendInfoLine: "Calculating decoder coefficients..."

for spk from 1 to numSpeakers
    az = speakerAz[spk]
    el = speakerEl[spk]
    
    cos_az = cos(az)
    sin_az = sin(az)
    cos_el = cos(el)
    sin_el = sin(el)
    cos_el_sq = cos_el * cos_el
    sin_el_sq = sin_el * sin_el
    
    # 1st order coefficients (ACN ordering: W, Y, Z, X)
    # W = 1 (omni)
    # Y = sin(az)*cos(el)
    # Z = sin(el)
    # X = cos(az)*cos(el)
    
    coeff[spk, 1] = 1.0
    coeff[spk, 2] = sin_az * cos_el
    coeff[spk, 3] = sin_el
    coeff[spk, 4] = cos_az * cos_el
    
    # 2nd order (V, T, R, S, U)
    if ambisonic_order >= 2
        cos_2az = cos(2 * az)
        sin_2az = sin(2 * az)
        
        coeff[spk, 5] = sqrt3 * sin_2az * cos_el_sq * 0.5
        coeff[spk, 6] = sqrt3 * sin_az * sin_el * cos_el
        coeff[spk, 7] = 0.5 * (3 * sin_el_sq - 1)
        coeff[spk, 8] = sqrt3 * cos_az * sin_el * cos_el
        coeff[spk, 9] = sqrt3 * cos_2az * cos_el_sq * 0.5
    endif
    
    # 3rd order (Q, O, M, K, L, N, P)
    if ambisonic_order >= 3
        cos_3az = cos(3 * az)
        sin_3az = sin(3 * az)
        cos_2az = cos(2 * az)
        sin_2az = sin(2 * az)
        
        coeff[spk, 10] = sqrt5 * sin_3az * cos_el * cos_el_sq * 0.25
        coeff[spk, 11] = sqrt15 * sin_2az * sin_el * cos_el_sq * 0.5
        coeff[spk, 12] = sqrt3 * sin_az * cos_el * (5 * sin_el_sq - 1) * 0.25
        coeff[spk, 13] = 0.5 * sin_el * (5 * sin_el_sq - 3)
        coeff[spk, 14] = sqrt3 * cos_az * cos_el * (5 * sin_el_sq - 1) * 0.25
        coeff[spk, 15] = sqrt15 * cos_2az * sin_el * cos_el_sq * 0.5
        coeff[spk, 16] = sqrt5 * cos_3az * cos_el * cos_el_sq * 0.25
    endif
    
    # Apply decode method weighting
    if decode_method = 2
        # Max-rE: optimize energy vector
        weight1 = 1 / sqrt(numSpeakers)
        weight2 = weight1 * 1.5
        weight3 = weight1 * 1.9
        
        for ch from 1 to 4
            coeff[spk, ch] = coeff[spk, ch] * weight1
        endfor
        if ambisonic_order >= 2
            for ch from 5 to 9
                coeff[spk, ch] = coeff[spk, ch] * weight2
            endfor
        endif
        if ambisonic_order >= 3
            for ch from 10 to 16
                coeff[spk, ch] = coeff[spk, ch] * weight3
            endfor
        endif
        
    elsif decode_method = 3
        # In-phase: controlled directivity
        weight1 = 1 / numSpeakers
        weight2 = weight1 * 0.75
        weight3 = weight1 * 0.5
        
        for ch from 1 to 4
            coeff[spk, ch] = coeff[spk, ch] * weight1
        endfor
        if ambisonic_order >= 2
            for ch from 5 to 9
                coeff[spk, ch] = coeff[spk, ch] * weight2
            endfor
        endif
        if ambisonic_order >= 3
            for ch from 10 to 16
                coeff[spk, ch] = coeff[spk, ch] * weight3
            endfor
        endif
    else
        # Basic: simple normalization
        weight = 1 / sqrt(numSpeakers)
        for ch from 1 to expectedChannels
            coeff[spk, ch] = coeff[spk, ch] * weight
        endfor
    endif
endfor

appendInfoLine: "Decoder matrix calculated"
appendInfoLine: ""

# ============================================================
# DECODE: CREATE SPEAKER FEEDS
# ============================================================

appendInfoLine: "Decoding to speaker feeds..."

for spk from 1 to numSpeakers
    appendInfoLine: "  Processing speaker ", spk, "/", numSpeakers
    
    # Create silent output channel
    Create Sound from formula: "Speaker_" + string$(spk), 1, 0, duration, sr, "0"
    speakerSound[spk] = selected("Sound")
    
    # Sum weighted ambisonic channels using Formula
    # Build formula string that references all input channels
    
    for ch from 1 to expectedChannels
        c = coeff[spk, ch]
        
        if c <> 0
            coeffStr$ = fixed$(c, 8)
            inputIdStr$ = string$(ambiChannel[ch])
            
            selectObject: speakerSound[spk]
            Formula: "self + " + coeffStr$ + " * Object_" + inputIdStr$ + "[col]"
        endif
    endfor
endfor

appendInfoLine: ""

# ============================================================
# NORMALIZE
# ============================================================

if normalize_output
    appendInfoLine: "Normalizing speaker outputs..."
    
    # Find global peak across all speakers
    globalPeak = 0
    for spk from 1 to numSpeakers
        selectObject: speakerSound[spk]
        peak = Get absolute extremum: 0, 0, "None"
        if peak > globalPeak
            globalPeak = peak
        endif
    endfor
    
    # Apply uniform scaling to preserve relative levels
    if globalPeak > 0
        scaleFactor = 0.99 / globalPeak
        scaleStr$ = fixed$(scaleFactor, 8)
        
        for spk from 1 to numSpeakers
            selectObject: speakerSound[spk]
            Formula: "self * " + scaleStr$
        endfor
        
        appendInfoLine: "  Global peak: ", fixed$(globalPeak, 4)
        appendInfoLine: "  Scale factor: ", fixed$(scaleFactor, 4)
    endif
endif

# ============================================================
# COMBINE TO MULTICHANNEL OUTPUT
# ============================================================

appendInfoLine: ""
appendInfoLine: "Combining to multichannel output..."

selectObject: speakerSound[1]
for spk from 2 to numSpeakers
    plusObject: speakerSound[spk]
endfor

result = Combine to stereo
selectObject: result
Rename: "AmbiDecode_" + orderName$ + "_" + presetName$ + "_" + methodName$

# Get final info
selectObject: result
finalChannels = Get number of channels
finalDur = Get total duration

# Clean up individual speaker sounds
for spk from 1 to numSpeakers
    removeObject: speakerSound[spk]
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
    Select outer viewport: 0, 8, 0, 0.45
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##Ambisonic Decoder##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.25, "half",
        ... orderName$ + " order → " + presetName$
        ... + " (" + string$(numSpeakers) + " spk)"
        ... + "  |  " + methodName$

    # ----------------------------------------------------------
    # Speaker layout (left half)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.5, 0.52, 3.82
    Select inner viewport: 0.45, 4.20, 0.62, 3.70

    Axes: -1.6, 1.6, -1.6, 1.6
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.6, 1.6, -1.6, 1.6

    # Reference circle + crosshairs
    Colour: "{0.86, 0.86, 0.86}"
    Line width: 1
    Draw circle: 0, 0, 0.5
    Draw circle: 0, 0, 1.0
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, -1.45, 0, 1.45
    Draw line: -1.45, 0, 1.45, 0

    # Direction labels
    Font size: 6
    Colour: "{0.50, 0.50, 0.50}"
    Text: 0.08, "left", 1.42, "half", "Front"
    Text: 0.08, "left", -1.42, "half", "Rear"
    Text: -1.48, "right", -0.12, "half", "L"
    Text: 1.48, "left", -0.12, "half", "R"

    # Listener
    Paint circle (mm): "{0.35, 0.35, 0.35}", 0, 0, 2.2
    Font size: 5
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0, "centre", -0.16, "half", "Listener"

    # Speakers — coloured squares with radial lines
    for spk from 1 to numSpeakers
        az = speakerAz[spk]
        spkVizX = sin(az)
        spkVizY = cos(az)

        # Colour from hue wheel
        hue = (spk - 1) / numSpeakers
        sR = 0.30 + 0.50 * sin(hue * 2 * pi)
        sG = 0.30 + 0.50 * sin(hue * 2 * pi + 2 * pi / 3)
        sB = 0.30 + 0.50 * sin(hue * 2 * pi + 4 * pi / 3)
        spkCol$ = "{" + fixed$(sR, 2) + ", " + fixed$(sG, 2) + ", " + fixed$(sB, 2) + "}"

        Paint rectangle: spkCol$,
            ... spkVizX - 0.08, spkVizX + 0.08,
            ... spkVizY - 0.08, spkVizY + 0.08

        # Radial line
        Colour: spkCol$
        Dotted line
        Draw line: 0, 0, spkVizX * 0.85, spkVizY * 0.85
        Solid line

        # Number label outside
        lblDist = 1.18
        lblX = lblDist * sin(az)
        lblY = lblDist * cos(az)
        Font size: 6
        Colour: "{0.30, 0.30, 0.30}"
        Text: lblX, "centre", lblY, "half", string$(spk)
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Speaker layout: " + presetName$

    # ----------------------------------------------------------
    # Per-speaker W-coefficient bar chart (right, upper)
    # ----------------------------------------------------------
    Select outer viewport: 4.5, 8, 0.52, 2.22
    Select inner viewport: 4.80, 7.65, 0.62, 2.10

    # Use W (channel 1) coefficient as representative gain per speaker
    maxWcoeff = 0
    for spk from 1 to numSpeakers
        if abs(coeff[spk, 1]) > maxWcoeff
            maxWcoeff = abs(coeff[spk, 1])
        endif
    endfor
    if maxWcoeff < 0.01
        maxWcoeff = 1
    endif
    wTop = maxWcoeff * 1.3

    Axes: 0.3, numSpeakers + 0.7, 0, wTop
    Paint rectangle: "{0.96, 0.96, 0.96}", 0.3, numSpeakers + 0.7, 0, wTop

    for spk from 1 to numSpeakers
        wVal = abs(coeff[spk, 1])
        hue = (spk - 1) / numSpeakers
        sR = 0.30 + 0.50 * sin(hue * 2 * pi)
        sG = 0.30 + 0.50 * sin(hue * 2 * pi + 2 * pi / 3)
        sB = 0.30 + 0.50 * sin(hue * 2 * pi + 4 * pi / 3)
        Paint rectangle: "{" + fixed$(sR, 2) + ", " + fixed$(sG, 2) + ", " + fixed$(sB, 2) + "}",
            ... spk - 0.32, spk + 0.32, 0, wVal
        Font size: 5
        Colour: "{0.30, 0.30, 0.30}"
        Text: spk, "centre", wVal + wTop * 0.04, "half", fixed$(wVal, 3)
        Font size: 6
        Text: spk, "centre", -wTop * 0.07, "half", string$(spk)
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "W gain"
    Text bottom: "yes", "Speaker"
    Text top: "no", "Omni (W) coefficient per speaker"

    # ----------------------------------------------------------
    # Output waveform — mono downmix (right, lower)
    # ----------------------------------------------------------
    Select outer viewport: 4.5, 8, 2.30, 3.82
    Select inner viewport: 4.80, 7.65, 2.38, 3.72

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
    Select inner viewport: 0.45, 7.65, 3.98, 4.76
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.82, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"

    # Speaker angle list
    spkAngles$ = ""
    for spk from 1 to numSpeakers
        if spk > 1
            spkAngles$ = spkAngles$ + "  "
        endif
        azDeg = speakerAz[spk] * 180 / pi
        spkAngles$ = spkAngles$ + string$(spk) + ":" + fixed$(azDeg, 0) + "°"
    endfor

    Text: 0.02, "left", 0.58, "half",
        ... "Order: " + orderName$
        ... + "  |  Method: " + methodName$
        ... + "  |  Layout: " + presetName$
        ... + " (" + string$(numSpeakers) + " spk)"
        ... + "  |  Duration: " + fixed$(finalDur, 2) + " s"
    Text: 0.02, "left", 0.22, "half",
        ... "Speakers:  " + spkAngles$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================
# FINAL OUTPUT
# ============================================================

selectObject: result

appendInfoLine: ""
appendInfoLine: "============================================"
appendInfoLine: "DECODING COMPLETE"
appendInfoLine: "============================================"
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Channels: ", finalChannels
appendInfoLine: "Duration: ", fixed$(finalDur, 3), " s"
appendInfoLine: "Sample rate: ", sr, " Hz"
appendInfoLine: ""
appendInfoLine: "Ambisonic order: ", orderName$
appendInfoLine: "Speaker layout: ", presetName$
appendInfoLine: "Decode method: ", methodName$
appendInfoLine: ""
appendInfoLine: "Decoder coefficients (W weight per speaker):"
for spk from 1 to numSpeakers
    appendInfoLine: "  Spk ", spk, ": W=", fixed$(coeff[spk, 1], 4), ", Y=", fixed$(coeff[spk, 2], 4), ", Z=", fixed$(coeff[spk, 3], 4), ", X=", fixed$(coeff[spk, 4], 4)
endfor

# ============================================================
# PLAY RESULT
# ============================================================

if play_result
    selectObject: result
    Play
endif

selectObject: result