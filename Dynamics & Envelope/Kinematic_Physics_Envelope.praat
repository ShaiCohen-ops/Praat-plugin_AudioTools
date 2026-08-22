# ============================================================
# Praat AudioTools - Kinematic_Physics_Envelope.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Bouncing-ball / impact-envelope generator. Simulates a ball
#   falling, bouncing, and settling under gravity (with optional
#   linear air resistance) and uses the resulting height/velocity
#   trajectory to shape an amplitude envelope. Several presets are
#   named for the kind of impact pattern they produce (e.g.
#   "Earthquake Tremor", "Heartbeat Pulse") rather than for a
#   distinct underlying physical system - all presets run the same
#   fall-and-bounce equations with different parameters.
#
# Changelog v1.4 (2026):
#   - VISUALIZATION / UI STANDARDIZATION ONLY. Audio analysis,
#     DSP, scheduling and rendering are unchanged from the
#     previous version.
#   - Adopted the Praat AudioTools 8-inch visualization header,
#     suite typography, neutral panel backgrounds, summary-style
#     reporting and full-page Picture export restoration.
#   - Preserved the script-specific diagnostic / transformation
#     views rather than replacing them with generic plots.
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
#     one of three time-mapping modes (Stretch / Real-time / Loop).
#
# Changelog v1.2 (2026) - external review round:
#   - FIX: envelope application now multiplies the sound directly
#     in the linear-amplitude domain via a control-rate envelope
#     Sound object referenced by time (Sound_<name>(x) lookup),
#     replacing "Sound & IntensityTier: Multiply". That Praat
#     command silently rescales its result's peak to 0.90 (0.95
#     with a further Normalize pass), so Normalize = no was never
#     actually un-normalized and Amplitude_scale / Min_amplitude
#     were not absolute levels. Removing the dB round-trip also
#     means the drawn envelope and the envelope actually applied
#     to the sound are now the same curve.
#   - SCOPE: the v1.1 description promised "bouncing ball,
#     pendulum, spring, and other physical systems", but every
#     preset ran the same vertical fall-and-bounce equations;
#     Spring Oscillation, Pendulum Swing, and Rolling Downhill were
#     the bounce model wearing different names. Rather than add
#     three more ODE models on top of parameters that don't map
#     cleanly onto them, those three presets are removed and the
#     description now says what the script actually does.
#   - FIX: maxHeight/maxVelocity (used to normalize the envelope)
#     are now the actual simulated maxima, read back from the
#     physics arrays after the run, instead of initial_height_m and
#     a closed-form estimate. The old estimate ignored that a
#     positive Initial_velocity_m_s launches the ball above its
#     initial height, and was off by 2-5x on several presets.
#   - FIX: rest detection no longer requires bouncesDone >=
#     max_bounces. The ball now settles as soon as its post-bounce
#     speed drops below a rest threshold, or as soon as
#     max_bounces is reached, whichever comes first - independent
#     of each other. Previously, once max_bounces was reached
#     without the ball being at rest, "height" could go negative
#     and keep integrating downward for the full 30 s time cap.
#   - FIX: "Velocity (kinetic energy)" mapped abs(velocity), which
#     is speed, not energy (energy is proportional to v^2). Mapping
#     options are now Height, Speed, Kinetic energy (v^2), and
#     Combined - each named for what it actually computes.
#   - FIX: envelope control rate is now derived from audio duration
#     (~2 ms spacing, capped at 20000 points) instead of a fixed
#     500 points, which degraded to >500 ms spacing on long inputs.
#   - FIX: the Sound object's own start/end time are now read (Get
#     start time / Get end time) and used throughout, instead of
#     assuming every Sound starts at 0.
#   - FIX: Loop mode now applies a short crossfade at each loop
#     boundary (blending toward the physics-start state) so
#     consecutive physics cycles don't click.
#   - FIX: Reverse_envelope now also mirrors bounce-marker times,
#     so the markers still line up with the reversed curve.
#   - FIX: added parameter validation, and the script now reports
#     explicitly if the 30 s physics time cap was hit before the
#     ball settled, instead of silently reporting a normal-looking
#     physics duration.
#   - RENAME: "Real-time (silence after ball rests)" -> "Real-time
#     (minimum level after rest)", since the default Min_amplitude
#     (0.01, about -40 dB) is not silence.
#   - ADD: an actual linear air-resistance term (Drag_coefficient),
#     which makes "damping and air resistance" in the v1.0
#     changelog true rather than aspirational. Default 0 for all
#     presets except Feather Falling.
#   - Visualization: physics/envelope panels now share the sound's
#     real time domain with the Input/Result panels (previously
#     hardcoded to start at 0), the envelope panel's vertical scale
#     now reflects the actual data range instead of a fixed 1.2,
#     and the forced-peak note is gone because there's no forced
#     peak rescale left to explain.
#
# Changelog v1.3 (2026) - second review round:
#   - FIX: the envelope's control-rate sample times were computed
#     edge-to-edge (0, dt, 2*dt, ..., duration), but Praat places a
#     Sound's samples at the CENTER of each sample interval
#     (xmin + (i-0.5)*dx). The envelope actually applied could
#     therefore sit up to half a control frame away from where it
#     was computed - up to ~7.5 ms at the 20000-point cap on long
#     files. Sample times are now computed with the same
#     (i-0.5)*dx convention Praat itself uses, so the computed and
#     applied envelopes align exactly.
#   - FIX: Max_bounces and the reported bounce count now count the
#     same thing. Every ground contact was previously counted as a
#     "bounce", including the final contact where the ball is
#     settling rather than reflecting - so e.g. Max_bounces = 8
#     could report 9 "actual bounces". Rebounds (reflections,
#     capped by Max_bounces) and ground contacts (all contacts,
#     including the final settle) are now tracked and reported
#     separately.
#   - FIX: the physics-trajectory panel draws simHeight[] in its
#     original, unreversed time order, but was marking bounces with
#     the mirrored times used for the (possibly reversed) envelope
#     curve. It now uses its own unreversed copy of the bounce
#     times; the Envelope panel gained its own bounce markers using
#     the mirrored times, so each panel's markers match its own
#     curve.
#   - FIX: the time-cap warning told users to raise
#     Bounce_coefficient, which prolongs the bounce sequence and
#     makes hitting the time cap MORE likely. It now recommends
#     lowering Bounce_coefficient/Max_bounces or raising
#     Drag_coefficient.
#   - FIX: Drag_coefficient now has an enforced upper bound. Above
#     1/physDt the explicit-Euler velocity update's (1 - drag*dt)
#     factor goes negative, flipping velocity sign each step
#     instead of damping it - i.e. "more drag" becomes instability,
#     not more damping. Capped at a safe margin below that.
#   - ADD: the Info window now reports the effective control
#     spacing in ms, so it's clear when a long file's envelope grid
#     has coarsened below 2 ms.
# ============================================================

