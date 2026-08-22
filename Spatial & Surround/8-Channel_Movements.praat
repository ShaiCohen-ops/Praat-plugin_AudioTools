# ============================================================
# Praat AudioTools - 8-Channel_Movements.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.6 (2026)
# v0.6 (2026): SPATIAL VISUALIZATION STANDARDIZATION ONLY - label rails, compact summary, typography; DSP unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   8-Channel Spatial Movement Generator.
#   A virtual source is moved on a 2D path around a listener at the
#   centre of an octagon of speakers. Distance from the source to each
#   speaker gives a weight, the weights are normalised to constant
#   power, and the result is written to one IntensityTier per channel.
#   Output as octophonic, stems, or a geometric downmix.
#
#   Speaker layout (y up, angle 0 = front, clockwise):
#     Ch1 FL 315   Ch2 F   0   Ch3 FR  45   Ch4 R  90
#     Ch5 BR 135   Ch6 B 180   Ch7 BL 225   Ch8 L 270
#
# Changelog v0.6 (2026):
#   - FIX: Figure-8 left the path radius. y = r sin(2p) has excursion
#     r*sqrt(25/16) = 1.25 r, so at Path_radius 0.98 the source reached
#     1.225 - outside the speaker ring itself, which contradicts both
#     the field name and the 0.98 guard. y = (r/2) sin(2p) is still a
#     Gerono lemniscate and its maximum radius is exactly r.
#   - FIX: the gain floor broke constant power. v0.4 clamped each
#     finished gain to the floor after normalising, which adds energy
#     the normalisation had already balanced. A tight lobe at a -6 dB
#     floor came out at sum g^2 = 2.56, a 4 dB jump, and a completed
#     fade-out landed sqrt(8) = +9.03 dB above the floor that was asked
#     for - at -6 dB that is +3.03 dB, i.e. louder than unity. The
#     floor is now applied to the WEIGHTS, before normalisation, so
#     sum g^2 = 1 holds for any floor setting. Only a numerical floor
#     of 1e-9 remains, purely to keep log10 defined.
#   - FIX: the claim "sum of squared channel gains = 1 at every
#     instant" was wrong for the global envelopes, where the sum should
#     be envelope(t)^2 - the envelope is meant to scale the whole
#     field. The pipeline now normalises the spatial weights first and
#     applies the envelope afterwards, and the report states this.
#   - FIX: Fade in, Fade out and Triangle still ran to 0 and relied on
#     a clamp, so part of each curve sat flat at the floor instead of
#     moving. They now span floor to unity continuously, as Sine and
#     Exponential already did. Negligible at -60 dB, obvious at -12.
#   - FIX: Gaussian weights could all underflow to zero for a distant
#     Custom position or a high Source_focus, at which point the floor
#     made all eight channels equal and the position vanished. The
#     common factor exp(-focus * d2min) is now divided out before the
#     exponential - it cancels in the normalisation anyway - so the
#     nearest speaker always starts at weight 1.
#   - FIX: the plot sampled the motion far more coarsely than the
#     tiers. Fixed counts of 400 / 240 / 200 gave 1.67 / 1.00 / 0.83
#     points per cycle on a 60 s Figure-8 at speed 2, so the drawn
#     curves were aliased and "measured peak gain" could miss the peak.
#     All three now scale with fMax * duration, capped for drawing
#     speed, and the panel title says so when the display is decimated.
#   - Number_of_points is now natural rather than positive: it is a
#     count, and a fractional value made no sense.
#   - Motion_speed does not apply to every pattern. The form says so
#     and the Info window now lists the active parameters per pattern,
#     including the effective sweep rate 2r/D for Linear sweep.
#   - Custom position outside the speaker ring is reported rather than
#     silently accepted; it stays legal, since the weights still
#     resolve, but the image cannot localise beyond the array.
#
# Changelog v0.4 (2026):
#   The motion engine is rebuilt before any output work, because most
#   of the patterns did not do what their names and the plot promised.
#
#   - FIX (critical): per-channel normalisation destroyed the spatial
#     field. Every channel went through Multiply: "yes", which scales
#     each result independently to a peak of about 0.9. Whatever gain
#     the pattern assigned was therefore discarded: a channel near the
#     source and a channel far from it both arrived at 0.9. Custom
#     position was the clearest casualty - it produced eight nearly
#     identical copies. Multiply is now "no", the eight channels keep
#     their relative levels, and a single shared gain is applied to all
#     of them afterwards. Only the downmix formats normalise again,
#     once, after the sums exist.
#     (Custom position was doubly broken: with the old unit-square
#     coordinates the default 0.5, 0.5 put every speaker between 0.375
#     and 0.400 away, so exp(-10d) spread the eight channels over
#     0.36 dB even before normalisation flattened them.)
#   - FIX: two different speaker geometries were in use - posX/posY on
#     a unit square for Custom position, spkX/spkY on a unit circle for
#     the plot - so the audio and the picture described different
#     rooms. There is now one geometry, on the unit circle, used by the
#     panning, by Custom position, by the plot and by the downmixes.
#   - FIX: circular rotation was rotated 45 degrees against its own
#     speaker map. The gain phase used (ch-1)*45 degrees, i.e. Ch1 at
#     0 degrees, while the map puts Ch1 at 315 and the front speaker is
#     Ch2. At t = 0 the lobe therefore sat on Front-Left while the plot
#     showed the path starting at Front. Gains now come from the real
#     speaker angles, so t = 0 peaks on Ch2 and the lobe travels
#     Ch2 -> Ch3 -> Ch4 clockwise.
#   - FIX: no constant-power normalisation. Summing sinusoids in dB
#     does not hold sum(g^2) = 1, so total level drifted over a
#     rotation. Weights are now computed linearly, normalised by
#     sqrt(sum w^2), and only then converted to dB. With the source at
#     the centre every channel sits at exactly -9.03 dB, i.e. 1/sqrt(8).
#   - FIX: Figure-8 was not a figure-8. The plot drew the Gerono
#     lemniscate x = A sin(wt), y = B sin(2wt), but the audio used a
#     single sinusoid with per-channel phase offsets - one lobe going
#     round the octagon at double speed in the opposite direction, with
#     no second coordinate and no crossing of the centre. Both now come
#     from the same lemniscate.
#   - FIX: Random walk was not a random walk. It was eight
#     deterministic sinusoids at different phases: no random numbers,
#     no dependence on the previous step, no bounded path. It is now a
#     real walk - momentum plus pseudo-random increments, reflected at
#     the path radius - reproducible from Random_seed, since Praat has
#     no seedable RNG and the old version was not reproducible either.
#   - FIX: Spiral had no radius. The old formula only scaled the
#     modulation depth by t/D, which widens the contrast between
#     channels but never moves a source outwards. The plot always drew
#     exactly one turn while the audio performed motion_speed * D of
#     them. Both now use r(t) = r_max * t/D with the same turn count.
#   - FIX: Linear sweep was not left to right. Peaking Ch1..Ch8 in
#     order walks around the octagon: FL, F, FR, R, BR, B, BL, L. It is
#     now a straight path across x with y = 0, so it really does travel
#     Ch8 (Left) to Ch4 (Right). The old peak spacing (ch-1)/8 also
#     left Ch8 peaking at 0.875 D rather than at the end.
#   - FIX: patterns 1-6 are global amplitude envelopes, not movement -
#     all eight channels received an identical curve. They are labelled
#     [GLOBAL] in the menu and are now applied to a centred source, so
#     they combine with an even eight-channel distribution instead of
#     pretending to be spatial.
#   - FIX: Sine wave spanned 50..150 dB rather than the stated 30..100,
#     since it was Amplitude+50+Amplitude*sin. The plot clipped at
#     max+8, hiding 42 dB of it. Fade in, Fade out and Triangle ignored
#     Min_volume entirely and ran to 0. Exponential decay used absolute
#     seconds, so the same exponent behaved completely differently on a
#     2 s and a 30 s file. All are now defined on normalised time as
#     linear gains between the floor and unity.
#   - FIX: IntensityTier values are relative gains in dB, not SPL. The
#     old fields asked for 30..100 dB, which is a linear gain of 31.6
#     to 100000 - a 3162:1 ratio, and only Multiply's own rescaling hid
#     it. Min_volume, Max_volume and Amplitude are replaced by Floor_db
#     (default -60 dB), and the tier now carries attenuation: 0 dB for
#     unity, negative for quieter.
#   - FIX: point density. The tier interpolates linearly between
#     points, and 100 points over a 60 s file at speed 2 gives 0.83
#     points per cycle - the motion is simply not represented.
#     Number_of_points is now a floor; the script computes 30 points
#     per cycle of the fastest component (2f for Figure-8) and raises
#     it when needed, reporting the change.
#   - FIX: stereo input produced 16 channels, not 8. The source was
#     copied eight times without a mono conversion, so each channel
#     object stayed stereo and Combine to stereo summed the channel
#     counts. The source is converted to mono first.
#   - NEW: Output_format menu, with geometric routing rather than the
#     canon's positional one.
#       1  8 channels - octophonic
#       2  4 opposing stereo pairs   Ch1|Ch5 Ch2|Ch6 Ch3|Ch7 Ch4|Ch8
#       3  2 quadraphonic groups     diagonal Ch1357, cardinal Ch2468
#       4  4-channel fold-down       FL FR BR BL, diagonals direct and
#                                    cardinals split equal-power to the
#                                    two speakers either side
#       5  Stereo fold-down          equal-power from each speaker's x
#     The pairs are opposing axes, not adjacent channels, so a pair is
#     a through-the-listener axis. The quad split is diagonal against
#     cardinal, which is a real 45-degree rotation, rather than Ch1-4
#     against Ch5-8 which would cut the octagon in half. The 4-channel
#     fold-down must not use Ch1+Ch5: that sums opposite corners into
#     one speaker and cancels the movement.
#   - NEW: the plot is generated from the same procedures as the audio.
#     The path in Panel A, the curves in Panel B and the peaks in Panel
#     C all call the trajectory and gain routines the tiers were built
#     from. Panel C previously drew max_volume for almost every pattern
#     regardless of what the channel actually did.
#
# Changelog v0.3:
#   - Resized visualization from non-standard 10x canvas to 8x8
#   - Multi-panel layout; all 8 channels visualized
# ============================================================

