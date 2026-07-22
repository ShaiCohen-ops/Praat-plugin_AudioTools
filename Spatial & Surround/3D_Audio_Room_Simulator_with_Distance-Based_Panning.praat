# ============================================================
# Praat AudioTools - 3D Audio Room Simulator with Distance-Based Panning.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Image-source room simulator projected to stereo.
#   A source is moved along a 3D trajectory around a listener at the
#   room centre. Two IR models are offered:
#     (1) Shared room IR   - one IR for the whole run; position
#                            controls level and pan only.
#     (2) Per-position IR  - direct sound and first/second-order axial
#                            image sources recomputed at every position,
#                            each reflection panned from its own image
#                            direction, over a decorrelated diffuse tail
#                            held at constant level. Direct, early and
#                            diffuse share one propagation delay, so the
#                            response is causal at every position.
#   Panning is DBAP or equal-power stereo.
#
#   NOT a binaural renderer. Output is 2-channel loudspeaker stereo
#   with no HRTF, no elevation cue and no head model: vertical motion
#   changes distance only. Height is shown in the plot, not encoded
#   in the audio.
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Changelog v0.5 (2026):
#   - FIX: diffuse tail was about 3.1 dB too quiet. The level was solved
#     from an energy match against int exp(-13.8t/RT60) dt = RT60/13.8,
#     but the envelope actually applied is exp(-6.9t/RT60) *
#     (1 - exp(-3t/t_mix)); the fade-in factor was left out of the
#     integral. At t_mix = RT60/8 the true energy is 49.3% of the assumed
#     value, so the stated crossover at d_crit really sat near 1.42 *
#     d_crit. The envelope energy is now integrated in closed form,
#     1/(2a) - 2/(2a+b) + 1/(2a+2b), so the calibration matches the
#     envelope for any t_mix. Note the match is against the diffuse tail
#     only; early reflections add further non-direct energy on top.
#   - FIX (causality): with Propagation_delay on, the diffuse tail could
#     arrive before the direct sound. v0.4 convolved the tail once from
#     the whole source and wrote it at t = 0, while the direct sound of
#     each position was delayed by d/c, so for a distant source the room
#     started responding before the sound reached the listener. The tail
#     is now part of each per-position IR and the whole response - direct,
#     early and diffuse - is delayed together when written to the output.
#     The tail level stays independent of distance, so this changes the
#     onset without reintroducing a reverb that decays with distance.
#     Cost: two long convolutions per position instead of two short ones
#     plus two long ones overall, so long RT60 with many positions is
#     slower than in v0.4.
#   - FIX: the spiral ran its radius on .uOpen and its angle on .uClosed,
#     which are different clocks, so radius and angle did not reach their
#     ends together and the curve depended on how many points sampled it.
#     Angle now runs on .uOpen as well.
#   - FIX: the plotted path is now sampled over the audio's own parameter
#     domain. v0.4 called computePosition with .total = 200 for the curve
#     and .total = Num_positions for the audio, so anything keyed to
#     .uClosed traced a slightly different path and the markers were not
#     guaranteed to lie on the drawn line - visible in the elevation
#     panel. The curve now uses fractional indices against the audio's
#     own .total, so it passes through every marker exactly.
#   - FIX: three preset labels disagreed with the values they set
#     (Small Studio 3x4x2.5 vs 4x3x2.5, Living Room 5x6x3 vs 6x5x3,
#     Bathroom 2x2.5x2.5 vs 2.5x2x2.5). Since length is the stereo axis,
#     the transposition changed left-right reflection times, the Left to
#     Right bound and DBAP geometry. Labels corrected to match the code.
#   - FIX: the script indexed the source from t = 0. A Praat Sound need
#     not start at 0 - anything extracted with preserved times does not -
#     and every segment boundary was then displaced by xmin. The script
#     now works on a copy whose domain starts at 0.
#   - FIX: speakers were pinned at x = +-1 m even in rooms narrower than
#     2 m on x, which put them outside the walls and computed DBAP on a
#     geometry the plot did not show. Speaker positions are now clamped
#     to 0.9 * half_x.
#
# Changelog v0.4 (2026):
#   - FIX (critical): coordinate system was inconsistent. Trajectories
#     used x for front/back and y for left/right, while the speakers,
#     the DBAP distances and the plot used x for left/right. "Front to
#     Back" therefore panned left-right and "Left to Right" stayed in
#     the centre; equal-power panning read y while DBAP read x. One
#     convention now throughout: x = left/right (spans room_length),
#     y = back/front (spans room_width), z = down/up (spans
#     room_height). Equal-power pan is x / (room_length/2).
#   - FIX: early-reflection times were half their correct value. v0.3
#     used wall_distance/c for a first-order reflection, i.e. the one-way
#     trip to the wall. Replaced by an image-source model: image at
#     2*m*half + (-1)^|m| * coord, delay = |image| / c. For a centred
#     source this gives room_length/c, twice the v0.3 value. It is also
#     valid for an off-centre source, which the old formula was not.
#   - FIX: reflection amplitude used (1 - alpha). Alpha is an energy
#     absorption coefficient, so the pressure reflection coefficient is
#     sqrt(1 - alpha). At alpha = 0.6 the reflections were 0.40 instead
#     of 0.632, i.e. ~4 dB too dark.
#   - FIX: absorption is now clamped to (0, 1]. Custom_absorption could
#     previously be negative or > 1 and still reach the Sabine equation.
#   - FIX: the IR "impulse" was a 0.1 ms rectangular pulse (4-5 samples
#     at 44.1 kHz), not an impulse. Taps are now written into exactly
#     one sample by targeting a sub-sample window.
#   - FIX: the diffuse tail used randomGauss with no seed, so identical
#     input and parameters produced different output on every run.
#     Replaced with a deterministic hash noise, so runs are reproducible.
#   - FIX: crossfade validation. v0.3 tested sound_dur < 1.2 *
#     segment_duration, which is not the overlap condition. The real
#     constraint is crossfade_time <= sound_dur / num_positions;
#     above it a segment overlaps more than one neighbour and its own
#     fade-in and fade-out regions cross, so the windows no longer sum
#     to unity. That is what is checked now.
#   - FIX: convolution read index. v0.3 assumed the convolution output
#     starts at t = 0 with colF = t * sr + 1. A Convolve output has
#     x1 = x1_a + x1_b, so this was off by about one sample. Reads now
#     go through object(id, time), which resolves x1 and dx from the
#     object itself.
#   - FIX: Figure-8 was r*sin(2A)*cos(A), r*sin(2A)*sin(A), which is the
#     polar rose rho = r*sin(2A) - a four-petal clover, not a figure-8.
#     Now x = r*sin(A), y = (r/2)*sin(2A).
#   - FIX: Movement_radius meant a different thing per trajectory (r for
#     circular, 0.5r for up/down, sqrt(2)*r for diagonal). All
#     trajectories are now normalised so the maximum distance from the
#     listener equals Movement_radius exactly.
#   - FIX: the trajectory was never tested against the room. A default
#     radius of 2.5 m put the source largely outside a Small Studio or
#     a Bathroom. The radius is now clamped per trajectory to keep the
#     path inside the walls, and the clamp is reported.
#   - FIX: audio and plot are now generated by one procedure, so the
#     drawn path is by construction the path that was rendered. v0.3
#     drew "Up and Down" as horizontal motion that did not exist in the
#     audio, and drew the random walk through drawPos = 1..100 while the
#     audio used pos = 1..num_positions in the same formula, so the
#     curve was not the sampled path.
#   - FIX: the random walk is now parameterised by normalised progress
#     rather than by the raw index, so its shape no longer depends on
#     num_positions.
#   - NEW: per-position IR model. v0.3 built one IR and convolved every
#     segment with it, so "synthesized room IR per position" in the
#     header was not what the code did: position affected gain and
#     balance only, never reflection times, wall levels, reflection
#     directions or the direct-to-reverberant ratio. In the new model
#     each reflection is panned from its own image-source direction, the
#     direct sound carries 1/d, and the diffuse tail is convolved once
#     at constant level, so D/R now falls with distance as it should.
#   - NEW: optional propagation delay d/c on the direct sound.
#   - RENAME: Reverb_tail -> Ir_padding. It never affected the decay
#     rate or RT60; it only appended time after the tail had already
#     decayed. Default lowered from 1.5 s to 0.3 s.
#   - NOTE: distance attenuation in shared-IR mode is 1/(1+d), which is
#     a softened inverse-distance amplitude law, not the inverse-square
#     law the v0.3 comment claimed. It is kept as the legacy sonic
#     behaviour and the comment is corrected. Per-position mode uses
#     1/d on the direct sound instead.
#   - NOTE: the DBAP comment claimed the exponent is "typically 6 for
#     3D". 6 is a rolloff in dB per doubling of distance, not the
#     exponent. The code was already right: weights 1/d^2 with a sqrt
#     normalisation give 1/d amplitude, i.e. about 6 dB per doubling.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# Coordinate convention (audio, geometry and plot all share it):
#   x = left (-) / right (+)   spans room_length
#   y = back (-) / front (+)   spans room_width
#   z = down (-) / up (+)      spans room_height
# Listener at the origin, i.e. at the centre of the room.

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
sound_name$ = selected$("Sound")
sound_dur = Get total duration
sound_sr = Get sampling frequency

