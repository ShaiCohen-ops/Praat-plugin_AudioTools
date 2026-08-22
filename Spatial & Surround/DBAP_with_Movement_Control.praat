# ============================================================
# Praat AudioTools - DBAP_with_Movement_Control.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026)
# v0.5.1 (2026): RUNTIME VISUAL QA - stacked-panel label gaps corrected; DSP unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   DBAP (Distance-Based Amplitude Panning) with movement control.
#   A source is moved along a 2D path; each speaker's gain follows
#   1 / d^a, optionally normalised so the squared gains sum to 1.
#   2-8 speakers, ten trajectories, with the LFE excluded from the
#   spatial calculation in the 5.1 and 7.1 layouts.
#
# Changelog v0.5.1 (2026):
#   - FIX: the radial clamp was deforming the Square and the Zigzag.
#     Both were built on +-Radius, which puts the corners at sqrt(2)*R,
#     and the clamp then projected them onto the circle - at Radius 0.8
#     the top edge bowed from 0.566 out to 0.800, a 41% bulge. It was
#     not a square. Both are now built on the half-side R/sqrt(2), so
#     the corners land exactly at Radius and the sides stay straight.
#     The clamp remains only as a safety net and should never fire.
#   - RENAME: Path_cycles -> Path_rate. "One full traversal for every
#     trajectory" was only true for the closed shapes. Linear ignores it
#     entirely; the spirals use it as a TURN count during a single
#     radial pass; the zigzag uses it for x crossings while y still
#     rises once over the file; the Lissajous has no repeat period at
#     the 2.75:1.947 ratio; the random walk uses it as waypoint density.
#     The report now prints what it means for the path in use.
#   - NEW: Channel_order. Printing the internal order is not enough once
#     the file is saved as WAV and opened elsewhere - the LFE would land
#     on a surround speaker and vice versa. The standard option emits
#     FL FR C LFE SL SR [BL BR] with the LFE fourth.
#   - FIX: the gain panel did not show what was applied. With listener
#     distance attenuation on, the audio was scaled but the panel was
#     not. Its axis ceiling was also wrong: the loop left the gain
#     variable holding only the LAST speaker, so a louder channel
#     elsewhere was clipped by the axis. Both fixed, and the panel is
#     retitled to say it is before the global output gain.
#   - FIX: the report claimed sum(g^2) = 1 at every control point, which
#     stops being true once the distance term multiplies in - it becomes
#     the distance gain squared. Reworded, with the observed range.
#   - NEW: Reference_distance. v0.3 hard-wired it to 1, so at the 0.8
#     default radius the path never exceeded it and the whole distance
#     term was inert - it did nothing unless the path left the unit
#     circle. The report says when it is inert, and states that the
#     coordinates are map units rather than metres.
#   - Added the missing checks: Radius may not be negative (0 is legal,
#     a fixed source at the centre) and a negative seed is treated as 0.
#   - FIX: when a control-rate cap bit, nothing said so. The cap is
#     reported with the points per cycle actually achieved, and the rate
#     printed is now the one the rounded point count really gives rather
#     than the pre-rounding figure.
#   - FIX: the spectrogram ceiling was fixed at 5000 Hz regardless of
#     the sampling rate; it now follows Nyquist when that is lower.
#   - The summary no longer prints a Radius for the linear path, which
#     does not use it.
#
# Changelog v0.3 (2026):
#   - FIX (the main one): the audio was cut into chunks, each given one
#     constant gain, and the pieces concatenated back. Two problems.
#     First, the gain was a staircase: it changed instantaneously at
#     every chunk boundary while the signal kept running, so continuous
#     movement was rendered as steps. At the 0.02 s default and Speed 1
#     the worst step is small (0.07 dB), but it scales with movement
#     rate - 0.55 dB per boundary at Speed 10 - and a step at a sample
#     boundary is a click however small it is.
#     Second, and worse in practice, each chunk did a Copy and a
#     Concatenate PER SPEAKER, and Concatenate rewrites the whole
#     accumulated buffer every time. A 60 s file at 20 ms chunks with
#     8 speakers is 24,000 object operations rewriting roughly 32
#     BILLION samples. That is quadratic, and it is why the script
#     appeared to hang on anything long.
#     The audio is no longer cut at all. Gains are computed at control
#     points, written to one AmplitudeTier per speaker, and applied to
#     the whole source in a single Multiply. Chunk_duration is now
#     Control_time_step and the gains interpolate between points.
#   - FIX: the LFE was treated as a directional speaker. In the 5.1 and
#     7.1 presets Ch6 and Ch8 sat at (0, -0.3) and took part in the
#     distance calculation, the normalisation and the movement - but an
#     LFE is not another loudspeaker in the array. DBAP now runs on the
#     five (5.1) or seven (7.1) directional channels only; the LFE is a
#     lowpassed copy of the source at its own level, excluded from
#     sum(g^2) but still taking the global output gain so its ratio to
#     the mains is stable.
#   - FIX: the source time domain was not normalised to 0 while every
#     extraction and every trajectory ran from 0.
#   - RENAME: Rolloff is an EXPONENT, not a dB figure. At a = 1 doubling
#     the distance gives -6.02 dB, so the two are not interchangeable.
#     It is called Distance_exponent, and a second option lets the
#     figure be entered as dB per doubling instead, converted by
#     a = R / 6.0206.
#   - FIX: the hard clamp dist = max(dist, 0.01) creates a flat top and
#     a derivative discontinuity right where the source crosses a
#     speaker, and at exponent 2 it lets the raw gain reach 10,000
#     (1,000,000 at exponent 3). Replaced with the standard DBAP
#     spatial blur, d' = sqrt(d^2 + b^2), which is smooth through the
#     speaker position and bounds the gain at 1/b^a.
#   - FIX: Speed was not a consistent cycle count. At Speed 1 the
#     circle, ellipse and square made one lap but Figure-8, both
#     spirals and the pendulum made two, and the zigzag four. It is now
#     Path_cycles and one really is one full traversal of the shape for
#     every trajectory.
#   - FIX: Radius was not the maximum radius. The ellipse reaches 1.4r
#     on its long axis and the square and zigzag reach sqrt(2)*r at the
#     corners, so Radius 0.8 put the source at 1.131 - outside a unit
#     speaker ring. Every trajectory is now clamped so the greatest
#     distance from the centre really is Radius.
#   - RENAME: "Random Walk" had no randomness - it was
#     x = 0.7r sin(137.5 s q), y = 0.7r cos(97.3 s q), a deterministic
#     quasi-periodic Lissajous with no seed, no accumulation and no
#     boundary handling. It is named Quasi-random Lissajous, and a real
#     seeded random walk with momentum and boundary reflection is added
#     alongside it.
#   - FIX: the control rate did not follow the movement. 20 ms is 50 Hz
#     regardless of how fast the path is running. It is now derived from
#     the fastest component of the chosen trajectory, at a target number
#     of points per cycle, with the requested step as a ceiling.
#   - NEW: Output_gain_handling - Peak, Attenuate only, or None. The
#     v0.2 Scale peak always rescaled to 0.95, which removes the level
#     differences between renders and would cancel any distance
#     attenuation.
#   - NEW: optional distance-to-listener attenuation. Normalised DBAP
#     keeps sum(g^2) = 1, so a source far outside the array has the same
#     total energy as one at the centre - only the distribution changes.
#     That is correct for DBAP and is now stated, with a separate
#     d0/max(d,d0) term available when depth is wanted too.
#   - NEW: channel roles are reported. v0.2 printed only numbers, so
#     nothing said that Quad Ch1 is Right, Ch2 Front, Ch3 Left, Ch4
#     Back - which is not the usual quad order and matters when the file
#     reaches a DAW.
#   - NEW: Monitoring - multichannel, stereo preview, or none. Play on a
#     6- or 8-channel object depends on the audio interface; the stereo
#     preview folds by speaker x position without touching the output.
#   - FIX: the trajectory plot kept at most 200 points regardless of how
#     many cycles the path ran, so a fast circle drew as a polygon. It
#     now scales with the cycle count.
#   - FIX: the spectrogram analysed channel 1 of the ORIGINAL input, not
#     the mono working copy that was actually spatialised.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