# === Check Input (before the form, so a bad selection costs nothing) ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

form 8-Channel Spatial Movements
    comment === MOVEMENT PATTERN ===
    optionmenu Pattern: 8
        option: "1. [GLOBAL] Sine wave (no spatial movement)"
        option: "2. [GLOBAL] Fade in"
        option: "3. [GLOBAL] Fade out"
        option: "4. [GLOBAL] Triangle envelope"
        option: "5. [GLOBAL] Constant"
        option: "6. [GLOBAL] Exponential decay"
        option: "7. [SPATIAL] Linear sweep (Left to Right)"
        option: "8. [SPATIAL] Circular rotation"
        option: "9. [SPATIAL] Figure-8"
        option: "10. [SPATIAL] Random walk (bounded)"
        option: "11. [SPATIAL] Spiral (centre outwards)"
        option: "12. [SPATIAL] Custom fixed position"

    comment === TIMING (Motion_speed: Circular, Figure-8, Spiral, Walk only) ===
    positive Motion_speed 1.0
    positive Frequency_hz 2.0
    positive Fadein_time 1.0
    positive Exponent 1.0

    comment === SPATIAL (speakers sit on the unit circle, r = 1) ===
    positive Path_radius 0.7
    positive Source_focus 2.0
    real Custom_x 0.0
    real Custom_y 0.0

    comment === GAIN (tier holds relative dB: 0 = unity) ===
    real Floor_db -60.0
    positive Scale_peak 0.95

    comment === QUALITY ===
    natural Number_of_points 100
    integer Random_seed 1

    comment === OUTPUT FORMAT ===
    optionmenu Output_format: 1
        option: "8 channels - octophonic (Ch1-Ch8)"
        option: "4 opposing stereo pairs (Ch1|Ch5, Ch2|Ch6, Ch3|Ch7, Ch4|Ch8)"
        option: "2 quadraphonic groups (diagonal Ch1357, cardinal Ch2468)"
        option: "4-channel fold-down (FL, FR, BR, BL)"
        option: "Stereo fold-down (equal-power from speaker x)"

    comment === OUTPUT ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Pattern name and class ===
if pattern = 1
    patternName$ = "SineWave"
elsif pattern = 2
    patternName$ = "FadeIn"
elsif pattern = 3
    patternName$ = "FadeOut"
elsif pattern = 4
    patternName$ = "Triangle"
elsif pattern = 5
    patternName$ = "Constant"
elsif pattern = 6
    patternName$ = "Exponential"
elsif pattern = 7
    patternName$ = "LinearSweep"
elsif pattern = 8
    patternName$ = "Circular"
elsif pattern = 9
    patternName$ = "Figure8"
elsif pattern = 10
    patternName$ = "RandomWalk"
elsif pattern = 11
    patternName$ = "Spiral"
