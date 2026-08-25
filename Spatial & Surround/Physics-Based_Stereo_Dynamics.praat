# ============================================================
# Praat AudioTools - Physics-Based_Stereo_Dynamics.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.6.2 (2026)
# v0.6.2 (2026): REPORTING/VISUALIZATION CORRECTION ONLY - stop the physics
#   integrator at the final audio sample, and draw the motion path with the
#   same [-1,+1] pan clamp used by the audio. DSP mapping/output unchanged.
# v0.6.1 (2026): visualization frame alignment fix.
# v0.6 (2026): SPATIAL VISUALIZATION STANDARDIZATION ONLY - label rails, compact summary, typography; DSP unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   A ballistic bouncing-ball simulation drives amplitude and stereo
#   position. Height and speed map to level; horizontal motion maps to
#   pan; an optional geometric distance model ties level to how far the
#   ball actually is from the listener.
#
#   What is genuinely simulated: vertical ballistic motion under
#   constant gravity, with impacts resolved analytically inside the
#   timestep and a coefficient of restitution at each bounce.
#   What is not: the horizontal motion, which is a prescribed pan path,
#   not a solved trajectory. Spring and Pendulum are ballistic height
#   with a sinusoidal pan, not spring or pendulum equations - they are
#   named accordingly.
#
# Changelog v0.6 (2026):
#   - The form was 32 rows and ran off the screen. It is now 15, with
#     nothing removed: groups of numbers moved into sentence fields read
#     with extractNumber, and menus that always travelled together were
#     merged.
#       Physics    h0= v0= grav= rest= bounces=   (was 5 rows)
#       Pan_path   start= end= cycles=            (was 3 rows)
#       Geometry   width= listener= ref=          (was 3 rows)
#       Level_model now carries the lateral/geometric choice AND the
#         louder-at-centre / louder-at-edges direction (was 2 rows)
#       Mapping now carries the control/energy model AND the quantity
#         (was 2 rows)
#       Mix_and_output_gain carries the mix law AND the gain policy
#         (was 2 rows)
#     Keep the key= words in the sentence fields; only the numbers
#     matter, and order and spacing are free. A missing or malformed key
#     falls back to its default and is reported rather than feeding an
#     undefined value into the simulation.
#     Peak_target is fixed at 0.99, which was its default.
#
# Changelog v0.4 (2026):
#   - FIX (critical, and not in the review): THE PANNING DID ALMOST
#     NOTHING. Each channel was multiplied by its tier with
#     Multiply: "yes", which rescales that channel to a peak of about
#     0.99 - independently of the other. Whatever level difference the
#     pan law had just created was divided straight back out: at pan
#     -0.9 the intended L/R difference is 12.79 dB, and after two
#     separate normalisations what survived was the ratio of the two
#     channels' PEAKS, not the pan. Now Multiply: "no", with one shared
#     gain applied afterwards. This is the same bug that was in
#     8-Channel Movements v0.3.
#   - FIX: velocity was normalised against v0 + g*D, where D is the
#     LENGTH OF THE AUDIO FILE. That is not a physical maximum and it
#     grows without limit: with the default preset the ball's true peak
#     speed is 7.715 m/s, but the divisor is 25.6 on a 2 s file and
#     594 on a 60 s one, so the Velocity and Combined mappings peaked
#     at amplitude 0.30 and 0.013 respectively - nearly silent before
#     the final normalisation rescued them. Both height and velocity
#     are now normalised against the maxima MEASURED in the completed
#     simulation.
#   - FIX: height was normalised against Initial_height, but every
#     preset starts with upward velocity, so the ball rises above it
#     immediately: the apex is h0 + v0^2/(2g), which for the default is
#     3.037 m against h0 = 1.2, i.e. a gain of 2.53 before
#     Amplitude_scale. Ping Pong Frenzy reaches 7.38.
#   - FIX: the oscillating pan formula was
#     panStart + (panEnd - panStart) * sin(...), which oscillates about
#     panStart rather than between the two values. For -1 to +1 it
#     spans -3 to +1, and half the trajectory sits below -1 and is
#     clipped to hard left. It is now centre + halfRange * sin(...),
#     which really does stay between the endpoints. The comment also
#     claimed 4 cycles while sin(4*pi*q) completes 2; the cycle count
#     is now a form field and is honoured.
#   - FIX: impacts were detected only after the ball had already passed
#     through the ground, and the overshoot was never given back. At
#     the 2000-point cap a 60 s file has a 30 ms step, during which a
#     ball at 6 m/s travels 180 mm - so the bounce time and the energy
#     lost to it carried an error that depended on the file length.
#     The impact time is now solved exactly inside the step from
#     0.5*g*tau^2 - v*tau - h = 0, the bounce applied at tau, and the
#     remainder of the step integrated with the new velocity. The
#     simulation also runs on its own fixed grid rather than one tied
#     to the audio length, so the physics no longer changes with the
#     file.
#   - FIX: no bounds on the physics parameters. Custom accepted
#     negative height, negative or zero gravity, and a restitution
#     coefficient outside [0, 1] - above 1 the ball gains energy at
#     every bounce, below 0 it leaves the ground in the wrong
#     direction. All are validated; e > 1 is allowed but reported as a
#     superelastic, non-physical mode.
#   - FIX: attenuation used the UNCLAMPED pan, while the audio used the
#     clamped one. Water Skipping Stone ends at pan 1.5, so its image
#     was pinned hard right while its level kept responding to motion
#     beyond the speaker. Both now read the same position.
#   - FIX: stereo input was never panned. The left envelope was applied
#     to the source's own left channel and the right to its right, so a
#     sound sitting only on the right could not move left - it could
#     only get quieter. That is balance modulation. Input now downmixes
#     to mono by default, which is what a point-source ball needs, with
#     the old behaviour as an explicit option. Sources with more than
#     two channels were silently reduced to the first two; they are now
#     downmixed or rejected.
#   - FIX: the time domain was not normalised to 0 while the tiers were
#     always built from 0.
#   - FIX: the final Scale peak always rescaled to 0.99, which made
#     Amplitude_scale nearly meaningless at 100% wet - the uniform
#     factor it applied was divided straight back out - and erased the
#     level differences between presets. Output_gain_handling now
#     offers Attenuate only (the default for a physical tool), Peak, or
#     None.
#   - FIX: the amplitude floor of 0.001 is -60 dB, so the sound never
#     fully stopped even after the ball came to rest. It is now -120 dB,
#     present only to keep log10 defined, and is described as such.
#   - NEW: Mapping_model. Control mappings are the v0.3 curves under
#     accurate names (height, absolute speed, their average). Energy
#     mappings are the physical quantities: Ep = g*h, Ek = v^2/2,
#     E = Ep + Ek, each normalised to the simulation maximum, with
#     amplitude taken as sqrt(E/Emax) since acoustic energy goes as the
#     square of pressure. v0.3 labelled its control curves "potential
#     energy" and "kinetic energy" while computing h and |v|, and
#     called their mean "total mechanical energy", which it is not.
#   - NEW: an optional geometric distance model. Centre_attenuation
#     works on |pan| alone and ignores height entirely, so it is not a
#     distance - it is a lateral-position weighting, and is named that.
#     With a stage half-width and a listener distance the script can
#     instead compute a real distance,
#     d = sqrt((pan*W)^2 + h^2 + z0^2), and apply d0/max(d,d0).
#   - NEW: equal-power wet/dry as an option. The linear crossfade dips
#     in the middle when the two signals are similar and combs when
#     they are not.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select a Sound object first."
endif