form DBAP Movement Control v0.5.1
    comment === MOVEMENT TRAJECTORY ===
    optionmenu Movement_type: 2
        option: "1. Linear"
        option: "2. Circular"
        option: "3. Figure-8"
        option: "4. Spiral In"
        option: "5. Spiral Out"
        option: "6. Pendulum"
        option: "7. Zigzag"
        option: "8. Quasi-random Lissajous (was Random Walk)"
        option: "9. Ellipse"
        option: "10. Square"
        option: "11. Random walk (seeded, with momentum)"
    sentence Linear_path start_x=-1.0 start_y=0.0 end_x=1.0 end_y=0.0
    real Radius 0.8
    optionmenu Channel_order: 1
        option: "Praat AudioTools internal (LFE last)"
        option: "Standard WAV 5.1/7.1 (FL FR C LFE SL SR [BL BR])"
    positive Path_rate 1.0
    integer Random_seed 0

    comment === SPEAKERS ===
    optionmenu Speaker_preset: 8
        option: "Stereo (2)"
        option: "Triangle (3)"
        option: "Quad (4)"
        option: "Pentagon (5)"
        option: "Hexagon (6)"
        option: "Surround 5.1 (5 directional + LFE)"
        option: "Surround 7.1 (7 directional + LFE)"
        option: "Octagon (8)"
    sentence Lfe lowpass=100 level=0.4

    comment === DBAP ===
    optionmenu Exponent_units: 1
        option: "Distance exponent a in 1/d^a"
        option: "dB per doubling of distance"
    positive Distance_exponent 1.0
    positive Spatial_blur 0.10
    positive Reference_distance 1.0
    boolean Normalize_gains 1
    boolean Listener_distance_attenuation 0
    positive Control_time_step 0.02

    comment === OUTPUT ===
    optionmenu Output_gain_handling: 1
        option: "Peak (scale to target)"
        option: "Attenuate only (never boost)"
        option: "None"
    real Peak_target 0.95
    optionmenu Monitoring: 2
        option: "Play the multichannel object directly"
        option: "Stereo preview (folded by speaker x)"
        option: "No playback"
    boolean Draw_visualization 1
endform

# ---- unpack the grouped fields ----
start_x = extractNumber(linear_path$, "start_x=")
start_y = extractNumber(linear_path$, "start_y=")
end_x = extractNumber(linear_path$, "end_x=")
end_y = extractNumber(linear_path$, "end_y=")
lfeCut = extractNumber(lfe$, "lowpass=")
lfeLevel = extractNumber(lfe$, "level=")
parseFailed = 0
if start_x = undefined
    start_x = -1.0
    parseFailed = 1
endif
if start_y = undefined
    start_y = 0.0
    parseFailed = 1
endif
if end_x = undefined
    end_x = 1.0
    parseFailed = 1
endif
if end_y = undefined
    end_y = 0.0
    parseFailed = 1
endif
if lfeCut = undefined or lfeCut <= 0
    lfeCut = 100
    parseFailed = 1
endif
if lfeLevel = undefined or lfeLevel < 0
    lfeLevel = 0.4
    parseFailed = 1
endif

# v0.3: an exponent and a dB-per-doubling figure are different things.
# a = 1 IS -6.02 dB per doubling, so entering "6" as an exponent asks
# for -36 dB per doubling.
if exponent_units = 2
    dbPerDouble = distance_exponent
    distExp = distance_exponent / (20 * log10(2))
    expNote$ = fixed$(dbPerDouble, 2) + " dB/doubling = exponent " + fixed$(distExp, 4)
else
    distExp = distance_exponent
    dbPerDouble = distExp * 20 * log10(2)
    expNote$ = "exponent " + fixed$(distExp, 3) + " = " + fixed$(dbPerDouble, 2) + " dB/doubling"
endif
if distExp <= 0
    distExp = 1
endif
if spatial_blur < 0.001
    spatial_blur = 0.001
endif
if peak_target <= 0 or peak_target > 1
    peak_target = 0.95
endif
if lfeLevel > 1
    lfeLevel = 1
endif

# v0.5: Radius is a real, so a negative value was reachable and would
# invert every shape and the clamp with it. 0 is legal - a fixed source
# at the centre.
if radius < 0
    radius = 0
endif
if reference_distance <= 0
    reference_distance = 1.0
endif
if random_seed < 0
    random_seed = 0
endif

# Per-trajectory meaning of Path_rate. v0.3 reported "full cycles" for
# all of them, which is only true for the closed shapes.
rateMeaning$[1] = "not used - the linear path is one traversal whatever this says"
rateMeaning$[2] = "full laps"
rateMeaning$[3] = "full figure-8s"
rateMeaning$[4] = "angular TURNS during the single radial pass inward"
rateMeaning$[5] = "angular TURNS during the single radial pass outward"
rateMeaning$[6] = "full swings"
rateMeaning$[7] = "x crossings; y still rises once over the file"
rateMeaning$[8] = "rate scale - the 2.75:1.947 ratio has no single repeat period"
rateMeaning$[9] = "full laps"
rateMeaning$[10] = "full circuits"
rateMeaning$[11] = "waypoint density, not cycles" 

