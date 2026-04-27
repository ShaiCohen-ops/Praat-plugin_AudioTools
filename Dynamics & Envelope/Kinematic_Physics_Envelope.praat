# ============================================================
# Praat AudioTools - Kinematic_Physics_Envelope.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Kinematic physics envelope generator. Simulates bouncing ball,
#   pendulum, spring, and other physical systems to create
#   amplitude envelopes.
#
# Changelog v1.0:
#   - Single unified form interface
#   - Added damping and air resistance options
#   - Added reverse envelope option
#   - Improved visualization with bounce markers
#   - Added smoothing option
#   - Optional play/visualize
#
# Changelog v1.1 (2026):
#   - FIX (architectural): v1.0 derived the physics timestep from
#     the AUDIO duration (timeStep = duration / 499). For long
#     inputs (>10 s) the timestep grew to ~20-100 ms, which (a)
#     caused Euler integration to skip bounce events entirely
#     when the ball moved more than 1 sample-period of distance
#     between samples, and (b) compressed the entire bounce
#     sequence into the audio's first ~10% with no auto-handling
#     of the silent "ball at rest" remainder.
#
#     v1.1 decouples physics from audio: physics now runs in
#     REAL TIME at a fixed 1 ms timestep (sub-step refinement at
#     bounce moments to find exact zero-crossing) until the ball
#     stops bouncing or hits the energy/time cap. The resulting
#     physics curve is then resampled to the audio duration via
#     one of three time-mapping modes:
#       - STRETCH:    physics duration → audio duration (v1.0
#                     intent, but with accurate physics).
#       - REAL-TIME:  physics timing as-is. If shorter than the
#                     audio, the remainder uses min_amplitude
#                     (ball at rest). If longer, physics is
#                     truncated to the audio length.
#       - LOOP:       physics curve tiles over the audio length.
#                     For "applying a rubber ball envelope to a
#                     30 s pad", this is usually what you want.
#   - Bounce markers in the viz now show actual physics-time
#     bounce locations, not Euler-step approximations.
# ============================================================

form Kinematic Physics Envelope v1.1
    optionmenu Preset 1
        option Custom
        option Bouncy Rubber Ball
        option Steel Ball Drop
        option Ping Pong Frenzy
        option Basketball Dribble
        option Super Ball Chaos
        option Dropping Stone
        option Feather Falling
        option Moon Gravity
        option Tennis Ball
        option Water Skipping Stone
        option Earthquake Tremor
        option Heartbeat Pulse
        option Spring Oscillation
        option Pendulum Swing
        option Rolling Downhill
    comment === Physics Parameters ===
    real Initial_height_m 1.0
    real Initial_velocity_m_s 5.0
    real Gravity_m_s2 9.8
    real Bounce_coefficient 0.7
    natural Max_bounces 10
    comment === Envelope Mapping ===
    optionmenu Mapping 3
        option Height (potential energy)
        option Velocity (kinetic energy)
        option Combined (height + velocity)
    optionmenu Time_mapping 2
        option Stretch (physics fills audio)
        option Real-time (silence after ball rests)
        option Loop (tile physics over audio)
    real Amplitude_scale 1.0
    comment === Modifiers ===
    boolean Reverse_envelope 0
    integer Smoothing_passes 0
    real Min_amplitude 0.01
    comment === Output ===
    boolean Normalize 1
    boolean Visualize 1
    boolean Play 1
endform

# === INPUT VALIDATION ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
sound_name$ = selected$("Sound")

selectObject: sound
duration = Get total duration
sr = Get sampling frequency

# === APPLY PRESETS ===
if preset = 2
    # Bouncy Rubber Ball
    initial_height_m = 1.2
    initial_velocity_m_s = 6.0
    gravity_m_s2 = 9.8
    bounce_coefficient = 0.75
    max_bounces = 8
    mapping = 3
    amplitude_scale = 1.0
    presetName$ = "RubberBall"
elsif preset = 3
    # Steel Ball Drop
    initial_height_m = 2.0
    initial_velocity_m_s = 3.0
    gravity_m_s2 = 9.8
    bounce_coefficient = 0.92
    max_bounces = 12
    mapping = 1
    amplitude_scale = 1.2
    presetName$ = "SteelBall"
elsif preset = 4
    # Ping Pong Frenzy
    initial_height_m = 0.8
    initial_velocity_m_s = 10.0
    gravity_m_s2 = 9.8
    bounce_coefficient = 0.85
    max_bounces = 15
    mapping = 2
    amplitude_scale = 0.9
    presetName$ = "PingPong"