else
    patternName$ = "CustomPos"
endif

if pattern <= 6
    isSpatial = 0
    classLabel$ = "global envelope"
else
    isSpatial = 1
    classLabel$ = "spatial trajectory"
endif

# === Guards ===
if floor_db > -6
    floor_db = -6
endif
if floor_db < -120
    floor_db = -120
endif
gFloorLin = 10 ^ (floor_db / 20)

if scale_peak > 1
    scale_peak = 1
endif

if path_radius > 0.98
    path_radius = 0.98
endif

# === Input: mono working copy ===
# v0.4: without this a stereo source gives eight stereo channel objects
# and Combine to stereo produces sixteen channels, not eight.
sound = selected("Sound")
soundName$ = selected$("Sound")
duration = Get total duration
srcChannels = Get number of channels

if srcChannels > 1
    Convert to mono
    monoID = selected("Sound")
    wasMulti = 1
else
    Copy: "mv_mono"
    monoID = selected("Sound")
    wasMulti = 0
endif
selectObject: monoID
Rename: "mv_source"

# ============================================================
# SPEAKER GEOMETRY - one definition for audio, plot and downmix
# ============================================================
# y up, angle 0 = front, increasing clockwise. x = sin, y = cos.

spkAngleDeg[1] = 315
spkAngleDeg[2] = 0
spkAngleDeg[3] = 45
spkAngleDeg[4] = 90
spkAngleDeg[5] = 135
spkAngleDeg[6] = 180
spkAngleDeg[7] = 225
spkAngleDeg[8] = 270

spkName$[1] = "FL"
spkName$[2] = "F"
spkName$[3] = "FR"
spkName$[4] = "R"
spkName$[5] = "BR"
spkName$[6] = "B"
spkName$[7] = "BL"
spkName$[8] = "L"

for k from 1 to 8
    spkAng = spkAngleDeg[k] * pi / 180
    spkX[k] = sin(spkAng)
    spkY[k] = cos(spkAng)
endfor

# ============================================================
# POINT DENSITY
# ============================================================
# The tier interpolates linearly between points, so the grid has to
# resolve the fastest component of the motion. 30 points per cycle.

if pattern = 9
    fMax = 2 * motion_speed
elsif pattern = 8 or pattern = 11
    fMax = motion_speed
elsif pattern = 1
    fMax = frequency_hz
elsif pattern = 10
    fMax = 4 * motion_speed
else
    fMax = 1 / duration
endif

ptsNeeded = ceiling(30 * fMax * duration)
if ptsNeeded < 50
    ptsNeeded = 50
endif

nPoints = number_of_points
pointsRaised = 0
pointsCapped = 0
if ptsNeeded > nPoints
    nPoints = ptsNeeded
    pointsRaised = 1
endif
# Each point costs eight Add point calls, so the cap keeps a long,
# fast-moving file from taking minutes to build.
if nPoints > 12000
    nPoints = 12000
    pointsCapped = 1
endif

# ============================================================
# PROCEDURES
# ============================================================

# Deterministic pseudo-random value in [-1, 1] from an index and a lane.
# Praat has no seedable RNG, so the walk is built from a hash of
# Random_seed instead: same seed, same path, every run.
procedure hashv: .i, .lane
    .v = sin(.i * 12.9898 + .lane * 78.233 + random_seed * 3.71) * 43758.5453
    .h = 2 * (.v - floor(.v)) - 1
endproc

# Random walk waypoints, precomputed once. Momentum plus random
# increments, reflected at path_radius so the path stays bounded.
# The waypoint count depends only on speed and duration, so the shape
# does not change when Number_of_points changes.
nWalk = ceiling(4 * motion_speed * duration)
if nWalk < 8
    nWalk = 8
endif
if nWalk > 4000
    nWalk = 4000
endif

procedure buildWalk
    .wx = 0
    .wy = 0
    .vx = 0
    .vy = 0
    .step = path_radius * 0.12
    for .i from 0 to nWalk
        walkX[.i] = .wx
        walkY[.i] = .wy
        @hashv: .i, 1
        .h1 = hashv.h
        @hashv: .i, 2
        .h2 = hashv.h
        .vx = 0.8 * .vx + .step * .h1
        .vy = 0.8 * .vy + .step * .h2
        .wx = .wx + .vx
        .wy = .wy + .vy
        .rr = sqrt(.wx * .wx + .wy * .wy)
        if .rr > path_radius and .rr > 0
            .nx = .wx / .rr
            .ny = .wy / .rr
            .wx = .nx * path_radius
            .wy = .ny * path_radius
            .vdotn = .vx * .nx + .vy * .ny
            .vx = .vx - 2 * .vdotn * .nx
            .vy = .vy - 2 * .vdotn * .ny
        endif
    endfor
endproc

if pattern = 10
    @buildWalk
endif

# Source position at time .t, in the same unit-circle space as the
# speakers. This is the single definition the audio and the plot share.
procedure trajectory: .t
    .u = .t / duration
    if .u < 0
        .u = 0
    endif
    if .u > 1
        .u = 1
    endif
    .phase = 2 * pi * motion_speed * .t

    if pattern = 7
        # True left to right: Ch8 (Left) to Ch4 (Right), y held at 0.
        .x = -path_radius + 2 * path_radius * .u
        .y = 0
    elsif pattern = 8
        # Clockwise from Front at t = 0
        .x = path_radius * sin(.phase)
        .y = path_radius * cos(.phase)
    elsif pattern = 9
        # Gerono lemniscate, normalised so max |position| = path_radius.
        # v0.4 used y = r sin(2p), whose excursion is r*sqrt(25/16) =
        # 1.25 r: at Path_radius 0.98 the source reached 1.225, outside
        # the speaker ring itself. Halving y gives exactly r.
        .x = path_radius * sin(.phase)
        .y = path_radius * 0.5 * sin(2 * .phase)
    elsif pattern = 10
        .p = .u * nWalk
        .i0 = floor(.p)
        if .i0 > nWalk - 1
            .i0 = nWalk - 1
        endif
        if .i0 < 0
            .i0 = 0
        endif
        .f = .p - .i0
        .x = walkX[.i0] + .f * (walkX[.i0 + 1] - walkX[.i0])
        .y = walkY[.i0] + .f * (walkY[.i0 + 1] - walkY[.i0])
    elsif pattern = 11
        # Radius really grows from the centre outwards
        .r = path_radius * .u
        .x = .r * sin(.phase)
        .y = .r * cos(.phase)
    elsif pattern = 12
        .x = custom_x
        .y = custom_y
    else
        # Global envelopes: source stays at the listener position, so
        # the eight channels share one even distribution.
        .x = 0
        .y = 0
    endif