# ============================================================
# SOURCE: mono working copy starting at t = 0
# ============================================================
sound = selected("Sound")
soundName$ = selected$("Sound")
selectObject: sound
sr = Get sampling frequency
numCh = Get number of channels
srcT1 = Get end time

if numCh > 1
    selectObject: sound
    Convert to mono
    monoID = selected("Sound")
else
    selectObject: sound
    Copy: "dbap_mono"
    monoID = selected("Sound")
endif

# v0.3: every extraction and every trajectory runs from 0, but Convert
# to mono and Copy keep the original time domain.
selectObject: monoID
monoT0 = Get start time
if monoT0 <> 0
    selectObject: monoID
    shifted = Extract part: monoT0, srcT1, "rectangular", 1.0, "no"
    removeObject: monoID
    monoID = shifted
endif
selectObject: monoID
Rename: "dbap_src"
duration = Get total duration

if duration <= 0
    removeObject: monoID
    exitScript: "Source has zero duration."
endif

nyq = sr / 2
if lfeCut > nyq * 0.9
    lfeCut = nyq * 0.9
endif

# ============================================================
# SPEAKERS
# ============================================================
# v0.3: hasLfe marks a layout where one channel is a band-limited
# effects channel rather than a position in the array. It takes no part
# in the distance calculation or the normalisation.
hasLfe = 0
if speaker_preset = 1
    numDir = 2
    spkX[1] = -1.0
    spkY[1] = 0.0
    spkRole$[1] = "L"
    spkX[2] = 1.0
    spkY[2] = 0.0
    spkRole$[2] = "R"
    configName$ = "Stereo"
elsif speaker_preset = 2
    numDir = 3
    spkX[1] = -0.866
    spkY[1] = -0.5
    spkRole$[1] = "BL"
    spkX[2] = 0.866
    spkY[2] = -0.5
    spkRole$[2] = "BR"
    spkX[3] = 0.0
    spkY[3] = 1.0
    spkRole$[3] = "F"
    configName$ = "Triangle"
elsif speaker_preset = 3
    numDir = 4
    for i from 1 to 4
        angle = (i - 1) * 2 * pi / 4
        spkX[i] = cos(angle)
        spkY[i] = sin(angle)
    endfor
    spkRole$[1] = "R"
    spkRole$[2] = "F"
    spkRole$[3] = "L"
    spkRole$[4] = "B"
    configName$ = "Quad"
elsif speaker_preset = 4
    numDir = 5
    for i from 1 to 5
        angle = (i - 1) * 2 * pi / 5 - pi / 2
        spkX[i] = cos(angle)
        spkY[i] = sin(angle)
        spkRole$[i] = "P" + string$(i)
    endfor
    configName$ = "Pentagon"
elsif speaker_preset = 5
    numDir = 6
    for i from 1 to 6
        angle = (i - 1) * 2 * pi / 6
        spkX[i] = cos(angle)
        spkY[i] = sin(angle)
        spkRole$[i] = "H" + string$(i)
    endfor
    configName$ = "Hexagon"
elsif speaker_preset = 6
    # v0.3: five DIRECTIONAL channels. v0.2 put an LFE at (0, -0.3) and
    # panned to it as though it were a rear speaker.
    numDir = 5
    spkX[1] = -0.6
    spkY[1] = 0.8
    spkRole$[1] = "FL"
    spkX[2] = 0.6
    spkY[2] = 0.8
    spkRole$[2] = "FR"
    spkX[3] = 0.0
    spkY[3] = 1.0
    spkRole$[3] = "C"
    spkX[4] = -0.9
    spkY[4] = -0.5
    spkRole$[4] = "SL"
    spkX[5] = 0.9
    spkY[5] = -0.5
    spkRole$[5] = "SR"
    hasLfe = 1
    configName$ = "5.1"
elsif speaker_preset = 7
    numDir = 7
    spkX[1] = -0.6
    spkY[1] = 0.8
    spkRole$[1] = "FL"
    spkX[2] = 0.6
    spkY[2] = 0.8
    spkRole$[2] = "FR"
    spkX[3] = 0.0
    spkY[3] = 1.0
    spkRole$[3] = "C"
    spkX[4] = -1.0
    spkY[4] = 0.0
    spkRole$[4] = "SL"
    spkX[5] = 1.0
    spkY[5] = 0.0
    spkRole$[5] = "SR"
    spkX[6] = -0.7
    spkY[6] = -0.7
    spkRole$[6] = "BL"
    spkX[7] = 0.7
    spkY[7] = -0.7
    spkRole$[7] = "BR"
    hasLfe = 1
    configName$ = "7.1"
else
    numDir = 8
    for i from 1 to 8
        angle = (i - 1) * 2 * pi / 8
        spkX[i] = cos(angle)
        spkY[i] = sin(angle)
        spkRole$[i] = "O" + string$(i)
    endfor
    configName$ = "Octagon"
endif

numOut = numDir + hasLfe
if hasLfe = 1
    spkRole$[numOut] = "LFE"
endif

movementNames$[1] = "Linear"
movementNames$[2] = "Circular"
movementNames$[3] = "Figure8"
movementNames$[4] = "SpiralIn"
movementNames$[5] = "SpiralOut"
movementNames$[6] = "Pendulum"
movementNames$[7] = "Zigzag"
movementNames$[8] = "Lissajous"
movementNames$[9] = "Ellipse"
movementNames$[10] = "Square"
movementNames$[11] = "RandomWalk"
movementName$ = movementNames$[movement_type]

# ============================================================
# CONTROL RATE
# ============================================================
# v0.3: the fastest internal component of each path, so the control
# rate follows the movement instead of sitting at a fixed 50 Hz.
fastMult[1] = 1
fastMult[2] = 1
fastMult[3] = 2
fastMult[4] = 1
fastMult[5] = 1
fastMult[6] = 1
fastMult[7] = 1
fastMult[8] = 3
fastMult[9] = 1
fastMult[10] = 4
fastMult[11] = 4

cycleRate = path_rate / duration
fastRate = cycleRate * fastMult[movement_type]
if fastRate <= 0
    fastRate = 1 / duration
endif

