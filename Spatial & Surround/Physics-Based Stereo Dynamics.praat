# ============================================================
# Praat AudioTools - Physics-Based Stereo Dynamics.praat  
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Optimized
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Applies physics-based amplitude and stereo modulation using
#   bouncing ball simulation with gravity, velocity, and spatial
#   positioning. Creates dynamic stereo effects with distance-based
#   loudness attenuation.
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
#   - Fixed memory leak with stereo conversion
#   - Vector arrays instead of indexed variables (performance)
#   - Added visualization/play toggles
#   - Added wet/dry mix control
#   - Simulation resolution scales with duration
#   - Modern Praat syntax throughout
#   - Traditional form with Apply button
# ============================================================

# ============================================================
# Physics-Based Stereo Dynamics
# Features: Bouncing Physics + Distance Loudness + Stereo Panning
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

# TRADITIONAL FORM (Apply keeps window open)
form Physics-Based Stereo Dynamics v0.2
    comment ═══════════════════════════════════════
    comment PRESET SELECTION
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
    comment ═══════════════════════════════════════
    comment CUSTOM PARAMETERS (used if Custom selected)
    comment Vertical Physics:
    real Initial_height 1.2
    real Initial_velocity 6.0
    real Gravity 9.8
    real Bounce_coefficient 0.75
    natural Number_of_bounces 8
    comment Lateral Physics (Stereo):
    real Pan_start -0.9
    real Pan_end 0.9
    real Distance_attenuation 0.3
    comment Envelope Mapping:
    optionmenu Mapping: 3
        option Height to amplitude (potential energy)
        option Velocity to amplitude (kinetic energy)
        option Combined (height and velocity)
    real Amplitude_scale 1.0
    comment ═══════════════════════════════════════
    comment OUTPUT OPTIONS (Mix: 0=dry 100=wet)
    real Mix_percent 100
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Clamp wet/dry
if mix_percent < 0
    mixPercent = 0
elif mix_percent > 100
    mixPercent = 100
else
    mixPercent = mix_percent
endif
wet_level = mixPercent / 100
dry_level = 1 - wet_level

# Set parameters based on preset
if preset = 1
    # Custom - use form values
    panStart = pan_start
    panEnd = pan_end
    distAtten = distance_attenuation
    presetName$ = "Custom"
    
elif preset = 2
    # Bouncy Rubber Ball
    initial_height = 1.2
    initial_velocity = 6.0
    gravity = 9.8
    bounce_coefficient = 0.75
    number_of_bounces = 8
    mapping = 3
    amplitude_scale = 1.0
    panStart = -0.9
    panEnd = 0.9
    distAtten = 0.3
    presetName$ = "Bouncy_Rubber_Ball"
    
elif preset = 3
    # Steel Ball Drop
    initial_height = 2.0
    initial_velocity = 3.0
    gravity = 9.8
    bounce_coefficient = 0.92
    number_of_bounces = 12
    mapping = 1
    amplitude_scale = 1.2
    panStart = 0.0
    panEnd = 0.0
    distAtten = 0.0
    presetName$ = "Steel_Ball_Drop"
    
elif preset = 4
    # Ping Pong Frenzy
    initial_height = 0.8
    initial_velocity = 10.0
    gravity = 9.8
    bounce_coefficient = 0.85
    number_of_bounces = 15
    mapping = 2
    amplitude_scale = 0.9
    panStart = -1.0
    panEnd = 1.0
    distAtten = 0.5
    presetName$ = "Ping_Pong_Frenzy"
    
elif preset = 5
    # Basketball Dribble
    initial_height = 1.5
    initial_velocity = 4.0
    gravity = 9.8
    bounce_coefficient = 0.70
    number_of_bounces = 6
    mapping = 3
    amplitude_scale = 1.1
    panStart = 0.5
    panEnd = 0.7
    distAtten = 0.2
    presetName$ = "Basketball_Dribble"
    
elif preset = 6
    # Super Ball Chaos
    initial_height = 1.0
    initial_velocity = 8.0
    gravity = 9.8
    bounce_coefficient = 0.95
    number_of_bounces = 20
    mapping = 2
    amplitude_scale = 0.85
    panStart = -0.8
    panEnd = 0.2
    distAtten = 0.4
    presetName$ = "Super_Ball_Chaos"
    
elif preset = 7
    # Dropping Stone
    initial_height = 3.0
    initial_velocity = 0.0
    gravity = 12.0
    bounce_coefficient = 0.0
    number_of_bounces = 0
    mapping = 2
    amplitude_scale = 1.5
    panStart = 0.0
    panEnd = 0.0
    distAtten = 0.0
    presetName$ = "Dropping_Stone"
    