endproc

# Global amplitude envelope as a linear gain in [gFloorLin, 1].
# Defined on normalised time, so the same settings behave the same way
# on a 2 s and a 30 s source.
procedure envelope: .t
    .u = .t / duration
    if .u > 1
        .u = 1
    endif
    if pattern = 1
        .g = gFloorLin + (1 - gFloorLin) * (1 + sin(2 * pi * frequency_hz * .t)) / 2
    elsif pattern = 2
        # v0.6: spans the floor to unity. v0.4 started at 0 and relied
        # on a clamp, so the first part of the fade was flat at the
        # floor - inaudible at -60 dB, very audible at -12 or -6.
        if fadein_time > 0 and .t < fadein_time
            .g = gFloorLin + (1 - gFloorLin) * (.t / fadein_time)
        else
            .g = 1
        endif
    elsif pattern = 3
        .g = gFloorLin + (1 - gFloorLin) * (1 - .u)
    elsif pattern = 4
        .g = gFloorLin + (1 - gFloorLin) * (1 - 2 * abs(.u - 0.5))
    elsif pattern = 5
        .g = 1
    elsif pattern = 6
        # Starts exactly at unity, ends exactly at the floor
        .g = gFloorLin ^ (.u ^ exponent)
    else
        .g = 1
    endif
    if .g < gFloorLin
        .g = gFloorLin
    endif
endproc

# Constant-power channel gains at time .t, left in gw[1..8].
# Gaussian weights on distance, then g_i = w_i / sqrt(sum w_j^2), so
# sum g_i^2 = 1 at every instant. Source at the centre gives every
# channel 1/sqrt(8) = -9.03 dB.
procedure computeGains: .t
    @trajectory: .t

    # Squared distances, and the closest speaker.
    .d2min = 1e300
    for .k from 1 to 8
        .dx = trajectory.x - spkX[.k]
        .dy = trajectory.y - spkY[.k]
        d2[.k] = .dx * .dx + .dy * .dy
        if d2[.k] < .d2min
            .d2min = d2[.k]
        endif
    endfor

    # v0.6: the common factor exp(-focus * d2min) cancels in the
    # normalisation anyway, so factoring it out costs nothing and stops
    # every weight underflowing to zero when the source is far away or
    # the focus is high. The nearest speaker always starts at 1.
    for .k from 1 to 8
        gw[.k] = exp(-source_focus * (d2[.k] - .d2min))
        if gw[.k] < gFloorLin
            gw[.k] = gFloorLin
        endif
    endfor

    # v0.6: the floor is applied to the WEIGHTS, before normalisation.
    # v0.4 clamped the finished gains channel by channel, which added
    # energy the normalisation had already accounted for: at a -6 dB
    # floor a tight lobe came out at sum g^2 = 2.56, a 4 dB level jump,
    # and a completed fade-out landed sqrt(8) = +9.03 dB above the
    # floor the user asked for. Flooring first and normalising after
    # keeps sum g^2 = 1 for any floor setting.
    .sumsq = 0
    for .k from 1 to 8
        .sumsq = .sumsq + gw[.k] * gw[.k]
    endfor
    .norm = sqrt(.sumsq)
    if .norm < 1e-12
        .norm = 1e-12
    endif
    for .k from 1 to 8
        gw[.k] = gw[.k] / .norm
    endfor

    # The global envelope scales the whole field, so sum g^2 = e(t)^2.
    # For the spatial trajectories e = 1 and sum g^2 = 1 exactly.
    @envelope: .t
    for .k from 1 to 8
        gw[.k] = gw[.k] * envelope.g
        # Numerical floor for log10 only - deliberately far below any
        # audible level, so it never acts as a gain floor.
        if gw[.k] < 1e-9
            gw[.k] = 1e-9
        endif
    endfor
endproc

# ============================================================
# BUILD THE EIGHT CHANNELS
# ============================================================

for ch from 1 to 8
    selectObject: monoID
    channel[ch] = Copy: "mvch" + string$(ch)
endfor

for ch from 1 to 8
    intensityTier[ch] = Create IntensityTier: "mvint" + string$(ch), 0, duration
endfor

# Point-outer: the constant-power normalisation needs all eight weights
# at each instant anyway, so computing them once per point and writing
# to all eight tiers costs one eighth of the arithmetic of a
# channel-outer loop.
for i from 0 to nPoints
    t = i * duration / nPoints
    @computeGains: t
    for ch from 1 to 8
        selectObject: intensityTier[ch]
        Add point: t, 20 * log10(gw[ch])
    endfor
endfor

# v0.4: Multiply "no". With "yes" every channel was rescaled to its own
# peak of 0.9 and the whole spatial field was thrown away.
for ch from 1 to 8
    selectObject: channel[ch], intensityTier[ch]
    result[ch] = Multiply: "no"
    Rename: "mvout" + string$(ch)
endfor

# ============================================================
# SHARED-GAIN NORMALISATION
# ============================================================
# Stage 1: one gain from the loudest of the eight, applied to all eight,
# so the relative field survives. Stage 2 (downmix formats only) below.

peakAll = 0
for ch from 1 to 8
    selectObject: result[ch]
    thisPeak = Get absolute extremum: 0, 0, "None"
    if thisPeak > peakAll
        peakAll = thisPeak
    endif
endfor
if peakAll < 1e-9
    peakAll = 1e-9
endif
sharedGain = scale_peak / peakAll
sharedGain$ = fixed$(sharedGain, 10)

for ch from 1 to 8
    selectObject: result[ch]
    Formula: "self * " + sharedGain$
endfor

# ============================================================
# DOWNMIX WEIGHT MATRICES
# ============================================================
# wmix[outChannel, sourceChannel]. Zero means the channel does not
# contribute. Every output channel of a given format ends up with the
# same number of contributions, so the divide-by-N that Convert to mono
# applies is uniform and the balance between output channels is intact.

# Flat indexing: wmix[(out - 1) * 8 + src], to stay on Praat's
# one-dimensional indexed variables.
for o from 1 to 4
    for s from 1 to 8
        wmix[(o - 1) * 8 + s] = 0
    endfor
endfor

