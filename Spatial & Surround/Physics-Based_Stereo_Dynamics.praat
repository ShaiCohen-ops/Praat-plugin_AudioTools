# ============================================================
# Praat AudioTools - Physics-Based_Stereo_Dynamics.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Bouncing-ball physics simulation drives amplitude and stereo
#   panning of the input sound. Height/velocity map to amplitude,
#   horizontal motion maps to pan position.
#
# Changelog v0.3:
#   - Fix: 17 instances of `elif` replaced with `elsif`. `elif`
#     is not standard Praat keyword — older builds reject it
#     outright, and on builds where it does parse the behaviour
#     is undocumented. Now uses standard `elsif` everywhere.
#   - Fix: Custom mode no longer relies on case-insensitive
#     accidental-match between form variable names and working
#     variable names. All seven physics parameters are
#     explicitly mapped from form values into local working
#     variables in the Custom branch. Renaming form variables
#     can no longer silently break Custom.
#   - Fix: oscillating pan ("Spring", "Pendulum") was triggered
#     by a string-compare on presetName$, so Custom mode
#     could not request it regardless of parameter values.
#     Replaced with an explicit `pan_motion` form parameter
#     (Linear / Oscillating). Presets set this parameter, no
#     more presetName$ comparisons in the math.
#   - Clarification: "distance attenuation" was ambiguous —
#     the math made the ball quieter as it moved off-centre,
#     which is the opposite of the bouncing-ball-on-stage
#     metaphor (sound louder when it gets closer to the
#     listener at centre). The parameter is now called
#     "Centre attenuation" with a `attenuation_direction`
#     toggle: "Louder at edges" (audience POV, ball passes
#     speakers) vs "Louder at centre" (listener-at-stage-front
#     POV, the v0.2 default). Default kept at "Louder at
#     centre" so v0.2 presets sound the same.
#   - Visualization rewritten to suite 8x8 standard
#     (matching 22.2 Stem Renderer, 8-ch I Ching, 8-ch
#     Movements, 4-ch Canon, 8-ch Spectral Shift, 8-ch
#     Speed Deviations, 8-ch Speech-Driven Spatialization,
#     Stereo Distribution).
#     Panels:
#       A: 2D motion path — pan-vs-height, time-graded
#          colour, dot size = current amplitude. Ground
#          line, speaker triangles, listener at centre.
#          This is what the script is actually computing.
#       B: Height vs time (the physics).
#       C: Pan vs time (the spatialization).
#       D: Output waveform (L blue, R orange).
#       E: Summary stats bar (grey, framed).
# Changelog v0.2:
#   - Memory leak fix on stereo conversion
#   - Vector arrays
#   - Wet/dry mix
#   - Visualization toggle
# ============================================================

# Get selected sound
if numberOfSelected("Sound") <> 1
    exitScript: "Please select a Sound object first."
endif

original = selected("Sound")
originalName$ = selected$("Sound")
duration = Get total duration
sr = Get sampling frequency
nChannels = Get number of channels

# === FORM ===
form Physics-Based Stereo Dynamics v0.3
    comment === PRESET ===
    optionmenu Preset: 2
        option Custom (use parameters below)
        option Bouncy Rubber Ball (L to R)
        option Steel Ball Drop (Center)
        option Ping Pong Frenzy (Wide Stereo)
        option Basketball Dribble (Right Side)
        option Super Ball Chaos (Fast Pan)
        option Dropping Stone (Center)
        option Feather Falling (L to R)
        option Moon Gravity (Slow Pan)
        option Tennis Ball (Cross Court)
        option Water Skipping Stone (Fade away)
        option Earthquake Tremor (Stereo Shake)
        option Heartbeat Pulse (Center)
        option Spring Oscillation (Pan Oscillation)
        option Pendulum Swing (Wide Arc)
        option Rolling Downhill (L to R)
    
    comment === CUSTOM PHYSICS (Custom preset only) ===
    real Initial_height 1.2
    real Initial_velocity 6.0
    real Gravity 9.8
    real Bounce_coefficient 0.75
    natural Number_of_bounces 8
    
    comment === CUSTOM STEREO (Custom preset only) ===
    real Pan_start -0.9
    real Pan_end 0.9
    optionmenu Pan_motion: 1
        option Linear (start -> end)
        option Oscillating (sine wave)
    real Center_attenuation 0.3
    optionmenu Attenuation_direction: 1
        option Louder at centre (v0.2 default — listener at centre)
        option Louder at edges (audience POV — ball passes speakers)
    
    comment === CUSTOM ENVELOPE (Custom preset only) ===
    optionmenu Mapping: 3
        option Height to amplitude (potential energy)
        option Velocity to amplitude (kinetic energy)
        option Combined (height and velocity)
    real Amplitude_scale 1.0
    
    comment === OUTPUT ===
    real Mix_percent 100
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Clamp wet/dry
if mix_percent < 0
    mixPercent = 0