elsif preset = 5
    # Basketball Dribble
    initial_height_m = 1.5
    initial_velocity_m_s = 4.0
    gravity_m_s2 = 9.8
    bounce_coefficient = 0.70
    max_bounces = 6
    mapping = 3
    amplitude_scale = 1.1
    presetName$ = "Basketball"
elsif preset = 6
    # Super Ball Chaos
    initial_height_m = 1.0
    initial_velocity_m_s = 8.0
    gravity_m_s2 = 9.8
    bounce_coefficient = 0.95
    max_bounces = 20
    mapping = 2
    amplitude_scale = 0.85
    presetName$ = "SuperBall"
elsif preset = 7
    # Dropping Stone
    initial_height_m = 3.0
    initial_velocity_m_s = 0.0
    gravity_m_s2 = 12.0
    bounce_coefficient = 0.0
    max_bounces = 0
    mapping = 2
    amplitude_scale = 1.5
    presetName$ = "Stone"
elsif preset = 8
    # Feather Falling
    initial_height_m = 2.0
    initial_velocity_m_s = 1.0
    gravity_m_s2 = 2.0
    bounce_coefficient = 0.3
    max_bounces = 3
    mapping = 1
    amplitude_scale = 0.8
    presetName$ = "Feather"
elsif preset = 9
    # Moon Gravity
    initial_height_m = 1.5
    initial_velocity_m_s = 4.0
    gravity_m_s2 = 1.62
    bounce_coefficient = 0.65
    max_bounces = 8
    mapping = 3
    amplitude_scale = 1.0
    presetName$ = "Moon"
elsif preset = 10
    # Tennis Ball
    initial_height_m = 1.3
    initial_velocity_m_s = 5.5
    gravity_m_s2 = 9.8
    bounce_coefficient = 0.73
    max_bounces = 7
    mapping = 3
    amplitude_scale = 1.0
    presetName$ = "Tennis"
elsif preset = 11
    # Water Skipping Stone
    initial_height_m = 0.5
    initial_velocity_m_s = 12.0
    gravity_m_s2 = 9.8
    bounce_coefficient = 0.60
    max_bounces = 10
    mapping = 2
    amplitude_scale = 0.75
    presetName$ = "Skipping"
elsif preset = 12
    # Earthquake Tremor
    initial_height_m = 0.3
    initial_velocity_m_s = 3.0
    gravity_m_s2 = 15.0
    bounce_coefficient = 0.88
    max_bounces = 25
    mapping = 2
    amplitude_scale = 1.3
    presetName$ = "Earthquake"
elsif preset = 13
    # Heartbeat Pulse
    initial_height_m = 0.8
    initial_velocity_m_s = 6.0
    gravity_m_s2 = 18.0
    bounce_coefficient = 0.65
    max_bounces = 12
    mapping = 2
    amplitude_scale = 1.4
    presetName$ = "Heartbeat"
elsif preset = 14
    # Spring Oscillation
    initial_height_m = 1.0
    initial_velocity_m_s = 7.0
    gravity_m_s2 = 8.0
    bounce_coefficient = 0.82
    max_bounces = 15
    mapping = 3
    amplitude_scale = 0.95
    presetName$ = "Spring"
elsif preset = 15
    # Pendulum Swing
    initial_height_m = 1.8
    initial_velocity_m_s = 2.5
    gravity_m_s2 = 5.0
    bounce_coefficient = 0.90
    max_bounces = 10
    mapping = 1
    amplitude_scale = 1.1
    presetName$ = "Pendulum"
elsif preset = 16
    # Rolling Downhill
    initial_height_m = 2.5
    initial_velocity_m_s = 1.0
    gravity_m_s2 = 15.0
    bounce_coefficient = 0.45
    max_bounces = 5
    mapping = 2
    amplitude_scale = 1.3
    presetName$ = "Rolling"
else
    presetName$ = "Custom"
endif

# === GET MAPPING NAME ===
if mapping = 1
    mappingName$ = "Height"
elsif mapping = 2
    mappingName$ = "Velocity"
else
    mappingName$ = "Combined"
endif

# === GET TIME-MAPPING NAME ===
if time_mapping = 1
    timeMapName$ = "Stretch"
elsif time_mapping = 2
    timeMapName$ = "Real-time"