if output_format = 4
    # FL FR BR BL. Diagonals pass straight through; each cardinal
    # speaker is split equal-power between the two corners beside it.
    # Ch1+Ch5 style pairing is wrong here - it would sum opposite
    # corners of the octagon into one speaker and cancel the movement.
    half = 1 / sqrt(2)
    wmix[1] = 1
    wmix[2] = half
    wmix[8] = half
    wmix[8 + 3] = 1
    wmix[8 + 2] = half
    wmix[8 + 4] = half
    wmix[16 + 5] = 1
    wmix[16 + 4] = half
    wmix[16 + 6] = half
    wmix[24 + 7] = 1
    wmix[24 + 6] = half
    wmix[24 + 8] = half
    foldName$[1] = "FL"
    foldName$[2] = "FR"
    foldName$[3] = "BR"
    foldName$[4] = "BL"
endif

# Stereo fold-down: each speaker is panned by its own x coordinate.
# p = x / r, gL = cos(pi/4 (p+1)), gR = sin(pi/4 (p+1)), so Ch8 (Left)
# goes hard left, Ch4 (Right) hard right, Ch2 and Ch6 split evenly, and
# the diagonals follow their horizontal position. Front/back is lost by
# construction; left/right survives.
for s from 1 to 8
    ppos = spkX[s]
    if ppos < -1
        ppos = -1
    endif
    if ppos > 1
        ppos = 1
    endif
    aPan = (ppos + 1) * pi / 4
    stereoL[s] = cos(aPan)
    stereoR[s] = sin(aPan)
endfor

# ============================================================
# FORMAT LABELS
# ============================================================
if output_format = 1
    formatName$ = "8-channel octophonic"
    mapLine$ = "out1-out8 = Ch1-Ch8"
elsif output_format = 2
    formatName$ = "4 opposing stereo pairs"
    mapLine$ = "Ch1|Ch5  Ch2|Ch6  Ch3|Ch7  Ch4|Ch8  (opposing axes)"
elsif output_format = 3
    formatName$ = "2 quadraphonic groups"
    mapLine$ = "diagonal = Ch1 Ch3 Ch5 Ch7    cardinal = Ch2 Ch4 Ch6 Ch8"
elsif output_format = 4
    formatName$ = "4-channel fold-down"
    mapLine$ = "FL FR BR BL, cardinals split equal-power to both sides"
else
    formatName$ = "Stereo fold-down"
    mapLine$ = "equal-power pan from each speaker's x coordinate"
endif

needStereoFold = 0
if output_format = 2 or output_format = 3 or output_format = 5
    needStereoFold = 1
endif

# ============================================================
# STEREO FOLD  (format 5 output, and the preview for stem formats)
# ============================================================

if needStereoFold
    # Left
    nL = 0
    for s from 1 to 8
        if stereoL[s] > 1e-6
            selectObject: result[s]
            Copy: "mvtmpL" + string$(s)
            nL = nL + 1
            tmpL[nL] = selected("Sound")
            Formula: "self * " + fixed$(stereoL[s], 8)
        endif
    endfor
    selectObject: tmpL[1]
    for k from 2 to nL
        plusObject: tmpL[k]
    endfor
    Combine to stereo
    stackL = selected("Sound")
    Convert to mono
    mixL = selected("Sound")
    Rename: "mv_mixL"
    removeObject: stackL
    for k from 1 to nL
        removeObject: tmpL[k]
    endfor

    # Right
    nR = 0
    for s from 1 to 8
        if stereoR[s] > 1e-6
            selectObject: result[s]
            Copy: "mvtmpR" + string$(s)
            nR = nR + 1
            tmpR[nR] = selected("Sound")
            Formula: "self * " + fixed$(stereoR[s], 8)
        endif
    endfor
    selectObject: tmpR[1]
    for k from 2 to nR
        plusObject: tmpR[k]
    endfor
    Combine to stereo
    stackR = selected("Sound")
    Convert to mono
    mixR = selected("Sound")
    Rename: "mv_mixR"
    removeObject: stackR
    for k from 1 to nR
        removeObject: tmpR[k]
    endfor
endif

# ============================================================
# OUTPUT FORMAT BRANCH
# ============================================================

downmixNorm = 0
monitorID = 0

if output_format = 1
    selectObject: result[1], result[2], result[3], result[4],
        ... result[5], result[6], result[7], result[8]
    Combine to stereo
    out[1] = selected("Sound")
    Rename: soundName$ + "_8chMove_" + patternName$
    outCount = 1
    outChannels = 8

elsif output_format = 2
    # Opposing axes: each pair is a line through the listener.
    pairA[1] = 1
    pairB[1] = 5
    pairA[2] = 2
    pairB[2] = 6
    pairA[3] = 3
    pairB[3] = 7
    pairA[4] = 4
    pairB[4] = 8
    for k from 1 to 4
        selectObject: result[pairA[k]], result[pairB[k]]
        Combine to stereo
        out[k] = selected("Sound")
        Rename: soundName$ + "_move_axis_" + spkName$[pairA[k]]
            ... + spkName$[pairB[k]] + "_" + patternName$
    endfor
    outCount = 4
    outChannels = 2

elsif output_format = 3
    # Diagonal quad (a conventional quad) against cardinal quad (the
    # same square rotated 45 degrees). Ch1-4 against Ch5-8 would just
    # cut the octagon into two halves.
    selectObject: result[1], result[3], result[5], result[7]
    Combine to stereo
    out[1] = selected("Sound")
    Rename: soundName$ + "_move_quad_diagonal_" + patternName$
    selectObject: result[2], result[4], result[6], result[8]
    Combine to stereo
    out[2] = selected("Sound")
    Rename: soundName$ + "_move_quad_cardinal_" + patternName$
    outCount = 2
    outChannels = 4

elsif output_format = 4
    for o from 1 to 4
        nC = 0
        for s from 1 to 8
            if wmix[(o - 1) * 8 + s] > 1e-6
                selectObject: result[s]
                Copy: "mvfold" + string$(o) + "_" + string$(s)
                nC = nC + 1
                tmpF[nC] = selected("Sound")
                Formula: "self * " + fixed$(wmix[(o - 1) * 8 + s], 8)
            endif
        endfor
        selectObject: tmpF[1]
        for k from 2 to nC
            plusObject: tmpF[k]
        endfor
        Combine to stereo
        stackF = selected("Sound")
        Convert to mono
        foldCh[o] = selected("Sound")
        Rename: "mv_fold_" + foldName$[o]
        removeObject: stackF
        for k from 1 to nC
            removeObject: tmpF[k]
        endfor
    endfor
    selectObject: foldCh[1], foldCh[2], foldCh[3], foldCh[4]
    Combine to stereo
    out[1] = selected("Sound")
    Rename: soundName$ + "_move_fold4_" + patternName$
    Scale peak: scale_peak
    downmixNorm = 1
    outCount = 1
    outChannels = 4
    removeObject: foldCh[1], foldCh[2], foldCh[3], foldCh[4]