form Physics-Based Stereo Dynamics v0.6.2
    optionmenu Preset: 2
        option Custom (use the three sentence fields below)
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
        option Spring Oscillation (ballistic height, sine pan)
        option Pendulum Swing (ballistic height, wide sine pan)
        option Rolling Downhill (ballistic, L to R)
    comment Custom only. Keep the key= words; only the numbers matter.
    sentence Physics h0=1.2 v0=6.0 grav=9.8 rest=0.75 bounces=8
    sentence Pan_path start=-0.9 end=0.9 cycles=2
    optionmenu Pan_motion: 1
        option Linear (start -> end)
        option Oscillating (sine between start and end)
    comment Level, mapping, output
    optionmenu Level_model: 1
        option Lateral weighting, louder at centre (uses |pan| only)
        option Lateral weighting, louder at edges (uses |pan| only)
        option Geometric distance (uses pan AND height)
    real Attenuation_amount 0.3
    sentence Geometry width=3.0 listener=4.0 ref=1.0
    optionmenu Mapping: 3
        option Height (control curve)
        option Speed (control curve)
        option Height and speed, mean (control curve)
        option Potential energy g*h
        option Kinetic energy v^2/2
        option Total mechanical energy
    real Amplitude_scale 1.0
    optionmenu Input_handling: 1
        option Downmix to mono and pan (true panning)
        option Preserve stereo, modulate balance
    real Mix_percent 100
    optionmenu Mix_and_output_gain: 1
        option Equal-power mix, attenuate only
        option Equal-power mix, peak normalise
        option Equal-power mix, no gain change
        option Linear mix, attenuate only
        option Linear mix, peak normalise
        option Linear mix, no gain change
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# UNPACK THE COMPACT FORM
# ============================================================
# v0.6: the v0.4 form was 32 rows and ran off the screen. Nothing was
# dropped - grouped numbers moved into sentence fields read with
# extractNumber, and related menus were merged. 32 rows -> 15.
# extractNumber finds the number after each key, so the keys must stay
# in the text; their order and any extra spacing do not matter.

initial_height = extractNumber(physics$, "h0=")
initial_velocity = extractNumber(physics$, "v0=")
gravity = extractNumber(physics$, "grav=")
bounce_coefficient = extractNumber(physics$, "rest=")
number_of_bounces = extractNumber(physics$, "bounces=")
pan_start = extractNumber(pan_path$, "start=")
pan_end = extractNumber(pan_path$, "end=")
pan_cycles = extractNumber(pan_path$, "cycles=")
stage_half_width_m = extractNumber(geometry$, "width=")
listener_distance_m = extractNumber(geometry$, "listener=")
reference_distance_m = extractNumber(geometry$, "ref=")

# A missing or malformed key yields undefined, so fall back rather than
# poisoning the simulation with it.
parseFailed = 0
if initial_height = undefined
    initial_height = 1.2
    parseFailed = 1
endif
if initial_velocity = undefined
    initial_velocity = 6.0
    parseFailed = 1
endif
if gravity = undefined
    gravity = 9.8
    parseFailed = 1
endif
if bounce_coefficient = undefined
    bounce_coefficient = 0.75
    parseFailed = 1
endif
if number_of_bounces = undefined
    number_of_bounces = 8
    parseFailed = 1
endif
number_of_bounces = round(number_of_bounces)
if number_of_bounces < 0
    number_of_bounces = 0
endif
if pan_start = undefined
    pan_start = -0.9
    parseFailed = 1
endif
if pan_end = undefined
    pan_end = 0.9
    parseFailed = 1
endif
if pan_cycles = undefined or pan_cycles <= 0
    pan_cycles = 2
    parseFailed = 1
endif
if stage_half_width_m = undefined or stage_half_width_m <= 0
    stage_half_width_m = 3.0
    parseFailed = 1
endif
if listener_distance_m = undefined or listener_distance_m <= 0
    listener_distance_m = 4.0
    parseFailed = 1
endif
if reference_distance_m = undefined or reference_distance_m <= 0
    reference_distance_m = 1.0
    parseFailed = 1
endif

# Level_model carries both the model and, for the lateral one, its
# direction - v0.4 spent two rows on that.
if level_model = 3
    distance_model = 2
    attenuation_direction = 1