form Kinematic Physics Envelope v1.4
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
    comment === Physics Parameters ===
    real Initial_height_m 1.0
    real Initial_velocity_m_s 5.0
    real Gravity_m_s2 9.8
    real Bounce_coefficient 0.7
    natural Max_bounces 10
    real Drag_coefficient 0.0
    comment === Envelope Mapping ===
    optionmenu Mapping 4
        option Height (potential energy proxy)
        option Speed (velocity magnitude)
        option Kinetic energy (v squared)
        option Combined (height + speed)
    optionmenu Time_mapping 2
        option Stretch (physics fills audio)
        option Real-time (minimum level after rest)
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

# === INPUT VALIDATION (sound selection) ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
sound_name$ = selected$("Sound")

selectObject: sound
duration = Get total duration
sr = Get sampling frequency
srcStart = Get start time
srcEnd = Get end time

# === APPLY PRESETS ===
if preset = 2
    # Bouncy Rubber Ball
    initial_height_m = 1.2
    initial_velocity_m_s = 6.0
    gravity_m_s2 = 9.8
    bounce_coefficient = 0.75
    max_bounces = 8
    drag_coefficient = 0.0
    mapping = 4
    amplitude_scale = 1.0
    presetName$ = "RubberBall"
elsif preset = 3
    # Steel Ball Drop
    initial_height_m = 2.0
    initial_velocity_m_s = 3.0
    gravity_m_s2 = 9.8
    bounce_coefficient = 0.92
    max_bounces = 12
    drag_coefficient = 0.0
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
    drag_coefficient = 0.0
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
    drag_coefficient = 0.0
    mapping = 4
    amplitude_scale = 1.1
    presetName$ = "Basketball"