if sound_dur <= 0
    exitScript: "Selected Sound has zero duration."
endif

# sound_temp marks a working copy this script owns and must delete.
sound_temp = 0

# Convert to mono if needed
numberOfChannels = Get number of channels
if numberOfChannels > 1
    sound_mono = Convert to mono
    sound = sound_mono
    sound_temp = 1
endif

# v0.5: the segment loop indexes the source from t = 0, and the room
# response is written into the output from t = 0. A Praat Sound need not
# start at 0 - anything extracted with preserved times does not - and in
# that case every segment boundary was displaced by xmin. Work on a copy
# whose domain starts at 0 rather than assuming it.
selectObject: sound
src_t0 = Get start time
if src_t0 <> 0
    src_t1 = Get end time
    sound_zero = Extract part: src_t0, src_t1, "rectangular", 1, "no"
    Rename: "work_zero"
    if sound_temp = 1
        removeObject: sound
    endif
    sound = sound_zero
    sound_temp = 1
    selectObject: sound
    sound_dur = Get total duration
endif

# === Single form for all parameters ===
form 3D Audio Room Simulator v0.5
    comment === Room Preset (length x width x height = L/R, B/F, D/U) ===
    optionmenu Preset 1
        option Custom
        option Small Studio (4x3x2.5m, dry)
        option Living Room (6x5x3m, medium)
        option Concert Hall (20x15x8m, live)
        option Cathedral (40x25x15m, very live)
        option Bathroom (2.5x2x2.5m, very live)
        option Anechoic Chamber (5x5x3m, dead)
        option Club/Bar (15x10x3.5m, medium)
    comment === Custom dimensions (used only if preset=Custom) ===
    comment Length = left-right, Width = back-front, Height = down-up
    positive Custom_length 8.0
    positive Custom_width 6.0
    positive Custom_height 3.0
    real Custom_absorption 0.3
    comment === Movement (radius = max distance from listener) ===
    optionmenu Movement 1
        option Circular (horizontal)
        option Front to Back
        option Left to Right
        option Spiral (horizontal)
        option Up and Down
        option Random walk (deterministic wander)
        option Figure-8 (horizontal)
        option Diagonal sweep
    positive Movement_radius 2.5
    natural Num_positions 16
    comment === Room model ===
    optionmenu Ir_model 2
        option Shared room IR (position = gain + pan only)
        option Per-position image-source IR
    boolean Propagation_delay 1
    positive Ir_padding 0.3
    positive Crossfade_time 0.1
    boolean Use_dbap 1
endform

# Apply preset values
if preset = 1
    room_length = custom_length
    room_width = custom_width
    room_height = custom_height
    absorption = custom_absorption
elsif preset = 2
    room_length = 4.0
    room_width = 3.0
    room_height = 2.5
    absorption = 0.6
elsif preset = 3
    room_length = 6.0
    room_width = 5.0
    room_height = 3.0
    absorption = 0.4
elsif preset = 4
    room_length = 20.0
    room_width = 15.0
    room_height = 8.0
    absorption = 0.15
elsif preset = 5
    room_length = 40.0
    room_width = 25.0
    room_height = 15.0
    absorption = 0.08