else
    distance_model = 1
    attenuation_direction = level_model
endif
center_attenuation = attenuation_amount

# One Mapping menu now carries both the model and the quantity.
if mapping <= 3
    mapping_model = 1
else
    mapping_model = 2
endif
mappingChoice = mapping
if mappingChoice > 3
    mappingChoice = mappingChoice - 3
endif
mapping = mappingChoice

# One menu carries the mix law and the output gain policy.
if mix_and_output_gain <= 3
    mix_law = 1
    output_gain_handling = mix_and_output_gain
else
    mix_law = 2
    output_gain_handling = mix_and_output_gain - 3
endif
peak_target = 0.99

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
    panCycles        = pan_cycles
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
    panCycles = 2
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
    panCycles = 2
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
    panCycles = 2
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
    panCycles = 2
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
    panCycles = 2
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
    panCycles = 2
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
    panCycles = 2
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
    panCycles = 2
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
    panCycles = 2
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
    panCycles = 2
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
    panCycles = 2
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
    panCycles = 2
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
    panCycles = 2
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
    panCycles = 2
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
    panCycles = 2
    centerAtten = 0.5
    attenDir = 1
    mappingMode = 2
    ampScale = 1.3
    presetName$ = "Rolling_Downhill"
endif

# Resolve labels
if panMotion = 1
    panMotionName$ = "Linear"
else
    panMotionName$ = "Oscillating"
endif
if attenDir = 1
    attenDirName$ = "LouderAtCentre"
else
    attenDirName$ = "LouderAtEdges"
endif
if mapping_model = 1
    if mappingMode = 1
        mappingName$ = "Height (control)"
    elsif mappingMode = 2
        mappingName$ = "Speed (control)"
    else
        mappingName$ = "Height+Speed mean (control)"
    endif
else
    if mappingMode = 1
        mappingName$ = "Potential energy g*h"
    elsif mappingMode = 2
        mappingName$ = "Kinetic energy v^2/2"
    else
        mappingName$ = "Total mechanical energy"
    endif
endif

# ============================================================
# PARAMETER BOUNDS
# ============================================================
# v0.4: Custom accepted values that break the model outright.
boundNotes = 0
if initialHeight < 0
    initialHeight = 0
    boundNotes = 1
endif
if gravityVal <= 0
    gravityVal = 9.8
    boundNotes = 1
endif
superElastic = 0
if bounceCoef < 0
    bounceCoef = 0
    boundNotes = 1
endif
if bounceCoef > 1
    superElastic = 1
endif
if centerAtten < 0
    centerAtten = 0
    boundNotes = 1
endif
if ampScale < 0
    ampScale = 0
    boundNotes = 1
endif
if peak_target <= 0 or peak_target > 1
    peak_target = 0.99
endif
if initialHeight = 0 and initialVelocity <= 0
    exitScript: "The ball starts on the ground with no upward velocity, so"
        ... + " nothing will happen. Raise Initial_height or Initial_velocity."
endif

panClipWarn = 0
if panStart < -1 or panStart > 1 or panEnd < -1 or panEnd > 1
    panClipWarn = 1
endif

if mix_percent < 0
    mixPercent = 0
elsif mix_percent > 100
    mixPercent = 100
else
    mixPercent = mix_percent
endif
mixFrac = mixPercent / 100
if mix_law = 1
    wet_level = sin(mixFrac * pi / 2)
    dry_level = cos(mixFrac * pi / 2)
    mixLaw$ = "equal power"
else
    wet_level = mixFrac
    dry_level = 1 - mixFrac
    mixLaw$ = "linear"
endif

# ============================================================
# SOURCE: mono working copy, time domain starting at 0
# ============================================================
original = selected("Sound")
originalName$ = selected$("Sound")
selectObject: original
sr = Get sampling frequency
nChannels = Get number of channels
srcT1 = Get end time

if nChannels > 2 and input_handling = 2
    input_handling = 1
    forcedDownmix = 1
else
    forcedDownmix = 0
endif

if input_handling = 1
    if nChannels > 1
        selectObject: original
        Convert to mono
        srcID = selected("Sound")
    else
        selectObject: original
        Copy: "pb_src"
        srcID = selected("Sound")
    endif
    inputNote$ = "downmixed to mono and panned"
else
    selectObject: original
    Copy: "pb_src"
    srcID = selected("Sound")
    if nChannels = 1
        inputNote$ = "mono source, panned"
    else
        inputNote$ = "stereo preserved, BALANCE modulated (not panned)"
    endif
endif

selectObject: srcID
workT0 = Get start time
if workT0 <> 0
    selectObject: srcID
    shiftedID = Extract part: workT0, srcT1, "rectangular", 1.0, "no"
    removeObject: srcID
    srcID = shiftedID
endif
selectObject: srcID
Rename: "pb_src"
duration = Get total duration

if duration <= 0
    removeObject: srcID
    exitScript: "Source has zero duration."
endif

# ============================================================
# PHYSICS SIMULATION
# ============================================================
# v0.4: the simulation runs on its own fixed grid, not one derived from
# the audio length, and each impact is solved analytically inside the
# step. v0.3 detected a bounce only after the ball had already passed
# below ground, threw away the overshoot, and used a step that grew
# with the file - 30 ms at 60 s, during which a ball at 6 m/s covers
# 180 mm - so the bounce times depended on the file duration.

simRate = 2000
nSim = round(duration * simRate)
if nSim < 400
    nSim = 400
endif
if nSim > 400000
    nSim = 400000
    simRate = nSim / duration
endif
dt = duration / (nSim - 1)

time# = zero#(nSim)
height# = zero#(nSim)
speed# = zero#(nSim)
pan# = zero#(nSim)

h = initialHeight
v = initialVelocity
bouncesDone = 0
maxHeightSeen = 0
maxSpeedSeen = 0
firstImpactTime = -1
lastImpactTime = -1