elsif mix_percent > 100
    mixPercent = 100
else
    mixPercent = mix_percent
endif
wet_level = mixPercent / 100
dry_level = 1 - wet_level

# === Apply preset OR copy custom values explicitly ===
if preset = 1
    # Custom: explicit mapping from form to working vars
    initialHeight    = initial_height
    initialVelocity  = initial_velocity
    gravityVal       = gravity
    bounceCoef       = bounce_coefficient
    numBounces       = number_of_bounces
    panStart         = pan_start
    panEnd           = pan_end
    panMotion        = pan_motion
    centerAtten      = center_attenuation
    attenDir         = attenuation_direction
    mappingMode      = mapping
    ampScale         = amplitude_scale
    presetName$ = "Custom"
elsif preset = 2
    initialHeight = 1.2
    initialVelocity = 6.0
    gravityVal = 9.8
    bounceCoef = 0.75
    numBounces = 8
    panStart = -0.9
    panEnd = 0.9
    panMotion = 1
    centerAtten = 0.3
    attenDir = 1
    mappingMode = 3
    ampScale = 1.0
    presetName$ = "Bouncy_Rubber_Ball"
elsif preset = 3
    initialHeight = 2.0
    initialVelocity = 3.0
    gravityVal = 9.8
    bounceCoef = 0.92
    numBounces = 12
    panStart = 0.0
    panEnd = 0.0
    panMotion = 1
    centerAtten = 0.0
    attenDir = 1
    mappingMode = 1
    ampScale = 1.2
    presetName$ = "Steel_Ball_Drop"
elsif preset = 4
    initialHeight = 0.8
    initialVelocity = 10.0
    gravityVal = 9.8
    bounceCoef = 0.85
    numBounces = 15
    panStart = -1.0
    panEnd = 1.0
    panMotion = 1
    centerAtten = 0.5
    attenDir = 1
    mappingMode = 2
    ampScale = 0.9
    presetName$ = "Ping_Pong_Frenzy"
elsif preset = 5
    initialHeight = 1.5
    initialVelocity = 4.0
    gravityVal = 9.8
    bounceCoef = 0.70
    numBounces = 6
    panStart = 0.5
    panEnd = 0.7
    panMotion = 1
    centerAtten = 0.2
    attenDir = 1
    mappingMode = 3
    ampScale = 1.1
    presetName$ = "Basketball_Dribble"
elsif preset = 6
    initialHeight = 1.0
    initialVelocity = 8.0
    gravityVal = 9.8
    bounceCoef = 0.95
    numBounces = 20
    panStart = -0.8
    panEnd = 0.2
    panMotion = 1
    centerAtten = 0.4
    attenDir = 1
    mappingMode = 2
    ampScale = 0.85
    presetName$ = "Super_Ball_Chaos"
elsif preset = 7
    initialHeight = 3.0
    initialVelocity = 0.0
    gravityVal = 12.0
    bounceCoef = 0.0
    numBounces = 0
    panStart = 0.0
    panEnd = 0.0
    panMotion = 1
    centerAtten = 0.0
    attenDir = 1
    mappingMode = 2
    ampScale = 1.5
    presetName$ = "Dropping_Stone"
elsif preset = 8
    initialHeight = 2.0
    initialVelocity = 1.0
    gravityVal = 2.0
    bounceCoef = 0.3
    numBounces = 3
    panStart = -0.5
    panEnd = 0.5
    panMotion = 1
    centerAtten = 0.2
    attenDir = 1
    mappingMode = 1
    ampScale = 0.8
    presetName$ = "Feather_Falling"