elsif preset = 6
    # Super Ball Chaos
    initial_height_m = 1.0
    initial_velocity_m_s = 8.0
    gravity_m_s2 = 9.8
    bounce_coefficient = 0.95
    max_bounces = 20
    drag_coefficient = 0.0
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
    drag_coefficient = 0.0
    mapping = 2
    amplitude_scale = 1.5
    presetName$ = "Stone"
elsif preset = 8
    # Feather Falling - real terminal velocity via linear drag,
    # not a fudged-down gravity constant.
    initial_height_m = 2.0
    initial_velocity_m_s = 1.0
    gravity_m_s2 = 9.8
    bounce_coefficient = 0.3
    max_bounces = 3
    drag_coefficient = 6.5
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
    drag_coefficient = 0.0
    mapping = 4
    amplitude_scale = 1.0
    presetName$ = "Moon"
elsif preset = 10
    # Tennis Ball
    initial_height_m = 1.3
    initial_velocity_m_s = 5.5
    gravity_m_s2 = 9.8
    bounce_coefficient = 0.73
    max_bounces = 7
    drag_coefficient = 0.0
    mapping = 4
    amplitude_scale = 1.0
    presetName$ = "Tennis"
elsif preset = 11
    # Water Skipping Stone
    initial_height_m = 0.5
    initial_velocity_m_s = 12.0
    gravity_m_s2 = 9.8
    bounce_coefficient = 0.60
    max_bounces = 10
    drag_coefficient = 0.0
    mapping = 2
    amplitude_scale = 0.75
    presetName$ = "Skipping"
elsif preset = 12
    # Earthquake Tremor - impulse-train envelope, named for its
    # shape, not a separate seismic model.
    initial_height_m = 0.3
    initial_velocity_m_s = 3.0
    gravity_m_s2 = 15.0
    bounce_coefficient = 0.88
    max_bounces = 25
    drag_coefficient = 0.0
    mapping = 2
    amplitude_scale = 1.3
    presetName$ = "Earthquake"
elsif preset = 13
    # Heartbeat Pulse - likewise an impulse-train shape.
    initial_height_m = 0.8
    initial_velocity_m_s = 6.0
    gravity_m_s2 = 18.0
    bounce_coefficient = 0.65
    max_bounces = 12
    drag_coefficient = 0.0
    mapping = 2
    amplitude_scale = 1.4
    presetName$ = "Heartbeat"
else
    presetName$ = "Custom"
endif

# Physics timestep, defined early so validation can check
# Drag_coefficient against it: the Euler update multiplies
# velocity by (1 - drag_coefficient * physDt) each step, so a
# drag_coefficient near or above 1/physDt flips the sign of that
# factor and produces oscillation/instability instead of damping.
physDt = 0.001
maxSafeDrag = 0.5 / physDt

# === PARAMETER VALIDATION (final, post-preset values) ===
if initial_height_m < 0
    exitScript: "Initial_height_m must be >= 0 m."
endif
if gravity_m_s2 <= 0
    exitScript: "Gravity_m_s2 must be > 0 m/s^2."
endif
if bounce_coefficient < 0 or bounce_coefficient > 1
    exitScript: "Bounce_coefficient must be between 0 and 1."
endif
if drag_coefficient < 0
    exitScript: "Drag_coefficient must be >= 0."
endif
if drag_coefficient > maxSafeDrag
    exitScript: "Drag_coefficient must be <= " + string$(maxSafeDrag) + " at the fixed 1 ms physics timestep (higher values produce numerical instability, not stronger damping)."
endif
if amplitude_scale < 0
    exitScript: "Amplitude_scale must be >= 0."
endif
if min_amplitude < 0 or min_amplitude > 2
    exitScript: "Min_amplitude must be between 0 and 2."
endif
if smoothing_passes < 0
    exitScript: "Smoothing_passes must be >= 0."
endif

# === GET MAPPING NAME ===
if mapping = 1
    mappingName$ = "Height"
elsif mapping = 2
    mappingName$ = "Speed"
elsif mapping = 3
    mappingName$ = "Kinetic energy"
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
writeInfoLine: "  KINEMATIC PHYSICS ENVELOPE v1.4"
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
writeInfoLine: "  Drag coefficient: ", fixed$(drag_coefficient, 2)
writeInfoLine: "  Max bounces: ", max_bounces
writeInfoLine: "  Mapping: ", mappingName$
writeInfoLine: "  Time mapping: ", timeMapName$
writeInfoLine: ""