for i from 1 to nSim
    t = (i - 1) * dt
    time#[i] = t
    height#[i] = h
    speed#[i] = abs(v)
    if h > maxHeightSeen
        maxHeightSeen = h
    endif
    if abs(v) > maxSpeedSeen
        maxSpeedSeen = abs(v)
    endif

    # --- advance one step, resolving any impact inside it ---
    # v0.6.2: the last stored sample is already at t = duration. Do not
    # integrate one extra dt beyond the audio and accidentally count an
    # impact that the rendered sound can never contain.
    if i < nSim
        remaining = dt
        while remaining > 1e-12
            # Exact ballistic step: h(tau) = h + v*tau - g*tau^2/2
            hEnd = h + v * remaining - 0.5 * gravityVal * remaining * remaining
            if hEnd >= 0 or bouncesDone >= numBounces
                if hEnd < 0
                    hEnd = 0
                    v = 0
                else
                    v = v - gravityVal * remaining
                endif
                h = hEnd
                remaining = 0
            else
                # Solve 0.5*g*tau^2 - v*tau - h = 0 for the first positive root
                disc = v * v + 2 * gravityVal * h
                if disc < 0
                    disc = 0
                endif
                tau = (v + sqrt(disc)) / gravityVal
                if tau < 0
                    tau = 0
                endif
                if tau > remaining
                    tau = remaining
                endif
                vImpact = v - gravityVal * tau
                h = 0
                v = -vImpact * bounceCoef
                bouncesDone = bouncesDone + 1
                if firstImpactTime < 0
                    firstImpactTime = t + (dt - remaining) + tau
                endif
                lastImpactTime = t + (dt - remaining) + tau
                remaining = remaining - tau
                if abs(v) < 1e-6
                    v = 0
                    h = 0
                    remaining = 0
                endif
            endif
        endwhile
    endif
endfor

if maxHeightSeen < 1e-9
    maxHeightSeen = 1e-9
endif
if maxSpeedSeen < 1e-9
    maxSpeedSeen = 1e-9
endif

# Analytic check on the first impact speed, for the report
apexHeight = initialHeight
if initialVelocity > 0
    apexHeight = initialHeight + initialVelocity * initialVelocity / (2 * gravityVal)
endif
vImpactTheory = sqrt(initialVelocity * initialVelocity + 2 * gravityVal * initialHeight)

# ============================================================
# PAN PATH
# ============================================================
# v0.4: oscillate BETWEEN the endpoints. v0.3 used
# panStart + (panEnd - panStart)*sin(...), which oscillates ABOUT
# panStart: for -1 to +1 that spans -3 to +1, and half the trajectory
# was clipped to hard left. The cycle count is honoured too - v0.3's
# sin(4*pi*q) is 2 cycles, not the 4 its comment claimed.
panCentre = (panStart + panEnd) / 2
panHalf = (panEnd - panStart) / 2
for i from 1 to nSim
    q = (i - 1) / (nSim - 1)
    if panMotion = 2
        pan#[i] = panCentre + panHalf * sin(2 * pi * panCycles * q)
    else
        pan#[i] = panStart + (panEnd - panStart) * q
    endif
endfor

# ============================================================
# MAP PHYSICS TO AMPLITUDE AND PAN
# ============================================================
# v0.4: both quantities normalised against the maxima MEASURED in the
# completed simulation. v0.3 divided height by Initial_height, which
# every preset exceeds on the way up, and speed by v0 + g*duration,
# which is not a physical maximum and grows with the length of the
# audio file.

maxEp = gravityVal * maxHeightSeen
maxEk = 0.5 * maxSpeedSeen * maxSpeedSeen
maxEtot = maxEp + maxEk
if maxEp < 1e-12
    maxEp = 1e-12
endif
if maxEk < 1e-12
    maxEk = 1e-12
endif
if maxEtot < 1e-12
    maxEtot = 1e-12
endif

# -120 dB, present only so log10 stays defined. v0.3 used 0.001, which
# is -60 dB, so the sound never fully stopped after the ball came to
# rest.
ampFloor = 1e-6

ampTrace# = zero#(nSim)
gainL# = zero#(nSim)
gainR# = zero#(nSim)
distTrace# = zero#(nSim)

tierL = Create IntensityTier: "pb_envL", 0, duration
tierR = Create IntensityTier: "pb_envR", 0, duration

for i from 1 to nSim
    t = time#[i]
    hh = height#[i]
    vv = speed#[i]
    pRaw = pan#[i]

    # v0.4: the audio and the level model now read the SAME position.
    # v0.3 clamped the pan for the audio but fed the unclamped value to
    # the attenuation, so Water Skipping Stone (pan_end 1.5) was pinned
    # hard right while its level kept responding to motion beyond the
    # speaker.
    p = pRaw
    if p < -1
        p = -1
    endif
    if p > 1
        p = 1
    endif

    if mapping_model = 1
        # Control mappings: the v0.3 curves, correctly named.
        if mappingMode = 1
            amp = hh / maxHeightSeen
        elsif mappingMode = 2
            amp = vv / maxSpeedSeen
        else
            amp = (hh / maxHeightSeen + vv / maxSpeedSeen) / 2
        endif
    else
        # Energy mappings. Acoustic energy goes as pressure squared, so
        # amplitude is the square root of normalised energy.
        ep = gravityVal * hh
        ek = 0.5 * vv * vv
        if mappingMode = 1
            amp = sqrt(ep / maxEp)
        elsif mappingMode = 2
            amp = sqrt(ek / maxEk)
        else
            amp = sqrt((ep + ek) / maxEtot)
        endif
    endif

    # --- level versus position ---
    if distance_model = 1
        # Lateral-position weighting. This uses |pan| alone and ignores
        # height entirely, so it is not a distance.
        dd = abs(p)
        if attenDir = 1
            distFactor = 1 / (1 + centerAtten * dd)
        else
            distFactor = 1 / (1 + centerAtten * (1 - dd))
        endif
        distTrace#[i] = dd
    else
        # v0.4: a real geometric distance, so height finally matters.
        xm = p * stage_half_width_m
        dGeo = sqrt(xm * xm + hh * hh + listener_distance_m * listener_distance_m)
        if dGeo < reference_distance_m
            dGeo = reference_distance_m
        endif
        distFactor = reference_distance_m / dGeo
        distTrace#[i] = dGeo
    endif

    amp = amp * ampScale * distFactor
    if amp < 0
        amp = 0
    endif
    ampTrace#[i] = amp

    panNorm = (p + 1) / 2
    ampL = amp * sqrt(1 - panNorm)
    ampR = amp * sqrt(panNorm)
    gainL#[i] = ampL
    gainR#[i] = ampR

    if ampL < ampFloor
        ampL = ampFloor
    endif
    if ampR < ampFloor
        ampR = ampFloor
    endif

    selectObject: tierL
    Add point: t, 20 * log10(ampL)
    selectObject: tierR
    Add point: t, 20 * log10(ampR)