elsif preset = 9
    initialHeight = 1.5
    initialVelocity = 4.0
    gravityVal = 1.62
    bounceCoef = 0.65
    numBounces = 8
    panStart = -0.8
    panEnd = 0.8
    panMotion = 1
    centerAtten = 0.2
    attenDir = 1
    mappingMode = 3
    ampScale = 1.0
    presetName$ = "Moon_Gravity"
elsif preset = 10
    initialHeight = 1.3
    initialVelocity = 5.5
    gravityVal = 9.8
    bounceCoef = 0.73
    numBounces = 7
    panStart = -1.0
    panEnd = 1.0
    panMotion = 1
    centerAtten = 0.6
    attenDir = 1
    mappingMode = 3
    ampScale = 1.0
    presetName$ = "Tennis_Ball"
elsif preset = 11
    initialHeight = 0.5
    initialVelocity = 12.0
    gravityVal = 9.8
    bounceCoef = 0.60
    numBounces = 10
    panStart = -0.2
    panEnd = 1.5
    panMotion = 1
    centerAtten = 0.8
    attenDir = 1
    mappingMode = 2
    ampScale = 0.75
    presetName$ = "Water_Skipping_Stone"
elsif preset = 12
    initialHeight = 0.3
    initialVelocity = 3.0
    gravityVal = 15.0
    bounceCoef = 0.88
    numBounces = 25
    panStart = -0.3
    panEnd = 0.3
    panMotion = 1
    centerAtten = 0.1
    attenDir = 1
    mappingMode = 2
    ampScale = 1.3
    presetName$ = "Earthquake_Tremor"
elsif preset = 13
    initialHeight = 0.8
    initialVelocity = 6.0
    gravityVal = 18.0
    bounceCoef = 0.65
    numBounces = 12
    panStart = 0.0
    panEnd = 0.0
    panMotion = 1
    centerAtten = 0.0
    attenDir = 1
    mappingMode = 2
    ampScale = 1.4
    presetName$ = "Heartbeat_Pulse"
elsif preset = 14
    initialHeight = 1.0
    initialVelocity = 7.0
    gravityVal = 8.0
    bounceCoef = 0.82
    numBounces = 15
    panStart = -1.0
    panEnd = 1.0
    panMotion = 2
    centerAtten = 0.4
    attenDir = 1
    mappingMode = 3
    ampScale = 0.95
    presetName$ = "Spring_Oscillation"
elsif preset = 15
    initialHeight = 1.8
    initialVelocity = 2.5
    gravityVal = 5.0
    bounceCoef = 0.90
    numBounces = 10
    panStart = -1.0
    panEnd = 1.0
    panMotion = 2
    centerAtten = 0.7
    attenDir = 1
    mappingMode = 1
    ampScale = 1.1
    presetName$ = "Pendulum_Swing"
else
    # Rolling Downhill (preset 16)
    initialHeight = 2.5
    initialVelocity = 1.0
    gravityVal = 15.0
    bounceCoef = 0.45
    numBounces = 5
    panStart = -1.0
    panEnd = 1.0
    panMotion = 1
    centerAtten = 0.5
    attenDir = 1
    mappingMode = 2
    ampScale = 1.3
    presetName$ = "Rolling_Downhill"
endif

# Resolve labels for output
if panMotion = 1
    panMotionName$ = "Linear"
else
    panMotionName$ = "Oscillating"
endif
if attenDir = 1
    attenDirName$ = "LouderAtCenter"
else
    attenDirName$ = "LouderAtEdges"
endif
if mappingMode = 1
    mappingName$ = "Height"
elsif mappingMode = 2
    mappingName$ = "Velocity"
else
    mappingName$ = "Combined"
endif

# === Info ===
writeInfoLine: "=== Physics-Based Stereo Dynamics v0.3 ==="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Pan: ", fixed$(panStart, 2), " -> ", fixed$(panEnd, 2),
    ... " (", panMotionName$, ")"
appendInfoLine: "Attenuation: ", fixed$(centerAtten, 2), " (", attenDirName$, ")"
appendInfoLine: "Mapping: ", mappingName$, "  |  Wet/Dry: ", fixed$(mixPercent, 0), "%"
appendInfoLine: ""

# ============================================================
# PHYSICS SIMULATION
# ============================================================

numPoints = round(duration * 100)
if numPoints < 200
    numPoints = 200
elsif numPoints > 2000
    numPoints = 2000
endif

timeStep = duration / (numPoints - 1)