# ============================================================
# PHYSICS SIMULATION (real-time, fixed 1 ms dt, sub-step bounce
# refinement, optional linear air resistance, rest-driven stop)
# ============================================================
# Run physics at a fixed fine timestep until the ball comes to
# rest (settles on the ground) OR a hard time cap is hit. "At
# rest" is now decided purely by post-bounce speed and by
# max_bounces being reached - not by both at once - so a low
# Bounce_coefficient can no longer leave the ball integrating
# through the floor for the rest of the time cap.

appendInfoLine: "Simulating physics in real time..."

physTimeCap = 30.0
maxPhysSamples = round(physTimeCap / physDt) + 10
restThresholdV = 0.01

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
# reboundsDone counts actual reflections off the ground (this is
# what Max_bounces caps). groundContacts additionally counts the
# final settling contact, which has no reflection. Reporting them
# separately means "actual bounces" never appears to exceed
# Max_bounces.
reboundsDone = 0
groundContacts = 0
onGround = 0
truncated = 0

# Sample 1 = initial state
physTime[1] = 0
physHeight[1] = currentHeight
physVel[1] = abs(currentVelocity)
nPhys = 1

keepGoing = 1
while keepGoing = 1 and nPhys < maxPhysSamples
    prevHeight = currentHeight
    prevVelocity = currentVelocity
    prevTime = currentTime

    if onGround = 1
        currentHeight = 0
        currentVelocity = 0
        currentTime = currentTime + physDt
    else
        # Euler step with gravity and linear air resistance
        nextVelocity = currentVelocity - gravity_m_s2 * physDt - drag_coefficient * currentVelocity * physDt
        nextHeight = currentHeight + nextVelocity * physDt
        nextTime = currentTime + physDt

        if nextHeight <= 0 and prevHeight > 0
            # Sub-step bounce refinement: find the exact zero
            # crossing by linear interpolation within this step.
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
            vAtBounce = prevVelocity - gravity_m_s2 * bounceDt - drag_coefficient * prevVelocity * bounceDt
            vAfterBounce = -vAtBounce * bounce_coefficient

            if reboundsDone >= max_bounces or abs(vAfterBounce) < restThresholdV
                # This contact is the last one: either the rebound
                # budget is spent, or the rebound is too weak to
                # matter. Settle here rather than reflecting - this
                # contact is a ground contact but not a rebound.
                currentTime = prevTime + bounceDt
                currentHeight = 0
                currentVelocity = 0
                onGround = 1
                groundContacts = groundContacts + 1
                numBounceEvents = numBounceEvents + 1
                bounceTime[numBounceEvents] = currentTime
            else
                remDt = physDt - bounceDt
                currentVelocity = vAfterBounce - gravity_m_s2 * remDt - drag_coefficient * vAfterBounce * remDt
                currentHeight = vAfterBounce * remDt - 0.5 * gravity_m_s2 * remDt * remDt
                if currentHeight < 0
                    currentHeight = 0
                    currentVelocity = 0
                endif
                currentTime = nextTime
                reboundsDone = reboundsDone + 1
                groundContacts = groundContacts + 1
                numBounceEvents = numBounceEvents + 1
                bounceTime[numBounceEvents] = prevTime + bounceDt
            endif
        elsif nextHeight <= 0 and prevHeight <= 0
            # Defensive fallback: already at/through the ground
            # without a fresh crossing this step. Stay at rest.
            currentHeight = 0
            currentVelocity = 0
            currentTime = nextTime
            onGround = 1
        else
            currentHeight = nextHeight
            currentVelocity = nextVelocity
            currentTime = nextTime
        endif
    endif

    nPhys = nPhys + 1
    physTime[nPhys] = currentTime
    physHeight[nPhys] = currentHeight
    physVel[nPhys] = abs(currentVelocity)

    if onGround = 1
        keepGoing = 0
    endif
    if currentTime >= physTimeCap
        keepGoing = 0
        if onGround = 0
            truncated = 1
        endif
    endif
endwhile

physDur = physTime[nPhys]