elsif preset = 6
    room_length = 2.5
    room_width = 2.0
    room_height = 2.5
    absorption = 0.05
elsif preset = 7
    room_length = 5.0
    room_width = 5.0
    room_height = 3.0
    absorption = 0.99
else
    room_length = 15.0
    room_width = 10.0
    room_height = 3.5
    absorption = 0.25
endif

if room_length <= 0 or room_width <= 0 or room_height <= 0
    exitScript: "Invalid room dimensions!"
endif

# v0.4: alpha is an energy absorption coefficient and must lie in (0, 1].
# Custom_absorption could previously be negative or greater than 1.
absorption_in = absorption
if absorption < 0.01
    absorption = 0.01
endif
if absorption > 1.0
    absorption = 1.0
endif
absorption_clamped = 0
if absorption <> absorption_in
    absorption_clamped = 1
endif

if num_positions < 2
    num_positions = 2
endif

half_x = room_length / 2
half_y = room_width / 2
half_z = room_height / 2

if movement = 1
    movement$ = "Circular"
elsif movement = 2
    movement$ = "Front to Back"
elsif movement = 3
    movement$ = "Left to Right"
elsif movement = 4
    movement$ = "Spiral"
elsif movement = 5
    movement$ = "Up and Down"
elsif movement = 6
    movement$ = "Random walk"
elsif movement = 7
    movement$ = "Figure-8"
else
    movement$ = "Diagonal"
endif

# v0.4: keep the trajectory inside the room. Each trajectory has its own
# relation between Movement_radius and the extreme coordinate it reaches,
# so the admissible radius is per-trajectory.
if movement = 1 or movement = 4
    r_allow = min(half_x, half_y)
elsif movement = 2
    r_allow = half_y
elsif movement = 3
    r_allow = half_x
elsif movement = 5
    r_allow = half_z
elsif movement = 6
    # Wander reaches 0.720*r on x and 0.834*r on y (measured on the
    # normalised curve below), so the two axes constrain it separately.
    r_allow = min(half_x / 0.72, half_y / 0.834)
elsif movement = 8
    r_allow = sqrt(2) * min(half_x, half_y)
else
    r_allow = min(half_x, 2 * half_y)
endif
r_allow = r_allow * 0.95

radius_requested = movement_radius
radius_clamped = 0
if movement_radius > r_allow
    movement_radius = r_allow
    radius_clamped = 1
endif

# Speed of sound
c = 343

# Minimum source-listener distance, so a trajectory passing through the
# listener does not produce an unbounded 1/d.
min_dist = 0.3

# Pressure reflection coefficient. alpha is energy absorption, so
# alpha = 1 - |R|^2 and |R| = sqrt(1 - alpha).
refl = sqrt(1 - absorption)

# Sabine RT60
volume = room_length * room_width * room_height
area_xy = room_length * room_width
area_xz = room_length * room_height
area_yz = room_width * room_height
surface_area = 2 * (area_xy + area_xz + area_yz)
rt60 = 0.161 * volume / (absorption * surface_area + 0.001)

if rt60 > 5.0
    rt60 = 5.0
endif
if rt60 < 0.05
    rt60 = 0.05
endif

# Critical distance (omnidirectional source): the distance at which the
# direct and reverberant fields are equal. Used to set the diffuse tail
# level so that direct-to-reverberant ratio behaves correctly with
# distance in per-position mode.
d_crit = 0.057 * sqrt(volume / rt60)
if d_crit < 0.15
    d_crit = 0.15
endif

# IR lengths.
#   tail_dur   - diffuse decay plus padding
#   early_dur  - long enough for the most distant second-order image
max_half = max(half_x, half_y, half_z)
tail_dur = rt60 + ir_padding
early_dur = (4 * max_half + movement_radius) / c + 0.02
if early_dur < 0.05
    early_dur = 0.05
endif

# Overlap condition. With hop B = sound_dur / num_positions and segment
# length B + C, adjacent segments overlap by exactly C and the linear
# fades sum to unity provided C <= B. Above that a segment overlaps more
# than one neighbour and its own fade-in and fade-out regions cross.
block_dur = sound_dur / num_positions
if crossfade_time > block_dur
    if sound_temp = 1
        removeObject: sound
    endif
    exitScript: "Crossfade too long. With ", num_positions,
        ... " positions over ", fixed$(sound_dur, 2),
        ... " s the hop is ", fixed$(block_dur, 3),
        ... " s, so Crossfade_time must be <= ", fixed$(block_dur, 3),
        ... " s. Reduce Crossfade_time or Num_positions, or use a longer source."
endif

segment_duration = block_dur + crossfade_time

# Speaker positions (stereo pair on the left-right axis, ear height).
# v0.5: kept inside the room. At +-1 m a room narrower than 2 m on x put
# the speakers outside the walls, so DBAP was computed on a geometry the
# plot did not show.
speaker_x = 1.0
if speaker_x > half_x * 0.9
    speaker_x = half_x * 0.9
endif
speaker_L_x = -speaker_x
speaker_L_y = 0.0
speaker_L_z = 0.0
speaker_R_x = speaker_x
speaker_R_y = 0.0
speaker_R_z = 0.0

# DBAP weighting exponent. Weights are 1/d^2 and the normalisation takes
# a square root, so the resulting amplitude law is 1/d, i.e. about 6 dB
# per doubling of distance. (6 is the rolloff in dB, not the exponent.)
dbap_exponent = 2.0

ir_dx = 1 / sound_sr

# ============================================================
# PROCEDURES
# ============================================================