endfor

# ============================================================
# APPLY
# ============================================================
selectObject: srcID
nCh = Get number of channels
if nCh = 1
    selectObject: srcID
    Copy: "pb_L"
    chL = selected("Sound")
    selectObject: srcID
    Copy: "pb_R"
    chR = selected("Sound")
else
    selectObject: srcID
    Extract one channel: 1
    chL = selected("Sound")
    selectObject: srcID
    Extract one channel: 2
    chR = selected("Sound")
endif

# v0.4: Multiply "no". v0.3 used "yes", which rescales each channel to
# a peak of about 0.99 independently of the other - so the level
# difference the pan law had just created was divided straight back
# out. At pan -0.9 the intended difference is 12.79 dB; what survived
# was the ratio of the two channels' peaks, not the pan.
selectObject: chL
plusObject: tierL
Multiply: "no"
chLmod = selected("Sound")

selectObject: chR
plusObject: tierR
Multiply: "no"
chRmod = selected("Sound")

selectObject: chLmod, chRmod
Combine to stereo
wetSound = selected("Sound")

removeObject: chL, chR, chLmod, chRmod, tierL, tierR

# ============================================================
# WET / DRY
# ============================================================
if dry_level > 0.0001
    selectObject: srcID
    Copy: "pb_dry"
    dryCopy = selected("Sound")
    # The formula below refers to this object BY NAME, so the stereo
    # version built underneath has to end up carrying that name.
    selectObject: dryCopy
    nChDry = Get number of channels
    if nChDry = 1
        # v0.4: a mono dry signal is placed at centre with the same
        # constant-power law the wet path uses, so the two are
        # comparable rather than the dry being two full-level copies.
        selectObject: dryCopy
        Formula: "self * " + fixed$(1 / sqrt(2), 10)
        selectObject: dryCopy
        Copy: "pb_dryR"
        dryR = selected("Sound")
        selectObject: dryCopy, dryR
        Combine to stereo
        dryStereo = selected("Sound")
        removeObject: dryCopy, dryR
        dryCopy = dryStereo
        selectObject: dryCopy
        Rename: "pb_dry"
    endif

    selectObject: wetSound
    mixFml$ = "self * " + fixed$(wet_level, 10) + " + Sound_pb_dry[row, col] * " + fixed$(dry_level, 10)
    Formula: mixFml$
    removeObject: dryCopy
endif

selectObject: wetSound
Rename: originalName$ + "_" + presetName$
result = selected("Sound")
prePeak = Get absolute extremum: 0, 0, "None"

# v0.4: attenuate-only by default. v0.3 always rescaled to 0.99, which
# made Amplitude_scale nearly meaningless at 100% wet and flattened the
# level differences between presets.
normGain = 1
if output_gain_handling = 1
    if prePeak > peak_target and prePeak > 0
        normGain = peak_target / prePeak
    endif
    normMode$ = "attenuate only"
elsif output_gain_handling = 2
    if prePeak > 0
        normGain = peak_target / prePeak
    endif
    normMode$ = "peak (scaled to target)"
else
    normMode$ = "none"
endif
if normGain <> 1
    selectObject: result
    Formula: "self * " + fixed$(normGain, 10)
endif
selectObject: result
finalPeak = Get absolute extremum: 0, 0, "None"
finalDur = Get total duration
resultName$ = selected$("Sound")

# ============================================================
# REPORT
# ============================================================
writeInfoLine: "=== Physics-Based Stereo Dynamics v0.6.2 ==="
appendInfoLine: "Input: ", originalName$, "  (", fixed$(duration, 3), " s, ",
    ... nChannels, " ch @ ", sr, " Hz)"
appendInfoLine: "Source handling: ", inputNote$
if forcedDownmix = 1
    appendInfoLine: "  NOTE: a ", nChannels, "-channel source cannot be balance-modulated"
    appendInfoLine: "        as a stereo pair, so it was downmixed."
endif
if input_handling = 2 and nChannels = 2
    appendInfoLine: "  WARNING: each envelope gates its own original channel, so a"
    appendInfoLine: "  sound sitting only on one side cannot move across - it can only"
    appendInfoLine: "  get quieter. That is balance modulation, not panning."
endif
appendInfoLine: "Preset: ", presetName$
if parseFailed = 1 and preset = 1
    appendInfoLine: "  NOTE: one or more key= entries in the sentence fields could not"
    appendInfoLine: "        be read and fell back to their defaults. Keep the key words"
    appendInfoLine: "        (h0= v0= grav= rest= bounces=, start= end= cycles=,"
    appendInfoLine: "        width= listener= ref=); only the numbers should change."
endif
appendInfoLine: ""