appendInfoLine: "  Physics duration: ", fixed$(physDur, 3), " s (", nPhys, " samples at 1 ms)"
appendInfoLine: "  Rebounds: ", reboundsDone, " (Max_bounces = ", max_bounces, ")"
appendInfoLine: "  Ground contacts: ", groundContacts, " (includes the final, non-reflecting contact)"
if truncated
    appendInfoLine: "  WARNING: hit the ", fixed$(physTimeCap, 1), " s physics time cap before the ball"
    appendInfoLine: "           settled. A higher Bounce_coefficient makes this MORE likely,"
    appendInfoLine: "           not less. Try a lower Bounce_coefficient, a lower Max_bounces,"
    appendInfoLine: "           or more Drag_coefficient - or accept the truncation."
endif

# Length comparison and recommendation
if physDur < duration * 0.5 and time_mapping = 2
    appendInfoLine: "  NOTE: physics is much shorter than audio."
    appendInfoLine: "        Audio tail will use Min_amplitude (ball at rest)."
    appendInfoLine: "        Try Time_mapping = Loop or Stretch for non-trivial tail."
endif

# ============================================================
# RESAMPLE PHYSICS TO ENVELOPE (time-mapping modes)
# ============================================================

appendInfoLine: "Building envelope (mode: ", timeMapName$, ")..."

# Control rate is derived from audio duration (~2 ms spacing)
# instead of a fixed 500 points, so long files don't get a
# coarse, transient-smearing envelope grid. Capped for sanity.
targetControlDt = 0.002
numPoints = round(duration / targetControlDt) + 1
if numPoints < 100
    numPoints = 100
endif
maxEnvPoints = 20000
if numPoints > maxEnvPoints
    numPoints = maxEnvPoints
endif

# dx and per-sample time here MUST match how Praat places samples
# in "Create Sound from formula" (sample i is at the CENTER of its
# sample interval: xmin + (i - 0.5) * dx over numPoints samples,
# not spread edge-to-edge over numPoints-1 steps). If the two
# don't match, envAmp[1]/envAmp[numPoints] end up applied roughly
# dx/2 away from srcStart/srcEnd instead of exactly there.
dx = duration / numPoints
controlSpacingMs = dx * 1000
appendInfoLine: "  Effective control spacing: ", fixed$(controlSpacingMs, 2), " ms"

for i from 1 to numPoints
    simTime[i] = 0
    simHeight[i] = 0
    simVelocity[i] = 0
endfor

# Procedure: linearly interpolate physHeight/physVel at a given physics time tQ.
# Caller sets queryT, reads result via lookupPhysics.h and lookupPhysics.v.
procedure lookupPhysics: .queryT
    if .queryT <= 0
        .h = physHeight[1]
        .v = physVel[1]
    elsif .queryT >= physDur
        .h = physHeight[nPhys]
        .v = physVel[nPhys]
    else
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

# Loop-mode crossfade length: blend the last few percent of each
# physics cycle toward the physics-start state, so tiling the
# curve doesn't click at the seam.
loopFadeLen = 0
if time_mapping = 3 and physDur > 1e-9
    loopFadeLen = physDur * 0.05
    if loopFadeLen > 0.05
        loopFadeLen = 0.05
    endif
endif

for i from 1 to numPoints
    audioT = (i - 0.5) * dx
    simTime[i] = srcStart + audioT

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
    h = lookupPhysics.h
    v = lookupPhysics.v

    if loopFadeLen > 0
        distFromEnd = physDur - queryT
        if distFromEnd < loopFadeLen
            w = distFromEnd / loopFadeLen
            @lookupPhysics: 0
            h = h * w + lookupPhysics.h * (1 - w)
            v = v * w + lookupPhysics.v * (1 - w)
        endif
    endif

    simHeight[i] = h
    simVelocity[i] = v
endfor

# Map physics-time bounce events to envelope-time (absolute, in
# the sound's own time domain) for the viz.
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
        envBounceTime[numEnvBounces] = srcStart + et
    elsif time_mapping = 2
        # REAL-TIME: same time, only show if within audio duration
        if pt <= duration
            numEnvBounces = numEnvBounces + 1
            envBounceTime[numEnvBounces] = srcStart + pt
        endif
    else
        # LOOP: each physics bounce repeats once per loop period
        if physDur > 1e-9
            nLoops = floor(duration / physDur) + 1
            for L from 0 to nLoops - 1
                et = pt + L * physDur
                if et <= duration and numEnvBounces < max_bounces * 100 + 100
                    numEnvBounces = numEnvBounces + 1
                    envBounceTime[numEnvBounces] = srcStart + et
                endif
            endfor
        endif
    endif