appendInfoLine: "Simulation: ", numPoints, " points, dt=", fixed$(timeStep * 1000, 2), "ms"

time# = zero#(numPoints)
height# = zero#(numPoints)
velocity# = zero#(numPoints)
pan# = zero#(numPoints)

currentHeight = initialHeight
currentVelocity = initialVelocity
currentTime = 0
bouncesDone = 0
groundLevel = 0

for i from 1 to numPoints
    time#[i] = currentTime
    height#[i] = currentHeight
    velocity#[i] = abs(currentVelocity)
    
    progress = (i - 1) / (numPoints - 1)
    if panMotion = 2
        # Oscillating pan, 4 cycles across the recording
        pan#[i] = panStart + (panEnd - panStart) * sin(progress * pi * 4)
    else
        pan#[i] = panStart + (panEnd - panStart) * progress
    endif
    
    # Euler integration
    currentVelocity = currentVelocity - gravityVal * timeStep
    currentHeight = currentHeight + currentVelocity * timeStep
    
    if currentHeight <= groundLevel and bouncesDone < numBounces
        currentHeight = groundLevel
        currentVelocity = -currentVelocity * bounceCoef
        bouncesDone = bouncesDone + 1
    endif
    
    if currentHeight < groundLevel
        currentHeight = groundLevel
        currentVelocity = 0
    endif
    
    currentTime = currentTime + timeStep
endfor

appendInfoLine: "Physics: ", bouncesDone, " bounces simulated"

# Track height range for visualization
maxHeightSeen = height#[1]
for i from 2 to numPoints
    if height#[i] > maxHeightSeen
        maxHeightSeen = height#[i]
    endif
endfor

# ============================================================
# MAP PHYSICS TO AMPLITUDE & STEREO  -> IntensityTier
# ============================================================

tierL = Create IntensityTier: "envelope_left", 0, duration
tierR = Create IntensityTier: "envelope_right", 0, duration

maxVelocity = initialVelocity + gravityVal * duration
if maxVelocity < 0.001
    maxVelocity = 0.001
endif

normHeight = initialHeight
if normHeight < 0.001
    normHeight = 0.001
endif

# Track instant amplitude per simulation point (for viz Panel A dot sizing)
ampTrace# = zero# (numPoints)

for i from 1 to numPoints
    t = time#[i]
    h = height#[i]
    v = velocity#[i]
    p = pan#[i]
    
    # Base amp from chosen energy mapping
    if mappingMode = 1
        amp = h / normHeight
    elsif mappingMode = 2
        amp = v / maxVelocity
    else
        amp = (h / normHeight + v / maxVelocity) / 2
    endif
    
    # Centre attenuation (direction now explicit)
    dist = abs(p)
    if attenDir = 1
        # Louder at centre — quieter as we move off-centre
        distFactor = 1.0 / (1.0 + centerAtten * dist)
    else
        # Louder at edges — quieter near centre
        distFactor = 1.0 / (1.0 + centerAtten * (1 - dist))
    endif
    amp = amp * ampScale * distFactor
    
    if amp < 0.001
        amp = 0.001
    endif
    ampTrace#[i] = amp
    
    # Constant-power pan
    pClamped = p
    if pClamped < -1
        pClamped = -1
    endif
    if pClamped > 1
        pClamped = 1
    endif
    panNorm = (pClamped + 1) / 2
    
    ampL = amp * sqrt(1 - panNorm)
    ampR = amp * sqrt(panNorm)
    
    if ampL < 0.00001
        ampL = 0.00001
    endif
    if ampR < 0.00001
        ampR = 0.00001
    endif
    
    dbL = 20 * log10(ampL)
    dbR = 20 * log10(ampR)
    
    selectObject: tierL
    Add point: t, dbL
    selectObject: tierR
    Add point: t, dbR
endfor

appendInfoLine: "Envelope tiers created"

# ============================================================
# APPLY TO SOUND
# ============================================================
selectObject: original
workingCopy = Copy: "temp_working"

selectObject: workingCopy
nCh = Get number of channels
if nCh = 1
    stereoTemp = Convert to stereo
    removeObject: workingCopy
    workingCopy = stereoTemp
endif

selectObject: workingCopy
ch1 = Extract one channel: 1
selectObject: workingCopy
ch2 = Extract one channel: 2

selectObject: ch1
plusObject: tierL
Multiply: "yes"
ch1Mod = selected("Sound")