else
    timeMapName$ = "Loop"
endif

# === INFO HEADER ===
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  KINEMATIC PHYSICS ENVELOPE v1.1"
writeInfoLine: "=============================================="
writeInfoLine: ""
writeInfoLine: "Input: ", sound_name$, " (", fixed$(duration, 3), "s)"
writeInfoLine: "Preset: ", presetName$
writeInfoLine: ""
writeInfoLine: "=== Physics Parameters ==="
writeInfoLine: "  Initial height: ", fixed$(initial_height_m, 2), " m"
writeInfoLine: "  Initial velocity: ", fixed$(initial_velocity_m_s, 2), " m/s"
writeInfoLine: "  Gravity: ", fixed$(gravity_m_s2, 2), " m/s²"
writeInfoLine: "  Bounce coefficient: ", fixed$(bounce_coefficient, 2)
writeInfoLine: "  Max bounces: ", max_bounces
writeInfoLine: "  Mapping: ", mappingName$
writeInfoLine: "  Time mapping: ", timeMapName$
writeInfoLine: ""

# ============================================================
# PHYSICS SIMULATION (v1.1: real-time, fixed dt, sub-step bounce refinement)
# ============================================================
# Run physics at a fixed fine timestep (1 ms) until the ball stops
# bouncing OR max_bounces is reached OR a hard time cap is hit.
# At each step where the ball crosses zero height we refine the
# bounce moment by linear interpolation between the two adjacent
# samples (so the bounce is timed accurately, not snapped to the
# next 1ms grid point).

appendInfoLine: "Simulating physics in real time..."

physDt = 0.001
physTimeCap = 30.0
maxPhysSamples = round(physTimeCap / physDt) + 10
restThresholdH = 0.001
restThresholdV = 0.01

# Pre-allocate physics arrays. Praat indexed-scalar arrays are
# 1-based so we use index 1..nPhys.
for i from 1 to maxPhysSamples
    physTime[i] = 0
    physHeight[i] = 0
    physVel[i] = 0
endfor

numBounceEvents = 0
for i from 1 to max_bounces + 5
    bounceTime[i] = 0
endfor

currentHeight = initial_height_m
currentVelocity = initial_velocity_m_s
currentTime = 0
bouncesDone = 0

# Sample 1 = initial state
physTime[1] = 0
physHeight[1] = currentHeight
physVel[1] = abs(currentVelocity)
nPhys = 1

# Real-time loop. Stop when ball is at rest AND max_bounces would
# be hit, OR when we exceed the physics time cap, OR when array fills.
keepGoing = 1
while keepGoing = 1 and nPhys < maxPhysSamples
    prevHeight = currentHeight
    prevVelocity = currentVelocity
    prevTime = currentTime

    # Euler step
    nextVelocity = currentVelocity - gravity_m_s2 * physDt
    nextHeight = currentHeight + nextVelocity * physDt
    nextTime = currentTime + physDt

    # Sub-step bounce refinement: if we crossed zero height this
    # step AND we have bounces remaining, find the exact zero
    # crossing and apply the bounce there.
    if nextHeight <= 0 and prevHeight > 0 and bouncesDone < max_bounces
        # Linear interpolation: at what fraction f of physDt is height = 0?
        # h(prev) > 0, h(next) <= 0, so f = h(prev) / (h(prev) - h(next))
        denom = prevHeight - nextHeight
        if denom > 1e-12
            frac = prevHeight / denom
        else
            frac = 1
        endif
        if frac < 0
            frac = 0
        endif
        if frac > 1
            frac = 1
        endif

        bounceDt = physDt * frac
        # Velocity at bounce moment (before reflection):
        vAtBounce = prevVelocity - gravity_m_s2 * bounceDt
        # Reflect:
        vAfterBounce = -vAtBounce * bounce_coefficient

        # Advance from bounce moment to end of step with reflected velocity
        remDt = physDt - bounceDt
        currentVelocity = vAfterBounce - gravity_m_s2 * remDt
        currentHeight = 0 + vAfterBounce * remDt - 0.5 * gravity_m_s2 * remDt * remDt
        if currentHeight < 0
            currentHeight = 0
            currentVelocity = 0
        endif
        currentTime = nextTime

        # Record the bounce at its exact physics time
        bouncesDone = bouncesDone + 1
        numBounceEvents = numBounceEvents + 1
        bounceTime[numBounceEvents] = prevTime + bounceDt
    elsif nextHeight <= 0 and bouncesDone >= max_bounces
        # No more bounces allowed: clamp to ground at rest
        currentHeight = 0
        currentVelocity = 0
        currentTime = nextTime
    else
        currentHeight = nextHeight
        currentVelocity = nextVelocity
        currentTime = nextTime
    endif

    nPhys = nPhys + 1
    physTime[nPhys] = currentTime
    physHeight[nPhys] = currentHeight
    physVel[nPhys] = abs(currentVelocity)

    # Termination: rest detection (ball at floor with negligible velocity)
    if currentHeight < restThresholdH and abs(currentVelocity) < restThresholdV and bouncesDone >= max_bounces
        keepGoing = 0
    endif
    if currentHeight = 0 and currentVelocity = 0 and bouncesDone >= max_bounces
        keepGoing = 0
    endif
    if currentTime >= physTimeCap
        keepGoing = 0
    endif