ptsPerCycle = 48
ctrlRate = ptsPerCycle * fastRate
reqRate = 1 / control_time_step
if ctrlRate < reqRate
    ctrlRate = reqRate
endif
ctrlRaised = 0
if ctrlRate > reqRate + 1e-9
    ctrlRaised = 1
endif
ctrlCapped = 0
if ctrlRate > 4000
    ctrlRate = 4000
    ctrlCapped = 1
endif
nCtrl = round(duration * ctrlRate)
if nCtrl < 8
    nCtrl = 8
endif
if nCtrl > 200000
    nCtrl = 200000
    ctrlCapped = 1
endif
# v0.5: report the rate that the rounded point count actually gives,
# not the pre-rounding figure, and say when a cap has bitten.
ctrlRate = nCtrl / duration
achievedPts = ctrlRate / fastRate

# ============================================================
# RANDOM WALK WAYPOINTS
# ============================================================
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedApplied = 1
else
    random_initializeSafelyAndUnpredictably ()
    seedApplied = 0
endif

nWalk = ceiling(8 * path_rate) + 4
if nWalk < 12
    nWalk = 12
endif
if nWalk > 4000
    nWalk = 4000
endif
if movement_type = 11
    wx = 0
    wy = 0
    wvx = 0
    wvy = 0
    wstep = radius * 0.22
    for i from 0 to nWalk
        walkX[i] = wx
        walkY[i] = wy
        wvx = 0.75 * wvx + wstep * randomUniform(-1, 1)
        wvy = 0.75 * wvy + wstep * randomUniform(-1, 1)
        wx = wx + wvx
        wy = wy + wvy
        wr = sqrt(wx * wx + wy * wy)
        if wr > radius and wr > 0
            wnx = wx / wr
            wny = wy / wr
            wx = wnx * radius
            wy = wny * radius
            wdot = wvx * wnx + wvy * wny
            wvx = wvx - 2 * wdot * wnx
            wvy = wvy - 2 * wdot * wny
        endif
    endfor
endif
random_initializeSafelyAndUnpredictably ()

# ============================================================
# TRAJECTORY
# ============================================================
# v0.3: one Path_cycles is one full traversal of the shape for EVERY
# path. v0.2's Speed gave the circle one lap but Figure-8, the spirals
# and the pendulum two, and the zigzag four.
# Every path is also clamped so Radius really is the greatest distance
# from the centre: the ellipse reached 1.4r and the square and zigzag
# sqrt(2)*r, so Radius 0.8 put the source at 1.131 - outside a unit ring.

procedure trajectory: .q
    .ph = 2 * pi * path_rate * .q
    .r = radius

    if movement_type = 1
        .x = start_x + (end_x - start_x) * .q
        .y = start_y + (end_y - start_y) * .q
    elsif movement_type = 2
        .x = .r * cos(.ph)
        .y = .r * sin(.ph)
    elsif movement_type = 3
        # Gerono lemniscate, one full figure per cycle
        .x = .r * sin(.ph)
        .y = .r * 0.5 * sin(2 * .ph)
    elsif movement_type = 4
        .rr = .r * (1 - .q)
        .x = .rr * cos(.ph)
        .y = .rr * sin(.ph)
    elsif movement_type = 5
        .rr = .r * .q
        .x = .rr * cos(.ph)
        .y = .rr * sin(.ph)
    elsif movement_type = 6
        # One swing out and back per cycle
        .sw = sin(.ph) * pi / 3
        .x = .r * sin(.sw)
        .y = -.r * cos(.sw) * 0.5
    elsif movement_type = 7
        # v0.5: built on the half-side R/sqrt(2), so the extreme corners
        # land exactly at Radius and the radial clamp never has to touch
        # the shape. Using +-R on both axes put the corners at sqrt(2)R
        # and the clamp then bent the path.
        .hs = .r / sqrt(2)
        .zt = .ph / (2 * pi)
        .zf = .zt - floor(.zt)
        .x = .hs * (2 * abs(2 * .zf - 1) - 1)
        .y = .hs * (2 * .q - 1)
    elsif movement_type = 8
        # Quasi-random Lissajous: deterministic, not a random walk.
        .x = .r * 0.7 * sin(.ph * 2.75)
        .y = .r * 0.7 * cos(.ph * 1.947)
    elsif movement_type = 9
        .x = .r * cos(.ph)
        .y = .r * 0.5 * sin(.ph)
    elsif movement_type = 10
        # v0.5: half-side R/sqrt(2), so the CORNERS sit at Radius and the
        # sides stay straight. v0.3 built the square on +-R, which put
        # the corners at sqrt(2)R, and the radial clamp then projected
        # them onto the circle - bowing every edge outward from 0.566 to
        # 0.800 at Radius 0.8. That is not a square.
        .hs = .r / sqrt(2)
        .st = .ph / (2 * pi) * 4
        .sn = floor(.st) mod 4
        .sf = .st - floor(.st)
        if .sn = 0
            .x = -.hs + 2 * .hs * .sf
            .y = .hs
        elsif .sn = 1
            .x = .hs
            .y = .hs - 2 * .hs * .sf
        elsif .sn = 2
            .x = .hs - 2 * .hs * .sf
            .y = -.hs
        else
            .x = -.hs
            .y = -.hs + 2 * .hs * .sf
        endif
    else
        .p = .q * nWalk
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
    endif

    # Radius clamp, now only a SAFETY net: every shape is built to reach
    # Radius on its own, so this should not fire. The linear path is
    # exempt - its endpoints are given explicitly and are meant to be
    # honoured.
    if movement_type <> 1
        .rho = sqrt(.x * .x + .y * .y)
        if .rho > .r and .rho > 1e-12
            .x = .x * .r / .rho
            .y = .y * .r / .rho
        endif
    endif
endproc

# ============================================================
# GAIN ENVELOPES
# ============================================================
# v0.3: no chunking. Gains go into one AmplitudeTier per directional
# channel and are applied to the whole source in a single Multiply, so
# the envelope interpolates instead of stepping - and the quadratic
# Copy/Concatenate cost is gone entirely.

for sp from 1 to numDir
    tierID[sp] = Create AmplitudeTier: "dbapT" + string$(sp), 0, duration
endfor

nTrace = ceiling(60 * path_rate * fastMult[movement_type])
if nTrace < 300
    nTrace = 300
endif
if nTrace > 4000
    nTrace = 4000
endif
if nTrace > nCtrl
    nTrace = nCtrl
endif