# Source position for index .idx of .total, in metres.
# Two parameterisations: .uClosed for periodic paths (so the last point
# does not duplicate the first), .uOpen for one-way sweeps.
# All trajectories are normalised so max sqrt(x^2+y^2+z^2) = radius.
procedure computePosition: .idx, .total
    .uClosed = (.idx - 1) / .total
    if .total > 1
        .uOpen = (.idx - 1) / (.total - 1)
    else
        .uOpen = 0
    endif
    .ang = .uClosed * 2 * pi
    .r = movement_radius
    .diag = 1 / sqrt(2)

    if movement = 1
        # Circular, horizontal
        .x = .r * cos(.ang)
        .y = .r * sin(.ang)
        .z = 0
    elsif movement = 2
        # Front to Back: front is +y
        .x = 0
        .y = .r * (1 - 2 * .uOpen)
        .z = 0
    elsif movement = 3
        # Left to Right: left is -x
        .x = .r * (2 * .uOpen - 1)
        .y = 0
        .z = 0
    elsif movement = 4
        # Spiral, horizontal. v0.5: the angle now runs on .uOpen like the
        # radius. With the angle on .uClosed the two ran on different
        # clocks, so radius and angle did not reach their endpoints
        # together and the curve depended on .total.
        .rs = .r * .uOpen
        .sa = 6 * pi * .uOpen
        .x = .rs * cos(.sa)
        .y = .rs * sin(.sa)
        .z = 0
    elsif movement = 5
        # Up and Down: z only. Reaches +-radius (v0.3 reached +-0.5r).
        .x = 0
        .y = 0
        .z = .r * sin(.ang)
    elsif movement = 6
        # Deterministic wander. Parameterised by normalised progress, so
        # the shape no longer depends on num_positions, and the plotted
        # curve is the same curve the audio samples. 0.8407296 is the
        # reciprocal of the curve's own maximum radius, so that max
        # distance from the listener is exactly Movement_radius.
        .kw = 0.8407296
        .x = .r * .kw * sin(2 * pi * 1.7 * .uOpen + 0.4) * cos(2 * pi * 0.9 * .uOpen)
        .y = .r * .kw * cos(2 * pi * 1.3 * .uOpen) * sin(2 * pi * 2.1 * .uOpen + 1.1)
        .z = 0
    elsif movement = 7
        # Figure-8 (Gerono lemniscate). Max |x| = r, max |y| = r/2.
        .x = .r * sin(.ang)
        .y = .r * 0.5 * sin(2 * .ang)
        .z = 0
    else
        # Diagonal sweep, normalised so the corners sit at radius r
        .x = .r * .diag * (2 * .uOpen - 1)
        .y = .r * .diag * (2 * .uOpen - 1)
        .z = 0
    endif
endproc

# Stereo gains for a source (or image source) at .x, .y, .z.
# Both laws satisfy gL^2 + gR^2 = 1.
procedure panGains: .x, .y, .z
    if use_dbap
        .dL = sqrt((.x - speaker_L_x)^2 + (.y - speaker_L_y)^2 + (.z - speaker_L_z)^2)
        .dR = sqrt((.x - speaker_R_x)^2 + (.y - speaker_R_y)^2 + (.z - speaker_R_z)^2)
        if .dL < 0.05
            .dL = 0.05
        endif
        if .dR < 0.05
            .dR = 0.05
        endif
        .wL = 1 / (.dL ^ dbap_exponent)
        .wR = 1 / (.dR ^ dbap_exponent)
        .tot = .wL + .wR
        .gL = sqrt(.wL / .tot)
        .gR = sqrt(.wR / .tot)
    else
        # Equal power. v0.3 read y here, which is the front/back axis.
        if half_x > 0
            .p = .x / half_x
        else
            .p = 0
        endif
        if .p < -1
            .p = -1
        endif
        if .p > 1
            .p = 1
        endif
        .a = (.p + 1) * pi / 4
        .gL = cos(.a)
        .gR = sin(.a)
    endif
    .pan = .gR - .gL
endproc

# Add a single-sample tap of amplitude .amp at time .t in object .obj.
# The IRs are created with xmin = 0, so sample k sits at (k - 0.5) * dx.
# The window (k - 0.75)*dx .. (k - 0.25)*dx contains that sample time and
# no other, whatever the endpoint convention: this writes exactly one
# sample, unlike v0.3's 0.1 ms rectangular pulse.
procedure addTap: .obj, .t, .amp
    if .t >= 0 and abs(.amp) > 1e-9
        .k = round(.t / ir_dx + 0.5)
        if .k < 1
            .k = 1
        endif
        if .k <= tap_n
            selectObject: .obj
            Formula (part): (.k - 0.75) * ir_dx, (.k - 0.25) * ir_dx, 1, 1,
                ... "self + " + fixed$(.amp, 10)
        endif
    endif
endproc

# Write the direct sound and the axial image sources for a source at
# .sx, .sy, .sz into the L and R early IRs .objL and .objR.
# 1-D image source positions on each axis: 2*m*half + (-1)^|m| * coord,
# for m = -2..2 excluding 0, so first and second order per wall pair.
# Each image is panned from its own direction, so early reflections
# arrive from different places instead of following the source as one
# mono object.
procedure buildEarlyIR: .objL, .objR, .sx, .sy, .sz
    .dDir = sqrt(.sx^2 + .sy^2 + .sz^2)
    if .dDir < min_dist
        .dDir = min_dist
    endif

    # v0.5: the direct sound always sits at t = 0 inside the IR, and the
    # whole response - direct, early reflections and diffuse tail alike -
    # is delayed by .delay when it is written into the output. v0.4 baked
    # d/c into the taps instead, which delayed the early field but not
    # the separately convolved tail.
    .tBase = .dDir / c
    if propagation_delay
        .delay = .dDir / c
    else
        .delay = 0
    endif

    @panGains: .sx, .sy, .sz
    .gL = panGains.gL
    .gR = panGains.gR
    .pan = panGains.pan
    .aDir = 1 / .dDir
    @addTap: .objL, .dDir / c - .tBase, .aDir * .gL
    @addTap: .objR, .dDir / c - .tBase, .aDir * .gR

    for .ax from 1 to 3
        for .m from -2 to 2
            if .m <> 0
                if (abs(.m) mod 2) = 0
                    .sgn = 1
                else
                    .sgn = -1
                endif
                .ix = .sx
                .iy = .sy
                .iz = .sz
                if .ax = 1
                    .ix = 2 * .m * half_x + .sgn * .sx
                elsif .ax = 2
                    .iy = 2 * .m * half_y + .sgn * .sy
                else
                    .iz = 2 * .m * half_z + .sgn * .sz
                endif
                .dImg = sqrt(.ix^2 + .iy^2 + .iz^2)
                if .dImg < min_dist
                    .dImg = min_dist
                endif
                .aImg = refl ^ abs(.m) / .dImg
                @panGains: .ix, .iy, .iz
                @addTap: .objL, .dImg / c - .tBase, .aImg * panGains.gL
                @addTap: .objR, .dImg / c - .tBase, .aImg * panGains.gR
            endif
        endfor
    endfor