appendInfoLine: "Physics: h0 ", fixed$(initialHeight, 3), " m, v0 ",
    ... fixed$(initialVelocity, 3), " m/s, g ", fixed$(gravityVal, 3),
    ... " m/s^2, e ", fixed$(bounceCoef, 3)
appendInfoLine: "  Simulation ", fixed$(simRate, 0), " Hz, dt ",
    ... fixed$(dt * 1000, 3), " ms, ", nSim, " steps"
appendInfoLine: "  Impacts are solved analytically inside the step from"
appendInfoLine: "  0.5*g*tau^2 - v*tau - h = 0, so bounce times do not depend on the"
appendInfoLine: "  step size. v0.3 detected them only after the ball had passed"
appendInfoLine: "  through the ground and discarded the overshoot."
appendInfoLine: "  Bounces: ", bouncesDone, " of ", numBounces, " requested"
if firstImpactTime >= 0
    appendInfoLine: "  First impact ", fixed$(firstImpactTime, 4), " s   last ",
        ... fixed$(lastImpactTime, 4), " s"
endif
appendInfoLine: "  Apex ", fixed$(apexHeight, 4), " m (h0 + v0^2/2g); measured max ",
    ... fixed$(maxHeightSeen, 4), " m"
appendInfoLine: "  First impact speed sqrt(v0^2 + 2*g*h0) = ",
    ... fixed$(vImpactTheory, 4), " m/s; measured max ",
    ... fixed$(maxSpeedSeen, 4), " m/s"
appendInfoLine: "  Energy retained per bounce e^2 = ",
    ... fixed$(bounceCoef * bounceCoef, 4)
if superElastic = 1
    appendInfoLine: "  NOTE: e > 1 is superelastic - the ball GAINS energy at every"
    appendInfoLine: "        bounce. Legal here as an effect, but not physical."
endif
if boundNotes = 1
    appendInfoLine: "  NOTE: one or more physics parameters were out of range and were"
    appendInfoLine: "        clamped."
endif
appendInfoLine: ""

appendInfoLine: "Normalisation of the mappings:"
appendInfoLine: "  Height by the MEASURED maximum ", fixed$(maxHeightSeen, 4), " m"
appendInfoLine: "    v0.3 used Initial_height ", fixed$(initialHeight, 3),
    ... ", which the ball exceeds on the way"
appendInfoLine: "    up: h/h0 would have peaked at ",
    ... fixed$(maxHeightSeen / max(initialHeight, 1e-9), 3)
appendInfoLine: "  Speed by the MEASURED maximum ", fixed$(maxSpeedSeen, 4), " m/s"
v03div = initialVelocity + gravityVal * duration
appendInfoLine: "    v0.3 used v0 + g*duration = ", fixed$(v03div, 2),
    ... ", not a physical maximum and"
appendInfoLine: "    growing with the file: amplitude would have peaked at ",
    ... fixed$(maxSpeedSeen / v03div, 4)
appendInfoLine: ""

appendInfoLine: "Mapping: ", mappingName$
if mapping_model = 2
    appendInfoLine: "  Energy model: Ep = g*h, Ek = v^2/2, E = Ep + Ek, each"
    appendInfoLine: "  normalised to the simulation maximum, amplitude = sqrt(E/Emax)"
    appendInfoLine: "  since acoustic energy goes as pressure squared."
    appendInfoLine: "  Max Ep ", fixed$(maxEp, 3), "   max Ek ", fixed$(maxEk, 3),
        ... "   max E ", fixed$(maxEtot, 3)
else
    appendInfoLine: "  Control model: the v0.3 curves. These are height and absolute"
    appendInfoLine: "  speed, NOT potential and kinetic energy, which is what v0.3"
    appendInfoLine: "  called them - and their mean is not total mechanical energy."
endif
appendInfoLine: "  Amplitude scale ", fixed$(ampScale, 3)
appendInfoLine: "  Amplitude floor ", fixed$(20 * log10(ampFloor), 0),
    ... " dB, present only to keep log10 defined."
appendInfoLine: ""

appendInfoLine: "Pan: ", fixed$(panStart, 2), " -> ", fixed$(panEnd, 2),
    ... "  (", panMotionName$, ")"
if panMotion = 2
    appendInfoLine: "  ", fixed$(panCycles, 2), " cycle(s), oscillating between the two"
    appendInfoLine: "  endpoints about their centre ", fixed$(panCentre, 3),
        ... " with half-range ", fixed$(panHalf, 3)
    appendInfoLine: "  v0.3 oscillated ABOUT panStart, so -1 to +1 spanned -3 to +1"
    appendInfoLine: "  and half the path was clipped to hard left."
endif
if panClipWarn = 1
    appendInfoLine: "  NOTE: an endpoint lies outside +/-1. The pan saturates at the"
    appendInfoLine: "        speakers, and in v0.4 the level model saturates with it -"
    appendInfoLine: "        v0.3 let the level keep responding past the speaker."
endif
appendInfoLine: ""

if distance_model = 1
    appendInfoLine: "Level vs position: lateral-position weighting (",
        ... attenDirName$, "), amount ", fixed$(centerAtten, 2)
    appendInfoLine: "  This reads |pan| only. Height plays no part, so it is a"
    appendInfoLine: "  position weighting rather than a distance."
else
    appendInfoLine: "Level vs position: geometric distance"
    appendInfoLine: "  d = sqrt((pan*", fixed$(stage_half_width_m, 2), ")^2 + h^2 + ",
        ... fixed$(listener_distance_m, 2), "^2), gain = ",
        ... fixed$(reference_distance_m, 2), "/max(d, ",
        ... fixed$(reference_distance_m, 2), ")"
    appendInfoLine: "  Height now affects the level, which it never did in v0.3."
endif
appendInfoLine: ""

appendInfoLine: "Mix: ", fixed$(mixPercent, 0), "% wet, ", mixLaw$,
    ... "   (wet ", fixed$(wet_level, 3), ", dry ", fixed$(dry_level, 3), ")"