else
    selectObject: mixL, mixR
    Combine to stereo
    out[1] = selected("Sound")
    Rename: soundName$ + "_move_stereo_" + patternName$
    Scale peak: scale_peak
    downmixNorm = 1
    outCount = 1
    outChannels = 2
endif

# Preview mix for the stem formats, from the same stereo fold
if output_format = 2 or output_format = 3
    selectObject: mixL, mixR
    Combine to stereo
    monitorID = selected("Sound")
    Rename: "mv_monitor"
    Scale peak: scale_peak
endif

if needStereoFold
    removeObject: mixL, mixR
endif

# ============================================================
# INFO
# ============================================================
writeInfoLine: "=== 8-Channel Spatial Movements ==="
appendInfoLine: "Source: ", soundName$, "  (", fixed$(duration, 2), " s)"
if wasMulti = 1
    appendInfoLine: "  input had ", srcChannels, " channels - converted to mono"
endif
appendInfoLine: "Pattern: ", patternName$, "  (", classLabel$, ")"
if isSpatial = 0
    appendInfoLine: "  All eight channels receive the same curve; the source is"
    appendInfoLine: "  held at the listener position. This is an amplitude"
    appendInfoLine: "  envelope, not spatial movement."
endif
appendInfoLine: ""
appendInfoLine: "Geometry: octagon on the unit circle, listener at the origin"
for ch from 1 to 8
    appendInfoLine: "  Ch", ch, " ", spkName$[ch], "  ", spkAngleDeg[ch], " deg   x=",
        ... fixed$(spkX[ch], 3), "  y=", fixed$(spkY[ch], 3)
endfor
appendInfoLine: ""
if isSpatial = 1
    appendInfoLine: "Path radius: ", fixed$(path_radius, 2),
        ... "   focus: ", fixed$(source_focus, 2)
endif
if pattern = 12
    customR = sqrt(custom_x * custom_x + custom_y * custom_y)
    appendInfoLine: "Custom position: x=", fixed$(custom_x, 3), "  y=",
        ... fixed$(custom_y, 3), "   radius=", fixed$(customR, 3)
    if customR > 1
        appendInfoLine: "  NOTE: this is outside the speaker ring (r = 1). That is"
        appendInfoLine: "  allowed - the weights still resolve - but the source cannot"
        appendInfoLine: "  be localised beyond the array, so the image will sit on the"
        appendInfoLine: "  nearest speakers and simply lose focus as radius grows."
    endif
endif
appendInfoLine: "Tier points: ", nPoints, " (", fixed$(nPoints / (fMax * duration), 1),
    ... " per cycle of the fastest component)"
if pointsRaised = 1
    appendInfoLine: "  raised from ", number_of_points,
        ... " - the requested count could not represent the motion"
endif
if pointsCapped = 1
    appendInfoLine: "  capped at 12000 points; reduce Motion_speed for finer motion"
endif
appendInfoLine: "Gain floor: ", fixed$(floor_db, 1), " dB"
appendInfoLine: "Spatial gains are constant-power before the global envelope:"
appendInfoLine: "  sum of squared channel gains = 1, and the envelope then scales"
appendInfoLine: "  the whole field, so the sum equals envelope^2 at each instant."
appendInfoLine: "  (source at centre gives every channel 1/sqrt(8) = -9.03 dB)"
appendInfoLine: "  Floor_db is a bleed floor on the spatial weights, applied before"
appendInfoLine: "  normalisation, so it never inflates the total field level." 

appendInfoLine: ""
appendInfoLine: "Active parameters for this pattern:"
if pattern = 8 or pattern = 9 or pattern = 11
    appendInfoLine: "  Motion_speed (cycles/s), Path_radius, Source_focus"
elsif pattern = 10
    appendInfoLine: "  Motion_speed (waypoint rate = 4x speed), Path_radius,"
    appendInfoLine: "  Source_focus, Random_seed"
elsif pattern = 7
    appendInfoLine: "  Path_radius, Source_focus. Motion_speed is NOT used: the"
    appendInfoLine: "  sweep always spans the whole file, so its rate is 2r/D = ",
        ... fixed$(2 * path_radius / duration, 4), " per second."
elsif pattern = 12
    appendInfoLine: "  Custom_x, Custom_y, Source_focus. Motion_speed is not used."
elsif pattern = 1
    appendInfoLine: "  Frequency_hz, Floor_db. Motion_speed and Path_radius are not used."
elsif pattern = 2
    appendInfoLine: "  Fadein_time, Floor_db."
elsif pattern = 6
    appendInfoLine: "  Exponent, Floor_db."
else
    appendInfoLine: "  Floor_db only."
endif

appendInfoLine: ""
appendInfoLine: "Output format: ", formatName$
appendInfoLine: "Objects: ", outCount, "  |  channels each: ", outChannels
if output_format = 1
    appendInfoLine: "  out1-out8: Ch1 - Ch8"
elsif output_format = 2
    for k from 1 to 4
        appendInfoLine: "  Axis ", k, ": Ch", pairA[k], " (", spkName$[pairA[k]],
            ... ") -> L,  Ch", pairB[k], " (", spkName$[pairB[k]], ") -> R"
    endfor
elsif output_format = 3
    appendInfoLine: "  Diagonal quad: Ch1 FL, Ch3 FR, Ch5 BR, Ch7 BL"
    appendInfoLine: "  Cardinal quad: Ch2 F,  Ch4 R,  Ch6 B,  Ch8 L"
elsif output_format = 4
    appendInfoLine: "  FL = Ch1 + 0.707*(Ch2 + Ch8)"
    appendInfoLine: "  FR = Ch3 + 0.707*(Ch2 + Ch4)"
    appendInfoLine: "  BR = Ch5 + 0.707*(Ch4 + Ch6)"
    appendInfoLine: "  BL = Ch7 + 0.707*(Ch6 + Ch8)"
else
    for s from 1 to 8
        appendInfoLine: "  Ch", s, " ", spkName$[s], "  L=", fixed$(stereoL[s], 3),
            ... "  R=", fixed$(stereoR[s], 3)
    endfor
endif

appendInfoLine: ""
appendInfoLine: "Normalisation:"
appendInfoLine: "  Shared gain across all eight channels: x", fixed$(sharedGain, 4),
    ... " (from peak ", fixed$(peakAll, 4), ")"
if downmixNorm = 1
    appendInfoLine: "  Final peak normalisation after downmix: Scale peak ",
        ... fixed$(scale_peak, 3)
else
    appendInfoLine: "  No downmix, so no second normalisation stage."
endif

if outCount = 1
    objWord$ = " object"