stopwatch
minSumSq = 1e30
maxSumSq = 0
maxRho = 0
for i from 0 to nCtrl
    t = i * duration / nCtrl
    q = i / nCtrl
    @trajectory: q
    sx = trajectory.x
    sy = trajectory.y
    rho = sqrt(sx * sx + sy * sy)
    if rho > maxRho
        maxRho = rho
    endif

    sumSq = 0
    for sp from 1 to numDir
        dx = sx - spkX[sp]
        dy = sy - spkY[sp]
        # v0.3: spatial blur instead of a hard clamp. sqrt(d^2 + b^2) is
        # smooth through the speaker position and bounds the gain at
        # 1/b^a; the old max(d, 0.01) flat-topped and kinked there, and
        # at exponent 2 it let the raw gain reach 10,000.
        dist = sqrt(dx * dx + dy * dy + spatial_blur * spatial_blur)
        g[sp] = 1 / (dist ^ distExp)
        sumSq = sumSq + g[sp] * g[sp]
    endfor

    if normalize_gains and sumSq > 0
        nrm = sqrt(sumSq)
        for sp from 1 to numDir
            g[sp] = g[sp] / nrm
        endfor
        sumSq = 1
    endif

    if listener_distance_attenuation
        # Normalised DBAP holds sum(g^2) = 1, so distance from the array
        # changes only the DISTRIBUTION, not the total energy. This adds
        # the depth term separately when it is wanted.
        # v0.5: the reference distance is a field. v0.3 hard-wired it to
        # 1, so at the 0.8 default radius rho never exceeded it and the
        # whole term was inert - it did nothing at all unless the path
        # left the unit circle. Coordinates are MAP UNITS, not metres.
        dl = rho
        if dl < reference_distance
            dl = reference_distance
        endif
        distGain = reference_distance / dl
        for sp from 1 to numDir
            g[sp] = g[sp] * distGain
        endfor
        sumSq = sumSq * distGain * distGain
    endif

    if sumSq < minSumSq
        minSumSq = sumSq
    endif
    if sumSq > maxSumSq
        maxSumSq = sumSq
    endif

    for sp from 1 to numDir
        selectObject: tierID[sp]
        Add point: t, g[sp]
    endfor
endfor
envElapsed = stopwatch

stopwatch
for sp from 1 to numDir
    selectObject: monoID
    plusObject: tierID[sp]
    Multiply
    chID[sp] = selected("Sound")
    Rename: "dbapCh" + string$(sp)
    removeObject: tierID[sp]
endfor

# v0.3: a real LFE - band-limited, at its own level, and no part of the
# spatial calculation or the normalisation.
if hasLfe = 1
    selectObject: monoID
    Filter (pass Hann band): 0, lfeCut, 30
    chID[numOut] = selected("Sound")
    selectObject: chID[numOut]
    Formula: "self * " + fixed$(lfeLevel, 8)
    Rename: "dbapChLFE"
endif
applyElapsed = stopwatch

# ============================================================
# COMBINE AND GAIN
# ============================================================
# v0.5: channel order. Printing the internal order is not enough once
# the file is saved as WAV and imported somewhere else - the LFE would
# land on a surround speaker and vice versa. The standard order puts
# the LFE fourth.
#   internal: FL FR C SL SR [BL BR] LFE
#   standard: FL FR C LFE SL SR [BL BR]
for k from 1 to numOut
    outIdx[k] = k
endfor
orderName$ = "internal (LFE last)"
if channel_order = 2 and hasLfe = 1
    outIdx[1] = 1
    outIdx[2] = 2
    outIdx[3] = 3
    outIdx[4] = numOut
    for k from 5 to numOut
        outIdx[k] = k - 1
    endfor
    orderName$ = "standard WAV 5.1/7.1 (LFE 4th)"
endif

selectObject: chID[outIdx[1]]
for sp from 2 to numOut
    plusObject: chID[outIdx[sp]]
endfor
Combine to stereo
result = selected("Sound")
Rename: soundName$ + "_DBAP_" + movementName$ + "_" + configName$

selectObject: result
prePeak = Get absolute extremum: 0, 0, "None"
normGain = 1
if output_gain_handling = 1
    if prePeak > 0
        normGain = peak_target / prePeak
    endif
    normMode$ = "peak (scaled to target)"
elsif output_gain_handling = 2
    if prePeak > peak_target and prePeak > 0
        normGain = peak_target / prePeak
    endif
    normMode$ = "attenuate only"
else
    normMode$ = "none"
endif
if normGain <> 1
    selectObject: result
    Formula: "self * " + fixed$(normGain, 10)
endif
selectObject: result
finalPeak = Get absolute extremum: 0, 0, "None"
resultName$ = selected$("Sound")

# ============================================================
# REPORT
# ============================================================
writeInfoLine: "=== DBAP with Movement Control v0.5.1 ==="
appendInfoLine: "Source: ", soundName$, "  (", fixed$(duration, 2), " s @ ", sr, " Hz)"
if parseFailed = 1
    appendInfoLine: "  NOTE: a key= entry could not be read and fell back to its"
    appendInfoLine: "        default. Keep the key words; only the numbers change."
endif
appendInfoLine: ""

appendInfoLine: "Speakers: ", configName$, " - ", numDir, " directional",
    ... " + ", hasLfe, " LFE = ", numOut, " output channel(s)"
appendInfoLine: "Channel order: ", orderName$
for sp from 1 to numDir
    ang = arctan2(spkY[sp], spkX[sp]) * 180 / pi
    if ang < 0
        ang = ang + 360
    endif
    appendInfoLine: "  Ch", sp, "  ", spkRole$[sp], "   x=", fixed$(spkX[sp], 3),
        ... "  y=", fixed$(spkY[sp], 3), "   ", fixed$(ang, 1), " deg"
endfor
if hasLfe = 1
    appendInfoLine: "  Ch", numOut, "  LFE  lowpass ", fixed$(lfeCut, 0),
        ... " Hz at level ", fixed$(lfeLevel, 2)
    appendInfoLine: "        Not spatialised and not part of sum(g^2), but it does take"
    appendInfoLine: "        the global output gain, so its ratio to the mains is stable."
    appendInfoLine: "        v0.2 placed it at (0, -0.3) and panned to it like a speaker."
endif
appendInfoLine: "  Channel ORDER matters when this reaches a DAW - v0.2 printed"
appendInfoLine: "  numbers only, so nothing said that Quad Ch1 is Right, not Front Left."
appendInfoLine: ""