endfor

# The physics-trajectory panel always draws simHeight[] in its
# original (unreversed) time order, so it needs its own,
# never-mirrored copy of the bounce marker times.
for b from 1 to numEnvBounces
    origEnvBounceTime[b] = envBounceTime[b]
endfor

# ============================================================
# MAP PHYSICS TO AMPLITUDE
# ============================================================

appendInfoLine: "Creating envelope..."

# Actual simulated maxima (not a closed-form estimate). A
# positive Initial_velocity_m_s launches the ball above its
# starting height, so the true peak can exceed initial_height_m
# by several meters; the old estimate ignored this.
maxHeight = physHeight[1]
maxVelocity = physVel[1]
for i from 2 to nPhys
    if physHeight[i] > maxHeight
        maxHeight = physHeight[i]
    endif
    if physVel[i] > maxVelocity
        maxVelocity = physVel[i]
    endif
endfor

if maxHeight < 0.001
    maxHeight = 0.001
endif
if maxVelocity < 0.001
    maxVelocity = 0.001
endif
maxV2 = maxVelocity * maxVelocity

# Create envelope array
for i from 1 to numPoints
    h = simHeight[i]
    v = simVelocity[i]

    # Map to amplitude
    if mapping = 1
        amp = h / maxHeight
    elsif mapping = 2
        amp = v / maxVelocity
    elsif mapping = 3
        amp = (v * v) / maxV2
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

# Apply reverse if requested (also mirror the bounce markers,
# so they still line up with the reversed curve)
if reverse_envelope
    for i from 1 to numPoints
        j = numPoints - i + 1
        tempAmp[i] = envAmp[j]
    endfor
    for i from 1 to numPoints
        envAmp[i] = tempAmp[i]
    endfor
    for b from 1 to numEnvBounces
        envBounceTime[b] = srcStart + srcEnd - envBounceTime[b]
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

# Actual envelope max (for viz scaling)
envMax = envAmp[1]
for i from 2 to numPoints
    if envAmp[i] > envMax
        envMax = envAmp[i]
    endif
endfor
envAxisMax = envMax * 1.1
if envAxisMax < 1.2
    envAxisMax = 1.2
endif
if envAxisMax > 2.2
    envAxisMax = 2.2
endif

# ============================================================
# APPLY ENVELOPE DIRECTLY (linear-amplitude domain, no forced
# peak rescale, no dB round-trip)
# ============================================================
# Instead of an IntensityTier (which is applied via
# "Sound & IntensityTier: Multiply" - a command that always
# rescales its output peak to 0.90, dB-interpolates between
# points, and therefore both silently "normalizes" even with
# Normalize = no and draws a curve that isn't quite the curve
# actually applied) this builds a control-rate envelope as a
# plain Sound object and multiplies sample-by-sample using
# Praat's cross-object time lookup: Sound_<name>(x).

appendInfoLine: "Applying envelope..."

envName$ = "kpe_envelope_" + presetName$
Create Sound from formula: envName$, 1, srcStart, srcEnd, numPoints, "0"
envSound = selected("Sound")

for i from 1 to numPoints
    selectObject: envSound
    Set value at sample number: 1, i, envAmp[i]
endfor

selectObject: sound
resultName$ = sound_name$ + "_" + presetName$
Copy: resultName$
result = selected("Sound")

selectObject: result
Formula: "self * Sound_" + envName$ + " (x)"