endproc

# ============================================================
# REPORT
# ============================================================

writeInfoLine: "3D Audio Room Simulator v0.5 - STEREO"
if preset = 2
    appendInfoLine: "Preset: Small Studio"
elsif preset = 3
    appendInfoLine: "Preset: Living Room"
elsif preset = 4
    appendInfoLine: "Preset: Concert Hall"
elsif preset = 5
    appendInfoLine: "Preset: Cathedral"
elsif preset = 6
    appendInfoLine: "Preset: Bathroom"
elsif preset = 7
    appendInfoLine: "Preset: Anechoic Chamber"
elsif preset = 8
    appendInfoLine: "Preset: Club/Bar"
else
    appendInfoLine: "Preset: Custom"
endif
appendInfoLine: "Room: ", fixed$(room_length, 1), " x ", fixed$(room_width, 1),
    ... " x ", fixed$(room_height, 1), " m  (x=L/R, y=B/F, z=D/U)"
appendInfoLine: "Absorption (alpha): ", fixed$(absorption, 3),
    ... "   reflection coeff sqrt(1-alpha): ", fixed$(refl, 3)
if absorption_clamped = 1
    appendInfoLine: "  NOTE: absorption clamped from ", fixed$(absorption_in, 3), " into (0, 1]."
endif
appendInfoLine: "RT60: ", fixed$(rt60, 2), " s   critical distance: ", fixed$(d_crit, 2), " m"
appendInfoLine: "Movement: ", movement$, "   radius: ", fixed$(movement_radius, 2), " m"
if radius_clamped = 1
    appendInfoLine: "  NOTE: radius clamped from ", fixed$(radius_requested, 2),
        ... " m to keep the path inside the room."
endif
if ir_model = 1
    appendInfoLine: "IR model: shared room IR (position = gain + pan only)"
else
    appendInfoLine: "IR model: per-position image-source IR"
    if propagation_delay
        appendInfoLine: "  Propagation delay d/c: on (direct, early and diffuse together)"
    else
        appendInfoLine: "  Propagation delay d/c: off"
    endif
endif
if use_dbap
    appendInfoLine: "Panning: DBAP (weights 1/d^2, amplitude ~1/d)"
else
    appendInfoLine: "Panning: Equal-power stereo on x"
endif
appendInfoLine: "Processing ", num_positions, " positions..."

# ============================================================
# BUILD OUTPUT BUFFERS
# ============================================================

# The extra movement_radius / c covers the propagation delay applied to
# the last position when Propagation_delay is on.
output_duration = sound_dur + crossfade_time + max(early_dur, tail_dur) + movement_radius / c + 0.5

Create Sound from formula: "output_L", 1, 0, output_duration, sound_sr, "0"
output_L = selected("Sound")
Create Sound from formula: "output_R", 1, 0, output_duration, sound_sr, "0"
output_R = selected("Sound")

rt60_str$ = fixed$(rt60, 8)
t_mix = rt60 / 8
if t_mix < 0.005
    t_mix = 0.005
endif
t_mix_str$ = fixed$(t_mix, 8)

# Energy of the tail envelope exp(-a t) * (1 - exp(-b t)), squared and
# integrated:
#   E = int_0^inf exp(-2a t) (1 - exp(-b t))^2 dt
#     = 1/(2a) - 2/(2a + b) + 1/(2a + 2b)
# with 2a = 13.8 / RT60 and b = 3 / t_mix.
# v0.4 used only 1/(2a), i.e. it costed the decay but not the diffuse
# fade-in. At t_mix = RT60/8 that leaves 49.3% of the assumed energy, so
# the tail came out about 3.1 dB low and the real direct/diffuse
# crossover sat at roughly 1.42 * d_crit instead of at d_crit.
decay_rate = 13.8 / rt60
onset_rate = 3 / t_mix
env_energy = 1 / decay_rate - 2 / (decay_rate + onset_rate) + 1 / (decay_rate + 2 * onset_rate)

# Deterministic hash noise. v0.3 used randomGauss with no seed, so the
# same input and parameters gave a different IR on every run. These two
# hashes are mutually decorrelated, which gives a diffuse field that is
# wide instead of a mono object glued to the source.
hashA$ = "(2 * (sin(col * 12.9898 + 78.2330) * 43758.5453"
    ... + " - floor(sin(col * 12.9898 + 78.2330) * 43758.5453)) - 1)"
hashB$ = "(2 * (sin(col * 4.14140 + 21.1910) * 24634.6345"
    ... + " - floor(sin(col * 4.14140 + 21.1910) * 24634.6345)) - 1)"
env$ = "exp(-6.9 * x / " + rt60_str$ + ")"
    ... + " * (1 - exp(-3 * x / " + t_mix_str$ + "))"

# ============================================================
# MODE 1 - SHARED ROOM IR
# ============================================================

if ir_model = 1
    ir_dur = max(tail_dur, early_dur)
    Create Sound from formula: "room_ir", 1, 0, ir_dur, sound_sr, "0"
    room_ir = selected("Sound")
    tap_n = Get number of samples

    # Source assumed at the room centre. Reflection amplitudes keep the
    # v0.3 balance (0.7 for first order, 0.35 for second) but use the
    # corrected pressure reflection coefficient and the corrected,
    # image-source derived arrival times.
    @addTap: room_ir, 0, 1
    for ax from 1 to 3
        for m from -2 to 2
            if m <> 0
                if ax = 1
                    d_img = 2 * abs(m) * half_x
                elsif ax = 2
                    d_img = 2 * abs(m) * half_y
                else
                    d_img = 2 * abs(m) * half_z
                endif
                if abs(m) = 1
                    a_img = refl * 0.7
                else
                    a_img = refl ^ 2 * 0.35
                endif
                @addTap: room_ir, d_img / c, a_img
            endif
        endfor
    endfor

    selectObject: room_ir
    Formula: "self + 0.1 * " + hashA$ + " * " + env$
    Scale peak: 0.99
endif

# ============================================================
# MODE 2 - PER-POSITION IR TEMPLATES (diffuse tail)
# ============================================================