appendInfoLine: "Movement: ", movementName$, "   Path_rate ", fixed$(path_rate, 2)
appendInfoLine: "  For this path that means: ", rateMeaning$[movement_type]
appendInfoLine: "  v0.3 called it 'full cycles' for every trajectory, which holds"
appendInfoLine: "  only for the closed shapes." 
if movement_type = 1
    appendInfoLine: "  Radius is not used by the linear path; endpoints (",
        ... fixed$(start_x, 2), ", ", fixed$(start_y, 2), ") to (",
        ... fixed$(end_x, 2), ", ", fixed$(end_y, 2), ")"
    appendInfoLine: "  Greatest distance reached ", fixed$(maxRho, 3)
else
    appendInfoLine: "  Radius ", fixed$(radius, 3), "   greatest distance reached ",
        ... fixed$(maxRho, 3)
    if movement_type = 10 or movement_type = 7
        appendInfoLine: "    Built on the half-side ", fixed$(radius / sqrt(2), 3),
            ... ", so the corners land exactly at Radius"
        appendInfoLine: "    and the sides stay straight. v0.3 used +-Radius on both"
        appendInfoLine: "    axes and let the radial clamp bend every edge."
    endif
endif
if movement_type = 8
    appendInfoLine: "  This path is DETERMINISTIC: a quasi-periodic Lissajous with no"
    appendInfoLine: "  randomness at all. v0.2 called it Random Walk."
elsif movement_type = 11
    if seedApplied = 1
        appendInfoLine: "  Seeded random walk, seed ", random_seed,
            ... " - reproducible, with momentum and boundary reflection."
    else
        appendInfoLine: "  Random walk with seed 0 - unpredictable, not reproducible."
    endif
endif
appendInfoLine: ""

appendInfoLine: "DBAP: ", expNote$
appendInfoLine: "  Spatial blur ", fixed$(spatial_blur, 3),
    ... " - d' = sqrt(d^2 + b^2), so the gain is bounded at ",
    ... fixed$(1 / spatial_blur ^ distExp, 1)
appendInfoLine: "  and stays smooth where the source crosses a speaker. v0.2 clamped"
appendInfoLine: "  d to 0.01, which flat-tops and kinks there and reaches ",
    ... fixed$(1 / 0.01 ^ distExp, 0), " at this exponent."
if normalize_gains
    appendInfoLine: "  Normalised: the DIRECTIONAL DBAP gains are unit-power, i.e."
    appendInfoLine: "  sum(g^2) = 1, BEFORE the optional listener-distance term."
    appendInfoLine: "  Normalised DBAP controls the DISTRIBUTION of energy, not the"
    appendInfoLine: "  total: a source far outside the array carries the same energy as"
    appendInfoLine: "  one at the centre. Turn on listener distance attenuation if you"
    appendInfoLine: "  want depth as well."
    if listener_distance_attenuation
        appendInfoLine: "  With that term on, sum(g^2) equals the distance gain squared"
        appendInfoLine: "  rather than 1. Observed range: ", fixed$(minSumSq, 4), " to ",
            ... fixed$(maxSumSq, 4), "."
    endif
else
    appendInfoLine: "  NOT normalised: raw 1/d^a gains, so the total field energy rises"
    appendInfoLine: "  sharply near a speaker. Observed sum(g^2) ran ",
        ... fixed$(minSumSq, 4), " to ", fixed$(maxSumSq, 4), "."
endif
if listener_distance_attenuation
    appendInfoLine: "  Listener distance attenuation ON: an extra d0/max(rho,d0) term"
    appendInfoLine: "  with d0 = ", fixed$(reference_distance, 3),
        ... ". Coordinates are MAP UNITS, not metres."
    if radius <= reference_distance and movement_type <> 1
        appendInfoLine: "  NOTE: the path never exceeds d0, so this term is currently"
        appendInfoLine: "        inert. Raise Radius above ", fixed$(reference_distance, 2),
            ... " or lower the reference distance."
    endif
endif
appendInfoLine: ""

appendInfoLine: "Control: ", fixed$(ctrlRate, 1), " Hz, ", nCtrl, " points = ",
    ... fixed$(achievedPts, 1), " per cycle of the fastest path component"
if ctrlRaised = 1
    appendInfoLine: "  Raised above the requested ", fixed$(reqRate, 1),
        ... " Hz to keep up with the movement."
endif
if ctrlCapped = 1
    appendInfoLine: "  CAPPED: the target is ", ptsPerCycle,
        ... " points per fastest cycle but only ", fixed$(achievedPts, 1),
        ... " were achieved."
    appendInfoLine: "  Reduce Path_rate, or accept coarser motion resolution."
endif
appendInfoLine: "  The gains ride an AmplitudeTier over the WHOLE source, so they"
appendInfoLine: "  interpolate rather than stepping at chunk edges."
appendInfoLine: "  v0.2 cut the audio into ", ceiling(duration / control_time_step),
    ... " chunks and did a Copy and a"
appendInfoLine: "  Concatenate per chunk PER SPEAKER - ",
    ... ceiling(duration / control_time_step) * numOut,
    ... " object operations here, each"
appendInfoLine: "  rewriting the whole accumulation. That is quadratic, and it is why"
appendInfoLine: "  long files appeared to hang."
appendInfoLine: ""

appendInfoLine: "Output: ", numOut, " channels, ", normMode$
appendInfoLine: "  Peak ", fixed$(prePeak, 4), " -> ", fixed$(finalPeak, 4),
    ... "  (gain x", fixed$(normGain, 4), ")"
appendInfoLine: "(envelopes ", fixed$(envElapsed, 2), " s   apply ",
    ... fixed$(applyElapsed, 2), " s)"