elif preset = 8
    # Feather Falling
    initial_height = 2.0
    initial_velocity = 1.0
    gravity = 2.0
    bounce_coefficient = 0.3
    number_of_bounces = 3
    mapping = 1
    amplitude_scale = 0.8
    panStart = -0.5
    panEnd = 0.5
    distAtten = 0.2
    presetName$ = "Feather_Falling"
    
elif preset = 9
    # Moon Gravity
    initial_height = 1.5
    initial_velocity = 4.0
    gravity = 1.62
    bounce_coefficient = 0.65
    number_of_bounces = 8
    mapping = 3
    amplitude_scale = 1.0
    panStart = -0.8
    panEnd = 0.8
    distAtten = 0.2
    presetName$ = "Moon_Gravity"
    
elif preset = 10
    # Tennis Ball
    initial_height = 1.3
    initial_velocity = 5.5
    gravity = 9.8
    bounce_coefficient = 0.73
    number_of_bounces = 7
    mapping = 3
    amplitude_scale = 1.0
    panStart = -1.0
    panEnd = 1.0
    distAtten = 0.6
    presetName$ = "Tennis_Ball"
    
elif preset = 11
    # Water Skipping Stone
    initial_height = 0.5
    initial_velocity = 12.0
    gravity = 9.8
    bounce_coefficient = 0.60
    number_of_bounces = 10
    mapping = 2
    amplitude_scale = 0.75
    panStart = -0.2
    panEnd = 1.5
    distAtten = 0.8
    presetName$ = "Water_Skipping_Stone"
    
elif preset = 12
    # Earthquake Tremor
    initial_height = 0.3
    initial_velocity = 3.0
    gravity = 15.0
    bounce_coefficient = 0.88
    number_of_bounces = 25
    mapping = 2
    amplitude_scale = 1.3
    panStart = -0.3
    panEnd = 0.3
    distAtten = 0.1
    presetName$ = "Earthquake_Tremor"
    
elif preset = 13
    # Heartbeat Pulse
    initial_height = 0.8
    initial_velocity = 6.0
    gravity = 18.0
    bounce_coefficient = 0.65
    number_of_bounces = 12
    mapping = 2
    amplitude_scale = 1.4
    panStart = 0.0
    panEnd = 0.0
    distAtten = 0.0
    presetName$ = "Heartbeat_Pulse"
    
elif preset = 14
    # Spring Oscillation
    initial_height = 1.0
    initial_velocity = 7.0
    gravity = 8.0
    bounce_coefficient = 0.82
    number_of_bounces = 15
    mapping = 3
    amplitude_scale = 0.95
    panStart = -1.0
    panEnd = 1.0
    distAtten = 0.4
    presetName$ = "Spring_Oscillation"
    
elif preset = 15
    # Pendulum Swing
    initial_height = 1.8
    initial_velocity = 2.5
    gravity = 5.0
    bounce_coefficient = 0.90
    number_of_bounces = 10
    mapping = 1
    amplitude_scale = 1.1
    panStart = -1.0
    panEnd = 1.0
    distAtten = 0.7
    presetName$ = "Pendulum_Swing"
    
else
    # Rolling Downhill (preset 16)
    initial_height = 2.5
    initial_velocity = 1.0
    gravity = 15.0
    bounce_coefficient = 0.45
    number_of_bounces = 5
    mapping = 2
    amplitude_scale = 1.3
    panStart = -1.0
    panEnd = 1.0
    distAtten = 0.5
    presetName$ = "Rolling_Downhill"
endif

writeInfoLine: "=== Physics-Based Stereo Dynamics v0.2 ==="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Panning: ", fixed$(panStart, 2), " -> ", fixed$(panEnd, 2)
appendInfoLine: "Wet/Dry: ", fixed$(mixPercent, 0), "%"
appendInfoLine: ""

# ============================================================
# PHYSICS SIMULATION
# ============================================================

# Scale simulation points with duration (min 200, max 2000)
numPoints = round(duration * 100)
if numPoints < 200
    numPoints = 200
elif numPoints > 2000
    numPoints = 2000
endif

timeStep = duration / (numPoints - 1)

appendInfoLine: "Simulation: ", numPoints, " points, dt=", fixed$(timeStep * 1000, 2), "ms"

# Initialize vector arrays (much faster than indexed variables)
time# = zero#(numPoints)
height# = zero#(numPoints)
velocity# = zero#(numPoints)
pan# = zero#(numPoints)