if ir_model = 2
    # Tail level from the critical distance, by energy match:
    #   sum(h^2) = tail_amp^2 * var * fs * env_energy = 1 / d_crit^2
    # with var = 1/3 for the uniform hash noise, so std = 1/sqrt(3). The
    # diffuse field then equals the direct field at d_crit and the
    # direct-to-diffuse ratio falls with distance, which is the point of
    # the exercise. Divided by sqrt(2) across two decorrelated channels.
    #
    # Note this equalises direct against the DIFFUSE TAIL only. The early
    # reflections carry their own energy on top, so the total non-direct
    # field already exceeds the direct sound at d_crit.
    tail_amp = 1 / (d_crit * 0.57735027 * sqrt(sound_sr * env_energy) * sqrt(2))
    tail_amp_str$ = fixed$(tail_amp, 10)

    # v0.5: the tail is now part of each per-position IR rather than a
    # separate convolution of the whole source placed at t = 0. With
    # Propagation_delay on, that arrangement let the diffuse field start
    # rising before the direct sound had arrived - acausal for any source
    # away from the listener, and the fade-in only softened it. Building
    # the tail into the IR and delaying the whole response by d/c makes
    # the onset causal at every position while keeping the tail level
    # independent of distance.
    #
    # The two hashes are mutually decorrelated, so the diffuse field is
    # wide rather than a mono object following the source. Since the
    # crossfade windows sum to unity, summing the windowed segments
    # reconstructs the same diffuse field a single convolution would
    # give when all delays are equal.
    ir_dur2 = max(tail_dur, early_dur)

    Create Sound from formula: "irP_L", 1, 0, ir_dur2, sound_sr, "0"
    ir_tmpl_L = selected("Sound")
    tap_n = Get number of samples
    Formula: tail_amp_str$ + " * " + hashA$ + " * " + env$

    Create Sound from formula: "irP_R", 1, 0, ir_dur2, sound_sr, "0"
    ir_tmpl_R = selected("Sound")
    Formula: tail_amp_str$ + " * " + hashB$ + " * " + env$
endif

# ============================================================
# POSITION LOOP
# ============================================================

for pos from 1 to num_positions
    @computePosition: pos, num_positions
    x_pos = computePosition.x
    y_pos = computePosition.y
    z_pos = computePosition.z

    distance = sqrt(x_pos^2 + y_pos^2 + z_pos^2)
    if distance < min_dist
        distance = min_dist
    endif

    time_offset = (pos - 1) * block_dur

    # --- extract and window the segment ---
    selectObject: sound
    start_time = time_offset
    end_time = time_offset + segment_duration
    if start_time < 0
        start_time = 0
    endif
    if end_time > sound_dur
        end_time = sound_dur
    endif

    segment = Extract part: start_time, end_time, "rectangular", 1, "no"
    seg_dur = Get total duration

    cf_str$ = fixed$(crossfade_time, 8)
    seg_str$ = fixed$(seg_dur, 8)

    if pos > 1 and pos < num_positions
        Formula: "self * (if x < " + cf_str$
            ... + " then x / " + cf_str$
            ... + " else (if x > " + seg_str$ + " - " + cf_str$
            ... + " then (" + seg_str$ + " - x) / " + cf_str$
            ... + " else 1 fi) fi)"
    elsif pos = 1
        Formula: "self * (if x > " + seg_str$ + " - " + cf_str$
            ... + " then (" + seg_str$ + " - x) / " + cf_str$
            ... + " else 1 fi)"
    else
        Formula: "self * (if x < " + cf_str$
            ... + " then x / " + cf_str$
            ... + " else 1 fi)"
    endif

    toStr$ = fixed$(time_offset, 8)

    if ir_model = 1
        # --- shared IR: position controls level and pan only ---
        # Softened inverse-distance amplitude law. This is not the
        # inverse-square law the v0.3 comment claimed; it approaches
        # 1/d far from the listener and flattens near it. Kept as the
        # legacy sonic behaviour of this mode.
        atten = 1 / (1 + distance)
        selectObject: segment
        Formula: "self * " + fixed$(atten, 8)

        @panGains: x_pos, y_pos, z_pos
        gain_L = panGains.gL
        gain_R = panGains.gR
        pan = panGains.pan

        selectObject: segment
        plusObject: room_ir
        conv = Convolve: "sum", "zero"
        conv_dur = Get total duration
        end_write = time_offset + conv_dur
        if end_write > output_duration
            end_write = output_duration
        endif

        # v0.4: read by time, not by a hand-built sample index. A
        # Convolve output has x1 = x1_a + x1_b, so t * sr + 1 was off
        # by about a sample; object(id, t) resolves x1 and dx itself.
        selectObject: output_L
        Formula (part): time_offset, end_write, 1, 1,
            ... "self + object(" + string$(conv) + ", x - " + toStr$ + ") * "
            ... + fixed$(gain_L, 8)
        selectObject: output_R
        Formula (part): time_offset, end_write, 1, 1,
            ... "self + object(" + string$(conv) + ", x - " + toStr$ + ") * "
            ... + fixed$(gain_R, 8)

        removeObject: segment, conv
    else
        # --- per-position image-source IR (direct + early + tail) ---
        # The templates already hold the decorrelated diffuse tail, so
        # copying them and stamping the direct and image taps on top
        # gives one causal room response per position and per channel.
        selectObject: ir_tmpl_L
        irP_L = Copy: "irP_L_" + string$(pos)
        selectObject: ir_tmpl_R
        irP_R = Copy: "irP_R_" + string$(pos)

        @buildEarlyIR: irP_L, irP_R, x_pos, y_pos, z_pos
        gain_L = buildEarlyIR.gL
        gain_R = buildEarlyIR.gR
        pan = buildEarlyIR.pan

        # Propagation delay now shifts the whole response, tail included,
        # instead of only the taps inside the IR.
        write_at = time_offset + buildEarlyIR.delay
        atStr$ = fixed$(write_at, 8)

        selectObject: segment
        plusObject: irP_L
        conv_L = Convolve: "sum", "zero"
        conv_dur = Get total duration

        selectObject: segment
        plusObject: irP_R
        conv_R = Convolve: "sum", "zero"

        end_write = write_at + conv_dur
        if end_write > output_duration
            end_write = output_duration
        endif

        # Gains are already baked into the taps, one per image direction.
        selectObject: output_L
        Formula (part): write_at, end_write, 1, 1,
            ... "self + object(" + string$(conv_L) + ", x - " + atStr$ + ")"
        selectObject: output_R
        Formula (part): write_at, end_write, 1, 1,
            ... "self + object(" + string$(conv_R) + ", x - " + atStr$ + ")"

        removeObject: segment, conv_L, conv_R, irP_L, irP_R
    endif

    appendInfoLine: "Position ", pos, "/", num_positions,
        ... " - x:", fixed$(x_pos, 2), " y:", fixed$(y_pos, 2), " z:", fixed$(z_pos, 2),
        ... "  d:", fixed$(distance, 2), "m  L:", fixed$(gain_L, 2),
        ... " R:", fixed$(gain_R, 2)