selectObject: ch2
plusObject: tierR
Multiply: "yes"
ch2Mod = selected("Sound")

selectObject: ch1Mod
plusObject: ch2Mod
Combine to stereo
wetSound = selected("Sound")

# Wet/dry mix
if dry_level > 0
    selectObject: original
    dryCopy = Copy: "temp_dry"
    selectObject: dryCopy
    nChDry = Get number of channels
    if nChDry = 1
        dryStTemp = Convert to stereo
        removeObject: dryCopy
        dryCopy = dryStTemp
    endif
    
    wetStr$ = string$(wet_level)
    dryStr$ = string$(dry_level)
    dryIdStr$ = string$(dryCopy)
    
    selectObject: wetSound
    Formula: "self * " + wetStr$ + " + object[" + dryIdStr$ + ", row, col] * " + dryStr$
    
    removeObject: dryCopy
endif

selectObject: wetSound
Rename: originalName$ + "_" + presetName$
result = selected("Sound")
Scale peak: 0.99

selectObject: result
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"

# === Cleanup intermediates ===
selectObject: workingCopy
plusObject: ch1
plusObject: ch2
plusObject: ch1Mod
plusObject: ch2Mod
plusObject: tierL
plusObject: tierR
Remove

appendInfoLine: "Processing complete"

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_visualization
    
    Erase all
    
    # Find max amplitude in trace for marker scaling
    maxAmpTrace = ampTrace#[1]
    for i from 2 to numPoints
        if ampTrace#[i] > maxAmpTrace
            maxAmpTrace = ampTrace#[i]
        endif
    endfor
    if maxAmpTrace < 0.001
        maxAmpTrace = 0.001
    endif
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##PHYSICS-BASED STEREO DYNAMICS##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... originalName$
        ... + "  |  Preset: " + presetName$
        ... + "  |  " + fixed$(duration, 2) + " s"
        ... + "  |  Bounces: " + string$(bouncesDone)
        ... + "  |  Mapping: " + mappingName$
        ... + "  |  Wet: " + fixed$(mixPercent, 0) + "%"
    
    # ----------------------------------------------------------
    # PANEL A: 2D MOTION PATH  (left, headline)
    # X-axis = pan position [-1, +1]
    # Y-axis = height [0, maxHeight]
    # The actual computed trajectory of the ball in stereo×height
    # space. Time-graded colour (cool start -> warm end).
    # Dot size = current amplitude. Speakers at the extremes,
    # listener at centre.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.40, 4.00, 0.95, 4.45
    
    yMax = maxHeightSeen * 1.15
    if yMax < 0.1
        yMax = 0.1
    endif
    
    Axes: -1.25, 1.25, -0.10 * yMax, yMax
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.25, 1.25, -0.10 * yMax, yMax
    
    # Ground line
    Colour: "{0.65, 0.50, 0.30}"
    Line width: 2
    Draw line: -1.25, 0, 1.25, 0
    Line width: 1
    
    # Vertical guides at L = -1, C = 0, R = +1
    Colour: "{0.85, 0.85, 0.85}"
    Dotted line
    Draw line: -1.0, 0, -1.0, yMax
    Draw line:  0.0, 0,  0.0, yMax
    Draw line:  1.0, 0,  1.0, yMax
    Solid line
    
    # Speaker icons (triangles via two diagonal lines from base)
    Colour: "{0.40, 0.40, 0.50}"
    Line width: 1.5
    spkY = -0.05 * yMax
    spkH = 0.08 * yMax
    spkW = 0.08
    # Left speaker
    Draw line: -1.0 - spkW, spkY, -1.0 + spkW, spkY
    Draw line: -1.0 - spkW, spkY, -1.0, spkY + spkH
    Draw line: -1.0 + spkW, spkY, -1.0, spkY + spkH
    # Right speaker
    Draw line: 1.0 - spkW, spkY, 1.0 + spkW, spkY
    Draw line: 1.0 - spkW, spkY, 1.0, spkY + spkH
    Draw line: 1.0 + spkW, spkY, 1.0, spkY + spkH
    Line width: 1
    Font size: 5
    Colour: "{0.30, 0.30, 0.40}"
    Text: -1.0, "centre", -0.08 * yMax, "half", "L"
    Text:  1.0, "centre", -0.08 * yMax, "half", "R"
    
    # Listener at centre on the ground
    Paint circle (mm): "{0.22, 0.62, 0.30}", 0, 0, 2.5
    Font size: 5
    Colour: "{0.15, 0.45, 0.18}"
    Text: 0, "centre", -0.06 * yMax, "half", "listener"
    
    # --- Trajectory: cool blue (start) -> warm red (end) ---
    Line width: 1.5
    for i from 2 to numPoints
        prog = (i - 1) / (numPoints - 1)
        tr = 0.20 + 0.65 * prog
        tg = 0.40 - 0.20 * prog
        tb = 0.85 - 0.65 * prog
        if tg < 0
            tg = 0
        endif
        if tb < 0
            tb = 0
        endif
        Colour: "{" + fixed$(tr, 2) + ", " + fixed$(tg, 2) + ", " + fixed$(tb, 2) + "}"
        Draw line: pan#[i - 1], height#[i - 1], pan#[i], height#[i]
    endfor
    Line width: 1
    
    # Dots at evenly-spaced points, sized by current amplitude.
    # Cap at ~20 markers to avoid clutter.
    if numPoints > 20
        markerStep = floor(numPoints / 20)
    else
        markerStep = 1
    endif
    if markerStep < 1
        markerStep = 1
    endif
    
    i = 1
    while i <= numPoints
        # Marker size in mm: 1.2 to 4.5, scaled by relative amplitude
        relAmp = ampTrace#[i] / maxAmpTrace
        if relAmp < 0
            relAmp = 0
        endif
        if relAmp > 1
            relAmp = 1
        endif
        diam = 1.2 + relAmp * 3.3
        
        # Same time-graded colour as the line
        prog = (i - 1) / max(1, numPoints - 1)
        tr = 0.20 + 0.65 * prog
        tg = 0.40 - 0.20 * prog
        tb = 0.85 - 0.65 * prog
        if tg < 0
            tg = 0
        endif
        if tb < 0
            tb = 0
        endif
        rgb$ = "{" + fixed$(tr, 2) + ", " + fixed$(tg, 2) + ", " + fixed$(tb, 2) + "}"
        Paint circle (mm): rgb$, pan#[i], height#[i], diam
        
        i = i + markerStep
    endwhile
    
    # Start and end markers (highlighted)
    Paint circle (mm): "{0.20, 0.40, 0.85}", pan#[1], height#[1], 2.0
    Paint circle (mm): "{0.85, 0.20, 0.20}", pan#[numPoints], height#[numPoints], 2.0
    Font size: 5
    Colour: "{0.20, 0.40, 0.85}"
    Text: pan#[1], "left", height#[1] + 0.04 * yMax, "half", "start"
    Colour: "{0.85, 0.20, 0.20}"
    Text: pan#[numPoints], "right", height#[numPoints] + 0.04 * yMax, "half", "end"
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Height (m)"
    Text bottom: "yes", "Pan position (-1 = L, 0 = C, +1 = R)"
    
    # ----------------------------------------------------------
    # PANEL B: HEIGHT vs TIME  (right column, upper)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 3.00
    Select inner viewport: 4.52, 7.75, 0.85, 2.92
    
    Axes: 0, duration, -0.05 * yMax, yMax
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, duration, -0.05 * yMax, yMax
    
    # Ground
    Colour: "{0.65, 0.50, 0.30}"
    Line width: 2
    Draw line: 0, 0, duration, 0
    Line width: 1
    
    # Initial height reference
    Colour: "{0.85, 0.85, 0.85}"
    Dotted line
    Draw line: 0, initialHeight, duration, initialHeight
    Solid line
    Font size: 5
    Colour: "{0.55, 0.55, 0.55}"
    Text: duration * 0.99, "right", initialHeight, "bottom", "h0 = " + fixed$(initialHeight, 2) + " m"
    
    # Height curve
    Colour: "{0.85, 0.40, 0.20}"
    Line width: 1.5
    for i from 2 to numPoints
        Draw line: time#[i - 1], height#[i - 1], time#[i], height#[i]
    endfor
    Line width: 1
    
    # Mark each bounce point (height crosses 0 from above)
    Colour: "{0.85, 0.20, 0.20}"
    bounceCount = 0
    for i from 2 to numPoints
        if height#[i - 1] > 0.001 and height#[i] <= 0.001 and bounceCount < numBounces
            Paint circle (mm): "{0.85, 0.20, 0.20}", time#[i], 0, 1.5
            bounceCount = bounceCount + 1
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Height (m)"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL C: PAN vs TIME  (right column, lower)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 3.05, 4.60
    Select inner viewport: 4.52, 7.75, 3.12, 4.52
    
    # Show clamped range (-1, +1) plus a margin to indicate excursion
    panLo = -1.2
    panHi = 1.2
    for i from 1 to numPoints
        if pan#[i] < panLo
            panLo = pan#[i] - 0.05
        endif
        if pan#[i] > panHi
            panHi = pan#[i] + 0.05
        endif
    endfor
    
    Axes: 0, duration, panLo, panHi
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, duration, panLo, panHi
    
    # Audible-clamping zone shading: anything outside [-1, +1] is clamped
    # at the audio output. Show those zones in light pink so the user
    # sees that the parameter exceeds what's audibly representable.
    if panLo < -1.0
        Paint rectangle: "{0.99, 0.93, 0.93}", 0, duration, panLo, -1.0
    endif
    if panHi > 1.0
        Paint rectangle: "{0.99, 0.93, 0.93}", 0, duration, 1.0, panHi
    endif
    
    # L = -1, C = 0, R = +1 reference lines
    Colour: "{0.55, 0.55, 0.55}"
    Dotted line
    Draw line: 0, -1.0, duration, -1.0
    Draw line: 0,  0.0, duration,  0.0
    Draw line: 0,  1.0, duration,  1.0
    Solid line
    Font size: 5
    Colour: "{0.45, 0.45, 0.45}"
    Text: duration * 0.99, "right", -1.0, "bottom", "L"
    Text: duration * 0.99, "right",  0.0, "bottom", "C"
    Text: duration * 0.99, "right",  1.0, "bottom", "R"
    
    # Pan curve
    Colour: "{0.30, 0.50, 0.78}"
    Line width: 1.5
    for i from 2 to numPoints
        Draw line: time#[i - 1], pan#[i - 1], time#[i], pan#[i]
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Pan"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "2D motion path  (blue = start, red = end, dot = amp)"
    Text: 6.10, "centre", 7.30, "half", "Height vs time (upper) & pan vs time (lower)"
    
    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.75
    Select inner viewport: 0.55, 7.72, 4.75, 5.68
    
    selectObject: result
    outDurViz = Get total duration
    outPeak = Get absolute extremum: 0, 0, "None"
    if outPeak < 0.001
        outPeak = 0.001
    endif
    ampViz = outPeak * 1.15
    
    Axes: 0, outDurViz, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, outDurViz, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, outDurViz, 0
    
    selectObject: result
    Extract one channel: 1
    vizCh1 = selected("Sound")
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    removeObject: vizCh1
    
    selectObject: result
    Extract one channel: 2
    vizCh2 = selected("Sound")
    Colour: "{0.82, 0.45, 0.25}"
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    removeObject: vizCh2
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Output  (blue = L,  orange = R)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.82, 6.58
    Select inner viewport: 0.55, 7.72, 5.88, 6.52
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + originalName$
        ... + "  |  " + fixed$(duration, 2) + " s"
        ... + "  |  Mapping: " + mappingName$
        ... + "  |  Pan motion: " + panMotionName$
        ... + "  |  Atten: " + attenDirName$
        ... + "  |  Wet: " + fixed$(mixPercent, 0) + "%"
    
    Text: 0.02, "left", 0.28, "half",
        ... "h0 = " + fixed$(initialHeight, 2) + " m"
        ... + "   v0 = " + fixed$(initialVelocity, 2) + " m/s"
        ... + "   g = " + fixed$(gravityVal, 2) + " m/s2"
        ... + "   bounce = " + fixed$(bounceCoef, 2)
        ... + "   bounces done: " + string$(bouncesDone) + " / " + string$(numBounces)
        ... + "   pan: " + fixed$(panStart, 2) + " -> " + fixed$(panEnd, 2)
        ... + "   centerAtten = " + fixed$(centerAtten, 2)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
    
endif

# === Done ===
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", originalName$ + "_" + presetName$
appendInfoLine: "Duration: ", fixed$(finalDur, 2), " s, peak=", fixed$(finalPeak, 3)

if play_result
    selectObject: result
    Play
endif

selectObject: result