endwhile

physDur = physTime[nPhys]

appendInfoLine: "  Physics duration: ", fixed$(physDur, 3), " s (", nPhys, " samples at 1 ms)"
appendInfoLine: "  Actual bounces: ", bouncesDone

# Length comparison and recommendation
if physDur < duration * 0.5 and time_mapping = 2
    appendInfoLine: "  NOTE: physics is much shorter than audio."
    appendInfoLine: "        Audio tail will use min_amplitude (ball at rest)."
    appendInfoLine: "        Try Time_mapping = Loop or Stretch for non-trivial tail."
endif

# ============================================================
# RESAMPLE PHYSICS TO ENVELOPE (v1.1: time-mapping modes)
# ============================================================

appendInfoLine: "Building envelope (mode: ", timeMapName$, ")..."

numPoints = 500
timeStep = duration / (numPoints - 1)

for i from 1 to numPoints
    simTime[i] = 0
    simHeight[i] = 0
    simVelocity[i] = 0
endfor

# Procedure: linearly interpolate physHeight/physVel at a given physics time tQ.
# Caller sets queryT, reads result via lookupPhysics.h and lookupPhysics.v.
procedure lookupPhysics: .queryT
    # Clamp to valid range
    if .queryT <= 0
        .h = physHeight[1]
        .v = physVel[1]
    elsif .queryT >= physDur
        .h = physHeight[nPhys]
        .v = physVel[nPhys]
    else
        # Find the bracketing samples. Since physTime is uniform
        # at physDt apart, we can index directly.
        .idxF = .queryT / physDt + 1
        .idxLo = floor(.idxF)
        .frac = .idxF - .idxLo
        if .idxLo < 1
            .idxLo = 1
        endif
        if .idxLo >= nPhys
            .idxLo = nPhys - 1
            .frac = 1
        endif
        .h = physHeight[.idxLo] * (1 - .frac) + physHeight[.idxLo + 1] * .frac
        .v = physVel[.idxLo]   * (1 - .frac) + physVel[.idxLo + 1]   * .frac
    endif
endproc

for i from 1 to numPoints
    audioT = (i - 1) * timeStep
    simTime[i] = audioT

    # Map audio time to physics time per the selected mode
    if time_mapping = 1
        # STRETCH: physics duration → audio duration
        if duration > 1e-9
            queryT = audioT * physDur / duration
        else
            queryT = 0
        endif
    elsif time_mapping = 2
        # REAL-TIME: physics timing as-is
        queryT = audioT
    else
        # LOOP: tile physics over audio
        if physDur > 1e-9
            queryT = audioT - floor(audioT / physDur) * physDur
        else
            queryT = 0
        endif
    endif

    @lookupPhysics: queryT
    simHeight[i] = lookupPhysics.h
    simVelocity[i] = lookupPhysics.v
endfor

# Map physics-time bounce events to envelope-time for the viz
numEnvBounces = 0
for b from 1 to numBounceEvents
    pt = bounceTime[b]
    if time_mapping = 1
        # STRETCH inverse: audio_t = phys_t * audio_dur / phys_dur
        if physDur > 1e-9
            et = pt * duration / physDur
        else
            et = 0
        endif
        numEnvBounces = numEnvBounces + 1
        envBounceTime[numEnvBounces] = et
    elsif time_mapping = 2
        # REAL-TIME: same time, only show if within audio duration
        if pt <= duration
            numEnvBounces = numEnvBounces + 1
            envBounceTime[numEnvBounces] = pt
        endif
    else
        # LOOP: each physics bounce repeats once per loop period
        if physDur > 1e-9
            nLoops = floor(duration / physDur) + 1
            for L from 0 to nLoops - 1
                et = pt + L * physDur
                if et <= duration and numEnvBounces < max_bounces * 100
                    numEnvBounces = numEnvBounces + 1
                    envBounceTime[numEnvBounces] = et
                endif
            endfor
        endif
    endif