# Physics simulation variables
currentHeight = initial_height
currentVelocity = initial_velocity
currentTime = 0
bouncesDone = 0
groundLevel = 0

# Simulate ball motion
for i from 1 to numPoints
    time#[i] = currentTime
    height#[i] = currentHeight
    velocity#[i] = abs(currentVelocity)
    
    # Calculate lateral position (pan)
    progress = (i - 1) / (numPoints - 1)
    if presetName$ = "Spring_Oscillation" or presetName$ = "Pendulum_Swing"
        # Oscillating pan
        pan#[i] = panStart + (panEnd - panStart) * sin(progress * pi * 4)
    else
        # Linear pan interpolation
        pan#[i] = panStart + (panEnd - panStart) * progress
    endif
    
    # Update vertical physics (Euler integration)
    currentVelocity = currentVelocity - gravity * timeStep
    currentHeight = currentHeight + currentVelocity * timeStep
    
    # Check for bounce
    if currentHeight <= groundLevel and bouncesDone < number_of_bounces
        currentHeight = groundLevel
        currentVelocity = -currentVelocity * bounce_coefficient
        bouncesDone = bouncesDone + 1
    endif
    
    # Clamp to ground after all bounces
    if currentHeight < groundLevel
        currentHeight = groundLevel
        currentVelocity = 0
    endif
    
    currentTime = currentTime + timeStep
endfor

appendInfoLine: "Physics: ", bouncesDone, " bounces simulated"

# ============================================================
# MAP PHYSICS TO AMPLITUDE & STEREO
# ============================================================

tierL = Create IntensityTier: "envelope_left", 0, duration
tierR = Create IntensityTier: "envelope_right", 0, duration

# Maximum possible velocity for normalization
maxVelocity = initial_velocity + gravity * duration
if maxVelocity < 0.001
    maxVelocity = 0.001
endif

# Ensure initial_height is not zero
normHeight = initial_height
if normHeight < 0.001
    normHeight = 0.001
endif

for i from 1 to numPoints
    t = time#[i]
    h = height#[i]
    v = velocity#[i]
    p = pan#[i]
    
    # 1. Base physical amplitude from mapping mode
    if mapping = 1
        # Height only (potential energy)
        amp = h / normHeight
    elif mapping = 2
        # Velocity only (kinetic energy)
        amp = v / maxVelocity
    else
        # Combined (height + velocity)
        amp = (h / normHeight + v / maxVelocity) / 2
    endif
    
    # 2. Distance-based loudness attenuation
    dist = abs(p)
    distFactor = 1.0 / (1.0 + distAtten * dist)
    amp = amp * amplitude_scale * distFactor
    
    # Floor amplitude
    if amp < 0.001
        amp = 0.001
    endif
    
    # 3. Stereo panning (constant-power square root law)
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
    
    # Ensure minimum for log10
    if ampL < 0.00001
        ampL = 0.00001
    endif
    if ampR < 0.00001
        ampR = 0.00001
    endif
    
    # Convert to dB
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

# Create working copy
selectObject: original
workingCopy = Copy: "temp_working"

# Convert to stereo if mono (capture the result)
selectObject: workingCopy
nCh = Get number of channels
if nCh = 1
    stereoTemp = Convert to stereo
    removeObject: workingCopy
    workingCopy = stereoTemp
endif

# Extract channels
selectObject: workingCopy
ch1 = Extract one channel: 1
selectObject: workingCopy
ch2 = Extract one channel: 2

# Apply intensity envelopes
selectObject: ch1
plusObject: tierL
Multiply: "yes"
ch1Mod = selected("Sound")

selectObject: ch2
plusObject: tierR
Multiply: "yes"
ch2Mod = selected("Sound")

# Combine to stereo
selectObject: ch1Mod
plusObject: ch2Mod
Combine to stereo
wetSound = selected("Sound")

# Apply wet/dry mix
if dry_level > 0
    # Need dry version in stereo
    selectObject: original
    dryCopy = Copy: "temp_dry"
    selectObject: dryCopy
    nChDry = Get number of channels
    if nChDry = 1
        dryStTemp = Convert to stereo
        removeObject: dryCopy
        dryCopy = dryStTemp
    endif
    
    # Mix formula
    wetStr$ = string$(wet_level)
    dryStr$ = string$(dry_level)
    dryIdStr$ = string$(dryCopy)
    
    selectObject: wetSound
    Formula: "self * " + wetStr$ + " + Object_" + dryIdStr$ + "[col] * " + dryStr$
    
    removeObject: dryCopy