appendInfoLine: "Output gain: ", normMode$
appendInfoLine: "  Peak ", fixed$(prePeak, 4), " -> ", fixed$(finalPeak, 4),
    ... "  (gain x", fixed$(normGain, 4), ")"
if output_gain_handling = 1
    appendInfoLine: "  Attenuate-only keeps Amplitude_scale and the attenuation"
    appendInfoLine: "  meaningful. v0.3 always rescaled to the target, which divided"
    appendInfoLine: "  a uniform Amplitude_scale straight back out at 100% wet."
endif
appendInfoLine: ""
appendInfoLine: "The vertical motion is genuinely simulated. The horizontal motion is"
appendInfoLine: "a prescribed pan path, not a solved trajectory - Spring and Pendulum"
appendInfoLine: "are ballistic height with a sinusoidal pan, not spring or pendulum"
appendInfoLine: "equations."

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================
if draw_visualization
    Erase all

    maxAmpTrace = 0
    for i from 1 to nSim
        if ampTrace#[i] > maxAmpTrace
            maxAmpTrace = ampTrace#[i]
        endif
    endfor
    if maxAmpTrace < 1e-6
        maxAmpTrace = 1e-6
    endif

    nDraw = 800
    if nDraw > nSim
        nDraw = nSim
    endif

    # ----------------------------------------------------------
    # TITLE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##PHYSICS-BASED STEREO DYNAMICS v0.6.2##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    if mapping_model = 1
        modelTag$ = "control"
    else
        modelTag$ = "energy"
    endif
    Text: 0.5, "centre", -0.22, "half",
        ... originalName$
        ... + "  |  " + presetName$
        ... + "  |  " + string$(bouncesDone) + " bounces, e=" + fixed$(bounceCoef, 2)
        ... + "  |  " + mappingName$ + " (" + modelTag$ + ")"
        ... + "  |  " + panMotionName$ + " pan"

    # ----------------------------------------------------------
    # PANEL A: MOTION PATH, pan vs height
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.72, 3.28
    Select inner viewport: 0.55, 7.75, 0.82, 3.05

    hTop = maxHeightSeen * 1.18
    if hTop < 0.05
        hTop = 0.05
    endif
    Axes: -1.35, 1.35, -hTop * 0.14, hTop
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.35, 1.35, -hTop * 0.14, hTop

    # Ground
    Colour: "{0.55, 0.45, 0.35}"
    Line width: 2
    Draw line: -1.35, 0, 1.35, 0
    Line width: 1

    # Speakers and listener
    Paint circle (mm): "{0.45, 0.45, 0.50}", -1.15, hTop * 0.06, 2.6
    Paint circle (mm): "{0.45, 0.45, 0.50}", 1.15, hTop * 0.06, 2.6
    Font size: 6
    Colour: "{0.35, 0.35, 0.40}"
    Text: -1.15, "centre", hTop * 0.13, "half", "L"
    Text: 1.15, "centre", hTop * 0.13, "half", "R"
    Paint circle (mm): "{0.22, 0.62, 0.30}", 0, -hTop * 0.07, 2.2
    Text: 0, "centre", -hTop * 0.125, "half", "listener"

    Colour: "{0.88, 0.88, 0.88}"
    Draw line: 0, 0, 0, hTop

    # Path, time-graded, thickness by amplitude
    for k from 2 to nDraw
        i1 = round((k - 2) / (nDraw - 1) * (nSim - 1)) + 1
        i2 = round((k - 1) / (nDraw - 1) * (nSim - 1)) + 1
        if i1 < 1
            i1 = 1
        endif
        if i2 > nSim
            i2 = nSim
        endif
        frac = (k - 1) / (nDraw - 1)
        pathCol$ = "{" + fixed$(0.20 + frac * 0.65, 2) + ", " + fixed$(0.45 - frac * 0.20, 2) + ", " + fixed$(0.80 - frac * 0.55, 2) + "}"
        Colour: pathCol$
        # v0.6.2: draw the same clamped pan position used by the DSP.
        p1 = pan#[i1]
        p2 = pan#[i2]
        if p1 < -1
            p1 = -1
        endif
        if p1 > 1
            p1 = 1
        endif
        if p2 < -1
            p2 = -1
        endif
        if p2 > 1
            p2 = 1
        endif
        Draw line: p1, height#[i1], p2, height#[i2]
    endfor

    # Impact markers, sized by amplitude at impact
    for k from 1 to nDraw
        i1 = round((k - 1) / (nDraw - 1) * (nSim - 1)) + 1
        if i1 < 2
            i1 = 2
        endif
        if i1 > nSim
            i1 = nSim
        endif
        if height#[i1] < hTop * 0.002 and speed#[i1] > maxSpeedSeen * 0.05
            rr = 1.0 + 3.5 * ampTrace#[i1] / maxAmpTrace
            pp = pan#[i1]
            if pp < -1
                pp = -1
            endif
            if pp > 1
                pp = 1
            endif
            Paint circle (mm): "{0.85, 0.35, 0.20}", pp, 0, rr
        endif
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Marks left: 3, "yes", "yes", "no"
    Select outer viewport: 0.08, 0.52, 0.72, 3.28
    Select inner viewport: 0.08, 0.52, 0.74, 3.26
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Height (m)"
    Select outer viewport: 0, 8, 0.72, 3.28
    Select inner viewport: 0.55, 7.75, 0.82, 3.05
    Axes: -1.35, 1.35, -hTop * 0.14, hTop
    Text bottom: "yes", "Pan  (-1 left, +1 right)   —   dots = impacts, size = amplitude"

    # ----------------------------------------------------------
    # PANEL B: HEIGHT AND SPEED VS TIME
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 3.58, 5.00
    Select inner viewport: 0.55, 4.00, 3.66, 4.76

    Axes: 0, duration, 0, 1.08
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, duration, 0, 1.08

    Line width: 1.5
    Colour: "{0.25, 0.45, 0.78}"
    for k from 2 to nDraw
        i1 = round((k - 2) / (nDraw - 1) * (nSim - 1)) + 1
        i2 = round((k - 1) / (nDraw - 1) * (nSim - 1)) + 1
        Draw line: time#[i1], height#[i1] / maxHeightSeen, time#[i2], height#[i2] / maxHeightSeen
    endfor
    Colour: "{0.85, 0.45, 0.20}"
    for k from 2 to nDraw
        i1 = round((k - 2) / (nDraw - 1) * (nSim - 1)) + 1
        i2 = round((k - 1) / (nDraw - 1) * (nSim - 1)) + 1
        Draw line: time#[i1], speed#[i1] / maxSpeedSeen, time#[i2], speed#[i2] / maxSpeedSeen
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 6
    Marks left: 3, "yes", "yes", "no"
    Font size: 6
    Select outer viewport: 0.08, 0.52, 3.58, 5.00
    Select inner viewport: 0.08, 0.52, 3.60, 4.98
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Normalised"
    Select outer viewport: 0, 4.2, 3.58, 5.00
    Select inner viewport: 0.55, 4, 3.66, 4.76
    Axes: 0, duration, 0, 1.08
    Text bottom: "yes", "Height (blue) and speed (orange), each / measured max"

    # ----------------------------------------------------------
    # PANEL C: CHANNEL GAINS
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 3.58, 5.00
    Select inner viewport: 4.55, 7.75, 3.66, 4.76

    gTop = maxAmpTrace * 1.12
    Axes: 0, duration, 0, gTop
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, duration, 0, gTop

    Line width: 1.5
    for k from 2 to nDraw
        i1 = round((k - 2) / (nDraw - 1) * (nSim - 1)) + 1
        i2 = round((k - 1) / (nDraw - 1) * (nSim - 1)) + 1
        Colour: "{0.25, 0.50, 0.82}"
        Draw line: time#[i1], gainL#[i1], time#[i2], gainL#[i2]
        Colour: "{0.82, 0.45, 0.25}"
        Draw line: time#[i1], gainR#[i1], time#[i2], gainR#[i2]
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 6
    Marks left: 3, "yes", "yes", "no"
    Font size: 6
    Select outer viewport: 4.02, 4.4, 3.58, 5.00
    Select inner viewport: 4.02, 4.4, 3.60, 4.98
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Gain"
    Select outer viewport: 4.2, 8, 3.58, 5.00
    Select inner viewport: 4.55, 7.75, 3.66, 4.76
    Axes: 0, duration, 0, gTop
    Text bottom: "yes", "Channel gains (blue L, orange R) — the pan law, preserved"

    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.30, 6.35
    Select inner viewport: 0.55, 7.75, 5.38, 6.12

    selectObject: result
    resPeak = Get absolute extremum: 0, 0, "None"
    if resPeak < 0.001
        resPeak = 0.001
    endif
    aMax = resPeak * 1.15
    Axes: 0, finalDur, -aMax, aMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDur, -aMax, aMax
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, finalDur, 0

    selectObject: result
    Extract one channel: 1
    vizL = selected("Sound")
    Colour: "{0.25, 0.50, 0.82}"
    Draw: 0, 0, -aMax, aMax, "no", "Curve"

    selectObject: result
    Extract one channel: 2
    vizR = selected("Sound")
    Colour: "{0.82, 0.45, 0.25}"
    Draw: 0, 0, -aMax, aMax, "no", "Curve"
    removeObject: vizL, vizR

    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.08, 0.52, 5.30, 6.35
    Select inner viewport: 0.08, 0.52, 5.32, 6.33
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Output"
    Select outer viewport: 0, 8, 5.30, 6.35
    Select inner viewport: 0.55, 7.75, 5.38, 6.12
    Axes: 0, finalDur, -aMax, aMax
    Text top: "no", "Output (blue = L, orange = R)"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL E: SUMMARY
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.65, 7.55
    Select inner viewport: 0.55, 7.75, 6.71, 7.49
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.70, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + originalName$
        ... + "  |  h0 " + fixed$(initialHeight, 2) + " m, v0 "
        ... + fixed$(initialVelocity, 2) + " m/s, g " + fixed$(gravityVal, 1)
        ... + "  |  e " + fixed$(bounceCoef, 2) + " (E x" + fixed$(bounceCoef^2, 2) + ")"
        ... + "  |  " + string$(bouncesDone) + " bounces"

    Text: 0.02, "left", 0.43, "half",
        ... "Max height " + fixed$(maxHeightSeen, 3) + " m"
        ... + "  |  Max speed " + fixed$(maxSpeedSeen, 3) + " m/s"
        ... + "  |  Sim " + fixed$(simRate, 0) + " Hz, dt " + fixed$(dt * 1000, 2) + " ms"
        ... + "  |  Pan " + fixed$(panStart, 2) + " to " + fixed$(panEnd, 2)
        ... + " (" + panMotionName$ + ")"

    if distance_model = 1
        distTag$ = "lateral weighting " + fixed$(centerAtten, 2)
    else
        distTag$ = "geometric distance, W=" + fixed$(stage_half_width_m, 1) + " z=" + fixed$(listener_distance_m, 1) + " m"
    endif
    Text: 0.02, "left", 0.16, "half",
        ... mappingName$
        ... + "  |  " + distTag$
        ... + "  |  " + fixed$(mixPercent, 0) + "% wet, " + mixLaw$
        ... + "  |  " + normMode$
        ... + "  |  Peak " + fixed$(prePeak, 3) + " -> " + fixed$(finalPeak, 3)

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Select outer viewport: 0, 8, 0, 7.65
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================
# CLEANUP
# ============================================================
removeObject: srcID

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Output: ", resultName$

if play_result
    selectObject: result
    Play
endif

selectObject: result