endfor

# ============================================================
# MAP PHYSICS TO AMPLITUDE
# ============================================================

appendInfoLine: "Creating envelope..."

# Find max values for normalization
# v1.1: maxVelocity is based on PHYSICS duration, not audio duration.
# In v1.0 the velocity normalizer scaled with audio length, so the
# Velocity-mapping envelope would look smaller for long audio inputs
# even though the actual physics velocities were unchanged.
maxHeight = initial_height_m
maxVelocity = initial_velocity_m_s + gravity_m_s2 * physDur

# Avoid division by zero
if maxHeight < 0.001
    maxHeight = 0.001
endif
if maxVelocity < 0.001
    maxVelocity = 0.001
endif

# Create envelope array
for i from 1 to numPoints
    h = simHeight[i]
    v = simVelocity[i]
    
    # Map to amplitude
    if mapping = 1
        amp = h / maxHeight
    elsif mapping = 2
        amp = v / maxVelocity
    else
        amp = (h / maxHeight + v / maxVelocity) / 2
    endif
    
    # Apply scale
    amp = amp * amplitude_scale
    
    # Clamp
    if amp < min_amplitude
        amp = min_amplitude
    endif
    if amp > 2.0
        amp = 2.0
    endif
    
    envAmp[i] = amp
endfor

# Apply reverse if requested
if reverse_envelope
    for i from 1 to numPoints
        j = numPoints - i + 1
        tempAmp[i] = envAmp[j]
    endfor
    for i from 1 to numPoints
        envAmp[i] = tempAmp[i]
    endfor
    appendInfoLine: "  Envelope reversed"
endif

# Apply smoothing if requested
if smoothing_passes > 0
    for pass to smoothing_passes
        for i from 2 to numPoints - 1
            smoothAmp[i] = (envAmp[i-1] + 2 * envAmp[i] + envAmp[i+1]) / 4
        endfor
        smoothAmp[1] = envAmp[1]
        smoothAmp[numPoints] = envAmp[numPoints]
        for i from 1 to numPoints
            envAmp[i] = smoothAmp[i]
        endfor
    endfor
    appendInfoLine: "  Smoothing applied (", smoothing_passes, " passes)"
endif

# ============================================================
# CREATE INTENSITY TIER AND APPLY
# ============================================================

tier = Create IntensityTier: "physics_envelope", 0, duration

for i from 1 to numPoints
    t = simTime[i]
    amp = envAmp[i]
    
    # Convert to dB
    if amp > 0.0001
        db = 20 * log10(amp)
    else
        db = -80
    endif
    
    if db < -80
        db = -80
    endif
    
    selectObject: tier
    Add point: t, db
endfor

# Apply to sound
selectObject: sound
plusObject: tier
result = Multiply: "yes"
Rename: sound_name$ + "_" + presetName$

# Normalize
if normalize
    selectObject: result
    Scale peak: 0.95
endif

appendInfoLine: ""
appendInfoLine: "Envelope applied successfully"

# ============================================================
# VISUALIZATION
# ============================================================