endif

selectObject: wetSound
Rename: originalName$ + "_" + presetName$
result = selected("Sound")
Scale peak: 0.99

# ============================================================
# CLEANUP INTERMEDIATES
# ============================================================

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
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 7, 0, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Physics-Based Stereo Dynamics: " + presetName$
    
    # Original waveform
    Select outer viewport: 0, 7, 0.5, 1.8
    Select inner viewport: 0.6, 6.6, 0.7, 1.6
    selectObject: original
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 7, 1.8, 3.1
    Select inner viewport: 0.6, 6.6, 2.0, 2.9
    selectObject: result
    Colour: "{0.3, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Result"
    Text bottom: "yes", "Time (s)"
    
    # Height trajectory
    Select outer viewport: 0, 7, 3.3, 4.6
    Select inner viewport: 0.6, 6.6, 3.5, 4.4
    
    maxH = initial_height * 1.2
    if maxH < 0.1
        maxH = 0.1
    endif
    
    Axes: 0, duration, 0, maxH
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, 0, maxH
    
    # Ground line
    Colour: "{0.7, 0.5, 0.3}"
    Line width: 2
    Draw line: 0, 0, duration, 0
    Line width: 1
    
    # Height curve
    Colour: "{0.8, 0.4, 0.2}"
    Line width: 2
    for i from 2 to numPoints
        Draw line: time#[i-1], height#[i-1], time#[i], height#[i]
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Height (m)"
    Text top: "no", "Ball Height Trajectory"
    
    # Pan trajectory (top view)
    Select outer viewport: 0, 7, 4.8, 6.3
    Select inner viewport: 0.6, 6.6, 5.0, 6.1
    
    panMin = panStart
    if panEnd < panMin
        panMin = panEnd
    endif
    panMin = panMin - 0.2
    
    panMax = panStart
    if panEnd > panMax
        panMax = panEnd
    endif
    panMax = panMax + 0.2
    
    if panMin > -1.2
        panMin = -1.2
    endif
    if panMax < 1.2
        panMax = 1.2
    endif
    
    Axes: 0, duration, panMin, panMax
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, panMin, panMax
    
    # Center line
    Colour: "{0.8, 0.8, 0.8}"
    Draw line: 0, 0, duration, 0
    
    # Left/Right labels
    Font size: 6
    Colour: "{0.6, 0.6, 0.6}"
    Text: duration * 0.02, "left", -0.9, "half", "L"
    Text: duration * 0.02, "left", 0.9, "half", "R"
    
    # Pan curve
    Colour: "{0.2, 0.5, 0.8}"
    Line width: 2
    for i from 2 to numPoints
        Draw line: time#[i-1], pan#[i-1], time#[i], pan#[i]
    endfor
    Line width: 1
    
    # Ball markers (size = height)
    markerInterval = round(numPoints / 20)
    if markerInterval < 1
        markerInterval = 1
    endif
    for i from 1 to numPoints
        if i mod markerInterval = 0
            t = time#[i]
            p = pan#[i]
            h = height#[i]
            markerSize = h / normHeight * 0.12
            if markerSize < 0.02
                markerSize = 0.02
            endif
            Colour: "{0.9, 0.4, 0.3}"
            Paint circle: "{0.9, 0.4, 0.3}", t, p, markerSize
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Pan"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Pan Trajectory (ball size = height)"
    
    # Parameters summary
    Select outer viewport: 0, 7, 6.4, 6.8
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "g=" + fixed$(gravity, 1) + " | bounce=" + fixed$(bounce_coefficient, 2) + " | h0=" + fixed$(initial_height, 1) + " | v0=" + fixed$(initial_velocity, 1) + " | wet=" + fixed$(mixPercent, 0) + "%"
    
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# FINAL OUTPUT
# ============================================================

selectObject: result

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Original preserved: ", originalName$
appendInfoLine: "Result created: ", originalName$ + "_" + presetName$
appendInfoLine: "Channels: stereo"
appendInfoLine: "Physics: g=", fixed$(gravity, 1), " m/s2, bounce=", fixed$(bounce_coefficient, 2)
appendInfoLine: "Pan: ", fixed$(panStart, 2), " -> ", fixed$(panEnd, 2)
appendInfoLine: "Distance attenuation: ", fixed$(distAtten, 2)
appendInfoLine: "Wet/Dry: ", fixed$(mixPercent, 0), "%"
appendInfoLine: ""

if play_result
    selectObject: result
    Play
endif

selectObject: result