# ============================================================
# STEREO PREVIEW
# ============================================================
# Folds by speaker x with an equal-power law. The multichannel object is
# untouched; this is only for monitoring, since Play on a 6- or
# 8-channel object depends entirely on the audio interface.
previewID = 0
if monitoring = 2
    nL = 0
    nR = 0
    for sp from 1 to numDir
        px = spkX[sp]
        if px < -1
            px = -1
        endif
        if px > 1
            px = 1
        endif
        aPan = (px + 1) * pi / 4
        selectObject: chID[sp]
        Copy: "dbPvL" + string$(sp)
        nL = nL + 1
        pvL[nL] = selected("Sound")
        Formula: "self * " + fixed$(cos(aPan), 8)
        selectObject: chID[sp]
        Copy: "dbPvR" + string$(sp)
        nR = nR + 1
        pvR[nR] = selected("Sound")
        Formula: "self * " + fixed$(sin(aPan), 8)
    endfor
    if hasLfe = 1
        selectObject: chID[numOut]
        Copy: "dbPvLlfe"
        nL = nL + 1
        pvL[nL] = selected("Sound")
        Formula: "self * 0.7071"
        selectObject: chID[numOut]
        Copy: "dbPvRlfe"
        nR = nR + 1
        pvR[nR] = selected("Sound")
        Formula: "self * 0.7071"
    endif

    selectObject: pvL[1]
    for k from 2 to nL
        plusObject: pvL[k]
    endfor
    Combine to stereo
    stkL = selected("Sound")
    Convert to mono
    mixL = selected("Sound")
    Formula: "self * " + fixed$(nL, 8)
    removeObject: stkL
    for k from 1 to nL
        removeObject: pvL[k]
    endfor

    selectObject: pvR[1]
    for k from 2 to nR
        plusObject: pvR[k]
    endfor
    Combine to stereo
    stkR = selected("Sound")
    Convert to mono
    mixR = selected("Sound")
    Formula: "self * " + fixed$(nR, 8)
    removeObject: stkR
    for k from 1 to nR
        removeObject: pvR[k]
    endfor

    selectObject: mixL, mixR
    Combine to stereo
    previewID = selected("Sound")
    Rename: "dbap_stereo_preview"
    Scale peak: peak_target
    removeObject: mixL, mixR
    appendInfoLine: ""
    appendInfoLine: "Stereo preview created (folded by speaker x). It is a monitoring"
    appendInfoLine: "aid, not the output object."
endif

for sp from 1 to numOut
    removeObject: chID[sp]
endfor