# Normalize (now a single, explicit pass - not stacked on top of
# a Multiply command that already rescaled the peak)
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
    vizName$ = replace$(sound_name$, "_", "\_ ", 0)
    pageWidth = 8
    # === Header ===
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Kinematic Physics Envelope v1.4##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", vizName$ + " | " + presetName$ + " | " + mappingName$ + " | " + timeMapName$

    # === PHYSICS TRAJECTORY ===
    Select outer viewport: 0, 8, 0.5, 2.0
    Select inner viewport: 0.8, 7.6, 0.6, 1.8

    # Create trajectory sound for display
    Create Sound from formula: "trajectory_viz", 1, srcStart, srcEnd, numPoints, ~ 0
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
    Axes: srcStart, srcEnd, -0.1, maxH * 1.1
    Paint rectangle: "{0.95, 0.97, 1.0}", srcStart, srcEnd, -0.1, maxH * 1.1

    # Ground line
    Colour: "{0.6, 0.4, 0.2}"
    Line width: 2
    Draw line: srcStart, 0, srcEnd, 0

    # Trajectory
    Colour: "{0.3, 0.5, 0.8}"
    Line width: 2
    selectObject: trajectory_viz
    Draw: 0, 0, -0.1, maxH * 1.1, "no", "Curve"

    # Mark bounces. This panel always draws simHeight[] in its
    # original (unreversed) time order, so it uses
    # origEnvBounceTime[] - the pre-Reverse marker times - even
    # when Reverse_envelope is on. The (possibly mirrored) markers
    # for the actual applied/reversed curve are drawn on the
    # Envelope panel below.
    Colour: "{0.9, 0.3, 0.3}"
    Line width: 1
    for b from 1 to numEnvBounces
        bt = origEnvBounceTime[b]
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
    Create Sound from formula: "env_viz", 1, srcStart, srcEnd, numPoints, ~ 0
    env_viz = selected("Sound")

    for i from 1 to numPoints
        selectObject: env_viz
        Set value at sample number: 1, i, envAmp[i]
    endfor

    # Background
    Axes: srcStart, srcEnd, 0, envAxisMax
    Paint rectangle: "{0.95, 0.98, 0.95}", srcStart, srcEnd, 0, envAxisMax

    # Unity reference
    Colour: "{0.7, 0.7, 0.7}"
    Dashed line
    Draw line: srcStart, 1, srcEnd, 1
    Solid line

    # Envelope
    Colour: "{0.2, 0.7, 0.3}"
    Line width: 2
    selectObject: env_viz
    Draw: 0, 0, 0, envAxisMax, "no", "Curve"

    # Mark bounces against the curve actually shown here (i.e.
    # already mirrored if Reverse_envelope is on).
    Colour: "{0.9, 0.3, 0.3}"
    Line width: 1
    for b from 1 to numEnvBounces
        bt = envBounceTime[b]
        Draw line: bt, 0, bt, envAxisMax * 0.05
    endfor

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

    # === Summary strip ===
    selectObject: result
    outPeakViz = Get absolute extremum: 0, 0, "None"
    Select outer viewport: 0, 8, 5.62, 6.82
    Select inner viewport: 0.60, 7.70, 5.70, 6.74
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.02, "left", 0.78, "half", "##Physics##  h0 " + fixed$(initial_height_m, 2) + " m | v0 " + fixed$(initial_velocity_m_s, 2) + " m/s | g " + fixed$(gravity_m_s2, 2) + " m/s2 | bounce " + fixed$(bounce_coefficient, 2) + " | drag " + fixed$(drag_coefficient, 2)
    Text: 0.02, "left", 0.50, "half", "##Mapping##  " + mappingName$ + " | " + timeMapName$ + " | rebounds " + string$(reboundsDone) + " | envelope bounce markers " + string$(numEnvBounces) + " | reverse " + if reverse_envelope then "on" else "off" fi
    Text: 0.02, "left", 0.22, "half", "##Output##  audio " + fixed$(duration, 3) + " s | physics " + fixed$(physDur, 3) + " s | smoothing " + string$(smoothing_passes) + " passes | peak " + fixed$(outPeakViz, 3)
    Colour: "Black"
    Draw inner box
    # Restore complete page for Picture export / clipboard.
    pageHeight = 7.00
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line

endif

# ============================================================
# CLEANUP & OUTPUT
# ============================================================

removeObject: envSound

selectObject: result

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE: ", selected$("Sound")
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Physics summary:"
appendInfoLine: "  Rebounds: ", reboundsDone, " | Ground contacts: ", groundContacts
appendInfoLine: "  Physics duration: ", fixed$(physDur, 3), " s"
appendInfoLine: "  Audio duration:   ", fixed$(duration, 3), " s"
appendInfoLine: "  Mapping: ", mappingName$
appendInfoLine: "  Time mapping: ", timeMapName$
if reverse_envelope
    appendInfoLine: "  Envelope: REVERSED"
endif
if truncated
    appendInfoLine: "  NOTE: physics simulation was truncated at the time cap."
endif

if play
    appendInfoLine: ""
    appendInfoLine: "Playing..."
    Play
endif

selectObject: result