else
    objWord$ = " objects"
endif

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================
# v0.4: every panel is generated by the same procedures the tiers were
# built from, so the picture cannot drift away from the audio.

if draw_visualization

    # v0.6: the plot only verifies the audio if it samples the motion at
    # a comparable density. v0.4 used fixed 400 / 240 / 200 points, which
    # on a 60 s Figure-8 at speed 2 (fastest component 4 Hz) gave 1.67,
    # 1.00 and 0.83 points per cycle - the curves were aliased and the
    # "measured peak" could miss the real peak entirely. These now scale
    # with fMax * duration, capped so drawing stays responsive.
    vizBase = ceiling(24 * fMax * duration)

    nPath = vizBase
    if nPath < 400
        nPath = 400
    endif
    if nPath > 2000
        nPath = 2000
    endif

    nCurve = vizBase
    if nCurve < 240
        nCurve = 240
    endif
    if nCurve > 1500
        nCurve = 1500
    endif

    # Arithmetic only, no drawing, so this one can be dense.
    nScan = ceiling(60 * fMax * duration)
    if nScan < 400
        nScan = 400
    endif
    if nScan > 8000
        nScan = 8000
    endif

    curvePerCycle = nCurve / (fMax * duration)
    if curvePerCycle < 8
        vizNote$ = "  [display decimated: " + fixed$(curvePerCycle, 1) + " pts/cycle]"
    else
        vizNote$ = ""
    endif

    Erase all

    chColR[1] = 0.80
    chColG[1] = 0.20
    chColB[1] = 0.20
    chColR[2] = 0.20
    chColG[2] = 0.65
    chColB[2] = 0.20
    chColR[3] = 0.20
    chColG[3] = 0.25
    chColB[3] = 0.85
    chColR[4] = 0.75
    chColG[4] = 0.48
    chColB[4] = 0.10
    chColR[5] = 0.60
    chColG[5] = 0.20
    chColB[5] = 0.70
    chColR[6] = 0.15
    chColG[6] = 0.65
    chColB[6] = 0.72
    chColR[7] = 0.72
    chColG[7] = 0.68
    chColB[7] = 0.10
    chColR[8] = 0.50
    chColG[8] = 0.50
    chColB[8] = 0.50

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##8-CHANNEL SPATIAL MOVEMENTS v0.6##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... soundName$
        ... + "  |  " + patternName$ + " (" + classLabel$ + ")"
        ... + "  |  " + fixed$(duration, 2) + " s"
        ... + "  |  Speed: " + fixed$(motion_speed, 2)
        ... + "  |  Format: " + formatName$

    # ----------------------------------------------------------
    # PANEL A: OCTAGON MAP WITH THE ACTUAL PATH  (left column)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.85, 4.34

    Axes: -1.45, 1.45, -1.45, 1.45
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.45, 1.45, -1.45, 1.45

    Colour: "{0.88, 0.88, 0.88}"
    Line width: 1
    Draw ellipse: -1, 1, -1, 1
    Draw ellipse: -0.5, 0.5, -0.5, 0.5
    Draw line: 0, -1.35, 0, 1.35
    Draw line: -1.35, 0, 1.35, 0

    # Octagon outline
    Colour: "{0.82, 0.82, 0.82}"
    for k from 1 to 8
        k2 = (k mod 8) + 1
        Draw line: spkX[k], spkY[k], spkX[k2], spkY[k2]
    endfor

    # The path, from the same procedure the tiers used
    if isSpatial = 1
        Line width: 2
        @trajectory: 0
        prevPX = trajectory.x
        prevPY = trajectory.y
        for j from 1 to nPath
            tj = j * duration / nPath
            @trajectory: tj
            frac = j / nPath
            Colour: "{" + fixed$(0.30 + frac * 0.55, 2) + ", "
                ... + fixed$(0.30 - frac * 0.12, 2) + ", "
                ... + fixed$(0.75 - frac * 0.50, 2) + "}"
            Draw line: prevPX, prevPY, trajectory.x, trajectory.y
            prevPX = trajectory.x
            prevPY = trajectory.y
        endfor
        Line width: 1
        # Start marker
        @trajectory: 0
        Paint circle (mm): "{0.10, 0.30, 0.85}", trajectory.x, trajectory.y, 3
    else
        Paint circle (mm): "{0.55, 0.55, 0.55}", 0, 0, 4
        Font size: 6
        Colour: "{0.40, 0.40, 0.40}"
        Text: 0, "centre", -0.30, "half", "no spatial movement"
    endif

    # Speaker dots, sized by their gain at t = 0
    @computeGains: 0
    for k from 1 to 8
        dotR = 2.5 + 4.5 * gw[k]
        Paint circle (mm): "{" + fixed$(chColR[k], 2) + ", " + fixed$(chColG[k], 2)
            ... + ", " + fixed$(chColB[k], 2) + "}", spkX[k], spkY[k], dotR
        Colour: "White"
        Font size: 6
        Text: spkX[k], "centre", spkY[k], "half", string$(k)
        Colour: "{0.40, 0.40, 0.40}"
        Font size: 6
        Text: spkX[k] * 1.24, "centre", spkY[k] * 1.24, "half", spkName$[k]
    endfor

    Paint circle (mm): "{0.22, 0.62, 0.30}", 0, 0, 3
    Colour: "Black"
    Line width: 1
    Draw inner box

    # ----------------------------------------------------------
    # PANEL B: THE EIGHT GAIN CURVES  (right column, upper)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 2.70
    Select inner viewport: 4.52, 7.75, 0.85, 2.48

    dbTop = 2
    dbBot = floor_db
    if dbBot < -70
        dbBot = -70
    endif
    Axes: 0, duration, dbBot, dbTop
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, duration, dbBot, dbTop

    # -9.03 dB reference: every channel sits here when the source is
    # at the centre, since 20*log10(1/sqrt(8)) = -9.03
    Colour: "{0.82, 0.82, 0.82}"
    Dotted line
    Draw line: 0, -9.03, duration, -9.03
    Draw line: 0, 0, duration, 0
    Solid line

    for ch from 1 to 8
        Line width: 1.5
        Colour: "{" + fixed$(chColR[ch], 2) + ", " + fixed$(chColG[ch], 2)
            ... + ", " + fixed$(chColB[ch], 2) + "}"
        @computeGains: 0
        prevV = 20 * log10(gw[ch])
        if prevV < dbBot
            prevV = dbBot
        endif
        prevT = 0
        for j from 1 to nCurve
            tj = j * duration / nCurve
            @computeGains: tj
            vj = 20 * log10(gw[ch])
            if vj < dbBot
                vj = dbBot
            endif
            if vj > dbTop
                vj = dbTop
            endif
            Draw line: prevT, prevV, tj, vj
            prevT = tj
            prevV = vj
        endfor
    endfor

    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Font size: 6
    Marks left every: 1, 10, "yes", "yes", "no"
    Font size: 6
    Text bottom: "yes", "Time (s)"
    Select outer viewport: 4.02, 4.4, 0.75, 2.70
    Select inner viewport: 4.02, 4.4, 0.77, 2.68
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Gain (dB)"
    Select outer viewport: 4.2, 8, 0.75, 2.70
    Select inner viewport: 4.52, 7.75, 0.85, 2.48
    Axes: 0, duration, dbBot, dbTop

    # ----------------------------------------------------------
    # PANEL C: MEASURED PEAK GAIN PER CHANNEL  (right column, lower)
    # ----------------------------------------------------------
    # v0.3 drew max_volume here for almost every pattern, which said
    # nothing about what the channel actually did. These are measured.
    Select outer viewport: 4.2, 8, 3.00, 4.60
    Select inner viewport: 4.52, 7.75, 3.10, 4.38

    for k from 1 to 8
        peakG[k] = 0
    endfor
    for j from 0 to nScan
        tj = j * duration / nScan
        @computeGains: tj
        for k from 1 to 8
            if gw[k] > peakG[k]
                peakG[k] = gw[k]
            endif
        endfor
    endfor

    Axes: dbBot, dbTop, 0.5, 8.5
    Paint rectangle: "{0.96, 0.96, 0.96}", dbBot, dbTop, 0.5, 8.5
    Colour: "{0.80, 0.80, 0.80}"
    Dotted line
    Draw line: -9.03, 0.5, -9.03, 8.5
    Solid line

    for k from 1 to 8
        y = 9 - k
        pv = 20 * log10(peakG[k])
        if pv < dbBot
            pv = dbBot
        endif
        Paint rectangle: "{" + fixed$(chColR[k], 2) + ", " + fixed$(chColG[k], 2)
            ... + ", " + fixed$(chColB[k], 2) + "}", dbBot, pv, y - 0.38, y + 0.38
        Font size: 6
        Colour: "{0.30, 0.30, 0.30}"
        Text: dbBot - (dbTop - dbBot) * 0.02, "right", y, "half",
            ... string$(k) + " " + spkName$[k]
        Colour: "White"
        Text: (dbBot + pv) / 2, "centre", y, "half", fixed$(pv, 1)
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 6
    Select outer viewport: 4.02, 4.4, 3.00, 4.60
    Select inner viewport: 4.02, 4.4, 3.02, 4.58
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Ch"
    Select outer viewport: 4.2, 8, 3.00, 4.60
    Select inner viewport: 4.52, 7.75, 3.10, 4.38
    Axes: dbBot, dbTop, 0.5, 8.5
    Text bottom: "yes", "Peak gain (dB)"

    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8

    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Speaker map and source path (dot size = gain at t=0)"
    Text: 6.10, "centre", 7.30, "half",
        ... "Channel gains (upper) & measured peaks (lower)" + vizNote$

    # ----------------------------------------------------------
    # PANEL D: PROCESSED CHANNELS  (full width)
    # ----------------------------------------------------------
    # Drawn from the working channels, so the panel is the same in all
    # five output formats.
    Select outer viewport: 0, 8, 4.90, 5.95
    Select inner viewport: 0.55, 7.72, 4.98, 5.72

    selectObject: result[2]
    outDurViz = Get total duration
    peakViz = Get absolute extremum: 0, 0, "None"
    selectObject: result[6]
    peak2 = Get absolute extremum: 0, 0, "None"
    if peak2 > peakViz
        peakViz = peak2
    endif
    if peakViz < 0.001
        peakViz = 0.001
    endif
    ampViz = peakViz * 1.15

    Axes: 0, outDurViz, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, outDurViz, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, outDurViz, 0

    selectObject: result[2]
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"

    selectObject: result[6]
    Colour: "{0.82, 0.45, 0.25}"
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Opposing channels  (blue = Ch2 Front,  orange = Ch6 Back)"
    Select outer viewport: 0.08, 0.52, 4.90, 5.95
    Select inner viewport: 0.08, 0.52, 4.92, 5.93
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Amp"
    Select outer viewport: 0, 8, 4.90, 5.95
    Select inner viewport: 0.55, 7.72, 4.98, 5.72
    Axes: 0, outDurViz, -ampViz, ampViz
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR (full width, bottom)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.20, 7.08
    Select inner viewport: 0.55, 7.72, 6.26, 7.02
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.72, "half",
        ... "##" + patternName$ + "##"
        ... + "  " + soundName$
        ... + "  |  " + fixed$(duration, 2) + " s"
        ... + "  |  Speed: " + fixed$(motion_speed, 2)
        ... + "  |  Radius: " + fixed$(path_radius, 2)
        ... + "  |  Focus: " + fixed$(source_focus, 2)

    Text: 0.02, "left", 0.45, "half",
        ... "Floor: " + fixed$(floor_db, 0) + " dB"
        ... + "  |  Points: " + string$(nPoints)
        ... + " (" + fixed$(nPoints / (fMax * duration), 1) + "/cycle)"
        ... + "  |  Seed: " + string$(random_seed)
        ... + "  |  Const-power before envelope"

    Text: 0.02, "left", 0.18, "half",
        ... "Format: " + formatName$
        ... + "  |  " + string$(outCount) + objWord$
        ... + " x " + string$(outChannels) + " ch"
        ... + "  |  " + mapLine$

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Select outer viewport: 0, 8, 0, 7.18
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
removeObject: monoID
for ch from 1 to 8
    removeObject: channel[ch], intensityTier[ch], result[ch]
endfor

# === Done ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="
if outCount = 1
    appendInfoLine: "Output: 1 object, ", outChannels, "-channel, ", patternName$, " movement"
else
    appendInfoLine: "Output: ", outCount, " objects, ", outChannels,
        ... "-channel each, ", patternName$, " movement"
endif

if play_result
    if outCount = 1
        selectObject: out[1]
        Play
    else
        appendInfoLine: ""
        appendInfoLine: "Playback: stereo preview folded from all eight channels."
        appendInfoLine: "          It is not one of the ", outCount, " output objects."
        selectObject: monitorID
        Play
    endif
endif

if monitorID <> 0
    removeObject: monitorID
endif

# === Select the output object(s) ===
selectObject: out[1]
for k from 2 to outCount
    plusObject: out[k]
endfor