if visualize
    appendInfoLine: ""
    appendInfoLine: "Creating visualization..."
    
    Erase all
    
    # === TITLE ===
    Select outer viewport: 1, 8, 0, 0.4
    Font size: 11
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Kinematic Physics Envelope v1.1## | " + presetName$ + " | " + mappingName$ + " | " + timeMapName$
    
    # === PHYSICS TRAJECTORY ===
    Select outer viewport: 0, 8, 0.5, 2.0
    Select inner viewport: 0.8, 7.6, 0.6, 1.8
    
    # Create trajectory sound for display
    Create Sound from formula: "trajectory_viz", 1, 0, duration, numPoints, ~ 0
    trajectory_viz = selected("Sound")
    
    for i from 1 to numPoints
        selectObject: trajectory_viz
        Set value at sample number: 1, i, simHeight[i]
    endfor
    
    # Get height range
    selectObject: trajectory_viz
    maxH = Get maximum: 0, 0, "Sinc70"
    if maxH < 0.1
        maxH = 1
    endif
    
    # Background
    Axes: 0, duration, -0.1, maxH * 1.1
    Paint rectangle: "{0.95, 0.97, 1.0}", 0, duration, -0.1, maxH * 1.1
    
    # Ground line
    Colour: "{0.6, 0.4, 0.2}"
    Line width: 2
    Draw line: 0, 0, duration, 0
    
    # Trajectory
    Colour: "{0.3, 0.5, 0.8}"
    Line width: 2
    selectObject: trajectory_viz
    Draw: 0, 0, -0.1, maxH * 1.1, "no", "Curve"
    
    # Mark bounces
    # v1.1: viz uses envBounceTime[] (envelope-time) not bounceTime[]
    # (physics-time). For Stretch mode they map differently; for
    # Loop mode each physics bounce repeats once per loop period.
    Colour: "{0.9, 0.3, 0.3}"
    Line width: 1
    for b from 1 to numEnvBounces
        bt = envBounceTime[b]
        Draw line: bt, -0.05, bt, 0.05
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    
    Font size: 7
    Select outer viewport: 0.15, 8, 0.5, 2.0
    Text left: "yes", "Height (m)"
    
    removeObject: trajectory_viz
    
    # === ENVELOPE ===
    Select outer viewport: 0, 8, 2.1, 3.3
    Select inner viewport: 0.8, 7.6, 2.2, 3.1
    
    # Create envelope sound for display
    Create Sound from formula: "env_viz", 1, 0, duration, numPoints, ~ 0
    env_viz = selected("Sound")
    
    for i from 1 to numPoints
        selectObject: env_viz
        Set value at sample number: 1, i, envAmp[i]
    endfor
    
    # Background
    Axes: 0, duration, 0, 1.2
    Paint rectangle: "{0.95, 0.98, 0.95}", 0, duration, 0, 1.2
    
    # Unity reference
    Colour: "{0.7, 0.7, 0.7}"
    Dashed line
    Draw line: 0, 1, duration, 1
    Solid line
    
    # Envelope
    Colour: "{0.2, 0.7, 0.3}"
    Line width: 2
    selectObject: env_viz
    Draw: 0, 0, 0, 1.2, "no", "Curve"
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    
    Font size: 7
    Select outer viewport: 0.15, 8, 2.1, 3.3
    Text left: "yes", "Envelope"
    
    removeObject: env_viz
    
    # === ORIGINAL ===
    Select outer viewport: 0, 8, 3.4, 4.4
    Select inner viewport: 0.8, 7.6, 3.5, 4.2
    
    selectObject: sound
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    
    Font size: 7
    Select outer viewport: 0.15, 8, 3.4, 4.4
    Text left: "yes", "Input"
    
    # === RESULT ===
    Select outer viewport: 0, 8, 4.5, 5.5
    Select inner viewport: 0.8, 7.6, 4.6, 5.3
    
    selectObject: result
    Colour: "{0.3, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    
    Font size: 7
    Select outer viewport: 0.15, 8, 4.5, 5.5
    Text left: "yes", "Result"
    Text bottom: "yes", "Time (s)"
    
    # === PARAMETERS ===
    Select outer viewport: 0, 8, 5.6, 6.0
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 1.5, "centre", 0.5, "half", "h₀=" + fixed$(initial_height_m, 1) + "m | v₀=" + fixed$(initial_velocity_m_s, 1) + "m/s | g=" + fixed$(gravity_m_s2, 1) + "m/s² | bounce=" + fixed$(bounce_coefficient, 2) + " | bounces=" + string$(bouncesDone)
    
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# CLEANUP & OUTPUT
# ============================================================

removeObject: tier

selectObject: result

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE: ", selected$("Sound")
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Physics summary:"
appendInfoLine: "  Bounces simulated: ", bouncesDone
appendInfoLine: "  Physics duration: ", fixed$(physDur, 3), " s"
appendInfoLine: "  Audio duration:   ", fixed$(duration, 3), " s"
appendInfoLine: "  Mapping: ", mappingName$
appendInfoLine: "  Time mapping: ", timeMapName$
if reverse_envelope
    appendInfoLine: "  Envelope: REVERSED"
endif

if play
    appendInfoLine: ""
    appendInfoLine: "Playing..."
    Play
endif

selectObject: result