endfor

if ir_model = 2
    removeObject: ir_tmpl_L, ir_tmpl_R
endif

# Combine to stereo
selectObject: output_L
plusObject: output_R
output_stereo = Combine to stereo
Rename: sound_name$ + "_spatial_stereo"
Scale peak: 0.99

# Clean up
removeObject: output_L, output_R
if ir_model = 1
    removeObject: room_ir
endif
if sound_temp = 1
    removeObject: sound
endif

# ============================================================
# VISUALIZATION
# ============================================================

if preset = 2
    presetDisp$ = "Small Studio"
elsif preset = 3
    presetDisp$ = "Living Room"
elsif preset = 4
    presetDisp$ = "Concert Hall"
elsif preset = 5
    presetDisp$ = "Cathedral"
elsif preset = 6
    presetDisp$ = "Bathroom"
elsif preset = 7
    presetDisp$ = "Anechoic"
elsif preset = 8
    presetDisp$ = "Club/Bar"
else
    presetDisp$ = "Custom"
endif

dbapStr$ = "EP stereo"
if use_dbap
    dbapStr$ = "DBAP"
endif
if ir_model = 1
    irStr$ = "shared IR"
else
    irStr$ = "per-position IR"
endif

Erase all
Select outer viewport: 0, 8, 0, 8

# ----------------------------------------------------------
# Title
# ----------------------------------------------------------
Select outer viewport: 0, 8, 0, 0.60
Axes: 0, 1, 0, 1
Font size: 12
Colour: "Black"
Text: 0.5, "centre", 0.65, "half", "##3D Audio Room Simulator v0.5##"
Font size: 7
Colour: "{0.35, 0.35, 0.52}"
Text: 0.5, "centre", -0.25, "half",
    ... sound_name$ + "  |  " + presetDisp$
    ... + "  |  " + fixed$(room_length, 1) + "×" + fixed$(room_width, 1)
    ... + "×" + fixed$(room_height, 1) + "m"
    ... + "  |  RT60=" + fixed$(rt60, 2) + "s"
    ... + "  |  " + movement$ + "  |  " + irStr$

# ----------------------------------------------------------
# Room top view with movement path (x = left/right, y = back/front)
# ----------------------------------------------------------
Select outer viewport: 0, 8, 0.50, 4.10
Select inner viewport: 0.55, 7.65, 0.70, 4.00

margin = max(room_length, room_width) * 0.18
Axes: -half_x - margin, half_x + margin, -half_y - margin, half_y + margin

Paint rectangle: "{0.94, 0.94, 0.90}", -half_x, half_x, -half_y, half_y

Colour: "{0.30, 0.30, 0.30}"
Line width: 3
Draw rectangle: -half_x, half_x, -half_y, half_y
Line width: 1

Colour: "{0.85, 0.85, 0.82}"
for gridX from -floor(half_x) to floor(half_x)
    Draw line: gridX, -half_y, gridX, half_y
endfor
for gridY from -floor(half_y) to floor(half_y)
    Draw line: -half_x, gridY, half_x, gridY
endfor

# Path drawn from the same procedure the audio used, over the same
# parameter domain. v0.4 called it with .total = 200 while the audio
# called it with .total = Num_positions; anything keyed to .uClosed then
# ran on a different clock, so the markers did not have to sit on the
# drawn curve. Passing a fractional index against the audio's own .total
# makes the curve pass through every marker exactly.
Line width: 2.5
numDrawPoints = 200
prev_x = 0
prev_y = 0

for drawPos from 1 to numDrawPoints
    fidx = 1 + (drawPos - 1) / (numDrawPoints - 1) * (num_positions - 1)
    @computePosition: fidx, num_positions
    dx_pos = computePosition.x
    dy_pos = computePosition.y
    progress = (drawPos - 1) / (numDrawPoints - 1)

    cR = progress
    cG = 0.20
    cB = 1 - progress

    if drawPos > 1
        Colour: "{" + fixed$(cR, 2) + ", " + fixed$(cG, 2) + ", " + fixed$(cB, 2) + "}"
        Draw line: prev_x, prev_y, dx_pos, dy_pos
    endif
    prev_x = dx_pos
    prev_y = dy_pos
endfor

for pos from 1 to num_positions
    @computePosition: pos, num_positions
    progress = (pos - 1) / (num_positions - 1)
    cR = progress
    cB = 1 - progress
    Paint circle (mm): "{" + fixed$(cR, 2) + ", 0.30, " + fixed$(cB, 2) + "}",
        ... computePosition.x, computePosition.y, 2.2
endfor

# Listener at centre
Paint circle (mm): "White", 0, 0, 4.5
Paint circle (mm): "{0.20, 0.68, 0.22}", 0, 0, 3.8

# Speakers
Paint circle (mm): "{0.58, 0.38, 0.18}", speaker_L_x, speaker_L_y, 3
Paint circle (mm): "{0.58, 0.38, 0.18}", speaker_R_x, speaker_R_y, 3

lblOff = max(room_width, room_length) * 0.06
Font size: 6
Colour: "{0.12, 0.40, 0.12}"
Text: 0, "centre", -lblOff, "half", "Listener"
Colour: "{0.40, 0.25, 0.10}"
Text: speaker_L_x, "centre", speaker_L_y - lblOff, "half", "L"
Text: speaker_R_x, "centre", speaker_R_y - lblOff, "half", "R"