# ============================================================
# VISUALIZATION
# ============================================================
if draw_visualization
    Erase all

    # ----------------------------------------------------------
    # TITLE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##DBAP with Movement Control v0.5.1##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    if normalize_gains
        nrmTag$ = "normalised"
    else
        nrmTag$ = "raw 1/d^a"
    endif
    # Radius is not used by the linear path, so it is not claimed there.
    if movement_type = 1
        radiusTag$ = "  |  linear endpoints"
    else
        radiusTag$ = "  |  Radius " + fixed$(radius, 2)
    endif
    Text: 0.5, "centre", -0.25, "half",
        ... soundName$
        ... + "  |  " + movementName$ + " rate " + fixed$(path_rate, 2)
        ... + "  |  " + configName$ + " (" + string$(numOut) + " ch)"
        ... + "  |  a=" + fixed$(distExp, 2) + ", blur=" + fixed$(spatial_blur, 2)
        ... + "  |  " + nrmTag$

    # ----------------------------------------------------------
    # PANEL A: SPATIAL MAP
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.72, 4.20
    Select inner viewport: 0.42, 4.00, 0.82, 4.10

    Axes: -1.6, 1.6, -1.6, 1.6
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.6, 1.6, -1.6, 1.6
    Colour: "{0.88, 0.88, 0.88}"
    Draw ellipse: -1, 1, -1, 1
    Draw line: 0, -1.5, 0, 1.5
    Draw line: -1.5, 0, 1.5, 0

    # v0.3: the trace scales with the cycle count. v0.2 kept at most 200
    # points however many laps the path made, so a fast circle drew as
    # a polygon and a Lissajous drew a shape the audio never followed.
    Line width: 1.6
    @trajectory: 0
    prevX = trajectory.x
    prevY = trajectory.y
    for k from 1 to nTrace
        qk = k / nTrace
        @trajectory: qk
        frac = qk
        trCol$ = "{" + fixed$(0.22 + frac * 0.62, 2) + ", " + fixed$(0.45 - frac * 0.18, 2) + ", " + fixed$(0.82 - frac * 0.58, 2) + "}"
        Colour: trCol$
        Draw line: prevX, prevY, trajectory.x, trajectory.y
        prevX = trajectory.x
        prevY = trajectory.y
    endfor
    Line width: 1
    @trajectory: 0
    Paint circle (mm): "{0.10, 0.30, 0.85}", trajectory.x, trajectory.y, 2.4
    @trajectory: 1
    Paint circle (mm): "{0.85, 0.25, 0.10}", trajectory.x, trajectory.y, 2.4

    for sp from 1 to numDir
        Paint circle (mm): "{0.30, 0.55, 0.35}", spkX[sp], spkY[sp], 3.4
        Colour: "White"
        Font size: 6
        Text: spkX[sp], "centre", spkY[sp], "half", string$(sp)
        Colour: "{0.35, 0.35, 0.35}"
        Font size: 6
        Text: spkX[sp] * 1.22, "centre", spkY[sp] * 1.22, "half", spkRole$[sp]
    endfor
    if hasLfe = 1
        Paint circle (mm): "{0.55, 0.55, 0.55}", 0, -1.42, 2.2
        Font size: 6
        Colour: "{0.40, 0.40, 0.40}"
        Text: 0.14, "left", -1.42, "half", "LFE (not spatialised)"
    endif
    Paint circle (mm): "{0.22, 0.62, 0.30}", 0, 0, 1.8

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Speaker map and path (blue = start, red = end)"

    # ----------------------------------------------------------
    # PANEL B: GAIN ENVELOPES
    # ----------------------------------------------------------
    # v0.3: recomputed from the same procedure the tiers used, so the
    # panel shows the envelope that was actually applied.
    Select outer viewport: 4.2, 8, 0.72, 2.50
    Select inner viewport: 4.55, 7.75, 0.82, 2.40

    # v0.5: the axis ceiling is the maximum over EVERY speaker and every
    # plotted instant. v0.3's loop left gg holding only the LAST
    # speaker's gain, so a louder channel elsewhere was clipped by the
    # axis. It also now includes the distance term, which v0.3 applied
    # to the audio but not to this panel.
    gTop = 0
    nPlot = 320
    for k from 0 to nPlot
        qk = k / nPlot
        @trajectory: qk
        rhoK = sqrt(trajectory.x * trajectory.x + trajectory.y * trajectory.y)
        ss = 0
        for sp from 1 to numDir
            ddx = trajectory.x - spkX[sp]
            ddy = trajectory.y - spkY[sp]
            dd = sqrt(ddx * ddx + ddy * ddy + spatial_blur * spatial_blur)
            gv[sp] = 1 / (dd ^ distExp)
            ss = ss + gv[sp] * gv[sp]
        endfor
        dgK = 1
        if listener_distance_attenuation
            dlK = rhoK
            if dlK < reference_distance
                dlK = reference_distance
            endif
            dgK = reference_distance / dlK
        endif
        for sp from 1 to numDir
            if normalize_gains and ss > 0
                gg = gv[sp] / sqrt(ss) * dgK
            else
                gg = gv[sp] * dgK
            endif
            if gg > gTop
                gTop = gg
            endif
        endfor
    endfor
    if gTop < 0.1
        gTop = 0.1
    endif
    gTop = gTop * 1.12

    Axes: 0, duration, 0, gTop
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, duration, 0, gTop

    Line width: 1.2
    for sp from 1 to numDir
        hue = (sp - 1) / max(1, numDir)
        gCol$ = "{" + fixed$(0.25 + hue * 0.60, 2) + ", " + fixed$(0.55 - hue * 0.28, 2) + ", " + fixed$(0.80 - hue * 0.55, 2) + "}"
        Colour: gCol$
        prevG = 0
        prevT = 0
        for k from 0 to nPlot
            qk = k / nPlot
            tk = qk * duration
            @trajectory: qk
            rhoK = sqrt(trajectory.x * trajectory.x + trajectory.y * trajectory.y)
            ss = 0
            for s2 from 1 to numDir
                ddx = trajectory.x - spkX[s2]
                ddy = trajectory.y - spkY[s2]
                dd = sqrt(ddx * ddx + ddy * ddy + spatial_blur * spatial_blur)
                gv[s2] = 1 / (dd ^ distExp)
                ss = ss + gv[s2] * gv[s2]
            endfor
            dgK = 1
            if listener_distance_attenuation
                dlK = rhoK
                if dlK < reference_distance
                    dlK = reference_distance
                endif
                dgK = reference_distance / dlK
            endif
            if normalize_gains and ss > 0
                gcur = gv[sp] / sqrt(ss) * dgK
            else
                gcur = gv[sp] * dgK
            endif
            if gcur > gTop
                gcur = gTop
            endif
            if k > 0
                Draw line: prevT, prevG, tk, gcur
            endif
            prevT = tk
            prevG = gcur
        endfor
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 6
    Marks left: 3, "yes", "yes", "no"
    Font size: 6
    Select outer viewport: 4.02, 4.4, 0.72, 2.5
    Select inner viewport: 4.02, 4.4, 0.74, 2.48
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Gain"
    Select outer viewport: 4.2, 8, 0.72, 2.5
    Select inner viewport: 4.55, 7.75, 0.82, 2.4
    Axes: 0, duration, 0, gTop
    Text bottom: "yes", "Directional gain envelopes, before the global output gain"

    # ----------------------------------------------------------
    # PANEL C: SPECTROGRAM OF THE MONO WORKING COPY
    # ----------------------------------------------------------
    # v0.2 analysed channel 1 of the ORIGINAL input, which is not what
    # was spatialised when the source was stereo.
    Select outer viewport: 4.2, 8, 2.70, 4.20
    Select inner viewport: 4.55, 7.75, 2.78, 4.10

    # v0.5: the 5000 Hz ceiling is meaningless above Nyquist on a
    # low-rate source.
    specTop = 5000
    if specTop > nyq * 0.95
        specTop = nyq * 0.95
    endif
    selectObject: monoID
    specID = To Spectrogram: 0.01, specTop, 0.004, 20, "Gaussian"
    Paint: 0, 0, 0, specTop, 100, "yes", 50, 6, 0, "no"
    removeObject: specID

    Colour: "Black"
    Draw inner box
    Font size: 6
    Select outer viewport: 4.02, 4.4, 2.70, 4.20
    Select inner viewport: 4.02, 4.4, 2.72, 4.18
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Hz"
    Select outer viewport: 4.2, 8, 2.70, 4.20
    Select inner viewport: 4.55, 7.75, 2.78, 4.10
    Text bottom: "yes", "Source (the mono copy that was spatialised)"

    # ----------------------------------------------------------
    # PANEL D: OUTPUT
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.45, 5.57
    Select inner viewport: 0.55, 7.75, 4.51, 5.50

    selectObject: result
    resPeak = Get absolute extremum: 0, 0, "None"
    if resPeak < 0.001
        resPeak = 0.001
    endif
    aMax = resPeak * 1.15
    Axes: 0, duration, -aMax, aMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, -aMax, aMax
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, duration, 0

    selectObject: result
    Extract one channel: 1
    vizA = selected("Sound")
    Colour: "{0.25, 0.50, 0.82}"
    Draw: 0, 0, -aMax, aMax, "no", "Curve"
    selectObject: result
    Extract one channel: 2
    vizB = selected("Sound")
    Colour: "{0.82, 0.45, 0.25}"
    Draw: 0, 0, -aMax, aMax, "no", "Curve"
    removeObject: vizA, vizB

    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.08, 0.52, 4.45, 5.57
    Select inner viewport: 0.08, 0.52, 4.47, 5.55
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Output"
    Select outer viewport: 0, 8, 4.45, 5.57
    Select inner viewport: 0.55, 7.75, 4.51, 5.50
    Axes: 0, duration, -aMax, aMax
    Text top: "no", "Output channels 1 and 2 of " + string$(numOut)
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL E: SUMMARY
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.80, 6.87
    Select inner viewport: 0.55, 7.75, 5.86, 6.81
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.72, "half",
        ... "##" + movementName$ + "##"
        ... + "  " + soundName$
        ... + "  |  " + fixed$(duration, 2) + " s"
        ... + "  |  rate " + fixed$(path_rate, 2)
        ... + radiusTag$
        ... + "  |  max rho " + fixed$(maxRho, 3)

    Text: 0.02, "left", 0.45, "half",
        ... configName$ + ": " + string$(numDir) + " directional"
        ... + " + " + string$(hasLfe) + " LFE"
        ... + "  |  " + orderName$
        ... + "  |  " + expNote$
        ... + "  |  blur " + fixed$(spatial_blur, 2)
        ... + "  |  " + nrmTag$

    Text: 0.02, "left", 0.18, "half",
        ... "Control " + fixed$(ctrlRate, 0) + " Hz = "
        ... + fixed$(achievedPts, 0) + " pts/cycle"
        ... + "  |  " + normMode$
        ... + "  |  Peak " + fixed$(prePeak, 3) + " -> " + fixed$(finalPeak, 3)
        ... + "  |  AmplitudeTier, no chunking"

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Select outer viewport: 0, 8, 0, 6.97
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================
# CLEANUP AND PLAYBACK
# ============================================================
removeObject: monoID

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Output: ", resultName$

if monitoring = 1
    selectObject: result
    Play
elsif monitoring = 2 and previewID <> 0
    selectObject: previewID
    Play
endif

selectObject: result
if previewID <> 0
    plusObject: previewID
endif