Font size: 7
Colour: "{0.45, 0.45, 0.45}"
Text: 0, "centre", half_y + margin * 0.55, "half", "Front (+y)"
Text: 0, "centre", -half_y - margin * 0.55, "half", "Back (-y)"
Text: -half_x - margin * 0.50, "centre", 0, "half", "Left"
Text: half_x + margin * 0.50, "centre", 0, "half", "Right"

Font size: 5
Colour: "{0.00, 0.20, 1.00}"
Text: half_x + margin * 0.45, "centre", -half_y - margin * 0.30, "half", "Start"
Colour: "{1.00, 0.20, 0.00}"
Text: half_x + margin * 0.45, "centre", -half_y - margin * 0.55, "half", "End"

Line width: 1
Colour: "Black"
Draw inner box
Font size: 7
Text top: "no", "Room top view (x-y)  —  " + movement$
    ... + "  (r=" + fixed$(movement_radius, 2) + "m)"

# ----------------------------------------------------------
# Elevation panel: z over the trajectory
# v0.3 drew "Up and Down" as horizontal motion in the top view, which
# did not exist in the audio. Height gets its own axis instead.
# ----------------------------------------------------------
Select outer viewport: 0, 8, 4.15, 5.15
Select inner viewport: 0.55, 7.65, 4.25, 4.98

Axes: 1, num_positions, -half_z - half_z * 0.15, half_z + half_z * 0.15
Paint rectangle: "{0.97, 0.97, 0.94}", 1, num_positions, -half_z, half_z
Colour: "{0.30, 0.30, 0.30}"
Draw line: 1, half_z, num_positions, half_z
Draw line: 1, -half_z, num_positions, -half_z
Colour: "{0.75, 0.75, 0.75}"
Draw line: 1, 0, num_positions, 0

Line width: 2
prev_z = 0
prev_zx = 1
for drawPos from 1 to numDrawPoints
    zx = 1 + (drawPos - 1) / (numDrawPoints - 1) * (num_positions - 1)
    @computePosition: zx, num_positions
    progress = (drawPos - 1) / (numDrawPoints - 1)
    if drawPos > 1
        Colour: "{" + fixed$(progress, 2) + ", 0.20, " + fixed$(1 - progress, 2) + "}"
        Draw line: prev_zx, prev_z, zx, computePosition.z
    endif
    prev_zx = zx
    prev_z = computePosition.z
endfor
Line width: 1

for pos from 1 to num_positions
    @computePosition: pos, num_positions
    progress = (pos - 1) / (num_positions - 1)
    Paint circle (mm): "{" + fixed$(progress, 2) + ", 0.30, "
        ... + fixed$(1 - progress, 2) + "}", pos, computePosition.z, 1.8
endfor

Colour: "Black"
Draw inner box
Font size: 6
Marks left: 3, "yes", "yes", "no"
Font size: 7
Text left: "yes", "Height z (m)"
Text bottom: "yes", "Position index"
Text top: "no", "Elevation  —  ceiling/floor at ±" + fixed$(half_z, 2)
    ... + "m  (not encoded in the stereo audio)"

# ----------------------------------------------------------
# Output waveform (L blue, R orange)
# ----------------------------------------------------------
Select outer viewport: 0, 8, 5.20, 6.30
Select inner viewport: 0.55, 7.65, 5.27, 6.23

selectObject: output_stereo
outPeak = Get absolute extremum: 0, 0, "None"
if outPeak < 0.001
    outPeak = 0.001
endif
ampMax = outPeak * 1.15

selectObject: output_stereo
outDur = Get total duration
Axes: 0, outDur, -ampMax, ampMax
Paint rectangle: "{0.97, 0.97, 0.97}", 0, outDur, -ampMax, ampMax
Colour: "{0.80, 0.80, 0.80}"
Draw line: 0, 0, outDur, 0

selectObject: output_stereo
Extract one channel: 1
vizL = selected("Sound")
Colour: "{0.25, 0.50, 0.82}"
Draw: 0, 0, -ampMax, ampMax, "no", "Curve"

selectObject: output_stereo
Extract one channel: 2
vizR = selected("Sound")
Colour: "{0.82, 0.45, 0.25}"
Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
removeObject: vizL, vizR

Colour: "Black"
Draw inner box
Font size: 7
Text left: "yes", "Output"
Text top: "no", "Stereo output  (blue=L  orange=R)"
Text bottom: "yes", "Time (s)"

# ----------------------------------------------------------
# Summary panel
# ----------------------------------------------------------
Select outer viewport: 0, 8, 6.45, 7.30
Select inner viewport: 0.55, 7.65, 6.50, 7.23
Axes: 0, 1, 0, 1
Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
Font size: 7
Colour: "Black"
Text: 0.02, "left", 0.84, "half", "##Summary##"
Font size: 6
Colour: "{0.30, 0.30, 0.30}"
Text: 0.02, "left", 0.60, "half",
    ... "Room: " + fixed$(room_length, 1) + "×" + fixed$(room_width, 1)
    ... + "×" + fixed$(room_height, 1) + "m"
    ... + "  |  Vol: " + fixed$(volume, 0) + " m³"
    ... + "  |  α: " + fixed$(absorption, 2)
    ... + "  |  |R|: " + fixed$(refl, 2)
    ... + "  |  RT60: " + fixed$(rt60, 2) + "s"
    ... + "  |  d_crit: " + fixed$(d_crit, 2) + "m"
Text: 0.02, "left", 0.36, "half",
    ... "Movement: " + movement$
    ... + "  |  Radius: " + fixed$(movement_radius, 2) + "m"
    ... + "  |  Positions: " + string$(num_positions)
    ... + "  |  Hop: " + fixed$(block_dur, 3) + "s"
    ... + "  |  Crossfade: " + fixed$(crossfade_time, 2) + "s"
Text: 0.02, "left", 0.12, "half",
    ... "Panning: " + dbapStr$
    ... + "  |  IR model: " + irStr$
    ... + "  |  IR padding: " + fixed$(ir_padding, 2) + "s"
    ... + "  |  Stereo loudspeaker projection, no HRTF"
Colour: "Black"
Draw rectangle: 0, 1, 0, 1

Font size: 10
Colour: "Black"
Line width: 1

selectObject: output_stereo
Play

appendInfoLine: ""
appendInfoLine: "Done."
appendInfoLine: "Output: STEREO - ", selected$("Sound")
